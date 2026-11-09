# SPDX-License-Identifier: MIT
"""ASCII renderer for HudFrame - used by tests and terminal preview.

Deterministic, dependency-free. Good enough to eyeball the translator output
and to assert on in unit tests.
"""

from __future__ import annotations

from .hud_model import HudFrame
from .nav_events import Maneuver

# Compact arrow glyphs. Not the real BMW ROM art - just legible stand-ins.
_ARROW_GLYPH = {
    Maneuver.CONTINUE: "^",
    Maneuver.TURN_LEFT: "<-",
    Maneuver.TURN_RIGHT: "->",
    Maneuver.SLIGHT_LEFT: "<'",
    Maneuver.SLIGHT_RIGHT: "'>",
    Maneuver.SHARP_LEFT: "<|",
    Maneuver.SHARP_RIGHT: "|>",
    Maneuver.UTURN: "U",
    Maneuver.KEEP_LEFT: "(<",
    Maneuver.KEEP_RIGHT: ">)",
    Maneuver.MERGE: "Y",
    Maneuver.ROUNDABOUT: "O",
    Maneuver.EXIT_LEFT: "/<",
    Maneuver.EXIT_RIGHT: ">/",
    Maneuver.FERRY: "~",
    Maneuver.DESTINATION: "[]",
}

_WIDTH = 30


def render_ascii(frame: HudFrame) -> str:
    """Return a small fixed-width card for the frame."""
    if not frame.visible:
        return _box(["(HUD off)"])

    lines = []
    arrow = _ARROW_GLYPH.get(frame.arrow, "?")
    top = arrow
    if frame.roundabout_exit:
        top = f"{arrow} exit {frame.roundabout_exit}"
    if frame.distance_text:
        top = f"{top}   {frame.distance_text}"
    lines.append(top)

    # countdown bar
    if frame.distance_text and frame.distance_text != "now":
        fill = int(round(frame.distance_fraction * (_WIDTH - 2)))
        bar = "[" + "#" * fill + "-" * (_WIDTH - 2 - fill) + "]"
        lines.append(bar)

    if frame.label:
        lines.append(frame.label)
    if frame.lanes:
        lines.append("lanes: " + " ".join(frame.lanes))
    if frame.eta_text:
        lines.append("ETA " + frame.eta_text)
    if frame.banner:
        lines.append("* " + frame.banner + " *")
    return _box(lines)


def _box(lines) -> str:
    w = max(_WIDTH, max((len(x) for x in lines), default=0) + 2)
    top = "+" + "-" * w + "+"
    out = [top]
    for ln in lines:
        out.append("|" + ln.ljust(w) + "|")
    out.append(top)
    return "\n".join(out)
