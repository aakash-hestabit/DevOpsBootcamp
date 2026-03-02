# nextjs-products-frontend

Next.js 15 frontend for the FastAPI MySQL Products API (Stack 3).

## Features
- Server Components + Client Components (Next.js 15 App Router)
- Products CRUD (list, create, edit, delete) with pagination
- Live backend health indicator on home page
- TypeScript throughout
- Tailwind CSS v4 styling
- Runs on ports 3005 and 3006 (two instances for load balancing)

## Quick Start

```bash
# 1. Install dependencies
npm install

# 2. Set up environment
cp .env.example .env.local
# Edit .env.local — set NEXT_PUBLIC_API_URL to your FastAPI backend

# 3. Start development server
npm run dev          # starts on port 3005

# Second instance (separate terminal)
npm run dev:3006     # starts on port 3006

# Production build
npm run build
npm run start        # starts on port 3005
npm run start:3006   # starts on port 3006
```

## Environment Variables

| Variable              | Default                | Description                    |
|-----------------------|------------------------|--------------------------------|
| NEXT_PUBLIC_API_URL   | http://localhost:8003  | FastAPI backend base URL       |

> In production with Nginx, set `NEXT_PUBLIC_API_URL=http://localhost:80`

## Backend (FastAPI)

> **Copy the existing `fastapi-mysql-api` folder into `stack3_next_fastapi_mysql/backend/` as-is.**

```bash
cp -r path/to/fastapi-mysql-api/ stack3_next_fastapi_mysql/backend/
```

Then start it on the required ports:
```bash
cd backend
cp env.example.txt .env
# edit .env

python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
mysql -u fastapiuser -p fastapidb < migrations/001_create_products_table.sql

# Instance 1
uvicorn main:app --port 8003 &
# Instance 2
uvicorn main:app --port 8004 &
# Instance 3
uvicorn main:app --port 8005 &
```

## Pages

| Route     | Description                    |
|-----------|--------------------------------|
| /         | Dashboard with health status   |
| /products | Full products CRUD interface   |

## Architecture

```
Browser → Nginx (port 80) → Next.js 3005 or 3006
                          ↓
                    FastAPI (8003 / 8004 / 8005) → MySQL
```