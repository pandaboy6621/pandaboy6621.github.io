---
title: "How to Run Phantom on a GL.iNet Router So Remote Minecraft Bedrock Servers Show Up as LAN Games"
date: 2026-11-08
description: "Consoles can't add custom Bedrock servers easily, but they can see LAN games. Run Phantom as a procd service on an OpenWrt-based GL.iNet router and a remote server appears on every device at home."
tags: [minecraft, glinet, openwrt, networking, homelab]
---

Minecraft Bedrock on consoles makes it awkward to join custom servers, but every client will happily join a game listed under **LAN Games**. [Phantom](https://github.com/jhead/phantom) is a small proxy that makes a remote Bedrock server appear on your local network. Running it on your router means it's always on and starts on boot, with no PC left running.

GL.iNet routers run OpenWrt underneath, so this works on most OpenWrt devices too.

## Step 1: Get a shell on the router

1. Open the router's admin panel, go to **Applications → Plugins**, and install `nano` (optional, but easier than `vi`).
2. SSH in. The password is the same as the admin panel password:

```bash
ssh root@<router-ip>
```

## Step 2: Put the Phantom binary on the router

1. Check the router's CPU architecture:
   ```bash
   uname -m
   ```
2. Download the matching build from the [Phantom releases page](https://github.com/jhead/phantom/releases) and copy it to `/root/phantom` (for example with `scp`).
3. Make it executable:
   ```bash
   chmod +x /root/phantom
   ```

## Step 3: Create a procd service

OpenWrt manages services with **procd**, which is different from the SysV `init.d` scripts on Debian or Ubuntu. Create `/etc/init.d/phantom` with this content, replacing `mc.example.com` with your server's address:

```sh
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=99

start_service() {
    rm -f /tmp/phantom.log

    procd_open_instance
    procd_set_param command /bin/sh -c '
        for i in $(seq 1 30); do
            if nslookup mc.example.com >/dev/null 2>&1; then
                exec /root/phantom -server mc.example.com:19132 >>/tmp/phantom.log 2>&1
            fi
            sleep 2
        done
        exit 1
    '
    procd_set_param respawn
    procd_close_instance
}
```

### Why the DNS wait loop?

On boot, the router may start services before the WAN link or DNS is up. The loop retries the lookup every 2 seconds for up to 60 seconds before launching Phantom. If DNS never resolves, the script exits and `respawn` tries again.

## Step 4: Enable and start it

```bash
chmod +x /etc/init.d/phantom
/etc/init.d/phantom enable   # start on boot
/etc/init.d/phantom start    # start now
```

Open Minecraft on any device on your network and check the **Friends → LAN Games** list. Your server should be there.

## Useful commands

```bash
/etc/init.d/phantom stop
/etc/init.d/phantom restart
/etc/init.d/phantom enabled   # exit code 0 means it's set to start on boot
logread | grep phantom        # procd/system log
cat /tmp/phantom.log          # Phantom's own output
```

`/tmp` on OpenWrt is RAM-backed and wiped on reboot, so the log won't grow forever and doesn't need rotating.

## Debian or Ubuntu instead?

On a regular Linux box, skip the init script and use a systemd unit:

```ini
# /etc/systemd/system/phantom.service
[Unit]
Description=Phantom - show remote Bedrock server as a LAN game
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/phantom -server mc.example.com:19132
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now phantom
```

## References

- [Phantom on GitHub](https://github.com/jhead/phantom)
- [OpenWrt init scripts](https://openwrt.org/docs/techref/initscripts)
