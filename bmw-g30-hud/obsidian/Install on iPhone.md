---
tags: [bmw/g30, app, install]
updated: 2026-11-13
---
# Install on iPhone (SideStore)

The app ("BMW Link") is built by CI as an unsigned `.ipa` and published to a
rolling GitHub pre-release with a SideStore source, so it updates from the phone.

## Already set up (this project)
- **SideStore** installed (via iloader once on a computer), pairing file set,
  anisette worked around with Nightly.
- Add the source once:
  `…/releases/download/bmwlink-latest/sidestore-source.json`
- New builds appear as **updates**: SideStore → **My Apps** → **Update**
  (keep LocalDevVPN on; refresh weekly).

## Free alternative (no SideStore)
Sideload the `.ipa` with Sideloadly + a free Apple ID (7-day signing, 3-app
limit). Needs a computer each time.

## Phone-only car test (no app at all)
`tools/bmw_car_test.py` runs in the **a-Shell** app — the read-only test and
Test 2, free. See `docs/phone-only-car-test.md`.

Related: [[Status and Roadmap]]
