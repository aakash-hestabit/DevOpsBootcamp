"""Application configuration via environment variables."""
from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    # Server
    app_env: str = "production"
    app_port: int = 8000
    app_workers: int = 4
    app_host: str = "0.0.0.0"
    app_version: str = "1.0.0"
    app_title: str = "FastAPI MySQL Products API"

    # Database
    db_host: str = "localhost"
    db_port: int = 3306
    db_name: str = "fastapidb"
    db_user: str = "fastapiuser"
    db_password: str

    # Connection Pool
    db_pool_min: int = 5
    db_pool_max: int = 20
    db_pool_recycle: int = 3600

    # Logging
    log_level: str = "INFO"
    log_dir: str = "../var/log/apps"

    class Config:
        env_file = ".env"
        case_sensitive = False


@lru_cache()
def get_settings() -> Settings:
    return Settings()