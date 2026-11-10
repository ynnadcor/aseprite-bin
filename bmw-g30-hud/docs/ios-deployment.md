# iOS Build, Signing & Install — the honest options (iPhone‑only reality)

You want to develop and run your own iOS app **without owning a Mac**. Here's the
real picture, with costs and the exact blockers.

## Build: solved without a Mac (via cloud CI)

Compiling an iOS app needs Apple's toolchain (Xcode), which only runs on macOS. You
don't need to *own* the Mac: **GitHub Actions provides hosted macOS runners**, and for
a **public** repository (this one is public) they cost **$0**.

This repo's workflow (`.github/workflows/bmw-g30-hud-ci.yml`) runs on every push and:

1. runs the Python tests and the Swift package tests (Linux);
2. on a **macOS runner**: runs the Swift package tests (including the
   Network.framework transport), generates the Xcode project with XcodeGen, builds
   the SwiftUI app for the iOS Simulator, and builds an **unsigned device app
   packaged as `BMWLink-unsigned.ipa`** (downloadable from the run's Artifacts).

You can start runs, read logs, and download artifacts from the GitHub app or a phone
browser. **Building is therefore iPhone‑controllable at $0.**

## Install: this is the real blocker

An iPhone runs only apps **signed** for it. The unsigned `.ipa` above must be signed
with an Apple ID before it can be installed. The options:

| Option | Cost | Signing lasts | Needs a computer? | CarPlay nav entitlement? |
|---|---|---|---|---|
| **Free Apple ID (Personal Team)** via Xcode | $0 | **7 days**, then re‑sign | Yes, a Mac running Xcode for each signing | ❌ |
| **Free Apple ID via third‑party re‑signers** (e.g. Sideloadly, AltStore/SideStore) | $0 | **7 days** (same Apple rule) | The common tools need a computer for at least the **initial setup**; SideStore aims to refresh on‑device afterwards. **Verify current requirements before relying on this.** | ❌ |
| **Apple Developer Program + TestFlight** | **$99/yr** | 90‑day TestFlight builds, re‑uploaded by CI | **No.** CI signs and uploads; you install from the TestFlight app on the iPhone | ✅ can be requested |

So, precisely:
- **At $0 there is no fully computer‑free install path** that we can verify today. The
  $0 routes need a computer at least occasionally (Xcode) or for setup (re‑signers),
  and they re‑sign every 7 days.
- **The only fully iPhone‑only path is $99/yr**: Developer Program → CI signs with a
  distribution certificate stored as a GitHub secret → uploads to TestFlight → you
  install and update over the air from the TestFlight app. That's also the path that
  unlocks the CarPlay navigation entitlement (`navigation-data.md`).

> **Spending:** we will **not** enroll in anything or spend money without your
> explicit go‑ahead. Signing keys and Apple credentials would go into **GitHub
> encrypted secrets**, never into chat or the repository.

## Recommended sequencing (minimizes spend)

1. **Now, $0 (done):** core logic built and tested in the cloud; app compiled by CI.
2. **Next, $0:** borrow a Mac **once** (or a friend's), install the app on your iPhone
   with your **free** Apple ID, and run the **read‑only Identify** against the car.
   This validates the whole ENET → DoIP → UDS chain before any money is spent.
3. **Only if it proves useful:** the $99/yr program for computer‑free TestFlight
   updates and, if you choose the CarPlay route, the navigation entitlement. We'll
   ask first.

## What runs where (nothing overstated)

| Component | Verified where | Status |
|---|---|---|
| `proto/bmwdiag` (Python DoIP/UDS) | this cloud dev env | ✅ tests pass |
| `sim/navhud` (Python nav→HUD) | this cloud dev env | ✅ tests pass |
| `ios-app/BMWLinkKit` package (BMWLinkKit + NavHUDKit) | Swift 6.0.3 Linux container (this env) and Swift 6.3.3 on the macOS CI runner | ✅ builds, all XCTests pass |
| Socket transport + HSFZ/DoIP links | Linux container and macOS CI, end to end over real sockets | ✅ tests pass; not yet used against a car |
| `MapKitRouteSource` (MapKit) | macOS CI runner | compiled by CI; not yet run against live Apple routing |
| SwiftUI app | macOS CI runner, Xcode 26.6 (Simulator + unsigned device build) | ✅ `BUILD SUCCEEDED` (CI run #1); see the latest run for the HUD tab |
| App on your iPhone | needs signing (above) | ❌ not yet |
| App against your car | needs your iPhone + ENET | ❌ not yet (Stage 5) |
