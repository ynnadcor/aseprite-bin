# SPDX-License-Identifier: MIT
import json
import os
import sys
import unittest

HERE = os.path.dirname(__file__)
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "proto"))

from bmwdiag import doip  # noqa: E402

VECTORS = json.load(open(os.path.join(ROOT, "test-vectors", "doip_uds_vectors.json")))


class TestDoIPFraming(unittest.TestCase):
    def test_vehicle_identification_request_vector(self):
        got = doip.build_vehicle_identification_request().hex()
        self.assertEqual(got, VECTORS["doip"]["vehicle_identification_request"]["frame_hex"])

    def test_routing_activation_request_vector(self):
        v = VECTORS["doip"]["routing_activation_request_default"]
        got = doip.build_routing_activation_request(v["tester_address"]).hex()
        self.assertEqual(got, v["frame_hex"])

    def test_diagnostic_message_vector(self):
        v = VECTORS["doip"]["diagnostic_message_tester_present"]
        frame = doip.build_diagnostic_message(
            v["source"], v["target"], bytes.fromhex(v["uds_hex"])
        )
        self.assertEqual(frame.hex(), v["frame_hex"])

    def test_header_roundtrip_and_inverse_check(self):
        frame = doip.build_vehicle_identification_request()
        header, rest = doip.parse_header(frame)
        self.assertEqual(header.payload_type, doip.PayloadType.VEHICLE_ID_REQUEST)
        self.assertEqual(header.payload_length, 0)
        self.assertEqual(rest, b"")

    def test_bad_inverse_version_rejected(self):
        frame = bytearray(doip.build_vehicle_identification_request())
        frame[1] ^= 0xFF  # corrupt the inverse-version byte
        with self.assertRaises(ValueError):
            doip.parse_header(bytes(frame))

    def test_parse_vehicle_announcement(self):
        vin = "WBAJE7C50JWA00000"
        payload = vin.encode().ljust(17, b"\x00")
        payload += (0x0010).to_bytes(2, "big")
        payload += b"\x01\x02\x03\x04\x05\x06"  # EID
        payload += b"\x01\x02\x03\x04\x05\x06"  # GID
        payload += b"\x00"
        ann = doip.parse_vehicle_announcement(payload)
        self.assertEqual(ann.vin, vin)
        self.assertEqual(ann.logical_address, 0x0010)

    def test_short_payloads_raise(self):
        with self.assertRaises(ValueError):
            doip.parse_vehicle_announcement(b"\x00" * 10)
        with self.assertRaises(ValueError):
            doip.parse_routing_activation_response(b"\x00")
        with self.assertRaises(ValueError):
            doip.parse_diagnostic_message(b"\x00")


if __name__ == "__main__":
    unittest.main()
