---
tags: [bmw/g30, app, diagnostics]
updated: 2026-11-13
---
# Car Test and Test 2 (Car tab)

The guided, read-only connection to the car over the ENET cable.

## Steps
1. **Cable** — confirm the USB-C Ethernet adapter is up (a `169.254.x.x` link-local
   address).
2. **Find the car** — automatic search, a typed gateway IP, or a slow cable sweep.
   The working address is remembered.
3. **Identify** — read VIN and identification from the gateway, head unit, cluster
   and HUD, plus the head unit's fault codes (~10 reads).

## Test 2
- **Find every module** — one request all modules answer (finds the HUD address).
- **Read engine values** — standard OBD values from the DME; boost = manifold −
  barometric.

## Confirmed on the real car (2026-11-11)
- Gateway (ZGW `0x10`), head unit (`0x63`), cluster (KOMBI `0x60`) answered over
  **HSFZ**. HUD did not answer at `0x3D` (still unconfirmed).
- No real faults stored in the head unit; lots of "not tested yet" entries.

## Capturing BMW-specific values
Test 2 and a scan are also how we capture the BMW-specific identifiers the
[[Gauges Dashboard]] needs for fuel pressure and charge.

Related: [[Car Test Procedure]] · [[Glossary]]
