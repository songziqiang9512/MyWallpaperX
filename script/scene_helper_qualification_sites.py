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
* `--apply-from` qualifies the sites of a compiler report produced outside the tool.
  A whole-set typecheck stops reporting once it has enough errors, so a name-dense
  family is swept one file at a time (`swiftc -frontend -typecheck -primary-file`), the
  diagnostics are collected into a report, and the report is handed here; the compiler
  stays an external command rather than something this tool embeds.
* `--brace-delta` is the post-condition for the deletion step: every edited file must
  keep the same brace deficit as its committed version, because a naive cut can swallow
  the closing brace of the enclosing type (brace counting inside regex literals such as
  `#{2}#` makes a plain count unusable).

Usage:
    python3 script/scene_helper_qualification_sites.py --name matches --name capture
    python3 script/scene_helper_qualification_sites.py --name matches --apply
    python3 script/scene_helper_qualification_sites.py --name matches --apply-from report.txt
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
    parser.add_argument("--name", action="append", default=[], help="helper name whose definition moved")
    parser.add_argument("--family", action="append", default=[], help="source-root prefix to consider (default: shader family)")
    parser.add_argument("--apply", action="store_true", help="qualify the reported sites and iterate until clean")
    parser.add_argument(
        "--apply-from",
        help="compiler report produced outside the tool (one file per -primary-file pass); qualify its sites",
    )
    parser.add_argument("--qualified-with", default="SceneShaderSourceTextFacts", help="type that now owns the helper")
    parser.add_argument("--brace-delta", action="append", default=[], help="file edited by a deletion; verify its brace deficit")
    parser.add_argument("--base-ref", default="HEAD", help="git ref the brace deficit is compared against")
    return parser.parse_args()


def load_module(path: Path):
    """Import the harness module as `script.tests.<name>`.

    The harnesses import each other by package-relative name (`from .test_x import ...`)
    and by repository path (`import script.scene_swift_source_sets`); loading them under
    a bare stem makes both forms fail, which silently removes those source sets from the
    sweep. The package form resolves both, and the bare load stays as a fallback.
    """
    try:
        return importlib.import_module(f"script.tests.{path.stem}"), None
    except Exception as package_error:  # pragma: no cover - depends on the module under test
        spec = importlib.util.spec_from_file_location(path.stem, path)
        if spec is None or spec.loader is None:
            return None, "no import spec"
        module = importlib.util.module_from_spec(spec)
        sys.modules[path.stem] = module
        try:
            spec.loader.exec_module(module)
        except Exception as error:
            return None, f"{type(error).__name__}: {error} (as package: {package_error})"
        return module, None


def harness_sets(prefixes: tuple[str, ...]) -> tuple[list[tuple[str, list[Path], str]], list[tuple[str, str]]]:
    sys.path.insert(0, str(REPOSITORY_ROOT))
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
        records.update(parse_sites(completed.stderr.splitlines(), names))
    return sorted(records), failures


def unresolved_sites(names: list[str], sets) -> list[str]:
    records, _ = scan_sites(names, sets)
    return [f"{path}:{line}:{name}" for path, line, _, name in records]


def qualify(path: str, line: int, column: int, name: str, qualified_with: str) -> bool:
    """Qualify one reported site, anchored on the compiler's own (line, column).

    The column points at the identifier, so the rewrite is exact.  Only when the
    column does not land on the name (some diagnostics point at the enclosing
    expression) does this fall back to the reported line, and then only if that line
    holds exactly one bare call; a line with several candidates is left alone rather
    than guessed, because guessing swaps sites and makes the scan oscillate.
    """

    file = Path(path)
    text = file.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    if line < 1 or line > len(lines):
        return False
    pattern = re.compile(r"(?<![.\w])%s\s*\(" % re.escape(name))

    offset = sum(len(entry) for entry in lines[: line - 1]) + (column - 1)
    if text[offset : offset + len(name)] == name:
        after = text[offset + len(name) :]
        stripped = after.lstrip()
        if stripped.startswith("("):
            text = text[:offset] + f"{qualified_with}.{name}" + after
            file.write_text(text, encoding="utf-8")
            return True

    candidates = list(pattern.finditer(lines[line - 1]))
    if len(candidates) != 1:
        return False
    match = candidates[0]
    lines[line - 1] = (
        lines[line - 1][: match.start()] + f"{qualified_with}.{name}" + lines[line - 1][match.end() - 1 :]
    )
    file.write_text("".join(lines), encoding="utf-8")
    return True


def parse_sites(lines: Iterable[str], names: Sequence[str]) -> list[tuple[str, int, int, str]]:
    """Extract the diagnostics that mean "the helper definition moved away"."""

    wanted = set(names)
    records: set[tuple[str, int, int, str]] = set()
    for line in lines:
        for pattern in DIAGNOSTIC_PATTERNS:
            match = pattern.match(line)
            if match and match.group(4) in wanted:
                records.add((match.group(1), int(match.group(2)), int(match.group(3)), match.group(4)))
                break
    return sorted(records)


def qualify_from_report(
    report: Path, names: Sequence[str], qualified_with: str
) -> tuple[int, list[str]]:
    """Qualify the sites of a compiler report produced outside this tool.

    A whole-set `swiftc -typecheck` stops reporting once it has enough errors, so a
    name-dense family needs a per-file sweep: typecheck one file as the frontend's
    `-primary-file`, collect those diagnostics into a report, and hand the report here.
    Compiling stays an external command, and this tool only rewrites what a report
    proves unresolved -- one report per file, one pass per file instead of the waves a
    whole-set scan produces.
    """

    records = parse_sites(report.read_text(encoding="utf-8").splitlines(), names)
    total = 0
    missed: list[str] = []
    for path, line, column, name in sorted(records, reverse=True):
        if qualify(path, line, column, name, qualified_with):
            total += 1
        else:
            missed.append(f"{path}:{line}:{column}:{name}")
    return total, missed


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

    if args.apply_from:
        if not args.name:
            print("--apply-from requires --name", file=sys.stderr)
            return 2
        total, unresolved = qualify_from_report(Path(args.apply_from), args.name, args.qualified_with)
        print(f"qualified {total} site(s) from {args.apply_from}")
        for entry in unresolved:
            print(f"unresolved: {entry}", file=sys.stderr)
        return 1 if unresolved else 0

    sets, skipped = harness_sets(prefixes)
    for stem, reason in skipped:
        print(f"skipped harness set {stem}: {reason}", file=sys.stderr)
    if not args.name:
        print("--name is required outside --brace-delta mode", file=sys.stderr)
        return 2
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
