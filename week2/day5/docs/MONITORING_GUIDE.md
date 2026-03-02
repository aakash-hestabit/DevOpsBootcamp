# Monitoring Guide

## Overview

Multi-layered monitoring for all 3 production stacks covering system resources, application health, database status, and alerting.

---

## Monitoring Tools

| Tool | Purpose | Location |
|------|---------|----------|
| `monitoring_dashboard.sh` | Real-time TUI dashboard | `./monitoring_dashboard.sh` |
| `monitoring/uptime_monitor.sh` | Uptime tracking + CSV logging | `./monitoring/uptime_monitor.sh` |
| `monitoring/alert_system.sh` | Threshold-based alerting | `./monitoring/alert_system.sh` |
| `monitoring/metrics_collector.sh` | Metrics collection for trending | `./monitoring/metrics_collector.sh` |
| `health_check_all_stacks.sh` | Multi-level health checks | `./health_check_all_stacks.sh` |

---

## Dashboard

Real-time terminal dashboard showing all stacks at a glance.

```bash
# Start dashboard (refreshes every 5 seconds)
./monitoring_dashboard.sh

# Custom refresh interval
./monitoring_dashboard.sh --interval 10
```

**Displays:**
- CPU, RAM, Disk utilization with color-coded bars
- Stack 1: Express.js (3/3) + Next.js (2/2) + MongoDB (3/3) status
- Stack 2: Laravel (3/3) + Queue Workers (2/2) + MySQL replication status
- Stack 3: FastAPI (3/3) + Next.js (2/2) + MySQL connections
- Nginx load balancer status
- Recent alerts

---

## Health Checks

Three levels of health verification:

```bash
# Level 1 — Infrastructure (Nginx, DBs, disk, memory)
./health_check_all_stacks.sh --level 1

# Level 2 — Applications (processes, ports, HTTP endpoints)
./health_check_all_stacks.sh --level 2

# Level 3 — Business logic (DB queries, API functional tests)
./health_check_all_stacks.sh --level 3

# All levels
./health_check_all_stacks.sh --level all
```

---

## Uptime Monitoring

Continuous uptime tracking with CSV output for reporting.

```bash
# Start continuous monitoring (60s interval)
./monitoring/uptime_monitor.sh --interval 60

# Single check
./monitoring/uptime_monitor.sh --once

# View daily report
./monitoring/uptime_monitor.sh --report
```

**Data stored at:** `var/log/uptime/uptime_YYYYMMDD.csv`

**CSV format:** `timestamp,endpoint_name,status,http_code,response_ms`

---

## Alert System

Threshold-based monitoring with escalation levels.

```bash
# Start continuous alerting (30s interval)
./monitoring/alert_system.sh --interval 30

# Single check
./monitoring/alert_system.sh --once

# View alert summary
./monitoring/alert_system.sh --summary
```

### Alert Thresholds

| Resource | Warning | Critical |
|----------|---------|----------|
| CPU | 70% | 90% |
| Memory | 75% | 90% |
| Disk | 80% | 95% |
| Response Time | 500ms | 2000ms |

### Alert Levels

| Level | Action |
|-------|--------|
| INFO | Logged only |
| WARNING | Logged + displayed |
| CRITICAL | Logged + displayed + email notification (if configured) |

**Alert log:** `var/log/alerts.log`

---

## Metrics Collection

Background metrics collection for trending and capacity planning.

```bash
# Start collector (60s interval)
./monitoring/metrics_collector.sh --interval 60

# Single collection
./monitoring/metrics_collector.sh --once

# Export day's data as JSON
./monitoring/metrics_collector.sh --export 20260302
```

### Metrics Collected

**System metrics** (every interval):
- CPU load average
- Memory total/used/percentage
- Disk usage
- Swap usage
- Network bytes (rx/tx)
- Process count

**Application metrics** (every interval):
- HTTP status code per endpoint
- Response time in ms
- UP/DOWN status

**Database metrics** (every interval):
- MongoDB active connections
- MySQL threads connected
- MySQL total queries

**Data stored at:** `var/log/metrics/`

---

## Recommended Monitoring Schedule

| Monitor | Interval | Run As |
|---------|----------|--------|
| Dashboard | 5s (interactive) | Manual |
| Uptime monitor | 60s | cron or systemd timer |
| Alert system | 30s | cron or systemd timer |
| Metrics collector | 60s | cron or systemd timer |
| Full health check | 5 min | cron |

### Crontab Example

```cron
# Health check every 5 minutes
*/5 * * * * /path/to/health_check_all_stacks.sh --level all >> /var/log/health_check.log 2>&1

# Metrics collection every minute
* * * * * /path/to/monitoring/metrics_collector.sh --once >> /dev/null 2>&1

# Uptime check every minute
* * * * * /path/to/monitoring/uptime_monitor.sh --once >> /dev/null 2>&1

# Alert check every 30 seconds (use systemd timer for sub-minute)
* * * * * /path/to/monitoring/alert_system.sh --once >> /dev/null 2>&1
```
