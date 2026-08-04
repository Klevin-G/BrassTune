import json

import app.api.auth as auth_module
import app.services.audio_storage as audio_storage_module


class _Response:
    def __init__(self, payload=None):
        self.payload = payload if payload is not None else {}

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return json.dumps(self.payload).encode("utf-8")


def test_audio_storage_secret_key_is_sent_only_as_apikey(monkeypatch):
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "sb_secret_test_audio_storage_only")

    assert audio_storage_module._supabase_headers("audio/webm") == {
        "apikey": "sb_secret_test_audio_storage_only",
        "Content-Type": "audio/webm",
    }


def test_user_validation_and_global_sign_out_preserve_user_bearer_token(monkeypatch):
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "sb_secret_test_auth_only")
    monkeypatch.setenv("SUPABASE_URL", "https://project.supabase.co")
    observed = []

    def fake_urlopen(request, timeout):
        observed.append((request.full_url, request.get_method(), dict(request.headers), timeout))
        return _Response({"id": "user-123"})

    monkeypatch.setattr(auth_module.urllib.request, "urlopen", fake_urlopen)

    assert auth_module._fetch_supabase_user("user-session-jwt") == {"id": "user-123"}
    assert auth_module.supabase_global_sign_out("user-session-jwt") is True

    assert observed == [
        (
            "https://project.supabase.co/auth/v1/user",
            "GET",
            {"Apikey": "sb_secret_test_auth_only", "Authorization": "Bearer user-session-jwt"},
            10,
        ),
        (
            "https://project.supabase.co/auth/v1/logout?scope=global",
            "POST",
            {
                "Apikey": "sb_secret_test_auth_only",
                "Authorization": "Bearer user-session-jwt",
                "Content-type": "application/json",
            },
            10,
        ),
    ]


def test_identity_deletion_sends_secret_only_as_apikey(monkeypatch):
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "sb_secret_test_admin_only")
    monkeypatch.setenv("SUPABASE_URL", "https://project.supabase.co")
    observed = {}

    def fake_urlopen(request, timeout):
        observed.update(
            url=request.full_url,
            method=request.get_method(),
            headers=dict(request.headers),
            timeout=timeout,
        )
        return _Response()

    monkeypatch.setattr(auth_module.urllib.request, "urlopen", fake_urlopen)

    assert auth_module.delete_supabase_identity("user/id") is True
    assert observed == {
        "url": "https://project.supabase.co/auth/v1/admin/users/user%2Fid",
        "method": "DELETE",
        "headers": {"Apikey": "sb_secret_test_admin_only"},
        "timeout": 10,
    }
