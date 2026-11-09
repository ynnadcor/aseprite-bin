# BMW G30 — Apple‑Maps‑on‑HUD + Read‑Only ENET Toolkit

An iPhone‑centric software project for a **2018 BMW 540i (G30, NBT EVO, iDrive 6,
factory HUD, wireless CarPlay)**. Built and tested in a cloud dev environment; no
vehicle is touched by anything in this repo.

> **Reality check up front.** Putting the *stock Apple Maps app's* directions on the
> factory HUD is **not possible** through any supported/legal interface — iOS doesn't
> expose that data. What's feasible is **equivalent functionality**: a custom app
> using Apple's own MapKit/CarPlay navigation, whose maneuvers feed an on‑head‑unit
> agent that drives the HUD. The simulator, translator, and read‑only diagnostics for
> that path are built and tested here; the on‑car agent is the real blocker and is
> deliberately design‑only and gated on your approval. Full analysis:
> [`docs/navigation-data.md`](docs/navigation-data.md),
> [`docs/compatibility-assessment.md`](docs/compatibility-assessment.md).

## What works right now (in this cloud, no car)

- **Navigation → HUD simulator** — a vendor‑neutral nav event stream translated into
  constrained factory‑HUD/KOMBI "frames," rendered as ASCII and amber SVG so you can
  see the output on your phone. Exercises turns, distance countdown, street names,
  highway exits, roundabouts, reroute, and arrival.
- **Read‑only ENET diagnostic core** — ISO 13400 (DoIP) + ISO 14229 (UDS) **read‑only**
  services, with a mock BMW gateway. It can read VIN, software versions, DTCs, and
  (placeholder) live B58 values — and it **cannot** write, flash, or clear anything
  (enforced in code and asserted by tests).
- **Swift package for the iOS app** (`ios-app/BMWLinkKit`) — the same read‑only
  stack in Swift, compiled with the official Swift 6.0.3 toolchain.
- **Tests:** 36 Python unit tests + 17 Swift XCTests pass, both asserting the same
  golden wire‑format vectors. CI (`.github/workflows/bmw-g30-hud-ci.yml`) also
  builds the SwiftUI app on a GitHub‑hosted **macOS** runner and produces an
  unsigned `.ipa`.

```
bmw-g30-hud/
├── sim/navhud/          Module 3+4: nav events, HUD model, translator, renderers, CLI
├── proto/bmwdiag/       Module 1+2: DoIP + UDS (read-only), DID catalogue, mock gateway
├── ios-app/             Module 5: Swift Package (BMWLinkKit) + SwiftUI app skeleton
├── tests/               36 Python unit tests (stdlib only); Swift tests live in ios-app/
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
| A. Apple‑Maps‑on‑HUD | **Partial/blocked** — simulator+translator done; stock‑Apple‑Maps source is impossible, MapKit source is the designed substitute; on‑car output blocked (see below). |
| B. Native BMW iPhone app (ENET) | **Built, not yet installed** — Swift core compiles and passes 17 tests; the SwiftUI app is built by macOS CI. Installing on your phone needs Apple signing (`docs/ios-deployment.md`). Not yet run against the car. |
| C. Safe deployment workflow | **Documented** — `docs/safety.md`, `docs/deployment-and-blockers.md`. |
| D. Custom BMW software platform | **Foundation only** — read‑only live‑value plumbing exists; dashboards/theme deferred. |
| E. GitHub repository | **This repo**, branch `claude/bmw-g30-maps-hud-eyvj50`. |

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
