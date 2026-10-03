#!/usr/bin/env python3
"""Freeze a bounded source-shape assertion signal; this is not a behavior test.

Only literal first arguments of attribute calls named assertIn/assertNotIn
starting with a Swift declaration/control keyword are detected. Expressions,
computed strings, other assertion methods and semantic behavior are outside v1.
"""

from __future__ import annotations

import argparse
import ast
from collections import Counter
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "script/test_assertion_baseline.json"
BASELINE_RELATIVE = "script/test_assertion_baseline.json"
DETECTOR = {
    "id": "python-unittest-swift-declaration-literal-v1",
    "methods": ["assertIn", "assertNotIn"],
    "keywords": ["func", "let", "var", "struct", "class", "enum", "case", "guard", "if"],
    "scope": "Git tracked and untracked non-ignored script/tests/test_*.py files",
    "boundary": "AST attribute calls with a literal string first argument starting with a listed keyword followed by whitespace; multiline and either quote style included. Computed strings, non-keyword expressions, other assertion methods and behavioral correctness are outside this signal.",
}
PREFIX = re.compile(r"^(?:" + "|".join(DETECTOR["keywords"]) + r")\s")
Identity = tuple[str, str, str, str]


def test_paths(root: Path) -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "script/tests"],
        cwd=root, capture_output=True, check=True,
    )
    paths = {p.decode("utf-8") for p in result.stdout.split(b"\0") if p}
    return sorted(p for p in paths if PurePosixPath(p).name.startswith("test_")
                  and p.endswith(".py") and (root / p).is_file())


def detect_source(text: str, path: str) -> Counter[Identity]:
    findings: Counter[Identity] = Counter()

    class Visitor(ast.NodeVisitor):
        def __init__(self) -> None:
            self.scope: list[str] = []

        def visit_scope(self, node: ast.ClassDef | ast.FunctionDef | ast.AsyncFunctionDef) -> None:
            self.scope.append(node.name)
            self.generic_visit(node)
            self.scope.pop()

        visit_ClassDef = visit_scope
        visit_FunctionDef = visit_scope
        visit_AsyncFunctionDef = visit_scope

        def visit_Call(self, node: ast.Call) -> None:
            if (isinstance(node.func, ast.Attribute)
                    and node.func.attr in DETECTOR["methods"] and node.args
                    and isinstance(node.args[0], ast.Constant)
                    and isinstance(node.args[0].value, str)
                    and PREFIX.match(node.args[0].value)):
                findings[(path, ".".join(self.scope), node.func.attr, node.args[0].value)] += 1
            self.generic_visit(node)

    Visitor().visit(ast.parse(text, filename=path))
    return findings


def inventory(root: Path) -> Counter[Identity]:
    findings: Counter[Identity] = Counter()
    for path in test_paths(root):
        findings.update(detect_source((root / path).read_text(encoding="utf-8"), path))
    return findings


def expression_census(root: Path) -> dict:
    """Inventory every excluded literal membership check without calling it debt.

    The operand and enclosing test make manual provenance review possible.
    String membership in output/JSON is often a valid behavior assertion; this
    deliberately inclusive census is not an automatic source-text verdict.
    """
    entries = []
    for path in test_paths(root):
        class Visitor(ast.NodeVisitor):
            scope = []
            def visit_scope(self, node):
                self.scope.append(node.name); self.generic_visit(node); self.scope.pop()
            visit_ClassDef = visit_scope
            visit_FunctionDef = visit_scope
            visit_AsyncFunctionDef = visit_scope
            def visit_Call(self, node):
                if (isinstance(node.func, ast.Attribute) and node.func.attr in DETECTOR['methods']
                        and len(node.args) >= 2 and isinstance(node.args[0], ast.Constant)
                        and isinstance(node.args[0].value, str) and not PREFIX.match(node.args[0].value)):
                    entries.append({'path': path, 'line': node.lineno, 'scope': '.'.join(self.scope),
                                    'method': node.func.attr, 'literal': node.args[0].value,
                                    'operand': ast.unparse(node.args[1])})
                self.generic_visit(node)
        Visitor().visit(ast.parse((root / path).read_text(), filename=path))
    return {'schemaVersion': 1, 'classification': 'manual-provenance-review',
            'boundary': 'All literal assertIn/assertNotIn outside v1, including legitimate behavior checks. Computed needles and other assertion methods remain outside this census.',
            'count': len(entries), 'entries': entries}


def document(findings: Counter[Identity]) -> dict:
    return {
        "schemaVersion": 1,
        "detector": DETECTOR,
        "entries": [dict(zip(("path", "scope", "method", "literal"), identity), count=count)
                    for identity, count in sorted(findings.items())],
    }


def load_baseline(path: Path) -> Counter[Identity]:
    return parse_baseline(path.read_text(encoding="utf-8"))


def parse_baseline(text: str) -> Counter[Identity]:
    value = json.loads(text)
    if not isinstance(value, dict) or value.get("schemaVersion") != 1 or value.get("detector") != DETECTOR:
        raise ValueError("baseline schema or detector changed; explicit reviewed policy migration required")
    if not isinstance(value.get("entries"), list):
        raise ValueError("baseline entries must be a list")
    counts: Counter[Identity] = Counter()
    for entry in value["entries"]:
        if not isinstance(entry, dict) or set(entry) != {"path", "scope", "method", "literal", "count"}:
            raise ValueError("invalid baseline entry fields")
        identity = tuple(entry[k] for k in ("path", "scope", "method", "literal"))
        if not all(isinstance(v, str) for v in identity):
            raise ValueError("baseline identity values must be strings")
        relative, _, method, literal = identity
        pure = PurePosixPath(relative)
        if (pure.is_absolute() or ".." in pure.parts or pure.as_posix() != relative
                or not relative.startswith("script/tests/") or not pure.name.startswith("test_")
                or pure.suffix != ".py" or method not in DETECTOR["methods"] or not PREFIX.match(literal)):
            raise ValueError("invalid baseline assertion identity")
        count = entry["count"]
        if type(count) is not int or count < 1 or identity in counts:
            raise ValueError("baseline counts must be positive and identities unique")
        counts[identity] = count
    return counts


def baseline_at_ref(root: Path, base_ref: str) -> Counter[Identity] | None:
    resolved = subprocess.run(
        ["git", "rev-parse", "--verify", "--end-of-options", f"{base_ref}^{{commit}}"],
        cwd=root, capture_output=True, text=True, check=True,
    ).stdout.strip()
    listing = subprocess.run(
        ["git", "ls-tree", "-z", resolved, "--", BASELINE_RELATIVE],
        cwd=root, capture_output=True, check=True,
    )
    if not listing.stdout:
        return None
    previous = subprocess.run(
        ["git", "show", f"{resolved}:{BASELINE_RELATIVE}"],
        cwd=root, capture_output=True, text=True, check=True,
    )
    return parse_baseline(previous.stdout)


def compare(current: Counter[Identity], baseline: Counter[Identity]) -> tuple[list[str], list[str]]:
    growth, reductions = [], []
    for identity in sorted(current.keys() | baseline.keys()):
        now, old = current[identity], baseline[identity]
        description = f"{identity[0]}:{identity[1]} {identity[2]}({identity[3]!r}) {old} -> {now}"
        if now > old:
            growth.append(description)
        elif now < old:
            reductions.append(description)
    return growth, reductions


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="check current assertion identities (default)")
    mode.add_argument("--ratchet-baseline", action="store_true", help="record only verified removals or count reductions")
    mode.add_argument("--census-expressions", action="store_true", help="JSON inventory of excluded literal membership assertions for provenance review")
    parser.add_argument("--base-ref", default="HEAD", help="committed baseline to check against (default: HEAD)")
    args = parser.parse_args(argv)
    try:
        if args.census_expressions:
            print(json.dumps(expression_census(ROOT), ensure_ascii=False, indent=2))
            return 0
        baseline = load_baseline(BASELINE)
        previous = baseline_at_ref(ROOT, args.base_ref)
        if previous is None:
            print(f"BOOTSTRAP: {args.base_ref} has no {BASELINE_RELATIVE}; "
                  "this first baseline requires review of its detector and inventory.")
        else:
            baseline_growth, _ = compare(baseline, previous)
            if baseline_growth:
                for finding in baseline_growth:
                    print(f"ERROR baseline expansion against {args.base_ref}: {finding}", file=sys.stderr)
                return 1
        current = inventory(ROOT)
        growth, reductions = compare(current, baseline)
        if growth:
            for finding in growth:
                print(f"ERROR new source-shape assertion: {finding}", file=sys.stderr)
            return 1
        if args.ratchet_baseline:
            if reductions:
                BASELINE.write_text(json.dumps(document(current), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            print(f"Assertion baseline ratchet: {sum(baseline.values())} -> {sum(current.values())}")
        elif reductions:
            for finding in reductions:
                print(f"ERROR shrink requires --ratchet-baseline: {finding}", file=sys.stderr)
            return 1
        print(f"Test assertion signal passed: {sum(current.values())} occurrences in "
              f"{len({identity[0] for identity in current})} files; detector {DETECTOR['id']}. "
              "This bounded signal does not establish behavioral test quality.")
        return 0
    except (OSError, ValueError, SyntaxError, subprocess.CalledProcessError) as error:
        print(f"ERROR test assertion inventory: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
