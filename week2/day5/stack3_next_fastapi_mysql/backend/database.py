"""Async MySQL connection pool management."""
import aiomysql
import structlog
from contextlib import asynccontextmanager
from config import get_settings

logger = structlog.get_logger(__name__)
settings = get_settings()

# Module-level pool reference
_pool: aiomysql.Pool | None = None


async def create_pool() -> aiomysql.Pool:
    """Create and return the aiomysql connection pool."""
    global _pool
    _pool = await aiomysql.create_pool(
        host=settings.db_host,
        port=settings.db_port,
        user=settings.db_user,
        password=settings.db_password,
        db=settings.db_name,
        minsize=settings.db_pool_min,
        maxsize=settings.db_pool_max,
        pool_recycle=settings.db_pool_recycle,
        autocommit=True,
        charset="utf8mb4",
    )
    logger.info("Database pool created", minsize=settings.db_pool_min, maxsize=settings.db_pool_max)
    return _pool


async def close_pool() -> None:
    """Gracefully close the connection pool."""
    global _pool
    if _pool:
        _pool.close()
        await _pool.wait_closed()
        _pool = None
        logger.info("Database pool closed")


def get_pool() -> aiomysql.Pool:
    """Return the active pool — call after create_pool()."""
    if _pool is None:
        raise RuntimeError("Database pool is not initialized. Call create_pool() first.")
    return _pool


@asynccontextmanager
async def get_connection():
    """Async context manager: acquire a connection from the pool."""
    pool = get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor(aiomysql.DictCursor) as cursor:
            yield cursor


async def test_connection() -> bool:
    """Verify the pool can reach the database."""
    try:
        async with get_connection() as cur:
            await cur.execute("SELECT 1")
        return True
    except Exception as exc:
        logger.error("Database connectivity check failed", error=str(exc))
        return False


def get_pool_stats() -> dict:
    """Return pool size metrics."""
    pool = get_pool()
    return {
        "size": pool.size,
        "free_size": pool.freesize,
        "min_size": pool.minsize,
        "max_size": pool.maxsize,
    }