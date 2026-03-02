# Zero-Downtime Deployment Guide

## Strategy: Blue-Green Deployment

Zero-downtime deployment uses a Blue-Green strategy where a new version (Green) is deployed alongside the existing version (Blue). Traffic is switched only after the Green version passes all health checks.

---

## How It Works

```
Phase 1: Deploy Green          Phase 2: Switch Traffic       Phase 3: Decommission
┌──────────────┐              ┌──────────────┐              ┌──────────────┐
│   Nginx LB   │──→ Blue      │   Nginx LB   │──→ Green     │   Nginx LB   │──→ Green
│              │              │              │              │              │
│  Blue (live) │              │  Blue (idle) │              │              │
│  Green (new) │ health check │  Green (live)│ monitor 5min │  Green (live)│
└──────────────┘              └──────────────┘              └──────────────┘
```

### Port Mapping

| Stack | Component | Blue (Original) | Green (+10 Offset) |
|-------|-----------|-----------------|---------------------|
| 1 | Express.js | 3000, 3003, 3004 | 3010, 3013, 3014 |
| 1 | Next.js | 3001, 3002 | 3011, 3012 |
| 2 | Laravel | 8000, 8001, 8002 | 8010, 8011, 8012 |
| 3 | FastAPI | 8003, 8004, 8005 | 8013, 8014, 8015 |
| 3 | Next.js | 3005, 3006 | 3015, 3016 |

---

## Usage

```bash
# Deploy with zero downtime
sudo ./zero_downtime_deploy.sh --stack 1
sudo ./zero_downtime_deploy.sh --stack 2
sudo ./zero_downtime_deploy.sh --stack 3

# Dry run (preview only)
sudo ./zero_downtime_deploy.sh --stack 1 --dry-run
```

---

## Deployment Phases

### Phase 1: Pre-flight Checks
- Verify current (Blue) deployment is healthy
- Check system resources (disk, memory)
- Validate new code/configuration

### Phase 2: Deploy Green
- Start new application instances on offset ports
- Wait for processes to initialize (30s warmup)
- Run health checks on Green endpoints

### Phase 3: Switch Traffic
- Update Nginx upstream block to point to Green ports
- Reload Nginx (`nginx -s reload` — no dropped connections)
- Verify traffic is flowing to Green

### Phase 4: Monitor
- Watch Green for 5 minutes for errors
- Check error rates, response times, health endpoints
- Compare metrics against Blue baseline

### Phase 5: Finalize
- **If healthy:** Stop Blue instances, deployment complete
- **If issues:** Revert Nginx to Blue upstream, stop Green, rollback

---

## Rollback

Automatic rollback triggers:
- Green health check fails after switch
- Error rate exceeds 5% during monitoring window
- Manual `Ctrl+C` during monitoring phase

Manual rollback:
```bash
./rollback.sh --stack 1 --auto
```

---

## Nginx Upstream Switching

The script dynamically rewrites the upstream block:

**Before (Blue):**
```nginx
upstream stack1_express {
    server 127.0.0.1:3000;
    server 127.0.0.1:3003;
    server 127.0.0.1:3004;
}
```

**After (Green):**
```nginx
upstream stack1_express {
    server 127.0.0.1:3010;
    server 127.0.0.1:3013;
    server 127.0.0.1:3014;
}
```

Nginx is reloaded gracefully — existing connections complete on Blue while new connections go to Green.

---

## Best Practices

1. **Always test in staging first** — run `--dry-run` to preview changes
2. **Monitor the monitoring window** — don't walk away during the 5-minute check
3. **Keep Blue running** until Green is confirmed stable (at least 15 minutes)
4. **Database migrations** must be backward-compatible (both Blue and Green must work with the same schema)
5. **Feature flags** — use them for risky features so you can disable without redeployment
