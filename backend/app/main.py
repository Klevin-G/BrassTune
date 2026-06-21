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


app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins(),
    allow_origin_regex=os.getenv("CORS_ALLOWED_ORIGIN_REGEX"),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _positive_int_env(name: str, default: int) -> int:
    try:
        return max(0, int(os.getenv(name, str(default))))
    except ValueError:
        return default


@app.middleware("http")
async def request_abuse_limits(request: Request, call_next):
    if request.method.upper() == "OPTIONS":
        return await call_next(request)

    content_type = request.headers.get("content-type", "")
    content_length = request.headers.get("content-length")
    max_json_bytes = _positive_int_env("BRASSTUNE_MAX_JSON_BODY_BYTES", 1_000_000)
    if max_json_bytes and "application/json" in content_type.lower() and content_length:
        try:
            if int(content_length) > max_json_bytes:
                return JSONResponse({"detail": "Request body is too large."}, status_code=413)
        except ValueError:
            return JSONResponse({"detail": "Invalid request size."}, status_code=400)

    rate_limit = _positive_int_env("BRASSTUNE_RATE_LIMIT_PER_MINUTE", 900)
    if rate_limit and request.url.path != "/api/health":
        client_host = request.client.host if request.client else "unknown"
        key = (client_host, request.url.path)
        now = time.monotonic()
        bucket = _RATE_LIMIT_BUCKETS[key]
        while bucket and now - bucket[0] > 60:
            bucket.popleft()
        if len(bucket) >= rate_limit:
            return JSONResponse({"detail": "Too many requests. Try again soon."}, status_code=429)
        bucket.append(now)

    return await call_next(request)


app.include_router(api_router)
app.include_router(websocket_router)
