# Troubleshooting Guide

Common issues and solutions for Nginx, Apache, SSL, and reverse proxy configurations.

---

## Nginx

### nginx -t fails after editing config

```bash
sudo nginx -t
# Check the error message carefully — it includes the file and line number
```

Common causes: missing semicolons, unclosed braces, wrong file paths.

### Port 80 already in use

```bash
sudo ss -tlnp | grep :80
# If Apache is on port 80, either stop it or change Nginx to another port
sudo systemctl stop apache2
```

### 502 Bad Gateway

The backend application is not running or not listening on the expected port.

```bash
# Check if backend is running
ss -tlnp | grep :3000

# Start a test backend
node -e "require('http').createServer((req,res)=>res.end('ok')).listen(3000)"

# Check Nginx error log
tail -50 /var/log/nginx/error.log
```

### 403 Forbidden

Nginx cannot read the document root.

```bash
ls -la /var/www/html
# Fix permissions
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html
```

### Nginx Not Reloading After Config Change

```bash
sudo nginx -t           # Test first
sudo systemctl reload nginx   # Reload (no downtime)
# Or full restart
sudo systemctl restart nginx
```

---

## Apache

### apachectl configtest fails

```bash
sudo apachectl configtest
# Read the error and check the indicated file
```

### Port 8080 not accessible

```bash
# Confirm Listen 8080 is in ports.conf
grep -i listen /etc/apache2/ports.conf

# Check firewall
sudo ufw status
sudo ufw allow 8080
```

### mod_proxy returns "Proxy: No protocol handler was valid"

```bash
sudo a2enmod proxy proxy_http
sudo systemctl restart apache2
```

### 500 Internal Server Error

```bash
tail -50 /var/log/apache2/error.log
```

---

## SSL

### SSL certificate errors in browser

For self-signed certificates, browsers will always show a warning. Accept the exception, or add the cert to your system's trust store:

```bash
sudo cp /etc/ssl/certs/devops.local.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

### certbot: domain not reachable

Let's Encrypt must reach your server on port 80 from the internet.

```bash
# Confirm port 80 is open in firewall
sudo ufw allow 80
sudo ufw allow 443

# Test from outside
curl http://yourdomain.com
```

### Certificate expired

```bash
sudo ./scripts/ssl_renewal_automation.sh
# Or directly
sudo certbot renew
```

### Wrong certificate being served

Check which config is active:

```bash
ls -la /etc/nginx/sites-enabled/
sudo nginx -T | grep ssl_certificate
```

---

## Load Balancer

### All backends returning 502

```bash
# Check if backends are running
for port in 3000 3001 3002; do
    nc -z localhost $port && echo "Port $port: UP" || echo "Port $port: DOWN"
done
```

### Requests not distributing evenly

With `ip_hash`, all requests from the same IP always go to the same server by design. Switch to `round_robin` or `least_conn` for even distribution.

### Backup server not activating

The backup server only receives traffic when all primary servers fail their health checks. Verify `max_fails` and `fail_timeout` values, and that the primary servers are actually failing.

---

## Health Monitor

### Health monitor shows all backends DOWN

If you are running in a local/dev environment, the backend IPs in the monitor script need to match actual running services. Edit `BACKENDS` array in `webserver_health_monitor.sh`:

```bash
sudo ./scripts/webserver_health_monitor.sh --backends 127.0.0.1:3000,127.0.0.1:3001
```

### curl: (7) Failed to connect

The service is not listening on that port. Use `ss -tlnp` to verify.

---

## Log Locations

| Service | Access Log | Error Log |
|---------|-----------|-----------|
| Nginx | `/var/log/nginx/access.log` | `/var/log/nginx/error.log` |
| Apache | `/var/log/apache2/access.log` | `/var/log/apache2/error.log` |
| Script logs | `var/log/apps/` | same files |
