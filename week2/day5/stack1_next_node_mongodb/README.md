# Stack 1: Next.js + Node.js + MongoDB

## Deployment Flow

Simple step-by-step of what happens when you run `sudo ./deploy_stack1.sh`:

1. **Pre-flight** — verify `node`, `npm`, `pm2`, `mongod`, `mongosh` are installed
2. **Git pull (pseudo)** — logs current branch/commit info but does NOT actually pull (git stash/pull are commented out to protect local code)
3. **MongoDB Replica Set** — start 3 `mongod` nodes (27017 · 27018 · 27019), run `rs.initiate()`, create users
4. **Backend dependencies** — `npm ci --omit=dev` inside `backend/`, copy `.env.production` → `.env`
5. **Migrations** — run every `backend/migrations/*.js` to create collections and indexes in MongoDB
6. **Frontend build** — `npm ci` + `npm run build` inside `frontend/` to produce the `.next` production bundle
7. **PM2 launch / rolling restart**
   - *Fresh deploy*: clean start — `pm2 start pm2/ecosystem.config.js` launches all 5 processes at once
   - *Re-deploy*: save current state, restart each instance one by one, health-check after each restart, roll back via `pm2 resurrect` if any check fails
8. **SSL certificate** — generate a CA-signed cert for `stack1.devops.local` (skipped if cert already exists)
9. **Nginx** — install config, symlink to `sites-enabled`, reload nginx
10. **Post-deploy health checks** — poll all 3 backend ports, both frontend ports, and the Nginx HTTPS endpoint

If everything passes, the stack is live at `https://stack1.devops.local`.


## Architecture 

## 1. Ingress & Reverse Proxy (Nginx)
All external traffic is handled by **Nginx**, which serves as the entry point for the infrastructure.
* **SSL/TLS Termination:** Manages HTTPS encryption and certificate handling.
* **Static Asset Caching:** Offloads requests for static files to improve latency and reduce application load.

## 2. Load Balancing & Traffic Distribution
Traffic is routed based on URI context using specific distribution algorithms:
* **Frontend Cluster (`/`):** Traffic is directed to Next.js instances using a **Round-Robin** algorithm for balanced distribution.
* **API Cluster (`/api/*`):** Traffic is routed to Express.js instances using the **Least Connections (`least_conn`)** method to optimize for longer-running requests.

## 3. Application Layer (Node.js/PM2)
The application logic is decoupled into two clusters, managed by **PM2** for process monitoring and automatic self-healing.
* **Web Tier:** 2x Next.js instances (Ports 3001, 3002) providing Server-Side Rendering (SSR).
* **API Tier:** 3x Express.js instances (Ports 3000, 3003, 3004) handling business logic and DB I/O.
* **Resiliency:** PM2 ensures high availability by automatically restarting instances in the event of a process failure.

## 4. Database Layer (MongoDB Replica Set)
Data persistence is managed via a **3-node MongoDB Replica Set (`rs0`)** to ensure zero single point of failure (SPOF).
* **Primary Node (Port 27017):** Handles all write operations and maintains data consistency.
* **Secondary Nodes (Ports 27018, 27019):** Maintain real-time data replication.
* **Automated Failover:** In the event of a Primary node outage, the cluster performs an election to promote a Secondary node to Primary, ensuring continuous uptime.

---

### Architectural Flow



```text
       [ User Traffic ]
              │ (HTTPS)
              ▼
      [ Nginx Ingress ]
              │
      ┌───────┴───────┐
      │               │
  (Path: /)     (Path: /api/*)
      │               │
      ▼               ▼
[ Next.js ]     [ Express.js ] ──► [ MongoDB Cluster ]
 (2 Nodes)       (3 Nodes)          (Primary/Secondaries)

```

## Project Structure

```
stack1_next_node_mongodb/
│
├── deploy_stack1.sh                  <-- full deployment (MongoDB + build + migrate + PM2 + Nginx)
├── health_check_stack1.sh            <-- live health monitor (polls every 5s)
├── .env.production                   <-- root production environment template
│
├── backend/                          <-- Express.js REST API
│   ├── server.js
│   ├── .env                          <-- active runtime config (git-ignored)
│   ├── .env.production               <-- production template with replica set URI
│   ├── config/                       <-- DB connection + logger setup
│   ├── controllers/
│   ├── models/
│   ├── routes/
│   └── var/log/apps/                 <-- Winston + PM2 logs
│
├── frontend/                         <-- Next.js SSR app
│   ├── app/
│   ├── components/
│   ├── lib/
│   ├── .env                          <-- active runtime config
│   ├── .env.local                    <-- local overrides (git-ignored)
│   └── var/log/                      <-- PM2 logs
│
├── mongodb-replicaset/               <-- MongoDB HA configuration
│   ├── setup-replicaset.sh           <-- init 3-node replica set + auth
│   ├── manage-replicaset.sh          <-- start / stop / status / logs
│   ├── test-failover.sh              <-- automated 7-step failover test
│   └── config/
│       ├── mongod-node1.conf         <-- port 27017 (preferred primary)
│       ├── mongod-node2.conf         <-- port 27018 (secondary)
│       └── mongod-node3.conf         <-- port 27019 (secondary)
│
├── nginx/                            <-- Nginx load balancer
│   ├── stack1.conf                   <-- upstream pools + SSL + proxy rules
│   ├── setup-ssl.sh                  <-- generate self-signed certificate
│   └── install-nginx-config.sh       <-- install Nginx + deploy config
│
└── pm2/
    └── ecosystem.config.js           <-- PM2 process definitions (5 apps)
```

---

## Quick Deployment

```bash
# Full deployment - MongoDB + build + PM2 + SSL + Nginx
sudo ./deploy_stack1.sh

# if MongoDB is already running Skip it
sudo ./deploy_stack1.sh --skip-mongo

# To Just restart app
./deploy_stack1.sh --skip-mongo --skip-nginx

# Options
./deploy_stack1.sh --help
```

---

## Step-by-Step

### Step 0 — Code

The deploy script has git pull **disabled** (pseudo pull only) to protect local changes.  
To update from remote manually:

```bash
cd stack1_next_node_mongodb
git stash
git pull origin main
git stash pop
```

---

### Step 1 — MongoDB Replica Set

```bash
./mongodb-replicaset/setup-replicaset.sh
```

What it does:
1. Creates a shared auth keyfile
2. Starts `mongod` on ports **27017**, **27018**, **27019**
3. Runs `rs.initiate()` — node1 is preferred primary (priority 2)
4. Creates users: `admin / Admin@123` and `devops / Devops@123`
5. Restarts all nodes with authentication enabled

Check status:
```bash
./mongodb-replicaset/manage-replicaset.sh status
# localhost:27017 - PRIMARY
# localhost:27018 - SECONDARY
# localhost:27019 - SECONDARY
```

---

### Step 2 — Backend (3 instances)

```bash
cd backend
npm ci --omit=dev
cp .env.production .env     # apply production config
```

Key settings from `.env.production`:
```env
MONGODB_URI=mongodb://devops:Devops%40123@localhost:27017,localhost:27018,localhost:27019/usersdb?replicaSet=rs0&authSource=admin&readPreference=primaryPreferred&retryWrites=true&w=majority
CORS_ORIGIN=https://stack1.devops.local
```

```bash
# Run migrations (creates collections + indexes)
npm run migrate
```

---

### Step 3 — Frontend (2 instances)

```bash
cd frontend
npm ci
npm run build     
```

---

### Step 4 — PM2

```bash
# Fresh start
pm2 start pm2/ecosystem.config.js
pm2 save
pm2 startup        # enable autostart on system reboot

# Re-deploy (rolling restart — zero-downtime, health-checked per instance)
pm2 restart backend-3000 && sleep 5
pm2 restart backend-3003 && sleep 5
pm2 restart backend-3004 && sleep 5
pm2 restart frontend-3001 && sleep 5
pm2 restart frontend-3002
pm2 save
```

| PM2 name        | Mode    | Port | Role        |
|-----------------|---------|------|-------------|
| `backend-3000`  | cluster | 3000 | Express API |
| `backend-3003`  | cluster | 3003 | Express API |
| `backend-3004`  | cluster | 3004 | Express API |
| `frontend-3001` | fork    | 3001 | Next.js SSR |
| `frontend-3002` | fork    | 3002 | Next.js SSR |

- Backend uses `cluster` mode; Next.js uses `fork` mode (it manages its own concurrency internally).
- The deploy script performs the rolling restart automatically and rolls back via `pm2 resurrect` if any health check fails.

---

### Step 5 — Nginx + SSL

```bash
# Generate self-signed certificate for stack1.devops.local
sudo ./nginx/setup-ssl.sh

# Install Nginx and enable the site
sudo ./nginx/install-nginx-config.sh

# Add to /etc/hosts (development machines only)
echo "127.0.0.1  stack1.devops.local" | sudo tee -a /etc/hosts
```

Nginx handles: HTTP --> HTTPS redirect, frontend proxy, API proxy, WebSocket support, static asset caching.

<details>
<summary>Nginx configuration (stack1.conf)</summary>

```nginx
# Backend API upstream (least_conn, 3 Express instances)
upstream nodejs_api {
    least_conn;
    server 127.0.0.1:3000 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:3003 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:3004 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

# Frontend upstream (round-robin, 2 Next.js instances)
upstream nextjs_frontend {
    server 127.0.0.1:3001 max_fails=2 fail_timeout=30s;
    server 127.0.0.1:3002 max_fails=2 fail_timeout=30s;
    keepalive 16;
}

# HTTP → HTTPS redirect
server {
    listen 80;
    server_name stack1.devops.local;
    return 301 https://$server_name$request_uri;
}

# HTTPS server with SSL termination
server {
    listen 443 ssl http2;
    server_name stack1.devops.local;

    ssl_certificate     /etc/ssl/certs/stack1.crt;
    ssl_certificate_key /etc/ssl/private/stack1.key;
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

    # Backend API
    location /api/ {
        proxy_pass http://nodejs_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # Static assets cached for 1 year
    location /_next/static/ {
        proxy_pass http://nextjs_frontend;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

Health checks: passive (Nginx OSS `max_fails`/`fail_timeout`) + active (`./health_check_stack1.sh --interval 5`).

</details>

---

## Endpoints

| URL | Description |
|-----|-------------|
| `https://stack1.devops.local/` | Next.js frontend |
| `https://stack1.devops.local/api/health` | API health check |
| `https://stack1.devops.local/api/users` | Users CRUD |
| `https://stack1.devops.local/api-docs` | Swagger UI |
| `http://localhost:3000/api/health` | Direct backend |
| `http://localhost:3001` | Direct frontend |

---

## Health Monitoring

```bash
./health_check_stack1.sh              # polls every 5 seconds continuously
./health_check_stack1.sh --once       # single check then exit
./health_check_stack1.sh --interval 10
```

Checks: all 3 Express API instances, both Next.js instances, all 3 MongoDB nodes, Nginx status + redirect.

---

## Failover Test

```bash
./mongodb-replicaset/test-failover.sh
```

7 automated checks: topology, write to primary, secondary replication, kill primary, election timing, API availability during failover, and node recovery.

---

## Ports

| Service | Port | Notes |
|---------|------|-------|
| Nginx HTTPS | 443 | SSL termination |
| Nginx HTTP  | 80  | Redirects to 443 |
| Express API | 3000, 3003, 3004 | PM2 cluster |
| Next.js SSR | 3001, 3002 | PM2 fork |
| MongoDB primary | 27017 | rs0, priority 2 |
| MongoDB secondary | 27018, 27019 | rs0, priority 1 |

---

## Common Commands

```bash
# PM2
pm2 list
pm2 logs
pm2 restart backend-3000
pm2 reload pm2/ecosystem.config.js   # zero-downtime reload

# MongoDB
./mongodb-replicaset/manage-replicaset.sh start
./mongodb-replicaset/manage-replicaset.sh stop
./mongodb-replicaset/manage-replicaset.sh status

# Nginx
sudo nginx -t
sudo systemctl reload nginx
sudo tail -f /var/log/nginx/stack1-access.log
```

---

## Troubleshooting

**MongoDB won't connect**
```bash
pgrep -fl mongod
mongosh "mongodb://devops:Devops%40123@localhost:27017/usersdb?authSource=admin"
mongosh "mongodb://admin:Admin%40123@localhost:27017/admin?authSource=admin" --eval "rs.status()"
```

**Backend fails to start**
```bash
pm2 logs backend-3000 --lines 50
ss -tlnp | grep -E '3000|3003|3004'
```

**Frontend not loading**
```bash
cd frontend && rm -rf .next && npm run build
pm2 logs frontend-3001 --lines 50
```

**Nginx SSL errors**
```bash
sudo nginx -t
sudo ./nginx/setup-ssl.sh      # regenerate certificate
```

---

