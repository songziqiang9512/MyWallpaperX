#!/usr/bin/env python3
"""Format or lint Swift files changed from a Git revision."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="HEAD", help="Git revision compared with the working tree")
    parser.add_argument("--lint", action="store_true", help="Report differences instead of rewriting files")
    return parser.parse_args()


def _git_paths(*arguments: str) -> list[str]:
    completed = subprocess.run(
        ["git", *arguments],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return [line for line in completed.stdout.splitlines() if line]


def changed_swift_files(base: str) -> list[Path]:
    changed = _git_paths("diff", "--name-only", "--diff-filter=ACMR", base, "--", "*.swift")
    untracked = _git_paths("ls-files", "--others", "--exclude-standard", "--", "*.swift")
    return sorted({ROOT / line for line in (*changed, *untracked)})


def main() -> int:
    args = parse_arguments()
    files = [path for path in changed_swift_files(args.base) if path.is_file()]
    if not files:
        print("No changed Swift files.")
        return 0
    command = ["xcrun", "swift-format", "lint" if args.lint else "format"]
    command.append("--strict" if args.lint else "--in-place")
    command.extend(["--configuration", str(ROOT / ".swift-format")])
    command.extend(str(path) for path in files)
    return subprocess.run(command, cwd=ROOT).returncode


if __name__ == "__main__":
    raise SystemExit(main())
