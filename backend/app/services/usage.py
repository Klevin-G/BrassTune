"""Lightweight, best-effort product-usage tracking.

Deliberately tiny: a single usage_events table plus a last_active_at stamp on
users. Never raises to the caller — analytics must not break a real request.
"""
import datetime as dt
from typing import Optional

from sqlalchemy.orm import Session

from app.models.db import UsageEvent


def record_event(db: Session, event_name: str, user_id: Optional[int] = None, properties: Optional[dict] = None) -> None:
    """Persist one coarse usage event. Call AFTER the primary operation has
    committed so a failure here can only roll back this row, not the caller's work."""
    try:
        db.add(UsageEvent(user_id=user_id, event_name=event_name, properties=properties or {}))
        db.commit()
    except Exception:  # noqa: BLE001 — usage tracking is strictly best-effort
        db.rollback()
