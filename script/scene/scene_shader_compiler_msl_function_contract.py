#!/usr/bin/env python3
"""Narrow actual-MSL function and carrier-parameter contract helpers."""

from __future__ import annotations

import math
import re
from dataclasses import dataclass


_SCALAR_TOKEN = re.compile(
    r"\s*(?:(?P<number>(?:\d+(?:\.\d*)?|\.\d+)"
    r"(?:[eE][+-]?\d+)?[fF]?)|(?P<identifier>[A-Za-z_]\w*)|"
    r"(?P<scope>::)|(?P<symbol>[()+\-*/,\.]))"
)


@dataclass(frozen=True)
class _ValueFact:
    kind: str
    ownership: str
    carrier_derived: bool = False


class _ScalarExpressionParser:
    def __init__(
        self,
        expression: str,
        symbols: dict[str, _ValueFact],
        authored: set[str],
    ) -> None:
        self.tokens = self._tokens(expression)
        self.symbols = symbols
        self.authored = authored
        self.cursor = 0

    @staticmethod
    def _tokens(expression: str) -> list[tuple[str, str]] | None:
        result: list[tuple[str, str]] = []
        cursor = 0
        while cursor < len(expression):
            match = _SCALAR_TOKEN.match(expression, cursor)
            if match is None:
                return None if expression[cursor:].strip() else result
            kind = match.lastgroup
            if kind is None:
                return None
            result.append((kind, match.group(kind)))
            cursor = match.end()
        return result

    def parse(self) -> str | None:
        if self.tokens is None:
            return None
        result = self._additive()
        return result if self.cursor == len(self.tokens) else None

    def _additive(self) -> str | None:
        result = self._multiplicative()
        while self._peek("+") or self._peek("-"):
            self.cursor += 1
            right = self._multiplicative()
            if result is None or result != right:
                return None
        return result

    def _multiplicative(self) -> str | None:
        result = self._unary()
        while self._peek("*") or self._peek("/"):
            operator = self.tokens[self.cursor][1] if self.tokens else ""
            self.cursor += 1
            right = self._unary()
            if result is None or right is None:
                return None
            if result == right == "scalar":
                result = "scalar"
            elif result == "vector" and right in ("scalar", "vector"):
                result = "vector"
            elif operator == "*" and result == "scalar" and right == "vector":
                result = "vector"
            else:
                return None
        return result

    def _unary(self) -> str | None:
        if self._peek("+") or self._peek("-"):
            self.cursor += 1
            return self._unary()
        return self._primary()

    def _primary(self) -> str | None:
        if self.tokens is None or self.cursor >= len(self.tokens):
            return None
        kind, value = self.tokens[self.cursor]
        if kind == "number":
            self.cursor += 1
            try:
                return "scalar" if math.isfinite(float(value.rstrip("fF"))) else None
            except ValueError:
                return None
        if value == "(":
            self.cursor += 1
            result = self._additive()
            return result if result is not None and self._consume(")") else None
        if kind != "identifier":
            return None
        self.cursor += 1
        name = value
        if self._consume("::"):
            if self.tokens is None or self.cursor >= len(self.tokens):
                return None
            nested_kind, nested = self.tokens[self.cursor]
            if nested_kind != "identifier":
                return None
            self.cursor += 1
            name = f"{name}::{nested}"
        if self._consume("("):
            arguments: list[str] = []
            while True:
                argument = self._additive()
                if argument is None:
                    return None
                arguments.append(argument)
                if self._consume(")"):
                    break
                if not self._consume(","):
                    return None
            if name.split("::")[-1] in self.authored:
                return None
            if name == "length" and arguments == ["vector"]:
                return "scalar"
            if name in ("step", "min", "fast::min") and arguments == [
                "scalar", "scalar",
            ]:
                return "scalar"
            if name == "float" and arguments == ["scalar"]:
                return "scalar"
            if name in ("float2", "float3") and arguments == [
                "scalar",
            ]:
                return "vector"
            if name == "float4" and arguments == ["scalar"]:
                return "scalar"
            return None
        result = self.symbols.get(name)
        kind = result.kind if result is not None else None
        qualified = name
        while self._consume("."):
            if self.tokens is None or self.cursor >= len(self.tokens):
                return None
            component_kind, component = self.tokens[self.cursor]
            self.cursor += 1
            if component_kind != "identifier":
                return None
            qualified = f"{qualified}.{component}"
            exact = self.symbols.get(qualified)
            if exact is not None:
                kind = exact.kind
                continue
            if kind != "vector" or re.fullmatch(r"[xyzwrgba]{1,4}", component) is None:
                return None
            kind = "scalar" if len(component) == 1 else "vector"
        return kind

    def _peek(self, value: str) -> bool:
        return (
            self.tokens is not None
            and self.cursor < len(self.tokens)
            and self.tokens[self.cursor][1] == value
        )

    def _consume(self, value: str) -> bool:
        if not self._peek(value):
            return False
        self.cursor += 1
        return True


def sample_end(source: str, start: int) -> int | None:
    depth = 0
    for index in range(start, len(source)):
        character = source[index]
        if character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth == 0:
                return index + 1
    return None


def function_body(source: str, name: str) -> str | None:
    match = re.search(rf"\b{re.escape(name)}\s*\(", source)
    if match is None:
        return None
    opening = source.find("(", match.start())
    parameters_end = sample_end(source, opening)
    if parameters_end is None:
        return None
    opening_brace = source.find("{", parameters_end)
    semicolon = source.find(";", parameters_end)
    if opening_brace < 0 or (semicolon >= 0 and semicolon < opening_brace):
        return None
    depth = 0
    for index in range(opening_brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[opening_brace + 1:index]
    return None


def call_arguments(expression: str) -> list[str] | None:
    value = expression.strip()
    match = re.match(r"[A-Za-z_]\w*\s*\(", value)
    if match is None:
        return None
    opening = value.find("(", match.start())
    closing = sample_end(value, opening)
    if closing is None or value[closing:].strip():
        return None
    interior = value[opening + 1:closing - 1]
    arguments: list[str] = []
    start = 0
    depth = 0
    pairs = {"(": ")", "[": "]", "{": "}"}
    closing_tokens = set(pairs.values())
    for index, character in enumerate(interior):
        if character in pairs:
            depth += 1
        elif character in closing_tokens:
            depth -= 1
        elif character == "," and depth == 0:
            argument = interior[start:index].strip()
            if not argument:
                return None
            arguments.append(argument)
            start = index + 1
        if depth < 0:
            return None
    final = interior[start:].strip()
    if depth != 0 or not final:
        return None
    arguments.append(final)
    return arguments


def _authored_function_names(source: str) -> set[str]:
    return set(re.findall(
        r"\b[A-Za-z_]\w*\s+(?P<name>[A-Za-z_]\w*)\s*"
        r"\([^;{}]*\)\s*\{", source
    ))


def _expression_kind(
    expression: str,
    symbols: dict[str, _ValueFact],
    authored: set[str],
) -> str | None:
    return _ScalarExpressionParser(expression, symbols, authored).parse()


def _entry_parameters(source: str) -> tuple[str, str] | None:
    headers = list(re.finditer(
        r"\bfragment\s+(?P<return>[A-Za-z_]\w*)\s+"
        r"mwxGenericFragment\s*\(",
        source,
    ))
    if len(headers) != 1:
        return None
    opening = source.find("(", headers[0].start())
    end = sample_end(source, opening)
    if end is None:
        return None
    return headers[0].group("return"), source[opening + 1:end - 1]


def _structure_fields(source: str, name: str) -> dict[str, str] | None:
    structures = re.findall(
        rf"\bstruct\s+{re.escape(name)}\s*\{{(?P<body>.*?)\}}\s*;",
        source,
        re.DOTALL,
    )
    if len(structures) != 1:
        return None
    fields: dict[str, str] = {}
    for value_type, field in re.findall(
        r"\b(float|int|uint|float[234]|int[234]|uint[234])\s+"
        r"([A-Za-z_]\w*)\s*(?:\[\[[^\]]+\]\])?\s*;",
        structures[0],
    ):
        if field in fields:
            return None
        fields[field] = (
            "scalar" if value_type in ("float", "int", "uint") else "vector"
        )
    return fields


def _entry_value_context(
    source: str,
) -> tuple[str, dict[str, _ValueFact], str] | None:
    entry = _entry_parameters(source)
    if entry is None:
        return None
    return_type, parameter_text = entry
    parameters = call_arguments(f"mwx({parameter_text})")
    if parameters is None:
        return None
    uniforms: list[tuple[str, str]] = []
    stage_inputs: list[tuple[str, str]] = []
    for parameter in parameters:
        uniform = re.fullmatch(
            r"constant\s+(MWXFragmentUniforms)\s*&\s*"
            r"([A-Za-z_]\w*)\s*\[\[\s*buffer\(8\)\s*\]\]",
            parameter.strip(),
        )
        if uniform is not None:
            uniforms.append((uniform.group(1), uniform.group(2)))
            continue
        stage_input = re.fullmatch(
            r"([A-Za-z_]\w*)\s+([A-Za-z_]\w*)\s*"
            r"\[\[\s*stage_in\s*\]\]",
            parameter.strip(),
        )
        if stage_input is not None:
            stage_inputs.append((stage_input.group(1), stage_input.group(2)))
    if len(uniforms) != 1 or len(stage_inputs) > 1:
        return None
    symbols: dict[str, _ValueFact] = {}
    uniform_type, uniform_name = uniforms[0]
    uniform_fields = _structure_fields(source, uniform_type)
    if uniform_fields is None:
        return None
    for field, kind in uniform_fields.items():
        symbols[f"{uniform_name}.{field}"] = _ValueFact(kind, "uniform")
    if stage_inputs:
        input_type, input_name = stage_inputs[0]
        input_fields = _structure_fields(source, input_type)
        if input_fields is None:
            return None
        for field, kind in input_fields.items():
            symbols[f"{input_name}.{field}"] = _ValueFact(kind, "host")
    return return_type, symbols, uniform_name


def _rgb_scalar_declaration(
    statement: str,
    carrier: str,
    symbols: dict[str, _ValueFact],
    authored: set[str],
) -> str | None:
    declaration = re.fullmatch(
        r"(?:const\s+)?float\s+(?P<name>[A-Za-z_]\w*)\s*=\s*"
        r"(?P<expression>.+)",
        statement.strip(),
        re.DOTALL,
    )
    if declaration is None or len(re.findall(
        rf"\b{re.escape(carrier)}\b", declaration.group("expression")
    )) != 1:
        return None
    expression = declaration.group("expression").strip()
    depth = 0
    split = None
    for index, character in enumerate(expression):
        if character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
        elif character in "*/" and depth == 0:
            split = index
            break
        if depth < 0:
            return None
    if depth != 0:
        return None
    step_expression = expression if split is None else expression[:split].strip()
    factor = None if split is None else expression[split + 1:].strip()
    step_arguments = call_arguments(step_expression)
    if (
        step_arguments is None
        or re.match(r"\s*step\s*\(", step_expression) is None
        or len(step_arguments) != 2
        or "step" in authored
        or "length" in authored
        or re.fullmatch(
            rf"\s*length\s*\(\s*{re.escape(carrier)}\s*\.\s*"
            r"(?:xyz|rgb)\s*\)\s*",
            step_arguments[0],
        ) is None
        or _expression_kind(step_arguments[1], symbols, authored) != "scalar"
        or (
            factor is not None
            and _expression_kind(factor, symbols, authored) != "scalar"
        )
    ):
        return None
    return declaration.group("name")


def _sample_value(
    expression: str,
    symbols: dict[str, _ValueFact],
    authored: set[str],
) -> tuple[int, str] | None:
    value = expression.strip()
    match = re.match(
        r"g_Texture(?P<slot>[0-7])\s*\.\s*sample\s*\(", value
    )
    if match is None:
        return None
    opening = value.find("(", match.start())
    end = sample_end(value, opening)
    if end is None:
        return None
    arguments = call_arguments(f"sample{value[opening:end]}")
    if (
        arguments is None
        or len(arguments) != 2
        or _expression_kind(arguments[1], symbols, authored) != "vector"
    ):
        return None
    suffix = value[end:].strip()
    if not suffix:
        return int(match.group("slot")), "whole"
    projection = re.fullmatch(r"\.\s*(xy|rg)", suffix)
    if projection is None:
        return None
    return int(match.group("slot")), "vector"


def _numeric_declaration(statement: str) -> re.Match[str] | None:
    return re.fullmatch(
        r"(?:const\s+)?(?P<type>float|int|uint|float[234]|int[234]|uint[234])"
        r"\s+(?P<name>[A-Za-z_]\w*)\s*=\s*(?P<rhs>.+)",
        statement.strip(),
        re.DOTALL,
    )


def _shadow_symbol(symbols: dict[str, _ValueFact], name: str) -> None:
    symbols.pop(name, None)
    for qualified in [key for key in symbols if key.startswith(f"{name}.")]:
        symbols.pop(qualified, None)


def _call_is_whitelisted(
    callee: str,
    arguments: list[str],
    authored: set[str],
) -> bool:
    leaf = callee.split("::")[-1]
    if leaf in authored:
        return False
    arities = {
        "length": 1,
        "step": 2,
        "min": 2,
        "fast::min": 2,
        "float": 1,
        "float2": 1,
        "float3": 1,
        "float4": 1,
        "sample": 2,
        "sampler": 0,
    }
    if "::" in callee and callee != "fast::min":
        return False
    return arities.get(callee if "::" in callee else leaf) == len(arguments)


def _calls(statement: str) -> list[tuple[str, list[str], int, int]] | None:
    result: list[tuple[str, list[str], int, int]] = []
    for match in re.finditer(
        r"(?P<name>[A-Za-z_]\w*(?:::[A-Za-z_]\w*)?)\s*\(", statement
    ):
        opening = statement.find("(", match.start())
        end = sample_end(statement, opening)
        if end is None:
            return None
        interior = statement[opening + 1:end - 1]
        if interior.strip():
            arguments = call_arguments(f"mwx{statement[opening:end]}")
            if arguments is None:
                return None
        else:
            arguments = []
        result.append((match.group("name"), arguments, match.start(), end))
    return result


def _symbol_has_unsafe_use(
    statement: str,
    name: str,
    authored: set[str],
) -> bool:
    root = rf"(?:\(\s*)*\b{re.escape(name)}\b(?:\s*\))*"
    chain = r"(?:\s*\.\s*[A-Za-z_]\w*|\s*\[[^\]]+\])*"
    operator = r"(?:\+\+|--|\+=|-=|\*=|/=|=(?!=))"
    if re.search(rf"{root}\s*{chain}\s*{operator}", statement) is not None:
        return True
    if re.search(rf"(?:\+\+|--)\s*{root}\s*{chain}", statement) is not None:
        return True
    calls = _calls(statement)
    if calls is None:
        return True
    for callee, arguments, _, _ in calls:
        if not any(re.search(rf"\b{re.escape(name)}\b", value) for value in arguments):
            continue
        if not _call_is_whitelisted(callee, arguments, authored):
            return True
    return False


def _contains_unproven_call(statement: str, authored: set[str]) -> bool:
    calls = _calls(statement)
    return calls is None or any(
        not _call_is_whitelisted(callee, arguments, authored)
        for callee, arguments, _, _ in calls
    )


def safe_initial_carrier_flow(
    source: str,
    prefix: str,
    carrier: str,
    initial_expression: str,
) -> bool:
    """Proves ordered carrier and scalar/vector provenance to the first write."""
    authored = _authored_function_names(source)
    context = _entry_value_context(source)
    if context is None:
        return False
    return_type, symbols, uniform_name = context
    declarations: set[str] = set()
    carrier_declared = False
    for match in re.finditer(r"(?P<statement>[^;]*);", prefix, re.DOTALL):
        statement = match.group("statement").strip()
        if not statement:
            continue
        declaration = _numeric_declaration(statement)
        if declaration is not None:
            name = declaration.group("name")
            _shadow_symbol(symbols, name)
            if name in declarations:
                return False
            declarations.add(name)
        for name, fact in list(symbols.items()):
            if fact.ownership == "local" and _symbol_has_unsafe_use(
                statement, name, authored
            ):
                return False
        carrier_uses = len(re.findall(rf"\b{re.escape(carrier)}\b", statement))
        if carrier_uses:
            carrier_sample = (
                _sample_value(declaration.group("rhs"), symbols, authored)
                if declaration is not None else None
            )
            if (
                declaration is not None
                and declaration.group("type") == "float4"
                and declaration.group("name") == carrier
                and carrier_uses == 1
                and carrier_sample is not None
                and carrier_sample[1] == "whole"
                and not carrier_declared
            ):
                carrier_declared = True
                continue
            rgb_name = _rgb_scalar_declaration(
                statement, carrier, symbols, authored
            )
            if (
                rgb_name is not None
                and declaration is not None
                and rgb_name == declaration.group("name")
            ):
                symbols[rgb_name] = _ValueFact(
                    "scalar", "local", carrier_derived=True
                )
                continue
            mutation = re.fullmatch(
                rf"{re.escape(carrier)}\s*(?:\*=|/=)\s*(?P<rhs>.+)",
                statement,
                re.DOTALL,
            )
            if (
                carrier_uses != 1
                or mutation is None
                or _expression_kind(
                    mutation.group("rhs"), symbols, authored
                ) != "scalar"
            ):
                return False
            continue
        if declaration is not None:
            name = declaration.group("name")
            expected_kind = (
                "scalar"
                if declaration.group("type") in ("float", "int", "uint")
                else "vector"
            )
            value_kind = _expression_kind(
                declaration.group("rhs"), symbols, authored
            )
            if value_kind != expected_kind and expected_kind == "vector":
                sampled = _sample_value(
                    declaration.group("rhs"), symbols, authored
                )
                value_kind = sampled[1] if sampled is not None else None
            if value_kind != expected_kind:
                return False
            symbols[name] = _ValueFact(value_kind, "local")
            continue
        if re.fullmatch(
            rf"{re.escape(return_type)}\s+out(?:\s*=\s*\{{\s*\}})?",
            statement,
        ) is not None:
            continue
        if (
            _contains_unproven_call(statement, authored)
            or re.search(r"(?:\+\+|--|\+=|-=|\*=|/=|=(?!=))", statement)
            is not None
            or re.search(rf"\b{re.escape(uniform_name)}\b", statement)
            is not None
        ):
            return False

    if not carrier_declared:
        return False
    initial = initial_expression.strip()
    if initial == carrier:
        return True
    transformed = re.fullmatch(
        rf"{re.escape(carrier)}\s*[*/]\s*(?P<scalar>.+)",
        initial,
        re.DOTALL,
    )
    return (
        transformed is not None
        and len(re.findall(rf"\b{re.escape(carrier)}\b", initial)) == 1
        and _expression_kind(
            transformed.group("scalar"), symbols, authored
        ) == "scalar"
    )


def safe_carrier_parameter(
    source: str,
    callee: str,
    arguments: list[str],
    carrier_index: int,
    require_const_reference: bool,
) -> bool:
    headers = re.findall(
        rf"\b(?P<return>[A-Za-z_]\w*)\s+{re.escape(callee)}"
        rf"\s*\((?P<parameters>[^;{{}}]*)\)\s*\{{", source
    )
    parsed = call_arguments(f"mwx({headers[0][1]})") if len(headers) == 1 else None
    if parsed is None or headers[0][0] != "float4" or len(parsed) != len(arguments):
        return False
    parameter = parsed[carrier_index] if carrier_index < len(parsed) else ""
    safe = re.fullmatch(
        r"(?:(?P<value>float4)\s+|thread\s+const\s+float4\s*&\s*)"
        r"(?P<name>[A-Za-z_]\w*)", parameter
    )
    if safe is None or (require_const_reference and safe.group("value") is not None):
        return False
    if safe.group("value") is not None:
        return True
    body = function_body(source, callee)
    if body is None or re.search(
        rf"(?:\b(?:const|reinterpret|static)_cast\b|&[^;]*)"
        rf"[^;]*\b{re.escape(safe.group('name'))}\b", body
    ) is not None:
        return False
    authored = set(re.findall(
        r"\b[A-Za-z_]\w*\s+(?P<name>[A-Za-z_]\w*)\s*"
        r"\([^;{}]*\)\s*\{", source
    ))
    # The fixed backend's proven root helper is leaf-shaped. Rejecting every
    # authored nested call also rejects transitive escapes and all cycles
    # without creating a second carrier-dataflow analyzer here.
    return not any(
        name in authored
        for name in re.findall(r"\b([A-Za-z_]\w*)\s*\(", body)
    )
