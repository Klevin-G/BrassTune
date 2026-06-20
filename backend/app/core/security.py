import os
from typing import List


LOCAL_FRONTEND_ORIGINS = ["http://localhost:5173", "http://127.0.0.1:5173"]
AUTH_MODES = {"disabled", "supabase"}
LOCAL_ENVIRONMENTS = {"local", "test", "development", "dev"}
DEPLOYED_ENVIRONMENTS = {"production", "staging", "preview"}
APP_ENVIRONMENTS = LOCAL_ENVIRONMENTS | DEPLOYED_ENVIRONMENTS


def app_environment() -> str:
    environment = os.getenv("APP_ENV", "production").strip().lower()
    if environment not in APP_ENVIRONMENTS:
        raise RuntimeError("APP_ENV must be one of: dev, development, local, preview, production, staging, test.")
    return environment


def auth_mode() -> str:
    configured = os.getenv("BRASSTUNE_AUTH_MODE")
    if configured:
        mode = configured.strip().lower()
        if mode not in AUTH_MODES:
            raise RuntimeError("BRASSTUNE_AUTH_MODE must be one of: disabled, supabase.")
        return mode
    if app_environment() in DEPLOYED_ENVIRONMENTS:
        raise RuntimeError("BRASSTUNE_AUTH_MODE must be set to disabled or supabase when APP_ENV=production.")
    return "disabled"


def allowed_origins() -> List[str]:
    configured = os.getenv("CORS_ALLOWED_ORIGINS") or os.getenv("FRONTEND_ORIGIN")
    origins = [] if app_environment() in DEPLOYED_ENVIRONMENTS else list(LOCAL_FRONTEND_ORIGINS)
    if configured:
        origins.extend([item.strip() for item in configured.split(",") if item.strip()])
    return sorted(set(origins))
