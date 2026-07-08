import os

import pytest


os.environ.setdefault("APP_ENV", "local")
os.environ.setdefault("BRASSTUNE_AUTH_MODE", "disabled")
os.environ.setdefault("CORS_ALLOWED_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173,https://brass-tune.vercel.app")


@pytest.fixture(autouse=True)
def local_backend_env(monkeypatch):
    monkeypatch.setenv("APP_ENV", "local")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "disabled")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173,https://brass-tune.vercel.app")
    monkeypatch.delenv("BRASSTUNE_ALLOW_LOCAL_AUTH", raising=False)
