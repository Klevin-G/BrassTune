import hmac
import os
import re
from typing import Iterable

from sqlalchemy import inspect, text
from sqlalchemy.exc import SQLAlchemyError

from app.api.auth import assert_auth_configured
from app.core.security import DEPLOYED_ENVIRONMENTS, app_environment
from app.db.database import DATABASE_URL, assert_database_configured, build_engine, configured_database_url, database_backend, engine
from app.services.account_deletion import (
    DeletionTombstoneSecretError,
    deletion_tombstone_key_verifier,
    deletion_tombstone_secret_issue,
)
from app.services.audio_storage import (
    ALLOWED_AUDIO_MIME_TYPES,
    MAX_AUDIO_UPLOAD_BYTES,
    _supabase_bucket,
    _supabase_bucket_name,
    _supabase_url,
    storage_backend,
)


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
    "deleted_identity_tombstones": {"id", "subject_digest", "created_at"},
    "deleted_identity_tombstone_config": {"id", "key_verifier", "enforcement_phase", "created_at"},
    "audio_storage_jobs": {
        "id",
        "user_id",
        "session_id",
        "idempotency_key",
        "action",
        "provider",
        "object_key",
        "size_bytes",
        "reason",
        "status",
        "retry_count",
        "next_retry_at",
        "safe_error_category",
        "details_json",
        "completed_at",
    },
}

REQUIRED_INDEX_COLUMN_SETS = {
    "invitations": {("invited_user_id",), ("invited_by_user_id",)},
    "account_deletion_jobs": {
        ("status", "next_retry_at", "updated_at", "id"),
        ("completed_at", "id"),
    },
    "audio_storage_jobs": {
        ("user_id", "action", "status"),
        ("status", "next_retry_at", "updated_at", "id"),
        ("completed_at", "id"),
    },
}

REQUIRED_POSTGRES_UNIQUE_COLUMN_SETS = {
    "group_members": {("group_id", "user_id")},
    "deleted_identity_tombstones": {("subject_digest",)},
}

REQUIRED_POSTGRES_COLUMN_TYPES = {
    "account_deletion_jobs": {
        "counts_json": "jsonb",
    },
    "audio_storage_jobs": {
        "details_json": "jsonb",
    },
}

REQUIRED_POSTGRES_COLUMN_NULLABILITY = {
    # Terminal rows are immediately stripped of account/session identifiers.
    "account_deletion_jobs": {"user_id": True},
    "audio_storage_jobs": {"user_id": True, "session_id": True},
}

BACKEND_APPLICATION_TABLES = {
    "users",
    "instrument_profiles",
    "practice_sessions",
    "pitch_samples",
    "note_events",
    "groups",
    "group_members",
    "invitations",
    "recommendations",
    "account_deletion_jobs",
    "usage_events",
    "audio_storage_jobs",
}
DATA_API_ROLES = {"anon", "authenticated"}

_REVISION_RE = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$", re.IGNORECASE)


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


def _postgres_column_nullability_issues(table_name: str, columns: list[dict]) -> list[str]:
    columns_by_name = {column["name"]: column for column in columns}
    issues = []
    for column_name, expected_nullable in REQUIRED_POSTGRES_COLUMN_NULLABILITY.get(table_name, {}).items():
        actual_nullable = columns_by_name.get(column_name, {}).get("nullable")
        if actual_nullable is not expected_nullable:
            expectation = "nullable" if expected_nullable else "not nullable"
            issues.append("Column %s.%s must be %s." % (table_name, column_name, expectation))
    return issues


def _postgres_application_security_issues(connection, table_names: set[str]) -> list[str]:
    issues = []
    missing_tables = sorted(BACKEND_APPLICATION_TABLES - table_names)
    for table_name in missing_tables:
        issues.append("Missing backend application table: %s." % table_name)

    present_tables = sorted(BACKEND_APPLICATION_TABLES & table_names)
    if not present_tables:
        return issues

    rls_rows = connection.execute(
        text(
            "select c.relname as table_name, c.relrowsecurity as rls_enabled "
            "from pg_class c join pg_namespace n on n.oid = c.relnamespace "
            "where n.nspname = 'public' and c.relkind in ('r', 'p') "
            "and c.relname = any(:table_names)"
        ),
        {"table_names": present_tables},
    ).mappings()
    rls_by_table = {row["table_name"]: row["rls_enabled"] for row in rls_rows}
    for table_name in present_tables:
        if rls_by_table.get(table_name) is not True:
            issues.append("Row level security must be enabled on public.%s." % table_name)

    policy_rows = connection.execute(
        text(
            "select tablename, count(*) as policy_count from pg_policies "
            "where schemaname = 'public' and tablename = any(:table_names) "
            "group by tablename"
        ),
        {"table_names": present_tables},
    ).mappings()
    for row in policy_rows:
        if int(row["policy_count"] or 0) > 0:
            issues.append(
                "Backend-only public.%s must not have Data API RLS policies."
                % row["tablename"]
            )

    grant_rows = connection.execute(
        text(
            "select r.rolname, c.relname as table_name, "
            "has_table_privilege(r.oid, c.oid, 'select') as can_select, "
            "has_table_privilege(r.oid, c.oid, 'insert') as can_insert, "
            "has_table_privilege(r.oid, c.oid, 'update') as can_update, "
            "has_table_privilege(r.oid, c.oid, 'delete') as can_delete, "
            "has_table_privilege(r.oid, c.oid, 'truncate') as can_truncate, "
            "has_table_privilege(r.oid, c.oid, 'references') as can_reference, "
            "has_table_privilege(r.oid, c.oid, 'trigger') as can_trigger "
            "from pg_roles r cross join pg_class c "
            "join pg_namespace n on n.oid = c.relnamespace "
            "where r.rolname = any(:role_names) and n.nspname = 'public' "
            "and c.relname = any(:table_names)"
        ),
        {"role_names": sorted(DATA_API_ROLES), "table_names": present_tables},
    ).mappings()
    found_roles = set()
    for row in grant_rows:
        found_roles.add(row["rolname"])
        if any(
            row[name]
            for name in (
                "can_select",
                "can_insert",
                "can_update",
                "can_delete",
                "can_truncate",
                "can_reference",
                "can_trigger",
            )
        ):
            issues.append(
                "Data API role %s must not access public.%s."
                % (row["rolname"], row["table_name"])
            )
    for role_name in sorted(DATA_API_ROLES - found_roles):
        issues.append("Could not verify application grants for Data API role %s." % role_name)

    sequence_rows = connection.execute(
        text(
            "select distinct r.rolname, s.relname as sequence_name, "
            "has_sequence_privilege(r.oid, s.oid, 'usage') as can_use, "
            "has_sequence_privilege(r.oid, s.oid, 'select') as can_select, "
            "has_sequence_privilege(r.oid, s.oid, 'update') as can_update "
            "from pg_roles r cross join pg_class s "
            "join pg_namespace n on n.oid = s.relnamespace "
            "join pg_depend d on d.objid = s.oid and d.deptype in ('a', 'i') "
            "join pg_class t on t.oid = d.refobjid "
            "where r.rolname = any(:role_names) and n.nspname = 'public' "
            "and s.relkind = 'S' and t.relname = any(:table_names)"
        ),
        {"role_names": sorted(DATA_API_ROLES), "table_names": present_tables},
    ).mappings()
    for row in sequence_rows:
        if row["can_use"] or row["can_select"] or row["can_update"]:
            issues.append(
                "Data API role %s must not access application sequence %s."
                % (row["rolname"], row["sequence_name"])
            )
    return issues


def _postgres_audio_job_security_issues(connection) -> list[str]:
    issues = []
    privacy_constraint_count = int(
        connection.execute(
            text(
                "select count(*) from pg_constraint "
                "where conrelid = to_regclass('public.audio_storage_jobs') "
                "and conname = 'audio_storage_jobs_terminal_privacy_check' "
                "and convalidated"
            )
        ).scalar()
        or 0
    )
    if privacy_constraint_count != 1:
        issues.append("Validated terminal privacy constraint is required on audio_storage_jobs.")

    rows = connection.execute(
        text(
            "select rolname, "
            "has_table_privilege(rolname, 'public.audio_storage_jobs', 'select') as can_select, "
            "has_table_privilege(rolname, 'public.audio_storage_jobs', 'insert') as can_insert, "
            "has_table_privilege(rolname, 'public.audio_storage_jobs', 'update') as can_update, "
            "has_table_privilege(rolname, 'public.audio_storage_jobs', 'delete') as can_delete, "
            "has_sequence_privilege(rolname, 'public.audio_storage_jobs_id_seq', 'usage') as can_use_sequence, "
            "has_sequence_privilege(rolname, 'public.audio_storage_jobs_id_seq', 'select') as can_select_sequence, "
            "has_sequence_privilege(rolname, 'public.audio_storage_jobs_id_seq', 'update') as can_update_sequence "
            "from pg_roles where rolname = 'service_role'"
        )
    ).mappings()
    for row in rows:
        if any(
            row[name]
            for name in (
                "can_select",
                "can_insert",
                "can_update",
                "can_delete",
                "can_use_sequence",
                "can_select_sequence",
                "can_update_sequence",
            )
        ):
            issues.append("Service role must not access backend-only audio_storage_jobs.")
    return issues


def _policy_roles(value) -> set[str]:
    if isinstance(value, (list, tuple, set)):
        return {str(item) for item in value}
    if not value:
        return set()
    return {
        item.strip().strip('"')
        for item in str(value).strip("{}").split(",")
        if item.strip()
    }


def _storage_policy_expression_may_reach_bucket(expression: str, bucket_name: str) -> bool:
    expression = expression.lower()
    if not expression or "bucket_id" not in expression:
        return True
    if re.search(r"\bor\b|<>|!=", expression):
        return True
    literals = [
        value.replace("''", "'")
        for value in re.findall(r"'((?:''|[^'])*)'", expression)
    ]
    if bucket_name.lower() in {value.lower() for value in literals}:
        return True
    # Prove exclusion only for the conventional equality restriction to one or
    # more explicitly different bucket literals. Complex expressions fail shut.
    return re.search(r"bucket_id\s*=\s*'((?:''|[^'])*)'(?:::[a-z_ ]+)?", expression) is None


def _storage_policy_may_reach_bucket(policy: dict, bucket_name: str) -> bool:
    if not (_policy_roles(policy.get("roles")) & {"public", "anon", "authenticated"}):
        return False
    expressions = [
        str(policy.get(name) or "")
        for name in ("qual", "with_check")
        if policy.get(name) is not None
    ]
    return not expressions or any(
        _storage_policy_expression_may_reach_bucket(expression, bucket_name)
        for expression in expressions
    )


def _postgres_storage_security_issues(connection, bucket_name: str) -> list[str]:
    issues = []
    columns = {
        row["column_name"]
        for row in connection.execute(
            text(
                "select column_name from information_schema.columns "
                "where table_schema = 'storage' and table_name = 'buckets'"
            )
        ).mappings()
    }
    required_columns = {"id", "public", "file_size_limit", "allowed_mime_types"}
    missing_columns = sorted(required_columns - columns)
    if missing_columns:
        issues.append("Supabase audio bucket settings could not be fully verified.")
    else:
        bucket = connection.execute(
            text(
                "select public, file_size_limit, allowed_mime_types "
                "from storage.buckets where id = :bucket_name"
            ),
            {"bucket_name": bucket_name},
        ).mappings().first()
        if bucket is None:
            issues.append("Configured private audio bucket is missing.")
        else:
            if bucket["public"] is not False:
                issues.append("Configured audio bucket must be private.")
            if int(bucket["file_size_limit"] or 0) != MAX_AUDIO_UPLOAD_BYTES:
                issues.append("Configured audio bucket must enforce the backend upload-size limit.")
            allowed_mime_types = set(bucket["allowed_mime_types"] or [])
            if allowed_mime_types != set(ALLOWED_AUDIO_MIME_TYPES):
                issues.append("Configured audio bucket MIME allowlist does not match the backend.")

    table_rows = connection.execute(
        text(
            "select c.relname as table_name, c.relrowsecurity as rls_enabled "
            "from pg_class c join pg_namespace n on n.oid = c.relnamespace "
            "where n.nspname = 'storage' and c.relname in ('buckets', 'objects')"
        )
    ).mappings()
    security_by_table = {row["table_name"]: row["rls_enabled"] for row in table_rows}
    for table_name in ("buckets", "objects"):
        if security_by_table.get(table_name) is not True:
            issues.append("Row level security must be enabled on storage.%s." % table_name)

    policy_rows = connection.execute(
        text(
            "select tablename, policyname, roles, qual, with_check "
            "from pg_policies where schemaname = 'storage' "
            "and tablename in ('buckets', 'objects')"
        )
    ).mappings()
    if any(_storage_policy_may_reach_bucket(dict(row), bucket_name) for row in policy_rows):
        issues.append("Browser-facing Storage policies may expose the configured audio bucket.")
    return issues


def _postgres_account_deletion_security_issues(connection) -> list[str]:
    issues = []
    for table_name in (
        "account_deletion_jobs",
        "deleted_identity_tombstones",
        "deleted_identity_tombstone_config",
    ):
        rls_enabled = connection.execute(
            text(
                "select c.relrowsecurity "
                "from pg_class c join pg_namespace n on n.oid = c.relnamespace "
                "where n.nspname = 'public' and c.relname = :table_name"
            ),
            {"table_name": table_name},
        ).scalar()
        if rls_enabled is not True:
            issues.append("Row level security must be enabled on %s." % table_name)

        policy_count = int(
            connection.execute(
                text(
                    "select count(*) from pg_policies "
                    "where schemaname = 'public' and tablename = :table_name"
                ),
                {"table_name": table_name},
            ).scalar()
            or 0
        )
        if policy_count:
            issues.append("Backend-only %s must not have Data API RLS policies." % table_name)

        rows = connection.execute(
            text(
                "select rolname, "
                "has_table_privilege(rolname, 'public.' || :table_name, 'select') as can_select, "
                "has_table_privilege(rolname, 'public.' || :table_name, 'insert') as can_insert, "
                "has_table_privilege(rolname, 'public.' || :table_name, 'update') as can_update, "
                "has_table_privilege(rolname, 'public.' || :table_name, 'delete') as can_delete "
                "from pg_roles where rolname in ('anon', 'authenticated', 'service_role')"
            ),
            {"table_name": table_name},
        ).mappings()
        for row in rows:
            if any(row[name] for name in ("can_select", "can_insert", "can_update", "can_delete")):
                issues.append("Data API role %s must not access %s." % (row["rolname"], table_name))

    constraint_states = list(
        connection.execute(
            text(
                "select convalidated from pg_constraint "
                "where conrelid = to_regclass('public.account_deletion_jobs') "
                "and conname = 'account_deletion_jobs_terminal_privacy_check'"
            )
        ).scalars()
    )
    enforcement_phase = connection.execute(
        text(
            "select enforcement_phase from public.deleted_identity_tombstone_config "
            "where id = 1"
        )
    ).scalar()
    issues.extend(_account_deletion_constraint_phase_issues(enforcement_phase, constraint_states))
    try:
        expected_verifier = deletion_tombstone_key_verifier()
        stored_verifier = connection.execute(
            text("select key_verifier from public.deleted_identity_tombstone_config where id = 1")
        ).scalar()
        if not stored_verifier or not hmac.compare_digest(stored_verifier, expected_verifier):
            issues.append("Deleted identity tombstone key does not match durable key state.")
    except DeletionTombstoneSecretError:
        issues.append("Deleted identity tombstone key state cannot be verified.")
    return issues


def _account_deletion_constraint_phase_issues(
    enforcement_phase: str | None,
    constraint_states: Iterable[bool],
) -> list[str]:
    states = list(constraint_states)
    if enforcement_phase == "expand":
        if states:
            return ["Expand-phase account deletion privacy must not install the terminal constraint."]
        return []
    if enforcement_phase == "contract":
        if states == [True]:
            return []
        return ["Contract-phase account deletion privacy requires one validated terminal constraint."]
    return ["Account deletion privacy rollout phase is missing or invalid."]


def _postgres_unique_key_issues(table_name: str, unique_constraints: list[dict], indexes: list[dict]) -> list[str]:
    """Require an unconditional unique key over the exact ordered columns.

    PostgreSQL/SQLAlchemy versions may expose a UNIQUE constraint through
    `get_unique_constraints`, `get_indexes`, or both, so either representation
    is accepted. Partial unique indexes are not equivalent to the invariant.
    """
    issues = []
    constraint_columns = {
        tuple(constraint.get("column_names") or [])
        for constraint in unique_constraints
    }
    unconditional_unique_index_columns = set()
    for index in indexes:
        dialect_options = index.get("dialect_options") or {}
        predicate = index.get("postgresql_where")
        if predicate is None:
            predicate = dialect_options.get("postgresql_where")
        if bool(index.get("unique")) and predicate is None:
            unconditional_unique_index_columns.add(tuple(index.get("column_names") or []))
    available = constraint_columns | unconditional_unique_index_columns
    for columns in sorted(REQUIRED_POSTGRES_UNIQUE_COLUMN_SETS.get(table_name, set())):
        if columns not in available:
            issues.append("Missing unique constraint or index on %s(%s)." % (table_name, ", ".join(columns)))
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
                    issues.extend(_postgres_column_nullability_issues(table_name, columns))
                required_index_columns = REQUIRED_INDEX_COLUMN_SETS.get(table_name, set()) if database_backend(url) == "postgresql" else set()
                required_unique_columns = REQUIRED_POSTGRES_UNIQUE_COLUMN_SETS.get(table_name, set()) if database_backend(url) == "postgresql" else set()
                indexes = None
                index_inspection_failed = False
                if required_index_columns or required_unique_columns:
                    try:
                        indexes = inspector.get_indexes(table_name)
                    except (NotImplementedError, SQLAlchemyError):
                        index_inspection_failed = True
                        if required_index_columns:
                            issues.append("Could not inspect indexes on %s." % table_name)
                if required_index_columns and indexes is not None:
                    indexed_columns = {tuple(index.get("column_names") or []) for index in indexes}
                    for columns in sorted(required_index_columns):
                        if columns not in indexed_columns:
                            issues.append("Missing index on %s(%s)." % (table_name, ", ".join(columns)))
                if required_unique_columns:
                    unique_constraints = None
                    unique_inspection_failed = False
                    try:
                        unique_constraints = inspector.get_unique_constraints(table_name)
                    except (NotImplementedError, SQLAlchemyError):
                        unique_inspection_failed = True
                    if indexes is not None or unique_constraints is not None:
                        unique_issues = _postgres_unique_key_issues(
                            table_name,
                            unique_constraints or [],
                            indexes or [],
                        )
                        if unique_issues and (index_inspection_failed or unique_inspection_failed):
                            issues.append("Could not verify unique constraint or index on %s." % table_name)
                        else:
                            issues.extend(unique_issues)
                    else:
                        issues.append("Could not verify unique constraint or index on %s." % table_name)
            if database_backend(url) == "postgresql":
                issues.extend(_postgres_application_security_issues(connection, table_names))
                if "audio_storage_jobs" in table_names:
                    issues.extend(_postgres_audio_job_security_issues(connection))
                if {
                    "account_deletion_jobs",
                    "deleted_identity_tombstones",
                    "deleted_identity_tombstone_config",
                }.issubset(table_names):
                    issues.extend(_postgres_account_deletion_security_issues(connection))
                if (
                    app_environment() in DEPLOYED_ENVIRONMENTS
                    and storage_backend() == "supabase"
                    and os.getenv("SUPABASE_STORAGE_BUCKET")
                ):
                    try:
                        bucket_name = _supabase_bucket_name()
                    except Exception:
                        issues.append("Configured audio bucket name is invalid.")
                    else:
                        issues.extend(
                            _postgres_storage_security_issues(
                                connection,
                                bucket_name,
                            )
                        )
    except (SQLAlchemyError, OSError, RuntimeError) as exc:
        # Driver messages can embed connection hosts, usernames, query text, or
        # provider details. Preserve the failure class without exposing it in
        # deploy logs or the detailed internal readiness report.
        issues.append("Database readiness check failed (%s)." % type(exc).__name__)
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
    try:
        _supabase_url("/")
        _supabase_bucket()
    except Exception:
        return ["Supabase storage URL or bucket configuration is invalid."]
    return []


def maintenance_readiness_issues() -> list[str]:
    if app_environment() not in DEPLOYED_ENVIRONMENTS:
        return []
    issues = []
    if not os.getenv("BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET"):
        issues.append("Missing BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET for maintenance retry executors.")
    tombstone_issue = deletion_tombstone_secret_issue()
    if tombstone_issue:
        issues.append(tombstone_issue)
    return issues


def revision_candidates() -> list[tuple[str, str]]:
    candidates = []
    for name in (
        "RENDER_GIT_COMMIT",
        "VERCEL_GIT_COMMIT_SHA",
        "GITHUB_SHA",
        "BRASSTUNE_RELEASE_SHA",
    ):
        value = (os.getenv(name) or "").strip()
        if value:
            candidates.append((name, value))
    return candidates


def release_readiness_issues() -> list[str]:
    if app_environment() not in DEPLOYED_ENVIRONMENTS:
        return []
    candidates = revision_candidates()
    if not candidates:
        return ["Missing exact release revision identity."]
    invalid = [name for name, value in candidates if not _REVISION_RE.fullmatch(value)]
    if invalid:
        return ["Release revision identity must be a full Git object id."]
    if len({value.lower() for _, value in candidates}) > 1:
        return ["Configured release revision identities do not match."]
    return []


def readiness_report() -> dict:
    database_issues = database_readiness_issues()
    auth_issues = auth_readiness_issues()
    storage_issues = storage_readiness_issues()
    maintenance_issues = maintenance_readiness_issues()
    release_issues = release_readiness_issues()
    issues = database_issues + auth_issues + storage_issues + maintenance_issues + release_issues
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
            "release": {"ok": not release_issues, "issues": release_issues},
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
    candidates = revision_candidates()
    revision_source, commit_sha = candidates[0] if candidates else ("unavailable", "unknown")
    return {
        "service": "BrassTune Analytics API",
        "version": os.getenv("BRASSTUNE_APP_VERSION", "0.1.0"),
        "commit_sha": commit_sha,
        "revision_source": revision_source,
        "environment": app_environment(),
    }
