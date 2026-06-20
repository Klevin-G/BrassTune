from contextlib import asynccontextmanager
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.auth import assert_auth_configured
from app.api.routes import router as api_router
from app.api.websocket import router as websocket_router
from app.core.security import LOCAL_ENVIRONMENTS, allowed_origins, app_environment
from app.db.database import SessionLocal, init_db
from app.db.seed import seed_demo_data


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


app.include_router(api_router)
app.include_router(websocket_router)
