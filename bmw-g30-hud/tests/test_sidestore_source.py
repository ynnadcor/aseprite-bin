# SPDX-License-Identifier: MIT
"""tools/make_sidestore_source.py reads the .ipa and writes a valid source."""

import datetime
import importlib.util
import json
import os
import plistlib
import sys
import tempfile
import unittest
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "make_sidestore_source", os.path.join(os.path.dirname(HERE), "tools", "make_sidestore_source.py"))
src = importlib.util.module_from_spec(_spec)
sys.modules["make_sidestore_source"] = src
_spec.loader.exec_module(src)


def fake_ipa(path, version="0.2.12", build="12"):
    info = {
        "CFBundleIdentifier": "io.github.ynnadcor.bmwlink",
        "CFBundleDisplayName": "BMW Link",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
        "MinimumOSVersion": "16.0",
        "NSLocalNetworkUsageDescription": "Reads diagnostic data over the ENET cable.",
    }
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("Payload/BMWLink.app/Info.plist", plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
        z.writestr("Payload/BMWLink.app/BMWLink", b"\x00" * 64)
        z.writestr("Payload/BMWLink.app/Frameworks/X.framework/Info.plist", plistlib.dumps({"a": 1}))


class SideStoreSourceTests(unittest.TestCase):
    def test_source_matches_the_ipa(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = os.path.join(tmp, "BMWLink.ipa")
            fake_ipa(ipa)
            out = os.path.join(tmp, "source.json")
            with open(os.devnull, "w") as quiet:
                old, sys.stdout = sys.stdout, quiet
                try:
                    code = src.main(["--ipa", ipa, "--download-url", "https://example.invalid/BMWLink.ipa",
                                     "--icon-url", "https://example.invalid/icon.png", "--notes", "Build 12",
                                     "--out", out])
                finally:
                    sys.stdout = old
            self.assertEqual(code, 0)
            with open(out) as f:
                data = json.load(f)
            app = data["apps"][0]
            v = app["versions"][0]
            self.assertEqual(data["identifier"], "io.github.ynnadcor.bmwlink.source")
            self.assertEqual(app["bundleIdentifier"], "io.github.ynnadcor.bmwlink")
            self.assertEqual(app["name"], "BMW Link")
            self.assertEqual((v["version"], v["buildVersion"], v["minOSVersion"]), ("0.2.12", "12", "16.0"))
            self.assertEqual(v["size"], os.path.getsize(ipa))
            self.assertEqual(v["downloadURL"], "https://example.invalid/BMWLink.ipa")
            self.assertEqual(app["appPermissions"]["privacy"],
                             {"NSLocalNetworkUsageDescription": "Reads diagnostic data over the ENET cable."})
            self.assertEqual(app["appPermissions"]["entitlements"], [])
            self.assertEqual((app["version"], app["downloadURL"]), ("0.2.12", v["downloadURL"]))
            datetime.datetime.strptime(v["date"], "%Y-%m-%dT%H:%M:%SZ")

    def test_rejects_a_file_that_is_not_an_app(self):
        with tempfile.TemporaryDirectory() as tmp:
            bad = os.path.join(tmp, "bad.ipa")
            with zipfile.ZipFile(bad, "w") as z:
                z.writestr("readme.txt", "no app here")
            with self.assertRaises(ValueError):
                src.build_source(bad, "u", "i", "n", "")


if __name__ == "__main__":
    unittest.main()
