"""
Actual pool management is in fastapi-mysql-api/database.py
"""
import os
import aiomysql
from contextlib import asynccontextmanager

pool_config = {
    "host":         os.getenv("DB_HOST", "localhost"),
    "port":         int(os.getenv("DB_PORT", "3306")),
    "user":         os.getenv("DB_USER"),
    "password":     os.getenv("DB_PASSWORD"),
    "db":           os.getenv("DB_NAME"),
    "minsize":      5,       # keep 5 connections warm at all times
    "maxsize":      20,      # max concurrent connections
    "pool_recycle": 3600,    # recycle connections after 1 hour to avoid stale connections
    "autocommit":   True,
    "charset":      "utf8mb4",
}


@asynccontextmanager
async def get_db_pool():
    """Context manager that creates and tears down the pool."""
    pool = await aiomysql.create_pool(**pool_config)
    try:
        yield pool
    finally:
        pool.close()
        await pool.wait_closed()