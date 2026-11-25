---
title: "How to Plan a CircuitPython Macropad Layout (with a Bongo Cat Screen)"
date: 2026-11-12
description: "Planning a 12-key Adafruit MacroPad RP2040 build: volume knob, media controls, Home Assistant buttons, a Discord mute key with a status LED, and a bongo cat that slaps the table every time you press a key."
tags: [circuitpython, macropad, diy, home-assistant]
---

The [Adafruit MacroPad RP2040](https://www.adafruit.com/product/5128) packs 12 mechanical keys with RGB LEDs, a rotary encoder, and a tiny OLED into one board you program in CircuitPython. Before writing any code, it helps to plan what each key does. Here's how I laid mine out.

## The layout

| Input | Action | How |
|---|---|---|
| Encoder turn | Volume up/down | Consumer Control `VOLUME_INCREMENT` / `DECREMENT` |
| Encoder click | Play/pause | Consumer Control `PLAY_PAUSE` |
| Key 1 | Open my homelab dashboard | `Win+R`, type the URL, `Enter` |
| Key 2 | Quick search | `Alt+Space` (PowerToys Run / Command Palette) |
| Key 3 | File Explorer | `Win+E` |
| Key 4 | Desk LEDs on/off | Home Assistant service call |
| Key 5 | Cycle desk LED effect | Home Assistant script |
| Key 6 | Screenshot | `Win+Shift+S` |
| Keys 7-10 | Spare | Room to grow |
| Key 11 | System mute | Consumer Control `MUTE` |
| Key 12 | Discord mute | `Alt+M` (set as Discord's mute keybind), LED red when muted, green when live |

## The OLED: bongo cat

The screen shows a bongo cat all the time:

- **No keys pressed:** paws up.
- **Any key pressed:** paws down on the table.

It's just two bitmaps swapped based on whether any key is held, which is easy to do with `displayio` and a small sprite sheet.

## Getting started in CircuitPython

1. Install the latest CircuitPython for the MacroPad from [circuitpython.org](https://circuitpython.org/board/adafruit_macropad_rp2040/).
2. Copy the `adafruit_macropad` library (and its dependencies) from the library bundle into `CIRCUITPY/lib`.
3. Start from a simple `code.py`:

```python
from adafruit_macropad import MacroPad

macropad = MacroPad()
last_position = macropad.encoder

while True:
    # encoder -> volume
    position = macropad.encoder
    if position > last_position:
        macropad.consumer_control.send(macropad.ConsumerControlCode.VOLUME_INCREMENT)
    elif position < last_position:
        macropad.consumer_control.send(macropad.ConsumerControlCode.VOLUME_DECREMENT)
    last_position = position

    # encoder click -> play/pause
    macropad.encoder_switch_debounced.update()
    if macropad.encoder_switch_debounced.pressed:
        macropad.consumer_control.send(macropad.ConsumerControlCode.PLAY_PAUSE)

    # keys
    event = macropad.keys.events.get()
    if event and event.pressed:
        if event.key_number == 2:  # Key 3: File Explorer
            macropad.keyboard.send(macropad.Keycode.WINDOWS, macropad.Keycode.E)
```

Keys are numbered 0-11 in code, so "Key 3" in the table is `key_number == 2`.

## Home Assistant buttons

The MacroPad is just a USB keyboard, so it can't call Home Assistant directly. Two easy options:

- **Keyboard shortcut + automation:** send an unused combo like `Ctrl+Alt+F13` and have a desktop tool (AutoHotkey, or the HASS.Agent app on Windows) call the Home Assistant service.
- **Open a URL:** point a key at a Home Assistant webhook automation.

## The Discord mute LED

The MacroPad can't know Discord's real mute state, so the LED just tracks presses of the key: toggle a variable each time it's pressed and set `macropad.pixels[11]` to red or green. If you mute with the mouse, it'll drift out of sync. Press the key twice to fix it.

## Key icons

If you print key labels or show icons on the OLED, free icon sets like [Icons8](https://icons8.com) have matching styles for home, search, folder, lamp and list icons.
