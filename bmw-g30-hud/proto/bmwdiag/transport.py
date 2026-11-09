# SPDX-License-Identifier: MIT
"""Transport abstraction + an in-memory mock DoIP server.

`Transport` is the seam that lets the whole read-only stack be developed and
tested with no vehicle. The real app provides a TCP implementation (DoIP is TCP
port 13400); here we provide `MockEnetServer`, which answers framed DoIP
requests exactly like a BMW gateway would for the read-only subset.
"""

from __future__ import annotations

import struct
from typing import Dict, List, Optional, Protocol

from . import doip
from . import uds
from .doip import PayloadType


class Transport(Protocol):
    """One framed DoIP request -> one framed DoIP response."""

    def request(self, frame: bytes) -> bytes: ...

    def close(self) -> None: ...


class MockEnetServer:
    """A deterministic stand-in for a BMW DoIP gateway (read-only subset).

    Construct with a VIN and an optional DID store / DTC list. It is a
    `Transport`, so you can hand it straight to `ReadOnlyDiagClient`.
    """

    def __init__(
        self,
        vin: str = "WBAJE7C50JWA00000",  # synthetic test VIN - not a real vehicle
        entity_address: int = doip.ZGW_ADDRESS,
        did_store: Optional[Dict[int, bytes]] = None,
        dtcs: Optional[List] = None,
    ):
        if len(vin) != 17:
            raise ValueError("VIN must be 17 chars")
        self.vin = vin
        self.entity_address = entity_address
        self.routing_active = False
        self.did_store: Dict[int, bytes] = dict(_DEFAULT_DIDS)
        self.did_store[0xF190] = vin.encode("ascii")
        if did_store:
            self.did_store.update(did_store)
        # list of (dtc_int, status)
        self.dtcs = list(dtcs) if dtcs is not None else [(0x4B1C00, 0x08)]
        self.closed = False

    # -- Transport interface --------------------------------------------------

    def request(self, frame: bytes) -> bytes:
        if self.closed:
            raise ConnectionError("transport closed")
        header, payload = doip.parse_header(frame)
        pt = header.payload_type

        if pt == PayloadType.VEHICLE_ID_REQUEST:
            return self._announce()
        if pt == PayloadType.ROUTING_ACTIVATION_REQUEST:
            return self._routing_activation(payload)
        if pt == PayloadType.DIAGNOSTIC_MESSAGE:
            return self._diag(payload)
        if pt == PayloadType.ALIVE_CHECK_REQUEST:
            return doip.DoIPHeader(PayloadType.ALIVE_CHECK_RESPONSE, 2).encode(
                struct.pack(">H", doip.DEFAULT_TESTER_ADDRESS)
            )
        # unknown -> generic NACK
        return doip.DoIPHeader(PayloadType.GENERIC_NACK, 1).encode(b"\x00")

    def close(self) -> None:
        self.closed = True

    # -- handlers -------------------------------------------------------------

    def _announce(self) -> bytes:
        payload = self.vin.encode("ascii")[:17].ljust(17, b"\x00")
        payload += struct.pack(">H", self.entity_address)
        payload += b"\xDE\xAD\xBE\xEF\x00\x01"  # EID (fake MAC)
        payload += b"\xDE\xAD\xBE\xEF\x00\x01"  # GID
        payload += b"\x00"                        # further action required = none
        return doip.DoIPHeader(PayloadType.VEHICLE_ANNOUNCEMENT, len(payload)).encode(payload)

    def _routing_activation(self, payload: bytes) -> bytes:
        tester = struct.unpack(">H", payload[:2])[0] if len(payload) >= 2 else 0
        self.routing_active = True
        body = struct.pack(">HHB", tester, self.entity_address,
                           int(doip.RoutingActivationResponseCode.SUCCESS))
        body += b"\x00\x00\x00\x00"
        return doip.DoIPHeader(PayloadType.ROUTING_ACTIVATION_RESPONSE, len(body)).encode(body)

    def _diag(self, payload: bytes) -> bytes:
        msg = doip.parse_diagnostic_message(payload)
        if not self.routing_active:
            # DoIP negative ack: routing not activated
            body = struct.pack(">HHB", msg.target_address, msg.source_address, 0x06)
            return doip.DoIPHeader(PayloadType.DIAGNOSTIC_NEGATIVE_ACK, len(body)).encode(body)

        uds_resp = self._handle_uds(msg.uds)
        # respond from module back to tester (swap src/target)
        return doip.build_diagnostic_message(
            msg.target_address, msg.source_address, uds_resp
        )

    def _handle_uds(self, req: bytes) -> bytes:
        if not req:
            return bytes([uds.NEGATIVE_RESPONSE_SID, 0x00, uds.NRC.INCORRECT_LENGTH])
        sid = req[0]

        if sid == uds.UdsService.TESTER_PRESENT:
            return bytes([sid + uds.POSITIVE_RESPONSE_OFFSET, 0x00])

        if sid == uds.UdsService.DIAGNOSTIC_SESSION_CONTROL:
            session = req[1] if len(req) > 1 else 0x01
            # timing params P2=0x0032, P2*=0x01F4 (example)
            return bytes([sid + uds.POSITIVE_RESPONSE_OFFSET, session,
                          0x00, 0x32, 0x01, 0xF4])

        if sid == uds.UdsService.READ_DATA_BY_IDENTIFIER:
            if len(req) < 3:
                return bytes([uds.NEGATIVE_RESPONSE_SID, sid, uds.NRC.INCORRECT_LENGTH])
            did = struct.unpack(">H", req[1:3])[0]
            data = self.did_store.get(did)
            if data is None:
                return bytes([uds.NEGATIVE_RESPONSE_SID, sid, uds.NRC.REQUEST_OUT_OF_RANGE])
            return struct.pack(">BH", sid + uds.POSITIVE_RESPONSE_OFFSET, did) + data

        if sid == uds.UdsService.READ_DTC_INFORMATION:
            sub = req[1] if len(req) > 1 else 0x02
            out = bytes([sid + uds.POSITIVE_RESPONSE_OFFSET, sub, 0xFF])
            for dtc, status in self.dtcs:
                out += bytes([(dtc >> 16) & 0xFF, (dtc >> 8) & 0xFF, dtc & 0xFF, status])
            return out

        # anything else -> service not supported (the client shouldn't send these)
        return bytes([uds.NEGATIVE_RESPONSE_SID, sid, uds.NRC.SERVICE_NOT_SUPPORTED])


_DEFAULT_DIDS: Dict[int, bytes] = {
    0xF18C: b"SN-0001-ABCDEF",
    0xF191: b"HW-6WA-01",
    0xF194: b"SW-03.19.22",
    0xF195: b"NBTevo_Y24073J",   # matches a confirmed-working G31 build string
    0xF197: b"HeadUnitHigh2",
    # a couple of UNVERIFIED candidate live values so the demo has something:
    0xDD01: bytes([40 + 88]),             # coolant ~88 C
    0xDD02: bytes([40 + 31]),             # IAT ~31 C
    0xDD03: bytes([40 + 104]),            # oil ~104 C
    0xDD04: (1500).to_bytes(2, "big"),    # boost ~1500 mbar abs
    0xDD05: bytes([int(0.62 * 255)]),     # load ~62%
}
