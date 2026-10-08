#!/usr/bin/env python3
"""Actual bounded/generic fragment raster-position compiler and pixel gates."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_scene_generic_shader_float_array_index import (
    GLSLANG, HARNESS as COMPILER_HARNESS, REPOSITORY_ROOT, SWIFT_SOURCES,
)


VERTEX = """attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    gl_Position = vec4(a_Position, 1.0);
    v_TexCoord = a_TexCoord;
}
"""

# Keep the existing compiler harness and its source ownership. This adds only
# Metal submission/readback; both stage functions come from product compilers.
RENDER_METHOD = r'''
    private static func render(_ arguments: [String]) throws {
        let configuration = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: arguments[2]))
        ) as! [String: Any]
        let device = MTLCreateSystemDefaultDevice()!
        let vertexLibrary = try device.makeLibrary(
            source: String(contentsOfFile: configuration["vertex"] as! String, encoding: .utf8),
            options: nil
        )
        let fragmentLibrary = try device.makeLibrary(
            source: String(contentsOfFile: configuration["fragment"] as! String, encoding: .utf8),
            options: nil
        )
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexLibrary.makeFunction(name: configuration["vertexName"] as! String)
        descriptor.fragmentFunction = fragmentLibrary.makeFunction(name: configuration["fragmentName"] as! String)
        descriptor.colorAttachments[0].pixelFormat = .rgba32Float
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let width = configuration["width"] as! Int
        let height = configuration["height"] as! Int
        let target = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false
        )
        target.storageMode = .shared
        target.usage = [.renderTarget]
        let texture = device.makeTexture(descriptor: target)!
        let queue = device.makeCommandQueue()!
        let viewport = configuration["viewport"] as! [Double]
        let locations = configuration["locations"] as! [[Int]]
        let uniformIndex = configuration["uniformIndex"] as! Int
        var uniforms = [Float(width), Float(height), Float(0), Float(0)]
        var frames: [[[Float]]] = []
        for _ in 0..<2 {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(-1, -1, -1, -1)
            let command = queue.makeCommandBuffer()!
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            encoder.setRenderPipelineState(pipeline)
            encoder.setViewport(MTLViewport(
                originX: viewport[0], originY: viewport[1], width: viewport[2],
                height: viewport[3], znear: 0, zfar: 1
            ))
            uniforms.withUnsafeBytes {
                encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: uniformIndex)
                encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: uniformIndex)
            }
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            guard command.status == .completed else {
                throw NSError(domain: "fragment-position-gpu-completion", code: 1)
            }
            var pixels: [[Float]] = []
            for location in locations {
                var pixel = [Float](repeating: 0, count: 4)
                pixel.withUnsafeMutableBytes {
                    texture.getBytes($0.baseAddress!, bytesPerRow: 16,
                        from: MTLRegionMake2D(location[0], location[1], 1, 1), mipmapLevel: 0)
                }
                pixels.append(pixel)
            }
            frames.append(pixels)
        }
        print(json: ["frames": frames, "completion": "completed", "submissions": 2])
    }
'''

HARNESS = COMPILER_HARNESS.replace("import Foundation", "import Foundation\nimport Metal")
HARNESS = HARNESS.replace(
    "        let arguments = CommandLine.arguments",
    "        let arguments = CommandLine.arguments\n"
    "        if arguments[1] == \"--render\" { try render(arguments); return }",
)
HARNESS = HARNESS.replace("    private static func print(json", RENDER_METHOD + "\n    private static func print(json")


class SceneShaderFragmentPositionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-fragment-position-")
        cls.root = Path(cls.temporary.name)
        sources = cls.root / "sources"
        sources.mkdir()
        cls.source_facts = {}
        frozen = []
        for index, path in enumerate(SWIFT_SOURCES):
            data = path.read_bytes()
            target = sources / f"{index:03d}-{path.name}"
            target.write_bytes(data)
            frozen.append(target)
            cls.source_facts[str(path.relative_to(REPOSITORY_ROOT))] = hashlib.sha256(data).hexdigest()
        cls.source_hash = hashlib.sha256(json.dumps(cls.source_facts, sort_keys=True).encode()).hexdigest()
        cls.results = []
        harness = cls.root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = cls.root / "fragment-position"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(cls.root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(cls.root / "swift-cache")
        completed = subprocess.run([
            "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
            *(str(path) for path in frozen), str(harness),
            "-module-cache-path", str(cls.root / "module-cache"), "-o", str(cls.binary),
        ], cwd=REPOSITORY_ROOT, env=environment, capture_output=True, text=True, timeout=180)
        if completed.returncode:
            cls.temporary.cleanup()
            raise RuntimeError(completed.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        if destination := os.environ.get("MWX_FRAGMENT_POSITION_EVIDENCE"):
            path = Path(destination)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps({
                "sourceSHA256": cls.source_hash, "sources": cls.source_facts,
                "results": cls.results,
            }, indent=2) + "\n", encoding="utf-8")
        cls.temporary.cleanup()

    def compile(self, fragment: str, vertex: str = VERTEX) -> tuple[dict, Path]:
        directory = Path(tempfile.mkdtemp(prefix="case-", dir=self.root))
        (directory / "input.vert").write_text(vertex, encoding="utf-8")
        (directory / "input.frag").write_text(fragment, encoding="utf-8")
        completed = subprocess.run([
            str(self.binary), str(directory / "input.vert"), str(directory / "input.frag"),
            str(directory / "output.vert"), str(directory / "output.frag"),
        ], capture_output=True, text=True, timeout=30)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout), directory

    def generic_metal(self, directory: Path, *, accepted: bool = True) -> list[Path]:
        linked = subprocess.run([
            str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations", "-l",
            str(directory / "output.vert"), str(directory / "output.frag"),
        ], cwd=directory, capture_output=True, text=True, timeout=30)
        if not accepted:
            self.assertNotEqual(linked.returncode, 0, linked.stdout + linked.stderr)
            return []
        self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)
        result = []
        for stage in ("vert", "frag"):
            metal = directory / f"generic-{stage}.metal"
            cross = subprocess.run([
                str(GLSLANG.with_name("spirv-cross")), str(directory / f"{stage}.spv"),
                "--msl", "--rename-entry-point", "main", f"position_{stage}", stage,
                "--output", str(metal),
            ], capture_output=True, text=True, timeout=30)
            self.assertEqual(cross.returncode, 0, cross.stdout + cross.stderr)
            result.append(metal)
        return result

    def offline_metal(self, path: Path) -> None:
        completed = subprocess.run([
            "xcrun", "-sdk", "macosx", "metal", "-c", str(path),
            "-o", str(path.with_suffix(".air")),
        ], capture_output=True, text=True, timeout=30)
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_fragment_reads_and_helper_use_stage_input_on_both_backends(self) -> None:
        for body in (
            "void main() { gl_FragColor = vec4(gl_Position.xy / vec2(96.0,64.0), 0.25, 1.0); }",
            "vec2 raster() { return gl_Position.xy; }\n"
            "vec2 nested() { return raster(); }\n"
            "void main() { gl_FragColor = vec4(nested() / vec2(96.0,64.0), 0.25, 1.0); }",
        ):
            with self.subTest(body=body):
                result, directory = self.compile(body)
                self.assertTrue(result["ok"], result)
                self.assertTrue(result["boundedHasProgram"], result["boundedDiagnostics"])
                self.assertIn("mwxInput.position . xy", result["boundedMetal"])
                self.assertIn("gl_FragCoord.xy", result["fragment"])
                bounded = directory / "bounded.metal"
                bounded.write_text(result["boundedMetal"], encoding="utf-8")
                self.offline_metal(bounded)
                for metal in self.generic_metal(directory):
                    self.offline_metal(metal)

    def test_vertex_output_and_similarly_named_identifier_are_preserved(self) -> None:
        vertex = VERTEX.replace(
            "gl_Position = vec4(a_Position, 1.0);",
            "gl_Position = vec4(a_Position, 1.0);\n    gl_Position.xy *= 0.5;",
        )
        result, directory = self.compile(
            "vec2 own_gl_PositionLike() { return vec2(0.2,0.3); }\n"
            "void main() { gl_FragColor = vec4(own_gl_PositionLike(), 0.25, 1.0); }", vertex,
        )
        self.assertTrue(result["ok"], result)
        self.assertTrue(result["boundedHasProgram"], result["boundedDiagnostics"])
        self.assertIn("mwxOutput.position . xy *=", result["boundedMetal"])
        self.assertIn("gl_Position.xy *= 0.5", result["vertex"])
        self.assertIn("gl_PositionLike", result["fragment"])
        self.assertNotIn("gl_FragCoordLike", result["fragment"])
        bounded = directory / "bounded.metal"
        bounded.write_text(result["boundedMetal"], encoding="utf-8")
        self.offline_metal(bounded)
        for metal in self.generic_metal(directory):
            self.offline_metal(metal)
        # A literal gl_ prefix is reserved in GLSL. Test its token preservation
        # at normalization, without claiming the author declaration is legal.
        result, _ = self.compile(
            "vec2 gl_PositionLike() { return vec2(0.2,0.3); }\n"
            "void main() { gl_FragColor = vec4(gl_PositionLike(), 0.25, 1.0); }",
        )
        self.assertTrue(result["ok"], result)
        self.assertIn("gl_PositionLike", result["fragment"])
        self.assertNotIn("gl_FragCoordLike", result["fragment"])

    @unittest.skipUnless(os.environ.get("MWX_RUN_FRAGMENT_POSITION_GPU") == "1", "isolated GPU lane required")
    def test_two_frames_multi_pixel_raster_coordinates_and_vertex_counterexample(self) -> None:
        fragments = {
            "direct": "void main() { gl_FragColor = vec4(gl_Position.xy / vec2(96.0,64.0),0.25,1.0); }",
            "helper": "vec2 location() { return gl_Position.xy; }\n"
                      "void main() { gl_FragColor = vec4(location() / vec2(96.0,64.0),0.25,1.0); }",
        }
        for name, fragment in fragments.items():
            result, directory = self.compile(fragment)
            self.assertTrue(result["boundedHasProgram"], result["boundedDiagnostics"])
            bounded = directory / "bounded.metal"
            bounded.write_text(result["boundedMetal"], encoding="utf-8")
            generic = self.generic_metal(directory)
            for backend, stages, functions, uniform_index in (
                ("bounded", [bounded, bounded], ["sceneAuthoredVertex", "sceneAuthoredFragment"], 0),
                ("generic", generic, ["position_vert", "position_frag"], 8),
            ):
                for size, viewport, locations in (
                    ((96,64), (0,0,96,64), [(24,16),(48,32),(72,48)]),
                    ((96,64), (8,6,64,48), [(16,12),(40,30),(64,48)]),
                    ((48,40), (0,0,48,40), [(8,6),(24,20),(40,34)]),
                ):
                    with self.subTest(name=name, backend=backend, size=size, viewport=viewport):
                        output = self.render(directory, stages, functions, uniform_index, size, viewport, locations)
                        for frame in output["frames"]:
                            for pixel, (x,y) in zip(frame, locations, strict=True):
                                for actual, expected in zip(pixel, [(x+0.5)/96,(y+0.5)/64,0.25,1], strict=True):
                                    self.assertAlmostEqual(actual, expected, delta=2e-6)
                        self.results.append({"case": name, "backend": backend, "size": size,
                                             "viewport": viewport, "locations": locations, **output})
        result, directory = self.compile(
            "void main() { gl_FragColor = vec4(0.2,0.3,0.25,1.0); }",
            VERTEX.replace("vec4(a_Position, 1.0)", "vec4(a_Position * 0.5, 1.0)"),
        )
        bounded = directory / "bounded.metal"
        bounded.write_text(result["boundedMetal"], encoding="utf-8")
        for backend, stages, functions, uniform_index in (
            ("bounded", [bounded,bounded], ["sceneAuthoredVertex","sceneAuthoredFragment"], 0),
            ("generic", self.generic_metal(directory), ["position_vert","position_frag"], 8),
        ):
            output = self.render(directory, stages, functions, uniform_index,
                                 (96,64), (0,0,96,64), [(4,4),(48,32),(92,60)])
            for frame in output["frames"]:
                self.assertEqual(frame[0], [-1]*4)
                self.assertEqual(frame[2], [-1]*4)
                for actual, expected in zip(frame[1], [0.2,0.3,0.25,1], strict=True):
                    self.assertAlmostEqual(actual, expected, delta=2e-6)
            self.results.append({"case": "vertex-scaled", "backend": backend, **output})

    def render(self, directory, stages, functions, uniform_index, size, viewport, locations):
        configuration = directory / "render.json"
        configuration.write_text(json.dumps({
            "vertex": str(stages[0]), "fragment": str(stages[1]),
            "vertexName": functions[0], "fragmentName": functions[1],
            "uniformIndex": uniform_index, "width": size[0], "height": size[1],
            "viewport": viewport, "locations": locations,
        }), encoding="utf-8")
        completed = subprocess.run([str(self.binary), "--render", str(configuration)],
                                   capture_output=True, text=True, timeout=30)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        output = json.loads(completed.stdout)
        self.assertEqual(output["completion"], "completed")
        self.assertEqual(output["submissions"], 2)
        return output


if __name__ == "__main__":
    unittest.main()
