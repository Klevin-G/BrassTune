import datetime as dt
import json
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import pytest
import app.db.database as database_module
from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from app.api.auth import AuthContext
from app.api.routes import (
    _generate_join_code,
    ensemble_group_my_progress,
    ensemble_group_report,
    ensemble_group_roster,
    ensemble_group_summary,
    get_ensemble_group,
    list_ensemble_groups,
    rotate_ensemble_join_code,
    start_practice_session,
    stop_practice_session,
    update_my_group_sharing_consent,
)
from app.db.database import Base
from app.db.readiness import REQUIRED_POSTGRES_UNIQUE_COLUMN_SETS, REQUIRED_TABLE_COLUMNS, _postgres_column_default_issues, _postgres_required_check_constraint_issues
from app.models.db import Group, GroupMember, PitchSample, PracticeSession, User
from app.schemas.schemas import (
    AcceptInvitationRequest,
    CreateGroupRequest,
    JoinByCodeRequest,
    StartSessionRequest,
    UpdateClassSharingConsentRequest,
)
from app.services.session_service import (
    save_pitch_frames_detailed,
    start_session_with_replay,
    stop_session_with_replay,
)


CONSENT = {
    "scope_code": "cloud_practice_sessions_since_membership_v1",
    "acknowledged": True,
}


def _user(user_id: int, username: str, *, role: str = "student") -> User:
    return User(
        id=user_id,
        username=username,
        name=username.title(),
        role=role,
        primary_instrument_id="trumpet",
    )


def _valid_frame(index: int, timestamp_ms: int = 100) -> dict:
    return {
        "client_frame_index": index,
        "timestamp_ms": timestamp_ms,
        "frequency_hz": 440.0,
        "confidence": 0.99,
        "rms": 0.1,
        "instrument_id": "trumpet",
        "reference_pitch_hz": 440.0,
    }


def test_consent_and_class_name_contracts_are_strict_and_normalized():
    assert CreateGroupRequest(name="  Cafe\u0301 Brass  ").name == "Caf\u00e9 Brass"
    with pytest.raises(ValidationError):
        CreateGroupRequest(name="   ")
    with pytest.raises(ValidationError):
        JoinByCodeRequest(code="ABCD")
    with pytest.raises(ValidationError):
        JoinByCodeRequest(code="１２３４５６", sharing_consent=CONSENT)
    with pytest.raises(ValidationError):
        AcceptInvitationRequest(instrument_id="horn")
    assert JoinByCodeRequest(code="abcd", sharing_consent=CONSENT).code == "ABCD"
    assert JoinByCodeRequest(code="  000123  ", sharing_consent=CONSENT).code == "000123"


def test_numeric_join_code_generation_preserves_leading_zeroes_and_retries_collisions(monkeypatch):
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    try:
        director = _user(8998, "code-director", role="director")
        db.add_all([director, Group(name="Taken", director_user_id=director.id, join_code="000001")])
        db.commit()
        values = iter((1, 2))
        monkeypatch.setattr("app.api.routes.secrets.randbelow", lambda _: next(values))
        assert _generate_join_code(db) == "000002"
    finally:
        db.close()
        engine.dispose()


def test_start_batch_and_stop_replays_are_idempotent_and_conflicts_fail_closed():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    try:
        db.add(_user(9001, "sync9001"))
        db.commit()
        started_at = dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=2)
        session, replayed = start_session_with_replay(
            db,
            "trumpet",
            "Cloud sync",
            440.0,
            9001,
            client_session_id="ios.session.9001",
            started_at=started_at,
        )
        assert replayed is False
        same, replayed = start_session_with_replay(
            db,
            "trumpet",
            "Cloud sync",
            440.0,
            9001,
            client_session_id="ios.session.9001",
            started_at=started_at,
        )
        assert replayed is True and same.id == session.id
        assert db.query(PracticeSession).count() == 1
        with pytest.raises(HTTPException) as conflict:
            start_session_with_replay(
                db,
                "horn",
                "Cloud sync",
                440.0,
                9001,
                client_session_id="ios.session.9001",
                started_at=started_at,
            )
        assert conflict.value.status_code == 409

        rejected_frame = {**_valid_frame(9, timestamp_ms=90), "confidence": 0.1}
        saved = save_pitch_frames_detailed(db, session.id, [_valid_frame(0), rejected_frame])
        replay = save_pitch_frames_detailed(db, session.id, [_valid_frame(0)])
        assert (len(saved.saved_samples), len(saved.replayed_samples), saved.rejected) == (1, 0, 1)
        assert (len(replay.saved_samples), len(replay.replayed_samples), replay.rejected) == (0, 1, 0)
        assert db.query(PitchSample).count() == 1
        with pytest.raises(HTTPException) as frame_conflict:
            save_pitch_frames_detailed(db, session.id, [_valid_frame(0, timestamp_ms=101)])
        assert frame_conflict.value.status_code == 409

        ended_at = started_at + dt.timedelta(minutes=1)
        stopped, replayed = stop_session_with_replay(
            db,
            session.id,
            client_session_id="ios.session.9001",
            ended_at=ended_at,
        )
        assert stopped is not None and replayed is False
        stopped_again, replayed = stop_session_with_replay(
            db,
            session.id,
            client_session_id="ios.session.9001",
            ended_at=ended_at,
        )
        assert stopped_again.id == session.id and replayed is True
        durable_retry = save_pitch_frames_detailed(db, session.id, [_valid_frame(0), rejected_frame])
        assert (
            len(durable_retry.saved_samples),
            len(durable_retry.replayed_samples),
            durable_retry.rejected,
        ) == (0, 1, 1)
        rejected_only = save_pitch_frames_detailed(
            db,
            session.id,
            [{**_valid_frame(10, timestamp_ms=91), "confidence": 0.1}],
        )
        assert (len(rejected_only.saved_samples), len(rejected_only.replayed_samples), rejected_only.rejected) == (0, 0, 1)
        with pytest.raises(HTTPException) as late_new_frame:
            save_pitch_frames_detailed(db, session.id, [_valid_frame(1)])
        assert late_new_frame.value.status_code == 409
        with pytest.raises(HTTPException) as late_conflicting_frame:
            save_pitch_frames_detailed(db, session.id, [_valid_frame(0, timestamp_ms=101)])
        assert late_conflicting_frame.value.status_code == 409
        with pytest.raises(HTTPException) as stop_conflict:
            stop_session_with_replay(
                db,
                session.id,
                client_session_id="ios.session.9001",
                ended_at=ended_at + dt.timedelta(seconds=1),
            )
        assert stop_conflict.value.status_code == 409
    finally:
        db.close()
        engine.dispose()


def test_concurrent_start_and_batch_replays_create_one_durable_row_each():
    with tempfile.TemporaryDirectory() as directory:
        engine = create_engine(
            "sqlite:///%s" % (Path(directory) / "sync.db"),
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(engine)
        Factory = sessionmaker(bind=engine)
        db = Factory()
        db.add(_user(9010, "sync9010"))
        db.commit()
        db.close()
        started_at = dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=1)

        def start_once():
            scoped = Factory()
            try:
                session, replayed = start_session_with_replay(
                    scoped,
                    "trumpet",
                    "Concurrent",
                    440.0,
                    9010,
                    client_session_id="concurrent.session.9010",
                    started_at=started_at,
                )
                return session.id, replayed
            finally:
                scoped.close()

        with ThreadPoolExecutor(max_workers=2) as pool:
            starts = list(pool.map(lambda _: start_once(), range(2)))
        assert len({row[0] for row in starts}) == 1
        assert sorted(row[1] for row in starts) == [False, True]

        session_id = starts[0][0]

        def batch_once():
            scoped = Factory()
            try:
                result = save_pitch_frames_detailed(scoped, session_id, [_valid_frame(4)])
                return len(result.saved_samples), len(result.replayed_samples)
            finally:
                scoped.close()

        with ThreadPoolExecutor(max_workers=2) as pool:
            batches = list(pool.map(lambda _: batch_once(), range(2)))
        assert sorted(batches) == [(0, 1), (1, 0)]
        verify = Factory()
        try:
            assert verify.query(PracticeSession).count() == 1
            assert verify.query(PitchSample).count() == 1
        finally:
            verify.close()
            engine.dispose()


def test_start_response_key_and_concurrent_stop_event_are_exact(monkeypatch):
    with tempfile.TemporaryDirectory() as directory:
        engine = create_engine(
            "sqlite:///%s" % (Path(directory) / "stop.db"),
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(engine)
        Factory = sessionmaker(bind=engine)
        db = Factory()
        user = _user(9015, "sync9015")
        db.add(user)
        db.commit()
        payload = start_practice_session(
            StartSessionRequest(
                instrument_id="trumpet",
                client_session_id="stop.session.9015",
            ),
            db=db,
            auth=AuthContext(user=user),
        )
        session_id = payload["id"]
        assert payload["idempotency_replayed"] is False
        assert "idempotent_replay" not in payload
        db.close()

        observed_events = []
        events_guard = threading.Lock()

        def fake_record_event(_db, event_name, user_id, properties):
            with events_guard:
                observed_events.append((event_name, user_id, properties["session_id"]))

        monkeypatch.setattr("app.api.routes.record_event", fake_record_event)

        def stop_once():
            scoped = Factory()
            try:
                scoped_user = scoped.query(User).filter(User.id == 9015).one()
                return stop_practice_session(
                    session_id,
                    payload=None,
                    db=scoped,
                    auth=AuthContext(user=scoped_user),
                )
            finally:
                scoped.close()

        with ThreadPoolExecutor(max_workers=2) as pool:
            responses = list(pool.map(lambda _: stop_once(), range(2)))
        assert sorted(row["idempotency_replayed"] for row in responses) == [False, True]
        assert observed_events == [("session_completed", 9015, session_id)]
        engine.dispose()


def test_member_progress_is_bounded_isolated_weighted_and_contains_no_audio_detail():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    now = dt.datetime.utcnow()
    try:
        student = _user(9021, "student9021")
        outsider = _user(9022, "outsider9022")
        owner = _user(9023, "owner9023", role="director")
        group = Group(id=9024, name="Progress Class", director_user_id=owner.id)
        db.add_all([student, outsider, owner, group])
        db.commit()
        member = GroupMember(
            group_id=group.id,
            user_id=student.id,
            instrument_id="trumpet",
            status="active",
            active_since=now - dt.timedelta(days=20),
            aggregate_sharing_consented_at=now - dt.timedelta(days=20),
            aggregate_sharing_scope_code=CONSENT["scope_code"],
        )
        db.add(member)
        db.add_all([
            PracticeSession(user_id=student.id, instrument_id="trumpet", name="private audio one", started_at=now - dt.timedelta(days=2), duration_seconds=60, notes_count=1, average_abs_cents=20, in_tune_percentage=20, audio_object_key="secret/object"),
            PracticeSession(user_id=student.id, instrument_id="trumpet", name="private audio two", started_at=now - dt.timedelta(days=1), duration_seconds=180, notes_count=1, average_abs_cents=4, in_tune_percentage=80),
            PracticeSession(user_id=student.id, instrument_id="trumpet", name="previous", started_at=now - dt.timedelta(days=9), duration_seconds=120, notes_count=1, average_abs_cents=10, in_tune_percentage=50),
            PracticeSession(user_id=outsider.id, instrument_id="trumpet", name="outsider secret", started_at=now - dt.timedelta(days=1), duration_seconds=9999, notes_count=1, average_abs_cents=99, in_tune_percentage=1),
        ])
        db.commit()
        payload = ensemble_group_my_progress(group.id, db=db, auth=AuthContext(user=student))
        assert payload["current_7d"]["practice_minutes"] == 4.0
        assert payload["current_7d"]["average_abs_cents"] == 8.0
        assert payload["current_7d"]["in_tune_percentage"] == 65.0
        assert payload["previous_7d"]["practice_minutes"] == 2.0
        assert payload["delta"]["practice_minutes"] == 2.0
        serialized = json.dumps(payload)
        assert "audio_object_key" not in serialized
        assert "audio_mime_type" not in serialized
        assert "secret" not in serialized.lower()
        assert "session_id" not in serialized
    finally:
        db.close()
        engine.dispose()


def test_legacy_active_membership_is_excluded_until_self_scoped_consent():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    now = dt.datetime.utcnow()
    try:
        student = _user(9026, "legacy9026")
        owner = _user(9027, "owner9027", role="director")
        outsider = _user(9028, "outsider9028")
        group = Group(id=9029, name="Legacy Consent Class", director_user_id=owner.id)
        db.add_all([student, owner, outsider, group])
        db.commit()
        member = GroupMember(
            group_id=group.id,
            user_id=student.id,
            instrument_id="trumpet",
            status="active",
            active_since=now - dt.timedelta(days=3),
        )
        db.add(member)
        db.add(
            PracticeSession(
                user_id=student.id,
                instrument_id="trumpet",
                name="must remain private before opt in",
                started_at=now - dt.timedelta(days=1),
                duration_seconds=600,
                notes_count=1,
                average_abs_cents=5,
                in_tune_percentage=90,
            )
        )
        db.commit()

        student_detail = get_ensemble_group(group.id, db=db, auth=AuthContext(user=student))
        student_listed = next(row for row in list_ensemble_groups(db=db, auth=AuthContext(user=student)) if row["id"] == group.id)
        before = ensemble_group_roster(group.id, db=db, auth=AuthContext(user=owner))
        assert student_detail["viewer_has_aggregate_sharing_consent"] is False
        assert student_listed["viewer_has_aggregate_sharing_consent"] is False
        assert before["students"][0]["practice_minutes"] == 0

        with pytest.raises(HTTPException) as denied:
            update_my_group_sharing_consent(
                group.id,
                UpdateClassSharingConsentRequest(sharing_consent=CONSENT),
                db=db,
                auth=AuthContext(user=outsider),
            )
        assert denied.value.status_code == 403

        accepted = update_my_group_sharing_consent(
            group.id,
            UpdateClassSharingConsentRequest(sharing_consent=CONSENT),
            db=db,
            auth=AuthContext(user=student),
        )
        assert accepted["viewer_has_aggregate_sharing_consent"] is True
        student_detail = get_ensemble_group(group.id, db=db, auth=AuthContext(user=student))
        student_listed = next(row for row in list_ensemble_groups(db=db, auth=AuthContext(user=student)) if row["id"] == group.id)
        after = ensemble_group_roster(group.id, db=db, auth=AuthContext(user=owner))
        assert student_detail["viewer_has_aggregate_sharing_consent"] is True
        assert student_listed["viewer_has_aggregate_sharing_consent"] is True
        assert after["students"][0]["practice_minutes"] == 10
    finally:
        db.close()
        engine.dispose()


def test_assistant_gets_redacted_roster_and_analytics_but_mutation_is_denied():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    try:
        owner = _user(9031, "owner9031", role="director")
        assistant = _user(9032, "assistant9032")
        student = _user(9033, "student9033")
        assistant.name = "Duplicate Name"
        student.name = "Duplicate Name"
        group = Group(id=9034, name="Assistant Class", director_user_id=owner.id, join_code="ASSIST34")
        db.add_all([owner, assistant, student, group])
        db.commit()
        db.add_all([
            GroupMember(group_id=group.id, user_id=assistant.id, instrument_id="trumpet", role_in_group="assistant", status="active", active_since=dt.datetime.utcnow() - dt.timedelta(days=10), aggregate_sharing_consented_at=dt.datetime.utcnow(), aggregate_sharing_scope_code=CONSENT["scope_code"]),
            GroupMember(group_id=group.id, user_id=student.id, instrument_id="horn", role_in_group="student", status="active", active_since=dt.datetime.utcnow() - dt.timedelta(days=10), aggregate_sharing_consented_at=dt.datetime.utcnow(), aggregate_sharing_scope_code=CONSENT["scope_code"]),
        ])
        db.commit()
        exact_practice_at = dt.datetime.utcnow() - dt.timedelta(days=2, hours=3)
        db.add_all([
            PracticeSession(user_id=assistant.id, instrument_id="trumpet", name="assistant", started_at=exact_practice_at, duration_seconds=60, notes_count=1, average_abs_cents=4, in_tune_percentage=90),
            PracticeSession(user_id=student.id, instrument_id="horn", name="student", started_at=exact_practice_at, duration_seconds=60, notes_count=1, average_abs_cents=5, in_tune_percentage=80),
        ])
        db.commit()
        detail = get_ensemble_group(group.id, db=db, auth=AuthContext(user=assistant))
        roster = ensemble_group_roster(group.id, db=db, auth=AuthContext(user=assistant))
        owner_roster = ensemble_group_roster(group.id, db=db, auth=AuthContext(user=owner))
        assert detail["viewer_can_view_roster"] is True
        assert detail["viewer_can_view_class_analytics"] is True
        assert detail["roster_scope"] == "active_redacted"
        assert roster["roster_scope"] == "active_redacted"
        assert all("user_id" not in row and "username" not in row and "member_id" not in row for row in roster["students"])
        assert all("member_id" in row and "user_id" not in row for row in owner_roster["students"])
        for visible_roster in (roster, owner_roster):
            assert len({row["roster_row_id"] for row in visible_roster["students"]}) == 2
            assert all(row["last_practice_at"] is None for row in visible_roster["students"])
            assert all(row["current_7d"]["last_practice_at"] is None for row in visible_roster["students"])
            assert all(row["previous_7d"]["last_practice_at"] is None for row in visible_roster["students"])
            assert all(row["inactivity"]["last_practice_at"] is None for row in visible_roster["students"])
            assert exact_practice_at.isoformat() not in json.dumps(visible_roster)
        with pytest.raises(HTTPException) as denied:
            rotate_ensemble_join_code(group.id, db=db, auth=AuthContext(user=assistant))
        assert denied.value.status_code == 403
    finally:
        db.close()
        engine.dispose()


def test_legacy_assistant_capabilities_and_analytics_require_self_consent():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    try:
        owner = _user(9041, "owner9041", role="director")
        assistant = _user(9042, "assistant9042")
        group = Group(id=9043, name="Legacy Assistant", director_user_id=owner.id)
        db.add_all([owner, assistant, group])
        db.commit()
        db.add(
            GroupMember(
                group_id=group.id,
                user_id=assistant.id,
                instrument_id="trumpet",
                role_in_group="assistant",
                status="active",
                active_since=dt.datetime.utcnow() - dt.timedelta(days=2),
            )
        )
        db.commit()
        auth = AuthContext(user=assistant)

        before = get_ensemble_group(group.id, db=db, auth=auth)
        assert before["viewer_role"] == "assistant"
        assert before["viewer_has_aggregate_sharing_consent"] is False
        assert before["viewer_can_view_roster"] is False
        assert before["viewer_can_view_class_analytics"] is False
        assert before["roster_scope"] == "self"
        for endpoint in (ensemble_group_roster, ensemble_group_summary, ensemble_group_report):
            with pytest.raises(HTTPException) as denied:
                endpoint(group.id, db=db, auth=auth)
            assert denied.value.status_code == 403

        update_my_group_sharing_consent(
            group.id,
            UpdateClassSharingConsentRequest(sharing_consent=CONSENT),
            db=db,
            auth=auth,
        )
        after = get_ensemble_group(group.id, db=db, auth=auth)
        assert after["viewer_has_aggregate_sharing_consent"] is True
        assert after["viewer_can_view_roster"] is True
        assert after["viewer_can_view_class_analytics"] is True
        assert after["roster_scope"] == "active_redacted"
        assert ensemble_group_roster(group.id, db=db, auth=auth)["roster_scope"] == "active_redacted"
        assert ensemble_group_summary(group.id, db=db, auth=auth)["group_id"] == group.id
        assert ensemble_group_report(group.id, db=db, auth=auth)["group_id"] == group.id
    finally:
        db.close()
        engine.dispose()


def test_migration_and_readiness_require_private_sync_and_consent_shape():
    migration = next(
        (Path(__file__).resolve().parents[3] / "supabase" / "migrations").glob(
            "*_add_class_consent_and_sync_idempotency.sql"
        )
    ).read_text().lower()
    for expected in (
        "client_session_id",
        "unique (user_id, client_session_id)",
        "client_frame_index",
        "unique (session_id, client_frame_index)",
        "aggregate_sharing_consented_at",
        "aggregate_sharing_scope_code",
        "roster_row_id",
        "alter column roster_row_id set default gen_random_uuid()::text",
        "cloud_practice_sessions_since_membership_v1",
        "group_members_aggregate_sharing_pair_check",
        "enable row level security",
        "revoke all privileges",
    ):
        assert expected in migration
    assert "set aggregate_sharing_consented_at" not in migration
    assert "set aggregate_sharing_scope_code" not in migration
    assert "group_members_active_aggregate_consent_check check" not in migration
    assert "audio_" not in migration
    assert "client_session_id" in REQUIRED_TABLE_COLUMNS["practice_sessions"]
    assert "client_frame_index" in REQUIRED_TABLE_COLUMNS["pitch_samples"]
    assert ("user_id", "client_session_id") in REQUIRED_POSTGRES_UNIQUE_COLUMN_SETS["practice_sessions"]
    assert ("session_id", "client_frame_index") in REQUIRED_POSTGRES_UNIQUE_COLUMN_SETS["pitch_samples"]
    assert ("roster_row_id",) in REQUIRED_POSTGRES_UNIQUE_COLUMN_SETS["group_members"]
    assert _postgres_column_default_issues(
        "group_members",
        [{"name": "roster_row_id", "default": "(gen_random_uuid())::text"}],
    ) == []
    assert _postgres_column_default_issues(
        "group_members",
        [{"name": "roster_row_id", "default": None}],
    ) == [
        "Column group_members.roster_row_id must have a server default containing gen_random_uuid()."
    ]

    valid_rows = [
        {"table_name": "group_members", "constraint_name": "group_members_aggregate_sharing_scope_check", "validated": True},
        {"table_name": "group_members", "constraint_name": "group_members_aggregate_sharing_pair_check", "validated": True},
    ]
    assert _postgres_required_check_constraint_issues(valid_rows, {"group_members"}) == []
    assert _postgres_required_check_constraint_issues(valid_rows[:1], {"group_members"}) == [
        "Missing required check constraint group_members_aggregate_sharing_pair_check on group_members."
    ]
    invalid_rows = [dict(valid_rows[0]), {**valid_rows[1], "validated": False}]
    assert _postgres_required_check_constraint_issues(invalid_rows, {"group_members"}) == [
        "Required check constraint group_members_aggregate_sharing_pair_check on group_members must be validated."
    ]


def test_existing_sqlite_schema_upgrades_sync_consent_and_roster_contract(monkeypatch):
    with tempfile.TemporaryDirectory() as directory:
        legacy_engine = create_engine("sqlite:///%s" % (Path(directory) / "legacy-class.db"))
        with legacy_engine.begin() as connection:
            connection.execute(text("create table practice_sessions (id integer primary key, user_id integer not null)"))
            connection.execute(text("create table pitch_samples (id integer primary key, session_id integer not null)"))
            connection.execute(text("create table group_members (id integer primary key, group_id integer not null, user_id integer not null, status varchar)"))
            connection.execute(text("insert into practice_sessions (id, user_id) values (1, 10)"))
            connection.execute(text("insert into pitch_samples (id, session_id) values (1, 1)"))
            connection.execute(text("insert into group_members (id, group_id, user_id, status) values (1, 20, 10, 'active'), (2, 20, 11, 'active')"))
        monkeypatch.setattr(database_module, "engine", legacy_engine)

        database_module.ensure_additive_columns()
        database_module.ensure_additive_columns()

        with legacy_engine.connect() as connection:
            practice_columns = {row[1] for row in connection.execute(text("pragma table_info(practice_sessions)"))}
            pitch_columns = {row[1] for row in connection.execute(text("pragma table_info(pitch_samples)"))}
            member_columns = {row[1] for row in connection.execute(text("pragma table_info(group_members)"))}
            members = connection.execute(
                text(
                    "select roster_row_id, aggregate_sharing_consented_at, aggregate_sharing_scope_code "
                    "from group_members order by id"
                )
            ).all()
        assert "client_session_id" in practice_columns
        assert "client_frame_index" in pitch_columns
        assert {
            "aggregate_sharing_consented_at",
            "aggregate_sharing_scope_code",
            "roster_row_id",
        } <= member_columns
        assert len({row[0] for row in members}) == 2
        assert all(row[0] and row[1] is None and row[2] is None for row in members)
        assert ("user_id", "client_session_id") in database_module._sqlite_unique_column_sets("practice_sessions")
        assert ("session_id", "client_frame_index") in database_module._sqlite_unique_column_sets("pitch_samples")
        assert ("roster_row_id",) in database_module._sqlite_unique_column_sets("group_members")
        legacy_engine.dispose()
