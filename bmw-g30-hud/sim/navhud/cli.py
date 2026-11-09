# SPDX-License-Identifier: MIT
"""Command-line driver for the navigation -> HUD simulator.

Examples:
    python -m navhud.cli --scenario city --sink hud --ascii
    python -m navhud.cli --scenario highway --sink kombi --html out.html

The HTML output is a single self-contained file (inline SVG frames) you can
open on a phone to review what the translator would push to the panel.
"""

from __future__ import annotations

import argparse
import sys
from typing import List

from .nav_events import NavEvent
from .hud_model import G30_HUD_PROFILE, G30_KOMBI_PROFILE
from .translator import Translator
from .render_ascii import render_ascii
from .render_svg import render_svg
from .scenarios import SCENARIOS


def _profile(name: str):
    return G30_HUD_PROFILE if name == "hud" else G30_KOMBI_PROFILE


def run(events: List[NavEvent], sink: str) -> List:
    tr = Translator(_profile(sink))
    return [tr.translate(ev) for ev in events]


def _html(frames, title: str) -> str:
    cards = []
    for i, f in enumerate(frames):
        svg = render_svg(f)
        cards.append(
            f'<figure style="margin:0"><div>{svg}</div>'
            f'<figcaption style="color:#999;font:12px/1.4 monospace;'
            f'text-align:center">#{i} {f.arrow.value}</figcaption></figure>'
        )
    grid = "".join(cards)
    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<title>{title}</title></head>"
        "<body style='background:#111;margin:0;padding:16px'>"
        f"<h1 style='color:#ffb000;font:600 18px system-ui'>{title}</h1>"
        "<div style='display:grid;grid-template-columns:repeat(auto-fill,minmax(360px,1fr));"
        "gap:12px'>"
        f"{grid}</div></body></html>"
    )


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="navigation -> HUD simulator")
    ap.add_argument("--scenario", choices=sorted(SCENARIOS), default="city")
    ap.add_argument("--sink", choices=("hud", "kombi"), default="hud")
    ap.add_argument("--ascii", action="store_true", help="print ASCII frames")
    ap.add_argument("--html", metavar="PATH", help="write an HTML strip of SVG frames")
    args = ap.parse_args(argv)

    events = SCENARIOS[args.scenario]()
    frames = run(events, args.sink)

    if args.ascii or not args.html:
        for i, f in enumerate(frames):
            print(f"--- frame #{i} ---")
            print(render_ascii(f))

    if args.html:
        html = _html(frames, f"{args.scenario} / {args.sink}")
        with open(args.html, "w", encoding="utf-8") as fh:
            fh.write(html)
        print(f"wrote {args.html} ({len(frames)} frames)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
