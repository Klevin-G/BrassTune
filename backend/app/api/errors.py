from typing import Any, Optional

from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse


ERROR_CODES_BY_STATUS = {
    400: "bad_request",
    401: "authentication_required",
    403: "permission_denied",
    404: "not_found",
    405: "method_not_allowed",
    409: "conflict",
    410: "resource_gone",
    413: "payload_too_large",
    415: "unsupported_media_type",
    422: "request_validation_failed",
    423: "account_locked",
    429: "rate_limited",
    500: "internal_error",
    502: "upstream_failure",
    503: "service_unavailable",
}


def error_code_for_status(status_code: int) -> str:
    """Return the stable, intentionally coarse public code for an HTTP status."""
    return ERROR_CODES_BY_STATUS.get(status_code, "request_failed")


def error_payload(status_code: int, detail: Any, *, code: Optional[str] = None) -> dict:
    """Keep FastAPI's existing ``detail`` contract and add a stable code."""
    return {
        "detail": jsonable_encoder(detail),
        "code": code or error_code_for_status(status_code),
    }


def client_error_response(
    status_code: int,
    detail: Any,
    *,
    code: Optional[str] = None,
    headers: Optional[dict] = None,
) -> JSONResponse:
    return JSONResponse(
        error_payload(status_code, detail, code=code),
        status_code=status_code,
        headers=headers,
    )
