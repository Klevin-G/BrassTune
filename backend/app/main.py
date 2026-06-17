import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import router as api_router
from app.api.websocket import router as websocket_router
from app.db.database import SessionLocal, init_db
from app.db.seed import seed_demo_data

app = FastAPI(title="BrassTune Analytics API", version="0.1.0")


def cors_origins():
    configured = os.getenv("CORS_ALLOWED_ORIGINS") or os.getenv("FRONTEND_ORIGIN")
    origins = ["http://localhost:5173", "http://127.0.0.1:5173"]
    if configured:
        origins.extend([item.strip() for item in configured.split(",") if item.strip()])
    return sorted(set(origins))


app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def startup() -> None:
    init_db()
    db = SessionLocal()
    try:
        seed_demo_data(db)
    finally:
        db.close()


app.include_router(api_router)
app.include_router(websocket_router)
