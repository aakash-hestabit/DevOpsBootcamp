# Reverse Proxy Guide

Configuration reference for Nginx and Apache2 reverse proxies.

---

## Nginx Reverse Proxy

### How It Works

Nginx receives client requests on port 80/443 and forwards them to a backend application server running on localhost. The backend (Node.js, Python, PHP) never directly handles TLS or external connections.

```
Client → Nginx (80/443) → Backend App (3000/8000/9000)
```

### Key Directives

| Directive | Purpose |
|-----------|---------|
| `proxy_pass` | Backend URL to forward requests to |
| `proxy_set_header Host $host` | Preserve original host header |
| `proxy_set_header X-Real-IP $remote_addr` | Pass real client IP |
| `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for` | Append to forwarded-for chain |
| `proxy_set_header X-Forwarded-Proto $scheme` | Tell backend if request was HTTPS |
| `proxy_http_version 1.1` | Required for keepalive and WebSocket |

### WebSocket Support (Node.js)

WebSocket upgrade headers must be forwarded explicitly:

```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

### Generated Configs

Run `nginx_reverse_proxy.sh` to generate configs saved to `/etc/nginx/sites-available/`:

| Config | Backend | Port |
|--------|---------|------|
| `nodejs-app.conf` | Node.js with WebSocket | 3000 |
| `python-app.conf` | Python (Gunicorn/uWSGI) | 8000 |
| `php-app.conf` | PHP-FPM via FastCGI | 9000 |

### Usage

```bash
sudo ./scripts/nginx_reverse_proxy.sh
sudo ./scripts/nginx_reverse_proxy.sh --domain myapp.local
```

---

## Apache2 Reverse Proxy

### Key Directives

| Directive | Purpose |
|-----------|---------|
| `ProxyPass` | Forward requests to backend |
| `ProxyPassReverse` | Rewrite Location headers from backend |
| `ProxyPreserveHost On` | Preserve original Host header |
| `RequestHeader set X-Forwarded-Proto "https"` | Inform backend of original scheme |

### Generated Configs

Run `apache_reverse_proxy.sh` to generate configs saved to `/etc/apache2/sites-available/`:

| Config | Backend |
|--------|---------|
| `nodejs-proxy.conf` | Node.js on port 3000 |
| `python-proxy.conf` | Python on port 8000 |

### Usage

```bash
sudo ./scripts/apache_reverse_proxy.sh
sudo ./scripts/apache_reverse_proxy.sh --domain myapp.local
```

---

## HTTP to HTTPS Redirect

Both Nginx and Apache configs include a port 80 server block that returns a 301 redirect to HTTPS:

Nginx:
```nginx
server {
    listen 80;
    server_name app.devops.local;
    return 301 https://$server_name$request_uri;
}
```

Apache:
```apache
<VirtualHost *:80>
    ServerName app.devops.local
    Redirect permanent / https://app.devops.local/
</VirtualHost>
```

---

## Testing a Reverse Proxy

Start a simple backend:

```bash
# Node.js
node -e "require('http').createServer((req,res)=>res.end('node ok')).listen(3000)"

# Python
python3 -m http.server 8000
```

Test through the proxy:

```bash
curl -k https://node.devops.local
curl -k https://python.devops.local
```

The `-k` flag skips SSL verification for self-signed certificates.
