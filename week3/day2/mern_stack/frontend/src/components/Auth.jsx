import React, { useState } from 'react';

const API = import.meta.env.VITE_API_URL || '/api';

export default function Auth({ onLogin }) {
  const [mode, setMode]         = useState('login');   // 'login' | 'register'
  const [form, setForm]         = useState({ name: '', email: '', password: '' });
  const [loading, setLoading]   = useState(false);
  const [error, setError]       = useState(null);

  const handle = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const url  = mode === 'login' ? `${API}/auth/login` : `${API}/auth/register`;
      const body = mode === 'login'
        ? { email: form.email, password: form.password }
        : { name: form.name, email: form.email, password: form.password };

      const res  = await fetch(url, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify(body),
      });
      const data = await res.json();
      if (!data.success) throw new Error(data.error);
      onLogin(data.token);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="auth-wrap">
      <div className="auth-card">
        <div className="logo" style={{ marginBottom: 28, justifyContent: 'center' }}>
          <span className="logo-icon">⬡</span>
          <span className="logo-text">MERN Stack</span>
        </div>

        <div className="card-title" style={{ textAlign: 'center', marginBottom: 24 }}>
          {mode === 'login' ? 'Sign In' : 'Create Account'}
        </div>

        {error && <div className="error-box">⚠ {error}</div>}

        <form onSubmit={handle}>
          {mode === 'register' && (
            <div className="form-group" style={{ marginBottom: 14 }}>
              <label>Name</label>
              <input
                type="text"
                placeholder="Full name"
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
                required
              />
            </div>
          )}
          <div className="form-group" style={{ marginBottom: 14 }}>
            <label>Email</label>
            <input
              type="email"
              placeholder="email@example.com"
              value={form.email}
              onChange={(e) => setForm({ ...form, email: e.target.value })}
              required
            />
          </div>
          <div className="form-group" style={{ marginBottom: 24 }}>
            <label>Password</label>
            <input
              type="password"
              placeholder="••••••••"
              value={form.password}
              onChange={(e) => setForm({ ...form, password: e.target.value })}
              required
            />
          </div>
          <button className="btn btn-primary" type="submit" disabled={loading} style={{ width: '100%', justifyContent: 'center' }}>
            {loading ? 'Please wait…' : mode === 'login' ? 'Sign In' : 'Register'}
          </button>
        </form>

        <p style={{ textAlign: 'center', marginTop: 20, fontSize: '.88rem', color: 'var(--text-muted)' }}>
          {mode === 'login' ? "Don't have an account? " : 'Already have an account? '}
          <button className="auth-toggle" onClick={() => { setMode(mode === 'login' ? 'register' : 'login'); setError(null); }}>
            {mode === 'login' ? 'Register' : 'Sign In'}
          </button>
        </p>
      </div>
    </div>
  );
}
