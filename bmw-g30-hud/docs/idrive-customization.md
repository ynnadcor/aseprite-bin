# Customizing iDrive 6 (NBT EVO) on the G30 — the honest map

The end goal of this project is to adjust the car's iDrive. "Adjust iDrive"
covers very different things with very different risk. This page lays them out
straight, says which the app helps with, and marks the one line this project
won't cross.

Quick summary:

| Road | What you get | Risk | In this app? |
|---|---|---|---|
| 1. Coding | Turn on features already in the firmware (CarPlay full-screen, Sport displays, HUD content, video-in-motion, menus…) | **Low** — reversible, no software change to the head unit | ✅ **iDrive tab**: a guide; you apply each in BimmerCode |
| 2. Factory gauges on the screen | BMW's own Sport/performance displays on iDrive and the cluster | **Low** — it's a coding change (road 1) | ✅ iDrive tab → Displays & HUD → Sport displays |
| 3. Fully-custom gauges | Your own boost/oil/G screens | Low on the **phone**; high on the **iDrive screen** | 🟡 phone app (future); on-screen = road 4 |
| 4. Reskin iDrive / add native apps | New themes, skins, extra apps on the head unit | **High** — needs unlocking the head unit; can brick it | ⛔ not here; briefing only |

---

## Road 1 — Coding (the main event, and it's a lot)

Your car shipped with hundreds of iDrive settings switched off. **Coding**
turns them on or off. It changes *settings*, not *software*: you're flipping
options BMW already built, so it's reversible and low-risk, and it's what the
huge majority of "custom iDrive" actually is.

- **You already have the tool:** BimmerCode on the phone, over the same OBD
  connection. (E-Sys/NCS-Expert on a laptop do the same lower-level job.)
- **The app's iDrive tab** is a guide to the changes worth making on a
  G30/NBT EVO: for each one, what it does, where to find it in BimmerCode,
  any caveat, and how to undo it. The list is generated from
  `tools/make_idrive_tweaks.py`.
- **BMW Link never writes coding.** It only *reads* (it can already read your
  head unit's coding versions in a scan). You make each change in BimmerCode,
  with your hands on it. That keeps the project's "read-only first; explicit
  approval before changing coding" rule intact.
- **Availability depends on your car.** BimmerCode only shows options your
  car's equipment and software actually support — it's the source of truth.
  The app's list is the menu; your car decides what's on it.

Examples on the iDrive tab: Apple CarPlay full-screen, Sport displays, digital
speed in the HUD and cluster, more HUD content, video-in-motion (passenger
use), navigation map in the HUD, skip the start-up disclaimer, auto-lock,
fold-mirrors-on-lock, start-up animation, hide unused menus.

### Could the app write coding later?

Technically yes, but it would be a real step up in risk: a bad coding write
can leave a module misbehaving, and some need a known-good backup and the
right recovery path. Per the project's safety rules that needs a
vehicle-specific review, a written recovery plan, and your explicit approval
**per change** — not a casual toggle. For now the app guides and BimmerCode
writes, which is the safer division of labour and loses you nothing.

## Road 2 — Gauges on the iDrive/cluster screen

The factory way to get real gauges *on the screen* is **BMW's own Sport
displays** (digital power/torque, consumption), unlocked by coding. That's on
the iDrive tab under **Displays & HUD**. No head-unit modification, fully
reversible. For most people this is the answer to "I want gauges on my iDrive".

## Road 3 — Fully-custom gauges (your own design)

A correction worth being clear about: **Apple does not let a third-party app
draw arbitrary gauges on the car screen through CarPlay.** CarPlay only offers
set template types (navigation maps, audio, lists, and a few task categories);
there's no "custom dashboard" surface for an app like this one. So "my own
boost gauge on the iDrive screen via CarPlay" isn't something Apple allows.

Realistic options for custom gauges:
- **On the phone** (the BMW Link app, mounted): fully custom, we control every
  pixel. This is the natural home for a custom performance display and a future
  build can add it. It's on the phone, not the iDrive screen.
- **On the iDrive screen:** only the factory Sport displays (road 2), or a
  head-unit modification (road 4).

## Road 4 — Reskin iDrive, or add native apps (the hard line)

This is the part people picture when they see heavily-modified iDrive 7/8 cars.
On NBT EVO it means changing the head unit's **own software** — replacing theme
files or adding applications on its internal (QNX) system.

Why it's a different world from coding:

- It requires **developer/root access to the head unit**, which is obtained by
  **exploiting** it — not a setting BMW exposes.
- A failed or interrupted modification can leave the head unit **unbootable**
  ("bricked"). Recovery isn't guaranteed by a file backup and can need
  specialist equipment or replacing the module (often four figures).
- It can affect CarPlay, audio, the displays and the car's data network.

Per `safety.md` this is **red tier**. **This project won't do it:** BMW Link
won't unlock the head unit, won't script or package the exploit, and won't
flash head-unit software. That isn't a judgement on you doing your own
research — it's the boundary this tool keeps so it can never be the thing that
bricks your car.

If you still want to go down this road, the honest path is: it's your call and
your risk; do it with the specific NBT EVO community guides and a real recovery
plan (a way to restore the head unit if it won't boot) worked out **before** you
start, ideally with someone who has done it on this exact head unit. Ask in chat
and I'll talk through the trade-offs and what a recovery plan has to include —
I just won't hand you the unlock itself.

### What about an external box?

A plug-in wireless CarPlay/Android adapter box runs its own apps (streaming,
etc.) and shows them through the factory CarPlay input. It **doesn't modify the
head unit**, so it's reversible (unplug it) and low-risk. It costs money, so
that's your decision — this project won't spend anything without your say-so.

---

## Where this leaves the project

- **Build now, in your hands:** the iDrive coding guide (road 1 + 2). That's
  the biggest, safest lever on how your iDrive looks and behaves, and you can
  use it today with BimmerCode.
- **Possible next:** a custom performance display on the phone (road 3).
- **Won't build:** head-unit unlock, theming or app-injection tooling (road 4).
  Briefing and honest discussion only.
