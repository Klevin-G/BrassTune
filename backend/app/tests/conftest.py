import pytest


@pytest.fixture(autouse=True)
def local_backend_env(monkeypatch):
    monkeypatch.setenv("APP_ENV", "local")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "disabled")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173,https://brass-tune.vercel.app")
    monkeypatch.delenv("BRASSTUNE_ALLOW_LOCAL_AUTH", raising=False)
