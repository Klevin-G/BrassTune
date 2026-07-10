import os
import re
from typing import List
from urllib.parse import urlparse


LOCAL_FRONTEND_ORIGINS = ["http://localhost:5173", "http://127.0.0.1:5173"]
AUTH_MODES = {"disabled", "supabase"}
LOCAL_ENVIRONMENTS = {"local", "test", "development", "dev"}
DEPLOYED_ENVIRONMENTS = {"production", "staging", "preview"}
APP_ENVIRONMENTS = LOCAL_ENVIRONMENTS | DEPLOYED_ENVIRONMENTS


def app_environment() -> str:
    environment = os.getenv("APP_ENV", "production").strip().lower()
    if environment not in APP_ENVIRONMENTS:
        raise RuntimeError("APP_ENV must be one of: dev, development, local, preview, production, staging, test.")
    return environment


def auth_mode() -> str:
    configured = os.getenv("BRASSTUNE_AUTH_MODE")
    if configured:
        mode = configured.strip().lower()
        if mode not in AUTH_MODES:
            raise RuntimeError("BRASSTUNE_AUTH_MODE must be one of: disabled, supabase.")
        return mode
    if app_environment() in DEPLOYED_ENVIRONMENTS:
        raise RuntimeError("BRASSTUNE_AUTH_MODE must be set to disabled or supabase when APP_ENV=production.")
    return "disabled"


def allowed_origins() -> List[str]:
    configured = os.getenv("CORS_ALLOWED_ORIGINS") or os.getenv("FRONTEND_ORIGIN")
    environment = app_environment()
    if environment in DEPLOYED_ENVIRONMENTS and not configured:
        raise RuntimeError("CORS_ALLOWED_ORIGINS or FRONTEND_ORIGIN must be set to exact HTTPS origins in deployed environments.")
    origins = [] if environment in DEPLOYED_ENVIRONMENTS else list(LOCAL_FRONTEND_ORIGINS)
    if configured:
        origins.extend([_normalize_origin(item) for item in configured.split(",") if item.strip()])
    return sorted(set(origins))


def _normalize_origin(raw_origin: str) -> str:
    origin = raw_origin.strip().rstrip("/")
    if app_environment() in DEPLOYED_ENVIRONMENTS:
        _validate_deployed_origin(origin)
    return origin


def _validate_deployed_origin(origin: str) -> None:
    if origin == "*" or "*" in origin:
        raise RuntimeError("Deployed CORS origins must be exact HTTPS origins; wildcards are not allowed.")
    parsed = urlparse(origin)
    if parsed.scheme != "https" or not parsed.netloc:
        raise RuntimeError("Deployed CORS origins must use https:// and include a host.")
    if parsed.path or parsed.params or parsed.query or parsed.fragment:
        raise RuntimeError("Deployed CORS origins must not include paths, query strings, or fragments.")
    if parsed.username or parsed.password:
        raise RuntimeError("Deployed CORS origins must not include credentials.")
    if parsed.hostname in {"localhost", "127.0.0.1", "::1"}:
        raise RuntimeError("Deployed CORS origins must not point to localhost.")


def cors_allowed_origin_regex() -> str | None:
    regex = os.getenv("CORS_ALLOWED_ORIGIN_REGEX")
    if not regex:
        return None
    if app_environment() in DEPLOYED_ENVIRONMENTS and os.getenv("BRASSTUNE_ALLOW_CORS_REGEX", "").strip().lower() not in {"1", "true", "yes", "on"}:
        raise RuntimeError("CORS_ALLOWED_ORIGIN_REGEX is disabled in deployed environments unless BRASSTUNE_ALLOW_CORS_REGEX=1 is explicitly set.")
    return regex


def origin_is_allowed(origin: str | None) -> bool:
    """True if the origin passes the SAME policy the HTTP CORS layer applies:
    an exact match against the configured origin list OR the configured
    origin regex (when enabled). Used by the WebSocket handshake so that WS and
    HTTP never diverge — otherwise a frontend allowed over HTTP by the regex is
    silently rejected on the pitch socket."""
    if not origin:
        return False
    normalized = origin.strip().rstrip("/")
    if normalized in allowed_origins():
        return True
    try:
        regex = cors_allowed_origin_regex()
    except RuntimeError:
        regex = None
    if regex:
        try:
            # Starlette's CORSMiddleware uses re.fullmatch for allow_origin_regex.
            if re.fullmatch(regex, normalized):
                return True
        except re.error:
            return False
    return False
