#!/usr/bin/env python3
"""Static source authority classification, metric migration and directory contracts.

This bounded lexical checker is governance evidence, not Swift semantic or runtime proof.
"""
from __future__ import annotations

import fnmatch
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path


def swift_without_comments(text: str) -> str:
    output: list[str] = []
    index = 0
    block_depth = 0
    state = "code"
    while index < len(text):
        if state == "line-comment":
            if text[index] == "\n":
                output.append("\n")
                state = "code"
            else:
                output.append(" ")
            index += 1
            continue
        if state == "block-comment":
            if text.startswith("/*", index):
                output.extend("  ")
                block_depth += 1
                index += 2
            elif text.startswith("*/", index):
                output.extend("  ")
                block_depth -= 1
                index += 2
                if block_depth == 0:
                    state = "code"
            else:
                output.append("\n" if text[index] == "\n" else " ")
                index += 1
            continue
        if state == "string":
            output.append(text[index])
            if text[index] == "\\" and index + 1 < len(text):
                output.append(text[index + 1])
                index += 2
            else:
                if text[index] == '"':
                    state = "code"
                index += 1
            continue
        if state == "multiline-string":
            if text.startswith('"""', index):
                output.extend('"""')
                index += 3
                state = "code"
            else:
                output.append(text[index])
                index += 1
            continue
        if text.startswith("//", index):
            output.extend("  ")
            index += 2
            state = "line-comment"
        elif text.startswith("/*", index):
            output.extend("  ")
            index += 2
            block_depth = 1
            state = "block-comment"
        elif text.startswith('"""', index):
            output.extend('"""')
            index += 3
            state = "multiline-string"
        elif text[index] == '"':
            output.append('"')
            index += 1
            state = "string"
        else:
            output.append(text[index])
            index += 1
    return "".join(output)


GOVERNANCE_TOKEN_PATTERN = re.compile(
    r'(?P<hash>\#*)(?:"""[\s\S]*?"""|"(?:\\.|[^"\\])*")(?P=hash)|`[A-Za-z_]\w*`|[A-Za-z_]\w*|[^\s]'
)


def governance_tokens(text: str) -> list[tuple[str, int]]:
    """Bounded lexical classification, not a Swift semantic parser.

    Preserve offsets; strings cannot impersonate declarations or braces.
    Unsupported syntax stays unclassified and therefore fails closed.
    """
    return [("<literal>" if '"' in match.group() else match.group().strip("`"), match.start())
            for match in GOVERNANCE_TOKEN_PATTERN.finditer(text)]


def direct_scope_indices(values: list[str], lower: int, upper: int) -> list[int]:
    depth = 0
    indices: list[int] = []
    for index in range(lower, upper):
        if depth == 0:
            indices.append(index)
        depth += (values[index] == "{") - (values[index] == "}")
    return indices


def named_scope_range(tokens: list[tuple[str, int]], scopes: list[dict]) -> tuple[int, int] | None:
    values = [value for value, _ in tokens]
    lower, upper = 0, len(values)
    for scope in scopes:
        starts = [index for index in direct_scope_indices(values, lower, upper)
                  if values[index:index + 2] == [scope["kind"], scope["name"]]]
        if len(starts) != 1:
            return None
        opening = next((index for index in range(starts[0] + 2, upper)
                        if values[index] == "{"), None)
        if opening is None:
            return None
        depth = 1
        for closing in range(opening + 1, upper):
            depth += (values[closing] == "{") - (values[closing] == "}")
            if depth == 0:
                lower, upper = opening + 1, closing
                break
        else:
            return None
    return lower, upper


def conditional_stack_at(text: str, offset: int) -> list[str]:
    # Compiler directives inside normal/raw/multiline strings are data. Keep
    # offsets and newlines unchanged so the declaration still indexes this view.
    text = GOVERNANCE_TOKEN_PATTERN.sub(
        lambda match: "".join("\n" if char == "\n" else " " for char in match.group())
        if '"' in match.group() else match.group(), text,
    )
    stack: list[str] = []
    for match in re.finditer(r"(?m)^\s*#(if|elseif|else|endif)\b([^\n]*)", text[:offset]):
        directive, condition = match.groups()
        if directive == "if":
            stack.append(condition.strip())
        elif directive == "endif" and stack:
            stack.pop()
        elif stack:
            stack[-1] = "<alternate-branch>"
    return stack


def classified_authority_count(text: str, relative: str, rule: dict) -> tuple[int, list[str], set[int]]:
    matches = list(re.finditer(rule["pattern"], text, re.MULTILINE))
    classifications = rule.get("classifications", [])
    if not classifications:
        return len(matches), [], set()
    errors: list[str] = []
    for classification in classifications:
        if classification["kind"] != "passive-value-declaration":
            continue
        declaration_tokens = governance_tokens(classification["declaration"])
        name = declaration_tokens[1][0]
        owner = classification["scope"][0]["name"]
        if name not in text and owner not in text:
            continue
        values = [value for value, _ in governance_tokens(text)]
        for index, value in enumerate(values):
            if value == "extension":
                end = next((end for end in range(index + 1, len(values))
                            if values[end] in {"{", ":", "where"}), len(values))
                if name in values[index + 1:end]:
                    errors.append(f"{relative}: extension of classified passive declaration requires review")
            elif value == "typealias":
                end = next((end for end in range(index + 1, len(values))
                            if values[end] in {"{", "}", ";", "typealias", "extension", "struct",
                                               "class", "enum", "func", "let", "var", "import"}), len(values))
                head = values[index + 1:end]
                rhs = head[head.index("=") + 1:] if "=" in head else []
                aliases_owner = owner in rhs
                aliases_unqualified_value = any(token == name and (index == 0 or rhs[index - 1] != ".")
                                                for index, token in enumerate(rhs))
                if aliases_owner or aliases_unqualified_value:
                    # An alias can become an extension target elsewhere. It is
                    # an unreviewed escape from this bounded passive identity.
                    errors.append(f"{relative}: typealias of classified passive declaration requires review")
    if not any(item["file"] == relative for item in classifications):
        if matches and rule.get("metric") == "local-alias-declarations":
            errors.append(f"{relative}: unclassified singular reference")
        return len(matches), errors, set()
    tokens = governance_tokens(text)
    values = [value for value, _ in tokens]
    positions = {offset: index for index, (_, offset) in enumerate(tokens)}
    admitted: dict[int, tuple[int, int]] = {}
    observed: set[int] = set()
    for number, classification in enumerate(classifications):
        if classification["file"] != relative:
            continue
        scope = named_scope_range(tokens, classification["scope"])
        if scope is None:
            errors.append(f"{relative}: classified scope is missing or ambiguous")
            continue
        lower, upper = scope
        declaration = [value for value, _ in governance_tokens(classification["declaration"])]
        declarations = [index for index in direct_scope_indices(values, lower, upper)
                        if values[index:index + len(declaration)] == declaration]
        if len(declarations) != 1:
            errors.append(f"{relative}: classified declaration is missing or ambiguous")
            continue
        start = declarations[0]
        kind = classification["kind"]
        if kind == "passive-value-declaration":
            if conditional_stack_at(text, tokens[start][1]) != classification["conditions"]:
                errors.append(f"{relative}: passive declaration conditional scope changed")
                continue
            # Only the complete reviewed value declaration is excluded, never its file.
            for index in range(start, start + len(declaration)):
                admitted[index] = (0, number)
        elif kind == "local-readonly-alias":
            if declaration[0] != "let" or declaration[1] != classification["identifier"]:
                errors.append(f"{relative}: alias must be an immutable local binding")
                continue
            following = start + len(declaration)
            if following < upper and values[following] not in {
                ";", "let", "var", "if", "guard", "switch", "return", "for", "while",
            }:
                errors.append(f"{relative}: alias initializer extends past its classified binding")
                continue
            admitted[start + 1] = (1, number)
            for index in range(start + len(declaration), upper):
                if values[index] != classification["identifier"] or values[index - 1] in {".", "&"}:
                    continue
                for read in classification["reads"]:
                    read_tokens = [value for value, _ in governance_tokens(read)]
                    end = index + len(read_tokens)
                    if values[index:end] == read_tokens and values[end:end + 1] not in (
                        ["="], ["+"], ["-"], ["*"], ["/"], ["%"], ["&"], ["|"],
                        ["^"], ["<"], [">"], ["."], ["?"], ["!"], ["["],
                    ):
                        admitted[index] = (0, number)
        else:
            errors.append(f"{relative}: unsupported classification kind {kind}")
    count = 0
    for match in matches:
        # Declaration patterns may include indentation. Match the first real token.
        offset = match.start() + len(match.group()) - len(match.group().lstrip())
        index = positions.get(offset)
        if index in admitted:
            weight, number = admitted[index]
            count += weight
            observed.add(number)
        elif rule.get("metric", "occurrences") == "local-alias-declarations":
            errors.append(f"{relative}:{text.count(chr(10), 0, match.start()) + 1}: unclassified singular reference")
            count += 1
        else:
            count += 1
    return count, errors, observed


def authority_metric_contract(rule: dict) -> dict:
    return {key: rule.get(key) for key in (
        "id", "pattern", "baseline_occurrences", "allowed_files", "scope_files", "scan_root",
        "start_marker", "end_marker", "metric", "classifications",
    )}


def authority_metric_digest(rule: dict) -> str:
    payload = json.dumps(authority_metric_contract(rule), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()


def classification_transition_violations(old: dict, new: dict) -> list[str]:
    if old.get("metric") is not None or new.get("classifications"):
        if any(old.get(field) != new.get(field) for field in (
            "pattern", "scan_root", "scope_files", "start_marker", "end_marker",
        )):
            return [f"{new['id']}: classified inventory must preserve its global discovery contract"]
    retired = (old.get("classification_migration") is not None
               and not new.get("classifications")
               and new.get("metric") == old.get("metric")
               and new.get("baseline_occurrences") == 0
               and not new.get("allowed_files") and not new.get("scope_files"))
    if retired:
        return []
    if (old.get("classification_migration") is not None
            and new.get("classification_migration") != old["classification_migration"]):
        return [f"{new['id']}: committed migration record is immutable until complete retirement"]
    changed = any(old.get(key) != new.get(key) for key in ("metric", "classifications"))
    if not changed:
        return []
    migration = new.get("classification_migration", {})
    if (old.get("classification_migration") is not None
            or old.get("metric") is not None or old.get("classifications") is not None
            or old.get("role") != "inventory" or new.get("role") != "inventory"
            or migration.get("from_contract_sha256") != authority_metric_digest(old)
            or migration.get("to_contract_sha256") != authority_metric_digest(new)
            or migration.get("design_doc") != "docs/development/structural-governance-design.md"
            or any(not migration.get(key) for key in ("owner", "reason", "retirement"))):
        return [f"{new['id']}: classification change requires its approved one-time metric migration"]
    return []



def authority_call_inventory(sources: dict[str, str], pattern: str) -> dict[str, list[tuple[str, ...]]]:
    """Exact call tokens, retaining literal contents and ignoring only comments/spacing."""
    result = {}
    for path, source in sorted(sources.items()):
        text = swift_without_comments(source)
        calls = []
        for match in re.finditer(pattern, text, re.MULTILINE):
            tokens = list(GOVERNANCE_TOKEN_PATTERN.finditer(text, match.start()))
            opening = next((i for i, token in enumerate(tokens) if token.group() == "("), None)
            if opening is None or tokens[opening].end() != match.end():
                raise ValueError("authority relocation must identify a complete call opening")
            depth = 0
            for closing in range(opening, len(tokens)):
                value = tokens[closing].group()
                depth += (value == "(") - (value == ")")
                if depth == 0:
                    calls.append(tuple(token.group() for token in tokens[:closing + 1]))
                    break
            else:
                raise ValueError("authority relocation call is unbalanced")
        if calls:
            result[path] = calls
    return result


def authority_relocation_transition_violations(
    old: dict, new: dict, old_sources: dict[str, str], new_sources: dict[str, str],
) -> list[str]:
    """Validate one reviewed method extraction; never grant a general allowed-set exemption."""
    key = "owner_relocation"
    before, receipt = old.get(key), new.get(key)
    if before is not None:
        discovery_changed = any(old.get(k) != new.get(k) for k in authority_metric_contract(old)
                                if k not in {"allowed_files", "baseline_occurrences"})
        grew = (not set(new.get("allowed_files", [])).issubset(old["allowed_files"])
                or new.get("baseline_occurrences", 0) > old["baseline_occurrences"])
        if discovery_changed or grew or new.get("role") != old.get("role"):
            return [f"{new['id']}: committed relocation discovery and owner scope cannot expand or change"]
        retired = (new.get("baseline_occurrences") == 0 and not new.get("allowed_files")
                   and receipt is None)
        if not retired and receipt != before:
            return [f"{new['id']}: committed owner relocation is immutable until complete retirement"]
        return []
    if receipt is None:
        return []
    error = [f"{new['id']}: owner relocation requires its exact reviewed call-preserving receipt"]
    if not isinstance(receipt, dict):
        return error
    if (old.get("id") != "bounded-frontend-product-entry" or new.get("id") != old["id"]
            or old.get("role") != "inventory" or new.get("role") != "inventory"
            or old.get("pattern") != r"SceneAuthoredShaderFrontend\.compile\("
            or any(old.get(k) != new.get(k) for k in authority_metric_contract(old) if k != "allowed_files")
            or any(old.get(k) is not None for k in ("scope_files", "scan_root", "start_marker", "end_marker", "metric", "classifications"))
            or receipt.get("from_contract_sha256") != authority_metric_digest(old)
            or receipt.get("to_contract_sha256") != authority_metric_digest(new)
            or receipt.get("design_doc") != "docs/scene/roadmap/batch2/frame-admission-retry-design.md"
            or any(not isinstance(receipt.get(k), str) or not receipt[k].strip()
                   for k in ("owner", "reason", "retirement"))):
        return error
    removed = set(old["allowed_files"]) - set(new["allowed_files"])
    added = set(new["allowed_files"]) - set(old["allowed_files"])
    if (removed != {receipt.get("from_file")} or added != {receipt.get("to_file")}
            or len(removed) != 1 or len(added) != 1):
        return error
    try:
        previous = authority_call_inventory(old_sources, old["pattern"])
        current = authority_call_inventory(new_sources, new["pattern"])
    except ValueError:
        return error
    origin, destination = receipt["from_file"], receipt["to_file"]
    if (set(previous) != set(old["allowed_files"]) or set(current) != set(new["allowed_files"])
            or sum(map(len, previous.values())) != old["baseline_occurrences"]
            or sum(map(len, current.values())) != new["baseline_occurrences"]
            or origin in current or destination in previous
            or len(previous.get(origin, [])) != 1
            or previous[origin] != current.get(destination)):
        return error
    expected = {destination if path == origin else path: calls for path, calls in previous.items()}
    return [] if expected == current else error


def render_chain_authority_violations(
    source_root: Path,
    rules: list[dict[str, object]],
    repository_root: Path | None = None,
) -> list[str]:
    violations: list[str] = []
    all_sources = sorted(source_root.rglob("*.swift"))
    sources_by_root = {source_root: all_sources}
    searchable_by_path: dict[Path, str] = {}
    for rule in rules:
        rule_id = str(rule["id"])
        allowed_files = [str(value) for value in rule["allowed_files"]]
        scope_files = [str(value) for value in rule.get("scope_files", [])]
        rule_source_root = source_root
        scan_root = rule.get("scan_root")
        if scan_root is not None:
            if repository_root is None:
                violations.append(
                    f"{rule_id}: scan_root requires an explicit repository root"
                )
                continue
            rule_source_root = repository_root / str(scan_root)
        if scope_files:
            sources = [rule_source_root / relative for relative in scope_files]
        else:
            if rule_source_root not in sources_by_root:
                sources_by_root[rule_source_root] = sorted(rule_source_root.rglob("*.swift"))
            sources = sources_by_root[rule_source_root]
        matches_by_file: dict[str, int] = {}
        observed_classifications: set[int] = set()
        for source in sources:
            if not source.is_file():
                violations.append(f"{rule_id}: scope file is missing: {source}")
                continue
            relative = source.relative_to(rule_source_root).as_posix()
            if source not in searchable_by_path:
                searchable_by_path[source] = swift_without_comments(source.read_text(encoding="utf-8"))
            searchable = searchable_by_path[source]
            start_marker = rule.get("start_marker")
            end_marker = rule.get("end_marker")
            if start_marker is not None:
                start = searchable.find(str(start_marker))
                if start < 0:
                    violations.append(
                        f"{rule_id}: start marker missing in {relative}"
                    )
                    continue
                searchable = searchable[start:]
            if end_marker is not None:
                end = searchable.find(str(end_marker))
                if end < 0:
                    violations.append(f"{rule_id}: end marker missing in {relative}")
                    continue
                searchable = searchable[:end]
            count, classification_errors, observed = classified_authority_count(searchable, relative, rule)
            observed_classifications.update(observed)
            violations.extend(f"{rule_id}: {error}" for error in classification_errors)
            if count:
                matches_by_file[relative] = count

        for number, classification in enumerate(rule.get("classifications", [])):
            if number not in observed_classifications:
                violations.append(f"{rule_id}: stale classification in {classification['file']}")

        actual_files = sorted(matches_by_file)
        actual_occurrences = sum(matches_by_file.values())
        baseline_occurrences = int(rule["baseline_occurrences"])
        if actual_files != allowed_files:
            violations.append(
                f"{rule_id}: files {actual_files} != baseline {allowed_files}"
            )
        if actual_occurrences != baseline_occurrences:
            violations.append(
                f"{rule_id}: occurrences {actual_occurrences} != baseline "
                f"{baseline_occurrences}; ratchet the manifest when authority shrinks"
            )
    return violations


def render_chain_completion_violations(
    source_root: Path,
    layout: dict[str, object],
    repository_root: Path | None = None,
) -> list[str]:
    contract = layout["render_chain_authority_ratchet"]
    assert isinstance(contract, dict)
    rules = contract["rules"]
    states = contract["completion_state"]
    assert isinstance(rules, list)
    assert isinstance(states, dict)

    violations = render_chain_authority_violations(
        source_root,
        rules,
        repository_root,
    )
    r4_state = str(states.get("r4"))
    r5_state = str(states.get("r5"))
    if r5_state in {"partial", "complete"} and r4_state != "complete":
        violations.append("r5: cannot start before r4 is complete")

    completed_phases: set[str] = set()
    if r4_state == "complete":
        completed_phases.add("r4")
    if r5_state == "complete":
        completed_phases.update({"r4", "r5"})
    for rule in rules:
        if rule.get("role") != "retirement":
            continue
        phase = str(rule["completion_phase"])
        if phase not in completed_phases:
            continue
        baseline = int(rule["baseline_occurrences"])
        target = int(rule["completion_target_occurrences"])
        if baseline != target:
            violations.append(
                f"{rule['id']}: {phase} completion requires {target} "
                f"occurrences, found {baseline}"
            )
        if target == 0 and rule["allowed_files"]:
            violations.append(
                f"{rule['id']}: completed zero target must have no allowed files"
            )
    return violations


def scene_source_layout_violations(source_root: Path, layout: dict) -> list[str]:
    """Every Swift file belongs to exactly one declared directory inventory."""
    paths = sorted(source_root.rglob("*"))
    sources = [path.relative_to(source_root) for path in paths
               if path.is_file() and path.suffix == ".swift"]
    contracts = {Path(top) / second: contract["file_globs"]
                 for top, seconds in layout["declared_second_level_directories"].items()
                 for second, contract in seconds.items()}
    violations: list[str] = []
    for top, contract in layout["declared_flat_directories"].items():
        files = contract["files"]
        if files != sorted(set(files)) or any(
            Path(name).name != name or not name.endswith(".swift")
            or any(char in name for char in "*?[") for name in files
        ):
            violations.append(f"{top}: flat inventory must contain sorted unique exact Swift filenames")
        contracts[Path(top)] = files
    if {source.parts[0] for source in sources} != set(layout["top_level_directories"]):
        violations.append("top-level directories differ from the declared inventory")
    names: defaultdict[str, list[Path]] = defaultdict(list)
    for source in sources:
        names[source.name].append(source)
        patterns = contracts.get(source.parent)
        if patterns is None:
            violations.append(f"{source}: directory is not declared")
        elif not any(fnmatch.fnmatchcase(source.name, pattern) for pattern in patterns):
            violations.append(f"{source}: filename is outside its directory contract")
    for parent, patterns in contracts.items():
        for pattern in patterns:
            matches = [source for source in sources if fnmatch.fnmatchcase(source.name, pattern)]
            if not matches:
                violations.append(f"{parent}/{pattern}: layout entry matched no files")
            for source in matches:
                if source.parent != parent:
                    violations.append(f"{source}: belongs in {parent}")
    for name, locations in names.items():
        if len(locations) > 1:
            violations.append(f"{name}: duplicate Swift basename: {locations}")
    for path in paths:
        if path.is_dir() and path.name in layout["forbidden_directory_names"]:
            violations.append(f"{path.relative_to(source_root)}: forbidden directory name")
    return violations
