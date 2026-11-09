# BMW Link — iOS app (Module 5)

A **read‑only** BMW diagnostic app for iPhone that talks to the car over the wired
ENET cable (iPhone → USB‑C Ethernet adapter → ENET → OBD). It identifies the vehicle
(VIN, head‑unit software build, hardware number), lists fault codes, and shows a
small live‑values panel. It **cannot** write, code, clear codes, or flash anything:
the UDS layer refuses every non‑read service (see `../docs/safety.md`).

```
ios-app/
├── BMWLinkKit/          Swift Package: DoIP + UDS (read-only), DID catalogue,
│                        MockEnetServer, ENetTransport (Network.framework)
├── BMWLinkApp/          SwiftUI app sources (ContentView, view model, @main)
└── project.yml          XcodeGen spec -> generates BMWLink.xcodeproj
```

## What has actually been verified

| Piece | Verified how | Result |
|---|---|---|
| `BMWLinkKit` core (DoIP, UDS, mock, client, DIDs) | `swift test` in the official **Swift 6.0.3 Linux** container | ✅ builds, **17/17 XCTest pass** |
| Same wire format as the Python reference | both suites assert the shared `../test-vectors/doip_uds_vectors.json` | ✅ |
| `ENetTransport` (Network.framework) | macOS CI job (`swift test` on macOS) | ⏳ runs in GitHub Actions — see the CI status |
| SwiftUI app compiles for iOS | macOS CI job: XcodeGen + `xcodebuild` (iOS Simulator) | ⏳ runs in GitHub Actions |
| Real car connection | needs your iPhone + ENET cable | ❓ not yet — Stage 5 |

Nothing here is claimed to have run against a vehicle.

## Building without owning a Mac

Every push that touches `bmw-g30-hud/` runs **`.github/workflows/bmw-g30-hud-ci.yml`**
on GitHub‑hosted runners (free for this public repo):

1. Python + Swift‑Linux tests.
2. On a **macOS runner**: package tests, `xcodegen generate`, an iOS Simulator build,
   and an **unsigned device build packaged as `BMWLink-unsigned.ipa`** (downloadable
   from the run's *Artifacts*).

An unsigned `.ipa` **cannot be installed as‑is**. It must be signed with an Apple ID
first — see `../docs/ios-deployment.md` for the options and their real limits (free
Apple ID = 7‑day signing; $99/yr program = 1‑year signing + TestFlight).

## Building with a Mac (if you ever have one)

```bash
brew install xcodegen
cd bmw-g30-hud/ios-app
xcodegen generate
open BMWLink.xcodeproj   # pick your Personal Team under Signing, run on your iPhone
```

## Using it

- **Mock mode** (default): tap *Identify* — everything runs against the built‑in mock
  gateway. Good for checking the UI with no car.
- **Real car mode** (Stage 5, read‑only): plug in the USB‑C Ethernet adapter + ENET
  cable, ignition on, toggle *Use real car*, enter the gateway/head‑unit IP, tap
  *Identify*. iOS will ask for **Local Network** permission the first time — allow it.
  The B58 live values are shown in orange as **UNVERIFIED** until their identifiers and
  scaling are confirmed on your car.
