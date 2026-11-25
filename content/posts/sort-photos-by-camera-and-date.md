---
title: "How to Sort Photos into Device/Year/Month/Day Folders with exiftool and Python"
date: 2026-10-21
description: "Turn a messy dump of phone and camera photos into a tidy Device/YYYY/MM/DD folder tree, safely: dry run by default, moves instead of copies, and never overwrites."
tags: [macos, photos, python, scripts]
---

Old phone backups and SD card dumps end up as one giant folder of `IMG_1234.HEIC` files. This script reads the camera model and capture date from each file's metadata and moves it into:

```
Sorted Pictures/
└── iPhone 13/
    └── 2023/
        └── 07/
            └── 14/
                └── IMG_1234.HEIC
```

## What makes it safe

- **Dry run by default.** Nothing changes until you add `--move`.
- **Moves, never copies.** On the same drive that's a true rename, so created and modified dates are preserved.
- **Never overwrites.** Name clashes get `_1`, `_2` and so on.
- **Re-runnable.** The output folder is skipped when scanning.

## Step 1: Install the tools

These steps are for macOS, but the script works anywhere Python 3 and exiftool are installed.

1. Install [Homebrew](https://brew.sh) if you don't have it.
2. Install exiftool:
   ```bash
   brew install exiftool
   ```
3. Check for Python 3:
   ```bash
   python3 --version
   ```
   If it's missing, macOS will offer to install the Command Line Tools, or run `brew install python`.

## Step 2: Save the script

Save the script at the bottom of this post as `sort_pictures.py`, for example in `~/Scripts`.

## Step 3: Do a dry run

```bash
python3 ~/Scripts/sort_pictures.py "/Volumes/Backup/Old iPhone"
```

Read the summary at the end. Pay attention to how many files landed in `Unknown Device` and how many fell back to the file-modified date.

## Step 4: Run it for real

```bash
python3 ~/Scripts/sort_pictures.py "/Volumes/Backup/Old iPhone" --move
```

### Options

| Flag | What it does |
|---|---|
| `--device "Name"` | Uses one device name for every file instead of reading the Model tag |
| `--out "PATH"` | Puts sorted folders somewhere other than `<source>/Sorted Pictures` |

Always quote paths; spaces and `+` signs are common in folder names.

`--device` is handy for Samsung phones, which store a model code like `SM-S906B` rather than a friendly name:

```bash
python3 sort_pictures.py "/Volumes/Backup/Samsung/DCIM/Camera" --device "Galaxy S22+" --move
```

## Things to know

- The `Sorted Pictures` folder **doesn't exist after a dry run**; it's only created with `--move`.
- Date priority: `DateTimeOriginal` → `CreateDate` → `MediaCreateDate` → file modified date.
- Files with no camera model go under `Unknown Device`.
- Only photos and videos are moved. Sidecar files like iPhone `.AAE` stay put.
- Hidden files, including macOS `._` files on external drives, are skipped.
- Moving across drives turns into a copy and changes dates, so keep `--out` on the same volume as the source.

## Troubleshooting

| Problem | Fix |
|---|---|
| `exiftool not found` | `brew install exiftool` |
| Can't find `Sorted Pictures` | You only did a dry run. Re-run with `--move` |
| `Found 0 media files` | Check the path, the quotes, and that the drive is mounted |
| Folders named like `SM-S906B` | Use `--device "Friendly Name"` |

## The script

```python
#!/usr/bin/env python3
"""
Sort photos/videos into:  <Device Name>/<YYYY>/<MM>/<DD>/

- Dry run by default (nothing is touched). Add --move to actually do it.
- Files are MOVED (renamed) on the same volume, never copied, so
  created/modified dates stay exactly as they are.
- Never overwrites: name clashes get _1, _2, ... appended.
- Requires exiftool:  brew install exiftool
"""
import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter

OUT_NAME = "Sorted Pictures"

MEDIA_EXTS = {
    ".jpg", ".jpeg", ".heic", ".heif", ".png", ".gif", ".tif", ".tiff",
    ".bmp", ".webp", ".dng", ".raw", ".cr2", ".cr3", ".nef", ".arw",
    ".mov", ".mp4", ".m4v", ".avi", ".3gp",
}

DATE_TAGS = ["DateTimeOriginal", "CreateDate", "MediaCreateDate", "FileModifyDate"]
DATE_RE = re.compile(r"^(\d{4}):(\d{2}):(\d{2})")
CHUNK = 500


def find_files(src, out_dir):
    out_abs = os.path.abspath(out_dir)
    found = []
    for root, dirs, files in os.walk(src):
        # don't re-scan the output folder, skip hidden dirs
        dirs[:] = [
            d for d in dirs
            if not d.startswith(".")
            and os.path.abspath(os.path.join(root, d)) != out_abs
        ]
        for f in files:
            if f.startswith("."):  # includes ._AppleDouble files
                continue
            if os.path.splitext(f)[1].lower() in MEDIA_EXTS:
                found.append(os.path.join(root, f))
    return found


def read_metadata(paths):
    """Yield exiftool metadata dicts, in chunks."""
    for i in range(0, len(paths), CHUNK):
        chunk = paths[i:i + CHUNK]
        cmd = [
            "exiftool", "-json", "-charset", "filename=UTF8",
            "-api", "QuickTimeUTC=1",
            "-Model", *[f"-{t}" for t in DATE_TAGS],
            "-@", "-",
        ]
        res = subprocess.run(
            cmd, input="\n".join(chunk), capture_output=True, text=True
        )
        if not res.stdout.strip():
            print(res.stderr, file=sys.stderr)
            continue
        for item in json.loads(res.stdout):
            yield item


def pick_date(meta):
    for tag in DATE_TAGS:
        m = DATE_RE.match(str(meta.get(tag, "")))
        if m and m.group(1) != "0000" and m.group(2) != "00" and m.group(3) != "00":
            return m.groups(), tag
    return None, None


def clean(name):
    name = re.sub(r'[/:\\\0]', "-", str(name)).strip()
    return name or "Unknown Device"


def unique_path(path):
    if not os.path.exists(path):
        return path
    base, ext = os.path.splitext(path)
    n = 1
    while os.path.exists(f"{base}_{n}{ext}"):
        n += 1
    return f"{base}_{n}{ext}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", help="source folder")
    ap.add_argument("--out", help=f'output folder (default: "<src>/{OUT_NAME}")')
    ap.add_argument("--move", action="store_true", help="actually move files (default is dry run)")
    ap.add_argument("--device", help="force a device name for every file (skips Model lookup)")
    args = ap.parse_args()

    src = os.path.abspath(args.src)
    out_dir = os.path.abspath(args.out or os.path.join(src, OUT_NAME))

    if not os.path.isdir(src):
        sys.exit(f"Source not found: {src}")
    if subprocess.run(["which", "exiftool"], capture_output=True).returncode != 0:
        sys.exit("exiftool not found. Install with: brew install exiftool")

    mode = "MOVING" if args.move else "DRY RUN (nothing will be changed)"
    print(f"{mode}\n  from: {src}\n  to:   {out_dir}\n")

    files = find_files(src, out_dir)
    print(f"Found {len(files)} media files. Reading metadata...\n")

    moved = 0
    errors = 0
    fallback_dates = 0
    per_device = Counter()

    for meta in read_metadata(files):
        path = meta["SourceFile"]
        date, tag = pick_date(meta)
        if date is None:
            print(f"SKIP (no usable date): {path}")
            errors += 1
            continue
        if tag == "FileModifyDate":
            fallback_dates += 1

        device = clean(args.device or meta.get("Model") or "Unknown Device")
        yyyy, mm, dd = date
        dest_dir = os.path.join(out_dir, device, yyyy, mm, dd)
        dest = unique_path(os.path.join(dest_dir, os.path.basename(path)))

        print(f"{os.path.relpath(path, src)}  ->  {os.path.relpath(dest, out_dir)}")

        if args.move:
            try:
                os.makedirs(dest_dir, exist_ok=True)
                # os.rename = a true move on the same volume; keeps all timestamps.
                os.rename(path, dest)
            except OSError as e:
                print(f"  ERROR: {e}")
                errors += 1
                continue
        moved += 1
        per_device[device] += 1

    verb = "Moved" if args.move else "Would move"
    print(f"\n{verb} {moved} files. Errors/skipped: {errors}.")
    if fallback_dates:
        print(f"{fallback_dates} files had no capture date and used the file modified date instead.")
    for dev, n in per_device.most_common():
        print(f"  {dev}: {n}")
    if not args.move:
        print("\nLooks right? Re-run with --move to do it for real.")


if __name__ == "__main__":
    main()
```
