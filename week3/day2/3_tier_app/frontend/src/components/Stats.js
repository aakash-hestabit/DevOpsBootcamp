import React, { useState, useEffect, useCallback } from 'react';

const API = process.env.REACT_APP_API_URL || '/api';

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
  const [stats, setStats]   = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError]   = useState(null);
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
          { label: 'Server Uptime', value: stats?.uptime ?? '—'       },
          { label: 'Node Version',  value: stats?.nodeVersion ?? '—'  },
          { label: 'Server Time',   value: stats?.serverTime ? new Date(stats.serverTime).toLocaleTimeString() : '—' },
        ].map(({ label, value }) => (
          <div className="stat-tile" key={label}>
            <div className="label">{label}</div>
            <div className="value" style={{ fontSize: '1.4rem' }}>{value}</div>
          </div>
        ))}
      </div>

      <div className="grid-2">
        {/* Role breakdown */}
        <div className="card">
          <div className="card-title">Users by Role</div>
          {stats?.roleBreakdown?.length ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              {stats.roleBreakdown.map(({ role, count }) => {
                const pct = stats.totalUsers > 0 ? ((count / stats.totalUsers) * 100).toFixed(0) : 0;
                return (
                  <div key={role}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4, fontSize: '.88rem' }}>
                      <span className={`tag ${role}`}>{role}</span>
                      <span style={{ fontWeight: 700, color: 'var(--accent)' }}>{count} <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>({pct}%)</span></span>
                    </div>
                    <div style={{ background: 'var(--bg-card)', borderRadius: 4, height: 6 }}>
                      <div style={{ width: `${pct}%`, height: '100%', background: 'var(--accent)', borderRadius: 4, transition: 'width .4s' }} />
                    </div>
                  </div>
                );
              })}
            </div>
          ) : (
            <div className="empty">No users yet</div>
          )}
        </div>

        {/* Memory usage */}
        <div className="card">
          <div className="card-title">Backend Memory Usage</div>
          {stats?.memoryUsage ? (
            <>
              <MemBar label="Heap Used"  value={stats.memoryUsage.heapUsed}  max={stats.memoryUsage.heapTotal} />
              <MemBar label="Heap Total" value={stats.memoryUsage.heapTotal} max={stats.memoryUsage.rss} />
              <MemBar label="RSS"        value={stats.memoryUsage.rss}       max={stats.memoryUsage.rss * 1.5} />
              <MemBar label="External"   value={stats.memoryUsage.external}  max={stats.memoryUsage.rss} />
            </>
          ) : (
            <div className="empty">No data</div>
          )}
        </div>
      </div>

      {/* ── Recent users ── */}
      <div className="card" style={{ marginTop: 20 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
          <div className="card-title" style={{ margin: 0 }}>Recent Users</div>
          {lastFetch && (
            <span style={{ fontSize: '.78rem', color: 'var(--text-muted)' }}>
              Updated: {lastFetch.toLocaleTimeString()}
            </span>
          )}
        </div>
        {stats?.recentUsers?.length ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>ID</th>
                  <th>Name</th>
                  <th>Email</th>
                  <th>Role</th>
                  <th>Joined</th>
                </tr>
              </thead>
              <tbody>
                {stats.recentUsers.map((u) => (
                  <tr key={u.id}>
                    <td style={{ color: 'var(--text-muted)', fontFamily: 'monospace' }}>#{u.id}</td>
                    <td style={{ fontWeight: 600 }}>{u.name}</td>
                    <td style={{ color: 'var(--text-muted)' }}>{u.email}</td>
                    <td><span className={`tag ${u.role}`}>{u.role}</span></td>
                    <td style={{ color: 'var(--text-muted)', fontSize: '.82rem' }}>
                      {new Date(u.created_at).toLocaleDateString()}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="empty">No users yet</div>
        )}
      </div>
    </div>
  );
}
