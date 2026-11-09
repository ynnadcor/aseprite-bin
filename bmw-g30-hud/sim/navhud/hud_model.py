# SPDX-License-Identifier: MIT
"""Models of the factory display sinks and the HUD "frame" IR (Module 4).

Two sinks are modeled because the G30 has two distinct guidance surfaces and
they do NOT have the same capabilities:

  * HUD  - the windshield head-up display. Monochrome (amber/white), a small
           fixed render area, driven by the KOMBI (instrument cluster). It can
           show a maneuver arrow + a distance countdown + a short road label.
           It can NOT show an arbitrary moving map.
  * KOMBI - the instrument cluster guidance strip / mini-map area. Slightly
           richer (can show a schematic junction, lane bars on some builds).

A `HudProfile` captures the *limits* so the translator degrades gracefully and
we never promise pixels the panel can't draw. These limits are conservative,
documented estimates for a 2018 G30 NBT EVO cluster; exact glyph metrics must
be confirmed on the real car (a user-dependent capture step).
"""

from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Dict, Any, List, Optional

from .nav_events import Maneuver


@dataclass(frozen=True)
class HudProfile:
    name: str
    # which maneuver pictograms the panel can actually show (fixed icon ROM)
    supported_maneuvers: frozenset
    max_label_chars: int          # road/exit text the strip can show
    supports_distance: bool       # numeric/bar distance countdown
    supports_lanes: bool          # lane-array bars
    supports_roundabout_exit: bool
    supports_eta: bool
    # distance "buckets" the HUD counts down through (meters), coarse on purpose
    distance_steps_m: tuple = (1000, 500, 300, 200, 150, 100, 70, 50, 30, 10, 0)

    def can_show(self, m: Maneuver) -> bool:
        return m in self.supported_maneuvers


# The full BMW guidance arrow catalogue we rely on. All of these exist in the
# factory nav graphics set; this is the safe subset the translator targets.
_FULL_ARROWS = frozenset(Maneuver)

# HUD is the most constrained surface: arrow + distance + a short label.
G30_HUD_PROFILE = HudProfile(
    name="G30-HUD",
    supported_maneuvers=frozenset(
        {
            Maneuver.CONTINUE,
            Maneuver.TURN_LEFT,
            Maneuver.TURN_RIGHT,
            Maneuver.SLIGHT_LEFT,
            Maneuver.SLIGHT_RIGHT,
            Maneuver.SHARP_LEFT,
            Maneuver.SHARP_RIGHT,
            Maneuver.UTURN,
            Maneuver.KEEP_LEFT,
            Maneuver.KEEP_RIGHT,
            Maneuver.MERGE,
            Maneuver.ROUNDABOUT,
            Maneuver.EXIT_LEFT,
            Maneuver.EXIT_RIGHT,
            Maneuver.DESTINATION,
        }
    ),
    max_label_chars=18,
    supports_distance=True,
    supports_lanes=False,          # factory HUD does not draw lane arrays
    supports_roundabout_exit=True,
    supports_eta=False,            # HUD shows next-maneuver, not ETA
)

# KOMBI cluster guidance strip: a bit more room, can show lanes on some builds.
G30_KOMBI_PROFILE = HudProfile(
    name="G30-KOMBI",
    supported_maneuvers=_FULL_ARROWS,
    max_label_chars=24,
    supports_distance=True,
    supports_lanes=True,
    supports_roundabout_exit=True,
    supports_eta=True,
)


@dataclass
class HudFrame:
    """The intermediate representation handed to a renderer or (eventually) to
    a real HUD message encoder. This is deliberately tiny and declarative: it
    is exactly what a constrained panel can depict, nothing more.

    `arrow` is always a maneuver the target profile `can_show`; the translator
    guarantees this (falling back to CONTINUE / KEEP_* when needed).
    """

    profile_name: str
    visible: bool = True
    arrow: Maneuver = Maneuver.CONTINUE
    distance_text: str = ""        # already-localized, e.g. "500 ft", "1.2 mi"
    distance_fraction: float = 0.0  # 0..1 for a countdown bar (1 = far)
    label: str = ""                # road/exit text, already truncated
    roundabout_exit: Optional[int] = None
    lanes: List[str] = field(default_factory=list)  # empty if unsupported
    eta_text: str = ""
    banner: str = ""               # e.g. "Rerouting", "Arrived", "" normally

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["arrow"] = self.arrow.value
        return d
