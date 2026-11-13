---
tags: [bmw/g30, safety]
updated: 2026-11-13
---
# Safety and Boundaries

The non-negotiable rules for this project. They're enforced in code where
possible, not just promised.

## Hard rules
- **Read-only to the car by default.** The diagnostics layer can only send a
  small allowlist of UDS/OBD **read** services (`22`, `19`, `3E`, `10 01`, and
  OBD `01/03/07/0A`). Writes, DTC clearing (`14`/OBD `04`), routines, flashing
  and security access are not buildable and are rejected before anything is sent.
- **No engine/tune changes.** The DME and MHD calibration are never modified.
- **No safety-system changes.** Nothing touches brakes, airbags, steering or
  stability control.
- **Coding is read, never written by the app.** The app can read coding
  versions; **you** apply any change in BimmerCode. See [[iDrive Coding Guide]].
- **No head-unit unlock.** The project won't script, package or run the head
  unit exploit. See [[Head Unit Unlock Briefing]].
- **Ask first** before: spending money, installing software on the car, changing
  coding, flashing, or any persistent vehicle change.
- **No personal data in the public repo:** no VIN, serials, MAC, Apple ID.

## Why read-only matters
A read can't change state; it's the same class of traffic any scan tool sends.
The guarantee is a property of the code (no write path exists), checked by tests
on both the Python reference and the Swift app.
