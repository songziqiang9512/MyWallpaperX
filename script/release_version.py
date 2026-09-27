#!/usr/bin/env python3
"""One committed version/build pair for source, App and Sparkle publication."""

import argparse
from pathlib import Path
import plistlib
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT = Path("MyWallpaperX.xcodeproj/project.pbxproj")
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def version_pair(version, build):
    if not isinstance(version, str) or not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError(f"Invalid marketing version: {version!r}")
    if not re.fullmatch(r"[1-9][0-9]*", str(build)):
        raise ValueError(f"Invalid build version: {build!r}")
    return version, int(build)


def project_version(text):
    values = []
    for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
        found = {value.strip().strip('"') for value in re.findall(rf"{key} = ([^;]+);", text)}
        if len(found) != 1:
            raise ValueError(f"Missing or conflicting {key}: {sorted(found)}")
        values.append(found.pop())
    return version_pair(*values)


def appcast_version(data):
    items = ET.fromstring(data).findall("channel/item")
    if len(items) != 1:
        raise ValueError("Release feed must contain exactly one item")
    return version_pair(items[0].findtext(SPARKLE + "shortVersionString"),
                        items[0].findtext(SPARKLE + "version"))


def require_newer(candidate, previous):
    if tuple(map(int, candidate[0].split('.'))) <= tuple(map(int, previous[0].split('.'))) or candidate[1] <= previous[1]:
        raise ValueError(f"Version and build must both increase: {candidate} <= published {previous}")


def validate_artifacts(expected, *, app=None, appcast=None, previous_appcast=None):
    if app:
        with (app / "Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        actual = version_pair(info.get("CFBundleShortVersionString"), info.get("CFBundleVersion"))
        if actual != expected:
            raise ValueError(f"App version {actual} differs from committed project {expected}")
    if appcast:
        actual = appcast_version(appcast.read_bytes())
        if actual != expected:
            raise ValueError(f"Appcast version {actual} differs from committed project {expected}")
    if previous_appcast:
        require_newer(expected, appcast_version(previous_appcast.read_bytes()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--appcast", type=Path)
    parser.add_argument("--previous-appcast", type=Path)
    args = parser.parse_args()
    try:
        version, build = project_version((ROOT / PROJECT).read_text())
        validate_artifacts((version, build), **vars(args))
    except (OSError, ValueError, ET.ParseError, plistlib.InvalidFileException) as error:
        parser.error(str(error))
    print(f"MARKETING_VERSION={version}\nBUILD_VERSION={build}")


if __name__ == "__main__":
    main()
