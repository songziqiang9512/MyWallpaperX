import Foundation

/// Behavioral checks on a Program produced by the real parser/descriptor/compiler.
/// Observation restore here exercises the Runtime API, not an absent host rollback caller.
enum SceneTimelineCombinedPlaybackChecks {
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
