# Load Balancing Guide

Nginx load balancer configuration with multiple algorithms, health checks, and failover.

---

## Overview

```
Clients → Nginx Load Balancer (port 80) → Upstream Servers (3000+)
```

Nginx distributes incoming requests across multiple backend servers using the configured algorithm. Unhealthy servers are automatically removed from rotation.

---

## Load Balancing Algorithms

### Round-Robin (default)

Requests are distributed sequentially across all servers. Best for homogeneous servers with similar capacity.

```nginx
upstream app_cluster {
    server 192.168.1.10:3000 max_fails=3 fail_timeout=30s;
    server 192.168.1.11:3000 max_fails=3 fail_timeout=30s;
    server 192.168.1.12:3000 max_fails=3 fail_timeout=30s;
}
```

### Least Connections (`least_conn`)

Each new request goes to the server with the fewest active connections. Best for varying request durations (e.g., API servers, long-poll).

```nginx
upstream app_cluster {
    least_conn;
    server 192.168.1.10:3000 max_fails=3 fail_timeout=30s;
    server 192.168.1.11:3000 max_fails=3 fail_timeout=30s;
}
```

### IP Hash (`ip_hash`)

Each client IP always routes to the same server. Provides sticky sessions without shared session storage.

```nginx
upstream app_cluster {
    ip_hash;
    server 192.168.1.10:3000;
    server 192.168.1.11:3000;
}
```

---

## Health Checks

Nginx uses passive health checks based on connection failures:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `max_fails` | 3 | Failed attempts before server is marked down |
| `fail_timeout` | 30s | Period to count failures; also how long server stays down |

```nginx
server 192.168.1.10:3000 max_fails=3 fail_timeout=30s;
```

After `fail_timeout` seconds, Nginx will try the server again. If it responds, it's restored to rotation.

---

## Backup Server

A backup server receives traffic only when all primary servers are down:

```nginx
upstream app_cluster {
    server 192.168.1.10:3000 max_fails=3 fail_timeout=30s;
    server 192.168.1.11:3000 max_fails=3 fail_timeout=30s;
    server 192.168.1.20:3000 backup;
}
```

---

## Failover Configuration

`proxy_next_upstream` tells Nginx which errors should trigger trying the next server:

```nginx
proxy_next_upstream error timeout http_500 http_502 http_503 http_504;
```

---

## Generating a Load Balancer Config

```bash
sudo ./scripts/nginx_load_balancer.sh
# Enter number of primary servers (2-5)
# Enter each server IP:PORT
# Enter backup server IP:PORT

# Or with flags
sudo ./scripts/nginx_load_balancer.sh --algorithm least_conn
sudo ./scripts/nginx_load_balancer.sh --algorithm ip_hash --sticky
sudo ./scripts/nginx_load_balancer.sh --domain lb.myapp.local
```

Generated file: `/etc/nginx/sites-available/load-balancer.conf`

---

## Testing Load Balancer

Run a simple server on multiple ports to simulate backends:

```bash
# On backend server 1
python3 -m http.server 3000

# On backend server 2
python3 -m http.server 3001
```

Test distribution:

```bash
for i in {1..10}; do curl -s http://lb.devops.local; done
```

Check the access log to confirm requests are distributed:

```bash
tail -f /var/log/nginx/lb.access.log
```

---

## Status Endpoint

The generated load balancer config includes a health check endpoint:

```bash
curl http://lb.devops.local/lb-status
# Response: load-balancer-ok
```
