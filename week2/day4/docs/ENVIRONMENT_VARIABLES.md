# Environment Variables Reference

Each project uses a `.env` file. Start from the `env.example.txt` in each project directory.

---

## Express PostgreSQL API (`express-postgresql-api/.env`)

| Variable | Default | Description |
|----------|---------|-------------|
| `NODE_ENV` | `production` | Runtime environment |
| `PORT` | `3000` | HTTP port |
| `DB_HOST` | `localhost` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_NAME` | `apidb` | Database name |
| `DB_USER` | `apiuser` | Database user |
| `DB_PASSWORD` | *(required)* | Database password |
| `DB_POOL_MAX` | `20` | Max pool connections |
| `DB_POOL_MIN` | `5` | Min pool connections |
| `LOG_LEVEL` | `info` | Winston log level |
| `LOG_DIR` | `../var/log/apps` | Log output directory |
| `RATE_LIMIT_WINDOW_MS` | `900000` | Rate limit window (15min) |
| `RATE_LIMIT_MAX_REQUESTS` | `100` | Max requests per window |
| `APP_VERSION` | `1.0.0` | Reported in health check |

---

## FastAPI MySQL API (`fastapi-mysql-api/.env`)

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_ENV` | `production` | Runtime environment |
| `APP_PORT` | `8000` | Uvicorn listen port |
| `APP_WORKERS` | `4` | Number of uvicorn workers |
| `DB_HOST` | `localhost` | MySQL host |
| `DB_PORT` | `3306` | MySQL port |
| `DB_NAME` | `fastapidb` | Database name |
| `DB_USER` | `fastapiuser` | Database user |
| `DB_PASSWORD` | *(required)* | Database password |
| `DB_POOL_MIN` | `5` | Min pool size |
| `DB_POOL_MAX` | `20` | Max pool size |
| `LOG_LEVEL` | `INFO` | Log level |
| `LOG_DIR` | `../var/log/apps` | Log directory |

---

## Laravel MySQL API (`laravel-mysql-api/.env`)

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_ENV` | `production` | Laravel environment |
| `APP_KEY` | *(generate)* | Laravel 32-byte key (`php artisan key:generate`) |
| `APP_DEBUG` | `false` | Show error details |
| `DB_CONNECTION` | `mysql` | Database driver |
| `DB_HOST` | `127.0.0.1` | MySQL host |
| `DB_PORT` | `3306` | MySQL port |
| `DB_DATABASE` | `laraveldb` | Database name |
| `DB_USERNAME` | `laraveluser` | Database user |
| `DB_PASSWORD` | *(required)* | Database password |
| `QUEUE_CONNECTION` | `database` | Queue driver |
| `LOG_CHANNEL` | `daily` | Log channel |
| `LOG_LEVEL` | `error` | Minimum log severity |

---

## Next.js App (`nextjs-fullstack-app/.env.local`)

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3001` | Next.js port |
| `NODE_ENV` | `production` | Runtime environment |
| `DB_HOST` | `localhost` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_NAME` | `apidb` | Database name |
| `DB_USER` | `apiuser` | Database user |
| `DB_PASSWORD` | *(required)* | Database password |
| `DB_POOL_MAX` | `10` | Max pool connections |
| `NEXT_PUBLIC_APP_NAME` | `NextJS Fullstack App` | Displayed in UI |
| `NEXT_PUBLIC_API_BASE_URL` | `http://localhost:3001` | Client-side base URL |

---
