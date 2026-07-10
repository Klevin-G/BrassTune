import json
import asyncio
from collections import defaultdict
from typing import Optional

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect

from app.api.auth import AuthContext, auth_context_from_token, local_auth_enabled
from app.core.security import LOCAL_ENVIRONMENTS, app_environment, origin_is_allowed
from app.core.instruments.profiles import is_valid_instrument_id
from app.core.pitch.detector import PitchDetector
from app.db.database import SessionLocal
from app.models.db import PracticeSession
from app.schemas.schemas import AudioFrameIn
from app.services.session_service import save_pitch_frames, start_session, stop_session

router = APIRouter()

MAX_WS_MESSAGE_BYTES = 256 * 1024
MAX_UNAUTHENTICATED_ERRORS = 3
UNAUTHENTICATED_TIMEOUT_SECONDS = 15
IDLE_TIMEOUT_SECONDS = 120


async def _reject(websocket: WebSocket, message: str) -> None:
    await websocket.accept()
    await websocket.send_json({"type": "error", "message": message})
    await websocket.close(code=1008)


def _origin_allowed(websocket: WebSocket) -> bool:
    origin = websocket.headers.get("origin")
    if not origin:
        return app_environment() in LOCAL_ENVIRONMENTS
    # Mirror the HTTP CORS policy exactly (exact list OR regex) so a frontend
    # allowed over HTTP is never silently rejected on the pitch WebSocket.
    return origin_is_allowed(origin)


@router.websocket("/ws/pitch")
async def pitch_socket(websocket: WebSocket):
    if not _origin_allowed(websocket):
        await _reject(websocket, "WebSocket origin is not allowed.")
        return
    await websocket.accept()
    detector = PitchDetector()
    db = SessionLocal()
    auth: Optional[AuthContext] = None
    try:
        if websocket.query_params:
            await websocket.send_json({"type": "error", "message": "WebSocket query-token auth is disabled."})
            await websocket.close(code=1008)
            db.close()
            return
        if local_auth_enabled():
            auth = auth_context_from_token(db, None)
    except HTTPException as exc:
        await websocket.send_json({"type": "error", "message": exc.detail})
        await websocket.close()
        db.close()
        return
    pending_frames = defaultdict(list)
    unauthenticated_errors = 0

    def flush_session(session_id: int) -> None:
        frames = pending_frames.get(session_id, [])
        if frames:
            save_pitch_frames(db, session_id, frames)
            pending_frames[session_id] = []

    def can_write_session(session_id: int) -> bool:
        session = db.query(PracticeSession).filter(PracticeSession.id == session_id).first()
        if session is None:
            return False
        return auth.user.role == "admin" or session.user_id == auth.user.id

    def session_for_write(session_id: int) -> Optional[PracticeSession]:
        session = db.query(PracticeSession).filter(PracticeSession.id == session_id).first()
        if session is None:
            return None
        if auth.user.role == "admin" or session.user_id == auth.user.id:
            return session
        raise HTTPException(status_code=403, detail="You do not have access to this session.")

    try:
        while True:
            try:
                raw = await asyncio.wait_for(
                    websocket.receive_text(),
                    timeout=UNAUTHENTICATED_TIMEOUT_SECONDS if auth is None else IDLE_TIMEOUT_SECONDS,
                )
            except asyncio.TimeoutError:
                await websocket.send_json({"type": "error", "message": "WebSocket authentication timed out." if auth is None else "WebSocket idle timeout."})
                await websocket.close(code=1008 if auth is None else 1001)
                return
            if len(raw.encode("utf-8")) > MAX_WS_MESSAGE_BYTES:
                await websocket.send_json({"type": "error", "message": "WebSocket message is too large."})
                await websocket.close(code=1009)
                return
            try:
                message = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_json({"type": "error", "message": "Malformed JSON frame."})
                continue
            msg_type = message.get("type")
            if auth is None:
                if msg_type != "authenticate":
                    await websocket.send_json({"type": "error", "message": "Authenticate before sending pitch frames."})
                    unauthenticated_errors += 1
                    if unauthenticated_errors >= MAX_UNAUTHENTICATED_ERRORS:
                        await websocket.close(code=1008)
                        return
                    continue
                try:
                    token = message.get("token")
                    if not isinstance(token, str) or not token:
                        raise HTTPException(status_code=401, detail="Authentication token is required.")
                    auth = auth_context_from_token(db, token)
                    await websocket.send_json({"type": "authenticated"})
                except HTTPException as exc:
                    await websocket.send_json({"type": "error", "message": exc.detail})
                    await websocket.close()
                    return
                continue
            if msg_type == "authenticate":
                await websocket.send_json({"type": "authenticated"})
            elif msg_type == "ping":
                await websocket.send_json({"type": "pong"})
            elif msg_type == "start_session":
                instrument_id = str(message.get("instrument_id", "trumpet"))
                if not is_valid_instrument_id(instrument_id):
                    await websocket.send_json({"type": "error", "message": "Unknown instrument_id: %s" % instrument_id})
                    continue
                session = start_session(
                    db,
                    instrument_id,
                    message.get("name"),
                    float(message.get("reference_pitch_hz", 440.0)),
                    auth.user.id,
                )
                await websocket.send_json({"type": "session_started", "session": {"id": session.id, "name": session.name}})
            elif msg_type == "stop_session":
                session_id = int(message.get("session_id", 0))
                try:
                    writable_session = session_for_write(session_id)
                except HTTPException as exc:
                    await websocket.send_json({"type": "error", "message": exc.detail})
                    continue
                if writable_session is None:
                    await websocket.send_json({"type": "error", "message": "Session not found."})
                    continue
                flush_session(session_id)
                session = stop_session(db, writable_session.id)
                if session is None:
                    await websocket.send_json({"type": "error", "message": "Session not found."})
                else:
                    await websocket.send_json({"type": "session_stopped", "session": {"id": session.id, "average_abs_cents": session.average_abs_cents}})
            elif msg_type == "audio_frame":
                try:
                    payload = AudioFrameIn(**message)
                    if not is_valid_instrument_id(payload.instrument_id):
                        await websocket.send_json({"type": "error", "message": "Unknown instrument_id: %s" % payload.instrument_id})
                        continue
                    frame = detector.estimate_frame(payload.pcm, payload.sample_rate, payload.instrument_id, payload.reference_pitch_hz).to_dict()
                    if payload.session_id:
                        if not can_write_session(payload.session_id):
                            await websocket.send_json({"type": "error", "message": "You do not have access to this session."})
                            continue
                        pending_frames[payload.session_id].append(frame)
                        if len(pending_frames[payload.session_id]) >= 12:
                            flush_session(payload.session_id)
                    await websocket.send_json({"type": "pitch_frame", "frame": frame})
                except Exception as exc:
                    detail = str(exc).lower()
                    if "pcm" in detail and ("too large" in detail or "at most" in detail):
                        await websocket.send_json({"type": "error", "message": "PCM frame is too large."})
                    else:
                        await websocket.send_json({"type": "error", "message": "Pitch detection failed."})
            else:
                await websocket.send_json({"type": "error", "message": "Unsupported WebSocket message type."})
    except WebSocketDisconnect:
        pass
    finally:
        for session_id in list(pending_frames.keys()):
            flush_session(session_id)
        db.close()
