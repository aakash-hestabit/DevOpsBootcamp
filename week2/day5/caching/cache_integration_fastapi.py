"""
Redis Cache Integration for Stack 3 (FastAPI + MySQL)

File: caching/cache_integration_fastapi.py

Install:
    cd stack3_next_fastapi_mysql/backend
    source venv/bin/activate
    pip install aioredis

Usage: Import the cache decorator or Redis client into your FastAPI routes.

Redis DB: 2 (Stack 3 dedicated)
"""

import json
import hashlib
import functools
from typing import Optional, Any, Callable
from datetime import timedelta

import aioredis
from fastapi import Request, Response

# ---------------------------------------------------------------------------
# Redis client singleton
# ---------------------------------------------------------------------------

REDIS_URL = "redis://127.0.0.1:6379/2"  # DB 2 for Stack 3
REDIS_PASSWORD = "DevOpsRedis@123"

_redis_pool: Optional[aioredis.Redis] = None


async def get_redis() -> aioredis.Redis:
    """Get or create the Redis connection pool."""
    global _redis_pool
    if _redis_pool is None:
        _redis_pool = aioredis.from_url(
            REDIS_URL,
            password=REDIS_PASSWORD,
            encoding="utf-8",
            decode_responses=True,
            max_connections=20,
        )
    return _redis_pool


async def close_redis():
    """Close Redis connection pool (call on app shutdown)."""
    global _redis_pool
    if _redis_pool:
        await _redis_pool.close()
        _redis_pool = None


# ---------------------------------------------------------------------------
# Cache decorator for route handlers
# ---------------------------------------------------------------------------

def cached(prefix: str = "stack3", ttl: int = 300):
    """
    Decorator to cache FastAPI route responses in Redis.

    Args:
        prefix: Redis key prefix (e.g., "stack3:products")
        ttl: Time-to-live in seconds (default: 300)

    Usage:
        @app.get("/api/products")
        @cached(prefix="stack3:products", ttl=300)
        async def list_products():
            return await db.fetch_all("SELECT * FROM products")
    """
    def decorator(func: Callable):
        @functools.wraps(func)
        async def wrapper(*args, **kwargs):
            try:
                redis = await get_redis()

                # Build cache key from function name + args
                key_data = f"{func.__name__}:{str(args)}:{str(sorted(kwargs.items()))}"
                cache_key = f"{prefix}:{hashlib.md5(key_data.encode()).hexdigest()}"

                # Check cache
                cached_value = await redis.get(cache_key)
                if cached_value is not None:
                    return json.loads(cached_value)

                # Execute function
                result = await func(*args, **kwargs)

                # Store in cache
                await redis.setex(cache_key, ttl, json.dumps(result, default=str))

                return result

            except Exception as e:
                # On Redis failure, execute function without cache
                print(f"[Redis] Cache error: {e}")
                return await func(*args, **kwargs)

        return wrapper
    return decorator


# ---------------------------------------------------------------------------
# Cache invalidation helpers
# ---------------------------------------------------------------------------

async def invalidate_pattern(pattern: str):
    """Delete all keys matching a pattern."""
    try:
        redis = await get_redis()
        keys = []
        async for key in redis.scan_iter(match=pattern):
            keys.append(key)
        if keys:
            await redis.delete(*keys)
            print(f"[Redis] Invalidated {len(keys)} keys matching: {pattern}")
    except Exception as e:
        print(f"[Redis] Invalidation error: {e}")


async def invalidate_products():
    """Invalidate all product-related caches."""
    await invalidate_pattern("stack3:products:*")


# ---------------------------------------------------------------------------
# FastAPI middleware for HTTP cache headers
# ---------------------------------------------------------------------------

async def cache_headers_middleware(request: Request, call_next):
    """Add Cache-Control and ETag headers to GET responses."""
    response: Response = await call_next(request)

    if request.method == "GET" and response.status_code == 200:
        # Read body for ETag computation
        body = b""
        async for chunk in response.body_iterator:
            body += chunk if isinstance(chunk, bytes) else chunk.encode()

        etag = hashlib.md5(body).hexdigest()
        response.headers["ETag"] = f'"{etag}"'
        response.headers["Cache-Control"] = "public, max-age=60"

        # Return new response with body
        from starlette.responses import Response as StarletteResponse
        return StarletteResponse(
            content=body,
            status_code=response.status_code,
            headers=dict(response.headers),
        )

    return response


# ---------------------------------------------------------------------------
# FastAPI app integration example
# ---------------------------------------------------------------------------
#
# from fastapi import FastAPI
# from cache_integration_fastapi import (
#     get_redis, close_redis, cached, invalidate_products, cache_headers_middleware
# )
#
# app = FastAPI()
#
# # Register middleware
# app.middleware("http")(cache_headers_middleware)
#
# # Startup/shutdown
# @app.on_event("startup")
# async def startup():
#     await get_redis()
#
# @app.on_event("shutdown")
# async def shutdown():
#     await close_redis()
#
# # Cached endpoint
# @app.get("/api/products")
# @cached(prefix="stack3:products", ttl=300)
# async def list_products(db = Depends(get_db)):
#     rows = await db.fetch_all("SELECT * FROM products")
#     return {"status": "ok", "data": [dict(row) for row in rows]}
#
# # Write endpoint with cache invalidation
# @app.post("/api/products")
# async def create_product(product: ProductCreate, db = Depends(get_db)):
#     await db.execute("INSERT INTO products ...")
#     await invalidate_products()
#     return {"status": "ok"}
