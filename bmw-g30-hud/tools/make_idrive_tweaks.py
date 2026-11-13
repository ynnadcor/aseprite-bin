#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Builds the iDrive customization catalog the BMW Link app shows.

    python3 tools/make_idrive_tweaks.py

writes ios-app/BMWLinkKit/Sources/BMWLinkKit/Resources/idrive-tweaks.json.
Edit the data below, not the JSON; tests/test_idrive_tweaks.py fails when the
JSON is out of date.

What this is: a curated list of well-known, reversible coding changes for a
2018 G30 with NBT EVO (iDrive 6), the kind BimmerCode exposes as friendly
toggles. Each entry says what it does, where to find it, caveats and how to
undo it. The owner applies changes in BimmerCode; BMW Link never writes coding.

What this is NOT: a guarantee. Which features your car supports depends on its
equipment and software version. BimmerCode only shows the ones that apply to
your car, and that is the source of truth. Anything that modifies the head
unit's software (themes, extra apps) is deliberately out of scope here: that
needs unlocking the head unit, a separate, risky path (see
docs/idrive-customization.md), and this app won't do it.
"""

from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "ios-app", "BMWLinkKit", "Sources", "BMWLinkKit",
                   "Resources", "idrive-tweaks.json")

# Where BimmerCode groups the change. These are the modules BMW Link can already
# see in a scan, so the app can tell you which ones your car answered.
MODULES = {
    "HU": ("Head unit (NBT EVO)", 0x63),
    "KOMBI": ("Instrument cluster (KOMBI)", 0x60),
    "HUD": ("Instrument cluster (KOMBI)", 0x60),   # HUD content is coded in KOMBI
    "BDC": ("Body domain controller (BDC)", 0x40),
}

CATEGORIES = ("Apple CarPlay", "Displays & HUD", "Media & video", "Navigation",
              "Phone & voice", "Comfort", "Startup & appearance", "Menus")

# risk: "green"  = infotainment/comfort only, fully reversible
#       "amber"  = reversible, but has a real caveat (legality, distraction, wear)
RISKS = ("green", "amber")

TWEAKS: list = []


def add(id, title, category, module, what, why, how, undo, risk="green",
        caveat=None, needs=None):
    assert category in CATEGORIES, category
    assert module in MODULES, module
    assert risk in RISKS, risk
    assert not any(t["id"] == id for t in TWEAKS), f"duplicate {id}"
    name, address = MODULES[module]
    TWEAKS.append({
        "id": id,
        "title": title,
        "category": category,
        "module": name,
        "moduleAddress": address,
        "what": what,
        "why": why,
        "how": how,
        "undo": undo,
        "risk": risk,
        "caveat": caveat,
        # What equipment the car needs for the option to exist, in plain words.
        "needs": needs,
    })


# --- Apple CarPlay --------------------------------------------------------------

add("carplay-fullscreen", "Apple CarPlay full-screen", "Apple CarPlay", "HU",
    "Makes CarPlay fill the whole iDrive screen instead of leaving BMW's side band of widgets.",
    "CarPlay maps and apps get the full display, which is easier to read while driving.",
    "BimmerCode -> Head unit (HU) -> look for “Apple CarPlay” / “CarPlay fullscreen” and turn it on.",
    "Set it back to the factory value (the split view).",
    needs="Apple CarPlay already active on the car (your car has wireless CarPlay).")

add("carplay-no-expiry", "Keep CarPlay from expiring", "Apple CarPlay", "HU",
    "Removes the time limit some cars put on the CarPlay enablement so it stays on for good.",
    "CarPlay keeps working without a renewal or a dealer visit.",
    "BimmerCode -> Head unit (HU): the CarPlay/feature-enablement option. On many G30s CarPlay is already permanent; check first.",
    "Restore the original value.",
    caveat="Only relevant if your CarPlay was ever shown as time-limited. Yours already works, so this may not apply.")

# --- Displays & HUD -------------------------------------------------------------

add("sport-displays", "Sport displays (gauges on iDrive)", "Displays & HUD", "HU",
    "Turns on BMW's own performance pages: a digital power and torque gauge, plus consumption, on the iDrive screen.",
    "This is the factory way to get real gauges on the iDrive screen — no head-unit modification needed.",
    "BimmerCode -> Head unit (HU) -> “Sport displays” / “M Sport displays” -> on. Then on the car: Menu -> your vehicle -> the Sport/performance view.",
    "Turn the option back off.",
    needs="NBT EVO (you have it). The look is BMW's; it isn't a custom gauge you design.")

add("digital-speed-hud", "Digital speed in the Head-Up Display", "Displays & HUD", "HUD",
    "Adds a digital km/h or mph number to the colour Head-Up Display.",
    "A clear speed readout in your line of sight.",
    "BimmerCode -> Instrument cluster (KOMBI) -> HUD content -> enable the digital speed field.",
    "Remove the field in the same place.",
    needs="The factory Head-Up Display (your car has it).")

add("hud-extra-content", "More content in the Head-Up Display", "Displays & HUD", "HUD",
    "Shows extra items in the HUD such as the speed-limit sign, entertainment and phone info.",
    "More at-a-glance information without looking down.",
    "BimmerCode -> Instrument cluster (KOMBI) -> HUD content -> enable the fields you want.",
    "Turn the individual fields back off.",
    risk="amber",
    caveat="A busy HUD can be distracting; add fields one at a time and keep what helps.",
    needs="The factory Head-Up Display.")

add("digital-speed-cluster", "Digital speed in the cluster", "Displays & HUD", "KOMBI",
    "Adds a digital speed number to the instrument cluster.",
    "An exact speed without reading the analogue needle.",
    "BimmerCode -> Instrument cluster (KOMBI) -> the digital-speed option.",
    "Turn it back off.")

add("consumption-display", "Extra consumption & efficiency views", "Displays & HUD", "KOMBI",
    "Unlocks extra trip and efficiency readouts in the cluster and iDrive.",
    "More detail on how the car is driving and using fuel.",
    "BimmerCode -> Instrument cluster (KOMBI) / Head unit (HU): the consumption/statistics options.",
    "Turn the options back off.")

# --- Media & video --------------------------------------------------------------

add("video-in-motion", "Video in motion", "Media & video", "HU",
    "Lets the screen play video (and CarPlay video apps) while the car is moving, instead of only when parked.",
    "A passenger can watch video on a drive.",
    "BimmerCode -> Head unit (HU) -> “Video in motion” / “VIM” -> on.",
    "Turn it back off.",
    risk="amber",
    caveat="For passenger use. Watching video while driving is unsafe and illegal in most places — don't use it in the driver's view while moving.")

add("usb-video", "Play video from USB", "Media & video", "HU",
    "Enables playing video files from a USB stick through iDrive.",
    "Watch your own media without extra hardware.",
    "BimmerCode -> Head unit (HU): the USB/media video option, where present.",
    "Turn it back off.",
    risk="amber",
    caveat="Same as video in motion: passenger use only while driving.")

# --- Navigation -----------------------------------------------------------------

add("nav-map-hud", "Navigation map in the HUD", "Navigation", "HUD",
    "Shows a small navigation map or richer turn arrows in the Head-Up Display.",
    "Follow directions without glancing at the centre screen.",
    "BimmerCode -> Instrument cluster (KOMBI) -> HUD content -> navigation.",
    "Turn the navigation HUD content back off.",
    needs="Factory navigation and the Head-Up Display (your car has both).")

add("faster-boot", "Faster screen wake", "Navigation", "HU",
    "Tweaks a start-up delay so the screen and map come up sooner after the car is unlocked.",
    "Less waiting for iDrive after you get in.",
    "BimmerCode -> Head unit (HU): the quick-start / standby options, where present.",
    "Restore the factory value.",
    risk="amber",
    caveat="Keeping the head unit more awake can draw a little more power when parked; fine with regular driving.")

# --- Phone & voice --------------------------------------------------------------

add("enhanced-bluetooth", "Second phone / full Bluetooth", "Phone & voice", "HU",
    "Enables pairing a second phone at once and the fuller Bluetooth office/streaming features.",
    "Two phones connected, and more phone features in iDrive.",
    "BimmerCode -> Head unit (HU) -> the telephony / Bluetooth feature options.",
    "Turn the options back off.")

# --- Comfort --------------------------------------------------------------------

add("legal-disclaimer-off", "Skip the “I agree” start-up screen", "Comfort", "HU",
    "Stops iDrive from showing the legal warning you have to confirm every time the car starts.",
    "iDrive goes straight to the map or your last screen.",
    "BimmerCode -> Head unit (HU) -> “Disclaimer” / “Legal disclaimer” -> disable.",
    "Re-enable the disclaimer.")

add("auto-lock", "Automatic door locking", "Comfort", "BDC",
    "Locks the doors automatically as you drive off, and/or unlocks when you park or take the key out.",
    "Convenience and a bit of security, set to your taste.",
    "BimmerCode -> Body (BDC) -> the auto-lock / auto-unlock options.",
    "Set them back to the factory behaviour.")

add("mirror-fold", "Fold mirrors when locking", "Comfort", "BDC",
    "Folds the door mirrors in when you lock the car and unfolds them when you unlock it.",
    "Tidier parking and a little protection in tight spots.",
    "BimmerCode -> Body (BDC) -> the mirror fold-on-lock option.",
    "Turn it back off.",
    needs="Power-folding mirrors.")

add("windows-from-key", "Windows from the key / comfort access", "Comfort", "BDC",
    "Lets you open or close the windows (and sunroof) by holding the key button or the door handle.",
    "Air the car out before you get in on a hot day.",
    "BimmerCode -> Body (BDC) -> the remote window / comfort-opening options.",
    "Turn the options back off.")

# --- Startup & appearance -------------------------------------------------------

add("startup-animation", "Start-up animation", "Startup & appearance", "KOMBI",
    "Changes the welcome animation shown on the cluster and screen at start-up (e.g. a sportier set).",
    "A nicer greeting that matches your car.",
    "BimmerCode -> Instrument cluster (KOMBI) / Head unit (HU) -> the start-up / welcome animation option.",
    "Choose the factory animation again.",
    caveat="This picks between BMW's built-in animations. A fully custom animation needs head-unit modification (out of scope).")

add("cluster-style", "Cluster style / lighting", "Startup & appearance", "KOMBI",
    "Switches between the cluster's built-in looks (e.g. the Sport red/black style) where the car offers them.",
    "A dashboard look you prefer.",
    "BimmerCode -> Instrument cluster (KOMBI) -> the cluster style / background option.",
    "Choose the factory style again.",
    needs="The cluster must have more than one built-in style.")

# --- Menus ----------------------------------------------------------------------

add("menu-ac-off", "Hide screens you don't use", "Menus", "HU",
    "Lets you turn off iDrive menu tiles and tabs you never open, where the coding allows.",
    "A cleaner iDrive with only what you use.",
    "BimmerCode -> Head unit (HU): the menu / main-menu visibility options, where present.",
    "Re-enable the tiles.",
    caveat="How much can be hidden varies by software version.")

add("idrive-shortcuts", "More favourite buttons", "Menus", "HU",
    "Unlocks extra programmable favourite buttons for iDrive functions, where supported.",
    "One-press access to the screens you use most.",
    "BimmerCode -> Head unit (HU): the favourites / programmable-button options.",
    "Set the count back to standard.")


def build() -> dict:
    return {
        "_comment": "Generated by tools/make_idrive_tweaks.py - edit there, not here. "
                    "Known reversible G30/NBT EVO coding changes, applied by the owner in "
                    "BimmerCode. BMW Link never writes coding. Availability depends on the "
                    "car; BimmerCode is the source of truth. Head-unit software mods (themes, "
                    "extra apps) are out of scope - see docs/idrive-customization.md.",
        "version": 1,
        "categories": list(CATEGORIES),
        "tweaks": [TWEAKS[i] for i in sorted(range(len(TWEAKS)),
                                             key=lambda i: (CATEGORIES.index(TWEAKS[i]["category"]),
                                                            TWEAKS[i]["title"]))],
    }


def render() -> str:
    return json.dumps(build(), indent=1, ensure_ascii=False) + "\n"


def main(argv=None) -> int:
    out = (argv or sys.argv[1:] or [OUT])[0]
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write(render())
    print(f"{len(TWEAKS)} iDrive tweaks -> {os.path.relpath(out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
