# Module 3 — Navigation Data: what's actually accessible

This document is deliberately blunt because it is the make‑or‑break question for
"Apple Maps on the HUD."

## The claim we refuse to make

> "The app reads the turn‑by‑turn directions from the Apple Maps app while it
> navigates on CarPlay, and sends them to the HUD."

**This is not possible through any public, supported, or legal interface**, and we
will not ship anything that pretends it is. Reasons:

1. **No iOS API exposes another app's navigation state.** Apple Maps' live
   maneuvers, distances and ETA are private to that app. There is no public
   notification, no shared container, no accessory API that yields them.
2. **CarPlay does not relay structured guidance.** When Apple Maps runs on the
   CarPlay head unit, the car receives an **encoded video stream** plus audio and
   touch — not a list of maneuvers it (or we) may repurpose. The head unit can't
   read "turn right in 200 ft" as data from that stream, and neither can we.
3. **Getting it anyway would require modifying iOS** (a jailbreak / injecting into
   Maps). That breaks CarPlay guarantees, is fragile across iOS updates, and is out
   of scope. You explicitly asked us *not* to modify iOS or break CarPlay.

If any product claims to put the *stock Apple Maps app's* directions on a BMW HUD
without a jailbreak, treat that claim with suspicion until proven; the supported
mechanism below is almost certainly what's really happening.

## What IS accessible (and is genuinely Apple's maps)

### A. MapKit routing — `MKDirections` / `MKRoute.steps`
Apple provides the **same routing engine that powers Apple Maps** to any app via
**MapKit**. Your own app can request a route and receive a structured list of steps,
each with an instruction string, a maneuver type, and distances. Because your app is
doing the navigating, reading its own guidance is 100% legitimate.

- Pro: fully legal, offline‑of‑CarPlay, no entitlement needed for basic routing.
- Con: it's *your* app's navigation, not a mirror of the Maps app. The user would
  start navigation in your app (or a CarPlay nav app, below), not in Apple Maps.

### B. CarPlay navigation app — `CPMapTemplate` + `CPManeuver`
Apple grants a special **CarPlay navigation entitlement** to navigation apps. With
it, your app:
- renders its map/guidance **on the CarPlay screen** (like Google Maps/Waze do), and
- drives the **CarPlay instrument/maneuver surfaces** with `CPManeuver`,
  `CPTravelEstimates`, etc.

This is the closest thing to "Apple‑quality maps guidance you fully control," and the
maneuver objects are exactly what Module 4 needs.
- Pro: first‑class, on the car screen, you own the maneuver + ETA stream.
- Con: requires Apple to approve the CarPlay entitlement for your app (free to
  request; approval is discretionary and can take time). See `ios-deployment.md`.

### C. Android Auto nav (only if the head unit runs the AA stack)
If the head unit is modified to run the community Android Auto daemon, then Google
Maps/Waze over Android Auto provides a turn‑by‑turn channel the on‑head‑unit app can
read and forward to the HUD — which is what the reference project does today. This is
**not Apple Maps** and requires the head‑unit modification; listed only for complete‑
ness.

## The abstraction we built (so the source can change later)

`sim/navhud/nav_events.py` defines a **vendor‑neutral `NavEvent`**. Every source
above normalizes into it:

```
MKRoute.step / CPManeuver  ─┐
Android Auto nav message  ──┤──►  NavEvent  ──►  Translator  ──►  HudFrame  ──► HUD
simulated route (today)   ─┘
```

Mapping sketch (to implement when a real source is wired):

| Apple `CPManeuver` / `MKRoute.Step` | `NavEvent` field |
|---|---|
| `maneuverType` / instruction parse | `maneuver` (our enum) |
| `distanceRemaining` to step | `distance_to_maneuver_m` |
| step road name / `instructionVariants[0]` | `road_name` |
| `CPTravelEstimates.timeRemaining` → clock | `eta_epoch_s` |
| junction/roundabout exit (if present) | `roundabout_exit` |
| lane guidance (if present) | `lanes` |

Because the translator only ever sees `NavEvent`, **none of Module 4, the renderers,
or the tests change** when we move from simulated events to `MKDirections`. That is
the point of the seam.

## Honest status

- Simulated `NavEvent` source: **done, tested** (this repo).
- `MKDirections` source adapter: **not built yet** (needs the iOS app target to grow a
  nav module; it's a well‑scoped next step with no car dependency).
- CarPlay navigation entitlement: **not requested** (a decision point — it's the
  cleanest path but needs the paid Apple Developer Program and Apple's approval).
- Forwarding `NavEvent` onto the real HUD: blocked on the on‑head‑unit agent and its
  deployment (`deployment-and-blockers.md`).
