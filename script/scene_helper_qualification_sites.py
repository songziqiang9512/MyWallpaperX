#!/usr/bin/env python3
"""Move a duplicated Scene helper family: find the call sites that stopped resolving,
qualify them, and verify the edits did not break the enclosing structure.

Consolidating a duplicated helper family means deleting definitions in many files and
qualifying the call sites that used them.  Name-based regex rewriting is not safe for
that step: Scene has unrelated same-name helpers, nested local functions with the same
name, local variables named like the helper, and shadowing declarations such as
`let matches = matches(pattern, in: source)`.  Rewriting by name alone silently edits
unrelated code (observed three times during the 2026-09-29 shader source-text
consolidation), and deleting a definition can also consume the enclosing type's closing
brace.

This tool therefore uses the compiler as the source of truth:

* Scan mode (default) typechecks every harness source set that compiles the family and
  reports the diagnostic sites that mean "this definition moved": `cannot find 'X' in
  scope` and `use of local variable 'X' before its declaration` (the shadowing form).
  Sets that cannot be imported are reported with their reason instead of being skipped
  silently.
* `--apply` qualifies those exact sites, anchored on the file and the line the compiler
  reported (searching at most three lines away when a diagnostic points past a
  multi-line call), never touching an already-qualified occurrence, and repeats until
  the compiler stops reporting the family.
* `--brace-delta` is the post-condition for the deletion step: every edited file must
  keep the same brace deficit as its committed version, because a naive cut can swallow
  the closing brace of the enclosing type (brace counting inside regex literals such as
  `#{2}#` makes a plain count unusable).

Usage:
    python3 script/scene_helper_qualification_sites.py --name matches --name capture
    python3 script/scene_helper_qualification_sites.py --name matches --apply
    python3 script/scene_helper_qualification_sites.py --brace-delta path/to/File.swift
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Iterable, Sequence


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
TESTS_ROOT = REPOSITORY_ROOT / "script/tests"
FAMILY_PREFIXES = (
    "Compilation/ShaderPreparation",
    "Compilation/ShaderFrontend",
    "Compilation/ShaderContract",
)
DIAGNOSTIC_PATTERNS = (
    re.compile(r"(.+?\.swift):(\d+):(\d+): error: cannot find '([A-Za-z_]\w*)' in scope"),
    re.compile(
        r"(.+?\.swift):(\d+):(\d+): error: use of local variable '([A-Za-z_]\w*)' before its declaration"
    ),
)
SEARCH_WINDOW = 3
MAX_ITERATIONS = 8


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", action="append", required=True, help="helper name whose definition moved")
    parser.add_argument("--family", action="append", default=[], help="source-root prefix to consider (default: shader family)")
    parser.add_argument("--apply", action="store_true", help="qualify the reported sites and iterate until clean")
    parser.add_argument("--qualified-with", default="SceneShaderSourceTextFacts", help="type that now owns the helper")
    parser.add_argument("--brace-delta", action="append", default=[], help="file edited by a deletion; verify its brace deficit")
    parser.add_argument("--base-ref", default="HEAD", help="git ref the brace deficit is compared against")
    return parser.parse_args()


def load_module(path: Path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    if spec is None or spec.loader is None:
        return None, "no import spec"
    module = importlib.util.module_from_spec(spec)
    sys.modules[path.stem] = module
    try:
        spec.loader.exec_module(module)
    except Exception as error:  # pragma: no cover - depends on the module under test
        return None, f"{type(error).__name__}: {error}"
    return module, None


def harness_sets(prefixes: tuple[str, ...]) -> tuple[list[tuple[str, list[Path], str]], list[tuple[str, str]]]:
    sys.path.insert(0, str(REPOSITORY_ROOT / "script"))
    sys.path.insert(0, str(TESTS_ROOT))
    sets: list[tuple[str, list[Path], str]] = []
    skipped: list[tuple[str, str]] = []
    for test_path in sorted(TESTS_ROOT.glob("test_*.py")):
        text = test_path.read_text(encoding="utf-8", errors="ignore")
        if "SWIFT_SOURCES" not in text and "scene_swift_source" not in text:
            continue
        module, error = load_module(test_path)
        if module is None:
            skipped.append((test_path.stem, f"import failed: {error}"))
            continue
        sources = sorted({Path(path) for path in getattr(module, "SWIFT_SOURCES", [])})
        if not sources:
            # An empty set cannot compile the family; report it only when the module
            # clearly intends to (it names one of the family prefixes).
            if any(prefix in text for prefix in prefixes):
                skipped.append((test_path.stem, "empty SWIFT_SOURCES"))
            continue
        if not any(any(prefix in str(path) for prefix in prefixes) for path in sources):
            continue
        value = getattr(module, "HARNESS", "import Foundation\n")
        harness_text = value.read_text(encoding="utf-8") if isinstance(value, Path) else str(value)
        sets.append((test_path.stem, sources, harness_text))
    return sets, skipped


def scan_sites(names: Sequence[str], sets) -> tuple[list[tuple[str, int, int, str]], list[tuple[str, str]]]:
    wanted = set(names)
    records: set[tuple[str, int, int, str]] = set()
    failures: list[tuple[str, str]] = []
    scratch = Path("/private/tmp")
    for stem, sources, harness_text in sets:
        harness = scratch / f"mwx-qualification-{stem}.swift"
        harness.write_text(harness_text, encoding="utf-8")
        completed = subprocess.run(
            ["swiftc", "-parse-as-library", "-typecheck", *map(str, sources), str(harness)],
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0 and not completed.stderr:
            failures.append((stem, f"swiftc exited {completed.returncode} without diagnostics"))
        for line in completed.stderr.splitlines():
            for pattern in DIAGNOSTIC_PATTERNS:
                match = pattern.match(line)
                if match and match.group(4) in wanted:
                    records.add((match.group(1), int(match.group(2)), int(match.group(3)), match.group(4)))
                    break
    return sorted(records), failures


def unresolved_sites(names: list[str], sets) -> list[str]:
    records, _ = scan_sites(names, sets)
    return [f"{path}:{line}:{name}" for path, line, _, name in records]


def qualify(path: str, line: int, column: int, name: str, qualified_with: str) -> bool:
    """Qualify one reported site, anchored on the line the compiler pointed at."""

    file = Path(path)
    lines = file.read_text(encoding="utf-8").splitlines(keepends=True)
    pattern = re.compile(r"(?<![.\w])%s\s*\(" % re.escape(name))
    first = max(0, line - 1 - SEARCH_WINDOW)
    last = min(len(lines), line - 1 + SEARCH_WINDOW + 1)
    for index in range(first, last):
        text = lines[index]
        match = pattern.search(text)
        if match is None:
            continue
        lines[index] = text[: match.start()] + f"{qualified_with}.{name}" + text[match.end() - 1:]
        file.write_text("".join(lines), encoding="utf-8")
        return True
    return False


def apply_qualifications(names: Sequence[str], sets, qualified_with: str) -> tuple[int, list[str]]:
    total = 0
    unresolved: list[str] = []
    for iteration in range(1, MAX_ITERATIONS + 1):
        records, _ = scan_sites(names, sets)
        print(f"iteration {iteration}: unresolved sites={len(records)}", flush=True)
        if not records:
            return total, []
        missed = []
        for path, line, column, name in sorted(records, reverse=True):
            if qualify(path, line, column, name, qualified_with):
                total += 1
            else:
                missed.append(f"{path}:{line}:{column}:{name}")
        if missed:
            unresolved = missed
            print(f"   {len(missed)} site(s) could not be qualified", flush=True)
            return total, unresolved
        print(f"   qualified {len(records)} site(s)", flush=True)
    records, _ = scan_sites(names, sets)
    return total, [f"{path}:{line}:{column}:{name}" for path, line, column, name in records]


def brace_deficit(text: str) -> int:
    return text.count("{") - text.count("}")


def brace_delta_report(targets: Iterable[str], base_ref: str) -> list[str]:
    problems: list[str] = []
    for rel in targets:
        file = Path(rel)
        if not file.is_file():
            problems.append(f"{rel}: missing")
            continue
        committed = subprocess.run(
            ["git", "show", f"{base_ref}:{rel}"], capture_output=True, text=True
        )
        if committed.returncode != 0:
            problems.append(f"{rel}: not in {base_ref}")
            continue
        before = brace_deficit(committed.stdout)
        after = brace_deficit(file.read_text(encoding="utf-8"))
        if before != after:
            problems.append(
                f"{rel}: brace deficit changed from {before} to {after}; "
                "the edit removed a structural brace"
            )
    return problems


def main() -> int:
    args = parse_arguments()
    prefixes = tuple(args.family) or FAMILY_PREFIXES

    if args.brace_delta:
        problems = brace_delta_report(args.brace_delta, args.base_ref)
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        if problems:
            return 1
        print(f"brace deficit holds for {len(args.brace_delta)} file(s) against {args.base_ref}")
        return 0

    sets, skipped = harness_sets(prefixes)
    for stem, reason in skipped:
        print(f"skipped harness set {stem}: {reason}", file=sys.stderr)
    if not sets:
        print("no harness source set compiles the requested family", file=sys.stderr)
        return 2

    if args.apply:
        total, unresolved = apply_qualifications(args.name, sets, args.qualified_with)
        print(f"qualified {total} site(s)")
        for entry in unresolved:
            print(f"unresolved: {entry}", file=sys.stderr)
        return 1 if unresolved else 0

    records, failures = scan_sites(args.name, sets)
    for stem, reason in failures:
        print(f"harness set produced no diagnostics: {stem}: {reason}", file=sys.stderr)
    print(f"harness sets typechecked: {len(sets)}; unresolved sites: {len(records)}")
    for path, count in Counter(Path(path).name for path, _, _, _ in records).most_common():
        print(f"  {count:4d}  {path}")
    for path, line, _, name in records:
        print(f"{path}:{line}:{name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
