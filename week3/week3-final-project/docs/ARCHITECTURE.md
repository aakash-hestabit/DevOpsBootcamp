# Architecture

## Overview

The platform follows a microservices architecture with an API gateway pattern. All services are containerized and communicate over Docker networks. The frontend terminates SSL/TLS and serves both HTTP and HTTPS.

```
Client Browser
      |
  [Frontend - Nginx]
   HTTP :80  |  HTTPS :443 (TLS 1.2/1.3)
      |
  [API Gateway - Express:3000]
      |
  +---+---+---+
  |       |       |
[User]  [Product] [Order]
:8000   :3000     :8001
  |       |         |
[PG]  [Mongo]     [PG]
  \     |         /
   [  Redis  ]
```

External ports: HTTP 8081, HTTPS 8443, Prometheus 9090, Grafana 3001, cAdvisor 9091

## Services

### Frontend
- React 18 single-page application
- Nginx reverse proxy routes /api/* and /health to API Gateway
- **HTTP on port 80** (mapped to host 8081)
- **HTTPS on port 443** (mapped to host 8443) with TLS 1.2/1.3
- Security headers: HSTS, X-Content-Type-Options, X-Frame-Options, X-XSS-Protection
- Self-signed SSL certificate in `ssl/` directory
- Tabs: Dashboard (health), Users, Products, Orders
- Dark theme matching Week 3 Day 2 reference

### API Gateway
- Express.js on port 3000
- Rate limiting: 100 requests per minute per IP
- Proxies requests to backend services
- Aggregates health status from all services
- Routes: /api/users, /api/products, /api/orders, /health

### User Service
- Python FastAPI on port 8000
- PostgreSQL for persistence (user-db)
- Redis caching on list endpoint (30s TTL)
- CRUD: create, read, update, delete users

### Product Service
- Node.js Express on port 3000
- MongoDB for persistence (product-db)
- Redis caching on list endpoint (30s TTL)
- Auto-seeds 5 sample products on first start

### Order Service
- Python FastAPI on port 8001
- PostgreSQL for persistence (order-db)
- Redis caching on list endpoint (30s TTL)
- Order statuses: pending, completed, cancelled

## Networks

| Network            | Services                                   | External |
|--------------------|--------------------------------------------|----------|
| frontend-network   | frontend, api-gateway                      | yes      |
| backend-network    | api-gateway, user/product/order-service, redis | yes  |
| db-network         | user/product/order-service, user-db, order-db, product-db, redis | no (internal) |
| monitoring-network | cadvisor, prometheus, grafana              | yes      |

## Data Flow

1. Browser loads React app from Nginx (frontend)
2. React makes API calls to /api/* which Nginx proxies to API Gateway
3. API Gateway applies rate limiting, then proxies to the target service
4. Each service checks Redis cache first (30s TTL), falls back to database
5. Responses flow back through the same chain

## Monitoring

- **cAdvisor** collects container metrics from Docker
- **Prometheus** scrapes cAdvisor every 10 seconds
  - `metric_relabel_configs` filters metrics to only keep containers matching `name=~"microservices-.+"` — this ensures the dashboard shows only project containers, not all containers on the Docker host
- **Grafana** displays a simplified, dashboard with 9 panels:
  - Running Containers (stat)
  - Total CPU Usage % (stat)
  - Total Memory Usage (stat)
  - Prometheus Uptime (stat)
  - CPU Usage per Container (timeseries)
  - Memory Usage per Container (timeseries)
  - Network Received bytes/sec (timeseries)
  - Network Sent bytes/sec (timeseries)
  - Memory Usage by Service 
