from fastapi.testclient import TestClient

from app.main import app


PUBLIC_URL = "https://abcdefghijklmnopqrst.supabase.co"
PUBLIC_KEY = "sb_publishable_0123456789abcdefghij"


def _configure_public_auth(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", PUBLIC_URL)
    monkeypatch.setenv("SUPABASE_PUBLISHABLE_KEY", PUBLIC_KEY)


def test_recovery_page_serves_only_public_config_with_restrictive_headers(monkeypatch):
    _configure_public_auth(monkeypatch)
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "never-render-this-secret")

    with TestClient(app) as client:
        response = client.get("/auth/reset-password")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["referrer-policy"] == "no-referrer"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["x-frame-options"] == "DENY"
    assert response.headers["cross-origin-resource-policy"] == "same-origin"
    assert response.headers["cross-origin-opener-policy"] == "same-origin"
    assert response.headers["x-robots-tag"] == "noindex, nofollow"
    assert "microphone=()" in response.headers["permissions-policy"]
    csp = response.headers["content-security-policy"]
    assert "default-src 'none'" in csp
    assert "script-src 'self'" in csp
    assert "style-src 'self'" in csp
    assert "connect-src %s" % PUBLIC_URL in csp
    assert "form-action 'none'" in csp
    assert "frame-ancestors 'none'" in csp
    assert "unsafe-inline" not in csp
    assert PUBLIC_URL in response.text
    assert PUBLIC_KEY in response.text
    assert "never-render-this-secret" not in response.text
    assert "service_role" not in response.text.lower()


def test_recovery_page_rejects_query_tokens_without_reflecting_them(monkeypatch):
    _configure_public_auth(monkeypatch)
    token = "access-token-that-must-not-be-reflected"

    with TestClient(app) as client:
        response = client.get("/auth/reset-password?access_token=%s" % token)

    assert response.status_code == 400
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["referrer-policy"] == "no-referrer"
    assert token not in response.text
    assert token not in str(dict(response.headers))


def test_recovery_page_fails_closed_for_invalid_or_secret_like_public_config(monkeypatch):
    cases = [
        ("http://abcdefghijklmnopqrst.supabase.co", PUBLIC_KEY),
        ("https://user@abcdefghijklmnopqrst.supabase.co", PUBLIC_KEY),
        ("https://abcdefghijklmnopqrst.supabase.co/path", PUBLIC_KEY),
        ("https://abcdefghijklmnopqrst.supabase.co:invalid", PUBLIC_KEY),
        (PUBLIC_URL, "sb_secret_this_must_not_be_rendered"),
        (PUBLIC_URL, "service_role_this_must_not_be_rendered"),
    ]
    for url, key in cases:
        monkeypatch.setenv("SUPABASE_URL", url)
        monkeypatch.setenv("SUPABASE_PUBLISHABLE_KEY", key)
        monkeypatch.setenv("SUPABASE_SECRET_KEY", "server-only-secret")
        with TestClient(app) as client:
            response = client.get("/auth/reset-password")
        assert response.status_code == 503
        assert url not in response.text
        assert key not in response.text
        assert "server-only-secret" not in response.text


def test_recovery_assets_are_no_store_same_origin_assets(monkeypatch):
    _configure_public_auth(monkeypatch)
    with TestClient(app) as client:
        script = client.get("/auth/recovery/recovery.js")
        stylesheet = client.get("/auth/recovery/recovery.css")

    for response in [script, stylesheet]:
        assert response.status_code == 200
        assert response.headers["cache-control"] == "no-store"
        assert response.headers["referrer-policy"] == "no-referrer"
        assert response.headers["cross-origin-resource-policy"] == "same-origin"
        assert response.headers["x-content-type-options"] == "nosniff"
    assert "localStorage" not in script.text
    assert "sessionStorage" not in script.text
    assert "console." not in script.text
    assert "/auth/v1/user" in script.text
