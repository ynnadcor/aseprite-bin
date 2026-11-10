# SPDX-License-Identifier: MIT
"""BMW HSFZ framing (ENET protocol of F-series and most G-series BMWs).

Mirrors ios-app/BMWLinkKit/Sources/BMWLinkKit/HSFZ.swift. Facts from public
references (Quantex HSFZ notes, scapy's HSFZ layer, EdiabasLib):

  TCP 6801 diagnostics, UDP 6811 vehicle identification (discovery).
  frame = length(4, big-endian, bytes after the 6-byte header)
        + control(2) + payload
  diagnostic payload = source(1) + target(1) + UDS
  ack (0x0002) echoes at most 13 bytes of the request; bare 0x00FF = NACK;
  alive check 0x0012 must be answered with 0x0013 [0x00, tester].
"""

from __future__ import annotations

import struct
from typing import Optional, Tuple, Dict

DIAG_PORT = 6801
IDENT_PORT = 6811
HEADER_LEN = 6
TESTER_ADDRESS = 0xF4
MAX_ACK_LEN = 13

CTRL_DIAGNOSTIC = 0x0001
CTRL_ACK = 0x0002
CTRL_VEHICLE_IDENT = 0x0011
CTRL_ALIVE_CHECK = 0x0012
CTRL_ALIVE_CHECK_RESPONSE = 0x0013
CTRL_NACK = 0x00FF


def frame(control: int, payload: bytes = b"") -> bytes:
    return struct.pack(">IH", len(payload), control) + bytes(payload)


def frame_length(header: bytes) -> Optional[int]:
    """Total frame length once the 6 header bytes are available."""
    if len(header) < HEADER_LEN:
        return None
    return HEADER_LEN + struct.unpack(">I", header[:4])[0]


def parse(f: bytes) -> Tuple[int, bytes]:
    total = frame_length(f)
    if total is None:
        raise ValueError("short HSFZ frame")
    if len(f) != total:
        raise ValueError("HSFZ length mismatch")
    control = struct.unpack(">H", f[4:6])[0]
    return control, f[HEADER_LEN:]


def build_ident_request() -> bytes:
    return frame(CTRL_VEHICLE_IDENT)


def build_diagnostic(source: int, target: int, uds: bytes) -> bytes:
    return frame(CTRL_DIAGNOSTIC, bytes([source & 0xFF, target & 0xFF]) + bytes(uds))


def build_alive_check_response(tester: int = TESTER_ADDRESS) -> bytes:
    return frame(CTRL_ALIVE_CHECK_RESPONSE, bytes([0x00, tester & 0xFF]))


def ack_matches(ack: bytes, request: bytes) -> bool:
    if not (HEADER_LEN <= len(ack) <= len(request)) or len(ack) > MAX_ACK_LEN:
        return False
    return ack[HEADER_LEN:] == request[HEADER_LEN:len(ack)]


def build_ident_reply(diag_address: int, mac: str, vin: str) -> bytes:
    text = "DIAGADR%02X" % diag_address + "BMWMAC" + mac + "BMWVIN" + vin
    return frame(CTRL_VEHICLE_IDENT, text.encode("ascii"))


def parse_ident_reply(f: bytes) -> Optional[Dict[str, object]]:
    try:
        control, payload = parse(f)
    except ValueError:
        return None
    if control != CTRL_VEHICLE_IDENT:
        return None
    text = payload.decode("ascii", errors="replace")
    i = text.find("DIAGADR")
    if i < 0:
        return None
    addr_txt = text[i + 7:i + 9]
    try:
        addr = int(addr_txt, 16)
    except ValueError:
        return None
    mac = ""
    j = text.find("BMWMAC")
    if j >= 0:
        mac = text[j + 6:j + 18]
    vin = ""
    k = text.find("BMWVIN")
    if k >= 0:
        vin = text[k + 6:k + 23]
    return {"diag_address": addr, "mac": mac, "vin": vin}
