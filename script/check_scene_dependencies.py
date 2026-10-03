#!/usr/bin/env python3
"""Ratchet the Rendering -> Compilation internal-type lexical dependency edge.

This is a token/declaration inventory, not Swift name resolution. Test harness
consumption is reported separately and does not make an internal type public.
"""
from __future__ import annotations

import argparse
import ast
import json
import re
import subprocess
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "script/scene_dependency_baseline.json"
# Swift's documented identifier-head ranges (including non-BMP names), not
# Python's narrower \w alphabet. See the boundary document's lexical source.
IDENTIFIER_HEAD = (
    r"A-Za-z_\u00a8\u00aa\u00ad\u00af\u00b2-\u00b5\u00b7-\u00ba"
    r"\u00bc-\u00be\u00c0-\u00d6\u00d8-\u00f6\u00f8-\u02ff"
    r"\u0370-\u167f\u1681-\u180d\u180f-\u1dbf\u1e00-\u1fff"
    r"\u200b-\u200d\u202a-\u202e\u203f-\u2040\u2054\u2060-\u206f"
    r"\u2070-\u20cf\u2100-\u218f\u2460-\u24ff\u2776-\u2793"
    r"\u2c00-\u2dff\u2e80-\u2fff\u3004-\u3007\u3021-\u302f\u3031-\ud7ff"
    r"\uf900-\ufd3d\ufd40-\ufdcf\ufdf0-\ufe1f\ufe30-\ufe44\ufe47-\ufffd"
    + "".join(f"\\U{plane << 16:08x}-\\U{((plane + 1) << 16) - 3:08x}"
              for plane in range(1, 15))
)
IDENTIFIER = rf"[{IDENTIFIER_HEAD}][{IDENTIFIER_HEAD}0-9\u0300-\u036f\u1dc0-\u1dff\u20d0-\u20ff\ufe20-\ufe2f]*"
RAW_IDENTIFIER = r"`[^`\\\x00\t\n\v\r\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+`"
NAME = rf"(?:{RAW_IDENTIFIER}|{IDENTIFIER})"
TOKEN = re.compile(rf"{NAME}|[{{}}]")
DECLARATIONS = {"struct", "enum", "class", "actor", "protocol", "typealias"}
SWIFT_FRAGMENT = re.compile(rf"\bimport\s+(?:Foundation|Metal|simd|AppKit)\b|\b(?:struct|enum|func|let|var)\s+{NAME}\s*[:=({{<]")


def mask_swift(text: str) -> str:
    """Preserve offsets while removing nested comments and quoted literals.

    Literal interpolation is intentionally masked too; regex literals, macros,
    and conditional compilation are outside this pilot's lexical contract.
    """
    chars = list(text)
    i = 0
    while i < len(text):
        start = i
        if text[i] == "`":
            identifier = re.match(RAW_IDENTIFIER, text[i:])
            if identifier is None:
                raise ValueError("unsupported or unterminated Swift raw identifier")
            i += len(identifier.group())
            continue
        if text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
        elif text.startswith("/*", i):
            i += 2
            depth = 1
            while i < len(text) and depth:
                if text.startswith("/*", i):
                    depth += 1
                    i += 2
                elif text.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
        else:
            opening = re.match(r'(#+)?("""|")', text[i:]) if text[i] in '#"' else None
            if not opening:
                i += 1
                continue
            hashes, quotes = opening.group(1) or "", opening.group(2)
            i += len(opening.group())
            close = quotes + hashes
            while i < len(text):
                if text.startswith("\\" + hashes, i):
                    i += len(hashes) + 2
                elif text.startswith(close, i):
                    i += len(close)
                    break
                else:
                    i += 1
        for j in range(start, min(i, len(chars))):
            if chars[j] != "\n":
                chars[j] = " "
    return "".join(chars)


def declared_types(text: str) -> set[str]:
    depth = 0
    previous = ""
    result: set[str] = set()
    for match in TOKEN.finditer(mask_swift(text)):
        token = match.group()
        if depth == 0 and previous in DECLARATIONS:
            if not re.fullmatch(NAME, token):
                raise ValueError(f"unsupported Swift type declaration after {previous}")
            result.add(token.strip('`'))
        if token == "{":
            depth += 1
        elif token == "}":
            depth -= 1
        previous = token
    if depth == 0 and previous in DECLARATIONS:
        raise ValueError(f"unsupported Swift type declaration after {previous}")
    return result


def harness_fragments(text: str, path: str) -> list[tuple[int, str]]:
    tree = ast.parse(text, filename=path)
    fragments: list[tuple[int, str]] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            if SWIFT_FRAGMENT.search(node.value):
                fragments.append((node.lineno, node.value))
    return fragments


def edge_key(edge: dict[str, Any]) -> tuple[str, str, str]:
    return edge["rule"], edge["consumer"], edge["symbol"]


def scan(sources: dict[str, str], config: dict[str, Any]) -> dict[str, Any]:
    source_root = config["source_root"].rstrip("/") + "/"
    target_root = source_root + config["rule"]["target"] + "/"
    consumer_root = source_root + config["rule"]["consumer"] + "/"
    symbols: dict[str, str] = {}
    for path, text in sorted(sources.items()):
        if path.startswith(target_root) and path.endswith(".swift"):
            for symbol in declared_types(text):
                if symbol in symbols:
                    raise ValueError(f"ambiguous top-level declaration {symbol}: {symbols[symbol]}, {path}")
                symbols[symbol] = path
    missing = set(config["public_contracts"]) - symbols.keys()
    if missing:
        raise ValueError(f"public contracts lack declarations: {', '.join(sorted(missing))}")
    edges, harness = [], []
    product_files = harness_files = fragments_count = 0
    for path, text in sorted(sources.items()):
        is_product = path.startswith(source_root) and path.endswith(".swift")
        is_harness = path.startswith(config["test_root"].rstrip("/") + "/")
        if is_product:
            product_files += 1
            if path.startswith(target_root):
                continue
            fragments = [(1, text)]
        elif is_harness and path.endswith((".swift", ".py")):
            fragments = [(1, text)] if path.endswith(".swift") else harness_fragments(text, path)
            if not fragments:
                continue
            harness_files += 1
            fragments_count += len(fragments)
        else:
            continue
        found: dict[str, int] = {}
        for line, fragment in fragments:
            for match in TOKEN.finditer(mask_swift(fragment)):
                symbol = match.group().strip('`')
                if symbol in symbols:
                    # Embedded lines point to the Python string origin, not a
                    # fabricated exact Swift line after escapes/dedenting.
                    location = line if path.endswith(".py") else line + fragment.count("\n", 0, match.start())
                    found.setdefault(symbol, location)
        for symbol, line in sorted(found.items()):
            public = symbol in config["public_contracts"]
            edge = {"consumer": path, "symbol": symbol, "declaration": symbols[symbol],
                    "line": line, "public_contract": public}
            if is_product:
                edge["forbidden"] = path.startswith(consumer_root) and not public
                edges.append(edge)
            else:
                harness.append(edge)
    violations = [{"rule": config["rule"]["id"], **edge} for edge in edges if edge["forbidden"]]
    return {"declarations": len(symbols), "product_files": product_files,
            "harness_files": harness_files, "harness_fragments": fragments_count,
            "edges": edges, "harness_consumers": harness, "violations": violations}


def validate_config(config: dict[str, Any]) -> None:
    if config.get("schema_version") != 1:
        raise ValueError("unsupported dependency baseline schema")
    for field in ("source_root", "test_root"):
        value = config.get(field)
        if not isinstance(value, str) or not value or Path(value).is_absolute() or ".." in Path(value).parts:
            raise ValueError(f"invalid {field}")
    rule = config["rule"]
    for field in ("id", "consumer", "target", "owner", "retirement"):
        if not isinstance(rule.get(field), str) or not rule[field].strip():
            raise ValueError(f"rule lacks {field}")
    for symbol, reason in config["public_contracts"].items():
        if not re.fullmatch(RAW_IDENTIFIER, '`' + symbol + '`') or not isinstance(reason, str) or not reason.strip():
            raise ValueError(f"invalid public contract {symbol}")
    keys = []
    for item in config["todo"]:
        keys.append(edge_key(item))
        for field in ("owner", "reason", "retirement"):
            if not isinstance(item.get(field), str) or not item[field].strip():
                raise ValueError(f"todo {edge_key(item)} lacks {field}")
        if item["rule"] != rule["id"]:
            raise ValueError("todo names unknown rule")
    if len(keys) != len(set(keys)):
        raise ValueError("duplicate todo edge")


def compare(config: dict[str, Any], report: dict[str, Any], previous: dict[str, Any] | None = None) -> dict[str, Any]:
    actual = {edge_key(x) for x in report["violations"]}
    allowed = {edge_key(x) for x in config["todo"]}
    errors = []
    if previous is not None:
        if any(config[k] != previous[k] for k in ("source_root", "test_root", "rule")):
            errors.append("dependency scope/rule changed relative to base ref")
        if set(config["public_contracts"]) - set(previous["public_contracts"]):
            errors.append("public contract allowance expanded relative to base ref")
        if allowed - {edge_key(x) for x in previous["todo"]}:
            errors.append("todo baseline expanded relative to base ref")
    return {"new": sorted(actual - allowed), "stale": sorted(allowed - actual), "errors": errors}


def ratchet(config: dict[str, Any], report: dict[str, Any], reason: str) -> dict[str, Any]:
    if not reason.strip():
        raise ValueError("--ratchet-baseline requires --reason")
    comparison = compare(config, report)
    if comparison["new"]:
        raise ValueError("ratchet refuses new dependency edges")
    actual = {edge_key(x) for x in report["violations"]}
    result = {**config, "todo": [x for x in config["todo"] if edge_key(x) in actual]}
    if comparison["stale"]:
        result["last_ratchet"] = {"reason": reason, "removed": comparison["stale"]}
    return result


def git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True, check=False)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--audit", action="store_true")
    mode.add_argument("--ratchet-baseline", action="store_true")
    parser.add_argument("--reason", default="")
    parser.add_argument("--base-ref")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args()
    try:
        config = json.loads((ROOT / BASELINE).read_text())
        validate_config(config)
        listing = git("ls-files", "-z", "--cached", "--others", "--exclude-standard")
        if listing.returncode:
            raise ValueError(listing.stderr.strip())
        sources = {}
        for path in sorted(set(listing.stdout.split("\0"))):
            if (path.startswith(config["source_root"] + "/") and path.endswith(".swift")) or (
                path.startswith(config["test_root"] + "/") and path.endswith((".swift", ".py"))
            ):
                absolute = ROOT / path
                if absolute.is_file():
                    sources[path] = absolute.read_text(encoding="utf-8")
        report = scan(sources, config)
        previous = None
        bootstrap = False
        if args.base_ref:
            ref = git("rev-parse", "--verify", args.base_ref + "^{commit}")
            if ref.returncode:
                raise ValueError(f"invalid --base-ref: {args.base_ref}")
            old = git("show", f"{ref.stdout.strip()}:{BASELINE}")
            if old.returncode:
                # A missing baseline is bootstrap; all other Git failures fail.
                exists = git("ls-tree", "--name-only", ref.stdout.strip(), "--", BASELINE)
                if exists.returncode or exists.stdout.strip():
                    raise ValueError(old.stderr.strip())
                bootstrap = True
            else:
                previous = json.loads(old.stdout)
                validate_config(previous)
        comparison = compare(config, report, previous)
        if args.ratchet_baseline:
            if comparison["errors"]:
                raise ValueError("; ".join(comparison["errors"]))
            config = ratchet(config, report, args.reason)
            (ROOT / BASELINE).write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
            comparison = compare(config, report, previous)
        ok = not any(comparison.values())
        payload = {"status": "PASS" if ok else "FAIL", "baseline_bootstrap": bootstrap,
                   **report, **comparison}
        if args.format == "json":
            print(json.dumps(payload, indent=2, ensure_ascii=False))
        else:
            print(f"scene-dependencies: {payload['status']}; {len(report['violations'])} todo edges; "
                  f"{len(report['edges'])} product references; {len(report['harness_consumers'])} harness references")
            if bootstrap:
                print("base ref has no dependency baseline: bootstrap, no historical ratchet comparison")
            for kind in ("new", "stale", "errors"):
                for item in comparison[kind]:
                    print(f"{kind}: {item}")
            if args.audit:
                for item in report["violations"]:
                    print(f"{item['consumer']}:{item['line']} -> {item['symbol']}")
        return 0 if args.audit or ok else 1
    except (ValueError, KeyError, TypeError, OSError, SyntaxError) as error:
        print(f"scene-dependencies: ERROR: {error}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
