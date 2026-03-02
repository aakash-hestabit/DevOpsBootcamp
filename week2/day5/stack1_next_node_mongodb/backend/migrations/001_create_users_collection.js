// Migration: 001_create_users_collection
// Description: Create the users collection with indexes in MongoDB
// Date: 2026-02-26
//
// Idempotent: safe to re-run on an existing collection.
// Any existing index on the same key with a different name is dropped and
// recreated so the canonical names (idx_users_*) are always present.
//
// Usage: MONGODB_URI=<uri> node 001_create_users_collection.js

'use strict';

const mongoose = require('mongoose');
// Dotenv is loaded as a best-effort fallback only; the deploy script always
// injects MONGODB_URI explicitly via the process environment.
require('dotenv').config({ path: require('path').resolve(__dirname, '../.env') });

const MONGODB_URI =
  process.env.MONGODB_URI ||
  'mongodb://devops:Devops%40123@localhost:27017,localhost:27018,localhost:27019/usersdb?replicaSet=rs0&authSource=admin&readPreference=primaryPreferred&retryWrites=true&w=majority';

/**
 * Ensure an index exists with the correct name.
 * If an index on the same key already exists with a different name,
 * drop it first so we can recreate it with the canonical name.
 */
async function ensureIndex(collection, keySpec, options) {
  const existing = await collection.indexes();
  const keyStr = JSON.stringify(keySpec);

  for (const idx of existing) {
    if (JSON.stringify(idx.key) === keyStr) {
      if (idx.name === options.name) {
        console.log(`Index already up-to-date: ${options.name}`);
        return; // already correct — nothing to do
      }
      // Same key, wrong name — drop the stale one
      console.log(`Dropping stale index "${idx.name}" (key: ${keyStr}) to recreate as "${options.name}"`);
      await collection.dropIndex(idx.name);
      break;
    }
  }

  await collection.createIndex(keySpec, options);
  console.log(`Index created: ${options.name}`);
}

async function migrate() {
  await mongoose.connect(MONGODB_URI);
  const db = mongoose.connection.db;

  // Create collection if it doesn't exist yet
  const collections = await db.listCollections({ name: 'users' }).toArray();
  if (collections.length === 0) {
    await db.createCollection('users');
    console.log('Created collection: users');
  } else {
    console.log('Collection already exists: users');
  }

  const usersCol = db.collection('users');

  await ensureIndex(usersCol, { username: 1 }, { unique: true, name: 'idx_users_username' });
  await ensureIndex(usersCol, { email: 1 },    { unique: true, name: 'idx_users_email' });
  await ensureIndex(usersCol, { created_at: 1 },              { name: 'idx_users_created_at' });

  console.log('Migration 001 complete.');
  await mongoose.disconnect();
}

migrate().catch((err) => {
  console.error('Migration failed:', err.message);
  process.exit(1);
});