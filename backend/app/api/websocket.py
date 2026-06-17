import json
from collections import defaultdict

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.core.instruments.profiles import is_valid_instrument_id
from app.core.pitch.detector import PitchDetector
from app.db.database import SessionLocal
from app.schemas.schemas import AudioFrameIn
from app.services.session_service import save_pitch_frames, start_session, stop_session

router = APIRouter()


@router.websocket("/ws/pitch")
async def pitch_socket(websocket: WebSocket):
    await websocket.accept()
    detector = PitchDetector()
    db = SessionLocal()
    pending_frames = defaultdict(list)

    def flush_session(session_id: int) -> None:
        frames = pending_frames.get(session_id, [])
        if frames:
            save_pitch_frames(db, session_id, frames)
            pending_frames[session_id] = []

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                message = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_json({"type": "error", "message": "Malformed JSON frame."})
                continue
            msg_type = message.get("type")
            if msg_type == "ping":
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
                    int(message.get("user_id", 1)),
                )
                await websocket.send_json({"type": "session_started", "session": {"id": session.id, "name": session.name}})
            elif msg_type == "stop_session":
                session_id = int(message.get("session_id", 0))
                flush_session(session_id)
                session = stop_session(db, session_id)
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
                        pending_frames[payload.session_id].append(frame)
                        if len(pending_frames[payload.session_id]) >= 12:
                            flush_session(payload.session_id)
                    await websocket.send_json({"type": "pitch_frame", "frame": frame})
                except Exception as exc:
                    await websocket.send_json({"type": "error", "message": "Pitch detection failed: %s" % exc})
            else:
                await websocket.send_json({"type": "error", "message": "Unsupported WebSocket message type."})
    except WebSocketDisconnect:
        pass
    finally:
        for session_id in list(pending_frames.keys()):
            flush_session(session_id)
        db.close()
