import Head from 'next/head';
import Link from 'next/link';
import styles from '../styles/Layout.module.css';

export default function Layout({ children, title = 'Next.js Fullstack App', description = 'A complete Next.js app with API routes' }) {
  return (
    <>
      <Head>
        <title>{title}</title>
        <meta name="description" content={description} />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
      </Head>

      <div className={styles.container}>
        <nav className={styles.navbar}>
          <div className={styles.navContent}>
            <Link href="/" className={styles.logo}>
                Next.js App
            </Link>
            <ul className={styles.navLinks}>
              <li>
                <Link href="/">Home</Link>
              </li>
              <li>
                <Link href="/users">Users</Link>
              </li>
            </ul>
          </div>
        </nav>

        <main className={styles.main}>
          {children}
        </main>

        <footer className={styles.footer}>
          <p>&copy; 2024 Next.js Fullstack App. All rights reserved.</p>
        </footer>
      </div>
    </>
  );
}
