# SPDX-License-Identifier: MIT
import os
import sys
import unittest

HERE = os.path.dirname(__file__)
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "proto"))

from bmwdiag import MockEnetServer, ReadOnlyDiagClient, uds  # noqa: E402
from bmwdiag import doip  # noqa: E402


class TestClientAgainstMock(unittest.TestCase):
    def setUp(self):
        self.vin = "WBAJE7C50JWA00000"
        self.server = MockEnetServer(vin=self.vin)
        self.client = ReadOnlyDiagClient(self.server, target_address=doip.ZGW_ADDRESS)

    def test_identify_returns_vin(self):
        ann = self.client.identify()
        self.assertEqual(ann.vin, self.vin)
        self.assertEqual(ann.logical_address, doip.ZGW_ADDRESS)

    def test_routing_activation_required_before_diag(self):
        # Without activation, a diagnostic message should be NACKed.
        with self.assertRaises(ConnectionError):
            self.client.read_did_raw(0xF190)
        self.assertTrue(self.client.activate())
        # now it works
        self.assertEqual(self.client.read_did_raw(0xF190).decode(), self.vin)

    def test_tester_present(self):
        self.client.activate()
        self.client.tester_present()  # should not raise

    def test_unknown_did_raises_negative(self):
        self.client.activate()
        with self.assertRaises(uds.UdsNegativeResponse):
            self.client.read_did_raw(0x1234)

    def test_read_dtcs(self):
        self.client.activate()
        dtcs = self.client.read_dtcs()
        self.assertEqual(dtcs.records[0].code, "0x4B1C00")

    def test_gather_vehicle_info(self):
        info = self.client.gather_vehicle_info()
        self.assertEqual(info.vin, self.vin)
        self.assertEqual(info.ecu_name, "HeadUnitHigh2")
        self.assertEqual(info.app_sw_version, "NBTevo_Y24073J")

    def test_candidate_live_values_decode(self):
        self.client.activate()
        oil, meta = self.client.read_did(0xDD03)
        self.assertEqual(oil, 104)             # 40 + 104 raw -> 104 C
        self.assertFalse(meta.verified)        # still flagged UNVERIFIED
        load, meta2 = self.client.read_did(0xDD05)
        self.assertAlmostEqual(load, 62.0, delta=0.5)


if __name__ == "__main__":
    unittest.main()
