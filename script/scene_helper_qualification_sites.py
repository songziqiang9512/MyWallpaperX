#!/usr/bin/env python3
"""List the call sites that stopped resolving after Scene helper definitions moved.

Consolidating a duplicated helper family means deleting definitions in many files
and qualifying the call sites that used them.  Name-based regex rewriting is not
safe for that step: Scene has unrelated same-name helpers, nested local functions
with the same name, and local variables named like the helper, so a repository-wide
substitution silently rewrites unrelated code (observed twice during the
2026-09-29 shader source-text consolidation).

This tool uses the compiler instead: for every harness source set that compiles a
Scene shader file it typechecks the set and reports the `cannot find '<name>' in
scope` sites, which is exactly the set of call sites whose definition moved.  Run it
after deleting the definitions and before rewriting any call site.

Usage:
    python3 script/scene_helper_qualification_sites.py --name matches --name capture
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
TESTS_ROOT = REPOSITORY_ROOT / "script/tests"
FAMILY_PREFIXES = (
    "Compilation/ShaderPreparation",
    "Compilation/ShaderFrontend",
    "Compilation/ShaderContract",
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", action="append", required=True, help="helper name whose definition moved")
    parser.add_argument("--family", action="append", default=[], help="source-root prefix to consider (default: shader family)")
    return parser.parse_args()


def load_module(path: Path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    sys.modules[path.stem] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        return None
    return module


def harness_sets(prefixes: tuple[str, ...]) -> list[tuple[str, list[Path], str]]:
    sys.path.insert(0, str(REPOSITORY_ROOT / "script"))
    sys.path.insert(0, str(TESTS_ROOT))
    sets = []
    for test_path in sorted(TESTS_ROOT.glob("test_*.py")):
        text = test_path.read_text(encoding="utf-8", errors="ignore")
        if "SWIFT_SOURCES" not in text and "scene_swift_source" not in text:
            continue
        module = load_module(test_path)
        if module is None:
            continue
        sources = sorted({Path(path) for path in getattr(module, "SWIFT_SOURCES", [])})
        if not any(any(prefix in str(path) for prefix in prefixes) for path in sources):
            continue
        value = getattr(module, "HARNESS", "import Foundation\n")
        harness_text = value.read_text(encoding="utf-8") if isinstance(value, Path) else str(value)
        sets.append((test_path.stem, sources, harness_text))
    return sets


def unresolved_sites(names: list[str], sets) -> list[str]:
    pattern = re.compile(r"(.+?\.swift):(\d+):\d+: error: cannot find '(%s)' in scope" % "|".join(map(re.escape, names)))
    sites = set()
    scratch = Path("/private/tmp")
    for stem, sources, harness_text in sets:
        harness = scratch / f"mwx-qualification-{stem}.swift"
        harness.write_text(harness_text, encoding="utf-8")
        completed = subprocess.run(
            ["swiftc", "-parse-as-library", "-typecheck", *map(str, sources), str(harness)],
            capture_output=True,
            text=True,
        )
        for line in completed.stderr.splitlines():
            match = pattern.match(line)
            if match:
                sites.add((match.group(1), int(match.group(2)), match.group(3)))
    return [f"{path}:{line}:{name}" for path, line, name in sorted(sites)]


def main() -> int:
    args = parse_arguments()
    prefixes = tuple(args.family) or FAMILY_PREFIXES
    sets = harness_sets(prefixes)
    if not sets:
        print("no harness source set compiles the requested family", file=sys.stderr)
        return 2
    sites = unresolved_sites(args.name, sets)
    print(f"harness sets typechecked: {len(sets)}; unresolved sites: {len(sites)}")
    for path, count in Counter(entry.split(":")[0].split("/")[-1] for entry in sites).most_common():
        print(f"  {count:4d}  {path}")
    for entry in sites:
        print(entry)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
