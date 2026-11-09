# SPDX-License-Identifier: MIT
import os
import sys
import unittest

HERE = os.path.dirname(__file__)
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "sim"))

from navhud.nav_events import NavEvent, Maneuver, EventKind  # noqa: E402
from navhud.hud_model import G30_HUD_PROFILE, G30_KOMBI_PROFILE  # noqa: E402
from navhud.translator import Translator, meters_to_us_text  # noqa: E402
from navhud.render_ascii import render_ascii  # noqa: E402
from navhud.render_svg import render_svg  # noqa: E402
from navhud import scenarios  # noqa: E402


class TestDistanceLocalization(unittest.TestCase):
    def test_feet_and_miles(self):
        self.assertEqual(meters_to_us_text(0), "now")
        self.assertEqual(meters_to_us_text(15), "50 ft")       # ~49ft -> round 10 => 50
        self.assertEqual(meters_to_us_text(30), "100 ft")
        self.assertEqual(meters_to_us_text(1609), "1.0 mi")
        self.assertEqual(meters_to_us_text(8047), "5.0 mi")
        self.assertEqual(meters_to_us_text(32187), "20 mi")


class TestTranslator(unittest.TestCase):
    def setUp(self):
        self.hud = Translator(G30_HUD_PROFILE)
        self.kombi = Translator(G30_KOMBI_PROFILE)

    def test_basic_turn_frame(self):
        ev = NavEvent(1, maneuver=Maneuver.TURN_RIGHT, distance_to_maneuver_m=150,
                      road_name="E Main St")
        f = self.hud.translate(ev)
        self.assertTrue(f.visible)
        self.assertEqual(f.arrow, Maneuver.TURN_RIGHT)
        self.assertEqual(f.label, "E Main St")
        self.assertTrue(f.distance_text)

    def test_label_truncation(self):
        long_name = "Avenida de los Insurgentes Sur Numero 1234"
        ev = NavEvent(1, maneuver=Maneuver.TURN_LEFT, distance_to_maneuver_m=100,
                      road_name=long_name)
        f = self.hud.translate(ev)
        self.assertLessEqual(len(f.label), G30_HUD_PROFILE.max_label_chars)
        self.assertTrue(f.label.endswith("…"))

    def test_hud_drops_lanes_kombi_keeps(self):
        ev = NavEvent(1, maneuver=Maneuver.MERGE, distance_to_maneuver_m=500,
                      road_name="I-94 W", lanes=["s", "s", "r"])
        self.assertEqual(self.hud.translate(ev).lanes, [])          # HUD unsupported
        self.assertEqual(self.kombi.translate(ev).lanes, ["s", "s", "r"])

    def test_roundabout_exit_shown(self):
        ev = NavEvent(1, maneuver=Maneuver.ROUNDABOUT, distance_to_maneuver_m=120,
                      roundabout_exit=2, road_name="Park Blvd")
        f = self.hud.translate(ev)
        self.assertEqual(f.arrow, Maneuver.ROUNDABOUT)
        self.assertEqual(f.roundabout_exit, 2)

    def test_exit_uses_signpost_label(self):
        ev = NavEvent(1, maneuver=Maneuver.EXIT_RIGHT, distance_to_maneuver_m=800,
                      exit_name="Jefferson Ave", exit_number="215B",
                      road_name="Exit 215B")
        f = self.kombi.translate(ev)
        self.assertIn("Jefferson", f.label)
        self.assertIn("215B", f.label)

    def test_nav_ended_hides_hud(self):
        ev = NavEvent(1, kind=EventKind.NAV_ENDED)
        f = self.hud.translate(ev)
        self.assertFalse(f.visible)

    def test_arrival_banner(self):
        ev = NavEvent(1, kind=EventKind.ARRIVAL, road_name="Park Blvd")
        f = self.hud.translate(ev)
        self.assertEqual(f.banner, "Arrived")
        self.assertEqual(f.arrow, Maneuver.DESTINATION)

    def test_reroute_banner(self):
        ev = NavEvent(1, kind=EventKind.REROUTE, maneuver=Maneuver.CONTINUE,
                      distance_to_maneuver_m=500, road_name="Lincoln Ave")
        f = self.hud.translate(ev)
        self.assertEqual(f.banner, "Rerouting")

    def test_unsupported_arrow_falls_back_on_hud(self):
        # FERRY is not in the HUD profile -> must fall back to a showable arrow.
        self.assertFalse(G30_HUD_PROFILE.can_show(Maneuver.FERRY))
        ev = NavEvent(1, maneuver=Maneuver.FERRY, distance_to_maneuver_m=100,
                      road_name="x")
        f = self.hud.translate(ev)
        self.assertTrue(G30_HUD_PROFILE.can_show(f.arrow))
        self.assertEqual(f.arrow, Maneuver.CONTINUE)


class TestRenderersAndScenarios(unittest.TestCase):
    def test_renderers_run_for_all_scenarios(self):
        for name, build in scenarios.SCENARIOS.items():
            events = build()
            self.assertGreater(len(events), 3)
            for sink in (G30_HUD_PROFILE, G30_KOMBI_PROFILE):
                tr = Translator(sink)
                for ev in events:
                    frame = tr.translate(ev)
                    ascii_card = render_ascii(frame)
                    svg = render_svg(frame)
                    self.assertIn("+", ascii_card)
                    self.assertTrue(svg.startswith("<svg"))
                    self.assertIn("</svg>", svg)

    def test_json_roundtrip_of_events(self):
        for ev in scenarios.city_drive():
            back = NavEvent.from_json(ev.to_json())
            self.assertEqual(back.to_dict(), ev.to_dict())


if __name__ == "__main__":
    unittest.main()
