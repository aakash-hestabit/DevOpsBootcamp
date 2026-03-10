import os
import time
import json
import psycopg2
import psycopg2.extras
import redis
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, EmailStr
from typing import Optional

app = FastAPI(title="User Service", version="1.0.0")

DB_HOST = os.getenv("DB_HOST", "user-db")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "userdb")
DB_USER = os.getenv("DB_USER", "userservice")
DB_PASS = os.getenv("DB_PASSWORD", "userpass")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))

START_TIME = time.time()

def get_db():
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
        user=DB_USER, password=DB_PASS
    )

def get_redis():
    try:
        return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
    except Exception:
        return None

class UserCreate(BaseModel):
    name: str
    email: str
    role: str = "user"

class UserUpdate(BaseModel):
    name: Optional[str] = None
    email: Optional[str] = None
    role: Optional[str] = None

@app.get("/health")
def health():
    db_status = "disconnected"
    redis_status = "disconnected"
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        db_status = "connected"
    except Exception:
        pass
    try:
        r = get_redis()
        if r and r.ping():
            redis_status = "connected"
    except Exception:
        pass
    status = "healthy" if db_status == "connected" else "degraded"
    return {
        "service": "user-service",
        "status": status,
        "uptime": f"{int(time.time() - START_TIME)}s",
        "dependencies": {
            "database": db_status,
            "redis": redis_status,
        }
    }

@app.get("/")
def root():
    return {"service": "user-service", "version": "1.0.0"}

@app.get("/api/users")
def list_users():
    r = get_redis()
    if r:
        cached = r.get("users:all")
        if cached:
            return {"success": True, "data": json.loads(cached), "source": "cache"}
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT id, name, email, role, created_at::text as created_at FROM users ORDER BY created_at DESC")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    if r:
        r.setex("users:all", 30, json.dumps(rows))
    return {"success": True, "data": rows, "count": len(rows)}

@app.get("/api/users/{user_id}")
def get_user(user_id: int):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT id, name, email, role, created_at::text as created_at FROM users WHERE id = %s", (user_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="User not found")
    return {"success": True, "data": row}

@app.post("/api/users", status_code=201)
def create_user(user: UserCreate):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    try:
        cur.execute(
            "INSERT INTO users (name, email, role) VALUES (%s, %s, %s) RETURNING id, name, email, role, created_at::text as created_at",
            (user.name, user.email, user.role)
        )
        row = cur.fetchone()
        conn.commit()
    except psycopg2.errors.UniqueViolation:
        conn.rollback()
        raise HTTPException(status_code=409, detail="Email already exists")
    except psycopg2.Error as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(e).split('\n')[0])
    finally:
        cur.close()
        conn.close()
    r = get_redis()
    if r:
        r.delete("users:all")
    return {"success": True, "data": row}

@app.put("/api/users/{user_id}")
def update_user(user_id: int, user: UserUpdate):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute(
        """UPDATE users SET
            name = COALESCE(%s, name),
            email = COALESCE(%s, email),
            role = COALESCE(%s, role)
        WHERE id = %s
        RETURNING id, name, email, role, created_at::text as created_at""",
        (user.name, user.email, user.role, user_id)
    )
    row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="User not found")
    r = get_redis()
    if r:
        r.delete("users:all")
    return {"success": True, "data": row}

@app.delete("/api/users/{user_id}")
def delete_user(user_id: int):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("DELETE FROM users WHERE id = %s RETURNING id", (user_id,))
    row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="User not found")
    r = get_redis()
    if r:
        r.delete("users:all")
    return {"success": True, "message": "User deleted"}
