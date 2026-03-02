# MongoDB Replica Set Setup Guide

Complete guide to setting up a 3-node MongoDB replica set for Stack 1.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MongoDB Replica Set (rs0)                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   Node 1     │  │   Node 2     │  │   Node 3     │       │
│  │  PRIMARY     │  │  SECONDARY   │  │  SECONDARY   │       │
│  │  Port: 27017 │  │  Port: 27018 │  │  Port: 27019 │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│         │                 │                 │               │
│         └─────────────────┴─────────────────┘               │
│                  Automatic Failover                         │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Option 1: Automated Setup
```bash
cd mongodb-replicaset

# Make scripts executable
chmod +x setup-replicaset.sh manage-replicaset.sh

# Run setup (this will configure everything)
./setup-replicaset.sh
```

The script will:
1.  Generate secure replica set keyfile
2.  Create 3 MongoDB instances (ports 27017, 27018, 27019)
3.  Initialize replica set named "rs0"
4.  Create admin user (admin/Admin@123)
5.  Create application user (devops/Devops@123)
6.  Enable authentication with keyfile

### Option 2: Manual Setup

If you prefer manual configuration, follow these steps:

#### Step 1: Generate Keyfile

```bash
cd mongodb-replicaset/config
openssl rand -base64 756 > replica-keyfile
chmod 400 replica-keyfile
```

#### Step 2: Start MongoDB Instances

```bash
# Node 1 (Primary)
mongod --config config/mongod-node1.conf --fork

# Node 2 (Secondary)
mongod --config config/mongod-node2.conf --fork

# Node 3 (Secondary)
mongod --config config/mongod-node3.conf --fork
```

#### Step 3: Initialize Replica Set

Connect to Node 1 and initialize:

```bash
mongosh --port 27017

# In mongosh:
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "localhost:27017", priority: 2 },
    { _id: 1, host: "localhost:27018", priority: 1 },
    { _id: 2, host: "localhost:27019", priority: 1 }
  ]
})
```

#### Step 4: Create Users

```javascript
// Create admin user
use admin
db.createUser({
  user: "admin",
  pwd: "Admin@123",
  roles: [ 
    { role: "root", db: "admin" },
    { role: "clusterAdmin", db: "admin" }
  ]
})

// Create application user
use usersdb
db.createUser({
  user: "devops",
  pwd: "Devops@123",
  roles: [ 
    { role: "readWrite", db: "usersdb" },
    { role: "dbAdmin", db: "usersdb" }
  ]
})
```

## Configuration Details

### Node Ports

| Node | Port  | Role       | Priority |
|------|-------|------------|----------|
| 1    | 27017 | Primary    | 2        |
| 2    | 27018 | Secondary  | 1        |
| 3    | 27019 | Secondary  | 1        |

### Data Directories

- Node 1: `data/node1/`
- Node 2: `data/node2/`
- Node 3: `data/node3/`

### Log Files

- Node 1: `logs/mongod-node1.log`
- Node 2: `logs/mongod-node2.log`
- Node 3: `logs/mongod-node3.log`


## Connection Strings

### For Backend Application

Update `backend/.env`:

```bash
# Single node (development)
MONGODB_URI=mongodb://devops:Devops%40123@localhost:27017/usersdb?authSource=admin

# Replica set (production) 
MONGODB_URI=mongodb://devops:Devops%40123@localhost:27017,localhost:27018,localhost:27019/usersdb?replicaSet=rs0&authSource=admin
```

### For Admin Access

```bash
mongodb://admin:Admin%40123@localhost:27017,localhost:27018,localhost:27019/admin?replicaSet=rs0&authSource=admin
```

## Management Commands

Use the management script for common operations:

```bash
# Check replica set status
./manage-replicaset.sh status

# Show which node is primary
./manage-replicaset.sh primary

# Check health of all nodes
./manage-replicaset.sh health

# Start all nodes
./manage-replicaset.sh start

# Stop all nodes
./manage-replicaset.sh stop

# Restart all nodes
./manage-replicaset.sh restart

# View recent logs
./manage-replicaset.sh logs

# Connect to primary with mongosh
./manage-replicaset.sh connect
```

##  Verification

### 1. Check Replica Set Status

```bash
./manage-replicaset.sh status
```

Expected output:
```
Replica Set: rs0

 localhost:27017 - PRIMARY (health: 1)
 localhost:27018 - SECONDARY (health: 1)
 localhost:27019 - SECONDARY (health: 1)
```

### 2. Test Connection

```bash
mongosh "mongodb://devops:Devops%40123@localhost:27017,localhost:27018,localhost:27019/usersdb?replicaSet=rs0&authSource=admin"
```

### 3. Test Backend Connection

```bash
# Update backend/.env with replica set connection string
cd ../backend
pm2 restart all

# Test health endpoint
curl http://localhost:3000/api/health | jq .
```

Expected output should show all 3 MongoDB nodes.

## Failover Testing

Test automatic failover:

```bash
# 1. Check current primary
./manage-replicaset.sh primary

# 2. Stop the primary node
# If node 1 is primary:
pkill -f "mongod.*27017"

# 3. Wait 10-15 seconds for election

# 4. Check new primary
./manage-replicaset.sh status

# 5. Restart the stopped node
mongod --config config/mongod-node1.conf --fork

# It will rejoin as secondary
```

## Integration with Backend

### Update Backend Environment

```bash
cd ../backend
nano .env

# Change from:
MONGODB_URI=mongodb://devops:Devops%40123@localhost:27017/usersdb?authSource=admin

# To:
MONGODB_URI=mongodb://devops:Devops%40123@localhost:27017,localhost:27018,localhost:27019/usersdb?replicaSet=rs0&authSource=admin
```

### Restart Backend Services

```bash
pm2 restart all
pm2 logs
```

### Verify Connection

```bash
curl http://localhost:3000/api/health
```

Should show:
```json
{
  "status": "healthy",
  "database": {
    "status": "connected",
    "replicaSet": "rs0",
    "members": 3
  }
}
```

## Troubleshooting

### Issue: Cannot connect to replica set

**Solution 1**: Check if all nodes are running
```bash
./manage-replicaset.sh health
```

**Solution 2**: Check logs for errors
```bash
./manage-replicaset.sh logs
```

**Solution 3**: Verify authentication
```bash
mongosh --port 27017 -u admin -p 'Admin@123' --authenticationDatabase admin
```

### Issue: No PRIMARY elected

**Solution**: Force reconfiguration
```bash
mongosh --port 27017 -u admin -p 'Admin@123' --authenticationDatabase admin

rs.conf()
rs.reconfig(rs.conf(), {force: true})
```

### Issue: Authentication failed

**Solution**: Verify keyfile permissions
```bash
ls -la config/replica-keyfile
# Should show: -r-------- (400)

chmod 400 config/replica-keyfile
```

### Issue: Node won't start

**Solution 1**: Check port availability
```bash
netstat -tuln | grep -E '2701[7-9]'
```

**Solution 2**: Check data directory permissions
```bash
ls -la data/
# Should be owned by your user
```

**Solution 3**: View startup logs
```bash
tail -f logs/mongod-node*.log
```
