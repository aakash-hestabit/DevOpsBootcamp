import Head from 'next/head';
import Link from 'next/link';

export default function UsersPage({ users, total }) {
  return (
    <>
      <Head><title>Users — Next.js App</title></Head>
      <main style={{ fontFamily: 'sans-serif', maxWidth: 800, margin: '0 auto', padding: 20 }}>
        <h1>Users ({total})</h1>
        <Link href="/">← Home</Link>
        {users.length === 0 ? (
          <p>No users yet. POST to /api/users to create one.</p>
        ) : (
          <table border="1" cellPadding="8" style={{ width: '100%', marginTop: 16 }}>
            <thead>
              <tr><th>ID</th><th>Username</th><th>Email</th><th>Full Name</th></tr>
            </thead>
            <tbody>
              {users.map(u => (
                <tr key={u.id}>
                  <td><Link href={`/users/${u.id}`}>{u.id}</Link></td>
                  <td>{u.username}</td>
                  <td>{u.email}</td>
                  <td>{u.full_name || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </main>
    </>
  );
}

export async function getServerSideProps() {
  try {
    const { query } = await import('../lib/db');
    const { rows } = await query('SELECT id, username, email, full_name FROM users ORDER BY id ASC LIMIT 50');
    const count = await query('SELECT COUNT(*) AS total FROM users');
    return { props: { users: rows, total: parseInt(count.rows[0].total) } };
  } catch {
    return { props: { users: [], total: 0 } };
  }
}