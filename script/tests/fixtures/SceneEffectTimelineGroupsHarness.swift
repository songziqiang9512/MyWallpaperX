import Foundation

@main
enum EffectTimelineGroupsProbe {
    typealias Target = SceneDynamicTarget

    static func key(_ target: Target) -> String {
        switch target {
        case let .effectConstant(layer, effect, pass, name):
            return "effect:\(layer):\(effect):\(pass):\(name)"
        case let .layer(layer, field): return "layer:\(layer):\(field.rawValue)"
        default: return String(describing: target)
        }
    }

    static func scalar(_ value: SceneDynamicValue) throws -> Double {
        guard case let .scalar(number) = value else {
            throw NSError(domain: "expected real scalar Timeline output", code: 1)
        }
        return number
    }

    static func numbers(_ values: [Target: SceneDynamicValue]) throws -> [String: Double] {
        try Dictionary(uniqueKeysWithValues: values.map { (key($0.key), try scalar($0.value)) })
    }

    static func descriptor(_ url: URL) throws -> SceneRenderDescriptor {
        let document = try SceneDocumentLoader().load(from: url)
        guard let value = SceneRenderDescriptorBuilder().build(
            project: SceneProject(rootURL: url.deletingLastPathComponent(), entryPath: url.lastPathComponent,
                userProperties: .empty), sceneDocument: document,
            assetCatalog: SceneAssetCatalog(models: [], materials: [], effectDefinitions: [],
                effectDefinitionDiagnostics: [], shaderReferences: [], textureReferences: []),
            resourceReferences: SceneResourceReferenceIndex(missingReferences: [], builtInReferenceCount: 0,
                runtimeProvidedReferenceCount: 0), capabilityProfile: SceneCapabilityProfile(firstStageRendererGaps: [])
        ) else { throw HarnessError.descriptorRejected }
        return value
    }

    static func snapshot(_ program: SceneTimelineProgram, values: [Target: SceneDynamicValue]) throws -> [String: Any] {
        let definitions = SceneTimelineRuntime.mergedDefinitions(propertyDefinitions: [], timelineProgram: program)
        let resolved = SceneDynamicSnapshotResolver().resolve(frameIndex: 41, generation: 7,
            definitions: definitions, timelineValues: values).snapshot
        var result: [String: Any] = [:]
        for binding in program.bindings {
            guard let entry = resolved[binding.target] else {
                throw NSError(domain: "Timeline output missing from real DynamicSnapshot", code: 2)
            }
            let number = try scalar(entry.value)
            result[key(binding.target)] = ["value": number, "source": entry.source.rawValue,
                "bits": String(number.bitPattern, radix: 16)]
        }
        return result
    }

    static func bindings(_ program: SceneTimelineProgram) throws -> [[String: Any]] {
        try program.bindings.map { binding in
            let options = binding.animation.options
            let authored = try scalar(binding.definition.authoredValue)
            let row: [String: Any] = ["target": key(binding.target), "owner": key(binding.playbackOwnerTarget),
                    "grouped": binding.playbackOwner != nil, "authored": authored,
                    "authoredBits": String(authored.bitPattern, radix: 16),
                    "fps": options.fps, "length": options.length, "mode": options.mode.rawValue,
                    "paused": options.startsPaused, "name": options.name ?? "",
                    "smoothing": options.smoothing.map { $0 as Any } ?? NSNull(),
                    "stiffness": options.stiffness.map { $0 as Any } ?? NSNull()]
            return row
        }
    }

    static func checkRetirement(_ program: SceneTimelineProgram, group: [SceneTimelineBinding],
                                root: Target, child: Target) throws -> [String: Bool] {
        let retired = SceneTimelinePlaybackRuntime(program: program)
        let control = SceneTimelinePlaybackRuntime(program: program)
        for runtime in [retired, control] {
            try runtime.apply([.init(target: root, command: .play)], sceneTime: 0).get()
        }
        retired.retire(targets: [child])
        var removed: Set<Target> = [child]
        var facts = ["retiredChildKeepsOtherValues": retired.values(sceneTime: 2)
            == control.values(sceneTime: 2).filter { !removed.contains($0.key) }]
        retired.retire(targets: [root])
        removed.insert(root)
        facts["retiredOwnerKeepsClock"] = retired.values(sceneTime: 3)
            == control.values(sceneTime: 3).filter { !removed.contains($0.key) }
        guard let survivor = group.first(where: { !removed.contains($0.target) }) else {
            throw NSError(domain: "fixture requires a surviving real pass alias", code: 3)
        }
        for runtime in [retired, control] {
            try runtime.apply([.init(target: survivor.target, command: .pause)], sceneTime: 3).get()
        }
        facts["survivorControlsOriginalState"] = retired.values(sceneTime: 7)
            == control.values(sceneTime: 7).filter { !removed.contains($0.key) }
        let before = retired.values(sceneTime: 7), observations = retired.observationSnapshot()
        let failure = retired.apply([.init(target: root, command: .play)], sceneTime: 7)
        var rejected = false
        if case let .failure(reason) = failure { rejected = reason == .unknownTarget(root) }
        facts["retiredTargetRejectedWithoutMutation"] = rejected
            && before == retired.values(sceneTime: 7) && observations == retired.observationSnapshot()
        retired.retire(targets: Set(program.bindings.map(\.target)))
        facts["allTargetsAndPendingObservationsRetire"] = retired.values(sceneTime: 20).isEmpty
            && retired.observationSnapshot() == SceneTimelinePlaybackRuntime(program: .empty).observationSnapshot()
        return facts
    }

    static func run(_ descriptor: SceneRenderDescriptor) throws -> [String: Any] {
        let program = SceneTimelineTargetCompiler.compile(descriptor: descriptor)
        guard let layerID = descriptor.layers.first?.id else { throw HarnessError.descriptorRejected }
        let primary = program.bindings.filter {
            guard case let .effectConstant(layer, effect, _, _) = $0.target else { return false }
            return layer == layerID && effect == 0
        }
        let group = primary.filter { $0.playbackOwner != nil }
        let groupTargets = Set(group.map(\.target))
        let playback = SceneTimelinePlaybackRuntime(program: program)
        let control = SceneTimelinePlaybackRuntime(program: program)
        var result: [String: Any] = ["bindings": try bindings(program), "diagnostics": program.diagnostics,
            "effectTargets": primary.map { key($0.target) }.sorted(),
            "groupTargets": group.map { key($0.target) }.sorted()]
        result["initial"] = try numbers(playback.values(sceneTime: 0))
        result["initialSnapshot"] = try snapshot(program, values: playback.values(sceneTime: 0))
        result["withoutGroupTimelineSnapshot"] = try snapshot(program,
            values: playback.values(sceneTime: 0).filter { !groupTargets.contains($0.key) })
        guard let root = group.first?.playbackOwnerTarget else { return result }
        guard case let .effectConstant(_, _, _, rootName) = root,
              let child = group.first(where: { binding in
                  guard case let .effectConstant(_, _, _, name) = binding.target else { return false }
                  return name != rootName
              })?.target else { throw NSError(domain: "fixture requires numeric child", code: 4) }
        var independent = true
        func sample(_ label: String, _ time: Double) throws {
            let values = playback.values(sceneTime: time)
            result[label] = try numbers(values)
            independent = independent && values.filter { !groupTargets.contains($0.key) }
                == control.values(sceneTime: time).filter { !groupTargets.contains($0.key) }
        }
        let previewBefore = playback.values(sceneTime: 0)
        let observationBefore = playback.observationSnapshot()
        result["preview10"] = try numbers(try playback.preview(
            [.init(target: child, command: .setFrame(10))], sceneTime: 0).get())
        result["previewDidNotCommit"] = previewBefore == playback.values(sceneTime: 0)
            && observationBefore == playback.observationSnapshot()
        try playback.apply([.init(target: child, command: .setFrame(10))], sceneTime: 0).get()
        try sample("key10", 4)
        result["key10Snapshot"] = try snapshot(program, values: playback.values(sceneTime: 4))
        try playback.apply([.init(target: child, command: .play)], sceneTime: 4).get()
        try sample("played30", 6)
        try playback.apply([.init(target: child, command: .pause)], sceneTime: 6).get()
        try sample("paused30", 8)
        try playback.apply([.init(target: root, command: .play)], sceneTime: 8).get()
        try sample("completed40", 9)
        try playback.apply([.init(target: root, command: .play)], sceneTime: 10).get()
        try sample("restart0", 10)
        try playback.apply([.init(target: root, command: .play)], sceneTime: 10.5).get()
        try sample("activePlay10", 11)
        try playback.apply([.init(target: root, command: .setFrame(20))], sceneTime: 11).get()
        try sample("seekPlaying30", 12)
        try playback.apply([.init(target: child, command: .stop)], sceneTime: 13).get()
        try sample("stopped0", 14)
        result["independentTracksUnchanged"] = independent
        for (label, commands) in [
            ("stopPlay10", [SceneTimelinePlaybackCommand.stop, .play]),
            ("playStop0", [SceneTimelinePlaybackCommand.play, .stop]),
        ] {
            let ordered = SceneTimelinePlaybackRuntime(program: program)
            try ordered.apply(commands.map { .init(target: root, command: $0) }, sceneTime: 1).get()
            result[label] = try numbers(ordered.values(sceneTime: 2))
        }
        result["retirement"] = try checkRetirement(program, group: group, root: root, child: child)
        return result
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw HarnessError.missingFixture }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let result = try run(descriptor(input))
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
