# express-postgresql-api

Production-ready REST API for user management built with Express.js and PostgreSQL.

## Features
- Full User CRUD with pagination
- PostgreSQL connection pooling (pg.Pool)
- Input validation (express-validator)
- Structured logging (winston + daily rotation)
- Request logging (morgan)
- Swagger/OpenAPI docs at `/api-docs`
- Rate limiting, CORS, Helmet security headers
- Health check endpoint
- Graceful shutdown

## Quick Start

```bash
# 1. Install dependencies
npm install

# 2. Set up environment
cp env.example.txt .env
# Edit .env with your DB credentials

# 3. Run database migration
psql -h localhost -U apiuser -d apidb -f migrations/001_create_users_table.sql

# 4. Start server
npm start          # production
npm run dev        # development (nodemon)
```

## API Endpoints

| Method | Endpoint         | Description        |
|--------|------------------|--------------------|
| GET    | /api/health      | Health check       |
| GET    | /api/users       | List users         |
| GET    | /api/users/:id   | Get user           |
| POST   | /api/users       | Create user        |
| PUT    | /api/users/:id   | Update user        |
| DELETE | /api/users/:id   | Delete user        |
| GET    | /api-docs        | Swagger UI         |

## Health Check Response

```json
{
  "status": "healthy",
  "timestamp": "2026-01-27T17:00:00Z",
  "uptime": 3600,
  "database": { "status": "connected", "pool": { "total": 10, "idle": 8, "active": 2 } },
  "environment": "production",
  "version": "1.0.0"
}
```

## Process Management
```bash
# PM2 (from project root)
pm2 start ecosystem.config.js --only express-api
pm2 logs express-api
pm2 monit
```

## Logs
- `var/log/apps/express-api-combined-YYYY-MM-DD.log`
- `var/log/apps/express-api-error-YYYY-MM-DD.log`