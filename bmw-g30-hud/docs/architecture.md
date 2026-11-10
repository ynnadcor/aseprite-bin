# Architecture

Modular by design: independent pieces with narrow contracts, so a failure or an
unknown in one module never forces a rewrite of another. Status is marked per module.

```
                        ┌──────────────────────────────────────────┐
   iPhone (your app)    │  Module 5: iOS app (SwiftUI)              │
                        │   - read‑only diagnostics UI             │
                        │   - (later) nav source + config          │
                        └───────────────┬───────────────┬──────────┘
                                        │               │
                      ┌─────────────────▼──┐   ┌─────────▼─────────────────┐
   Module 1/2         │ Vehicle connection │   │ Module 3: Navigation data │
   (DoIP/UDS,         │  + BMW protocols   │   │  NavEvent abstraction     │
    read‑only)        │  (ENET transport)  │   │  (sim today; MapKit next) │
                      └─────────┬──────────┘   └─────────┬─────────────────┘
                                │                        │
                        ┌───────▼───────┐        ┌───────▼─────────┐
   Module 7: tests ◄────┤ mock gateway  │        │ Module 4:       │
   + recovery docs      │ (no car)      │        │ HUD translation │
                        └───────────────┘        │ → HudFrame      │
                                                 └───────┬─────────┘
                                                         │ (renderers: ascii/svg today)
                                                         ▼
                                      ┌──────────────────────────────┐
                                      │ on‑head‑unit agent (BLOCKER,  │
                                      │ design‑only) → factory HUD    │
                                      └──────────────────────────────┘
   Module 6: custom iDrive apps — future, after the primary goal is proven.
```

## Modules

### Module 1 — Vehicle Connection · ✅ implemented (mock), ❓ on‑car verify
ENET transport + DoIP session: vehicle identification, routing activation, diagnostic
message framing. `proto/bmwdiag/doip.py`, `transport.py`. Swift mirror in
`ios-app/BMWLinkKit`. A `MockEnetServer` stands in for the car in tests.

### Module 2 — BMW Protocols (read‑only) · ✅ implemented (mock)
UDS (ISO 14229) **read‑only** services only, enforced in code (`uds.py`,
`ALLOWED_SERVICES`). DID catalogue in `dids.py` (standard DIDs verified; B58 live‑value
DIDs clearly marked UNVERIFIED pending an on‑car capture).

### Module 3 — Navigation Data · ✅ simulated source; ✅ Apple MapKit source built (not yet run live)
Swift: `NavHUDKit` (`NavEvent`, `ManeuverClassifier`, `RouteGuidance`,
`MapKitRouteSource`, `RouteTracker`, `DemoRoute`). MapKit steps carry no maneuver type, so maneuvers
are classified from instruction text plus polyline turn angles
(`navigation-data.md`).
Vendor‑neutral `NavEvent` (`sim/navhud/nav_events.py`). Simulated routes today; the
MapKit/CarPlay adapter is specified in `navigation-data.md` and drops in behind the
same type. **We do not claim access to the stock Apple Maps app's guidance**: it
can't be read on the phone, and receiving it on the head unit is unproven on NBT EVO.

### Module 4 — HUD Translation · ✅ implemented + tested (Python and Swift)
The Swift `Translator` is a line‑for‑line port, proven equal to the Python reference
on every case in `test-vectors/hud_golden.json` (54 events × 2 displays).
`Translator` turns `NavEvent` → `HudFrame` for a given sink profile (`G30_HUD_PROFILE`,
`G30_KOMBI_PROFILE`), degrading gracefully to each panel's real limits. ASCII + SVG
renderers let you inspect output with no car. **No vehicle‑network transmission.**

### Module 5 — iOS Application · ✅ core compiled + tested; app built in macOS CI
Swift Package `BMWLinkKit` (DoIP/UDS/transport/mock) + a SwiftUI app target for the
read‑only "Identify / Diagnostics" screens. Mirrors the Python core and shares the
JSON test vectors. The app has two tabs: **Diagnostics** (read‑only ENET) and
**HUD** (preview of HUD/cluster frames for the demo route or an Apple MapKit route,
played as a simulated drive). It's generated with XcodeGen and compiled on a
GitHub‑hosted macOS runner. Installing it on a phone needs Apple signing (see
`ios-deployment.md`).

### Module 6 — Custom iDrive Applications · ⏳ future
Performance widgets (boost/oil/IAT/coolant/load, G‑force, timers), info dashboards,
M5‑Lite theme. Deferred until the primary HUD goal is proven and only via the least
invasive mechanism (companion‑app rendering vs. on‑HU plugin TBD per `safety.md`).

### Module 7 — Testing & Recovery · ✅ ongoing
`tests/` (40 Python tests), `ios-app/BMWLinkKit/Tests` (46 Swift tests across
BMWLinkKit and NavHUDKit), shared golden `test-vectors/` that keep Python and Swift
byte‑identical, CI in `.github/workflows/bmw-g30-hud-ci.yml`, and the recovery
posture in `safety.md`.

## Key design decisions

- **Read‑only is a code property, not a convention.** The UDS layer cannot emit a
  write; tests assert it.
- **One abstraction boundary for nav** so the (hard, unsolved) data‑source question
  can be answered later without disturbing the tested translator/renderers.
- **The HUD contract is tiny on purpose** (`HudFrame`): when an on‑head‑unit agent is
  eventually justified, its input is a handful of auditable fields, not an open API.
- **Python reference + Swift port share golden vectors** so the on‑phone code and the
  verifiable cloud code can't silently diverge on the wire format.
