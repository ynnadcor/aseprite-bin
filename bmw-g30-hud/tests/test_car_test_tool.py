# SPDX-License-Identifier: MIT
"""Tests for tools/bmw_car_test.py, the phone-only (a-Shell) car test.

Same guarantees as the Swift app's tests: byte-exact frames (shared golden
vectors), real-gateway behaviour (acks, NACK, alive checks, response pending,
silent ECUs), read-only enforcement at the link, masked logs, and end-to-end
runs over real TCP/UDP sockets on 127.0.0.1.
"""

import contextlib
import importlib.util
import io
import json
import os
import socket
import sys
import tempfile
import threading
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
_spec = importlib.util.spec_from_file_location("bmw_car_test", os.path.join(ROOT, "tools", "bmw_car_test.py"))
ct = importlib.util.module_from_spec(_spec)
sys.modules["bmw_car_test"] = ct
_spec.loader.exec_module(ct)

with open(os.path.join(ROOT, "test-vectors", "doip_uds_vectors.json")) as _f:
    VECTORS = json.load(_f)

SIM_VIN = "WBAJE7C50JWA00000"   # synthetic test data, not a real car
SIM_MAC = "001A37C0FFEE"


def mock_link(kind, chunk_size=4096, **behaviour):
    gw = ct.MockGateway(kind, **behaviour)
    link = ct.make_link(ct.MockStream(gw, chunk_size), kind, ct.SessionLog(), ct.Timeouts.uniform(0.3))
    link.open()
    return gw, link


class GoldenVectorTests(unittest.TestCase):
    def test_hsfz_frames(self):
        v = VECTORS["hsfz"]
        self.assertEqual(ct.hsfz_ident_request().hex(), v["ident_request_hex"])
        d = v["diagnostic_rdbi_vin"]
        req = ct.hsfz_diagnostic(d["source"], d["target"], bytes.fromhex(d["uds_hex"]))
        self.assertEqual(req.hex(), d["frame_hex"])
        self.assertTrue(ct.hsfz_ack_matches(bytes.fromhex(v["ack_for_rdbi_vin_hex"]), req))
        self.assertEqual(ct.hsfz_alive_response().hex(), v["alive_check_response_hex"])
        r = v["ident_reply"]
        reply = ct.hsfz_ident_reply(r["diag_address"], r["mac"], r["vin"])
        self.assertEqual(reply.hex(), r["frame_hex"])
        self.assertEqual(ct.hsfz_parse_ident(reply),
                         {"diag_address": r["diag_address"], "mac": r["mac"], "vin": r["vin"]})

    def test_doip_bmw_frames(self):
        v = VECTORS["doip_bmw"]
        self.assertEqual(ct.doip_routing_activation().hex(), v["routing_activation_hex"])
        self.assertEqual(ct.doip_vehicle_id_request().hex(), v["vehicle_identification_request_hex"])
        self.assertEqual(ct.doip_alive_response().hex(), v["alive_check_response_hex"])

    def test_uds(self):
        u = VECTORS["uds"]
        self.assertEqual(ct.uds_read_did(u["build_rdbi_vin"]["did"]).hex(), u["build_rdbi_vin"]["request_hex"])
        p = u["parse_rdbi_vin"]
        data = ct.parse_read_did(bytes.fromhex(p["request_hex"]), bytes.fromhex(p["response_hex"]))
        self.assertEqual(data.decode(), p["expect_ascii"])
        self.assertEqual(ct.uds_read_dtcs(u["build_read_dtc"]["status_mask"]).hex(), u["build_read_dtc"]["request_hex"])
        d = u["parse_read_dtc"]
        recs = ct.parse_read_dtcs(bytes.fromhex(d["request_hex"]), bytes.fromhex(d["response_hex"]))
        self.assertEqual(recs, [(int(r["dtc"], 16), r["status"]) for r in d["expect_records"]])
        n = u["parse_negative_response"]
        with self.assertRaises(ct.NegativeResponse) as cm:
            ct.parse_read_did(bytes.fromhex(n["request_hex"]), bytes.fromhex(n["response_hex"]))
        self.assertEqual((cm.exception.sid, cm.exception.nrc), (n["expect_request_sid"], n["expect_nrc"]))
        self.assertEqual(ct.uds_tester_present().hex(), u["build_tester_present"]["request_hex"])


class ReadOnlyTests(unittest.TestCase):
    def test_blocked_services_never_reach_the_gateway(self):
        blocked = [int(s, 16) for s in VECTORS["blocked_services_must_refuse"]]
        for kind in ("hsfz", "doip"):
            gw, link = mock_link(kind)
            for sid in blocked:
                with self.assertRaises(ct.ReadOnlyViolation):
                    link.request(0x63, bytes([sid, 0x01, 0x02]))
            self.assertEqual(gw.uds_seen, [], kind)

    def test_only_default_session(self):
        for uds in (b"\x10\x02", b"\x10\x03", b"\x10", b"\x10\x01\x00", b""):
            with self.assertRaises(ct.ReadOnlyViolation):
                ct.check_read_only(uds)
        self.assertEqual(ct.check_read_only(b"\x10\x01"), 0x10)
        for uds in (b"\x22\xf1\x90", b"\x19\x02\xff", b"\x3e\x00"):
            ct.check_read_only(uds)

    def test_every_request_in_a_run_is_a_read(self):
        for kind in ("hsfz", "doip"):
            gw, link = mock_link(kind)
            ct.run_identify(link)
            self.assertTrue(gw.uds_seen)
            self.assertTrue(all(u[0] in (0x22, 0x19) for u in gw.uds_seen), kind)


class LinkTests(unittest.TestCase):
    def check_report(self, report):
        values = {(i.address, i.label): i for i in report.items}
        self.assertEqual(report.vin, SIM_VIN)
        self.assertEqual(values[(0x63, "ECU serial F18C")].detail, "SIM-HU-0001")
        self.assertEqual(values[(0x63, "Fault codes (19 02 FF)")].detail, "1: 4B1C00/08")
        self.assertEqual(values[(0x60, "BMW software list, SVK (F101)")].outcome, "declined")
        hud = [i for i in report.items if i.address == 0x3D]
        self.assertEqual([i.outcome for i in hud], ["no answer", "skipped"])
        self.assertEqual(report.summary, "9 answered, 1 declined, 1 no answer")

    def test_identify_both_protocols_with_one_byte_chunks(self):
        for kind in ("hsfz", "doip"):
            _, link = mock_link(kind, chunk_size=1)
            self.check_report(ct.run_identify(link))

    def test_alive_checks_and_pending(self):
        for kind in ("hsfz", "doip"):
            gw, link = mock_link(kind, alive_before_answer=True, response_pending=2)
            self.check_report(ct.run_identify(link))
            self.assertEqual(gw.alive_responses, len(gw.uds_seen) - 1, kind)  # HUD is silent

    def test_hsfz_nack_resend_once(self):
        gw, link = mock_link("hsfz", nack_first=True)
        self.assertEqual(ct.read_did(link, 0xF190, 0x10).decode(), SIM_VIN)

    def test_hsfz_two_nacks_is_an_error(self):
        gw = ct.MockGateway("hsfz")
        gw.handle = lambda frame: [ct.hsfz_frame(ct.C_NACK)]
        link = ct.make_link(ct.MockStream(gw), "hsfz", ct.SessionLog(), ct.Timeouts.uniform(0.3))
        with self.assertRaises(ct.GatewayError):
            link.request(0x10, ct.uds_read_did(0xF190))

    def test_doip_routing_denied(self):
        gw = ct.MockGateway("doip")
        gw.handle = lambda frame: [ct.doip_frame(ct.T_ROUTING_RESPONSE, b"\x0e\xf3\x00\x10\x00\x00\x00\x00\x00")]
        link = ct.make_link(ct.MockStream(gw), "doip", ct.SessionLog(), ct.Timeouts.uniform(0.3))
        with self.assertRaises(ct.RoutingDenied):
            link.open()

    def test_doip_unknown_target_nack(self):
        gw, link = mock_link("doip")
        real = gw.handle

        def handle(frame):
            _, ptype, payload = ct.doip_parse(frame)
            if ptype == ct.T_DIAGNOSTIC:
                return [ct.doip_frame(ct.T_DIAG_NACK, payload[2:4] + payload[0:2] + b"\x03")]
            return real(frame)
        gw.handle = handle
        with self.assertRaises(ct.GatewayError) as cm:
            link.request(0x99, ct.uds_read_did(0xF190))
        self.assertIn("unknown target address", str(cm.exception))

    def test_lost_connection_skips_the_rest(self):
        gw, link = mock_link("hsfz")
        calls = {"n": 0}
        real = link.stream.write

        def write(data):
            calls["n"] += 1
            if calls["n"] > 3:
                raise ct.Closed("connection closed by the car")
            real(data)
        link.stream.write = write
        report = ct.run_identify(link)
        self.assertEqual(report.count("value"), 3)
        self.assertEqual(report.items[3].outcome, "no answer")
        self.assertTrue(all(i.outcome == "skipped" and i.detail == "connection lost" for i in report.items[4:]))


class LogTests(unittest.TestCase):
    def test_vin_and_mac_masked_everywhere(self):
        log = ct.SessionLog()
        log.info("VIN " + SIM_VIN + " MAC " + SIM_MAC)
        log.rx("ident", ct.hsfz_ident_reply(0x10, SIM_MAC, SIM_VIN))
        log.rx("announce", bytes.fromhex(SIM_MAC) + SIM_VIN.encode())
        text = log.export(["header"], [ct.vin_secret(SIM_VIN), ct.mac_secret(SIM_MAC)])
        self.assertNotIn(SIM_VIN, text)
        self.assertNotIn(SIM_MAC, text)
        self.assertNotIn(ct.spaced_hex(SIM_VIN.encode()), text)
        self.assertNotIn(ct.spaced_hex(SIM_VIN.encode()[3:]), text)
        self.assertNotIn(ct.spaced_hex(SIM_MAC.encode()), text)
        self.assertNotIn(ct.spaced_hex(bytes.fromhex(SIM_MAC)), text)
        self.assertIn("WBA**************", text)
        self.assertIn("001A37******", text)
        self.assertIn("57 42 41 ** **", text)
        self.assertIn("00 1A 37 ** ** **", text)

    def test_replies_classified_by_content(self):
        hsfz = ct.parse_reply(ct.hsfz_ident_reply(0x10, SIM_MAC, SIM_VIN), "169.254.1.2")
        self.assertEqual((hsfz.kind, hsfz.vin, hsfz.mac, hsfz.address), ("hsfz", SIM_VIN, SIM_MAC, 0x10))
        ann = ct.MockGateway("doip").ident_reply(ct.doip_vehicle_id_request())
        doip = ct.parse_reply(ann, "169.254.1.2")
        self.assertEqual((doip.kind, doip.vin, doip.mac, doip.address), ("doip", SIM_VIN, SIM_MAC, 0x10))
        self.assertIsNone(ct.parse_reply(ct.hsfz_ident_request(), "x"))
        self.assertIsNone(ct.parse_reply(ct.doip_vehicle_id_request(), "x"))

    def test_wired_candidate(self):
        ifaces = [{"name": "en0", "index": 1, "ipv4": "192.168.1.5"},
                  {"name": "pdp_ip0", "index": 2, "ipv4": "10.1.2.3"},
                  {"name": "en7", "index": 9, "ipv4": "169.254.33.7"}]
        self.assertEqual(ct.wired_candidate(ifaces)["name"], "en7")
        self.assertIsNone(ct.wired_candidate(ifaces[:2]))


class LoopbackGateway(object):
    """The simulated gateway behind real sockets on 127.0.0.1."""

    def __init__(self, kind, answer_udp=True):
        self.gw = ct.MockGateway(kind, alive_before_answer=True, response_pending=1)
        self.stop = threading.Event()
        self.tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.tcp.bind(("127.0.0.1", 0))
        self.tcp.listen(4)
        self.tcp.settimeout(0.2)
        self.udp = []
        for _ in range(2):
            u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            u.bind(("127.0.0.1", 0))
            u.settimeout(0.2)
            self.udp.append(u)
        tcp_port = self.tcp.getsockname()[1]
        self.ports = ct.Ports(self.udp[0].getsockname()[1], self.udp[1].getsockname()[1], tcp_port, tcp_port)
        self.threads = [threading.Thread(target=self._serve_tcp)]
        if answer_udp:
            self.threads += [threading.Thread(target=self._serve_udp, args=(u,)) for u in self.udp]
        for t in self.threads:
            t.daemon = True
            t.start()

    def _serve_tcp(self):
        while not self.stop.is_set():
            try:
                conn, _ = self.tcp.accept()
            except (socket.timeout, OSError):
                continue
            conn.settimeout(0.2)
            reader = ct.FrameReader(self.gw.kind)
            with conn:
                while not self.stop.is_set():
                    try:
                        data = conn.recv(4096)
                    except socket.timeout:
                        continue
                    except OSError:
                        break
                    if not data:
                        break
                    reader.append(data)
                    while True:
                        frame = reader.next_frame()
                        if frame is None:
                            break
                        for out in self.gw.handle(frame):
                            conn.sendall(out)

    def _serve_udp(self, sock):
        while not self.stop.is_set():
            try:
                data, addr = sock.recvfrom(4096)
            except (socket.timeout, OSError):
                continue
            reply = self.gw.ident_reply(data)
            if reply:
                sock.sendto(reply, addr)

    def close(self):
        self.stop.set()
        for t in self.threads:
            t.join(2)
        self.tcp.close()
        for u in self.udp:
            u.close()


class LoopbackTests(unittest.TestCase):
    def setUp(self):
        self.servers = []

    def tearDown(self):
        for s in self.servers:
            s.close()

    def server(self, kind, answer_udp=True):
        s = LoopbackGateway(kind, answer_udp)
        self.servers.append(s)
        return s

    def test_probe_connect_identify_both_protocols(self):
        for kind in ("hsfz", "doip"):
            s = self.server(kind)
            log = ct.SessionLog()
            found = ct.Discovery(log, s.ports).probe("127.0.0.1", listen=0.5)
            self.assertEqual([(g.kind, g.vin, g.mac) for g in found], [(kind, SIM_VIN, SIM_MAC)])
            link = ct.connect_link("127.0.0.1", kind, port=s.ports.hsfz_diag, log=log,
                                   timeouts=ct.Timeouts.uniform(0.5))
            try:
                report = ct.run_identify(link, host="127.0.0.1", log=log)
            finally:
                link.close()
            self.assertEqual(report.summary, "9 answered, 1 declined, 1 no answer", kind)
            self.assertTrue(all(u[0] in (0x22, 0x19) for u in s.gw.uds_seen))
            self.assertGreater(s.gw.alive_responses, 0)

    def test_tcp_fallback_when_ident_is_ignored(self):
        s = self.server("hsfz", answer_udp=False)
        found = ct.Discovery(ct.SessionLog(), s.ports).probe("127.0.0.1", listen=0.3)
        self.assertEqual([(g.host, g.kind) for g in found], [("127.0.0.1", "hsfz")])

    def test_nothing_listening(self):
        s = self.server("hsfz", answer_udp=False)
        port = s.ports.hsfz_diag
        s.close()
        self.servers.remove(s)
        found = ct.Discovery(ct.SessionLog(), ct.Ports(port, port, port, port)).probe(
            "127.0.0.1", listen=0.2, tcp_timeout=0.5)
        self.assertEqual(found, [])

    def test_sweep_finds_the_gateway(self):
        for kind in ("hsfz", "doip"):
            s = self.server(kind)
            gw = ct.Discovery(ct.SessionLog(), s.ports).sweep(
                None, ct.ip_value("127.0.0.1"), ct.ip_value("127.0.0.3"), per_second=250)
            self.assertIsNotNone(gw, kind)
            self.assertEqual((gw.host, gw.kind), ("127.0.0.1", kind))

    def test_sweep_cancel(self):
        s = self.server("hsfz", answer_udp=False)
        self.assertIsNone(ct.Discovery(ct.SessionLog(), s.ports).sweep(
            None, ct.ip_value("127.0.0.1"), ct.ip_value("127.0.0.9"), is_cancelled=lambda: True))

    def test_cli_against_the_loopback_car(self):
        for kind in ("hsfz", "doip"):
            s = self.server(kind)
            with tempfile.TemporaryDirectory() as tmp:
                state = os.path.join(tmp, "state.json")
                out = io.StringIO()
                p = s.ports
                with contextlib.redirect_stdout(out):
                    code = ct.main(["--host", "127.0.0.1", "--yes", "--log-dir", tmp, "--state-file", state,
                                    "--test-ports", "%d,%d,%d,%d" % (p.hsfz_ident, p.doip, p.hsfz_diag, p.doip_diag)])
                self.assertEqual(code, 0, out.getvalue())
                self.assertIn("It speaks %s." % kind.upper().replace("DOIP", "DoIP"), out.getvalue())
                with open(state) as f:
                    self.assertEqual(json.load(f), {"host": "127.0.0.1", "protocol": kind})
                logs = [n for n in os.listdir(tmp) if n.startswith("bmw-log-")]
                self.assertEqual(len(logs), 1)
                with open(os.path.join(tmp, logs[0])) as f:
                    text = f.read()
                self.assertNotIn(SIM_VIN, text)
                self.assertNotIn(SIM_VIN[-4:] + "\n", text)
                self.assertNotIn(SIM_MAC, text)
                self.assertIn("Identify: 9 answered, 1 declined, 1 no answer", text)


class PracticeModeTests(unittest.TestCase):
    def test_practice_both_protocols(self):
        for kind in ("hsfz", "doip"):
            with tempfile.TemporaryDirectory() as tmp:
                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    code = ct.main(["--practice", "--yes", "--protocol", kind, "--log-dir", tmp,
                                    "--state-file", os.path.join(tmp, "state.json")])
                self.assertEqual(code, 0, out.getvalue())
                self.assertIn("Python sockets on this phone: working", out.getvalue())
                self.assertFalse(os.path.exists(os.path.join(tmp, "state.json")))
                (name,) = os.listdir(tmp)
                self.assertTrue(name.startswith("bmw-log-practice-"))
                with open(os.path.join(tmp, name)) as f:
                    text = f.read()
                self.assertNotIn(SIM_VIN, text)
                self.assertNotIn("0000", text.split("-" * 60)[0])   # header has no VIN digits
                self.assertNotIn(ct.spaced_hex(SIM_VIN.encode()[3:]), text)
                self.assertIn("57 42 41 ** ** ** ** ** ** ** ** ** ** ** ** ** **", text)


if __name__ == "__main__":
    unittest.main()
