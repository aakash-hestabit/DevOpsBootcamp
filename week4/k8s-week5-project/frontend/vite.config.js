import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  root: path.resolve(__dirname, '.'),
  server: {
    port: 3000,
    host: '0.0.0.0',
    strictPort: false,
  },
  build: {
    target: 'esnext',
    minify: 'terser',
    sourcemap: false,
    outDir: 'dist',
    assetsDir: 'static',
  },
  preview: {
    port: 3000,
    host: '0.0.0.0',
  },
});
