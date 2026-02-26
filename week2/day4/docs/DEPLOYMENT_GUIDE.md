# Deployment Guide

Covers deploying all four applications on a single Ubuntu 22.04/24.04 server.

---

## Prerequisites

```bash
# Node.js 18+
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo bash -
sudo apt install -y nodejs

# Python 3.11+
sudo apt install -y python3.11 python3.11-venv python3-pip

# PHP 8.2 + Composer
sudo apt install -y php8.2 php8.2-cli php8.2-mysql php8.2-fpm composer

# PostgreSQL client
sudo apt install -y postgresql-client

# MySQL client
sudo apt install -y mysql-client

# PM2
sudo npm install -g pm2

# Supervisor
sudo apt install -y supervisor
```

---

## Database Setup

### PostgreSQL (for Express + Next.js)
```bash
sudo -u postgres psql
CREATE DATABASE apidb;
CREATE USER apiuser WITH ENCRYPTED PASSWORD 'your_pass';
GRANT ALL PRIVILEGES ON DATABASE apidb TO apiuser;
\q
```

### MySQL (for FastAPI + Laravel)
```bash
sudo mysql
CREATE DATABASE fastapidb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE laraveldb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'fastapiuser'@'localhost' IDENTIFIED BY 'your_pass';
CREATE USER 'laraveluser'@'localhost' IDENTIFIED BY 'your_pass';
GRANT ALL PRIVILEGES ON fastapidb.* TO 'fastapiuser'@'localhost';
GRANT ALL PRIVILEGES ON laraveldb.* TO 'laraveluser'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

---

## Deploying Express API (PM2)

```bash
cd your_project_folder
git clone <repo> day4
cd day4/express-postgresql-api

cp env.example.txt .env   # fill in values
npm install --production

# Run migration
psql -h localhost -U apiuser -d apidb -f migrations/001_create_users_table.sql

# Start with PM2 (from day4 root)
cd ..
pm2 start process-management/ecosystem.config.js --only express-api --env production
pm2 save
pm2 startup  # run the printed command
```

---

## Deploying FastAPI (Supervisor)

```bash
cd day4/fastapi-mysql-api

python3.11 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

cp env.example.txt .env   # fill in values

# Run migration
mysql -u fastapiuser -p fastapidb < migrations/001_create_products_table.sql

# Install supervisor config
sudo cp supervisor/fastapi.conf /etc/supervisor/conf.d/fastapi-mysql-api.conf
# Edit paths in the conf file if needed
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start fastapi-mysql-api
sudo supervisorctl status
```

---

## Deploying Laravel (PHP-FPM + Queue Worker)

```bash
cd day4/laravel-mysql-api

composer install --no-dev --optimize-autoloader
cp env.example.txt .env
php artisan key:generate
php artisan migrate --force
php artisan db:seed --class=TaskSeeder
php artisan config:cache
php artisan route:cache

# Queue worker via systemd
sudo cp ../process-management/systemd/laravel-worker.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable laravel-worker
sudo systemctl start laravel-worker
sudo systemctl status laravel-worker
```

**Web server:** Configure Nginx or Apache to serve Laravel via PHP-FPM pointing document root to `public/`.

---

## Deploying Next.js (PM2)

```bash
cd /var/www/day4/nextjs-fullstack-app

npm install
cp env.local.example.txt .env.local   # fill in values
npm run build

# Start with PM2 (from day4 root)
cd ..
pm2 start process-management/ecosystem.config.js --only nextjs-app --env production
pm2 save
```

---

## Running All Migrations at Once

```bash
cd day4

# Set common env vars
export DB_HOST=localhost
export DB_USER=apiuser
export DB_PASSWORD=your_pass
export DB_NAME=apidb

bash scripts/run_migrations.sh --target express

export DB_USER=fastapiuser
export DB_NAME=fastapidb
bash scripts/run_migrations.sh --target fastapi

bash scripts/run_migrations.sh --target laravel
```

---

## Monitoring

```bash
# Add to crontab
crontab -e
*/5 * * * * /var/www/day4/scripts/app_monitor.sh --email aakash@hestabit.in
0 7 * * * /path/to/day4/scripts/log_analyzer.sh
```