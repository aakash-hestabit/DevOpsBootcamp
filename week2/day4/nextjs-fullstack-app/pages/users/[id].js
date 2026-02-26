import { useState } from 'react';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import UserForm from '../../components/UserForm';
import { query } from '../../lib/db';
import styles from '../../styles/UserDetail.module.css';

export default function UserDetailPage({ user, error }) {
  const router = useRouter();
  const [isEditing, setIsEditing] = useState(false);
  const [currentUser, setCurrentUser] = useState(user);
  const [message, setMessage] = useState('');

  if (error) {
    return (
      <main className={styles.container}>
        <Link href="/users" className={styles.backLink}>
          ⬅️ Back to Users
        </Link>
        <div className={styles.error}>
          <h1>Error</h1>
          <p>{error}</p>
        </div>
      </main>
    );
  }

  const handleUpdate = async (formData) => {
    try {
      const res = await fetch(`/api/users/${currentUser.id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData),
      });

      if (!res.ok) {
        const errorData = await res.json();
        throw new Error(errorData.error || 'Failed to update user');
      }

      const data = await res.json();
      setCurrentUser(data.data);
      setIsEditing(false);
      setMessage('User updated successfully!');
      setTimeout(() => setMessage(''), 3000);
    } catch (err) {
      throw err;
    }
  };

  const handleDelete = async () => {
    if (confirm('Are you sure you want to delete this user?')) {
      try {
        const res = await fetch(`/api/users/${currentUser.id}`, {
          method: 'DELETE',
        });

        if (!res.ok) {
          const errorData = await res.json();
          throw new Error(errorData.error || 'Failed to delete user');
        }

        router.push('/users');
      } catch (err) {
        alert(`Error: ${err.message}`);
      }
    }
  };

  return (
    <>
      <Head>
        <title>User: {currentUser.username} - Next.js App</title>
      </Head>

      <main className={styles.container}>
        <Link href="/users" className={styles.backLink}>
          ⬅️ Back to Users
        </Link>

        {message && <div className={styles.successMessage}>{message}</div>}

        <div className={styles.userHeader}>
          <div>
            <h1>{currentUser.username}</h1>
            <p className={styles.email}>{currentUser.email}</p>
            {currentUser.full_name && <p className={styles.fullName}>{currentUser.full_name}</p>}
          </div>
          <div className={styles.actions}>
            {!isEditing && (
              <>
                <button onClick={() => setIsEditing(true)} className={styles.btnEdit}>
                  Edit User
                </button>
                <button onClick={handleDelete} className={styles.btnDelete}>
                  Delete User
                </button>
              </>
            )}
          </div>
        </div>

        <div className={styles.info}>
          <div className={styles.infoItem}>
            <label>User ID</label>
            <p>{currentUser.id}</p>
          </div>
          <div className={styles.infoItem}>
            <label>Created</label>
            <p>{new Date(currentUser.created_at).toLocaleString()}</p>
          </div>
          <div className={styles.infoItem}>
            <label>Last Updated</label>
            <p>{new Date(currentUser.updated_at).toLocaleString()}</p>
          </div>
        </div>

        {isEditing && (
          <div className={styles.formContainer}>
            <h2>Edit User</h2>
            <UserForm user={currentUser} onSubmit={handleUpdate} />
            <button onClick={() => setIsEditing(false)} className={styles.btnCancel}>
              Cancel
            </button>
          </div>
        )}
      </main>
    </>
  );
}

export async function getServerSideProps(context) {
  const { id } = context.params;

  try {
    const { rows } = await query('SELECT * FROM users WHERE id = $1', [id]);

    if (!rows[0]) {
      return {
        notFound: true,
      };
    }

    // Convert Date objects to strings for serialization
    const serializedUser = {
      ...rows[0],
      created_at: rows[0].created_at.toISOString(),
      updated_at: rows[0].updated_at.toISOString(),
    };

    return {
      props: {
        user: serializedUser,
        error: null,
      },
    };
  } catch (err) {
    console.error('[USER DETAIL PAGE]', err.message);
    return {
      props: {
        user: null,
        error: 'Failed to load user details',
      },
    };
  }
}