# Licensing & Reuse Boundary

This project reuses **ideas and publicly documented behavior** from prior art, but
**not code**. This file records the boundary so the licensing stays clean.

## This repository's own code
- Licensed **MIT** (see `LICENSE`). All Python/Swift under `sim/`, `proto/`,
  `ios-app/`, `tests/` is original to this project.

## Prior art consulted (reference only)

### Sq00ky / NBT‑AAD — "Supra iDrive 6 Android Auto"
- **License:** PolyForm Noncommercial 1.0.0 (their `LICENSE.md`).
- **What we used:** publicly documented *facts* — that NBT EVO is QNX/armv7le, that
  an on‑head‑unit app can emit guidance messages the KOMBI/HUD renders, that a G31
  5‑Series (same HU family as the G30) is confirmed working, and the general module
  shape (cluster/MOST/plugin). These are facts about the platform, not their code.
- **What we did NOT do:** copy, vendor, translate, or re‑host any of their source;
  reproduce their head‑unit SSH‑unlock / firewall tooling; or bundle their binaries.
- **If you ever use their actual software** on your car, do so under *their* license
  and terms, from their official releases — not through this repo.

### Wayglass (wayglass.info/hud)
- **Proprietary.** Treated purely as a *capability reference* (what the market claims
  is possible). No source obtained or used; its network host was unreachable from this
  environment, so even its public page is cited only from memory of its advertised
  scope and flagged UNVERIFIED where relevant.

## Why MIT here and not a copyleft/noncommercial license
This repo is your own tooling and simulator; MIT keeps it maximally reusable for you.
Because we copied **no** PolyForm‑licensed code, there is no license‑compatibility
obligation flowing into this repo. If that ever changes (e.g. you decide to vendor a
GPL/PolyForm component), this file and `LICENSE` must be revisited **before** merging
that code.

## Third‑party code actually present
- None vendored today. (The Swift package has no external dependencies; the Python
  uses only the standard library.) If a dependency is added later, record its license
  here.
