#!/usr/bin/env python3
"""Report script entrypoints missing from the index and oversized test modules."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "script"
README = SCRIPT / "README.md"
LINE_LIMIT = 1000


def read_lines(path: Path) -> int:
    return sum(1 for _ in path.open(errors="ignore"))


def inspect() -> dict:
    readme = README.read_text() if README.is_file() else ""
    entries: list[str] = []
    libraries: list[str] = []
    for path in sorted(SCRIPT.rglob("*.py")):
        if "__pycache__" in path.parts or path.is_relative_to(SCRIPT / "tests"):
            continue
        text = path.read_text(errors="ignore")
        (entries if "__main__" in text else libraries).append(path.name)
    oversized = [
        {"path": str(path.relative_to(ROOT)), "lines": lines}
        for path in sorted((SCRIPT / "tests").rglob("test_*.py"))
        if (lines := read_lines(path)) > LINE_LIMIT
    ]
    oversized.sort(key=lambda item: item["lines"], reverse=True)
    return {
        "entrypoints": entries,
        "libraries": libraries,
        "unindexed": [name for name in entries if name not in readme],
        "oversizedTests": oversized,
        "lineLimit": LINE_LIMIT,
        "evidenceLimit": "Index and line counts only; they do not prove whether an entrypoint is still useful.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--strict", action="store_true", help="fail when an entrypoint is unindexed")
    args = parser.parse_args()

    report = inspect()
    if args.format == "json":
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print(
            f"entrypoints={len(report['entrypoints'])} libraries={len(report['libraries'])} "
            f"unindexed={len(report['unindexed'])} oversizedTests={len(report['oversizedTests'])}"
        )
        for name in report["unindexed"]:
            print(f"unindexed {name}")
        for item in report["oversizedTests"]:
            print(f"oversized {item['lines']:>5} {item['path']}")
    return 1 if args.strict and report["unindexed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
