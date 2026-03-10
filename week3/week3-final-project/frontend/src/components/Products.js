import React, { useState, useEffect, useCallback } from 'react';

const API = '/api';

export default function Products() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading]   = useState(true);
  const [error, setError]       = useState(null);
  const [saving, setSaving]     = useState(false);
  const [form, setForm]         = useState({ name: '', description: '', price: '', category: 'general', stock: '' });
  const [editId, setEditId]     = useState(null);

  const fetchProducts = useCallback(async () => {
    try {
      setError(null);
      const res = await fetch(`${API}/products`);
      const data = await res.json();
      if (!data.success) throw new Error(data.error);
      setProducts(data.data);
    } catch (err) { setError(err.message); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { fetchProducts(); }, [fetchProducts]);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setSaving(true); setError(null);
    try {
      const body = { ...form, price: parseFloat(form.price), stock: parseInt(form.stock, 10) };
      const url = editId ? `${API}/products/${editId}` : `${API}/products`;
      const method = editId ? 'PUT' : 'POST';
      const res = await fetch(url, { method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      const data = await res.json();
      if (!data.success) throw new Error(data.error);
      setForm({ name: '', description: '', price: '', category: 'general', stock: '' }); setEditId(null);
      fetchProducts();
    } catch (err) { setError(err.message); }
    finally { setSaving(false); }
  };

  const handleEdit = (p) => {
    setEditId(p._id);
    setForm({ name: p.name, description: p.description, price: String(p.price), category: p.category, stock: String(p.stock) });
  };

  const handleDelete = async (id) => {
    if (!window.confirm('Delete this product?')) return;
    try {
      const res = await fetch(`${API}/products/${id}`, { method: 'DELETE' });
      const data = await res.json();
      if (!data.success) throw new Error(data.error);
      fetchProducts();
    } catch (err) { setError(err.message); }
  };

  return (
    <div>
      <div className="card" style={{ marginBottom: 20 }}>
        <div className="card-title">{editId ? 'Edit Product' : 'Add New Product'}</div>
        {error && <div className="error-box">{error}</div>}
        <form onSubmit={handleSubmit}>
          <div className="form-row">
            <div className="form-group">
              <label>Name</label>
              <input type="text" placeholder="Product name" value={form.name} onChange={e => setForm({...form, name: e.target.value})} required />
            </div>
            <div className="form-group">
              <label>Price</label>
              <input type="number" step="0.01" placeholder="0.00" value={form.price} onChange={e => setForm({...form, price: e.target.value})} required />
            </div>
            <div className="form-group" style={{ maxWidth: 100 }}>
              <label>Stock</label>
              <input type="number" placeholder="0" value={form.stock} onChange={e => setForm({...form, stock: e.target.value})} required />
            </div>
            <div style={{ display: 'flex', gap: 8, alignItems: 'flex-end' }}>
              <button className="btn btn-primary" type="submit" disabled={saving}>{saving ? 'Saving...' : editId ? 'Update' : '+ Add'}</button>
              {editId && <button className="btn btn-ghost" type="button" onClick={() => { setEditId(null); setForm({ name: '', description: '', price: '', category: 'general', stock: '' }); }}>Cancel</button>}
            </div>
          </div>
        </form>
      </div>

      <div className="card">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
          <div className="card-title" style={{ margin: 0 }}>Products{!loading && ` (${products.length})`}</div>
          <button className="btn btn-ghost" onClick={fetchProducts} style={{ fontSize: '.8rem', padding: '6px 12px' }}>Refresh</button>
        </div>
        {loading ? <div className="loader">Loading products...</div> : products.length === 0 ? <div className="empty">No products yet.</div> : (
          <div className="table-wrap">
            <table>
              <thead><tr><th>Name</th><th>Category</th><th>Price</th><th>Stock</th><th>Actions</th></tr></thead>
              <tbody>
                {products.map(p => (
                  <tr key={p._id}>
                    <td style={{ fontWeight: 600 }}>{p.name}</td>
                    <td><span className="tag user">{p.category}</span></td>
                    <td style={{ fontFamily: 'monospace' }}>${p.price?.toFixed(2)}</td>
                    <td>{p.stock}</td>
                    <td>
                      <div style={{ display: 'flex', gap: 8 }}>
                        <button className="btn btn-ghost" style={{ padding: '4px 10px', fontSize: '.8rem' }} onClick={() => handleEdit(p)}>Edit</button>
                        <button className="btn btn-danger" style={{ padding: '4px 10px', fontSize: '.8rem' }} onClick={() => handleDelete(p._id)}>Delete</button>
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
