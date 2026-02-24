# Web Server Setup Guide

Manual installation steps documented from the automated setup scripts.

---

## Nginx

### 1. Install Nginx

```bash
sudo apt update
sudo apt install -y nginx curl
nginx -v
```

### 2. Configure nginx.conf

Edit `/etc/nginx/nginx.conf`:

```nginx
user www-data;
worker_processes auto;

events {
    worker_connections 1024;
    multi_accept on;
    use epoll;
}

http {
    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;
    server_tokens off;

    # Gzip
    gzip on;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript;

    include /etc/nginx/mime.types;
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
```

### 3. Create Directory Structure

```bash
sudo mkdir -p /etc/nginx/sites-available
sudo mkdir -p /etc/nginx/sites-enabled
sudo mkdir -p /var/www/html
```

### 4. Create Default Server Block

Create `/etc/nginx/sites-available/default`:

```nginx
server {
    listen 80 default_server;
    root /var/www/html;
    index index.html;
    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

Enable it:

```bash
sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
```

### 5. Configure Log Rotation

Create `/etc/logrotate.d/nginx`:

```
/var/log/nginx/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        kill -USR1 $(cat /run/nginx.pid)
    endscript
}
```

### 6. Start and Enable

```bash
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl start nginx
```

### 7. Verify

```bash
curl -I http://localhost
# Expected: HTTP/1.1 200 OK
```

---

## Apache2

### 1. Install Apache2

```bash
sudo apt update
sudo apt install -y apache2 curl
apache2 -v
```

### 2. Enable Required Modules

```bash
sudo a2enmod proxy proxy_http ssl rewrite headers mpm_event
sudo a2dismod mpm_prefork   # disable if loaded
```

### 3. Configure MPM Event

Create `/etc/apache2/conf-available/mpm-event-tuning.conf`:

```apache
<IfModule mpm_event_module>
    StartServers         2
    MinSpareThreads     25
    MaxSpareThreads     75
    ThreadsPerChild     25
    MaxRequestWorkers  150
    MaxConnectionsPerChild 1000
</IfModule>

KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5
ServerTokens Prod
ServerSignature Off
```

Enable it:

```bash
sudo a2enconf mpm-event-tuning
```

### 4. Add Port 8080

Edit `/etc/apache2/ports.conf` and add:

```
Listen 8080
```

### 5. Create Default Virtual Host

Create `/etc/apache2/sites-available/000-default.conf`:

```apache
<VirtualHost *:8080>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined

    <Directory /var/www/html>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
```

Enable it:

```bash
sudo a2ensite 000-default
```

### 6. Start and Enable

```bash
sudo apachectl configtest
sudo systemctl enable apache2
sudo systemctl start apache2
```

### 7. Verify

```bash
curl -I http://localhost:8080
# Expected: HTTP/1.1 200 OK or HTTP/1.1 403 Forbidden (both confirm Apache is running)
```

---

## Service Management

| Action | Nginx | Apache |
|--------|-------|--------|
| Start | `systemctl start nginx` | `systemctl start apache2` |
| Stop | `systemctl stop nginx` | `systemctl stop apache2` |
| Reload | `systemctl reload nginx` | `systemctl reload apache2` |
| Test config | `nginx -t` | `apachectl configtest` |
| Status | `systemctl status nginx` | `systemctl status apache2` |
