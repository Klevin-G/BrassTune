import datetime as dt
import hashlib
import hmac
import os

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from app.models.db import AccountDeletionJob, DeletedIdentityTombstone, DeletedIdentityTombstoneConfig


# The constant is an environment-variable name, never credential material.
DELETION_TOMBSTONE_SECRET_ENV = "BRASSTUNE_DELETION_TOMBSTONE_SECRET"  # nosec B105
MIN_DELETION_TOMBSTONE_SECRET_BYTES = 32
DEFAULT_TERMINAL_JOB_RETENTION_DAYS = 7
MAX_TERMINAL_JOB_RETENTION_DAYS = 30
MAX_TERMINAL_JOB_PURGE_BATCH = 1_000
_DIGEST_DOMAIN = b"brasstune:deleted-supabase-subject:v1\0"
_KEY_VERIFIER_DOMAIN = b"brasstune:deleted-identity-key-verifier:v1"


class DeletionTombstoneSecretError(RuntimeError):
    pass


def deletion_tombstone_secret_issue() -> str | None:
    value = os.getenv(DELETION_TOMBSTONE_SECRET_ENV, "")
    if len(value.encode("utf-8")) < MIN_DELETION_TOMBSTONE_SECRET_BYTES:
        return (
            "%s must be a stable, dedicated secret of at least %s bytes."
            % (DELETION_TOMBSTONE_SECRET_ENV, MIN_DELETION_TOMBSTONE_SECRET_BYTES)
        )
    return None


def deleted_identity_digest(subject: str) -> str:
    issue = deletion_tombstone_secret_issue()
    if issue:
        raise DeletionTombstoneSecretError(issue)
    normalized_subject = str(subject or "").strip()
    if not normalized_subject:
        raise ValueError("Deleted identity subject must be non-empty.")
    key = os.environ[DELETION_TOMBSTONE_SECRET_ENV].encode("utf-8")
    return hmac.new(key, _DIGEST_DOMAIN + normalized_subject.encode("utf-8"), hashlib.sha256).hexdigest()


def deletion_tombstone_key_verifier() -> str:
    issue = deletion_tombstone_secret_issue()
    if issue:
        raise DeletionTombstoneSecretError(issue)
    key = os.environ[DELETION_TOMBSTONE_SECRET_ENV].encode("utf-8")
    return hmac.new(key, _KEY_VERIFIER_DOMAIN, hashlib.sha256).hexdigest()


def ensure_deletion_tombstone_key_state(db: Session, allow_initialization: bool = False) -> None:
    expected = deletion_tombstone_key_verifier()
    state = db.query(DeletedIdentityTombstoneConfig).filter(DeletedIdentityTombstoneConfig.id == 1).first()
    if state is None:
        has_tombstones = db.query(DeletedIdentityTombstone.id).first() is not None
        if not allow_initialization or has_tombstones:
            raise DeletionTombstoneSecretError("Deleted identity key state is not initialized.")
        db.add(DeletedIdentityTombstoneConfig(id=1, key_verifier=expected))
        db.flush()
        return
    if not hmac.compare_digest(state.key_verifier, expected):
        raise DeletionTombstoneSecretError("Deleted identity key does not match durable key state.")


def deleted_identity_is_blocked(db: Session, subject: str) -> bool:
    ensure_deletion_tombstone_key_state(db)
    digest = deleted_identity_digest(subject)
    return (
        db.query(DeletedIdentityTombstone.id)
        .filter(DeletedIdentityTombstone.subject_digest == digest)
        .first()
        is not None
    )


def _store_deleted_identity_tombstone(db: Session, subject: str) -> None:
    ensure_deletion_tombstone_key_state(db)
    digest = deleted_identity_digest(subject)
    if (
        db.query(DeletedIdentityTombstone.id)
        .filter(DeletedIdentityTombstone.subject_digest == digest)
        .first()
        is not None
    ):
        return
    try:
        # A savepoint makes concurrent completion idempotent without rolling
        # back the surrounding account-deletion state.
        with db.begin_nested():
            db.add(DeletedIdentityTombstone(subject_digest=digest))
            db.flush()
    except IntegrityError:
        pass


def terminal_job_is_scrubbed(job: AccountDeletionJob) -> bool:
    return bool(
        job.status == "completed"
        and job.id is not None
        and job.user_id is None
        and job.supabase_user_id is None
        and job.idempotency_key == "terminal:%s" % job.id
        and (job.counts_json == {} or job.counts_json == "{}")
        and job.completed_at is not None
    )


def complete_and_scrub_account_deletion_job(db: Session, job: AccountDeletionJob) -> None:
    """Atomically persist a minimal deny-list tombstone and scrub the job."""
    if job.id is None:
        db.add(job)
        db.flush()
    if job.supabase_user_id:
        _store_deleted_identity_tombstone(db, job.supabase_user_id)
    now = dt.datetime.utcnow()
    job.stage = "completed"
    job.status = "completed"
    job.user_id = None
    job.supabase_user_id = None
    job.idempotency_key = "terminal:%s" % job.id
    job.safe_error_category = None
    job.counts_json = {}
    job.next_retry_at = None
    job.completed_at = job.completed_at or now
    job.updated_at = now
    db.add(job)


def _terminal_job_retention_days() -> int:
    try:
        configured = int(
            os.getenv(
                "BRASSTUNE_ACCOUNT_DELETION_JOB_RETENTION_DAYS",
                str(DEFAULT_TERMINAL_JOB_RETENTION_DAYS),
            )
        )
    except (TypeError, ValueError):
        return DEFAULT_TERMINAL_JOB_RETENTION_DAYS
    if configured <= 0:
        return DEFAULT_TERMINAL_JOB_RETENTION_DAYS
    return min(configured, MAX_TERMINAL_JOB_RETENTION_DAYS)


def scrub_legacy_terminal_account_deletion_jobs(db: Session, limit: int = 1_000) -> dict:
    """Backfill tombstones before removing identifiers from legacy terminal rows."""
    jobs = (
        db.query(AccountDeletionJob)
        .filter(
            AccountDeletionJob.status == "completed",
            (
                AccountDeletionJob.user_id.is_not(None)
                | AccountDeletionJob.supabase_user_id.is_not(None)
            ),
        )
        .order_by(AccountDeletionJob.completed_at.asc(), AccountDeletionJob.id.asc())
        .limit(max(1, min(limit, 10_000)))
        .all()
    )
    scrubbed = 0
    failed = 0
    for job in jobs:
        if terminal_job_is_scrubbed(job):
            continue
        try:
            complete_and_scrub_account_deletion_job(db, job)
            scrubbed += 1
        except (DeletionTombstoneSecretError, ValueError):
            failed += 1
    try:
        db.commit()
    except Exception:
        db.rollback()
        return {"scrubbed": 0, "failed": max(1, failed + scrubbed)}
    return {"scrubbed": scrubbed, "failed": failed}


def purge_terminal_account_deletion_jobs(db: Session) -> dict:
    """Purge only already-scrubbed jobs after a short, bounded retention period."""
    retention_days = _terminal_job_retention_days()
    cutoff = dt.datetime.utcnow() - dt.timedelta(days=retention_days)
    candidates = (
        db.query(AccountDeletionJob)
        .filter(
            AccountDeletionJob.status == "completed",
            AccountDeletionJob.completed_at.is_not(None),
            AccountDeletionJob.completed_at <= cutoff,
        )
        .order_by(AccountDeletionJob.completed_at.asc(), AccountDeletionJob.id.asc())
        .limit(MAX_TERMINAL_JOB_PURGE_BATCH)
        .all()
    )
    candidate_ids = [job.id for job in candidates if terminal_job_is_scrubbed(job)]
    try:
        purged = 0
        if candidate_ids:
            purged = (
                db.query(AccountDeletionJob)
                .filter(AccountDeletionJob.id.in_(candidate_ids))
                .delete(synchronize_session=False)
            )
        db.commit()
        return {"retention_days": retention_days, "purged": int(purged or 0), "failed": False}
    except Exception:
        db.rollback()
        return {"retention_days": retention_days, "purged": 0, "failed": True}


def validate_account_deletion_privacy_constraint(db: Session) -> bool | None:
    if db.get_bind().dialect.name != "postgresql":
        return None
    try:
        already_validated = db.execute(
            text(
                "select convalidated from pg_constraint "
                "where conrelid = to_regclass('public.account_deletion_jobs') "
                "and conname = 'account_deletion_jobs_terminal_privacy_check'"
            )
        ).scalar()
        # The expand migration intentionally has no terminal privacy constraint
        # so the previously deployed writer remains safe during database-first
        # rollout and rollback. The separately applied contract migration adds
        # and validates it after this backend has scrubbed legacy terminal rows.
        if already_validated is None:
            db.rollback()
            return None
        if already_validated is True:
            db.rollback()
            return True
        db.execute(
            text(
                "alter table public.account_deletion_jobs "
                "validate constraint account_deletion_jobs_terminal_privacy_check"
            )
        )
        db.commit()
        return True
    except SQLAlchemyError:
        db.rollback()
        return False


def maintain_terminal_account_deletion_jobs(db: Session, limit: int = 1_000) -> dict:
    scrub = scrub_legacy_terminal_account_deletion_jobs(db, limit=limit)
    validation = validate_account_deletion_privacy_constraint(db)
    purge = purge_terminal_account_deletion_jobs(db)
    return {
        "scrubbed": scrub["scrubbed"],
        "failed": scrub["failed"],
        "constraint_validated": validation,
        "terminal_purge": purge,
    }
