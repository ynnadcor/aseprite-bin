#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Write the SideStore/AltStore "source" that lists the latest BMW Link build.

Add the published source to SideStore once (Sources > +); after that, every new
build CI publishes shows up in SideStore as an update. The app's name, bundle
ID, versions, minimum iOS and permission texts are read from the .ipa itself,
so the source always matches the file it points to.

    python3 make_sidestore_source.py --ipa BMWLink.ipa --download-url URL \
        --icon-url URL --notes "what changed" --out sidestore-source.json

Format: AltStore source v2 (used by SideStore), plus the older single-version
fields that earlier versions read.
"""

import argparse
import datetime
import json
import os
import plistlib
import sys
import zipfile

SOURCE_ID = "io.github.ynnadcor.bmwlink.source"
TINT = "#1C69D4"


def read_info_plist(ipa_path):
    with zipfile.ZipFile(ipa_path) as z:
        names = [n for n in z.namelist()
                 if n.startswith("Payload/") and n.endswith(".app/Info.plist") and n.count("/") == 2]
        if len(names) != 1:
            raise ValueError("expected one Payload/<app>.app/Info.plist in %s, found %d" % (ipa_path, len(names)))
        return plistlib.loads(z.read(names[0]))


def build_source(ipa_path, download_url, icon_url, notes, website, now=None):
    info = read_info_plist(ipa_path)
    version = info.get("CFBundleShortVersionString", "0")
    build = str(info.get("CFBundleVersion", "0"))
    when = (now or datetime.datetime.now(datetime.timezone.utc)).strftime("%Y-%m-%dT%H:%M:%SZ")
    size = os.path.getsize(ipa_path)
    privacy = {k: v for k, v in sorted(info.items()) if k.endswith("UsageDescription") and isinstance(v, str)}
    description = ("Read-only BMW diagnostics over the ENET cable (finds the car, reads identification, "
                   "software versions and fault memory) and a HUD navigation preview. It cannot write, "
                   "code, clear faults or flash anything.")
    entry = {
        "version": version,
        "buildVersion": build,
        "date": when,
        "localizedDescription": notes,
        "downloadURL": download_url,
        "size": size,
        "minOSVersion": str(info.get("MinimumOSVersion", "16.0")),
    }
    app = {
        "name": info.get("CFBundleDisplayName") or info.get("CFBundleName", "BMW Link"),
        "bundleIdentifier": info["CFBundleIdentifier"],
        "developerName": "bmw-g30-hud project",
        "subtitle": "Read-only BMW G30 car test and HUD preview",
        "localizedDescription": description,
        "iconURL": icon_url,
        "tintColor": TINT,
        "category": "utilities",
        "screenshots": [],
        "versions": [entry],
        "appPermissions": {"entitlements": [], "privacy": privacy},
        # Older single-version fields.
        "version": version,
        "versionDate": when,
        "versionDescription": notes,
        "downloadURL": download_url,
        "size": size,
    }
    return {
        "name": "BMW Link (G30)",
        "identifier": SOURCE_ID,
        "subtitle": "Builds of the bmw-g30-hud project",
        "description": description,
        "iconURL": icon_url,
        "website": website,
        "tintColor": TINT,
        "apps": [app],
        "news": [],
    }


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--ipa", required=True)
    p.add_argument("--download-url", required=True)
    p.add_argument("--icon-url", required=True)
    p.add_argument("--notes", default="New build.")
    p.add_argument("--website", default="")
    p.add_argument("--out", required=True)
    args = p.parse_args(argv)
    source = build_source(args.ipa, args.download_url, args.icon_url, args.notes, args.website)
    with open(args.out, "w") as f:
        json.dump(source, f, indent=2)
        f.write("\n")
    v = source["apps"][0]["versions"][0]
    print("wrote %s: %s %s (%s) %d bytes" % (args.out, source["apps"][0]["bundleIdentifier"],
                                            v["version"], v["buildVersion"], v["size"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
