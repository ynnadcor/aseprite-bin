# SPDX-License-Identifier: MIT
"""Data Identifier (DID) catalogue.

Two tiers:

  * STANDARD_DIDS - ISO 14229 / ISO 14229-1 "common" identifiers that virtually
    every UDS ECU implements the same way. These are safe to read and their
    meaning is stable across vehicles.

  * BMW_CANDIDATE_DIDS - identifiers that are *believed* to expose the live
    B58 values the user wants (boost, oil temp, IAT, coolant, load). These are
    marked UNVERIFIED on purpose: the exact DID numbers and their scaling on a
    2018 G30 B58 must be captured from the real car (a user-dependent step),
    because BMW live data is more commonly delivered via module-specific
    identifiers/measurement blocks than via fixed standard DIDs.

Never present a BMW_CANDIDATE value to the user as a real reading until it has
been confirmed against the car; the app surfaces them as "unconfirmed".
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Dict, Optional


@dataclass(frozen=True)
class Did:
    did: int
    name: str
    verified: bool
    # optional decoder: bytes -> human value; None means "show raw/ascii"
    decode: Optional[Callable[[bytes], object]] = None
    unit: str = ""
    note: str = ""


def _ascii(b: bytes) -> str:
    return b.decode("ascii", errors="replace").rstrip("\x00 ")


# ---- standard, stable identifiers -------------------------------------------
STANDARD_DIDS: Dict[int, Did] = {
    0xF190: Did(0xF190, "VIN", True, _ascii, note="ISO VIN data identifier"),
    0xF18C: Did(0xF18C, "ECU serial number", True, _ascii),
    0xF191: Did(0xF191, "ECU hardware number", True, _ascii),
    0xF194: Did(0xF194, "Supplier software version", True, _ascii),
    0xF195: Did(0xF195, "Application software version", True, _ascii),
    0xF197: Did(0xF197, "System name / ECU name", True, _ascii),
    0xF1A2: Did(0xF1A2, "Application data identification", True, _ascii),
    0xF186: Did(0xF186, "Active diagnostic session", True,
                lambda b: b[0] if b else None),
}


# ---- UNVERIFIED BMW/B58 live-value candidates -------------------------------
# Scalings below are the usual A*factor+offset conventions but MUST be confirmed.
def _temp_offset(b: bytes) -> Optional[float]:
    # common convention: value in degC = raw - 40  (1 byte)
    return (b[0] - 40) if b else None


def _u16(b: bytes) -> Optional[int]:
    return (b[0] << 8 | b[1]) if len(b) >= 2 else None


BMW_CANDIDATE_DIDS: Dict[int, Did] = {
    0xDD01: Did(0xDD01, "Coolant temperature (candidate)", False, _temp_offset,
                "degC", "UNVERIFIED - confirm DID & scaling on-car"),
    0xDD02: Did(0xDD02, "Intake air temperature (candidate)", False, _temp_offset,
                "degC", "UNVERIFIED - confirm DID & scaling on-car"),
    0xDD03: Did(0xDD03, "Oil temperature (candidate)", False, _temp_offset,
                "degC", "UNVERIFIED - confirm DID & scaling on-car"),
    0xDD04: Did(0xDD04, "Charge/boost pressure (candidate)", False, _u16,
                "mbar", "UNVERIFIED - confirm DID & scaling on-car"),
    0xDD05: Did(0xDD05, "Engine load (candidate)", False,
                lambda b: (b[0] * 100.0 / 255.0) if b else None,
                "%", "UNVERIFIED - confirm DID & scaling on-car"),
}


def lookup(did: int) -> Optional[Did]:
    return STANDARD_DIDS.get(did) or BMW_CANDIDATE_DIDS.get(did)
