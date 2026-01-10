import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    CONTAINER_PREFIX: str = os.environ.get('CONTAINER_PREFIX', 'hub-')
    APP_NAME: str = os.environ.get('APP_NAME', 'privacy-hub')
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

    # Auth
    HUB_API_KEY: str | None = os.environ.get('HUB_API_KEY')
    ADMIN_PASS_RAW: str | None = os.environ.get('ADMIN_PASS_RAW')
    VPN_PASS_RAW: str | None = os.environ.get('VPN_PASS_RAW')

    class Config:
        env_file = ".env"

settings = Settings()
