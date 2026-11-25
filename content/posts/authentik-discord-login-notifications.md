---
title: "How to Send \"User Is Logging Into App\" Alerts from authentik to Discord"
date: 2026-11-21
description: "authentik's built-in Discord notifications only tell you who logged in. Here's how to get a clean \"alex is logging into Grafana\" message using a webhook mapping and the right event."
tags: [homelab, authentik, discord, sso, notifications]
---

authentik can post to Discord out of the box, but the default embed only names the user and the event type. I wanted a short message that says who signed into which app:

> **alex** is logging into **Grafana**

Tested on authentik 2026.8.

## Why the default doesn't work

- The plain `login` event happens at the authentik level, *before* any app is involved, so it has no app name.
- The `authorize_application` event fires when a user is authorized for a specific app. That's the one to match on.
- The transport mode called "Slack Webhook (Discord compatible)" uses a fixed embed and **ignores property mappings entirely**.

## Step 1: Create a Discord webhook

In Discord: **Channel Settings → Integrations → Webhooks → New Webhook**, then copy the URL. It should look like this:

```
https://discord.com/api/webhooks/<id>/<token>
```

**Don't add `/slack` to the end** (more on that in the troubleshooting table). Treat this URL like a password: anyone who has it can post to your channel.

## Step 2: Create the webhook mapping

**Customization → Property Mappings → Create → Webhook Mapping (Notification)**

```python
from authentik.core.models import Application

event = notification.event
ctx = event.context or {}
user = (event.user or {}).get("username", "Unknown user")

app = ctx.get("authorized_application", {}).get("name")
if not app:
    match = Application.objects.filter(
        provider__authorization_flow__pk=ctx.get("flow")
    ).first()
    app = match.name if match else "an application"

return {"content": f"**{user}** is logging into **{app}**"}
```

It tries the app name from the event context first. If that's missing, it looks up the app from the flow ID.

> **Caveat:** the flow-ID fallback can pick the wrong app when several apps share one authorization flow, which is the default for most setups. If you see the wrong app name, give each provider its own authorization flow, or use the debug mapping below to find a better key.

## Step 3: Create the notification transport

**Events → Notification Transports → Create**

- **Mode:** `Webhook (generic)`, *not* the Slack/Discord-compatible mode
- **Webhook URL:** the Discord URL from step 1
- **Webhook Mapping Body:** the mapping from step 2

The **test (play) button** next to the transport sends a test message without you having to log in.

## Step 4: Create the event matcher policy

**Customization → Policies → Create → Event Matcher Policy**

- **Name:** `authorize-application-event`
- **Action:** `Authorize Application`
- Leave app and client IP empty to match every app.

Note that this lives under *Customization → Policies*, not under Events.

## Step 5: Create the notification rule

**Events → Notification Rules**

1. Select the transport from step 3.
2. Set the severity to `Notice` or lower, or the event gets filtered out.
3. Expand the rule and use **Bind existing Policy/Group/User** to bind the policy from step 4.
4. Remove any binding to a `login` event matcher, or you'll get two messages per login.

## Step 6: Test it

Log out and back into an app, or use a private window. A fresh `authorize_application` event should fire and the message should appear in Discord.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Discord still shows the default embed | Transport is in Slack/Discord-compatible mode | Switch to `Webhook (generic)` and select the mapping |
| `400 Client Error: Bad Request` | URL ends in `/slack`, so Discord expects a Slack payload (`text`) but gets `content` | Remove `/slack`, or return `{"text": ...}` |
| Event page in authentik looks unchanged | The event page shows the raw stored event; mappings only change what's sent | Check Discord, not the event page |
| No message at all | An existing session means no new `authorize_application` event, or the rule uses the wrong transport | Log out/in, and check the rule's transport and policy binding |
| Webhook URL showed up in an error message | authentik's error text includes the full URL | Delete and recreate the webhook in Discord, then update the transport |

## Debug mapping

Swap this in temporarily to see exactly what the event context contains. It shows up in Discord as a code block:

```python
import json
event = notification.event
return {"content": "```" + json.dumps(event.context, default=str)[:1800] + "```"}
```

## Extras

- Discord webhooks also accept embeds if you want something fancier:
  `{"embeds": [{"title": "Login", "description": f"{user} is logging into {app}"}]}`
- If messages break after an authentik upgrade, run the debug mapping first to check whether the context keys changed.
