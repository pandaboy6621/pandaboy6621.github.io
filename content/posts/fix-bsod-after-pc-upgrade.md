---
title: "How to Troubleshoot Constant Blue Screens After a PC Upgrade"
date: 2026-10-30
description: "Swapped the CPU, motherboard and RAM, and now Windows blue-screens with a different error every time? Here's what those stop codes point to and the order to work through them."
tags: [windows, pc-building, troubleshooting, bsod]
---

I upgraded nearly everything in my desktop (CPU, motherboard, RAM and GPU) but kept the old SSD, case and fans. On first boot it blue-screened over and over during light use: a Discord call and a browser. Resetting Windows didn't fix it.

When you see a *different* stop code almost every crash, that's a clue. It usually means something low-level (memory, CPU stability, firmware or a driver) is corrupting whatever happens to be running, rather than one specific broken program.

## What the stop codes mean

| Code | Name | Usually points to |
|---|---|---|
| `0x0000003B` | SYSTEM_SERVICE_EXCEPTION | Driver or memory fault in a system call |
| `0x00000109` | CRITICAL_STRUCTURE_CORRUPTION | Kernel data corrupted; often RAM or a bad driver |
| `0x00000050` | PAGE_FAULT_IN_NONPAGED_AREA | Invalid memory referenced; RAM or driver |
| `0x0000007F` | UNEXPECTED_KERNEL_MODE_TRAP | CPU trap; often unstable CPU/RAM settings |
| `0x0000000A` | IRQL_NOT_LESS_OR_EQUAL | Driver accessing memory it shouldn't |
| `0x0000007E` | SYSTEM_THREAD_EXCEPTION_NOT_HANDLED | Driver crash in a system thread |
| `0x0000001A` | MEMORY_MANAGEMENT | Serious memory management error; very often RAM |
| `0x00000133` | DPC_WATCHDOG_VIOLATION | Driver or storage controller hanging |

Notice the theme: memory and drivers.

## Step 1: Update the BIOS and reset memory settings

New boards often ship with early firmware that has memory-compatibility bugs.

1. Update the motherboard BIOS to the latest version from the manufacturer's site.
2. Load optimized defaults.
3. **Turn off XMP/EXPO** for now and test at stock memory speed. If the crashes stop, your RAM kit is unstable at its rated profile on this board/CPU.

## Step 2: Test the RAM

- Run **Windows Memory Diagnostic** (`mdsched.exe`) as a quick check.
- For a thorough test, boot **MemTest86** from a USB stick and let it run several passes.
- If you have two sticks, test one at a time in the slot the manual recommends.

Any error at all means a bad stick, bad settings, or a seating problem. Reseat the RAM and try again.

## Step 3: Repair Windows system files

Open **Terminal (Admin)** and run:

```powershell
sfc /scannow
DISM.exe /Online /Cleanup-Image /RestoreHealth
```

Run `sfc /scannow` a second time after DISM finishes.

## Step 4: Clean up old drivers

Carrying an old Windows install over to new hardware is a classic cause of this. Old chipset, storage and GPU drivers stay around.

1. Install the **chipset drivers** for your *new* motherboard from the board or CPU maker.
2. Use **DDU (Display Driver Uninstaller)** in Safe Mode to remove old GPU drivers, then install fresh ones.
3. Remove old motherboard utilities (RGB software, fan controllers, tuning apps) from the previous system.

If none of that helps, a truly clean install is better than a "reset": back up your files, create a USB installer with the Media Creation Tool, and delete the old partitions during setup.

## Step 5: Read the dump files

Install **WinDbg** from the Microsoft Store, open a file from `C:\Windows\Minidump`, and run:

```
!analyze -v
```

Look for the `MODULE_NAME` / `IMAGE_NAME` line. If it keeps naming the same driver (a `.sys` file), you've found your suspect.

## Step 6: Check the hardware basics

- Make sure the 24-pin and CPU 8-pin power cables are fully seated.
- Confirm your PSU is big enough for the new parts, and the GPU has its own PCIe power cables rather than one daisy-chained cable.
- Check CPU temperatures under load with HWiNFO.

## The short version

1. BIOS update → defaults → XMP/EXPO off
2. MemTest86
3. `sfc` + `DISM`
4. New chipset drivers, DDU for GPU, remove old utilities
5. Clean install if it's still crashing
6. Read the minidumps to find the driver
