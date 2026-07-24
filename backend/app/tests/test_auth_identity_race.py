import datetime as dt
import logging

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

import app.api.auth as auth_module
from app.db.database import get_db
from app.main import app
from app.models.db import AccountDeletionJob, User


class _RaceQuery:
    def __init__(self, session, model):
        self._session = session
        self._model = model

    def filter(self, *_args):
        return self

    def order_by(self, *_args):
        return self

    def first(self):
        if self._model is AccountDeletionJob:
            return None
        if self._model is User:
            self._session.user_query_count += 1
            # Initial identity lookup and username availability lookup both
            # happen before the competing request commits its row.
            if self._session.user_query_count <= 2:
                return None
            return self._session.concurrent_winner
        raise AssertionError("Unexpected query model: %r" % (self._model,))


class _DuplicateIdentityRaceSession:
    def __init__(self, winner, integrity_error):
        self.concurrent_winner = winner
        self.integrity_error = integrity_error
        self.user_query_count = 0
        self.rollback_count = 0
        self.refresh_count = 0

    def query(self, model):
        return _RaceQuery(self, model)

    def add(self, _value):
        return None

    def commit(self):
        raise self.integrity_error

    def rollback(self):
        self.rollback_count += 1

    def refresh(self, value):
        assert value is self.concurrent_winner
        self.refresh_count += 1


def _winner(supabase_id: str, email: str) -> User:
    now = dt.datetime(2026, 7, 23, 12, 0, 0)
    return User(
        id=731,
        supabase_user_id=supabase_id,
        email=email,
        username="race-player",
        name="Race Player",
        display_name="Race Player",
        role="student",
        admin_granted_by_env=False,
        primary_instrument_id="trumpet",
        created_at=now,
        updated_at=now,
        last_active_at=now,
    )


def test_duplicate_supabase_identity_race_converges_without_logging_insert_parameters(monkeypatch, caplog):
    supabase_id = "identity-race-sensitive-subject"
    email = "identity-race-sensitive@example.com"
    display_name = "Identity Race Sensitive Name"
    statement = "INSERT INTO users (supabase_user_id, email, name) VALUES (?, ?, ?)"
    parameters = (supabase_id, email, display_name)
    winner = _winner(supabase_id, email)
    db = _DuplicateIdentityRaceSession(
        winner,
        IntegrityError(statement, parameters, Exception("duplicate key")),
    )
    signup_events = []
    payload = {
        "id": supabase_id,
        "email": email,
        "user_metadata": {
            "username": "race-player",
            "display_name": display_name,
        },
        "app_metadata": {},
    }
    monkeypatch.setattr(auth_module, "deleted_identity_is_blocked", lambda *_args: False)
    monkeypatch.setattr(auth_module, "record_event", lambda *args: signup_events.append(args))
    monkeypatch.setattr(auth_module, "_fetch_supabase_user", lambda _token: payload)
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "supabase")

    caplog.set_level(logging.DEBUG)
    app.dependency_overrides[get_db] = lambda: db
    client = TestClient(app)
    try:
        response = client.get(
            "/api/users/current",
            headers={"Authorization": "Bearer identity-race-access-token"},
        )
    finally:
        client.close()
        app.dependency_overrides.pop(get_db, None)

    assert response.status_code == 200
    assert response.json()["id"] == winner.id
    assert response.json()["supabase_user_id"] == supabase_id
    assert response.json()["email"] == email
    assert db.rollback_count == 1
    assert db.refresh_count == 1
    assert signup_events == []
    for sensitive_value in (statement, supabase_id, email, display_name):
        assert sensitive_value not in caplog.text


def test_unmatched_identity_insert_conflict_returns_sanitized_retry(monkeypatch, caplog):
    supabase_id = "unmatched-sensitive-subject"
    email = "unmatched-sensitive@example.com"
    statement = "INSERT INTO users (supabase_user_id, email) VALUES (?, ?)"
    db = _DuplicateIdentityRaceSession(
        None,
        IntegrityError(statement, (supabase_id, email), Exception("duplicate key")),
    )
    monkeypatch.setattr(auth_module, "deleted_identity_is_blocked", lambda *_args: False)

    caplog.set_level(logging.DEBUG)
    with pytest.raises(HTTPException) as blocked:
        auth_module._sync_supabase_user(
            db,
            {
                "id": supabase_id,
                "email": email,
                "user_metadata": {},
                "app_metadata": {},
            },
        )

    assert blocked.value.status_code == 503
    assert blocked.value.detail == "Account setup is temporarily unavailable. Try again."
    assert blocked.value.__cause__ is None
    assert blocked.value.__suppress_context__ is True
    for sensitive_value in (statement, supabase_id, email):
        assert sensitive_value not in caplog.text
