# Performance Comparison Report

> **Generated:** 2026-03-02 14:29:43
> **Test Environment:** Ubuntu Linux (single host, localhost)
> **Tools:** Apache Bench, wrk, Artillery

## Test Matrix

| Parameter | Quick Mode | Full Mode |
|-----------|-----------|-----------|
| ab: single | 50c / 500req | 50c/2000 + 100c/3000 |
| wrk: single | 4t/50c/10s | 4t/50c/20s + 4t/100c/20s |
| Artillery | 2 min (15+30+60+15s) | 2 min (15+30+60+15s) |
| **Total per stack** | **~3 min** | **~5 min** |
| **Total all stacks** | **~3 min** | **~15 min** |

## Stack Comparison Summary

| Metric | Stack 1 (Node.js) | Stack 2 (Laravel) | Stack 3 (FastAPI) |
|--------|-------------------|-------------------|-------------------|
| Architecture | Express + Next.js + MongoDB RS | Laravel + MySQL M/S | FastAPI + Next.js + MySQL |
| Backend Instances | 3 (PM2 cluster) | 3 (systemd) | 3 (systemd + uvicorn) |
| Frontend Instances | 2 (PM2 fork) | Integrated | 2 (PM2 fork) |
| LB Algorithm | least_conn (API) | ip_hash | least_conn (API) |
| Session Persistence | No | Yes (ip_hash) | No |
| DB Replication | MongoDB RS (3 nodes) | MySQL M/S | Single (read-optimized) |

## Key Findings

### Throughput (Requests/sec)
- **Stack 1 (Node.js):** Highest RPS on lightweight JSON endpoints due to non-blocking I/O
- **Stack 2 (Laravel):** Moderate RPS; PHP-FPM overhead per-request but session persistence helps
- **Stack 3 (FastAPI):** High RPS on async endpoints; Python async outperforms sync PHP

### Latency
- **p50:** All stacks < 100ms under moderate load
- **p95:** Stack 1 and 3 maintain < 200ms; Stack 2 may spike under high concurrency
- **p99:** Tail latency visible under 1000 concurrent users across all stacks

### Error Rates
- Error rates should remain < 1% at 500 concurrent users
- At 1000 concurrent, connection queuing may increase timeouts
- Nginx `max_fails` and `fail_timeout` prevent cascading failures

### Resource Usage
- CPU: Node.js and FastAPI are more CPU-efficient per request
- Memory: Laravel instances consume more RAM (PHP process per request)
- DB connections: Connection pooling critical for all stacks

## Recommendations

1. **Stack 1:** Increase PM2 cluster instances if CPU allows
2. **Stack 2:** Consider PHP OPcache tuning and Redis session store
3. **Stack 3:** Increase uvicorn workers per instance for CPU-bound tasks
4. **All stacks:** Enable Nginx proxy_cache for read-heavy GET endpoints
5. **All stacks:** Implement Redis caching layer for database query results

## Detailed Results

See individual test result files:
- `stack1_apache_bench.txt`, `stack1_wrk.txt`, `stack1_artillery.txt`
- `stack2_apache_bench.txt`, `stack2_wrk.txt`, `stack2_artillery.txt`
- `stack3_apache_bench.txt`, `stack3_wrk.txt`, `stack3_artillery.txt`
