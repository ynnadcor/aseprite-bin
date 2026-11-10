# SPDX-License-Identifier: MIT
"""Fails if test-vectors/hud_golden.json no longer matches the Python
translator. The Swift port is tested against that file, so a stale golden
would let the two implementations drift apart unnoticed."""
import json
import os
import sys
import unittest

HERE = os.path.dirname(__file__)
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "sim"))

from navhud.golden import build_golden, render  # noqa: E402

GOLDEN = os.path.join(ROOT, "test-vectors", "hud_golden.json")


class TestHudGolden(unittest.TestCase):
    def test_committed_golden_is_current(self):
        with open(GOLDEN, encoding="utf-8") as fh:
            committed = fh.read()
        self.assertEqual(
            committed, render(build_golden()),
            "hud_golden.json is stale: cd sim && python -m navhud.golden "
            "../test-vectors/hud_golden.json",
        )

    def test_golden_covers_every_maneuver_and_kind(self):
        golden = json.loads(render(build_golden()))
        maneuvers = {c["event"]["maneuver"] for c in golden["cases"]}
        kinds = {c["event"]["kind"] for c in golden["cases"]}
        from navhud.nav_events import Maneuver, EventKind
        self.assertEqual(maneuvers, {m.value for m in Maneuver})
        self.assertEqual(kinds, {k.value for k in EventKind})


if __name__ == "__main__":
    unittest.main()
