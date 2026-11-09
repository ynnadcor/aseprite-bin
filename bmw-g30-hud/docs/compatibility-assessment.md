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
| Turn‑by‑turn **from the stock Apple Maps app** (via CarPlay) onto the HUD | ⛔ Not feasible | iOS exposes no API to read the Apple Maps app's live guidance; CarPlay does not surface it. |
| Turn‑by‑turn **from a custom MapKit/CarPlay nav app** onto the HUD | 🧪 Experimental | The maneuver stream is legally accessible inside your own app; the hard part is getting it onto the HUD. |
| **Nav arrows on a G‑chassis NBT EVO HUD/KOMBI at all** | ✅ Verified (others) | The Sq00ky NBT‑AAD project renders AA nav arrows on NBT EVO HUD/KOMBI; its confirmed list includes a **G31 5‑Series** (same head unit family as your G30). |
| **Read‑only diagnostics over your iPhone+ENET** (VIN, versions, DTCs, live B58 values) | ✅ Verified feasible | Standard DoIP/UDS over the ENET cable; you already run coding over this exact path. Implemented + tested in this repo (mock). |
| **Custom iDrive 6 apps / M5‑Lite theme** | 🧪 Experimental | NBT‑AAD ships an iDrive6 RHMI plugin, proving third‑party iDrive apps are possible; scope/stability are the question. |
| **iPhone‑only build & install of your own iOS app** | 🧪 Partly | A free Apple ID signs a 7‑day app, but **building an iOS binary needs macOS/Xcode** — not doable purely on‑device. See `ios-deployment.md`. |

**Bottom line for your #1 goal:** "Apple Maps on the HUD" in the literal sense
(the stock Apple Maps app's directions, pulled off CarPlay) is **not achievable**
through any supported or legal interface — the data simply isn't exposed by iOS.
What *is* achievable is **equivalent functionality**: a custom navigation app
(using Apple's own MapKit routing) whose maneuvers are forwarded to an on‑head‑unit
agent that emits the same bus messages the factory nav uses to drive the HUD. That
on‑head‑unit agent is the same class of software as NBT‑AAD, and it is the real
blocker (it requires modifying the head unit — see `deployment-and-blockers.md`).

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
| Stock **Apple Maps app** guidance, read off the phone | ⛔ No | No public iOS API; CarPlay does not expose the active app's turn list to third parties. Scraping it would require modifying iOS (jailbreak) — out of scope and fragile. |
| Stock **Apple Maps on CarPlay**, read off the head unit | ⛔ No | CarPlay video is an encoded H.264 stream to the HU; maneuvers are not delivered as structured data the HU may repurpose. |
| **Your own iOS nav app** via **MapKit `MKDirections`** | ✅ Yes | Apple's *own* routing engine. You get a structured `MKRoute.steps` / maneuver stream legally, in your process. This is "Apple Maps data" in the routing sense. |
| **Your own CarPlay navigation app** (`CPMapTemplate`/`CPManeuver`) | ✅ Yes (entitlement) | Apple grants a **CarPlay navigation** entitlement to nav apps; you then own the maneuver + ETA stream and render on the CarPlay screen. Entitlement approval required. |
| **Android Auto** nav (Google Maps/Waze) on an AA‑enabled HU | 🧪 Yes | This is literally what NBT‑AAD forwards to the HUD today — but it's *Android Auto*, and needs the head‑unit modification. |

**Conclusion:** the only legal, documented way to get high‑quality maps guidance
that you can forward to the HUD is a **custom app using Apple MapKit / CarPlay
navigation templates**. Our Module 3 is built around exactly this abstraction and
runs on simulated events today; swapping in `MKDirections` later is a drop‑in.

---

## 4. iPhone + ENET connection (diagnostics path) — ✅ feasible, implemented here

- The ENET cable presents the car's **Ethernet** to the iPhone via the USB‑C
  adapter. Two distinct things live on that wire:
  1. **DoIP diagnostics** (ISO 13400) to the central gateway (ZGW) and modules —
     VIN, software versions, DTCs, live values. **Read‑only and safe.**
  2. **Direct Ethernet to the head unit** at a link‑local `169.254.x.x` address —
     this is the path the community SSH tooling uses. (Relevant only to deployment,
     not to our read‑only app.)
- **You already run coding over this exact iPhone→USB‑C→ENET→OBD path**, which is
  our strongest evidence the wired link works from your phone. ✅
- **iOS app specifics — ❓ to verify on device:** a native app opens TCP to the HU/
  gateway with `Network.framework` (`NWConnection`). Expected caveats: iOS shows a
  **Local Network permission** prompt; link‑local `169.254` addressing must be
  present on the Ethernet interface (the adapter/OS handles this in your working
  coding setup, so it is promising but we flag the raw‑socket case as *verify on
  device*). No special entitlement is needed for outbound TCP.
- **Implemented now (Modules 1 & 2):** a strictly read‑only DoIP + UDS stack
  (`proto/bmwdiag`, mirrored in Swift) with a mock gateway and **36 passing tests**.
  It can only ever issue read services (ReadDataByIdentifier, ReadDTC, TesterPresent,
  default session) — write/flash/clear/routine services are refused in code.

---

## 5. Wireless Apple CarPlay — ✅ present, but not a data tap

Your wireless CarPlay works and should be left exactly as it is. Important framing:
CarPlay is a **sink** (the car shows the phone's screen + routes audio), not a
**source** you can read structured navigation from. Nothing in this project modifies,
intercepts, or degrades the working CarPlay session. (The reference project happens
to reuse CarPlay's Wi‑Fi link for Android Auto transport, but that's an AA concern,
not something we need for the read‑only app or the MapKit approach.)

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
- **Not promised:** reading the stock Apple Maps app. We will not pretend this exists.
  The equivalent‑functionality path (custom MapKit/CarPlay nav app) is the honest
  substitute and the architecture is built around it.

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
"Stage 5" user‑dependent steps, and each is individually optional.
