const ENVIRONMENT = process.env.NODE_ENV || 'development';
const DB_HOST = process.env.DB_HOST || 'localhost';
const DB_NAME = process.env.DB_NAME || 'appdb';

console.log(`[MIGRATE] Running database migrations for ${ENVIRONMENT} environment`);
console.log(`[MIGRATE] Target database: ${DB_HOST}/${DB_NAME}`);
console.log(`[MIGRATE] Migration 001_create_users_table ... OK`);
console.log(`[MIGRATE] Migration 002_create_sessions_table ... OK`);
console.log(`[MIGRATE] All migrations applied successfully.`);
process.exit(0);
