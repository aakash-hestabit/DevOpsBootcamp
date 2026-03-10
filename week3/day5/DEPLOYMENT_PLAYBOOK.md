# Production Deployment Playbook

## Pre-Deployment Checklist

- **[ ] All tests passing in CI/CD**
  Every automated test (unit, integration, end-to-end) must be green before the deployment proceeds — a single failure means the build is not release-ready.

- **[ ] Security scan completed (no CRITICAL)**
  Run Trivy or equivalent against all built images and confirm zero CRITICAL-severity CVEs; HIGH findings should be reviewed and documented.

- **[ ] Database migrations reviewed and tested**
  Every new migration script should be read by a second engineer and dry-run against a staging database so schema changes do not break production data.

- **[ ] Full system backup completed**
  Run `./backup-docker-system.sh` and verify the manifest shows all volumes, images, and configs archived — this is the rollback safety net.

- **[ ] Team notified of upcoming deployment**
  Post in the team channel with the expected start time, duration, and a brief change summary so no one is surprised if services restart.

- **[ ] Maintenance window scheduled**
  Confirm the window is recorded in the shared calendar and any external status page is updated to reflect the planned maintenance period.

- **[ ] Rollback plan documented and rehearsed**
  The engineer performing the deploy should be able to describe the rollback steps from memory; the `rollback.sh` or restore script must be tested in staging.

- **[ ] Monitoring and alerting confirmed operational**
  Open the Grafana dashboard and Prometheus targets page to confirm all scrapers are UP and alert rules are active before the deploy begins.

---

## Deployment Steps

### 1. Backup Current System

Run the full system backup and verify the manifest before touching anything.

```bash
./backup-docker-system.sh
cat /backup/docker/$(ls -t /backup/docker | head -1)/manifest.txt
```

### 2. Pull Latest Code

Fetch the latest changes from the main branch into the project directory.

```bash
cd /opt/apps/myapp
git pull origin main
```

### 3. Build New Images

Rebuild all service images using the production compose file to pick up code and dependency changes.

```bash
docker compose -f docker-compose.prod.yml build --no-cache
```

### 4. Run Database Migrations

Execute pending migrations in a one-off container to update the schema before the new application code starts.

```bash
docker compose -f docker-compose.prod.yml run --rm api npm run migrate
```

### 5. Deploy Application

Start (or recreate) all services and remove any containers that are no longer defined in compose.

```bash
docker compose -f docker-compose.prod.yml up -d --remove-orphans
```

### 6. Verify Deployment

Confirm every service is running and responding as expected immediately after the deploy.

```bash
# Check service status
docker compose -f docker-compose.prod.yml ps

# Tail recent logs for errors
docker compose -f docker-compose.prod.yml logs --tail=50

# Hit health and status endpoints
curl -f http://localhost/health
curl -f http://localhost/api/status
```

---

## Post-Deployment Verification

- **[ ] All services report healthy status**
  `docker compose ps` should show every container as `Up` with `(healthy)` if a HEALTHCHECK is defined — any `unhealthy` or `restarting` state is a blocker.

- **[ ] Health endpoints returning 200**
  `curl -f` against `/health` and `/api/status` must return HTTP 200; a non-200 means the application did not start correctly.

- **[ ] Database connections working**
  Verify the API can query the database by hitting a data-dependent endpoint or running a quick `SELECT 1` through the app's DB connection.

- **[ ] No error-level log entries**
  Scan the last 100 lines of each service log (`docker compose logs --tail=100`) for `ERROR`, `FATAL`, or stack traces that indicate a startup or runtime failure.

- **[ ] Monitoring dashboards showing normal metrics**
  Open the Grafana "Container Monitoring" dashboard and confirm CPU, memory, and network panels are plotting data within expected baselines.

- **[ ] Resource usage within expected limits**
  Run `docker stats --no-stream` and confirm no container is using more CPU or memory than its resource limits allow.

- **[ ] User acceptance testing passed**
  Have a team member (or automated smoke test) walk through the core user flows — login, data retrieval, create/update operations — and confirm correct behaviour.

---

## Rollback Procedure

Use this procedure if any post-deployment check fails or critical errors are detected.

### 1. Stop New Containers

Bring down all services started by the latest deployment.

```bash
docker compose -f docker-compose.prod.yml down
```

### 2. Restore from Backup

Run the restore script with the backup timestamp directory to recover volumes, configs, and images.

```bash
# List available backups
ls -lt /backup/docker/

# Restore the most recent backup
./restore-docker-system.sh <backup-date>
```

### 3. Start Previous Version

Bring the services back up — Docker will use the restored images and configuration.

```bash
docker compose -f docker-compose.prod.yml up -d
```

### 4. Verify Rollback

Confirm the system is back to its pre-deployment state and all services are healthy.

```bash
docker compose -f docker-compose.prod.yml ps
curl -f http://localhost/health
docker compose -f docker-compose.prod.yml logs --tail=20
```

### 5. Post-Rollback Actions

- Notify the team that the deployment was rolled back and services are restored.
- Create an incident report documenting the failure reason and the timeline.
- Fix the root cause in a development environment before attempting another deployment.
