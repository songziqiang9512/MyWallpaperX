"""Read production DTO declarations into the graph gate's runtime leaf shell."""
from pathlib import Path


SOURCE = Path(__file__).resolve().parents[2] / (
    "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/"
    "SceneResolvedMaterialRuntimeBridge+SourceMaterials.swift"
)


def _declaration(source: str, name: str) -> str:
    marker = f"    struct {name} {{"
    if source.count(marker) != 1:
        raise AssertionError(f"expected one production declaration: {name}")
    start = source.index(marker)
    cursor = source.index("{", start)
    depth = 0
    state = "code"
    while cursor < len(source):
        pair = source[cursor:cursor + 2]
        char = source[cursor]
        if state == "line":
            if char == "\n":
                state = "code"
        elif state == "block":
            if pair == "*/":
                state = "code"
                cursor += 1
        elif state == "string":
            if char == "\\":
                cursor += 1
            elif char == '"':
                state = "code"
        elif pair == "//":
            state = "line"
            cursor += 1
        elif pair == "/*":
            state = "block"
            cursor += 1
        elif char == '"':
            state = "string"
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[start:cursor + 1]
        cursor += 1
    raise AssertionError(f"unclosed production declaration: {name}")


def framebuffer_source_material_declarations() -> str:
    source = SOURCE.read_text()
    return "\n\n".join(_declaration(source, name) for name in (
        "PreparedSourceMaterial", "FramebufferSourceMaterial"
    )) + "\n"
