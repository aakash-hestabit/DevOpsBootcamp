// File: pm2/nextjs-ecosystem.config.js
// Description: PM2 configuration for Next.js frontend instances (Stack 3)
// Ports: 3005, 3006 with ISR (Incremental Static Regeneration) enabled

const BASE = '/home/aakash/Desktop/DevOpsBootcamp/week2/day5/stack3_next_fastapi_mysql';

module.exports = {
  apps: [
    // Next.js Frontend Instance 1 - Port 3005
    {
      name: 'nextjs-3005',
      script: 'node_modules/next/dist/bin/next',
      args: 'start -p 3005',
      cwd: `${BASE}/frontend`,
      instances: 1,
      exec_mode: 'fork',
      env: {
        NODE_ENV: 'production',
        PORT: 3005,
        NEXT_PUBLIC_API_URL: 'https://stack3.devops.local',
      },
      error_file: `${BASE}/var/log/apps/nextjs-3005-error.log`,
      out_file: `${BASE}/var/log/apps/nextjs-3005-out.log`,
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      watch: false,
      kill_timeout: 5000,
    },

    // Next.js Frontend Instance 2 - Port 3006
    {
      name: 'nextjs-3006',
      script: 'node_modules/next/dist/bin/next',
      args: 'start -p 3006',
      cwd: `${BASE}/frontend`,
      instances: 1,
      exec_mode: 'fork',
      env: {
        NODE_ENV: 'production',
        PORT: 3006,
        NEXT_PUBLIC_API_URL: 'https://stack3.devops.local',
      },
      error_file: `${BASE}/var/log/apps/nextjs-3006-error.log`,
      out_file: `${BASE}/var/log/apps/nextjs-3006-out.log`,
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      watch: false,
      kill_timeout: 5000,
    },
  ],
};
