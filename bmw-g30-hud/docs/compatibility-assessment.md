# Stage 1 — Compatibility & Feasibility Assessment

**Vehicle:** 2018 BMW 540i (G30), RWD, B58 (gen 1), NBT EVO head unit, iDrive 6,
factory HUD, factory wireless Apple CarPlay, 6WA-class digital cluster.
**Available hardware:** iPhone 16 (USB‑C) → USB‑C/Ethernet adapter → BMW ENET
(OBD→Ethernet) cable. Coding over this path already works for the owner.

Status legend: **✅ Verified** (evidence cited) · **🧪 Experimental** (demonstrated
by others, not yet on this car) · **❓ Unknown** (needs a capture on the real car)
· **⛔ Not feasible** through any documented/legal interface.

---

## 1. Executive summary

| Goal | Verdict | One-line reason |
|---|---|---|
| Turn‑by‑turn **from the stock Apple Maps app** onto the HUD | ❓ Unproven | Can't be read on the phone (no API). CarPlay *can* send it to head units that request it (newer BMWs do), but NBT EVO doesn't as delivered. Making it do so needs head‑unit modification and a confidential Apple protocol. |
| Turn‑by‑turn **from a custom MapKit/CarPlay nav app** onto the HUD | 🧪 Experimental | The maneuver stream is legally accessible inside your own app; the hard part is getting it onto the HUD. |
| **Nav arrows on a G‑chassis NBT EVO HUD/KOMBI at all** | ✅ Verified (others) | The Sq00ky NBT‑AAD project renders AA nav arrows on NBT EVO HUD/KOMBI; its confirmed list includes a **G31 5‑Series** (same head unit family as your G30). |
| **Read‑only diagnostics over your iPhone+ENET** (VIN, versions, DTCs, live B58 values) | ✅ Verified feasible | Standard DoIP/UDS over the ENET cable; you already run coding over this exact path. Implemented + tested in this repo (mock). |
| **Custom iDrive 6 apps / M5‑Lite theme** | 🧪 Experimental | NBT‑AAD ships an iDrive6 RHMI plugin, proving third‑party iDrive apps are possible; scope/stability are the question. |
| **iPhone‑only build & install of your own iOS app** | 🧪 Partly | A free Apple ID signs a 7‑day app, but **building an iOS binary needs macOS/Xcode** — not doable purely on‑device. See `ios-deployment.md`. |

**Bottom line for your #1 goal:** every route to arrows on *your* HUD goes through
**software running on the head unit** that sends the guidance messages the factory
nav uses. That's the real blocker: it means modifying the head unit (see
`deployment-and-blockers.md`). The open question is only where the guidance comes from:

1. **Stock Apple Maps, received by the head unit over CarPlay.** CarPlay already sends
   maneuver data to head units that ask for it (newer BMWs show Apple Maps on the HUD
   this way). NBT EVO doesn't ask as delivered, and the protocol is
   Apple‑confidential. This is the most "native" route, unproven on NBT EVO, and the
   hardest to do cleanly.
2. **Your own MapKit/CarPlay nav app.** Legal, documented, fully under your control,
   and a different app from Apple Maps (with Apple's routing).
3. **Android Auto (Google Maps/Waze)** through the community NBT‑AAD project. Reported
   working on the HUD, but it isn't Apple Maps.

What's **not** possible is reading the Apple Maps app's directions **on the phone**:
iOS has no API for it. Details in `navigation-data.md`.

---

## 2. Head unit & displays

### 2.1 NBT EVO — ✅ compatible platform
- Your 2018 G30 ships **NBT EVO** (iDrive 6 / "ID6"). This is the head‑unit
  generation the Sq00ky project targets.
- NBT EVO is a **QNX / ARMv7LE** system. Third‑party native code for it is built
  with the QNX 6.5 toolchain (the reference project's `build.sh` uses a QNX 6.5
  SDP Docker image, `qcc`, `armv7le`). This is not an Android/MGU platform.
- **Evidence of same‑family compatibility:** the project's `requirements.md`
  "confirmed working" table lists **`NBTevo_Y24073J` on a BMW 5‑Series G31 (2017)**
  and multiple F‑chassis 5/3/4‑series. The G31 is the wagon sibling of your G30
  sedan with the **same NBT EVO unit** — strong evidence the head‑unit platform in
  your car can run this class of software. (Your exact build string is readable at
  *Navigation → Settings → Position and software version*; our iOS app also reads
  it over ENET as DID `0xF195`.)

### 2.2 Factory HUD + 6WA cluster — 🧪 arrows demonstrated, Apple-sourced data unproven
- On a factory BMW, the **HUD and cluster render navigation guidance from messages
  on the car's internal bus** (historically MOST / internal IPC), produced by the
  head unit's own navigation. The windshield HUD is **not** a general framebuffer —
  it shows a *fixed catalogue* of maneuver pictograms + a distance + a short label.
  No arbitrary moving map, no custom animations. (Our `hud_model.py` encodes exactly
  this constraint so we never promise pixels the panel can't draw.)
- The reference project demonstrates an **on‑head‑unit app emitting those guidance
  messages** so AA directions appear on the HUD/KOMBI (roadmap: *"proof of concept
  is working, navigation arrows are being shown on the HUD/KOMBI"*; source tree has
  `src/cluster/hud6wa_display`, `nav_core`, `nav_msg`, and a MOST client in
  `src/most/`). **6WA** is the BMW extended digital cluster family your G30 uses.
- **What is NOT proven:** driving that same path from **Apple Maps** data, because
  the data source problem (below) is unsolved. The *rendering* path is credible;
  the *Apple* data feeding it is the gap.

---

## 3. The navigation data source — the crux

This is where "Apple Maps on the HUD" lives or dies. Detailed analysis in
`navigation-data.md`; summary:

| Candidate source | Accessible? | Notes |
|---|---|---|
| Stock **Apple Maps app** guidance, read **on the phone** by another app | ⛔ No | No public iOS API lets one app read another's navigation. Getting it anyway would mean modifying iOS (jailbreak), which is out of scope and fragile. |
| Stock **Apple Maps**, received by the **head unit** via CarPlay's cluster/HUD guidance | ❓ In principle | CarPlay sends maneuver data to head units that request it (iOS 17.4 extended it with maneuver/junction/lane types). Newer BMWs use it; NBT EVO doesn't as delivered. Head‑unit side is Apple‑confidential (MFi). |
| **Your own iOS nav app** via **MapKit `MKDirections`** | ✅ Yes | Apple's *own* routing engine. You get a structured `MKRoute.steps` / maneuver stream legally, in your process. This is "Apple Maps data" in the routing sense. |
| **Your own CarPlay navigation app** (`CPMapTemplate`/`CPManeuver`) | ✅ Yes (entitlement) | Apple grants a **CarPlay navigation** entitlement to nav apps; you then own the maneuver + ETA stream and render on the CarPlay screen. Entitlement approval required. |
| **Android Auto** nav (Google Maps/Waze) on an AA‑enabled HU | 🧪 Yes | This is literally what NBT‑AAD forwards to the HUD today — but it's *Android Auto*, and needs the head‑unit modification. |

**Conclusion:** the guidance source we can build **today, with public documentation**
is a **custom app using Apple MapKit / CarPlay navigation**. Receiving the stock
Apple Maps app's guidance on the head unit is possible in principle but unproven on
NBT EVO. Module 3 is built around a source‑neutral abstraction, so either can be
plugged in later without changing the translator or its tests.

---

## 4. iPhone + ENET connection (diagnostics path) — ✅ feasible, implemented here

- The ENET cable presents the car's **Ethernet** to the iPhone via the USB‑C
  adapter. Two distinct things live on that wire:
  1. **Diagnostics** to the central gateway (ZGW) and modules: VIN, software
     versions, DTCs, live values. **Read‑only and safe.** BMW uses one of two
     protocols here: **HSFZ** (TCP 6801, F‑series and most G‑series) or **DoIP**
     (ISO 13400, TCP 13400, newer cars). No source says which a 2018 G30 uses, but
     HSFZ is most likely. The app supports both and detects which one answers.
  2. **Direct Ethernet to the head unit** at a link‑local `169.254.x.x` address —
     this is the path the community SSH tooling uses. (Relevant only to deployment,
     not to our read‑only app.)
- **You already run coding over this exact iPhone→USB‑C→ENET→OBD path**, which is
  our strongest evidence the wired link works from your phone. ✅
- **iOS app specifics — ❓ to verify on device:** the app uses plain BSD sockets
  pinned to the USB Ethernet interface. Expected caveats: iOS shows a **Local Network
  permission** prompt; the car's address is self‑assigned (`169.254.x.x`) and must be
  discovered. **Finding:** since iOS 14.5, *sending a UDP broadcast* (how BMW tools
  find the car) requires Apple's **multicast networking entitlement**, which needs a
  paid developer account and Apple's approval. Without it the app finds the car by a
  typed address, a remembered one, or a paced unicast sweep of the cable. Unicast and
  TCP need no entitlement.
- **Implemented now (Modules 1 & 2):** a strictly read‑only HSFZ + DoIP + UDS stack
  in Swift (Python reference codec), tested end to end over real sockets against a
  simulated gateway, in both languages for the wire format.
  It can only ever issue read services (ReadDataByIdentifier, ReadDTC, TesterPresent,
  default session) — write/flash/clear/routine services are refused in code.

---

## 5. Wireless Apple CarPlay — ✅ present; its guidance channel is unused on NBT EVO

Your wireless CarPlay works and should be left exactly as it is. On your car CarPlay
is a **sink**: the car shows the phone's screen and plays its audio. CarPlay *does*
have a channel that sends turn‑by‑turn data to cars that request it (that's how newer
BMWs show Apple Maps on the HUD), but your NBT EVO doesn't use it. Nothing in this
project modifies, intercepts, or degrades the working CarPlay session. (The reference
project reuses CarPlay's Wi‑Fi link to carry Android Auto, which is an AA concern, not
something the read‑only app or the MapKit approach needs.)

---

## 6. Supra NBT EVO vs. your G30 — the differences that matter

The Toyota **Supra (J29)** is built on BMW architecture and uses a **BMW NBT EVO**
head unit and iDrive — which is why a "Supra" project applies to BMWs at all, and
why its confirmed list is mostly actual BMWs. Practical differences for a G30:

- **Cluster type:** the project carries both Supra `j29_*` cluster code **and** BMW
  `hud6wa_*` code. Your G30 is the **6WA/BMW** path, which the project already
  targets. ✅ closer match than the Supra path.
- **HMI skin / coding:** menu entries, texts, and some FDL coding differ between
  Supra and BMW; cosmetic, not architectural.
- **Confirmed BMW G‑chassis:** G31 5‑Series and G01 X3 appear in the working list —
  same NBT EVO generation as the G30. ❓ Your exact `NBTevo_*` build must still be
  cross‑checked (readable via our app or in the iDrive menu).

---

## 7. What this means for the build plan

- **Do now, safely, no car risk:** the read‑only ENET diagnostic app and the
  navigation→HUD **simulator** — both implemented and tested in this repo.
- **Feasible with real engineering + a reviewed deployment:** an on‑head‑unit agent
  that turns a maneuver stream into factory HUD guidance messages. This is credible
  because NBT‑AAD does the analogous thing, but it requires modifying the head unit
  (SSH + filesystem RW), which is the genuine blocker and is **gated on your explicit
  approval and an independent recovery plan** (`deployment-and-blockers.md`).
- **Not promised:** stock Apple Maps guidance on your HUD. It can't be read on the
  phone, and receiving it on the head unit is unproven on NBT EVO. We won't present
  it as working until it's demonstrated on a car. The architecture accepts it *or* a
  custom MapKit/CarPlay source without changes.

---

## 8. Open items that need a capture on *your* car (read‑only, low‑risk)

1. Exact `NBTevo_*` software build string (DID `0xF195`, or iDrive menu).
2. Head‑unit logical address + whether it answers DoIP routing activation from the
   iPhone+ENET path (our app's "Identify" screen).
3. Real B58 live‑value DIDs/measurement blocks + scaling (ours are clearly marked
   **UNVERIFIED** placeholders until captured).
4. Whether iOS presents the `169.254.x.x` Ethernet interface to a `Network.framework`
   socket in your adapter setup.

None of these require any modification to the car — they are reads. They are the
"Stage 5" user‑dependent steps, and each is individually optional. Step‑by‑step:
[`stage5-vehicle-capture.md`](stage5-vehicle-capture.md).

---

## 9. Prior art checked this session

### Phone‑based installer (Discussion #109) — Android only
- An **Android** app by a community developer (BimmerTuner, published from a fork
  of the Sq00ky repo), **not** by the NBT‑AAD maintainer. It installs and updates
  NBT‑AAD on an NBT EVO head unit from a phone, over ENET + a USB‑C Ethernet adapter.
- **No iOS version**, and nothing in the thread says it works from an iPhone.
- License **unconfirmed**. The fork has a LICENSE file we couldn't read in full, and
  a collaborator noted the app's source hadn't been published yet.
- It opens SSH on the head unit through a third‑party relay, which means it performs
  the head‑unit unlock. Reported problems: unlock attempts can stop getting
  responses until the car sleeps (~20 min) or the battery is disconnected, and an
  iDrive 5 car (G11) didn't work. Reported successes: a Supra owner says Waze
  turn‑by‑turn shows on the cluster and HUD. A G30 success appears only in a
  summarized part of the page and is **unverified**.
- **What it tells us:** (a) phone + ENET + USB‑C adapter is a working physical link to
  NBT EVO; (b) the head unit answers at diagnostic address **0x63**, which matches
  `HEADUNIT_ADDRESS` in this repo; (c) the unlock uses a diagnostic **routine**
  (UDS 0x31), exactly the class of service our read‑only client refuses. Porting it
  to iOS would mean rebuilding someone else's head‑unit unlock path, which this
  project doesn't do.

### Wayglass (wayglass.info/hud) — not verified
- The site is blocked by this cloud environment's network policy, and web search
  returned nothing about it. Its claims (Apple/Google Maps on NBT EVO / G‑series
  HUDs) remain **unverified**. If it does put the *stock* Apple Maps guidance on an
  NBT EVO HUD, the CarPlay cluster‑guidance route in Section 3 is the likely
  mechanism. That's an inference, not a finding.
