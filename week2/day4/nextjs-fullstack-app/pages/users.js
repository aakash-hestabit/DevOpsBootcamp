import { useState } from 'react';
import Head from 'next/head';
import Link from 'next/link';
import UserCard from '../components/UserCard';
import UserForm from '../components/UserForm';
import { query } from '../lib/db';
import styles from '../styles/Users.module.css';

export default function UsersPage({ initialUsers = [], error }) {
  const [users, setUsers] = useState(initialUsers);
  const [showForm, setShowForm] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [isLoading, setIsLoading] = useState(false);

  if (error) {
    return (
      <main className={styles.container}>
        <Link href="/" className={styles.backLink}>
          ⬅️ Home
        </Link>
        <div className={styles.error}>
          <h1>Error Loading Users</h1>
          <p>{error}</p>
        </div>
      </main>
    );
  }

  const handleCreateUser = async (formData) => {
    try {
      const res = await fetch('/api/users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData),
      });

      if (!res.ok) {
        const errorData = await res.json();
        throw new Error(errorData.error || 'Failed to create user');
      }

      const data = await res.json();
      setUsers((prev) => [data.data, ...prev]);
      setShowForm(false);
    } catch (err) {
      throw err;
    }
  };

  const handleDeleteUser = (userId) => {
    setUsers((prev) => prev.filter((u) => u.id !== userId));
  };

  const filteredUsers = users.filter(
    (user) =>
      user.username.toLowerCase().includes(searchTerm.toLowerCase()) ||
      user.email.toLowerCase().includes(searchTerm.toLowerCase()) ||
      (user.full_name && user.full_name.toLowerCase().includes(searchTerm.toLowerCase()))
  );

  return (
    <>
      <Head>
        <title>Users - Next.js App</title>
      </Head>

      <main className={styles.container}>
        <Link href="/" className={styles.backLink}>
          ⬅️ Home
        </Link>

        <div className={styles.header}>
          <div>
            <h1>Users</h1>
            <p className={styles.count}>Total: {users.length} users</p>
          </div>
          <button
            onClick={() => setShowForm(!showForm)}
            className={styles.btnCreate}
          >
            {showForm ? '✕ Close' : '+ New User'}
          </button>
        </div>

        {showForm && (
          <div className={styles.formSection}>
            <h2>Create New User</h2>
            <UserForm onSubmit={handleCreateUser} />
          </div>
        )}

        <div className={styles.searchBar}>
          <input
            type="text"
            placeholder="Search by username, email, or full name..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className={styles.searchInput}
          />
        </div>

        {filteredUsers.length === 0 ? (
          <div className={styles.emptyState}>
            {users.length === 0 ? (
              <>
                <h2>No users yet</h2>
                <p>Create your first user using the form above</p>
              </>
            ) : (
              <>
                <h2>No results found</h2>
                <p>Try adjusting your search criteria</p>
              </>
            )}
          </div>
        ) : (
          <div className={styles.usersList}>
            {filteredUsers.map((user) => (
              <UserCard key={user.id} user={user} onDelete={handleDeleteUser} />
            ))}
          </div>
        )}
      </main>
    </>
  );
}

export async function getServerSideProps() {
  try {
    const { rows } = await query('SELECT * FROM users ORDER BY created_at DESC LIMIT 50', []);
    
    // Convert Date objects to strings for serialization
    const serializedUsers = rows.map(user => ({
      ...user,
      created_at: user.created_at.toISOString(),
      updated_at: user.updated_at.toISOString(),
    }));
    
    return {
      props: { initialUsers: serializedUsers, error: null },
    };
  } catch (err) {
    console.error('[USERS PAGE]', err.message);
    return {
      props: { initialUsers: [], error: 'Failed to load users' },
    };
  }
}