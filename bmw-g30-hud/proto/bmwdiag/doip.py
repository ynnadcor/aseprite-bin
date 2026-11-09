# SPDX-License-Identifier: MIT
"""ISO 13400-2 (DoIP) encoding/decoding - the subset we need, read-only.

DoIP is the protocol that carries UDS diagnostics over Ethernet. On a BMW you
reach it through the OBD port with an ENET (OBD->Ethernet) cable; the car's
gateway (ZGW) is a DoIP "edge node" that announces itself and routes diagnostic
messages to modules by logical address.

Generic DoIP message layout (big-endian):

    +----------+------------------+--------------+----------------+-----------+
    | version  | inverse version  | payload type | payload length | payload   |
    | 1 byte   | 1 byte           | 2 bytes      | 4 bytes        | n bytes   |
    +----------+------------------+--------------+----------------+-----------+

We implement only: vehicle identification request, parsing of the vehicle
announcement, routing activation request/response, and the diagnostic-message
wrapper (which carries UDS). Nothing here writes to the car by itself; writing
is a property of the UDS *service* inside a diagnostic message, and the UDS
layer forbids write services.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from enum import IntEnum
from typing import Tuple, Optional

# BMW ENET uses DoIP protocol version 0x02 (ISO 13400-2:2012).
PROTOCOL_VERSION = 0x02

# Well-known logical addresses. The tester (our app) commonly uses 0x0E00..0x0EFF.
DEFAULT_TESTER_ADDRESS = 0x0E00
# The central gateway (ZGW) on BMW F/G chassis is typically 0x0010; the head
# unit (NBT EVO / HU) is commonly 0x0063 (confirm on the real car via scan).
ZGW_ADDRESS = 0x0010
HEADUNIT_ADDRESS = 0x0063


class PayloadType(IntEnum):
    GENERIC_NACK = 0x0000
    VEHICLE_ID_REQUEST = 0x0001
    VEHICLE_ANNOUNCEMENT = 0x0004  # also the vehicle identification response
    ROUTING_ACTIVATION_REQUEST = 0x0005
    ROUTING_ACTIVATION_RESPONSE = 0x0006
    ALIVE_CHECK_REQUEST = 0x0007
    ALIVE_CHECK_RESPONSE = 0x0008
    DIAGNOSTIC_MESSAGE = 0x8001
    DIAGNOSTIC_POSITIVE_ACK = 0x8002
    DIAGNOSTIC_NEGATIVE_ACK = 0x8003


class RoutingActivationResponseCode(IntEnum):
    SUCCESS = 0x10
    DENIED_UNKNOWN_SOURCE = 0x00
    DENIED_ALL_SOCKETS_REGISTERED = 0x01
    DENIED_SOURCE_MISMATCH = 0x02
    DENIED_SOURCE_IN_USE = 0x03
    DENIED_MISSING_AUTH = 0x04
    DENIED_REJECTED_CONFIRMATION = 0x05
    DENIED_UNSUPPORTED_TYPE = 0x06


_HEADER = struct.Struct(">BBHI")  # version, inv, type, length


@dataclass
class DoIPHeader:
    payload_type: int
    payload_length: int
    version: int = PROTOCOL_VERSION

    def encode(self, payload: bytes = b"") -> bytes:
        inv = (~self.version) & 0xFF
        return _HEADER.pack(self.version, inv, self.payload_type, len(payload)) + payload


def _frame(payload_type: int, payload: bytes) -> bytes:
    return DoIPHeader(payload_type, len(payload)).encode(payload)


def parse_header(data: bytes) -> Tuple[DoIPHeader, bytes]:
    """Parse the 8-byte header, validate the inverse-version byte, and return
    (header, remaining-bytes-after-header). Raises ValueError on malformed data.
    """
    if len(data) < _HEADER.size:
        raise ValueError("short DoIP header")
    version, inv, ptype, plen = _HEADER.unpack(data[: _HEADER.size])
    if (version ^ inv) != 0xFF:
        raise ValueError("DoIP inverse version mismatch")
    rest = data[_HEADER.size :]
    return DoIPHeader(ptype, plen, version), rest


# ---- request builders (read-only safe) --------------------------------------

def build_vehicle_identification_request() -> bytes:
    """Broadcast-style identification request (empty payload)."""
    return _frame(PayloadType.VEHICLE_ID_REQUEST, b"")


def build_routing_activation_request(
    tester_address: int = DEFAULT_TESTER_ADDRESS,
    activation_type: int = 0x00,
) -> bytes:
    """Routing activation. Activation type 0x00 = default (diagnostics).

    Payload: source(2) + activation_type(1) + reserved(4=0). We omit the
    optional OEM-specific 4 bytes (allowed by the spec).
    """
    payload = struct.pack(">HB", tester_address & 0xFFFF, activation_type & 0xFF)
    payload += b"\x00\x00\x00\x00"  # reserved
    return _frame(PayloadType.ROUTING_ACTIVATION_REQUEST, payload)


def build_diagnostic_message(
    source_address: int, target_address: int, uds_payload: bytes
) -> bytes:
    """Wrap a UDS payload in a DoIP diagnostic message (0x8001)."""
    payload = struct.pack(">HH", source_address & 0xFFFF, target_address & 0xFFFF)
    payload += bytes(uds_payload)
    return _frame(PayloadType.DIAGNOSTIC_MESSAGE, payload)


# ---- response parsers --------------------------------------------------------

@dataclass
class VehicleAnnouncement:
    vin: str
    logical_address: int
    eid: bytes  # 6 bytes (usually MAC)
    gid: bytes  # 6 bytes
    further_action: int


def parse_vehicle_announcement(payload: bytes) -> VehicleAnnouncement:
    """Parse a 0x0004 payload: VIN(17) + LA(2) + EID(6) + GID(6) + FA(1)[+...]."""
    if len(payload) < 17 + 2 + 6 + 6 + 1:
        raise ValueError("short vehicle announcement")
    vin = payload[:17].decode("ascii", errors="replace").rstrip("\x00 ")
    la = struct.unpack(">H", payload[17:19])[0]
    eid = payload[19:25]
    gid = payload[25:31]
    fa = payload[31]
    return VehicleAnnouncement(vin, la, eid, gid, fa)


@dataclass
class RoutingActivationResponse:
    tester_address: int
    entity_address: int
    response_code: int

    @property
    def ok(self) -> bool:
        return self.response_code == RoutingActivationResponseCode.SUCCESS


def parse_routing_activation_response(payload: bytes) -> RoutingActivationResponse:
    """Parse a 0x0006 payload: tester_LA(2) + entity_LA(2) + code(1) + reserved(4)."""
    if len(payload) < 5:
        raise ValueError("short routing activation response")
    tester, entity = struct.unpack(">HH", payload[:4])
    code = payload[4]
    return RoutingActivationResponse(tester, entity, code)


@dataclass
class DiagnosticMessage:
    source_address: int
    target_address: int
    uds: bytes


def parse_diagnostic_message(payload: bytes) -> DiagnosticMessage:
    """Parse a 0x8001 payload: source(2) + target(2) + UDS(n)."""
    if len(payload) < 4:
        raise ValueError("short diagnostic message")
    src, tgt = struct.unpack(">HH", payload[:4])
    return DiagnosticMessage(src, tgt, payload[4:])
