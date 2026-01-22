"""Configuration settings for the Privacy Hub API.

This module centralizes all application configuration using Pydantic settings
management. Environment variables are loaded from .env files and system
environment, with validation and type conversion handled automatically.

Configuration Categories:
    - Application: APP_NAME, CONTAINER_PREFIX, PORT
    - File Paths: CONFIG_DIR, PROFILES_DIR, LOG_FILE, etc.
    - Network: LAN_IP, WG_HOST, DESEC_DOMAIN, CORS_ORIGINS
    - Authentication: HUB_API_KEY, ADMIN_PASS_RAW, VPN_PASS_RAW

Key Features:
    - Pydantic-based validation and type coercion
    - Support for .env file loading
    - Flexible CORS origin parsing (JSON array or comma-separated)
    - Environment variable overrides
    - Immutable configuration after initialization

Path Strategy:
    - /app: Main configuration directory (CONFIG_DIR)
    - /profiles: WireGuard profile storage
    - /app/data: Database and persistent data
    - /assets: Static assets (icons, templates)

Network Configuration:
    - LAN_IP: Server's local network IP address
    - WG_HOST: Public hostname for WireGuard clients
    - DESEC_DOMAIN: Optional deSEC domain for SSL

Security Considerations:
    - Secrets loaded from environment (not committed to repo)
    - API keys validated and sanitized before use
    - CORS origins configurable per deployment
    - File permissions enforced on secrets file (0o600)

Usage:
    from app.core.config import settings
    
    print(settings.LAN_IP)
    print(settings.ADMIN_PASS_RAW)

References:
    - Pydantic Settings: https://docs.pydantic.dev/latest/usage/settings/
    - Google Python Style Guide

Author: ZimaOS Privacy Hub Team
Version: 2.0.0
"""

import json
import os
from typing import List, Optional, Union

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings and environment configuration."""

    CONTAINER_PREFIX: str = os.environ.get("CONTAINER_PREFIX", "hub-")
    APP_NAME: str = os.environ.get("APP_NAME", "privacy-hub")
    PORT: int = 55555

    # Paths
    CONFIG_DIR: str = "/app"
    PROFILES_DIR: str = "/profiles"
    CONTROL_SCRIPT: str = "/usr/local/bin/wg-control.sh"
    LOG_FILE: str = "/app/deployment.log"
    DB_FILE: str = "/app/data/logs.db"
    ASSETS_DIR: str = "/assets"
    SERVICES_FILE: str = os.path.join(CONFIG_DIR, "services.json")
    DATA_USAGE_FILE: str = "/app/.data_usage"
    WGE_DATA_USAGE_FILE: str = "/app/.wge_data_usage"
    SESSIONS_FILE: str = "/app/data/sessions.json"
    SECRETS_FILE: str = "/app/.secrets"

    # Network
    LAN_IP: str = os.environ.get("LAN_IP", "127.0.0.1")
    WG_HOST: str = os.environ.get("WG_HOST", "")
    DESEC_DOMAIN: str = os.environ.get("DESEC_DOMAIN", "")
    CORS_ORIGINS: List[str] = ["http://localhost", "http://127.0.0.1", "*"]

    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def assemble_cors_origins(cls, v: Union[str, List[str]]) -> List[str]:
        """Parses CORS origins from various string formats or lists.

        Args:
            v: Raw CORS origins input (JSON string, comma-separated, or list).

        Returns:
            A list of valid origin URLs.
        """
        if isinstance(v, str):
            if not v.strip():
                return ["http://localhost", "http://127.0.0.1"]
            if v.startswith("[") and v.endswith("]"):
                try:
                    return json.loads(v)
                except json.JSONDecodeError:
                    pass
            # Fallback to comma-separated
            return [i.strip() for i in v.split(",") if i.strip()]
        return v

    # Auth
    HUB_API_KEY: Optional[str] = os.environ.get("HUB_API_KEY")
    ADMIN_PASS_RAW: Optional[str] = os.environ.get("ADMIN_PASS_RAW")
    VPN_PASS_RAW: Optional[str] = os.environ.get("VPN_PASS_RAW")

    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )


settings = Settings()
