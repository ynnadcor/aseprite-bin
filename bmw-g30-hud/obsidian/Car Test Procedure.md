---
tags: [bmw/g30, diagnostics]
updated: 2026-11-13
---
# Car Test Procedure (at the car)

Read-only. Parked, ignition on (engine idling for live values).

## Setup
1. ENET cable into the OBD port; USB-C Ethernet adapter into the iPhone.
2. Wait ~10 s for the adapter to get a `169.254.x.x` address.

## In the app
1. **Car** tab → **My car** → find the car (steps 1–2). The address is remembered.
2. **Codes** tab → **Scan all modules** (see [[Fault Code Reader]]).
3. **Car** tab → **Test 2** (find every module, read engine values).
4. **Gauges** tab → **My car** → Start (watch boost/temps live).
5. **Session log** → Share, and send it back.

## What the log gives us
- Whether the DME answers OBD-II code requests over the cable.
- Any real stored faults.
- The HUD's address (if it answers).
- BMW-specific identifiers for the [[Gauges Dashboard]] fuel/charge values.

> The log masks VIN, MAC and ECU serials.
