# PM2 Management Guide

## Why PM2?
PM2 keeps Node.js processes alive, clusters them across CPU cores (more throughput), and
restarts them automatically on crash. It also provides log aggregation and a monitoring dashboard.

---

## Installation
```bash
npm install -g pm2
```

## Starting Applications
```bash
# Start all apps from the ecosystem file
pm2 start process-management/ecosystem.config.js

# Start with production environment variables
pm2 start process-management/ecosystem.config.js --env production

# Start individual app
pm2 start process-management/ecosystem.config.js --only express-api
pm2 start process-management/ecosystem.config.js --only nextjs-app
```

## Status and Monitoring
```bash
pm2 list                    # list all processes and their status
pm2 show express-api        # detailed info for one app
pm2 monit                   # real-time CPU/memory dashboard
pm2 status                  # same as pm2 list
```

## Logs
```bash
pm2 logs                    # tail all logs
pm2 logs express-api        # tail one app's logs
pm2 logs --lines 200        # last 200 lines
pm2 flush                   # clear all log files
```

## Reload / Restart
```bash
pm2 reload express-api      # zero-downtime reload (cluster mode)
pm2 restart express-api     # hard restart
pm2 reload all              # reload all cluster apps with zero downtime
pm2 restart all
```

## Stop / Delete
```bash
pm2 stop express-api
pm2 stop all
pm2 delete express-api
pm2 delete all
```

## Auto-startup (persist across reboots)
```bash
pm2 startup                 # generates and prints the system-level startup command
# Run the printed sudo command, then:
pm2 save                    # saves current process list
pm2 resurrect               # manually restore saved list
```

## Scale Up/Down
```bash
pm2 scale express-api 8     # increase to 8 instances
pm2 scale express-api -2    # decrease by 2 instances
```

## Update Ecosystem and Reload
```bash
pm2 reload process-management/ecosystem.config.js --update-env
```

---

## Cluster Mode - Why?
Cluster mode forks the app N times (one per CPU core). Each fork is a separate OS process,
so they share the same port via Node's `cluster` module. If one instance crashes, only that
fork restarts, the others continue serving traffic. Use `pm2 reload` (not restart) for
zero-downtime deploys in cluster mode.