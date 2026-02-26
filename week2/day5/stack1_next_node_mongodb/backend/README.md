# express-mongodb-api

Production-ready REST API for user management built with Express.js and MongoDB (Mongoose ODM).

## Features
- Full User CRUD with pagination
- MongoDB via Mongoose ODM with connection pooling
- Input validation (express-validator)
- Structured logging (winston + daily rotation)
- Swagger/OpenAPI docs at `/api-docs`
- Rate limiting, CORS, Helmet security headers
- Health check endpoint
- Graceful shutdown
- MongoDB replica set support (3-node)

## Quick Start

```bash
# 1. Install dependencies
npm install

# 2. Set up environment
cp env.example.txt .env
# Edit .env with your MongoDB credentials

# 3. Start MongoDB (single node dev)
mongod --dbpath /data/db

# 4. Start server
npm run dev        # development (port 3000)
npm start          # production

# Multi-instance (ports 3000, 3003, 3004)
PORT=3000 npm start &
PORT=3003 npm start &
PORT=3004 npm start &
```

## MongoDB Setup

```bash
# Install MongoDB Community Edition, then:
# Single node (development)
MONGODB_URI=mongodb://localhost:27017/usersdb

# Replica set (production - 3 nodes)
# Initialize replica set:
mongosh
> rs.initiate({
    _id: "rs0",
    members: [
      { _id: 0, host: "mongo1:27017" },
      { _id: 1, host: "mongo2:27017" },
      { _id: 2, host: "mongo3:27017" }
    ]
  })

# Connection string for replica set:
MONGODB_URI=mongodb://mongo1:27017,mongo2:27017,mongo3:27017/usersdb?replicaSet=rs0
```

## API Endpoints

| Method | Endpoint       | Description        |
|--------|----------------|--------------------|
| GET    | /api/health    | Health check       |
| GET    | /api/users     | List users (paged) |
| GET    | /api/users/:id | Get user (ObjectId)|
| POST   | /api/users     | Create user        |
| PUT    | /api/users/:id | Update user        |
| DELETE | /api/users/:id | Delete user        |
| GET    | /api-docs      | Swagger UI         |

> **Note:** IDs are MongoDB ObjectId strings (e.g., `65c1234abcd5678ef90abcde`), not integers.

## Environment Variables

| Variable            | Default                               | Description              |
|---------------------|---------------------------------------|--------------------------|
| PORT                | 3000                                  | Server port              |
| MONGODB_URI         | mongodb://localhost:27017/usersdb     | MongoDB connection string|
| CORS_ORIGIN         | *                                     | Allowed CORS origin      |
| LOG_LEVEL           | info                                  | Logging level            |
| RATE_LIMIT_MAX_REQUESTS | 100                               | Requests per window      |

## Logs
- `var/log/apps/express-mongo-combined-YYYY-MM-DD.log`
- `var/log/apps/express-mongo-error-YYYY-MM-DD.log`