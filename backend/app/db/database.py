import os
from pathlib import Path

from sqlalchemy import create_engine, text
from sqlalchemy.orm import declarative_base, sessionmaker

BASE_DIR = Path(__file__).resolve().parents[2]
DATA_DIR = BASE_DIR / "data"
DATA_DIR.mkdir(exist_ok=True)

DATABASE_URL = os.getenv("DATABASE_URL") or os.getenv("BRASSTUNE_DATABASE_URL") or "sqlite:///%s" % (DATA_DIR / "brasstune.db")
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
engine = create_engine(DATABASE_URL, connect_args=connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    from app.models.db import Base as ModelsBase

    ModelsBase.metadata.create_all(bind=engine)
    ensure_additive_columns()


def _sqlite_columns(table_name: str):
    with engine.connect() as connection:
        rows = connection.execute(text("PRAGMA table_info(%s)" % table_name)).fetchall()
    return {row[1] for row in rows}


def _add_sqlite_column(table_name: str, column_name: str, definition: str) -> None:
    if column_name in _sqlite_columns(table_name):
        return
    with engine.begin() as connection:
        connection.execute(text("ALTER TABLE %s ADD COLUMN %s %s" % (table_name, column_name, definition)))


def ensure_additive_columns() -> None:
    if not DATABASE_URL.startswith("sqlite"):
        return
    additions = {
        "users": {
            "supabase_user_id": "VARCHAR",
            "username": "VARCHAR",
            "display_name": "VARCHAR",
            "email": "VARCHAR",
            "onboarding_completed_at": "DATETIME",
            "updated_at": "DATETIME",
        },
        "practice_sessions": {
            "audio_storage_provider": "VARCHAR",
            "audio_object_key": "VARCHAR",
            "audio_mime_type": "VARCHAR",
            "audio_duration_seconds": "FLOAT",
            "audio_size_bytes": "INTEGER",
            "audio_uploaded_at": "DATETIME",
        },
        "groups": {
            "updated_at": "DATETIME",
        },
        "group_members": {
            "role_in_group": "VARCHAR DEFAULT 'student'",
            "status": "VARCHAR DEFAULT 'active'",
        },
    }
    for table_name, columns in additions.items():
        existing = _sqlite_columns(table_name)
        if not existing:
            continue
        for column_name, definition in columns.items():
            if column_name not in existing:
                _add_sqlite_column(table_name, column_name, definition)
