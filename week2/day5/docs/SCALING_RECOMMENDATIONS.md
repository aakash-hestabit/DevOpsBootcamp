# Scaling Recommendations

## Current Architecture

All 3 stacks run on a single server. This document outlines horizontal and vertical scaling strategies for production growth.

---

## Vertical Scaling (Scale Up)

### Immediate Gains (Single Server)

| Resource | Current | Recommended | Impact |
|----------|---------|-------------|--------|
| CPU Cores | Varies | 8+ cores | More PM2 cluster workers, MySQL threads |
| RAM | Varies | 16+ GB | Larger InnoDB buffer pool, MongoDB cache |
| Disk | HDD/SSD | NVMe SSD | 3-5x IOPS improvement for databases |
| Network | 1 Gbps | 10 Gbps | Eliminates bandwidth bottleneck |

### Process Scaling

| Component | Current Instances | Scale To | How |
|-----------|------------------|----------|-----|
| Express.js API | 3 (cluster) | CPU_COUNT | PM2 `instances: "max"` |
| Next.js SSR (S1) | 2 (fork) | 4 | Add ports 3003-3004 to PM2 + Nginx upstream |
| Laravel | 3 (systemd) | 5-6 | Add systemd units + Nginx upstream |
| Queue Workers | 2 | 4-8 | `systemctl start laravel-worker@{3,4,5,6}` |
| FastAPI | 3 (systemd) | 6 | Add systemd units on ports 8006-8008 |
| Next.js SSR (S3) | 2 (fork) | 4 | Add ports 3007-3008 to PM2 |

---

## Horizontal Scaling (Scale Out)

### Phase 1: Separate Database Tier

Move databases to dedicated servers:

```
[App Server]  ←→  [DB Server 1: MongoDB RS]
     ↕              [DB Server 2: MySQL M/S]
[Nginx LB]
```

**Benefits:** Isolated resource contention, independent scaling, better I/O.

### Phase 2: Multiple App Servers

```
                    ┌─ [App Server 1: Stack 1]
[Nginx LB] ────────┼─ [App Server 2: Stack 2]
                    └─ [App Server 3: Stack 3]
                    
[Shared: Redis, MongoDB RS, MySQL Cluster]
```

**Benefits:** Each stack gets dedicated CPU/RAM, independent deployments.

### Phase 3: Load Balancer Tier

```
[HAProxy/Nginx Plus]
    ├── [App Server 1a] ──┐
    ├── [App Server 1b] ──┤── [MongoDB RS]
    ├── [App Server 2a] ──┤── [MySQL Cluster]
    ├── [App Server 2b] ──┤── [Redis Cluster]
    ├── [App Server 3a] ──┘
    └── [App Server 3b]
```

---

## Database Scaling

### MongoDB (Stack 1)

| Strategy | When | How |
|----------|------|-----|
| Add secondaries | Read-heavy | Add nodes 4-5 to replica set |
| Sharding | >100GB data | Enable `sh.shardCollection()` |
| Read preference | High read load | `readPreference: "secondaryPreferred"` |

### MySQL (Stacks 2 & 3)

| Strategy | When | How |
|----------|------|-----|
| Read replicas | Read-heavy | Add slave nodes, route reads via ProxySQL |
| Connection pooling | >200 connections | Deploy ProxySQL or PgBouncer equivalent |
| Partitioning | Large tables | Range/hash partitioning on date columns |
| Galera Cluster | Write scaling | Multi-master synchronous replication |

---

## Caching Scaling

### Current: Single Redis Instance

### Scale Path:
1. **Redis Sentinel** — Automatic failover (3 Sentinel + 1 master + 2 replicas)
2. **Redis Cluster** — Horizontal sharding across 6+ nodes
3. **CDN Layer** — CloudFlare/Fastly for static assets and cacheable pages

### Cache Hit Rate Targets

| Layer | Target | Monitoring |
|-------|--------|-----------|
| Application (Redis) | >85% | `redis-cli INFO stats \| grep hit_rate` |
| Nginx proxy_cache | >60% | Check `X-Cache-Status` header |
| Browser cache | >90% | Set `Cache-Control: max-age=31536000` for assets |

---

## Application-Specific Recommendations

### Stack 1 (Node.js)
- Enable `NODE_CLUSTER` module for Express if PM2 cluster is insufficient
- Use WebSocket connection pooling (Socket.io with Redis adapter)
- Consider SSG (Static Site Generation) for pages that don't need real-time data

### Stack 2 (Laravel)
- Deploy Laravel Horizon for queue monitoring and auto-scaling workers
- Use `php artisan optimize` in production
- Consider Laravel Octane (Swoole/RoadRunner) for persistent process model — 5-10x throughput

### Stack 3 (FastAPI)
- Increase uvicorn workers: `workers = multiprocessing.cpu_count() * 2 + 1`
- Use `uvloop` and `httptools` for maximum async performance
- Consider connection pooling with `databases` library for MySQL

---

## Monitoring Thresholds for Scaling Triggers

| Metric | Warning | Scale Action |
|--------|---------|-------------|
| CPU sustained >70% | 5 min | Add app instances |
| Memory >80% | 10 min | Add RAM or move DBs |
| Response time P99 >2s | 5 min | Add instances + check queries |
| DB connections >80% max | Immediate | Add read replicas |
| Disk usage >85% | 24 hours | Expand storage |
| Error rate >1% | Immediate | Investigate + rollback |
| Queue backlog >1000 | 10 min | Scale queue workers |

---

## Cost-Effective Scaling Priority

1. **Redis caching** (free, 3-10x improvement)
2. **Application tuning** (free, 20-40% improvement)
3. **Sysctl + Nginx tuning** (free, 15-25% improvement)
4. **Vertical scaling** (moderate cost, immediate impact)
5. **Database separation** (infrastructure cost, eliminates contention)
6. **Horizontal app scaling** (significant cost, near-linear scaling)
