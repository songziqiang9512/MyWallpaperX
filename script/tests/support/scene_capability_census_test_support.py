"""Shared authored-package fixture for census observation and output tests."""

from __future__ import annotations

import json
import struct
from pathlib import Path


def pkg(entries: list[tuple[str, bytes]], magic: str = "PKGV0024") -> bytes:
    table = bytearray()
    magic_bytes = magic.encode("utf-8")
    table += struct.pack("<I", len(magic_bytes)) + magic_bytes
    table += struct.pack("<I", len(entries))
    payload = bytearray()
    for path, value in entries:
        path_bytes = path.encode("utf-8")
        table += struct.pack("<I", len(path_bytes)) + path_bytes
        table += struct.pack("<II", len(payload), len(value))
        payload += value
    return bytes(table + payload)


def json_bytes(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def make_fixture(root: Path, *, include_failures: bool = False) -> tuple[Path, Path, Path, Path]:
    samples = root / "samples"
    stock = root / "stock"
    sample = samples / "0000000001"
    sample.mkdir(parents=True)
    stock.mkdir(parents=True)
    (sample / "project.json").write_text(
        json.dumps({
            "type": "Scene",
            "file": "scene.json",
            "title": "Fixture",
            "general": {
                "supportsaudioprocessing": True,
                "properties": {
                    "toggle": {"type": "bool", "value": True, "order": 0, "text": "Toggle"}
                }
            },
        }),
        encoding="utf-8",
    )
    scene = {
        "version": 1,
        "objects": [{
            "id": 6,
            "name": "Hidden Parent",
            "visible": False,
        }, {
            "id": 7,
            "name": "Layer",
            "image": "models/layer.json",
            "visible": True,
            "parent": 6,
            "origin": "10 20 0",
            "instance": {
                "usertextures": [
                    {"type": "system", "name": "$mediaThumbnail"},
                    {"type": "property", "name": "not-system"},
                    {"type": "system", "name": ""},
                    42,
                ],
            },
            "effects": [{
                "id": 9,
                "file": "effects/fixture/effect.json",
                "visible": True,
                "passes": [{
                    "id": 0,
                    "combos": {"MASK": 0},
                    "constantshadervalues": {
                        "alpha": {
                            "script": (
                                "// engine.registerAudioBuffers(64);\n"
                                "const ignored = 'engine.registerAudioBuffers(16)';\n"
                                "const audio = engine.registerAudioBuffers("
                                "engine.AUDIO_RESOLUTION_32);\n"
                                "export function update() { return engine.frametime; }"
                            ),
                            "value": 1,
                        }
                    },
                    "textures": [None, "mask"],
                    "usertextures": [
                        None,
                        {"type": "system", "name": "$mediaPreviousThumbnail"},
                        {"type": "system"},
                    ],
                }],
            }],
        }, {
            "id": 10,
            "name": "Visible Material Reuse",
            "image": "models/layer.json",
            "visible": True,
        }, {
            "id": 8,
            "particle": "particles/root.json",
            "visible": True,
            "instanceoverride": {"id": 8, "rate": {"user": "toggle", "value": 2}},
        }],
    }
    entries = [
        ("scene.json", json_bytes(scene)),
        ("models/layer.json", json_bytes({"autosize": True, "material": "materials/layer.json"})),
        ("materials/layer.json", json_bytes({"passes": [{
            "shader": "genericimage2", "blending": "translucent",
            "depthtest": "disabled", "depthwrite": "disabled",
            "cullmode": "nocull", "textures": ["image"],
            "usertextures": [
                {"type": "system", "name": "$mediaThumbnail"},
                {"type": "system", "name": "$mediaPreviousThumbnail"},
                {"type": "system", "name": "$customProvider"},
                {"type": "property", "name": "not-system"},
                {"type": "system", "name": ""},
                "plain-string",
            ],
        }]})),
        ("materials/image.tex", b"not-a-real-tex"),
        ("materials/mask.tex", b"not-a-real-tex"),
        ("effects/fixture/effect.json", json_bytes({
            "name": "Fixture", "group": "Test", "dependencies": [],
            "passes": [{
                "material": "materials/effects/fixture.json",
                "target": "_rt_fixture",
                "bind": [{"name": "previous", "index": 0}],
            }],
            "fbos": [{"name": "_rt_fixture", "format": "rgba8888", "scale": 2}],
        })),
        ("effects/fixture/materials/effects/fixture.json", json_bytes({"passes": [{
            "shader": "effects/fixture", "blending": "translucent",
            "depthtest": "disabled", "depthwrite": "disabled",
            "cullmode": "nocull", "textures": [None, "mask"],
            "combos": {"AUDIOPROCESSING": 0},
            "constantshadervalues": {"audioamount": 1},
            "usertextures": [
                {"type": "SYSTEM", "name": "  $mediaThumbnail  "},
                {"type": "property", "name": "not-system"},
                {"type": "system", "name": ""},
            ],
        }]})),
        ("particles/root.json", json_bytes({
            "maxcount": 10, "starttime": 0,
            "material": "materials/particle.json",
            "emitter": [{
                "id": 1, "name": "sphererandom", "rate": 2,
                "audioprocessingmode": 3,
            }],
            "initializer": [{"id": 2, "name": "lifetimerandom", "min": 1, "max": 2}],
            "operator": [{"id": 3, "name": "movement", "gravity": "0 1 0"}],
            "renderer": [{"id": 4, "name": "sprite"}],
            "children": [{"id": 5, "name": "particles/child.json", "type": "static"}],
        })),
        ("particles/child.json", json_bytes({
            "maxcount": 1, "starttime": 0,
            "material": "materials/particle.json",
            "emitter": [{"id": 1, "name": "boxrandom", "rate": 1}],
            "initializer": [], "operator": [],
            "renderer": [{"id": 2, "name": "sprite"}],
        })),
        ("materials/particle.json", json_bytes({"passes": [{
            "shader": "particle", "textures": ["particle"],
            "blending": "additive", "depthtest": "disabled",
            "depthwrite": "disabled", "cullmode": "nocull",
        }]})),
        ("materials/particle.tex", b"not-a-real-tex"),
        ("shaders/effects/fixture.vert", b"uniform mat4 g_ModelViewProjectionMatrix;\nvoid main() {}\n"),
        ("shaders/effects/fixture.frag", (
            b'uniform sampler2D g_Texture0; // {"mode":"rgbmask","combo":"MASK"}\n'
            b"// uniform float g_AudioSpectrum64Right[64];\n"
            b"uniform float g_AudioSpectrum16Left[16];\n"
            b"uniform float g_AudioSpectrum16Right[16];\n"
            b"uniform vec2 g_AudioSpectrum32Left[32];\n"
            b"uniform float g_AudioSpectrum32Right[16];\n"
            b"#if 0\n"
            b"uniform float g_AudioSpectrum64Left[64];\n"
            b"#endif\n"
            b"uniform float g_Alpha;\nvoid main() {}\n"
        )),
    ]
    (sample / "scene.pkg").write_bytes(pkg(entries))
    matrix = root / "matrix.json"
    matrix.write_text(json.dumps({"schema_version": 1, "samples": []}), encoding="utf-8")
    ledger = root / "ledger.json"
    ledger.write_text(json.dumps({"schema_version": 1, "families": []}), encoding="utf-8")
    if include_failures:
        shader_only = samples / "0000000002"
        (shader_only / "shaders").mkdir(parents=True)
        (shader_only / "shaders/only.frag").write_text("void main() {}", encoding="utf-8")
        (shader_only / "preview.png").write_bytes(b"preview is not a manual screenshot")
        malformed = samples / "0000000003"
        malformed.mkdir()
        (malformed / "project.json").write_text("{broken-json", encoding="utf-8")
        (malformed / "截屏-test.PNG").write_bytes(b"manual screenshot presence fixture")
        (malformed / "用户观察说明.md").write_text("Fixture observation", encoding="utf-8")
    return samples, stock, matrix, ledger
