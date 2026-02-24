# Performance Tuning Guide

Nginx and Apache optimization parameters and the logic behind the automated tuner.

---

## Automated Tuner

```bash
sudo ./scripts/webserver_performance_tuner.sh
sudo ./scripts/webserver_performance_tuner.sh --dry-run   # preview changes
```

The tuner detects CPU cores and RAM, calculates optimal values, backs up original configs, applies changes, and generates a report at `var/log/apps/performance_tuning_YYYY-MM-DD.txt`.

---

## Nginx Parameters

### Worker Processes

```nginx
worker_processes auto;  # Set to number of CPU cores
```

Use `auto` or set explicitly. More workers than cores provide no benefit and wastes memory.

### Worker Connections

```nginx
worker_connections 1024;  # 2048 for servers with 4GB+ RAM
```

Maximum simultaneous connections per worker. Total max connections = `worker_processes × worker_connections`.

### Keepalive Timeout

```nginx
keepalive_timeout 65;
```

How long to keep idle client connections open. Higher values reduce handshake overhead but hold connections longer.

### Buffer Sizes

```nginx
client_body_buffer_size    128k;   # 256k–512k for high-traffic servers
client_max_body_size       16m;
client_header_buffer_size  1k;
large_client_header_buffers 4 16k;
proxy_buffer_size          4k;
proxy_buffers              8 16k;
```

Buffers trade memory for reduced disk I/O. Size them for your typical request sizes.

### Gzip Compression

```nginx
gzip on;
gzip_comp_level 6;   # Level 1 (fast) to 9 (max). Level 6 is the best trade-off.
gzip_types text/plain text/css application/json application/javascript;
gzip_min_length 256; # Don't compress very small responses
```

### Open File Cache

```nginx
open_file_cache          max=1000 inactive=20s;
open_file_cache_valid    30s;
open_file_cache_min_uses 2;
```

Caches file descriptors to avoid stat() calls on every request.

---

## Apache Parameters

### MaxRequestWorkers

```apache
MaxRequestWorkers 150
```

Maximum simultaneous requests. Formula used by tuner: `(RAM × 0.8) / 25MB per worker`. Clamped 50–400.

### ThreadsPerChild

```apache
ThreadsPerChild 25
```

Threads per worker process. Total capacity = `MaxRequestWorkers`.

### KeepAlive

```apache
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5
```

Short `KeepAliveTimeout` (5s) is appropriate for high-traffic sites to avoid holding connections.

---

## Key Metrics to Monitor After Tuning

| Metric | Tool | Target |
|--------|------|--------|
| Active connections | `ss -tnp \| grep nginx` | Below `worker_connections` |
| Worker count | `ps aux \| grep apache2` | Below `MaxRequestWorkers` |
| Response time | `curl -w "%{time_total}"` | Under 200ms |
| Error rate | `/var/log/nginx/error.log` | 0 critical errors |
| CPU usage | `top` or `htop` | Below 80% sustained |

---

## Backups

The tuner creates timestamped backups before applying changes:

```
/etc/nginx/nginx.conf.bak.YYYYMMDDHHMMSS
/etc/apache2/apache2.conf.bak.YYYYMMDDHHMMSS
```

To restore:

```bash
sudo cp /etc/nginx/nginx.conf.bak.TIMESTAMP /etc/nginx/nginx.conf
sudo systemctl reload nginx
```
