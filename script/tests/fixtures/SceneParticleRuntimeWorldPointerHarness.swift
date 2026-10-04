import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

extension Harness {
    static func realPointerDemand(
        evidencePath: String,
        cachePath: String,
        layerID: Int,
        pointer: SIMD3<Double>
    ) throws -> [String: Any] {
        let cache = URL(fileURLWithPath: cachePath, isDirectory: true)
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: cache,
            device: device
        )
        var batches: [SceneParticleDrawBatch] = []
        for _ in 0..<4 {
            batches = runtime.advance(
                by: 1.0 / 60.0,
                pointerLocalPositions: [layerID: pointer]
            )
        }
        let layerBatches = batches.filter { $0.layerID == layerID }
        let positions = layerBatches.flatMap { $0.instances.map {
            [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
        } }
        return [
            "demandedLayerIDs": Array(runtime.pointerControlPointLayerIDs),
            "activeLayerIDs": runtime.activeLayerIDs,
            "positionCount": positions.count,
            "positions": positions,
            "diagnosticKinds": runtime.diagnostics.map(\.kind.rawValue),
        ]
    }

    /// Audio response gates emission through authored bounds alone: the
    /// editor writes `audioprocessingbounds` for an audio-gated emitter and
    /// `audioprocessingmode` only selects the channel. A bounds-only emitter
    /// (corpus: 8 emitters / 8 samples, e.g. 3665307769 red_fire) must stay
    /// silent without audio and emit with it.
    /// The pointer-trail rope family (2986218263 and five more samples):
    /// world system, pointer-locked CP0 with an implicit emitter source, and
    /// a rope renderer with flags=1 / subdivision=100 / maxcount=256.
    /// The mouse-repel family (1994794519 / 3078285611 / 3396722575): a
    /// world/perspective system whose pointer CP1 drives a negative-scale
    /// controlpointattract. The pointer value is the layer-local
    /// unprojection and the force composes positions entirely in local
    /// space, so the demand shares the emitter path's space pairing.
    /// positionaroundcontrolpoint (authored as mapsequencearoundcontrolpoint)
    /// on a pointer CP in a world system: births distribute around the
    /// pointer's layer-local position. Same-family release as the force path
    /// (no newly affected corpus consumer in the current shape).
    static func syntheticWorldSpacePointerPositionAround() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-worldspace-posaround-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 100, "flags": 1,
            "controlpoint": [
                ["id": 0, "flags": 0, "offset": "0 0 0"],
                ["id": 1, "flags": 1, "offset": "0 0 0"],
            ],
            "emitter": [[
                "name": "sphererandom", "rate": 120,
                "distancemin": 20, "distancemax": 50, "controlpoint": 1,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "sizerandom", "min": 8, "max": 8],
                [
                    "name": "mapsequencearoundcontrolpoint", "controlpoint": 1,
                    "bounds": "0 1", "count": 4,
                    "speedmin": "10 10 0", "speedmax": "10 10 0",
                    "limitbehavior": "repeat",
                ],
            ],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/world-posaround.json"))
        let descriptor = SceneRenderDescriptor(
            layers: [layer(131, "particles/world-posaround.json")],
            renderOrderLayerIDs: [131],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        let pointer = SIMD3<Double>(60, 40, 0)
        var batches: [SceneParticleDrawBatch] = []
        for _ in 0..<4 {
            batches = runtime.advance(
                by: 1.0 / 60.0,
                pointerLocalPositions: [131: pointer]
            )
        }
        let positions = (batches.first { $0.layerID == 131 })?.instances.map {
            [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
        } ?? []
        return [
            "demandedLayerIDs": Array(runtime.pointerControlPointLayerIDs),
            "positions": positions,
            "diagnosticKinds": runtime.diagnostics.map(\.kind.rawValue),
        ]
    }

    static func syntheticWorldSpacePointerForce() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-worldspace-force-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 100, "flags": 1,
            "controlpoint": [
                ["id": 0, "flags": 0, "offset": "0 0 0"],
                ["id": 1, "flags": 1, "offset": "0 0 0"],
            ],
            "emitter": [[
                "name": "sphererandom", "rate": 120,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 10, "max": 10],
                ["name": "sizerandom", "min": 8, "max": 8],
            ],
            "operator": [
                ["name": "movement"],
                [
                    "name": "controlpointattract", "controlpoint": 1,
                    "scale": -10000, "threshold": 128,
                ],
            ],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/world-force.json"))
        let descriptor = SceneRenderDescriptor(
            layers: [layer(121, "particles/world-force.json")],
            renderOrderLayerIDs: [121],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        func positionsAfterAdvances(pointer: SIMD3<Double>?) -> [[Float]] {
            let runtime = SceneParticleRuntime(
                descriptor: descriptor,
                cacheDirectory: directory,
                device: device
            )
            var batches: [SceneParticleDrawBatch] = []
            for _ in 0..<4 {
                batches = runtime.advance(
                    by: 1.0 / 60.0,
                    pointerLocalPositions: pointer.map { [121: $0] } ?? [:]
                )
            }
            return (batches.first { $0.layerID == 121 })?.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? []
        }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        _ = runtime.advance(by: 1.0 / 60.0)
        let demand = Array(runtime.pointerControlPointLayerIDs)
        // Pointer at +X with a negative-scale attract: particles near the
        // origin accelerate away from the pointer (negative X).
        let withPointer = positionsAfterAdvances(pointer: SIMD3(60, 0, 0))
        let withoutPointer = positionsAfterAdvances(pointer: nil)
        return [
            "demandedLayerIDs": demand,
            "withPointerPositions": withPointer,
            "withoutPointerPositions": withoutPointer,
            "diagnosticKinds": runtime.diagnostics.map(\.kind.rawValue),
        ]
    }

    static func syntheticWorldSpaceRopeTrail() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-worldspace-rope-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 256, "flags": 1,
            "controlpoint": [["id": 0, "flags": 1, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 120, "flags": 2,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 0.5, "max": 0.5],
                ["name": "sizerandom", "min": 8, "max": 8],
            ],
            "renderer": [["name": "rope", "flags": 1, "subdivision": 100]],
        ], to: directory.appendingPathComponent("particles/world-rope.json"))
        let descriptor = SceneRenderDescriptor(
            layers: [layer(111, "particles/world-rope.json")],
            renderOrderLayerIDs: [111],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        // The trail is the birth history: hold the pointer at two positions
        // so particles cluster around both and the connecting rope has real
        // extent.
        var batches: [SceneParticleDrawBatch] = []
        for pointer in [SIMD3<Double>(40, 60, 0), SIMD3<Double>(240, 180, 0)] {
            for _ in 0..<6 {
                batches = runtime.advance(
                    by: 1.0 / 60.0,
                    pointerLocalPositions: [111: pointer]
                )
            }
        }
        let ropeInstances = (batches.first { $0.layerID == 111 })?.instances ?? []
        let positions = ropeInstances.prefix(4).map {
            [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
        }
        return [
            "activeLayerIDs": runtime.activeLayerIDs,
            "instanceCount": ropeInstances.count,
            "firstPositions": positions,
            "demandedLayerIDs": Array(runtime.pointerControlPointLayerIDs),
            "diagnosticKinds": runtime.diagnostics.map(\.kind.rawValue),
            "ropeDiagnostic": runtime.diagnostics.contains {
                $0.kind == .ropeRendererUnsupported && $0.layerID == 111
            },
        ]
    }

    static func syntheticAudioBoundsGate() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-audio-bounds-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        func writeGatedParticle(_ path: String, mode: Int?) throws {
            var emitter: [String: Any] = [
                "name": "sphererandom", "rate": 120,
                "distancemin": 0, "distancemax": 0,
                "audioprocessingbounds": "0.8 1",
            ]
            if let mode { emitter["audioprocessingmode"] = mode }
            try writeJSON([
                "material": "materials/shared.json", "maxcount": 100,
                "emitter": [emitter],
                "initializer": [
                    ["name": "lifetimerandom", "min": 10, "max": 10],
                    ["name": "sizerandom", "min": 8, "max": 8],
                ],
                "renderer": [["name": "sprite"]],
            ], to: directory.appendingPathComponent(path))
        }
        try writeGatedParticle("particles/bounds-only.json", mode: nil)
        try writeGatedParticle("particles/mode-center.json", mode: 3)
        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(101, "particles/bounds-only.json"),
                layer(102, "particles/mode-center.json"),
            ],
            renderOrderLayerIDs: [101, 102],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        func runtimeFor(_ path: String) -> SceneParticleRuntime {
            SceneParticleRuntime(
                descriptor: SceneRenderDescriptor(
                    layers: [layer(path == "particles/bounds-only.json" ? 101 : 102, path)],
                    renderOrderLayerIDs: [path == "particles/bounds-only.json" ? 101 : 102],
                    materialPasses: descriptor.materialPasses
                ),
                cacheDirectory: directory,
                device: device
            )
        }
        let loud = SceneParticleAudioInput(
            left: Array(repeating: 1, count: SceneParticleAudioInput.bandCount),
            right: Array(repeating: 1, count: SceneParticleAudioInput.bandCount),
            generation: 1
        )
        func counts(_ runtime: SceneParticleRuntime, audio: SceneParticleAudioInput) -> Int {
            var batches: [SceneParticleDrawBatch] = []
            for _ in 0..<4 {
                batches = runtime.advance(by: 1.0 / 60.0, audioInput: audio)
            }
            return batches.reduce(0) { $0 + $1.instances.count }
        }
        let boundsOnly = runtimeFor("particles/bounds-only.json")
        let silentCount = counts(boundsOnly, audio: .silent)
        let loudCount = counts(
            runtimeFor("particles/bounds-only.json"), audio: loud
        )
        let modeCenter = runtimeFor("particles/mode-center.json")
        let modeSilentCount = counts(modeCenter, audio: .silent)
        return [
            "boundsOnlySilentCount": silentCount,
            "boundsOnlyLoudCount": loudCount,
            "modeCenterSilentCount": modeSilentCount,
        ]
    }

    static func syntheticWorldSpacePointerEmitter() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-worldspace-pointer-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 100, "flags": 1,
            "controlpoint": [["id": 1, "flags": 1, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 120, "controlpoint": 1,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 0.5, "max": 0.5],
                ["name": "sizerandom", "min": 8, "max": 8],
            ],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/world-pointer.json"))
        let descriptor = SceneRenderDescriptor(
            layers: [layer(91, "particles/world-pointer.json")],
            renderOrderLayerIDs: [91],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        let pointer = SIMD3<Double>(40, 60, 0)
        var batches: [SceneParticleDrawBatch] = []
        for _ in 0..<3 {
            batches = runtime.advance(
                by: 1.0 / 60.0,
                pointerLocalPositions: [91: pointer]
            )
        }
        let positions = (batches.first { $0.layerID == 91 })?.instances.map {
            [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
        } ?? []
        return [
            "pointerDemandLayerIDs": Array(runtime.pointerControlPointLayerIDs),
            "positions": positions,
            "diagnosticKinds": runtime.diagnostics.map(\.kind.rawValue),
        ]
    }

}
