# SPDX-License-Identifier: MIT
"""Sample navigation sessions used for development and tests.

Each scenario is a plain list of NavEvents. They exercise the required cases:
turns, distance countdown, street names, highway exits, roundabouts, reroute,
arrival, and navigation ending. No vehicle, no network - just data.
"""

from __future__ import annotations

from typing import List

from .nav_events import NavEvent, Maneuver, EventKind, Side


def city_drive() -> List[NavEvent]:
    """A short surface-street route with a reroute and arrival."""
    eid = iter(range(1, 10_000))
    evs: List[NavEvent] = []

    evs.append(NavEvent(next(eid), kind=EventKind.NAV_STARTED,
                        road_name="Route started", distance_remaining_m=4200))

    # approaching a right turn, counting down
    for d in (800, 500, 300, 150, 60, 20):
        evs.append(NavEvent(
            next(eid), kind=EventKind.GUIDANCE, maneuver=Maneuver.TURN_RIGHT,
            distance_to_maneuver_m=d, road_name="E Main St",
            distance_remaining_m=3600 + d))

    # now a slight left onto a named avenue
    for d in (400, 200, 80, 15):
        evs.append(NavEvent(
            next(eid), kind=EventKind.GUIDANCE, maneuver=Maneuver.SLIGHT_LEFT,
            distance_to_maneuver_m=d, road_name="Lincoln Ave",
            distance_remaining_m=2600 + d))

    # a reroute happens
    evs.append(NavEvent(next(eid), kind=EventKind.REROUTE,
                        maneuver=Maneuver.CONTINUE, distance_to_maneuver_m=500,
                        road_name="Lincoln Ave", distance_remaining_m=3000))

    # roundabout, take 2nd exit
    for d in (300, 120, 40):
        evs.append(NavEvent(
            next(eid), kind=EventKind.GUIDANCE, maneuver=Maneuver.ROUNDABOUT,
            distance_to_maneuver_m=d, roundabout_exit=2,
            road_name="Park Blvd", distance_remaining_m=1500 + d))

    # arrival
    for d in (200, 60):
        evs.append(NavEvent(
            next(eid), kind=EventKind.GUIDANCE, maneuver=Maneuver.DESTINATION,
            distance_to_maneuver_m=d, road_name="Park Blvd",
            distance_remaining_m=d))
    evs.append(NavEvent(next(eid), kind=EventKind.ARRIVAL,
                        road_name="Park Blvd"))
    evs.append(NavEvent(next(eid), kind=EventKind.NAV_ENDED))
    return evs


def highway_drive() -> List[NavEvent]:
    """Highway merge, an exit with a signpost, then surface streets."""
    eid = iter(range(1, 10_000))
    evs: List[NavEvent] = []
    evs.append(NavEvent(next(eid), kind=EventKind.NAV_STARTED,
                        road_name="Route started", distance_remaining_m=18_500))

    for d in (1000, 500, 150):
        evs.append(NavEvent(
            next(eid), maneuver=Maneuver.MERGE, distance_to_maneuver_m=d,
            road_name="I-94 W", distance_remaining_m=17_000 + d,
            lanes=["s", "s", "r"]))

    # long highway cruise (sparse updates)
    for d in (12_000, 6000, 2500):
        evs.append(NavEvent(
            next(eid), maneuver=Maneuver.CONTINUE, distance_to_maneuver_m=d,
            road_name="I-94 W", distance_remaining_m=d + 1500))

    # exit right with signpost
    for d in (1600, 800, 300, 90):
        evs.append(NavEvent(
            next(eid), maneuver=Maneuver.EXIT_RIGHT, distance_to_maneuver_m=d,
            exit_name="Jefferson Ave", exit_number="215B",
            road_name="Exit 215B", distance_remaining_m=1500 + d,
            lanes=["s", "s", "r", "r"]))

    for d in (250, 60):
        evs.append(NavEvent(
            next(eid), maneuver=Maneuver.TURN_LEFT, distance_to_maneuver_m=d,
            road_name="Jefferson Ave", distance_remaining_m=d + 200))
    evs.append(NavEvent(next(eid), kind=EventKind.ARRIVAL, road_name="Jefferson Ave"))
    evs.append(NavEvent(next(eid), kind=EventKind.NAV_ENDED))
    return evs


SCENARIOS = {
    "city": city_drive,
    "highway": highway_drive,
}
