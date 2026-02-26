"""Pydantic models for products."""
from decimal import Decimal
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field, field_validator


class ProductBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=100, examples=["Widget Pro"])
    description: Optional[str] = Field(None, max_length=1000)
    price: Decimal = Field(..., gt=0, examples=[29.99])
    stock_quantity: int = Field(default=0, ge=0)

    @field_validator("name")
    @classmethod
    def name_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Product name cannot be blank")
        return v.strip()


class ProductCreate(ProductBase):
    pass


class ProductUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = Field(None, max_length=1000)
    price: Optional[Decimal] = Field(None, gt=0)
    stock_quantity: Optional[int] = Field(None, ge=0)


class Product(ProductBase):
    id: int
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class ProductListResponse(BaseModel):
    status: str = "success"
    data: list[Product]
    meta: dict


class ProductResponse(BaseModel):
    status: str = "success"
    data: Product