# fastapi-mysql-api

async REST API for product management with FastAPI and MySQL, managed by Supervisor.

## Features
- Async MySQL via aiomysql connection pool
- Pydantic v2 validation
- Auto-generated Swagger UI at `/docs` and ReDoc at `/redoc`
- Structured logging with structlog
- Supervisor process management (4 workers)
- Health check endpoint

## Quick Start

```bash
# 1. Create and activate virtual environment
python3 -m venv venv
source venv/bin/activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Set up environment
cp env.example.txt .env
# Edit .env with your MySQL credentials

# 4. Run database migration
mysql -h localhost -u fastapiuser -p fastapidb < migrations/001_create_products_table.sql

# 5. Start development server
uvicorn main:app --reload --port 8000

# 6. Production (Supervisor)
# See supervisor/fastapi.conf
```

## API Endpoints

| Method | Endpoint                  | Description       |
|--------|---------------------------|-------------------|
| GET    | /health                   | Health check      |
| GET    | /api/v1/products          | List products     |
| GET    | /api/v1/products/{id}     | Get product       |
| POST   | /api/v1/products          | Create product    |
| PUT    | /api/v1/products/{id}     | Update product    |
| DELETE | /api/v1/products/{id}     | Delete product    |
| GET    | /docs                     | Swagger UI        |
| GET    | /redoc                    | ReDoc UI          |

## Supervisor Setup
```bash
sudo cp supervisor/fastapi.conf /etc/supervisor/conf.d/fastapi-mysql-api.conf
# Edit the paths in the conf file
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start fastapi-mysql-api
sudo supervisorctl status
```

## Logs
- `var/log/apps/fastapi-access.log`
- `var/log/apps/fastapi-supervisor-access.log`
- `var/log/apps/fastapi-supervisor-error.log`