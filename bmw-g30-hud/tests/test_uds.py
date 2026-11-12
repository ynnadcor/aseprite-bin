# SPDX-License-Identifier: MIT
import json
import os
import sys
import unittest

HERE = os.path.dirname(__file__)
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "proto"))

from bmwdiag import uds  # noqa: E402

VECTORS = json.load(open(os.path.join(ROOT, "test-vectors", "doip_uds_vectors.json")))


class TestUdsBuilders(unittest.TestCase):
    def test_build_rdbi_vector(self):
        v = VECTORS["uds"]["build_rdbi_vin"]
        self.assertEqual(uds.build_read_data_by_identifier(v["did"]).hex(), v["request_hex"])

    def test_build_read_dtc_vector(self):
        v = VECTORS["uds"]["build_read_dtc"]
        self.assertEqual(uds.build_read_dtc_by_status_mask(v["status_mask"]).hex(), v["request_hex"])

    def test_build_tester_present_vector(self):
        v = VECTORS["uds"]["build_tester_present"]
        self.assertEqual(uds.build_tester_present(v["suppress"]).hex(), v["request_hex"])

    def test_session_control_only_default(self):
        self.assertEqual(uds.build_diagnostic_session_control(0x01).hex(), "1001")
        with self.assertRaises(ValueError):
            uds.build_diagnostic_session_control(0x03)  # extended session blocked
        with self.assertRaises(ValueError):
            uds.build_diagnostic_session_control(0x02)  # programming session blocked


class TestUdsParsing(unittest.TestCase):
    def test_parse_rdbi_vin(self):
        v = VECTORS["uds"]["parse_rdbi_vin"]
        parsed = uds.parse_response(bytes.fromhex(v["request_hex"]), bytes.fromhex(v["response_hex"]))
        self.assertEqual(parsed.did, v["expect_did"])
        self.assertEqual(parsed.data.decode("ascii"), v["expect_ascii"])

    def test_parse_read_dtc(self):
        v = VECTORS["uds"]["parse_read_dtc"]
        parsed = uds.parse_response(bytes.fromhex(v["request_hex"]), bytes.fromhex(v["response_hex"]))
        self.assertEqual(len(parsed.records), len(v["expect_records"]))
        self.assertEqual(parsed.records[0].code, v["expect_records"][0]["dtc"])
        self.assertEqual(parsed.records[0].status, v["expect_records"][0]["status"])

    def test_parse_negative_response_raises(self):
        v = VECTORS["uds"]["parse_negative_response"]
        with self.assertRaises(uds.UdsNegativeResponse) as ctx:
            uds.parse_response(bytes.fromhex(v["request_hex"]), bytes.fromhex(v["response_hex"]))
        self.assertEqual(ctx.exception.request_sid, v["expect_request_sid"])
        self.assertEqual(ctx.exception.nrc, v["expect_nrc"])

    def test_response_sid_mismatch_raises(self):
        with self.assertRaises(ValueError):
            uds.parse_response(bytes.fromhex("22f190"), bytes.fromhex("6ef190"))


class TestReadOnlyEnforcement(unittest.TestCase):
    def test_write_services_are_blocked(self):
        # Every blocked SID from the shared vector list must raise on guard.
        for sid_hex in VECTORS["blocked_services_must_refuse"]:
            sid = int(sid_hex, 16)
            with self.assertRaises(ValueError, msg=f"SID {sid_hex} should be blocked"):
                uds._guard(sid)

    def test_allowed_services_are_exactly_read_only(self):
        self.assertEqual(
            uds.ALLOWED_SERVICES,
            frozenset(
                {
                    uds.UdsService.DIAGNOSTIC_SESSION_CONTROL,
                    uds.UdsService.TESTER_PRESENT,
                    uds.UdsService.READ_DTC_INFORMATION,
                    uds.UdsService.READ_DATA_BY_IDENTIFIER,
                    0x01, 0x03, 0x07, 0x0A,   # OBD-II reads
                }
            ),
        )

    def test_obd_clear_and_control_are_blocked(self):
        for sid in (0x04, 0x08, 0x14):
            with self.assertRaises(ValueError):
                uds.build_obd_request(sid)


class TestObdReads(unittest.TestCase):
    V = VECTORS["obd"]

    def test_builders(self):
        for key in ("build_stored", "build_pending", "build_permanent", "build_monitor_status"):
            v = self.V[key]
            got = uds.build_obd_request(v["service"], v.get("pid"))
            self.assertEqual(got.hex(), v["expect_hex"], key)

    def test_mode_01_needs_a_pid(self):
        with self.assertRaises(ValueError):
            uds.build_obd_request(0x01)

    def test_code_lists(self):
        for v in self.V["dtc_responses"]:
            got = uds.parse_obd_dtcs(v["request_sid"], bytes.fromhex(v["response_hex"]))
            self.assertEqual(got, v["codes"], v["response_hex"])

    def test_negative_answer(self):
        v = self.V["negative"]
        with self.assertRaises(uds.UdsNegativeResponse) as ctx:
            uds.parse_obd_dtcs(v["request_sid"], bytes.fromhex(v["response_hex"]))
        self.assertEqual(ctx.exception.nrc, v["expect_nrc"])

    def test_wrong_answer_and_odd_length(self):
        with self.assertRaises(ValueError):
            uds.parse_obd_dtcs(0x03, bytes.fromhex("470171"))
        with self.assertRaises(ValueError):
            uds.parse_obd_dtcs(0x03, bytes.fromhex("43020171"))

    def test_sae_letters(self):
        self.assertEqual(uds.sae_dtc(0x01, 0x71), "P0171")
        self.assertEqual(uds.sae_dtc(0x13, 0x00), "P1300")
        self.assertEqual(uds.sae_dtc(0x7F, 0xFF), "C3FFF")
        self.assertEqual(uds.sae_dtc(0xC1, 0x55), "U0155")


if __name__ == "__main__":
    unittest.main()
