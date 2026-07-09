import datetime as dt
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Optional, Tuple

from fastapi import HTTPException

from app.db.database import DATA_DIR
from app.models.db import PracticeSession

ALLOWED_AUDIO_MIME_TYPES = {
    "audio/webm": ".webm",
    "audio/mp4": ".m4a",
    "audio/mpeg": ".mp3",
    "audio/wav": ".wav",
    "audio/ogg": ".ogg",
}
MAGIC_BYTES = {
    "audio/webm": (b"\x1a\x45\xdf\xa3",),
    "audio/mp4": (b"ftyp",),
    "audio/mpeg": (b"ID3", b"\xff\xfb", b"\xff\xf3", b"\xff\xf2"),
    "audio/wav": (b"RIFF",),
    "audio/ogg": (b"OggS",),
}
MAX_AUDIO_UPLOAD_BYTES = int(os.getenv("SESSION_AUDIO_MAX_BYTES", str(50 * 1024 * 1024)))
LOCAL_AUDIO_DIR = DATA_DIR / "audio"


def storage_backend() -> str:
    return os.getenv("SESSION_AUDIO_STORAGE_BACKEND", "local").strip().lower() or "local"


def audio_extension(mime_type: str) -> str:
    if mime_type not in ALLOWED_AUDIO_MIME_TYPES:
        raise HTTPException(status_code=400, detail="Unsupported audio MIME type.")
    return ALLOWED_AUDIO_MIME_TYPES[mime_type]


def read_audio_bytes(data: bytes, mime_type: str) -> Tuple[bytes, str]:
    mime_type = (mime_type or "application/octet-stream").split(";", 1)[0].strip().lower()
    audio_extension(mime_type)
    if not data:
        raise HTTPException(status_code=400, detail="Audio upload was empty.")
    if len(data) > MAX_AUDIO_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Audio upload is too large.")
    signatures = MAGIC_BYTES.get(mime_type, ())
    if mime_type == "audio/mp4":
        if len(data) < 12 or data[4:8] not in signatures:
            raise HTTPException(status_code=400, detail="Audio upload does not match its declared format.")
    elif mime_type == "audio/wav":
        if len(data) < 12 or not data.startswith(b"RIFF") or data[8:12] != b"WAVE":
            raise HTTPException(status_code=400, detail="Audio upload does not match its declared format.")
    elif signatures and not any(data.startswith(signature) for signature in signatures):
        raise HTTPException(status_code=400, detail="Audio upload does not match its declared format.")
    return data, mime_type


def object_key_for(session: PracticeSession, mime_type: str) -> str:
    extension = audio_extension(mime_type)
    return "%s/%s/recording%s" % (session.user_id, session.id, extension)


def local_audio_path(object_key: str) -> Path:
    safe_parts = [part for part in object_key.split("/") if part not in {"", ".", ".."}]
    path = LOCAL_AUDIO_DIR.joinpath(*safe_parts).resolve()
    if not str(path).startswith(str(LOCAL_AUDIO_DIR.resolve())):
        raise HTTPException(status_code=400, detail="Invalid audio object key.")
    return path


def _supabase_headers(mime_type: Optional[str] = None) -> dict:
    key = os.getenv("SUPABASE_SECRET_KEY")
    if not key:
        raise HTTPException(status_code=503, detail="Audio storage is unavailable.")
    headers = {"apikey": key, "Authorization": "Bearer %s" % key}
    if mime_type:
        headers["Content-Type"] = mime_type
    return headers


def _supabase_url(path: str) -> str:
    base = os.getenv("SUPABASE_URL")
    if not base:
        raise HTTPException(status_code=503, detail="Audio storage is unavailable.")
    parsed = urllib.parse.urlparse(base)
    is_local_http = parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1", "::1"}
    if parsed.scheme != "https" and not is_local_http:
        raise HTTPException(status_code=503, detail="Audio storage is unavailable.")
    if not parsed.netloc:
        raise HTTPException(status_code=503, detail="Audio storage is unavailable.")
    return "%s/%s" % (base.rstrip("/"), path.lstrip("/"))


def _upload_to_supabase(object_key: str, data: bytes, mime_type: str) -> None:
    bucket = os.getenv("SUPABASE_STORAGE_BUCKET", "session-audio")
    encoded_key = urllib.parse.quote(object_key)
    request = urllib.request.Request(
        _supabase_url("/storage/v1/object/%s/%s" % (bucket, encoded_key)),
        data=data,
        method="POST",
        headers={**_supabase_headers(mime_type), "x-upsert": "true"},
    )
    try:
        with urllib.request.urlopen(request, timeout=20):  # nosec B310
            return
    except urllib.error.HTTPError as exc:
        raise HTTPException(status_code=502, detail="Supabase audio upload failed.") from exc


def _read_supabase_object(object_key: str) -> bytes:
    bucket = os.getenv("SUPABASE_STORAGE_BUCKET", "session-audio")
    encoded_key = urllib.parse.quote(object_key)
    request = urllib.request.Request(
        _supabase_url("/storage/v1/object/%s/%s" % (bucket, encoded_key)),
        headers=_supabase_headers(),
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:  # nosec B310
            return response.read()
    except urllib.error.HTTPError as exc:
        raise HTTPException(status_code=502, detail="Supabase audio download failed.") from exc


def _delete_supabase_object(object_key: str) -> None:
    bucket = os.getenv("SUPABASE_STORAGE_BUCKET", "session-audio")
    encoded_key = urllib.parse.quote(object_key)
    request = urllib.request.Request(
        _supabase_url("/storage/v1/object/%s/%s" % (bucket, encoded_key)),
        method="DELETE",
        headers=_supabase_headers(),
    )
    try:
        with urllib.request.urlopen(request, timeout=20):  # nosec B310
            return
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return
        raise HTTPException(status_code=502, detail="Supabase audio deletion failed.") from exc


def create_supabase_signed_url(object_key: str, expires_in: int = 900) -> str:
    bucket = os.getenv("SUPABASE_STORAGE_BUCKET", "session-audio")
    encoded_key = urllib.parse.quote(object_key)
    request = urllib.request.Request(
        _supabase_url("/storage/v1/object/sign/%s/%s" % (bucket, encoded_key)),
        data=json.dumps({"expiresIn": expires_in}).encode("utf-8"),
        method="POST",
        headers={**_supabase_headers("application/json")},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:  # nosec B310
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise HTTPException(status_code=502, detail="Supabase signed URL failed.") from exc
    signed = payload.get("signedURL") or payload.get("signedUrl") or payload.get("signed_url")
    if not signed:
        raise HTTPException(status_code=502, detail="Supabase did not return a signed playback URL.")
    if signed.startswith("http"):
        return signed
    return _supabase_url(signed)


def attach_audio_to_session(session: PracticeSession, data: bytes, mime_type: str, duration_seconds: Optional[float]) -> PracticeSession:
    provider = storage_backend()
    object_key = object_key_for(session, mime_type)
    if provider == "supabase":
        _upload_to_supabase(object_key, data, mime_type)
    elif provider == "local":
        path = local_audio_path(object_key)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    else:
        raise HTTPException(status_code=503, detail="Unsupported SESSION_AUDIO_STORAGE_BACKEND.")
    session.audio_storage_provider = provider
    session.audio_object_key = object_key
    session.audio_mime_type = mime_type
    session.audio_duration_seconds = duration_seconds
    session.audio_size_bytes = len(data)
    session.audio_uploaded_at = dt.datetime.utcnow()
    return session


def delete_audio_for_session(session: PracticeSession) -> None:
    if not session.audio_object_key:
        return
    if session.audio_storage_provider == "local":
        path = local_audio_path(session.audio_object_key)
        if path.exists():
            path.unlink()
    elif session.audio_storage_provider == "supabase":
        _delete_supabase_object(session.audio_object_key)
    session.audio_storage_provider = None
    session.audio_object_key = None
    session.audio_mime_type = None
    session.audio_duration_seconds = None
    session.audio_size_bytes = None
    session.audio_uploaded_at = None


def audio_bytes_for_export(session: PracticeSession) -> Optional[Tuple[str, bytes]]:
    if not session.audio_object_key:
        return None
    filename = Path(session.audio_object_key).name
    if session.audio_storage_provider == "local":
        path = local_audio_path(session.audio_object_key)
        if not path.exists():
            return None
        return filename, path.read_bytes()
    if session.audio_storage_provider == "supabase":
        return filename, _read_supabase_object(session.audio_object_key)
    return None
