import Foundation
import simd

// Peripheral immutable DTOs only. MDL parsing, pose preparation, evaluation,
// playback, clipping, geometry, buffers and Metal types are production sources.
struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let puppetMeshPath: String?
        let puppetAnimationLayers: [ScenePuppetAnimationLayer]
        let hasInlineScript: Bool
        let renderSizeWH: [Float]? = [100, 80]
    }
    let layers: [Layer]
}
enum SceneDynamicTarget: Hashable {
    case scriptInstanceProperty(layerID: Int, path: [String])
}
enum SceneDynamicValue { case bool(Bool) }
struct SceneDynamicResolvedValue { let value: SceneDynamicValue }
struct SceneDynamicSnapshot {
    let frameIndex: UInt64
    let values: [SceneDynamicTarget: SceneDynamicResolvedValue]
    subscript(target: SceneDynamicTarget) -> SceneDynamicResolvedValue? { values[target] }
}
struct SceneScriptPuppetBoneMutation {
    let layerID: Int
    let boneIndex: Int
    let matrix: [Double]
}

private func sourceLayer(_ id: Int, mesh: String, animated: Bool = false,
                         script: Bool = false) -> SceneRenderDescriptor.Layer {
    let clip = ScenePuppetAnimationLayer(id: 7, animationID: 101, name: "owned",
        additive: false, blend: 1, blendIn: false, blendOut: false,
        blendTime: 0, rate: 1, visible: true, visibilityBinding: nil)
    return .init(id: id, puppetMeshPath: mesh,
        puppetAnimationLayers: animated ? [clip] : [], hasInlineScript: script)
}

private func describe(_ pose: ScenePuppetLayerLoad.PreparedPose?) throws -> [String: Any] {
    guard let pose else { return ["kind": "none"] }
    switch pose.geometry {
    case let .unavailable(allowsTexture, message):
        return ["kind": "unavailable", "allowsTexture": allowsTexture, "message": message]
    case let .bind(_, fallback):
        return ["kind": "bind", "fallback": fallback ?? "", "animationIDs": []]
    case let .evaluated(_, selection, evaluator, kind):
        let kindName: String
        switch kind {
        case .animation: kindName = "animation"
        case .reference: kindName = "reference"
        case .script: kindName = "script"
        }
        let neutral = try evaluator.boneTransforms(
            selection: .init(clips: [], composition: .layered), frameSamples: [])
        let samples = selection.clips.map { _ in
            ScenePuppetAnimationEvaluator.FrameSample(frameA: 1, frameB: 1)
        }
        let sampled = try evaluator.boneTransforms(selection: selection, frameSamples: samples)
        let points = try evaluator.deformedPositions(selection: selection, frameSamples: samples)
        return ["kind": kindName, "animationIDs": selection.clips.map { $0.animation.id },
            "neutralRootX": neutral.local[0].columns.3.x,
            "sampledRootX": sampled.local[0].columns.3.x,
            "points": points.map { [$0.x, $0.y] }]
    }
}

private func bones(_ asset: ScenePuppetLayerLoad.AssetPreparation) -> [String: Any] {
    guard case let .ready(asset) = asset,
          let configuration = ScenePuppetLayerLoad.boneConfiguration(for: asset) else {
        return ["available": false]
    }
    return ["available": true, "names": configuration.names,
        "parents": configuration.parentIndices,
        "local": configuration.localMatrices, "world": configuration.worldMatrices]
}

private func failure(_ preparation: ScenePuppetLayerLoad.AssetPreparation) -> [String: Any] {
    switch preparation {
    case .ready: return ["kind": "ready"]
    case let .unavailable(allowsTexture, message):
        return ["kind": "unavailable", "allowsTexture": allowsTexture, "message": message]
    }
}

@main
private enum ScenePuppetPreparationCases {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        func asset(_ name: String, animations: Bool = true) -> ScenePuppetLayerLoad.AssetPreparation {
            ScenePuppetLayerLoad.prepareAsset(meshPath: name,
                cacheDirectory: root, needsAnimations: animations)
        }
        var output: [String: Any] = [:]
        var orders: [String: Any] = [:]
        for (label, path, reversed) in [("plain-first", "shared.mdl", false),
                                        ("animated-first", "shared.mdl", true),
                                        ("renamed", "renamed.mdl", false)] {
            let plain = sourceLayer(1, mesh: path)
            let animated = sourceLayer(2, mesh: path, animated: true, script: true)
            let resources = try ScenePreparedPuppetResources.prepare(
                descriptor: .init(layers: reversed ? [animated, plain] : [plain, animated]),
                cacheDirectory: root, cancellationCheck: {})
            orders[label] = ["assetCount": resources.assetsByMeshPath.count,
                "source": try describe(resources.posesByLayerID[2]),
                "default": try describe(resources.defaultPose(for: animated))]
        }
        output["resource-orders"] = orders
        let withSourceScript = sourceLayer(3, mesh: "shared.mdl", animated: true, script: true)
        output["default-reference"] = try describe(ScenePuppetLayerLoad.preparePose(
            for: withSourceScript, asset: asset("shared.mdl"), usesDefaultConfiguration: true))
        let withoutReference = sourceLayer(4, mesh: "bind.mdl", animated: true, script: true)
        output["default-bind"] = try describe(ScenePuppetLayerLoad.preparePose(
            for: withoutReference, asset: asset("bind.mdl"), usesDefaultConfiguration: true))

        var exactBind: [String: Any] = [:]
        for path in ["bind-shear.mdl", "bind-small.mdl"] {
            let prepared = asset(path, animations: false)
            var row = bones(prepared)
            row["pose"] = try describe(ScenePuppetLayerLoad.preparePose(
                for: sourceLayer(5, mesh: path), asset: prepared))
            exactBind[path] = row
        }
        output["exact-bind"] = exactBind
        let badReference = asset("bad-reference.mdl", animations: false)
        output["bad-reference"] = ["bonesAvailable": bones(badReference)["available"]!,
            "pose": try describe(ScenePuppetLayerLoad.preparePose(
                for: sourceLayer(6, mesh: "bad-reference.mdl"), asset: badReference))]

        let retained = asset("reuse.mdl")
        let beforeBones = bones(retained)
        try FileManager.default.removeItem(at: root.appendingPathComponent("reuse.mdl"))
        let retainedLayer = sourceLayer(7, mesh: "reuse.mdl", animated: true, script: true)
        output["reuse"] = ["fileExists": FileManager.default.fileExists(
            atPath: root.appendingPathComponent("reuse.mdl").path),
            "beforeBones": beforeBones, "afterBones": bones(retained),
            "source": try describe(ScenePuppetLayerLoad.preparePose(for: retainedLayer, asset: retained)),
            "default": try describe(ScenePuppetLayerLoad.preparePose(
                for: retainedLayer, asset: retained, usesDefaultConfiguration: true))]

        var failures: [String: Any] = [:]
        for (label, path) in [("missing", "missing.mdl"), ("read", "directory.mdl"),
                               ("parse", "bad-mesh.mdl"), ("path", "../outside.mdl")] {
            failures[label] = failure(asset(path))
        }
        for (label, path, requested) in [("rig", "bad-rig.mdl", true),
                                         ("animation", "bad-animation.mdl", true),
                                         ("absent-animation", "absent-animation.mdl", true),
                                         ("unprepared-animation", "shared.mdl", false)] {
            failures[label] = try describe(ScenePuppetLayerLoad.preparePose(
                for: sourceLayer(8, mesh: path, animated: true),
                asset: asset(path, animations: requested)))
        }
        output["failures"] = failures

        let first = sourceLayer(21, mesh: "shared.mdl")
        let second = sourceLayer(22, mesh: "other.mdl")
        let resources = try ScenePreparedPuppetResources.prepare(descriptor: .init(layers: [first, second]),
            cacheDirectory: root, cancellationCheck: {})
        output["identity"] = ["first": try describe(resources.posesByLayerID[21]),
            "second": try describe(resources.posesByLayerID[22]),
            "default-first": try describe(resources.defaultPose(for: first)),
            "default-second": try describe(resources.defaultPose(for: second)),
            "missingLayerPresent": resources.posesByLayerID[999] != nil,
            "missingMeshPresent": resources.defaultPose(for: sourceLayer(-1, mesh: "unprepared.mdl")) != nil]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
