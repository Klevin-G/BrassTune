from concurrent.futures import ThreadPoolExecutor
import datetime as dt
from pathlib import Path
import threading

import app.db.readiness as readiness_module


def _job(**overrides):
    return {
        "jobid": 17,
        "jobname": readiness_module.ACCOUNT_DELETION_CRON_JOB_NAME,
        "schedule": readiness_module.ACCOUNT_DELETION_CRON_SCHEDULE,
        "command": readiness_module.ACCOUNT_DELETION_CRON_COMMAND,
        "active": True,
        "targets_current_database": True,
        **overrides,
    }


def _run(now: dt.datetime, **overrides):
    return {
        "status": "succeeded",
        "start_time": now - dt.timedelta(minutes=1),
        "end_time": now - dt.timedelta(seconds=50),
        **overrides,
    }


def test_scheduler_readiness_requires_exact_active_contract():
    now = dt.datetime(2026, 7, 24, 12, tzinfo=dt.timezone.utc)
    started = now - dt.timedelta(minutes=1)

    missing = readiness_module._account_deletion_scheduler_metadata_issues(
        [],
        [],
        now=now,
        process_started_at=started,
        function_exists=False,
    )
    assert "scheduler function is missing" in " ".join(missing).lower()
    assert "exactly one" in " ".join(missing).lower()

    invalid = readiness_module._account_deletion_scheduler_metadata_issues(
        [
            _job(
                active=False,
                schedule="0 * * * *",
                command="select public.unreviewed_function();",
            )
        ],
        [_run(now)],
        now=now,
        process_started_at=started,
    )
    assert "must be active" in " ".join(invalid).lower()
    assert "cadence" in " ".join(invalid).lower()
    assert "command" in " ".join(invalid).lower()


def test_scheduler_readiness_allows_only_bounded_first_run_startup_grace():
    now = dt.datetime(2026, 7, 24, 12, tzinfo=dt.timezone.utc)

    assert readiness_module._account_deletion_scheduler_metadata_issues(
        [_job()],
        [],
        now=now,
        process_started_at=now - dt.timedelta(minutes=19),
    ) == []
    overdue = readiness_module._account_deletion_scheduler_metadata_issues(
        [_job()],
        [],
        now=now,
        process_started_at=now - dt.timedelta(minutes=21),
    )
    assert "first observed run" in " ".join(overdue).lower()


def test_scheduler_readiness_rejects_failed_stuck_and_overdue_runs():
    now = dt.datetime(2026, 7, 24, 12, tzinfo=dt.timezone.utc)
    started = now - dt.timedelta(hours=1)

    failed = readiness_module._account_deletion_scheduler_metadata_issues(
        [_job()],
        [_run(now, status="failed")],
        now=now,
        process_started_at=started,
    )
    assert "latest" in " ".join(failed).lower()
    assert "failed" in " ".join(failed).lower()

    stuck = readiness_module._account_deletion_scheduler_metadata_issues(
        [_job()],
        [
            _run(
                now,
                status="running",
                start_time=now - dt.timedelta(minutes=6),
                end_time=None,
            ),
            _run(
                now,
                start_time=now - dt.timedelta(minutes=10),
                end_time=now - dt.timedelta(minutes=9),
            ),
        ],
        now=now,
        process_started_at=started,
    )
    assert "stuck" in " ".join(stuck).lower()

    overdue = readiness_module._account_deletion_scheduler_metadata_issues(
        [_job()],
        [
            _run(
                now,
                start_time=now - dt.timedelta(minutes=40),
                end_time=now - dt.timedelta(minutes=39),
            )
        ],
        now=now,
        process_started_at=started,
    )
    assert "overdue" in " ".join(overdue).lower()

    assert readiness_module._account_deletion_scheduler_metadata_issues(
        [_job()],
        [_run(now)],
        now=now,
        process_started_at=started,
    ) == []


def test_backend_heartbeat_readiness_accepts_fresh_and_rejects_stale_or_invalid():
    now = dt.datetime(2026, 7, 24, 12, tzinfo=dt.timezone.utc)
    started = now - dt.timedelta(hours=1)

    fresh = readiness_module._account_deletion_heartbeat_issues(
        [
            {
                "purpose": readiness_module.ACCOUNT_DELETION_HEARTBEAT_PURPOSE,
                "last_succeeded_at": now - dt.timedelta(minutes=1),
            }
        ],
        now=now,
        process_started_at=started,
    )
    stale = readiness_module._account_deletion_heartbeat_issues(
        [
            {
                "purpose": readiness_module.ACCOUNT_DELETION_HEARTBEAT_PURPOSE,
                "last_succeeded_at": now - dt.timedelta(minutes=36),
            }
        ],
        now=now,
        process_started_at=started,
    )
    invalid = readiness_module._account_deletion_heartbeat_issues(
        [
            {
                "purpose": readiness_module.ACCOUNT_DELETION_HEARTBEAT_PURPOSE,
                "last_succeeded_at": None,
            }
        ],
        now=now,
        process_started_at=started,
    )

    assert fresh == []
    assert "overdue" in " ".join(stale).lower()
    assert "invalid" in " ".join(invalid).lower()


def test_backend_heartbeat_missing_is_allowed_only_during_startup_grace():
    now = dt.datetime(2026, 7, 24, 12, tzinfo=dt.timezone.utc)

    assert readiness_module._account_deletion_heartbeat_issues(
        [],
        now=now,
        process_started_at=now - dt.timedelta(minutes=19),
    ) == []
    overdue = readiness_module._account_deletion_heartbeat_issues(
        [],
        now=now,
        process_started_at=now - dt.timedelta(minutes=21),
    )
    assert "no successful backend heartbeat" in " ".join(overdue).lower()


def test_deployed_auth_readiness_probes_public_settings_without_service_key(
    monkeypatch,
):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "supabase")
    monkeypatch.setenv("SUPABASE_URL", "https://project-ref.supabase.co")
    monkeypatch.setenv("SUPABASE_PUBLISHABLE_KEY", "publishable-test-key")
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "service-test-key-never-sent")
    observed = {}

    class Response:
        status = 200

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

    def fake_urlopen(request, timeout):
        observed["url"] = request.full_url
        observed["apikey"] = request.headers.get("Apikey")
        observed["authorization"] = request.headers.get("Authorization")
        observed["timeout"] = timeout
        return Response()

    readiness_module._reset_supabase_auth_probe_cache_for_tests()
    monkeypatch.setattr(readiness_module.urllib.request, "urlopen", fake_urlopen)

    assert readiness_module.auth_readiness_issues() == []
    assert observed == {
        "url": "https://project-ref.supabase.co/auth/v1/settings",
        "apikey": "publishable-test-key",
        "authorization": None,
        "timeout": readiness_module.SUPABASE_AUTH_PROBE_TIMEOUT_SECONDS,
    }


def test_deployed_auth_readiness_fails_closed_on_dns_or_settings_failure(
    monkeypatch,
):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "supabase")
    monkeypatch.setenv("SUPABASE_URL", "https://inactive-project.supabase.co")
    monkeypatch.setenv("SUPABASE_PUBLISHABLE_KEY", "publishable-test-key")
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "service-test-key")
    readiness_module._reset_supabase_auth_probe_cache_for_tests()
    monkeypatch.setattr(
        readiness_module.urllib.request,
        "urlopen",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            OSError("provider hostname and credential-like details")
        ),
    )

    issues = readiness_module.auth_readiness_issues()

    assert issues == ["Supabase Auth settings endpoint is unreachable."]
    assert "credential-like" not in " ".join(issues)


def test_supabase_auth_probe_is_single_flight_on_concurrent_cold_cache(
    monkeypatch,
):
    monkeypatch.setenv("SUPABASE_URL", "https://project-ref.supabase.co")
    monkeypatch.setenv("SUPABASE_PUBLISHABLE_KEY", "publishable-test-key")
    readiness_module._reset_supabase_auth_probe_cache_for_tests()
    all_callers_entered = threading.Event()
    state_lock = threading.Lock()
    call_count = 0
    caller_count = 0

    class Response:
        status = 200

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

    def fake_supabase_endpoint(path):
        nonlocal caller_count
        if path == "/":
            with state_lock:
                caller_count += 1
                if caller_count == 8:
                    all_callers_entered.set()
        return "https://project-ref.supabase.co" + (
            "" if path == "/" else path
        )

    def fake_urlopen(_request, timeout):
        nonlocal call_count
        assert timeout == readiness_module.SUPABASE_AUTH_PROBE_TIMEOUT_SECONDS
        with state_lock:
            call_count += 1
        # The leader cannot complete until every submitted caller reached the
        # cold-cache boundary. Without single-flight, all eight probes escape.
        assert all_callers_entered.wait(timeout=5)
        return Response()

    monkeypatch.setattr(
        readiness_module,
        "_supabase_endpoint",
        fake_supabase_endpoint,
    )
    monkeypatch.setattr(readiness_module.urllib.request, "urlopen", fake_urlopen)
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = [
            pool.submit(readiness_module._supabase_auth_reachability_issue)
            for _ in range(8)
        ]
        results = [future.result(timeout=5) for future in futures]

    assert results == [None] * 8
    assert caller_count == 8
    assert call_count == 1


def test_supabase_auth_probe_refreshes_stale_cached_result(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", "https://project-ref.supabase.co")
    monkeypatch.setenv("SUPABASE_PUBLISHABLE_KEY", "publishable-test-key")
    readiness_module._reset_supabase_auth_probe_cache_for_tests()
    clock = {"value": 10.0}
    attempts = []

    class Response:
        status = 200

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

    def fake_urlopen(*_args, **_kwargs):
        attempts.append(True)
        if len(attempts) == 1:
            raise OSError("first probe unavailable")
        return Response()

    monkeypatch.setattr(
        readiness_module.time,
        "monotonic",
        lambda: clock["value"],
    )
    monkeypatch.setattr(readiness_module.urllib.request, "urlopen", fake_urlopen)

    assert (
        readiness_module._supabase_auth_reachability_issue()
        == "Supabase Auth settings endpoint is unreachable."
    )
    clock["value"] += readiness_module.SUPABASE_AUTH_PROBE_CACHE_SECONDS - 1
    assert (
        readiness_module._supabase_auth_reachability_issue()
        == "Supabase Auth settings endpoint is unreachable."
    )
    assert len(attempts) == 1

    clock["value"] += 2
    assert readiness_module._supabase_auth_reachability_issue() is None
    assert len(attempts) == 2


def test_local_auth_readiness_never_performs_provider_probe(monkeypatch):
    monkeypatch.setenv("APP_ENV", "local")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "disabled")
    monkeypatch.setattr(
        readiness_module,
        "_supabase_auth_reachability_issue",
        lambda: (_ for _ in ()).throw(AssertionError("local readiness must be offline")),
    )

    assert readiness_module.auth_readiness_issues() == []


def test_maintenance_heartbeat_migration_is_idempotent_and_private():
    migration = (
        Path(__file__).resolve().parents[3]
        / "supabase"
        / "migrations"
        / "20260724072904_account_deletion_maintenance_heartbeats.sql"
    ).read_text().lower()

    assert "create table if not exists public.maintenance_heartbeats" in migration
    assert "purpose text primary key" in migration
    assert "last_succeeded_at timestamptz not null" in migration
    assert "enable row level security" in migration
    assert "('anon', 'authenticated', 'service_role')" in migration
    assert "revoke all privileges on table public.maintenance_heartbeats" in migration
    assert "request, credential, user, or object identifiers" in migration
