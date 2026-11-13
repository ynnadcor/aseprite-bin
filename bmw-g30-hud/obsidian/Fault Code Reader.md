---
tags: [bmw/g30, app, diagnostics]
updated: 2026-11-13
---
# Fault Code Reader (Codes tab)

Scan the whole car for fault codes and understand them. Read-only — it never
clears codes.

## What a scan does
1. Finds every module with one request to all of them.
2. Reads each module's fault memory (`19 02 FF`).
3. Reads the engine computer's OBD-II codes (modes `03`/`07`/`0A`) and the
   engine-light / inspection-readiness status.

## Tap a code → you get
- What's wrong, in plain English.
- Can I keep driving? (colour-coded urgency)
- Most likely causes, ranked.
- What to check first (cheapest first).
- What it leads to if ignored.
- Related findings — see [[Fault Code Combinations]].
- The exact status bits, a web-search button, and a notes field (kept on phone).

## Coverage
- **156 generic OBD-II codes** (P/C/B/U) explained fully. These mean the
  same on every car (SAE J2012).
- **BMW's own 6-digit codes** have no public text, so they're explained by the
  module that stored them (what it does, how urgent, a search button). MHD /
  BimmerLink show BMW's wording for engine codes.

## "Not tested yet"
BMW modules report most of their list as "not tested yet" — that's normal, not a
fault, so the app hides those.

Related: [[Car Test and Test 2]] · [[Glossary]]
