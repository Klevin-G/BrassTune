"""Backfill keyed tombstones and scrub legacy terminal deletion jobs.

Run after the additive migration and before the read-only readiness gate. The
command never calls Supabase or retries account deletion; it only transforms
already-completed local rows and validates their privacy constraint.
"""

import json

from sqlalchemy.exc import SQLAlchemyError

from app.db.database import SessionLocal
from app.services.account_deletion import (
    DeletionTombstoneSecretError,
    ensure_deletion_tombstone_key_state,
    maintain_terminal_account_deletion_jobs,
)


def main() -> int:
    db = SessionLocal()
    total_scrubbed = 0
    try:
        try:
            ensure_deletion_tombstone_key_state(db, allow_initialization=True)
            db.commit()
            for _ in range(100):
                result = maintain_terminal_account_deletion_jobs(db, limit=1_000)
                total_scrubbed += int(result["scrubbed"])
                if result["failed"]:
                    print(json.dumps({"ok": False, "scrubbed": total_scrubbed, "reason": "terminal_rows_not_scrubbed"}))
                    return 1
                if result["scrubbed"] == 0:
                    validated = result["constraint_validated"]
                    ok = validated is not False
                    print(json.dumps({"ok": ok, "scrubbed": total_scrubbed, "constraint_validated": validated}))
                    return 0 if ok else 1
            print(json.dumps({"ok": False, "scrubbed": total_scrubbed, "reason": "bounded_batch_limit_reached"}))
            return 1
        except (DeletionTombstoneSecretError, SQLAlchemyError):
            db.rollback()
            print(json.dumps({"ok": False, "scrubbed": total_scrubbed, "reason": "privacy_migration_unavailable"}))
            return 1
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
