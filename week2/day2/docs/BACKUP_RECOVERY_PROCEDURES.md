# BACKUP_RECOVERY_PROCEDURES.md
# Backup & Recovery Procedures

---

## Backup Strategy

| Type    | Frequency      | Retention |
|---------|----------------|-----------|
| Daily   | Every day 2 AM | 7 days    |
| Weekly  | Every Sunday   | 4 weeks   |
| Monthly | 1st of month   | 12 months |

Backups stored at `/backups/<database>/<type>/<YYYY-MM-DD>/`

---

## Running Backups

### Automated (cron)
```bash
0 2 * * * /path/to/db_backup_automation.sh
```

### Manual
```bash
sudo ./db_backup_automation.sh              # all databases
sudo ./db_backup_automation.sh --type postgresql
sudo ./db_backup_automation.sh --type mysql
sudo ./db_backup_automation.sh --type mongodb
sudo ./db_backup_automation.sh --verbose    # verbose output
```

---

## Backup Methods Used

**PostgreSQL** — `pg_dump -Fc` (custom format, compressed, supports parallel restore)  
**MySQL** — `mysqldump --single-transaction` (consistent, no table locks)  
**MongoDB** — `mongodump --gzip --archive` (single compressed archive)

---

## Restore Procedure

Run the interactive restore tool:

```bash
sudo ./db_restore.sh
```

The tool will:
1. List available backups with size and timestamp
2. Prompt you to select a backup and target database
3. Create a **safety backup** of the current database (stored in `/backups/<dbtype>/pre_restore/`)
4. Validate the backup file (gzip integrity check)
5. Drop and recreate the target database (PostgreSQL only)
6. Restore the selected backup
7. Verify the restore (table/collection count)
8. Log the operation to `var/log/apps/db_restore.log`

---

## Manual Restore Commands

> **Note**: Safety backups are **automatically created** in `/backups/<dbtype>/pre_restore/` before restore operations begin.

### PostgreSQL
```bash
# Drop & recreate database
PGPASSWORD=password123 psql -U dbadmin -h 127.0.0.1 postgres -c "DROP DATABASE IF EXISTS targetdb;"
PGPASSWORD=password123 psql -U dbadmin -h 127.0.0.1 postgres -c "CREATE DATABASE targetdb;"

# Restore from backup
zcat backup.dump.gz | PGPASSWORD=password123 pg_restore -U dbadmin -h 127.0.0.1 -d targetdb --no-owner
```

### MySQL
```bash
# Create database if needed
mysql -u root -p -h localhost -e "CREATE DATABASE IF NOT EXISTS targetdb;"

# Restore from backup
zcat backup.sql.gz | mysql -u root -p -h localhost targetdb
```

### MongoDB
```bash
mongorestore -u mongoadmin -p password --authenticationDatabase admin \
  --gzip --archive=backup.archive.gz --drop
```

---

## Backup Report
The backup script generates a daily report at `var/log/apps/backup_report_YYYY-MM-DD.txt` and logs to `var/log/apps/db_backup_automation.log`

Report contains:
- Backup type (daily/weekly/monthly)
- All backup files created with sizes
- Retention policy information

Example:
```
POSTGRESQL:
  test_20260223_130324.dump.gz  4.0K
  testdb_20260223_130324.dump.gz  4.0K

MYSQL:
  appdb_20260223_130404.sql.gz  4.0K
  testdb_20260223_130404.sql.gz  4.0K

MONGODB:
  mongodb_20260223_130627.archive.gz  4.0K
```

---

## Recovery Testing
Run monthly:
```bash
sudo ./db_restore.sh   # restore to a test database
```

---

## Database Health Monitoring

Monitor database connectivity, performance, and resource usage:

```bash
sudo ./db_health_monitor.sh              # basic health check
sudo ./db_health_monitor.sh --verbose    # detailed output
```

Checks performed:
- Service status (running/stopped)
- Database connectivity
- Connection pool usage (alerts if >80%)
- Database sizes
- Disk usage (alerts if >85%)
- Long-running queries

---

## Performance Baseline Testing

Benchmark database INSERT/SELECT/UPDATE operations:

```bash
sudo ./db_performance_baseline.sh                    # 1000 iterations
sudo ./db_performance_baseline.sh --iterations 500   # custom count
sudo ./db_performance_baseline.sh --verbose          # detailed output
```

Results saved to `var/log/apps/db_performance_baseline.txt`

---

## Troubleshooting

**MySQL Connection Errors**: Use `localhost` instead of `127.0.0.1`
- MySQL only grants 'root'@'localhost' by default
- Fix: `GRANT ALL ON *.* TO 'root'@'localhost';`

**PostgreSQL Timeout**: Verify server running
- Check: `systemctl status postgresql`
- Test: `PGPASSWORD=password123 psql -U dbadmin -h 127.0.0.1 postgres`

**MongoDB Auth Issues**: Check database parameter
- Use: `--authenticationDatabase admin`
- Test: `mongosh --username mongoadmin --password password --authenticationDatabase admin`

**Backup Validation**: Test backup integrity
- Check: `gzip -t backup.dump.gz`
- Disk: `df -h /backups`
