# Rollback Procedures

## Overview

The rollback system supports restoring any stack to a previous known-good state. Backups are created automatically during deployments and can be triggered manually.

---

## Quick Reference

```bash
# List all available backups
./rollback.sh --list

# Rollback with interactive selection
./rollback.sh --stack 1
./rollback.sh --stack 2
./rollback.sh --stack 3

# Automatic rollback (selects most recent backup)
./rollback.sh --stack 1 --auto
./rollback.sh --stack 2 --auto
./rollback.sh --stack 3 --auto
```

---

## What Gets Rolled Back

| Component | Stack 1 | Stack 2 | Stack 3 |
|-----------|---------|---------|---------|
| Application code | ✓ | ✓ | ✓ |
| Dependencies | ✓ (node_modules) | ✓ (vendor) | ✓ (venv) |
| Build artifacts | ✓ (.next) | — | ✓ (.next) |
| Environment files | ✓ (.env) | ✓ (.env) | ✓ (.env) |
| PM2 config | ✓ | — | ✓ |
| Systemd units | — | ✓ | ✓ |
| Nginx config | ✓ | ✓ | ✓ |
| Database | Not rolled back (see below) |

---

## Rollback Process

### Step 1: Pre-Rollback Safety Backup
Before any rollback, the current state is backed up:
```
backups/pre-rollback-stack1-YYYYMMDD-HHMMSS.tar.gz
```

### Step 2: Service Stop
- PM2: `pm2 stop` relevant processes
- systemd: `systemctl stop` relevant services
- Nginx: remains running (serves 503 briefly)

### Step 3: Restore Files
Selected backup is extracted over the application directory.

### Step 4: Service Restart
Services are restarted in correct order:
1. Database connections verified
2. Application processes started
3. Health checks run
4. Nginx reloaded if config changed

### Step 5: Verification
Automated health check runs against all restored endpoints.

---

## Backup Locations

| Stack | Backup Directory |
|-------|-----------------|
| Stack 1 | `backups/stack1-YYYYMMDD-HHMMSS.tar.gz` |
| Stack 2 | `backups/stack2-YYYYMMDD-HHMMSS.tar.gz` |
| Stack 3 | `backups/stack3-YYYYMMDD-HHMMSS.tar.gz` |

Backups are created:
- Before each deployment (`deploy_stack*.sh`)
- Before each rollback (safety backup)
- Before zero-downtime deployments

---

## Database Rollback

Database rollback is **intentionally excluded** from automatic rollback because:
- Data loss risk is high
- Migrations may not be reversible
- Replication state must be preserved

### Manual Database Rollback

**MongoDB (Stack 1):**
```bash
# Point-in-time recovery using oplog
mongorestore --oplogReplay --oplogLimit "$(date -u +%Y-%m-%dT%H:%M:%S)" dump/

# Or restore from mongodump backup
mongorestore --uri "mongodb://devops:Devops@123@localhost:27017" dump/
```

**MySQL (Stacks 2 & 3):**
```bash
# Restore from mysqldump
mysql -u root -p < backup_YYYYMMDD.sql

# Point-in-time recovery using binlog
mysqlbinlog --stop-datetime="2026-03-02 12:00:00" /var/log/mysql/binlog.000001 | mysql -u root -p
```

---

## Rollback Decision Matrix

| Scenario | Action |
|----------|--------|
| Application crash after deploy | `./rollback.sh --stack N --auto` |
| Performance degradation | Check if caching/config changed, then rollback |
| Database migration failure | Rollback app code + `php artisan migrate:rollback` or Alembic downgrade |
| Nginx config error | `sudo nginx -t` + restore from backup |
| Complete stack failure | Rollback all 3 stacks + verify databases |

---

## Testing Rollback

Regularly test the rollback procedure:

```bash
# 1. Create a known-good backup
./rollback.sh --list  # Note latest backup timestamp

# 2. Make a non-breaking change
echo "# test" >> stack1_next_node_mongodb/backend/server.js

# 3. Rollback
./rollback.sh --stack 1 --auto

# 4. Verify the change was reverted
tail -1 stack1_next_node_mongodb/backend/server.js
```
