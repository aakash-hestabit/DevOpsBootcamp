# Deployment Guide

## Architecture Overview

Three production-grade full-stack applications deployed on a single Ubuntu server with Nginx load balancing, process management, and database replication.

### Stack 1 — Next.js + Express.js + MongoDB Replica Set

| Component | Technology | Ports | Process Manager |
|-----------|-----------|-------|----------------|
| Frontend | Next.js SSR | 3001, 3002 | PM2 (fork) |
| Backend | Express.js API | 3000, 3003, 3004 | PM2 (cluster) |
| Database | MongoDB 3-node RS | 27017, 27018, 27019 | systemd (mongod) |
| Proxy | Nginx | 80/443 | systemd |

**Domain:** `stack1.devops.local`

### Stack 2 — Laravel + MySQL Master-Slave

| Component | Technology | Ports | Process Manager |
|-----------|-----------|-------|----------------|
| Backend | Laravel (PHP-FPM) | 8000, 8001, 8002 | systemd |
| Queue Workers | Laravel Queue | — | systemd (x2) |
| Scheduler | Laravel Scheduler | — | systemd |
| Database Master | MySQL 8.0 | 3306 | systemd |
| Database Slave | MySQL 8.0 | 3307 | systemd |
| Proxy | Nginx | 80/443 | systemd |

**Domain:** `stack2.devops.local`

### Stack 3 — Next.js + FastAPI + MySQL

| Component | Technology | Ports | Process Manager |
|-----------|-----------|-------|----------------|
| Frontend | Next.js SSR | 3005, 3006 | PM2 (fork) |
| Backend | FastAPI/uvicorn | 8003, 8004, 8005 | systemd |
| Database | MySQL 8.0 | 3306 | systemd |
| Proxy | Nginx | 80/443 | systemd |

**Domain:** `stack3.devops.local`

---

## Prerequisites

- Ubuntu 22.04 LTS
- Root or sudo access
- Node.js 20.x LTS, PHP 8.2+, Python 3.11+
- Nginx, MySQL 8.0, MongoDB 7.0, Redis 7.x
- PM2 (`npm install -g pm2`)
- Self-signed SSL certificates in `/etc/ssl/certs/` and `/etc/ssl/private/`

## Deployment Steps

### Stack 1

```bash
cd stack1_next_node_mongodb/
sudo bash deploy_stack1.sh --full
```

**What it does:**
1. Validates prerequisites (Node.js, MongoDB, Nginx)
2. Creates MongoDB replica set (3 nodes)
3. Installs npm dependencies for backend + frontend
4. Builds Next.js production bundle
5. Starts PM2 processes (Express cluster + Next.js fork)
6. Deploys Nginx config with SSL
7. Runs health checks

### Stack 2

```bash
cd stack2_laravel_mysql_api/
sudo bash deploy_stack2.sh --full
```

**What it does:**
1. Validates PHP, Composer, MySQL
2. Configures MySQL master-slave replication
3. Runs `composer install --no-dev`
4. Runs migrations + seeders
5. Caches config/routes/views
6. Deploys systemd services (3 app + 2 workers + scheduler)
7. Deploys Nginx config with SSL

### Stack 3

```bash
cd stack3_next_fastapi_mysql/
sudo bash deploy_stack3.sh --full
```

**What it does:**
1. Validates Python, Node.js, MySQL
2. Creates Python virtualenv, installs requirements
3. Runs Alembic migrations
4. Starts FastAPI via systemd (3 instances)
5. Builds and starts Next.js via PM2 (2 instances)
6. Deploys Nginx config with SSL

---

## Post-Deployment Verification

```bash
# Health check all stacks
./health_check_all_stacks.sh --level all

# Individual stack checks
./stack1_next_node_mongodb/health_check_stack1.sh --once
./stack2_laravel_mysql_api/health_check_stack2.sh --once
./stack3_next_fastapi_mysql/health_check_stack3.sh --once
```

## DNS Configuration

Add to `/etc/hosts`:
```
127.0.0.1  stack1.devops.local
127.0.0.1  stack2.devops.local
127.0.0.1  stack3.devops.local
```

## SSL Certificates

Self-signed certs generated during deployment:
```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/stack1.key \
    -out /etc/ssl/certs/stack1.crt \
    -subj "/CN=stack1.devops.local"
```

## Service Management

| Action | Stack 1 | Stack 2 | Stack 3 |
|--------|---------|---------|---------|
| Start | `pm2 start ecosystem.config.js` | `sudo systemctl start laravel-app-800{0,1,2}` | Both PM2 + systemd |
| Stop | `pm2 stop all` | `sudo systemctl stop laravel-app-800{0,1,2}` | Both PM2 + systemd |
| Restart | `pm2 restart all` | `sudo systemctl restart laravel-app-800{0,1,2}` | Both |
| Logs | `pm2 logs` | `journalctl -u laravel-app-8000` | Both |
| Status | `pm2 status` | `systemctl status laravel-app-*` | Both |
