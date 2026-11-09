# SPDX-License-Identifier: MIT
"""SVG renderer for HudFrame - produces a windshield-style amber HUD card.

Monochrome amber on black to evoke the factory HUD. Pure string building, no
dependencies, so it runs anywhere. Used by the CLI to emit an HTML strip you
can open on a phone.
"""

from __future__ import annotations

from .hud_model import HudFrame
from .nav_events import Maneuver

_AMBER = "#ffb000"
_DIM = "#5a3d00"
_BG = "#0a0a0a"

W, H = 360, 200


def _arrow_path(m: Maneuver) -> str:
    """Return SVG elements drawing a maneuver arrow centered around (180,70)."""
    cx, cy = 180, 72
    s = 34  # scale
    a = _AMBER

    def line(x1, y1, x2, y2, w=10):
        return (
            f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" '
            f'stroke="{a}" stroke-width="{w}" stroke-linecap="round" '
            f'stroke-linejoin="round"/>'
        )

    def tri(points):
        pts = " ".join(f"{x},{y}" for x, y in points)
        return f'<polygon points="{pts}" fill="{a}"/>'

    # Each arrow = a shaft + a head. Keep them schematic but distinguishable.
    if m == Maneuver.CONTINUE or m == Maneuver.MERGE:
        return line(cx, cy + s, cx, cy - s + 8) + tri(
            [(cx - 16, cy - s + 10), (cx + 16, cy - s + 10), (cx, cy - s - 14)]
        )
    if m == Maneuver.TURN_RIGHT:
        return line(cx - 10, cy + s, cx - 10, cy) + line(cx - 10, cy, cx + s - 6, cy) + tri(
            [(cx + s - 6, cy - 16), (cx + s - 6, cy + 16), (cx + s + 14, cy)]
        )
    if m == Maneuver.TURN_LEFT:
        return line(cx + 10, cy + s, cx + 10, cy) + line(cx + 10, cy, cx - s + 6, cy) + tri(
            [(cx - s + 6, cy - 16), (cx - s + 6, cy + 16), (cx - s - 14, cy)]
        )
    if m == Maneuver.SLIGHT_RIGHT or m == Maneuver.KEEP_RIGHT or m == Maneuver.EXIT_RIGHT:
        return line(cx - 6, cy + s, cx + 10, cy - 6) + tri(
            [(cx + 2, cy - 18), (cx + 24, cy - 2), (cx + 20, cy - 26)]
        )
    if m == Maneuver.SLIGHT_LEFT or m == Maneuver.KEEP_LEFT or m == Maneuver.EXIT_LEFT:
        return line(cx + 6, cy + s, cx - 10, cy - 6) + tri(
            [(cx - 2, cy - 18), (cx - 24, cy - 2), (cx - 20, cy - 26)]
        )
    if m == Maneuver.SHARP_RIGHT:
        return line(cx - 6, cy + s, cx - 6, cy + 4) + line(cx - 6, cy + 4, cx + 20, cy + 20) + tri(
            [(cx + 10, cy + 4), (cx + 28, cy + 10), (cx + 24, cy + 30)]
        )
    if m == Maneuver.SHARP_LEFT:
        return line(cx + 6, cy + s, cx + 6, cy + 4) + line(cx + 6, cy + 4, cx - 20, cy + 20) + tri(
            [(cx - 10, cy + 4), (cx - 28, cy + 10), (cx - 24, cy + 30)]
        )
    if m == Maneuver.UTURN:
        return (
            f'<path d="M {cx+14} {cy+s} L {cx+14} {cy-6} '
            f'A 18 18 0 0 0 {cx-14} {cy-6} L {cx-14} {cy+2}" '
            f'fill="none" stroke="{_AMBER}" stroke-width="10" '
            f'stroke-linecap="round"/>'
            + tri([(cx - 26, cy + 2), (cx - 2, cy + 2), (cx - 14, cy + 24)])
        )
    if m == Maneuver.ROUNDABOUT:
        return (
            f'<circle cx="{cx}" cy="{cy}" r="20" fill="none" '
            f'stroke="{_AMBER}" stroke-width="8"/>'
            + line(cx, cy + s, cx, cy + 20, 8)
            + line(cx, cy - 20, cx + 24, cy - 28, 8)
            + tri([(cx + 16, cy - 36), (cx + 30, cy - 20), (cx + 34, cy - 40)])
        )
    if m == Maneuver.DESTINATION:
        # checkered flag-ish marker
        sq = 8
        cells = []
        for r in range(3):
            for c in range(3):
                if (r + c) % 2 == 0:
                    cells.append(
                        f'<rect x="{cx-12+c*sq}" y="{cy-12+r*sq}" '
                        f'width="{sq}" height="{sq}" fill="{_AMBER}"/>'
                    )
        return "".join(cells)
    return line(cx, cy + s, cx, cy - s)


def render_svg(frame: HudFrame) -> str:
    if not frame.visible:
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
            f'viewBox="0 0 {W} {H}"><rect width="{W}" height="{H}" fill="{_BG}"/>'
            f'<text x="{W/2}" y="{H/2}" fill="{_DIM}" font-family="monospace" '
            f'font-size="18" text-anchor="middle">HUD off</text></svg>'
        )

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
        f'<rect width="{W}" height="{H}" fill="{_BG}"/>',
        _arrow_path(frame.arrow),
    ]

    # distance text (big, right of arrow)
    if frame.distance_text:
        parts.append(
            f'<text x="330" y="80" fill="{_AMBER}" font-family="Helvetica,Arial" '
            f'font-size="30" font-weight="bold" text-anchor="end">{_esc(frame.distance_text)}</text>'
        )
    if frame.roundabout_exit:
        parts.append(
            f'<text x="330" y="112" fill="{_AMBER}" font-family="Helvetica,Arial" '
            f'font-size="16" text-anchor="end">exit {frame.roundabout_exit}</text>'
        )

    # countdown bar
    if frame.distance_text and frame.distance_text != "now":
        bw = 320
        fill = int(bw * max(0.0, min(1.0, frame.distance_fraction)))
        parts.append(f'<rect x="20" y="126" width="{bw}" height="8" rx="4" fill="{_DIM}"/>')
        parts.append(f'<rect x="20" y="126" width="{fill}" height="8" rx="4" fill="{_AMBER}"/>')

    # label
    if frame.label:
        parts.append(
            f'<text x="20" y="162" fill="{_AMBER}" font-family="Helvetica,Arial" '
            f'font-size="20" text-anchor="start">{_esc(frame.label)}</text>'
        )

    # eta / banner
    if frame.eta_text:
        parts.append(
            f'<text x="340" y="162" fill="{_AMBER}" font-family="Helvetica,Arial" '
            f'font-size="16" text-anchor="end">ETA {_esc(frame.eta_text)}</text>'
        )
    if frame.banner:
        parts.append(
            f'<text x="180" y="190" fill="{_AMBER}" font-family="Helvetica,Arial" '
            f'font-size="16" text-anchor="middle">{_esc(frame.banner)}</text>'
        )

    parts.append("</svg>")
    return "".join(parts)


def _esc(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )
