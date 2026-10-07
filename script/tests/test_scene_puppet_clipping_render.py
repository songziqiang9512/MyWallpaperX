"""Real prepared Puppet clipping raster, part draws, and local failure behavior."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCENE = Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [SCENE / path for path in (
    "Format/SceneMdlPuppetMeshReader.swift",
    "Systems/Puppet/ScenePuppetClipping.swift",
    "Rendering/Geometry/SceneGeometryProduct.swift",
    "Rendering/Metal/SceneMetalPipeline.swift",
    "Rendering/Targets/SceneOffscreenResolutionPolicy.swift",
    "Diagnostics/ScenePerformanceCounterHub.swift",
)]

HARNESS = r'''
import Foundation
import Metal
import simd

final class Allocations {
    let device: MTLDevice
    var attempts: [[Int]] = []
    var releases = 0
    var denyAll = false
    var remaining: Int?
    init(_ device: MTLDevice, remaining: Int? = nil) {
        self.device = device; self.remaining = remaining
    }
    func reserve(_ ordinal: Int, _ width: Int, _ height: Int,
                 _ commandBuffer: MTLCommandBuffer) -> ScenePuppetClipping.Allocation? {
        attempts.append([ordinal, width, height])
        guard !denyAll, remaining != 0 else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm,
            width: width, height: height, mipmapped: false)
        desc.storageMode = .private; desc.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        if let remaining { self.remaining = remaining - 1 }
        return .init(texture: texture, release: { self.releases += 1 })
    }
}

@main enum Harness {
    typealias Mesh = SceneMdlPuppetMesh
    static func record(_ target: Int, _ sources: [Int]) -> Mesh.ClipRecord {
        .init(id: UInt32(target), flags: 0, rawOptions: SIMD2(0, 1),
            maskTexturePath: "fixture/paint", targetPartOrdinal: target, sourcePartOrdinals: sources)
    }
    static func fixture(_ rects: [SIMD4<Float>], colors: [Int], records: [Mesh.ClipRecord]) -> Mesh {
        var vertices: [Mesh.Vertex] = [], indices: [UInt16] = [], parts: [Mesh.DrawPart] = []
        for (ordinal, rect) in rects.enumerated() {
            let base = UInt16(vertices.count), offset = indices.count
            // Each part uses one atlas texel. Vertex coverage defaults to 1;
            // a separate case exercises the unsupported provider-alpha boundary.
            let u = (Float(colors[ordinal]) + 0.5) / 4
            vertices += [SIMD2(rect.x, rect.y), SIMD2(rect.z, rect.y),
                         SIMD2(rect.x, rect.w), SIMD2(rect.z, rect.w)].map {
                .init(x: $0.x, y: $0.y, z: 0, u: u, v: 0.5)
            }
            indices += [base, base + 1, base + 2, base + 2, base + 1, base + 3]
            parts.append(.init(ordinal: ordinal, id: UInt32(ordinal), flags: 0,
                               indexOffset: offset, indexCount: 6))
        }
        return .init(version: "MDLV0023", vertexStride: 80, meshBlockOffset: 9,
                     vertices: vertices, indices: indices, drawParts: parts, clipRecords: records)
    }
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}"); return
        }
        let library = try device.makeLibrary(URL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let image = SceneImageLayerPipeline(device: device, library: library)!
        guard let maskPipeline = ScenePuppetClipping.makePipeline(device: device) else {
            fatalError("production clipping pipeline unavailable")
        }
        func texture(_ format: MTLPixelFormat, _ width: Int, _ height: Int,
                     bytes: [UInt8] = [], target: Bool = false) -> MTLTexture {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                width: width, height: height, mipmapped: false)
            desc.storageMode = .shared; desc.usage = target ? [.renderTarget] : [.shaderRead]
            let texture = device.makeTexture(descriptor: desc)!
            if !bytes.isEmpty {
                bytes.withUnsafeBytes {
                    texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                        withBytes: $0.baseAddress!, bytesPerRow: width * (format == .r8Unorm ? 1 : 4))
                }
            }
            return texture
        }
        // Transparent displayed providers isolate the target's output pixels.
        // Mask generation receives paint and posed geometry, never this atlas.
        let atlas = texture(.rgba8Unorm, 4, 1,
            bytes: [0, 0, 0, 0, 160, 80, 40, 255, 0, 200, 0, 255, 0, 0, 0, 0])
        let white = texture(.r8Unorm, 4, 4, bytes: Array(repeating: 255, count: 16))
        let gray = texture(.r8Unorm, 4, 4, bytes: Array(repeating: 128, count: 16))
        let black = texture(.r8Unorm, 4, 4, bytes: Array(repeating: 0, count: 16))
        let standardPoints: [String: SIMD2<Float>] = [
            "left": SIMD2(-0.375, 0), "right": SIMD2(0.375, 0),
            "healthy": SIMD2(0.7, 0.7), "center": .zero]
        func vertices(_ mesh: Mesh) -> [SceneQuadVertex] {
            mesh.vertices.map { .init(position: SIMD2($0.x, $0.y), texcoord: SIMD2($0.u, $0.v)) }
        }
        func buffers(_ mesh: Mesh, _ posed: [SceneQuadVertex]) -> (MTLBuffer, MTLBuffer) {
            var posed = posed, indices = mesh.indices
            return (device.makeBuffer(bytes: &posed,
                length: posed.count * MemoryLayout<SceneQuadVertex>.stride, options: .storageModeShared)!,
                device.makeBuffer(bytes: &indices,
                    length: indices.count * MemoryLayout<UInt16>.stride, options: .storageModeShared)!)
        }
        func owner(_ mesh: Mesh, _ paints: [Int: MTLTexture], _ allocations: Allocations) -> ScenePuppetClipping {
            ScenePuppetClipping(mesh: mesh, pipeline: maskPipeline, paintTextures: paints,
                allocate: { allocations.reserve($0, $1, $2, $3) })
        }
        func render(_ mesh: Mesh, _ clipping: ScenePuppetClipping, posed: [SceneQuadVertex]? = nil,
                    points: [String: SIMD2<Float>] = standardPoints) -> [String: [UInt8]] {
            let posed = posed ?? vertices(mesh), (vb, ib) = buffers(mesh, posed)
            let command = queue.makeCommandBuffer()!
            var releases: [() -> Void] = []
            clipping.prepare(commandBuffer: command, extent: SIMD2(64, 64), mvp: matrix_identity_float4x4,
                retainAuxiliary: { releases.append($0) }, vertices: posed, vertexBuffer: vb, indexBuffer: ib)
            let target = texture(.bgra8Unorm, 64, 64, target: true)
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            image.bind(encoder: encoder)
            encoder.setCullMode(.none); encoder.setVertexBuffer(vb, offset: 0, index: 0)
            var mvp = matrix_identity_float4x4
            var uniforms = SceneLayerFragmentUniforms(time: 0, alpha: 1, dependencyBlendMode: 0,
                usesDependencyBlend: 0, cursorUV: .zero, sourceSampling: SIMD2(2, 0),
                tint: SIMD4(repeating: 1), textureFrame0: SIMD4(0, 0, 1, 0), textureFrame1: SIMD4(0, 1, 0, 0))
            encoder.setVertexBytes(&mvp, length: MemoryLayout<simd_float4x4>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SceneLayerFragmentUniforms>.stride, index: 0)
            encoder.setFragmentTexture(atlas, index: 0); encoder.setFragmentTexture(atlas, index: 1)
            clipping.draw(encoder: encoder, sourceTexture: atlas, indexBuffer: ib)
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            releases.forEach { $0() }
            guard command.status == .completed, command.error == nil else { fatalError("GPU completion") }
            var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
            pixels.withUnsafeMutableBytes {
                target.getBytes($0.baseAddress!, bytesPerRow: 64 * 4, from: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0)
            }
            return points.mapValues { point in
                let x = Int((point.x + 1) * 32), y = Int((1 - point.y) * 32), offset = (y * 64 + x) * 4
                return [pixels[offset + 2], pixels[offset + 1], pixels[offset], pixels[offset + 3]]
            }
        }
        let left = SIMD4<Float>(-0.75, -0.5, 0, 0.5)
        let full = SIMD4<Float>(-0.75, -0.5, 0.75, 0.5)
        let healthy = SIMD4<Float>(0.55, 0.55, 0.85, 0.85)
        let basic = fixture([left, full, healthy], colors: [0, 1, 2], records: [record(1, [0])])
        let movement = Allocations(device), moving = owner(basic, [0: white], movement)
        let leftFrame = render(basic, moving)
        var moved = vertices(basic)
        for index in 0..<4 { moved[index].position.x += 0.75 }
        let rightFrame = render(basic, moving, posed: moved)
        movement.denyAll = true
        let failedFrame = render(basic, moving, posed: moved)
        let blackAlloc = Allocations(device), grayAlloc = Allocations(device)
        let blackFrame = render(basic, owner(basic, [0: black], blackAlloc))
        let grayFrame = render(basic, owner(basic, [0: gray], grayAlloc))

        let overlap = fixture([left, left, full, healthy], colors: [0, 0, 1, 2],
                              records: [record(2, [0, 1])])
        let overlapAlloc = Allocations(device)
        let overlapFrame = render(overlap, owner(overlap, [0: gray], overlapAlloc))
        let alphaAlloc = Allocations(device), alphaOwner = owner(basic, [0: white], alphaAlloc)
        var translucentProvider = vertices(basic)
        for index in 0..<4 { translucentProvider[index].vertexCoverage = 0.5 }
        let unsupportedAlphaFrame = render(basic, alphaOwner, posed: translucentProvider)
        let unsupportedAlphaAttempts = alphaAlloc.attempts
        let restoredAlphaFrame = render(basic, alphaOwner)

        let selfCandidate = fixture([left, full, healthy], colors: [0, 1, 2], records: [record(1, [0, 1])])
        let selfOnly = fixture([left, full, healthy], colors: [0, 1, 2], records: [record(1, [1])])
        let selfAlloc = Allocations(device), onlyAlloc = Allocations(device)
        let selfFrame = render(selfCandidate, owner(selfCandidate, [0: white], selfAlloc))
        let onlyFrame = render(selfOnly, owner(selfOnly, [0: white], onlyAlloc))

        let nested = fixture([left, full, full, healthy], colors: [0, 0, 1, 2],
                             records: [record(1, [0]), record(2, [1])])
        let nestedAlloc = Allocations(device)
        let nestedFrame = render(nested, owner(nested, [0: white, 1: white], nestedAlloc))
        // An empty clipped source contributes zero geometry, not an
        // unavailable dependency that hides its healthy union sibling.
        let emptySource = Mesh(version: nested.version, vertexStride: nested.vertexStride,
            meshBlockOffset: 9, vertices: nested.vertices,
            indices: Array(nested.indices[0..<6]) + Array(nested.indices[12...]),
            drawParts: [
                .init(ordinal: 0, id: 0, flags: 0, indexOffset: 0, indexCount: 6),
                .init(ordinal: 1, id: 1, flags: 0, indexOffset: 6, indexCount: 0),
                .init(ordinal: 2, id: 2, flags: 0, indexOffset: 6, indexCount: 6),
                .init(ordinal: 3, id: 3, flags: 0, indexOffset: 12, indexCount: 6)],
            clipRecords: [record(1, [0]), record(2, [0, 1])])
        let emptySourceAlloc = Allocations(device)
        let emptySourceFrame = render(emptySource,
            owner(emptySource, [0: white, 1: white], emptySourceAlloc))
        let cycle = fixture([full, full, healthy], colors: [1, 1, 2],
                            records: [record(0, [1]), record(1, [0])])
        let cycleAlloc = Allocations(device)
        let cycleFrame = render(cycle, owner(cycle, [0: white, 1: white], cycleAlloc))

        let unavailable = fixture([SIMD4(-0.9, -0.8, 0.9, 0.8), SIMD4(-0.8, -0.4, -0.2, 0.4),
                                   SIMD4(-0.8, -0.4, -0.2, 0.4), SIMD4(0.4, -0.4, 0.8, 0.4)],
                                  colors: [0, 1, 1, 2],
                                  records: [record(1, [0]), record(2, [1]), record(3, [0])])
        let localBudget = Allocations(device, remaining: 1)
        let unavailableFrame = render(unavailable, owner(unavailable, [1: white, 2: white], localBudget),
            points: ["left": SIMD2(-0.5, 0), "right": SIMD2(0.6, 0)])

        // Interior perspective derivative maximum: the corner-only estimate
        // underallocates width to about 44 although the interior needs >=127.
        let roi = fixture([SIMD4(0, 0, 1, 10), SIMD4(0, 0, 1, 10)], colors: [0, 1], records: [record(1, [0])])
        let roiAlloc = Allocations(device); roiAlloc.denyAll = true
        let roiOwner = owner(roi, [0: white], roiAlloc)
        let roiVertices = vertices(roi), (roiVB, roiIB) = buffers(roi, roiVertices)
        let perspective = simd_float4x4(SIMD4(0.01, 0, 0, 1), SIMD4(0, 1, 0, 1),
                                        SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1))
        roiOwner.prepare(commandBuffer: queue.makeCommandBuffer()!, extent: SIMD2(1000, 1000), mvp: perspective,
            retainAuxiliary: { $0() }, vertices: roiVertices, vertexBuffer: roiVB, indexBuffer: roiIB)

        // Disjoint ranges may reuse the same four physical vertices; UInt16
        // indices stay legal while the typed dependency chain has 50,000 nodes.
        let base = fixture([full], colors: [2], records: [])
        let count = 50_000
        let chain = Mesh(version: base.version, vertexStride: base.vertexStride, meshBlockOffset: 9,
            vertices: base.vertices, indices: (0...count).flatMap { _ in base.indices },
            drawParts: (0...count).map { .init(ordinal: $0, id: UInt32($0), flags: 0, indexOffset: $0 * 6, indexCount: 6) },
            clipRecords: (0..<count).map { record($0 + 1, [$0]) })
        let chainAlloc = Allocations(device)
        let chainFrame = render(chain, owner(chain, [:], chainAlloc))
        let result: [String: Any] = [
            "left": leftFrame, "right": rightFrame, "failed": failedFrame,
            "black": blackFrame, "gray": grayFrame, "selfCandidate": selfFrame, "selfOnly": onlyFrame,
            "overlap": overlapFrame, "unsupportedAlpha": unsupportedAlphaFrame,
            "unsupportedAlphaAttempts": unsupportedAlphaAttempts, "restoredAlpha": restoredAlphaFrame,
            "nested": nestedFrame, "cycle": cycleFrame, "missingPaint": unavailableFrame,
            "emptySource": emptySourceFrame, "emptySourceAttempts": emptySourceAlloc.attempts,
            "movementReleases": movement.releases, "movementAttempts": movement.attempts,
            "nestedAttempts": nestedAlloc.attempts, "cycleAttempts": cycleAlloc.attempts,
            "localBudgetAttempts": localBudget.attempts, "localBudgetReleases": localBudget.releases,
            "roiAttempts": roiAlloc.attempts, "chain": chainFrame, "chainAttempts": chainAlloc.attempts,
            "chainCount": chain.clipRecords.count,
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class ScenePuppetClippingRenderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc") or not shutil.which("xcrun"):
            raise unittest.SkipTest("Swift/Metal toolchain unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-puppet-clip-render-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            harness.write_text(HARNESS)
            air, library, binary = root / "image.air", root / "image.metallib", root / "render"
            cls.run_command(["xcrun", "--sdk", "macosx", "metal", "-c",
                             str(SCENE / "Rendering/Composition/SceneImageLayer.metal"), "-o", str(air)])
            cls.run_command(["xcrun", "--sdk", "macosx", "metallib", str(air), "-o", str(library)])
            cls.run_command(["swiftc", *map(str, SOURCES), str(harness),
                             "-module-cache-path", str(root / "module-cache"), "-o", str(binary)])
            cls.result = json.loads(cls.run_command([str(binary), str(library)]))
        if cls.result.get("metalUnavailable"):
            raise unittest.SkipTest("Metal unavailable")

    @staticmethod
    def run_command(command):
        run = subprocess.run(command, capture_output=True, text=True, timeout=120)
        if run.returncode:
            raise RuntimeError(run.stdout + run.stderr)
        return run.stdout

    def assert_pixel(self, frame, point, expected):
        for actual, wanted in zip(self.result[frame][point], expected):
            self.assertAlmostEqual(actual, wanted, delta=1, msg=f"{frame}.{point}")

    def test_posed_provider_moves_target_coverage_and_keeps_healthy_part(self):
        self.assert_pixel("left", "left", [160, 80, 40, 255])
        self.assert_pixel("left", "right", [0, 0, 0, 0])
        self.assert_pixel("right", "left", [0, 0, 0, 0])
        self.assert_pixel("right", "right", [160, 80, 40, 255])
        for frame in ("left", "right", "failed"):
            self.assert_pixel(frame, "healthy", [0, 200, 0, 255])

    def test_black_gray_paint_and_next_failure_never_leak_unclipped_target(self):
        self.assert_pixel("gray", "left", [80, 40, 20, 128])
        self.assert_pixel("gray", "right", [0, 0, 0, 0])
        for frame in ("black", "failed"):
            for point in ("left", "right"):
                self.assert_pixel(frame, point, [0, 0, 0, 0])
        for frame in ("black", "gray"):
            self.assert_pixel(frame, "healthy", [0, 200, 0, 255])
        self.assertEqual(self.result["movementReleases"], 2)
        self.assertEqual(len(self.result["movementAttempts"]), 3)

    def test_self_source_does_not_create_coverage_or_false_cycle(self):
        self.assert_pixel("selfCandidate", "left", [160, 80, 40, 255])
        self.assert_pixel("selfCandidate", "right", [0, 0, 0, 0])
        for point in ("left", "right"):
            self.assert_pixel("selfOnly", point, [0, 0, 0, 0])
        self.assert_pixel("selfOnly", "healthy", [0, 200, 0, 255])

    def test_overlapping_opaque_providers_do_not_accumulate_gray_paint(self):
        self.assert_pixel("overlap", "left", [80, 40, 20, 128])
        self.assert_pixel("overlap", "right", [0, 0, 0, 0])
        self.assert_pixel("overlap", "healthy", [0, 200, 0, 255])

    def test_unsupported_provider_alpha_fails_locally_and_can_recover(self):
        self.assertEqual(self.result["unsupportedAlphaAttempts"], [])
        for point in ("left", "right"):
            self.assert_pixel("unsupportedAlpha", point, [0, 0, 0, 0])
        self.assert_pixel("unsupportedAlpha", "healthy", [0, 200, 0, 255])
        self.assert_pixel("restoredAlpha", "left", [160, 80, 40, 255])
        self.assert_pixel("restoredAlpha", "right", [0, 0, 0, 0])
        self.assert_pixel("restoredAlpha", "healthy", [0, 200, 0, 255])

    def test_nested_mask_and_cycle_failures_are_local(self):
        self.assert_pixel("nested", "left", [160, 80, 40, 255])
        self.assert_pixel("nested", "right", [0, 0, 0, 0])
        self.assertEqual([row[0] for row in self.result["nestedAttempts"]], [0, 1])
        self.assertEqual(self.result["cycleAttempts"], [])
        for point in ("left", "right"):
            self.assert_pixel("cycle", point, [0, 0, 0, 0])
        for frame in ("nested", "cycle"):
            self.assert_pixel(frame, "healthy", [0, 200, 0, 255])

    def test_missing_paint_dependency_does_not_spend_independent_component_budget(self):
        self.assertEqual([row[0] for row in self.result["localBudgetAttempts"]], [2])
        self.assertEqual(self.result["localBudgetReleases"], 1)
        self.assert_pixel("missingPaint", "left", [0, 0, 0, 0])
        self.assert_pixel("missingPaint", "right", [0, 200, 0, 255])

    def test_empty_clipped_source_preserves_healthy_union_coverage(self):
        self.assertEqual([row[0] for row in self.result["emptySourceAttempts"]], [1])
        self.assert_pixel("emptySource", "left", [160, 80, 40, 255])
        self.assert_pixel("emptySource", "right", [0, 0, 0, 0])
        self.assert_pixel("emptySource", "healthy", [0, 200, 0, 255])

    def test_perspective_roi_bounds_interior_sampling_density(self):
        requests = self.result["roiAttempts"]
        self.assertEqual(len(requests), 1)
        self.assertGreaterEqual(requests[0][1], 127)

    def test_fifty_thousand_nested_records_do_not_exhaust_stack(self):
        self.assertEqual(self.result["chainCount"], 50_000)
        self.assertEqual(self.result["chainAttempts"], [])
        self.assert_pixel("chain", "center", [0, 200, 0, 255])
