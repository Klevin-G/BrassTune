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


def _sqlite_column_rows(table_name: str):
    with engine.connect() as connection:
        return connection.execute(text("PRAGMA table_info(%s)" % table_name)).fetchall()


def _add_sqlite_column(table_name: str, column_name: str, definition: str) -> None:
    if column_name in _sqlite_columns(table_name):
        return
    with engine.begin() as connection:
        connection.execute(text("ALTER TABLE %s ADD COLUMN %s %s" % (table_name, column_name, definition)))


def _ensure_sqlite_account_deletion_user_id_nullable() -> None:
    """Converge older local databases without discarding retry state.

    SQLite cannot drop a NOT NULL constraint in place. This table has no
    foreign keys, so an atomic table rebuild is the narrow compatibility path.
    """
    columns = {row[1]: row for row in _sqlite_column_rows("account_deletion_jobs")}
    if not columns or int(columns.get("user_id", (None, None, None, 0))[3] or 0) == 0:
        return
    with engine.begin() as connection:
        connection.execute(text("alter table account_deletion_jobs rename to account_deletion_jobs_pre_privacy"))
        for index_name in (
            "ix_account_deletion_jobs_id",
            "ix_account_deletion_jobs_user_id",
            "ix_account_deletion_jobs_supabase_user_id",
            "ix_account_deletion_jobs_idempotency_key",
        ):
            connection.execute(text("drop index if exists %s" % index_name))
        connection.execute(
            text(
                "create table account_deletion_jobs ("
                "id integer not null primary key, "
                "user_id integer, "
                "supabase_user_id varchar, "
                "idempotency_key varchar not null, "
                "stage varchar not null, "
                "status varchar not null, "
                "retry_count integer not null, "
                "next_retry_at datetime, "
                "safe_error_category varchar, "
                "counts_json json not null, "
                "completed_at datetime, "
                "created_at datetime not null, "
                "updated_at datetime not null)"
            )
        )
        connection.execute(
            text(
                "insert into account_deletion_jobs "
                "select id, user_id, supabase_user_id, idempotency_key, stage, status, retry_count, "
                "next_retry_at, safe_error_category, counts_json, completed_at, created_at, updated_at "
                "from account_deletion_jobs_pre_privacy"
            )
        )
        connection.execute(text("drop table account_deletion_jobs_pre_privacy"))
        connection.execute(text("create index ix_account_deletion_jobs_id on account_deletion_jobs (id)"))
        connection.execute(text("create index ix_account_deletion_jobs_user_id on account_deletion_jobs (user_id)"))
        connection.execute(text("create index ix_account_deletion_jobs_supabase_user_id on account_deletion_jobs (supabase_user_id)"))
        connection.execute(text("create unique index ix_account_deletion_jobs_idempotency_key on account_deletion_jobs (idempotency_key)"))


def _ensure_sqlite_deletion_tombstone_enforcement_phase() -> None:
    """Converge fresh and legacy local databases on the safe expand phase."""
    columns = _sqlite_columns("deleted_identity_tombstone_config")
    if not columns:
        return
    if "enforcement_phase" not in columns:
        _add_sqlite_column(
            "deleted_identity_tombstone_config",
            "enforcement_phase",
            "VARCHAR NOT NULL DEFAULT 'expand'",
        )
    with engine.begin() as connection:
        connection.execute(
            text(
                "update deleted_identity_tombstone_config "
                "set enforcement_phase = 'expand' "
                "where enforcement_phase is null "
                "or enforcement_phase not in ('expand', 'contract')"
            )
        )


def ensure_additive_columns() -> None:
    # Tests and maintenance callers may supply a scoped engine. Inspect the
    # engine that will actually be mutated instead of the import-time URL.
    if database_backend(str(engine.url)) != "sqlite":
        return
    additions = {
        "users": {
            "supabase_user_id": "VARCHAR",
            "username": "VARCHAR",
            "display_name": "VARCHAR",
            "email": "VARCHAR",
            "admin_granted_by_env": "BOOLEAN DEFAULT 0",
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
            "join_code": "VARCHAR",
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
    _ensure_sqlite_account_deletion_user_id_nullable()
    _ensure_sqlite_deletion_tombstone_enforcement_phase()
