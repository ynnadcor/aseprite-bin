# Module 3 — Navigation Data: what's actually accessible

This is the make‑or‑break question for "Apple Maps on the HUD," so it is written
carefully, with what is verified separated from what is not.

> **Correction (end of session 1):** an earlier draft said CarPlay never carries
> structured guidance to the car. That was wrong. CarPlay *does* send turn‑by‑turn
> **maneuver metadata to head units that ask for it**. Newer BMWs (iDrive 7/8),
> Volvo, and Polestar use it to show Apple Maps on the cluster/HUD. The NBT EVO in a
> 2018 G30 does not use that channel as delivered. Details below.

## Two very different questions

### 1. Can an iPhone app read the Apple Maps app's directions? — ⛔ No
There is **no public iOS API** that exposes another app's navigation state. Apple
Maps' live maneuvers, distances, and ETA are private to Apple Maps. Getting at them
on the phone would mean modifying iOS (jailbreak), which breaks CarPlay guarantees,
is fragile across updates, and is out of scope.

### 2. Can the *car* receive the Apple Maps app's directions? — ❓ Yes in principle; not on NBT EVO as delivered
CarPlay has a path for exactly this: when a car's head unit says it supports
**instrument‑cluster / HUD guidance**, iOS sends it the current maneuvers. iOS 17.4
added a richer set of maneuver data (maneuver type, junction type, lane guidance,
road names) for the instrument cluster and HUD. Third‑party CarPlay navigation apps
can feed the same channel through `CPNavigationSession`
([Apple: CPManeuver](https://developer.apple.com/documentation/carplay/cpmaneuver),
[CPRouteInformation](https://developer.apple.com/documentation/carplay/cprouteinformation),
[MacRumors: iOS 17.4 cluster maneuvers](https://www.macrumors.com/2024/02/20/ios-17-4-beta-carplay-instrument-cluster/)).

What that means for a G30:
- **Verified:** newer BMWs show Apple Maps guidance on the HUD over CarPlay, so the
  mechanism exists and BMW uses it on later head units.
- **Verified for your car (by its behavior):** your NBT EVO shows **no** CarPlay
  guidance on the HUD. Its CarPlay integration doesn't request or use this data as
  delivered.
- **Unknown:** whether NBT EVO's CarPlay stack has any dormant support, and what it
  would take to make the head unit request the guidance and pass it to the KOMBI/HUD.
- **Not public:** the head‑unit side of the protocol is part of Apple's
  **confidential MFi licensee specification**. We have not seen it, and we won't use
  leaked copies.

**Bottom line:** the stock Apple Maps app's guidance *can* reach a car. On your car
it would need a modification **on the head unit** (its CarPlay integration plus a HUD
emitter), not on the phone. That modification is the same blocker described in
`deployment-and-blockers.md`, plus a protocol we don't have documentation for. It's
the most "native" possible route, and it's also the hardest to do cleanly.

## Sources of guidance we *can* build on today

| Source | Accessible? | Notes |
|---|---|---|
| **Your own iOS app using MapKit** (`MKDirections` → `MKRoute.steps`) | ✅ Yes | Apple's routing engine; the steps are yours to read. No entitlement needed for basic routing. |
| **Your own CarPlay navigation app** (`CPMapTemplate`, `CPNavigationSession`, `CPManeuver`) | ✅ Yes (entitlement) | Needs Apple's CarPlay navigation entitlement (paid developer program; approval at Apple's discretion). You own the maneuver stream, and on cars that support it iOS also forwards it to the cluster/HUD. |
| **Stock Apple Maps, received by the head unit** (CarPlay cluster guidance) | ❓ Possible in principle | See question 2 above. Needs head‑unit work and a confidential protocol. |
| **Android Auto navigation** (Google Maps/Waze) on an AA‑enabled NBT EVO | 🧪 Reported working | The community NBT‑AAD project forwards AA guidance to the cluster and HUD. A user reports Waze turn‑by‑turn on both (2024 Supra). Not Apple Maps, and needs the head‑unit modification. |
| **Simulated routes** (this repo) | ✅ Done | Used for development and tests. |

## The abstraction (so the source can change later)

`sim/navhud/nav_events.py` defines a vendor‑neutral **`NavEvent`**. Every source
normalizes into it:

```
MKRoute.step / CPManeuver ────┐
CarPlay cluster guidance (HU)─┤
Android Auto nav message ─────┼──►  NavEvent  ──►  Translator  ──►  HudFrame  ──►  HUD
simulated route (today) ──────┘
```

Mapping sketch for the Apple sources:

| Apple field | `NavEvent` field |
|---|---|
| `CPManeuver.maneuverType` (iOS 17.4+) / instruction text | `maneuver` |
| `CPManeuver.junctionType` | used to pick roundabout vs. turn |
| distance remaining to the maneuver | `distance_to_maneuver_m` |
| road name variants | `road_name` |
| trip travel estimates → arrival clock | `eta_epoch_s` |
| roundabout exit number (if present) | `roundabout_exit` |
| `CPLaneGuidance` (iOS 17.4+) | `lanes` |

The CarPlay maneuver model is very close to what the BMW HUD can draw (pictogram,
distance, short road name), which is a good sign for the `HudFrame` contract. Because
the translator only sees `NavEvent`, **Module 4, the renderers, and the tests don't
change** when a real source replaces the simulated one.

## Status

- Simulated `NavEvent` source: **done, tested**.
- `MKDirections` adapter in the iOS app: **not built yet** (well scoped, no car needed).
- CarPlay navigation entitlement: **not requested** (needs the paid developer program;
  we'll ask before spending).
- Receiving stock Apple Maps guidance on the head unit: **research only**. Unproven on
  NBT EVO; depends on head‑unit modification (Red tier, `safety.md`).
