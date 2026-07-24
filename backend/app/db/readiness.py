import base64
import binascii
import datetime as dt
import hmac
import os
import re
import threading
import time
import urllib.error
import urllib.request
from typing import Iterable

from sqlalchemy import inspect, text
from sqlalchemy.exc import SQLAlchemyError

from app.api.auth import _supabase_endpoint, assert_auth_configured
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
    "maintenance_request_nonces": {
        "id",
        "nonce_digest",
        "key_id",
        "purpose",
        "created_at",
        "expires_at",
    },
    "maintenance_heartbeats": {
        "purpose",
        "last_succeeded_at",
    },
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
    "maintenance_request_nonces": {
        ("expires_at",),
    },
}

REQUIRED_POSTGRES_UNIQUE_COLUMN_SETS = {
    "group_members": {("group_id", "user_id")},
    "deleted_identity_tombstones": {("subject_digest",)},
    "maintenance_request_nonces": {("nonce_digest",)},
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
    "maintenance_heartbeats",
    "maintenance_request_nonces",
}
DATA_API_ROLES = {"anon", "authenticated"}

_REVISION_RE = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$", re.IGNORECASE)
ACCOUNT_DELETION_CRON_JOB_NAME = "brasstune-account-deletion-retry"
ACCOUNT_DELETION_CRON_SCHEDULE = "*/15 * * * *"
ACCOUNT_DELETION_CRON_COMMAND = "select brasstune_private.enqueue_account_deletion_retry();"
ACCOUNT_DELETION_CRON_STARTUP_GRACE_SECONDS = 20 * 60
ACCOUNT_DELETION_CRON_MAX_SUCCESS_AGE_SECONDS = 35 * 60
ACCOUNT_DELETION_CRON_MAX_RUNNING_SECONDS = 5 * 60
ACCOUNT_DELETION_HEARTBEAT_PURPOSE = "account-deletions-retry-v1"
ACCOUNT_DELETION_HEARTBEAT_STARTUP_GRACE_SECONDS = 20 * 60
ACCOUNT_DELETION_HEARTBEAT_MAX_SUCCESS_AGE_SECONDS = 35 * 60
SUPABASE_AUTH_PROBE_TIMEOUT_SECONDS = 3
SUPABASE_AUTH_PROBE_CACHE_SECONDS = 30
_PROCESS_STARTED_AT = dt.datetime.now(dt.timezone.utc)
_SUPABASE_AUTH_PROBE_CONDITION = threading.Condition()
_SUPABASE_AUTH_PROBE_CACHE: dict[str, object] = {
    "origin": None,
    "checked_at": 0.0,
    "issue": None,
    "in_flight_origin": None,
}


def _configured_engine():
    url = configured_database_url()
    if url == DATABASE_URL:
        return engine, False, url
    return build_engine(url), True, url


def _utc_aware(value: dt.datetime) -> dt.datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=dt.timezone.utc)
    return value.astimezone(dt.timezone.utc)


def _normalized_sql(value: object) -> str:
    return " ".join(str(value or "").strip().lower().split())


def _account_deletion_scheduler_metadata_issues(
    jobs: list[dict],
    runs: list[dict],
    *,
    now: dt.datetime | None = None,
    process_started_at: dt.datetime | None = None,
    function_exists: bool = True,
) -> list[str]:
    """Validate only non-secret pg_cron metadata and bounded run history."""
    issues = []
    if not function_exists:
        issues.append("Account-deletion scheduler function is missing.")
    if len(jobs) != 1:
        issues.append("Exactly one account-deletion scheduler job is required.")
        return issues

    job = jobs[0]
    if job.get("active") is not True:
        issues.append("Account-deletion scheduler job must be active.")
    if str(job.get("schedule") or "") != ACCOUNT_DELETION_CRON_SCHEDULE:
        issues.append("Account-deletion scheduler cadence does not match the durable contract.")
    if _normalized_sql(job.get("command")) != _normalized_sql(ACCOUNT_DELETION_CRON_COMMAND):
        issues.append("Account-deletion scheduler command does not match the durable contract.")
    if job.get("targets_current_database") is not True:
        issues.append("Account-deletion scheduler targets the wrong database.")

    current = _utc_aware(now or dt.datetime.now(dt.timezone.utc))
    started = _utc_aware(process_started_at or _PROCESS_STARTED_AT)
    ordered_runs = sorted(
        runs,
        key=lambda row: _utc_aware(row.get("start_time") or dt.datetime.min),
        reverse=True,
    )
    if not ordered_runs:
        if (current - started).total_seconds() > ACCOUNT_DELETION_CRON_STARTUP_GRACE_SECONDS:
            issues.append("Account-deletion scheduler has not completed its first observed run.")
        return issues

    latest = ordered_runs[0]
    latest_status = str(latest.get("status") or "").strip().lower()
    latest_started = latest.get("start_time")
    if latest_status == "running":
        if (
            latest_started is None
            or (current - _utc_aware(latest_started)).total_seconds()
            > ACCOUNT_DELETION_CRON_MAX_RUNNING_SECONDS
        ):
            issues.append("Account-deletion scheduler run is stuck.")
    elif latest_status != "succeeded":
        issues.append("Latest account-deletion scheduler run failed.")

    successful_at = None
    for run in ordered_runs:
        if str(run.get("status") or "").strip().lower() != "succeeded":
            continue
        successful_at = run.get("end_time") or run.get("start_time")
        if successful_at is not None:
            break
    if successful_at is None:
        if (current - started).total_seconds() > ACCOUNT_DELETION_CRON_STARTUP_GRACE_SECONDS:
            issues.append("Account-deletion scheduler has no successful observed run.")
    elif (
        current - _utc_aware(successful_at)
    ).total_seconds() > ACCOUNT_DELETION_CRON_MAX_SUCCESS_AGE_SECONDS:
        issues.append("Account-deletion scheduler success is overdue.")
    return issues


def _account_deletion_heartbeat_issues(
    heartbeats: list[dict],
    *,
    now: dt.datetime | None = None,
    process_started_at: dt.datetime | None = None,
) -> list[str]:
    """Require durable proof that the backend finished recent maintenance."""
    current = _utc_aware(now or dt.datetime.now(dt.timezone.utc))
    started = _utc_aware(process_started_at or _PROCESS_STARTED_AT)
    matching = [
        row
        for row in heartbeats
        if row.get("purpose") == ACCOUNT_DELETION_HEARTBEAT_PURPOSE
    ]
    if not matching:
        if (
            current - started
        ).total_seconds() <= ACCOUNT_DELETION_HEARTBEAT_STARTUP_GRACE_SECONDS:
            return []
        return ["Account-deletion maintenance has no successful backend heartbeat."]
    if len(matching) != 1:
        return ["Exactly one account-deletion maintenance heartbeat is required."]

    succeeded_at = matching[0].get("last_succeeded_at")
    if not isinstance(succeeded_at, dt.datetime):
        return ["Account-deletion maintenance heartbeat timestamp is invalid."]
    age_seconds = (current - _utc_aware(succeeded_at)).total_seconds()
    if age_seconds < -60:
        return ["Account-deletion maintenance heartbeat timestamp is invalid."]
    if age_seconds > ACCOUNT_DELETION_HEARTBEAT_MAX_SUCCESS_AGE_SECONDS:
        return ["Account-deletion maintenance backend heartbeat is overdue."]
    return []


def _postgres_account_deletion_scheduler_issues(
    connection,
    *,
    heartbeat_table_exists: bool,
) -> list[str]:
    function_exists = connection.execute(
        text(
            "select to_regprocedure("
            "'brasstune_private.enqueue_account_deletion_retry()'"
            ") is not null"
        )
    ).scalar()
    jobs = [
        dict(row)
        for row in connection.execute(
            text(
                "select jobid, jobname, schedule, command, active, "
                "database = current_database() as targets_current_database "
                "from cron.job where jobname = :job_name"
            ),
            {"job_name": ACCOUNT_DELETION_CRON_JOB_NAME},
        ).mappings()
    ]
    runs = []
    if len(jobs) == 1 and jobs[0].get("jobid") is not None:
        runs = [
            dict(row)
            for row in connection.execute(
                text(
                    "select status, start_time, end_time "
                    "from cron.job_run_details where jobid = :job_id "
                    "order by start_time desc nulls last limit 8"
                ),
                {"job_id": jobs[0]["jobid"]},
            ).mappings()
        ]
    issues = _account_deletion_scheduler_metadata_issues(
        jobs,
        runs,
        function_exists=function_exists is True,
    )
    if not heartbeat_table_exists:
        issues.append("Account-deletion maintenance heartbeat table is missing.")
        return issues
    heartbeats = [
        dict(row)
        for row in connection.execute(
            text(
                "select purpose, last_succeeded_at "
                "from public.maintenance_heartbeats "
                "where purpose = :purpose"
            ),
            {"purpose": ACCOUNT_DELETION_HEARTBEAT_PURPOSE},
        ).mappings()
    ]
    issues.extend(_account_deletion_heartbeat_issues(heartbeats))
    return issues


def _reset_supabase_auth_probe_cache_for_tests() -> None:
    with _SUPABASE_AUTH_PROBE_CONDITION:
        _SUPABASE_AUTH_PROBE_CACHE.update(
            {
                "origin": None,
                "checked_at": 0.0,
                "issue": None,
                "in_flight_origin": None,
            }
        )
        _SUPABASE_AUTH_PROBE_CONDITION.notify_all()


def _supabase_auth_reachability_issue() -> str | None:
    """Probe the public Auth settings endpoint without sending service secrets."""
    origin = _supabase_endpoint("/")
    while True:
        monotonic_now = time.monotonic()
        with _SUPABASE_AUTH_PROBE_CONDITION:
            if (
                _SUPABASE_AUTH_PROBE_CACHE["origin"] == origin
                and monotonic_now
                - float(_SUPABASE_AUTH_PROBE_CACHE["checked_at"])
                <= SUPABASE_AUTH_PROBE_CACHE_SECONDS
            ):
                return _SUPABASE_AUTH_PROBE_CACHE["issue"]  # type: ignore[return-value]
            if _SUPABASE_AUTH_PROBE_CACHE["in_flight_origin"] is None:
                _SUPABASE_AUTH_PROBE_CACHE["in_flight_origin"] = origin
                break
            _SUPABASE_AUTH_PROBE_CONDITION.wait()

    issue: str | None = None
    try:
        publishable_key = os.getenv("SUPABASE_PUBLISHABLE_KEY") or ""
        request = urllib.request.Request(
            _supabase_endpoint("/auth/v1/settings"),
            headers={"apikey": publishable_key},
            method="GET",
        )
        with urllib.request.urlopen(  # nosec B310 - validated Supabase HTTPS origin
            request,
            timeout=SUPABASE_AUTH_PROBE_TIMEOUT_SECONDS,
        ) as response:
            raw_status = getattr(response, "status", None)
            if raw_status is None:
                raw_status = response.getcode()
            status = int(raw_status)
            if status < 200 or status >= 300:
                issue = "Supabase Auth settings endpoint is unavailable."
    except (urllib.error.HTTPError, urllib.error.URLError, OSError, TimeoutError):
        issue = "Supabase Auth settings endpoint is unreachable."
    except Exception:
        issue = "Supabase Auth settings endpoint could not be verified."
    finally:
        with _SUPABASE_AUTH_PROBE_CONDITION:
            _SUPABASE_AUTH_PROBE_CACHE.update(
                {
                    "origin": origin,
                    "checked_at": time.monotonic(),
                    "issue": issue,
                    "in_flight_origin": None,
                }
            )
            _SUPABASE_AUTH_PROBE_CONDITION.notify_all()
    return issue


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
        "maintenance_request_nonces",
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
                    if app_environment() in DEPLOYED_ENVIRONMENTS:
                        issues.extend(
                            _postgres_account_deletion_scheduler_issues(
                                connection,
                                heartbeat_table_exists=(
                                    "maintenance_heartbeats" in table_names
                                ),
                            )
                        )
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
    if app_environment() in DEPLOYED_ENVIRONMENTS:
        try:
            reachability_issue = _supabase_auth_reachability_issue()
        except Exception:
            # URL/config errors are already sanitized by assert_auth_configured;
            # unexpected probe failures must remain fail-closed and secret-free.
            reachability_issue = "Supabase Auth settings endpoint could not be verified."
        if reachability_issue:
            return [reachability_issue]
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
    key_id = (os.getenv("BRASSTUNE_MAINTENANCE_HMAC_KEY_ID") or "").strip()
    key_value = (os.getenv("BRASSTUNE_MAINTENANCE_HMAC_KEY") or "").strip()
    previous_key_id = (os.getenv("BRASSTUNE_MAINTENANCE_HMAC_PREVIOUS_KEY_ID") or "").strip()
    previous_key_value = (os.getenv("BRASSTUNE_MAINTENANCE_HMAC_PREVIOUS_KEY") or "").strip()
    key_id_pattern = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")

    if not key_id or not key_value:
        issues.append("Missing current HMAC key configuration for maintenance retry executors.")
    elif not key_id_pattern.fullmatch(key_id):
        issues.append("Current maintenance HMAC key id is invalid.")
    else:
        try:
            decoded_key = base64.b64decode(key_value, validate=True)
        except (binascii.Error, ValueError):
            decoded_key = b""
        if len(decoded_key) < 32:
            issues.append("Current maintenance HMAC key must be valid base64 encoding at least 32 bytes.")

    if bool(previous_key_id) != bool(previous_key_value):
        issues.append("Previous maintenance HMAC key id and key must be configured together.")
    elif previous_key_id:
        if not key_id_pattern.fullmatch(previous_key_id):
            issues.append("Previous maintenance HMAC key id is invalid.")
        elif previous_key_id == key_id:
            issues.append("Current and previous maintenance HMAC key ids must be distinct.")
        try:
            decoded_previous_key = base64.b64decode(previous_key_value, validate=True)
        except (binascii.Error, ValueError):
            decoded_previous_key = b""
        if len(decoded_previous_key) < 32:
            issues.append("Previous maintenance HMAC key must be valid base64 encoding at least 32 bytes.")

    if os.getenv("BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET"):
        issues.append("Legacy maintenance retry secret must be removed in deployed environments.")
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
