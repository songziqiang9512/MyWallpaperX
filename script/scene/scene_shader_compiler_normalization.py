"""Normalize source pairs for the offline shader compiler harness."""

from __future__ import annotations

import re
from itertools import accumulate
from typing import Any

from scene_shader_compiler_request_contract import ALLOWED_STAGES, uses_source_raster_projection
from scene_shader_compiler_texture_sampling import shader_compatibility_lines, texture_sampling_support_lines


ALLOWED_DIALECTS = ("glsl-450", "wallpaper-engine-glsl-like-v0")
SOURCE_RASTER_PROJECTION = "mwxSourceRasterProjection"
VALUE_TYPES = {
    "bool", "int", "uint", "float",
    "ivec2", "ivec3", "ivec4",
    "uvec2", "uvec3", "uvec4",
    "vec2", "vec3", "vec4",
    "mat2", "mat3", "mat4",
}
DECLARATION = re.compile(
    r"^\s*(?P<storage>uniform|attribute|varying)\s+"
    r"(?P<type>[A-Za-z_][A-Za-z0-9_]*)\s+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
    r"(?P<array>\s*\[\s*(?P<count>[0-9]+)\s*\])?\s*;"
    r"(?P<comment>\s*(?://.*)?)$"
)
SCALAR_TEXTURE_ASSIGNMENT = re.compile(
    r"(?P<prefix>\bfloat\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*)"
    r"(?P<sample>texSample2D\([^;]+\))(?P<suffix>\s*;)"
)


class HarnessFailure(RuntimeError):
    def __init__(self, phase: str, code: str, details: list[str] | None = None) -> None:
        super().__init__(f"{phase}:{code}")
        self.phase = phase
        self.code = code
        self.details = details or []


def validated_defines(payload: dict[str, Any]) -> dict[str, int]:
    raw = payload.get("defines", {})
    if not isinstance(raw, dict) or len(raw) > 128:
        raise HarnessFailure("request", "defines-shape")
    result: dict[str, int] = {}
    for name, value in raw.items():
        if not isinstance(name, str) or re.fullmatch(r"[A-Z_][A-Z0-9_]*", name) is None:
            raise HarnessFailure("request", "define-name", [str(name)])
        if isinstance(value, bool):
            result[name] = int(value)
        elif isinstance(value, int) and -(2 ** 31) <= value < 2 ** 31:
            result[name] = value
        else:
            raise HarnessFailure("request", "define-value", [name])
    return result


def _used_varying_components(body: str, name: str, width: int) -> set[str]:
    ordered = "xyzw"[:width]
    aliases = dict(zip("rgba", "xyzw"))
    used: set[str] = set()
    for match in re.finditer(
        rf"\b{re.escape(name)}\b(?P<swizzle>\.[xyzwrgba]{{1,4}})?",
        body,
    ):
        swizzle = match.group("swizzle")
        if swizzle is None:
            return set(ordered)
        used.update(aliases.get(component, component) for component in swizzle[1:])
    return used


def _prune_unused_varying_component_assignments(
    vertex_body: str,
    fragment_body: str,
    varying_shapes: dict[str, tuple[str, int | None]],
) -> tuple[str, int]:
    pruned = 0
    for name, (value_type, count) in varying_shapes.items():
        width_match = re.fullmatch(r"vec([2-4])", value_type)
        if count is not None or width_match is None:
            continue
        used = _used_varying_components(
            fragment_body, name, int(width_match.group(1))
        )
        aliases = dict(zip("rgba", "xyzw"))
        assignment = re.compile(
            rf"^[ \t]*{re.escape(name)}\.(?P<swizzle>[xyzwrgba]{{1,4}})"
            rf"\s*=\s*(?P<expression>[^;]*);[ \t]*$",
            re.MULTILINE,
        )

        def replacement(match: re.Match[str]) -> str:
            nonlocal pruned
            assigned = {
                aliases.get(component, component)
                for component in match.group("swizzle")
            }
            expression = match.group("expression")
            calls = re.findall(r"\b([A-Za-z_]\w*)\s*\(", expression)
            if assigned & used or any(
                call not in {"float", "int", "uint", "vec2", "vec3", "vec4"}
                for call in calls
            ):
                return match.group(0)
            if "++" in expression or "--" in expression:
                return match.group(0)
            if not re.fullmatch(r"[A-Za-z0-9_.,()\s+\-*/]+", expression):
                return match.group(0)
            pruned += 1
            return ""

        vertex_body = assignment.sub(replacement, vertex_body)
    return vertex_body, pruned


def _rewrite_texture_coordinates(
    source: str,
    shapes: dict[str, tuple[str, int | None]],
) -> str:
    """Apply the shared sampler float2 narrowing rule to declared vec3/vec4 names."""
    pattern = re.compile(
        r"\btexSample2D\(\s*(g_Texture[0-7])\s*,\s*"
        r"([A-Za-z_][A-Za-z0-9_]*)\s*\)"
    )

    def replacement(match: re.Match[str]) -> str:
        texture, coordinate = match.groups()
        value_type, _ = shapes.get(coordinate, ("", None))
        if value_type not in {"vec3", "vec4"}:
            return match.group(0)
        return f"texSample2D({texture}, {coordinate}.xy)"

    return pattern.sub(replacement, source)


def _rewrite_scalar_vector_assignments(
    source: str,
    shapes: dict[str, tuple[str, int | None]],
) -> str:
    vector_names = {
        name for name, (value_type, _) in shapes.items()
        if value_type in {"vec2", "vec3", "vec4"}
    }
    if not vector_names:
        return source
    assignment = re.compile(
        r"\bfloat\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*([^;]+);"
    )
    vector = re.compile(
        r"\b(?:" + "|".join(map(re.escape, sorted(vector_names)))
        + r")\b(?!\s*(?:\[[^\]]*\]|\.\s*[xyzwrgba]\b))"
    )
    function_call = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\s*\(")
    scalar_result = re.compile(r"(?:\.\s*[xyzwrgba]|\[[^\]]*\])\s*$")

    def contains_top_level_comma(expression: str) -> bool:
        depth = 0
        for character in expression:
            if character in "([{":
                depth += 1
            elif character in ")]}":
                depth = max(0, depth - 1)
            elif character == "," and depth == 0:
                return True
        return False

    def replacement(match: re.Match[str]) -> str:
        expression = match.group(1)
        if contains_top_level_comma(expression):
            return match.group(0)
        if scalar_result.search(expression):
            return match.group(0)
        if function_call.search(expression):
            return match.group(0)
        if not vector.search(expression):
            return match.group(0)
        if expression.strip().startswith("vec"):
            return match.group(0)
        return match.group(0).replace(expression, f"({expression}).x", 1)

    return assignment.sub(replacement, source)


def _rewrite_boolean_scalar_compound_assignments(source: str) -> str:
    assignment = re.compile(
        r"\b[A-Za-z_][A-Za-z0-9_]*"
        r"(?:\s*(?:\.\s*[xyzwrgba]|\[[^\]\r\n]+\]))*"
        r"\s*(?:\+=|-=|\*=|/=)\s*"
        r"([^;?\r\n]*(?:<=|>=|==|!=|<|>)[^;?\r\n]*)(\s*;)"
    )

    def replacement(match: re.Match[str]) -> str:
        expression = match.group(1)
        if expression.strip().startswith("float("):
            return match.group(0)
        start, end = match.span(1)
        relative_start = start - match.start()
        relative_end = end - match.start()
        return (
            match.group(0)[:relative_start]
            + f"float({expression})"
            + match.group(0)[relative_end:]
        )

    return assignment.sub(replacement, source)


def _rewrite_floating_modulo_assignments(source: str) -> str:
    declarations = {
        name: value_type
        for value_type, name in re.findall(
            r"\b(float|int|uint)\s+([A-Za-z_][A-Za-z0-9_]*)\b",
            source,
        )
    }
    atom = r"(?:[A-Za-z_][A-Za-z0-9_]*|[-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))"
    assignment = re.compile(
        rf"\b(float|int|uint)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
        rf"({atom})\s*%\s*({atom})\s*;"
    )

    def scalar_type(value: str) -> str:
        return declarations.get(value, "float" if "." in value else "int")

    def replacement(match: re.Match[str]) -> str:
        target, name, left, right = match.groups()
        if scalar_type(left) != "float" and scalar_type(right) != "float":
            return match.group(0)
        remainder = f"mod(float({left}), float({right}))"
        value = remainder if target == "float" else f"{target}({remainder})"
        return f"{target} {name} = {value};"

    return assignment.sub(replacement, source)


def _rewrite_scalar_builtin_integer_endpoints(source: str) -> str:
    user_defined = set(re.findall(
        r"\b(?:bool|int|uint|float|[biu]?vec[2-4])\s+"
        r"(lerp|smoothstep)\s*\(",
        source,
    ))
    call = re.compile(
        r"\b(lerp|smoothstep)\s*\(\s*"
        r"([-+]?[0-9]+)\s*,\s*([-+]?[0-9]+)\s*,"
    )

    def replacement(match: re.Match[str]) -> str:
        name, first, second = match.groups()
        if name in user_defined:
            return match.group(0)
        return f"{name}({first}.0, {second}.0,"

    result = call.sub(replacement, source)
    if "lerp" not in user_defined:
        result = re.sub(r"\blerp(?=\s*\()", "mix", result)
    return result


def _rewrite_vector_constructor_assignments(
    source: str,
    shapes: dict[str, tuple[str, int | None]],
) -> str:
    assignment = re.compile(
        r"\b(vec[2-4])\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
        r"(vec[2-4])\s*\(([^;]*)\);"
    )

    def replacement(match: re.Match[str]) -> str:
        target, name, constructor, arguments = match.groups()
        target_width = int(target[3:])
        source_width = int(constructor[3:])
        if source_width <= target_width:
            return match.group(0)
        suffix = ".xy" if target_width == 2 else ".xyz"
        return f"{target} {name} = {constructor}({arguments}){suffix};"

    return assignment.sub(replacement, source)


def normalize_wallpaper_engine_pair(
    stages: list[dict[str, str]],
    defines: dict[str, int],
    source_raster_projection: bool = False,
) -> tuple[list[dict[str, str]], dict[str, Any]]:
    parsed: dict[str, dict[str, Any]] = {}
    uniform_shapes: dict[str, tuple[str, int | None]] = {}
    sampler_slots: dict[str, int] = {}
    varying_shapes: dict[str, tuple[str, int | None]] = {}
    attribute_shapes: dict[str, tuple[str, int | None]] = {}
    stage_varyings: dict[str, set[str]] = {stage: set() for stage in ALLOWED_STAGES}
    scalar_texture_rewrites = 0
    boolean_combo_rewrites = 0
    reserved_identifier_rewrites = 0
    inactive_fragment_varyings_pruned = 0
    fragment_reads_raster_position = False

    for stage in stages:
        stage_name = stage["stage"]
        kept: list[str] = []
        declarations: list[tuple[str, str, str, int | None]] = []
        seen_declarations: set[tuple[str, str]] = set()
        for line in stage["source"].replace("\r\n", "\n").replace("\r", "\n").split("\n"):
            if line.lstrip().startswith("#version"):
                continue
            match = DECLARATION.fullmatch(line)
            if match is None:
                if re.match(r"^\s*(uniform|attribute|varying)\b", line):
                    raise HarnessFailure(
                        "normalization", "declaration-unsupported", [stage_name, line.strip()]
                    )
                kept.append(line)
                continue
            storage = match.group("storage")
            value_type = match.group("type")
            name = match.group("name")
            count = int(match.group("count")) if match.group("count") else None
            if count is not None and not (1 <= count <= 128):
                raise HarnessFailure("normalization", "array-count", [stage_name, name])
            declaration_identity = (storage, name)
            if declaration_identity in seen_declarations:
                raise HarnessFailure(
                    "normalization", "declaration-duplicate", [stage_name, storage, name]
                )
            seen_declarations.add(declaration_identity)
            declarations.append((storage, value_type, name, count))
            if storage == "uniform":
                if value_type.startswith("sampler"):
                    slot_match = re.fullmatch(r"g_Texture([0-7])", name)
                    if value_type != "sampler2D" or slot_match is None or count is not None:
                        raise HarnessFailure(
                            "normalization", "sampler-unsupported", [stage_name, name, value_type]
                        )
                    slot = int(slot_match.group(1))
                    existing_slot = sampler_slots.setdefault(name, slot)
                    if existing_slot != slot:
                        raise HarnessFailure("normalization", "sampler-conflict", [name])
                else:
                    audio_array = (
                        value_type == "float"
                        and count in (16, 32, 64)
                        and name in (
                            f"g_AudioSpectrum{count}Left",
                            f"g_AudioSpectrum{count}Right",
                        )
                    )
                    if value_type not in VALUE_TYPES or (
                        count is not None and not audio_array
                    ):
                        raise HarnessFailure(
                            "normalization", "uniform-type", [stage_name, name, value_type]
                        )
                    shape = (value_type, count)
                    existing = uniform_shapes.setdefault(name, shape)
                    if existing != shape:
                        raise HarnessFailure("normalization", "uniform-conflict", [name])
            elif storage == "attribute":
                if stage_name != "vertex" or value_type not in VALUE_TYPES or count is not None:
                    raise HarnessFailure("normalization", "attribute-unsupported", [stage_name, name])
                shape = (value_type, count)
                existing = attribute_shapes.setdefault(name, shape)
                if existing != shape:
                    raise HarnessFailure("normalization", "attribute-conflict", [name])
            elif storage == "varying":
                # Varying linkage is derived after the declaration-free body
                # exists, so an unused fragment input cannot create a false
                # cross-stage ABI conflict.
                pass
        body = "\n".join(kept)
        for storage, value_type, name, count in declarations:
            if storage != "varying":
                continue
            if value_type not in VALUE_TYPES or (count is not None and count > 16):
                raise HarnessFailure(
                    "normalization", "varying-type", [stage_name, name]
                )
            if stage_name == "fragment" and re.search(
                rf"\b{re.escape(name)}\b", body
            ) is None or (
                stage_name == "fragment"
                and _has_local_declaration(name, body)
            ):
                inactive_fragment_varyings_pruned += 1
                continue
            shape = (value_type, count)
            existing = varying_shapes.setdefault(name, shape)
            if existing != shape:
                raise HarnessFailure("normalization", "varying-conflict", [name])
            stage_varyings[stage_name].add(name)
        body, replacements = re.subn(r"\bsample\b", "mwx_sample", body)
        reserved_identifier_rewrites += replacements
        if stage_name == "fragment":
            if source_raster_projection:
                code = re.sub(r"/\*.*?\*/|//[^\n]*", " ", body, flags=re.DOTALL)
                fragment_reads_raster_position = re.search(r"\bgl_(?:Position|FragCoord)\b", code) is not None
                body = re.sub(r"\bgl_Position\b", "gl_FragCoord", body)
            body = re.sub(r"\bgl_FragColor\b", "mwxFragColor", body)
            body, replacements = SCALAR_TEXTURE_ASSIGNMENT.subn(
                r"\g<prefix>\g<sample>.r\g<suffix>", body
            )
            scalar_texture_rewrites += replacements
        for define_name in defines:
            body, replacements = re.subn(
                rf"\b{re.escape(define_name)}\s*\?",
                f"({define_name} != 0) ?",
                body,
            )
            boolean_combo_rewrites += replacements
        parsed[stage_name] = {"body": body, "declarations": declarations}

    expected_attributes = {
        "a_Position": ("vec3", None),
        "a_TexCoord": ("vec2", None),
    }
    if attribute_shapes != expected_attributes:
        raise HarnessFailure(
            "normalization", "vertex-attributes-unsupported",
            sorted(attribute_shapes),
        )
    missing_vertex_outputs = stage_varyings["fragment"] - stage_varyings["vertex"]
    if missing_vertex_outputs:
        raise HarnessFailure(
            "normalization", "varying-link",
            sorted(missing_vertex_outputs),
        )

    if "mwxRenderSize" in uniform_shapes:
        raise HarnessFailure("normalization", "reserved-uniform", ["mwxRenderSize"])
    if SOURCE_RASTER_PROJECTION in uniform_shapes:
        raise HarnessFailure("normalization", "reserved-uniform", [SOURCE_RASTER_PROJECTION])
    uses_target_pixel_position = source_raster_projection or re.search(
        r"\bg_ModelViewProjectionMatrix\b", parsed["vertex"]["body"]
    ) is not None
    position_expression = (
        "(mwxPosition - vec2(0.5)) * mwxRenderSize"
        if uses_target_pixel_position
        else "mwxPosition * 2.0 - vec2(1.0)"
    )
    entry = "mwxSourceAuthorVertex" if source_raster_projection else "main"
    coordinates = (
        "mwxVertexCoordinates01.xy, mwxVertexCoordinates01.zw,\n"
        "        mwxVertexCoordinates23.xy, mwxVertexCoordinates23.zw"
        if source_raster_projection else
        "vec2(0.0, 1.0), vec2(1.0, 1.0),\n"
        "        vec2(0.0, 0.0), vec2(1.0, 0.0)"
    )
    vertex_body, main_replacements = re.subn(
        r"\bvoid\s+main\s*\(\s*\)\s*\{",
        f"""void {entry}() {{
    const vec2 mwxCoordinates[4] = vec2[4](
        {coordinates});
    vec2 a_TexCoord = mwxCoordinates[gl_VertexIndex];
    vec2 mwxPosition = vec2(a_TexCoord.x, 1.0 - a_TexCoord.y);
    vec3 a_Position = vec3({position_expression}, 0.0);""",
        parsed["vertex"]["body"],
        count=1,
    )
    if main_replacements != 1:
        raise HarnessFailure("normalization", "vertex-main")
    if source_raster_projection:
        vertex_body += f"""

void main() {{
    {entry}();
    gl_Position = {SOURCE_RASTER_PROJECTION} * gl_Position;
}}"""
    vertex_body, varying_component_prunes = (
        _prune_unused_varying_component_assignments(
            vertex_body,
            parsed["fragment"]["body"],
            varying_shapes,
        )
    )
    parsed["vertex"]["body"] = vertex_body
    parsed["vertex"]["body"] = _rewrite_texture_coordinates(
        parsed["vertex"]["body"],
        {**attribute_shapes, **varying_shapes, **uniform_shapes},
    )
    parsed["fragment"]["body"] = _rewrite_texture_coordinates(
        parsed["fragment"]["body"],
        {**varying_shapes, **uniform_shapes},
    )
    parsed["fragment"]["body"] = _rewrite_boolean_scalar_compound_assignments(
        parsed["fragment"]["body"]
    )
    parsed["fragment"]["body"] = _rewrite_floating_modulo_assignments(
        parsed["fragment"]["body"]
    )
    parsed["fragment"]["body"] = _rewrite_scalar_builtin_integer_endpoints(
        parsed["fragment"]["body"]
    )
    parsed["fragment"]["body"] = _rewrite_scalar_vector_assignments(
        parsed["fragment"]["body"],
        {**varying_shapes, **uniform_shapes},
    )
    parsed["fragment"]["body"] = _rewrite_vector_constructor_assignments(
        parsed["fragment"]["body"],
        {**varying_shapes, **uniform_shapes},
    )

    attribute_order = sorted(
        attribute_shapes,
        key=lambda name: ({"a_Position": 0, "a_TexCoord": 1}.get(name, 2), name),
    )
    varying_order = sorted(varying_shapes)
    varying_spans = [varying_shapes[name][1] or 1 for name in varying_order]
    varying_locations = dict(zip(varying_order, [0, *accumulate(varying_spans)]))
    active_uniform_names = {
        name
        for name in uniform_shapes
        if any(
            re.search(rf"\b{re.escape(name)}\b", parsed[stage]["body"])
            for stage in ALLOWED_STAGES
        )
    }
    uniform_lines = [
        f"    {value_type} {name}{f'[{count}]' if count is not None else ''};"
        for name, (value_type, count) in sorted(uniform_shapes.items())
        if name in active_uniform_names
    ]
    uniform_lines.append("    vec2 mwxRenderSize;")
    if source_raster_projection:
        uniform_lines.extend([
            "    vec4 mwxVertexCoordinates01;", "    vec4 mwxVertexCoordinates23;",
            f"    mat4 {SOURCE_RASTER_PROJECTION};",
        ])
    define_lines = [f"#define {name} {value}" for name, value in sorted(defines.items())]
    compatibility_lines = shader_compatibility_lines()
    texture_support_lines = texture_sampling_support_lines()

    normalized: list[dict[str, str]] = []
    for stage in stages:
        stage_name = stage["stage"]
        interface: list[str] = []
        active_sampler_lines = [
            f"layout(set = 0, binding = {slot}) uniform sampler2D {name};"
            for name, slot in sorted(sampler_slots.items(), key=lambda item: item[1])
            if re.search(rf"\b{re.escape(name)}\b", parsed[stage_name]["body"])
        ]
        for name in varying_order:
            if name not in stage_varyings[stage_name]:
                continue
            value_type, count = varying_shapes[name]
            suffix = f"[{count}]" if count is not None else ""
            direction = "out" if stage_name == "vertex" else "in"
            interface.append(
                f"layout(location = {varying_locations[name]}) "
                f"{direction} {value_type} {name}{suffix};"
            )
        if stage_name == "fragment":
            interface.append("layout(location = 0) out vec4 mwxFragColor;")
        uniform_block = (
            "layout(std140, set = 0, binding = 8) uniform MWXUniforms {\n"
            + "\n".join(uniform_lines)
            + "\n};\n"
        )
        source = "\n".join([
            "#version 450",
            *define_lines,
            *compatibility_lines,
            uniform_block.rstrip(),
            *texture_support_lines,
            *active_sampler_lines,
            *interface,
            parsed[stage_name]["body"],
        ]).strip() + "\n"
        normalized.append({
            "stage": stage_name,
            "entryPoint": stage["entryPoint"],
            "source": source,
        })
    return normalized, {
        "dialect": "wallpaper-engine-glsl-like-v0",
        "uniformCount": len(uniform_shapes),
        "activeUniformCount": len(active_uniform_names),
        "inactiveUniformsPruned": len(uniform_shapes) - len(active_uniform_names),
        "inactiveFragmentVaryingsPruned": inactive_fragment_varyings_pruned,
        "unusedVaryingComponentAssignmentsPruned": varying_component_prunes,
        "samplerSlots": sorted(sampler_slots.values()),
        "attributeCount": len(attribute_shapes),
        "varyingCount": len(varying_shapes),
        "defineCount": len(defines),
        "scalarTextureChannelRewrites": scalar_texture_rewrites,
        "booleanComboTernaryRewrites": boolean_combo_rewrites,
        "reservedIdentifierRewrites": reserved_identifier_rewrites,
        "vertexPositionInput": (
            "target-pixels" if uses_target_pixel_position else "clip-space"
        ),
        **({"fragmentReadsRasterPosition": fragment_reads_raster_position} if source_raster_projection else {}),
    }


def _has_local_declaration(name: str, source: str) -> bool:
    types = "|".join(re.escape(value) for value in sorted(VALUE_TYPES))
    return re.search(
        rf"\b(?:{types})\s+{re.escape(name)}\b", source
    ) is not None


def normalize_request(
    payload: dict[str, Any],
    stages: list[dict[str, str]],
) -> tuple[list[dict[str, str]], dict[str, Any]]:
    dialect = payload.get("sourceDialect", "glsl-450")
    if dialect not in ALLOWED_DIALECTS:
        raise HarnessFailure("request", "source-dialect", [str(dialect)])
    defines = validated_defines(payload)
    if dialect == "glsl-450":
        if defines:
            raise HarnessFailure("request", "defines-with-standard-glsl")
        return stages, {"dialect": dialect, "transformed": False}
    normalized, summary = normalize_wallpaper_engine_pair(stages, defines, uses_source_raster_projection(payload))
    summary["transformed"] = True
    return normalized, summary
