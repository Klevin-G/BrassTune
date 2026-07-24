import os
import tempfile
from pathlib import Path

import pytest


os.environ.setdefault("APP_ENV", "local")
os.environ.setdefault("BRASSTUNE_AUTH_MODE", "disabled")
os.environ.setdefault("CORS_ALLOWED_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173,https://brasstune.vercel.app")

# Importing app.db.database creates the engine immediately. Ambient application
# database variables must never make an ordinary pytest run mutate a developer
# or production database. PostgreSQL integration runs opt in through the
# test-only variable below.
_PYTEST_DATABASE_URL = os.getenv("BRASSTUNE_TEST_DATABASE_URL", "").strip()
_PYTEST_TOMBSTONE_SECRET = (
    os.getenv("BRASSTUNE_DELETION_TOMBSTONE_SECRET", "").strip()
    or "test-only-deletion-tombstone-key-32-bytes"
)
os.environ.pop("BRASSTUNE_DATABASE_URL", None)
os.environ.pop("DATABASE_URL", None)
if _PYTEST_DATABASE_URL:
    os.environ["BRASSTUNE_DATABASE_URL"] = _PYTEST_DATABASE_URL
    os.environ.pop("BRASSTUNE_PYTEST_DATABASE_ISOLATED", None)
else:
    _PYTEST_DATABASE_DIR = tempfile.TemporaryDirectory(prefix="brasstune-pytest-")
    _PYTEST_DATABASE_PATH = Path(_PYTEST_DATABASE_DIR.name) / "brasstune-test.db"
    os.environ["BRASSTUNE_DATABASE_URL"] = "sqlite:///%s" % _PYTEST_DATABASE_PATH
    os.environ["BRASSTUNE_PYTEST_DATABASE_ISOLATED"] = "1"


@pytest.fixture(autouse=True)
def local_backend_env(monkeypatch):
    monkeypatch.setenv("APP_ENV", "local")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "disabled")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173,https://brasstune.vercel.app")
    monkeypatch.setenv("BRASSTUNE_DELETION_TOMBSTONE_SECRET", _PYTEST_TOMBSTONE_SECRET)
    monkeypatch.delenv("BRASSTUNE_ALLOW_LOCAL_AUTH", raising=False)
