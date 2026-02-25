import Head from 'next/head';
import Link from 'next/link';

export default function UserDetail({ user }) {
  if (!user) {
    return (
      <main style={{ fontFamily: 'sans-serif', maxWidth: 800, margin: '0 auto', padding: 20 }}>
        <h1>User not found</h1>
        <Link href="/users">← Back to Users</Link>
      </main>
    );
  }

  return (
    <>
      <Head><title>User #{user.id} — Next.js App</title></Head>
      <main style={{ fontFamily: 'sans-serif', maxWidth: 800, margin: '0 auto', padding: 20 }}>
        <Link href="/users">← Back to Users</Link>
        <h1>User #{user.id}</h1>
        <table border="1" cellPadding="8">
          <tbody>
            <tr><td><strong>Username</strong></td><td>{user.username}</td></tr>
            <tr><td><strong>Email</strong></td><td>{user.email}</td></tr>
            <tr><td><strong>Full Name</strong></td><td>{user.full_name || '—'}</td></tr>
            <tr><td><strong>Created</strong></td><td>{new Date(user.created_at).toLocaleString()}</td></tr>
            <tr><td><strong>Updated</strong></td><td>{new Date(user.updated_at).toLocaleString()}</td></tr>
          </tbody>
        </table>
      </main>
    </>
  );
}

export async function getServerSideProps({ params }) {
  const id = parseInt(params.id);
  if (isNaN(id)) return { notFound: true };

  try {
    const { query } = await import('../../lib/db');
    const { rows } = await query('SELECT * FROM users WHERE id = $1', [id]);
    return rows[0]
      ? { props: { user: rows[0] } }
      : { notFound: true };
  } catch {
    return { notFound: true };
  }
}