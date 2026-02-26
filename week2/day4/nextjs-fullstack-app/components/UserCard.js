import Link from 'next/link';
import styles from '../styles/UserCard.module.css';

export default function UserCard({ user, onDelete }) {
  const handleDelete = async () => {
    if (confirm('Are you sure you want to delete this user?')) {
      try {
        const res = await fetch(`/api/users/${user.id}`, {
          method: 'DELETE',
        });

        if (!res.ok) {
          const error = await res.json();
          alert(`Error: ${error.error}`);
          return;
        }

        onDelete?.(user.id);
      } catch (err) {
        alert(`Error deleting user: ${err.message}`);
      }
    }
  };

  return (
    <div className={styles.card}>
      <div className={styles.header}>
        <h3 className={styles.username}>{user.username}</h3>
        <span className={styles.id}>ID: {user.id}</span>
      </div>

      <div className={styles.body}>
        <p>
          <strong>Email:</strong> <a href={`mailto:${user.email}`}>{user.email}</a>
        </p>
        {user.full_name && (
          <p>
            <strong>Full Name:</strong> {user.full_name}
          </p>
        )}
        <p className={styles.meta}>
          Created: {new Date(user.created_at).toLocaleDateString()} at {new Date(user.created_at).toLocaleTimeString()}
        </p>
      </div>

      <div className={styles.actions}>
        <Link href={`/users/${user.id}`} className={styles.btnPrimary}>
          View Details
        </Link>
        <button onClick={handleDelete} className={styles.btnDanger}>
          Delete
        </button>
      </div>
    </div>
  );
}
