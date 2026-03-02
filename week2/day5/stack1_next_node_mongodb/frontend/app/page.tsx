import Link from 'next/link';
import { api } from '@/lib/api';

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
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-bold text-gray-900">Stack 1: Users Dashboard</h1>
        <p className="mt-2 text-gray-600">Next.js 15 frontend connected to Express.js + MongoDB backend</p>
      </div>

      {/* Health status card */}
      <div className="bg-white rounded-xl border border-gray-200 p-6 shadow-sm">
        <h2 className="text-lg font-semibold text-gray-800 mb-4">Backend Health</h2>
        {health ? (
          <div className="space-y-2">
            <div className="flex items-center gap-2">
              <span className={`inline-block w-3 h-3 rounded-full ${isHealthy ? 'bg-green-500' : 'bg-red-500'}`} />
              <span className="font-medium capitalize text-black">{String(health.status)}</span>
            </div>
            <div className="text-sm text-gray-600 grid grid-cols-2 gap-2 mt-3">
              <div><span className="font-medium">Environment:</span> {String(health.environment)}</div>
              <div><span className="font-medium">Version:</span> {String(health.version)}</div>
              <div><span className="font-medium">Uptime:</span> {String(health.uptime)}s</div>
              <div>
                <span className="font-medium">Database:</span>{' '}
                {String((health.database as Record<string,unknown>)?.status)}
              </div>
            </div>
          </div>
        ) : (
          <div className="flex items-center gap-2 text-red-600">
            <span className="inline-block w-3 h-3 rounded-full bg-red-500" />
            <span>Backend unreachable — is the Express server running on port 3000?</span>
          </div>
        )}
      </div>

      
      <Link
        href="/users"
        className="inline-block bg-gray-900 text-white px-6 py-3 rounded-lg font-medium hover:bg-gray-700 transition-colors"
      >
        Manage Users →
      </Link>
    </div>
  );
}