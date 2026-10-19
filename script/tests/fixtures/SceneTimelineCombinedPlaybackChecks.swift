import Foundation

/// Behavioral checks on a Program produced by the real parser/descriptor/compiler.
/// Observation restore here exercises the Runtime API, not an absent host rollback caller.
enum SceneTimelineCombinedPlaybackChecks {
    private static func components(
        _ values: [SceneDynamicTarget: SceneDynamicValue], targets: [SceneDynamicTarget]
    ) throws -> [[Double]] {
        try targets.map { target in
            switch values[target] {
            case let .scalar(value)?: return [value]
            case let .vector3(x, y, z)?: return [x, y, z]
            default: throw NSError(domain: "missing combined typed value", code: 2)
            }
        }
    }

    static func mixed(
        _ program: SceneTimelineProgram, descriptor: SceneRenderDescriptor
    ) throws -> [String: Any] {
        let members = program.bindings.filter { $0.playbackOwner != nil }
        let healthy = SceneDynamicTarget.layer(layerID: 202, field: .alpha)
        var facts = ["independentSurvives": SceneTimelineRuntime.values(
            program: program, sceneTime: 2)[healthy] == .scalar(1)]
        guard members.count == 3, let owner = members.first?.playbackOwner,
              case let .layer(layerID, _) = owner else {
            facts["wholeGroupRefused"] = program.bindings.allSatisfy { $0.target == healthy }
                && !program.diagnostics.isEmpty
            return ["groupCount": members.count, "facts": facts]
        }
        let targets: [SceneDynamicTarget] = [.layer(layerID: layerID, field: .origin),
            .layer(layerID: layerID, field: .scale), .layer(layerID: layerID, field: .alpha)]
        let root = members.first { $0.target == owner }!
        let options = root.animation.options
        facts["preparedMembership"] = Set(members.map(\.target)) == Set(targets)
            && members.allSatisfy { $0.playbackOwner == owner }
        facts["compositionAndAuthoredBase"] = members.allSatisfy {
            $0.target == targets[2]
                ? $0.composition == .absolute && $0.definition.authoredValue == .scalar(0.375)
                : $0.composition == .additive && $0.definition.valueType == .vector3
        }
        facts["rootSettingsOnly"] = options.fps == 10 && options.length == 40
            && options.startsPaused && members.allSatisfy {
                let member = $0.animation.options
                return member.fps == options.fps && member.length == options.length
                    && member.mode == options.mode && member.startsPaused == options.startsPaused
                    && member.wrapsLoop == options.wrapsLoop && member.parent == nil && member.children.isEmpty
                    && member.smoothing == nil && member.stiffness == nil
                    && member.name == ($0.target == owner ? "mixed cohort" : nil)
            }
        let playback = SceneTimelinePlaybackRuntime(program: program)
        let definitions = SceneTimelineRuntime.mergedDefinitions(
            propertyDefinitions: [], timelineProgram: program)
        var frame: UInt64 = 0
        var typed = true
        func sample(_ time: Double) throws -> [[Double]] {
            let resolved = SceneDynamicSnapshotResolver().resolve(
                frameIndex: frame, generation: 1, definitions: definitions,
                userValues: [targets[2]: .scalar(0.9)], timelineValues: playback.values(sceneTime: time))
            frame += 1
            typed = typed && resolved.diagnostics.isEmpty && targets.allSatisfy {
                resolved.snapshot[$0]?.source == .timeline
                    && resolved.snapshot[$0]?.value.valueType == ($0 == targets[2] ? .scalar : .vector3)
            }
            return try components(Dictionary(uniqueKeysWithValues: targets.compactMap { target in
                resolved.snapshot[target].map { (target, $0.value) }
            }), targets: targets)
        }
        let child = targets.first { $0 != owner }!
        var samples = [try sample(4)]
        try playback.apply([.init(target: child, command: .play)], sceneTime: 4).get()
        samples.append(try sample(5))
        samples.append(try sample(6))
        try playback.apply([.init(target: targets[2], command: .pause)], sceneTime: 6).get()
        samples.append(try sample(9))
        let observed = playback.observationSnapshot()
        let preview = try playback.preview([.init(target: child, command: .stop)], sceneTime: 9).get()
        let repeated = try playback.preview([.init(target: child, command: .stop)], sceneTime: 9).get()
        let projected = try components(preview, targets: targets)
        facts["previewFanout"] = Set(preview.keys) == Set(targets) && preview == repeated
            && projected == samples[0]
            && observed == playback.observationSnapshot()
        let invalid = SceneDynamicTarget.layer(layerID: -500, field: .alpha)
        let commands = [SceneTimelinePlaybackMutation(target: child, command: .stop),
                        .init(target: invalid, command: .play)]
        let before = playback.values(sceneTime: 9)
        let invalidPreview = playback.preview(commands, sceneTime: 9)
        let invalidApply = playback.apply(commands, sceneTime: 9)
        let applyRejected: Bool
        if case let .failure(failure) = invalidApply { applyRejected = failure == .unknownTarget(invalid) }
        else { applyRejected = false }
        facts["atomicBadCommands"] = invalidPreview == .failure(.unknownTarget(invalid)) && applyRejected
            && playback.values(sceneTime: 9) == before
        try playback.apply([.init(target: child, command: .stop)], sceneTime: 10).get()
        samples.append(try sample(10))
        facts["typedTimelinePriority"] = typed
        let ordered = SceneTimelinePlaybackRuntime(program: program)
        let reversed = SceneTimelinePlaybackRuntime(program: program)
        let order = [SceneTimelinePlaybackMutation(target: child, command: .stop),
                     .init(target: owner, command: .play)]
        try ordered.apply(order, sceneTime: 0).get()
        try reversed.apply(Array(order.reversed()), sceneTime: 0).get()
        let forwardValues = try components(ordered.values(sceneTime: 2), targets: targets)
        let backwardValues = try components(reversed.values(sceneTime: 2), targets: targets)
        facts["commandOrder"] = forwardValues == samples[2] && backwardValues == samples[0]
        let curve = try (0...5).map { try components(ordered.values(sceneTime: Double($0)), targets: targets) }
        let index = descriptor.layers.firstIndex { $0.id == layerID }!
        for scalar in [false, true] {
            var unsafe = descriptor
            if scalar { unsafe.layers[index].alpha = .infinity }
            else { unsafe.layers[index].scaleXYZ = [.infinity, 1, 1] }
            let rejected = SceneTimelineTargetCompiler.compile(descriptor: unsafe)
            facts[scalar ? "nonfiniteScalarBase" : "nonfiniteVectorBase"] = rejected.bindings.allSatisfy {
                !targets.contains($0.target)
            } && rejected.bindings.contains { $0.target == healthy }
        }
        var duplicate = descriptor
        duplicate.layers.append(descriptor.layers[index])
        let rejected = SceneTimelineTargetCompiler.compile(descriptor: duplicate)
        facts["duplicateTypedTargets"] = rejected.bindings.allSatisfy { !targets.contains($0.target) }
            && rejected.bindings.contains { $0.target == healthy }
        return ["groupCount": members.count, "samples": samples, "curve": curve, "facts": facts]
    }

    static func camera(_ program: SceneTimelineProgram) throws -> [String: Bool] {
        let origin = SceneDynamicTarget.camera(.origin)
        let zoom = SceneDynamicTarget.camera(.zoom)
        let targets = Set([origin, zoom])
        func cameraValues(_ values: [SceneDynamicTarget: SceneDynamicValue])
            -> [SceneDynamicTarget: SceneDynamicValue] {
            values.filter { targets.contains($0.key) }
        }
        let initial = cameraValues(SceneTimelineRuntime.values(program: program, sceneTime: 0))
        let advanced = cameraValues(SceneTimelineRuntime.values(program: program, sceneTime: 1))
        let playback = SceneTimelinePlaybackRuntime(program: program)
        try playback.apply([.init(target: zoom, command: .stop)], sceneTime: 5).get()
        let stopped = cameraValues(playback.values(sceneTime: 5))
        try playback.apply([.init(target: zoom, command: .play)], sceneTime: 5).get()
        let played = cameraValues(playback.values(sceneTime: 6))
        try playback.apply([.init(target: origin, command: .pause)], sceneTime: 6).get()
        let held = cameraValues(playback.values(sceneTime: 9))
        let beforePreview = playback.observationSnapshot()
        let preview = try playback.preview([.init(target: zoom, command: .stop)], sceneTime: 9).get()
        return ["stoppedPair": initial.count == 2 && stopped == initial,
                "playedPair": advanced != initial && played == advanced,
                "pausedPair": held == advanced,
                "previewPair": Set(preview.keys) == targets && preview == initial,
                "previewNoConsumption": beforePreview == playback.observationSnapshot()]
    }

    static func run(_ program: SceneTimelineProgram) throws -> [String: Any] {
        let members = program.bindings.filter { $0.playbackOwner != nil }
        guard members.count == 3, let root = members.first?.playbackOwner else {
            throw NSError(domain: "combined preparation", code: 1)
        }
        let targets = members.map(\.target)
        let child = targets.first { $0 != root }!
        let other = targets.last!
        let invalid = SceneDynamicTarget.layer(layerID: 999, field: .alpha)
        let playback = SceneTimelinePlaybackRuntime(program: program)
        func vectors(_ values: [SceneDynamicTarget: SceneDynamicValue]) throws -> [[Double]] {
            try targets.map { target in
                guard case let .vector3(x, y, z)? = values[target] else {
                    throw NSError(domain: "missing combined value", code: 2)
                }
                return [x, y, z]
            }
        }
        func sample(_ time: Double) throws -> [[Double]] {
            let resolution = SceneDynamicSnapshotResolver().resolve(
                frameIndex: UInt64(time * 100), generation: 1,
                definitions: program.bindings.map(\.definition),
                timelineValues: playback.values(sceneTime: time))
            guard resolution.diagnostics.isEmpty,
                  targets.allSatisfy({ resolution.snapshot[$0]?.source == .timeline }) else {
                throw NSError(domain: "combined typed publication", code: 3)
            }
            return try vectors(Dictionary(uniqueKeysWithValues: targets.map {
                ($0, resolution.snapshot[$0]!.value)
            }))
        }
        var samples = [try sample(4)]
        try playback.apply([.init(target: child, command: .play)], sceneTime: 4).get()
        let pending = playback.observationSnapshot()
        samples.append(try sample(5))
        let consumed = playback.observationSnapshot()
        playback.restoreObservationState(pending)
        let restored = playback.observationSnapshot()
        try playback.apply([.init(target: other, command: .pause)], sceneTime: 5).get()
        samples.append(try sample(8))
        try playback.apply([.init(target: root, command: .play)], sceneTime: 8).get()
        samples.append(try sample(10))
        let before = playback.values(sceneTime: 11)
        let beforeObservations = playback.observationSnapshot()
        let restart = [SceneTimelinePlaybackMutation(target: child, command: .play)]
        let projected = try playback.preview(restart, sceneTime: 11).get()
        let repeated = try playback.preview(restart, sceneTime: 11).get()
        let afterPreviewObservations = playback.observationSnapshot()
        let failedPreview = playback.preview(restart + [.init(target: invalid, command: .stop)], sceneTime: 11)
        let failedApply = playback.apply(restart + [.init(target: invalid, command: .pause)], sceneTime: 11)
        let failedApplyRejected: Bool
        if case let .failure(failure) = failedApply {
            failedApplyRejected = failure == .unknownTarget(invalid)
        } else { failedApplyRejected = false }
        let unchangedAfterFailure = before == playback.values(sceneTime: 11)
        try playback.apply(restart, sceneTime: 11).get()
        samples.append(try sample(11))
        try playback.apply([.init(target: other, command: .play)], sceneTime: 11.5).get()
        samples.append(try sample(12))
        try playback.apply([.init(target: other, command: .stop)], sceneTime: 12).get()
        samples.append(try sample(20))
        let ordered = SceneTimelinePlaybackRuntime(program: program)
        let reversed = SceneTimelinePlaybackRuntime(program: program)
        let commands = [SceneTimelinePlaybackMutation(target: root, command: .stop),
                        .init(target: child, command: .play)]
        try ordered.apply(commands, sceneTime: 0).get()
        try reversed.apply(Array(commands.reversed()), sceneTime: 0).get()
        let decoded = try JSONDecoder().decode(SceneTimelineProgram.self,
            from: JSONEncoder().encode(program))
        let legacy = SceneTimelineProgram(bindings: [program.bindings.last!], diagnostics: [])
        let legacyData = try JSONEncoder().encode(legacy)
        let oldWire = try JSONSerialization.jsonObject(with: legacyData) as! [String: Any]
        let oldBinding = (oldWire["bindings"] as! [[String: Any]])[0]
        let legacyDecoded = try JSONDecoder().decode(SceneTimelineProgram.self, from: legacyData)
        let legacyValues = SceneTimelinePlaybackRuntime(program: legacyDecoded).values(sceneTime: 2)
        return [
            "samples": samples,
            "preview": try vectors(projected),
            "ordered": try vectors(ordered.values(sceneTime: 1)),
            "reversed": try vectors(reversed.values(sceneTime: 1)),
            "facts": [
                "roundTrip": decoded == program,
                "legacyAbsentOwner": oldBinding["playbackOwner"] == nil
                    && legacyDecoded.bindings[0].playbackOwner == nil
                    && legacyValues[.layer(layerID: 202, field: .alpha)] == .scalar(1),
                "observationAPIChanged": pending != consumed,
                "observationAPIRestored": pending == restored,
                "previewWholeGroup": Set(projected.keys) == Set(targets),
                "previewRepeated": projected == repeated,
                "previewNoObservationConsumption": beforeObservations == afterPreviewObservations,
                "failedPreview": failedPreview == .failure(.unknownTarget(invalid)),
                "failedApply": failedApplyRejected,
                "failedBatchNoStateCommit": unchangedAfterFailure,
                "independentSurvives": playback.values(sceneTime: 20)[.layer(layerID: 202, field: .alpha)] == .scalar(1),
            ],
        ]
    }
}
