# Quick Start - MongoDB Replica Set

## Setup

### 1. Run Setup Script
```bash
cd mongodb-replicaset
./setup-replicaset.sh
```

Wait for completion (~2 minutes)

### 2. Update Backend Connection
```bash
cd ../backend
nano .env
```

Change the `MONGODB_URI` to:
```bash
MONGODB_URI=mongodb://devops:Devops%40123@localhost:27017,localhost:27018,localhost:27019/usersdb?replicaSet=rs0&authSource=admin
```

### 3. Restart Backend
```bash
cd ..
pm2 restart all
```

### 4. Verify
```bash
# Check replica set status
cd mongodb-replicaset
./manage-replicaset.sh status

# Test backend connection
curl http://localhost:3000/api/health | jq .
```

## Common Commands

```bash
# Check status
./manage-replicaset.sh status

# Show primary
./manage-replicaset.sh primary

# View logs
./manage-replicaset.sh logs

# Stop all nodes
./manage-replicaset.sh stop

# Start all nodes
./manage-replicaset.sh start

# Connect to primary
./manage-replicaset.sh connect
```

## Connection String

**For Backend:**
```
mongodb://devops:Devops%40123@localhost:27017,localhost:27018,localhost:27019/usersdb?replicaSet=rs0&authSource=admin
```

**For Admin:**
```
mongodb://admin:Admin%40123@localhost:27017,localhost:27018,localhost:27019/admin?replicaSet=rs0&authSource=admin
```

## Ports

- Node 1 (Primary): 27017
- Node 2 (Secondary): 27018
- Node 3 (Secondary): 27019

## Health Check

Expected output from `./manage-replicaset.sh status`:
```
localhost:27017 - PRIMARY (health: 1)
 localhost:27018 - SECONDARY (health: 1)
 localhost:27019 - SECONDARY (health: 1)
```

## Restart Everything

```bash
# Stop replica set
./manage-replicaset.sh stop

# Start replica set
./manage-replicaset.sh start

# Restart backend
cd ..
pm2 restart all
```