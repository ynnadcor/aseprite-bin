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
| 3. Fully-custom gauges | Your own boost/oil/G screens | Low on the **phone**; high on the **iDrive screen** | ✅ **Gauges tab** (phone, live); on-screen = road 4 |
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
  pixel. **Shipped: the Gauges tab** — a live dashboard (boost, temps, load,
  RPM, speed) polled read-only over ENET, the on-the-phone version of the
  video's "M Vitals" screen. It's on the phone, not the iDrive screen.
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

### The unlock, briefed honestly (no steps here)

So you can decide with eyes open, here's what that road actually involves, in
plain terms. This is a briefing, not a how-to — I won't name or hand you the
exploit, the tools or the sequence.

1. **Get a foothold.** The head unit runs a locked-down QNX system. To change
   it you first need developer/root access, which isn't a BMW setting — it's
   obtained by **running an exploit** the community found. It's unsupported by
   BMW and can stop working after a map/software update.
2. **Change the filesystem.** With access, you replace or add files on the head
   unit: theme/skin files, or application packages (the dashboards and games in
   that video). Every write to the head unit's own storage is a chance to leave
   it in a state it can't boot from.
3. **Make it stick.** Getting it to survive restarts and updates is extra work,
   and each step is another chance to break it.

**Where it can go wrong, and how bad:**

- A failed or interrupted write can leave the head unit in a **boot loop or
  dead** — black screen, no iDrive, often no radio, no climate control UI, no
  CarPlay. In some cases it disturbs the car's data bus and throws errors in
  other modules.
- **A file backup is not a guarantee.** If the unit won't boot, you may not be
  able to put the backup back without low-level access (serial/JTAG-type
  recovery) or specialist help. Worst case is **replacing the head unit**, which
  is typically four figures plus coding/programming to the car.

**What a real recovery plan has to include before you'd touch it:**

- A **tested** way to restore the head unit to a bootable state **without the
  car running or even present** — proven on a bench or a spare unit first, not
  "I have a backup".
- Your **exact** head-unit hardware and software identifiers, and guides known
  to match that exact unit (this app can read those in a scan).
- Acceptance that recovery can still fail, and the money for a replacement if it
  does.
- Ideally, someone who has done this on **your** head unit variant walking it
  with you.

If, knowing all that, you want to go ahead, it's your call and your risk. Ask in
chat and I'll talk through the trade-offs and pressure-test your recovery plan —
I just won't hand you the unlock itself, because that's the boundary that keeps
this tool from ever being the thing that bricks your car.

### What about an external box?

A plug-in wireless CarPlay/Android adapter box runs its own apps (streaming,
etc.) and shows them through the factory CarPlay input. It **doesn't modify the
head unit**, so it's reversible (unplug it) and low-risk. It costs money, so
that's your decision — this project won't spend anything without your say-so.

---

## Where this leaves the project

- **Shipped:** the **iDrive coding guide** (road 1 + 2) and the **Gauges tab**
  (road 3) — a live performance dashboard on the phone (boost, temps, load,
  RPM, speed) polled read-only over ENET. That's the safe, on-the-phone version
  of the video's "M Vitals" screen, and it's genuinely more than BimmerCode does.
- **Next on the gauges:** capture the BMW-specific values (fuel rail pressure,
  requested vs actual charge) on the car so the Fuel & Ignition gauges fill in.
- **Won't build:** head-unit unlock, theming or app-injection tooling (road 4).
  Honest briefing and discussion only (above).
