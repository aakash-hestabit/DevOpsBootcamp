/**
 * Redis Cache Integration for Stack 1 (Node.js Express API)
 *
 * File: caching/cache_integration_nodejs.js
 *
 * Install:
 *   cd stack1_next_node_mongodb/backend
 *   npm install redis
 *
 * Usage: Import this module in your Express routes to cache
 *        database query results and API responses.
 *
 * Redis DB: 0 (Stack 1 dedicated)
 */

const { createClient } = require('redis');

// ---------------------------------------------------------------------------
// Redis client singleton
// ---------------------------------------------------------------------------
let client = null;

async function getRedisClient() {
    if (client && client.isOpen) return client;

    client = createClient({
        url: process.env.REDIS_URL || 'redis://127.0.0.1:6379',
        password: process.env.REDIS_PASSWORD || 'DevOpsRedis@123',
        database: 0, // DB 0 for Stack 1
        socket: {
            reconnectStrategy: (retries) => Math.min(retries * 100, 5000),
        },
    });

    client.on('error', (err) => console.error('[Redis] Connection error:', err.message));
    client.on('connect', () => console.log('[Redis] Connected to 127.0.0.1:6379 (DB 0)'));

    await client.connect();
    return client;
}

// ---------------------------------------------------------------------------
// Cache middleware for Express routes
// ---------------------------------------------------------------------------
function cacheMiddleware(keyPrefix, ttlSeconds = 300) {
    return async (req, res, next) => {
        try {
            const redis = await getRedisClient();
            const cacheKey = `${keyPrefix}:${req.originalUrl}`;
            const cached = await redis.get(cacheKey);

            if (cached) {
                res.set('X-Cache', 'HIT');
                return res.json(JSON.parse(cached));
            }

            // Store original json method to intercept response
            const originalJson = res.json.bind(res);
            res.json = async (body) => {
                try {
                    await redis.setEx(cacheKey, ttlSeconds, JSON.stringify(body));
                } catch (err) {
                    console.error('[Redis] Cache write error:', err.message);
                }
                res.set('X-Cache', 'MISS');
                return originalJson(body);
            };

            next();
        } catch (err) {
            console.error('[Redis] Middleware error:', err.message);
            next(); // Proceed without cache on Redis failure
        }
    };
}

// ---------------------------------------------------------------------------
// Cache invalidation helpers
// ---------------------------------------------------------------------------
async function invalidateCache(pattern) {
    try {
        const redis = await getRedisClient();
        const keys = await redis.keys(pattern);
        if (keys.length > 0) {
            await redis.del(keys);
            console.log(`[Redis] Invalidated ${keys.length} keys matching: ${pattern}`);
        }
    } catch (err) {
        console.error('[Redis] Invalidation error:', err.message);
    }
}

async function invalidateUserCache() {
    await invalidateCache('stack1:users:*');
    await invalidateCache('stack1:api:/api/users*');
}

// ---------------------------------------------------------------------------
// Usage examples in Express routes:
//
// const { cacheMiddleware, invalidateUserCache } = require('./cache');
//
// // GET /api/users — cache for 5 minutes
// router.get('/users', cacheMiddleware('stack1:api', 300), async (req, res) => {
//     const users = await User.find();
//     res.json({ status: 'ok', data: users });
// });
//
// // POST /api/users — invalidate cache after create
// router.post('/users', async (req, res) => {
//     const user = await User.create(req.body);
//     await invalidateUserCache();
//     res.status(201).json({ status: 'ok', data: user });
// });
// ---------------------------------------------------------------------------

module.exports = {
    getRedisClient,
    cacheMiddleware,
    invalidateCache,
    invalidateUserCache,
};
