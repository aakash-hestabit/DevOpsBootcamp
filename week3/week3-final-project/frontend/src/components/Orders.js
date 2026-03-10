import React, { useState, useEffect, useCallback } from 'react';

const API = '/api';

export default function Orders() {
  const [orders, setOrders]   = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError]     = useState(null);
  const [saving, setSaving]   = useState(false);
  const [form, setForm]       = useState({ user_id: '', product_id: '', quantity: '1', total_price: '' });

  const fetchOrders = useCallback(async () => {
    try {
      setError(null);
      const res = await fetch(`${API}/orders`);
      const data = await res.json();
      if (!data.success) throw new Error(data.error || data.detail);
      setOrders(data.data);
    } catch (err) { setError(err.message); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { fetchOrders(); }, [fetchOrders]);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setSaving(true); setError(null);
    try {
      const body = { user_id: parseInt(form.user_id, 10), product_id: form.product_id, quantity: parseInt(form.quantity, 10), total_price: parseFloat(form.total_price) };
      const res = await fetch(`${API}/orders`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      const data = await res.json();
      if (!data.success) throw new Error(data.error || data.detail);
      setForm({ user_id: '', product_id: '', quantity: '1', total_price: '' });
      fetchOrders();
    } catch (err) { setError(err.message); }
    finally { setSaving(false); }
  };

  const handleDelete = async (id) => {
    if (!window.confirm('Delete this order?')) return;
    try {
      const res = await fetch(`${API}/orders/${id}`, { method: 'DELETE' });
      const data = await res.json();
      if (!data.success) throw new Error(data.error || data.detail);
      fetchOrders();
    } catch (err) { setError(err.message); }
  };

  return (
    <div>
      <div className="card" style={{ marginBottom: 20 }}>
        <div className="card-title">Create Order</div>
        {error && <div className="error-box">{error}</div>}
        <form onSubmit={handleSubmit}>
          <div className="form-row">
            <div className="form-group" style={{ maxWidth: 120 }}>
              <label>User ID</label>
              <input type="number" placeholder="1" value={form.user_id} onChange={e => setForm({...form, user_id: e.target.value})} required />
            </div>
            <div className="form-group">
              <label>Product ID</label>
              <input type="text" placeholder="MongoDB ObjectId" value={form.product_id} onChange={e => setForm({...form, product_id: e.target.value})} required />
            </div>
            <div className="form-group" style={{ maxWidth: 100 }}>
              <label>Qty</label>
              <input type="number" min="1" value={form.quantity} onChange={e => setForm({...form, quantity: e.target.value})} required />
            </div>
            <div className="form-group" style={{ maxWidth: 120 }}>
              <label>Total</label>
              <input type="number" step="0.01" placeholder="0.00" value={form.total_price} onChange={e => setForm({...form, total_price: e.target.value})} required />
            </div>
            <div style={{ display: 'flex', gap: 8, alignItems: 'flex-end' }}>
              <button className="btn btn-primary" type="submit" disabled={saving}>{saving ? 'Saving...' : '+ Order'}</button>
            </div>
          </div>
        </form>
      </div>

      <div className="card">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
          <div className="card-title" style={{ margin: 0 }}>Orders{!loading && ` (${orders.length})`}</div>
          <button className="btn btn-ghost" onClick={fetchOrders} style={{ fontSize: '.8rem', padding: '6px 12px' }}>Refresh</button>
        </div>
        {loading ? <div className="loader">Loading orders...</div> : orders.length === 0 ? <div className="empty">No orders yet.</div> : (
          <div className="table-wrap">
            <table>
              <thead><tr><th>ID</th><th>User</th><th>Product</th><th>Qty</th><th>Total</th><th>Status</th><th>Created</th><th>Actions</th></tr></thead>
              <tbody>
                {orders.map(o => (
                  <tr key={o.id}>
                    <td style={{ color: 'var(--text-muted)', fontFamily: 'monospace' }}>#{o.id}</td>
                    <td>User #{o.user_id}</td>
                    <td style={{ color: 'var(--text-muted)', fontSize: '.8rem', fontFamily: 'monospace' }}>{String(o.product_id).slice(0, 8)}...</td>
                    <td>{o.quantity}</td>
                    <td style={{ fontFamily: 'monospace' }}>${parseFloat(o.total_price).toFixed(2)}</td>
                    <td><span className={`tag ${o.status}`}>{o.status}</span></td>
                    <td style={{ color: 'var(--text-muted)', fontSize: '.82rem' }}>{new Date(o.created_at).toLocaleDateString()}</td>
                    <td>
                      <button className="btn btn-danger" style={{ padding: '4px 10px', fontSize: '.8rem' }} onClick={() => handleDelete(o.id)}>Delete</button>
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
