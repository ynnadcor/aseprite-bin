# SPDX-License-Identifier: MIT
"""ReadOnlyDiagClient - orchestrates a safe, read-only diagnostic session.

Flow (all non-destructive):
    1. identify()      - DoIP vehicle identification -> VIN + logical address
    2. activate()      - DoIP routing activation
    3. read_did()      - UDS ReadDataByIdentifier
    4. read_dtcs()     - UDS ReadDTCInformation (report only; never clears)
    5. tester_present()- keep-alive

The client holds no capability to write. It only ever calls the read-only
builders in `uds`, which themselves refuse non-read services.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional

from . import doip
from . import uds
from .dids import lookup, STANDARD_DIDS
from .transport import Transport


@dataclass
class VehicleInfo:
    vin: str = ""
    entity_address: int = 0
    ecu_name: str = ""
    app_sw_version: str = ""
    hw_number: str = ""
    extra: Dict[str, str] = field(default_factory=dict)


class ReadOnlyDiagClient:
    def __init__(
        self,
        transport: Transport,
        tester_address: int = doip.DEFAULT_TESTER_ADDRESS,
        target_address: int = doip.HEADUNIT_ADDRESS,
    ):
        self.t = transport
        self.tester_address = tester_address
        self.target_address = target_address
        self._activated = False

    # -- DoIP layer -----------------------------------------------------------

    def identify(self) -> doip.VehicleAnnouncement:
        resp = self.t.request(doip.build_vehicle_identification_request())
        header, payload = doip.parse_header(resp)
        if header.payload_type != doip.PayloadType.VEHICLE_ANNOUNCEMENT:
            raise ValueError(f"expected announcement, got 0x{header.payload_type:04X}")
        return doip.parse_vehicle_announcement(payload)

    def activate(self) -> bool:
        resp = self.t.request(
            doip.build_routing_activation_request(self.tester_address)
        )
        header, payload = doip.parse_header(resp)
        if header.payload_type != doip.PayloadType.ROUTING_ACTIVATION_RESPONSE:
            raise ValueError("no routing activation response")
        ra = doip.parse_routing_activation_response(payload)
        self._activated = ra.ok
        return ra.ok

    # -- UDS layer (read-only) ------------------------------------------------

    def _uds_roundtrip(self, uds_request: bytes) -> bytes:
        frame = doip.build_diagnostic_message(
            self.tester_address, self.target_address, uds_request
        )
        resp = self.t.request(frame)
        header, payload = doip.parse_header(resp)
        if header.payload_type == doip.PayloadType.DIAGNOSTIC_NEGATIVE_ACK:
            raise ConnectionError("DoIP diagnostic negative ack (routing not active?)")
        if header.payload_type != doip.PayloadType.DIAGNOSTIC_MESSAGE:
            raise ValueError(f"unexpected DoIP payload 0x{header.payload_type:04X}")
        msg = doip.parse_diagnostic_message(payload)
        return msg.uds

    def tester_present(self) -> None:
        req = uds.build_tester_present()
        resp = self._uds_roundtrip(req)
        uds.parse_response(req, resp)

    def read_did_raw(self, did: int) -> bytes:
        req = uds.build_read_data_by_identifier(did)
        resp = self._uds_roundtrip(req)
        parsed = uds.parse_response(req, resp)
        return parsed.data  # type: ignore[union-attr]

    def read_did(self, did: int):
        """Read a DID and decode it if we know how. Returns (value, Did|None)."""
        raw = self.read_did_raw(did)
        meta = lookup(did)
        if meta and meta.decode:
            try:
                return meta.decode(raw), meta
            except Exception:
                return raw, meta
        return raw, meta

    def read_dtcs(self, status_mask: int = 0xFF):
        req = uds.build_read_dtc_by_status_mask(status_mask)
        resp = self._uds_roundtrip(req)
        return uds.parse_response(req, resp)

    # -- high-level convenience ----------------------------------------------

    def gather_vehicle_info(self) -> VehicleInfo:
        """Non-destructive identity sweep used by the app's 'Identify' screen."""
        ann = self.identify()
        info = VehicleInfo(vin=ann.vin, entity_address=ann.logical_address)
        if not self._activated:
            self.activate()

        def _try(did: int) -> str:
            try:
                val, _ = self.read_did(did)
                return val if isinstance(val, str) else repr(val)
            except uds.UdsNegativeResponse:
                return ""
            except Exception:
                return ""

        info.ecu_name = _try(0xF197)
        info.app_sw_version = _try(0xF195)
        info.hw_number = _try(0xF191)
        info.extra["supplier_sw"] = _try(0xF194)
        info.extra["serial"] = _try(0xF18C)
        return info
