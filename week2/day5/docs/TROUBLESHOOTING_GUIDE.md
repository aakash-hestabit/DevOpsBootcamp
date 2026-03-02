# Troubleshooting Guide

## Quick Diagnostics

```bash
# Check all stacks at once
./health_check_all_stacks.sh --level all

# Monitoring dashboard (real-time)
./monitoring_dashboard.sh

# Alert summary
./monitoring/alert_system.sh --summary
```

---

## Common Issues

### 1. Service Won't Start

**Symptoms:** `systemctl status` shows `failed` or `inactive`

**Stack 1 (PM2):**
```bash
pm2 status                          # Check process status
pm2 logs --lines 50                 # View recent logs
pm2 describe express-api-3000       # Detailed process info
pm2 restart all                     # Restart all processes
```

**Stack 2 (systemd):**
```bash
sudo systemctl status laravel-app-8000
sudo journalctl -u laravel-app-8000 --since "5 min ago"
# Check PHP errors
tail -50 /var/log/laravel/laravel.log
# Restart
sudo systemctl restart laravel-app-800{0,1,2}
```

**Stack 3 (systemd + PM2):**
```bash
sudo systemctl status fastapi-8003
sudo journalctl -u fastapi-8003 --since "5 min ago"
pm2 status                          # Next.js processes
```

### 2. Nginx 502 Bad Gateway

**Cause:** Backend application not running or wrong port.

```bash
# Check if backends are listening
ss -tlnp | grep -E '(3000|3001|8000|8003)'

# Test backend directly
curl -v http://127.0.0.1:3000/api/health
curl -v http://127.0.0.1:8000/api/health
curl -v http://127.0.0.1:8003/health

# Check Nginx config
sudo nginx -t
sudo tail -20 /var/log/nginx/error.log

# Restart Nginx
sudo systemctl reload nginx
```

### 3. Nginx 504 Gateway Timeout

**Cause:** Backend too slow to respond.

```bash
# Check backend response time
time curl http://127.0.0.1:8000/api/health

# Increase proxy timeout in Nginx config
# proxy_read_timeout 60s;
# proxy_connect_timeout 10s;
sudo nginx -t && sudo systemctl reload nginx
```

### 4. Database Connection Refused

**MongoDB (Stack 1):**
```bash
# Check replica set status
mongosh "mongodb://devops:Devops%40123@localhost:27017/admin" \
    --eval "rs.status()"

# Check if mongod is running
sudo systemctl status mongod-node{1,2,3}

# Check logs
sudo tail -50 /var/log/mongodb/mongod-node1.log

# Restart replica set
sudo systemctl restart mongod-node{1,2,3}
```

**MySQL (Stacks 2 & 3):**
```bash
# Check MySQL status
sudo systemctl status mysql

# Test connection
mysql -u root -p -e "SELECT 1"

# Check max connections
mysql -u root -e "SHOW STATUS LIKE 'Threads_connected'"
mysql -u root -e "SHOW VARIABLES LIKE 'max_connections'"

# Check replication (Stack 2)
mysql -h 127.0.0.1 -P 3307 -u root -e "SHOW SLAVE STATUS\G"
```

### 5. MySQL Replication Broken

**Symptoms:** Slave_IO_Running or Slave_SQL_Running = No

```bash
# Check slave status
mysql -h 127.0.0.1 -P 3307 -u root -e "SHOW SLAVE STATUS\G"

# Fix: Reset and re-sync
mysql -h 127.0.0.1 -P 3307 -u root -e "STOP SLAVE; RESET SLAVE;"

# Get master position
MASTER_STATUS=$(mysql -h 127.0.0.1 -P 3306 -u root -e "SHOW MASTER STATUS\G")
# Re-configure slave with correct binlog position

# Alternative: Full re-sync
mysqldump -h 127.0.0.1 -P 3306 -u root --all-databases --master-data=2 > /tmp/master_dump.sql
mysql -h 127.0.0.1 -P 3307 -u root < /tmp/master_dump.sql
```

### 6. High Memory Usage

```bash
# Find top memory consumers
ps aux --sort=-%mem | head -20

# Check Node.js heap
pm2 monit

# Restart memory-heavy processes
pm2 restart express-api-3000 --max-memory-restart 500M

# Check for memory leaks
pm2 describe express-api-3000 | grep "restart time"
# Many restarts may indicate a leak
```

### 7. High CPU / Slow Response Times

```bash
# Check system load
top -bn1 | head -5
awk '{print $1, $2, $3}' /proc/loadavg

# Find CPU-intensive processes
ps aux --sort=-%cpu | head -10

# Enable slow query log (MySQL)
mysql -u root -e "SET GLOBAL slow_query_log = 'ON'; SET GLOBAL long_query_time = 1;"

# Check MongoDB slow queries
mongosh --eval "db.setProfilingLevel(1, { slowms: 100 })"
```

### 8. Disk Space Full

```bash
# Check disk usage
df -h /
du -sh /var/log/* | sort -rh | head -10

# Clean old logs
sudo journalctl --vacuum-time=7d
sudo find /var/log -name "*.gz" -mtime +30 -delete

# Run log rotation
sudo logrotate -f /etc/logrotate.conf
```

### 9. Redis Connection Issues

```bash
# Check Redis status
redis-cli -a 'DevOpsRedis@123' ping

# Check memory
redis-cli -a 'DevOpsRedis@123' INFO memory

# Check connected clients
redis-cli -a 'DevOpsRedis@123' INFO clients

# Flush cache if corrupted
redis-cli -a 'DevOpsRedis@123' FLUSHALL
```

### 10. SSL Certificate Issues

```bash
# Check certificate expiry
echo | openssl s_client -connect stack1.devops.local:443 2>/dev/null | openssl x509 -noout -dates

# Regenerate self-signed cert
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/stack1.key \
    -out /etc/ssl/certs/stack1.crt \
    -subj "/CN=stack1.devops.local"

sudo systemctl reload nginx
```

---

## Emergency Procedures

### Full Stack Rollback
```bash
# List available backups
./rollback.sh --list

# Rollback specific stack
./rollback.sh --stack 1 --auto
./rollback.sh --stack 2 --auto
./rollback.sh --stack 3 --auto
```

### Emergency Stop All Services
```bash
# Stop all applications
pm2 stop all
sudo systemctl stop laravel-app-800{0,1,2}
sudo systemctl stop laravel-worker@{1,2}
sudo systemctl stop laravel-scheduler
sudo systemctl stop fastapi-800{3,4,5}

# Stop Nginx (takes everything offline)
sudo systemctl stop nginx
```

### Emergency Restart
```bash
# Restart in order: databases → applications → proxy
sudo systemctl restart mongod-node{1,2,3} mysql
sleep 5
pm2 restart all
sudo systemctl restart laravel-app-800{0,1,2} fastapi-800{3,4,5}
sleep 3
sudo systemctl restart nginx
```

---

## Log Locations

| Component | Log Location |
|-----------|-------------|
| Nginx Access | `/var/log/nginx/access.log` |
| Nginx Error | `/var/log/nginx/error.log` |
| PM2 | `~/.pm2/logs/` |
| Laravel | `/var/log/laravel/laravel.log` |
| FastAPI | `journalctl -u fastapi-8003` |
| MongoDB | `/var/log/mongodb/mongod-node*.log` |
| MySQL | `/var/log/mysql/error.log` |
| Redis | `/var/log/redis/redis-server.log` |
| Alerts | `var/log/alerts.log` |
