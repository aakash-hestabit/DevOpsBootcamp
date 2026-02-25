# nextjs-fullstack-app

Full-stack Next.js application with Server-Side Rendering (SSR), API routes, and PostgreSQL.

## Features
- SSR with `getServerSideProps` for all user-facing pages
- API routes that connect directly to PostgreSQL
- PostgreSQL connection pool via `lib/db.js`
- Health check API route
- Security headers via `next.config.js`

## Quick Start

```bash
# 1. Install dependencies
npm install

# 2. Set up environment
cp env.local.example.txt .env.local
# Edit .env.local with your PostgreSQL credentials

# 3. Start development server (port 3001)
npm run dev

# 4. Build and start production
npm run build
npm start
```

## Pages

| Route           | Type | Description              |
|-----------------|------|--------------------------|
| /               | SSR  | Home with health status  |
| /users          | SSR  | User list from DB        |
| /users/[id]     | SSR  | User detail page         |

## API Routes

| Method | Route            | Description      |
|--------|------------------|------------------|
| GET    | /api/health      | Health check     |
| GET    | /api/users       | List users       |
| POST   | /api/users       | Create user      |
| GET    | /api/users/[id]  | Get user         |
| PUT    | /api/users/[id]  | Update user      |
| DELETE | /api/users/[id]  | Delete user      |

## PM2 (from project root)
```bash
pm2 start ecosystem.config.js --only nextjs-app
```