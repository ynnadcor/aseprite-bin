---
tags: [bmw/g30, status]
updated: 2026-11-13
---
# Status and Roadmap

## Done & shipped
- Read-only ENET diagnostics (HSFZ + DoIP), discovery, redacted logs.
- [[Car Test and Test 2]] — proven on the real car over HSFZ.
- [[Fault Code Reader]] + [[Fault Code Combinations]].
- [[iDrive Coding Guide]] + [[Coding Tweaks Catalog]].
- [[Gauges Dashboard]] — live performance gauges on the phone.
- [[HUD Preview]] simulator.
- App installs/updates via [[Install on iPhone|SideStore]].

## Next
- Run the full scan + Test 2 on the car and send the log.
- Capture BMW-specific live values (fuel rail pressure, requested/actual charge)
  so the Gauges "Fuel & ignition" card fills in.
- Pick [[Coding Tweaks Catalog|coding changes]] to apply in BimmerCode.

## Won't do
- [[Head Unit Unlock Briefing|Head-unit unlock]] (themes/apps on the screen):
  briefing only, no exploit/tooling.
- Engine tuning / coding **writes** from the app. See [[Safety and Boundaries]].
