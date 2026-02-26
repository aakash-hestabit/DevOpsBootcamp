"""Product CRUD router."""
from fastapi import APIRouter, HTTPException, Query
import structlog
from database import get_connection
from models.product import Product, ProductCreate, ProductUpdate, ProductListResponse, ProductResponse

router = APIRouter(prefix="/api/v1/products", tags=["Products"])
logger = structlog.get_logger(__name__)


@router.get("/", response_model=ProductListResponse, summary="List all products")
async def list_products(
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    async with get_connection() as cur:
        await cur.execute("SELECT COUNT(*) AS total FROM products")
        total = (await cur.fetchone())["total"]

        await cur.execute(
            "SELECT * FROM products ORDER BY id ASC LIMIT %s OFFSET %s",
            (limit, offset),
        )
        rows = await cur.fetchall()

    return {"status": "success", "data": rows, "meta": {"total": total, "limit": limit, "offset": offset}}


@router.get("/{product_id}", response_model=ProductResponse, summary="Get product by ID")
async def get_product(product_id: int):
    async with get_connection() as cur:
        await cur.execute("SELECT * FROM products WHERE id = %s", (product_id,))
        row = await cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Product not found")
    return {"status": "success", "data": row}


@router.post("/", response_model=ProductResponse, status_code=201, summary="Create a product")
async def create_product(payload: ProductCreate):
    async with get_connection() as cur:
        await cur.execute(
            "INSERT INTO products (name, description, price, stock_quantity) VALUES (%s, %s, %s, %s)",
            (payload.name, payload.description, float(payload.price), payload.stock_quantity),
        )
        product_id = cur.lastrowid
        await cur.execute("SELECT * FROM products WHERE id = %s", (product_id,))
        row = await cur.fetchone()

    logger.info("product_created", product_id=product_id, name=payload.name)
    return {"status": "success", "data": row}


@router.put("/{product_id}", response_model=ProductResponse, summary="Update a product")
async def update_product(product_id: int, payload: ProductUpdate):
    fields, values = [], []
    if payload.name is not None:
        fields.append("name = %s"); values.append(payload.name)
    if payload.description is not None:
        fields.append("description = %s"); values.append(payload.description)
    if payload.price is not None:
        fields.append("price = %s"); values.append(float(payload.price))
    if payload.stock_quantity is not None:
        fields.append("stock_quantity = %s"); values.append(payload.stock_quantity)

    if not fields:
        raise HTTPException(status_code=400, detail="No fields provided for update")

    values.append(product_id)
    async with get_connection() as cur:
        await cur.execute(f"UPDATE products SET {', '.join(fields)} WHERE id = %s", values)
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="Product not found")
        await cur.execute("SELECT * FROM products WHERE id = %s", (product_id,))
        row = await cur.fetchone()

    logger.info("product_updated", product_id=product_id)
    return {"status": "success", "data": row}


@router.delete("/{product_id}", status_code=204, summary="Delete a product")
async def delete_product(product_id: int):
    async with get_connection() as cur:
        await cur.execute("DELETE FROM products WHERE id = %s", (product_id,))
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="Product not found")

    logger.info("product_deleted", product_id=product_id)