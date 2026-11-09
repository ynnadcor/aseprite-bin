# SPDX-License-Identifier: MIT
"""Vendor-neutral turn-by-turn navigation event model (Module 3).

Design goal: this schema is the *abstraction boundary*. Any navigation source
(a simulated route here; in the real app, Apple MapKit `MKRoute.steps` /
CarPlay `CPManeuver`; later possibly others) is normalized into these events.
The HUD translator never sees source-specific types.

Why this shape: it matches the lowest common denominator of what the factory
BMW HUD/KOMBI can actually depict (a maneuver pictogram + a distance + a short
label), while carrying a little extra (lanes, exit numbers, ETA) that richer
sinks can use and the HUD can drop.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field, asdict
from enum import Enum
from typing import Optional, List, Dict, Any


class Maneuver(str, Enum):
    """Maneuver pictograms. Chosen to map onto the finite BMW turn-arrow set.

    The factory cluster/HUD exposes a *fixed* catalogue of guidance arrows; you
    cannot draw arbitrary geometry. This enum is intentionally close to that
    catalogue so the translator is a near 1:1 lookup, not a rendering engine.
    """

    CONTINUE = "continue"            # keep straight / stay on road
    TURN_LEFT = "turn_left"
    TURN_RIGHT = "turn_right"
    SLIGHT_LEFT = "slight_left"
    SLIGHT_RIGHT = "slight_right"
    SHARP_LEFT = "sharp_left"
    SHARP_RIGHT = "sharp_right"
    UTURN = "uturn"
    KEEP_LEFT = "keep_left"          # fork / lane-keep
    KEEP_RIGHT = "keep_right"
    MERGE = "merge"
    ROUNDABOUT = "roundabout"        # use `roundabout_exit` for the exit number
    EXIT_LEFT = "exit_left"          # highway ramp / Ausfahrt
    EXIT_RIGHT = "exit_right"
    FERRY = "ferry"
    DESTINATION = "destination"      # arrival pictogram (checkered)

    @property
    def is_turn(self) -> bool:
        return self not in (Maneuver.CONTINUE, Maneuver.DESTINATION)


class Side(str, Enum):
    """Driving side; affects roundabout rotation and default turn emphasis."""

    RIGHT = "right"   # right-hand traffic (US) - default for a US-market G30
    LEFT = "left"     # left-hand traffic


class EventKind(str, Enum):
    """What kind of update this event represents."""

    GUIDANCE = "guidance"        # a maneuver update (the common case)
    REROUTE = "reroute"          # route recalculated
    ARRIVAL = "arrival"          # arrived at destination
    NAV_ENDED = "nav_ended"      # navigation stopped / cancelled
    NAV_STARTED = "nav_started"  # a route began


@dataclass
class NavEvent:
    """A single normalized navigation event.

    Distances are in meters, times in seconds (SI; the renderer localizes to
    mi/ft for a US car). `event_id` is monotonic per session so a sink can
    detect drops/duplicates on a lossy transport.
    """

    event_id: int
    kind: EventKind = EventKind.GUIDANCE
    maneuver: Maneuver = Maneuver.CONTINUE
    # distance from the car to the *next* maneuver point, meters
    distance_to_maneuver_m: float = 0.0
    road_name: str = ""              # road you are on / turning onto
    exit_name: str = ""              # exit signpost text, if any
    exit_number: str = ""            # e.g. "23A"
    roundabout_exit: Optional[int] = None  # which exit to take (1-based)
    # remaining to destination
    distance_remaining_m: Optional[float] = None
    eta_epoch_s: Optional[int] = None      # absolute ETA (unix seconds)
    # lane guidance: list of lanes, each a string of hints e.g. "l", "s", "r"
    lanes: List[str] = field(default_factory=list)
    side: Side = Side.RIGHT
    # free-form, never required by the HUD path
    extra: Dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        self._validate()

    def _validate(self) -> None:
        if not isinstance(self.event_id, int) or self.event_id < 0:
            raise ValueError("event_id must be a non-negative int")
        if self.distance_to_maneuver_m < 0:
            raise ValueError("distance_to_maneuver_m must be >= 0")
        if self.maneuver == Maneuver.ROUNDABOUT and self.roundabout_exit is not None:
            if self.roundabout_exit < 1:
                raise ValueError("roundabout_exit is 1-based")
        if self.distance_remaining_m is not None and self.distance_remaining_m < 0:
            raise ValueError("distance_remaining_m must be >= 0")

    # ---- serialization (the wire format between Module 3 and Module 4) ----

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["kind"] = self.kind.value
        d["maneuver"] = self.maneuver.value
        d["side"] = self.side.value
        return d

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), separators=(",", ":"), sort_keys=True)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "NavEvent":
        d = dict(d)
        d["kind"] = EventKind(d.get("kind", "guidance"))
        d["maneuver"] = Maneuver(d.get("maneuver", "continue"))
        d["side"] = Side(d.get("side", "right"))
        # ignore unknown keys defensively so schema can grow
        known = {f for f in cls.__dataclass_fields__}  # type: ignore[attr-defined]
        d = {k: v for k, v in d.items() if k in known}
        return cls(**d)

    @classmethod
    def from_json(cls, s: str) -> "NavEvent":
        return cls.from_dict(json.loads(s))
