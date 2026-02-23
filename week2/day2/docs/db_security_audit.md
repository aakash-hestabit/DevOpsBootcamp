# db_security_audit.md
# Database Security Configuration Review

---

## PostgreSQL 15

| Check                        | Status | Notes                                      |
|------------------------------|--------|--------------------------------------------|
| Authentication method        | PASS | SCRAM-SHA-256 (strongest available)        |
| Remote root access disabled  | PASS | Only local and 127.0.0.1 allowed          |
| pg_hba.conf override         | PASS | Via `conf.d` include model                |
| Superuser is named role      | PASS | `dbadmin` — not `postgres`               |
| Password set on all roles    | PASS | Enforced at creation                      |
| WAL logging enabled          | PASS | `wal_level = replica`                     |
| Logging of DDL statements    | PASS | `log_min_duration_statement = 1000ms`     |

**Recommendations:**
- Rotate `dbadmin` password every 90 days
- Restrict `pg_hba.conf` to specific application IP ranges in production
- Enable `ssl = on` for network connections (`hostssl` entries in pg_hba.conf)
- Audit superuser access with `pg_stat_activity`

---

## MySQL 8.0

| Check                        | Status | Notes                                      |
|------------------------------|--------|--------------------------------------------|
| Root password set            | PASS | `mysql_native_password` auth              |
| Anonymous users removed      | PASS | Removed during secure setup               |
| Remote root login disabled   | PASS | Root only allowed from localhost          |
| Test database removed        | PASS | Dropped during secure setup               |
| App user has least privilege | PASS | DML + DDL on appdb only                  |
| Binary logging enabled       | PASS | For audit trail and recovery              |
| Slow query log enabled       | PASS | 2s threshold, helps detect anomalies      |
| `skip_name_resolve`          | PASS | Prevents DNS-based auth attacks           |

**Recommendations:**
- Use `mysql_ssl_rsa_setup` to enable TLS connections
- Rotate `appuser` password every 90 days
- Consider `REQUIRE SSL` on user accounts for network access
- Review `mysql.user` table quarterly: `SELECT User, Host FROM mysql.user;`

---

## MongoDB 7.0

| Check                        | Status | Notes                                      |
|------------------------------|--------|--------------------------------------------|
| Authentication enabled       | PASS | `security.authorization: enabled`         |
| Bound to localhost only      | PASS | `bindIp: 127.0.0.1`                       |
| Admin user created           | PASS | `mongoadmin` with scoped roles            |
| App user has least privilege | PASS | `readWrite` on appdb only                |
| Operation profiling enabled  | PASS | Slow ops > 100ms logged                  |
| WiredTiger journal enabled   | PASS | Crash recovery guaranteed                |

**Recommendations:**
- Enable TLS in `net.tls` section for non-localhost access
- Rotate credentials every 90 days
- Audit user access quarterly: `db.system.users.find()`
- For multi-server: configure keyFile or x.509 for replica auth

---

## General Best Practices Applied

- All passwords use strong complexity (uppercase, lowercase, numbers, symbols)
- All databases listen on localhost only (`127.0.0.1`)
- Logs retained and rotated to prevent disk exhaustion
- Binary/WAL logs enabled for point-in-time recovery capability
- Least privilege enforced: application users cannot access other databases
