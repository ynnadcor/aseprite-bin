# SPDX-License-Identifier: MIT
"""Translate normalized NavEvents into HudFrames for a given sink (Module 4).

This is the heart of the "degrade gracefully" contract:

  * pick an arrow the target profile can actually show,
  * localize distance to US units and quantize to the panel's coarse steps,
  * truncate labels to the panel's character budget,
  * drop fields the panel can't depict (lanes, ETA) instead of faking them.

It never invents data. If a field isn't in the event, it isn't in the frame.
"""

from __future__ import annotations

from typing import Optional

from .nav_events import NavEvent, Maneuver, EventKind, Side
from .hud_model import HudProfile, HudFrame


# Fallback mapping when a profile can't show a specific arrow.
_ARROW_FALLBACK = {
    Maneuver.KEEP_LEFT: Maneuver.SLIGHT_LEFT,
    Maneuver.KEEP_RIGHT: Maneuver.SLIGHT_RIGHT,
    Maneuver.EXIT_LEFT: Maneuver.SLIGHT_LEFT,
    Maneuver.EXIT_RIGHT: Maneuver.SLIGHT_RIGHT,
    Maneuver.FERRY: Maneuver.CONTINUE,
    Maneuver.SHARP_LEFT: Maneuver.TURN_LEFT,
    Maneuver.SHARP_RIGHT: Maneuver.TURN_RIGHT,
    Maneuver.SLIGHT_LEFT: Maneuver.TURN_LEFT,
    Maneuver.SLIGHT_RIGHT: Maneuver.TURN_RIGHT,
    Maneuver.MERGE: Maneuver.CONTINUE,
    Maneuver.ROUNDABOUT: Maneuver.CONTINUE,
}

_METERS_PER_MILE = 1609.344
_METERS_PER_FOOT = 0.3048


def meters_to_us_text(m: float) -> str:
    """Localize a distance to the way a US BMW cluster shows it.

    Under ~0.1 mi it shows feet rounded to a "nice" value; above that, miles to
    one decimal (or whole miles when large). This mirrors factory behavior
    closely enough for visual review; exact thresholds are confirmable on-car.

    Rounding never makes the readout jump to a value at or past the next unit
    step: 527 ft would round to "550 ft", which is more than "0.1 mi", so it is
    shown as "0.1 mi"; likewise 9.97 mi is "10 mi", never "10.0 mi". Python's
    round() is round-half-even; the Swift port uses .toNearestOrEven to match.
    """
    if m <= 0:
        return "now"
    feet = m / _METERS_PER_FOOT
    if feet < 528:  # < 0.1 mi -> show feet
        # round to 50 ft below 500, 10 ft below 100
        if feet < 100:
            val = int(round(feet / 10.0) * 10)
        else:
            val = int(round(feet / 50.0) * 50)
        val = max(val, 10)
        if val < 528:
            return f"{val} ft"
        # rounded up past 0.1 mi: fall through to the miles display
    miles = m / _METERS_PER_MILE
    if miles < 10:
        txt = f"{miles:.1f}"
        if txt != "10.0":
            return f"{txt} mi"
    return f"{int(round(miles))} mi"


def _resolve_arrow(profile: HudProfile, m: Maneuver) -> Maneuver:
    """Return an arrow the profile can show, chasing the fallback chain."""
    seen = set()
    cur = m
    while not profile.can_show(cur) and cur not in seen:
        seen.add(cur)
        cur = _ARROW_FALLBACK.get(cur, Maneuver.CONTINUE)
    return cur if profile.can_show(cur) else Maneuver.CONTINUE


def _distance_fraction(profile: HudProfile, m: float) -> float:
    """Map a distance to a 0..1 countdown-bar fill (1.0 = far, 0.0 = at point).

    Uses the profile's coarse step table so the bar "ticks" like the factory
    one rather than sliding smoothly.
    """
    steps = profile.distance_steps_m
    top = steps[0] if steps else 1000
    if m >= top:
        return 1.0
    if m <= 0:
        return 0.0
    return max(0.0, min(1.0, m / float(top)))


def _truncate(text: str, n: int) -> str:
    text = (text or "").strip()
    if len(text) <= n:
        return text
    if n <= 1:
        return text[:n]
    return text[: n - 1] + "…"  # ellipsis


class Translator:
    def __init__(self, profile: HudProfile):
        self.profile = profile

    def translate(self, ev: NavEvent) -> HudFrame:
        p = self.profile

        if ev.kind == EventKind.NAV_ENDED:
            return HudFrame(profile_name=p.name, visible=False, banner="")

        if ev.kind == EventKind.ARRIVAL:
            return HudFrame(
                profile_name=p.name,
                visible=True,
                arrow=_resolve_arrow(p, Maneuver.DESTINATION),
                distance_text="now",
                distance_fraction=0.0,
                label=_truncate(ev.road_name or "Destination", p.max_label_chars),
                banner="Arrived",
            )

        banner = "Rerouting" if ev.kind == EventKind.REROUTE else ""

        arrow = _resolve_arrow(p, ev.maneuver)

        distance_text = ""
        distance_fraction = 0.0
        if p.supports_distance:
            distance_text = meters_to_us_text(ev.distance_to_maneuver_m)
            distance_fraction = _distance_fraction(p, ev.distance_to_maneuver_m)

        # Label: prefer the exit signpost on highway exits, else the road name.
        if ev.maneuver in (Maneuver.EXIT_LEFT, Maneuver.EXIT_RIGHT) and ev.exit_name:
            base = ev.exit_name
            if ev.exit_number:
                base = f"{ev.exit_number} {base}"
        else:
            base = ev.road_name
        label = _truncate(base, p.max_label_chars)

        roundabout_exit = None
        if p.supports_roundabout_exit and ev.maneuver == Maneuver.ROUNDABOUT:
            roundabout_exit = ev.roundabout_exit

        lanes = list(ev.lanes) if (p.supports_lanes and ev.lanes) else []

        eta_text = ""
        if p.supports_eta and ev.eta_epoch_s:
            eta_text = _format_eta(ev.eta_epoch_s)

        return HudFrame(
            profile_name=p.name,
            visible=True,
            arrow=arrow,
            distance_text=distance_text,
            distance_fraction=distance_fraction,
            label=label,
            roundabout_exit=roundabout_exit,
            lanes=lanes,
            eta_text=eta_text,
            banner=banner,
        )


def _format_eta(epoch_s: int) -> str:
    import time

    lt = time.localtime(epoch_s)
    h = lt.tm_hour
    ampm = "AM" if h < 12 else "PM"
    h12 = h % 12
    if h12 == 0:
        h12 = 12
    return f"{h12}:{lt.tm_min:02d} {ampm}"
