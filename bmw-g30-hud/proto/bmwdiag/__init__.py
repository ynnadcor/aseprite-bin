# SPDX-License-Identifier: MIT
"""bmwdiag - a strictly read-only ENET/DoIP diagnostic reference.

This is the Python reference implementation (Modules 1 & 2) that the Swift
iOS app mirrors. It implements just enough of:

  * ISO 13400 (DoIP) - the transport BMW uses over the ENET (OBD->Ethernet)
    cable: vehicle identification, routing activation, diagnostic messages.
  * ISO 14229 (UDS)  - but ONLY read-only services (ReadDataByIdentifier,
    ReadDTCInformation, TesterPresent, and the default diagnostic session).

By construction it cannot write, flash, clear DTCs, run routines, or change a
session to programming/extended. See `uds.ALLOWED_SERVICES`. This mirrors the
project's safety rules: inspection first, nothing persistent, nothing risky.

The code is transport-agnostic: `transport.Transport` is an interface and
`transport.MockEnetServer` lets the whole stack be exercised with no car.
"""

from .doip import (
    DoIPHeader,
    PayloadType,
    build_vehicle_identification_request,
    build_routing_activation_request,
    build_diagnostic_message,
    parse_header,
    parse_vehicle_announcement,
    parse_routing_activation_response,
    parse_diagnostic_message,
)
from .uds import (
    UdsService,
    ALLOWED_SERVICES,
    build_read_data_by_identifier,
    build_read_dtc_by_status_mask,
    build_tester_present,
    parse_response,
    UdsNegativeResponse,
)
from .transport import Transport, MockEnetServer
from .client import ReadOnlyDiagClient, VehicleInfo

__all__ = [
    "DoIPHeader",
    "PayloadType",
    "build_vehicle_identification_request",
    "build_routing_activation_request",
    "build_diagnostic_message",
    "parse_header",
    "parse_vehicle_announcement",
    "parse_routing_activation_response",
    "parse_diagnostic_message",
    "UdsService",
    "ALLOWED_SERVICES",
    "build_read_data_by_identifier",
    "build_read_dtc_by_status_mask",
    "build_tester_present",
    "parse_response",
    "UdsNegativeResponse",
    "Transport",
    "MockEnetServer",
    "ReadOnlyDiagClient",
    "VehicleInfo",
]

__version__ = "0.1.0"
