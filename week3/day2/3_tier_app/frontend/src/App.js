import React, { useState } from 'react';
import HealthStatus from './components/HealthStatus';
import UserList from './components/UserList';
import Stats from './components/Stats';
import './App.css';

const TABS = ['Dashboard', 'Users', 'Stats'];

function App() {
  const [activeTab, setActiveTab] = useState('Dashboard');

  return (
    <div className="app">
      {/* ── Header ── */}
      <header className="header">
        <div className="header-inner">
          <div className="logo">
            <span className="logo-icon">⬡</span>
            <span className="logo-text">3-Tier App</span>
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
            <span className="badge pg">PostgreSQL</span>
          </div>
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
            <UserList />
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
        <p>3-Tier App &mdash; React · Express · PostgreSQL · Docker</p>
      </footer>
    </div>
  );
}

export default App;
