import json
import asyncio
from collections import defaultdict, deque
import ipaddress
import os
import threading
import time
from typing import Optional

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import ValidationError

from app.api.auth import AuthContext, auth_context_from_token, local_auth_enabled
from app.core.security import LOCAL_ENVIRONMENTS, app_environment, origin_is_allowed
from app.core.instruments.profiles import is_valid_instrument_id
from app.core.pitch.detector import PitchDetector
from app.db.database import SessionLocal
from app.models.db import PracticeSession
from app.schemas.schemas import AudioFrameIn, StartSessionRequest
from app.services.session_service import save_pitch_frames, start_session, stop_session

router = APIRouter()

MAX_WS_MESSAGE_BYTES = 256 * 1024
MAX_UNAUTHENTICATED_ERRORS = 3
UNAUTHENTICATED_TIMEOUT_SECONDS = 15
IDLE_TIMEOUT_SECONDS = 120

_WS_STATE_LOCK = threading.Lock()
_WS_CONNECTIONS_BY_IP = defaultdict(int)
_WS_CONNECTIONS_BY_ACCOUNT = defaultdict(int)
_WS_SESSION_STARTS_BY_IP = defaultdict(deque)
_WS_SESSION_STARTS_BY_ACCOUNT = defaultdict(deque)
_WS_ACTIVE_PITCH_COMPUTATIONS = 0
_WS_SESSION_START_WINDOW_SECONDS = 60


def _positive_int_env(name: str, default: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default
    return value if value >= 0 else default


def _websocket_client_host(websocket: WebSocket) -> str:
    if os.getenv("BRASSTUNE_TRUST_PROXY", "").strip().lower() in {"1", "true", "yes"}:
        forwarded = websocket.headers.get("x-forwarded-for", "")
        if forwarded and len(forwarded) <= 1024:
            # Match Render's first-entry contract and the HTTP middleware. A
            # malformed first entry fails back to the socket peer; never scan
            # later, potentially attacker-controlled values for a usable IP.
            candidate = forwarded.split(",", 1)[0].strip()
            try:
                if candidate and len(candidate) <= 64 and "%" not in candidate:
                    return str(ipaddress.ip_address(candidate))
            except ValueError:
                pass
    return websocket.client.host if websocket.client else "unknown"


def _try_acquire_connection(store, key, limit: int) -> bool:
    with _WS_STATE_LOCK:
        if limit and store[key] >= limit:
            return False
        store[key] += 1
        return True


def _release_connection(store, key) -> None:
    if key is None:
        return
    with _WS_STATE_LOCK:
        remaining = store.get(key, 0) - 1
        if remaining > 0:
            store[key] = remaining
        else:
            store.pop(key, None)


def _try_acquire_pitch_compute_slot() -> bool:
    global _WS_ACTIVE_PITCH_COMPUTATIONS
    limit = _positive_int_env("BRASSTUNE_WS_MAX_CONCURRENT_PITCH_COMPUTATIONS", 4)
    with _WS_STATE_LOCK:
        if limit and _WS_ACTIVE_PITCH_COMPUTATIONS >= limit:
            return False
        _WS_ACTIVE_PITCH_COMPUTATIONS += 1
        return True


def _release_pitch_compute_slot() -> None:
    global _WS_ACTIVE_PITCH_COMPUTATIONS
    with _WS_STATE_LOCK:
        _WS_ACTIVE_PITCH_COMPUTATIONS = max(0, _WS_ACTIVE_PITCH_COMPUTATIONS - 1)


def _prune_start_buckets(store, now: float) -> None:
    for key in list(store.keys()):
        bucket = store[key]
        while bucket and now - bucket[0] >= _WS_SESSION_START_WINDOW_SECONDS:
            bucket.popleft()
        if not bucket:
            del store[key]


def _try_consume_session_start(account_key: str, client_host: str, now: float | None = None) -> bool:
    timestamp = time.monotonic() if now is None else now
    account_limit = _positive_int_env("BRASSTUNE_WS_SESSION_STARTS_PER_ACCOUNT_PER_MINUTE", 30)
    ip_limit = _positive_int_env("BRASSTUNE_WS_SESSION_STARTS_PER_IP_PER_MINUTE", 60)
    with _WS_STATE_LOCK:
        _prune_start_buckets(_WS_SESSION_STARTS_BY_ACCOUNT, timestamp)
        _prune_start_buckets(_WS_SESSION_STARTS_BY_IP, timestamp)
        account_bucket = _WS_SESSION_STARTS_BY_ACCOUNT.get(account_key)
        ip_bucket = _WS_SESSION_STARTS_BY_IP.get(client_host)
        if account_limit and account_bucket is not None and len(account_bucket) >= account_limit:
            return False
        if ip_limit and ip_bucket is not None and len(ip_bucket) >= ip_limit:
            return False
        if account_limit:
            _WS_SESSION_STARTS_BY_ACCOUNT[account_key].append(timestamp)
        if ip_limit:
            _WS_SESSION_STARTS_BY_IP[client_host].append(timestamp)
        return True


def _reset_abuse_state_for_tests() -> None:
    global _WS_ACTIVE_PITCH_COMPUTATIONS
    with _WS_STATE_LOCK:
        _WS_CONNECTIONS_BY_IP.clear()
        _WS_CONNECTIONS_BY_ACCOUNT.clear()
        _WS_SESSION_STARTS_BY_IP.clear()
        _WS_SESSION_STARTS_BY_ACCOUNT.clear()
        _WS_ACTIVE_PITCH_COMPUTATIONS = 0


class _AudioFrameBudget:
    def __init__(self) -> None:
        self.events = deque()

    def consume(self, sample_count: int, now: float | None = None) -> bool:
        timestamp = time.monotonic() if now is None else now
        while self.events and timestamp - self.events[0][0] >= 1.0:
            self.events.popleft()
        frame_limit = _positive_int_env("BRASSTUNE_WS_MAX_AUDIO_FRAMES_PER_SECOND", 30)
        sample_limit = _positive_int_env("BRASSTUNE_WS_MAX_PCM_SAMPLES_PER_SECOND", 400_000)
        if frame_limit and len(self.events) >= frame_limit:
            return False
        samples = max(0, sample_count)
        if sample_limit and sum(count for _, count in self.events) + samples > sample_limit:
            return False
        self.events.append((timestamp, samples))
        return True


def _can_track_pending_session(pending_frames, session_id: int) -> bool:
    limit = _positive_int_env("BRASSTUNE_WS_MAX_PENDING_SESSIONS_PER_CONNECTION", 4)
    return session_id in pending_frames or not limit or len(pending_frames) < limit


async def _reject(websocket: WebSocket, message: str, code: int = 1008) -> None:
    await websocket.accept()
    await websocket.send_json({"type": "error", "message": message})
    await websocket.close(code=code)


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

    client_host = _websocket_client_host(websocket)
    ip_acquired = _try_acquire_connection(
        _WS_CONNECTIONS_BY_IP,
        client_host,
        _positive_int_env("BRASSTUNE_WS_MAX_CONNECTIONS_PER_IP", 8),
    )
    if not ip_acquired:
        await _reject(websocket, "Too many WebSocket connections from this network.", code=1013)
        return

    db = None
    account_key = None
    account_acquired = False
    pending_frames = defaultdict(list)
    frame_budget = _AudioFrameBudget()
    unauthenticated_errors = 0

    try:
        await websocket.accept()
        detector = PitchDetector()
        db = SessionLocal()
        auth: Optional[AuthContext] = None

        def acquire_account(auth_context: AuthContext) -> bool:
            nonlocal account_key, account_acquired
            candidate = str(auth_context.user.id)
            if not _try_acquire_connection(
                _WS_CONNECTIONS_BY_ACCOUNT,
                candidate,
                _positive_int_env("BRASSTUNE_WS_MAX_CONNECTIONS_PER_ACCOUNT", 4),
            ):
                return False
            account_key = candidate
            account_acquired = True
            return True

        if websocket.query_params:
            await websocket.send_json({"type": "error", "message": "WebSocket query-token auth is disabled."})
            await websocket.close(code=1008)
            return
        if local_auth_enabled():
            try:
                auth = auth_context_from_token(db, None)
            except HTTPException as exc:
                await websocket.send_json({"type": "error", "message": exc.detail})
                await websocket.close(code=1008)
                return
            if not acquire_account(auth):
                await websocket.send_json({"type": "error", "message": "Too many WebSocket connections for this account."})
                await websocket.close(code=1013)
                return

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
            if not isinstance(message, dict):
                await websocket.send_json({"type": "error", "message": "WebSocket messages must be JSON objects."})
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
                    authenticated = auth_context_from_token(db, token)
                    if not acquire_account(authenticated):
                        await websocket.send_json({"type": "error", "message": "Too many WebSocket connections for this account."})
                        await websocket.close(code=1013)
                        return
                    auth = authenticated
                    await websocket.send_json({"type": "authenticated"})
                except HTTPException as exc:
                    await websocket.send_json({"type": "error", "message": exc.detail})
                    await websocket.close(code=1008)
                    return
                continue
            if msg_type == "authenticate":
                await websocket.send_json({"type": "authenticated"})
            elif msg_type == "ping":
                await websocket.send_json({"type": "pong"})
            elif msg_type == "start_session":
                try:
                    request = StartSessionRequest.model_validate(
                        {
                            "instrument_id": message.get("instrument_id", "trumpet"),
                            "name": message.get("name"),
                            "reference_pitch_hz": message.get("reference_pitch_hz", 440.0),
                        }
                    )
                except ValidationError:
                    await websocket.send_json({"type": "error", "message": "Session details are invalid."})
                    continue
                if not is_valid_instrument_id(request.instrument_id):
                    await websocket.send_json({"type": "error", "message": "Unknown instrument_id: %s" % request.instrument_id})
                    continue
                if not _try_consume_session_start(str(auth.user.id), client_host):
                    await websocket.send_json({"type": "error", "message": "Too many session starts. Wait a moment before trying again."})
                    continue
                try:
                    session = start_session(
                        db,
                        request.instrument_id,
                        request.name,
                        request.reference_pitch_hz,
                        auth.user.id,
                    )
                except HTTPException as exc:
                    db.rollback()
                    await websocket.send_json({"type": "error", "message": exc.detail})
                    continue
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
                    raw_pcm = message.get("pcm")
                    sample_count = len(raw_pcm) if isinstance(raw_pcm, list) else 0
                    if not frame_budget.consume(sample_count):
                        await websocket.send_json({"type": "error", "message": "WebSocket audio frame rate limit exceeded."})
                        await websocket.close(code=1008)
                        return
                    payload = AudioFrameIn(**message)
                    if not is_valid_instrument_id(payload.instrument_id):
                        await websocket.send_json({"type": "error", "message": "Unknown instrument_id: %s" % payload.instrument_id})
                        continue
                    if not _try_acquire_pitch_compute_slot():
                        await websocket.send_json({"type": "error", "message": "Pitch processing is busy. Reconnect in a moment."})
                        await websocket.close(code=1013)
                        return
                    def estimate_with_slot():
                        try:
                            return detector.estimate_frame(
                                payload.pcm,
                                payload.sample_rate,
                                payload.instrument_id,
                                payload.reference_pitch_hz,
                            )
                        finally:
                            # Release from the worker only after the synchronous
                            # detector actually stops, even if the awaiting socket
                            # task is cancelled while work is still running.
                            _release_pitch_compute_slot()

                    detected = await asyncio.to_thread(
                        estimate_with_slot,
                    )
                    frame = detected.to_dict()
                    if payload.session_id:
                        if not can_write_session(payload.session_id):
                            await websocket.send_json({"type": "error", "message": "You do not have access to this session."})
                            continue
                        if not _can_track_pending_session(pending_frames, payload.session_id):
                            await websocket.send_json({"type": "error", "message": "Too many pending sessions on this WebSocket connection."})
                            await websocket.close(code=1008)
                            return
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
        try:
            if db is not None:
                for session_id in list(pending_frames.keys()):
                    try:
                        frames = pending_frames.get(session_id, [])
                        if frames:
                            save_pitch_frames(db, session_id, frames)
                    except Exception:
                        db.rollback()
                db.close()
        finally:
            if account_acquired:
                _release_connection(_WS_CONNECTIONS_BY_ACCOUNT, account_key)
            _release_connection(_WS_CONNECTIONS_BY_IP, client_host)
