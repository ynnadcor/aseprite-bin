# Vehicle Safety Requirements & Recovery

The target car is a daily driver. Every decision in this project is ordered by:
**preserve factory function first, add features second.** This file is the
binding safety contract; code and docs defer to it.

## Hard rules (non‑negotiable, enforced where possible in code)

1. **No engine/DME changes.** Nothing here touches the ECU/DME or any engine
   calibration, factory or aftermarket.
2. **No tuning / calibration interaction.** The diagnostic app does not write fueling,
   boost, or any calibration. It cannot — the UDS layer refuses write services.
3. **No safety‑critical systems.** No writes to braking, steering, airbag (ACSM),
   stability control, or their coding.
4. **No whole‑module firmware flashing.** No UDS transfer/programming services exist
   in this codebase (`0x34/0x36/0x37` absent; programming/extended sessions blocked).
5. **No untested binaries on the car.** The simulator and the iOS read‑only app never
   place code on a vehicle module.
6. **No vehicle‑network writes without a vehicle‑specific, reviewed analysis.** The
   HUD‑message emitter (future, on‑head‑unit) is design‑only until such a review and
   your explicit approval.
7. **A file backup is not a recovery plan for a bricked head unit.** We assume only
   BMW/Toyota reflash can recover an unresponsive HU, and plan accordingly.
8. **Document anything that could affect** CarPlay, audio, nav, cameras, or displays.
9. **Protect against interrupted installs / power loss** in any future deployment.
10. **An independently justified recovery procedure is required before any persistent
    vehicle modification.** "It worked for someone on GitHub" is not a recovery plan.

## How the code enforces the read‑only promise (Modules 1 & 2)

- `proto/bmwdiag/uds.py` defines `ALLOWED_SERVICES` = {default‑session, TesterPresent,
  ReadDTCInformation, ReadDataByIdentifier}. Every request builder calls `_guard()`,
  which raises on any SID outside that set. There is **no builder** for Write, Clear,
  Reset, RoutineControl, SecurityAccess, or TransferData.
- Only the **default diagnostic session (0x01)** can be requested. Extended/
  programming sessions — the ones that unlock writes — are rejected.
- Tests (`tests/test_uds.py::TestReadOnlyEnforcement`) assert that a list of write/
  flash SIDs all raise, so a future careless change can't silently add a write path
  without breaking the build.
- **Second layer (Swift app):** each HSFZ/DoIP link (`DiagLink.swift`) checks the
  service ID again before anything is sent, so even a request built without the UDS
  builders can't reach the car. Tests send write/flash/reset SIDs straight to the links
  and assert that nothing arrives at the simulated gateway. The end‑to‑end socket
  tests also check that every request the gateway received was a read service.

- **OBD‑II reads (code scan):** besides those four UDS reads, the app and the
  Python reference allow the four legislated OBD‑II *read* services that every
  generic scanner sends: `01` (current data; only PID `01`, engine light and
  readiness, is used), `03` (stored codes), `07` (pending codes) and `0A`
  (permanent codes). `04` (clear codes) and `08` (control of on‑board systems)
  stay refused; they're in the shared `blocked_services_must_refuse` list, so the
  Python and Swift tests both fail if either becomes sendable.

- **Phone‑only tool** (`tools/bmw_car_test.py`, run in a-Shell): the same
  allowlist, checked inside each HSFZ/DoIP link right before anything is sent;
  only the default session (`10 01`) passes. Its tests send write/flash/reset SIDs
  to both links and assert nothing reaches the simulated gateway, and that every
  request in a full run is a read. It sends exactly the traffic in the table below.

## Evaluated effects of the car test's network traffic

| Traffic | What reaches the car | Effect evaluated |
|---|---|---|
| Discovery broadcast / probe | The standard BMW vehicle‑identification message (HSFZ `0x0011` on UDP 6811, DoIP `0x0001` on UDP 13400), the same message every BMW tool sends | Gateway replies with its VIN/MAC/address. No state change. |
| Opt‑in cable sweep | One ARP request per candidate address (about 250/s, at most about 65,000 over ~4 min) plus the ident message to the one address that exists | ARP requests for other addresses are ignored by the car's network stack; roughly 15 KB/s on a dedicated diagnostic link. User‑started, cancellable, stops at the first answer. |
| Identify | About 10 ReadDataByIdentifier/ReadDTCInformation requests, sent one at a time | Reads only. ECUs that don't answer are skipped after one timeout (no retry loops). |
| Keep‑alive answers | Replies to the gateway's own alive checks | Required by the protocol to keep the session open. |
| Test 2: module scan | One ReadDataByIdentifier F150 sent to BMW's "all modules" address (0xDF) over HSFZ, the identification request BMW tools send at the start of a session | Every module answers once with its variant index. Nothing changes. |
| Test 2: engine values | About 10 ReadDataByIdentifier requests to the engine computer (DME, 0x12): variant index, software list, and standard OBD values (identifiers F4xx) | Reads only: no session change, no security access, nothing written; the MHD tune is not touched. Values the DME doesn't share come back "not supported". |
| Codes tab: code scan (app) | The Test 2 module scan, then one ReadDTCInformation `19 02 FF` per module that answered, then to the engine computer only: OBD‑II `03`, `07`, `0A`, and DID `F401` (or OBD `01 01` if F401 isn't offered) | Reads only, the same requests any scan tool sends; codes are never cleared. If the engine computer doesn't answer the first OBD request, the rest are skipped. Stops at a dropped connection or when you tap Stop. |

What the app never sends: session changes beyond default, security access, routine
control, writes, DTC clearing (UDS `14` or OBD `04`), OBD `08`, ECU reset, or any
transfer/flash service.

**Coding is read, never written.** The app can read a module's coding versions
(SVK/CAFD) during a scan, but it has no way to write coding: the UDS write and
session services that coding needs are not on the allowlist. The **iDrive tab**
is a static guide only — it describes reversible coding changes you make in
**BimmerCode**, and sends nothing to the car itself. Head‑unit software
modification (themes, extra apps) is red tier and out of scope; see
[`idrive-customization.md`](idrive-customization.md).

## Risk tiers for the features you asked about

| Feature | Tier | Why |
|---|---|---|
| Read VIN / versions / DTCs / live values over ENET | **Green** | Read‑only UDS; same class as any scan tool. Reversible (reads nothing‑changes). |
| Nav→HUD **simulator** | **Green** | Pure software; no car. |
| Clearing DTCs, coding changes (BimmerCode‑style) | **Yellow** | Reversible but changes state; **out of scope here** — use your existing coding tools deliberately. |
| On‑head‑unit agent to drive the HUD | **Red** | Requires SSH + filesystem RW on the HU; can affect CarPlay/audio/displays; needs recovery plan + your approval. See `deployment-and-blockers.md`. |
| Any DME/flash/firmware | **Black** | Explicitly forbidden by this project. |

## Recovery posture (for the future Red‑tier work only)

Before *any* persistent head‑unit change is even proposed for your car, this project
requires, in writing and reviewed:

1. A confirmed way to **reach the HU out‑of‑band** (the ENET/SSH path) *after* a
   failed change — i.e. the change must not be able to close its own access path.
2. A **non‑destructive, move‑don't‑overwrite** install style (never overwrite a file
   that is in use; rename aside, copy new, keep the old as an undo).
3. A **power‑stable** environment (engine running or a maintainer/charger) so a
   write can't be interrupted by a low battery.
4. A written **rollback** that restores the prior state from the aside‑renamed files,
   plus the explicit acknowledgement that **if the HU won't boot, only a dealer/BMW
   reflash recovers it** — accepted by you before proceeding.
5. **Your explicit, per‑action approval.** No persistent vehicle change happens
   automatically or as a side effect.

This project will not automate step‑through of a head‑unit jailbreak, and it does not
bundle or reproduce one.
