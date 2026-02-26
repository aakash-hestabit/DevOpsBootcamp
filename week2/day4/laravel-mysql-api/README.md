# laravel-mysql-api

Laravel REST API for task management with MySQL, queue workers, and Eloquent ORM.

## Features
- Task CRUD with filtering, pagination, and status transitions
- Eloquent ORM with scopes
- Form Request validation
- MySQL with PDO persistent connections
- Queue workers via systemd
- Daily log rotation via Monolog
- Health check endpoint
- **Swagger UI Documentation** for interactive API testing

## Quick Start

```bash
# 1. Install dependencies
composer install 

# 2. Set up environment
cp env.example.txt .env
# Edit .env with your database credentials

# 3. Generate app key
php artisan key:generate

# 4. Run migrations and seed
php artisan migrate
php artisan db:seed --class=TaskSeeder

# 5. Generate Swagger documentation
php artisan l5-swagger:generate

# 6. Start development server
php artisan serve --port=8880
```

## Database Setup (First Time)

```bash
# Create database and user in MySQL
mysql -u root -p
> CREATE DATABASE laraveldb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
> CREATE USER 'laraveluser'@'127.0.0.1' IDENTIFIED BY 'LaravelPass123!';
> GRANT ALL PRIVILEGES ON laraveldb.* TO 'laraveluser'@'127.0.0.1';
> FLUSH PRIVILEGES;
> EXIT;
```

## API Endpoints

| Method | Endpoint                    | Description          |
|--------|-----------------------------|----------------------|
| GET    | /api/health                 | Health check         |
| GET    | /api/tasks                  | List tasks (paged)   |
| GET    | /api/tasks/{id}             | Get task             |
| POST   | /api/tasks                  | Create task          |
| PUT    | /api/tasks/{id}             | Update task          |
| DELETE | /api/tasks/{id}             | Delete task          |
| POST   | /api/tasks/{id}/complete    | Mark as complete     |

## Swagger UI Documentation

**Access interactive API documentation at:**
```
http://localhost:8880/api/documentation
```

Features:
- View all API endpoints with complete request/response schemas
- Test any endpoint directly from the browser using "Try it out" button
- See parameter descriptions and validation rules
- Examples of all status codes and responses

## Queue Worker
```bash
# Development
php artisan queue:work

# Production (systemd)
sudo cp ../process-management/systemd/laravel-worker.service /etc/systemd/system/
sudo systemctl enable laravel-worker
sudo systemctl start laravel-worker
```

## Logs
- `storage/logs/laravel-YYYY-MM-DD.log`