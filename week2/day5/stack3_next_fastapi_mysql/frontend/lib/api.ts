const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8003';

export interface Product {
  id: number;
  name: string;
  description: string | null;
  price: string; // decimal returned as string from FastAPI
  stock_quantity: number;
  created_at: string;
  updated_at: string;
}

export interface ProductListResponse {
  status: string;
  data: Product[];
  meta: { total: number; limit: number; offset: number };
}

async function handleResponse<T>(res: Response): Promise<T> {
  const json = await res.json();
  if (!res.ok) {
    const msg = json?.detail || json?.message || `HTTP ${res.status}`;
    throw new Error(typeof msg === 'string' ? msg : JSON.stringify(msg));
  }
  return json as T;
}

export const api = {
  async listProducts(limit = 50, offset = 0): Promise<ProductListResponse> {
    const res = await fetch(`${API_BASE}/api/v1/products?limit=${limit}&offset=${offset}`, {
      cache: 'no-store',
    });
    return handleResponse<ProductListResponse>(res);
  },

  async getProduct(id: number): Promise<{ status: string; data: Product }> {
    const res = await fetch(`${API_BASE}/api/v1/products/${id}`, { cache: 'no-store' });
    return handleResponse(res);
  },

  async createProduct(data: {
    name: string;
    description?: string;
    price: number;
    stock_quantity?: number;
  }): Promise<{ status: string; data: Product }> {
    const res = await fetch(`${API_BASE}/api/v1/products`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    return handleResponse(res);
  },

  async updateProduct(
    id: number,
    data: Partial<{ name: string; description: string; price: number; stock_quantity: number }>
  ): Promise<{ status: string; data: Product }> {
    const res = await fetch(`${API_BASE}/api/v1/products/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    return handleResponse(res);
  },

  async deleteProduct(id: number): Promise<void> {
    const res = await fetch(`${API_BASE}/api/v1/products/${id}`, { method: 'DELETE' });
    if (!res.ok && res.status !== 204) {
      const json = await res.json();
      throw new Error(json?.detail || `HTTP ${res.status}`);
    }
  },

  async health(): Promise<Record<string, unknown>> {
    const res = await fetch(`${API_BASE}/health`, { cache: 'no-store' });
    return handleResponse(res);
  },
};