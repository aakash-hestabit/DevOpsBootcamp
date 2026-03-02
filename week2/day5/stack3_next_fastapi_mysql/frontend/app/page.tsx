import Link from 'next/link';
import { api } from '@/lib/api';

// ISR: revalidate this page every 30 seconds
export const revalidate = 30;

async function getHealth() {
  try {
    return await api.health();
  } catch {
    return null;
  }
}

export default async function HomePage() {
  const health = await getHealth();
  const isHealthy = health && (health as Record<string,unknown>).status === 'healthy';

  return (
    <div className="space-y-8 animate-fade-in">
      {/* Hero Section */}
      <div className="relative overflow-hidden rounded-2xl bg-gradient-to-r from-indigo-600 via-purple-600 to-pink-600 p-12 text-white shadow-xl">
        <div className="absolute top-0 right-0 -mt-8 -mr-8 w-96 h-96 bg-white/10 rounded-full blur-3xl"></div>
        <div className="relative z-10">
          <h1 className="text-5xl font-bold mb-4">Products Dashboard</h1>
          <p className="text-lg text-white/90">Manage your inventory with real-time backend insights</p>
          <p className="text-sm text-white/70 mt-2">Stack 3: Next.js 15 + FastAPI + MySQL</p>
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="bg-white/60 backdrop-blur-sm rounded-2xl border border-white/40 p-8 shadow-sm hover:shadow-lg transition-all duration-300 group">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-gray-600 text-sm font-semibold uppercase tracking-wider">Backend Status</h3>
            <div className={`w-3 h-3 rounded-full ${isHealthy ? 'bg-green-500 animate-pulse' : 'bg-red-500'}`}></div>
          </div>
          <p className="text-3xl font-bold text-gray-900 capitalize">{isHealthy ? 'Healthy' : 'Offline'}</p>
          <p className="text-sm text-gray-500 mt-2">API connection status</p>
        </div>

        <div className="bg-white/60 backdrop-blur-sm rounded-2xl border border-white/40 p-8 shadow-sm hover:shadow-lg transition-all duration-300">
          <h3 className="text-gray-600 text-sm font-semibold uppercase tracking-wider mb-4">Database</h3>
          <p className="text-3xl font-bold text-gray-900">{health ? String((health.database as Record<string,unknown>)?.status) : 'N/A'}</p>
          <p className="text-sm text-gray-500 mt-2">MySQL connection</p>
        </div>

        <div className="bg-white/60 backdrop-blur-sm rounded-2xl border border-white/40 p-8 shadow-sm hover:shadow-lg transition-all duration-300">
          <h3 className="text-gray-600 text-sm font-semibold uppercase tracking-wider mb-4">Uptime</h3>
          <p className="text-3xl font-bold text-gray-900">{health ? `${String(health.uptime)}s` : 'N/A'}</p>
          <p className="text-sm text-gray-500 mt-2">Service runtime</p>
        </div>
      </div>

      {/* Health Card */}
      <div className="bg-white/80 backdrop-blur-sm rounded-2xl border border-white/40 p-8 shadow-sm hover:shadow-lg transition-all duration-300">
        <div className="flex items-start justify-between mb-6">
          <div>
            <h2 className="text-2xl font-bold text-gray-900 mb-2">Connection Details</h2>
            <p className="text-gray-600">Real-time backend information</p>
          </div>
          {health && (
            <span className={`px-4 py-2 rounded-full text-sm font-semibold ${
              isHealthy 
                ? 'bg-green-100 text-green-800' 
                : 'bg-red-100 text-red-800'
            }`}>
              {isHealthy ? '✓ Connected' : '✗ Disconnected'}
            </span>
          )}
        </div>

        {health ? (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="bg-gradient-to-br from-indigo-50 to-blue-50 rounded-xl p-6 border border-indigo-100">
              <h3 className="text-sm font-semibold text-indigo-900 mb-4 uppercase tracking-wide">Configuration</h3>
              <div className="space-y-3">
                <div className="flex justify-between items-center">
                  <span className="text-gray-600">Environment:</span>
                  <span className="font-semibold text-gray-900">{String(health.environment)}</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-gray-600">Version:</span>
                  <span className="font-semibold text-gray-900">{String(health.version)}</span>
                </div>
              </div>
            </div>

            <div className="bg-gradient-to-br from-purple-50 to-pink-50 rounded-xl p-6 border border-purple-100">
              <h3 className="text-sm font-semibold text-purple-900 mb-4 uppercase tracking-wide">Database</h3>
              <div className="space-y-3">
                <div className="flex justify-between items-center">
                  <span className="text-gray-600">Status:</span>
                  <span className={`font-semibold ${String((health.database as Record<string,unknown>)?.status) === 'connected' ? 'text-green-600' : 'text-red-600'}`}>
                    {String((health.database as Record<string,unknown>)?.status)}
                  </span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-gray-600">Uptime:</span>
                  <span className="font-semibold text-gray-900">{String(health.uptime)}s</span>
                </div>
              </div>
            </div>
          </div>
        ) : (
          <div className="bg-red-50 border-2 border-red-200 rounded-xl p-6 text-center">
            <div className="w-12 h-12 bg-red-100 rounded-full flex items-center justify-center mx-auto mb-4">
              <span className="text-2xl">⚠️</span>
            </div>
            <h3 className="text-lg font-bold text-red-900 mb-2">Backend Unreachable</h3>
            <p className="text-red-700">Make sure FastAPI is running on port 8003</p>
            <code className="mt-4 block text-sm bg-red-100 text-red-900 p-3 rounded font-mono">http://localhost:8003</code>
          </div>
        )}
      </div>

      {/* CTA Section */}
      <div className="flex gap-4 justify-center flex-wrap">
        <Link
          href="/products"
          className="px-8 py-4 rounded-xl bg-gradient-to-r from-indigo-600 to-purple-600 text-white font-semibold hover:shadow-lg hover:shadow-indigo-500/30 transition-all duration-200 transform hover:scale-105 flex items-center gap-2"
        >
          <span>📦</span> Manage Products
        </Link>
        <a
          href={`${process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8003'}/docs`}
          target="_blank"
          rel="noopener noreferrer"
          className="px-8 py-4 rounded-xl bg-white border-2 border-indigo-200 text-indigo-600 font-semibold hover:bg-indigo-50 transition-all duration-200 flex items-center gap-2"
        >
          <span>📚</span> API Documentation
        </a>
      </div>
    </div>
  );
}
