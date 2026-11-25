---
title: "How to Upgrade (and Set Up) authentik on Docker Compose Without Breaking Outposts"
date: 2026-11-15
description: "A repeatable upgrade routine for self-hosted authentik: back up Postgres, bump the tag, and fix the outposts that quietly stay on the old version."
tags: [homelab, authentik, docker, sso]
---

authentik upgrades are usually painless, until an LDAP or proxy outpost keeps running the old image and your NAS logins or forward-auth apps start acting strange. This is the routine I use for a Docker Compose install behind Traefik, plus a from-scratch setup at the end.

## Gotchas to know first

- `sudo cmd > file` fails in root-owned directories, because the redirect runs as your user. Write backups to `~/` (or pipe to `sudo tee`).
- Keep backups **outside** the stack directory.
- Outposts on the **Local Docker connection** don't reliably redeploy after a server upgrade.
- `docker stop` then `docker start` does nothing useful: the container comes back on the same old image. It has to be **removed** so authentik recreates it.
- The compose file is now `compose.yml` (it was `docker-compose.yml` before 2026.2). Diff before overwriting so you don't lose custom Traefik labels.
- `AUTHENTIK_POSTGRESQL__CONN_OPTIONS` is deprecated; remove it from `.env`.
- 2026.8 rewrote the proxy outpost, so re-test any forward-auth apps after major upgrades.

## Upgrading

Move one release family at a time. Patch bumps are routine; read the [release notes](https://docs.goauthentik.io/releases/) before major bumps.

```bash
cd /opt/stacks/authentik

# 1. Back up the database
sudo docker compose exec postgresql pg_dumpall -c -U ${PG_USER:-authentik} > ~/authentik_backup_$(date +%Y%m%d).sql

# 2. (Major bumps only) fetch the new compose file, diff it, reapply your labels
wget -O compose.new.yml https://goauthentik.io/version/<YYYY.M>/lifecycle/container/compose.yml
diff compose.yml compose.new.yml

# 3. Bump the tag in .env
#    AUTHENTIK_TAG=<new version>

# 4. Pull and restart
sudo docker compose pull
sudo docker compose up -d

# 5. Watch the migrations finish
sudo docker compose logs -f worker
```

## Fixing outpost version drift

**Applications → Outposts** flags any outpost that doesn't match the server version.

```bash
# find the outpost containers
sudo docker ps --format '{{.Names}}\t{{.Image}}' | grep -i outpost

# remove (don't just stop) so authentik recreates it on the new image
sudo docker rm -f ak-outpost-ldap-outpost

# wait about a minute, then confirm the new tag
sudo docker ps --format '{{.Names}}\t{{.Image}}' | grep -i outpost
```

If it doesn't come back, or comes back on the old tag:

1. **Applications → Outposts →** edit the outpost and click **Update** to force a reconcile.
2. **Admin → Integrations →** open the **Local Docker connection** and run its test/refresh.
3. Run the `docker rm -f` again.
4. Confirm the server containers themselves are on the new tag (`docker ps | grep authentik`).

## Post-upgrade checklist

- [ ] **Admin → Dashboards → Overview** shows the new version
- [ ] All outposts are Healthy with no version warning
- [ ] Apps behind forward-auth load through their normal URLs
- [ ] LDAP logins (for example from a NAS) still work

## Setting up from scratch

```bash
sudo mkdir -p /opt/stacks/authentik && cd /opt/stacks/authentik

# Official compose file for the release you want
sudo wget -O compose.yml https://goauthentik.io/version/<YYYY.M>/lifecycle/container/compose.yml

# Secrets and version pin
echo "PG_PASS=$(openssl rand -base64 36 | tr -d '\n')" | sudo tee -a .env
echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')" | sudo tee -a .env
echo "AUTHENTIK_TAG=<version>" | sudo tee -a .env

sudo docker compose pull
sudo docker compose up -d
```

1. Open `http://<host>:9000/if/flow/initial-setup/` and set the `akadmin` password.
2. Add your Traefik router labels to the `server` service and attach it to the Traefik network.
3. Leave the Docker socket mount on the worker intact. The Local Docker connection needs it to spawn outposts.

### LDAP outpost (for a NAS or other LDAP client)

1. Create an **LDAP provider** and an application for it.
2. **Applications → Outposts → Create:** type **LDAP**, integration **Local Docker connection**, and attach the application.
3. authentik spawns an `ak-outpost-...` container. Check it with `docker ps`.
4. Point your NAS at the host's LDAP port using the bind DN and base DN shown on the provider.

### Proxy outposts (forward-auth apps)

Create a **Proxy provider** per app, add each to a proxy outpost on the Local Docker connection, and keep your Traefik router labels in step with the forward-auth middleware.

## Backup and restore

```bash
# backup
sudo docker compose exec postgresql pg_dumpall -c -U ${PG_USER:-authentik} > ~/authentik_backup_$(date +%Y%m%d).sql

# restore (stack running, fresh database)
cat ~/authentik_backup_YYYYMMDD.sql | sudo docker compose exec -T postgresql psql -U ${PG_USER:-authentik} postgres
```

If migrations fail during an upgrade, restore the backup and pin the old tag rather than pushing forward.
