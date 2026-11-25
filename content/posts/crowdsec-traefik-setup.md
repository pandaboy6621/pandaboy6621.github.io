---
title: "How to Protect Traefik Services with CrowdSec"
date: 2026-11-19
description: "Ban abusive IPs at the edge of your homelab by wiring CrowdSec into Traefik with the bouncer plugin, plus a self-updating allowlist so you never lock yourself out."
tags: [homelab, traefik, crowdsec, security, docker]
---

If you expose self-hosted apps to the internet through Traefik, you will see scanners and brute-force attempts within hours. CrowdSec reads Traefik's access log, spots attack patterns, and tells a Traefik plugin to return `403` to the offenders. This guide walks through the full setup with Docker Compose.

## How it fits together

```
Internet → Traefik (https entrypoint) → crowdsec@file middleware → app
              │                               │
              │ writes JSON access log        │ asks "is this IP banned?"
              ▼                               ▼
        ./traefik/logs  ──────────►  CrowdSec container (reads log, detects, decides)
```

1. **Traefik** writes a JSON access log.
2. **The CrowdSec engine** reads that log, matches attack scenarios, and creates ban decisions. It also pulls the community blocklist.
3. **The bouncer** is a Traefik plugin, not a separate container. It asks CrowdSec's local API whether an IP is banned and returns `403` if so.

> CrowdSec ignores private ranges (`10.x`, `172.16-31.x`, `192.168.x`) by default, so LAN traffic can't get banned.

The examples assume this layout. Adjust the paths to match yours.

| Item | Example location |
|---|---|
| Traefik stack | `/opt/stacks/traefik` |
| Traefik static config | `/opt/stacks/traefik/data/traefik.yml` |
| Traefik dynamic config | `/opt/stacks/traefik/data/config.yml` |
| CrowdSec stack | `/opt/stacks/crowdsec` |
| Shared Docker network | `proxy` (external) |
| HTTPS entrypoint name | `https` |

## Part 1: One-time setup

### Step 1: Turn on Traefik's access log

In `traefik.yml`:

```yaml
accessLog:
  filePath: /var/log/traefik/access.log
  format: json
  bufferingSize: 100
```

Add a logs volume to Traefik's `compose.yaml`:

```yaml
    volumes:
      - ./logs:/var/log/traefik
```

```bash
mkdir -p /opt/stacks/traefik/logs
```

### Step 2: Create the CrowdSec acquisition file

Create this **before** you start the container:

`/opt/stacks/crowdsec/acquis.yaml`

```yaml
filenames:
  - /var/log/traefik/access.log
labels:
  type: traefik
```

> **Bind-mount gotcha:** if a bind-mounted file doesn't exist when a container starts, Docker creates an empty *directory* in its place and the mount fails with "not a directory". To fix it: `docker compose down`, `sudo rm -rf` the bogus directory (check both the host path and inside `./crowdsec/config/`), create the real file, and start again.

### Step 3: Write the CrowdSec compose file

`/opt/stacks/crowdsec/compose.yaml`

```yaml
services:
  crowdsec:
    image: crowdsecurity/crowdsec:latest
    container_name: crowdsec
    restart: unless-stopped
    environment:
      COLLECTIONS: crowdsecurity/traefik crowdsecurity/http-cve crowdsecurity/base-http-scenarios
      GID: "1000"
    volumes:
      - ./crowdsec/config:/etc/crowdsec
      - ./crowdsec/data:/var/lib/crowdsec/data
      - ./acquis.yaml:/etc/crowdsec/acquis.yaml
      - /opt/stacks/traefik/logs:/var/log/traefik:ro
    networks:
      - proxy
networks:
  proxy:
    external: true
```

```bash
cd /opt/stacks/crowdsec
docker compose up -d
docker logs crowdsec --tail 50
docker exec crowdsec cscli metrics    # access.log should show lines read and parsed
```

### Step 4: Create a bouncer API key

```bash
docker exec crowdsec cscli bouncers add traefik-bouncer
```

The key is shown **once**. If you lose it, run `cscli bouncers delete traefik-bouncer` and add it again. Keep it out of screenshots, chats and git.

### Step 5: Declare the plugin in Traefik

In `traefik.yml`. Plugins download at startup, so Traefik needs outbound access to GitHub:

```yaml
experimental:
  plugins:
    crowdsec-bouncer:
      moduleName: github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin
      version: v1.8.2
```

### Step 6: Define the middleware

In `config.yml`, add it under the **existing** `http: → middlewares:` block:

```yaml
http:
  middlewares:
    crowdsec:
      plugin:
        crowdsec-bouncer:
          enabled: true
          crowdsecMode: live
          crowdsecLapiScheme: http
          crowdsecLapiHost: crowdsec:8080
          crowdsecLapiKey: "PASTE_KEY_HERE"
    # ...your other middlewares
```

> **Never add a second `middlewares:` key.** YAML rejects duplicate keys and Traefik then drops the *entire* file provider. The symptom is `middleware "default-headers@file" does not exist` on every router. Check with `grep -n '^  middlewares:' config.yml`; you want exactly one match.

### Step 7: Restart Traefik

```bash
cd /opt/stacks/traefik
docker compose up -d --force-recreate traefik
docker logs traefik --since 1m     # no ERR lines = good
```

> **Single-file mounts go stale.** If `config.yml` is mounted as a single file, editors and `sed -i` can replace the file's inode and the container keeps reading the old copy. Recreating the container (as above) avoids this.

### Step 8: Confirm the bouncer is talking to CrowdSec

```bash
docker exec crowdsec cscli bouncers list    # "Last API pull" should show a timestamp
```

## Part 2: Allowlist your own IP (even if it changes)

If your home connection has a dynamic IP that you already track with DDNS, a small script can mirror that IP into a CrowdSec allowlist so you can never ban yourself.

```bash
docker exec crowdsec cscli allowlists create home -d "home WAN IP"
```

`~/scripts/update-home-allowlist.sh`:

```bash
#!/bin/bash
# Keep the CrowdSec "home" allowlist in sync with your DDNS hostname
DDNS_HOST="home.example.com"
NEW=$(/usr/bin/dig +short A "$DDNS_HOST" @1.1.1.1 | tail -1)
STATE=$HOME/scripts/home-ip.txt
OLD=$(cat "$STATE" 2>/dev/null)

# bail out if the lookup failed or didn't return an IPv4 address
[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
[ "$NEW" = "$OLD" ] && exit 0

/usr/bin/docker exec crowdsec cscli allowlists add home "$NEW"
[ -n "$OLD" ] && /usr/bin/docker exec crowdsec cscli allowlists remove home "$OLD"
echo "$NEW" > "$STATE"
echo "$(date) home IP changed: ${OLD:-none} -> $NEW"
```

Run it every five minutes with `crontab -e`:

```
*/5 * * * * $HOME/scripts/update-home-allowlist.sh >> $HOME/scripts/allowlist-update.log 2>&1
```

Check it with `docker exec crowdsec cscli allowlists inspect home`.

## Part 3: Adding a new app

Each time you expose a new app at `app.example.com`:

1. **DNS:** point `app.example.com` at your WAN IP (an A record, or a CNAME to your DDNS name).
2. **Network:** put the container on the shared `proxy` network.
3. **Labels:** put `crowdsec@file` first in the router's middleware list:

```yaml
- traefik.http.routers.app.middlewares=crowdsec@file,default-headers@file
```

A few rules of thumb:

- **`crowdsec@file` always goes first**, so banned IPs are dropped before anything else runs, including SSO/forward-auth.
- File-provider middlewares need the `@file` suffix in labels.
- To hide admin paths from the internet, exclude them in the external rule, for example ``Host(`app.example.com`) && !PathPrefix(`/admin`)``.

Then test from **outside** your LAN (a phone on cellular works) and confirm the real client IP shows up in the log:

```bash
tail -n 3 /opt/stacks/traefik/logs/access.log | grep -o '"ClientHost":"[^"]*"'
```

## Optional: protect every service at once

Attach the middleware to the `https` entrypoint in `traefik.yml` (merge into your existing `entryPoints:` block):

```yaml
entryPoints:
  https:
    address: ":443"
    http:
      middlewares:
        - crowdsec@file
```

After this, the per-router entry is redundant but harmless.

## Test that blocking actually works

```bash
# 1. ban your phone's cellular IP for 10 minutes
docker exec crowdsec cscli decisions add --ip <PHONE-IP> --duration 10m

# 2. wait 60-90 seconds (live mode caches "not banned" results)
# 3. reload the site on cellular in a private tab; a blank page is a bare 403

# 4. confirm in the log
grep <PHONE-IP> /opt/stacks/traefik/logs/access.log | tail -3 | grep -o '"DownstreamStatus":[0-9]*'

# 5. clean up
docker exec crowdsec cscli decisions delete --ip <PHONE-IP>
```

> Never ban your router's LAN address. Traffic that loops back through the gateway can appear as that address, so banning it blocks everything that arrives that way.

## Day-to-day commands

```bash
docker exec crowdsec cscli metrics          # logs read/parsed, scenarios triggered
docker exec crowdsec cscli alerts list      # what got flagged, and why
docker exec crowdsec cscli decisions list   # active bans
docker exec crowdsec cscli decisions add --ip X --duration 4h
docker exec crowdsec cscli decisions delete --ip X
docker exec crowdsec cscli bouncers list    # bouncer health
docker exec crowdsec cscli hub update && docker exec crowdsec cscli hub upgrade
```

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Mount error "not a directory" for `acquis.yaml` | Docker created a directory. Remove it, create the real file, start again |
| `middleware "default-headers@file" does not exist` everywhere | Duplicate `middlewares:` key in `config.yml` |
| Edits to `config.yml` are ignored | Stale single-file mount; `docker compose up -d --force-recreate traefik` |
| `cscli metrics` shows 0 lines read | Traefik isn't writing the log, or the volume path is wrong |
| Bouncer has no "Last API pull" | Middleware isn't on a router that has seen traffic, or the containers aren't on the same network |
| Every request comes from a `172.x` address | The client IP is masked before Traefik; check port forwarding and Docker networking |
| Plugin error at startup | Version typo, or no outbound access to GitHub |
| Locked yourself out | `docker exec crowdsec cscli decisions delete --ip <your-ip>` and check the allowlist |

## Done checklist

- [ ] `cscli metrics` shows `access.log` lines read and parsed
- [ ] `cscli bouncers list` shows a recent "Last API pull"
- [ ] Public IPs appear in `ClientHost`
- [ ] The block test returns 403 on cellular
- [ ] The `home` allowlist holds your current IP and the cron job is installed
- [ ] `config.yml` has exactly one `middlewares:` key
