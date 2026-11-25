---
title: "How to Send Notifications Anywhere with Apprise (Email, Discord, Matrix, Home Assistant)"
date: 2026-11-01
description: "One command-line tool, dozens of notification services. A practical Apprise cheat sheet with the URL formats I use, the errors I hit, and how to keep your secrets out of shell history."
tags: [apprise, notifications, homelab, cli]
---

[Apprise](https://github.com/caronc/apprise) sends a notification to almost any service using a single URL format. It's great for cron jobs, backup scripts, and anything else that should tell you when it finishes or fails.

## Install

```bash
pip install apprise      # or: brew install apprise
```

## The basic shape

```bash
apprise -vv -t "Title" -b "Body" "<service-url>"
```

`-v` adds verbosity; stack them (`-vv`, `-vvv`) when debugging.

## Send to several services at once

Just list more URLs:

```bash
apprise -vv --body="Backup finished" \
   "mailto://user:password@example.com" \
   "slack://token_a/token_b/token_c" \
   "kodi://media-box.local"
```

## Service examples

### Gmail

Gmail needs an **app password** (Google Account → Security → App passwords), not your normal password. Turn on 2-step verification first.

```bash
apprise -b "My message" "mailto://your.name:APP_PASSWORD@gmail.com"
```

### macOS notification centre

```bash
apprise -vv -t "Test title" -b "Test body" "macosx://"
```

### Discord

Create a webhook (**Channel Settings → Integrations → Webhooks**). Its URL looks like `https://discord.com/api/webhooks/<id>/<token>`. Apprise takes the same two parts:

```bash
apprise -vv -t "Test title" -b "Test body" "discord://<id>/<token>/"
```

> **Got a 401 error?** Make sure you copied the token *exactly*. It often contains hyphens and underscores, and dropping or changing one character gives a verification failure. You can also paste the full `https://discord.com/api/webhooks/...` URL straight into Apprise.

### Matrix

```bash
apprise -vv -t "Test title" -b "Test body" "matrixs://user:password@matrix.example.com/!roomid"
```

> **"Event not found"?** Check the room ID (it starts with `!`, not `#`), that the account has joined the room, and that the homeserver allows password logins. Some bridged or hosted services (Beeper, for example) don't support it, so a dedicated bot account on a regular homeserver is more reliable.

### Home Assistant

Create a **long-lived access token** in your Home Assistant profile:

```bash
apprise -vvv "hassio://homeassistant.local/<long-lived-token>"
```

Use `hassios://` if Home Assistant is behind HTTPS.

> **Command just hangs?** Check the host and port (`hassio://host:8123/token`), and that the machine running Apprise can actually reach Home Assistant.

## Keep secrets out of your shell history

Every one of these URLs contains a password or token. Instead of typing them inline, put them in a config file only you can read:

```bash
mkdir -p ~/.config/apprise
cat > ~/.config/apprise/apprise.yml <<'EOF'
urls:
  - discord://<id>/<token>/:
      tag: discord
  - mailto://your.name:APP_PASSWORD@gmail.com:
      tag: email
EOF
chmod 600 ~/.config/apprise/apprise.yml
```

Apprise reads that file automatically, and you pick services by tag:

```bash
apprise -t "Backup" -b "Done" --tag=discord
```

If a token ever ends up in a screenshot, a note, or git, revoke it and make a new one. Webhook URLs and app passwords are as good as a password to whoever has them.
