---
tags: [bmw/g30, reference]
updated: 2026-11-13
---
# Glossary

- **NBT EVO** — the head unit / iDrive 6 computer in the G30.
- **iDrive** — BMW's infotainment system (menus, map, media).
- **ENET** — BMW's Ethernet diagnostic connection (OBD port ↔ USB-C adapter).
- **HSFZ** — BMW's Ethernet diagnostic protocol (TCP 6801). Confirmed on this car.
- **DoIP** — the ISO-standard diagnostic-over-IP protocol (TCP 13400).
- **UDS** — ISO 14229 diagnostic services. This project uses only **read** ones.
- **OBD-II** — the legislated emissions diagnostics (code modes `03`/`07`/`0A`).
- **DID** — Data Identifier: a numbered value you read (e.g. VIN `F190`).
- **DTC** — Diagnostic Trouble Code (a fault code).
- **SVK (F101)** — a module's software/coding version list.
- **DME** — the engine computer (`0x12`).
- **KOMBI** — the instrument cluster (`0x60`). HUD content is coded here.
- **ZGW** — the central gateway (`0x10`).
- **BDC** — the body domain controller (`0x40`).
- **HUD** — the Head-Up Display.
- **Coding** — changing built-in settings (BimmerCode). Reversible. See
  [[iDrive Coding Guide]].
- **Flashing** — replacing a module's software. Not done here.
- **MHD** — the engine tuning app. Out of scope; never modified.
- **BimmerCode / BimmerLink** — apps for coding / live data respectively.
