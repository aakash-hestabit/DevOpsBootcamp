import React, { useState, useEffect, useCallback } from 'react';

const API = process.env.REACT_APP_API_URL || '/api';
const HEALTH_URL = process.env.REACT_APP_HEALTH_URL || '/health';

function ServiceRow({ name, description, status, detail }) {
  const dotClass = status === 'up' || status === 'connected' ? 'green' : status === 'loading' ? 'yellow' : 'red';
  return (
    <div className="service-row">
      <div className="service-info">
        <span className={`dot ${dotClass}`} />
        <div>
          <div className="service-name">{name}</div>
          <div className="service-desc">{description}</div>
        </div>
      </div>
      {detail && <span style={{ fontSize: '.82rem', color: 'var(--text-muted)' }}>{detail}</span>}
    </div>
  );
}

export default function HealthStatus() {
  const [health, setHealth] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [lastChecked, setLastChecked] = useState(null);

  const fetchHealth = useCallback(async () => {
    try {
      setError(null);
      const res = await fetch(HEALTH_URL);
      const data = await res.json();
      setHealth(data);
      setLastChecked(new Date());
    } catch (err) {
      setError('Cannot reach backend. Is the API running?');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchHealth();
    const id = setInterval(fetchHealth, 15000);
    return () => clearInterval(id);
  }, [fetchHealth]);

  const overallChip =
    loading ? 'loading' : error ? 'degraded' : health?.status === 'healthy' ? 'healthy' : 'degraded';
  const overallLabel =
    loading ? 'Checking…' : error ? 'Unreachable' : health?.status ?? 'unknown';

  return (
    <div>
      {/* ── Overall banner ── */}
      <div className="card" style={{ marginBottom: 20, display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 12 }}>
        <div>
          <div style={{ fontSize: '.78rem', fontWeight: 600, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '.05em', marginBottom: 6 }}>
            Overall System Status
          </div>
          <span className={`chip ${overallChip}`}>
            <span className={`dot ${overallChip === 'healthy' ? 'green' : overallChip === 'loading' ? 'yellow' : 'red'}`} />
            {overallLabel.charAt(0).toUpperCase() + overallLabel.slice(1)}
          </span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          {lastChecked && (
            <span style={{ fontSize: '.8rem', color: 'var(--text-muted)' }}>
              Last checked: {lastChecked.toLocaleTimeString()}
            </span>
          )}
          <button className="btn btn-ghost" onClick={fetchHealth} disabled={loading}>
            {loading ? '⟳ Refreshing…' : '⟳ Refresh'}
          </button>
        </div>
      </div>

      {error && <div className="error-box">⚠ {error}</div>}

      {/* ── Service cards grid ── */}
      <div className="grid-2">
        {/* Services */}
        <div className="card">
          <div className="card-title">Services</div>
          {loading ? (
            <div className="loader">Fetching health data…</div>
          ) : (
            <>
              <ServiceRow
                name="Frontend (React)"
                description="Nginx · Port 80"
                status="up"
                detail="running"
              />
              <ServiceRow
                name="Backend API (Express)"
                description="Node.js · Port 3000"
                status={health?.services?.api ?? (error ? 'down' : 'unknown')}
                detail={health?.uptime ? `uptime ${health.uptime}` : undefined}
              />
              <ServiceRow
                name="Database (PostgreSQL)"
                description="Port 5432"
                status={health?.services?.database ?? (error ? 'down' : 'unknown')}
                detail={health?.services?.database}
              />
            </>
          )}
        </div>

        {/* API response detail */}
        <div className="card">
          <div className="card-title">API Health Response</div>
          {loading ? (
            <div className="loader">Loading…</div>
          ) : health ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              {[
                { label: 'Status',      value: health.status },
                { label: 'Environment', value: health.environment },
                { label: 'Uptime',      value: health.uptime },
                { label: 'Version',     value: health.version },
                { label: 'Timestamp',   value: new Date(health.timestamp).toLocaleString() },
              ].map(({ label, value }) => (
                <div key={label} style={{ display: 'flex', justifyContent: 'space-between', fontSize: '.88rem' }}>
                  <span style={{ color: 'var(--text-muted)' }}>{label}</span>
                  <span style={{ fontWeight: 600 }}>{value ?? '—'}</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty">No data available</div>
          )}
        </div>
      </div>

      {/* ── Architecture overview ── */}
      <div className="card" style={{ marginTop: 20 }}>
        <div className="card-title">Architecture Overview</div>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', flexWrap: 'wrap', gap: 0 }}>
          {[
            { icon: '🌐', label: 'Browser', sub: 'User' },
            { arrow: true },
            { icon: '⚛', label: 'React', sub: 'Nginx · :80' },
            { arrow: true },
            { icon: '⚙', label: 'Express', sub: 'Node · :3000' },
            { arrow: true },
            { icon: '🗄', label: 'PostgreSQL', sub: ':5432' },
          ].map((item, i) =>
            item.arrow ? (
              <div key={i} style={{ color: 'var(--text-muted)', fontSize: '1.4rem', padding: '0 8px' }}>→</div>
            ) : (
              <div key={i} style={{ textAlign: 'center', padding: '12px 20px', background: 'var(--bg-card)', borderRadius: 8, border: '1px solid var(--border)', minWidth: 100 }}>
                <div style={{ fontSize: '1.6rem' }}>{item.icon}</div>
                <div style={{ fontWeight: 700, marginTop: 4 }}>{item.label}</div>
                <div style={{ fontSize: '.75rem', color: 'var(--text-muted)' }}>{item.sub}</div>
              </div>
            )
          )}
        </div>
      </div>
    </div>
  );
}
