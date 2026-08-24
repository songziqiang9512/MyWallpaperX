#!/usr/bin/env python3
"""Identity-free external-artifact contracts for independent RGBA stages."""

from __future__ import annotations

import ast
import math
import re
from dataclasses import dataclass
from typing import Any, Callable

from scene_shader_compiler_msl_function_contract import sample_end


PRODUCER_KIND = "independent-alpha-signal"
PRESERVING_KIND = "independent-alpha-signal-preserving"
_TRANSFER_KINDS = {PRODUCER_KIND, PRESERVING_KIND}
_UNPREMULTIPLY = "mwxIndependentSignalUnpremultiply"


class IndependentSignalContractFailure(RuntimeError):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


PreservingFallback = Callable[[str, dict[str, Any], list[dict[str, Any]]], dict[str, Any]]


@dataclass(frozen=True)
class _Function:
    name: str
    return_type: str
    body_start: int
    body_end: int


@dataclass(frozen=True)
class _Sample:
    start: int
    end: int
    slot: int
    projection: str | None


def parse_expected_transfer(value: Any) -> dict[str, Any] | None:
    """Validate the request's independent-signal transfer without broadening it."""
    if value is None:
        return None
    if not isinstance(value, dict) or set(value) != {"kind", "slot"}:
        raise IndependentSignalContractFailure("expected-color-transfer")
    kind, slot = value.get("kind"), value.get("slot")
    if (
        kind not in _TRANSFER_KINDS
        or isinstance(slot, bool)
        or not isinstance(slot, int)
        or not 0 <= slot < 8
    ):
        raise IndependentSignalContractFailure("expected-color-transfer")
    return {"kind": kind, "slot": slot}


def prepare_independent_signal_contract(
    fragment_msl: str,
    expected_transfer: Any,
    texture_bindings: list[dict[str, Any]],
    *,
    maximum_loop_work: int = 256,
    preserving_fallback: PreservingFallback | None = None,
) -> tuple[str, dict[str, Any]]:
    """Prepare a producer, accumulator, or existing preserving carrier."""
    expected = parse_expected_transfer(expected_transfer)
    if expected is None:
        raise IndependentSignalContractFailure("expected-color-transfer")
    if not isinstance(fragment_msl, str) or not fragment_msl.strip():
        raise IndependentSignalContractFailure("independent-signal-source")
    if (
        isinstance(maximum_loop_work, bool)
        or not isinstance(maximum_loop_work, int)
        or not 1 <= maximum_loop_work <= 4096
    ):
        raise IndependentSignalContractFailure("independent-loop-budget")
    _validate_expected_binding(expected["slot"], texture_bindings)

    if expected["kind"] == PRODUCER_KIND:
        return _prepare_producer(fragment_msl, expected), expected

    if _looks_like_accumulator(fragment_msl):
        independent_signal_accumulator_static_loop_work(
            fragment_msl,
            expected_slot=expected["slot"],
            maximum_loop_work=maximum_loop_work,
        )
        return fragment_msl, expected
    if preserving_fallback is None:
        raise IndependentSignalContractFailure("independent-preserving-not-applicable")
    fallback = preserving_fallback(fragment_msl, expected, texture_bindings)
    if fallback != expected:
        raise IndependentSignalContractFailure("independent-preserving-fallback")
    return fragment_msl, expected


def _validate_expected_binding(slot: int, texture_bindings: list[dict[str, Any]]) -> None:
    if not isinstance(texture_bindings, list):
        raise IndependentSignalContractFailure("independent-color-binding")
    matches = [
        binding for binding in texture_bindings
        if isinstance(binding, dict)
        and binding.get("slot") == slot
        and binding.get("name") == f"g_Texture{slot}"
    ]
    if len(matches) != 1:
        raise IndependentSignalContractFailure("independent-color-binding")


def _mask_comments(source: str) -> str:
    def mask(match: re.Match[str]) -> str:
        return "".join("\n" if value == "\n" else " " for value in match.group(0))

    return re.sub(r"/\*.*?\*/|//[^\n]*", mask, source, flags=re.DOTALL)


def _matching_brace(source: str, opening: int) -> int | None:
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return None


def _functions(source: str) -> list[_Function]:
    result: list[_Function] = []
    search_source = re.sub(
        r"\b__attribute__\s*\(\([^()]*\)\)",
        lambda match: " " * len(match.group(0)),
        source,
    )
    pattern = re.compile(
        r"\b(?P<return>[A-Za-z_]\w*(?:\s*<[^;{}]+>)?)\s+"
        r"(?P<name>[A-Za-z_]\w*)\s*\([^;{}]*\)\s*\{",
        re.DOTALL,
    )
    for match in pattern.finditer(search_source):
        opening = search_source.find("{", match.start(), match.end())
        closing = _matching_brace(search_source, opening)
        if closing is None:
            raise IndependentSignalContractFailure("independent-function-shape")
        result.append(_Function(
            name=match.group("name"),
            return_type=match.group("return").strip(),
            body_start=opening + 1,
            body_end=closing,
        ))
    names = [value.name for value in result]
    if len(set(names)) != len(names):
        raise IndependentSignalContractFailure("independent-function-shape")
    return result


def _entry(source: str) -> tuple[_Function, str]:
    functions = _functions(source)
    matches = [value for value in functions if value.name == "mwxGenericFragment"]
    if len(matches) != 1:
        raise IndependentSignalContractFailure("independent-output-carrier")
    entry = matches[0]
    structures = re.findall(
        rf"\bstruct\s+{re.escape(entry.return_type)}\s*\{{(?P<body>.*?)\}}\s*;",
        source,
        re.DOTALL,
    )
    if len(structures) != 1:
        raise IndependentSignalContractFailure("independent-output-carrier")
    attachments = re.findall(
        r"\bfloat4\s+([A-Za-z_]\w*)\s*"
        r"\[\[\s*color\((\d+)\)\s*\]\]\s*;",
        structures[0],
    )
    if attachments != [("mwxFragColor", "0")]:
        raise IndependentSignalContractFailure("independent-output-carrier")
    return entry, source[entry.body_start:entry.body_end]


def _samples(source: str) -> list[_Sample]:
    values: list[_Sample] = []
    for match in re.finditer(
        r"\bg_Texture(?P<slot>[0-7])\s*\.\s*sample\s*\(", source
    ):
        opening = source.find("(", match.start())
        end = sample_end(source, opening)
        if end is None:
            raise IndependentSignalContractFailure("independent-color-sample")
        projection_match = re.match(
            r"\s*\.\s*(?P<value>[A-Za-z_]\w*)", source[end:]
        )
        projection = projection_match.group("value") if projection_match else None
        values.append(_Sample(
            start=match.start(), end=end, slot=int(match.group("slot")),
            projection=projection,
        ))
    return values


def _output_writes(body: str) -> list[re.Match[str]]:
    return list(re.finditer(
        r"\bout\.mwxFragColor(?P<member>\s*\.\s*[xyzwrgba]{1,4})?\s*"
        r"(?P<operator>\+=|-=|\*=|/=|=(?!=))",
        body,
    ))


def _validate_return_and_output_scope(source: str, entry: _Function, body: str) -> None:
    returns = list(re.finditer(r"\breturn\s+out\s*;", body))
    if len(returns) != 1 or len(re.findall(r"\breturn\b", body)) != 1:
        raise IndependentSignalContractFailure("independent-output-return")
    if re.search(
        r"\b(if|else|switch|while|do|discard|break|continue|goto)\b|\?",
        body,
    ):
        raise IndependentSignalContractFailure("independent-control-flow")
    declarations = re.findall(
        rf"\b{re.escape(entry.return_type)}\s+out\s*=\s*\{{\s*\}}\s*;",
        body,
    )
    writes = _output_writes(body)
    if (
        len(declarations) != 1
        or len(re.findall(r"\bout\b", body)) != len(writes) + 2
    ):
        raise IndependentSignalContractFailure("independent-output-drift")
    outside = source[:entry.body_start] + source[entry.body_end:]
    if re.search(r"\bout\.mwxFragColor\b", outside):
        raise IndependentSignalContractFailure("independent-output-drift")


def _statement_bounds(source: str, index: int) -> tuple[int, int]:
    start = max(source.rfind(";", 0, index), source.rfind("{", 0, index)) + 1
    end = source.find(";", index)
    if end < 0:
        raise IndependentSignalContractFailure("independent-color-sample")
    return start, end + 1


def _prepare_producer(source: str, expected: dict[str, Any]) -> str:
    masked = _mask_comments(source)
    if re.search(rf"\b{re.escape(_UNPREMULTIPLY)}\b", masked):
        raise IndependentSignalContractFailure("independent-color-boundary")
    namespaces = list(re.finditer(r"\busing\s+namespace\s+metal\s*;", masked))
    if len(namespaces) != 1:
        raise IndependentSignalContractFailure("independent-color-boundary")
    entry, body = _entry(masked)
    _validate_return_and_output_scope(masked, entry, body)
    if re.search(r"\bfor\b", body):
        raise IndependentSignalContractFailure("independent-control-flow")

    samples = _samples(masked)
    whole = [value for value in samples if value.projection is None]
    slot = expected["slot"]
    if len(whole) != 1 or whole[0].slot != slot:
        raise IndependentSignalContractFailure("independent-color-sample")
    if sum(value.slot == slot for value in samples) != 1:
        raise IndependentSignalContractFailure("independent-color-sample")
    if any(
        value.projection not in ("x", "r", "xy", "rg")
        for value in samples if value is not whole[0]
    ):
        raise IndependentSignalContractFailure("independent-color-sample")
    if not entry.body_start <= whole[0].start < entry.body_end:
        raise IndependentSignalContractFailure("independent-color-sample")

    statement_start, statement_end = _statement_bounds(masked, whole[0].start)
    prefix = masked[statement_start:whole[0].start]
    suffix = masked[whole[0].end:statement_end]
    declaration = re.fullmatch(
        r"\s*(?:const\s+)?float4\s+(?P<name>[A-Za-z_]\w*)\s*=\s*",
        prefix,
    )
    if declaration is None or not re.fullmatch(r"\s*;", suffix):
        raise IndependentSignalContractFailure("independent-producer-carrier")
    carrier = declaration.group("name")
    carrier_pattern = re.escape(carrier)
    alpha_aliases = list(re.finditer(
        rf"\b(?:const\s+)?float\s+([A-Za-z_]\w*)\s*=\s*"
        rf"{carrier_pattern}\s*\.\s*(?:w|a)\s*;",
        body,
    ))
    if len(alpha_aliases) > 1:
        raise IndependentSignalContractFailure("independent-producer-flow")
    if alpha_aliases:
        alias = re.escape(alpha_aliases[0].group(1))
        alias_writes = re.findall(
            rf"\b{alias}(?:\s*\.\s*[xyzwrgba]{{1,4}})?\s*"
            r"(?:\+=|-=|\*=|/=|=(?!=))",
            body,
        )
        if len(alias_writes) != 1:
            raise IndependentSignalContractFailure("independent-producer-flow")
    alpha_source = (
        re.escape(alpha_aliases[0].group(1))
        if alpha_aliases else rf"{carrier_pattern}\s*\.\s*(?:w|a)"
    )
    packed_rgb_writes = list(re.finditer(
        rf"\b{carrier_pattern}\s*\.\s*(?:xyz|rgb)\s*\*=\s*"
        rf"(?:{alpha_source})\s*;",
        body,
    ))
    member_rgb_writes = list(re.finditer(
        rf"\b{carrier_pattern}\s*\.\s*(?P<member>[xyz])\s*\*=\s*"
        rf"(?:{alpha_source})\s*;",
        body,
    ))
    lowered_rgb_writes: list[re.Match[str]] = []
    lowered_flow_start: int | None = None
    if alpha_aliases:
        snapshots = list(re.finditer(
            rf"\bfloat4\s+(?P<name>[A-Za-z_]\w*)\s*=\s*"
            rf"{carrier_pattern}\s*;",
            body,
        ))
        if len(snapshots) == 1:
            snapshot = snapshots[0].group("name")
            snapshot_pattern = re.escape(snapshot)
            rgb_declarations = list(re.finditer(
                rf"\bfloat3\s+(?P<name>[A-Za-z_]\w*)\s*=\s*"
                rf"(?:{snapshot_pattern}\s*\.\s*(?:xyz|rgb)\s*\*\s*{alpha_source}"
                rf"|{alpha_source}\s*\*\s*{snapshot_pattern}\s*\.\s*(?:xyz|rgb))\s*;",
                body,
            ))
            if len(rgb_declarations) == 1:
                rgb = rgb_declarations[0].group("name")
                lowered_rgb_writes = list(re.finditer(
                    rf"\b{carrier_pattern}\s*\.\s*(?P<member>[xyz])\s*=\s*"
                    rf"{re.escape(rgb)}\s*\.\s*(?P<source>[xyz])\s*;",
                    body,
                ))
                if (
                    [value.group("member") for value in lowered_rgb_writes]
                    != ["x", "y", "z"]
                    or [value.group("source") for value in lowered_rgb_writes]
                    != ["x", "y", "z"]
                    or len(re.findall(rf"\b{snapshot_pattern}\b", body)) != 2
                    or len(re.findall(rf"\b{re.escape(rgb)}\b", body)) != 4
                    or len(re.findall(
                        rf"\b{re.escape(alpha_aliases[0].group(1))}\b", body
                    )) != 2
                ):
                    lowered_rgb_writes = []
                else:
                    lowered_flow_start = min(
                        snapshots[0].start(), rgb_declarations[0].start()
                    )

    if len(packed_rgb_writes) == 1 and not member_rgb_writes and not lowered_rgb_writes:
        rgb_writes = packed_rgb_writes
        lowered = False
    elif not packed_rgb_writes and not lowered_rgb_writes and [
        value.group("member") for value in member_rgb_writes
    ] == ["x", "y", "z"]:
        rgb_writes = member_rgb_writes
        lowered = False
    elif not packed_rgb_writes and not member_rgb_writes and lowered_rgb_writes:
        rgb_writes = lowered_rgb_writes
        lowered = True
    else:
        raise IndependentSignalContractFailure("independent-producer-flow")
    alpha_one = re.search(
        rf"\b{carrier_pattern}\s*\.\s*(?:w|a)\s*=\s*1(?:\.0+)?[fF]?\s*;",
        body,
    )
    writes = _output_writes(body)
    roots = [value for value in writes if value.group("member") is None]
    alpha_updates = [
        value for value in writes
        if re.sub(r"\s", "", value.group("member") or "") in (".w", ".a")
        and value.group("operator") == "*="
    ]
    if (
        alpha_one is None
        or any(
            not statement_end - entry.body_start < value.start() < alpha_one.start()
            for value in rgb_writes
        )
        or (
            alpha_aliases
            and not statement_end - entry.body_start
            < alpha_aliases[0].start()
            < (lowered_flow_start if lowered else rgb_writes[0].start())
        )
        or len(roots) != 1 or len(writes) not in (1, 2)
        or len(alpha_updates) != len(writes) - 1
        or roots[0].start() <= alpha_one.end()
    ):
        raise IndependentSignalContractFailure("independent-producer-flow")
    root_end = body.find(";", roots[0].end())
    if root_end < 0:
        raise IndependentSignalContractFailure("independent-producer-flow")
    root_expression = body[roots[0].end():root_end].strip()
    if (
        re.match(rf"(?:\(\s*)*{carrier_pattern}\b", root_expression) is None
    ):
        raise IndependentSignalContractFailure("independent-producer-flow")
    carrier_writes = re.findall(
        rf"\b{carrier_pattern}\s*\.\s*([xyzwrgba]{{1,4}})\s*"
        r"(\+=|-=|\*=|/=|=(?!=))",
        body,
    )
    normalized_writes = [(member, operator) for member, operator in carrier_writes]
    valid_writes = (
        [("xyz", "*="), ("w", "=")],
        [("rgb", "*="), ("a", "=")],
        [("x", "*="), ("y", "*="), ("z", "*="), ("w", "=")],
        [("r", "*="), ("g", "*="), ("b", "*="), ("a", "=")],
        [("x", "="), ("y", "="), ("z", "="), ("w", "=")],
        [("r", "="), ("g", "="), ("b", "="), ("a", "=")],
    )
    if normalized_writes not in valid_writes:
        raise IndependentSignalContractFailure("independent-producer-flow")

    call = source[whole[0].start:whole[0].end]
    transformed = (
        source[:whole[0].start]
        + f"{_UNPREMULTIPLY}({call})"
        + source[whole[0].end:]
    )
    namespace = re.search(r"\busing\s+namespace\s+metal\s*;", transformed)
    if namespace is None:
        raise IndependentSignalContractFailure("independent-color-boundary")
    helper = f"""

inline float4 {_UNPREMULTIPLY}(float4 color) {{
    const float alpha = clamp(color.w, 0.0, 1.0);
    const float3 rgb = alpha > 0.0
        ? clamp(color.xyz / alpha, float3(0.0), float3(1.0))
        : float3(0.0);
    return float4(rgb, alpha);
}}
"""
    return transformed[:namespace.end()] + helper + transformed[namespace.end():]


def _looks_like_accumulator(source: str) -> bool:
    masked = _mask_comments(source)
    try:
        _, body = _entry(masked)
    except IndependentSignalContractFailure:
        return False
    return (
        len([value for value in _output_writes(body) if value.group("member") is None]) == 1
        and re.search(r"\bfor\s*\(", masked) is not None
        and re.search(r"\bg_Texture[0-7]\s*\.\s*sample\s*\(", masked) is not None
    )


def _strip_parentheses(value: str) -> str:
    result = value.strip()
    while result.startswith("(") and result.endswith(")"):
        end = sample_end(result, 0)
        if end != len(result):
            break
        result = result[1:-1].strip()
    return result


def _interval(expression: str, symbols: dict[str, tuple[float, float]]) -> tuple[float, float] | None:
    normalized = re.sub(r"\b(?:float|int)\s*\(", "(", expression)
    normalized = re.sub(
        r"(?<=\d)[fF]\b|(?<=\.)[fF]\b", "", normalized
    )
    try:
        tree = ast.parse(normalized, mode="eval")
    except SyntaxError:
        return None

    def visit(node: ast.AST) -> tuple[float, float] | None:
        if isinstance(node, ast.Expression):
            return visit(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
            value = float(node.value)
            return (value, value) if math.isfinite(value) else None
        if isinstance(node, ast.Name):
            return symbols.get(node.id)
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            value = visit(node.operand)
            if value is None:
                return None
            return value if isinstance(node.op, ast.UAdd) else (-value[1], -value[0])
        if isinstance(node, ast.BinOp):
            left, right = visit(node.left), visit(node.right)
            if left is None or right is None:
                return None
            if isinstance(node.op, ast.Add):
                return left[0] + right[0], left[1] + right[1]
            if isinstance(node.op, ast.Sub):
                return left[0] - right[1], left[1] - right[0]
            if isinstance(node.op, ast.Mult):
                products = [a * b for a in left for b in right]
                return min(products), max(products)
            if isinstance(node.op, ast.Div):
                if right[0] <= 0 <= right[1]:
                    return None
                quotients = [a / b for a in left for b in right]
                return min(quotients), max(quotients)
        return None

    result = visit(tree)
    if result is None or not all(math.isfinite(value) for value in result):
        return None
    return result


def _validate_accumulator_helper_calls(functions: list[_Function], helper: _Function, source: str) -> None:
    by_name = {value.name: value for value in functions}
    helper_body = source[helper.body_start:helper.body_end]
    called = [
        name for name in by_name
        if re.search(rf"\b{re.escape(name)}\s*\(", helper_body)
    ]
    if helper.name in called:
        raise IndependentSignalContractFailure("independent-accumulator-recursion")
    for name in called:
        auxiliary = by_name[name]
        body = source[auxiliary.body_start:auxiliary.body_end]
        if (
            auxiliary.return_type != "float2"
            or len(re.findall(r"\breturn\b", body)) != 1
            or re.search(
                r"\b(if|else|switch|for|while|do|discard|break|continue|goto)\b|\?",
                body,
            )
            or _samples(body)
            or re.search(r"\bout\s*\.", body)
            or re.search(r"(?<![=!<>+\-*/])=(?!=)", body)
        ):
            raise IndependentSignalContractFailure("independent-accumulator-helper-call")
        nested = [
            candidate for candidate in by_name
            if re.search(rf"\b{re.escape(candidate)}\s*\(", body)
        ]
        if helper.name in nested:
            raise IndependentSignalContractFailure("independent-accumulator-recursion")
        if nested:
            raise IndependentSignalContractFailure("independent-accumulator-helper-call")


def _accumulator_call_carrier(entry_body: str, helper_name: str, helper_count: int) -> str:
    direct = re.findall(
        rf"\b(?P<carrier>[A-Za-z_]\w*)\s*\+=\s*"
        rf"{re.escape(helper_name)}\s*\(",
        entry_body,
    )
    if len(direct) == helper_count and len(set(direct)) == 1:
        return direct[0]
    if direct:
        raise IndependentSignalContractFailure("independent-accumulator-main-flow")

    staged = list(re.finditer(
        rf"\bfloat4\s+(?P<name>[A-Za-z_]\w*)\s*=\s*"
        rf"{re.escape(helper_name)}\s*\([^;]+\)\s*;",
        entry_body,
    ))
    if len(staged) != helper_count:
        raise IndependentSignalContractFailure("independent-accumulator-main-flow")
    carriers: list[str] = []
    for declaration in staged:
        temporary = declaration.group("name")
        updates = re.findall(
            rf"\b([A-Za-z_]\w*)\s*\+=\s*{re.escape(temporary)}\s*;",
            entry_body,
        )
        if (
            len(updates) != 1
            or len(re.findall(rf"\b{re.escape(temporary)}\b", entry_body)) != 2
        ):
            raise IndependentSignalContractFailure("independent-accumulator-main-flow")
        carriers.extend(updates)
    if len(set(carriers)) != 1:
        raise IndependentSignalContractFailure("independent-accumulator-main-flow")
    return carriers[0]


def _accumulator_rgb_write_count(entry_body: str, carrier: str) -> int:
    carrier_pattern = re.escape(carrier)
    packed = list(re.finditer(
        rf"\b{carrier_pattern}\s*\.\s*(?:xyz|rgb)\s*\*=\s*[^;]+;",
        entry_body,
    ))
    snapshots = list(re.finditer(
        rf"\bfloat4\s+(?P<name>[A-Za-z_]\w*)\s*=\s*{carrier_pattern}\s*;",
        entry_body,
    ))
    lowered_count = 0
    if len(snapshots) == 1:
        snapshot = snapshots[0].group("name")
        rgb_declarations = list(re.finditer(
            rf"\bfloat3\s+(?P<name>[A-Za-z_]\w*)\s*=\s*"
            rf"{re.escape(snapshot)}\s*\.\s*(?:xyz|rgb)\s*\*\s*[^;]+;",
            entry_body,
        ))
        if len(rgb_declarations) == 1:
            rgb = rgb_declarations[0].group("name")
            assignments = list(re.finditer(
                rf"\b{carrier_pattern}\s*\.\s*(?P<member>[xyz])\s*=\s*"
                rf"{re.escape(rgb)}\s*\.\s*(?P<source>[xyz])\s*;",
                entry_body,
            ))
            if (
                [value.group("member") for value in assignments] == ["x", "y", "z"]
                and [value.group("source") for value in assignments] == ["x", "y", "z"]
                and len(re.findall(rf"\b{re.escape(snapshot)}\b", entry_body)) == 2
                and len(re.findall(rf"\b{re.escape(rgb)}\b", entry_body)) == 4
            ):
                lowered_count = 3
    if len(packed) == 1 and not snapshots:
        return 1
    if not packed and lowered_count == 3:
        return lowered_count
    if not packed and not snapshots:
        return 0
    raise IndependentSignalContractFailure("independent-accumulator-main-flow")


def independent_signal_accumulator_static_loop_work(
    source: str, *, expected_slot: int, maximum_loop_work: int
) -> int | None:
    if not _looks_like_accumulator(source):
        return None
    masked = _mask_comments(source)
    entry, entry_body = _entry(masked)
    _validate_return_and_output_scope(masked, entry, entry_body)
    if re.search(r"\b(for|if|else|switch|while|do|discard|break|continue|goto)\b", entry_body):
        raise IndependentSignalContractFailure("independent-accumulator-control")
    writes = _output_writes(entry_body)
    if len(writes) != 1 or writes[0].group("member") is not None or writes[0].group("operator") != "=":
        raise IndependentSignalContractFailure("independent-accumulator-output")

    functions = _functions(masked)
    samples = _samples(masked)
    if len(samples) != 1 or samples[0].slot != expected_slot or samples[0].projection is not None:
        raise IndependentSignalContractFailure("independent-accumulator-source")
    owners = [
        value for value in functions
        if value.body_start <= samples[0].start < value.body_end
    ]
    if len(owners) != 1 or owners[0].name == entry.name or owners[0].return_type != "float4":
        raise IndependentSignalContractFailure("independent-accumulator-helper")
    helper = owners[0]
    helper_body = masked[helper.body_start:helper.body_end]
    if re.search(
        r"\b(if|else|switch|while|do|discard|break|continue|goto)\b|\?",
        helper_body,
    ):
        raise IndependentSignalContractFailure("independent-accumulator-control")
    loops = list(re.finditer(
        r"\bfor\s*\(\s*int\s+(?P<index>[A-Za-z_]\w*)\s*=\s*0\s*;\s*"
        r"(?P=index)\s*<\s*(?P<bound>[A-Za-z_]\w*|\d+)\s*;\s*"
        r"(?:(?P=index)\s*\+\+|\+\+\s*(?P=index))\s*\)\s*\{",
        helper_body,
    ))
    if len(loops) != 1 or len(re.findall(r"\bfor\s*\(", masked)) != 1:
        raise IndependentSignalContractFailure("independent-accumulator-loop")
    loop = loops[0]
    opening = helper_body.find("{", loop.start(), loop.end())
    closing = _matching_brace(helper_body, opening)
    if closing is None:
        raise IndependentSignalContractFailure("independent-accumulator-loop")
    loop_body = helper_body[opening + 1:closing]
    if re.search(r"\bfor\s*\(", loop_body):
        raise IndependentSignalContractFailure("independent-accumulator-loop")

    symbols: dict[str, tuple[float, float]] = {}
    prefix = helper_body[:loop.start()]
    for declaration in re.finditer(
        r"(?m)^\s*(?:const\s+)?(?:int|float)\s+"
        r"(?P<name>[A-Za-z_]\w*)\s*=\s*(?P<value>[^;]+)\s*;",
        prefix,
    ):
        value = _interval(declaration.group("value"), symbols)
        if value is not None:
            symbols[declaration.group("name")] = value
    bound_text = loop.group("bound")
    bound_interval = (
        (float(bound_text), float(bound_text))
        if bound_text.isdigit() else symbols.get(bound_text)
    )
    if (
        bound_interval is None or bound_interval[0] != bound_interval[1]
        or int(bound_interval[0]) != bound_interval[0]
        or not 1 <= int(bound_interval[0]) <= 64
    ):
        raise IndependentSignalContractFailure("independent-accumulator-loop")
    bound = int(bound_interval[0])
    index_name = loop.group("index")
    if re.search(
        rf"\b{re.escape(index_name)}\b\s*(?:=|\+=|-=|\*=|/=|\+\+|--)",
        loop_body,
    ):
        raise IndependentSignalContractFailure("independent-accumulator-loop")

    sample_statement_start, sample_statement_end = _statement_bounds(
        helper_body, samples[0].start - helper.body_start
    )
    sample_statement = helper_body[sample_statement_start:sample_statement_end]
    sample_declaration = re.fullmatch(
        r"\s*(?:const\s+)?float4\s+(?P<name>[A-Za-z_]\w*)\s*=\s*"
        r"g_Texture[0-7]\s*\.\s*sample\s*\([^;]+\)\s*;",
        sample_statement,
    )
    if sample_declaration is None:
        raise IndependentSignalContractFailure("independent-accumulator-sample")
    sample_name = sample_declaration.group("name")
    zero_declarations = re.findall(
        r"(?m)^\s*float4\s+([A-Za-z_]\w*)\s*=\s*"
        r"float4\s*\(\s*0(?:\.0+)?[fF]?\s*\)\s*;",
        prefix,
    )
    if len(zero_declarations) != 1:
        raise IndependentSignalContractFailure("independent-accumulator-carrier")
    accumulator = zero_declarations[0]
    updates = list(re.finditer(
        rf"\b{re.escape(accumulator)}\s*\+=\s*(?P<value>[^;]+)\s*;",
        loop_body,
    ))
    if len(updates) != 1:
        raise IndependentSignalContractFailure("independent-accumulator-update")
    update = _strip_parentheses(updates[0].group("value"))
    weighted_sample = re.fullmatch(
        rf"{re.escape(sample_name)}\s*\*\s*(?P<weight>.+)", update
    )
    if weighted_sample is None:
        weighted_sample = re.fullmatch(
            rf"(?P<weight>.+?)\s*\*\s*{re.escape(sample_name)}", update
        )
    if weighted_sample is None:
        raise IndependentSignalContractFailure("independent-accumulator-update")
    weight_symbols = dict(symbols)
    weight_symbols[index_name] = (0.0, float(bound - 1))
    weight = _interval(
        _strip_parentheses(weighted_sample.group("weight")), weight_symbols
    )
    if weight is None or weight[0] < 0:
        raise IndependentSignalContractFailure("independent-accumulator-weight")
    if len(re.findall(rf"\b{re.escape(sample_name)}\b", helper_body)) != 2:
        raise IndependentSignalContractFailure("independent-accumulator-sample")
    if len(re.findall(rf"\b{re.escape(accumulator)}\b", helper_body)) != 3:
        raise IndependentSignalContractFailure("independent-accumulator-carrier")
    returns = re.findall(r"\breturn\s+([A-Za-z_]\w*)\s*;", helper_body)
    if returns != [accumulator] or len(re.findall(r"\breturn\b", helper_body)) != 1:
        raise IndependentSignalContractFailure("independent-accumulator-return")

    _validate_accumulator_helper_calls(functions, helper, masked)
    helper_calls = list(re.finditer(rf"\b{re.escape(helper.name)}\s*\(", entry_body))
    if not 1 <= len(helper_calls) <= 8:
        raise IndependentSignalContractFailure("independent-accumulator-calls")
    for function in functions:
        if function.name in (entry.name, helper.name):
            continue
        body = masked[function.body_start:function.body_end]
        if re.search(rf"\b{re.escape(helper.name)}\s*\(", body):
            raise IndependentSignalContractFailure("independent-accumulator-calls")
    if bound * len(helper_calls) > maximum_loop_work:
        raise IndependentSignalContractFailure("independent-loop-budget")

    main_carrier = _accumulator_call_carrier(entry_body, helper.name, len(helper_calls))
    declarations = re.findall(
        rf"\bfloat4\s+{re.escape(main_carrier)}\s*=\s*"
        r"float4\s*\(\s*0(?:\.0+)?[fF]?\s*\)\s*;",
        entry_body,
    )
    if len(declarations) != 1:
        raise IndependentSignalContractFailure("independent-accumulator-main-flow")
    root_end = entry_body.find(";", writes[0].end())
    output = entry_body[writes[0].end():root_end]
    rgb_uses = len(re.findall(
        rf"\b{re.escape(main_carrier)}\s*\.\s*(?:xyz|rgb)\b", output
    ))
    alpha_uses = len(re.findall(
        rf"\b{re.escape(main_carrier)}\s*\.\s*(?:w|a)\b", output
    ))
    if rgb_uses != 1 or alpha_uses != 1:
        raise IndependentSignalContractFailure("independent-accumulator-output")
    output_without_carrier = re.sub(
        rf"\b{re.escape(main_carrier)}\s*\.\s*(?:xyz|rgb|w|a)\b",
        "",
        output,
    )
    if re.search(r"\.\s*(?:xyz|rgb|w|a)\b", output_without_carrier):
        raise IndependentSignalContractFailure("independent-accumulator-output")
    rgb_write_count = _accumulator_rgb_write_count(entry_body, main_carrier)
    allowed_writes = 1 + len(helper_calls) + rgb_write_count
    all_writes = len(re.findall(
        rf"\b{re.escape(main_carrier)}(?:\s*\.\s*[xyzwrgba]{{1,4}})?\s*"
        r"(?:\+=|-=|\*=|/=|=(?!=))",
        entry_body,
    ))
    if all_writes != allowed_writes:
        raise IndependentSignalContractFailure("independent-accumulator-main-flow")
    return bound * len(helper_calls)
