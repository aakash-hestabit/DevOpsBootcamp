import { useState } from 'react';
import styles from '../styles/UserForm.module.css';

export default function UserForm({ user = null, onSubmit, isLoading = false }) {
  const [formData, setFormData] = useState({
    username: user?.username || '',
    email: user?.email || '',
    full_name: user?.full_name || '',
  });

  const [errors, setErrors] = useState({});
  const [loading, setLoading] = useState(isLoading);
  const [message, setMessage] = useState('');

  const validateForm = () => {
    const newErrors = {};

    if (!formData.username.trim()) {
      newErrors.username = 'Username is required';
    } else if (formData.username.length < 3) {
      newErrors.username = 'Username must be at least 3 characters';
    }

    if (!formData.email.trim()) {
      newErrors.email = 'Email is required';
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(formData.email)) {
      newErrors.email = 'Invalid email address';
    }

    return newErrors;
  };

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData((prev) => ({
      ...prev,
      [name]: value,
    }));
    // Clear error for this field
    if (errors[name]) {
      setErrors((prev) => ({
        ...prev,
        [name]: '',
      }));
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    
    const formErrors = validateForm();
    if (Object.keys(formErrors).length > 0) {
      setErrors(formErrors);
      return;
    }

    setLoading(true);
    setMessage('');

    try {
      await onSubmit(formData);
      setMessage(user ? 'User updated successfully!' : 'User created successfully!');
      if (!user) {
        setFormData({ username: '', email: '', full_name: '' });
      }
    } catch (err) {
      setMessage(`Error: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <form className={styles.form} onSubmit={handleSubmit}>
      {message && (
        <div className={message.startsWith('Error') ? styles.errorMessage : styles.successMessage}>
          {message}
        </div>
      )}

      <div className={styles.formGroup}>
        <label htmlFor="username">Username *</label>
        <input
          type="text"
          id="username"
          name="username"
          value={formData.username}
          onChange={handleChange}
          placeholder="Enter username"
          disabled={loading}
          required
        />
        {errors.username && <span className={styles.error}>{errors.username}</span>}
      </div>

      <div className={styles.formGroup}>
        <label htmlFor="email">Email *</label>
        <input
          type="email"
          id="email"
          name="email"
          value={formData.email}
          onChange={handleChange}
          placeholder="Enter email address"
          disabled={loading}
          required
        />
        {errors.email && <span className={styles.error}>{errors.email}</span>}
      </div>

      <div className={styles.formGroup}>
        <label htmlFor="full_name">Full Name (Optional)</label>
        <input
          type="text"
          id="full_name"
          name="full_name"
          value={formData.full_name}
          onChange={handleChange}
          placeholder="Enter full name"
          disabled={loading}
        />
      </div>

      <button type="submit" disabled={loading} className={styles.button}>
        {loading ? 'Processing...' : user ? 'Update User' : 'Create User'}
      </button>
    </form>
  );
}
