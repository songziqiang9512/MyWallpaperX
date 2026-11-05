import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

extension Harness {
    static func rootWorldRopeReference() throws -> [String: Any] {
        let input = try TranslationInput()
        func particle(_ path: String, force: Bool = false,
                      edit: (inout [String: Any]) -> Void = { _ in }) throws {
            try input.particle(path) { value in
                value["renderer"] = [["name": "rope", "subdivision": 0, "orientation": "screen"]]
                value["controlpoint"] = [["id": 0, "flags": 0], ["id": 1, "flags": 1]]
                if force {
                    value["operator"] = [["name": "movement", "gravity": "0 0 0"],
                        ["name": "controlpointattract", "controlpoint": 1, "scale": 60]]
                }
                edit(&value)
            }
        }
        func world(_ position: SIMD3<Double>, reference: simd_float4x4) -> SIMD3<Float> {
            let model = SceneParticleCameraFrame.particleLayerModel(worldFrame: reference, parallaxOffset: .zero)
            let p = model * SIMD4(Float(position.x), Float(position.y), Float(position.z), 1)
            return SIMD3(p.x, p.y, p.z)
        }
        func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool { simd_distance(a, b) < 0.002 }
        func vector(_ p: SIMD3<Float>) -> [Float] { [p.x, p.y, p.z] }
        var checks: [String: Bool] = [:], rows: [[String: Any]] = []
        for (id, name, angle) in [(81, "steam", Float(0)), (781, "renamed-reference", Float.pi / 2)] {
            let path = "particles/\(name).json", forcePath = "particles/\(name)-force.json"
            let peerPath = "particles/\(name)-local.json"
            try particle(path); try particle(forcePath, force: true)
            try input.particle(peerPath, world: false)
            var root = input.layer(id, path)
            root.scaleXYZ = [2, 3, 1]; root.anglesXYZ = [0, 0, angle]
            if id == 781 { root.originHasScript = false; root.timelines = [.init(host: .origin)] }
            let peer = input.layer(id + 1, peerPath, writer: false)
            let descriptor = input.descriptor([root, peer], authoredProjection: true)
            let origins = [SIMD3<Double>(100, 200, 0), SIMD3(140, 260, 0), SIMD3(180, 220, 0)]
            let snapshots = origins.map { input.snapshot([id: $0]) }
            let frames = snapshots.map { input.frames(descriptor, $0) }
            let runtime = input.runtime(descriptor, initial: snapshots[0])
            guard let sim = runtime.playbackSimulators.first(where: { $0.0 == id })?.1,
                  let reference = sim.rootWorldTranslation?.referenceWorldFrame else {
                checks[name + "-admitted"] = false; rows.append(["name": name, "active": runtime.activeLayerIDs]); continue
            }
            var populations: [[SIMD3<Float>]] = [], batches: [SceneParticleDrawBatch] = []
            for index in snapshots.indices {
                batches = runtime.advance(by: 1.0 / 60, dynamicValues: snapshots[index], layerWorldFrames: frames[index])
                populations.append(sim.particles.map { world($0.position, reference: reference) })
            }
            let expected = [SIMD3<Float>(100, 600, 0), SIMD3(140, 540, 0), SIMD3(180, 580, 0)]
            checks[name + "-admitted"] = true
            checks[name + "-old-world-points-and-current-birth"] = populations.map(\.count) == [1, 2, 3]
                && populations.enumerated().allSatisfy { row, points in
                    points.enumerated().allSatisfy { index, point in index <= row && near(point, expected[index]) }
                }
            let rope = batches.first { $0.layerID == id }
            let centers = rope?.instances.map { value in
                world(SIMD3(Double(value.positionAndSize.x), Double(value.positionAndSize.y),
                    Double(value.positionAndSize.z)), reference: reference)
            } ?? []
            checks[name + "-actual-connected-rope"] = centers.count == 2
                && near(centers[0], SIMD3(120, 570, 0)) && near(centers[1], SIMD3(160, 560, 0))
                && rope?.referenceWorldFrame == reference
            let prefix = input.snapshot([id: SIMD3(220, 180, 0)]), prefixFrames = input.frames(descriptor, prefix)
            let context = try runtime.emissionContext(layerID: id, dynamicValues: prefix,
                pointerLocalPosition: nil, audio: .silent, worldFrame: prefixFrames[id])
            let before = sim.frameSnapshot()
            let candidate = try sim.preparePlaybackCandidate(commands: [
                (.init(layerID: id, action: .emit, revision: 1, count: 1), context)
            ], charge: { _, _ in }, release: { _ in })
            checks[name + "-explicit-prefix-birth"] = candidate.state.particles.count == before.particles.count + 1
                && candidate.state.particles.last.map { near(world($0.position, reference: reference), SIMD3(220, 620, 0)) } == true
                && sim.particles == before.particles
            sim.restoreFrame(candidate.state)
            let peerTime = runtime.playbackSimulators.first { $0.0 == id + 1 }!.1.simulationTime
            let stable = sim.frameSnapshot()
            var invalid = prefixFrames
            invalid[id]!.columns.3.z += 1
            _ = runtime.advance(by: 0.25, dynamicValues: prefix, layerWorldFrames: invalid)
            checks[name + "-bad-z-local-freeze"] = sim.particles == stable.particles
                && sim.simulationTime == stable.simulationTime
                && runtime.playbackSimulators.first { $0.0 == id + 1 }!.1.simulationTime > peerTime
            _ = runtime.advance(by: 1.0 / 60, dynamicValues: prefix, layerWorldFrames: prefixFrames)
            checks[name + "-recovers-with-same-reference"] = sim.simulationTime > stable.simulationTime
                && sim.rootWorldTranslation?.referenceWorldFrame == reference

            var forceLayer = input.layer(id, forcePath)
            forceLayer.scaleXYZ = root.scaleXYZ; forceLayer.anglesXYZ = root.anglesXYZ
            forceLayer.originHasScript = root.originHasScript; forceLayer.timelines = root.timelines
            let forceDescriptor = input.descriptor([forceLayer], authoredProjection: true)
            var staticLayer = forceLayer; staticLayer.originHasScript = false; staticLayer.timelines = []
            var staticDescriptor = input.descriptor([staticLayer])
            staticDescriptor.camera = forceDescriptor.camera
            let dynamic = input.runtime(forceDescriptor, initial: snapshots[0])
            let stationary = input.runtime(staticDescriptor)
            let pointer = SIMD3<Double>(40, 0, 0)
            let movedPointer = angle == 0 ? SIMD3<Double>(20, -20, 0) : SIMD3<Double>(10, 40.0 / 3, 0)
            for index in 0..<2 {
                let currentPointer = index == 0 ? pointer : movedPointer
                _ = dynamic.advance(by: 1.0 / 60, dynamicValues: snapshots[index],
                    pointerLocalPositions: [id: currentPointer], layerWorldFrames: input.frames(forceDescriptor, snapshots[index]))
                _ = stationary.advance(by: 1.0 / 60, pointerLocalPositions: [id: pointer],
                    layerWorldFrames: input.frames(staticDescriptor, .empty(frameIndex: 0)))
            }
            let movingSim = dynamic.playbackSimulators.first { $0.0 == id }?.1
            let fixedSim = stationary.playbackSimulators.first { $0.0 == id }?.1
            var forceErrors: [Double] = []
            if let movingSim, let fixedSim, let moving = movingSim.particles.first, let fixed = fixedSim.particles.first {
                let positionError = simd_distance(moving.position, fixed.position)
                let velocityError = simd_distance(moving.velocity, fixed.velocity)
                forceErrors = [positionError, velocityError]
                // The authored pi/2 basis travels through Float world matrices;
                // the independent current-local pointer is a Double literal.
                checks[name + "-force-retained-in-reference"] = simd_length(moving.velocity) > 0
                    && positionError < 1e-6 && velocityError < 1e-6
                    && movingSim.dynamicControlPoints[1] == movedPointer
                checks[name + "-current-model-pointer-demand"] = dynamic.pointerControlPointDemands.contains(id)
                    && stationary.pointerControlPointDemands.contains(id)
                let emission = try dynamic.emissionContext(layerID: id, dynamicValues: snapshots[1],
                    pointerLocalPosition: movedPointer, audio: .silent,
                    worldFrame: input.frames(forceDescriptor, snapshots[1])[id])
                checks[name + "-explicit-force-target-reference"] = emission.controlPoints[1] == movedPointer
            } else { checks[name + "-force-retained-in-reference"] = false }
            rows.append(["name": name, "populations": populations.map { $0.map(vector) },
                "ropeCenters": centers.map(vector), "dynamicPointerDemand": dynamic.pointerControlPointDemands.sorted(),
                "forceErrors": forceErrors])
        }
        try input.particle("particles/safe-peer.json", world: false)
        for mode in ["flags2", "nonzero-origin", "birth-pointer", "position-around", "refraction"] {
            let path = "particles/rejected-\(mode).json"
            try particle(path, force: true) { value in
                switch mode {
                case "flags2": value["controlpoint"] = [["id": 0, "flags": 0], ["id": 1, "flags": 2]]
                case "nonzero-origin": value["operator"] = [["name": "controlpointattract", "controlpoint": 1,
                    "origin": "1 0 0", "scale": 60]]
                case "birth-pointer": value["emitter"] = [["name": "boxrandom", "rate": 60, "controlpoint": 1]]
                case "position-around": value["initializer"] = [["name": "mapsequencearoundcontrolpoint",
                    "controlpoint": 1, "bounds": "0 1", "count": 4, "speedmin": "1 1 0",
                    "speedmax": "1 1 0", "limitbehavior": "repeat"]]
                default: value["material"] = "materials/refract-owned.json"
                }
            }
            let layers = [input.layer(891, path), input.layer(892, "particles/safe-peer.json", writer: false)]
            let base = input.descriptor(layers, authoredProjection: true)
            var descriptor = mode == "refraction" ? SceneRenderDescriptor(layers: layers, renderOrderLayerIDs: layers.map(\.id),
                materialPasses: base.materialPasses + [.init(materialPath: "materials/refract-owned.json",
                    shaderPath: "genericparticle", texturePaths: ["_rt_FullFrameBuffer"], blending: "translucent", combos: ["REFRACT": 1])]) : base
            descriptor.camera = base.camera
            let rejected = input.runtime(descriptor)
            let batches = rejected.advance(by: 1.0 / 60, pointerLocalPositions: [891: SIMD3(40, 0, 0)],
                layerWorldFrames: input.frames(descriptor, .empty(frameIndex: 0)))
            if mode == "refraction" {
                checks[mode + "-missing-color-stays-local"] = !rejected.activeLayerIDs.contains(891)
                    && rejected.activeLayerIDs.contains(892)
                    && batches.allSatisfy { $0.layerID != 891 }
            } else {
                checks[mode + "-root-remains-active"] = rejected.activeLayerIDs.contains(891)
                    && rejected.activeLayerIDs.contains(892)
                    && batches.contains { $0.layerID == 891 && $0.referenceWorldFrame != nil }
            }
        }
        return ["checks": checks, "rows": rows]
    }

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
        var facts1: [String: Any] = [
            "demandedLayerIDs": runtime.pointerControlPointDemands.sorted(),
            "activeLayerIDs": runtime.activeLayerIDs,
            "positionCount": positions.count,
            "positions": positions,
        ]
#if DEBUG
        facts1["diagnosticKinds"] = runtime.diagnostics.map(\.kind.rawValue)
#endif
        return facts1
    }

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
        var facts2: [String: Any] = [
            "demandedLayerIDs": runtime.pointerControlPointDemands.sorted(),
            "positions": positions,
        ]
#if DEBUG
        facts2["diagnosticKinds"] = runtime.diagnostics.map(\.kind.rawValue)
#endif
        return facts2
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
        let demand = runtime.pointerControlPointDemands.sorted()
        // Pointer at +X with a negative-scale attract: particles near the
        // origin accelerate away from the pointer (negative X).
        let withPointer = positionsAfterAdvances(pointer: SIMD3(60, 0, 0))
        let withoutPointer = positionsAfterAdvances(pointer: nil)
        var facts3: [String: Any] = [
            "demandedLayerIDs": demand,
            "withPointerPositions": withPointer,
            "withoutPointerPositions": withoutPointer,
        ]
#if DEBUG
        facts3["diagnosticKinds"] = runtime.diagnostics.map(\.kind.rawValue)
#endif
        return facts3
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
        var facts4: [String: Any] = [
            "activeLayerIDs": runtime.activeLayerIDs,
            "instanceCount": ropeInstances.count,
            "firstPositions": positions,
            "demandedLayerIDs": runtime.pointerControlPointDemands.sorted(),
        ]
#if DEBUG
        facts4["diagnosticKinds"] = runtime.diagnostics.map(\.kind.rawValue)
        facts4["ropeDiagnostic"] = runtime.diagnostics.contains {
            $0.kind == .ropeRendererUnsupported && $0.layerID == 111
        }
#endif
        return facts4
    }

    static func syntheticAudioBoundsGate() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-audio-bounds-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        func writeGatedParticle(_ path: String, mode: Int?, pointer: Bool = false) throws {
            var emitter: [String: Any] = [
                "name": "sphererandom", "rate": 120,
                "distancemin": 0, "distancemax": 0,
                "audioprocessingbounds": "0.8 1",
            ]
            if let mode { emitter["audioprocessingmode"] = mode }
            if pointer { emitter["controlpoint"] = 1 }
            try writeJSON([
                "material": "materials/shared.json", "maxcount": 100,
                "controlpoint": pointer ? [["id": 1, "flags": 1, "offset": "0 0 0"]] : [],
                "emitter": [emitter],
                "initializer": [
                    ["name": "lifetimerandom", "min": 10, "max": 10],
                    ["name": "sizerandom", "min": 8, "max": 8],
                ],
                "renderer": [["name": "sprite"]],
            ], to: directory.appendingPathComponent(path))
        }
        try writeGatedParticle("particles/bounds-only.json", mode: nil)
        try writeGatedParticle("particles/explicit-off.json", mode: 0)
        try writeGatedParticle("particles/mode-center.json", mode: 3)
        let childPath = "particles/renamed-ink-child.json"
        let parentPath = "particles/renamed-ink-root.json"
        try writeGatedParticle(childPath, mode: nil, pointer: true)
        try writeParticle(parentPath, material: "materials/shared.json", rate: 0, instantaneous: 1,
            children: [["name": childPath, "type": "static"]], under: directory)
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
                    layers: [layer(101, path)], renderOrderLayerIDs: [101],
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
        func shape(_ runtime: SceneParticleRuntime, audio: SceneParticleAudioInput) -> [[Float]] {
            var batches: [SceneParticleDrawBatch] = []
            for _ in 0..<4 {
                batches = runtime.advance(by: 1.0 / 60.0, audioInput: audio)
            }
            return batches.flatMap { $0.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z, $0.positionAndSize.w]
            } }
        }
        let boundsOnly = runtimeFor("particles/bounds-only.json")
        let silent = shape(boundsOnly, audio: .silent)
        let active = shape(
            runtimeFor("particles/bounds-only.json"), audio: loud
        )
        let offSilent = shape(runtimeFor("particles/explicit-off.json"), audio: .silent)
        let offActive = shape(runtimeFor("particles/explicit-off.json"), audio: loud)
        let modeCenter = runtimeFor("particles/mode-center.json")
        let modeSilent = shape(modeCenter, audio: .silent)
        let modeActive = shape(runtimeFor("particles/mode-center.json"), audio: loud)
        let childRuntime = runtimeFor(parentPath)
        var childPositions: [[[Float]]] = []
        for pointer in [SIMD3<Double>(40, 60, 0), SIMD3<Double>(140, 180, 0)] {
            var batches: [SceneParticleDrawBatch] = []
            for _ in 0..<4 {
                batches = childRuntime.advance(by: 1.0 / 60.0,
                    pointerLocalPositions: [101: pointer], audioInput: .silent)
            }
            childPositions.append(batches.filter { $0.particlePath == childPath }.flatMap { $0.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } })
        }
        return [
            "boundsOnlySilentCount": silent.count,
            "boundsOnlyLoudCount": active.count,
            "boundsOnlyMatchesOff": silent == offSilent && active == offActive,
            "boundsOnlyIgnoresAudio": silent == active,
            "modeCenterSilentCount": modeSilent.count,
            "modeCenterLoudCount": modeActive.count,
            "childPositions": childPositions,
            "childPointerDemand": childRuntime.pointerControlPointDemands.sorted(),
            "childHasAudioConsumer": childRuntime.hasAudioConsumer,
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
        var facts5: [String: Any] = [
            "pointerDemandLayerIDs": runtime.pointerControlPointDemands.sorted(),
            "positions": positions,
        ]
#if DEBUG
        facts5["diagnosticKinds"] = runtime.diagnostics.map(\.kind.rawValue)
#endif
        return facts5
    }

}
