# Health Check Endpoints Reference

All applications expose a `/health` (or `/api/health`) endpoint that returns service status,
database connectivity, and runtime metrics. These endpoints are used by monitoring scripts,
load balancers, and uptime checkers.

---

## Express PostgreSQL API — `GET http://localhost:3000/api/health`

**When healthy (200):**
```json
{
  "status": "healthy",
  "timestamp": "2026-01-27T17:00:00Z",
  "uptime": 3600,
  "database": {
    "status": "connected",
    "pool": { "total": 10, "idle": 8, "active": 2 }
  },
  "environment": "production",
  "version": "1.0.0"
}
```

**When unhealthy (503):** same body but `"status": "unhealthy"` and `"database": { "status": "disconnected" }`.

```bash
curl -s http://localhost:3000/api/health | jq .
```

---

## FastAPI MySQL API — `GET http://localhost:8000/health`

**When healthy (200):**
```json
{
  "status": "healthy",
  "timestamp": "2026-01-27T17:00:00Z",
  "uptime": 1200,
  "database": {
    "status": "connected",
    "pool": { "size": 10, "free_size": 8, "min_size": 5, "max_size": 20 }
  },
  "environment": "production",
  "version": "1.0.0"
}
```

```bash
curl -s http://localhost:8000/health | python3 -m json.tool
```

---

## Laravel MySQL API — `GET http://localhost:8880/api/health`

**When healthy (200):**
```json
{
  "status": "healthy",
  "timestamp": "2026-01-27T17:00:00+00:00",
  "uptime": 45,
  "database": { "status": "connected", "driver": "mysql" },
  "environment": "production",
  "version": "1.0.0"
}
```

```bash
curl -s http://localhost:8880/api/health | jq .
```

---

## Next.js App — `GET http://localhost:3001/api/health`

```json
{
  "status": "healthy",
  "timestamp": "2026-01-27T17:00:00.000Z",
  "uptime": 7200,
  "database": { "status": "connected", "pool": { "total": 5, "idle": 4, "active": 1 } },
  "environment": "production",
  "version": "1.0.0"
}
```

```bash
curl -s http://localhost:3001/api/health | jq .
```

---

## Health Check Criteria

| Check | Healthy | Unhealthy |
|-------|---------|-----------|
| HTTP status code | 200 | 503 |
| Database status | "connected" | "disconnected" |
| Response time | < 500ms | > 1000ms |
| Pool active slots | < 90% of max | ≥ 90% of max |

---

## Monitoring Integration

### Cron-based (every 5 minutes)
```bash
*/5 * * * * /path/to/day4/scripts/app_monitor.sh --email aakash@hestabit.in
```

### Nginx upstream health probe
```nginx
location /health-probe {
    proxy_pass http://127.0.0.1:3000/api/health;
    access_log off;
}
```