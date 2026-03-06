import React, { useState, useEffect, useCallback } from 'react';

const API = process.env.REACT_APP_API_URL || '/api';

const ROLES = ['user', 'admin', 'moderator'];

function UserTag({ role }) {
  return <span className={`tag ${role}`}>{role}</span>;
}

export default function UserList() {
  const [users, setUsers]   = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError]   = useState(null);
  const [saving, setSaving] = useState(false);

  // Form state
  const [form, setForm] = useState({ name: '', email: '', role: 'user' });
  const [editId, setEditId] = useState(null);

  const fetchUsers = useCallback(async () => {
    try {
      setError(null);
      const res = await fetch(`${API}/users`);
      const data = await res.json();
      if (!data.success) throw new Error(data.error);
      setUsers(data.data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchUsers(); }, [fetchUsers]);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      const url    = editId ? `${API}/users/${editId}` : `${API}/users`;
      const method = editId ? 'PUT' : 'POST';
      const res    = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form),
      });
      const data = await res.json();
      if (!data.success) throw new Error(data.error);
      setForm({ name: '', email: '', role: 'user' });
      setEditId(null);
      fetchUsers();
    } catch (err) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  const handleEdit = (user) => {
    setEditId(user.id);
    setForm({ name: user.name, email: user.email, role: user.role });
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  const handleDelete = async (id) => {
    if (!window.confirm('Delete this user?')) return;
    try {
      const res  = await fetch(`${API}/users/${id}`, { method: 'DELETE' });
      const data = await res.json();
      if (!data.success) throw new Error(data.error);
      fetchUsers();
    } catch (err) {
      setError(err.message);
    }
  };

  const handleCancel = () => {
    setEditId(null);
    setForm({ name: '', email: '', role: 'user' });
    setError(null);
  };

  return (
    <div>
      {/* ── Add / Edit form ── */}
      <div className="card" style={{ marginBottom: 20 }}>
        <div className="card-title">{editId ? 'Edit User' : 'Add New User'}</div>
        {error && <div className="error-box">⚠ {error}</div>}
        <form onSubmit={handleSubmit}>
          <div className="form-row">
            <div className="form-group">
              <label>Name</label>
              <input
                type="text"
                placeholder="Full name"
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
                required
              />
            </div>
            <div className="form-group">
              <label>Email</label>
              <input
                type="email"
                placeholder="email@example.com"
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
                required
              />
            </div>
            <div className="form-group" style={{ maxWidth: 140 }}>
              <label>Role</label>
              <select value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value })}>
                {ROLES.map((r) => <option key={r} value={r}>{r}</option>)}
              </select>
            </div>
            <div style={{ display: 'flex', gap: 8, alignItems: 'flex-end' }}>
              <button className="btn btn-primary" type="submit" disabled={saving}>
                {saving ? 'Saving…' : editId ? '✓ Update' : '+ Add User'}
              </button>
              {editId && (
                <button className="btn btn-ghost" type="button" onClick={handleCancel}>
                  Cancel
                </button>
              )}
            </div>
          </div>
        </form>
      </div>

      {/* ── User table ── */}
      <div className="card">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
          <div className="card-title" style={{ margin: 0 }}>
            Users{!loading && ` (${users.length})`}
          </div>
          <button className="btn btn-ghost" onClick={fetchUsers} style={{ fontSize: '.8rem', padding: '6px 12px' }}>
            ⟳ Refresh
          </button>
        </div>

        {loading ? (
          <div className="loader">Loading users…</div>
        ) : users.length === 0 ? (
          <div className="empty">No users yet. Add one above.</div>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>ID</th>
                  <th>Name</th>
                  <th>Email</th>
                  <th>Role</th>
                  <th>Created</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {users.map((u) => (
                  <tr key={u.id}>
                    <td style={{ color: 'var(--text-muted)', fontFamily: 'monospace' }}>#{u.id}</td>
                    <td style={{ fontWeight: 600 }}>{u.name}</td>
                    <td style={{ color: 'var(--text-muted)' }}>{u.email}</td>
                    <td><UserTag role={u.role} /></td>
                    <td style={{ color: 'var(--text-muted)', fontSize: '.82rem' }}>
                      {new Date(u.created_at).toLocaleDateString()}
                    </td>
                    <td>
                      <div style={{ display: 'flex', gap: 8 }}>
                        <button className="btn btn-ghost" style={{ padding: '4px 10px', fontSize: '.8rem' }} onClick={() => handleEdit(u)}>
                          Edit
                        </button>
                        <button className="btn btn-danger" style={{ padding: '4px 10px', fontSize: '.8rem' }} onClick={() => handleDelete(u.id)}>
                          Delete
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
