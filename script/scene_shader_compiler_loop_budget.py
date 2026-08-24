#!/usr/bin/env python3
"""Conservatively prove static work for generic shader artifact loops."""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import Callable


TOKEN = re.compile(
    r"[A-Za-z_]\w*|"
    r"(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?[fF]?|"
    r"\+\+|--|&&|\|\||<=|>=|==|!=|\+=|-=|\*=|/=|%=|"
    r"[{}()\[\];,<>=+\-*/%!]"
)
IDENTIFIER = re.compile(r"[A-Za-z_]\w*\Z")
ASSIGNMENTS = {"=", "+=", "-=", "*=", "/=", "%="}
CONTROLS = {"for", "if", "switch", "while"}


@dataclass(frozen=True)
class _Loop:
    name: str
    variable_type: str
    header_start: int
    header_end: int
    initialization: range
    condition: range
    increment: range
    body: range


@dataclass(frozen=True)
class _Function:
    name: str
    body: range


def _without_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.DOTALL)
    return re.sub(r"//[^\n]*", " ", source)


def _tokenize(source: str) -> list[str]:
    return TOKEN.findall(_without_comments(source))


def _matching(
    tokens: list[str], start: int, opening: str, closing: str
) -> int | None:
    if start >= len(tokens) or tokens[start] != opening:
        return None
    depth = 0
    for index in range(start, len(tokens)):
        if tokens[index] == opening:
            depth += 1
        elif tokens[index] == closing:
            depth -= 1
            if depth == 0:
                return index
    return None


def _split(
    tokens: list[str], token_range: range, separator: str
) -> list[range]:
    result: list[range] = []
    start = token_range.start
    depth = 0
    for index in token_range:
        if tokens[index] in ("(", "["):
            depth += 1
        elif tokens[index] in (")", "]"):
            depth -= 1
        elif depth == 0 and tokens[index] == separator:
            result.append(range(start, index))
            start = index + 1
    result.append(range(start, token_range.stop))
    return result


def _loop_body(tokens: list[str], header_end: int) -> range | None:
    start = header_end + 1
    if start >= len(tokens):
        return None
    if tokens[start] == "{":
        end = _matching(tokens, start, "{", "}")
        return None if end is None else range(start + 1, end)
    depth = 0
    for index in range(start, len(tokens)):
        if tokens[index] in ("(", "["):
            depth += 1
        elif tokens[index] in (")", "]"):
            depth -= 1
        elif depth == 0 and tokens[index] == ";":
            return range(start, index + 1)
    return None


def _parse_loop(tokens: list[str], for_index: int) -> _Loop | None:
    if for_index + 1 >= len(tokens) or tokens[for_index + 1] != "(":
        return None
    header_end = _matching(tokens, for_index + 1, "(", ")")
    if header_end is None:
        return None
    parts = _split(tokens, range(for_index + 2, header_end), ";")
    if len(parts) != 3:
        return None
    initialization = [tokens[index] for index in parts[0]]
    if (
        len(initialization) != 4
        or initialization[0] not in ("int", "float")
        or IDENTIFIER.fullmatch(initialization[1]) is None
        or initialization[2] != "="
        or _integer_value(initialization[3]) != 0
    ):
        return None
    body = _loop_body(tokens, header_end)
    if body is None:
        return None
    return _Loop(
        name=initialization[1],
        variable_type=initialization[0],
        header_start=for_index,
        header_end=header_end,
        initialization=parts[0],
        condition=parts[1],
        increment=parts[2],
        body=body,
    )


def _integer_value(token: str) -> int | None:
    try:
        value = float(token.removesuffix("f").removesuffix("F"))
    except ValueError:
        return None
    if not math.isfinite(value) or value != math.trunc(value):
        return None
    return int(value)


def _is_increment(tokens: list[str], token_range: range, name: str) -> bool:
    values = [tokens[index] for index in token_range]
    return values in ([name, "++"], ["++", name])


def _is_written(tokens: list[str], token_range: range, name: str) -> bool:
    for index in token_range:
        if tokens[index] != name:
            continue
        if index + 1 < token_range.stop and (
            tokens[index + 1] in ASSIGNMENTS or tokens[index + 1] in ("++", "--")
        ):
            return True
        if index > token_range.start and tokens[index - 1] in ("++", "--"):
            return True
    return False


def _functions(tokens: list[str]) -> list[_Function] | None:
    result: list[_Function] = []
    for opening, token in enumerate(tokens):
        if (
            token != "("
            or opening < 2
            or IDENTIFIER.fullmatch(tokens[opening - 1]) is None
            or tokens[opening - 1] in CONTROLS
            or IDENTIFIER.fullmatch(tokens[opening - 2]) is None
        ):
            continue
        closing = _matching(tokens, opening, "(", ")")
        if closing is None or closing + 1 >= len(tokens) or tokens[closing + 1] != "{":
            continue
        body_end = _matching(tokens, closing + 1, "{", "}")
        if body_end is None:
            return None
        result.append(_Function(tokens[opening - 1], range(closing + 2, body_end)))
    if len({function.name for function in result}) != len(result):
        return None
    return result


def _is_passed_to_authored_function(
    tokens: list[str], token_range: range, name: str
) -> bool:
    functions = _functions(tokens)
    if functions is None:
        return True
    names = {function.name for function in functions}
    for index in token_range:
        if (
            tokens[index] not in names
            or index + 1 >= token_range.stop
            or tokens[index + 1] != "("
        ):
            continue
        closing = _matching(tokens, index + 1, "(", ")")
        if closing is None or closing >= token_range.stop:
            return True
        if name in tokens[index + 2 : closing]:
            return True
    return False


def _enclosing_function(tokens: list[str], loop_index: int) -> range | None:
    functions = _functions(tokens)
    if functions is None:
        return None
    candidates = [
        function.body for function in functions if loop_index in function.body
    ]
    if not candidates:
        return None
    return min(candidates, key=len)


def _root_invariant_bound(
    tokens: list[str], function: range, before: int, name: str, expected_type: str
) -> int | None:
    declarations: list[tuple[range, int]] = []
    depth = 0
    index = function.start
    while index < function.stop:
        token = tokens[index]
        if token == "{":
            depth += 1
            index += 1
            continue
        if token == "}":
            depth -= 1
            index += 1
            continue
        type_index = index + 1 if token == "const" else index
        name_index = type_index + 1
        if (
            type_index < function.stop
            and tokens[type_index] == expected_type
            and name_index < function.stop
            and tokens[name_index] == name
        ):
            value_index = name_index + 2
            end = value_index + 2
            if (
                depth != 0
                or end > function.stop
                or tokens[name_index + 1] != "="
                or tokens[value_index + 1] != ";"
            ):
                return None
            value = _integer_value(tokens[value_index])
            if value is None:
                return None
            declarations.append((range(index, end), value))
            index = end
            continue
        index += 1
    if len(declarations) != 1:
        return None
    declaration, value = declarations[0]
    if declaration.start >= before:
        return None
    remainder = range(declaration.stop, function.stop)
    if _is_written(tokens, remainder, name) or _is_passed_to_authored_function(
        tokens, remainder, name
    ):
        return None
    return value


def _bound_value(
    tokens: list[str], loop: _Loop, token: str, *, early_exit: bool
) -> int | None:
    literal = _integer_value(token)
    if literal is not None:
        return literal
    if IDENTIFIER.fullmatch(token) is None:
        return None
    function = _enclosing_function(tokens, loop.header_start)
    if function is None:
        return None
    expected_type = "float" if early_exit else "int"
    return _root_invariant_bound(
        tokens, function, loop.header_start, token, expected_type
    )


def _iterations(tokens: list[str], loop: _Loop) -> int | None:
    if not _is_increment(tokens, loop.increment, loop.name):
        return None
    if _is_written(tokens, loop.body, loop.name) or _is_passed_to_authored_function(
        tokens, loop.body, loop.name
    ):
        return None
    conjuncts = _split(tokens, loop.condition, "&&")
    early_exit = len(conjuncts) >= 2
    if early_exit and loop.variable_type != "float":
        return None
    if not early_exit and loop.variable_type != "int":
        return None
    bound: int | None = None
    for conjunct in conjuncts:
        values = [tokens[index] for index in conjunct]
        if (
            len(values) == 3
            and values[0] == loop.name
            and values[1] == "<"
        ):
            if bound is not None:
                return None
            candidate = _bound_value(
                tokens, loop, values[2], early_exit=early_exit
            )
            if candidate is None:
                return None
            bound = candidate
        elif loop.name in values:
            return None
    return bound


def _loop_call_graph_is_single_shot(
    tokens: list[str], loops: list[_Loop]
) -> bool:
    if not loops:
        return True
    functions = _functions(tokens)
    if functions is None or sum(function.name == "main" for function in functions) != 1:
        return False
    loop_functions: set[str] = set()
    for loop in loops:
        owners = [function for function in functions if loop.header_start in function.body]
        if len(owners) != 1:
            return False
        loop_functions.add(owners[0].name)
    for name in loop_functions - {"main"}:
        calls: list[tuple[str, int]] = []
        for function in functions:
            for index in function.body:
                if (
                    tokens[index] == name
                    and index + 1 < function.body.stop
                    and tokens[index + 1] == "("
                ):
                    calls.append((function.name, index))
        if (
            len(calls) != 1
            or calls[0][0] != "main"
            or any(calls[0][1] in loop.body for loop in loops)
        ):
            return False
    return True


def static_loop_work(
    stage_sources: dict[str, str], failure: Callable[[str], Exception]
) -> int:
    total = 0
    for source in stage_sources.values():
        tokens = _tokenize(source)
        if any(token in ("while", "do") for token in tokens):
            raise failure("loop-unbounded")
        for_indices = [index for index, token in enumerate(tokens) if token == "for"]
        loops = [_parse_loop(tokens, for_index) for for_index in for_indices]
        if any(loop is None for loop in loops):
            raise failure("loop-unbounded")
        parsed_loops = [loop for loop in loops if loop is not None]
        if not _loop_call_graph_is_single_shot(tokens, parsed_loops):
            raise failure("loop-unbounded")
        for loop in parsed_loops:
            if any(
                tokens[index] == "for" for index in loop.body
            ):
                raise failure("loop-unbounded")
            iterations = _iterations(tokens, loop)
            if iterations is None:
                raise failure("loop-unbounded")
            if not 1 <= iterations <= 64:
                raise failure("loop-bound")
            total += iterations
    if total > 256:
        raise failure("loop-budget")
    return total
