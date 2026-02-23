# PERFORMANCE_TUNING.md
# Database Configuration & Performance Guide

---

## Performance Baseline Testing

Run `db_performance_baseline.sh` to measure database performance with INSERT/SELECT/UPDATE operations:

```bash
sudo ./db_performance_baseline.sh
# Runs 1000 iterations per operation (adjustable with -n/--iterations)
# Results saved to: db_performance_baseline.txt
```

**Key metrics measured:**
- INSERT operations (queries/second)
- SELECT operations (queries/second)
- UPDATE operations (queries/second)
- Average operation time (milliseconds)

Run after configuration changes to verify performance improvement.

---

## PostgreSQL 15 (8GB RAM Server)

| Parameter               | Value   | Reason                                   |
|-------------------------|---------|------------------------------------------|
| `shared_buffers`        | 256MB   | ~25% of RAM for buffer cache             |
| `effective_cache_size`  | 1GB     | Planner hint for available OS cache      |
| `work_mem`              | 16MB    | Per sort/hash operation (100 connections)|
| `maintenance_work_mem`  | 128MB   | VACUUM, CREATE INDEX operations          |
| `max_connections`       | 100     | Use PgBouncer for higher concurrency     |
| `wal_buffers`           | 16MB    | Write-ahead log buffer                   |
| `checkpoint_completion_target` | 0.9 | Spreads checkpoint I/O             |
| `random_page_cost`      | 1.1     | Tuned for SSD storage                   |

**Key recommendations:**
- Enable `pg_stat_statements` for query analysis
- Use connection pooling (PgBouncer) if connections exceed 100
- Run `ANALYZE` after bulk imports
- Index foreign keys and frequently filtered columns

---

## MySQL 8.0 (8GB RAM Server)

| Parameter                   | Value | Reason                             |
|-----------------------------|-------|------------------------------------|
| `innodb_buffer_pool_size`   | 512MB | Main InnoDB cache (~60-70% of RAM) |
| `innodb_buffer_pool_instances` | 4  | Reduces contention on pool         |
| `innodb_log_file_size`      | 128MB | Larger = fewer checkpoints         |
| `innodb_flush_method`       | O_DIRECT | Avoids double buffering         |
| `innodb_flush_log_at_trx_commit` | 1 | Full ACID compliance           |
| `max_connections`           | 150   | Monitor with `Threads_connected`   |
| `query_cache_size`          | 0     | Disabled — deprecated in MySQL 8   |

**Key recommendations:**
- Monitor slow query log (`/var/log/mysql/slow.log`, threshold: 2s)
- Use `EXPLAIN ANALYZE` on slow queries
- Ensure all tables use InnoDB (`innodb_file_per_table = 1`)
- Binary logging enabled for point-in-time recovery

---

## MongoDB 7.0 (8GB RAM Server)

| Parameter                      | Value  | Reason                            |
|--------------------------------|--------|-----------------------------------|
| `wiredTiger.cacheSizeGB`       | 1GB    | WiredTiger internal cache         |
| `maxIncomingConnections`       | 200    | Network connection limit          |
| `journalCompressor`            | snappy | Fast compression for journal      |
| `blockCompressor`              | snappy | Collection data compression       |
| `slowOpThresholdMs`            | 100ms  | Profiler captures slow operations |

**Key recommendations:**
- Always index fields used in `find()` filters
- Use `explain("executionStats")` to inspect query plans
- Monitor with `db.serverStatus()` and `db.stats()`
- Prefer compound indexes over multiple single-field indexes

---

## Running the Performance Baseline
```bash
sudo ./db_performance_baseline.sh
# Results saved to: db_performance_baseline.txt
```
Re-run after configuration changes to measure improvement.
