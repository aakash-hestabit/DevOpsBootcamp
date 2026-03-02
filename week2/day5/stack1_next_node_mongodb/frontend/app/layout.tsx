import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Users Dashboard | Stack 1',
  description: 'Next.js frontend for Express MongoDB API',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-gray-50">
        <nav className="bg-gray-900 text-white px-6 py-4 flex items-center gap-6">
          <span className="font-bold text-lg">Stack 1</span>
          <span className="text-gray-400 text-sm">Next.js + Express + MongoDB</span>
          <div className="ml-auto flex gap-4 text-sm">
            <a href="/" className="hover:text-gray-300 transition-colors">Home</a>
            <a href="/users" className="hover:text-gray-300 transition-colors">Users</a>
            <a
              href={`${process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3000'}/api-docs`}
              target="_blank"
              rel="noopener noreferrer"
              className="hover:text-gray-300 transition-colors"
            >
              API Docs ↗
            </a>
          </div>
        </nav>
        <main className="max-w-5xl mx-auto px-4 py-8">{children}</main>
      </body>
    </html>
  );
}