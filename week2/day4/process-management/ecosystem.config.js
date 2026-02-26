// PM2 Ecosystem Configuration
// Author: Aakash
// Usage:
//   pm2 start ecosystem.config.js          # start all
//   pm2 start ecosystem.config.js --only express-api
//   pm2 reload ecosystem.config.js         # zero-downtime reload
//   pm2 save && pm2 startup                # persist across reboots

module.exports = {
  apps: [
    // Express PostgreSQL API 
    {
      name: 'express-api',
      script: './server.js',
      instances: 4,
      exec_mode: 'cluster',
      cwd: './express-postgresql-api',
      watch: false,
      env: {
        NODE_ENV: 'development',
        PORT: 3000,
        DB_HOST: 'localhost',
        DB_PORT: 5432,
        DB_NAME: 'apidb',
        DB_USER: 'apiuser',
        DB_PASSWORD: 'Api@123',
        LOG_DIR: './var/log/apps',
        APP_VERSION: '1.0.0',
      },
      env_production: {
        NODE_ENV: 'production',
        PORT: 3000,
        DB_HOST: 'localhost',
        DB_PORT: 5432,
        DB_NAME: 'apidb',
        DB_USER: 'apiuser',
        DB_PASSWORD: 'Api@123',
        LOG_DIR: './var/log/apps',
      },
      error_file: './var/log/apps/express-api-pm2-error.log',
      out_file: './var/log/apps/express-api-pm2-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss',
      max_memory_restart: '500M',
      min_uptime: '10s',
      max_restarts: 10,
      restart_delay: 4000,
      kill_timeout: 5000,
      listen_timeout: 8000,
      autorestart: true,
    },

    // Next.js Fullstack App 
    {
      name: 'nextjs-app',
      script: './node_modules/next/dist/bin/next',
      args: 'start',
      cwd: '/home/aakash/Desktop/DevOpsBootcamp/week2/day4/nextjs-fullstack-app',
      instances: 2,
      exec_mode: 'cluster',
      watch: false,
      env: {
        NODE_ENV: 'development',
        PORT: 3001,
        DB_HOST: 'localhost', 
        DB_PORT: 5432,
        DB_NAME: 'apidb',
        DB_USER: 'apiuser',
        DB_PASSWORD: 'Api@123',
      },
      env_production: {
        NODE_ENV: 'production',
        PORT: 3001,
        DB_HOST: 'localhost', 
        DB_PORT: 5432,
        DB_NAME: 'apidb',
        DB_USER: 'apiuser',
        DB_PASSWORD: 'Api@123',
      },
      error_file: './var/log/apps/nextjs-pm2-error.log',
      out_file: './var/log/apps/nextjs-pm2-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss',
      max_memory_restart: '500M',
      min_uptime: '10s',
      max_restarts: 10,
      restart_delay: 4000,
      kill_timeout: 5000,
      autorestart: true,
    },
  ],
};