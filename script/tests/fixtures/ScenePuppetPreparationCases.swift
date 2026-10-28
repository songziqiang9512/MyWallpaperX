import Foundation
import simd
import Darwin

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
enum SceneDynamicValue { case bool(Bool), scalar(Double) }
enum SceneDynamicSource { case authored, userProperty, timeline, sceneScript }
struct SceneDynamicResolvedValue {
    let value: SceneDynamicValue
    var source: SceneDynamicSource = .authored
}
struct SceneDynamicSnapshot {
    let frameIndex: UInt64
    let values: [SceneDynamicTarget: SceneDynamicResolvedValue]
    subscript(target: SceneDynamicTarget) -> SceneDynamicResolvedValue? { values[target] }
}
struct SceneScriptPuppetBoneMutation {
    enum Operation { case matrix([Double]), impulse(SIMD3<Double>) }
    let layerID: Int
    let boneIndex: Int
    let operation: Operation
}

private func sourceLayer(_ id: Int, mesh: String, animated: Bool = false,
                         script: Bool = false, animationID: Int = 101,
                         clipRate: Double = 1) -> SceneRenderDescriptor.Layer {
    let clip = ScenePuppetAnimationLayer(id: 7, animationID: animationID, name: "owned",
        additive: false, blend: 1, blendIn: false, blendOut: false,
        blendTime: 0, rate: clipRate, visible: true, visibilityBinding: nil)
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
    case let .evaluated(_, selection, evaluator, kind, fallback):
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
            "fallback": fallback ?? "",
            "neutralRootX": neutral.local[0].columns.3.x,
            "sampledRootX": sampled.local[0].columns.3.x,
            "localTranslations": sampled.local.map {
                [$0.columns.3.x, $0.columns.3.y, $0.columns.3.z] },
            "worldTranslations": sampled.world.map {
                [$0.columns.3.x, $0.columns.3.y, $0.columns.3.z] },
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
    private enum ProbeStop: Error { case stopped }

    private static func isOpen(_ target: URL) -> Bool {
        let expected = target.resolvingSymlinksInPath().standardizedFileURL.path
        for descriptor: Int32 in 0..<512 {
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if fcntl(descriptor, F_GETPATH, &path) == 0,
               URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().standardizedFileURL.path == expected {
                return true
            }
        }
        return false
    }

    private static func resourceReadChecks(_ root: URL) throws -> [String: Bool] {
        let package = root.appendingPathComponent("lookup-primary")
        let loose = root.appendingPathComponent("lookup-loose")
        try FileManager.default.createDirectory(at: package.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: loose, withIntermediateDirectories: true)
        let original = try Data(contentsOf: root.appendingPathComponent("shared.mdl"))
        let target = package.appendingPathComponent("selected.mdl")
        try original.write(to: target)
        try original.write(to: package.appendingPathComponent(".hidden/rig.mdl"))
        try original.write(to: package.appendingPathComponent("renamed..rig.mdl"))
        try Data("bad mesh".utf8).write(to: package.appendingPathComponent("bad.mdl"))
        try original.write(to: loose.appendingPathComponent("bad.mdl"))
        try original.write(to: loose.appendingPathComponent("lower-only.mdl"))
        try FileManager.default.createDirectory(at: package.appendingPathComponent("nested"), withIntermediateDirectories: true)
        let view = SceneResourceView(projectRootURL: loose, packageRootURL: package, stockAssetsRootURL: nil)
        var checks: [String: Bool] = [:]
        let hidden = try ScenePuppetLayerLoad.prepareAsset(meshPath: ".hidden/rig.mdl", resourceView: view, needsAnimations: true)
        checks["hiddenExactPrimaryEntryRemainsReadable"] = failure(hidden)["kind"] as? String == "ready"
        let equivalent = try ScenePuppetLayerLoad.prepareAsset(meshPath: "./.hidden//rig.mdl", resourceView: view, needsAnimations: true)
        checks["safeDotAndSeparatorVariantKeepsExactFile"] = failure(equivalent)["kind"] as? String == "ready"
        let dottedName = try ScenePuppetLayerLoad.prepareAsset(meshPath: "renamed..rig.mdl", resourceView: view, needsAnimations: true)
        checks["dotsInsideFilenameAreNotTraversal"] = failure(dottedName)["kind"] as? String == "ready"
        let containedParent = try ScenePuppetLayerLoad.prepareAsset(meshPath: "nested/../selected.mdl", resourceView: view, needsAnimations: true)
        checks["containedParentUsesTheActualEntry"] = failure(containedParent)["kind"] as? String == "ready"
        for path in ["../shared.mdl", "nested/../../shared.mdl", "/shared.mdl", "selected.mdl\0other"] {
            let rejected = try ScenePuppetLayerLoad.prepareAsset(meshPath: path, resourceView: view, needsAnimations: false)
            checks["pathComponentsRemainRejected:" + path] = failure(rejected)["allowsTexture"] as? Bool == false
        }
        let bad = try ScenePuppetLayerLoad.prepareAsset(meshPath: "bad.mdl", resourceView: view, needsAnimations: true)
        checks["badPrimaryDoesNotSelectHealthyLowerRoot"] = failure(bad)["allowsTexture"] as? Bool == false
        let missing = try ScenePuppetLayerLoad.prepareAsset(meshPath: "lower-only.mdl", resourceView: view, needsAnimations: true)
        checks["missingPrimaryUsesHealthyLooseEntry"] = failure(missing)["kind"] as? String == "ready"
        let absent = try ScenePuppetLayerLoad.prepareAsset(meshPath: "absent.mdl", resourceView: view, needsAnimations: true)
        checks["missingInEveryAuthorRootKeepsTextureFallback"] = failure(absent)["allowsTexture"] as? Bool == true
        let stock = root.appendingPathComponent("lookup-stock")
        try FileManager.default.createDirectory(at: stock, withIntermediateDirectories: true)
        try original.write(to: stock.appendingPathComponent("stock-only.mdl"))
        try Data("bad loose mesh".utf8).write(to: loose.appendingPathComponent("packaged.mdl"))
        let mounted = SceneResourceView(
            projectRoot: .init(source: .loose, url: loose),
            packageRoot: try .package(openedPackage: ScenePkgReader().openPackage(
                packageURL: root.appendingPathComponent("puppet-sources.pkg"))),
            stockRoot: .init(source: .stock, url: stock))
        for path in ["packaged.mdl", ".hidden/rig.mdl", "./.hidden//rig.mdl", "lower-only.mdl"] {
            let asset = try ScenePuppetLayerLoad.prepareAsset(meshPath: path, resourceView: mounted, needsAnimations: true)
            checks["mountedPackageOrLooseIsPrepared:" + path] = failure(asset)["kind"] as? String == "ready"
        }
        let selectedBad = try ScenePuppetLayerLoad.prepareAsset(meshPath: "bad.mdl", resourceView: mounted, needsAnimations: true)
        checks["selectedBadPackageNeverUsesHealthyLoose"] = failure(selectedBad)["allowsTexture"] as? Bool == false
        let directory = try ScenePuppetLayerLoad.prepareAsset(meshPath: "folder.mdl/", resourceView: mounted, needsAnimations: false)
        checks["explicitPackageDirectoryIsNotAMesh"] = failure(directory)["allowsTexture"] as? Bool == false
        let stockOnly = try ScenePuppetLayerLoad.prepareAsset(meshPath: "stock-only.mdl", resourceView: mounted, needsAnimations: true)
        checks["authorOnlySelectionDoesNotAcquireStockMesh"] = failure(stockOnly)["allowsTexture"] as? Bool == true
        var changed = false
        let descriptor = SceneRenderDescriptor(layers: [sourceLayer(801, mesh: "selected.mdl", animated: true)])
        do {
            _ = try ScenePreparedPuppetResources.prepare(descriptor: descriptor, resourceView: view,
                cancellationCheck: {
                    if !changed, isOpen(target) {
                        try original.dropLast().write(to: target, options: .atomic)
                        changed = true
                    }
                })
            checks["sourceChangeEscapesPreparedResourceOwner"] = false
        } catch SceneResourceView.ReadError.sourceChanged {
            checks["sourceChangeEscapesPreparedResourceOwner"] = changed
        }
        try original.write(to: target, options: .atomic)
        var stopped = false
        do {
            _ = try ScenePreparedPuppetResources.prepare(descriptor: descriptor, resourceView: view,
                cancellationCheck: {
                    if isOpen(target) { stopped = true; throw ProbeStop.stopped }
                })
            checks["nonReadCancellationEscapesOpenedRead"] = false
        } catch ProbeStop.stopped {
            checks["nonReadCancellationEscapesOpenedRead"] = stopped
        }
        let recovered = try ScenePreparedPuppetResources.prepare(descriptor: descriptor, resourceView: view,
            cancellationCheck: {})
        checks["failedReadDoesNotPoisonNextPreparedResource"] = recovered.assetsByMeshPath.count == 1
            && recovered.posesByLayerID[801] != nil
        return checks
    }

    private static func optionalHiddenChecks(
        _ preparation: ScenePuppetLayerLoad.AssetPreparation
    ) throws -> [String: Any] {
        guard case let .ready(base) = preparation,
              let set = try base.animationSet?.get(), let good = set.animations.first else {
            throw ProbeStop.stopped
        }
        let bad = SceneMdlPuppetAnimation(id: 202, name: "broken-optional", mode: "loop",
            framesPerSecond: 1, frameCount: 1, transformsByBone: [])
        let alpha = SceneMdlPuppetAnimation(id: 203, name: "hidden-alpha", mode: good.mode,
            framesPerSecond: good.framesPerSecond, frameCount: good.frameCount,
            transformsByBone: good.transformsByBone,
            alphaByBone: good.transformsByBone.map { $0.map { _ in Float(0.25) } })
        let auxiliary = SceneMdlPuppetAnimation(id: 204, name: "hidden-scalar", mode: good.mode,
            framesPerSecond: good.framesPerSecond, frameCount: good.frameCount,
            transformsByBone: good.transformsByBone, hasAuxiliaryScalarTrack: true)
        let prepared = ScenePuppetLayerLoad.AssetPreparation.ready(.init(
            meshPath: base.meshPath, mesh: base.mesh, attachments: base.attachments,
            rig: base.rig, animationSet: .success(.init(boneCount: set.boneCount,
                animations: [good, bad, alpha, auxiliary])),
            referenceEvaluator: base.referenceEvaluator, initialBones: base.initialBones))
        func slot(_ id: Int, resource: Int = 101, visible: Bool = false,
                  script: Bool = false) -> ScenePuppetAnimationLayer {
            .init(id: id, animationID: resource, name: "slot-\(id)", additive: false,
                blend: 1, blendIn: false, blendOut: false, blendTime: 0, rate: 1,
                visible: visible, visibilityBinding: nil, hasVisibilityScript: script)
        }
        func layer(_ clips: [ScenePuppetAnimationLayer]) -> SceneRenderDescriptor.Layer {
            .init(id: 71, puppetMeshPath: base.meshPath, puppetAnimationLayers: clips,
                hasInlineScript: false)
        }
        let active = slot(10, visible: true), broken = slot(6, resource: 202)
        let authored = [broken, slot(7, script: true), slot(8), slot(9, resource: 203)]
        let hiddenLayer = layer(authored)
        guard let pose = ScenePuppetLayerLoad.preparePose(for: hiddenLayer, asset: prepared),
              case let .evaluated(_, selection, evaluator, _, _) = pose.geometry else {
            throw ProbeStop.stopped
        }
        let runtime = ScenePuppetAnimationPlaybackRuntime()
        try runtime.register(layerID: 71, selection: selection, authoredLayers: authored).get()
        let first = runtime.advance(frameIndex: 0, sceneTime: 0,
            dynamicValues: .init(frameIndex: 0, values: [:]))
        let identity = first.animationSnapshots[0].identity
        try runtime.apply([.init(identity: identity, action: .setFrame(0.5),
            callbackEpoch: 1, ordinal: 0)], frameIndex: 0).get()
        let frame = runtime.advance(frameIndex: 1, sceneTime: 1,
            dynamicValues: .init(frameIndex: 1, values: [:]))
        let samples = frame[71]!.samples
        let neutral = try evaluator.boneTransforms(selection: selection, frameSamples: samples)
        var coverage = [Float](repeating: 0, count: base.mesh.vertices.count)
        var scratch = [Float](repeating: 0, count: set.boneCount)
        try evaluator.writeVertexCoverages(selection: selection, frameSamples: samples,
            into: &coverage, boneScratch: &scratch)
        let positions = try evaluator.deformedPositions(selection: selection, frameSamples: samples)
        func neutralGeometry(_ pose: ScenePuppetLayerLoad.PreparedPose?) throws -> [String: Any] {
            guard let pose else { throw ProbeStop.stopped }
            var description = try describe(pose)
            var points = base.mesh.vertices.map { SIMD2($0.x, $0.y) }
            var alpha = [Float](repeating: 1, count: base.mesh.vertices.count)
            if case let .evaluated(_, clips, evaluator, _, _) = pose.geometry {
                let samples = [ScenePuppetAnimationEvaluator.FrameSample?](
                    repeating: nil, count: clips.clips.count)
                points = try evaluator.deformedPositions(selection: clips, frameSamples: samples)
                try evaluator.writeVertexCoverages(selection: clips, frameSamples: samples,
                    into: &alpha, boneScratch: &scratch)
            }
            description["points"] = points.map { [$0.x, $0.y] }
            description["coverage"] = alpha
            return description
        }
        let defaultGeometry = try neutralGeometry(ScenePuppetLayerLoad.preparePose(for: hiddenLayer,
            asset: prepared, usesDefaultConfiguration: true))
        return ["activeWithBadOptional": try describe(ScenePuppetLayerLoad.preparePose(
                    for: layer([active, broken]), asset: prepared)),
            "badRequired": try describe(ScenePuppetLayerLoad.preparePose(
                    for: layer([active, slot(6, resource: 202, visible: true)]), asset: prepared)),
            "badOnly": try neutralGeometry(ScenePuppetLayerLoad.preparePose(
                    for: layer([broken]), asset: prepared)),
            "auxiliaryWithActive": try describe(ScenePuppetLayerLoad.preparePose(
                    for: layer([active, slot(11, resource: 204)]), asset: prepared)),
            "default": defaultGeometry,
            "points": positions.map { [$0.x, $0.y] },
            "defaultPoints": defaultGeometry["points"]!,
            "defaultCoverage": defaultGeometry["coverage"]!,
            "animationIDs": frame.animationSnapshots.map(\.animationID),
            "slotIDs": frame.animationSnapshots.compactMap { $0.identity.animationLayerID },
            "slotIndices": frame.animationSnapshots.map { $0.identity.animationLayerIndex },
            "visible": frame.animationSnapshots.map(\.visible),
            "currentFrames": frame.animationSnapshots.map(\.currentFrame),
            "nilSamples": samples.allSatisfy { $0 == nil },
            "neutralRootX": neutral.local[0].columns.3.x, "coverage": coverage]
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let resourceView = SceneResourceView(projectRootURL: root, packageRootURL: nil, stockAssetsRootURL: nil)
        func asset(_ name: String, animations: Bool = true) throws -> ScenePuppetLayerLoad.AssetPreparation {
            try ScenePuppetLayerLoad.prepareAsset(meshPath: name,
                resourceView: resourceView, needsAnimations: animations)
        }
        var output: [String: Any] = [:]
        output["optional-hidden"] = try optionalHiddenChecks(asset("shared.mdl"))
        output["optional-hidden-bind"] = try optionalHiddenChecks(asset("bind.mdl"))
        var orders: [String: Any] = [:]
        for (label, path, reversed) in [("plain-first", "shared.mdl", false),
                                        ("animated-first", "shared.mdl", true),
                                        ("renamed", "renamed.mdl", false)] {
            let plain = sourceLayer(1, mesh: path)
            let animated = sourceLayer(2, mesh: path, animated: true, script: true)
            let resources = try ScenePreparedPuppetResources.prepare(
                descriptor: .init(layers: reversed ? [animated, plain] : [plain, animated]),
                resourceView: resourceView, cancellationCheck: {})
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
            let prepared = try asset(path, animations: false)
            var row = bones(prepared)
            row["pose"] = try describe(ScenePuppetLayerLoad.preparePose(
                for: sourceLayer(5, mesh: path), asset: prepared))
            exactBind[path] = row
        }
        output["exact-bind"] = exactBind
        let badReference = try asset("bad-reference.mdl", animations: false)
        output["bad-reference"] = ["bonesAvailable": bones(badReference)["available"]!,
            "pose": try describe(ScenePuppetLayerLoad.preparePose(
                for: sourceLayer(6, mesh: "bad-reference.mdl"), asset: badReference))]

        let retained = try asset("reuse.mdl")
        let beforeBones = bones(retained)
        try FileManager.default.removeItem(at: root.appendingPathComponent("reuse.mdl"))
        let retainedLayer = sourceLayer(7, mesh: "reuse.mdl", animated: true, script: true)
        output["reuse"] = ["fileExists": FileManager.default.fileExists(
            atPath: root.appendingPathComponent("reuse.mdl").path),
            "beforeBones": beforeBones, "afterBones": bones(retained),
            "source": try describe(ScenePuppetLayerLoad.preparePose(for: retainedLayer, asset: retained)),
            "default": try describe(ScenePuppetLayerLoad.preparePose(
                for: retainedLayer, asset: retained, usesDefaultConfiguration: true))]

        let staticPath = "static-uv20.mdl"
        let staticPrepared = try asset(staticPath, animations: false)
        if case let .ready(value) = staticPrepared {
            let layer = sourceLayer(31, mesh: staticPath)
            let before = try describe(ScenePuppetLayerLoad.preparePose(for: layer, asset: staticPrepared))
            try FileManager.default.removeItem(at: root.appendingPathComponent(staticPath))
            output["static-uv20"] = ["kind": "ready", "stride": value.mesh.vertexStride,
                "vertices": value.mesh.vertices.map { [$0.x, $0.y, $0.z, $0.u, $0.v] },
                "indices": value.mesh.indices.map(Int.init),
                "bonesAvailable": ScenePuppetLayerLoad.boneConfiguration(for: value) != nil,
                "animationsPrepared": value.animationSet != nil,
                "fileExists": FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(staticPath).path),
                "before": before,
                "after": try describe(ScenePuppetLayerLoad.preparePose(for: layer, asset: staticPrepared))]
        } else {
            output["static-uv20"] = failure(staticPrepared)
        }

        var failures: [String: Any] = [:]
        for (label, path) in [("missing", "missing.mdl"), ("read", "directory.mdl"),
                               ("parse", "bad-mesh.mdl"), ("path", "../outside.mdl")] {
            failures[label] = try failure(asset(path))
        }
        for (label, path, requested) in [("rig", "bad-rig.mdl", true),
                                         ("animation", "bad-animation.mdl", true),
                                         ("absent-animation", "absent-animation.mdl", true),
                                         ("unprepared-animation", "bind.mdl", false)] {
            failures[label] = try describe(ScenePuppetLayerLoad.preparePose(
                for: sourceLayer(8, mesh: path, animated: true),
                asset: asset(path, animations: requested)))
        }
        failures["selector"] = try describe(ScenePuppetLayerLoad.preparePose(
            for: sourceLayer(9, mesh: "bind.mdl", animated: true, animationID: 909),
            asset: asset("bind.mdl")))
        failures["unsupported-selector"] = try describe(ScenePuppetLayerLoad.preparePose(
            for: sourceLayer(9, mesh: "bind.mdl", animated: true, clipRate: 0),
            asset: asset("bind.mdl")))
        failures["no-reference-script"] = try describe(ScenePuppetLayerLoad.preparePose(
            for: sourceLayer(10, mesh: "bad-animation.mdl", animated: true, script: true),
            asset: asset("bad-animation.mdl")))
        output["failures"] = failures

        var referenceFallbacks: [String: Any] = [:]
        for (label, path, requested, animationID, rate) in [
            ("bad", "reference-bad-animation.mdl", true, 101, 1.0),
            ("absent", "reference-absent-animation.mdl", true, 101, 1.0),
            ("unprepared", "shared.mdl", false, 101, 1.0),
            ("unknown", "shared.mdl", true, 909, 1.0),
            ("unsupported", "shared.mdl", true, 101, 0.0),
            ("renamed", "renamed-reference-failure.mdl", true, 101, 1.0),
            ("independent", "independent-reference-failure.mdl", true, 101, 1.0),
            ("reordered", "reordered-reference-failure.mdl", true, 101, 1.0)
        ] {
            let prepared = try asset(path, animations: requested)
            let layer = sourceLayer(41, mesh: path, animated: true,
                animationID: animationID, clipRate: rate)
            referenceFallbacks[label] = ["bones": bones(prepared),
                "pose": try describe(ScenePuppetLayerLoad.preparePose(for: layer, asset: prepared)),
                "default": try describe(ScenePuppetLayerLoad.preparePose(
                    for: layer, asset: prepared, usesDefaultConfiguration: true))]
        }
        output["reference-fallbacks"] = referenceFallbacks
        var referenceSafety: [String: Any] = [:]
        for (label, path) in [("rig", "reference-bad-rig.mdl"),
                               ("reference", "invalid-reference-failure.mdl"),
                               ("selected-evaluator", "selected-evaluator-failure.mdl")] {
            let prepared = try asset(path)
            referenceSafety[label] = ["bones": bones(prepared),
                "pose": try describe(ScenePuppetLayerLoad.preparePose(
                    for: sourceLayer(42, mesh: path, animated: true), asset: prepared))]
        }
        output["reference-safety"] = referenceSafety

        let first = sourceLayer(21, mesh: "shared.mdl")
        let second = sourceLayer(22, mesh: "other.mdl")
        let resources = try ScenePreparedPuppetResources.prepare(descriptor: .init(layers: [first, second]),
            resourceView: resourceView, cancellationCheck: {})
        output["identity"] = ["first": try describe(resources.posesByLayerID[21]),
            "second": try describe(resources.posesByLayerID[22]),
            "default-first": try describe(resources.defaultPose(for: first)),
            "default-second": try describe(resources.defaultPose(for: second)),
            "missingLayerPresent": resources.posesByLayerID[999] != nil,
            "missingMeshPresent": resources.defaultPose(for: sourceLayer(-1, mesh: "unprepared.mdl")) != nil]
        output["resource-read-checks"] = try resourceReadChecks(root)
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
