# SSL Certificate Guide

Setup, management, and renewal for self-signed and Let's Encrypt certificates.

---

## Self-Signed Certificates

Best for development and internal services where browser trust is not required.

### Generate Manually

```bash
# Generate private key
openssl genrsa -out /etc/ssl/private/devops.local.key 2048

# Generate certificate (valid 365 days)
openssl req -new -x509 \
  -key /etc/ssl/private/devops.local.key \
  -out /etc/ssl/certs/devops.local.crt \
  -days 365 \
  -subj "/C=US/ST=State/L=City/O=DevOps Bootcamp/CN=devops.local"

# Secure the key
chmod 600 /etc/ssl/private/devops.local.key
```

### Use in Nginx

```nginx
ssl_certificate     /etc/ssl/certs/devops.local.crt;
ssl_certificate_key /etc/ssl/private/devops.local.key;
```

### Using the Script

```bash
sudo ./scripts/ssl_certificate_generator.sh
# Choose option 1
# Enter domain, organization, country, state, city
```

---

## Let's Encrypt Certificates

For production servers with a public domain and internet-accessible port 80.

### Prerequisites

- A real domain pointing to your server's public IP
- Port 80 open and Nginx running

### Install certbot

```bash
sudo apt install -y certbot python3-certbot-nginx
```

### Obtain Certificate

```bash
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com \
  --email admin@yourdomain.com --agree-tos --non-interactive
```

certbot will automatically modify your Nginx config to use the new certificate.

### Using the Script

```bash
sudo ./scripts/ssl_certificate_generator.sh
# Choose option 2
# Enter domain and email
```

Auto-renewal cron is configured automatically:

```
0 3 * * 1 certbot renew --quiet --post-hook 'systemctl reload nginx'
```

---

## Certificate Renewal

### Manual Renewal Test

```bash
sudo certbot renew --dry-run
```

### Automated Renewal

```bash
sudo ./scripts/ssl_renewal_automation.sh
```

The script checks expiry dates and only renews certificates expiring within 30 days (configurable with `--threshold`).

Recommended cron:

```
0 3 * * 1 /path/to/ssl_renewal_automation.sh
```

---

## Listing Certificates

```bash
sudo ./scripts/ssl_certificate_generator.sh
# Choose option 4

# Or directly
sudo certbot certificates
ls /etc/ssl/certs/*.crt
```

---

## SSL Best Practices

The file `configs/ssl_params.conf` implements Mozilla Modern SSL configuration:

- TLSv1.2 and TLSv1.3 only
- Strong ECDHE cipher suites
- Session cache (10MB shared)
- Session tickets disabled
- OCSP stapling enabled

Include it inside any SSL `server {}` block:

```nginx
include /etc/nginx/ssl_params.conf;
```

---

## Certificate File Locations

| File | Path |
|------|------|
| Self-signed certificate | `/etc/ssl/certs/<domain>.crt` |
| Self-signed private key | `/etc/ssl/private/<domain>.key` |
| Let's Encrypt certificate | `/etc/letsencrypt/live/<domain>/fullchain.pem` |
| Let's Encrypt private key | `/etc/letsencrypt/live/<domain>/privkey.pem` |
