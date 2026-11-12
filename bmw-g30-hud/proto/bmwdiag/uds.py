# SPDX-License-Identifier: MIT
"""ISO 14229 (UDS) - read-only services only.

Hard safety boundary: this module can only build request PDUs for services in
`ALLOWED_SERVICES`. Everything that writes, clears, flashes, resets, or runs a
routine is deliberately absent, and `build_request` refuses any SID not on the
allowlist. This is the software expression of the project's rule "read-only
operations first; nothing persistent without a reviewed recovery procedure."
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from enum import IntEnum
from typing import Dict, Optional, Union


class UdsService(IntEnum):
    DIAGNOSTIC_SESSION_CONTROL = 0x10   # we only ever use subfunction 0x01 (default)
    TESTER_PRESENT = 0x3E
    READ_DTC_INFORMATION = 0x19
    READ_DATA_BY_IDENTIFIER = 0x22


class ObdService(IntEnum):
    """Legislated OBD-II read services (SAE J1979 / ISO 15031-5). They only
    read: every generic OBD scanner sends them."""

    CURRENT_DATA = 0x01     # mode 01: live data; PID 01 = engine light + readiness
    STORED_DTCS = 0x03      # mode 03: confirmed emission-related codes
    PENDING_DTCS = 0x07     # mode 07: pending codes
    PERMANENT_DTCS = 0x0A   # mode 0A: permanent codes


# The ONLY services this library will emit. Note what is NOT here:
#   0x2E WriteDataByIdentifier, 0x14 ClearDTC, 0x31 RoutineControl,
#   0x11 ECUReset, 0x34/0x36/0x37 transfer (flashing), 0x27 SecurityAccess,
#   OBD 0x04 (clear codes) and OBD 0x08 (control of on-board systems), ...
ALLOWED_SERVICES = frozenset(
    {
        UdsService.DIAGNOSTIC_SESSION_CONTROL,
        UdsService.TESTER_PRESENT,
        UdsService.READ_DTC_INFORMATION,
        UdsService.READ_DATA_BY_IDENTIFIER,
        *ObdService,
    }
)

# Only the default session may be requested (0x01). Extended (0x03) and
# programming (0x02) sessions are what unlock write/flash services, so they are
# not allowed here.
DEFAULT_SESSION = 0x01
_ALLOWED_SESSIONS = {DEFAULT_SESSION}

POSITIVE_RESPONSE_OFFSET = 0x40
NEGATIVE_RESPONSE_SID = 0x7F


class NRC(IntEnum):
    """A few common negative response codes, for readable errors."""

    GENERAL_REJECT = 0x10
    SERVICE_NOT_SUPPORTED = 0x11
    SUBFUNCTION_NOT_SUPPORTED = 0x12
    INCORRECT_LENGTH = 0x13
    CONDITIONS_NOT_CORRECT = 0x22
    REQUEST_OUT_OF_RANGE = 0x31
    SECURITY_ACCESS_DENIED = 0x33
    RESPONSE_PENDING = 0x78


class UdsNegativeResponse(Exception):
    def __init__(self, sid: int, nrc: int):
        self.request_sid = sid
        self.nrc = nrc
        try:
            name = NRC(nrc).name
        except ValueError:
            name = f"0x{nrc:02X}"
        super().__init__(f"UDS negative response to SID 0x{sid:02X}: {name}")


def _guard(sid: int) -> None:
    if sid not in ALLOWED_SERVICES:
        raise ValueError(
            f"service 0x{sid:02X} is not read-only and is blocked by bmwdiag"
        )


# ---- request builders --------------------------------------------------------

def build_diagnostic_session_control(session: int = DEFAULT_SESSION) -> bytes:
    _guard(UdsService.DIAGNOSTIC_SESSION_CONTROL)
    if session not in _ALLOWED_SESSIONS:
        raise ValueError("only the default session (0x01) is permitted")
    return bytes([UdsService.DIAGNOSTIC_SESSION_CONTROL, session])


def build_tester_present(suppress_response: bool = False) -> bytes:
    _guard(UdsService.TESTER_PRESENT)
    sub = 0x80 if suppress_response else 0x00
    return bytes([UdsService.TESTER_PRESENT, sub])


def build_read_data_by_identifier(did: int) -> bytes:
    _guard(UdsService.READ_DATA_BY_IDENTIFIER)
    if not (0 <= did <= 0xFFFF):
        raise ValueError("DID must be a 16-bit value")
    return struct.pack(">BH", UdsService.READ_DATA_BY_IDENTIFIER, did)


def build_read_dtc_by_status_mask(status_mask: int = 0xFF) -> bytes:
    """reportDTCByStatusMask (subfunction 0x02)."""
    _guard(UdsService.READ_DTC_INFORMATION)
    return bytes([UdsService.READ_DTC_INFORMATION, 0x02, status_mask & 0xFF])


def build_obd_request(service: int, pid: Optional[int] = None) -> bytes:
    """An OBD-II read: mode 01 needs a PID, the code reads (03/07/0A) don't."""
    _guard(service)
    if service not in set(ObdService):
        raise ValueError(f"0x{service:02X} is not an OBD read service")
    if service == ObdService.CURRENT_DATA:
        if pid is None or not (0 <= pid <= 0xFF):
            raise ValueError("mode 01 needs a PID (0x00-0xFF)")
        return bytes([service, pid])
    return bytes([service])


def sae_dtc(hi: int, lo: int) -> str:
    """Two OBD bytes -> SAE J2012 code, e.g. 0x01 0x71 -> 'P0171'."""
    letter = "PCBU"[hi >> 6]
    return f"{letter}{(hi >> 4) & 0x3}{hi & 0xF:X}{lo:02X}"


def parse_obd_dtcs(request_sid: int, response: bytes) -> list:
    """Codes from a mode 03/07/0A answer. On CAN the answer has a count byte
    after the SID; older protocols pad with 00 00 instead. Both are accepted."""
    if not response:
        raise ValueError("empty OBD response")
    if response[0] == NEGATIVE_RESPONSE_SID:
        if len(response) < 3:
            raise ValueError("malformed negative response")
        raise UdsNegativeResponse(response[1], response[2])
    if response[0] != request_sid + POSITIVE_RESPONSE_OFFSET:
        raise ValueError(f"unexpected response SID 0x{response[0]:02X}")
    body = response[1:]
    if body and len(body) == 1 + 2 * body[0]:
        pairs = body[1:]
    elif len(body) % 2 == 0:
        pairs = body
    else:
        raise ValueError("OBD code list has an odd length")
    return [sae_dtc(pairs[i], pairs[i + 1]) for i in range(0, len(pairs), 2)
            if pairs[i] or pairs[i + 1]]


# ---- response parsing --------------------------------------------------------

@dataclass
class RdbiResponse:
    did: int
    data: bytes


@dataclass
class DtcRecord:
    dtc: int          # 3-byte DTC packed into an int
    status: int

    @property
    def code(self) -> str:
        return f"0x{self.dtc:06X}"


@dataclass
class ReadDtcResponse:
    availability_mask: int
    records: list


def parse_response(request: bytes, response: bytes):
    """Validate and decode a UDS response against the request that caused it.

    Raises UdsNegativeResponse on a 0x7F, ValueError on malformed/mismatched.
    Returns a typed object for RDBI/ReadDTC, or the raw response bytes for
    TesterPresent / session control.
    """
    if not response:
        raise ValueError("empty UDS response")

    req_sid = request[0] if request else 0

    if response[0] == NEGATIVE_RESPONSE_SID:
        if len(response) < 3:
            raise ValueError("malformed negative response")
        raise UdsNegativeResponse(response[1], response[2])

    expected = req_sid + POSITIVE_RESPONSE_OFFSET
    if response[0] != expected:
        raise ValueError(
            f"unexpected response SID 0x{response[0]:02X} (wanted 0x{expected:02X})"
        )

    if req_sid == UdsService.READ_DATA_BY_IDENTIFIER:
        if len(response) < 3:
            raise ValueError("short RDBI response")
        did = struct.unpack(">H", response[1:3])[0]
        return RdbiResponse(did, response[3:])

    if req_sid == UdsService.READ_DTC_INFORMATION:
        # 0x59 + subfunc(1) + availabilityMask(1) + records(4 each: 3 DTC + 1 status)
        if len(response) < 3:
            raise ValueError("short ReadDTC response")
        avail = response[2]
        body = response[3:]
        records = []
        for i in range(0, len(body) - 3, 4):
            dtc = (body[i] << 16) | (body[i + 1] << 8) | body[i + 2]
            status = body[i + 3]
            records.append(DtcRecord(dtc, status))
        return ReadDtcResponse(avail, records)

    # TesterPresent / session control: return raw tail
    return response
