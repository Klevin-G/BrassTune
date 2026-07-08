import os
from typing import Iterable

from sqlalchemy import inspect, text
from sqlalchemy.exc import SQLAlchemyError

from app.api.auth import assert_auth_configured
from app.core.security import DEPLOYED_ENVIRONMENTS, app_environment
from app.db.database import DATABASE_URL, assert_database_configured, build_engine, configured_database_url, database_backend, engine
from app.services.audio_storage import storage_backend


REQUIRED_TABLE_COLUMNS = {
    "users": {"id", "supabase_user_id", "username", "email", "role", "primary_instrument_id"},
    "practice_sessions": {
        "id",
        "user_id",
        "audio_storage_provider",
        "audio_object_key",
        "audio_mime_type",
        "audio_duration_seconds",
        "audio_size_bytes",
        "audio_uploaded_at",
    },
    "group_members": {"id", "group_id", "user_id", "active_since", "removed_at", "status"},
    "invitations": {"id", "group_id", "invited_user_id", "invited_by_user_id", "status"},
    "account_deletion_jobs": {
        "id",
        "user_id",
        "supabase_user_id",
        "idempotency_key",
        "stage",
        "status",
        "retry_count",
        "next_retry_at",
        "safe_error_category",
        "counts_json",
        "completed_at",
    },
}

REQUIRED_INDEX_COLUMN_SETS = {
    "invitations": {("invited_user_id",), ("invited_by_user_id",)},
}

REQUIRED_POSTGRES_COLUMN_TYPES = {
    "account_deletion_jobs": {
        "counts_json": "jsonb",
    },
}


def _configured_engine():
    url = configured_database_url()
    if url == DATABASE_URL:
        return engine, False, url
    return build_engine(url), True, url


def _missing_columns(actual_columns: Iterable[str], required_columns: Iterable[str]) -> list[str]:
    actual = set(actual_columns)
    return sorted(column for column in required_columns if column not in actual)


def _column_type_name(column: dict) -> str:
    return str(column.get("type", "")).lower()


def _postgres_column_type_issues(table_name: str, columns: list[dict]) -> list[str]:
    columns_by_name = {column["name"]: column for column in columns}
    issues = []
    for column_name, expected_type in REQUIRED_POSTGRES_COLUMN_TYPES.get(table_name, {}).items():
        actual_type = _column_type_name(columns_by_name.get(column_name, {}))
        if actual_type != expected_type:
            issues.append(
                "Column %s.%s must be %s, not %s."
                % (table_name, column_name, expected_type, actual_type or "unknown")
            )
    return issues


def database_readiness_issues() -> list[str]:
    issues: list[str] = []
    try:
        assert_database_configured()
    except RuntimeError as exc:
        issues.append(str(exc))
        if app_environment() in DEPLOYED_ENVIRONMENTS:
            return issues

    built_engine = None
    dispose_engine = False
    url = DATABASE_URL
    try:
        built_engine, dispose_engine, url = _configured_engine()
        with built_engine.connect() as connection:
            connection.execute(text("select 1"))
            inspector = inspect(connection)
            table_names = set(inspector.get_table_names())
            for table_name, required_columns in REQUIRED_TABLE_COLUMNS.items():
                if table_name not in table_names:
                    issues.append("Missing table: %s." % table_name)
                    continue
                columns = inspector.get_columns(table_name)
                missing = _missing_columns([column["name"] for column in columns], required_columns)
                if missing:
                    issues.append("Missing columns on %s: %s." % (table_name, ", ".join(missing)))
                if database_backend(url) == "postgresql":
                    issues.extend(_postgres_column_type_issues(table_name, columns))
                required_index_columns = REQUIRED_INDEX_COLUMN_SETS.get(table_name, set()) if database_backend(url) == "postgresql" else set()
                if required_index_columns:
                    indexed_columns = {tuple(index.get("column_names") or []) for index in inspector.get_indexes(table_name)}
                    for columns in sorted(required_index_columns):
                        if columns not in indexed_columns:
                            issues.append("Missing index on %s(%s)." % (table_name, ", ".join(columns)))
    except (SQLAlchemyError, OSError, RuntimeError) as exc:
        issues.append("Database readiness check failed: %s" % exc)
    finally:
        if dispose_engine and built_engine is not None:
            built_engine.dispose()

    if app_environment() in DEPLOYED_ENVIRONMENTS and database_backend(url) != "postgresql":
        issues.append("Deployed readiness requires PostgreSQL, not %s." % database_backend(url))
    return issues


def auth_readiness_issues() -> list[str]:
    try:
        assert_auth_configured()
    except RuntimeError as exc:
        return [str(exc)]
    return []


def storage_readiness_issues() -> list[str]:
    if app_environment() not in DEPLOYED_ENVIRONMENTS:
        return []
    backend = storage_backend()
    if backend != "supabase":
        return ["Deployed SESSION_AUDIO_STORAGE_BACKEND must be supabase."]
    missing = [name for name in ("SUPABASE_URL", "SUPABASE_SECRET_KEY", "SUPABASE_STORAGE_BUCKET") if not os.getenv(name)]
    if missing:
        return ["Missing Supabase storage configuration: %s." % ", ".join(missing)]
    return []


def maintenance_readiness_issues() -> list[str]:
    if app_environment() not in DEPLOYED_ENVIRONMENTS:
        return []
    if not os.getenv("BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET"):
        return ["Missing BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET for account deletion retry executor."]
    return []


def readiness_report() -> dict:
    database_issues = database_readiness_issues()
    auth_issues = auth_readiness_issues()
    storage_issues = storage_readiness_issues()
    maintenance_issues = maintenance_readiness_issues()
    issues = database_issues + auth_issues + storage_issues + maintenance_issues
    return {
        "ok": not issues,
        "service": "BrassTune Analytics API",
        "environment": app_environment(),
        "database_backend": database_backend(configured_database_url()),
        "checks": {
            "database": {"ok": not database_issues, "issues": database_issues},
            "auth": {"ok": not auth_issues, "issues": auth_issues},
            "storage": {"ok": not storage_issues, "issues": storage_issues},
            "maintenance": {"ok": not maintenance_issues, "issues": maintenance_issues},
        },
    }


def public_readiness_report(report: dict | None = None) -> dict:
    detailed = report or readiness_report()
    return {
        "ok": detailed["ok"],
        "service": detailed["service"],
        "environment": detailed["environment"],
        "database_backend": detailed["database_backend"],
        "checks": {name: {"ok": check.get("ok") is True} for name, check in detailed.get("checks", {}).items()},
    }


def version_payload() -> dict:
    commit_sha = (
        os.getenv("BRASSTUNE_RELEASE_SHA")
        or os.getenv("RENDER_GIT_COMMIT")
        or os.getenv("VERCEL_GIT_COMMIT_SHA")
        or os.getenv("GITHUB_SHA")
        or "unknown"
    )
    return {
        "service": "BrassTune Analytics API",
        "version": os.getenv("BRASSTUNE_APP_VERSION", "0.1.0"),
        "commit_sha": commit_sha,
        "environment": app_environment(),
    }
