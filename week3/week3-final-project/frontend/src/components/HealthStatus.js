import React, { useState, useEffect, useCallback } from 'react';

const HEALTH_URL = '/health';

function ServiceRow({ name, description, status, detail }) {
  const dotClass = status === 'healthy' || status === 'connected' || status === 'up' ? 'green'
    : status === 'loading' ? 'yellow' : 'red';
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
      setError('Cannot reach API Gateway. Is the system running?');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchHealth();
    const id = setInterval(fetchHealth, 15000);
    return () => clearInterval(id);
  }, [fetchHealth]);

  const overallChip = loading ? 'loading' : error ? 'unhealthy'
    : health?.status === 'healthy' ? 'healthy'
    : health?.status === 'degraded' ? 'degraded' : 'unhealthy';
  const overallLabel = loading ? 'Checking...' : error ? 'Unreachable' : health?.status ?? 'unknown';

  const svc = health?.services || {};

  return (
    <div>
      {/* Overall banner */}
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
            {loading ? 'Refreshing...' : 'Refresh'}
          </button>
        </div>
      </div>

      {error && <div className="error-box">{error}</div>}

      {/* Service grid */}
      <div className="grid-2">
        <div className="card">
          <div className="card-title">Microservices</div>
          {loading ? (
            <div className="loader">Fetching health data...</div>
          ) : (
            <>
              <ServiceRow
                name="API Gateway"
                description="Express.js / Port 3000"
                status={health ? 'healthy' : 'down'}
                detail={health?.uptime ?? ''}
              />
              <ServiceRow
                name="User Service"
                description="FastAPI + PostgreSQL / Port 8000"
                status={svc['user-service']?.status ?? (error ? 'down' : 'loading')}
                detail={svc['user-service']?.details?.uptime ?? ''}
              />
              <ServiceRow
                name="Product Service"
                description="Express + MongoDB / Port 3000"
                status={svc['product-service']?.status ?? (error ? 'down' : 'loading')}
                detail={svc['product-service']?.details?.uptime ?? ''}
              />
              <ServiceRow
                name="Order Service"
                description="FastAPI + PostgreSQL / Port 8001"
                status={svc['order-service']?.status ?? (error ? 'down' : 'loading')}
                detail={svc['order-service']?.details?.uptime ?? ''}
              />
            </>
          )}
        </div>

        <div className="card">
          <div className="card-title">Dependencies</div>
          {loading ? (
            <div className="loader">Loading...</div>
          ) : (
            <>
              <ServiceRow
                name="PostgreSQL (User DB)"
                description="Port 5432"
                status={svc['user-service']?.details?.dependencies?.database ?? 'unknown'}
                detail={svc['user-service']?.details?.dependencies?.database ?? ''}
              />
              <ServiceRow
                name="PostgreSQL (Order DB)"
                description="Port 5432"
                status={svc['order-service']?.details?.dependencies?.database ?? 'unknown'}
                detail={svc['order-service']?.details?.dependencies?.database ?? ''}
              />
              <ServiceRow
                name="MongoDB (Product DB)"
                description="Port 27017"
                status={svc['product-service']?.details?.dependencies?.database ?? 'unknown'}
                detail={svc['product-service']?.details?.dependencies?.database ?? ''}
              />
              <ServiceRow
                name="Redis (Cache)"
                description="Port 6379"
                status={svc['user-service']?.details?.dependencies?.redis ?? 'unknown'}
                detail={svc['user-service']?.details?.dependencies?.redis ?? ''}
              />
            </>
          )}
        </div>
      </div>

      {/* Architecture overview */}
      <div className="card" style={{ marginTop: 20 }}>
        <div className="card-title">Architecture Overview</div>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', flexWrap: 'wrap', gap: 0 }}>
          {[
            { icon: 'WWW', label: 'Browser',   sub: 'User' },
            { arrow: true },
            { icon: 'Nx',  label: 'Nginx',     sub: 'Frontend :80' },
            { arrow: true },
            { icon: 'GW',  label: 'Gateway',   sub: 'Express :3000' },
            { arrow: true },
            { icon: 'US',  label: 'Users',     sub: 'FastAPI :8000' },
            { arrow: true },
            { icon: 'PG',  label: 'PostgreSQL', sub: ':5432' },
          ].map((item, i) =>
            item.arrow ? (
              <div key={i} style={{ color: 'var(--text-muted)', fontSize: '1.4rem', padding: '0 8px' }}>{'->'}</div>
            ) : (
              <div key={i} style={{ textAlign: 'center', padding: '12px 16px', background: 'var(--bg-card)', borderRadius: 8, border: '1px solid var(--border)', minWidth: 90 }}>
                <div style={{ fontSize: '1.1rem', fontWeight: 700 }}>{item.icon}</div>
                <div style={{ fontWeight: 600, marginTop: 4, fontSize: '.85rem' }}>{item.label}</div>
                <div style={{ fontSize: '.7rem', color: 'var(--text-muted)' }}>{item.sub}</div>
              </div>
            )
          )}
        </div>
        <div style={{ display: 'flex', justifyContent: 'center', gap: 24, marginTop: 16 }}>
          {[
            { label: 'Products', sub: 'Express + Mongo' },
            { label: 'Orders', sub: 'FastAPI + PG' },
            { label: 'Redis', sub: 'Cache layer' },
          ].map((item, i) => (
            <div key={i} style={{ textAlign: 'center', padding: '10px 16px', background: 'var(--bg-card)', borderRadius: 8, border: '1px solid var(--border)', minWidth: 90 }}>
              <div style={{ fontWeight: 600, fontSize: '.85rem' }}>{item.label}</div>
              <div style={{ fontSize: '.7rem', color: 'var(--text-muted)' }}>{item.sub}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
