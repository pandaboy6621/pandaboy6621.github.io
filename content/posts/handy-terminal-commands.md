---
title: "Handy Terminal Commands I Keep Coming Back To (macOS, Windows, Linux)"
date: 2026-10-25
description: "A grab bag of one-liners worth bookmarking: back up your installed Mac apps, download video with yt-dlp, repair Windows, rescue a Home Assistant backup, and a few app settings that are hard to find."
tags: [cheat-sheet, macos, windows, linux, cli]
---

A running list of commands I keep having to look up. Bookmark it and steal whatever is useful.

## macOS

### Back up your list of installed apps

Handy before reinstalling macOS or setting up a new Mac:

```bash
brew list > ~/Desktop/brew_installed_apps.txt
mas list > ~/Desktop/macappstore_apps.txt    # needs: brew install mas
```

Better still, make a Brewfile that can reinstall everything in one go:

```bash
brew bundle dump --file=~/Desktop/Brewfile
brew bundle --file=~/Desktop/Brewfile         # on the new Mac
```

### Download a video with yt-dlp

```bash
brew install yt-dlp ffmpeg

# as MP4
yt-dlp --recode-video mp4 "URL"

# audio only, as MP3
yt-dlp -x --audio-format mp3 "URL"
```

Only download things you have the right to keep.

## Windows

### Repair system files

Run in **Terminal (Admin)**:

```powershell
sfc /scannow
DISM.exe /Online /Cleanup-Image /RestoreHealth
```

Run `sfc` again after DISM. This is my first step whenever Windows starts acting strangely.

### Turn off Focused Inbox in the new Outlook

There's no simple toggle any more. Go to **Settings (gear) → Mail → Layout**, and under **Focused Inbox** choose **Don't sort my messages**, then **Save**.

## Linux

### Rescue a Home Assistant backup from the command line

If Home Assistant OS won't boot properly but you can get to a shell, you can copy the backups off the data partition and make a fresh one:

```bash
# find the right disk and partition
lsblk -o+FSTYPE,MODEL

# mount it somewhere temporary
mkdir -p /mnt/data/temp/backup
mount /dev/sdX2 /mnt/data/temp/backup      # replace sdX2 with your partition

# copy the existing backups across
cp -Rv /mnt/data/supervisor/backup/* /mnt/data/temp/backup/
umount /mnt/data/temp/backup/

# create a new full backup
ha backup new --name "fullbackup"
```

Double-check the device name from `lsblk` before mounting anything.

## Browsers

### Force dark mode on every site in Brave or Chrome

Paste this into the address bar and set it to **Enabled**:

```
brave://flags/#enable-force-dark
```

In Chrome it's `chrome://flags/#enable-force-dark`.
