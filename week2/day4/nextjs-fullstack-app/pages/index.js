import Head from 'next/head';
import Link from 'next/link';
import { testConnection } from '../lib/db';
import styles from '../styles/Home.module.css';

export default function Home({ status }) {
  return (
    <>
      <Head>
        <title>Next.js Fullstack App</title>
        <meta name="description" content="A complete Next.js fullstack application with API routes and PostgreSQL" />
      </Head>

      <main className={styles.container}>
        <section className={styles.hero}>
          <h1>Next.js Fullstack App</h1>
          <p>A complete application with server-side rendering, API routes, and PostgreSQL database.</p>
        </section>

        <section className={styles.statusSection}>
          <div className={`${styles.statusCard} ${status === 'healthy' ? styles.healthy : styles.unhealthy}`}>
            <div className={styles.statusIcon}>
              {status === 'healthy' ? '✓' : '✗'}
            </div>
            <div>
              <h3>System Status</h3>
              <p>{status === 'healthy' ? 'All systems operational' : 'System error detected'}</p>
            </div>
          </div>
        </section>

        <section className={styles.linksSection}>
          <h2>Quick Navigation</h2>
          <div className={styles.links}>
            <Link href="/users" className={styles.link}>
              <span className={styles.icon}>👥</span>
              <div>
                <h3>Users</h3>
                <p>View and manage all users</p>
              </div>
            </Link>
          </div>
        </section>

        <section className={styles.apiSection}>
          <h2>API Endpoints</h2>
          <div className={styles.apiGrid}>
            <div className={styles.apiCard}>
              <div className={styles.method}>GET</div>
              <div className={styles.endpoint}>/api/health</div>
              <p>Health check endpoint</p>
            </div>
            <div className={styles.apiCard}>
              <div className={styles.method}>GET</div>
              <div className={styles.endpoint}>/api/users</div>
              <p>List all users</p>
            </div>
            <div className={styles.apiCard}>
              <div className={styles.method}>POST</div>
              <div className={styles.endpoint}>/api/users</div>
              <p>Create new user</p>
            </div>
            <div className={styles.apiCard}>
              <div className={styles.method}>GET</div>
              <div className={styles.endpoint}>/api/users/[id]</div>
              <p>Get user details</p>
            </div>
            <div className={styles.apiCard}>
              <div className={styles.method}>PUT</div>
              <div className={styles.endpoint}>/api/users/[id]</div>
              <p>Update user</p>
            </div>
            <div className={styles.apiCard}>
              <div className={styles.method}>DELETE</div>
              <div className={styles.endpoint}>/api/users/[id]</div>
              <p>Delete user</p>
            </div>
          </div>
        </section>

        <section className={styles.featuresSection}>
          <h2>Features</h2>
          <ul className={styles.featuresList}>
            <li>✓ Server-side rendering (SSR)</li>
            <li>✓ API routes for backend logic</li>
            <li>✓ PostgreSQL database integration</li>
            <li>✓ Client-side and server-side data fetching</li>
            <li>✓ Form handling with validation</li>
            <li>✓ Error boundaries</li>
            <li>✓ Environment variables</li>
            <li>✓ Health check monitoring</li>
          </ul>
        </section>

        <section className={styles.exampleSection}>
          <h2>Quick Test</h2>
          <p>Try these commands:</p>
          <pre className={styles.codeBlock}>
{`# Health check
curl http://localhost:3001/api/health

# List users
curl http://localhost:3001/api/users

# Create user
curl -X POST http://localhost:3001/api/users \\
  -H "Content-Type: application/json" \\
  -d '{
    "username": "john_doe",
    "email": "john@example.com",
    "full_name": "John Doe"
  }'

# Get specific user
curl http://localhost:3001/api/users/1

# Update user
curl -X PUT http://localhost:3001/api/users/1 \\
  -H "Content-Type: application/json" \\
  -d '{
    "email": "newemail@example.com"
  }'

# Delete user
curl -X DELETE http://localhost:3001/api/users/1`}
          </pre>
        </section>
      </main>
    </>
  );
}

export async function getServerSideProps() {
  try {
    const dbConnected = await testConnection();
    return {
      props: {
        status: dbConnected ? 'healthy' : 'unhealthy',
      },
    };
  } catch {
    return {
      props: {
        status: 'error',
      },
    };
  }
}