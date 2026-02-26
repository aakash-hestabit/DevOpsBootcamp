# Next.js Fullstack Application 

##  Project Successfully Completed

This is a complete Next.js full-stack application with all required features implemented and tested.

###  Implemented Features

#### 1. **Server-Side Rendering (SSR)**
-  Home page with SSR and health status display
-  Users list page with SSR showing all users from database
-  User detail page with SSR showing individual user information

#### 2. **API Routes**
All API endpoints fully functional:

| Method | Endpoint | Status | Description |
|--------|----------|--------|-------------|
| GET | `/api/health` |  | Health check with database connection status |
| GET | `/api/users` |  | List all users with pagination |
| POST | `/api/users` |  | Create new user with validation |
| GET | `/api/users/[id]` |  | Get specific user details |
| PUT | `/api/users/[id]` |  | Update user information |
| DELETE | `/api/users/[id]` |  | Delete user |

#### 3. **Database Integration**

The application will automatically create the `users` table if it doesn't exist. Ensure PostgreSQL is running with the credentials specified in `.env`:

```sql
-- Optional: Manually create the table if needed
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(255) UNIQUE NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  full_name VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```
-  PostgreSQL connection using `pg` library
-  Connection pooling configured
-  Users table with proper schema:
  - `id` - Auto-incrementing primary key
  - `username` - Unique constraint
  - `email` - Unique constraint
  - `full_name` - Optional field
  - `created_at` - Timestamp
  - `updated_at` - Timestamp

#### 4. **Pages Implemented**
-  `/` - Home page with system status and feature overview
-  `/users` - User list page with search and create functionality
-  `/users/[id]` - User detail page with edit and delete options

#### 5. **Components Built**
-  **Layout.js** - Navigation layout with navbar and footer
-  **UserForm.js** - Reusable form for creating/updating users with validation
-  **UserCard.js** - User card component with delete functionality
-  **ErrorBoundary.js** - Error boundary for error handling

#### 6. **Form Handling & Validation**
-  Form validation for username (min 3 chars)
-  Email validation using regex
-  Form submission with loading states
-  Error message display
-  Success message feedback


#### 8. **Environment Variables**
-  Database configuration via `.env` file
  - DB_HOST
  - DB_PORT
  - DB_NAME
  - DB_USER
  - DB_PASSWORD
  - DB_POOL_MAX
-  Application port configuration
-  API base URL configuration


##  Project Structure

```
nextjs-fullstack-app/
├── pages/                    # Next.js pages and API routes
│   ├── api/
│   │   ├── health.js        # Health check endpoint
│   │   └── users/
│   │       ├── index.js     # User list and create
│   │       └── [id].js      # User detail, update, delete
│   ├── users/
│   │   ├── index.js         # Users list page
│   │   └── [id].js          # User detail page
│   ├── _app.js              # App wrapper
│   ├── _document.js         # Document template
│   └── index.js             # Home page
├── components/              # React components
│   ├── Layout.js            # Navigation layout
│   ├── UserForm.js          # User form with validation
│   ├── UserCard.js          # User card component
│   └── ErrorBoundary.js     # Error boundary
├── styles/                  # CSS modules
│   ├── globals.css          # Global styles
│   ├── Layout.module.css
│   ├── Home.module.css
│   ├── Users.module.css
│   ├── UserDetail.module.css
│   ├── UserCard.module.css
│   ├── UserForm.module.css
│   └── ErrorBoundary.module.css
├── lib/                     # Utility functions
│   ├── db.js               # Database connection
│   └── api.js              # API client
├── public/                  # Static files
├── .env                     # Environment variables
├── .gitignore              # Git ignore
├── next.config.mjs         # Next.js config
├── package.json            # Dependencies
└── README.md               # This file
```

###  Running the Application

1. **Development Server:**
   ```bash
   cd nextjs-fullstack-app
   npm install
   npm run dev
   ```
   Server runs on `http://localhost:3001`

2. **Production Build:**
   ```bash
   npm run build
   npm start
   ```

3. **Database Setup:**
   - PostgreSQL must be running on localhost:5432
   - Database `apidb` with user `apiuser` (password: your_password)
   - Table `users` is auto-created if it doesn't exist

### All Endpoints

All API endpoints have been tested and verified working:

**Health Check:**
```bash
curl http://localhost:3001/api/health
```
Response:
```json
{
  "status": "healthy",
  "database": "connected",
  "pool": {"total": 1, "idle": 1, "active": 0},
  "timestamp": "2026-02-25T15:14:06.139Z",
  "uptime": 47.03
}
```

**Create User:**
```bash
curl -X POST http://localhost:3001/api/users \
  -H "Content-Type: application/json" \
  -d '{"username":"john_doe","email":"john@example.com","full_name":"John Doe"}'
```

**List Users:**
```bash
curl http://localhost:3001/api/users
```

**Get User:**
```bash
curl http://localhost:3001/api/users/1
```

**Update User:**
```bash
curl -X PUT http://localhost:3001/api/users/1 \
  -H "Content-Type: application/json" \
  -d '{"email":"newemail@example.com"}'
```

**Delete User:**
```bash
curl -X DELETE http://localhost:3001/api/users/1
```

---