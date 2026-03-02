import type { Metadata } from 'next';
import Link from 'next/link';
import './globals.css';

export const metadata: Metadata = {
  title: 'Products Dashboard | Stack 3',
  description: 'Next.js frontend for FastAPI MySQL Products API',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen">
        {/* Navigation */}
        <nav className="sticky top-0 z-50 backdrop-blur-xl bg-white/80 border-b border-gray-200/50 shadow-sm">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div className="flex items-center justify-between h-16">
              <div className="flex items-center gap-4">
                <div className="flex flex-col">
                  <span className="font-bold text-lg bg-gradient-to-r from-indigo-600 to-purple-600 bg-clip-text text-transparent">
                    Stack 3 Dashboard
                  </span>
                  <span className="text-xs text-gray-500">Next.js • FastAPI • MySQL</span>
                </div>
              </div>
              <div className="flex items-center gap-8">
                <Link 
                  href="/" 
                  className="text-gray-600 hover:text-indigo-600 font-medium text-sm transition-colors duration-200 relative group"
                >
                  Home
                  <span className="absolute bottom-0 left-0 w-0 h-0.5 bg-gradient-to-r from-indigo-600 to-purple-600 group-hover:w-full transition-all duration-300"></span>
                </Link>
                <Link 
                  href="/products" 
                  className="text-gray-600 hover:text-indigo-600 font-medium text-sm transition-colors duration-200 relative group"
                >
                  Products
                  <span className="absolute bottom-0 left-0 w-0 h-0.5 bg-gradient-to-r from-indigo-600 to-purple-600 group-hover:w-full transition-all duration-300"></span>
                </Link>
                <a
                  href={`${process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8003'}/docs`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="px-4 py-2 rounded-lg bg-gradient-to-r from-indigo-600 to-purple-600 text-white text-sm font-medium hover:shadow-lg hover:shadow-indigo-500/30 transition-all duration-200"
                >
                  API Docs ↗
                </a>
              </div>
            </div>
          </div>
        </nav>

        {/* Main Content */}
        <main className="min-h-[calc(100vh-64px)] bg-gradient-to-br from-slate-50 via-blue-50 to-indigo-50">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
            {children}
          </div>
        </main>

        {/* Footer */}
        <footer className="bg-gray-900 text-gray-400 py-8 mt-16">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center text-sm">
            <p>Stack 3 Products Dashboard • Built with Next.js 15, FastAPI & MySQL</p>
          </div>
        </footer>
      </body>
    </html>
  );
}