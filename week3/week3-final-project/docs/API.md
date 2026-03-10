# API Reference

Base URLs:
- HTTP: `http://localhost:8081`
- HTTPS: `https://localhost:8443` (self-signed certificate)

```bash
curl -sk https://localhost:8443/health
```

## Health

### GET /health

Returns aggregate health status of all services.

Response:
```json
{
  "service": "api-gateway",
  "status": "healthy",
  "uptime": "123s",
  "services": {
    "user-service": {
      "status": "healthy",
      "details": {
        "service": "user-service",
        "status": "healthy",
        "uptime": "120s",
        "dependencies": { "database": "connected", "redis": "connected" }
      }
    },
    "product-service": {
      "status": "healthy",
      "details": {
        "service": "product-service",
        "status": "healthy",
        "uptime": "120s",
        "dependencies": { "database": "connected", "redis": "connected" }
      }
    },
    "order-service": {
      "status": "healthy",
      "details": {
        "service": "order-service",
        "status": "healthy",
        "uptime": "120s",
        "dependencies": { "database": "connected", "redis": "connected" }
      }
    }
  }
}
```

Status values: healthy, degraded, unhealthy

## Users

### GET /api/users
List all users.

### POST /api/users
Create a user.
```json
{ "name": "John", "email": "john@example.com", "role": "admin" }
```
Valid roles: `admin`, `user`, `moderator`

### PUT /api/users/:id
Update a user.
```json
{ "name": "John Updated", "role": "moderator" }
```

### DELETE /api/users/:id
Delete a user.

## Products

### GET /api/products
List all products.

### POST /api/products
Create a product.
```json
{ "name": "Widget", "price": 29.99, "category": "electronics", "stock": 100 }
```

### PUT /api/products/:id
Update a product.
```json
{ "name": "Widget Pro", "price": 39.99 }
```

### DELETE /api/products/:id
Delete a product.

## Orders

### GET /api/orders
List all orders.

### POST /api/orders
Create an order.
```json
{ "user_id": 1, "product_id": "abc123", "quantity": 2, "total_price": 59.98 }
```

### PUT /api/orders/:id
Update order status.
```json
{ "status": "completed" }
```
Valid statuses: `pending`, `completed`, `cancelled`

### DELETE /api/orders/:id
Delete an order.
