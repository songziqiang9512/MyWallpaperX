#!/usr/bin/env python3
"""Same-slot authored UV mapping facts remain strict and identity-free."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources


SWIFT_SOURCES = scene_swift_sources("authored_shader_frontend_core")


HARNESS = r'''
import Foundation

private struct FactOutput: Codable, Equatable {
    let textureSlot: Int
    let sourceAttributeName: String
    let varyingName: String
    let sourceComponents: String
    let mappedComponents: String
}

private struct SourcePair {
    let vertex: String
    let fragment: String
    let activeSlots: Set<Int>
}

@main
private enum Harness {
    static func main() throws {
        let componentVertex = vertex(
            slot: 1,
            attribute: "a_TexCoord",
            varyingDeclaration: "varying vec4 v_TexCoord;",
            body: [
                "v_TexCoord = a_TexCoord.xyxy;",
                "v_TexCoord.z *= g_Texture1Resolution.z / g_Texture1Resolution.x;",
                "v_TexCoord.w *= g_Texture1Resolution.w / g_Texture1Resolution.y;",
            ]
        )
        let componentFragment = fragment(
            declarations: [
                "varying vec4 v_TexCoord;",
                "uniform sampler2D g_Texture0;",
                "uniform sampler2D g_Texture1;",
            ],
            helpers: [],
            body: [
                "vec4 base = texSample2D(g_Texture0, v_TexCoord.xy);",
                "vec4 mask = texSample2D(g_Texture1, v_TexCoord.zw);",
                "gl_FragColor = base * mask.r;",
            ]
        )

        let cases: [String: SourcePair] = [
            "whole": .init(
                vertex: vertex(
                    slot: 3,
                    attribute: "a_UV",
                    varyingDeclaration: "varying vec2 v_Mapped;",
                    body: [
                        "v_Mapped = vec2(a_UV.x * g_Texture3Resolution.z / g_Texture3Resolution.x, a_UV.y * g_Texture3Resolution.w / g_Texture3Resolution.y);",
                    ]
                ),
                fragment: fragment(
                    declarations: [
                        "varying vec2 v_Mapped;",
                        "uniform sampler2D g_Texture3;",
                    ],
                    helpers: [],
                    body: [
                        "gl_FragColor = texture2D(g_Texture3, v_Mapped);",
                    ]
                ),
                activeSlots: [3]
            ),
            "component": .init(
                vertex: componentVertex,
                fragment: componentFragment,
                activeSlots: [0, 1]
            ),
            "unseenNames": .init(
                vertex: vertex(
                    slot: 6,
                    attribute: "incomingCoordinates",
                    varyingDeclaration: "varying vec4 authoredTransport;",
                    body: [
                        "authoredTransport.xy = incomingCoordinates;",
                        "authoredTransport.zw = vec2(authoredTransport.x * g_Texture6Resolution.z / g_Texture6Resolution.x, authoredTransport.y * g_Texture6Resolution.w / g_Texture6Resolution.y);",
                    ]
                ),
                fragment: fragment(
                    declarations: [
                        "varying vec4 authoredTransport;",
                        "uniform sampler2D g_Texture6;",
                    ],
                    helpers: [],
                    body: [
                        "gl_FragColor = texSample2D(g_Texture6, authoredTransport.zw);",
                    ]
                ),
                activeSlots: [6]
            ),
            "wrongSlot": .init(
                vertex: componentVertex.replacingOccurrences(
                    of: "g_Texture1Resolution",
                    with: "g_Texture2Resolution"
                ).replacingOccurrences(
                    of: "uniform vec4 g_Texture1Resolution;",
                    with: "uniform vec4 g_Texture2Resolution;"
                ),
                fragment: componentFragment,
                activeSlots: [1]
            ),
            "mixedSample": .init(
                vertex: componentVertex,
                fragment: componentFragment.replacingOccurrences(
                    of: "gl_FragColor = base * mask.r;",
                    with: "vec4 secondMask = texSample2D(g_Texture1, v_TexCoord.xy);\n    gl_FragColor = base * mask.r * secondMask.r;"
                ),
                activeSlots: [1]
            ),
            "hiddenHelper": .init(
                vertex: componentVertex,
                fragment: fragment(
                    declarations: [
                        "varying vec4 v_TexCoord;",
                        "uniform sampler2D g_Texture1;",
                    ],
                    helpers: [
                        "vec4 hiddenRead(vec2 uv) { return texSample2D(g_Texture1, uv); }",
                    ],
                    body: [
                        "gl_FragColor = hiddenRead(v_TexCoord.zw);",
                    ]
                ),
                activeSlots: [1]
            ),
            "partial": .init(
                vertex: componentVertex.replacingOccurrences(
                    of: "v_TexCoord.w *= g_Texture1Resolution.w / g_Texture1Resolution.y;",
                    with: ""
                ),
                fragment: componentFragment,
                activeSlots: [1]
            ),
            "extraResolutionUse": .init(
                vertex: componentVertex.replacingOccurrences(
                    of: "gl_Position = vec4(a_Position, 1.0);",
                    with: "gl_Position = vec4(a_Position.x + g_Texture1Resolution.x, a_Position.yz, 1.0);"
                ),
                fragment: componentFragment,
                activeSlots: [1]
            ),
            "controlFlow": .init(
                vertex: componentVertex,
                fragment: componentFragment.replacingOccurrences(
                    of: "vec4 mask = texSample2D(g_Texture1, v_TexCoord.zw);",
                    with: "vec4 mask = vec4(1.0);\n    if (base.a > 0.0) { mask = texSample2D(g_Texture1, v_TexCoord.zw); }"
                ),
                activeSlots: [1]
            ),
            "earlyReturn": .init(
                vertex: componentVertex.replacingOccurrences(
                    of: "v_TexCoord.w *= g_Texture1Resolution.w / g_Texture1Resolution.y;",
                    with: "return;\n    v_TexCoord.w *= g_Texture1Resolution.w / g_Texture1Resolution.y;"
                ),
                fragment: componentFragment,
                activeSlots: [1]
            ),
            "offsetCoordinate": .init(
                vertex: componentVertex,
                fragment: componentFragment.replacingOccurrences(
                    of: "texSample2D(g_Texture1, v_TexCoord.zw)",
                    with: "texSample2D(g_Texture1, v_TexCoord.zw + vec2(0.1))"
                ),
                activeSlots: [1]
            ),
            "extraMappedUse": .init(
                vertex: componentVertex,
                fragment: componentFragment.replacingOccurrences(
                    of: "gl_FragColor = base * mask.r;",
                    with: "gl_FragColor = base * mask.r + vec4(v_TexCoord.zw, 0.0, 0.0);"
                ),
                activeSlots: [1]
            ),
        ]

        let output = cases.mapValues { pair in
            SceneAuthoredShaderSameSlotMappedCoordinateAnalyzer.analyze(
                vertexSource: pair.vertex,
                fragmentSource: pair.fragment,
                activeSamplerSlots: pair.activeSlots
            ).map {
                FactOutput(
                    textureSlot: $0.textureSlot,
                    sourceAttributeName: $0.sourceAttributeName,
                    varyingName: $0.varyingName,
                    sourceComponents: $0.sourceComponents,
                    mappedComponents: $0.mappedComponents
                )
            }.sorted { lhs, rhs in
                if lhs.textureSlot != rhs.textureSlot {
                    return lhs.textureSlot < rhs.textureSlot
                }
                return lhs.varyingName < rhs.varyingName
            }
        }
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }

    private static func vertex(
        slot: Int,
        attribute: String,
        varyingDeclaration: String,
        body: [String]
    ) -> String {
        ([
            "attribute vec3 a_Position;",
            "attribute vec2 \(attribute);",
            varyingDeclaration,
            "uniform vec4 g_Texture\(slot)Resolution;",
            "void main() {",
            "    gl_Position = vec4(a_Position, 1.0);",
        ] + body.map { "    \($0)" } + ["}"]).joined(separator: "\n")
    }

    private static func fragment(
        declarations: [String],
        helpers: [String],
        body: [String]
    ) -> String {
        (declarations + helpers + ["void main() {"]
            + body.map { "    \($0)" }
            + ["}"]).joined(separator: "\n")
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneAuthoredShaderSameSlotMappedCoordinateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(
            prefix="mwx-same-slot-mapped-coordinate-"
        )
        root = Path(cls.temporary.name)
        harness = root / "Harness.swift"
        cls.binary = root / "same-slot-mapped-coordinate-test"
        harness.write_text(HARNESS, encoding="utf-8")
        completed = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def result(self) -> dict[str, list[dict[str, object]]]:
        completed = subprocess.run(
            [str(self.binary)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout)

    def test_whole_component_and_unseen_names_produce_exact_facts(self) -> None:
        result = self.result()
        self.assertEqual(
            result["whole"],
            [{
                "textureSlot": 3,
                "sourceAttributeName": "a_UV",
                "varyingName": "v_Mapped",
                "sourceComponents": "xy",
                "mappedComponents": "xy",
            }],
        )
        self.assertEqual(
            result["component"],
            [{
                "textureSlot": 1,
                "sourceAttributeName": "a_TexCoord",
                "varyingName": "v_TexCoord",
                "sourceComponents": "xy",
                "mappedComponents": "zw",
            }],
        )
        self.assertEqual(
            result["unseenNames"],
            [{
                "textureSlot": 6,
                "sourceAttributeName": "incomingCoordinates",
                "varyingName": "authoredTransport",
                "sourceComponents": "xy",
                "mappedComponents": "zw",
            }],
        )

    def test_ambiguous_mixed_or_incomplete_flows_are_unproven(self) -> None:
        result = self.result()
        for name in (
            "wrongSlot",
            "mixedSample",
            "hiddenHelper",
            "partial",
            "extraResolutionUse",
            "controlFlow",
            "earlyReturn",
            "offsetCoordinate",
            "extraMappedUse",
        ):
            with self.subTest(name=name):
                self.assertEqual(result[name], [])


if __name__ == "__main__":
    unittest.main()
