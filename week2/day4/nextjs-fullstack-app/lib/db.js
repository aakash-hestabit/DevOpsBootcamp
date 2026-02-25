import { Pool } from 'pg';

// Reuse the pool across API route invocations in development
let pool;

function getPool() {
  if (!pool) {
    pool = new Pool({
      host:     process.env.DB_HOST     || 'localhost',
      port:     parseInt(process.env.DB_PORT || '5432', 10),
      database: process.env.DB_NAME     || 'apidb',
      user:     process.env.DB_USER     || 'apiuser',
      password: process.env.DB_PASSWORD,
      max:      parseInt(process.env.DB_POOL_MAX || '10', 10),
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
    });

    pool.on('error', (err) => {
      console.error('[DB] Unexpected error on idle client:', err.message);
    });
  }
  return pool;
}

export async function query(text, params = []) {
  const start = Date.now();
  const client = getPool();
  const result = await client.query(text, params);
  console.log(`[DB] ${text.substring(0, 60)} — ${Date.now() - start}ms, rows: ${result.rowCount}`);
  return result;
}

export async function testConnection() {
  try {
    await query('SELECT 1');
    return true;
  } catch {
    return false;
  }
}

export function getPoolStats() {
  const p = getPool();
  return { total: p.totalCount, idle: p.idleCount, active: p.totalCount - p.idleCount };
}