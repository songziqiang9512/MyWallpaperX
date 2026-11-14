import Foundation
import Metal

/// Real Reader -> resource preparation. Only descriptor/texture transport is
/// supplied by the enclosing parts fixture; selection remains production code.
enum SceneStaticModelMaterialSelectionChecks {
    static func run(root: URL, device: MTLDevice) throws -> [String: Bool] {
        let directory = root.appendingPathComponent("parts8")
        var bytes = try Data(contentsOf: directory.appendingPathComponent("models/parts.mdl"))
        let original = Data("materials/part007.json".utf8)
        let invalidTypedPath = Data("materials/part\u{7f}07.json".utf8)
        precondition(original.count == invalidTypedPath.count)
        bytes.replaceSubrange(bytes.range(of: original)!, with: invalidTypedPath)
        let parts = try SceneMdlStaticModelReader.readParts(data: bytes)
        let peer = try SceneMdlStaticModelReader.readParts(
            data: Data(contentsOf: directory.appendingPathComponent("models/peer.mdl")))
        precondition(parts.count == 8 && parts[7].materialPath.contains("\u{7f}"))
        var checks: [String: Bool] = [:]
        for reversed in [false, true] {
            let mode = reversed ? "reordered" : "first"
            let result = try autoreleasepool {
                try prepare(directory: directory, parts: parts, peer: peer,
                            reversed: reversed, device: device)
            }
            checks.merge(result.map { (mode + ":" + $0.key, $0.value) }, uniquingKeysWith: { $1 })
        }
        checks.merge(try planChecks(view: .init(root: directory)), uniquingKeysWith: { $1 })
        checks.merge(try launchChecks(directory: directory, parts: parts, peer: peer, device: device),
                     uniquingKeysWith: { $1 })
        return checks
    }

    static func planChecks(view: SceneResourceView) throws -> [String: Bool] {
        var nonDirect = pass("materials/nondirect.json")
        nonDirect.staticModelMaterialBindings = nil
        var explicit = pass("materials/explicit.json", texture: "materials/absent.png")
        explicit.staticModelDefaultAlbedoAssetPath = "materials/peer.png"
        var omitted = SceneRenderDescriptor.MaterialPassDescriptor(materialPath: "materials/default.json",
            textureSlots: [], combos: ["LIGHTING": 0], constantShaderValues: [:])
        omitted.staticModelDefaultAlbedoAssetPath = "materials/peer.png"
        let winner = pass("./MATERIALS/shared.json", alpha: 0.375)
        let descriptor = SceneRenderDescriptor(lighting: nil, layers: [], renderOrderLayerIDs: [], materialPasses: [
            pass("materials/rejected.json", rejected: true), pass("./materials/rejected.json"),
            nonDirect, pass("./materials/nondirect.json"), winner,
            pass("materials/shared.json", texture: "materials/peer.png"),
            pass("materials/nonzero.json", index: 1), pass("materials/nonzero.json"),
            pass("materials/named.json", texture: "_rt_imageLayerComposite_91_a"), explicit, omitted])
        let plan = try ScenePreparedStaticModelResources.compileMaterialPlan(
            descriptor: descriptor, resourceView: view, cancellationCheck: {})
        func item(_ name: String) -> ScenePreparedStaticModelResources.MaterialPlan.Item? {
            plan.materialsByPath[SceneVFSAssetPath("materials/" + name + ".json")!]
        }
        let common = SceneAssetTextureIdentity(virtualPath: "materials/part000.png", purpose: .straightAlbedo)!
        let absent = SceneAssetTextureIdentity(virtualPath: "materials/absent.png", purpose: .straightAlbedo)!
        let fallback = SceneAssetTextureIdentity(virtualPath: "materials/peer.png", purpose: .straightAlbedo)!
        return [
            "plan-first-rejected-not-replaced": item("rejected") == nil,
            "plan-first-nondirect-not-replaced": item("nondirect") == nil,
            "plan-first-alias-keeps-material": item("shared")?.material.opacity == 0.375,
            "plan-nonzero-does-not-shadow-zero": item("nonzero")?.albedoSource == .asset(common),
            "plan-named-keeps-reference": item("named")?.albedoSource == .named(.parse("_rt_imageLayerComposite_91_a")!),
            "plan-explicit-missing-keeps-source": item("explicit")?.albedoSource == .asset(absent),
            "plan-omitted-selects-default": item("default")?.albedoSource == .asset(fallback),
            "plan-demands-deduplicate-assets": plan.assetDemands == [common, absent, fallback]
        ]
    }

    private static func launchChecks(directory: URL, parts: [SceneMdlStaticModel],
                                     peer: [SceneMdlStaticModel], device: MTLDevice) throws -> [String: Bool] {
        let descriptor = SceneRenderDescriptor(lighting: nil,
            layers: [.init(id: 2, staticModelPath: "models/parts.mdl"), .init(id: 1, staticModelPath: "models/peer.mdl")],
            renderOrderLayerIDs: [2, 1], materialPasses: [pass("materials/part000.json"),
                pass("materials/part001.json", texture: "materials/part001.png"),
                pass("materials/peer.json", texture: "materials/peer.png")])
        let view = SceneResourceView(root: directory), loader = try SceneTextureLoader(root: directory, device: device)
        let plan = try ScenePreparedStaticModelResources.compileMaterialPlan(
            descriptor: descriptor, resourceView: view, cancellationCheck: {})
        let assets = try SceneStaticModelAssetInputs(materialPlan: plan, resourceView: view,
            descriptor: descriptor, loader: loader, device: device)
        let identity = SceneAssetTextureIdentity(virtualPath: "materials/part000.png", purpose: .straightAlbedo)!
        let cases: [(String, SceneAssetTextureLaunchState?, Bool)] = [
            ("ready", .ready(.color(.resolved(.straightAlpha))), true),
            ("prepared-video", .preparedVideo(.color(.resolved(.opaque))), true),
            ("absent", .absent, false), ("pending", .pending, false),
            ("unavailable", .unavailable, false), ("missing-key", nil, false),
            ("metadata-local", .effectLocalUnavailable(.animatedFrameMetadataInvalid), false)]
        var checks: [String: Bool] = [:]
        for (name, state, admitted) in cases {
            var states = assets.launchStates; states[identity] = state
            var sources: [String: SceneMdlStaticModel.PreparedSource] = [
                "models/parts.mdl": .init(parts: Array(parts.prefix(2)), animations: nil, attachments: .success([])),
                "models/peer.mdl": .init(parts: peer, animations: nil, attachments: .success([]))]
            let resources = try ScenePreparedStaticModelResources.prepare(descriptor: descriptor, resourceView: view,
                device: device, textureLoader: loader, materialPlan: plan, albedoStates: states,
                preparedSources: &sources, cancellationCheck: {})
            let videoAssets: [Int: Set<SceneAssetTextureIdentity>] = name == "prepared-video" ? [2: [identity]] : [:]
            checks["launch-" + name + "-part-local"] = resources[2]?.count == (admitted ? 2 : 1)
                && resources[1]?.count == 1 && resources.preparedLayerIDs == [1, 2] && sources.isEmpty
                && resources.videoAlbedoAssetsByLayerID == videoAssets
        }
        var absentSources: [String: SceneMdlStaticModel.PreparedSource] = [
            "models/parts.mdl": .init(parts: [parts[0]], animations: nil, attachments: .success([])),
            "models/peer.mdl": .init(parts: peer, animations: nil, attachments: .success([]))]
        var absentStates = assets.launchStates; absentStates[identity] = .absent
        let absentResources = try ScenePreparedStaticModelResources.prepare(descriptor: descriptor, resourceView: view,
            device: device, textureLoader: loader, materialPlan: plan, albedoStates: absentStates,
            preparedSources: &absentSources, cancellationCheck: {})
        checks["launch-cold-missing-layer-not-prepared"] = absentResources[2] == nil
            && absentResources.preparedLayerIDs == [1] && absentResources[1]?.count == 1
        return checks
    }

    private static func pass(
        _ path: String, texture: String = "materials/part000.png",
        index: Int = 0, color: [Double] = [1, 1, 1], alpha: Double = 1,
        rejected: Bool = false, depth: String? = nil
    ) -> SceneRenderDescriptor.MaterialPassDescriptor {
        var value = SceneRenderDescriptor.MaterialPassDescriptor(
            materialPath: path, textureSlots: [texture], combos: ["LIGHTING": 0],
            constantShaderValues: ["color": .init(components: color), "alpha": .init(components: [alpha])],
            passIndex: index, depthWrite: depth)
        if rejected {
            value.staticModelMaterialBindings = .init(
                state: .rejected, bindings: [], rejectionReason: "selection-fixture")
        }
        return value
    }

    private static func prepare(
        directory: URL, parts: [SceneMdlStaticModel], peer: [SceneMdlStaticModel],
        reversed: Bool, device: MTLDevice
    ) throws -> [String: Bool] {
        let winner = pass("./MATERIALS/Part000.JSON", color: [0.25, 0.5, 0.75],
                          alpha: 0.375, depth: "disabled")
        let duplicate = pass("materials\\part000.json", texture: "materials/peer.png",
                             color: [0.75, 0.25, 0.5], alpha: 0.625)
        let rejected = pass("materials/part002.json", rejected: true)
        let admitted = pass("./materials/part002.json", texture: "materials/part002.png")
        let missing = pass("materials/part003.json", texture: "materials/absent.png")
        let available = pass("./materials/part003.json", texture: "materials/part003.png")
        let passes = [pass("/materials/part000.json"), pass("materials/part000.json", index: 2)]
            + (reversed ? [duplicate, winner] : [winner, duplicate])
            + [pass("materials/part001.json", index: 1),
               pass("materials\\part001.json", texture: "materials/part001.png", alpha: 0.5)]
            + (reversed ? [admitted, rejected, available, missing] : [rejected, admitted, missing, available])
            + [pass("materials/part004.json", index: 3), pass("materials//part005.json"),
               pass("materials/part006.json", texture: "materials/part006.png"),
               pass(parts[7].materialPath), pass("materials/peer.json", texture: "materials/peer.png")]
        let layers = [SceneRenderDescriptor.Layer(id: 2, staticModelPath: "models/parts.mdl"),
                      .init(id: 1, staticModelPath: "models/peer.mdl")]
        let descriptor = SceneRenderDescriptor(lighting: nil, layers: layers,
            renderOrderLayerIDs: [2, 1], materialPasses: passes)
        var sources: [String: SceneMdlStaticModel.PreparedSource] = [
            "models/parts.mdl": .init(parts: parts, animations: nil, attachments: .success([])),
            "models/peer.mdl": .init(parts: peer, animations: nil, attachments: .success([]))]
        let loader = try SceneTextureLoader(root: directory, device: device)
        let materialPlan = try ScenePreparedStaticModelResources.compileMaterialPlan(
            descriptor: descriptor, resourceView: .init(root: directory), cancellationCheck: {})
        let assets = try SceneStaticModelAssetInputs(materialPlan: materialPlan, resourceView: .init(root: directory),
            descriptor: descriptor, loader: loader, device: device)
        let resources = try ScenePreparedStaticModelResources.prepare(
            descriptor: descriptor, resourceView: .init(root: directory), device: device,
            textureLoader: loader, materialPlan: materialPlan, albedoStates: assets.launchStates,
            preparedSources: &sources, cancellationCheck: {})
        let renderer = SceneMetalRenderer(device: device, resources: resources)
        assets.publish(to: renderer.textureRegistry)
        let entries = resources[2] ?? []
        let expected = reversed ? [0, 1, 2, 3, 6] : [0, 1, 6]
        let selected = entries.first
        let expectedColor = reversed ? SIMD3<Float>(0.75, 0.25, 0.5) : SIMD3<Float>(0.25, 0.5, 0.75)
        let expectedTexture = reversed ? "peer.png" : "part000.png"
        let expectedAlbedo = loader.candidates[directory.appendingPathComponent("materials/" + expectedTexture)
            .resolvingSymlinksInPath().path]
        let currentAlbedo: SceneTextureCandidate?
        if let selected, case let .asset(identity) = selected.albedoSource {
            currentAlbedo = renderer.textureRegistry.resource(for: .asset(identity))?.publication.candidate
        } else { currentAlbedo = nil }
        return [
            "paths-and-part-order": entries.map(\.materialPath) == expected.map { String(format: "materials/part%03d.json", $0) },
            "first-alias-wins-color-alpha-depth": selected?.material.color == expectedColor
                && selected?.material.opacity == (reversed ? 0.625 : 0.375)
                && selected?.writesDepth == reversed,
            "first-alias-wins-texture": expectedAlbedo != nil && currentAlbedo?.texture === expectedAlbedo?.texture,
            "nonzero-pass-does-not-shadow-zero": entries.first { $0.materialPath == "materials/part001.json" }?.material.opacity == 0.5,
            "invalid-missing-rejected-stay-local": entries.count == expected.count && resources[1]?.count == 1,
            "all-real-meshes": entries.allSatisfy { $0.mesh.indexCount == 6 && $0.mesh.vertexCount == 4 },
            "prepared-sources-consumed": sources.isEmpty
        ]
    }
}
