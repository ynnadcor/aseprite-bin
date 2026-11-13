---
tags: [bmw/g30, diagnostics]
updated: 2026-11-13
---
# Fault Code Combinations

The [[Fault Code Reader]] reads codes **together**, not one by one, because a set
of codes often points to one cause. Examples the app recognises:

- **Misfire + coil on the same cylinder** (e.g. P0302 + P0352) → that coil.
- **Several misfires** → look for a shared cause (plugs, boost/vacuum leak, fuel)
  before replacing parts.
- **Misfires + catalytic-converter code** → fix the misfires first; they
  overheat the converter.
- **Lean at idle vs lean under load** → a vacuum leak vs fuel delivery.
- **Underboost + signs of a leak** (P0299 + P2279/P0171) → boost leak; pressure-test.
- **Several modules lost communication with the same module** → that module (or
  its power/fuse), not the ones reporting it.
- **Old codes in many modules** → usually one battery event (flat battery, jump
  start), likely history.

Each finding shows what to check first and what it leads to if ignored, ranked
most-urgent first (engine protection like overheating/oil pressure first).
