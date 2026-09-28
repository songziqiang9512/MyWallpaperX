#!/usr/bin/env python3
"""Audit and ratchet the Scene defensive surface.

The Scene contract requires defense that the runtime contract demands
(authored-input validation, GPU/lifecycle hard rejects, visual fail-soft) and
forbids defensive surface that has no consumer: zero-caller entries, per-file
copies of a canonical helper, and errors swallowed inside identity or digest
computation.  This gate locks the measured inventory in
`script/scene_defense_baseline.json`; every family may only shrink.

Detector boundaries (documented on purpose, see the baseline `notes` too):
- A declaration counts as a zero-caller entry only when its name appears at
  most once in the whole tracked tree, so common names (`matches`, `capture`,
  `identifier`, ...) are effectively immune; the duplicate-helper lock covers
  them instead.
- The declaration scan sees `func|struct|enum|class|actor|protocol`
  declarations in the Scene source root only.
- An annotation (`// inventory-entry: <reason>`) exempts a declaration when it
  is a trailing comment on the declaration line or a standalone comment line
  directly above it.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Iterable, Sequence


REPO_ROOT = Path(__file__).resolve().parents[1]
BASELINE_RELATIVE_PATH = Path("script/scene_defense_baseline.json")
LAYOUT_RELATIVE_PATH = Path("script/scene_source_layout.json")

TEXT_EXTENSIONS = (
    ".swift",
    ".py",
    ".json",
    ".md",
    ".metal",
    ".pbxproj",
    ".xcconfig",
    ".sh",
    ".yml",
    ".yaml",
    ".h",
    ".hpp",
    ".c",
    ".cpp",
    ".mm",
    ".plist",
    ".xib",
    ".storyboard",
    ".strings",
    ".txt",
)
MAX_FILE_BYTES = 2_000_000
INVENTORY_REASON = "inventory-entry"
HELPER_META_FIELDS = ("canonical", "note", "owner", "retirement")
PATTERN_META_FIELDS = ("note", "owner", "retirement")

# A file-local helper with no caller is intentionally out of scope: the
# duplicate and canonical rules already cover private copies, and flagging
# them here would drown the inventory in private noise.
DECLARATION_PATTERN = re.compile(
    r"^[ \t]*(?P<prefix>(?:[A-Za-z_@][^\n]*?)?)"
    r"\b(?P<kind>func|struct|enum|class|actor|protocol)[ \t]+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
)
HIDDEN_ACCESS = re.compile(r"\b(?:private|fileprivate)\b")
TOKEN_PATTERN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
INVENTORY_COMMENT = re.compile(rf"//\s*{INVENTORY_REASON}\s*:\s*(?P<reason>.+)")
# Our own bookkeeping names every deleted symbol; if it counted as a reference the
# locked-dead-entry state could never hold (lock, then "lock" becomes a reference).
_SELF_RELATIVE = Path(__file__).resolve().relative_to(REPO_ROOT).as_posix()
EXCLUDED_REFERENCE_FILES = {
    BASELINE_RELATIVE_PATH.as_posix(),
    _SELF_RELATIVE,
    (Path(_SELF_RELATIVE).parent / "tests" / f"test_{Path(_SELF_RELATIVE).name}").as_posix(),
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="validate the tree against the baseline (default)")
    mode.add_argument("--audit", action="store_true", help="print current measurements without comparing")
    mode.add_argument(
        "--ratchet-baseline",
        action="store_true",
        help="lock the current measurements in; growth and set changes need explicit flags",
    )
    parser.add_argument(
        "--accept-growth",
        action="store_true",
        help=(
            "allow --ratchet-baseline to widen an allowance; each accepted change is recorded "
            "as an acknowledgedChanges entry carrying --reason (a family dropping to zero only "
            "needs --reason)"
        ),
    )
    parser.add_argument("--reason", default="", help="recorded reason for --accept-growth")
    parser.add_argument(
        "--base-ref",
        help="Git ref whose baseline must not be expanded (recommended in CI)",
    )
    parser.add_argument("--format", choices=("text", "github", "json"), default="text")
    return parser.parse_args()


def run_git(arguments: Sequence[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["git", *arguments],
        cwd=REPO_ROOT,
        capture_output=True,
        check=False,
    )


def tracked_paths() -> list[str]:
    completed = run_git(["ls-files", "-z", "--cached", "--others", "--exclude-standard"])
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", "replace").strip()
        raise ValueError(f"git ls-files failed with exit code {completed.returncode}: {detail}")
    return sorted(raw.decode("utf-8") for raw in completed.stdout.split(b"\0") if raw)


def is_text_path(path: str) -> bool:
    return path.endswith(TEXT_EXTENSIONS)


def read_text(path: str) -> str | None:
    absolute = REPO_ROOT / path
    try:
        if not absolute.is_file() or absolute.stat().st_size > MAX_FILE_BYTES:
            return None
        return absolute.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def scene_source_root() -> str:
    try:
        payload = json.loads((REPO_ROOT / LAYOUT_RELATIVE_PATH).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read {LAYOUT_RELATIVE_PATH}: {error}") from error
    root = payload.get("source_root")
    if not isinstance(root, str) or not root:
        raise ValueError(f"{LAYOUT_RELATIVE_PATH} must declare a source_root")
    return root


def scene_sources(paths: Sequence[str], source_root: str) -> dict[str, str]:
    prefix = source_root.rstrip("/") + "/"
    sources: dict[str, str] = {}
    for path in paths:
        if not path.startswith(prefix) or not path.endswith(".swift"):
            continue
        text = read_text(path)
        if text is not None:
            sources[path] = text
    return sources


def inventory_reason(lines: Sequence[str], index: int) -> str | None:
    trailing = INVENTORY_COMMENT.search(lines[index])
    if trailing is not None:
        return trailing.group("reason").strip()
    if index == 0:
        return None
    previous = lines[index - 1].strip()
    if not previous.startswith("//"):
        return None
    above = INVENTORY_COMMENT.search(previous)
    return above.group("reason").strip() if above is not None else None


def collect_declarations(
    sources: dict[str, str],
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    """Return (dead candidates, annotated inventory entries) for the Scene root."""

    inventory: list[dict[str, str]] = []
    candidates: list[dict[str, str]] = []
    for path, text in sources.items():
        lines = text.splitlines()
        for index, line in enumerate(lines):
            match = DECLARATION_PATTERN.match(line)
            if match is None:
                continue
            if HIDDEN_ACCESS.search(match.group("prefix")):
                continue
            name = match.group("name")
            if name.startswith("_"):
                continue
            entry = {"name": name, "file": path, "kind": match.group("kind")}
            reason = inventory_reason(lines, index)
            if reason:
                inventory.append({**entry, "reason": reason})
            else:
                candidates.append(entry)
    return candidates, inventory


def reference_counts(names: Iterable[str], paths: Sequence[str]) -> Counter[str]:
    wanted = set(names)
    counts: Counter[str] = Counter()
    if not wanted:
        return counts
    for path in paths:
        if not is_text_path(path) or path in EXCLUDED_REFERENCE_FILES:
            continue
        text = read_text(path)
        if text is None:
            continue
        for token in TOKEN_PATTERN.findall(text):
            if token in wanted:
                counts[token] += 1
    return counts


def count_dead_entries(
    sources: dict[str, str], paths: Sequence[str]
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    candidates, inventory = collect_declarations(sources)
    annotated = {entry["name"] for entry in inventory}
    candidates = [entry for entry in candidates if entry["name"] not in annotated]
    counts = reference_counts((entry["name"] for entry in candidates), paths)
    dead = [entry for entry in candidates if counts.get(entry["name"], 0) <= 1]
    dead.sort(key=lambda entry: (entry["file"], entry["name"]))
    inventory.sort(key=lambda entry: (entry["file"], entry["name"]))
    return dead, inventory


def count_canonical_helpers(
    helpers: Sequence[dict[str, Any]], sources: dict[str, str]
) -> dict[str, int]:
    counts: dict[str, int] = {}
    for helper in helpers:
        name = str(helper["name"])
        pattern = re.compile(rf"\bfunc[ \t]+{re.escape(name)}[ \t]*[(<]")
        counts[name] = sum(len(pattern.findall(text)) for text in sources.values())
    return counts


def count_swallow_patterns(
    patterns: Sequence[dict[str, Any]], sources: dict[str, str]
) -> dict[str, int]:
    counts: dict[str, int] = {}
    for entry in patterns:
        pattern = re.compile(str(entry["pattern"]))
        counts[str(entry["id"])] = sum(
            len(pattern.findall(text)) for text in sources.values()
        )
    return counts


def measure(paths: Sequence[str], baseline: dict[str, Any]) -> dict[str, Any]:
    source_root = str(baseline["sourceRoot"])
    sources = scene_sources(paths, source_root)
    dead, inventory = count_dead_entries(sources, paths)
    return {
        "deadEntries": dead,
        "inventoryEntries": inventory,
        "canonicalHelpers": count_canonical_helpers(baseline["canonicalHelpers"], sources),
        "swallowPatterns": count_swallow_patterns(baseline["swallowPatterns"], sources),
    }


def validate_repo_path(value: Any, source: str) -> None:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{source} contains an invalid repository path: {value!r}")
    if value.startswith(("/", ".")) or ".." in Path(value).parts:
        raise ValueError(f"{source} path must be repository-relative: {value!r}")


def validate_meta(entry: dict[str, Any], fields: Sequence[str], source: str, label: str) -> None:
    for field in fields:
        value = entry.get(field)
        if value is None:
            continue
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{source} {label} field {field} must be a non-empty string")


def load_baseline(text: str, source: str) -> dict[str, Any]:
    try:
        baseline = json.loads(text)
    except json.JSONDecodeError as error:
        raise ValueError(f"{source} is not valid JSON: {error}") from error
    if baseline.get("schemaVersion") != 1:
        raise ValueError(f"{source} must use schemaVersion 1")
    validate_repo_path(baseline.get("sourceRoot"), source)
    for key in ("deadEntries", "inventoryEntries"):
        entries = baseline.get(key)
        if not isinstance(entries, list):
            raise ValueError(f"{source} {key} must be a list")
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("name"), str):
                raise ValueError(f"{source} {key} entries need a name")
            validate_repo_path(entry.get("file"), source)
            if key == "inventoryEntries" and not str(entry.get("reason", "")).strip():
                raise ValueError(f"{source} inventory entries need a reason")
    for key in ("canonicalHelpers", "swallowPatterns"):
        entries = baseline.get(key)
        if not isinstance(entries, list) or not entries:
            raise ValueError(f"{source} {key} must be a non-empty list")
        for entry in entries:
            if key == "canonicalHelpers":
                if not isinstance(entry.get("name"), str) or not entry["name"]:
                    raise ValueError(f"{source} canonical helper needs a name")
                if not isinstance(entry.get("allowedCopies"), int):
                    raise ValueError(f"{source} canonical helper {entry['name']} needs allowedCopies")
                if entry.get("canonical") is not None:
                    validate_repo_path(entry["canonical"], source)
                validate_meta(entry, HELPER_META_FIELDS, source, f"canonical helper {entry['name']}")
                for required in ("owner", "retirement"):
                    if not str(entry.get(required, "")).strip():
                        raise ValueError(
                            f"{source} canonical helper {entry['name']} needs "
                            f"{'an owner' if required == 'owner' else 'a retirement condition'}"
                        )
            else:
                if not isinstance(entry.get("id"), str) or not entry["id"]:
                    raise ValueError(f"{source} swallow pattern needs an id")
                if not isinstance(entry.get("pattern"), str) or not entry["pattern"]:
                    raise ValueError(f"{source} swallow pattern {entry.get('id')} needs a pattern")
                try:
                    re.compile(entry["pattern"])
                except re.error as error:
                    raise ValueError(f"{source} swallow pattern {entry['id']} is invalid: {error}") from error
                if not isinstance(entry.get("allowedOccurrences"), int):
                    raise ValueError(f"{source} swallow pattern {entry['id']} needs allowedOccurrences")
                validate_meta(entry, PATTERN_META_FIELDS, source, f"swallow pattern {entry['id']}")
                for required in ("owner", "retirement"):
                    if not str(entry.get(required, "")).strip():
                        raise ValueError(
                            f"{source} swallow pattern {entry['id']} needs "
                            f"{'an owner' if required == 'owner' else 'a retirement condition'}"
                        )
    acknowledged = baseline.get("acknowledgedChanges", [])
    if not isinstance(acknowledged, list):
        raise ValueError(f"{source} acknowledgedChanges must be a list")
    details: set[str] = set()
    for entry in acknowledged:
        if not isinstance(entry, dict):
            raise ValueError(f"{source} acknowledgedChanges entries must be objects")
        for field in ("detail", "reason"):
            if not isinstance(entry.get(field), str) or not entry[field].strip():
                raise ValueError(
                    f"{source} acknowledgedChanges entries need a non-empty {field}"
                )
        if entry["detail"] in details:
            raise ValueError(f"{source} acknowledgedChanges repeats detail {entry['detail']!r}")
        details.add(entry["detail"])
    return baseline


def load_current_baseline() -> dict[str, Any]:
    try:
        text = (REPO_ROOT / BASELINE_RELATIVE_PATH).read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError(f"cannot read {BASELINE_RELATIVE_PATH}: {error}") from error
    return load_baseline(text, str(BASELINE_RELATIVE_PATH))


def baseline_at_ref(ref: str) -> dict[str, Any] | None:
    verified = run_git(["rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"])
    if verified.returncode != 0:
        raise ValueError(f"--base-ref is not a commit: {ref}")
    completed = run_git(["show", f"{ref}:{BASELINE_RELATIVE_PATH.as_posix()}"])
    if completed.returncode != 0:
        return None
    return load_baseline(completed.stdout.decode("utf-8"), f"{ref}:{BASELINE_RELATIVE_PATH}")


def key(entry: dict[str, str]) -> tuple[str, str]:
    return (entry["name"], entry["file"])


def check_growth(base: dict[str, Any], current: dict[str, Any]) -> tuple[list[str], list[str]]:
    """Return (growth errors, reviewed-set changes) of `current` relative to `base`.

    Every message is stable and specific so it can be acknowledged one by one via
    `acknowledgedChanges`; a single stale acknowledgement never waives a later,
    different change.
    """

    growth: list[str] = []
    changes: list[str] = []
    if base.get("sourceRoot") != current.get("sourceRoot"):
        changes.append(
            f"source root changed from {base.get('sourceRoot')!r} to {current.get('sourceRoot')!r}"
        )

    base_helpers = {entry["name"]: entry for entry in base["canonicalHelpers"]}
    current_helpers = {entry["name"]: entry for entry in current["canonicalHelpers"]}
    for name in sorted(set(current_helpers) - set(base_helpers)):
        changes.append(f"canonical helper {name} was added to the reviewed set")
    for name in sorted(set(base_helpers) - set(current_helpers)):
        changes.append(f"canonical helper {name} was removed from the reviewed set")
    for name, entry in current_helpers.items():
        if name not in base_helpers:
            continue
        baseline_entry = base_helpers[name]
        if entry["allowedCopies"] > baseline_entry["allowedCopies"]:
            growth.append(
                f"canonical helper {name} allowance grew from "
                f"{baseline_entry['allowedCopies']} to {entry['allowedCopies']}"
            )
        if entry.get("canonical") != baseline_entry.get("canonical"):
            changes.append(
                f"canonical helper {name} target changed from "
                f"{baseline_entry.get('canonical')!r} to {entry.get('canonical')!r}"
            )

    base_swallows = {entry["id"]: entry for entry in base["swallowPatterns"]}
    current_swallows = {entry["id"]: entry for entry in current["swallowPatterns"]}
    for pattern_id in sorted(set(current_swallows) - set(base_swallows)):
        changes.append(f"swallow pattern {pattern_id} was added to the reviewed set")
    for pattern_id in sorted(set(base_swallows) - set(current_swallows)):
        changes.append(f"swallow pattern {pattern_id} was removed from the reviewed set")
    for pattern_id, entry in current_swallows.items():
        if pattern_id not in base_swallows:
            continue
        baseline_entry = base_swallows[pattern_id]
        if entry["allowedOccurrences"] > baseline_entry["allowedOccurrences"]:
            growth.append(
                f"swallow pattern {pattern_id} allowance grew from "
                f"{baseline_entry['allowedOccurrences']} to {entry['allowedOccurrences']}"
            )
        if entry["pattern"] != baseline_entry["pattern"]:
            changes.append(
                f"swallow pattern {pattern_id} pattern text changed from "
                f"{baseline_entry['pattern']!r} to {entry['pattern']!r}"
            )

    base_dead = {key(entry) for entry in base["deadEntries"]}
    current_dead = {key(entry) for entry in current["deadEntries"]}
    for name, file in sorted(current_dead - base_dead):
        growth.append(f"dead inventory grew with {name} in {file}")
    base_inventory = {key(entry) for entry in base["inventoryEntries"]}
    current_inventory = {key(entry) for entry in current["inventoryEntries"]}
    for name, file in sorted(current_inventory - base_inventory):
        growth.append(f"inventory waiver grew with {name} in {file}")
    return growth, changes


def evaluate(baseline: dict[str, Any], measurements: dict[str, Any]) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []

    baseline_dead = {key(entry) for entry in baseline["deadEntries"]}
    current_dead = {key(entry) for entry in measurements["deadEntries"]}
    for name, file in sorted(current_dead - baseline_dead):
        errors.append(
            f"{file}: {name} has no reference anywhere in the repository; delete it or annotate "
            f"its declaration with `// {INVENTORY_REASON}: <reason>`"
        )
    for name, file in sorted(baseline_dead - current_dead):
        errors.append(
            f"{file}: locked dead entry {name} is gone; lock in the improvement with --ratchet-baseline"
        )
    for name, file in sorted(current_dead & baseline_dead):
        warnings.append(f"{file}: {name} is a locked dead entry awaiting deletion")

    baseline_inventory = {key(entry) for entry in baseline["inventoryEntries"]}
    current_inventory = {key(entry) for entry in measurements["inventoryEntries"]}
    for name, file in sorted(baseline_inventory - current_inventory):
        errors.append(
            f"{file}: inventory entry {name} no longer matches a declaration; refresh the baseline"
        )
    for name, file in sorted(current_inventory - baseline_inventory):
        errors.append(
            f"{file}: inventory waiver {name} is not in the baseline; lock it in with --ratchet-baseline"
        )

    for helper in baseline["canonicalHelpers"]:
        name = helper["name"]
        allowed = int(helper["allowedCopies"])
        count = int(measurements["canonicalHelpers"].get(name, 0))
        if count > allowed:
            target = helper.get("canonical") or "the reviewed family home recorded in this baseline"
            errors.append(
                f"canonical helper {name} now has {count} definitions (allowed {allowed}); "
                f"reuse {target} instead of adding another copy"
            )
        elif count < allowed:
            errors.append(
                f"canonical helper {name} shrank from {allowed} to {count} definitions; "
                "lock in the improvement with --ratchet-baseline"
            )

    for entry in baseline["swallowPatterns"]:
        pattern_id = entry["id"]
        allowed = int(entry["allowedOccurrences"])
        count = int(measurements["swallowPatterns"].get(pattern_id, 0))
        if count > allowed:
            errors.append(
                f"swallow pattern {pattern_id} matched {count} times (allowed {allowed}); "
                "make the failure explicit instead of discarding it"
            )
        elif count < allowed:
            errors.append(
                f"swallow pattern {pattern_id} shrank from {allowed} to {count} occurrences; "
                "lock in the improvement with --ratchet-baseline"
            )
    return errors, warnings


def retired_families(
    baseline: dict[str, Any], measurements: dict[str, Any]
) -> list[tuple[str, str, int]]:
    retired: list[tuple[str, str, int]] = []
    for entry in baseline["canonicalHelpers"]:
        before = int(entry["allowedCopies"])
        if before > 0 and int(measurements["canonicalHelpers"].get(entry["name"], 0)) == 0:
            retired.append(("canonical helper", entry["name"], before))
    for entry in baseline["swallowPatterns"]:
        before = int(entry["allowedOccurrences"])
        if before > 0 and int(measurements["swallowPatterns"].get(entry["id"], 0)) == 0:
            retired.append(("swallow pattern", entry["id"], before))
    return retired


def dedupe_acknowledgements(
    existing: Sequence[dict[str, str]], added: Sequence[dict[str, str]]
) -> list[dict[str, str]]:
    merged = {entry["detail"]: entry for entry in existing}
    for entry in added:
        merged[entry["detail"]] = entry
    return [merged[detail] for detail in sorted(merged)]


def ratcheted_baseline(baseline: dict[str, Any], measurements: dict[str, Any]) -> dict[str, Any]:
    current = {
        name: value
        for name, value in baseline.items()
        if name not in {
            "canonicalHelpers",
            "swallowPatterns",
            "deadEntries",
            "inventoryEntries",
        }
    }
    current["canonicalHelpers"] = [
        {**entry, "allowedCopies": int(measurements["canonicalHelpers"].get(entry["name"], 0))}
        for entry in baseline["canonicalHelpers"]
    ]
    current["swallowPatterns"] = [
        {**entry, "allowedOccurrences": int(measurements["swallowPatterns"].get(entry["id"], 0))}
        for entry in baseline["swallowPatterns"]
    ]
    current["deadEntries"] = measurements["deadEntries"]
    current["inventoryEntries"] = measurements["inventoryEntries"]
    return current


def ratchet(baseline: dict[str, Any], measurements: dict[str, Any], args: argparse.Namespace) -> int:
    if args.base_ref:
        print("--ratchet-baseline must not be combined with --base-ref", file=sys.stderr)
        return 2
    current = ratcheted_baseline(baseline, measurements)
    growth, changes = check_growth(baseline, current)
    retirements = [
        f"retired {kind} {name}: allowance {before} -> 0"
        for kind, name, before in retired_families(baseline, measurements)
    ]
    reason = args.reason.strip()
    # A ratchet copies the reviewed entry set, patterns and targets from the
    # baseline, so `changes` can only be non-empty when the baseline itself was
    # edited by hand; those edits are recorded through `acknowledgedChanges`
    # and the `--base-ref` guard, not through this path.
    if growth and not args.accept_growth:
        for message in growth:
            print(f"growth requires --accept-growth: {message}", file=sys.stderr)
        return 2
    if retirements and not reason:
        for message in retirements:
            print(f"{message} requires --reason", file=sys.stderr)
        return 2
    if growth and not reason:
        print("--accept-growth requires --reason", file=sys.stderr)
        return 2
    recorded = [
        {"detail": message, "reason": reason}
        for message in [*growth, *retirements]
    ]
    if recorded:
        current["acknowledgedChanges"] = dedupe_acknowledgements(
            baseline.get("acknowledgedChanges", []), recorded
        )
    text = json.dumps(current, ensure_ascii=False, indent=2) + "\n"
    (REPO_ROOT / BASELINE_RELATIVE_PATH).write_text(text, encoding="utf-8")
    print(f"wrote {BASELINE_RELATIVE_PATH}")
    return 0


def print_report(measurements: dict[str, Any], output_format: str) -> None:
    if output_format == "json":
        print(json.dumps(measurements, ensure_ascii=False, indent=2))
        return
    print(f"dead entries: {len(measurements['deadEntries'])}")
    for entry in measurements["deadEntries"]:
        print(f"  - {entry['name']} ({entry['kind']}) {entry['file']}")
    print(f"inventory entries: {len(measurements['inventoryEntries'])}")
    for entry in measurements["inventoryEntries"]:
        print(f"  - {entry['name']} {entry['file']} — {entry['reason']}")
    print("canonical helper definitions:")
    for name, count in measurements["canonicalHelpers"].items():
        print(f"  - {name}: {count}")
    print("swallow pattern matches:")
    for pattern_id, count in measurements["swallowPatterns"].items():
        print(f"  - {pattern_id}: {count}")


def escape_github(message: str) -> str:
    return message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def emit(messages: Sequence[str], level: str, output_format: str) -> None:
    for message in messages:
        if output_format == "github":
            print(f"::{level} title=scene-defense::{escape_github(message)}")
        elif output_format != "json":
            print(f"{level}: {message}")


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_arguments()
    try:
        baseline = load_current_baseline()
        layout_root = scene_source_root()
        if baseline["sourceRoot"] != layout_root:
            raise ValueError(
                f"{BASELINE_RELATIVE_PATH} sourceRoot {baseline['sourceRoot']!r} does not match "
                f"{LAYOUT_RELATIVE_PATH} source_root {layout_root!r}"
            )
        paths = tracked_paths()
        measurements = measure(paths, baseline)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2

    if args.audit:
        print_report(measurements, args.format)
        return 0
    if args.ratchet_baseline:
        return ratchet(baseline, measurements, args)

    errors, warnings = evaluate(baseline, measurements)
    guard_note = ""
    if args.base_ref:
        try:
            referenced = baseline_at_ref(args.base_ref)
        except ValueError as error:
            print(str(error), file=sys.stderr)
            return 2
        if referenced is None:
            warnings.append(f"no defense baseline at {args.base_ref}; growth guard unavailable")
            guard_note = f" (growth guard unavailable at {args.base_ref})"
        else:
            ref_growth, ref_changes = check_growth(referenced, baseline)
            acknowledged = {
                str(entry["detail"]) for entry in baseline.get("acknowledgedChanges", [])
            }
            for message in ref_growth:
                if message in acknowledged:
                    warnings.append(f"acknowledged growth: {message}")
                else:
                    errors.append(
                        f"{message}; acknowledge it deliberately with "
                        "`--ratchet-baseline --accept-growth --reason` so "
                        f"{BASELINE_RELATIVE_PATH.as_posix()} records the change"
                    )
            for message in ref_changes:
                if message in acknowledged:
                    warnings.append(f"acknowledged reviewed-set change: {message}")
                else:
                    errors.append(
                        f"{message}; land the reviewed-set change deliberately and record it "
                        f"in {BASELINE_RELATIVE_PATH.as_posix()} acknowledgedChanges"
                    )
    if args.format == "json":
        print(json.dumps(
            {
                "result": "failed" if errors else "holds",
                "errors": errors,
                "warnings": warnings,
                "measurements": measurements,
            },
            ensure_ascii=False,
            indent=2,
        ))
        return 1 if errors else 0
    emit(warnings, "warning", args.format)
    emit(errors, "error", args.format)
    if errors:
        print(f"scene defense ratchet failed with {len(errors)} error(s)")
        return 1
    print(
        "scene defense ratchet holds: "
        f"{len(measurements['deadEntries'])} locked dead entr(ies), "
        f"{len(measurements['canonicalHelpers'])} canonical helpers, "
        f"{len(measurements['swallowPatterns'])} swallow patterns{guard_note}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
