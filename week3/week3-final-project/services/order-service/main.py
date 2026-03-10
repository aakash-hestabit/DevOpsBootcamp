import os
import time
import json
from decimal import Decimal
import psycopg2
import psycopg2.extras
import redis
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional

app = FastAPI(title="Order Service", version="1.0.0")

def decimal_default(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def fix_decimals(rows):
    """Convert Decimal values to float in query results."""
    if isinstance(rows, list):
        return [{k: float(v) if isinstance(v, Decimal) else v for k, v in row.items()} for row in rows]
    if isinstance(rows, dict):
        return {k: float(v) if isinstance(v, Decimal) else v for k, v in rows.items()}
    return rows

DB_HOST = os.getenv("DB_HOST", "order-db")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "orderdb")
DB_USER = os.getenv("DB_USER", "orderservice")
DB_PASS = os.getenv("DB_PASSWORD", "orderpass")
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

class OrderCreate(BaseModel):
    user_id: int
    product_id: str
    quantity: int = 1
    total_price: float

class OrderUpdate(BaseModel):
    status: Optional[str] = None
    quantity: Optional[int] = None
    total_price: Optional[float] = None

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
        "service": "order-service",
        "status": status,
        "uptime": f"{int(time.time() - START_TIME)}s",
        "dependencies": {
            "database": db_status,
            "redis": redis_status,
        }
    }

@app.get("/")
def root():
    return {"service": "order-service", "version": "1.0.0"}

@app.get("/api/orders")
def list_orders():
    r = get_redis()
    if r:
        cached = r.get("orders:all")
        if cached:
            return {"success": True, "data": json.loads(cached), "source": "cache"}
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT id, user_id, product_id, quantity, total_price, status, created_at::text as created_at FROM orders ORDER BY created_at DESC")
    rows = fix_decimals(cur.fetchall())
    cur.close()
    conn.close()
    if r:
        r.setex("orders:all", 30, json.dumps(rows))
    return {"success": True, "data": rows, "count": len(rows)}

@app.get("/api/orders/{order_id}")
def get_order(order_id: int):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT id, user_id, product_id, quantity, total_price, status, created_at::text as created_at FROM orders WHERE id = %s", (order_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="Order not found")
    return {"success": True, "data": fix_decimals(row)}

@app.post("/api/orders", status_code=201)
def create_order(order: OrderCreate):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute(
        "INSERT INTO orders (user_id, product_id, quantity, total_price) VALUES (%s, %s, %s, %s) RETURNING id, user_id, product_id, quantity, total_price, status, created_at::text as created_at",
        (order.user_id, order.product_id, order.quantity, order.total_price)
    )
    row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    r = get_redis()
    if r:
        r.delete("orders:all")
    return {"success": True, "data": fix_decimals(row)}

@app.put("/api/orders/{order_id}")
def update_order(order_id: int, order: OrderUpdate):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute(
        """UPDATE orders SET
            status = COALESCE(%s, status),
            quantity = COALESCE(%s, quantity),
            total_price = COALESCE(%s, total_price)
        WHERE id = %s
        RETURNING id, user_id, product_id, quantity, total_price, status, created_at::text as created_at""",
        (order.status, order.quantity, order.total_price, order_id)
    )
    row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="Order not found")
    r = get_redis()
    if r:
        r.delete("orders:all")
    return {"success": True, "data": fix_decimals(row)}

@app.delete("/api/orders/{order_id}")
def delete_order(order_id: int):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("DELETE FROM orders WHERE id = %s RETURNING id", (order_id,))
    row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="Order not found")
    r = get_redis()
    if r:
        r.delete("orders:all")
    return {"success": True, "message": "Order deleted"}
