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
- ✅ HSFZ **and** DoIP links with real‑gateway behaviour (acks, alive checks, response pending); read‑only enforced twice
- ✅ Gateway discovery (broadcast / probe / opt‑in sweep) and a shareable, redacted session log
- ✅ End‑to‑end tests over real TCP/UDP sockets against a simulated gateway
- ✅ Guided car‑test screen with a simulated‑car practice mode; app builds on macOS CI
- 🔒 Install on your iPhone: [`docs/install-on-iphone.md`](docs/install-on-iphone.md) (free with a borrowed computer, or $99 TestFlight)
- ✅ First read‑only car test (phone‑only tool, [`docs/phone-only-car-test.md`](docs/phone-only-car-test.md)): HSFZ confirmed; gateway, head unit and cluster answered; HUD not at 0x3D
- ⏳ Test 2 (needs your OK): find every module (incl. the HUD) and try live engine values from the DME, read‑only
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
2. **Install the app** ([`docs/install-on-iphone.md`](docs/install-on-iphone.md)): borrow a computer once (free, 7‑day signing), or the $99/yr developer program (TestFlight, no computer; workflow prepared). We won't spend without your OK.
3. ~~Run the car test~~ ✅ done from the phone (2026-11-11). Next: say yes or no to Test 2.
