"""Isolated browser password recovery surface.

The backend only serves public Supabase configuration and static recovery
assets. Recovery credentials live in the URL fragment, which browsers do not
send in HTTP requests, and are submitted directly from the browser to
Supabase. This module must never accept, proxy, or log a recovery token.
"""

from __future__ import annotations

import html
import json
import os
import re
from pathlib import Path
from urllib.parse import urlsplit

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, PlainTextResponse, Response


router = APIRouter()

_STATIC_DIRECTORY = Path(__file__).resolve().parents[1] / "static" / "recovery"
_PUBLISHABLE_KEY_RE = re.compile(r"^sb_publishable_[A-Za-z0-9_-]{20,}$")


def _safe_public_supabase_config() -> tuple[str, str] | None:
    """Return only a validated public Auth origin and publishable key.

    This deliberately reads neither the Supabase secret key nor any service
    role fallback. A recovery page can authenticate its own short-lived
    recovery session directly with the public API.
    """

    raw_url = (os.getenv("SUPABASE_URL") or "").strip()
    publishable_key = (os.getenv("SUPABASE_PUBLISHABLE_KEY") or "").strip()
    try:
        parsed = urlsplit(raw_url)
        port = parsed.port
    except ValueError:
        return None
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or port is not None
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
        or not parsed.hostname.endswith(".supabase.co")
        or not _PUBLISHABLE_KEY_RE.fullmatch(publishable_key)
    ):
        return None
    return (f"https://{parsed.hostname}", publishable_key)


def _base_headers(*, csp: str | None = None) -> dict[str, str]:
    headers = {
        "Cache-Control": "no-store",
        "Pragma": "no-cache",
        "Referrer-Policy": "no-referrer",
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "Cross-Origin-Resource-Policy": "same-origin",
        "Cross-Origin-Opener-Policy": "same-origin",
        "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=()",
        "X-Robots-Tag": "noindex, nofollow",
    }
    if csp is not None:
        headers["Content-Security-Policy"] = csp
    return headers


def _static_asset(name: str, media_type: str) -> Response:
    path = _STATIC_DIRECTORY / name
    return Response(
        path.read_bytes(),
        media_type=media_type,
        headers=_base_headers(),
    )


def _recovery_unavailable() -> PlainTextResponse:
    return PlainTextResponse(
        "Password recovery is unavailable right now. Request a new recovery email and try again later.",
        status_code=503,
        headers=_base_headers(),
    )


async def _recovery_page(request: Request) -> Response:
    # A correct Supabase recovery URL uses a fragment, never a query string.
    # Do not reflect a malformed query; this also keeps recovery credentials
    # out of the page body and application-level logs.
    if request.scope.get("query_string"):
        return PlainTextResponse(
            "This recovery link is invalid. Request a new recovery email.",
            status_code=400,
            headers=_base_headers(),
        )
    config = _safe_public_supabase_config()
    if config is None:
        return _recovery_unavailable()
    supabase_url, publishable_key = config
    page_config = json.dumps(
        {"supabaseUrl": supabase_url, "publishableKey": publishable_key},
        separators=(",", ":"),
    ).replace("<", "\\u003c")
    document = (_STATIC_DIRECTORY / "index.html").read_text(encoding="utf-8")
    document = document.replace("__RECOVERY_PUBLIC_CONFIG__", html.escape(page_config, quote=False))
    csp = (
        "default-src 'none'; script-src 'self'; style-src 'self'; "
        f"connect-src {supabase_url}; form-action 'none'; base-uri 'none'; "
        "frame-ancestors 'none'"
    )
    return HTMLResponse(document, headers=_base_headers(csp=csp))


@router.get("/auth/reset-password", include_in_schema=False)
async def get_password_recovery(request: Request) -> Response:
    return await _recovery_page(request)


@router.get("/auth/reset-password/", include_in_schema=False)
async def get_password_recovery_with_slash(request: Request) -> Response:
    return await _recovery_page(request)


@router.get("/auth/recovery/recovery.js", include_in_schema=False)
async def get_password_recovery_script() -> Response:
    return _static_asset("recovery.js", "text/javascript")


@router.get("/auth/recovery/recovery.css", include_in_schema=False)
async def get_password_recovery_styles() -> Response:
    return _static_asset("recovery.css", "text/css")
