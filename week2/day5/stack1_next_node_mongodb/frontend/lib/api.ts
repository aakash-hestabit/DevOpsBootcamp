const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3000';

export interface User {
  id: string;
  username: string;
  email: string;
  full_name: string | null;
  created_at: string;
  updated_at: string;
}

export interface UserListResponse {
  status: string;
  data: User[];
  meta: { total: number; limit: number; offset: number };
}

export interface ApiError {
  status: string;
  message: string;
}

async function handleResponse<T>(res: Response): Promise<T> {
  const json = await res.json();
  if (!res.ok) {
    throw new Error((json as ApiError).message || `HTTP ${res.status}`);
  }
  return json as T;
}

export const api = {
  async listUsers(limit = 50, offset = 0): Promise<UserListResponse> {
    const res = await fetch(`${API_BASE}/api/users?limit=${limit}&offset=${offset}`, {
      cache: 'no-store',
    });
    return handleResponse<UserListResponse>(res);
  },

  async getUser(id: string): Promise<{ status: string; data: User }> {
    const res = await fetch(`${API_BASE}/api/users/${id}`, { cache: 'no-store' });
    return handleResponse(res);
  },

  async createUser(data: { username: string; email: string; full_name?: string }): Promise<{ status: string; data: User }> {
    const res = await fetch(`${API_BASE}/api/users`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    return handleResponse(res);
  },

  async updateUser(id: string, data: Partial<{ username: string; email: string; full_name: string }>): Promise<{ status: string; data: User }> {
    const res = await fetch(`${API_BASE}/api/users/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    return handleResponse(res);
  },

  async deleteUser(id: string): Promise<void> {
    const res = await fetch(`${API_BASE}/api/users/${id}`, { method: 'DELETE' });
    if (!res.ok && res.status !== 204) {
      const json = await res.json();
      throw new Error((json as ApiError).message || `HTTP ${res.status}`);
    }
  },

  async health(): Promise<Record<string, unknown>> {
    const res = await fetch(`${API_BASE}/api/health`, { cache: 'no-store' });
    return handleResponse(res);
  },
};