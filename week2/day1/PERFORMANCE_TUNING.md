# Runtime Performance Tuning Guide

## 1. Node.js (V8 Engine)
* Configured via the `NODE_OPTIONS` environment variable.

* **`--max-old-space-size=4096`**
    * Increases the Heap memory limit (Old Generation) to 4GB.
    * Prevents "Out of Memory" (OOM) crashes during memory-intensive tasks (e.g., heavy JSON processing).
    * The application can handle larger data sets but consumes more system RAM.
* **`--max-http-header-size=16384`**
    * Increases the allowed size of HTTP request headers to 16KB.
    * Prevents `431 Request Header Fields Too Large` errors when using large JWT tokens or complex cookies.

**Set in:** `/etc/environment` (Global) or `~/.bashrc` (User).

---

## 2. Python (CPython)
* Configured via system environment variables.

* **`PYTHONOPTIMIZE=1`**
    * Tells the interpreter to ignore `assert` statements and generate optimized bytecode.
    * Slightly reduces memory footprint and improves execution speed by skipping development-only checks.
* **`PYTHONUNBUFFERED=1`**
    * Forces the stdout and stderr streams to be unbuffered.
    * Essential for logging in PM2 or Docker; ensures logs are flushed to disk immediately so no data is lost during a crash.

**Set in:** `/etc/profile.d/python_tuning.sh` or `~/.bashrc`.

---

## 3. PHP 
* Configured via `php.ini` or modular `.ini` files in `conf.d/`.

* **`memory_limit = 256M`**
    * The maximum RAM a single script execution can consume.
    * Prevents complex framework processes (like Laravel migrations or Composer) from failing due to memory exhaustion.
* **`max_execution_time = 300`**
    * Sets a 5-minute timeout for script execution.
    * Allows longer-running background tasks to complete while preventing "zombie" processes from hanging indefinitely.
* **`opcache.enable = 1` & `opcache.memory_consumption = 128`**
    * Stores precompiled script bytecode in shared memory.
    * The **most critical** PHP optimization. Reduces CPU usage and response time by 2x-3x by removing the need to re-parse code on every request.

**Set in:** `/etc/php/X.Y/fpm/conf.d/99-performance.ini`.

---

## Summary of Scope & Independency

| Runtime | Persistence | Memory Scope | Refresh Method |
| :--- | :--- | :--- | :--- |
| **Node.js** | System Reboot / Relogin | **Independent** per process | `pm2 restart <app>` |
| **Python** | Shell Session / Relogin | **Independent** per process | `systemctl restart <app>` |
| **PHP** | Service Restart | **Shared** (OpCache) / **Indep.** (Limit) | `systemctl restart php-fpm` |

* Performance tuning values should be scaled based on our hardware. If we have 4 CPU cores and set Node's `--max-old-space-size=4096`, the app could potentially request **16GB of RAM** in cluster mode.