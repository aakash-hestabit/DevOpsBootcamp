# Stack 2: Laravel + MySQL

## Deployment Flow

Step-by-step of what happens when you run `sudo ./deploy_stack2.sh`:

1. **Pre-flight** -- verify `php`, `composer`, `mysql`, `npm` are installed and PHP >= 8.2 with required extensions
2. **Git pull (pseudo)** -- logs current branch/commit info but does NOT actually pull (git stash/pull are commented out to protect local code)
3. **MySQL Master-Slave** -- start master on port 3306 and slave on port 3307, configure GTID-based replication, create application database and users
4. **Composer install** -- `composer install --no-dev --optimize-autoloader` plus Laravel config/route/view caching
5. **Migrations** -- `php artisan migrate --force` with connectivity check and optional seeding on first deploy
6. **Frontend build** -- `npm install` + `npm run build` to compile Vite/Tailwind assets into `public/build/`
7. **systemd services (rolling restart)**
   - *Fresh deploy*: start all 3 Laravel instances, 2 queue workers, and the scheduler timer
   - *Re-deploy*: restart each instance one by one, health-check after each restart, abort and report on failure
8. **SSL certificate** -- generate a CA-signed cert for `stack2.devops.local` (skipped if cert already exists)
9. **Nginx** -- install config, symlink to `sites-enabled`, reload Nginx
10. **Post-deploy health checks** -- poll all 3 Laravel ports, MySQL master and slave, queue workers, scheduler, and the Nginx HTTPS endpoint

If everything passes, the stack is live at `https://stack2.devops.local`.

---

## Architecture

### 1. Ingress and Reverse Proxy (Nginx)

All external traffic is handled by Nginx, which serves as the single entry point for the infrastructure.

- **SSL/TLS Termination:** Manages HTTPS encryption and certificate handling at the edge.
- **Static Asset Serving:** Serves compiled Vite assets and static files directly from disk, reducing application load.
- **Session Persistence:** Uses `ip_hash` to ensure requests from the same client consistently reach the same Laravel instance, maintaining session state.

### 2. Load Balancing and Traffic Distribution

Traffic is distributed across the Laravel pool using `ip_hash` for session affinity:

- **Laravel Pool (all routes):** 3 instances on ports 8000, 8001, and 8002.
- **Passive Health Checks:** Nginx marks an upstream server as unavailable after 3 consecutive failures within a 30-second window.
- **Active Health Checks:** The bundled `health_check_stack2.sh` script polls `/api/health` on each instance at configurable intervals.

### 3. Application Layer (Laravel / PHP)

The application runs as 3 independent PHP processes managed by systemd, with queue workers and a scheduler:

- **Web Tier:** 3x Laravel instances (Ports 8000, 8001, 8002) serving both the frontend views and the REST API.
- **Queue Workers:** 2x systemd-managed workers processing background jobs from the database queue.
- **Scheduler:** A systemd timer triggers `php artisan schedule:run` every minute, replacing the traditional crontab entry.
- **Resiliency:** systemd automatically restarts any instance that exits unexpectedly. `StartLimitBurst` prevents infinite restart loops.

### 4. Database Layer (MySQL Master-Slave)

Data persistence is managed via MySQL master-slave replication for read scaling and redundancy:

- **Master (Port 3306):** Handles all write operations. Binary logging with `ROW` format and GTID enabled.
- **Slave (Port 3307):** Real-time read replica. Configured as `read_only` and `super_read_only` to prevent accidental writes.
- **Read/Write Split:** Laravel's database configuration routes SELECT queries to the slave and writes to the master. The `sticky` option ensures that after a write, subsequent reads in the same request hit the master to avoid stale data.

---

### Architectural Flow

```text
       [ User Traffic ]
              | (HTTPS)
              v
      [ Nginx Ingress ]
         (ip_hash LB)
              |
    +---------+---------+
    |         |         |
  :8000     :8001     :8002
    |         |         |
    v         v         v
     [ Laravel Instances ]
        (3x PHP artisan serve)
              |
     +--------+--------+
     |                  |
  [ Master ]       [ Slave ]
  (write)          (read)
  :3306            :3307

  [ Queue Workers x2 ]  [ Scheduler ]
```

---

## Project Structure

```
stack2_laravel_mysql_api/
|
|-- deploy_stack2.sh                  <-- full deployment (MySQL + build + migrate + systemd + Nginx)
|-- health_check_stack2.sh            <-- live health monitor (polls every 5s)
|-- .env.production                   <-- production environment template
|
|-- app/                              <-- Laravel application code
|   |-- Http/Controllers/
|   |   |-- HealthController.php      <-- /api/health endpoint
|   |   |-- TaskController.php        <-- tasks CRUD API
|   |   +-- SwaggerController.php     <-- OpenAPI metadata
|   |-- Models/
|   |   +-- Task.php                  <-- task model with scopes
|   +-- Providers/
|
|-- config/
|   +-- database.php                  <-- read/write split configuration
|
|-- database/
|   |-- migrations/                   <-- schema migrations
|   +-- seeders/                      <-- sample data
|
|-- resources/views/                  <-- Blade frontend templates
|   |-- layouts/app.blade.php         <-- base layout
|   +-- tasks/                        <-- task CRUD views (index, create, edit)
|
|-- routes/
|   |-- api.php                       <-- REST API routes
|   +-- web.php                       <-- web frontend routes
|
|-- mysql/                            <-- MySQL replication configuration
|   |-- master-slave-setup.sh         <-- automated replication setup
|   |-- master.cnf                    <-- master configuration (port 3306)
|   +-- slave.cnf                     <-- slave configuration (port 3307)
|
|-- nginx/                            <-- Nginx load balancer
|   |-- stack2.conf                   <-- upstream pools + SSL + proxy rules
|   |-- setup-ssl.sh                  <-- generate CA-signed certificate
|   +-- install-nginx-config.sh       <-- install Nginx + deploy config
|
|-- systemd/                          <-- process management
|   |-- laravel-app-8000.service      <-- Laravel instance on port 8000
|   |-- laravel-app-8001.service      <-- Laravel instance on port 8001
|   |-- laravel-app-8002.service      <-- Laravel instance on port 8002
|   |-- laravel-worker@.service       <-- queue worker template unit
|   |-- laravel-scheduler.service     <-- scheduler oneshot service
|   +-- laravel-scheduler.timer       <-- scheduler minutely timer
|
+-- var/log/apps/                     <-- application and deployment logs
```

---

## Quick Deployment

```bash
# Full deployment - MySQL + build + systemd + SSL + Nginx
sudo ./deploy_stack2.sh

# If MySQL is already running, skip it
sudo ./deploy_stack2.sh --skip-mysql

# Just restart app (no sudo needed)
./deploy_stack2.sh --skip-mysql --skip-nginx

# Options
./deploy_stack2.sh --help
```

---

## Step-by-Step

### Step 0 -- Code

The deploy script has git pull **disabled** (pseudo pull only) to protect local changes.
To update from remote manually:

```bash
cd stack2_laravel_mysql_api
git stash
git pull origin main
git stash pop
```

---

### Step 1 -- MySQL Master-Slave Replication

```bash
sudo bash mysql/master-slave-setup.sh
```

What it does:
1. Initializes separate data directories for master and slave
2. Starts master on port **3306** with binary logging and GTID enabled
3. Creates replication user, application user, and the `laraveldb` database
4. Starts slave on port **3307** with `read_only` and `super_read_only`
5. Configures GTID-based replication from slave to master
6. Runs a write-then-read test to verify data replication

Check status:
```bash
# Master status
mysql --socket=/var/run/mysqld/mysqld-master.sock -u root -p -e "SHOW MASTER STATUS\G"

# Slave status
mysql --socket=/var/run/mysqld/mysqld-slave.sock -u root -p -e "SHOW SLAVE STATUS\G"

# Quick test (should show Slave_IO_Running: Yes, Slave_SQL_Running: Yes)
mysql -h 127.0.0.1 -P 3307 -u root -p -e "SHOW SLAVE STATUS\G" | grep -E "Running|Behind"
```

**Configuration files:**

| File | Purpose |
|------|---------|
| `mysql/master.cnf` | Master: port 3306, `binlog_format=ROW`, `gtid_mode=ON`, `sync_binlog=1` |
| `mysql/slave.cnf` | Slave: port 3307, `read_only=1`, `super_read_only=1`, 4 parallel workers |

**Credentials:**

| User | Password | Scope |
|------|----------|-------|
| `root` | `Root@123` | Full access (both servers) |
| `replication` | `Repl@123` | Replication only |
| `laraveluser` | `Laravel@123` | `laraveldb` database (r/w on master, read on slave) |

---

### Step 2 -- Laravel Application (3 instances)

```bash
cd stack2_laravel_mysql_api

# Install dependencies
composer install --no-dev --optimize-autoloader

# Apply production environment
cp .env.production .env

# Cache configuration
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Run migrations
php artisan migrate --force

# Seed on first deploy only
php artisan db:seed --force
```

Key settings from `.env.production`:
```env
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=laraveldb
DB_USERNAME=laraveluser
DB_PASSWORD="Laravel@123"

# Read replica for read/write split
DB_READ_HOST=127.0.0.1
DB_READ_PORT=3307
```

The `config/database.php` file is configured with Laravel's read/write split:
- **Write queries** (INSERT, UPDATE, DELETE) go to the master on port 3306.
- **Read queries** (SELECT) go to the slave on port 3307.
- The `sticky` option is enabled so that after a write, subsequent reads in the same request use the master connection. This prevents stale reads immediately after writes.

---

### Step 3 -- Frontend Build

```bash
npm install
npm run build    # Vite production build
```

The Laravel frontend is a server-rendered Blade application with minimal CSS (no external dependencies). It provides a task management interface at the root URL.

---

### Step 4 -- systemd Services

```bash
# Install service files
sudo cp systemd/*.service systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload

# Start Laravel instances
sudo systemctl enable --now laravel-app-8000
sudo systemctl enable --now laravel-app-8001
sudo systemctl enable --now laravel-app-8002

# Start queue workers
sudo systemctl enable --now laravel-worker@1
sudo systemctl enable --now laravel-worker@2

# Start scheduler
sudo systemctl enable --now laravel-scheduler.timer
```

| Service | Type | Port/ID | Role |
|---------|------|---------|------|
| `laravel-app-8000` | long-running | 8000 | Web + API instance |
| `laravel-app-8001` | long-running | 8001 | Web + API instance |
| `laravel-app-8002` | long-running | 8002 | Web + API instance |
| `laravel-worker@1` | long-running | -- | Queue worker (database driver) |
| `laravel-worker@2` | long-running | -- | Queue worker (database driver) |
| `laravel-scheduler` | oneshot | -- | Runs `artisan schedule:run` |
| `laravel-scheduler.timer` | timer | -- | Triggers scheduler every minute |

The deploy script performs a rolling restart automatically. During re-deployment, each instance is restarted one at a time with a health check after each restart. If any instance fails its health check, the deployment is aborted and a failure report is printed.

---

### Step 5 -- Nginx + SSL

```bash
# Generate CA-signed certificate for stack2.devops.local
sudo bash nginx/setup-ssl.sh

# Install Nginx and enable the site
sudo bash nginx/install-nginx-config.sh

# Add to /etc/hosts (development machines only)
echo "127.0.0.1  stack2.devops.local" | sudo tee -a /etc/hosts
```

Nginx handles: HTTP to HTTPS redirect, load balancing with `ip_hash`, static asset serving, SSL termination, and security headers.

<details>
<summary>Nginx configuration overview (stack2.conf)</summary>

```nginx
# Laravel upstream (ip_hash for session persistence)
upstream laravel_pool {
    ip_hash;
    server 127.0.0.1:8000 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:8001 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:8002 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

# HTTP -> HTTPS redirect
server {
    listen 80;
    server_name stack2.devops.local;
    return 301 https://$server_name$request_uri;
}

# HTTPS server with SSL termination
server {
    listen 443 ssl http2;
    server_name stack2.devops.local;

    ssl_certificate     /etc/ssl/certs/stack2.crt;
    ssl_certificate_key /etc/ssl/private/stack2.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    # Nginx-level health check (responds without touching PHP)
    location = /health {
        return 200 '{"status":"ok","stack":"stack2"}';
    }

    # Static assets (Vite build) - cached for 1 year
    location /build/ {
        alias /path/to/public/build/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # API routes
    location /api/ {
        proxy_pass http://laravel_pool;
    }

    # All other requests (frontend)
    location / {
        proxy_pass http://laravel_pool;
    }
}
```

Health checks: passive (Nginx OSS `max_fails`/`fail_timeout`) + active (`./health_check_stack2.sh --interval 5`).

</details>

---

## Endpoints

| URL | Description |
|-----|-------------|
| `https://stack2.devops.local/` | Task management frontend |
| `https://stack2.devops.local/tasks/create` | Create new task |
| `https://stack2.devops.local/api/health` | Application health check (JSON) |
| `https://stack2.devops.local/api/tasks` | Tasks REST API (CRUD) |
| `https://stack2.devops.local/health` | Nginx-level health check |
| `http://localhost:8000` | Direct access to instance 1 |
| `http://localhost:8001` | Direct access to instance 2 |
| `http://localhost:8002` | Direct access to instance 3 |

---

## Health Monitoring

```bash
./health_check_stack2.sh              # polls every 5 seconds continuously
./health_check_stack2.sh --once       # single check then exit
./health_check_stack2.sh --interval 10
```

Checks performed:
- All 3 Laravel application instances via `/api/health`
- MySQL master connectivity (port 3306)
- MySQL slave connectivity (port 3307)
- Replication status (IO thread, SQL thread, seconds behind master)
- Queue workers (laravel-worker@1, laravel-worker@2)
- Scheduler timer (laravel-scheduler.timer)
- All 3 systemd services (laravel-app-8000/8001/8002)
- Nginx status and HTTP to HTTPS redirect
- Nginx HTTPS health endpoint

---

## Ports

| Service | Port | Notes |
|---------|------|-------|
| Nginx HTTPS | 443 | SSL termination, ip_hash load balancing |
| Nginx HTTP | 80 | Redirects to 443 |
| Laravel instance 1 | 8000 | systemd managed |
| Laravel instance 2 | 8001 | systemd managed |
| Laravel instance 3 | 8002 | systemd managed |
| MySQL master | 3306 | Write operations, binary logging |
| MySQL slave | 3307 | Read operations, read_only |

---

## Common Commands

```bash
# systemd services
sudo systemctl status laravel-app-8000
sudo systemctl restart laravel-app-8000
sudo journalctl -u laravel-app-8000 -f        # follow logs

# Queue workers
sudo systemctl status laravel-worker@1
sudo systemctl restart laravel-worker@1
sudo journalctl -u laravel-worker@1 -f

# Scheduler
sudo systemctl list-timers | grep laravel
sudo journalctl -u laravel-scheduler -n 20

# Laravel
php artisan tinker                             # Laravel REPL
php artisan queue:work --once                  # process single job
php artisan schedule:list                      # list scheduled tasks
php artisan config:clear && php artisan config:cache   # refresh config cache

# MySQL
mysql -h 127.0.0.1 -P 3306 -u laraveluser -p laraveldb   # connect to master
mysql -h 127.0.0.1 -P 3307 -u laraveluser -p laraveldb   # connect to slave

# Nginx
sudo nginx -t
sudo systemctl reload nginx
sudo tail -f /var/log/nginx/stack2-access.log
```

---

## MySQL Replication Commands

```bash
# Check replication status
mysql --socket=/var/run/mysqld/mysqld-slave.sock -u root -p -e "SHOW SLAVE STATUS\G"

# Key fields to check:
#   Slave_IO_Running:  Yes
#   Slave_SQL_Running: Yes
#   Seconds_Behind_Master: 0

# Check master binary log position
mysql --socket=/var/run/mysqld/mysqld-master.sock -u root -p -e "SHOW MASTER STATUS\G"

# Test replication (write on master, read on slave)
mysql -h 127.0.0.1 -P 3306 -u root -p -e "USE laraveldb; INSERT INTO tasks (title, status, priority) VALUES ('replication test', 'pending', 'low');"
mysql -h 127.0.0.1 -P 3307 -u root -p -e "USE laraveldb; SELECT * FROM tasks ORDER BY id DESC LIMIT 1;"

# If replication breaks
mysql --socket=/var/run/mysqld/mysqld-slave.sock -u root -p -e "
  STOP SLAVE;
  RESET SLAVE;
  CHANGE MASTER TO MASTER_HOST='127.0.0.1', MASTER_PORT=3306, MASTER_USER='replication', MASTER_PASSWORD='Repl@123', MASTER_AUTO_POSITION=1;
  START SLAVE;
  SHOW SLAVE STATUS\G"
```

---

## Troubleshooting

**MySQL master will not start**
```bash
# Check error log
sudo tail -50 /var/log/mysql/error-master.log

# Check if port is in use
ss -tlnp | grep 3306

# Check data directory permissions
ls -la /var/lib/mysql-master/
```

**Replication is broken**
```bash
# Check slave status for errors
mysql --socket=/var/run/mysqld/mysqld-slave.sock -u root -p -e "SHOW SLAVE STATUS\G" | grep -E "Running|Error|Behind"

# Reset and reconfigure replication
mysql --socket=/var/run/mysqld/mysqld-slave.sock -u root -p -e "STOP SLAVE; RESET SLAVE ALL;"
# Then re-run: sudo bash mysql/master-slave-setup.sh
```

**Laravel instance fails to start**
```bash
# Check systemd logs
sudo journalctl -u laravel-app-8000 -n 50

# Check if port is occupied
ss -tlnp | grep -E '8000|8001|8002'

# Test manually
cd stack2_laravel_mysql_api
php artisan serve --host=127.0.0.1 --port=8000

# Common issue: storage permissions
sudo chmod -R 775 storage bootstrap/cache
sudo chown -R www-data:www-data storage bootstrap/cache
```

**Database connection errors**
```bash
# Test connection directly
mysql -h 127.0.0.1 -P 3306 -u laraveluser -p"Laravel@123" laraveldb -e "SELECT 1"

# Check Laravel database config
php artisan tinker --execute="dd(config('database.connections.mysql'))"

# Clear and rebuild config cache
php artisan config:clear
php artisan config:cache
```

**Frontend not loading**
```bash
# Check if Vite assets are built
ls -la public/build/

# Rebuild
npm install && npm run build

# If build fails, check Node.js version
node --version   # should be 18+
```

**Nginx SSL errors**
```bash
sudo nginx -t
sudo bash nginx/setup-ssl.sh    # regenerate certificate
sudo systemctl reload nginx

# Check certificate
openssl x509 -in /etc/ssl/certs/stack2.crt -text -noout | head -20
```

**Queue jobs not processing**
```bash
# Check worker status
sudo systemctl status laravel-worker@1 laravel-worker@2

# Process a single job manually for debugging
php artisan queue:work database --once -v

# Check failed jobs
php artisan queue:failed

# Retry failed jobs
php artisan queue:retry all
```

---

## Deployment Notes & Platform-Specific Fixes

This section documents real-world issues encountered during deployment on Ubuntu with MySQL 8.0, and the fixes that were applied to the scripts. These are already incorporated into the deployment scripts so they work out of the box.

### 1. AppArmor Blocking the MySQL Slave Instance

**Problem:** Ubuntu ships with an AppArmor profile for `mysqld` that restricts it to `/var/lib/mysql/`. The slave instance needs its own data directory at `/var/lib/mysql-slave/`, a separate socket at `/var/run/mysqld/mysqld-slave.sock`, and log files at `/var/log/mysql/error-slave.log`. AppArmor silently blocks all of these.

**Symptoms:**
- `mysqld --initialize-insecure` fails with "Permission denied" (errno 13) for `/var/lib/mysql-slave/`
- Slave starts but immediately exits; `error-slave.log` shows permission errors for socket/pid files
- `dmesg | grep DENIED` shows AppArmor audit entries for mysqld

**Fix applied in `mysql/master-slave-setup.sh`:**  
The script writes a comprehensive local override to `/etc/apparmor.d/local/usr.sbin.mysqld` covering:
- Data directory: `/var/lib/mysql-slave/ rw` and `/var/lib/mysql-slave/** rwk`
- Socket/PID: `/var/run/mysqld/mysqld-slave.{pid,sock,sock.lock} rw`
- Logs: `/var/log/mysql/error-slave.log rw`, `/var/log/mysql/slow-slave.log rw`
- Binlog/relay: `/var/log/mysql/mysql-slave-bin* rw`, `/var/log/mysql/relay-bin* rw`
- Config: `/etc/mysql/stack2-slave.cnf r`

Then reloads with `apparmor_parser -r /etc/apparmor.d/usr.sbin.mysqld`.

### 2. MySQL 8.0 Authentication Plugin Incompatibility

**Problem:** MySQL 8.0 defaults to `caching_sha2_password`, which requires either an SSL connection or the RSA public key exchange. PHP PDO and MySQL replication over localhost without SSL both fail silently with "Access denied" errors.

**Symptoms:**
- `SQLSTATE[HY000] [1045] Access denied for user 'laraveluser'@'localhost'` even with correct password
- Replication `Slave_IO_Running: Connecting` (never reaches `Yes`)
- Direct `mysql -u laraveluser -p` works (CLI supports caching_sha2_password), but PHP PDO does not

**Fix applied in `mysql/master-slave-setup.sh`:**  
Both the replication user and the application user are created with `mysql_native_password`:
```sql
CREATE USER 'replication'@'%' IDENTIFIED WITH mysql_native_password BY '...';
CREATE USER 'laraveluser'@'localhost' IDENTIFIED WITH mysql_native_password BY '...';
```
The root user keeps `caching_sha2_password` since it's only used via socket auth with `debian-sys-maint`.

### 3. Slave Config File Placement

**Problem:** MySQL on Ubuntu auto-includes all files in `/etc/mysql/conf.d/`. Placing the slave config there causes the **master** to also read it on restart, breaking with conflicting `server-id`, `port`, and `datadir` settings.

**Symptoms:**
- System MySQL (master) fails to start after reboot
- `journalctl -u mysql` shows conflicting `server-id` or `port` settings

**Fix applied in `mysql/master-slave-setup.sh`:**  
The slave config is copied to `/etc/mysql/stack2-slave.cnf` (outside `conf.d/`), set to `chmod 600`, and passed explicitly via `--defaults-file=` when starting the slave. The master never sees it.

### 4. Read/Write Split Race Condition During Migrations

**Problem:** Laravel's read/write split routes SELECT queries to the slave. During `php artisan migrate`, Laravel checks the `migrations` table on the read connection (slave) immediately after creating it on the write connection (master). If the slave hasn't replicated yet, the migration fails with "table not found".

**Symptoms:**
- `SQLSTATE[42S02]: Base table or view not found: 1146 Table 'laraveldb.migrations' doesn't exist`
- Works on second run (slave has caught up by then)

**Fix applied in `deploy_stack2.sh`:**  
During migrations, the read connection is temporarily pointed at the master:
```bash
DB_READ_HOST=127.0.0.1 DB_READ_PORT=3306 php artisan migrate --seed --force
php artisan config:cache   # restore real read/write split
```

### 5. npm/Node.js Not Found Under sudo

**Problem:** When running `sudo ./deploy_stack2.sh`, the nvm-managed Node.js/npm is not in the sudo PATH (sudo strips the user's PATH for security).

**Symptoms:**
- `npm: command not found` during frontend build step
- `node: command not found`

**Fix applied in `deploy_stack2.sh`:**  
The script detects the nvm binary directory from `$SUDO_USER`'s home and prepends it to PATH:
```bash
for _dir in "/home/${SUDO_USER}/.nvm/versions/node"/*/bin "$HOME/.nvm/versions/node"/*/bin; do
    [[ -d "$_dir" ]] && export PATH="$_dir:$PATH" && break
done
```

---

## Verified Deployment Status

Deployment verified on **2026-03-01** with the following results:

| Component | Status | Details |
|-----------|--------|---------|
| Laravel instance :8000 | **OK** | Response time: 26ms |
| Laravel instance :8001 | **OK** | Response time: 21ms |
| Laravel instance :8002 | **OK** | Response time: 23ms |
| MySQL Master :3306 | **OK** | Connected, 6 tasks in database |
| MySQL Slave :3307 | **OK** | Connected, 6 tasks replicated |
| Replication | **OK** | IO: Yes, SQL: Yes, Lag: 0s |
| Queue Worker @1 | **OK** | systemd active |
| Queue Worker @2 | **OK** | systemd active |
| Scheduler Timer | **OK** | systemd active |
| Nginx HTTP→HTTPS | **OK** | 301 redirect |
| Nginx HTTPS LB | **OK** | Response time: 24ms |
| CRUD via API | **OK** | POST → master → slave read confirmed |

**Health check output:**
```
All 14 checks passed
```

### Software Versions

| Software | Version |
|----------|---------|
| PHP | 8.3.30 |
| Laravel | 11.48.0 |
| Composer | 2.9.5 |
| MySQL | 8.0.45 |
| Nginx | 1.24.0 |
| Node.js | v24.11.0 |
| npm | 11.6.2 |
| Vite | 6.4.1 |
| OS | Ubuntu (AppArmor enabled) |

---