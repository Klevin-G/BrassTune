import threading
from contextlib import contextmanager

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.db import AccountDeletionJob

_PROCESS_LOCKS_GUARD = threading.Lock()
_PROCESS_LOCKS: dict[int, tuple[threading.RLock, int]] = {}


def _retain_process_lock(user_id: int) -> threading.RLock:
    with _PROCESS_LOCKS_GUARD:
        lock, references = _PROCESS_LOCKS.get(user_id, (threading.RLock(), 0))
        _PROCESS_LOCKS[user_id] = (lock, references + 1)
        return lock


def _release_process_lock(user_id: int, lock: threading.RLock) -> None:
    with _PROCESS_LOCKS_GUARD:
        current_lock, references = _PROCESS_LOCKS.get(user_id, (lock, 1))
        if current_lock is not lock:
            return
        if references <= 1:
            _PROCESS_LOCKS.pop(user_id, None)
        else:
            _PROCESS_LOCKS[user_id] = (lock, references - 1)


@contextmanager
def account_mutation_guard(db: Session, user_id: int):
    """Serialize multi-commit account mutations in local SQLite environments.

    PostgreSQL writers instead share the account-row lock and durable deletion
    marker checked by ``assert_account_accepts_mutation``. That avoids checking
    out a second connection while a request session already owns one, which can
    deadlock a constrained production pool under bursts.
    """
    account_id = int(user_id)
    if account_id <= 0:
        raise ValueError("Account id is outside the supported mutation-lock range.")
    if db.get_bind().dialect.name == "postgresql":
        yield
        return

    process_lock = _retain_process_lock(account_id)
    process_lock.acquire()
    try:
        yield
    finally:
        process_lock.release()
        _release_process_lock(account_id, process_lock)


def assert_account_accepts_mutation(db: Session, user_id: int) -> None:
    """Reject writes after deletion has durably entered its first phase.

    Callers acquire the account row lock first. Deletion takes the same lock
    before committing this marker, so either the mutation commits first and is
    included in deletion's snapshot, or it observes the marker and stops.
    """
    deletion_started = (
        db.query(AccountDeletionJob.id)
        .filter(
            AccountDeletionJob.user_id == int(user_id),
            AccountDeletionJob.status != "completed",
        )
        .first()
    )
    if deletion_started is not None:
        raise HTTPException(
            status_code=423,
            detail="Account deletion is already in progress.",
        )
