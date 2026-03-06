import React, { useState } from 'react';
import Auth from './components/Auth.jsx';
import HealthStatus from './components/HealthStatus.jsx';
import UserList from './components/UserList.jsx';
import Stats from './components/Stats.jsx';

const TABS = ['Dashboard', 'Users', 'Stats'];

export default function App() {
  const [token, setToken]       = useState(() => localStorage.getItem('token') || '');
  const [activeTab, setActiveTab] = useState('Dashboard');

  const handleLogin = (t) => {
    setToken(t);
    localStorage.setItem('token', t);
  };

  const handleLogout = () => {
    setToken('');
    localStorage.removeItem('token');
  };

  if (!token) return <Auth onLogin={handleLogin} />;

  return (
    <div className="app">
      {/* ── Header ── */}
      <header className="header">
        <div className="header-inner">
          <div className="logo">
            <span className="logo-icon">⬡</span>
            <span className="logo-text">MERN Stack</span>
          </div>
          <nav className="nav">
            {TABS.map((tab) => (
              <button
                key={tab}
                className={`nav-btn ${activeTab === tab ? 'active' : ''}`}
                onClick={() => setActiveTab(tab)}
              >
                {tab}
              </button>
            ))}
          </nav>
          <div className="stack-badges">
            <span className="badge react">React</span>
            <span className="badge node">Node</span>
            <span className="badge mongo">MongoDB</span>
          </div>
          <button className="btn btn-ghost" onClick={handleLogout} style={{ marginLeft: 8 }}>
            Logout
          </button>
        </div>
      </header>

      {/* ── Main ── */}
      <main className="main">
        {activeTab === 'Dashboard' && (
          <div className="page">
            <div className="page-title">
              <h1>System Dashboard</h1>
              <p>Real-time health &amp; status of all services</p>
            </div>
            <HealthStatus />
          </div>
        )}
        {activeTab === 'Users' && (
          <div className="page">
            <div className="page-title">
              <h1>User Management</h1>
              <p>Create, read, update and delete users</p>
            </div>
            <UserList token={token} />
          </div>
        )}
        {activeTab === 'Stats' && (
          <div className="page">
            <div className="page-title">
              <h1>Application Stats</h1>
              <p>Live metrics from the backend</p>
            </div>
            <Stats />
          </div>
        )}
      </main>

      {/* ── Footer ── */}
      <footer className="footer">
        <p>MERN Stack &mdash; React · Vite · Express · MongoDB · Docker</p>
      </footer>
    </div>
  );
}
