from contextlib import asynccontextmanager
from collections import defaultdict, deque
import os
import time

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.auth import assert_auth_configured
from app.api.routes import router as api_router
from app.api.websocket import router as websocket_router
from app.core.security import LOCAL_ENVIRONMENTS, allowed_origins, app_environment
from app.db.database import SessionLocal, init_db
from app.db.seed import seed_demo_data


_RATE_LIMIT_BUCKETS = defaultdict(deque)


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
        return max(0, int(os.getenv(name, str(default))))
    except ValueError:
        return default


class JSONBodyLimitMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope.get("type") != "http":
            await self.app(scope, receive, send)
            return

        headers = {key.decode("latin1").lower(): value.decode("latin1") for key, value in scope.get("headers", [])}
        content_type = headers.get("content-type", "")
        max_json_bytes = _positive_int_env("BRASSTUNE_MAX_JSON_BODY_BYTES", 1_000_000)
        if not max_json_bytes or "application/json" not in content_type.lower():
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
                response = JSONResponse({"detail": "Request body is too large."}, status_code=413)
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


app.add_middleware(JSONBodyLimitMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins(),
    allow_origin_regex=os.getenv("CORS_ALLOWED_ORIGIN_REGEX"),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def request_abuse_limits(request: Request, call_next):
    def harden_response(response):
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
        response.headers.setdefault("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=(), usb=(), serial=(), browsing-topics=()")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'; base-uri 'none'")
        if request.url.scheme == "https" or app_environment() in {"production", "staging", "preview"}:
            response.headers.setdefault("Strict-Transport-Security", "max-age=63072000; includeSubDomains; preload")
        return response

    if request.method.upper() == "OPTIONS":
        return harden_response(await call_next(request))

    content_type = request.headers.get("content-type", "")
    max_json_bytes = _positive_int_env("BRASSTUNE_MAX_JSON_BODY_BYTES", 1_000_000)
    content_length = request.headers.get("content-length")
    if max_json_bytes and "application/json" in content_type.lower() and content_length:
        try:
            if int(content_length) > max_json_bytes:
                return harden_response(JSONResponse({"detail": "Request body is too large."}, status_code=413))
        except ValueError:
            return harden_response(JSONResponse({"detail": "Invalid request size."}, status_code=400))

    rate_limit = _positive_int_env("BRASSTUNE_RATE_LIMIT_PER_MINUTE", 900)
    if rate_limit and request.url.path != "/api/health":
        client_host = request.client.host if request.client else "unknown"
        key = (client_host, request.url.path)
        now = time.monotonic()
        bucket = _RATE_LIMIT_BUCKETS[key]
        while bucket and now - bucket[0] > 60:
            bucket.popleft()
        if len(bucket) >= rate_limit:
            return harden_response(JSONResponse({"detail": "Too many requests. Try again soon."}, status_code=429))
        bucket.append(now)

    response = await call_next(request)
    return harden_response(response)


app.include_router(api_router)
app.include_router(websocket_router)
