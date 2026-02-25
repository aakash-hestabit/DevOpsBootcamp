const BASE = process.env.NEXT_PUBLIC_API_BASE_URL || '';

async function apiFetch(path, options = {}) {
  const res = await fetch(`${BASE}${path}`, {
    headers: { 'Content-Type': 'application/json', ...options.headers },
    ...options,
  });
  const json = await res.json();
  if (!res.ok) throw new Error(json.message || 'API request failed');
  return json;
}

export const api = {
  getUsers:   ()       => apiFetch('/api/users'),
  getUser:    (id)     => apiFetch(`/api/users/${id}`),
  createUser: (body)   => apiFetch('/api/users', { method: 'POST', body: JSON.stringify(body) }),
  updateUser: (id, b)  => apiFetch(`/api/users/${id}`, { method: 'PUT', body: JSON.stringify(b) }),
  deleteUser: (id)     => apiFetch(`/api/users/${id}`, { method: 'DELETE' }),
};