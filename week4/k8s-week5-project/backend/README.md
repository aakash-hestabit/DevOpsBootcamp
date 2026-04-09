# Backend

- Health endpoint (`/health`) - Backend status
- Ready endpoint (`/ready`) - Database connectivity check
- PostgreSQL connection pooling
- CORS enabled
- Environment variable configuration


The backend runs on `http://localhost:9000`

### Environment Variables

```
PORT=8000
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=postgres
NODE_ENV=development
```

## API Endpoints

### GET /
Root endpoint - Returns API info

```json
{
  "message": "K8s Backend API",
  "version": "1.0.0",
  "endpoints": {
    "health": "/health",
    "ready": "/ready"
  }
}
```

### GET /health
Backend health status

```json
{
  "status": "healthy",
  "message": "Backend is up and running",
  "timestamp": "2026-02-16T10:30:00.000Z"
}
```

### GET /ready
Database readiness check

```json
{
  "status": "connected",
  "message": "Database connection successful",
  "database": "postgres",
  "host": "localhost",
  "timestamp": "2026-02-16T10:30:00.000Z"
}
```