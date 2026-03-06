const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

pool.on('error', (err) => {
  console.error('Unexpected error on idle db client', err);
});

const query = (text, params) => pool.query(text, params);

const getClient = () => pool.connect();

const testConnection = async () => {
  const client = await pool.connect();
  try {
    await client.query('SELECT NOW()');
    return true;
  } finally {
    client.release();
  }
};

module.exports = { query, getClient, testConnection, pool };
