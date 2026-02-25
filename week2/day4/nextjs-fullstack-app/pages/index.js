import Head from 'next/head';
import Link from 'next/link';

export default function Home({ health }) {
  return (
    <>
      <Head><title>Next.js Fullstack App</title></Head>
      <main style={{ fontFamily: 'sans-serif', maxWidth: 800, margin: '0 auto', padding: 20 }}>
        <h1>Next.js Fullstack App</h1>
        <p>Server status: <strong style={{ color: health.status === 'healthy' ? 'green' : 'red' }}>
          {health.status}
        </strong></p>
        <p>Database: {health.database?.status}</p>
        <p>Environment: {health.environment}</p>
        <nav>
          <Link href="/users">View All Users</Link>
        </nav>
      </main>
    </>
  );
}

// Server-side rendering: fetch health on every request
export async function getServerSideProps() {
  try {
    const { testConnection, getPoolStats } = await import('../lib/db');
    const dbConnected = await testConnection();
    return {
      props: {
        health: {
          status: dbConnected ? 'healthy' : 'unhealthy',
          database: { status: dbConnected ? 'connected' : 'disconnected' },
          environment: process.env.NODE_ENV,
        },
      },
    };
  } catch {
    return { props: { health: { status: 'error', database: { status: 'unknown' } } } };
  }
}