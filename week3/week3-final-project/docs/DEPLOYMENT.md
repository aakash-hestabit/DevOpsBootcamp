# Deployment Guide

## Prerequisites

- Docker Engine 24+
- Docker Compose v2
- 4 GB RAM minimum
- Ports available: 8081, 8443, 9090, 9091, 3001

## SSL/TLS Certificate

A self-signed certificate is included in `ssl/server.crt` and `ssl/server.key`. To regenerate:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ssl/server.key -out ssl/server.crt \
  -subj "/C=IN/ST=India/L=Bangalore/O=DevOps Bootcamp/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,DNS:frontend,IP:127.0.0.1"
```

To trust the certificate on your system and in Chrome:
```bash
sudo ./scripts/trust-ssl-cert.sh
```

## Development Deployment

```bash
./deploy.sh dev
```

This uses docker-compose.yml + docker-compose.dev.yml which enables:
- Hot reload for all services (volume mounts + reload commands)
- Database ports exposed (5432, 5433, 27017, 6379)
- Individual service ports exposed
- Relaxed resource limits (1 CPU, 512 MB per service)

## Production Deployment

```bash
./deploy.sh prod
```

This uses docker-compose.yml + docker-compose.prod.yml which enables:
- Strict resource limits and reservations
- Log rotation (10 MB max, 3 files)
- Restart policies (on-failure, max 3 attempts)
- No debug ports exposed

## Stopping

```bash
./deploy.sh down
```

## Other Commands

```bash
./deploy.sh restart    # Restart all services
./deploy.sh status     # Show running containers
```

## Backup

```bash
# Create a full backup (databases + configs)
./backup.sh

# List existing backups
./backup.sh --list

# Prune backups older than retention period (default 7 days)
./backup.sh --prune
```

Creates a timestamped backup in `./backups/` containing:
- Compressed PostgreSQL dumps (user-db.sql.gz, order-db.sql.gz)
- Compressed MongoDB archive (product-db.archive.gz)
- Configuration files (.env, docker-compose, monitoring, database init)
- SHA256 checksums for integrity verification

## Restore

```bash
# Restore from a backup directory
./backup.sh --restore backups/20260310_230607
```

Or manually restore individual databases:
```bash
# Restore user-db
gunzip -c backups/<timestamp>/user-db.sql.gz | docker compose exec -T user-db psql -U userservice userdb

# Restore order-db
gunzip -c backups/<timestamp>/order-db.sql.gz | docker compose exec -T order-db psql -U orderservice orderdb

# Restore product-db
gunzip -c backups/<timestamp>/product-db.archive.gz | docker compose exec -T product-db mongorestore --db productdb --archive
```

## Health Check

```bash
./scripts/health-check.sh
```

Checks all service endpoints, API routes, and monitoring services (Prometheus, Grafana, cAdvisor).

## Security Scan

```bash
./scripts/build-all.sh         # Build images first
./scripts/security-scan.sh     # Scan with Trivy
```

Reports saved to security/scan-reports/.

## End-to-End Tests

```bash
./scripts/test-all.sh
```

Runs smoke tests against all API endpoints and prints a pass/fail summary.

## Environment Variables

All configuration is in the `.env` file. See `.env.example` for reference.

Key variables:
- `FRONTEND_PORT`: External HTTP port for frontend (default: 8081)
- `FRONTEND_SSL_PORT`: External HTTPS port for frontend (default: 8443)
- `RATE_LIMIT`: API gateway rate limit per minute (default: 100)
- `USER_DB_PASSWORD`, `ORDER_DB_PASSWORD`: Database credentials
- `MONGO_INITDB_DATABASE`: MongoDB database name
- `REDIS_PORT`: Redis port (default: 6379)

## Rollback Procedure

1. Stop running services: `./deploy.sh down`
2. Restore previous images: `docker compose pull` (if using registry) or rebuild from previous tag
3. Restore database backups (see Restore section above)
4. Restart: `./deploy.sh prod`
