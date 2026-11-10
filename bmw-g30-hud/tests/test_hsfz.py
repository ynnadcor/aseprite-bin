# SPDX-License-Identifier: MIT
import json
import os
import sys
import unittest

HERE = os.path.dirname(__file__)
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "proto"))

from bmwdiag import hsfz, doip  # noqa: E402

VECTORS = json.load(open(os.path.join(ROOT, "test-vectors", "doip_uds_vectors.json")))
H = VECTORS["hsfz"]
D = VECTORS["doip_bmw"]


class TestHSFZ(unittest.TestCase):
    def test_ident_request_vector(self):
        self.assertEqual(hsfz.build_ident_request().hex(), H["ident_request_hex"])

    def test_diagnostic_vector_and_roundtrip(self):
        v = H["diagnostic_rdbi_vin"]
        f = hsfz.build_diagnostic(v["source"], v["target"], bytes.fromhex(v["uds_hex"]))
        self.assertEqual(f.hex(), v["frame_hex"])
        control, payload = hsfz.parse(f)
        self.assertEqual(control, hsfz.CTRL_DIAGNOSTIC)
        self.assertEqual(payload, bytes([0xF4, 0x10]) + bytes.fromhex("22f190"))
        self.assertEqual(hsfz.frame_length(f[:6]), len(f))

    def test_ack_matches_request(self):
        req = bytes.fromhex(H["diagnostic_rdbi_vin"]["frame_hex"])
        ack = bytes.fromhex(H["ack_for_rdbi_vin_hex"])
        self.assertTrue(hsfz.ack_matches(ack, req))
        wrong = bytearray(ack)
        wrong[-1] ^= 0xFF
        self.assertFalse(hsfz.ack_matches(bytes(wrong), req))

    def test_alive_check_response_vector(self):
        self.assertEqual(hsfz.build_alive_check_response(0xF4).hex(), H["alive_check_response_hex"])

    def test_ident_reply_vector_and_parse(self):
        v = H["ident_reply"]
        f = hsfz.build_ident_reply(v["diag_address"], v["mac"], v["vin"])
        self.assertEqual(f.hex(), v["frame_hex"])
        parsed = hsfz.parse_ident_reply(f)
        self.assertEqual(parsed, {"diag_address": 0x10, "mac": v["mac"], "vin": v["vin"]})

    def test_parse_rejects_bad_frames(self):
        with self.assertRaises(ValueError):
            hsfz.parse(b"\x00\x00")
        with self.assertRaises(ValueError):
            hsfz.parse(bytes.fromhex("000000050001f410"))  # truncated
        self.assertIsNone(hsfz.parse_ident_reply(hsfz.frame(hsfz.CTRL_ACK, b"x")))


class TestBMWDoIP(unittest.TestCase):
    def test_bmw_routing_activation_vector(self):
        f = doip.build_routing_activation_request(0x0EF3, 0x00, b"\x00" * 4, version=3)
        self.assertEqual(f.hex(), D["routing_activation_hex"])
        header, payload = doip.parse_header(f)
        self.assertEqual(header.version, 3)
        self.assertEqual(len(payload), 11)

    def test_bmw_vir_and_alive_vectors(self):
        self.assertEqual(doip.build_vehicle_identification_request(version=3).hex(),
                         D["vehicle_identification_request_hex"])
        self.assertEqual(doip.build_alive_check_response(0x0EF3, version=3).hex(),
                         D["alive_check_response_hex"])


if __name__ == "__main__":
    unittest.main()
