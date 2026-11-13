---
tags: [bmw/g30, app, idrive]
updated: 2026-11-13
---
# Gauges Dashboard (app tab)

A live performance dashboard on the phone, the safe version of the "M Vitals"
screen. Read-only: it polls values, changes nothing.

## Gauges
- **Boost** — big arc gauge with peak-hold, derived from manifold minus
  barometric pressure (OBD `0B` − `33`).
- **Temperatures** — coolant, oil, intake air, colour-coded for heat-soak.
- **Engine** — RPM, load, speed.
- **Fuel & ignition** — rail pressure, requested vs actual charge. These are
  **BMW-specific** (not standard OBD), so they show "needs capture" until read
  off the car. See [[Car Test and Test 2]].

## How it works
Polls `ReadDataByIdentifier` in a loop (paced to be gentle), decodes a
`LiveSample`, drives the gauges. Practice mode runs a simulated pull so it moves
with no car. On the car: engine idling (parked, in P) or a passenger holding the
phone on a drive.

## Not on the iDrive screen
This is on the phone. Gauges on the actual screen = factory Sport displays
([[Coding Tweaks Catalog]]) or [[Head Unit Unlock Briefing]].

Related: [[iDrive Customization]] · [[Safety and Boundaries]]
