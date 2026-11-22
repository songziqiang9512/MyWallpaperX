#!/usr/bin/env python3
"""Report test modules that no validation path group selects."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "script/scene_validation_gates.json"


def load_registry() -> dict:
    return json.loads(REGISTRY.read_text())


def mapped_modules(registry: dict) -> tuple[set[str], set[str]]:
    modules: set[str] = set()
    keywords: set[str] = set()
    for group in registry.get("path_groups", []):
        group_modules = [name for name in group.get("modules", []) if isinstance(name, str)]
        modules.update(group_modules)
        if not group_modules:
            keywords.update(name for name in group.get("keywords", []) if isinstance(name, str))
    for gate in registry.get("method_gates", {}).values():
        if isinstance(gate, dict) and gate.get("module"):
            modules.add(gate["module"])
    return modules, keywords


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--strict", action="store_true", help="fail when unmapped modules exist")
    args = parser.parse_args()

    modules, keywords = mapped_modules(load_registry())
    tests = sorted(path.stem for path in (ROOT / "script/tests").glob("test_*.py"))
    unmapped = [name for name in tests if name not in modules and not any(key in name for key in keywords)]
    payload = {
        "testModules": len(tests),
        "mappedModules": len(tests) - len(unmapped),
        "unmappedModules": unmapped,
        "keywords": sorted(keywords),
        "evidenceLimit": "Registry associations only select tests; they do not prove behavior coverage.",
    }
    if args.format == "json":
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    else:
        print(
            f"tests={payload['testModules']} mapped={payload['mappedModules']} "
            f"unmapped={len(unmapped)}"
        )
        for name in unmapped:
            print(name)
    return 1 if args.strict and unmapped else 0


if __name__ == "__main__":
    raise SystemExit(main())
