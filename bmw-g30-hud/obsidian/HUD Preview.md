---
tags: [bmw/g30, app, hud]
updated: 2026-11-13
---
# HUD Preview (HUD tab)

A simulator that turns navigation events into BMW Head-Up Display / cluster
frames and plays them as a drive. **Never talks to the car.**

- Translates turn-by-turn events into HUD guidance frames (arrows, distance, ETA).
- Works from a built-in demo route or an Apple MapKit route.
- Python and Swift produce byte-identical frames (golden-tested).

## Why it's only a preview
Getting Apple Maps guidance onto the **real** HUD needs software on the head unit
(it emits the HUD messages), which is the head-unit road — see
[[Head Unit Unlock Briefing]]. Whether NBT EVO can take CarPlay's cluster
guidance directly is still open research.

Related: [[iDrive Customization]]
