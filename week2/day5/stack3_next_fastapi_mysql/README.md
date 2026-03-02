# Stack 3: Next.js + FastAPI + MySQL

## Deployment Flow

Step-by-step of what happens when you run `sudo ./deploy_stack3.sh`:

1. **Pre-flight** -- verify `python3`, `pip3`, `node`, `npm`, `pm2`, `mysql` are installed
2. **Git pull (pseudo)** -- logs current branch/commit info but does NOT actually pull (git stash/pull are commented out to protect local code)
3. **MySQL setup** -- ensure database `fastapidb` exists, create user `fastapiuser`, grant privileges
4. **Backend dependencies** -- create Python virtual environment, `pip install -r requirements.txt`, copy `.env.production` to `.env`
5. **Migrations** -- run `backend/migrations/*.sql` to create tables and indexes in MySQL
6. **Frontend build** -- `npm ci` + `npm run build` inside `frontend/` to produce the `.next` production bundle with ISR enabled
7. **FastAPI systemd services** -- install and start 3 systemd services (`fastapi-8003`, `fastapi-8004`, `fastapi-8005`) with 4 workers each, health check after each start
8. **PM2 launch / rolling restart**
   - *Fresh deploy*: clean start -- `pm2 start pm2/nextjs-ecosystem.config.js` launches 2 Next.js instances
   - *Re-deploy*: save current state, restart each instance one by one, health-check after each restart, roll back via `pm2 resurrect` if any check fails
9. **SSL certificate** -- generate a self-signed cert for `stack3.devops.local` (skipped if cert already exists)
10. **Nginx** -- install config, symlink to `sites-enabled`, set up API response caching, reload nginx
11. **Post-deploy health checks** -- poll all 3 FastAPI ports, both Next.js ports, and the Nginx HTTPS endpoint

If everything passes, the stack is live at `https://stack3.devops.local`.

---

## Architecture

### 1. Ingress and Reverse Proxy (Nginx)
All external traffic is handled by **Nginx**, which serves as the entry point for the infrastructure.
* **SSL/TLS Termination:** Manages HTTPS encryption and certificate handling.
* **Static Asset Caching:** Offloads requests for static files (`/_next/static/`) with 1-year cache headers.
* **API Response Caching:** Selective caching for GET requests to `/api/products` with 5-minute TTL.

### 2. Load Balancing and Traffic Distribution
Traffic is routed based on URI context using specific distribution algorithms:
* **Frontend Cluster (`/`):** Traffic is directed to Next.js instances using **Round-Robin** for balanced distribution.
* **API Cluster (`/api/*`):** Traffic is routed to FastAPI instances using **Least Connections (`least_conn`)** to optimize for concurrent async requests.

### 3. Application Layer

#### Backend -- FastAPI (Python)
* 3 instances managed by **systemd** (ports 8003, 8004, 8005)
* 4 Uvicorn worker processes per instance (12 total workers)
* Async database connections via `aiomysql` connection pool
* Automatic restart on failure via systemd `Restart=always`

#### Frontend -- Next.js (Node.js)
* 2 instances managed by **PM2** (ports 3005, 3006)
* ISR (Incremental Static Regeneration) enabled with 30-second revalidation
* API routes proxied to FastAPI backend
* Automatic restart on failure via PM2 `autorestart`

### 4. Database Layer (MySQL)
Data persistence is managed via a single **MySQL** instance with read-optimized configuration.
* **Connection Pool:** 5-20 async connections via `aiomysql` per FastAPI worker
* **Read Optimization:** InnoDB buffer pool tuned for read-heavy workload (512MB), read I/O threads set to 8
* **Query Performance:** Slow query logging enabled, table caching configured

---

### Architectural Flow

```text
       [ User Traffic ]
              | (HTTPS)
              v
      [ Nginx Ingress ]
              |
      +-------+-------+
      |               |
  (Path: /)     (Path: /api/*)
      |               |
      v               v
[ Next.js ]     [ FastAPI ]  -->  [ MySQL ]
 (2 Nodes)       (3 Nodes)        (Read-Optimized)
  PM2 fork      systemd svc       InnoDB 512MB
 3005, 3006    8003, 8004, 8005   port 3306
```

---

## Project Structure

```
stack3_next_fastapi_mysql/
|
|-- deploy_stack3.sh                  # full deployment (MySQL + build + migrate + systemd + PM2 + Nginx)
|-- health_check_stack3.sh            # live health monitor (polls every 5s)
|-- .env.production                   # production environment template
|
|-- backend/                          # FastAPI REST API (Python)
|   |-- main.py                       # application entry point
|   |-- config.py                     # pydantic settings from environment
|   |-- database.py                   # async MySQL connection pool (aiomysql)
|   |-- .env                          # active runtime config (copied from .env.production)
|   |-- requirements.txt              # Python dependencies
|   |-- routers/
|   |   +-- products.py               # CRUD endpoints for products
|   |-- models/
|   |   +-- product.py                # pydantic models
|   |-- migrations/
|   |   +-- 001_create_products_table.sql
|   +-- venv/                         # Python virtual environment
|
|-- frontend/                         # Next.js SSR app
|   |-- app/
|   |   |-- page.tsx                  # home page (server component, ISR revalidate=30)
|   |   +-- products/page.tsx         # products CRUD page (client component)
|   |-- components/
|   |-- lib/
|   |   +-- api.ts                    # API client
|   |-- next.config.ts                # rewrites for backend proxy
|   +-- .env                          # frontend environment
|
|-- mysql/                            # MySQL configuration
|   +-- optimization.cnf              # read-optimized MySQL config
|
|-- nginx/                            # Nginx load balancer
|   |-- stack3.conf                   # upstream pools + SSL + proxy rules + caching
|   |-- setup-ssl.sh                  # generate self-signed certificate
|   +-- install-nginx-config.sh       # install Nginx + deploy config
|
|-- pm2/                              # PM2 process management
|   +-- nextjs-ecosystem.config.js    # PM2 config for 2 Next.js instances
|
|-- systemd/                          # systemd service files
|   |-- fastapi-8003.service          # FastAPI instance on port 8003
|   |-- fastapi-8004.service          # FastAPI instance on port 8004
|   +-- fastapi-8005.service          # FastAPI instance on port 8005
|
+-- var/log/apps/                     # application logs
```

---

## Quick Deployment

```bash
# Full deployment - MySQL + build + systemd + PM2 + SSL + Nginx
sudo ./deploy_stack3.sh

# Skip MySQL setup (already configured)
sudo ./deploy_stack3.sh --skip-mysql

# Skip Nginx (no sudo needed)
./deploy_stack3.sh --skip-mysql --skip-nginx

# Skip build steps (dependencies already installed)
sudo ./deploy_stack3.sh --skip-build

# View all options
./deploy_stack3.sh --help
```

---

## Step-by-Step

### Step 0 -- Code

The deploy script has git pull **disabled** (pseudo pull only) to protect local changes.
To update from remote manually:

```bash
cd stack3_next_fastapi_mysql
git stash
git pull origin main
git stash pop
```

---

### Step 1 -- MySQL Database

```bash
# Ensure MySQL is running
sudo systemctl start mysql

# Create database and user
sudo mysql <<EOF
CREATE DATABASE IF NOT EXISTS fastapidb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'fastapiuser'@'localhost' IDENTIFIED BY 'Fast@123';
GRANT ALL PRIVILEGES ON fastapidb.* TO 'fastapiuser'@'localhost';
FLUSH PRIVILEGES;
EOF

# Run migrations
mysql -u fastapiuser -pFast@123 fastapidb < backend/migrations/001_create_products_table.sql

# Verify
mysql -u fastapiuser -pFast@123 -e "SHOW TABLES" fastapidb
```

MySQL Read Optimization (`mysql/optimization.cnf`):

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `innodb_buffer_pool_size` | 512M | Cache frequently read data in memory |
| `innodb_buffer_pool_instances` | 4 | Reduce lock contention on buffer pool |
| `innodb_read_io_threads` | 8 | Parallel read I/O threads |
| `innodb_random_read_ahead` | ON | Prefetch pages for sequential reads |
| `max_connections` | 200 | Support connection pool from 3 FastAPI instances |
| `table_open_cache` | 4000 | Keep table handles open |
| `thread_cache_size` | 50 | Reuse threads instead of creating new ones |
| `slow_query_log` | 1 | Log queries exceeding 2 seconds |

To apply the optimization config:
```bash
sudo cp mysql/optimization.cnf /etc/mysql/mysql.conf.d/
sudo systemctl restart mysql
```

---

### Step 2 -- Backend (3 FastAPI instances)

```bash
cd backend

# Create virtual environment and install dependencies
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Apply production environment
cp ../.env.production .env
```

Key settings from `.env.production`:
```env
DB_HOST=localhost
DB_PORT=3306
DB_NAME=fastapidb
DB_USER=fastapiuser
DB_PASSWORD=Fast@123
DB_POOL_MIN=5
DB_POOL_MAX=20
```

Start via systemd (production):
```bash
sudo cp ../systemd/fastapi-800{3,4,5}.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now fastapi-8003 fastapi-8004 fastapi-8005
```

Start manually (development):
```bash
source venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8003 --workers 4
```

---

### Step 3 -- Frontend (2 Next.js instances)

```bash
cd frontend
npm ci
npm run build     # produces .next/ with ISR enabled
```

ISR Configuration:
- Home page (`/`) uses `export const revalidate = 30` for 30-second ISR
- Products page (`/products`) uses client-side rendering for real-time CRUD
- API routes are proxied to FastAPI via `next.config.ts` rewrites

---

### Step 4 -- PM2

```bash
# Fresh start
pm2 start pm2/nextjs-ecosystem.config.js
pm2 save
pm2 startup        # enable autostart on system reboot

# Re-deploy (rolling restart -- zero-downtime)
pm2 restart nextjs-3005 && sleep 5
pm2 restart nextjs-3006
pm2 save
```

| PM2 name      | Mode | Port | Role        |
|---------------|------|------|-------------|
| `nextjs-3005` | fork | 3005 | Next.js SSR |
| `nextjs-3006` | fork | 3006 | Next.js SSR |

Next.js uses `fork` mode because it manages its own concurrency internally. The deploy script performs rolling restart automatically and rolls back via `pm2 resurrect` if any health check fails.

---

### Step 5 -- Systemd Services (FastAPI)

```bash
# Install service files
sudo cp systemd/fastapi-800{3,4,5}.service /etc/systemd/system/
sudo systemctl daemon-reload

# Enable and start
sudo systemctl enable --now fastapi-8003 fastapi-8004 fastapi-8005

# Check status
sudo systemctl status fastapi-8003 fastapi-8004 fastapi-8005
```

| Service | Port | Workers | Role |
|---------|------|---------|------|
| `fastapi-8003` | 8003 | 4 | FastAPI API |
| `fastapi-8004` | 8004 | 4 | FastAPI API |
| `fastapi-8005` | 8005 | 4 | FastAPI API |

Each service runs Uvicorn with 4 worker processes, providing 12 total worker processes across the 3 instances. Services auto-restart on failure with a 5-second delay.

---

### Step 6 -- Nginx + SSL

```bash
# Generate self-signed certificate for stack3.devops.local
sudo ./nginx/setup-ssl.sh

# Install Nginx and enable the site
sudo ./nginx/install-nginx-config.sh

# Add to /etc/hosts (development machines only)
echo "127.0.0.1  stack3.devops.local" | sudo tee -a /etc/hosts
```

Nginx handles: HTTP to HTTPS redirect, frontend proxy, API proxy, WebSocket support, static asset caching, API response caching.

<details>
<summary>Nginx configuration (stack3.conf)</summary>

```nginx
# FastAPI upstream (least_conn, 3 instances)
upstream fastapi_backend {
    least_conn;
    server 127.0.0.1:8003 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:8004 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:8005 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

# Frontend upstream (round-robin, 2 instances)
upstream nextjs_frontend {
    server 127.0.0.1:3005 max_fails=2 fail_timeout=30s;
    server 127.0.0.1:3006 max_fails=2 fail_timeout=30s;
    keepalive 16;
}

# HTTP -> HTTPS redirect
server {
    listen 80;
    server_name stack3.devops.local;
    return 301 https://$server_name$request_uri;
}

# HTTPS server with SSL termination
server {
    listen 443 ssl http2;
    server_name stack3.devops.local;

    ssl_certificate     /etc/ssl/certs/stack3.crt;
    ssl_certificate_key /etc/ssl/private/stack3.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    # Frontend (Next.js SSR + WebSocket support)
    location / {
        proxy_pass http://nextjs_frontend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    # Backend API (path preserved)
    location /api/ {
        proxy_pass http://fastapi_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # API response caching (selective, GET products)
    location ~ ^/api/products$ {
        proxy_pass http://fastapi_backend;
        proxy_cache stack3_cache;
        proxy_cache_valid 200 5m;
        add_header X-Cache-Status $upstream_cache_status;
    }

    # Static assets cached for 1 year
    location /_next/static/ {
        proxy_pass http://nextjs_frontend;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

Health checks: passive (Nginx OSS `max_fails`/`fail_timeout`) + active (`./health_check_stack3.sh --interval 5`).

</details>

---

## Endpoints

| URL | Description |
|-----|-------------|
| `https://stack3.devops.local/` | Next.js frontend (ISR) |
| `https://stack3.devops.local/products` | Products CRUD page |
| `https://stack3.devops.local/api/health` | API health check |
| `https://stack3.devops.local/api/v1/products/` | Products REST API |
| `https://stack3.devops.local/docs` | Swagger UI |
| `https://stack3.devops.local/redoc` | ReDoc API docs |
| `http://localhost:8003/health` | Direct FastAPI health |
| `http://localhost:3005` | Direct frontend |

---

## Health Monitoring

```bash
./health_check_stack3.sh              # polls every 5 seconds continuously
./health_check_stack3.sh --once       # single check then exit
./health_check_stack3.sh --interval 10
```

Checks: all 3 FastAPI instances (HTTP health + systemd status), both Next.js instances (HTTP + PM2 status), MySQL connectivity, Nginx status + HTTP redirect.

---

## Ports

| Service | Port | Notes |
|---------|------|-------|
| Nginx HTTPS | 443 | SSL termination |
| Nginx HTTP | 80 | Redirects to 443 |
| FastAPI API | 8003, 8004, 8005 | systemd, 4 workers each |
| Next.js SSR | 3005, 3006 | PM2 fork |
| MySQL | 3306 | InnoDB, read-optimized |

---

## Common Commands

```bash
# PM2 (Next.js)
pm2 list
pm2 logs
pm2 restart nextjs-3005
pm2 restart all

# Systemd (FastAPI)
sudo systemctl status fastapi-8003
sudo systemctl restart fastapi-8003
sudo systemctl stop fastapi-8003
journalctl -u fastapi-8003 -f

# MySQL
mysql -u fastapiuser -pFast@123 fastapidb
sudo systemctl status mysql

# Nginx
sudo nginx -t
sudo systemctl reload nginx
sudo tail -f /var/log/nginx/stack3-access.log
```

---

## Troubleshooting

**MySQL connection failed**
```bash
sudo systemctl status mysql
mysql -u fastapiuser -pFast@123 -e "SELECT 1" fastapidb
sudo mysql -e "SHOW DATABASES"
```

**FastAPI fails to start**
```bash
journalctl -u fastapi-8003 -f --lines 50
ss -tlnp | grep -E '8003|8004|8005'
cd backend && source venv/bin/activate && python3 -c "from main import app"
```

**Frontend not loading**
```bash
cd frontend && rm -rf .next && npm run build
pm2 logs nextjs-3005 --lines 50
```

**Nginx SSL errors**
```bash
sudo nginx -t
sudo ./nginx/setup-ssl.sh      # regenerate certificate
```

**Connection pool exhausted**
```bash
# Check current MySQL connections
mysql -u fastapiuser -pFast@123 -e "SHOW STATUS LIKE 'Threads_connected'"

# Check pool stats via health endpoint
curl -s http://localhost:8003/health | python3 -m json.tool
```

---
