# Database Installation & Setup Guide

Documentation of **installation steps** of the automated setup scripts:

- `scripts/postgresql_setup.sh`
- `scripts/mysql_setup.sh`
- `scripts/mongodb_setup.sh`

---

## PostgreSQL 15

### 1. Install Dependencies
`sudo apt update`  
`sudo apt install -y curl ca-certificates`

### 2. Add Official PostgreSQL APT Repository
`sudo install -d /usr/share/postgresql-common/pgdg`  
`sudo curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc`  
`. /etc/os-release`  
`echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list`  
`sudo apt update`

### 3. Install PostgreSQL
`sudo apt install -y postgresql-15`

### 4. Apply Production Configuration
`sudo mkdir -p /etc/postgresql/15/main/conf.d`

Add include directive if not present:
`echo "include_dir = 'conf.d'" | sudo tee -a /etc/postgresql/15/main/postgresql.conf`

Create custom tuning file:
`sudo nano /etc/postgresql/15/main/conf.d/99-custom-production.conf`

Contents:
`shared_buffers = 256MB`  
`effective_cache_size = 1GB`  
`work_mem = 16MB`  
`maintenance_work_mem = 128MB`  
`max_connections = 100`

Append authentication rules:
`sudo nano /etc/postgresql/15/main/pg_hba.conf`

Add:
`host all all 127.0.0.1/32 scram-sha-256`  
`host all all ::1/128 scram-sha-256`

### 5. Create User and Database
`sudo -u postgres psql`

`CREATE ROLE dbadmin WITH LOGIN SUPERUSER PASSWORD 'password123';`  
`CREATE DATABASE testdb OWNER dbadmin;`

`\q`

### 6. Enable and Start Service
`sudo systemctl enable postgresql`  
`sudo systemctl restart postgresql`

### 7. Verify
`sudo -u postgres psql -c "\\conninfo"`

---

## MySQL 8.0

### 1. Install MySQL
`sudo apt update`  
`sudo apt install -y mysql-server mysql-client`

### 2. Secure Installation
If root has no password:

`sudo mysql`

`ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'RootPass@2026!';`  
`DELETE FROM mysql.user WHERE User='';`  
`DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');`  
`DROP DATABASE IF EXISTS test;`  
`DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';`  
`FLUSH PRIVILEGES;`

`\q`

### 3. Apply Production Configuration
Create config file:
`sudo nano /etc/mysql/conf.d/production.cnf`

Key settings:
`innodb_buffer_pool_size = 512M`  
`max_connections = 150`  
`slow_query_log = 1`  
`log_bin = /var/log/mysql/mysql-bin`  
`character_set_server = utf8mb4`

### 4. Restart MySQL
`sudo systemctl restart mysql`  
`sudo systemctl enable mysql`

### 5. Create Application User and Database
`mysql -u root -pRootPass@2026!`

`CREATE DATABASE appdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;`  
`CREATE USER 'appuser'@'localhost' IDENTIFIED BY 'AppPass@2026!';`  
`GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,DROP,INDEX,ALTER ON appdb.* TO 'appuser'@'localhost';`  
`FLUSH PRIVILEGES;`

### 6. Verify
`mysql -u appuser -pAppPass@2026! appdb -e "SELECT VERSION();"`

---

## MongoDB 7.0

### 1. Install Dependencies
`sudo apt install -y gnupg curl`

### 2. Add MongoDB Repository
`sudo rm -f /usr/share/keyrings/mongodb-server-7.0.gpg`  
`curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg`

`. /etc/os-release`

For Jammy or Noble:
`echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list`

`sudo apt update`

### 3. Install MongoDB
`sudo apt install -y mongodb-org`

### 4. Initial Configuration (No Auth)
`sudo nano /etc/mongod.conf`

Ensure:
`bindIp: 127.0.0.1`  
`authorization: disabled`

### 5. Create Admin User
`sudo systemctl start mongod`

`mongosh`

`use admin`  
`db.createUser({ user: 'mongoadmin', pwd: 'AdminPass@2026!', roles: [ { role: 'userAdminAnyDatabase', db: 'admin' }, { role: 'readWriteAnyDatabase', db: 'admin' } ] })`

### 6. Enable Authentication
Edit `/etc/mongod.conf`:
`security:`  
`  authorization: enabled`

Restart:
`sudo systemctl restart mongod`

### 7. Create Application User
`mongosh -u mongoadmin -p AdminPass@2026! --authenticationDatabase admin`

`use appdb`  
`db.createUser({ user: 'appuser', pwd: 'AppPass@2026!', roles: [ { role: 'readWrite', db: 'appdb' } ] })`

### 8. Verify
`mongosh -u appuser -p AppPass@2026! --authenticationDatabase appdb appdb --eval "db.runCommand({ ping: 1 })"`

---

## Backup Utilities

PostgreSQL: `pg_dump`, `pg_dumpall`, `pg_basebackup`  
MySQL: `mysqldump`, `mysqlpump`  
MongoDB: `mongodump`, `mongorestore`

---
