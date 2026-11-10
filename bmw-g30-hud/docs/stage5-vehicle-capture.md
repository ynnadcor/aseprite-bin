# Stage 5 — What to read from your car (read‑only)

Everything here is **look, don't change**: menus, observations, and photos. Nothing
is coded, flashed, or installed. Do it parked, with the ignition on (engine running
is fine). Skip any item you'd rather not do; each one is independent.

## Part A — no tools needed (about 5 minutes)

| # | What | Where / how | Why it matters |
|---|---|---|---|
| A1 | **Head‑unit software build** (looks like `NBTevo_X12345I`) | iDrive: **Navigation → Settings → Position and software version → Software version**. (Wording from the community project's docs; your menu labels may differ slightly.) A photo of the screen is perfect. | Checked against the list of builds where third‑party head‑unit software is known to work or fail. |
| A2 | **Cluster type** | Is the instrument cluster **one full screen** (digital needles drawn on a display), or **physical needles** with a small screen between them? A photo with the car on is perfect. | Decides which cluster/HUD guidance path applies (the community code targets the "6WA" full‑screen cluster). |
| A3 | **Factory nav on the HUD** | Start a short route in **BMW's own navigation** (not CarPlay). Do turn arrows and distances appear on the HUD? On the cluster? | Confirms the HUD's guidance display works on your car. This is the display the project would feed. |
| A4 | **CarPlay baseline** | Start a route in **Apple Maps on CarPlay**. Does *anything* (arrow, distance, street) appear on the HUD or cluster? | Expected: nothing. If something does appear, that's important news (see `navigation-data.md`). |
| A5 | **HUD settings** | iDrive: Settings → Head‑Up Display. Which items can you toggle (navigation, speed, etc.)? A photo works. | Shows what the HUD can display on your build. |

**What to send back:** the A1 build string, plus a sentence or photo for A2–A5.
**Don't send** your VIN or anything from the car's registration. They aren't needed.

## Part B — with your existing coding setup (optional)

Your current BMW coding app on the iPhone + ENET already connects to the car. If it
has a **read‑only** "vehicle info" or "ECU list" screen, a screenshot of it helps:

- the list of control units it found (names like `HU_NBT2`, `KOMBI`, `HUD`), and
- any "I‑step" / integration‑level string it shows.

**Only read.** Don't run coding, don't "save to car", and don't run any
backup‑restore or flash function for this. If a screen asks to *write* anything,
back out.

## Part C — with the BMW Link app (once it's installed)

Install: [`install-on-iphone.md`](install-on-iphone.md). Then follow
[`car-test-procedure.md`](car-test-procedure.md): about 10 minutes, read‑only, ending
with a log file to send back. It will confirm:

- that iOS exposes the ENET link to a normal app (the Local Network prompt appears,
  and the gateway at a `169.254.x.x` address answers),
- whether your car speaks **HSFZ** or **DoIP**, and
- the head unit's diagnostic address (expected `0x63`) and software build, read
  directly.

Live engine values (boost, oil temp, etc.) stay **unverified** until their
identifiers are confirmed on your car. That's a later, separate, still read‑only step.

## What none of these steps do

They don't change coding, enable SSH, modify the head unit, or touch the engine,
transmission, brakes, airbags, or the tune. All of that is out of scope until there's
a reviewed plan and your explicit go‑ahead (`safety.md`).
