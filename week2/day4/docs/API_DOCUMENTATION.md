# API Documentation

All APIs follow REST conventions. Request bodies use `application/json`. Responses
wrap data in `{ "status": "success", "data": ... }`.

---

## Interactive Docs (Swagger / OpenAPI)

| Application | URL |
|-------------|-----|
| Express API | http://localhost:3000/api-docs (Swagger UI) |
| Express OpenAPI JSON | http://localhost:3000/api-docs.json |
| FastAPI | http://localhost:8000/docs (Swagger UI) |
| FastAPI OpenAPI JSON | http://localhost:8000/openapi.json |

**Laravel and Next.js: import `docs/postman_collection.json` into Postman.**

---

## Express API — Users

**Base URL:** `http://localhost:3000`

| Method | Endpoint | Body | Response |
|--------|----------|------|----------|
| GET | `/api/health` | — | 200 HealthResponse |
| GET | `/api/users?limit=50&offset=0` | — | 200 UserList |
| GET | `/api/users/:id` | — | 200 User / 404 |
| POST | `/api/users` | `{username, email, full_name?}` | 201 User / 422 |
| PUT | `/api/users/:id` | `{username?, email?, full_name?}` | 200 User / 404 |
| DELETE | `/api/users/:id` | — | 204 / 404 |

---

## FastAPI — Products

**Base URL:** `http://localhost:8000`

| Method | Endpoint | Body | Response |
|--------|----------|------|----------|
| GET | `/health` | — | 200 HealthResponse |
| GET | `/api/v1/products?limit=50&offset=0` | — | 200 ProductList |
| GET | `/api/v1/products/{id}` | — | 200 Product / 404 |
| POST | `/api/v1/products` | `{name, price, description?, stock_quantity?}` | 201 Product / 422 |
| PUT | `/api/v1/products/{id}` | `{name?, price?, description?, stock_quantity?}` | 200 Product / 404 |
| DELETE | `/api/v1/products/{id}` | — | 204 / 404 |

---

## Laravel API — Tasks

**Base URL:** `http://localhost:8880`  
**Header required:** `Accept: application/json`

| Method | Endpoint | Body | Response |
|--------|----------|------|----------|
| GET | `/api/health` | — | 200 HealthResponse |
| GET | `/api/tasks?per_page=15&status=&priority=` | — | 200 TaskList (paginated) |
| GET | `/api/tasks/{id}` | — | 200 Task / 404 |
| POST | `/api/tasks` | `{title, description?, status?, priority?, due_date?}` | 201 Task / 422 |
| PUT | `/api/tasks/{id}` | `{title?, description?, status?, priority?, due_date?}` | 200 Task / 404 |
| DELETE | `/api/tasks/{id}` | — | 200 / 404 |
| POST | `/api/tasks/{id}/complete` | — | 200 Task / 409 already complete |

**Status values:** `pending` · `in_progress` · `completed`  
**Priority values:** `low` · `medium` · `high`

---

## Next.js API Routes

**Base URL:** `http://localhost:3001`

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Health check |
| GET | `/api/users` | List users |
| POST | `/api/users` | Create user |
| GET | `/api/users/:id` | Get user |
| PUT | `/api/users/:id` | Update user |
| DELETE | `/api/users/:id` | Delete user |

---

## Error Response Format

```json
{
  "status": "error",
  "message": "Descriptive error message",
  "errors": [
    { "field": "email", "message": "Valid email is required" }
  ]
}
```

HTTP status codes: 400 Bad Request · 404 Not Found · 409 Conflict · 422 Validation · 500 Internal Error