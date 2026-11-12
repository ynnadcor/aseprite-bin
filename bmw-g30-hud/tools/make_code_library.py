#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Builds the fault code library the BMW Link app uses to explain codes.

    python3 tools/make_code_library.py

writes ios-app/BMWLinkKit/Sources/BMWLinkKit/Resources/code-library.json.
Edit the data below, not the JSON; tests/test_code_library.py fails when the
JSON is out of date.

What's in it: generic OBD-II codes (P, C, B and U codes whose meaning is set by
SAE J2012 and is the same on every car), with plain-English explanations,
likely causes, checks and driving advice written for this project. It is
general guidance, not a diagnosis.

What's NOT in it: BMW's own fault code texts (the 6-digit codes BMW modules
store). Those are proprietary, so the app explains BMW codes from the module
they came from and offers a web search instead.
"""

from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "ios-app", "BMWLinkKit", "Sources", "BMWLinkKit",
                   "Resources", "code-library.json")

SEVERITIES = ("info", "soon", "now", "stop")

DRIVE = {
    "info": "Safe to drive. Have it looked at when convenient.",
    "soon": "Usually fine to drive gently. Get it checked soon.",
    "now": "Drive gently and only as far as you need to. Get it checked now.",
    "stop": "Stop as soon as it's safe and switch the engine off.",
}

CODES: dict = {}


def add(code, title, system, severity, meaning, causes, checks, drive=None, ignored=None):
    assert code not in CODES, f"duplicate {code}"
    assert severity in SEVERITIES, severity
    entry = {
        "code": code,
        "title": title,
        "system": system,
        "severity": severity,
        "meaning": meaning,
        # List items read as short lines in the app: no closing full stop.
        "causes": [c.rstrip(".") for c in causes],
        "checks": [c.rstrip(".") for c in checks],
        "drive": drive or DRIVE[severity],
    }
    if ignored:
        entry["ignored"] = ignored
    CODES[code] = entry


# --- Cam timing (VANOS) and engine position sensors ----------------------------

CAM = "Cam timing (VANOS)"
for code, cam, what in (("P0010", "intake", "Intake"), ("P0013", "exhaust", "Exhaust")):
    add(code, f"{what} cam adjuster circuit (bank 1)", CAM, "soon",
        f"Electrical fault in the circuit of the solenoid that adjusts the {cam} camshaft's "
        "timing (BMW calls this VANOS).",
        [f"{what} VANOS solenoid failed",
         "Solenoid connector loose, corroded or full of oil",
         "Wiring between the solenoid and the engine computer"],
        ["Check the solenoid's connector for oil, corrosion or damage",
         "Measure the solenoid's resistance against the specification",
         "Check the wiring back to the engine computer"],
        "Usually drivable, but power and smoothness can suffer. Get it checked soon.",
        "Rough running, less power and higher fuel use.")

CAM_DRIVE = ("Usually drivable with less power. Get it checked soon; if the engine rattles "
             "or runs badly, don't drive hard.")
for code, cam, what, how in (
        ("P0011", "intake", "Intake", "over-advanced or performance"),
        ("P0012", "intake", "Intake", "over-retarded"),
        ("P0014", "exhaust", "Exhaust", "over-advanced or performance"),
        ("P0015", "exhaust", "Exhaust", "over-retarded")):
    add(code, f"{what} cam timing {how} (bank 1)", CAM, "soon",
        f"The {cam} camshaft isn't reaching the timing the engine computer asks for.",
        ["Low, old or wrong engine oil (VANOS runs on oil pressure)",
         f"Sticking or dirty {cam} VANOS solenoid",
         "Worn or stretched timing chain, guides or tensioner",
         f"Faulty {cam} VANOS adjuster or camshaft sensor"],
        ["Check the oil level and when the oil was last changed",
         "Look for other cam or crank timing codes: several together point to the timing chain",
         f"Inspect, clean or replace the {cam} VANOS solenoid",
         "Have the cam timing checked if the code comes back"],
        CAM_DRIVE,
        "If the cause is a worn timing chain, it can eventually cause serious engine damage.")

for code, letter, cam in (("P0016", "A", "intake"), ("P0017", "B", "exhaust")):
    add(code, f"Crankshaft/camshaft correlation, sensor {letter} ({cam}, bank 1)", CAM, "soon",
        f"The crankshaft and {cam} camshaft positions don't line up the way they should.",
        ["Stretched timing chain or worn guides/tensioner",
         f"Faulty crankshaft or {cam} camshaft sensor",
         "VANOS solenoid or adjuster stuck",
         "Low oil level or pressure"],
        ["Check the oil level",
         "Check both sensors' connectors and wiring",
         "Read the cam timing deviation in live data",
         "Have the timing chain checked for stretch"],
        CAM_DRIVE,
        "A worn timing chain can eventually jump or break and cause severe engine damage.")

SENSORS = "Engine sensors"
add("P0335", "Crankshaft position sensor circuit", SENSORS, "now",
    "The engine computer isn't getting a usable signal from the crankshaft position sensor, "
    "which it needs to time fuel and spark.",
    ["Crankshaft sensor failing", "Damaged wiring or connector", "Damaged trigger wheel (rare)"],
    ["Check the sensor's connector and wiring", "Test the sensor's signal",
     "Note whether the engine stalls or won't restart when hot"],
    "The engine can stall or refuse to start. Get it checked now.",
    "The car can leave you stranded.")
for code, letter, cam in (("P0340", "A", "intake"), ("P0365", "B", "exhaust")):
    add(code, f"Camshaft position sensor {letter} circuit ({cam}, bank 1)", SENSORS, "soon",
        f"The engine computer isn't getting a good signal from the {cam} camshaft sensor.",
        ["Camshaft sensor failing", "Connector or wiring damage",
         "Oil in the connector from a leaking sensor seal"],
        ["Check the connector for oil or damage", "Check the wiring",
         "Try a known-good sensor if one is available"],
        "Expect long cranking or rough running. Get it checked soon.",
        "Starting problems and less power.")

# --- Fuel mixture ---------------------------------------------------------------

MIX = "Fuel mixture"
LEAN_CAUSES = ["Vacuum or boost leak (hoses, intake gasket)",
               "Crankcase ventilation fault, often in the valve cover",
               "Low fuel pressure (fuel pump or filter)",
               "Air flow or manifold pressure sensor reading wrong",
               "Exhaust leak before the front oxygen sensor"]
LEAN_CHECKS = ["Listen for hissing at idle and check intake and charge hoses",
               "Smoke test the intake for leaks",
               "Check fuel pressure, low and high side",
               "Watch fuel trims in live data at idle and under load"]
LEAN_DRIVE = ("Usually drivable. Get it checked soon, and avoid hard driving if the engine "
              "also misfires.")
LEAN_IGNORED = ("Misfires, and on a turbo engine, running lean under heavy load raises the "
                "risk of knock and engine damage.")
RICH_CAUSES = ["Leaking fuel injector", "Fuel vapor purge valve stuck open",
               "Air flow or pressure sensor reading wrong", "Fuel pressure too high",
               "Faulty front oxygen sensor"]
RICH_CHECKS = ["Look for other injector or purge codes", "Watch fuel trims in live data",
               "Check fuel pressure", "Check that the purge valve closes"]
RICH_IGNORED = ("Higher fuel use, fouled spark plugs and, over time, a damaged catalytic "
                "converter.")

for code, bank in (("P0171", 1), ("P0174", 2)):
    note = "" if bank == 1 else " (engines with two cylinder banks, such as V8s)"
    add(code, f"System too lean (bank {bank})", MIX, "soon",
        "The engine is getting more air or less fuel than expected, and the engine computer "
        f"has reached its limit for adding fuel{note}.",
        LEAN_CAUSES, LEAN_CHECKS, LEAN_DRIVE, LEAN_IGNORED)
for code, bank in (("P0172", 1), ("P0175", 2)):
    note = "" if bank == 1 else " (engines with two cylinder banks, such as V8s)"
    add(code, f"System too rich (bank {bank})", MIX, "soon",
        "The engine is getting more fuel than expected, and the engine computer has reached "
        f"its limit for taking fuel away{note}.",
        RICH_CAUSES, RICH_CHECKS, None, RICH_IGNORED)

add("P2096", "Rear fuel trim too lean (bank 1)", MIX, "soon",
    "The oxygen sensor after the catalytic converter keeps reading lean, and its correction "
    "has reached the limit.",
    ["Exhaust leak near the oxygen sensors", "Aging oxygen sensor",
     "A mixture problem (see any lean codes)", "Worn catalytic converter"],
    ["Check for exhaust leaks", "Fix any other mixture codes first",
     "Check both oxygen sensors' signals in live data"],
    None, "A failed emissions inspection; mixture problems can get worse.")
add("P2097", "Rear fuel trim too rich (bank 1)", MIX, "soon",
    "The oxygen sensor after the catalytic converter keeps reading rich, and its correction "
    "has reached the limit.",
    ["A rich mixture (leaking injector, purge valve)", "Aging oxygen sensor",
     "Worn catalytic converter", "Exhaust leak"],
    ["Fix any other mixture codes first", "Check for exhaust leaks",
     "Check both oxygen sensors' signals in live data"],
    None, "A failed emissions inspection and, over time, catalytic converter damage.")

add("P2177", "Too lean away from idle (bank 1)", MIX, "soon",
    "The mixture runs lean when driving above idle, beyond what the engine computer can correct.",
    ["Low fuel pressure or a weak fuel pump", "Air flow reading too low", "Boost leak",
     "Dirty or clogged injectors"],
    ["Check fuel pressure under load", "Check for boost leaks",
     "Compare fuel trims at idle and at cruise"],
    LEAN_DRIVE, "Hesitation, misfires and, under heavy load, a risk of knock.")
add("P2178", "Too rich away from idle (bank 1)", MIX, "soon",
    "The mixture runs rich when driving above idle, beyond what the engine computer can correct.",
    ["Air flow reading too high", "Leaking injector", "Fuel pressure too high",
     "Purge valve stuck open"],
    ["Watch fuel trims at cruise", "Check fuel pressure", "Look for injector or purge codes"],
    None, RICH_IGNORED)
add("P2187", "Too lean at idle (bank 1)", MIX, "soon",
    "The mixture is lean at idle, beyond what the engine computer can correct. Air leaks "
    "matter most at idle.",
    ["Vacuum leak", "Crankcase ventilation leak, often a failed valve cover",
     "Intake manifold gasket", "Loose or damaged oil filler cap"],
    ["Smoke test the intake", "Check the oil filler cap's seal",
     "Check the valve cover's crankcase ventilation"],
    None, "Rough idle and misfires; leaks usually get worse.")
add("P2188", "Too rich at idle (bank 1)", MIX, "soon",
    "The mixture is rich at idle, beyond what the engine computer can correct.",
    ["Purge valve stuck open", "Leaking injector", "Fuel pressure too high"],
    ["Check that the purge valve closes", "Look for injector codes", "Check fuel pressure"],
    None, RICH_IGNORED)
add("P2191", "Too lean at higher load (bank 1)", MIX, "soon",
    "The mixture runs lean under load, beyond what the engine computer can correct.",
    ["Fuel delivery: in-tank pump, high-pressure pump or filter", "Boost leak",
     "Air flow reading too low", "Clogged injectors"],
    ["Check fuel pressure at full load", "Do a boost leak test", "Check injector balance"],
    "Avoid hard acceleration until it's fixed: lean running under load can damage the engine. "
    "Get it checked soon.",
    "Under heavy load, a lean turbo engine risks knock and engine damage.")
add("P2192", "Too rich at higher load (bank 1)", MIX, "soon",
    "The mixture runs rich under load, beyond what the engine computer can correct.",
    ["Air flow reading too high", "Leaking injector", "Fuel pressure too high"],
    ["Watch fuel trims under load", "Check fuel pressure", "Look for injector codes"],
    None, RICH_IGNORED)

# --- Fuel pressure and injectors -------------------------------------------------

FUEL = "Fuel pressure"
add("P0087", "Fuel rail pressure too low", FUEL, "now",
    "Pressure in the high-pressure fuel rail is lower than the engine computer asks for.",
    ["High-pressure fuel pump wearing out", "Low supply from the in-tank fuel pump",
     "Clogged fuel filter", "Faulty rail pressure sensor"],
    ["Check the low-pressure side first (cheaper)",
     "Watch requested vs actual rail pressure under load", "Look for fuel leaks",
     "On a tuned engine, check that the fuel system can supply what the tune asks for"],
    "The engine can lose power, run lean or stall. Get it checked now.",
    "Stalling, lean misfires and possible engine damage under load.")
add("P0088", "Fuel rail pressure too high", FUEL, "now",
    "Pressure in the high-pressure fuel rail is higher than it should be.",
    ["High-pressure pump's control valve", "Faulty rail pressure sensor",
     "Pressure limiting valve"],
    ["Check the pressure sensor's wiring", "Compare rail pressure with the engine off and running",
     "Check the high-pressure pump's control valve"],
    "The engine may run poorly or limit power. Get it checked now.",
    "Rough running and strain on the fuel system.")
add("P0089", "Fuel pressure regulation performance", FUEL, "soon",
    "The fuel pressure doesn't follow what the engine computer asks for.",
    ["High-pressure fuel pump or its control valve", "Rail pressure sensor", "Wiring"],
    ["Watch requested vs actual rail pressure", "Check the pump control valve's connector"],
    None, "Hesitation and lean or rich running.")
add("P0191", "Fuel rail pressure sensor range/performance", FUEL, "soon",
    "The rail pressure sensor's reading doesn't make sense to the engine computer.",
    ["Rail pressure sensor", "Connector or wiring", "A real pressure problem (pump)"],
    ["Check the sensor's connector and wiring", "Compare its reading with live data at idle and load"],
    None, "Poor running if the engine computer can't trust the fuel pressure.")
for code, level in (("P0192", "low"), ("P0193", "high")):
    add(code, f"Fuel rail pressure sensor circuit {level}", FUEL, "soon",
        f"The rail pressure sensor's signal is too {level} to be real: usually an electrical fault.",
        ["Rail pressure sensor", "Short or break in the wiring", "Sensor 5 V supply problem"],
        ["Check the connector and wiring", "Check for sensor supply codes (P0641, P0651)"],
        None, "Poor running or stalling.")
add("P0627", "Fuel pump control circuit", FUEL, "now",
    "Electrical fault in the circuit that controls the in-tank fuel pump.",
    ["Fuel pump control module", "Wiring or connector", "Fuel pump"],
    ["Check fuses and the pump module's connectors",
     "Look for codes in the fuel pump control module"],
    "The engine can stall or not start. Get it checked now.",
    "The car can leave you stranded.")

MISFIRE = "Ignition and misfire"
MISFIRE_DRIVE = ("If the engine light flashes, slow down and avoid full throttle: a heavy "
                 "misfire overheats the catalytic converter. Get it fixed now.")
MISFIRE_IGNORED = ("Unburned fuel can overheat and ruin the catalytic converter, and the engine "
                   "runs worse.")
for n in range(1, 7):
    add(f"P020{n}", f"Injector circuit, cylinder {n}", "Fuel injectors", "now",
        f"Electrical fault in the circuit of cylinder {n}'s fuel injector.",
        [f"Injector for cylinder {n}", "Connector or wiring to the injector",
         "Engine computer's injector driver (rare)"],
        ["Check the injector's connector", "Measure the injector circuit against the specification",
         "Check the wiring back to the engine computer"],
        f"Expect a misfire on cylinder {n}. Drive gently and get it checked now.",
        MISFIRE_IGNORED)

# --- Ignition and misfire ----------------------------------------------------------

add("P0300", "Random or multiple cylinder misfire", MISFIRE, "now",
    "Misfires were detected that aren't limited to one cylinder.",
    ["Worn spark plugs (they wear faster on a tuned engine)", "Vacuum or boost leak",
     "Low fuel pressure", "Several weak ignition coils",
     "Carbon on the intake valves (direct-injection engines)"],
    ["Check when the spark plugs were last changed",
     "Read misfire counts per cylinder in live data",
     "Look for lean codes and air leaks", "Check fuel pressure"],
    MISFIRE_DRIVE, MISFIRE_IGNORED)
for n in range(1, 7):
    add(f"P030{n}", f"Cylinder {n} misfire", MISFIRE, "now",
        f"Cylinder {n} isn't burning its fuel properly, so the engine runs unevenly.",
        [f"Ignition coil on cylinder {n}", f"Spark plug in cylinder {n} (worn or wrong gap)",
         f"Fuel injector for cylinder {n}", f"Low compression in cylinder {n} (less common)"],
        [f"Swap the coil from cylinder {n} with a neighbor. If the misfire moves, replace that coil.",
         "If it doesn't move, swap the spark plug the same way.",
         "Still there: have the injector and the compression checked."],
        MISFIRE_DRIVE, MISFIRE_IGNORED)
add("P0313", "Misfire with low fuel", MISFIRE, "soon",
    "Misfires were detected while the tank was nearly empty.",
    ["Running the tank very low", "Fuel pickup or pump problem at low fuel level"],
    ["Fill the tank and see whether it comes back", "If it does, check the fuel pump and pickup"],
    "Fill up soon. If misfires continue, get it checked.",
    "Running out of fuel, or a damaged catalytic converter.")
for n, letter in zip(range(1, 7), "ABCDEF"):
    add(f"P035{n}", f"Ignition coil {letter} circuit (usually cylinder {n})", MISFIRE, "now",
        f"Electrical fault in ignition coil {letter}'s circuit. On most engines coil {letter} "
        f"fires cylinder {n}.",
        [f"Ignition coil {letter} failed", "Coil connector loose, corroded or damaged",
         "Wiring to the coil", "Engine computer's coil driver (rare)"],
        ["Check the coil's connector and wiring",
         "Swap the coil with a neighbor: if the code follows it, replace the coil"],
        "Expect a misfire on that cylinder. Drive gently and get it fixed now.",
        MISFIRE_IGNORED)

KNOCK = "Knock control"
KNOCK_DRIVE = ("Usually drivable; the engine computer may cut power to protect the engine. "
               "Avoid hard driving until it's fixed.")
KNOCK_IGNORED = "Less power, and hard driving without knock protection risks engine damage."
for code, title in (("P0325", "Knock sensor 1 circuit"), ("P0327", "Knock sensor 1 circuit low"),
                    ("P0328", "Knock sensor 1 circuit high")):
    add(code, title, KNOCK, "soon",
        "The engine computer isn't getting a good signal from knock sensor 1, which listens "
        "for harmful combustion knock.",
        ["Knock sensor", "Connector or wiring", "Sensor bolt loose or overtightened"],
        ["Check the connector and wiring", "Check the sensor's mounting", "Test the sensor"],
        KNOCK_DRIVE, KNOCK_IGNORED)

# --- Air intake and sensors ------------------------------------------------------------

AIR = "Air intake"
add("P0068", "Air flow doesn't match throttle position", AIR, "soon",
    "The air the engine computer measures doesn't match what the throttle position suggests.",
    ["Air leak after the throttle (intake manifold, hoses)",
     "Air flow or manifold pressure sensor", "Throttle body"],
    ["Check for vacuum leaks", "Check the sensors' connectors", "Inspect and clean the throttle body"],
    None, "Poor running, and the car may limit power.")
add("P0101", "Air flow sensor range/performance", AIR, "soon",
    "The air flow sensor's reading doesn't match what the engine computer expects "
    "(on engines that have one).",
    ["Dirty or failing air flow sensor", "Air leak between the sensor and the engine",
     "Clogged air filter"],
    ["Check the air filter and intake boots", "Check for leaks", "Inspect the sensor"],
    None, "Poor running and wrong mixture.")
for code, level in (("P0102", "low"), ("P0103", "high")):
    add(code, f"Air flow sensor circuit {level}", AIR, "soon",
        f"The air flow sensor's signal is too {level} to be real: usually an electrical fault.",
        ["Air flow sensor", "Connector or wiring", "Sensor supply"],
        ["Check the connector and wiring", "Inspect the sensor"],
        None, "Poor running and wrong mixture.")
add("P0106", "Manifold pressure sensor range/performance", AIR, "soon",
    "The intake manifold pressure sensor's reading doesn't make sense to the engine computer.",
    ["Pressure sensor", "Leak or blockage at the sensor's port", "Wiring"],
    ["With the engine off, the reading should match outside air pressure",
     "Check the sensor's seal and port", "Check the connector"],
    None, "Wrong fueling and boost control.")
for code, level in (("P0107", "low"), ("P0108", "high")):
    add(code, f"Manifold pressure sensor circuit {level}", AIR, "soon",
        f"The manifold pressure sensor's signal is too {level} to be real: usually an "
        "electrical fault.",
        ["Pressure sensor", "Connector or wiring", "Sensor 5 V supply"],
        ["Check the connector and wiring", "Look for sensor supply codes (P0641, P0651)"],
        None, "Wrong fueling and boost control.")
for code, title in (("P0111", "Intake air temperature sensor range/performance"),
                    ("P0112", "Intake air temperature sensor circuit low"),
                    ("P0113", "Intake air temperature sensor circuit high")):
    add(code, title, SENSORS, "soon",
        "The intake air temperature reading is out of range or doesn't make sense.",
        ["Air temperature sensor", "Connector or wiring"],
        ["Check the connector and wiring", "Compare the reading with outside temperature on a cold start"],
        None, "Slightly wrong fueling and timing.")
for code, title in (("P0116", "Coolant temperature sensor range/performance"),
                    ("P0117", "Coolant temperature sensor circuit low"),
                    ("P0118", "Coolant temperature sensor circuit high")):
    add(code, title, SENSORS, "soon",
        "The coolant temperature reading is out of range or doesn't make sense.",
        ["Coolant temperature sensor", "Connector or wiring", "Low coolant (the sensor reads air)"],
        ["Check the coolant level with the engine cold", "Check the sensor's connector",
         "Compare its reading with another temperature reading"],
        "Watch the temperature warning; the cooling fan may run all the time. Get it checked soon.",
        "Hard starting, high fuel use, and overheating could go unnoticed.")
for code, title in (("P0196", "Oil temperature sensor range/performance"),
                    ("P0197", "Oil temperature sensor circuit low"),
                    ("P0198", "Oil temperature sensor circuit high")):
    add(code, title, SENSORS, "soon",
        "The oil temperature reading is out of range or doesn't make sense.",
        ["Oil temperature sensor", "Connector or wiring"],
        ["Check the connector and wiring", "Compare with coolant temperature after a long drive"],
        None, "The engine computer can't protect the engine from high oil temperature.")
add("P2279", "Intake air leak", AIR, "soon",
    "The engine computer thinks air is getting into the intake without being measured.",
    ["Vacuum leak", "Crankcase ventilation leak (valve cover)", "Intake manifold gasket",
     "Loose intake boot or clamp"],
    ["Smoke test the intake", "Check all intake boots and clamps"],
    None, "Lean running, rough idle and misfires.")

# --- Turbo and boost -------------------------------------------------------------------

TURBO = "Turbo and boost"
add("P0234", "Turbo overboost", TURBO, "now",
    "Boost pressure went higher than the engine computer allows.",
    ["Wastegate stuck closed, or its actuator or linkage", "Boost pressure sensor reading wrong",
     "A tune asking for more boost than the limits allow"],
    ["Check that the wastegate actuator and linkage move freely",
     "With the engine off, compare the boost sensor with outside air pressure",
     "On a tuned engine, check the tune with its supplier"],
    "Drive gently; the engine computer may cut power. Get it checked now.",
    "Overboost can damage the turbo or the engine.")
add("P0236", "Boost pressure sensor range/performance", TURBO, "soon",
    "The boost pressure sensor's reading doesn't make sense to the engine computer.",
    ["Boost pressure sensor", "Leak or blockage at the sensor", "Wiring"],
    ["With the engine off, the reading should match outside air pressure",
     "Check the sensor's seal and connector"],
    None, "Wrong boost control and less power.")
for code, level in (("P0237", "low"), ("P0238", "high")):
    add(code, f"Boost pressure sensor circuit {level}", TURBO, "soon",
        f"The boost sensor's signal is too {level} to be real: usually an electrical fault.",
        ["Boost pressure sensor", "Connector or wiring", "Sensor 5 V supply"],
        ["Check the connector and wiring", "Look for sensor supply codes (P0641, P0651)"],
        None, "Wrong boost control and less power.")
add("P0243", "Wastegate actuator circuit", TURBO, "soon",
    "Electrical fault in the circuit that controls the turbo's wastegate, the valve that "
    "limits boost.",
    ["Wastegate actuator or solenoid", "Connector or wiring"],
    ["Check the actuator's connector", "Check that the wastegate moves freely"],
    "Expect less power or uneven boost. Get it checked soon.",
    "Boost problems: low power, or overboost if the wastegate stays shut.")
add("P0299", "Turbo underboost", TURBO, "soon",
    "Boost pressure stayed below what the engine computer asked for.",
    ["Boost leak: charge pipe, intercooler hoses or clamps", "Wastegate stuck open or its actuator",
     "Worn turbo", "Blocked air filter or intake",
     "A tune asking for more boost than the turbo delivers"],
    ["Inspect the charge pipe and intercooler hoses for cracks or loose clamps",
     "Do a boost leak (pressure) test", "Check that the wastegate actuator moves",
     "Compare requested and actual boost in live data"],
    "Drivable with less power. Get it checked soon.",
    "Leaks get worse; a failing turbo can damage the engine.")
add("P2261", "Turbo bypass (diverter) valve, mechanical", TURBO, "soon",
    "The valve that releases boost when you lift off the throttle isn't working as expected.",
    ["Diverter valve stuck or its diaphragm torn", "Its electric or vacuum control"],
    ["Check the diverter valve", "Listen for unusual noises when lifting off"],
    None, "Less boost, and extra strain on the turbo.")
add("P2263", "Turbo boost system performance", TURBO, "soon",
    "Boost doesn't follow what the engine computer asks for.",
    ["Boost leak", "Wastegate or its actuator", "Turbo wear", "Boost sensor"],
    ["Do a boost leak test", "Compare requested and actual boost", "Check wastegate movement"],
    None, "Low power, or the car limiting power.")
add("P2563", "Wastegate position sensor range/performance", TURBO, "soon",
    "The sensor that reports the wastegate position gives readings that don't make sense.",
    ["Electric wastegate actuator or its position sensor", "Sticking wastegate linkage", "Wiring"],
    ["Check the actuator's connector", "Check that the linkage moves freely"],
    None, "Uneven boost and less power.")

# --- Throttle and pedal ----------------------------------------------------------------------

THROTTLE = "Throttle and pedal"
TH_DRIVE = "The car may go into reduced power mode. Drive gently and get it checked now."
TH_IGNORED = "Sudden loss of power, which can be dangerous in traffic."
for code, title, causes in (
        ("P0121", "Throttle position sensor A range/performance",
         ["Throttle body's position sensor", "Dirty throttle body", "Wiring"]),
        ("P0122", "Throttle position sensor A circuit low", ["Throttle body's position sensor", "Wiring or connector"]),
        ("P0123", "Throttle position sensor A circuit high", ["Throttle body's position sensor", "Wiring or connector"]),
        ("P0221", "Throttle position sensor B range/performance",
         ["Throttle body's position sensor", "Dirty throttle body", "Wiring"]),
        ("P0638", "Throttle actuator range/performance (bank 1)",
         ["Throttle body motor or gears", "Carbon buildup", "Wiring"]),
        ("P2101", "Throttle actuator motor circuit range/performance",
         ["Throttle body motor", "Wiring or connector", "Engine computer's driver (rare)"]),
        ("P2111", "Throttle stuck open", ["Throttle body sticking from carbon buildup", "Throttle motor failing"]),
        ("P2112", "Throttle stuck closed", ["Throttle body sticking from carbon buildup", "Throttle motor failing"]),
        ("P2119", "Throttle body range/performance", ["Throttle body", "Carbon buildup", "Wiring"]),
        ("P2135", "Throttle position sensors A and B disagree", ["Throttle body's sensors", "Connector or wiring"])):
    add(code, title, THROTTLE, "now",
        "The engine computer doesn't trust the throttle's position or movement, so it may "
        "limit power for safety.",
        causes,
        ["Check the throttle body's connector and wiring", "Inspect and clean the throttle body",
         "Look for other throttle or pedal codes"],
        TH_DRIVE, TH_IGNORED)
add("P2138", "Accelerator pedal sensors D and E disagree", THROTTLE, "now",
    "The two sensors in the accelerator pedal report different positions, so the engine "
    "computer may limit power for safety.",
    ["Accelerator pedal sensor", "Pedal connector or wiring"],
    ["Check the pedal's connector", "Watch both pedal signals in live data"],
    TH_DRIVE, TH_IGNORED)

# --- Catalyst and oxygen sensors ----------------------------------------------------------------

CAT = "Exhaust and catalyst"
for code, bank in (("P0420", 1), ("P0430", 2)):
    add(code, f"Catalytic converter efficiency below threshold (bank {bank})", CAT, "soon",
        "The catalytic converter isn't cleaning the exhaust as well as it should, judging by "
        "the oxygen sensor after it.",
        ["Aging or damaged catalytic converter", "Faulty oxygen sensor after the converter",
         "Exhaust leak near the sensors",
         "Earlier misfires or rich running that damaged the converter",
         "Modified or removed catalytic converter"],
        ["Fix any misfire or mixture codes first", "Check for exhaust leaks",
         "Check the rear oxygen sensor's signal in live data"],
        "Safe to drive. Get it checked soon; it will fail an emissions inspection.",
        "A failed emissions inspection, and if misfires caused it, the converter gets worse.")

O2 = "Oxygen sensors"
O2_CAUSES = ["Oxygen sensor aging or failed", "Connector or wiring, often heat-damaged",
             "Exhaust leak near the sensor"]
O2_HEATER_CAUSES = ["The sensor's heater failed (replace the sensor)", "Heater fuse or wiring",
                    "Connector"]
O2_CHECKS = ["Check the sensor's connector and wiring near the exhaust",
             "Check for exhaust leaks", "Watch the sensor's signal in live data"]
O2_DRIVE = "Safe to drive. Fuel use may go up. Get it checked soon."
# SAE numbers these like decimals (P0139 is followed by P0140), so list them.
for codes, pos, where, ignored in (
        (("P0130", "P0131", "P0132", "P0133", "P0134", "P0135"), "front",
         "before the catalytic converter",
         "The engine computer can't fine-tune the mixture: higher fuel use and a failed emissions inspection."),
        (("P0136", "P0137", "P0138", "P0139", "P0140", "P0141"), "rear",
         "after the catalytic converter",
         "A failed emissions inspection; the catalytic converter can't be monitored.")):
    sensor = "sensor 1" if pos == "front" else "sensor 2"
    variants = (("circuit", "isn't giving a usable signal"),
                ("low reading", "reads lower than it should (stuck lean)"),
                ("high reading", "reads higher than it should (stuck rich)"),
                ("slow response", "reacts too slowly to mixture changes"),
                ("no activity", "doesn't respond at all"),
                ("heater circuit", "has a fault in its built-in heater"))
    for code, (what, says) in zip(codes, variants):
        add(code, f"{pos.capitalize()} oxygen sensor {what} (bank 1 {sensor})", O2, "soon",
            f"The oxygen sensor {where} {says}.",
            O2_HEATER_CAUSES if what == "heater circuit" else O2_CAUSES,
            O2_CHECKS, O2_DRIVE, ignored)
add("P0030", "Front oxygen sensor heater control circuit (bank 1 sensor 1)", O2, "soon",
    "The heater in the oxygen sensor before the catalytic converter has a circuit fault.",
    O2_HEATER_CAUSES, O2_CHECKS, O2_DRIVE,
    "Higher emissions after cold starts and a failed emissions inspection.")
add("P0036", "Rear oxygen sensor heater control circuit (bank 1 sensor 2)", O2, "soon",
    "The heater in the oxygen sensor after the catalytic converter has a circuit fault.",
    O2_HEATER_CAUSES, O2_CHECKS, O2_DRIVE,
    "A failed emissions inspection; the catalytic converter can't be monitored.")

# --- Fuel vapor (EVAP) ------------------------------------------------------------------------------

EVAP = "Fuel vapor (EVAP)"
EVAP_DRIVE = "Safe to drive. This affects emissions, not how the car runs."
EVAP_IGNORED = "Fuel smell and a failed emissions inspection."
add("P0440", "Fuel vapor system fault", EVAP, "info",
    "A fault in the system that stores fuel tank vapor and burns it in the engine.",
    ["Loose or damaged fuel cap", "Cracked vapor hose", "Purge valve", "Leak detection pump",
     "Charcoal canister"],
    ["Check that the fuel cap is tight and its seal is intact",
     "Inspect the vapor hoses near the tank and engine"],
    EVAP_DRIVE, EVAP_IGNORED)
add("P0441", "Fuel vapor purge flow incorrect", EVAP, "info",
    "Fuel vapor isn't flowing from the canister to the engine the way it should.",
    ["Purge valve stuck", "Blocked or cracked purge line"],
    ["Check the purge valve opens and closes", "Inspect the purge line"],
    EVAP_DRIVE, EVAP_IGNORED)
add("P0442", "Small fuel vapor leak", EVAP, "info",
    "The vapor system's leak test found a small leak.",
    ["Fuel cap seal", "Small crack in a vapor hose", "Leak detection pump", "Canister or its seals"],
    ["Check the fuel cap seal", "Have a smoke test done on the vapor system"],
    EVAP_DRIVE, EVAP_IGNORED)
add("P0455", "Large fuel vapor leak", EVAP, "info",
    "The vapor system's leak test found a large leak.",
    ["Fuel cap missing or loose", "Disconnected or cracked vapor hose", "Purge valve stuck open"],
    ["Check the fuel cap first", "Inspect the vapor hoses"],
    EVAP_DRIVE, EVAP_IGNORED)
add("P0456", "Very small fuel vapor leak", EVAP, "info",
    "The vapor system's leak test found a very small leak.",
    ["Fuel cap seal", "Tiny crack in a hose or seal", "Canister seal"],
    ["Check the fuel cap seal", "Have a smoke test done on the vapor system"],
    EVAP_DRIVE, EVAP_IGNORED)
add("P0457", "Fuel vapor leak (fuel cap loose or off)", EVAP, "info",
    "The vapor system found a leak that usually means the fuel cap wasn't closed properly.",
    ["Fuel cap loose, missing or damaged"],
    ["Tighten or replace the fuel cap. If that was it, the engine light goes off by itself "
     "after a few drives."],
    EVAP_DRIVE, EVAP_IGNORED)
add("P0496", "Fuel vapor purge flow when it shouldn't", EVAP, "soon",
    "Fuel vapor flows into the engine when the purge valve should be closed.",
    ["Purge valve stuck open"],
    ["Check whether the purge valve holds vacuum when it's off"],
    "Usually drivable; the engine may idle rough or start hard after refueling. Get it checked soon.",
    "Rough idle and rich mixture codes.")
for code, level in (("P0458", "low"), ("P0459", "high")):
    add(code, f"Purge valve circuit {level}", EVAP, "info",
        "Electrical fault in the circuit of the fuel vapor purge valve.",
        ["Purge valve", "Connector or wiring"],
        ["Check the valve's connector and wiring", "Measure the valve's resistance"],
        EVAP_DRIVE, EVAP_IGNORED)

# --- Battery, power and the engine computer ----------------------------------------------------------

POWER = "Battery and power"
LOW_V_CAUSES = ["Weak or old battery",
                "New battery not registered to the car (BMWs need this)",
                "Charging problem (alternator)",
                "Loose or corroded battery cables or ground",
                "Car parked for a long time"]
LOW_V_CHECKS = ["Have the battery tested", "Check charging voltage with the engine running",
                "Check the battery terminals and ground connections",
                "If the battery was replaced, make sure it was registered"]
LOW_V_DRIVE = ("Get it checked soon: low voltage makes other modules store faults and can stop "
               "the car starting.")
add("P0562", "System voltage low", POWER, "soon",
    "The engine computer saw battery voltage below normal.",
    LOW_V_CAUSES, LOW_V_CHECKS, LOW_V_DRIVE,
    "A no-start, and random warnings from other modules.")
add("P0563", "System voltage high", POWER, "soon",
    "The engine computer saw battery voltage above normal.",
    ["Charging system overcharging", "New battery not registered to the car",
     "Jump start or charger connected incorrectly"],
    ["Check charging voltage with the engine running",
     "If the battery was replaced, make sure it was registered"],
    "Get it checked soon: high voltage can damage the battery and electronics.",
    "Damage to the battery and electronics.")
add("U3003", "Battery voltage out of range", POWER, "soon",
    "This module saw battery voltage outside its normal range.",
    LOW_V_CAUSES, LOW_V_CHECKS, LOW_V_DRIVE,
    "A no-start, and random warnings from other modules.")

ECU = "Engine computer"
add("P0600", "Engine computer data link fault", ECU, "soon",
    "The engine computer has a problem talking to another module.",
    ["Data bus wiring or connector", "Low voltage", "Another module failing"],
    ["Look for lost-communication codes in other modules", "Have the battery tested"],
    None, "Other functions that depend on that data may stop working.")
add("P0601", "Engine computer memory checksum error", ECU, "now",
    "The engine computer found an error in its own memory or software.",
    ["Software update or tune flash interrupted or corrupted", "Engine computer fault"],
    ["Note whether software was recently updated or flashed",
     "Have the software checked by a dealer or the tune's supplier"],
    "The engine may not run properly or may not start. Get it checked now.",
    "The car can leave you stranded.")
add("P0606", "Engine computer processor fault", ECU, "now",
    "The engine computer found a fault in its own processor.",
    ["Engine computer fault", "Low voltage or a bad ground", "Software problem"],
    ["Have the battery and grounds checked", "Have the engine computer diagnosed"],
    "The engine may run poorly or stall. Get it checked now.",
    "The car can leave you stranded.")
for code, letter in (("P0641", "A"), ("P0651", "B")):
    add(code, f"Sensor 5 V supply {letter} out of range", ECU, "now",
        f"The engine computer's 5 V supply {letter}, shared by a group of sensors, is out of range.",
        ["One shorted sensor on that supply (it pulls the others down)", "Wiring short",
         "Engine computer"],
        ["Unplug sensors on that supply one at a time to find the one pulling it down",
         "Check the wiring for chafing"],
        "Several sensors drop out at once, so the engine may run badly. Get it checked now.",
        "Poor running or the car stopping.")
add("P0657", "Actuator supply voltage A circuit", ECU, "soon",
    "The power supply to a group of actuators is out of range.",
    ["Relay or fuse", "Wiring", "A shorted actuator"],
    ["Check the related fuses and relays", "Check the wiring"],
    None, "The parts on that supply stop working.")
add("P0685", "Engine computer main relay control circuit", ECU, "now",
    "Fault in the circuit that switches the engine computer's main power relay.",
    ["Main relay", "Fuse", "Wiring"],
    ["Check the main relay and its fuses", "Check the wiring"],
    "The engine may not start or may cut out. Get it checked now.",
    "The car can leave you stranded.")

# --- Cooling and oil -------------------------------------------------------------------------------------

COOL = "Cooling"
add("P0128", "Engine warms up too slowly (thermostat)", COOL, "soon",
    "The coolant stays below the thermostat's working temperature for too long, which "
    "usually means the thermostat is stuck open.",
    ["Thermostat stuck open (BMW uses an electronically controlled one)",
     "Coolant temperature sensor reading low", "Very cold weather with a lot of idling"],
    ["Watch coolant temperature in live data after a cold start",
     "Look for thermostat heater codes (P0597-P0599)"],
    "Safe to drive. Heating and fuel use suffer. Get it fixed soon.",
    "Higher fuel use and engine wear from running cold, and possibly a failed emissions inspection.")
add("P0217", "Engine overheating", COOL, "stop",
    "The engine got too hot.",
    ["Low coolant from a leak", "Water pump failing (many BMW engines use an electric one)",
     "Thermostat stuck closed", "Cooling fan not working", "Clogged radiator"],
    ["Stop and let the engine cool before opening anything",
     "Check the coolant level when cold", "Check that the fan and water pump work"],
    "Stop as soon as it's safe and switch the engine off. Driving while overheating can wreck "
    "the engine.",
    "A warped cylinder head, blown head gasket or ruined engine.")
add("P0480", "Cooling fan control circuit", COOL, "now",
    "Fault in the circuit that controls the engine's cooling fan.",
    ["Fan motor or its control electronics", "Wiring", "Fuse"],
    ["Check whether the fan runs when the engine is hot", "Check fuses and connectors"],
    "Watch the temperature: the engine can overheat in traffic. Get it checked now.",
    "Overheating and engine damage.")
for code, what in (("P0597", "open"), ("P0598", "low"), ("P0599", "high")):
    add(code, f"Thermostat heater circuit {what}", COOL, "soon",
        "BMW thermostats have an electric heater the engine computer uses to open them early; "
        "its circuit has a fault.",
        ["Thermostat heater failed (the thermostat is replaced as one part)", "Connector or wiring"],
        ["Check the thermostat's connector", "Measure the heater's resistance"],
        "Safe to drive in normal conditions; keep an eye on the temperature. Get it checked soon.",
        "The engine runs at a less ideal temperature: more fuel use or more heat under load.")

OIL = "Oil pressure"
add("P0520", "Oil pressure sensor circuit", OIL, "soon",
    "Electrical fault in the oil pressure sensor's circuit.",
    ["Oil pressure sensor", "Connector or wiring"],
    ["Check the oil level", "Check the sensor's connector and wiring"],
    "If the red oil warning comes on, stop the engine at once. Otherwise get it checked soon.",
    "The car can't warn you about low oil pressure.")
add("P0521", "Oil pressure sensor range/performance", OIL, "now",
    "The oil pressure reading doesn't match what the engine computer expects.",
    ["Low oil level", "Oil pressure sensor", "Oil pump or its pressure control"],
    ["Check the oil level now", "Have the actual oil pressure measured"],
    "Check the oil level now. If the red oil warning comes on, stop the engine.",
    "If the pressure really is low, the engine can be destroyed.")
add("P0524", "Oil pressure too low", OIL, "stop",
    "Oil pressure dropped below the safe minimum.",
    ["Low oil level", "Oil pump or its control valve", "Wrong oil viscosity",
     "Worn engine bearings", "Faulty sensor"],
    ["Stop and check the oil level", "Don't drive while the red oil warning is on",
     "Have the actual oil pressure measured"],
    "Stop the engine as soon as it's safe. Low oil pressure can destroy the engine in minutes.",
    "Engine failure.")

# --- Idle, speed and brakes ------------------------------------------------------------------------------

IDLE = "Idle"
add("P0506", "Idle speed lower than expected", IDLE, "info",
    "The engine idles slower than the engine computer wants.",
    ["Dirty throttle body", "Intake restriction", "Vacuum leak", "Heavy electrical or A/C load"],
    ["Inspect and clean the throttle body", "Check for vacuum leaks"],
    None, "Rough idle or stalling.")
add("P0507", "Idle speed higher than expected", IDLE, "info",
    "The engine idles faster than the engine computer wants.",
    ["Vacuum leak", "Crankcase ventilation leak", "Throttle body"],
    ["Check for vacuum leaks", "Inspect the throttle body"],
    None, "Higher fuel use; leaks usually get worse.")

BRAKES = "Speed and brakes"
add("P0500", "Vehicle speed signal", BRAKES, "soon",
    "The engine computer isn't getting a usable vehicle speed signal.",
    ["Wheel speed sensor (BMW uses the ABS sensors for speed)", "Stability control (DSC) module",
     "Wiring"],
    ["Look for codes in the stability control (DSC) module", "Check the wheel speed sensors"],
    "Speedometer, cruise control and shifting may be affected. Get it checked soon.",
    "Wrong shifting and disabled driver assistance.")
add("P0504", "Brake switch signals disagree", BRAKES, "soon",
    "The two signals from the brake light switch don't agree.",
    ["Brake light switch", "Wiring"],
    ["Check that the brake lights work", "Check the switch and its connector"],
    "Check your brake lights work. Cruise control may not work. Get it checked soon.",
    "Brake lights or cruise control may stop working.")
add("P0571", "Brake switch circuit", BRAKES, "soon",
    "Electrical fault in the brake light switch circuit.",
    ["Brake light switch", "Wiring"],
    ["Check that the brake lights work", "Check the switch and its connector"],
    "Check your brake lights work. Cruise control may not work. Get it checked soon.",
    "Brake lights or cruise control may stop working.")

# --- Transmission ----------------------------------------------------------------------------------------

GEARBOX = "Transmission"
add("P0700", "Transmission fault (warning light request)", GEARBOX, "soon",
    "The transmission computer stored its own fault and asked for the engine light.",
    ["See the transmission (EGS) module's codes for the actual fault"],
    ["Read the codes in the transmission module"],
    "If it shifts normally, drive gently and get it checked soon. If it stays in one gear, "
    "limit driving.",
    "Transmission damage if the underlying fault is mechanical.")
add("P0715", "Transmission input speed sensor circuit", GEARBOX, "now",
    "The transmission isn't getting a usable signal from its input speed sensor.",
    ["Speed sensor (often part of the transmission's control unit)", "Wiring or connector"],
    ["Check the transmission's connector for oil or damage", "Read the transmission's codes"],
    "Expect harsh shifts or a limp mode stuck in one gear. Get it checked now.",
    "Transmission damage from bad shifting.")
add("P0730", "Incorrect gear ratio", GEARBOX, "now",
    "The transmission's input and output speeds don't match the selected gear: something "
    "is slipping.",
    ["Low or worn transmission fluid", "Worn clutches inside the transmission",
     "Valve body or control unit fault"],
    ["Have the fluid level and condition checked", "Read the transmission's codes"],
    "Drive gently and get it checked now.",
    "More transmission wear and an expensive repair.")
add("P0741", "Torque converter clutch performance", GEARBOX, "soon",
    "The torque converter's lock-up clutch isn't engaging as it should.",
    ["Transmission fluid level or condition", "Torque converter clutch", "Valve body solenoid"],
    ["Have the fluid checked", "Read the transmission's codes"],
    None, "Higher fuel use and transmission heat.")

# --- Module network (U codes) ----------------------------------------------------------------------------

NET = "Module network"
add("U0001", "High-speed CAN bus fault", NET, "soon",
    "A fault on the high-speed data network that links the car's modules.",
    ["Wiring or connector on the bus", "A module disturbing the bus", "Low voltage"],
    ["Have the battery tested", "Look for lost-communication codes in several modules"],
    "If the car behaves normally and no warnings show, it may be history. Otherwise get it "
    "checked soon.",
    "Features that need that data may stop working.")
LOST = (("U0100", "engine computer"), ("U0101", "transmission computer"),
        ("U0121", "ABS / stability control module"), ("U0126", "steering angle sensor module"),
        ("U0131", "power steering module"), ("U0140", "body control module"),
        ("U0151", "airbag module"), ("U0155", "instrument cluster"),
        ("U0164", "climate control module"), ("U0184", "radio / head unit"))
for code, target in LOST:
    add(code, f"Lost communication with the {target}", NET, "soon",
        f"This module stopped hearing from the {target}.",
        ["Low battery voltage, or the battery was flat or disconnected at some point",
         f"Power, fuse or ground for the {target}", "Data bus wiring or connector",
         f"The {target} itself"],
        ["If the car behaves normally now, it may be history from a battery event",
         "See which other modules report the same thing",
         f"Check the {target}'s fuses and connectors"],
        "If the car drives normally and no warnings show, it's likely history. Otherwise get it "
        "checked soon.",
        f"Features that depend on the {target} may not work.")
for code, target in (("U0401", "engine computer"), ("U0415", "ABS / stability control module")):
    add(code, f"Invalid data from the {target}", NET, "soon",
        f"This module received data from the {target} that it didn't trust.",
        [f"A fault inside the {target} (check its own codes)",
         "Software or coding mismatch after a repair or update", "Data bus problem"],
        [f"Read the codes in the {target}", "Note any recent repairs or software updates"],
        None, f"Features that depend on the {target} may not work.")


def build() -> dict:
    return {
        "_comment": "Generated by tools/make_code_library.py - edit there, not here. Generic "
                    "OBD-II code meanings with plain-English guidance; not a diagnosis. BMW's "
                    "own fault code texts are proprietary and not included.",
        "version": 1,
        "codes": [CODES[k] for k in sorted(CODES)],
    }


def render() -> str:
    return json.dumps(build(), indent=1, ensure_ascii=False) + "\n"


def main(argv=None) -> int:
    out = (argv or sys.argv[1:] or [OUT])[0]
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write(render())
    print(f"{len(CODES)} codes -> {os.path.relpath(out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
