#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""BMW G30 read-only car test that runs on an iPhone, no computer needed.

Runs in the free "a-Shell" app from the App Store, using only Python's
standard library. It does the same read-only test as the BMW Link app:

  1. cable - finds the USB Ethernet adapter's 169.254.x.x address
  2. find  - locates the car's diagnostic gateway on the ENET cable
  3. read  - reads identification data and the head unit's fault codes
  4. log   - saves a log with the VIN and MAC masked, to paste into chat

Read-only by construction. The only UDS services this file can send are
ReadDataByIdentifier (0x22), ReadDTCInformation (0x19), TesterPresent (0x3E)
and the default diagnostic session (10 01). Every request is checked again
right before it is sent. Writing, coding, clearing fault codes, resets,
security access and flashing do not exist here.

In a-Shell:
    python3 bmw_car_test.py --practice          rehearse with a simulated car
    python3 bmw_car_test.py                     the real test, at the car
    python3 bmw_car_test.py --host 169.254.1.2  skip the search
    python3 bmw_car_test.py --test2             find every module, read engine values
    python3 bmw_car_test.py --help

This mirrors the app's Swift code (ios-app/BMWLinkKit: HSFZ.swift,
DoIP.swift, DiagLink.swift, Discovery.swift, DiagClient.swift). Tests:
tests/test_car_test_tool.py. Guide: docs/phone-only-car-test.md.
"""

from __future__ import annotations

import argparse
import errno
import json
import os
import select
import socket
import struct
import sys
import time

TOOL_VERSION = "1.0"


# =========================================================================
# Errors
# =========================================================================

class CarTestError(Exception):
    """Anything this tool reports as a failed step."""


class ReadOnlyViolation(CarTestError):
    pass


class ProtocolError(CarTestError):
    pass


class FramingError(ProtocolError):
    """The byte stream can no longer be split into frames."""


class TransportError(CarTestError):
    pass


class Closed(TransportError):
    pass


class Timeout(TransportError):
    pass


class TransportIO(TransportError):
    pass


class DiagError(CarTestError):
    pass


class NoAck(DiagError):
    pass


class NoResponse(DiagError):
    pass


class GatewayError(DiagError):
    pass


class RoutingDenied(DiagError):
    pass


class TooManyPending(DiagError):
    pass


class BroadcastBlocked(CarTestError):
    pass


class NegativeResponse(CarTestError):
    def __init__(self, sid, nrc):
        self.sid = sid
        self.nrc = nrc
        super().__init__("ECU declined service 0x%02X: %s" % (sid, nrc_name(nrc)))


def spaced_hex(data):
    return " ".join("%02X" % b for b in data)


# =========================================================================
# HSFZ (BMW ENET protocol): TCP 6801 diagnostics, UDP 6811 identification
#   frame = length(4, big-endian, bytes after the header) + control(2) + payload
#   diagnostic payload = source(1) + target(1) + UDS
# =========================================================================

HSFZ_DIAG_PORT = 6801
HSFZ_IDENT_PORT = 6811
HSFZ_HEADER = 6
HSFZ_TESTER = 0xF4
HSFZ_MAX_ACK = 13

C_DIAGNOSTIC = 0x0001
C_ACK = 0x0002
C_IDENT = 0x0011
C_ALIVE = 0x0012
C_ALIVE_RESPONSE = 0x0013
C_NACK = 0x00FF
HSFZ_ERRORS = {
    0x0040: "incorrect tester address",
    0x0041: "incorrect control word",
    0x0042: "incorrect format",
    0x0043: "incorrect destination address",
    0x0044: "message too large",
    0x0045: "diagnostic application not ready",
}


def hsfz_frame(control, payload=b""):
    return struct.pack(">IH", len(payload), control) + bytes(payload)


def hsfz_parse(frame):
    if len(frame) < HSFZ_HEADER:
        raise ProtocolError("short HSFZ frame")
    length = struct.unpack(">I", frame[:4])[0]
    if len(frame) != HSFZ_HEADER + length:
        raise ProtocolError("HSFZ length mismatch")
    return struct.unpack(">H", frame[4:6])[0], bytes(frame[HSFZ_HEADER:])


def hsfz_ident_request():
    return hsfz_frame(C_IDENT)


def hsfz_diagnostic(source, target, uds):
    return hsfz_frame(C_DIAGNOSTIC, bytes([source & 0xFF, target & 0xFF]) + bytes(uds))


def hsfz_alive_response(tester=HSFZ_TESTER):
    return hsfz_frame(C_ALIVE_RESPONSE, bytes([0x00, tester & 0xFF]))


def hsfz_ack_matches(ack, request):
    """Does an ack frame echo the start of the request (after the header)?"""
    n = min(len(ack), len(request))
    if n <= HSFZ_HEADER:
        return False
    return bytes(ack[HSFZ_HEADER:n]) == bytes(request[HSFZ_HEADER:n])


def hsfz_ident_reply(diag_address, mac, vin):
    text = "DIAGADR%02X" % diag_address + "BMWMAC" + mac + "BMWVIN" + vin
    return hsfz_frame(C_IDENT, text.encode("ascii"))


def hsfz_parse_ident(data):
    """Vehicle identification reply -> dict(diag_address, mac, vin), or None."""
    try:
        control, payload = hsfz_parse(data)
    except ProtocolError:
        return None
    if control != C_IDENT:
        return None
    text = payload.decode("ascii", "replace")
    i = text.find("DIAGADR")
    if i < 0:
        return None
    try:
        address = int(text[i + 7:i + 9], 16)
    except ValueError:
        return None
    j = text.find("BMWMAC")
    k = text.find("BMWVIN")
    return {
        "diag_address": address,
        "mac": text[j + 6:j + 18] if j >= 0 else "",
        "vin": text[k + 6:k + 23] if k >= 0 else "",
    }


# =========================================================================
# DoIP (ISO 13400) as BMW tools speak it: version 0x03, tester 0x0EF3
#   frame = version(1) + ~version(1) + payload type(2) + length(4) + payload
# =========================================================================

DOIP_PORT = 13400
DOIP_VERSION = 0x03
DOIP_TESTER = 0x0EF3
DOIP_ZGW = 0x0010

T_GENERIC_NACK = 0x0000
T_VEHICLE_ID_REQUEST = 0x0001
T_ANNOUNCEMENT = 0x0004
T_ROUTING_REQUEST = 0x0005
T_ROUTING_RESPONSE = 0x0006
T_ALIVE = 0x0007
T_ALIVE_RESPONSE = 0x0008
T_DIAGNOSTIC = 0x8001
T_DIAG_ACK = 0x8002
T_DIAG_NACK = 0x8003

DOIP_GENERIC_NACK = {
    0x00: "incorrect pattern format",
    0x01: "unknown payload type",
    0x02: "message too large",
    0x03: "out of memory",
    0x04: "invalid payload length",
}
DOIP_DIAG_NACK = {
    0x02: "invalid source address",
    0x03: "unknown target address",
    0x04: "message too large",
    0x05: "out of memory",
    0x06: "target unreachable",
    0x07: "unknown network",
    0x08: "transport protocol error",
}
DOIP_ROUTING = {
    0x00: "denied: unknown source address",
    0x01: "denied: all sockets in use",
    0x02: "denied: source address mismatch",
    0x03: "denied: source address already active",
    0x04: "denied: missing authentication",
    0x05: "denied: rejected confirmation",
    0x06: "denied: unsupported activation type",
    0x10: "success",
    0x11: "success, confirmation required",
}


def _name(table, code):
    return table.get(code, "code 0x%02X" % code)


def doip_frame(payload_type, payload=b"", version=DOIP_VERSION):
    return struct.pack(">BBHI", version, (~version) & 0xFF, payload_type, len(payload)) + bytes(payload)


def doip_parse(frame):
    """-> (version, payload_type, payload)."""
    if len(frame) < 8:
        raise ProtocolError("short DoIP header")
    version, inverse, payload_type, length = struct.unpack(">BBHI", frame[:8])
    if version ^ inverse != 0xFF:
        raise ProtocolError("DoIP inverse version mismatch")
    if len(frame) != 8 + length:
        raise ProtocolError("DoIP length mismatch")
    return version, payload_type, bytes(frame[8:])


def doip_vehicle_id_request(version=DOIP_VERSION):
    return doip_frame(T_VEHICLE_ID_REQUEST, b"", version)


def doip_routing_activation(tester=DOIP_TESTER, version=DOIP_VERSION):
    # source(2) + activation type 0x00 (default) + reserved(4) + OEM(4, zeros)
    payload = struct.pack(">HB", tester & 0xFFFF, 0x00) + b"\x00" * 4 + b"\x00" * 4
    return doip_frame(T_ROUTING_REQUEST, payload, version)


def doip_diagnostic(source, target, uds, version=DOIP_VERSION):
    return doip_frame(T_DIAGNOSTIC, struct.pack(">HH", source & 0xFFFF, target & 0xFFFF) + bytes(uds), version)


def doip_alive_response(tester=DOIP_TESTER, version=DOIP_VERSION):
    return doip_frame(T_ALIVE_RESPONSE, struct.pack(">H", tester & 0xFFFF), version)


def doip_parse_announcement(payload):
    if len(payload) < 32:
        raise ProtocolError("short vehicle announcement")
    return {
        "vin": payload[:17].decode("ascii", "replace").strip("\x00 "),
        "logical_address": struct.unpack(">H", payload[17:19])[0],
        "eid": payload[19:25].hex().upper(),
    }


# =========================================================================
# UDS (ISO 14229): read-only services only
# =========================================================================

SID_SESSION = 0x10
SID_READ_DTC = 0x19
SID_RDBI = 0x22
SID_TESTER_PRESENT = 0x3E
READ_ONLY_SERVICES = frozenset({SID_SESSION, SID_READ_DTC, SID_RDBI, SID_TESTER_PRESENT})

NRC_NAMES = {
    0x10: "general reject",
    0x11: "service not supported",
    0x12: "sub-function not supported",
    0x13: "incorrect message length or format",
    0x14: "response too long",
    0x21: "busy, repeat request",
    0x22: "conditions not correct",
    0x24: "request sequence error",
    0x31: "request out of range (not supported by this ECU)",
    0x33: "security access denied",
    0x78: "response pending",
    0x7E: "sub-function not supported in active session",
    0x7F: "service not supported in active session",
}


def nrc_name(code):
    return NRC_NAMES.get(code, "code 0x%02X" % code)


def check_read_only(uds):
    """Second safety layer: refuse anything that isn't a read, before sending."""
    if not uds:
        raise ReadOnlyViolation("refused: empty request")
    sid = uds[0]
    if sid not in READ_ONLY_SERVICES:
        raise ReadOnlyViolation("refused: UDS service 0x%02X is not read-only" % sid)
    if sid == SID_SESSION and (len(uds) != 2 or uds[1] != 0x01):
        raise ReadOnlyViolation("refused: only the default diagnostic session (10 01) is allowed")
    return sid


def uds_read_did(did):
    return bytes([SID_RDBI, (did >> 8) & 0xFF, did & 0xFF])


def uds_read_dtcs(status_mask=0xFF):
    return bytes([SID_READ_DTC, 0x02, status_mask & 0xFF])


def uds_tester_present():
    return bytes([SID_TESTER_PRESENT, 0x00])


def is_response_pending(answer, sid):
    return len(answer) >= 3 and answer[0] == 0x7F and answer[1] == sid and answer[2] == 0x78


def _check_answer(request, answer):
    if not answer:
        raise ProtocolError("empty UDS answer")
    if answer[0] == 0x7F:
        if len(answer) < 3:
            raise ProtocolError("malformed negative response")
        raise NegativeResponse(answer[1], answer[2])
    if answer[0] != request[0] + 0x40:
        raise ProtocolError("unexpected answer 0x%02X to service 0x%02X" % (answer[0], request[0]))


def parse_read_did(request, answer):
    _check_answer(request, answer)
    if len(answer) < 3:
        raise ProtocolError("short ReadDataByIdentifier answer")
    if answer[1:3] != request[1:3]:
        raise ProtocolError("answer is for a different DID")
    return bytes(answer[3:])


def parse_read_dtcs(request, answer):
    """-> list of (dtc, status)."""
    _check_answer(request, answer)
    if len(answer) < 3:
        raise ProtocolError("short ReadDTCInformation answer")
    body = answer[3:]
    return [((body[i] << 16) | (body[i + 1] << 8) | body[i + 2], body[i + 3])
            for i in range(0, len(body) - 3, 4)]


# =========================================================================
# Data identifiers (names and how to show them)
# =========================================================================

def _ascii(data):
    return data.decode("ascii", "replace").strip("\x00 ")


def _hex_and_text(data):
    printable = sum(1 for b in data if 0x20 <= b < 0x7F)
    if data and printable * 10 >= len(data) * 8:
        return '%s  "%s"' % (spaced_hex(data), _ascii(data))
    return spaced_hex(data)


# BMW process classes of the entries in a software list (SVK, DID F101).
SVK_CLASSES = {
    0x01: "HWEL", 0x02: "HWAP", 0x03: "HWFR", 0x04: "GWTB", 0x05: "CAFD", 0x06: "BTLD",
    0x07: "FLSL", 0x08: "SWFL", 0x09: "SWFF", 0x0A: "SWPF", 0x0B: "ONPS", 0x0C: "IBAD",
    0x0F: "FAFP", 0x10: "FCFA", 0x1A: "TLRT", 0x1B: "TPRG", 0x1C: "BLUP", 0x1D: "FLUP",
    0xA0: "ENTD", 0xA1: "NAVD", 0xA2: "FCFN", 0xC0: "SWUP", 0xC1: "SWIP",
}


def parse_svk(data):
    """BMW software list: header, then `count` entries of class(1) + id(4) + version(3).
    The header length is derived from the count, so its exact layout doesn't matter.
    Returns None when the bytes don't have that shape."""
    if len(data) < 4:
        return None
    count = (data[2] << 8) | data[3]
    header = len(data) - 8 * count
    if count == 0 or header < 7:
        return None
    date = None
    d = data[4:7]
    if all((b >> 4) <= 9 and (b & 0x0F) <= 9 for b in d):
        year, month, day = (int("%02X" % b) for b in d)
        if 1 <= month <= 12 and 1 <= day <= 31:
            date = "20%02d-%02d-%02d" % (year, month, day)
    entries = []
    for i in range(count):
        e = data[header + 8 * i:header + 8 * i + 8]
        version = "-" if e[5:8] == b"\xff\xff\xff" else "%d.%d.%d" % (e[5], e[6], e[7])
        entries.append((SVK_CLASSES.get(e[0], "0x%02X" % e[0]), e[1:5].hex().upper(), version))
    return {"date": date, "entries": entries, "dependencies_ok": data[1] == 0x01}


def svk_full(data):
    svk = parse_svk(data)
    if svk is None:
        return _hex_and_text(data)
    return "programmed %s, %d parts: %s" % (svk["date"] or "?", len(svk["entries"]), ", ".join(
        "%s %s %s" % entry for entry in svk["entries"]))


def svk_summary(data):
    """Short form for the screen: date, part count, software and coding versions."""
    svk = parse_svk(data)
    if svk is None:
        return _hex_and_text(data)
    parts = ["programmed %s" % (svk["date"] or "?"), "%d parts" % len(svk["entries"])]
    for cls, label in (("SWFL", "software"), ("CAFD", "coding"), ("GWTB", "gateway table")):
        versions = []
        for c, _, v in svk["entries"]:
            if c == cls and v != "-" and v not in versions:
                versions.append(v)
        if versions:
            parts.append("%s %s" % (label, "/".join(versions)))
    return "; ".join(parts)


# DTC status bits (ISO 14229): only these mean a real fault. 0x10 and 0x40
# just say "not tested yet", which BMW modules report for most of their list.
DTC_FAULT_BITS = 0x2F


def dtc_status_text(status):
    words = []
    if status & 0x01:
        words.append("active now")
    if status & 0x08:
        words.append("stored")
    if status & 0x04:
        words.append("pending")
    if not words and status & 0x22:
        words.append("failed earlier")
    return ", ".join(words) or "not tested yet"


def dtc_summary(records):
    if not records:
        return "none stored"
    faults = [(d, s) for d, s in records if s & DTC_FAULT_BITS]
    rest = len(records) - len(faults)
    if not faults:
        return "no faults (%d entries, all just 'not tested yet')" % len(records)
    shown = "; ".join("%06X (%s)" % (d, dtc_status_text(s)) for d, s in faults[:12])
    more = " and %d more" % (len(faults) - 12) if len(faults) > 12 else ""
    return "%d fault(s): %s%s; %d other entries not tested yet" % (len(faults), shown, more, rest)


DIDS = {
    0xF190: ("VIN", _ascii),
    0xF18C: ("ECU serial", _ascii),
    0xF191: ("ECU hardware number", _ascii),
    0xF194: ("Supplier software version", _ascii),
    0xF195: ("Application software version", _ascii),
    0xF197: ("System / ECU name", _ascii),
    0xF150: ("BMW ECU variant index (F150)", _hex_and_text),
    0xF101: ("BMW software list, SVK (F101)", svk_summary),
}


def _obd_u8(fmt, f):
    def decode(data):
        return fmt % f(data[0]) if len(data) >= 1 else spaced_hex(data)
    return decode


def _obd_u16(fmt, f):
    def decode(data):
        return fmt % f((data[0] << 8) | data[1]) if len(data) >= 2 else spaced_hex(data)
    return decode


# Standard OBD values read as UDS identifiers (SAE J1979-2 / ISO 27145 map
# OBD PID xx to DID F4xx). Whether a 2018 BMW engine computer shares them this
# way is exactly what Test 2 finds out; "declined" means it doesn't.
OBD_DIDS = {
    0xF40C: ("Engine speed (OBD 0C)", _obd_u16("%.0f rpm", lambda v: v / 4.0)),
    0xF405: ("Coolant temperature (OBD 05)", _obd_u8("%d \u00b0C", lambda v: v - 40)),
    0xF40F: ("Intake air temperature (OBD 0F)", _obd_u8("%d \u00b0C", lambda v: v - 40)),
    0xF45C: ("Oil temperature (OBD 5C)", _obd_u8("%d \u00b0C", lambda v: v - 40)),
    0xF40B: ("Intake manifold pressure (OBD 0B)", _obd_u8("%d kPa", lambda v: v)),
    0xF433: ("Barometric pressure (OBD 33)", _obd_u8("%d kPa", lambda v: v)),
    0xF404: ("Engine load (OBD 04)", _obd_u8("%.0f %%", lambda v: v * 100.0 / 255)),
    0xF40D: ("Vehicle speed (OBD 0D)", _obd_u8("%d km/h", lambda v: v)),
}
DIDS.update(OBD_DIDS)

# Usual BMW diagnostic addresses (F/G series). Only 0x10, 0x60 and 0x63 are
# confirmed on the owner's car; the rest are the common assignments.
MODULE_NAMES = {
    0x01: "Crash safety module (ACSM, airbags)",
    0x10: "Central gateway (ZGW)",
    0x12: "Engine computer (DME)",
    0x18: "Transmission (EGS)",
    0x29: "Stability control (DSC)",
    0x30: "Power steering (EPS)",
    0x40: "Body domain controller (BDC)",
    0x60: "Instrument cluster (KOMBI)",
    0x63: "Head unit (NBT EVO)",
}
FUNCTIONAL_ADDRESS = 0xDF   # BMW "all modules" address


# =========================================================================
# Session log, with the VIN and MAC masked in text and hex
# =========================================================================

class SessionLog(object):
    MARKS = {"info": "  ", "warn": "! ", "error": "!!", "tx": "->", "rx": "<-"}

    def __init__(self, echo=None):
        self.entries = []
        self.echo = echo

    def add(self, kind, text, data=None):
        entry = (time.time(), kind, text, None if data is None else bytes(data))
        self.entries.append(entry)
        if self.echo:
            self.echo(self.format(entry))

    def info(self, text):
        self.add("info", text)

    def warn(self, text):
        self.add("warn", text)

    def error(self, text):
        self.add("error", text)

    def tx(self, text, data):
        self.add("tx", text, data)

    def rx(self, text, data):
        self.add("rx", text, data)

    @classmethod
    def format(cls, entry):
        stamp, kind, text, data = entry
        when = time.strftime("%H:%M:%S", time.localtime(stamp)) + ".%03d" % int((stamp % 1) * 1000)
        line = "%s %s %s" % (when, cls.MARKS.get(kind, "  "), text)
        if data is not None:
            line += "  [" + spaced_hex(data) + "]"
        return line

    def export(self, header=(), secrets=()):
        lines = list(header) + ["-" * 60] + [self.format(e) for e in self.entries]
        return redact("\n".join(lines) + "\n", secrets)


def vin_secret(vin):
    return (vin, 3, False)


def mac_secret(mac):
    return (mac, 6, True)


def redact(text, secrets):
    """Mask each secret (value, keep, is_hex) as text, spaced hex and plain hex."""
    for value, keep, is_hex in secrets:
        if not value or len(value) <= keep:
            continue
        text = text.replace(value, value[:keep] + "*" * (len(value) - keep))
        forms = [(value.encode("ascii", "replace"), keep)]
        if is_hex:
            try:
                forms.append((bytes.fromhex(value), keep // 2))
            except ValueError:
                pass
        for raw, k in forms:
            if len(raw) <= k:
                continue
            hidden = len(raw) - k
            text = text.replace(spaced_hex(raw), " ".join(["%02X" % b for b in raw[:k]] + ["**"] * hidden))
            for h in (raw.hex(), raw.hex().upper()):
                text = text.replace(h, h[:2 * k] + "*" * (2 * hidden))
    return text


def short_vin(vin):
    return vin[:3] + "..." + vin[-4:] if len(vin) == 17 else (vin or "-")


# =========================================================================
# Byte streams and framing
# =========================================================================

IS_APPLE = sys.platform in ("darwin", "ios")
IP_BOUND_IF = getattr(socket, "IP_BOUND_IF", 25) if IS_APPLE else None
PERMISSION_ERRNOS = {errno.EHOSTUNREACH, errno.EACCES, errno.EPERM, errno.ENETUNREACH}
LOCAL_NETWORK_HINT = ("if iOS asked for Local Network access, allow it (Settings > "
                      "Privacy & Security > Local Network > a-Shell) and run again")
MAX_FRAME = 256 * 1024


def socket_error_text(error):
    code = getattr(error, "errno", None)
    text = os.strerror(code) if code else (str(error) or error.__class__.__name__)
    if code in PERMISSION_ERRNOS:
        text += " - " + LOCAL_NETWORK_HINT
    return text


def bind_to_interface(sock, interface, log=None):
    """Pin a socket to one interface (iOS/macOS), so car traffic can't go out over Wi-Fi."""
    if not interface or IP_BOUND_IF is None:
        return False
    try:
        sock.setsockopt(socket.IPPROTO_IP, IP_BOUND_IF, socket.if_nametoindex(interface))
        return True
    except (OSError, AttributeError) as e:
        if log:
            log.warn("could not pin traffic to %s: %s" % (interface, e))
        return False


class SocketStream(object):
    def __init__(self, sock):
        self.sock = sock
        self.closed = False

    @classmethod
    def connect(cls, host, port, interface=None, timeout=5.0, log=None):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            bind_to_interface(sock, interface, log)
            sock.settimeout(timeout)
            sock.connect((host, port))
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except socket.timeout:
            sock.close()
            raise TransportIO("no TCP connection to %s:%d within %.0f s" % (host, port, timeout))
        except OSError as e:
            sock.close()
            raise TransportIO("TCP connection to %s:%d failed: %s" % (host, port, socket_error_text(e)))
        return cls(sock)

    def write(self, data):
        if self.closed:
            raise Closed("connection already closed")
        try:
            self.sock.settimeout(5.0)
            self.sock.sendall(data)
        except socket.timeout:
            raise TransportIO("sending timed out")
        except (BrokenPipeError, ConnectionResetError):
            raise Closed("connection closed by the car")
        except OSError as e:
            raise TransportIO("send failed: %s" % socket_error_text(e))

    def read(self, timeout):
        if self.closed:
            raise Closed("connection already closed")
        try:
            ready, _, _ = select.select([self.sock], [], [], max(0.0, timeout))
        except (OSError, ValueError) as e:
            raise TransportIO("waiting for data failed: %s" % e)
        if not ready:
            raise Timeout("nothing received")
        try:
            data = self.sock.recv(65536)
        except (ConnectionResetError, BrokenPipeError):
            raise Closed("connection closed by the car")
        except OSError as e:
            raise TransportIO("receive failed: %s" % socket_error_text(e))
        if not data:
            raise Closed("connection closed by the car")
        return data

    def close(self):
        if not self.closed:
            self.closed = True
            try:
                self.sock.close()
            except OSError:
                pass


class FrameReader(object):
    def __init__(self, fmt):
        self.fmt = fmt
        self.buf = bytearray()

    def append(self, data):
        self.buf += data

    def next_frame(self):
        if self.fmt == "hsfz":
            if len(self.buf) < HSFZ_HEADER:
                return None
            total = HSFZ_HEADER + struct.unpack(">I", bytes(self.buf[:4]))[0]
        else:
            if len(self.buf) < 8:
                return None
            if self.buf[0] ^ self.buf[1] != 0xFF:
                raise FramingError("bad DoIP header (inverse version byte)")
            total = 8 + struct.unpack(">I", bytes(self.buf[4:8]))[0]
        if total > MAX_FRAME:
            raise FramingError("frame of %d bytes is too large" % total)
        if len(self.buf) < total:
            return None
        frame = bytes(self.buf[:total])
        del self.buf[:total]
        return frame


# =========================================================================
# Diagnostic links: what a real gateway sends around each answer
# =========================================================================

class Timeouts(object):
    def __init__(self, connect=5.0, ack=5.0, response=6.0, pending=10.0, max_pending=30):
        self.connect = connect
        self.ack = ack            # gateway acknowledgement (EdiabasLib uses 5 s)
        self.response = response  # first answer from the ECU after the ack
        self.pending = pending    # extra time after each "response pending"
        self.max_pending = max_pending

    @classmethod
    def uniform(cls, t):
        return cls(connect=t, ack=t, response=t, pending=t)


PROTOCOL_NAMES = {"hsfz": "HSFZ (TCP 6801)", "doip": "DoIP (TCP 13400)"}


def uds_label(uds):
    return spaced_hex(uds[:4]) + (" ..." if len(uds) > 4 else "")


class _Link(object):
    kind = ""

    def __init__(self, stream, fmt, log, timeouts, label):
        self.stream = stream
        self.reader = FrameReader(fmt)
        self.log = log or SessionLog()
        self.timeouts = timeouts or Timeouts()
        self.label = label

    def _send(self, frame, what):
        self.log.tx("%s %s" % (self.label, what), frame)
        self.stream.write(frame)

    def _read_frame(self, deadline, what):
        while True:
            frame = self.reader.next_frame()
            if frame is not None:
                return frame
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise Timeout(what)
            try:
                self.reader.append(self.stream.read(remaining))
            except Timeout:
                raise Timeout(what)

    def close(self):
        self.stream.close()
        self.log.info("%s connection closed" % self.label)


class HSFZLink(_Link):
    kind = "hsfz"

    def __init__(self, stream, log=None, timeouts=None, tester=HSFZ_TESTER):
        _Link.__init__(self, stream, "hsfz", log, timeouts, "HSFZ")
        self.tester = tester

    def open(self):
        self.log.info("HSFZ: no routing activation needed")

    def request(self, target, uds):
        sid = check_read_only(uds)
        if not 0 <= target <= 0xFF:
            raise DiagError("address 0x%04X is not valid for HSFZ" % target)
        request = hsfz_diagnostic(self.tester, target, uds)
        ecu = "0x%02X" % target
        self._send(request, "request -> %s: %s" % (ecu, uds_label(uds)))
        acked = False
        resent = False
        pending = 0
        deadline = time.monotonic() + self.timeouts.ack
        while True:
            try:
                frame = self._read_frame(deadline, "answer from ECU %s" % ecu if acked else "gateway ack")
            except Timeout as t:
                raise (NoResponse("no answer (%s)" % t) if acked
                       else NoAck("no acknowledgement from the gateway (%s)" % t))
            control, payload = hsfz_parse(frame)
            if control == C_ACK:
                self.log.rx("HSFZ ack", frame)
                if not hsfz_ack_matches(frame, request):
                    self.log.warn("HSFZ ack does not echo the request")
                acked = True
                deadline = time.monotonic() + self.timeouts.response
            elif control == C_NACK:
                self.log.rx("HSFZ NACK", frame)
                if resent:
                    raise GatewayError("gateway reported: NACK after resend")
                resent = True
                self._send(request, "resend after NACK")
                deadline = time.monotonic() + self.timeouts.ack
            elif control == C_ALIVE:
                self.log.rx("HSFZ alive check", frame)
                self._send(hsfz_alive_response(self.tester), "alive check response")
            elif control == C_DIAGNOSTIC:
                if len(payload) < 3:
                    self.log.warn("HSFZ: short diagnostic frame ignored")
                    continue
                source, dest, answer = payload[0], payload[1], payload[2:]
                self.log.rx("HSFZ answer <- 0x%02X" % source, frame)
                if source != target or dest != self.tester:
                    self.log.warn("HSFZ: frame for other addresses ignored")
                    continue
                if not acked:
                    self.log.warn("HSFZ: answer arrived before the ack")
                if is_response_pending(answer, sid):
                    pending += 1
                    if pending > self.timeouts.max_pending:
                        raise TooManyPending("ECU kept answering 'response pending'")
                    self.log.info("ECU %s says response pending (%d)" % (ecu, pending))
                    deadline = time.monotonic() + self.timeouts.pending
                    continue
                return answer
            elif control in HSFZ_ERRORS:
                self.log.rx("HSFZ error: " + HSFZ_ERRORS[control], frame)
                raise GatewayError("gateway reported: " + HSFZ_ERRORS[control])
            else:
                self.log.rx("HSFZ control 0x%04X (ignored)" % control, frame)

    def request_functional(self, uds, quiet=1.5, max_time=8.0, functional=FUNCTIONAL_ADDRESS):
        """Send one read-only request to every module at once (BMW's functional
        address) and collect the answers: [(address, answer)]. Collection ends
        `quiet` seconds after the last answer, or after `max_time`."""
        sid = check_read_only(uds)
        request = hsfz_diagnostic(self.tester, functional, uds)
        self._send(request, "request -> 0x%02X (all modules): %s" % (functional, uds_label(uds)))
        answers = {}
        resent = False
        end = time.monotonic() + max_time
        deadline = min(end, time.monotonic() + self.timeouts.ack)
        while True:
            try:
                frame = self._read_frame(deadline, "answers from all modules")
            except Timeout:
                break
            control, payload = hsfz_parse(frame)
            now = time.monotonic()
            if control == C_ACK:
                self.log.rx("HSFZ ack", frame)
                deadline = min(end, now + quiet)
            elif control == C_NACK:
                self.log.rx("HSFZ NACK", frame)
                if resent:
                    raise GatewayError("gateway reported: NACK after resend")
                resent = True
                self._send(request, "resend after NACK")
                deadline = min(end, now + self.timeouts.ack)
            elif control == C_ALIVE:
                self.log.rx("HSFZ alive check", frame)
                self._send(hsfz_alive_response(self.tester), "alive check response")
            elif control == C_DIAGNOSTIC:
                if len(payload) < 3:
                    continue
                source, dest, answer = payload[0], payload[1], payload[2:]
                self.log.rx("HSFZ answer <- 0x%02X" % source, frame)
                if dest != self.tester:
                    continue
                if is_response_pending(answer, sid):
                    deadline = min(end, now + self.timeouts.pending)
                    continue
                answers.setdefault(source, answer)
                deadline = min(end, now + quiet)
            elif control in HSFZ_ERRORS:
                self.log.rx("HSFZ error: " + HSFZ_ERRORS[control], frame)
                raise GatewayError("gateway reported: " + HSFZ_ERRORS[control])
            else:
                self.log.rx("HSFZ control 0x%04X (ignored)" % control, frame)
        self.log.info("All-modules request: %d answered" % len(answers))
        return sorted(answers.items())


class DoIPLink(_Link):
    kind = "doip"

    def __init__(self, stream, log=None, timeouts=None, tester=DOIP_TESTER, version=DOIP_VERSION):
        _Link.__init__(self, stream, "doip", log, timeouts, "DoIP")
        self.tester = tester
        self.version = version
        self.activated = False

    def _reply_alive(self, frame):
        self.log.rx("DoIP alive check", frame)
        self._send(doip_alive_response(self.tester, self.version), "alive check response")

    def open(self):
        self._send(doip_routing_activation(self.tester, self.version),
                   "routing activation (tester 0x%04X)" % self.tester)
        deadline = time.monotonic() + self.timeouts.ack
        while True:
            try:
                frame = self._read_frame(deadline, "routing activation response")
            except Timeout as t:
                raise NoResponse("no answer (%s)" % t)
            _, payload_type, payload = doip_parse(frame)
            if payload_type == T_ROUTING_RESPONSE:
                if len(payload) < 5:
                    raise ProtocolError("short routing activation response")
                code = payload[4]
                self.log.rx("DoIP routing activation: " + _name(DOIP_ROUTING, code), frame)
                if code != 0x10:
                    raise RoutingDenied("routing activation " + _name(DOIP_ROUTING, code))
                self.activated = True
                return
            if payload_type == T_ALIVE:
                self._reply_alive(frame)
            elif payload_type == T_GENERIC_NACK:
                self.log.rx("DoIP generic NACK", frame)
                raise GatewayError("gateway reported: generic NACK: "
                                   + _name(DOIP_GENERIC_NACK, payload[0] if payload else 0xFF))
            else:
                self.log.rx("DoIP payload 0x%04X (ignored)" % payload_type, frame)

    def request(self, target, uds):
        sid = check_read_only(uds)
        if not self.activated:
            self.open()
        ecu = "0x%04X" % target
        self._send(doip_diagnostic(self.tester, target, uds, self.version),
                   "request -> %s: %s" % (ecu, uds_label(uds)))
        acked = False
        pending = 0
        deadline = time.monotonic() + self.timeouts.ack
        while True:
            try:
                frame = self._read_frame(deadline, "answer from ECU %s" % ecu if acked else "gateway ack")
            except Timeout as t:
                raise (NoResponse("no answer (%s)" % t) if acked
                       else NoAck("no acknowledgement from the gateway (%s)" % t))
            _, payload_type, payload = doip_parse(frame)
            if payload_type == T_DIAG_ACK:
                self.log.rx("DoIP ack", frame)
                acked = True
                deadline = time.monotonic() + self.timeouts.response
            elif payload_type == T_DIAG_NACK:
                code = payload[4] if len(payload) >= 5 else 0xFF
                self.log.rx("DoIP NACK: " + _name(DOIP_DIAG_NACK, code), frame)
                raise GatewayError("gateway reported: diagnostic NACK: " + _name(DOIP_DIAG_NACK, code))
            elif payload_type == T_ALIVE:
                self._reply_alive(frame)
            elif payload_type == T_DIAGNOSTIC:
                if len(payload) < 4:
                    raise ProtocolError("short diagnostic message")
                source, dest = struct.unpack(">HH", payload[:4])
                answer = payload[4:]
                self.log.rx("DoIP answer <- 0x%04X" % source, frame)
                if source != target or dest != self.tester:
                    self.log.warn("DoIP: message for other addresses ignored")
                    continue
                if is_response_pending(answer, sid):
                    pending += 1
                    if pending > self.timeouts.max_pending:
                        raise TooManyPending("ECU kept answering 'response pending'")
                    self.log.info("ECU %s says response pending (%d)" % (ecu, pending))
                    deadline = time.monotonic() + self.timeouts.pending
                    continue
                return answer
            elif payload_type == T_GENERIC_NACK:
                self.log.rx("DoIP generic NACK", frame)
                raise GatewayError("gateway reported: generic NACK: "
                                   + _name(DOIP_GENERIC_NACK, payload[0] if payload else 0xFF))
            else:
                self.log.rx("DoIP payload 0x%04X (ignored)" % payload_type, frame)

    def request_functional(self, uds, **_):
        check_read_only(uds)
        raise DiagError("the all-modules scan is only built for HSFZ cars (yours speaks HSFZ)")


def make_link(stream, kind, log=None, timeouts=None):
    return HSFZLink(stream, log, timeouts) if kind == "hsfz" else DoIPLink(stream, log, timeouts)


def connect_link(host, kind, port=None, interface=None, log=None, timeouts=None):
    """Open TCP to the gateway and return a ready link."""
    log = log or SessionLog()
    timeouts = timeouts or Timeouts()
    port = port or (HSFZ_DIAG_PORT if kind == "hsfz" else DOIP_PORT)
    log.info("Connecting to %s:%d using %s%s" % (host, port, PROTOCOL_NAMES[kind],
                                                  " via " + interface if interface else ""))
    stream = SocketStream.connect(host, port, interface, timeouts.connect, log)
    log.info("TCP connected")
    link = make_link(stream, kind, log, timeouts)
    try:
        link.open()
    except Exception:
        link.close()
        raise
    return link


# =========================================================================
# Finding the car's gateway
# =========================================================================

class Ports(object):
    def __init__(self, hsfz_ident=HSFZ_IDENT_PORT, doip=DOIP_PORT, hsfz_diag=HSFZ_DIAG_PORT, doip_diag=DOIP_PORT):
        self.hsfz_ident = hsfz_ident
        self.doip = doip
        self.hsfz_diag = hsfz_diag
        self.doip_diag = doip_diag


class Gateway(object):
    def __init__(self, host, kind, vin="", mac="", address=0x10):
        self.host = host
        self.kind = kind
        self.vin = vin
        self.mac = mac
        self.address = address

    def __eq__(self, other):
        return isinstance(other, Gateway) and (self.host, self.kind) == (other.host, other.kind)

    def __hash__(self):
        return hash((self.host, self.kind))

    def __repr__(self):
        return "Gateway(%s, %s)" % (self.host, self.kind)


LINK_LOCAL_FIRST = 0xA9FE0100   # 169.254.1.0
LINK_LOCAL_LAST = 0xA9FEFEFF    # 169.254.254.255 (RFC 3927 usable range)


def ip_value(text):
    parts = text.strip().split(".")
    if len(parts) != 4:
        return None
    try:
        nums = [int(p) for p in parts]
    except ValueError:
        return None
    if any(n < 0 or n > 255 for n in nums):
        return None
    return (nums[0] << 24) | (nums[1] << 16) | (nums[2] << 8) | nums[3]


def ip_text(value):
    return "%d.%d.%d.%d" % ((value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def parse_reply(data, host):
    """Classify a UDP reply by its content (HSFZ ident or DoIP announcement)."""
    ident = hsfz_parse_ident(data)
    if ident is not None:
        return Gateway(host, "hsfz", ident["vin"], ident["mac"], ident["diag_address"])
    try:
        _, payload_type, payload = doip_parse(data)
        if payload_type == T_ANNOUNCEMENT:
            ann = doip_parse_announcement(payload)
            return Gateway(host, "doip", ann["vin"], ann["eid"], ann["logical_address"])
    except ProtocolError:
        pass
    return None


def list_interfaces():
    """[{name, index, ipv4}] - IPv4 found by asking iOS which source address it
    would use for a link-local destination through each interface."""
    result = []
    try:
        names = socket.if_nameindex()
    except (AttributeError, OSError):
        return result
    for index, name in names:
        result.append({"name": name, "index": index, "ipv4": _interface_ipv4(index)})
    return result


def _interface_ipv4(index):
    if IP_BOUND_IF is None:
        return None
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.setsockopt(socket.IPPROTO_IP, IP_BOUND_IF, index)
        sock.connect(("169.254.1.1", 9))   # UDP connect sends nothing
        address = sock.getsockname()[0]
        return address if address and address != "0.0.0.0" else None
    except OSError:
        return None
    finally:
        sock.close()


def is_link_local(address):
    return bool(address) and address.startswith("169.254.")


def wired_candidate(interfaces):
    """The USB Ethernet adapter: a 169.254.x.x address on an en* interface other than Wi-Fi (en0)."""
    def wired(i):
        return i["name"].startswith("en") and i["name"] != "en0"
    for i in interfaces:
        if wired(i) and is_link_local(i["ipv4"]):
            return i
    for i in interfaces:
        if i["name"] == "en0" and is_link_local(i["ipv4"]):
            return i
    for i in interfaces:
        if wired(i) and i["ipv4"]:
            return i
    return None


class Discovery(object):
    def __init__(self, log=None, ports=None):
        self.log = log or SessionLog()
        self.ports = ports or Ports()

    def _udp(self, interface, broadcast=False):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        if broadcast:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        bind_to_interface(sock, interface, self.log)
        sock.bind(("0.0.0.0", 0))
        sock.setblocking(False)
        return sock

    def _idents(self):
        return [(hsfz_ident_request(), self.ports.hsfz_ident), (doip_vehicle_id_request(), self.ports.doip)]

    def collect(self, sock, duration, stop_at_first=False):
        """Read replies for `duration` seconds; with 0, drain what has arrived."""
        found = []
        deadline = time.monotonic() + duration
        while True:
            remaining = max(0.0, deadline - time.monotonic())
            try:
                ready, _, _ = select.select([sock], [], [], remaining)
            except (OSError, ValueError):
                break
            if not ready:
                break
            try:
                data, (host, port) = sock.recvfrom(4096)
            except (BlockingIOError, InterruptedError):
                continue
            except OSError as e:
                self.log.warn("UDP receive: %s" % socket_error_text(e))
                if remaining <= 0:
                    break
                continue
            self.log.rx("UDP reply from %s:%d" % (host, port), data)
            gateway = parse_reply(data, host)
            if gateway is not None and gateway not in found:
                self.log.info("Found %s gateway at %s" % (PROTOCOL_NAMES[gateway.kind], host))
                found.append(gateway)
                if stop_at_first:
                    break
        return found

    def broadcast(self, interface=None, listen=2.0, subnet_broadcast=None):
        """What BMW tools do. iOS only allows it for apps with Apple's multicast entitlement."""
        try:
            sock = self._udp(interface, broadcast=True)
        except OSError as e:
            raise TransportIO(socket_error_text(e))
        try:
            destinations = ["255.255.255.255"]
            if subnet_broadcast and subnet_broadcast not in destinations:
                destinations.append(subnet_broadcast)
            sent = 0
            last = None
            for dest in destinations:
                for payload, port in self._idents():
                    try:
                        sock.sendto(payload, (dest, port))
                        self.log.tx("UDP broadcast ident -> %s:%d" % (dest, port), payload)
                        sent += 1
                    except OSError as e:
                        self.log.warn("broadcast to %s:%d failed: %s" % (dest, port, os.strerror(e.errno or 0)))
                        last = e
            if sent == 0:
                if last is not None and last.errno in PERMISSION_ERRNOS:
                    raise BroadcastBlocked("iOS blocked the broadcast (%s)" % os.strerror(last.errno))
                raise TransportIO(socket_error_text(last) if last else "could not send")
            return self.collect(sock, listen)
        finally:
            sock.close()

    def probe(self, host, interface=None, listen=1.5, tcp_timeout=2.0):
        """Ask one address (unicast needs no entitlement), with a TCP fallback."""
        try:
            sock = self._udp(interface)
        except OSError as e:
            raise TransportIO(socket_error_text(e))
        try:
            for payload, port in self._idents():
                try:
                    sock.sendto(payload, (host, port))
                    self.log.tx("UDP ident -> %s:%d" % (host, port), payload)
                except OSError as e:
                    self.log.warn("ident to %s:%d failed: %s" % (host, port, socket_error_text(e)))
            found = self.collect(sock, listen)
        finally:
            sock.close()
        if found:
            return found
        self.log.info("No UDP ident reply from %s; trying TCP ports" % host)
        for kind, port in (("hsfz", self.ports.hsfz_diag), ("doip", self.ports.doip_diag)):
            try:
                stream = SocketStream.connect(host, port, interface, tcp_timeout, self.log)
            except TransportError:
                continue
            stream.close()
            self.log.info("%s accepts TCP on %d -> %s" % (host, port, PROTOCOL_NAMES[kind]))
            return [Gateway(host, kind)]
        return []

    def sweep(self, interface=None, first=LINK_LOCAL_FIRST, last=LINK_LOCAL_LAST, per_second=250,
              include_doip=True, own_address=None, is_cancelled=lambda: False, progress=lambda done, total: None):
        """Unicast ident to each address in turn, paced; stops at the first answer.
        Each probe costs one small ARP request on the cable; the car's network
        stack ignores ARP requests for addresses that aren't its own."""
        try:
            sock = self._udp(interface)
        except OSError as e:
            raise TransportIO(socket_error_text(e))
        hsfz, doip = hsfz_ident_request(), doip_vehicle_id_request()
        own = ip_value(own_address) if own_address else None
        total = last - first + 1
        rate = max(10, per_second)
        batch = max(1, rate // 20)                 # one batch every 50 ms
        lag = max(1, rate // 2) if include_doip else 0   # DoIP probe ~0.5 s later
        self.log.info("Sweep: %d addresses at %d/s on %s" % (total, rate, interface or "default route"))
        send_errors = 0
        index = 0
        try:
            while index < total + lag:
                if is_cancelled():
                    self.log.info("Sweep cancelled at %d/%d" % (min(index, total), total))
                    return None
                started = time.monotonic()
                end = min(index + batch, total + lag)
                for i in range(index, end):
                    if i < total and first + i != own:
                        try:
                            sock.sendto(hsfz, (ip_text(first + i), self.ports.hsfz_ident))
                        except OSError:
                            send_errors += 1
                    j = i - lag
                    if include_doip and 0 <= j < total and first + j != own:
                        try:
                            sock.sendto(doip, (ip_text(first + j), self.ports.doip))
                        except OSError:
                            send_errors += 1
                index = end
                progress(min(index, total), total)
                found = self.collect(sock, 0, stop_at_first=True)
                if found:
                    self.log.info("Sweep found the gateway after %d addresses" % min(index, total))
                    return found[0]
                if send_errors > 1000 and send_errors * 2 > index:
                    raise TransportIO("most sends are failing - " + LOCAL_NETWORK_HINT)
                elapsed = time.monotonic() - started
                if elapsed < 0.05:
                    time.sleep(0.05 - elapsed)
            found = self.collect(sock, 2.0, stop_at_first=True)   # late replies
            if not found:
                self.log.info("Sweep finished: no gateway answered (%d send errors)" % send_errors)
            return found[0] if found else None
        finally:
            sock.close()


# =========================================================================
# The identify plan: every request is a read
# =========================================================================

class ECU(object):
    def __init__(self, name, address, confirmed, dids, read_dtcs):
        self.name = name
        self.address = address
        self.confirmed = confirmed
        self.dids = dids
        self.read_dtcs = read_dtcs


# ZGW 0x10, head unit 0x63 and KOMBI 0x60 answered on the owner's 2018 G30
# (first car test, 2026-11-11). The HUD did not answer at 0x3D, the usual BMW
# address, so its address on this car is still unknown.
G30_PLAN = [
    ECU("Central gateway (ZGW)", 0x10, True, [0xF190, 0xF150, 0xF101], False),
    ECU("Head unit (NBT EVO)", 0x63, True, [0xF190, 0xF150, 0xF101, 0xF18C], True),
    ECU("Instrument cluster (KOMBI)", 0x60, True, [0xF150, 0xF101], False),
    ECU("Head-up display (HUD)", 0x3D, False, [0xF150, 0xF101], False),
]


# Test 2: the engine computer. Reads only; MHD's tune is not touched.
ENGINE_PLAN = [
    ECU("Engine computer (DME)", 0x12, False, [0xF150, 0xF101] + list(OBD_DIDS), False),
]


def scan_modules(link, log=None):
    """One functional read of F150, which every module answers once.
    Returns [(address, name, outcome, detail)]."""
    log = log or SessionLog()
    request = uds_read_did(0xF150)
    modules = []
    for address, answer in link.request_functional(request):
        try:
            outcome, detail = "answered", spaced_hex(parse_read_did(request, answer))
        except NegativeResponse as e:
            outcome, detail = "declined", nrc_name(e.nrc)
        except ProtocolError as e:
            outcome, detail = "odd answer", str(e)
        modules.append((address, MODULE_NAMES.get(address, "unknown module"), outcome, detail))
    log.info("Module scan: %d answered: %s" % (len(modules), ", ".join(
        "0x%02X" % m[0] for m in modules) or "none"))
    return modules


def boost_from(report):
    """Boost from manifold minus barometric pressure, if the DME shared both."""
    m = report.raw.get((0x12, 0xF40B))
    b = report.raw.get((0x12, 0xF433))
    if not m or not b:
        return None
    kpa = m[0] - b[0]
    return "%.1f psi (%d kPa above outside air)" % (kpa * 0.1450377, kpa)


class Item(object):
    def __init__(self, ecu, address, label, outcome, detail):
        self.ecu = ecu
        self.address = address
        self.label = label
        self.outcome = outcome      # value | declined | no answer | skipped
        self.detail = detail


class Report(object):
    def __init__(self, kind, host):
        self.kind = kind
        self.host = host
        self.items = []
        self.vin = None
        self.secrets = []     # extra values to mask in the log (ECU serial numbers)
        self.raw = {}         # (address, did) -> data, for derived values

    def count(self, outcome):
        return sum(1 for i in self.items if i.outcome == outcome)

    @property
    def summary(self):
        return "%d answered, %d declined, %d no answer" % (
            self.count("value"), self.count("declined"), self.count("no answer"))


def read_did(link, did, target):
    request = uds_read_did(did)
    return parse_read_did(request, link.request(target, request))


def read_dtcs(link, target, status_mask=0xFF):
    request = uds_read_dtcs(status_mask)
    return parse_read_dtcs(request, link.request(target, request))


def run_identify(link, plan=None, host="", log=None, is_cancelled=lambda: False, on_item=None):
    """Run every read in the plan. One ECU not answering doesn't stop the others;
    a lost connection does."""
    log = log or SessionLog()
    plan = plan or G30_PLAN
    report = Report(link.kind, host)
    lost = False
    log.info("Identify: %d ECUs, read-only requests only" % len(plan))
    for ecu in plan:
        silent = False
        reads = []
        for did in ecu.dids:
            name, decode = DIDS.get(did, ("DID", spaced_hex))
            label = name if ("%04X" % did) in name else "%s %04X" % (name, did)
            reads.append((label, _did_reader(link, report, did, ecu, decode, log)))
        if ecu.read_dtcs:
            reads.append(("Fault codes (19 02 FF)", _dtc_reader(link, ecu, log)))
        for label, read in reads:
            if is_cancelled():
                item = Item(ecu.name, ecu.address, label, "skipped", "cancelled")
            elif lost:
                item = Item(ecu.name, ecu.address, label, "skipped", "connection lost")
            elif silent:
                item = Item(ecu.name, ecu.address, label, "skipped", "ECU did not answer earlier")
            else:
                try:
                    item = Item(ecu.name, ecu.address, label, "value", read())
                except NegativeResponse as e:
                    item = Item(ecu.name, ecu.address, label, "declined", nrc_name(e.nrc))
                except (NoAck, NoResponse) as e:
                    item = Item(ecu.name, ecu.address, label, "no answer", str(e))
                    silent = True
                except (TransportError, FramingError) as e:
                    item = Item(ecu.name, ecu.address, label, "no answer", str(e))
                    lost = True
                except CarTestError as e:
                    item = Item(ecu.name, ecu.address, label, "no answer", str(e))
            report.items.append(item)
            if on_item:
                on_item(item)
    log.info("Identify finished: " + report.summary)
    return report


def _did_reader(link, report, did, ecu, decode, log):
    def read():
        data = read_did(link, did, ecu.address)
        report.raw[(ecu.address, did)] = data
        if did == 0xF190:
            vin = _ascii(data)
            if len(vin) == 17:
                report.vin = vin
        elif did == 0xF18C:
            serial = _ascii(data)
            if len(serial) >= 6:
                report.secrets.append((serial, 0, False))
        elif did == 0xF101:
            log.info("Software list of %s (0x%02X): %s" % (ecu.name, ecu.address, svk_full(data)))
        return decode(data)
    return read


def _dtc_reader(link, ecu, log):
    def read():
        records = read_dtcs(link, ecu.address)
        summary = dtc_summary(records)
        log.info("Fault memory of %s (0x%02X): %s" % (ecu.name, ecu.address, summary))
        return summary
    return read


# =========================================================================
# Simulated car (practice mode and tests). VIN/MAC are synthetic test data.
# =========================================================================

class MockGateway(object):
    def __init__(self, kind, vin="WBAJE7C50JWA00000", mac="001A37C0FFEE", silent_ecus=(0x3D,),
                 alive_before_answer=False, response_pending=0, nack_first=False):
        self.kind = kind
        self.vin = vin
        self.mac = mac
        self.silent_ecus = set(silent_ecus)
        self.alive_before_answer = alive_before_answer
        self.response_pending = response_pending
        self.nack_first = nack_first
        self.uds_seen = []
        self.alive_responses = 0
        self._nacked = False
        self._routing = False
        v = vin.encode("ascii")
        self.dids = {
            0x10: {0xF190: v, 0xF150: bytes([0, 1, 2, 3]),
                   0xF101: synthetic_svk([(0x08, 0x1111, (1, 2, 3)), (0x04, 0x2222, (4, 5, 6))])},
            0x63: {0xF190: v, 0xF150: bytes([0, 0, 0x63, 1]), 0xF18C: b"SIM-HU-0001",
                   0xF101: synthetic_svk([(0x06, 0x3333, (7, 1, 0)), (0x08, 0x4444, (7, 1, 0)),
                                          (0x08, 0x4445, (7, 1, 0)), (0x05, 0x5555, (2, 0, 9))])},
            0x60: {0xF150: bytes([0, 0, 0x60, 1])},
            # Engine computer: some standard OBD values; oil temperature (F45C) is
            # left out on purpose so practice shows a "declined" read too.
            0x12: {0xF150: bytes([0, 0, 0x12, 1]),
                   0xF101: synthetic_svk([(0x08, 0x6666, (3, 4, 5)), (0x05, 0x7777, (1, 0, 2))]),
                   0xF40C: bytes([0x0C, 0xD0]), 0xF405: bytes([130]), 0xF40F: bytes([70]),
                   0xF40B: bytes([101]), 0xF433: bytes([100]), 0xF404: bytes([51]), 0xF40D: bytes([0])},
            0x29: {0xF150: bytes([0, 0, 0x29, 1])},
            0x40: {0xF150: bytes([0, 0, 0x40, 1])},
        }
        # one stored fault plus two "not tested yet" entries, as real modules report
        self.dtcs = {0x63: [(0x4B1C00, 0x08), (0x4B1C01, 0x50), (0x4B1C02, 0x40)]}

    def answer(self, ecu, request):
        sid = request[0]
        if sid == SID_RDBI:
            if len(request) < 3:
                return bytes([0x7F, sid, 0x13])
            data = self.dids.get(ecu, {}).get((request[1] << 8) | request[2])
            if data is None:
                return bytes([0x7F, sid, 0x31])
            return bytes([sid + 0x40, request[1], request[2]]) + data
        if sid == SID_READ_DTC:
            out = bytearray([sid + 0x40, request[1] if len(request) > 1 else 2, 0xFF])
            for dtc, status in self.dtcs.get(ecu, []):
                out += bytes([(dtc >> 16) & 0xFF, (dtc >> 8) & 0xFF, dtc & 0xFF, status])
            return bytes(out)
        if sid == SID_TESTER_PRESENT:
            return bytes([0x7E, 0x00])
        return bytes([0x7F, sid, 0x11])

    def handle(self, frame):
        """One complete frame in -> list of frames out."""
        return self._hsfz(frame) if self.kind == "hsfz" else self._doip(frame)

    def _hsfz(self, frame):
        try:
            control, payload = hsfz_parse(frame)
        except ProtocolError:
            return []
        if control == C_ALIVE_RESPONSE:
            self.alive_responses += 1
            return []
        if control != C_DIAGNOSTIC:
            return []
        if len(payload) < 3:
            return [hsfz_frame(0x0042)]
        tester, ecu, uds = payload[0], payload[1], payload[2:]
        if self.nack_first and not self._nacked:
            self._nacked = True
            return [hsfz_frame(C_NACK)]
        self.uds_seen.append(uds)
        out = [hsfz_frame(C_ACK, payload[:HSFZ_MAX_ACK - HSFZ_HEADER])]
        if ecu == FUNCTIONAL_ADDRESS:
            for module in sorted(self.dids):
                if module not in self.silent_ecus:
                    out.append(hsfz_diagnostic(module, tester, self.answer(module, uds)))
            return out
        if ecu in self.silent_ecus:
            return out
        if self.alive_before_answer:
            out.append(hsfz_frame(C_ALIVE))
        for _ in range(self.response_pending):
            out.append(hsfz_diagnostic(ecu, tester, bytes([0x7F, uds[0], 0x78])))
        out.append(hsfz_diagnostic(ecu, tester, self.answer(ecu, uds)))
        return out

    def _doip(self, frame):
        try:
            version, payload_type, payload = doip_parse(frame)
        except ProtocolError:
            return []
        if payload_type == T_ROUTING_REQUEST:
            tester = struct.unpack(">H", payload[:2])[0] if len(payload) >= 2 else 0
            self._routing = True
            body = struct.pack(">HH", tester, DOIP_ZGW) + bytes([0x10, 0, 0, 0, 0])
            return [doip_frame(T_ROUTING_RESPONSE, body, version)]
        if payload_type == T_ALIVE_RESPONSE:
            self.alive_responses += 1
            return []
        if payload_type == T_DIAGNOSTIC:
            if len(payload) < 5:
                return []
            source, target = struct.unpack(">HH", payload[:4])
            uds = payload[4:]
            if not self._routing:
                return [doip_frame(T_DIAG_NACK, struct.pack(">HH", target, source) + b"\x02", version)]
            self.uds_seen.append(uds)
            out = [doip_frame(T_DIAG_ACK, struct.pack(">HH", target, source) + b"\x00" + uds[:5], version)]
            if target in self.silent_ecus:
                return out
            if self.alive_before_answer:
                out.append(doip_frame(T_ALIVE, b"", version))
            for _ in range(self.response_pending):
                out.append(doip_diagnostic(target, source, bytes([0x7F, uds[0], 0x78]), version))
            out.append(doip_diagnostic(target, source, self.answer(target, uds), version))
            return out
        return [doip_frame(T_GENERIC_NACK, b"\x01", version)]

    def ident_reply(self, datagram):
        if self.kind == "hsfz":
            if datagram != hsfz_ident_request():
                return None
            return hsfz_ident_reply(0x10, self.mac, self.vin)
        try:
            version, payload_type, _ = doip_parse(datagram)
        except ProtocolError:
            return None
        if payload_type != T_VEHICLE_ID_REQUEST:
            return None
        mac = bytes.fromhex(self.mac)[:6]
        payload = self.vin.encode("ascii")[:17] + struct.pack(">H", DOIP_ZGW) + mac + mac + b"\x00\x00"
        return doip_frame(T_ANNOUNCEMENT, payload, version)


def synthetic_svk(entries, date=(0x24, 0x01, 0x15)):
    """A software list shaped like a real one (17-byte header). Test data only."""
    data = bytearray([0x01, 0x01, 0x00, len(entries)]) + bytes(date) + bytes(10)
    for cls, ident, version in entries:
        data += bytes([cls]) + struct.pack(">I", ident) + bytes(version)
    return bytes(data)


class MockStream(object):
    """An in-memory stream connected to a MockGateway."""

    def __init__(self, gateway, chunk_size=4096):
        self.gateway = gateway
        self.reader = FrameReader(gateway.kind)
        self.outbound = bytearray()
        self.closed = False
        self.chunk_size = max(1, chunk_size)

    def write(self, data):
        if self.closed:
            raise Closed("connection already closed")
        self.reader.append(data)
        while True:
            frame = self.reader.next_frame()
            if frame is None:
                break
            for out in self.gateway.handle(frame):
                self.outbound += out

    def read(self, timeout):
        if self.closed:
            raise Closed("connection already closed")
        if not self.outbound:
            if timeout > 0:
                time.sleep(min(timeout, 0.05))
            raise Timeout("simulated car has nothing to send")
        chunk = bytes(self.outbound[:self.chunk_size])
        del self.outbound[:self.chunk_size]
        return chunk

    def close(self):
        self.closed = True


def loopback_self_test():
    """Open, accept and use a local TCP connection in one thread: proves the
    phone's Python can use sockets at all. Nothing leaves the phone."""
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    accepted = None
    try:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        client.setblocking(False)
        try:
            client.connect(server.getsockname())
        except (BlockingIOError, InterruptedError):
            pass
        server.settimeout(3.0)
        accepted, _ = server.accept()
        client.setblocking(True)
        client.settimeout(3.0)
        client.sendall(hsfz_ident_request())
        accepted.settimeout(3.0)
        return accepted.recv(64) == hsfz_ident_request()
    except OSError:
        return False
    finally:
        for s in (accepted, client, server):
            if s is not None:
                s.close()


# =========================================================================
# Guided command-line test
# =========================================================================

STATE_FILE = "bmw_car_test_state.json"


class Console(object):
    def __init__(self, assume_yes=False, out=None):
        self.assume_yes = assume_yes
        self.out = out or sys.stdout

    def say(self, text=""):
        self.out.write(text + "\n")
        self.out.flush()

    def ask(self, question, default=True):
        if self.assume_yes:
            return default
        suffix = " [Y/n] " if default else " [y/N] "
        try:
            answer = input(question + suffix).strip().lower()
        except EOFError:
            return default
        if not answer:
            return default
        return answer.startswith("y")

    def ask_text(self, question):
        if self.assume_yes:
            return ""
        try:
            return input(question + " ").strip()
        except EOFError:
            return ""


def _load_state(path):
    try:
        with open(path) as f:
            state = json.load(f)
        if ip_value(state.get("host", "")) is not None and state.get("protocol") in PROTOCOL_NAMES:
            return state
    except (OSError, ValueError, AttributeError):
        pass
    return None


def _save_state(path, gateway):
    try:
        with open(path, "w") as f:
            json.dump({"host": gateway.host, "protocol": gateway.kind}, f)
    except OSError:
        pass


def _describe(gateway, show_vin, include_vin=True):
    text = "%s at %s" % (PROTOCOL_NAMES[gateway.kind], gateway.host)
    if gateway.vin and include_vin:
        text += ", VIN " + (gateway.vin if show_vin else short_vin(gateway.vin))
    return text


def find_car(args, console, log, discovery, interface):
    """Returns a Gateway or None."""
    if args.host:
        console.say("  Checking %s ..." % args.host)
        found = discovery.probe(args.host, interface)
        if not found and args.protocol:
            console.say("  No answer to the identification message; trying %s directly."
                        % PROTOCOL_NAMES[args.protocol])
            return Gateway(args.host, args.protocol)
        return _pick(found, args.protocol)

    state = _load_state(args.state_file)
    if state:
        console.say("  Trying the address that worked last time: %s ..." % state["host"])
        found = discovery.probe(state["host"], interface)
        if found:
            return _pick(found, args.protocol)
        console.say("  No answer there.")

    console.say("  Automatic search (2 seconds) ...")
    subnet = "169.254.255.255" if interface and is_link_local(interface.get("ipv4")) else None
    try:
        found = discovery.broadcast(interface["name"] if interface else None, 2.0, subnet)
        if found:
            return _pick(found, args.protocol)
        console.say("  Nothing answered.")
    except BroadcastBlocked:
        console.say("  iOS blocks automatic search for this app (that's normal). Using the next way.")
        log.info("Broadcast blocked by iOS; falling back to a unicast search")
    except TransportError as e:
        console.say("  Automatic search failed: %s" % e)

    if not interface:
        console.say("  (No wired Ethernet address was detected, so turn Wi-Fi off for the cable search.)")
    if console.ask("  Search every address on the cable? It takes up to about 4 minutes "
                   "(Ctrl-C stops it).", True):
        state = {"last": -1}

        def progress(done, total):
            pct = done * 100 // max(1, total)
            if pct // 10 != state["last"] // 10:
                state["last"] = pct
                console.say("    %3d%% of the cable's addresses checked" % pct)
        try:
            gateway = discovery.sweep(interface["name"] if interface else None,
                                      own_address=interface.get("ipv4") if interface else None,
                                      progress=progress)
        except KeyboardInterrupt:
            log.info("Sweep stopped by the user")
            console.say("  Search stopped.")
            gateway = None
        if gateway:
            return gateway
        console.say("  The cable search found nothing.")

    typed = console.ask_text("  If you know the car's address, type it (169.254.a.b), "
                             "or press Enter to stop:")
    if typed and ip_value(typed) is not None:
        found = discovery.probe(typed, interface["name"] if interface else None)
        return _pick(found, args.protocol)
    return None


def _pick(found, wanted):
    if not found:
        return None
    for g in found:
        if wanted is None or g.kind == wanted:
            return g
    return found[0]


def _result_line(item, show_vin):
    detail = item.detail
    if item.outcome == "value" and item.label.startswith("VIN") and len(detail) == 17 and not show_vin:
        detail = short_vin(detail)
    mark = {"value": "  ", "declined": "~ ", "no answer": "x ", "skipped": "- "}[item.outcome]
    prefix = {"value": "", "declined": "ECU declined: ", "no answer": "No answer: ",
              "skipped": "Skipped: "}[item.outcome]
    if len(detail) > 160:
        detail = detail[:157] + "..."
    return "  %s%s: %s%s" % (mark, item.label, prefix, detail)


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="bmw_car_test.py",
        description="Read-only BMW G30 car test over the ENET cable (no writes, coding or flashing).")
    parser.add_argument("--practice", action="store_true",
                        help="rehearse with a simulated car; nothing goes on the network")
    parser.add_argument("--host", help="the car gateway's address, if you know it (skips the search)")
    parser.add_argument("--protocol", choices=sorted(PROTOCOL_NAMES), help="force HSFZ or DoIP")
    parser.add_argument("--interface", help="network interface to use, e.g. en2 (normally found automatically)")
    parser.add_argument("--test2", action="store_true",
                        help="Test 2: find every module, then read engine values from the DME (read-only)")
    parser.add_argument("--yes", action="store_true", help="answer every question with its default")
    parser.add_argument("--show-vin", action="store_true", help="show the full VIN on screen (the log stays masked)")
    parser.add_argument("--verbose", action="store_true", help="print every message sent and received")
    parser.add_argument("--log-dir", default=".", help="where to save the log (default: current folder)")
    parser.add_argument("--state-file", default=STATE_FILE, help=argparse.SUPPRESS)
    # Tests only: HSFZ_IDENT,DOIP_UDP,HSFZ_TCP,DOIP_TCP instead of 6811,13400,6801,13400.
    parser.add_argument("--test-ports", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    ports = Ports(*[int(p) for p in args.test_ports.split(",")]) if args.test_ports else Ports()

    console = Console(args.yes)
    log = SessionLog(echo=(lambda line: console.say("    " + line)) if args.verbose else None)
    log.info("BMW car test %s (read-only), Python %s on %s" % (TOOL_VERSION, sys.version.split()[0], sys.platform))
    secrets = []
    report = None
    gateway = None
    started = time.time()
    console.say("BMW G30 car test %s - read-only" % TOOL_VERSION)
    if args.practice:
        console.say("PRACTICE: simulated car. Nothing goes on the network.")
    console.say("")

    try:
        # ---- 1. cable
        interface = None
        if args.practice:
            console.say("1 - Cable (practice)")
            ok = loopback_self_test()
            log.info("Local socket self-test: %s" % ("passed" if ok else "FAILED"))
            console.say("  Python sockets on this phone: %s" % ("working" if ok else "NOT working"))
        else:
            console.say("1 - Cable")
            interfaces = list_interfaces()
            shown = [i for i in interfaces if i["name"].startswith("en") or is_link_local(i["ipv4"])]
            log.info("Interfaces: " + (", ".join("%s=%s" % (i["name"], i["ipv4"] or "-") for i in shown) or "none"))
            if args.interface:
                interface = next((i for i in interfaces if i["name"] == args.interface),
                                 {"name": args.interface, "index": 0, "ipv4": None})
            else:
                interface = wired_candidate(interfaces)
            if interface and interface.get("ipv4"):
                console.say("  OK: wired Ethernet %s, address %s" % (interface["name"], interface["ipv4"]))
                if not is_link_local(interface["ipv4"]):
                    console.say("  Note: not a 169.254.x.x address; if the car isn't found, check the adapter.")
                log.info("Wired candidate: %s %s" % (interface["name"], interface["ipv4"]))
            elif interface:
                console.say("  Using interface %s." % interface["name"])
            else:
                console.say("  No wired Ethernet address yet. Check: ignition on, ENET cable in the OBD port,")
                console.say("  adapter in the iPhone, then wait 10 s. Wi-Fi off helps. Continuing anyway.")
                log.warn("No wired Ethernet interface with an IPv4 address")
        console.say("")

        # ---- 2. find the car
        console.say("2 - Find the car")
        if args.practice:
            kind = args.protocol or "hsfz"
            sim = MockGateway(kind)
            gateway = Gateway("simulated-car", kind, sim.vin, sim.mac)
            log.info("Practice: simulated %s gateway" % PROTOCOL_NAMES[kind])
        else:
            discovery = Discovery(log, ports)
            gateway = find_car(args, console, log, discovery, interface)
        if gateway is None:
            console.say("  The car wasn't found. Is the ignition on and the cable plugged in?")
            log.warn("Car not found")
        else:
            if gateway.vin:
                secrets.append(vin_secret(gateway.vin))
            if gateway.mac:
                secrets.append(mac_secret(gateway.mac))
            console.say("  Found: " + _describe(gateway, args.show_vin))
            console.say("  It speaks %s." % ("HSFZ" if gateway.kind == "hsfz" else "DoIP"))
        console.say("")

        # ---- 3. read identification (or Test 2)
        if gateway is not None:
            if args.test2:
                console.say("3 - Find every module (one read that all modules answer)")
            else:
                console.say("3 - Read identification (read-only, about 10 requests)")
            if args.practice:
                link = make_link(MockStream(sim, chunk_size=7), gateway.kind, log, Timeouts.uniform(1.0))
                link.open()
            else:
                pinned = interface["name"] if interface else None
                link = connect_link(gateway.host, gateway.kind,
                                    port=ports.hsfz_diag if gateway.kind == "hsfz" else ports.doip_diag,
                                    interface=pinned, log=log)
            current = {"ecu": None}

            def show(item):
                if item.ecu != current["ecu"]:
                    current["ecu"] = item.ecu
                    console.say("  %s, address 0x%02X" % (item.ecu, item.address))
                console.say("  " + _result_line(item, args.show_vin))
            try:
                if args.test2:
                    try:
                        modules = scan_modules(link, log)
                    except DiagError as e:
                        console.say("  Module scan: %s" % e)
                        modules = []
                    for address, name, outcome, detail in modules:
                        console.say("    0x%02X  %s: %s" % (address, name, detail if outcome == "answered"
                                                            else "%s (%s)" % (outcome, detail)))
                    console.say("  %d modules answered." % len(modules))
                    unknown = [m for m in modules if m[1] == "unknown module"]
                    if 0x3D in [m[0] for m in modules]:
                        console.say("  Something answered at 0x3D, the usual HUD address.")
                    elif unknown:
                        console.say("  Nothing at 0x3D, so the HUD is probably one of the %d unknown modules."
                                    % len(unknown))
                    elif modules:
                        console.say("  Nothing at 0x3D and no unknown modules: the HUD may not answer this read.")
                    console.say("")
                    console.say("4 - Engine values from the DME (read-only, standard OBD codes)")
                    report = run_identify(link, ENGINE_PLAN, gateway.host, log, on_item=show)
                    boost = boost_from(report)
                    if boost:
                        console.say("  Boost: " + boost)
                        log.info("Boost from manifold and barometric pressure: " + boost)
                else:
                    report = run_identify(link, G30_PLAN, gateway.host, log, on_item=show)
            finally:
                link.close()
            if report.vin:
                secrets.append(vin_secret(report.vin))
            secrets.extend(report.secrets)
            console.say("  Result: " + report.summary)
            if not args.practice and report.count("value") > 0:
                _save_state(args.state_file, gateway)
                log.info("Remembering %s for next time" % gateway.host)
            console.say("")
    except KeyboardInterrupt:
        log.warn("Stopped by the user")
        console.say("\nStopped.")
    except CarTestError as e:
        log.error(str(e))
        console.say("  Problem: %s" % e)
    except Exception as e:   # keep the log even after a bug
        log.error("Unexpected error: %r" % (e,))
        console.say("  Unexpected error: %r" % (e,))

    # ---- log
    console.say("%d - Log" % (5 if args.test2 else 4))
    stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(started))
    name = "bmw-log-%s%s%s.txt" % ("practice-" if args.practice else "", "test2-" if args.test2 else "", stamp)
    path = os.path.join(args.log_dir, name)
    header = [
        "BMW car test log %s - read-only diagnostics" % TOOL_VERSION,
        "Created: %s" % time.strftime("%Y-%m-%d %H:%M:%S %Z", time.localtime(started)),
        "Python %s on %s" % (sys.version.split()[0], sys.platform),
        "Mode: %s" % ("practice (simulated car)" if args.practice else "car"),
        "Test: %s" % ("2 - module scan and engine values" if args.test2 else "1 - identification"),
        "Gateway: %s" % (_describe(gateway, False, include_vin=False) if gateway else "not found"),
        "Identify: %s" % (report.summary if report else "not run"),
        "VIN and MAC are masked in this file.",
    ]
    text = log.export(header, secrets)
    try:
        with open(path, "w") as f:
            f.write(text)
        console.say("  Saved %s (VIN and MAC masked)." % path)
        console.say("  To send it: Files app > On My iPhone > a-Shell > %s > open it," % name)
        console.say("  select all, copy, and paste it into the chat.")
    except OSError as e:
        console.say("  Couldn't save the log (%s). Here it is:" % e)
        console.say(text)
    if report is not None and report.count("value") > 0:
        return 0
    return 2 if gateway is None else 1


if __name__ == "__main__":
    sys.exit(main())
