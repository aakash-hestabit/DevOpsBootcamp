# Baseline Performance Report

**Date:** 2026-03-02  
**Environment:** Ubuntu 24.04 LTS, Dell Latitude 3450 (12-core Intel, 24GB RAM, 468GB SSD)  
**Tools:** Apache Bench (ab), curl  
**Conditions:** All 3 stacks running simultaneously, Nginx HTTPS reverse proxy (TLS 1.3)

---

## System Resources (At Test Time)

| Metric | Value |
|--------|-------|
| CPU | 12 cores (Intel) |
| RAM | 24 GB (13 GB used, 57%) |
| Load Average | 1.50, 1.42, 1.39 |
| Disk | 468 GB SSD (339 GB used, 77%) |
| Active Connections (pre-test) | ~237 ESTABLISHED |
| MongoDB Connections | 35 |
| MySQL Threads | 49 |

---

## Stack 1 — Next.js + Express.js + MongoDB

### Express.js API (`GET /api/health`)

| Concurrency | Total Requests | Duration | Requests/sec | Avg Latency | P50 | P95 | P99 | Errors |
|-------------|---------------|----------|-------------|-------------|-----|-----|-----|--------|
| 1 | 1000 | 2.1s | 476 | 2.1ms | 2ms | 4ms | 8ms | 0 |
| 10 | 5000 | 5.9s | 847 | 11.8ms | 10ms | 25ms | 45ms | 0 |
| 50 | 10000 | 13.5s | 741 | 67ms | 55ms | 150ms | 320ms | 0 |
| 100 | 10000 | 13.9s | 719 | 139ms | 120ms | 380ms | 520ms | 12 |

### Next.js SSR (`GET /`)

| Concurrency | Total Requests | Requests/sec | Avg Latency | P99 | Errors |
|-------------|---------------|-------------|-------------|-----|--------|
| 1 | 500 | 62 | 16ms | 35ms | 0 |
| 10 | 2000 | 178 | 56ms | 180ms | 0 |
| 50 | 5000 | 162 | 308ms | 1.1s | 3 |
| 100 | 5000 | 148 | 675ms | 1.8s | 25 |

### MongoDB

| Metric | Value |
|--------|-------|
| Active Connections | 15 |
| Replica Set Lag | 0ms |
| Opcounter (query/s) | ~50 at rest |

---

## Stack 2 — Laravel + MySQL

### Laravel API (`GET /api/health`)

| Concurrency | Total Requests | Requests/sec | Avg Latency | P99 | Errors |
|-------------|---------------|-------------|-------------|-----|--------|
| 1 | 1000 | 210 | 4.8ms | 12ms | 0 |
| 10 | 5000 | 418 | 24ms | 85ms | 0 |
| 50 | 10000 | 392 | 128ms | 520ms | 0 |
| 100 | 10000 | 378 | 264ms | 890ms | 18 |

### Laravel CRUD (`POST /api/items`)

| Concurrency | Total Requests | Requests/sec | Avg Latency | Errors |
|-------------|---------------|-------------|-------------|--------|
| 1 | 500 | 142 | 7ms | 0 |
| 10 | 2000 | 280 | 36ms | 0 |
| 50 | 5000 | 245 | 204ms | 5 |

### MySQL

| Metric | Master (3306) | Slave (3307) |
|--------|--------------|--------------|
| Threads Connected | 12 | 8 |
| Queries/sec | ~120 | ~40 (read) |
| Slave IO Running | — | Yes |
| Slave SQL Running | — | Yes |
| Seconds Behind Master | — | 0 |

---

## Stack 3 — FastAPI + Next.js + MySQL

### FastAPI (`GET /health`)

| Concurrency | Total Requests | Requests/sec | Avg Latency | P99 | Errors |
|-------------|---------------|-------------|-------------|-----|--------|
| 1 | 1000 | 580 | 1.7ms | 5ms | 0 |
| 10 | 5000 | 1180 | 8.5ms | 30ms | 0 |
| 50 | 10000 | 1020 | 49ms | 210ms | 0 |
| 100 | 10000 | 975 | 103ms | 385ms | 0 |

### FastAPI CRUD (`GET /api/items`)

| Concurrency | Total Requests | Requests/sec | Avg Latency | Errors |
|-------------|---------------|-------------|-------------|--------|
| 1 | 1000 | 320 | 3.1ms | 0 |
| 10 | 5000 | 645 | 15.5ms | 0 |
| 50 | 10000 | 580 | 86ms | 0 |

### Next.js SSR (`GET /`)

| Concurrency | Total Requests | Requests/sec | Avg Latency | Errors |
|-------------|---------------|-------------|-------------|--------|
| 10 | 2000 | 168 | 59ms | 0 |
| 50 | 5000 | 155 | 322ms | 2 |

---

## Key Observations

1. **FastAPI** has the highest throughput (~1180 rps) due to async I/O and lightweight Python framework
2. **Express.js** performs well in cluster mode (~847 rps with 3 workers)
3. **Laravel** is the slowest API (~418 rps) due to PHP process model overhead
4. **Next.js SSR** is the bottleneck across all stacks (~150-178 rps) — SSR is CPU-intensive
5. **Error rates** appear only at concurrency ≥100, mainly timeouts
6. **Database connections** remain stable under load, replication lag stays at 0
