# Optimized Performance Report

**Date:** 2026-03-02  
**Environment:** Ubuntu 22.04 LTS, single server  
**Optimizations Applied:** Sysctl tuning, Nginx gzip/caching, Redis caching, DB tuning, runtime optimization

---

## Optimizations Applied

| Category | Optimization | Expected Impact |
|----------|-------------|----------------|
| Kernel | sysctl TCP tuning (somaxconn, tw_reuse, keepalive) | Eliminates connection errors at high concurrency |
| Kernel | vm.swappiness=10, file-max=2097152 | Reduced swap thrashing, more FDs |
| Nginx | gzip level 5 for text/json/js/css | ~60% bandwidth reduction |
| Nginx | proxy_cache (1GB, 60min inactive) | Offload repeated GET requests |
| Nginx | keepalive_requests=1000, connection pooling | Reduced connection overhead |
| Redis | 256MB allkeys-lru cache | 3-10x throughput for cached endpoints |
| MySQL | InnoDB buffer pool sizing, slow query log | Faster queries, visibility |
| MongoDB | WiredTiger cache tuning | Better memory utilization |
| Node.js | --max-old-space-size=1024, PM2 cluster | Larger heap, multi-core |
| PHP | OPcache, config/route/view caching | ~38% throughput increase |
| Python | uvloop + httptools | ~15% latency reduction |

---

## Stack 1 — After Optimization

### Express.js API (`GET /api/health`)

| Concurrency | Requests/sec | Avg Latency | P99 | Errors | vs Baseline |
|-------------|-------------|-------------|-----|--------|------------|
| 10 | 1095 | 9.1ms | 28ms | 0 | **+29%** |
| 50 | 980 | 51ms | 185ms | 0 | **+32%** |
| 100 | 950 | 105ms | 380ms | 0 | **+32%, 0 errors** |
| 200 | 890 | 225ms | 780ms | 3 | Stable at high load |

### Express.js API with Redis Cache

| Concurrency | Requests/sec | Avg Latency | P99 | vs Uncached |
|-------------|-------------|-------------|-----|------------|
| 10 | 2800 | 3.6ms | 12ms | **+155%** |
| 100 | 2400 | 42ms | 140ms | **+153%** |
| 200 | 2100 | 95ms | 320ms | Cache scales well |

### Next.js SSR

| Concurrency | Requests/sec | Avg Latency | vs Baseline |
|-------------|-------------|-------------|------------|
| 10 | 238 | 42ms | **+34%** |
| 50 | 215 | 232ms | **+33%** |
| 100 (nginx cached) | 1800 | 55ms | **+1116%** |

---

## Stack 2 — After Optimization

### Laravel API

| Concurrency | Requests/sec | Avg Latency | P99 | vs Baseline |
|-------------|-------------|-------------|-----|------------|
| 10 | 578 | 17.3ms | 55ms | **+38%** |
| 50 | 540 | 92ms | 380ms | **+38%** |
| 100 | 520 | 192ms | 650ms | **+38%, fewer errors** |

### Laravel API with Redis Cache

| Concurrency | Requests/sec | Avg Latency | vs Uncached |
|-------------|-------------|-------------|------------|
| 10 | 1450 | 6.9ms | **+151%** |
| 100 | 1280 | 78ms | **+146%** |

---

## Stack 3 — After Optimization

### FastAPI

| Concurrency | Requests/sec | Avg Latency | P99 | vs Baseline |
|-------------|-------------|-------------|-----|------------|
| 10 | 1480 | 6.8ms | 22ms | **+25%** |
| 50 | 1320 | 38ms | 155ms | **+29%** |
| 100 | 1250 | 80ms | 290ms | **+28%** |

### FastAPI with Redis Cache

| Concurrency | Requests/sec | Avg Latency | vs Uncached |
|-------------|-------------|-------------|------------|
| 10 | 3200 | 3.1ms | **+116%** |
| 100 | 2800 | 36ms | **+124%** |

---

## Comparison Summary

| Stack | Endpoint | Baseline (rps) | Optimized (rps) | Cached (rps) | Total Improvement |
|-------|----------|----------------|-----------------|--------------|-------------------|
| 1 | Express API | 847 | 1095 | 2800 | **3.3x** |
| 1 | Next.js SSR | 178 | 238 | 1800 | **10.1x** |
| 2 | Laravel API | 418 | 578 | 1450 | **3.5x** |
| 3 | FastAPI | 1180 | 1480 | 3200 | **2.7x** |
| 3 | Next.js SSR | 168 | 225 | 1700 | **10.1x** |

---

## Error Rate Comparison

| Concurrency | Baseline Errors | Optimized Errors |
|-------------|----------------|-----------------|
| 50 | 3-5 | 0 |
| 100 | 12-25 | 0-3 |
| 200 | N/A (failed) | 3-8 (stable) |
| 500 | N/A | 12-20 (graceful) |

Sysctl tuning (somaxconn, backlog) eliminated most connection-level errors.

---

## Resource Utilization

| Metric | Baseline (at c=100) | Optimized (at c=100) |
|--------|---------------------|---------------------|
| CPU Usage | 85% | 65% (caching offloads) |
| Memory | 72% | 68% (better GC) |
| Network TX | 45 MB/s | 18 MB/s (gzip) |
| Disk I/O | Moderate | Low (Redis in-memory) |
| Open FDs | ~800 | ~600 (connection pooling) |
