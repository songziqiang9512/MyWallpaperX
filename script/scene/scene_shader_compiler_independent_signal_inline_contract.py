#!/usr/bin/env python3
"""Bounded external-MSL proof for direct-entry independent RGBA accumulators."""

from __future__ import annotations

import ast
import math
import re
from collections import Counter
from dataclasses import dataclass

from scene_shader_compiler_msl_function_contract import sample_end


class InlineAccumulatorNotApplicable(RuntimeError):
    """The artifact is not a direct-entry accumulator and may use another proof."""


class InlineAccumulatorContractFailure(RuntimeError):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


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


def numeric_interval(
    expression: str,
    symbols: dict[str, tuple[float, float]],
) -> tuple[float, float] | None:
    """Evaluate a side-effect-free numeric expression over known intervals."""
    normalized = re.sub(r"\b(?:float|int)\s*\(", "(", expression)
    normalized = re.sub(r"(?<=\d)[fF]\b|(?<=\.)[fF]\b", "", normalized)
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


def _fail(code: str) -> None:
    raise InlineAccumulatorContractFailure(code)


def _mask_comments(source: str) -> str:
    def mask(match: re.Match[str]) -> str:
        return "".join("\n" if value == "\n" else " " for value in match.group(0))

    return re.sub(r"/\*.*?\*/|//[^\n]*", mask, source, flags=re.DOTALL)


def _matching(source: str, opening: int, left: str, right: str) -> int | None:
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == left:
            depth += 1
        elif source[index] == right:
            depth -= 1
            if depth == 0:
                return index
    return None


def _functions(source: str) -> list[_Function]:
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
    result: list[_Function] = []
    for match in pattern.finditer(search_source):
        opening = search_source.find("{", match.start(), match.end())
        closing = _matching(search_source, opening, "{", "}")
        if closing is None:
            _fail("independent-accumulator-function")
        result.append(_Function(
            name=match.group("name"),
            return_type=match.group("return").strip(),
            body_start=opening + 1,
            body_end=closing,
        ))
    if len({value.name for value in result}) != len(result):
        _fail("independent-accumulator-function")
    return result


def _entry_candidate(source: str) -> tuple[_Function, str]:
    functions = _functions(source)
    entries = [value for value in functions if value.name == "mwxGenericFragment"]
    if len(entries) != 1:
        raise InlineAccumulatorNotApplicable()
    entry = entries[0]
    body = source[entry.body_start:entry.body_end]
    if (
        re.search(r"\bfor\s*\(", body) is None
        or re.search(r"\bg_Texture[0-7]\s*\.\s*sample\s*\(", body) is None
    ):
        raise InlineAccumulatorNotApplicable()
    return entry, body


def _validate_output_carrier(source: str, entry: _Function, body: str) -> re.Match[str]:
    structures = re.findall(
        rf"\bstruct\s+{re.escape(entry.return_type)}\s*\{{(?P<body>.*?)\}}\s*;",
        source,
        re.DOTALL,
    )
    if len(structures) != 1:
        _fail("independent-accumulator-output")
    attachments = re.findall(
        r"\bfloat4\s+([A-Za-z_]\w*)\s*"
        r"\[\[\s*color\((\d+)\)\s*\]\]\s*;",
        structures[0],
    )
    if attachments != [("mwxFragColor", "0")]:
        _fail("independent-accumulator-output")
    declarations = re.findall(
        rf"\b{re.escape(entry.return_type)}\s+out\s*=\s*\{{\s*\}}\s*;",
        body,
    )
    writes = list(re.finditer(
        r"\bout\.mwxFragColor(?P<member>\s*\.\s*[xyzwrgba]{1,4})?\s*"
        r"(?P<operator>\+=|-=|\*=|/=|=(?!=))",
        body,
    ))
    roots = [value for value in writes if value.group("member") is None]
    returns = list(re.finditer(r"\breturn\s+out\s*;", body))
    if (
        len(declarations) != 1
        or len(writes) != 1
        or len(roots) != 1
        or roots[0].group("operator") != "="
        or len(returns) != 1
        or len(re.findall(r"\breturn\b", body)) != 1
        or len(re.findall(r"\bout\b", body)) != 3
        or roots[0].start() >= returns[0].start()
    ):
        _fail("independent-accumulator-output")
    outside = source[:entry.body_start] + source[entry.body_end:]
    if re.search(r"\bout\.mwxFragColor\b", outside):
        _fail("independent-accumulator-output")
    return roots[0]


def _samples(source: str) -> list[_Sample]:
    result: list[_Sample] = []
    for match in re.finditer(r"\bg_Texture(?P<slot>[0-7])\s*\.\s*sample\s*\(", source):
        opening = source.find("(", match.start())
        closing = sample_end(source, opening)
        if closing is None:
            _fail("independent-accumulator-source")
        projection = re.match(r"\s*\.\s*(?P<value>[A-Za-z_]\w*)", source[closing:])
        result.append(_Sample(
            start=match.start(),
            end=closing,
            slot=int(match.group("slot")),
            projection=projection.group("value") if projection else None,
        ))
    return result


def _statement_bounds(source: str, index: int) -> tuple[int, int]:
    start = max(source.rfind(";", 0, index), source.rfind("{", 0, index)) + 1
    end = source.find(";", index)
    if end < 0:
        _fail("independent-accumulator-source")
    return start, end + 1


def _strip_parentheses(value: str) -> str:
    result = value.strip()
    while result.startswith("(") and result.endswith(")"):
        closing = _matching(result, 0, "(", ")")
        if closing != len(result) - 1:
            break
        result = result[1:-1].strip()
    return result


def _split_top_level(value: str, separator: str) -> list[str] | None:
    result: list[str] = []
    start = 0
    stack: list[str] = []
    closing = {")": "(", "]": "[", "}": "{"}
    for index, character in enumerate(value):
        if character in "([{":
            stack.append(character)
        elif character in closing:
            if not stack or stack[-1] != closing[character]:
                return None
            stack.pop()
        elif character == separator and not stack:
            if not value[start:index].strip():
                return None
            result.append(value[start:index].strip())
            start = index + 1
    if stack or not value[start:].strip():
        return None
    result.append(value[start:].strip())
    return result


def _numeric_literal(value: str) -> float | None:
    interval = numeric_interval(_strip_parentheses(value), {})
    if interval is None or interval[0] != interval[1]:
        return None
    return interval[0]


def _static_symbols(prefix: str) -> dict[str, tuple[float, float]]:
    symbols: dict[str, tuple[float, float]] = {}
    for declaration in re.finditer(
        r"(?m)^\s*const\s+(?:int|float)\s+(?P<name>[A-Za-z_]\w*)\s*=\s*"
        r"(?P<value>[^;]+)\s*;",
        prefix,
    ):
        value = numeric_interval(declaration.group("value"), symbols)
        if value is not None:
            symbols[declaration.group("name")] = value
    return symbols


def _validate_weight(
    update: str,
    sample: str,
    index: str,
    bound: int,
    symbols: dict[str, tuple[float, float]],
) -> None:
    factors = _split_top_level(_strip_parentheses(update), "*")
    if factors is None or len(factors) != 2:
        _fail("independent-accumulator-update")
    sample_factors = [value for value in factors if _strip_parentheses(value) == sample]
    weights = [value for value in factors if _strip_parentheses(value) != sample]
    if len(sample_factors) != 1 or len(weights) != 1:
        _fail("independent-accumulator-update")
    weight = _strip_parentheses(weights[0])
    division = _split_top_level(weight, "/")
    if division is None or len(division) != 2:
        _fail("independent-accumulator-weight")
    numerator = _strip_parentheses(division[0])
    if re.fullmatch(rf"(?:float\s*\(\s*)?{re.escape(index)}\s*\)?", numerator) is None:
        _fail("independent-accumulator-weight")
    denominator = numeric_interval(_strip_parentheses(division[1]), symbols)
    if denominator != (float(bound - 1), float(bound - 1)):
        _fail("independent-accumulator-weight")
    weight_symbols = dict(symbols)
    weight_symbols[index] = (0.0, float(bound - 1))
    interval = numeric_interval(weight, weight_symbols)
    if interval is None or interval[0] < 0 or interval[1] > 1:
        _fail("independent-accumulator-weight")


def _validate_called_functions(
    source: str,
    functions: list[_Function],
    entry: _Function,
    body: str,
) -> None:
    by_name = {value.name: value for value in functions}
    called = [name for name in by_name if name != entry.name and re.search(
        rf"\b{re.escape(name)}\s*\(", body
    )]
    for name in called:
        auxiliary = by_name[name]
        auxiliary_body = source[auxiliary.body_start:auxiliary.body_end]
        nested = [candidate for candidate in by_name if re.search(
            rf"\b{re.escape(candidate)}\s*\(", auxiliary_body
        )]
        if (
            auxiliary.return_type not in {"float", "float2", "float3", "float4"}
            or len(re.findall(r"\breturn\b", auxiliary_body)) != 1
            or re.search(
                r"\b(if|else|switch|for|while|do|discard|break|continue|goto)\b|\?",
                auxiliary_body,
            )
            or _samples(auxiliary_body)
            or re.search(r"(?<![=!<>+\-*/])=(?!=)", auxiliary_body)
            or name in nested
            or nested
        ):
            _fail("independent-accumulator-helper-call")


def _tint_write_count(body: str, carrier: str, source: str) -> int:
    carrier_pattern = re.escape(carrier)
    packed = list(re.finditer(
        rf"\b{carrier_pattern}\s*\.\s*(?:xyz|rgb)\s*\*=\s*"
        r"(?P<tint>[^;]+)\s*;",
        body,
    ))
    snapshots = list(re.finditer(
        rf"\bfloat4\s+(?P<name>[A-Za-z_]\w*)\s*=\s*{carrier_pattern}\s*;",
        body,
    ))
    if (
        len(packed) == 1
        and not snapshots
        and _is_rgb_tint(packed[0].group("tint"), source)
    ):
        return 1
    if packed or len(snapshots) != 1:
        _fail("independent-accumulator-tint")
    snapshot = snapshots[0].group("name")
    declarations = list(re.finditer(
        rf"\bfloat3\s+(?P<name>[A-Za-z_]\w*)\s*=\s*"
        rf"{re.escape(snapshot)}\s*\.\s*(?:xyz|rgb)\s*\*\s*"
        r"(?P<tint>[^;]+)\s*;",
        body,
    ))
    if (
        len(declarations) != 1
        or not _is_rgb_tint(declarations[0].group("tint"), source)
    ):
        _fail("independent-accumulator-tint")
    rgb = declarations[0].group("name")
    assignments = list(re.finditer(
        rf"\b{carrier_pattern}\s*\.\s*(?P<member>[xyz])\s*=\s*"
        rf"{re.escape(rgb)}\s*\.\s*(?P<source>[xyz])\s*;",
        body,
    ))
    if (
        [value.group("member") for value in assignments] != ["x", "y", "z"]
        or [value.group("source") for value in assignments] != ["x", "y", "z"]
        or len(re.findall(rf"\b{re.escape(snapshot)}\b", body)) != 2
        or len(re.findall(rf"\b{re.escape(rgb)}\b", body)) != 4
    ):
        _fail("independent-accumulator-tint")
    return 3


def _is_rgb_tint(expression: str, source: str) -> bool:
    value = _strip_parentheses(expression)
    constructor = re.fullmatch(r"float3\s*\((?P<value>.+)\)", value)
    if constructor is not None:
        value = _strip_parentheses(constructor.group("value"))
    identity = re.fullmatch(
        r"(?:[A-Za-z_]\w*|[A-Za-z_]\w*\s*\.\s*[A-Za-z_]\w*)",
        value,
    )
    if identity is None:
        return False
    field = re.split(r"\s*\.\s*", identity.group(0))[-1]
    return len(re.findall(rf"\bfloat3\s+{re.escape(field)}\b", source)) == 1


def _output_expression(body: str, write: re.Match[str]) -> str:
    start = write.end()
    depth = 0
    for index in range(start, len(body)):
        character = body[index]
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
            if depth < 0:
                _fail("independent-accumulator-output")
        elif character == ";" and depth == 0:
            return body[start:index].strip()
    _fail("independent-accumulator-output")


def _constructor_arguments(expression: str, constructor: str) -> list[str]:
    value = _strip_parentheses(expression)
    match = re.match(rf"{re.escape(constructor)}\s*\(", value)
    if match is None:
        _fail("independent-accumulator-output")
    opening = value.find("(", match.start())
    closing = _matching(value, opening, "(", ")")
    if closing != len(value) - 1:
        _fail("independent-accumulator-output")
    arguments = _split_top_level(value[opening + 1:closing], ",")
    if arguments is None:
        _fail("independent-accumulator-output")
    return arguments


def _clamped_alpha(expression: str) -> str:
    value = _strip_parentheses(expression)
    saturate = re.match(r"(?:metal\s*::\s*)?saturate\s*\(", value)
    if saturate is not None:
        opening = value.find("(", saturate.start())
        closing = _matching(value, opening, "(", ")")
        if closing != len(value) - 1:
            _fail("independent-accumulator-alpha")
        arguments = _split_top_level(value[opening + 1:closing], ",")
        if arguments is None or len(arguments) != 1:
            _fail("independent-accumulator-alpha")
        return arguments[0]
    match = re.match(
        r"(?:(?:metal\s*::\s*)?(?:fast\s*::\s*)?)clamp\s*\(",
        value,
    )
    if match is None:
        _fail("independent-accumulator-alpha")
    opening = value.find("(", match.start())
    closing = _matching(value, opening, "(", ")")
    if closing != len(value) - 1:
        _fail("independent-accumulator-alpha")
    arguments = _split_top_level(value[opening + 1:closing], ",")
    if (
        arguments is None
        or len(arguments) != 3
        or _numeric_literal(arguments[1]) != 0
        or _numeric_literal(arguments[2]) != 1
    ):
        _fail("independent-accumulator-alpha")
    return arguments[0]


def _carrier_factors(expression: str, carrier: str, members: set[str]) -> Counter[str]:
    factors = _split_top_level(_strip_parentheses(expression), "*")
    if factors is None:
        _fail("independent-accumulator-output")
    carrier_pattern = re.compile(
        rf"^{re.escape(carrier)}\s*\.\s*(?:{'|'.join(sorted(members))})$"
    )
    carrier_factors = [value for value in factors if carrier_pattern.fullmatch(
        _strip_parentheses(value)
    )]
    if len(carrier_factors) != 1:
        _fail("independent-accumulator-output")
    remaining = [
        re.sub(r"\s+", "", _strip_parentheses(value))
        for value in factors
        if carrier_pattern.fullmatch(_strip_parentheses(value)) is None
    ]
    if not remaining or any(
        re.fullmatch(
            r"(?:[+]?(?:\d+(?:\.\d*)?|\.\d+)[fF]?|"
            r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)",
            value,
        ) is None
        for value in remaining
    ):
        _fail("independent-accumulator-output")
    return Counter(remaining)


def validate_rgba8_unorm_whole_carrier_output(
    expression: str,
    carrier: str,
) -> None:
    """Prove one whole carrier scaled only by simple scalar facts."""
    factors = _flattened_product(expression)
    if factors is None:
        _fail("independent-accumulator-output")
    carrier_pattern = re.compile(rf"^{re.escape(carrier)}$")
    carrier_factors = [
        value for value in factors
        if carrier_pattern.fullmatch(_strip_parentheses(value))
    ]
    remaining = [
        re.sub(r"\s+", "", _strip_parentheses(value))
        for value in factors
        if carrier_pattern.fullmatch(_strip_parentheses(value)) is None
    ]
    if len(carrier_factors) != 1 or not remaining or any(
        re.fullmatch(
            r"(?:[+]?(?:\d+(?:\.\d*)?|\.\d+)[fF]?|"
            r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)",
            value,
        ) is None
        for value in remaining
    ):
        _fail("independent-accumulator-output")


def _flattened_product(expression: str) -> list[str] | None:
    value = _strip_parentheses(expression)
    factors = _split_top_level(value, "*")
    if factors is None:
        return None
    if len(factors) == 1:
        return [value]
    result: list[str] = []
    for factor in factors:
        nested = _flattened_product(factor)
        if nested is None:
            return None
        result.extend(nested)
    return result


def _validate_output_expression(
    expression: str,
    carrier: str,
    *,
    uses_rgba8_unorm_attachment_boundary: bool,
) -> None:
    if uses_rgba8_unorm_attachment_boundary:
        validate_rgba8_unorm_whole_carrier_output(expression, carrier)
        return
    arguments = _constructor_arguments(expression, "float4")
    if len(arguments) != 2:
        _fail("independent-accumulator-output")
    rgb = _carrier_factors(arguments[0], carrier, {"rgb", "xyz"})
    alpha = _carrier_factors(_clamped_alpha(arguments[1]), carrier, {"a", "w"})
    if rgb != alpha:
        _fail("independent-accumulator-output")


def inline_accumulator_static_loop_work(
    source: str,
    *,
    expected_slot: int,
    maximum_loop_work: int,
    uses_rgba8_unorm_attachment_boundary: bool = False,
) -> int:
    """Prove one direct-entry independent-signal loop, or report not-applicable."""
    masked = _mask_comments(source)
    entry, body = _entry_candidate(masked)
    write = _validate_output_carrier(masked, entry, body)
    if re.search(
        r"\b(if|else|switch|while|do|discard|break|continue|goto)\b|\?",
        body,
    ):
        _fail("independent-accumulator-control")

    functions = _functions(masked)
    _validate_called_functions(masked, functions, entry, body)
    samples = _samples(masked)
    if (
        len(samples) != 1
        or samples[0].slot != expected_slot
        or samples[0].projection is not None
        or not entry.body_start <= samples[0].start < entry.body_end
    ):
        _fail("independent-accumulator-source")

    loops = list(re.finditer(
        r"\bfor\s*\(\s*int\s+(?P<index>[A-Za-z_]\w*)\s*=\s*0\s*;\s*"
        r"(?P=index)\s*<\s*(?P<bound>[A-Za-z_]\w*|\d+)\s*;\s*"
        r"(?:(?P=index)\s*\+\+|\+\+\s*(?P=index))\s*\)\s*\{",
        body,
    ))
    if len(loops) != 1 or len(re.findall(r"\bfor\s*\(", masked)) != 1:
        _fail("independent-accumulator-loop")
    loop = loops[0]
    opening = body.find("{", loop.start(), loop.end())
    closing = _matching(body, opening, "{", "}")
    if closing is None:
        _fail("independent-accumulator-loop")
    loop_body = body[opening + 1:closing]
    if re.search(r"\bfor\s*\(", loop_body):
        _fail("independent-accumulator-loop")

    prefix = body[:loop.start()]
    symbols = _static_symbols(prefix)
    bound_text = loop.group("bound")
    bound_interval = (
        (float(bound_text), float(bound_text))
        if bound_text.isdigit()
        else symbols.get(bound_text)
    )
    if (
        bound_interval is None
        or bound_interval[0] != bound_interval[1]
        or int(bound_interval[0]) != bound_interval[0]
        or not 2 <= int(bound_interval[0]) <= 64
    ):
        _fail("independent-accumulator-loop")
    bound = int(bound_interval[0])
    if bound > maximum_loop_work:
        _fail("independent-loop-budget")
    index = loop.group("index")
    if re.search(
        rf"\b{re.escape(index)}\b\s*(?:=|\+=|-=|\*=|/=|\+\+|--)",
        loop_body,
    ):
        _fail("independent-accumulator-loop")

    sample_start, sample_end_position = _statement_bounds(
        body,
        samples[0].start - entry.body_start,
    )
    if not opening < sample_start < sample_end_position <= closing:
        _fail("independent-accumulator-sample")
    sample_statement = body[sample_start:sample_end_position]
    sample_declaration = re.fullmatch(
        r"\s*(?:const\s+)?float4\s+(?P<name>[A-Za-z_]\w*)\s*=\s*"
        r"g_Texture[0-7]\s*\.\s*sample\s*\([^;]+\)\s*;",
        sample_statement,
    )
    if sample_declaration is None:
        _fail("independent-accumulator-sample")
    sample = sample_declaration.group("name")
    zero_declarations = re.findall(
        r"(?m)^\s*float4\s+([A-Za-z_]\w*)\s*=\s*"
        r"float4\s*\(\s*0(?:\.0+)?[fF]?\s*\)\s*;",
        prefix,
    )
    if len(zero_declarations) != 1:
        _fail("independent-accumulator-carrier")
    carrier = zero_declarations[0]
    updates = list(re.finditer(
        rf"\b{re.escape(carrier)}\s*\+=\s*(?P<value>[^;]+)\s*;",
        loop_body,
    ))
    if len(updates) != 1:
        _fail("independent-accumulator-update")
    if sample_end_position > opening + 1 + updates[0].start():
        _fail("independent-accumulator-update")
    _validate_weight(updates[0].group("value"), sample, index, bound, symbols)
    if len(re.findall(rf"\b{re.escape(sample)}\b", body)) != 2:
        _fail("independent-accumulator-sample")

    if write.start() <= closing:
        _fail("independent-accumulator-output")
    tint_writes = _tint_write_count(
        body[closing + 1:write.start()],
        carrier,
        masked,
    )
    all_writes = len(re.findall(
        rf"\b{re.escape(carrier)}(?:\s*\.\s*[xyzwrgba]{{1,4}})?\s*"
        r"(?:\+=|-=|\*=|/=|=(?!=))",
        body,
    ))
    if all_writes != 2 + tint_writes:
        _fail("independent-accumulator-carrier")
    expected_uses = 5 if tint_writes == 1 else 8
    if uses_rgba8_unorm_attachment_boundary:
        expected_uses -= 1
    if len(re.findall(rf"\b{re.escape(carrier)}\b", body)) != expected_uses:
        _fail("independent-accumulator-carrier")
    output = _output_expression(body, write)
    _validate_output_expression(
        output,
        carrier,
        uses_rgba8_unorm_attachment_boundary=
            uses_rgba8_unorm_attachment_boundary,
    )
    return bound
