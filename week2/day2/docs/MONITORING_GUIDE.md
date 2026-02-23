# MONITORING_GUIDE.md
# Database Health Monitoring Guide

---

## Health Monitor Script

`db_health_monitor.sh` checks all three databases and logs results to:  
`var/log/apps/db_health_YYYY-MM-DD.log`

---

## Setup: Cron (every 5 minutes)

```bash
sudo crontab -e
# Add:
*/5 * * * * /path/to/db_health_monitor.sh
```

---

## Checks Performed

**PostgreSQL:**
- Service status (`systemctl`)
- Connection test
- Active connections vs `max_connections`
- Database sizes
- Long-running queries (> 30s)
- Replication lag (if replica)

**MySQL:**
- Service status
- Connection test
- Thread connections vs `max_connections`
- InnoDB buffer pool usage
- Cumulative slow query count

**MongoDB:**
- Service status
- Ping test
- Replica set status
- Database sizes
- Total index count

---

## Alert Thresholds

| Metric                | Threshold        | Action              |
|-----------------------|------------------|---------------------|
| Connections           | > 80% of max     | Logged as ALERT     |
| Disk usage            | > 85%            | Logged as ALERT     |
| Slow queries (MySQL)  | > 100 cumulative | Logged as ALERT     |
| Long queries (PG)     | > 30 seconds     | Logged as ALERT     |

Alerts appear in the report with `ALERT:` prefix.

---

## Reading Reports

```bash
# Today's report
cat var/log/apps/db_health_$(date '+%Y-%m-%d').log

# Only alerts
grep "ALERT" var/log/apps/db_health_$(date '+%Y-%m-%d').log

# Run manually with verbose output
sudo ./db_health_monitor.sh --verbose
```

---

## Extending Alerts

To add email notifications, append to the script's `alert()` function:
```bash
alert() {
    ALERTS="${ALERTS}ALERT: $1\n"
    echo "ALERT: $1" | mail -s "DB Alert: $1" admin@example.com
}
```
