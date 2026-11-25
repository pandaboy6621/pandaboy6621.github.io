---
title: "How to Fix \"All Predefined Address Pools Have Been Fully Subnetted\" in Docker"
date: 2026-10-21
description: "Too many Compose stacks and Docker runs out of networks. Here's how to give it a bigger address pool, with notes for NAS boxes like ASUSTOR that don't use systemd."
tags: [docker, networking, nas, homelab]
---

You run `docker compose up` on a new stack and get this:

```
failed to create network file-browser_default: Error response from daemon:
all predefined address pools have been fully subnetted
```

Every Compose project gets its own bridge network, and Docker's default pools (`172.17-31.0.0/16` plus some `192.168.x.x` blocks) only stretch so far. Once you have a few dozen stacks, you run out.

I hit this on an ASUSTOR NAS running Docker CE from App Central, which has some quirks: no systemd, a BusyBox shell, and `sudo` needed for every Docker command. The fix works on any Linux host; only the restart step differs.

## Step 1: Define a bigger address pool

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<'EOF'
{
  "default-address-pools": [
    {"base": "10.200.0.0/16", "size": 24}
  ]
}
EOF
```

That gives you 256 networks of `/24` each. Pick a base that doesn't overlap your LAN, VPNs or any other route. Check with `ip route`.

> If you already have a `daemon.json`, merge the key in rather than overwriting the file.

## Step 2: Restart Docker

On a normal Linux host:

```bash
sudo systemctl restart docker
```

On ASUSTOR ADM, use the App Central control script (or toggle Docker CE off and on in App Central):

```bash
sudo /usr/local/AppCentral/docker-ce/CONTROL/start-stop.sh stop
sudo /usr/local/AppCentral/docker-ce/CONTROL/start-stop.sh start
```

Either way this **restarts every container**, so pick a quiet moment. On ADM you'll see harmless noise like `can't unmount docker_lib` or `rpcbind already running`.

## Step 3: Check the new pool is live

```bash
ps | grep [d]ockerd          # the PID should be different from before
sudo docker network create test-net
sudo docker network inspect test-net | grep Subnet
sudo docker network rm test-net
```

You should see a `10.200.x.0/24` subnet.

## Step 4: Pin a subnet if the stack still fails

In my case the original stack *still* threw the pool error after the restart, even though manual `docker network create` worked. Pinning an explicit subnet in the compose file fixed it, because explicit subnets skip the pool allocator:

```yaml
networks:
  default:
    ipam:
      config:
        - subnet: 10.201.0.0/24
```

Choose a range that isn't already in use (`sudo docker network ls`, `ip route`) and sits outside your new pool. `10.201.x` is outside `10.200.0.0/16`.

## Other things that help

- `sudo docker network prune` removes networks with no containers attached. It clears leftovers from stacks you stopped using.
- Existing networks keep their old `172.x` subnets. Only new networks come from the new pool.
- After a daemon restart, apps with dependencies (a database, Redis) may restart-loop briefly until those are healthy. Give it a minute before you panic.

## NAS caveats (ASUSTOR ADM)

- `/etc/docker/daemon.json` may not survive a reboot or a Docker CE package update. Check it with `cat /etc/docker/daemon.json` afterwards. If it's gone, recreate it, or add `--default-address-pool base=10.200.0.0/16,size=24` to the dockerd line in `start-stop.sh` (updates can overwrite that too).
- dockerd on ADM runs with `--iptables=false`, so Docker isn't managing NAT rules for bridge networks. That's unrelated to this error but worth knowing if a container can't reach out.

## Quick reference

| Task | Command |
|---|---|
| List Compose projects and paths | `sudo docker compose ls -a` |
| List networks | `sudo docker network ls` |
| Show every network's subnet | `sudo docker network inspect $(sudo docker network ls -q) \| grep -E '"Name"\|Subnet'` |
| Show host routes | `ip route` |
| Prune unused networks | `sudo docker network prune` |
