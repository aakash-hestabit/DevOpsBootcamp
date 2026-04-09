import React, { useState, useEffect, useCallback } from 'react';
import './App.css';

const API_URL = import.meta.env.VITE_API_URL || 'http://backend-service/api';

if (!import.meta.env.VITE_API_URL) {
  console.warn('VITE_API_URL not set, using default: http://backend-service/api');
}
console.log('API URL:', API_URL);

function ServiceRow({ name, description, status, detail }) {
  const dotClass =
    status === 'healthy' || status === 'connected'
      ? 'green'
      : status === 'loading'
      ? 'yellow'
      : status === 'degraded'
      ? 'yellow'
      : 'red';

  return (
    <div className="service-row">
      <div className="service-info">
        <span className={`dot ${dotClass}`} />
        <div>
          <div className="service-name">{name}</div>
          <div className="service-desc">{description}</div>
        </div>
      </div>
      {detail && (
        <span style={{ fontSize: '.82rem', color: 'var(--text-muted)' }}>
          {detail}
        </span>
      )}
    </div>
  );
}

function App() {
  const [backendHealth, setBackendHealth] = useState(null);
  const [dbReady, setDbReady] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [lastChecked, setLastChecked] = useState(null);

  const fetchStatus = useCallback(async () => {
  try {
    setError(null);

    // 1. Health (CRITICAL)
    const healthRes = await fetch(`${API_URL}/health`);
    const healthData = await healthRes.json();

    if (!healthRes.ok) {
      throw new Error(
        healthData.message || `Health check failed (${healthRes.status})`
      );
    }

    // 2. Ready (NON-CRITICAL)
    let readyData = null;

    try {
      const readyRes = await fetch(`${API_URL}/ready`);
      readyData = await readyRes.json();

      // even if not ok → still store response (important)
      setDbReady(readyData);

    } catch (err) {
      console.warn('DB check failed:', err.message);

      readyData = {
        status: 'disconnected',
        message: 'Database unreachable',
      };

      setDbReady(readyData);
    }

    // Always set backend if healthy
    setBackendHealth(healthData);
    setLastChecked(new Date());

  } catch (err) {
    console.error('Critical fetch error:', err);

    // ONLY backend/network errors come here
    setError(err.message || 'Backend unreachable');
    setBackendHealth(null);
    setDbReady(null);
  } finally {
    setLoading(false);
  }
}, [API_URL]);

  useEffect(() => {
    fetchStatus();
    const id = setInterval(fetchStatus, 10000);
    return () => clearInterval(id);
  }, [fetchStatus]);

  // Improved status logic
  const overallStatus = loading
    ? 'loading'
    : error
    ? 'unhealthy'
    : backendHealth?.status === 'healthy'
    ? dbReady?.status === 'connected'
      ? 'healthy'
      : 'degraded'
    : 'unhealthy';

  return (
    <div className="app">
      <header className="header">
        <div className="header-inner">
          <div className="logo">
            <span className="logo-icon">⚙️</span>
            <span className="logo-text">Dashboard</span>
          </div>
        </div>
      </header>

      <main className="main">
        <div className="page-title">
          <h1>System Status</h1>
          <p>Real-time health and connectivity status</p>
        </div>

        <div className="grid-2">
          {/* Overall Status */}
          <div className="card">
            <div className="card-title">Overall Status</div>

            {loading ? (
              <div className="loader">Checking status...</div>
            ) : (
              <>
                <div style={{ marginBottom: '16px' }}>
                  <span className={`chip ${overallStatus}`}>
                    {overallStatus === 'healthy'
                      ? '✓'
                      : overallStatus === 'degraded'
                      ? '⚠'
                      : '✕'}{' '}
                    {overallStatus.toUpperCase()}
                  </span>
                </div>

                {error && (
                  <div className="error-box" style={{ marginBottom: '10px' }}>
                    {error}
                  </div>
                )}

                {lastChecked && (
                  <div
                    style={{
                      fontSize: '.8rem',
                      color: 'var(--text-muted)',
                    }}
                  >
                    Last checked: {lastChecked.toLocaleTimeString()}
                  </div>
                )}
              </>
            )}
          </div>

          {/* Services */}
          <div className="card">
            <div className="card-title">Backend & Database</div>

            {!loading && (
              <>
                <ServiceRow
                  name="Backend Service"
                  description="Node.js API Server"
                  status={backendHealth?.status || 'unhealthy'}
                  detail={backendHealth?.message}
                />

                <ServiceRow
                  name="PostgreSQL Database"
                  description="Database Connection"
                  status={
                    dbReady?.status ||
                    (backendHealth?.status === 'healthy'
                      ? 'degraded'
                      : 'unhealthy')
                  }
                  detail={dbReady?.message}
                />
              </>
            )}
          </div>
        </div>
      </main>

      <footer className="footer">
        <p>Dashboard -- React / Node.js / PostgreSQL / Kubernetes</p>
      </footer>
    </div>
  );
}

export default App;
