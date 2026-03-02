import logging
import os
import time
from contextlib import asynccontextmanager
from pathlib import Path

import structlog
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from config import get_settings
from database import create_pool, close_pool, test_connection, get_pool_stats
from routers import products

settings = get_settings()

#  Structured Logging Setup 
log_dir = Path(settings.log_dir)
log_dir.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=getattr(logging, settings.log_level),
    format="%(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(log_dir / "fastapi-access.log"),
    ],
)

structlog.configure(
    wrapper_class=structlog.make_filtering_bound_logger(getattr(logging, settings.log_level)),
    logger_factory=structlog.PrintLoggerFactory(),
)

logger = structlog.get_logger(__name__)

# Track server start time for uptime reporting
START_TIME = time.time()


#  Lifespan: startup/shutdown 
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting FastAPI application", version=settings.app_version)
    await create_pool()
    yield
    logger.info("Shutting down FastAPI application")
    await close_pool()


# App Factory 
app = FastAPI(
    title=settings.app_title,
    version=settings.app_version,
    description="FastAPI application with MySQL and Supervisor process management",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Health Check 
@app.get("/health", tags=["Health"], summary="Service health check")
async def health_check():
    db_connected = await test_connection()
    pool_stats = get_pool_stats()
    uptime = int(time.time() - START_TIME)

    payload = {
        "status": "healthy" if db_connected else "unhealthy",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "uptime": uptime,
        "database": {
            "status": "connected" if db_connected else "disconnected",
            "pool": pool_stats,
        },
        "environment": settings.app_env,
        "version": settings.app_version,
    }
    return JSONResponse(content=payload, status_code=200 if db_connected else 503)


#  Routers 
app.include_router(products.router)


if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host=settings.app_host,
        port=settings.app_port,
        workers=settings.app_workers,
        log_level=settings.log_level.lower(),
        access_log=True,
    )