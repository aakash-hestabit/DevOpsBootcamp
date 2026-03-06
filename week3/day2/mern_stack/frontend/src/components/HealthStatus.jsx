import React, { useState, useEffect, useCallback } from 'react';

const HEALTH_URL = import.meta.env.VITE_HEALTH_URL || '/health';

function ServiceRow({ name, description, status, detail }) {
  const dotClass =
    status === 'up' || status === 'connected' ? 'green' : status === 'loading' ? 'yellow' : 'red';
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
  const [health, setHealth]       = useState(null);
  const [loading, setLoading]     = useState(true);
  const [error, setError]         = useState(null);
  const [lastChecked, setLastChecked] = useState(null);

  const fetchHealth = useCallback(async () => {
    try {
      setError(null);
      const res  = await fetch(HEALTH_URL);
      const data = await res.json();
      setHealth(data);
      setLastChecked(new Date());
    } catch {
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

      {/* ── Service cards ── */}
      {health && (
        <div className="grid-2">
          <div className="card">
            <div className="card-title">Services</div>
            <ServiceRow name="API Server"  description="Express.js REST API"   status={health.services?.api}      detail={health.uptime} />
            <ServiceRow name="MongoDB"     description="Primary replica node"  status={health.services?.database} />
          </div>
          <div className="card">
            <div className="card-title">Runtime</div>
            <ServiceRow name="Environment" description="Node environment"     status="up" detail={health.environment} />
            <ServiceRow name="Version"     description="App version"          status="up" detail={health.version} />
          </div>
        </div>
      )}
    </div>
  );
}
