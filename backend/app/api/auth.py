import datetime as dt
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Optional

from fastapi import Depends, Header, HTTPException
from sqlalchemy.orm import Session

from app.core.security import DEPLOYED_ENVIRONMENTS, LOCAL_ENVIRONMENTS, app_environment, auth_mode
from app.core.instruments.profiles import is_valid_instrument_id
from app.db.database import get_db
from app.models.db import AccountDeletionJob, User
from app.services.session_service import get_or_create_default_user


USERNAME_RE = re.compile(r"^[a-z0-9_-]{3,32}$")


@dataclass
class AuthContext:
    user: User
    is_guest: bool = False
    access_token: Optional[str] = None


def local_auth_enabled() -> bool:
    environment = app_environment()
    if environment in DEPLOYED_ENVIRONMENTS:
        return False
    return auth_mode() == "disabled" and (environment in LOCAL_ENVIRONMENTS or os.getenv("BRASSTUNE_ALLOW_LOCAL_AUTH") == "1")


def assert_auth_configured() -> None:
    environment = app_environment()
    if environment in DEPLOYED_ENVIRONMENTS and os.getenv("BRASSTUNE_ALLOW_LOCAL_AUTH") == "1":
        raise RuntimeError("BRASSTUNE_ALLOW_LOCAL_AUTH cannot be enabled in deployed environments.")
    mode = auth_mode()
    if mode == "disabled":
        if environment in DEPLOYED_ENVIRONMENTS:
            raise RuntimeError("BRASSTUNE_AUTH_MODE=disabled is not allowed in deployed environments.")
        return
    if not os.getenv("SUPABASE_URL"):
        raise RuntimeError("SUPABASE_URL is required when BRASSTUNE_AUTH_MODE=supabase.")
    if not os.getenv("SUPABASE_PUBLISHABLE_KEY"):
        raise RuntimeError("SUPABASE_PUBLISHABLE_KEY is required when BRASSTUNE_AUTH_MODE=supabase.")
    if not os.getenv("SUPABASE_SECRET_KEY"):
        raise RuntimeError("SUPABASE_SECRET_KEY is required when BRASSTUNE_AUTH_MODE=supabase.")


def _bearer_token(authorization: Optional[str]) -> Optional[str]:
    if not authorization:
        return None
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        return None
    return token.strip()


def _normalize_username(value: Optional[str], fallback: str) -> str:
    candidate = (value or fallback).strip().lower()
    candidate = re.sub(r"[^a-z0-9_-]+", "-", candidate).strip("-_")
    if not USERNAME_RE.match(candidate):
        candidate = fallback
    return candidate[:32]


def _unique_username(db: Session, preferred: str, user_id: Optional[int] = None) -> str:
    base = _normalize_username(preferred, "player")
    candidate = base
    suffix = 2
    while True:
        query = db.query(User).filter(User.username == candidate)
        if user_id is not None:
            query = query.filter(User.id != user_id)
        if query.first() is None:
            return candidate
        candidate = "%s-%s" % (base[: max(1, 31 - len(str(suffix)))], suffix)
        suffix += 1


def _sync_supabase_user(db: Session, payload: dict) -> User:
    supabase_id = str(payload.get("id") or "")
    if not supabase_id:
        raise HTTPException(status_code=401, detail="Supabase token did not include a user id.")
    email = payload.get("email")
    metadata = payload.get("user_metadata") or {}
    user = db.query(User).filter(User.supabase_user_id == supabase_id).first()
    if user is None:
        deletion_job = (
            db.query(AccountDeletionJob)
            .filter(AccountDeletionJob.supabase_user_id == supabase_id)
            .order_by(AccountDeletionJob.updated_at.desc())
            .first()
        )
        if deletion_job is not None:
            if deletion_job.status == "completed":
                raise HTTPException(status_code=410, detail="This account has been deleted.")
            raise HTTPException(status_code=423, detail="Account deletion is still finishing. Try again later.")
    if user is None:
        preferred_username = metadata.get("username") or (email.split("@")[0] if email else "player")
        user = User(
            supabase_user_id=supabase_id,
            email=email,
            username=_unique_username(db, preferred_username),
            name=metadata.get("display_name") or metadata.get("name") or email or "BrassTune Player",
            display_name=metadata.get("display_name") or metadata.get("name"),
            role="student",
            primary_instrument_id=metadata.get("primary_instrument_id") if is_valid_instrument_id(metadata.get("primary_instrument_id", "")) else "trumpet",
        )
        db.add(user)
    else:
        user.supabase_user_id = supabase_id
        user.email = email or user.email
        if metadata.get("display_name"):
            user.display_name = metadata["display_name"]
            user.name = metadata["display_name"]
        if metadata.get("username") and USERNAME_RE.match(str(metadata["username"])):
            user.username = _unique_username(db, metadata["username"], user.id)
        if is_valid_instrument_id(metadata.get("primary_instrument_id", "")):
            user.primary_instrument_id = metadata["primary_instrument_id"]
    user.updated_at = dt.datetime.utcnow()
    db.commit()
    db.refresh(user)
    return user


def _supabase_endpoint(path: str) -> str:
    supabase_url = os.getenv("SUPABASE_URL")
    if not supabase_url:
        raise HTTPException(status_code=401, detail="Supabase auth is not configured on the backend.")
    parsed = urllib.parse.urlparse(supabase_url)
    is_local_http = parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1", "::1"}
    if parsed.scheme != "https" and not is_local_http:
        raise HTTPException(status_code=503, detail="SUPABASE_URL must be HTTPS outside local development.")
    if not parsed.netloc:
        raise HTTPException(status_code=503, detail="SUPABASE_URL is invalid.")
    return "%s/%s" % (supabase_url.rstrip("/"), path.lstrip("/"))


def _fetch_supabase_user(token: str) -> dict:
    api_key = os.getenv("SUPABASE_SECRET_KEY") or os.getenv("SUPABASE_PUBLISHABLE_KEY")
    if not api_key:
        raise HTTPException(status_code=401, detail="Supabase auth is not configured on the backend.")
    request = urllib.request.Request(
        _supabase_endpoint("/auth/v1/user"),
        headers={"apikey": api_key, "Authorization": "Bearer %s" % token},
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:  # nosec B310
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired Supabase token.") from exc
    except OSError as exc:
        raise HTTPException(status_code=503, detail="Could not validate Supabase token.") from exc


def _supabase_service_key() -> str:
    key = os.getenv("SUPABASE_SECRET_KEY")
    if not key:
        raise HTTPException(status_code=503, detail="SUPABASE_SECRET_KEY is required for account deletion.")
    return key


def supabase_global_sign_out(token: Optional[str]) -> bool:
    if not token or token.startswith("dev-user-"):
        return False
    service_key = _supabase_service_key()
    request = urllib.request.Request(
        _supabase_endpoint("/auth/v1/logout?scope=global"),
        data=b"{}",
        method="POST",
        headers={"apikey": service_key, "Authorization": "Bearer %s" % token, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=10):  # nosec B310
            return True
    except urllib.error.HTTPError as exc:
        raise HTTPException(status_code=502, detail="Supabase session revocation failed.") from exc
    except OSError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Supabase to revoke sessions.") from exc


def delete_supabase_identity(supabase_user_id: Optional[str]) -> bool:
    if not supabase_user_id:
        return False
    service_key = _supabase_service_key()
    encoded_user_id = urllib.parse.quote(supabase_user_id, safe="")
    request = urllib.request.Request(
        _supabase_endpoint("/auth/v1/admin/users/%s" % encoded_user_id),
        method="DELETE",
        headers={"apikey": service_key, "Authorization": "Bearer %s" % service_key},
    )
    try:
        with urllib.request.urlopen(request, timeout=10):  # nosec B310
            return True
    except urllib.error.HTTPError as exc:
        raise HTTPException(status_code=502, detail="Supabase identity deletion failed.") from exc
    except OSError as exc:
        raise HTTPException(status_code=503, detail="Could not reach Supabase to delete the identity.") from exc


def _dev_token_user(db: Session, token: str) -> Optional[User]:
    if not local_auth_enabled() or not token.startswith("dev-user-"):
        return None
    try:
        user_id = int(token.replace("dev-user-", "", 1))
    except ValueError:
        return None
    return db.query(User).filter(User.id == user_id).first()


def get_auth_context(authorization: Optional[str] = Header(default=None), db: Session = Depends(get_db)) -> AuthContext:
    token = _bearer_token(authorization)
    return auth_context_from_token(db, token)


def auth_context_from_token(db: Session, token: Optional[str]) -> AuthContext:
    if token:
        dev_user = _dev_token_user(db, token)
        if dev_user is not None:
            return AuthContext(user=dev_user, is_guest=False, access_token=token)
        if auth_mode() == "disabled":
            raise HTTPException(status_code=401, detail="Accounts are unavailable in this environment.")
        payload = _fetch_supabase_user(token)
        return AuthContext(user=_sync_supabase_user(db, payload), is_guest=False, access_token=token)
    if local_auth_enabled():
        user = get_or_create_default_user(db)
        if not user.username:
            user.username = "avery"
            user.display_name = user.display_name or user.name
            db.add(user)
            db.commit()
            db.refresh(user)
        return AuthContext(user=user, is_guest=True, access_token=None)
    raise HTTPException(status_code=401, detail="Authentication required.")


def require_roles(*roles: str):
    def dependency(auth: AuthContext = Depends(get_auth_context)) -> AuthContext:
        if auth.user.role not in roles and auth.user.role != "admin":
            raise HTTPException(status_code=403, detail="Insufficient permissions.")
        return auth

    return dependency
