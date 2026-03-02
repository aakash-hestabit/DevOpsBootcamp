# fastapi-mysql-api (Stack 3 Backend)

## Database Setup

```bash
mysql -u root -p
> CREATE DATABASE fastapidb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
> CREATE USER 'fastapiuser'@'127.0.0.1' IDENTIFIED BY 'FastApiPass123!';
> GRANT ALL PRIVILEGES ON fastapidb.* TO 'fastapiuser'@'127.0.0.1';
> FLUSH PRIVILEGES;
> EXIT;

mysql -h 127.0.0.1 -u fastapiuser -p fastapidb < migrations/001_create_products_table.sql
```

## API Endpoints

| Method | Endpoint                  | Description     |
|--------|---------------------------|-----------------|
| GET    | /health                   | Health check    |
| GET    | /api/v1/products          | List products   |
| GET    | /api/v1/products/{id}     | Get product     |
| POST   | /api/v1/products          | Create product  |
| PUT    | /api/v1/products/{id}     | Update product  |
| DELETE | /api/v1/products/{id}     | Delete product  |
| GET    | /docs                     | Swagger UI      |

## Swagger UI
```
http://localhost:8003/docs
```