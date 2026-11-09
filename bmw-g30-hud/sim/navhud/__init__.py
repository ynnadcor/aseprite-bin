# SPDX-License-Identifier: MIT
"""navhud - a navigation -> BMW HUD/KOMBI translation simulator.

This package is a *pure-software* development harness. It does NOT talk to a
vehicle. It models:

  * a vendor-neutral stream of turn-by-turn navigation events (Module 3),
  * the constrained display vocabulary of a factory BMW G30 head-up display
    and instrument cluster (KOMBI), and
  * a translator that turns nav events into testable "HUD frames" (Module 4),
    plus ASCII and SVG renderers so the output can be inspected without a car.

Nothing in here transmits anything onto a vehicle network. See
docs/deployment-and-blockers.md for why the on-car step is deliberately out of
scope for the simulator.
"""

from .nav_events import (
    Maneuver,
    NavEvent,
    EventKind,
    Side,
)
from .hud_model import HudProfile, HudFrame, G30_HUD_PROFILE, G30_KOMBI_PROFILE
from .translator import Translator

__all__ = [
    "Maneuver",
    "NavEvent",
    "EventKind",
    "Side",
    "HudProfile",
    "HudFrame",
    "G30_HUD_PROFILE",
    "G30_KOMBI_PROFILE",
    "Translator",
]

__version__ = "0.1.0"
