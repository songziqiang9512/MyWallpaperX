#!/usr/bin/env python3

"""Real generic compiler stage-shape gate for the texture-transform ABI."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_scene_material_texture_transform import (
    REPOSITORY_ROOT,
    SUPPORT,
    SWIFT_SOURCES,
)

sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_shader_compiler_artifact import (  # noqa: E402
    ArtifactFailure,
    build_program_artifact,
)


GLSLANG = (
    REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneShaderCompilerTools/glslang"
)
SPIRV_CROSS = (
    REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneShaderCompilerTools/spirv-cross"
)


HARNESS = r'''
import Foundation

private struct Sources {
    let vertex: String
    let fragment: String
}

private let baseVertex = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    v_TexCoord = a_TexCoord;
    gl_Position = vec4(a_Position, 1.0);
}
"""

private let cases: [String: Sources] = [
    "fragment-only": .init(
        vertex: baseVertex,
        fragment: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
        }
        """
    ),
    "vertex-only": .init(
        vertex: """
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            float displacement = texSample2D(g_Texture0, a_TexCoord).r * 0.001;
            gl_Position = vec4(a_Position.xy, displacement, 1.0);
        }
        """,
        fragment: """
        void main() { gl_FragColor = vec4(0.25, 0.5, 0.75, 1.0); }
        """
    ),
    "helper": .init(
        vertex: """
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        uniform sampler2D g_Texture0;
        float sampleGlobal(vec2 coordinate) {
            return texture2D(g_Texture0, coordinate).r;
        }
        void main() {
            float displacement = sampleGlobal(a_TexCoord) * 0.001;
            gl_Position = vec4(a_Position.xy, displacement, 1.0);
        }
        """,
        fragment: """
        void main() { gl_FragColor = vec4(0.25, 0.5, 0.75, 1.0); }
        """
    ),
    "inactive-builtin-overload": .init(
        vertex: """
        mat3 inverse(mat3 value) {
            return value;
        }
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec2 v_TexCoord;
        void main() {
            v_TexCoord = a_TexCoord;
            gl_Position = vec4(a_Position, 1.0);
        }
        """,
        fragment: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
        }
        """
    ),
    "active-builtin-overload": .init(
        vertex: """
        mat3 inverse(mat3 value) {
            return value;
        }
        mat3 squareToQuad(vec2 value) {
            return mat3(value.x + 1.0);
        }
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec2 v_TexCoord;
        void main() {
            mat3 live = inverse(squareToQuad(a_TexCoord));
            v_TexCoord = a_TexCoord;
            gl_Position = vec4(live[0][0] * a_Position, 1.0);
        }
        """,
        fragment: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
        }
        """
    ),
    "both-stages": .init(
        vertex: """
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            v_TexCoord = a_TexCoord;
            float displacement = texSample2DLod(
                g_Texture0, a_TexCoord, 0.0
            ).r * 0.001;
            gl_Position = vec4(a_Position.xy, displacement, 1.0);
        }
        """,
        fragment: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            gl_FragColor = texture2DLod(g_Texture0, v_TexCoord, 0.0);
        }
        """
    ),
    "neutral-missing-resolution": .init(
        vertex: """
        uniform mat4 g_ModelViewProjectionMatrix;
        uniform vec4 g_Texture1Resolution;
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec4 v_TexCoord;
        void main() {
            gl_Position = mul(
                vec4(a_Position, 1.0), g_ModelViewProjectionMatrix
            );
            v_TexCoord.xy = a_TexCoord;
            v_TexCoord.zw = vec2(
                v_TexCoord.x * g_Texture1Resolution.z
                    / g_Texture1Resolution.x,
                v_TexCoord.y * g_Texture1Resolution.w
                    / g_Texture1Resolution.y
            );
        }
        """,
        fragment: """
        varying vec4 v_TexCoord;
        uniform sampler2D g_Texture1;
        uniform sampler2D g_Texture2;
        void main() {
            gl_FragColor = texSample2D(g_Texture2, v_TexCoord.zw);
        }
        """
    ),
    "active-resolution-sampler": .init(
        vertex: """
        uniform mat4 g_ModelViewProjectionMatrix;
        uniform vec4 g_Texture1Resolution;
        uniform sampler2D g_Texture1;
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec4 v_TexCoord;
        void main() {
            float displacement = texSample2D(
                g_Texture1, a_TexCoord
            ).r * 0.001;
            gl_Position = mul(
                vec4(a_Position.xy, displacement, 1.0),
                g_ModelViewProjectionMatrix
            );
            v_TexCoord.xy = a_TexCoord;
            v_TexCoord.zw = vec2(
                v_TexCoord.x * g_Texture1Resolution.z
                    / g_Texture1Resolution.x,
                v_TexCoord.y * g_Texture1Resolution.w
                    / g_Texture1Resolution.y
            );
        }
        """,
        fragment: """
        varying vec4 v_TexCoord;
        uniform sampler2D g_Texture2;
        void main() {
            gl_FragColor = texSample2D(g_Texture2, v_TexCoord.zw);
        }
        """
    ),
]

private let rejectedCases: [String: Sources] = [
    "inactive-invalid-body": .init(
        vertex: """
        mat3 inverse(mat3 value) {
            return undefinedHelper(value);
        }
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec2 v_TexCoord;
        void main() {
            v_TexCoord = a_TexCoord;
            gl_Position = vec4(a_Position, 1.0);
        }
        """,
        fragment: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
        }
        """
    ),
    "active-mat4-overload": .init(
        vertex: """
        mat3 inverse(mat3 value) {
            return value;
        }
        uniform mat4 g_Matrix;
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec2 v_TexCoord;
        void main() {
            mat4 live = inverse(g_Matrix);
            v_TexCoord = a_TexCoord;
            gl_Position = vec4(live[0][0] * a_Position, 1.0);
        }
        """,
        fragment: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
        }
        """
    ),
]

private func write(_ value: String, to url: URL) throws {
    try Data(value.utf8).write(to: url, options: .atomic)
}

private func normalize(root: URL) throws {
    for (name, authored) in cases.merging(rejectedCases, uniquingKeysWith: {
        current, _ in current
    }).sorted(by: { $0.key < $1.key }) {
        let canonical = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
            vertex: authored.vertex,
            fragment: authored.fragment
        )
        guard case let .success(pair) = SceneGenericShaderSourceNormalizer.normalize(
            vertexSource: canonical.vertex,
            fragmentSource: canonical.fragment,
            maximumStageSourceBytes: 100_000
        ) else { throw NSError(domain: "normalize", code: 1) }
        try write(canonical.vertex, to: root.appendingPathComponent("\(name).authored.vert"))
        try write(canonical.fragment, to: root.appendingPathComponent("\(name).authored.frag"))
        try write(pair.vertex, to: root.appendingPathComponent("\(name).vert"))
        try write(pair.fragment, to: root.appendingPathComponent("\(name).frag"))
    }
}

private func build(root: URL) throws -> [String: String] {
    var results: [String: String] = [:]
    for name in cases.keys.sorted() {
        let stages = try ["vertex", "fragment"].map { stage ->
            SceneGenericShaderArtifactBuilder.Stage in
            let suffix = stage == "vertex" ? "vert" : "frag"
            return .init(
                name: stage,
                source: try String(contentsOf: root.appendingPathComponent(
                    "\(name).\(suffix)"
                )),
                authoredSource: try String(contentsOf: root.appendingPathComponent(
                    "\(name).authored.\(suffix)"
                )),
                msl: try String(contentsOf: root.appendingPathComponent(
                    "\(name).\(stage).metal"
                )),
                reflection: try Data(contentsOf: root.appendingPathComponent(
                    "\(name).\(stage).reflection.json"
                ))
            )
        }
        switch SceneGenericShaderArtifactBuilder.build(
            requestKey: String(repeating: "a", count: 64),
            backendID: "glslang-spirv-cross-msl-v2",
            stages: stages,
            maximumArtifactBytes: 1_000_000
        ) {
        case let .success(artifact):
            let expectedSlots: [Int]
            switch name {
            case "neutral-missing-resolution": expectedSlots = [2]
            case "active-resolution-sampler": expectedSlots = [1, 2]
            default: expectedSlots = [0]
            }
            let fields = artifact.program.uniformLayout.fields
            let transformFields = fields.filter {
                SceneMaterialTextureTransformABI.component(
                    forFieldName: $0.authoredName
                ) != nil
            }
            let valid = artifact.program.textureBindings.map(\.slot) == expectedSlots
                && transformFields.count == expectedSlots.count * 2
                && transformFields.allSatisfy {
                    $0.stage == nil && $0.type == "float4"
                }
                && expectedSlots.allSatisfy { slot in
                    artifact.program.metalSource.contains(
                        "mwxTexture\(slot)Transform0"
                    ) && artifact.program.metalSource.contains(
                        "mwxTexture\(slot)Transform1"
                    )
                }
            results[name] = valid ? "accepted" : "invalid-abi"
            try write(
                artifact.program.metalSource,
                to: root.appendingPathComponent("\(name).final.metal")
            )
        case let .failure(failure):
            results[name] = String(describing: failure)
        }
    }
    return results
}

@main
private enum Main {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "arguments", code: 1)
        }
        let root = URL(
            fileURLWithPath: CommandLine.arguments[2], isDirectory: true
        )
        switch CommandLine.arguments[1] {
        case "normalize":
            try normalize(root: root)
        case "build":
            let data = try JSONSerialization.data(
                withJSONObject: build(root: root), options: [.sortedKeys]
            )
            FileHandle.standardOutput.write(data)
        case "decode-worker":
            let artifact = try JSONDecoder().decode(
                SceneGenericShaderProgramArtifact.self,
                from: Data(contentsOf: root.appendingPathComponent(
                    "fragment-only.worker.json"
                ))
            )
            let accepted = artifact.makeProgram(
                expectedKey: String(repeating: "a", count: 64),
                expectedColorTransfer: .passthrough(textureSlot: 0),
                expectedFragmentOutputChannelUse: .unproven
            ) != nil
            FileHandle.standardOutput.write(Data(String(accepted).utf8))
        default:
            throw NSError(domain: "arguments", code: 2)
        }
    }
}
'''


class SceneGenericShaderTextureTransformCompilerTests(unittest.TestCase):
    CASES = (
        "fragment-only",
        "vertex-only",
        "helper",
        "inactive-builtin-overload",
        "active-builtin-overload",
        "both-stages",
        "neutral-missing-resolution",
        "active-resolution-sampler",
    )

    @staticmethod
    def _expected_slots(name: str) -> tuple[int, ...]:
        if name == "neutral-missing-resolution":
            return (2,)
        if name == "active-resolution-sampler":
            return (1, 2)
        return (0,)

    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-generic-transform-compiler-"
        )
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        harness = root / "Harness.swift"
        cls.binary = root / "generic-transform-compiler"
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                str(support), *(str(path) for path in SWIFT_SOURCES), str(harness),
                "-framework", "Metal", "-framework", "CoreGraphics",
                "-module-cache-path", str(root / "module-cache"),
                "-o", str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        subprocess.run(
            [str(cls.binary), "normalize", str(root)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )
        cls._assert_rejected_overload_cases(root)
        cls._compile_real_stages(root)
        cls.worker_artifacts = cls._build_worker_artifacts(root)
        decoded = subprocess.run(
            [str(cls.binary), "decode-worker", str(root)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )
        if decoded.stdout != "true":
            raise RuntimeError("Python worker artifact rejected by Swift product decoder")
        built = subprocess.run(
            [str(cls.binary), "build", str(root)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(built.stdout)
        if any(value != "accepted" for value in cls.result.values()):
            raise RuntimeError(f"artifact builder rejected stage cases: {cls.result}")
        cls._preflight_final_metal(root)

    @classmethod
    def _worker_arguments(cls, root: Path, name: str) -> dict:
        compiled_stages = []
        msl_sources = {}
        stage_sources = {}
        for stage, suffix in (("vertex", "vert"), ("fragment", "frag")):
            compiled_stages.append({
                "stage": stage,
                "reflection": json.loads(
                    (root / f"{name}.{stage}.reflection.json").read_text()
                ),
            })
            msl_sources[stage] = (root / f"{name}.{stage}.metal").read_text()
            stage_sources[stage] = (root / f"{name}.{suffix}").read_text()
        return {
            "request_key": "a" * 64,
            "backend_id": "glslang-spirv-cross-msl-v2",
            "compiled_stages": compiled_stages,
            "stage_sources": stage_sources,
            "msl_sources": msl_sources,
            "maximum_artifact_bytes": 1_000_000,
        }

    @classmethod
    def _build_worker_artifacts(cls, root: Path) -> dict:
        results = {}
        for name in cls.CASES:
            artifact = build_program_artifact(**cls._worker_arguments(root, name))
            expected_slots = cls._expected_slots(name)
            fields = artifact["program"]["uniformLayout"]["fields"]
            transforms = [
                field for field in fields
                if field["authoredName"].startswith("mwxTexture")
            ]
            if (
                [
                    binding["slot"]
                    for binding in artifact["program"]["textureBindings"]
                ]
                != list(expected_slots)
                or len(transforms) != len(expected_slots) * 2
                or any(field.get("stage") is not None for field in transforms)
                or any(field["type"] != "float4" for field in transforms)
            ):
                raise RuntimeError(f"worker transform ABI invalid: {name}")
            (root / f"{name}.worker.json").write_text(json.dumps(artifact))
            (root / f"{name}.worker.final.metal").write_text(
                artifact["program"]["metalSource"]
            )
            results[name] = "accepted"
        return results

    @classmethod
    def _compile_real_stages(cls, root: Path) -> None:
        for name in cls.CASES:
            subprocess.run(
                [
                    str(GLSLANG), "-V", "--auto-map-bindings",
                    "--auto-map-locations", "-l",
                    str(root / f"{name}.vert"), str(root / f"{name}.frag"),
                ],
                cwd=root,
                check=True,
                capture_output=True,
                text=True,
            )
            for stage, suffix in (("vertex", "vert"), ("fragment", "frag")):
                spirv = root / f"{name}.{stage}.spv"
                subprocess.run(
                    [
                        str(GLSLANG), "-V", "--auto-map-bindings",
                        "--auto-map-locations", "-S", suffix, "-e", "main",
                        "-o", str(spirv), str(root / f"{name}.{suffix}"),
                    ],
                    cwd=root,
                    check=True,
                    capture_output=True,
                    text=True,
                )
                subprocess.run(
                    [
                        str(SPIRV_CROSS), str(spirv), "--msl", "--msl-version",
                        "20000", "--msl-decoration-binding",
                        "--rename-entry-point", "main",
                        "mwxGenericVertex" if stage == "vertex"
                        else "mwxGenericFragment",
                        suffix, "--output", str(root / f"{name}.{stage}.metal"),
                    ],
                    cwd=root,
                    check=True,
                    capture_output=True,
                    text=True,
                )
                subprocess.run(
                    [
                        str(SPIRV_CROSS), str(spirv), "--reflect", "--output",
                        str(root / f"{name}.{stage}.reflection.json"),
                    ],
                    cwd=root,
                    check=True,
                    capture_output=True,
                    text=True,
                )

    @classmethod
    def _assert_rejected_overload_cases(cls, root: Path) -> None:
        for name in ("inactive-invalid-body", "active-mat4-overload"):
            completed = subprocess.run(
                [
                    str(GLSLANG), "-V", "--auto-map-bindings",
                    "--auto-map-locations", "-l",
                    str(root / f"{name}.vert"), str(root / f"{name}.frag"),
                ],
                cwd=root,
                capture_output=True,
                text=True,
            )
            if completed.returncode == 0:
                raise RuntimeError(f"unsafe overload case accepted: {name}")

    @classmethod
    def _preflight_final_metal(cls, root: Path) -> None:
        for name in cls.CASES:
            for owner in ("", ".worker"):
                completed = subprocess.run(
                    [
                        "xcrun", "metal", "-x", "metal", "-std=macos-metal2.4",
                        "-c", str(root / f"{name}{owner}.final.metal"),
                        "-o", str(root / f"{name}{owner}.air"),
                    ],
                    cwd=root,
                    capture_output=True,
                    text=True,
                )
                if completed.returncode != 0:
                    raise RuntimeError(completed.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_real_compiler_stage_shapes_share_mandatory_transform_abi(self) -> None:
        self.assertEqual(self.result, {name: "accepted" for name in self.CASES})
        self.assertEqual(
            self.worker_artifacts,
            {name: "accepted" for name in self.CASES},
        )

    def test_worker_rejects_missing_malformed_and_stage_drift(self) -> None:
        root = Path(self.temporary_directory.name)
        for mutation, code in (
            ("missing", "texture-transform-layout"),
            ("malformed", "texture-transform-layout"),
            ("stage-drift", "uniform-stage-mismatch"),
        ):
            with self.subTest(mutation=mutation):
                arguments = self._worker_arguments(root, "both-stages")
                reflections = [
                    stage["reflection"] for stage in arguments["compiled_stages"]
                ]
                members = [
                    reflection["types"][reflection["ubos"][0]["type"]]["members"]
                    for reflection in reflections
                ]
                if mutation == "missing":
                    for values in members:
                        values[:] = [
                            field for field in values
                            if field["name"] != "mwxTexture0Transform1"
                        ]
                elif mutation == "malformed":
                    for values in members:
                        next(field for field in values if field["name"]
                             == "mwxTexture0Transform0")["type"] = "vec2"
                else:
                    next(field for field in members[0] if field["name"]
                         == "mwxTexture0Transform0")["type"] = "vec3"
                with self.assertRaisesRegex(ArtifactFailure, code):
                    build_program_artifact(**arguments)


if __name__ == "__main__":
    unittest.main()
