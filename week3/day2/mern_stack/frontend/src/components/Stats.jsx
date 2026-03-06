import React, { useState, useEffect, useCallback } from 'react';

const API = import.meta.env.VITE_API_URL || '/api';

function MemBar({ label, value, max }) {
  const pct = Math.min(100, (value / max) * 100).toFixed(1);
  return (
    <div style={{ marginBottom: 10 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '.8rem', marginBottom: 4 }}>
        <span style={{ color: 'var(--text-muted)' }}>{label}</span>
        <span style={{ fontWeight: 600 }}>{(value / 1024 / 1024).toFixed(1)} MB</span>
      </div>
      <div style={{ background: 'var(--bg-card)', borderRadius: 4, height: 6, overflow: 'hidden' }}>
        <div style={{ width: `${pct}%`, height: '100%', background: 'var(--accent)', borderRadius: 4, transition: 'width .4s' }} />
      </div>
    </div>
  );
}

export default function Stats() {
  const [stats, setStats]     = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError]     = useState(null);
  const [lastFetch, setLastFetch] = useState(null);

  const fetchStats = useCallback(async () => {
    try {
      setError(null);
      const res  = await fetch(`${API}/stats`);
      const data = await res.json();
      if (!data.success) throw new Error(data.error);
      setStats(data.data);
      setLastFetch(new Date());
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchStats();
    const id = setInterval(fetchStats, 20000);
    return () => clearInterval(id);
  }, [fetchStats]);

  if (loading) return <div className="loader">Loading statistics…</div>;

  return (
    <div>
      {error && <div className="error-box">⚠ {error}</div>}

      {/* ── KPI tiles ── */}
      <div className="grid-4" style={{ marginBottom: 20 }}>
        {[
          { label: 'Total Users',   value: stats?.totalUsers ?? '—'  },
          { label: 'Server Uptime', value: stats?.uptime ?? '—'      },
          { label: 'Node Version',  value: stats?.nodeVersion ?? '—' },
          { label: 'Server Time',   value: stats?.serverTime ? new Date(stats.serverTime).toLocaleTimeString() : '—' },
        ].map(({ label, value }) => (
          <div className="stat-tile" key={label}>
            <div className="label">{label}</div>
            <div className="value">{value}</div>
          </div>
        ))}
      </div>

      {/* ── Role breakdown ── */}
      {stats?.roleBreakdown?.length > 0 && (
        <div className="grid-2" style={{ marginBottom: 20 }}>
          <div className="card">
            <div className="card-title">Role Breakdown</div>
            {stats.roleBreakdown.map(({ role, count }) => (
              <div key={role} style={{ display: 'flex', justifyContent: 'space-between', padding: '8px 0', borderBottom: '1px solid var(--border)' }}>
                <span className={`tag ${role}`}>{role}</span>
                <span style={{ fontWeight: 600 }}>{count}</span>
              </div>
            ))}
          </div>

          {/* ── Memory ── */}
          {stats?.memoryUsage && (
            <div className="card">
              <div className="card-title">Memory Usage</div>
              <MemBar label="RSS"        value={stats.memoryUsage.rss}          max={512 * 1024 * 1024} />
              <MemBar label="Heap Used"  value={stats.memoryUsage.heapUsed}     max={stats.memoryUsage.heapTotal} />
              <MemBar label="Heap Total" value={stats.memoryUsage.heapTotal}    max={512 * 1024 * 1024} />
            </div>
          )}
        </div>
      )}

      {lastFetch && (
        <p style={{ textAlign: 'right', fontSize: '.8rem', color: 'var(--text-muted)' }}>
          Last updated: {lastFetch.toLocaleTimeString()} &nbsp;·&nbsp; auto-refresh every 20 s
        </p>
      )}
    </div>
  );
}
