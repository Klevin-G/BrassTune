import os
from pathlib import Path

from sqlalchemy import create_engine, event, text
from sqlalchemy.orm import declarative_base, sessionmaker

from app.core.security import DEPLOYED_ENVIRONMENTS, app_environment

BASE_DIR = Path(__file__).resolve().parents[2]
DATA_DIR = BASE_DIR / "data"
DATA_DIR.mkdir(exist_ok=True)

DEFAULT_SQLITE_DATABASE_URL = "sqlite:///%s" % (DATA_DIR / "brasstune.db")


def normalize_database_url(value: str) -> str:
    if value.startswith("postgres://"):
        value = value.replace("postgres://", "postgresql://", 1)
    if value.startswith("postgresql://"):
        value = value.replace("postgresql://", "postgresql+psycopg://", 1)
    return value


def configured_database_url() -> str:
    return normalize_database_url(os.getenv("BRASSTUNE_DATABASE_URL") or os.getenv("DATABASE_URL") or DEFAULT_SQLITE_DATABASE_URL)


DATABASE_URL = configured_database_url()


def database_backend(url: str = DATABASE_URL) -> str:
    if url.startswith("sqlite"):
        return "sqlite"
    if url.startswith("postgresql"):
        return "postgresql"
    return "unknown"


def _engine_kwargs(url: str) -> dict:
    if database_backend(url) == "sqlite":
        return {"connect_args": {"check_same_thread": False, "timeout": 30}}
    return {"pool_pre_ping": True}


def build_engine(url: str = DATABASE_URL):
    return create_engine(url, **_engine_kwargs(url))


def assert_database_configured() -> None:
    if app_environment() not in DEPLOYED_ENVIRONMENTS:
        return
    configured_url = os.getenv("BRASSTUNE_DATABASE_URL") or os.getenv("DATABASE_URL")
    if not configured_url:
        raise RuntimeError("BRASSTUNE_DATABASE_URL or DATABASE_URL is required when APP_ENV is deployed.")
    if database_backend(normalize_database_url(configured_url)) != "postgresql":
        raise RuntimeError("Deployed environments must use PostgreSQL for BRASSTUNE_DATABASE_URL or DATABASE_URL.")


engine = build_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


if database_backend(DATABASE_URL) == "sqlite":
    @event.listens_for(engine, "connect")
    def _configure_sqlite(dbapi_connection, _connection_record) -> None:
        cursor = dbapi_connection.cursor()
        try:
            cursor.execute("PRAGMA busy_timeout=30000")
            if DATABASE_URL != "sqlite:///:memory:":
                cursor.execute("PRAGMA journal_mode=WAL")
                cursor.execute("PRAGMA synchronous=NORMAL")
        finally:
            cursor.close()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    assert_database_configured()
    if app_environment() in DEPLOYED_ENVIRONMENTS:
        return

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
    if database_backend(DATABASE_URL) != "sqlite":
        return
    additions = {
        "users": {
            "supabase_user_id": "VARCHAR",
            "username": "VARCHAR",
            "display_name": "VARCHAR",
            "email": "VARCHAR",
            "onboarding_completed_at": "DATETIME",
            "last_active_at": "DATETIME",
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
            "active_since": "DATETIME",
            "removed_at": "DATETIME",
        },
    }
    for table_name, columns in additions.items():
        existing = _sqlite_columns(table_name)
        if not existing:
            continue
        for column_name, definition in columns.items():
            if column_name not in existing:
                _add_sqlite_column(table_name, column_name, definition)
