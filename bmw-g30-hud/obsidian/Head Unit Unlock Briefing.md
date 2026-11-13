---
tags: [bmw/g30, idrive, safety, unlock]
updated: 2026-11-13
---
# Head Unit Unlock Briefing

The road behind the "PlayStation" iDrive clips: custom dashboards, themes and
games **on the iDrive screen**. This is a briefing so you can decide with eyes
open — **not** a how-to. The project won't script the unlock.

## What it actually takes
1. **Get a foothold** — the head unit runs a locked-down QNX system. Access is
   gained by **running an exploit** the community found; it's unsupported and can
   stop working after a software update.
2. **Change the filesystem** — add/replace theme files or app packages. Every
   write to the head unit's storage is a chance to leave it unbootable.
3. **Make it persist** across restarts/updates — more writes, more risk.

## Where it bricks, and how bad
- A failed/interrupted write → **boot loop or dead** head unit: no iDrive, often
  no radio/climate UI, no CarPlay; sometimes it disturbs the car's data bus.
- **A file backup is not a guarantee.** Recovery can need low-level
  (serial/JTAG-type) access or specialist help. Worst case: **replace the head
  unit** (four figures + coding to the car).

## A real recovery plan must include
- A **tested** way to restore the unit to bootable **without the car** — proven
  on a bench/spare first.
- Your **exact** head-unit hardware/software IDs and guides matching that unit.
- Money for a replacement if recovery fails.
- Ideally someone who's done it on **your** variant.

## The line
It's your car and your risk if you choose it. I'll pressure-test your recovery
plan and talk trade-offs — I won't hand you the exploit, steps or tooling.

Full doc: `docs/idrive-customization.md`. Related: [[Safety and Boundaries]] ·
[[iDrive Customization]]
