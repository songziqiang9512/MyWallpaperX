"""Credential-free compiler fixtures with real, content-pinned signature checks.

Only a temporary resolver copy receives a test trust requirement. The product
resolver retains its Apple/Team requirement and is tested separately unchanged.
See https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
RESOLVER = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderCompilerBundle.swift"


def compiler_bundle(root: Path, *, signing_identity: str = "-") -> Path:
    resources = ROOT / "MyWallpaperX/Resources"
    bundle = root / "Compiler.bundle"
    contents = bundle / "Contents"
    (contents / "Resources").mkdir(parents=True)
    (contents / "Helpers").mkdir()
    (contents / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "org.mywallpaperx.self-authored-coordinate-test",
        "CFBundlePackageType": "BNDL", "CFBundleVersion": "1",
    }))
    shutil.copytree(resources / "SceneShaderCompilerLicenses.bundle",
                    contents / "Resources/SceneShaderCompilerLicenses.bundle")
    for name in ("glslang", "spirv-cross"):
        target = contents / "Helpers" / name
        shutil.copy2(resources / "SceneShaderCompilerTools" / name, target)
        for arguments in (["--force", "--sign", signing_identity, "--timestamp=none"],
                          ["--verify", "--strict", "--all-architectures"]):
            result = subprocess.run(["/usr/bin/codesign", *arguments, str(target)],
                capture_output=True, text=True, timeout=30)
            if result.returncode:
                raise RuntimeError("Temporary compiler helper signature failed: " + result.stderr)
    return bundle


def fixture_sources(root: Path, bundle: Path, sources: list[Path]) -> list[Path]:
    """Pin each signed fixture helper; keep all real resolver checks and APIs.

    This is a test-boundary substitution, not a product override or a switch
    that can authorize ad-hoc helpers in the App. No signature result is mocked.
    """
    unique = list(dict.fromkeys(sources))
    resolvers = [p for p in unique if p.name == RESOLVER.name]
    if len(resolvers) != 1:
        raise ValueError("Compiler fixture requires exactly one real bundle resolver")
    original = resolvers[0]
    source = original.read_text()
    hashes = {}
    for name in ("glslang", "spirv-cross"):
        target = bundle / "Contents/Helpers" / name
        description = subprocess.run(["/usr/bin/codesign", "--display", "--verbose=4", str(target)],
            capture_output=True, text=True, check=True, timeout=30)
        matches = re.findall(r"^CDHash=([0-9a-fA-F]{40})$", description.stderr, re.MULTILINE)
        if len(matches) != 1:
            raise ValueError("Expected one arm64 fixture CodeDirectory hash: " + name)
        hashes[name] = matches[0]
    needle = r'        let expression = "anchor apple generic and certificate leaf[subject.OU] = \"\(expectedTeamID)\""'
    if source.count(needle) != 1:
        raise ValueError("Resolver signature boundary changed; review the fixture trust substitution")
    lines = ["        let expression: String", "        switch url.lastPathComponent {"]
    for name, digest in hashes.items():
        requirement = f'cdhash H"{digest}"'
        lines.append(f"        case {json.dumps(name)}: expression = {json.dumps(requirement)}")
    lines += ["        default: return false", "        }"]
    transformed = source.replace(needle, "\n".join(lines))
    destination = root / "fixture-sources" / original.name
    destination.parent.mkdir(exist_ok=True)
    destination.write_text(transformed)
    (root / "fixture-trust.json").write_text(json.dumps({
        "scope": "test trust authority only; not Developer ID or distribution evidence",
        "originalResolverSHA256": hashlib.sha256(source.encode()).hexdigest(),
        "fixtureResolverSHA256": hashlib.sha256(transformed.encode()).hexdigest(),
        "helperCDHashes": hashes,
    }, indent=2) + "\n")
    return [destination if p == original else p for p in unique]
