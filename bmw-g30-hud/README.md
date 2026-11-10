# BMW G30 — Apple‑Maps‑on‑HUD + Read‑Only ENET Toolkit

An iPhone‑centric software project for a **2018 BMW 540i (G30, NBT EVO, iDrive 6,
factory HUD, wireless CarPlay)**. Built and tested in a cloud dev environment; no
vehicle is touched by anything in this repo.

> **Reality check up front.** Every route to arrows on the factory HUD needs
> **software on the head unit** that sends the HUD guidance messages, and that's the
> real blocker (it means modifying the head unit). The guidance can't be read from
> the Apple Maps app **on the phone** (iOS has no API). CarPlay *can* send it to head
> units that ask for it (newer BMWs do), but the G30's NBT EVO doesn't as delivered.
> The simulator, translator, and read‑only diagnostics for this path are built and
> tested here. The on‑car part is design‑only and needs your approval. Full analysis:
> [`docs/navigation-data.md`](docs/navigation-data.md),
> [`docs/compatibility-assessment.md`](docs/compatibility-assessment.md).

## What works right now (in this cloud, no car)

- **Navigation → HUD simulator** — a vendor‑neutral nav event stream translated into
  constrained factory‑HUD/KOMBI "frames," rendered as ASCII and amber SVG so you can
  see the output on your phone. Exercises turns, distance countdown, street names,
  highway exits, roundabouts, reroute, and arrival.
- **Read‑only ENET diagnostics, ready for a first car test.** Both BMW protocols
  (**HSFZ**, which a 2018 G30 most likely uses, and **DoIP**), real‑gateway behaviour
  (acks, keep‑alives, response pending), finding the car on the cable, and a shareable
  log with the VIN hidden. It **cannot** write, flash, or clear anything: that's
  enforced in code twice and asserted by tests, including end‑to‑end tests over real
  sockets.
- **Swift package for the iOS app** (`ios-app/BMWLinkKit`) with two libraries:
  `BMWLinkKit` (the read‑only diagnostics stack in Swift) and `NavHUDKit` (the
  nav→HUD translator plus an **Apple MapKit route source** that classifies each route
  step's maneuver from its instruction text and turn geometry).
- **iPhone app with two tabs:** *Diagnostics* (read‑only ENET) and *HUD* (plan a route
  with Apple's routing engine, then watch the HUD/cluster frames it would produce
  during a simulated drive; nothing is sent to the car).
- **Tests:** 40 Python + 46 Swift tests pass. The two languages are held
  byte‑identical by shared golden files (DoIP/UDS frames and 108 translated HUD
  frames). CI (`.github/workflows/bmw-g30-hud-ci.yml`) also builds the app on a
  GitHub‑hosted **macOS** runner and produces an unsigned `.ipa`.

```
bmw-g30-hud/
├── sim/navhud/          Module 3+4: nav events, HUD model, translator, renderers, CLI
├── proto/bmwdiag/       Module 1+2: DoIP + UDS (read-only), DID catalogue, mock gateway
├── ios-app/             Module 5: Swift Package (BMWLinkKit) + SwiftUI app skeleton
├── tests/               40 Python unit tests (stdlib only); Swift tests live in ios-app/
├── test-vectors/        golden DoIP/UDS vectors shared by Python + Swift
├── docs/                compatibility, architecture, navigation-data, safety, deployment
└── out/                 generated HUD HTML strips (visual review)
```

## Quick start (this environment)

```bash
# run every Python test (no dependencies needed)
python3 -m unittest discover -s tests -p 'test_*.py'

# run the Swift tests (needs a Swift toolchain, or Docker with the swift image)
cd ios-app/BMWLinkKit && swift test

# render HUD frames for a scenario, as ASCII
cd sim && python3 -m navhud.cli --scenario city --sink hud --ascii

# write an HTML strip of amber HUD frames you can open on a phone
cd sim && python3 -m navhud.cli --scenario highway --sink kombi --html ../out/highway.html
```

## Status by deliverable

| Deliverable | Status |
|---|---|
| A. Apple‑Maps‑on‑HUD | **Simulated only** — simulator + translator done. Stock Apple Maps guidance can only reach the HUD through the head unit (unproven on NBT EVO); a MapKit source is the buildable alternative. On‑car output is blocked on head‑unit software (`docs/deployment-and-blockers.md`). |
| B. Native BMW iPhone app (ENET) | **Ready for a first car test, not yet installed.** Both BMW protocols, discovery and a redacted log are tested end to end against a simulated gateway; macOS CI builds the app. Install: `docs/install-on-iphone.md`; test: `docs/car-test-procedure.md`. Not yet run against a real car. |
| C. Safe deployment workflow | **Documented** — `docs/safety.md`, `docs/deployment-and-blockers.md`. |
| D. Custom BMW software platform | **Foundation only** — read‑only live‑value plumbing exists; dashboards/theme deferred. |
| E. GitHub repository | **This repo**, branch `claude/bmw-g30-maps-hud-eyvj50`. |

## Milestones

[`ROADMAP.md`](ROADMAP.md): what's done and verified, what's next, and what's
waiting on you.

## Next steps on the car (read‑only)

1. [`docs/stage5-vehicle-capture.md`](docs/stage5-vehicle-capture.md): five minutes of
   looking at iDrive menus and the HUD. No tools, no changes to the car.
2. [`docs/install-on-iphone.md`](docs/install-on-iphone.md), then
   [`docs/car-test-procedure.md`](docs/car-test-procedure.md): connect the app over the
   ENET cable and read identification data. Read‑only, about 10 minutes, ends with a
   log to send back.

## Safety

Read [`docs/safety.md`](docs/safety.md). Summary: no DME/tune/flash/safety‑system
changes; read‑only diagnostics are enforced in code; any future on‑car change is
Red‑tier and requires an independent recovery plan **and your explicit approval**.

## Credits / prior art

- Architecture and HUD feasibility informed by the **Sq00ky / NBT‑AAD** project
  (Supra iDrive 6 Android Auto), which demonstrates third‑party NBT EVO apps and HUD
  nav rendering on this head‑unit family. That project is separate software under the
  **PolyForm Noncommercial** license; **no code from it is copied into this repo**,
  and we do not reproduce its head‑unit‑unlock tooling. This repo's own code is MIT.

Licensing details and the reuse boundary: [`docs/attribution.md`](docs/attribution.md).
