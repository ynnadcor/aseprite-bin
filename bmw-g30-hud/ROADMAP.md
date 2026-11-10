# Roadmap & milestones

Status legend: ✅ done and verified · 🟡 in progress / partly verified · ⏳ not started
· 🔒 waiting on a decision or action from the owner · ⛔ blocked.

Every "verified" claim refers to tests or CI runs on this branch, never to a car,
unless it says otherwise.

## M0: Feasibility & safety baseline ✅
- ✅ Compatibility assessment: [`docs/compatibility-assessment.md`](docs/compatibility-assessment.md)
- ✅ Navigation‑data analysis, incl. the CarPlay correction: [`docs/navigation-data.md`](docs/navigation-data.md)
- ✅ Safety contract and recovery posture: [`docs/safety.md`](docs/safety.md)
- ✅ Prior art reviewed: NBT‑AAD source; Discussion #109 installer. Wayglass is ⛔ unreachable from this environment.

## M1: Navigation → HUD pipeline (simulated) ✅
- ✅ `NavEvent` model and G30 HUD/KOMBI profiles (Python + Swift)
- ✅ Translator, golden‑tested so Python and Swift are byte‑identical
- ✅ Visual storyboards (HTML/SVG), published as a CI artifact

## M2: Read‑only diagnostics app 🟡
- ✅ DoIP + UDS read‑only stack, refusing every write service (Python + Swift)
- ✅ SwiftUI app builds on macOS CI (Simulator + unsigned device `.ipa`)
- 🔒 Install on your iPhone. Needs Apple signing: [`docs/ios-deployment.md`](docs/ios-deployment.md)
- 🔒 First read‑only "Identify" against the car (Stage 5)
- ⏳ Confirm the B58 live‑value identifiers and scaling on the car

## M3: Apple MapKit navigation source 🟡
- ✅ `MapKitRouteSource`: place search and driving route (compiled by CI)
- ✅ `ManeuverClassifier` (instruction text plus turn geometry); `RouteGuidance`; `RouteTracker` (GPS map‑matching)
- ✅ HUD tab: preview a demo route or an Apple route as a simulated drive
- ⏳ Run against live Apple routing (first app launch with network access)
- ⏳ Connect `RouteTracker` to the phone's GPS (live mode)
- 🔒 CarPlay navigation entitlement (paid developer program; owner's decision)

## M4: Vehicle characterization (Stage 5, read‑only) 🔒
- 🔒 Part A of [`docs/stage5-vehicle-capture.md`](docs/stage5-vehicle-capture.md): build string, cluster type, factory‑nav‑on‑HUD and CarPlay baselines
- ⏳ Cross‑check your `NBTevo_*` build against the community's known‑good and known‑bad builds

## M5: On‑car HUD output ⛔ (design only)
- ⛔ Needs software on the head unit (QNX/armv7le) that emits the HUD guidance
  messages, and that means modifying the head unit. Red tier per `safety.md`.
- Before anything happens here: a vehicle‑specific safety review, an independent
  recovery plan, and your explicit approval of each step.
- Open research: can NBT EVO receive CarPlay's cluster guidance (stock Apple Maps), or
  only guidance from our own app? See `navigation-data.md`.

## M6: Custom iDrive platform ⏳
- ⏳ Performance dashboard (boost, oil/coolant/IAT, load, G‑force, timers): companion app first
- ⏳ M5‑Lite‑style theme and iDrive apps: only after M5 is settled, via the least invasive mechanism

## What needs you, in order
1. **Stage 5 Part A** (5 minutes, no tools): send the head‑unit build string and answers A2–A5.
2. **Decide how to install the app on your iPhone:** borrow a Mac once (free, 7‑day signing), or the $99/yr developer program (TestFlight, no computer). We won't spend without your OK.
