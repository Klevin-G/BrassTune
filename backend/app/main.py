from contextlib import asynccontextmanager
from collections import defaultdict, deque
import ipaddress
import logging
import os
import re
import time
import uuid

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api.auth import assert_auth_configured
from app.api.errors import client_error_response
from app.api.routes import router as api_router
from app.api.websocket import router as websocket_router
from app.core.security import LOCAL_ENVIRONMENTS, allowed_origins, app_environment, cors_allowed_origin_regex
from app.db.database import SessionLocal, init_db
from app.db.seed import seed_demo_data


_RATE_LIMIT_BUCKETS = defaultdict(deque)
_GLOBAL_RATE_LIMIT_BUCKETS = defaultdict(deque)
_EXPENSIVE_RATE_LIMIT_BUCKETS = defaultdict(deque)
_RATE_LIMIT_WINDOW_SECONDS = 60
_DEFAULT_MAX_JSON_BODY_BYTES = 1_000_000
_ABSOLUTE_MAX_JSON_BODY_BYTES = 2_000_000
logger = logging.getLogger("brasstune.api")

_NUMERIC_PATH_SEGMENT = re.compile(r"^\d+$")
_UUID_PATH_SEGMENT = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    re.IGNORECASE,
)


def should_seed_demo_data() -> bool:
    configured = os.getenv("BRASSTUNE_SEED_DEMO_DATA", "").strip().lower()
    if configured in {"1", "true", "yes", "on"}:
        return True
    if configured in {"0", "false", "no", "off"}:
        return False
    return app_environment() in LOCAL_ENVIRONMENTS


@asynccontextmanager
async def lifespan(app: FastAPI):
    assert_auth_configured()
    init_db()
    db = SessionLocal()
    try:
        if should_seed_demo_data():
            seed_demo_data(db)
    finally:
        db.close()
    yield


app = FastAPI(title="BrassTune Analytics API", version="0.1.0", lifespan=lifespan)


def cors_origins():
    return allowed_origins()


def _positive_int_env(name: str, default: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default
    return value if value >= 0 else default


def _bounded_json_body_limit() -> int:
    configured = _positive_int_env("BRASSTUNE_MAX_JSON_BODY_BYTES", _DEFAULT_MAX_JSON_BODY_BYTES)
    if configured <= 0:
        return _DEFAULT_MAX_JSON_BODY_BYTES
    return min(configured, _ABSOLUTE_MAX_JSON_BODY_BYTES)


def _is_json_media_type(content_type: str) -> bool:
    media_type = (content_type or "").split(";", 1)[0].strip().lower()
    return media_type == "application/json" or media_type.endswith("+json")


def _prune_rate_limit_store(store, now: float | None = None) -> None:
    timestamp = time.monotonic() if now is None else now
    for key in list(store.keys()):
        bucket = store[key]
        while bucket and timestamp - bucket[0] > _RATE_LIMIT_WINDOW_SECONDS:
            bucket.popleft()
        if not bucket:
            del store[key]


def _prune_rate_limit_buckets(now: float | None = None) -> None:
    """Backward-compatible route-bucket pruning used by existing tests."""
    _prune_rate_limit_store(_RATE_LIMIT_BUCKETS, now)


def _ensure_rate_limit_capacity(store, max_buckets: int, now: float) -> None:
    """Keep limiter memory bounded without letting a cardinality attack deny all
    previously unseen clients/routes. The independent per-client global bucket
    remains the primary anti-rotation control."""
    if not max_buckets or len(store) < max_buckets:
        return
    _prune_rate_limit_store(store, now)
    while len(store) >= max_buckets:
        oldest_key = min(
            store,
            key=lambda key: store[key][-1] if store[key] else float("-inf"),
        )
        del store[oldest_key]


def _consume_rate_limit(store, key, limit: int, max_buckets: int, now: float) -> bool:
    if not limit:
        return True
    if key not in store:
        _ensure_rate_limit_capacity(store, max_buckets, now)
    bucket = store[key]
    while bucket and now - bucket[0] > _RATE_LIMIT_WINDOW_SECONDS:
        bucket.popleft()
    if len(bucket) >= limit:
        return False
    bucket.append(now)
    return True


def _canonical_rate_limit_path(path: str) -> str:
    segments = []
    for segment in path.split("/"):
        if _NUMERIC_PATH_SEGMENT.fullmatch(segment):
            segments.append("{id}")
        elif _UUID_PATH_SEGMENT.fullmatch(segment):
            segments.append("{uuid}")
        else:
            segments.append(segment)
    return "/".join(segments) or "/"


def _safe_log_route(request: Request) -> str:
    """Return only an application-owned route template, never raw user input."""
    route = request.scope.get("route")
    route_path = getattr(route, "path", None)
    if isinstance(route_path, str) and route_path.startswith("/") and len(route_path) <= 200:
        return route_path
    return "unmatched"


def _trusted_forwarded_client(request: Request) -> str | None:
    if os.getenv("BRASSTUNE_TRUST_PROXY", "").strip().lower() not in {"1", "true", "yes"}:
        return None
    forwarded = request.headers.get("x-forwarded-for", "")
    if not forwarded or len(forwarded) > 1024:
        return None
    # Render's documented rate-limit example uses the first X-Forwarded-For
    # entry, and Render staff state that the platform sets that entry to the
    # real client address. Never scan later entries after a malformed first
    # value: those values can originate in an untrusted incoming chain.
    candidate = forwarded.split(",", 1)[0].strip()
    if not candidate or len(candidate) > 64 or "%" in candidate:
        return None
    try:
        return str(ipaddress.ip_address(candidate))
    except ValueError:
        return None


def _request_client_host(request: Request) -> str:
    return _trusted_forwarded_client(request) or (request.client.host if request.client else "unknown")


def _expensive_operation_family(request: Request, canonical_path: str) -> tuple[str, int] | None:
    method = request.method.upper()
    if method == "POST" and canonical_path == "/api/ensemble/join":
        return "class-join", _positive_int_env("BRASSTUNE_CLASS_JOIN_RATE_LIMIT_PER_MINUTE", 10)

    is_expensive_mutation = method in {"POST", "PUT", "PATCH", "DELETE"} and (
        canonical_path == "/api/ensemble/groups"
        or canonical_path.endswith("/members/by-username")
        or canonical_path.endswith("/audio")
        or canonical_path == "/api/sessions/start"
        or canonical_path == "/api/users/me"
    )
    if is_expensive_mutation:
        if canonical_path.endswith("/audio"):
            family = "audio-upload"
        elif canonical_path.endswith("/members/by-username"):
            family = "class-invite"
        elif canonical_path == "/api/ensemble/groups":
            family = "class-create"
        elif canonical_path == "/api/sessions/start":
            family = "session-start"
        else:
            family = "account-mutation"
        return family, _positive_int_env("BRASSTUNE_EXPENSIVE_MUTATION_RATE_LIMIT_PER_MINUTE", 60)

    if method == "GET" and canonical_path == "/api/sessions/{id}/audio":
        return "audio-playback", _positive_int_env("BRASSTUNE_AUDIO_PLAYBACK_RATE_LIMIT_PER_MINUTE", 30)
    if method == "GET" and canonical_path == "/api/export/session/{id}/audio":
        return "audio-playback", _positive_int_env("BRASSTUNE_AUDIO_PLAYBACK_RATE_LIMIT_PER_MINUTE", 30)
    if method == "GET" and (
        canonical_path.startswith("/api/export/")
        or canonical_path == "/api/users/me/export.zip"
    ):
        return "large-export", _positive_int_env("BRASSTUNE_EXPENSIVE_READ_RATE_LIMIT_PER_MINUTE", 10)
    return None


class JSONBodyLimitMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope.get("type") != "http":
            await self.app(scope, receive, send)
            return

        headers = {key.decode("latin1").lower(): value.decode("latin1") for key, value in scope.get("headers", [])}
        content_type = headers.get("content-type", "")
        max_json_bytes = _bounded_json_body_limit()
        if not _is_json_media_type(content_type):
            await self.app(scope, receive, send)
            return

        body = bytearray()
        more_body = True
        while more_body:
            message = await receive()
            if message.get("type") != "http.request":
                continue
            body.extend(message.get("body", b""))
            if len(body) > max_json_bytes:
                response = client_error_response(413, "Request body is too large.")
                await response(scope, receive, send)
                return
            more_body = message.get("more_body", False)

        replayed = False

        async def replay_receive():
            nonlocal replayed
            if replayed:
                return {"type": "http.request", "body": b"", "more_body": False}
            replayed = True
            return {"type": "http.request", "body": bytes(body), "more_body": False}

        await self.app(scope, replay_receive, send)


_CORS_ALLOWED_ORIGINS = cors_origins()
_CORS_ALLOWED_ORIGIN_REGEX = cors_allowed_origin_regex()
_CORS_ORIGIN_REGEX_PATTERN = re.compile(_CORS_ALLOWED_ORIGIN_REGEX) if _CORS_ALLOWED_ORIGIN_REGEX else None


def _origin_allowed_for_cors(origin: str) -> bool:
    if "*" in _CORS_ALLOWED_ORIGINS or origin in _CORS_ALLOWED_ORIGINS:
        return True
    return _CORS_ORIGIN_REGEX_PATTERN is not None and _CORS_ORIGIN_REGEX_PATTERN.fullmatch(origin) is not None


app.add_middleware(JSONBodyLimitMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_CORS_ALLOWED_ORIGINS,
    allow_origin_regex=_CORS_ALLOWED_ORIGIN_REGEX,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Audio-Duration-Seconds"],
)


@app.exception_handler(StarletteHTTPException)
async def stable_http_error(_request: Request, exc: StarletteHTTPException):
    return client_error_response(
        exc.status_code,
        exc.detail,
        headers=dict(exc.headers or {}),
    )


@app.exception_handler(RequestValidationError)
async def stable_validation_error(_request: Request, exc: RequestValidationError):
    return client_error_response(422, exc.errors(), code="request_validation_failed")


@app.middleware("http")
async def request_abuse_limits(request: Request, call_next):
    request_id = uuid.uuid4().hex

    def harden_response(response):
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
        response.headers.setdefault("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=(), usb=(), serial=(), browsing-topics=()")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'; base-uri 'none'")
        response.headers.setdefault("Cache-Control", "no-store")
        response.headers.setdefault("X-Request-ID", request_id)
        if request.url.scheme == "https" or app_environment() in {"production", "staging", "preview"}:
            response.headers.setdefault("Strict-Transport-Security", "max-age=63072000; includeSubDomains; preload")
        # Guard responses (413/429/500) short-circuit before CORSMiddleware, so mirror the CORS
        # headers here for allowed origins; stays fail-closed and never overrides CORSMiddleware.
        origin = request.headers.get("origin")
        if origin and "access-control-allow-origin" not in response.headers and _origin_allowed_for_cors(origin):
            response.headers["Access-Control-Allow-Origin"] = origin
            response.headers["Access-Control-Allow-Credentials"] = "true"
            response.headers.setdefault("Vary", "Origin")
        return response

    origin = request.headers.get("origin")
    if origin and len(origin) > 512:
        return harden_response(client_error_response(400, "Origin header is too large."))

    if request.method.upper() == "OPTIONS":
        return harden_response(await call_next(request))

    content_type = request.headers.get("content-type", "")
    max_json_bytes = _bounded_json_body_limit()
    content_length = request.headers.get("content-length")
    if _is_json_media_type(content_type) and content_length:
        try:
            parsed_content_length = int(content_length)
            if parsed_content_length < 0:
                return harden_response(client_error_response(400, "Invalid request size."))
            if parsed_content_length > max_json_bytes:
                return harden_response(client_error_response(413, "Request body is too large."))
        except ValueError:
            return harden_response(client_error_response(400, "Invalid request size."))

    if request.url.path not in {"/api/health", "/api/live"}:
        client_host = _request_client_host(request)
        canonical_path = _canonical_rate_limit_path(request.url.path)
        now = time.monotonic()
        max_buckets = _positive_int_env("BRASSTUNE_RATE_LIMIT_MAX_BUCKETS", 10000)
        max_clients = _positive_int_env("BRASSTUNE_RATE_LIMIT_MAX_CLIENTS", 10000)

        global_limit = _positive_int_env("BRASSTUNE_GLOBAL_RATE_LIMIT_PER_MINUTE", 1800)
        if not _consume_rate_limit(
            _GLOBAL_RATE_LIMIT_BUCKETS,
            client_host,
            global_limit,
            max_clients,
            now,
        ):
            return harden_response(client_error_response(429, "Too many requests. Try again soon."))

        route_limit = _positive_int_env("BRASSTUNE_RATE_LIMIT_PER_MINUTE", 900)
        if not _consume_rate_limit(
            _RATE_LIMIT_BUCKETS,
            (client_host, canonical_path),
            route_limit,
            max_buckets,
            now,
        ):
            return harden_response(client_error_response(429, "Too many requests. Try again soon."))

        expensive = _expensive_operation_family(request, canonical_path)
        if expensive is not None:
            family, operation_limit = expensive
            if not _consume_rate_limit(
                _EXPENSIVE_RATE_LIMIT_BUCKETS,
                (client_host, family),
                operation_limit,
                max_buckets,
                now,
            ):
                return harden_response(client_error_response(429, "Too many requests for this operation. Try again soon."))

    try:
        response = await call_next(request)
    except Exception as exc:
        # Do not interpolate exception messages: SQL/HTTP exceptions can embed
        # credentials, identifiers, or request data. The request id preserves
        # operational correlation without disclosing sensitive values.
        logger.error(
            "Unhandled backend request failure request_id=%s method=%s path=%s error_type=%s",
            request_id,
            request.method.upper(),
            _safe_log_route(request),
            type(exc).__name__,
        )
        response = client_error_response(500, "The server could not complete this request.")
    return harden_response(response)


app.include_router(api_router)
app.include_router(websocket_router)
