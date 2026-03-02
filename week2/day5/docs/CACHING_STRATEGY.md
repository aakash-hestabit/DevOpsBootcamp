# Caching Strategy

## Architecture

Three-layer caching architecture across all stacks:

```
Client → [Browser Cache] → [Nginx Proxy Cache] → [Redis App Cache] → Application → Database
```

---

## Layer 1: Browser Cache

Static assets served with long cache headers:

```nginx
location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
}
```

| Asset Type | Cache Duration | Cache-Control |
|-----------|---------------|---------------|
| JS/CSS (hashed) | 1 year | `public, immutable` |
| Images | 1 year | `public, max-age=31536000` |
| HTML | no-cache | `no-cache, must-revalidate` |
| API responses | no-store | `no-store` |

---

## Layer 2: Nginx Proxy Cache

Nginx caches upstream responses to reduce backend load:

```nginx
proxy_cache_path /var/cache/nginx/main
    levels=1:2
    keys_zone=main_cache:10m
    max_size=1g
    inactive=60m;
```

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `keys_zone` | 10m (~80k keys) | Metadata storage |
| `max_size` | 1g | Disk cache limit |
| `inactive` | 60m | Evict after 1 hour unused |
| Cached routes | `GET /api/*` (200 only) | Cache successful reads |
| Bypass | `Cookie`, `Authorization` | Authenticated requests skip cache |

---

## Layer 3: Redis Application Cache

Redis provides shared application-level caching across all instances.

### Configuration

```
# /etc/redis/redis.conf
maxmemory 256mb
maxmemory-policy allkeys-lru
requirepass DevOpsRedis@123
appendonly yes
```

### Database Allocation

| DB | Stack | Purpose |
|----|-------|---------|
| 0 | Stack 1 | Express.js API cache |
| 1 | Stack 2 | Laravel cache + sessions |
| 2 | Stack 3 | FastAPI cache |
| 3 | Shared | Rate limiting, feature flags |

### Stack 1 — Express.js (Node.js)

**Cache middleware** wraps API endpoints:
```javascript
// GET /api/items → Check Redis → Hit: return cached → Miss: query DB → cache result
app.get('/api/items', cacheMiddleware(300), itemController.getAll);
```

| Key Pattern | TTL | Invalidation |
|------------|-----|-------------|
| `cache:items:list` | 300s | On POST/PUT/DELETE to `/api/items` |
| `cache:items:{id}` | 600s | On PUT/DELETE to `/api/items/{id}` |
| `cache:health` | 30s | Auto-expire |

### Stack 2 — Laravel (PHP)

**Cache driver:** Redis via `predis`
```php
// Automatic caching with Cache facade
$items = Cache::remember('items:all', 300, function () {
    return Item::paginate(20);
});
```

| Key Pattern | TTL | Invalidation |
|------------|-----|-------------|
| `laravel:items:*` | 300s | `Cache::tags(['items'])->flush()` on write |
| `laravel:config:*` | 86400s | `php artisan cache:clear` |
| `laravel:sessions:*` | 7200s | Auto-expire on logout |

### Stack 3 — FastAPI (Python)

**Async Redis decorator** with `aioredis`:
```python
@cached(ttl=300, prefix="items")
async def get_items(db: AsyncSession):
    return await db.execute(select(Item))
```

| Key Pattern | TTL | Invalidation |
|------------|-----|-------------|
| `fastapi:items:list` | 300s | Pattern-based `invalidate_pattern("items:*")` |
| `fastapi:items:{id}` | 600s | On update/delete |
| `fastapi:health` | 30s | Auto-expire |

---

## Cache Invalidation Strategy

### Write-Through
On any write operation (POST/PUT/DELETE), the cache entry is invalidated immediately:

```
Client → POST /api/items → Application → Write to DB → Delete Redis key → Return 201
```

### Pattern-Based Invalidation
When a single item changes, related list caches are also invalidated:
```
DELETE cache:items:list
DELETE cache:items:{id}
```

### TTL-Based Expiry
All cached entries have a TTL as a safety net — even if invalidation fails, stale data expires.

---

## Setup

```bash
# Install Redis and configure caching for all stacks
sudo ./caching_setup.sh

# Integration files for each stack
caching/cache_integration_nodejs.js    # Stack 1
caching/cache_integration_laravel.php  # Stack 2
caching/cache_integration_fastapi.py   # Stack 3
```

---

## Monitoring Cache Performance

```bash
# Redis CLI stats
redis-cli -a 'DevOpsRedis@123' INFO stats | grep -E "keyspace_hits|keyspace_misses"

# Calculate hit rate
# hit_rate = keyspace_hits / (keyspace_hits + keyspace_misses) * 100

# Memory usage
redis-cli -a 'DevOpsRedis@123' INFO memory | grep used_memory_human

# Key count per database
redis-cli -a 'DevOpsRedis@123' INFO keyspace
```

### Target Metrics

| Metric | Target | Action if Below |
|--------|--------|----------------|
| Hit rate | >85% | Increase TTL, cache more endpoints |
| Memory usage | <80% of maxmemory | Reduce TTL or increase maxmemory |
| Evictions/sec | <10 | Increase maxmemory |
| Latency (Redis) | <1ms | Check network, use unix socket |
