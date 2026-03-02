# nextjs-users-frontend

Next.js 15 frontend for the Express MongoDB Users API (Stack 1).

## Features
- Server Components + Client Components (Next.js 15 App Router)
- Users CRUD (list, create, edit, delete) with pagination
- Live backend health indicator on home page
- TypeScript throughout
- Tailwind CSS v4 styling
- Runs on ports 3001 and 3002 (two instances for load balancing)

## Quick Start

```bash
# 1. Install dependencies
npm install

# 2. Set up environment
cp .env.example .env.local
# Edit .env.local — set NEXT_PUBLIC_API_URL to your backend

# 3. Start development server
npm run dev          # starts on port 3001

# Second instance (separate terminal)
npm run dev:3002     # starts on port 3002

# Production build
npm run build
npm run start        # starts on port 3001
npm run start:3002   # starts on port 3002
```

## Environment Variables

| Variable              | Default               | Description                        |
|-----------------------|-----------------------|------------------------------------|
| NEXT_PUBLIC_API_URL   | http://localhost:3000 | Express MongoDB API base URL       |

> In production with Nginx load balancer, set `NEXT_PUBLIC_API_URL=http://localhost:80`

## Pages

| Route   | Description                   |
|---------|-------------------------------|
| /       | Dashboard with health status  |
| /users  | Full users CRUD interface     |

## Architecture

```
Browser → Nginx (port 80) → Next.js instance 1 (3001) or instance 2 (3002)
                          ↓
                     Express API (3000 / 3003 / 3004) → MongoDB replica set
```

## Notes
- User IDs are MongoDB ObjectIds (24-char hex strings), not integers
- The API URL is embedded in the browser bundle via `NEXT_PUBLIC_API_URL`
- For local dev, the browser calls the Express API directly (no proxy needed)