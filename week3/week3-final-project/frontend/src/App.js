import React, { useState } from 'react';
import HealthStatus from './components/HealthStatus';
import Users from './components/Users';
import Products from './components/Products';
import Orders from './components/Orders';
import './App.css';

const TABS = ['Dashboard', 'Users', 'Products', 'Orders'];

function App() {
  const [activeTab, setActiveTab] = useState('Dashboard');

  return (
    <div className="app">
      <header className="header">
        <div className="header-inner">
          <div className="logo">
            <span className="logo-icon">&#x2B21;</span>
            <span className="logo-text">Microservices</span>
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
            <span className="badge python">FastAPI</span>
            <span className="badge node">Express</span>
            <span className="badge pg">Postgres</span>
            <span className="badge mongo">Mongo</span>
            <span className="badge redis-b">Redis</span>
          </div>
        </div>
      </header>

      <main className="main">
        {activeTab === 'Dashboard' && (
          <div className="page">
            <div className="page-title">
              <h1>System Dashboard</h1>
              <p>Real-time health and status of all microservices</p>
            </div>
            <HealthStatus />
          </div>
        )}
        {activeTab === 'Users' && (
          <div className="page">
            <div className="page-title">
              <h1>User Management</h1>
              <p>CRUD operations via User Service (FastAPI)</p>
            </div>
            <Users />
          </div>
        )}
        {activeTab === 'Products' && (
          <div className="page">
            <div className="page-title">
              <h1>Product Catalog</h1>
              <p>CRUD operations via Product Service (Express + MongoDB)</p>
            </div>
            <Products />
          </div>
        )}
        {activeTab === 'Orders' && (
          <div className="page">
            <div className="page-title">
              <h1>Order Management</h1>
              <p>CRUD operations via Order Service (FastAPI)</p>
            </div>
            <Orders />
          </div>
        )}
      </main>

      <footer className="footer">
        <p>Microservices Dashboard -- React / Express Gateway / FastAPI / PostgreSQL / MongoDB / Redis / Docker</p>
      </footer>
    </div>
  );
}

export default App;
