import Foundation

/// Diagnostic input boundary: real parser, Program DTO, playback and resolver.
enum SceneTimelineFrameEvidenceChecks {
    static func frameEvidence(_ inputProgram: SceneTimelineProgram) throws -> [String: Bool] {
        let cameraTarget = SceneDynamicTarget.camera(.zoom)
        let cameraParsed = SceneTimelineAnimationParser.parse(host: ["value": 3, "animation": [
            "options": ["fps": 30, "length": 60, "mode": "single"],
            "c0": [["frame": 0, "value": 3], ["frame": 30, "value": 1]]]])
        guard let cameraAnimation = cameraParsed.animation, cameraParsed.diagnostics.isEmpty else {
            throw NSError(domain: "camera evidence animation did not parse", code: 1)
        }
        let generalTarget = SceneDynamicTarget.camera(.generalZoom)
        let program = SceneTimelineProgram(bindings: inputProgram.bindings + [SceneTimelineBinding(
            definition: .init(target: cameraTarget, valueType: .scalar, authoredValue: .scalar(3)),
            animation: cameraAnimation, composition: .absolute), SceneTimelineBinding(
            definition: .init(target: generalTarget, valueType: .scalar, authoredValue: .scalar(3)),
            animation: cameraAnimation, composition: .absolute)], diagnostics: inputProgram.diagnostics)
        guard let binding = program.bindings.first(where: { $0.playbackOwner != nil }),
              case let .layer(layerID, _) = binding.target else {
            throw NSError(domain: "evidence fixture needs a prepared transform", code: 1)
        }
        let missingID = layerID + 100_000
        func configuration(_ overrides: [String: Any] = [:]) throws
            -> SceneTimelineFrameEvidence.Configuration {
            var value: [String: Any] = ["layerIDs": [layerID, missingID],
                "sceneTimeWindow": [0, 2], "interval": 0.5, "maxSamples": 2]
            value.merge(overrides) { _, current in current }
            return try .parse(String(decoding: JSONSerialization.data(withJSONObject: value), as: UTF8.self))
        }
        func records(_ lines: [String]) throws -> [[String: Any]] {
            try lines.map { line in
                let json = String(line.dropFirst(SceneTimelineFrameEvidence.prefix.count))
                return try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
            }
        }
        let config = try configuration()
        let budget = SceneTimelineFrameEvidence.OutputBudget()
        var lines: [String] = []
        let observe = SceneTimelineFrameEvidence(configuration: config, budget: budget) { lines.append($0) }
        SceneTimelineFrameEvidence.recordProgram(program, configuration: config, budget: budget) { lines.append($0) }
        let playback = SceneTimelinePlaybackRuntime(program: program)
        let values = playback.values(sceneTime: 1)
        let before = playback.observationSnapshot()
        let resolution = SceneDynamicSnapshotResolver().resolve(frameIndex: 42, generation: 7,
            definitions: program.bindings.map(\.definition), timelineValues: values)
        let originalSnapshot = resolution.snapshot
        observe.record(streamID: 9, frameIndex: 42, sceneTime: 1, snapshot: originalSnapshot)
        let bytesAfterFirst = budget.consumedBytes
        observe.record(streamID: 9, frameIndex: 42, sceneTime: 1, snapshot: originalSnapshot)
        let deduplicated = budget.consumedBytes == bytesAfterFirst
        let authored = SceneDynamicSnapshotResolver().resolve(frameIndex: 43, generation: 8,
            definitions: program.bindings.map(\.definition), timelineValues: [:]).snapshot
        observe.record(streamID: 9, frameIndex: 43, sceneTime: 1.25, snapshot: authored)
        let intervalSkipped = budget.consumedBytes == bytesAfterFirst
        let fallback = SceneDynamicSnapshotResolver().resolve(frameIndex: 44, generation: 8,
            definitions: program.bindings.map(\.definition), timelineValues: [:]).snapshot
        observe.record(streamID: 9, frameIndex: 44, sceneTime: 1.5, snapshot: fallback)
        observe.record(streamID: 9, frameIndex: 45, sceneTime: 2,
            snapshot: .empty(frameIndex: 45, generation: 8))
        observe.finish()
        let output = try records(lines)
        let frames = output.filter { $0["kind"] as? String == "frame" }
        let first = frames[0]
        let firstRows = first["values"] as! [[String: Any]]
        let selected = firstRows.filter { ($0["target"] as! [String: Any])["layerID"] as? Int == layerID }
        let missing = firstRows.filter { ($0["target"] as! [String: Any])["layerID"] as? Int == missingID }
        let secondRows = frames[1]["values"] as! [[String: Any]]
        let retired = output.last!
        let metadata = output[0]
        let bindings = metadata["bindings"] as! [[String: Any]]
        var facts = [
            "selection": firstRows.count == 6 && selected.count == 3 && missing.count == 3,
            "actualTimelineSource": selected.allSatisfy { $0["source"] as? String == "timeline" },
            "authoredFallbackSource": secondRows.filter {
                ($0["target"] as! [String: Any])["layerID"] as? Int == layerID
            }.allSatisfy { $0["source"] as? String == "authored" },
            "missingExplicit": missing.allSatisfy {
                ($0["resolved"] as! [String: Any])["state"] as? String == "missing"
                    && $0["source"] is NSNull
                    && ($0["authored"] as! [String: Any])["state"] as? String == "missing"
            },
            "frameIdentity": first["frame"] as? Int == 42 && first["snapshotFrame"] as? Int == 42
                && first["generation"] as? Int == 7 && first["sceneTime"] as? Double == 1,
            "programProjection": bindings.count == 3 && bindings.allSatisfy {
                ($0["target"] as! [String: Any])["layerID"] as? Int == layerID
                    && $0["owner"] != nil && $0["keyframeCounts"] != nil && $0["animation"] == nil
            } && metadata["cameraZoom"] == nil,
            "duplicateNoBudget": deduplicated,
            "intervalNoBudget": intervalSkipped,
            "sampleLimit": frames.count == 2 && retired["samples"] as? Int == 2
                && (retired["reasons"] as? [String])?.contains("sample-limit") == true,
            "noPlaybackConsumption": before == playback.observationSnapshot()
                && originalSnapshot == resolution.snapshot && values == playback.values(sceneTime: 1),
        ]
        let cameraConfig = try configuration(["layerIDs": [Int](), "cameraZoom": true, "maxSamples": 3])
        let cameraBudget = SceneTimelineFrameEvidence.OutputBudget()
        var cameraLines: [String] = []
        let cameraObserve = SceneTimelineFrameEvidence(configuration: cameraConfig, budget: cameraBudget) { cameraLines.append($0) }
        SceneTimelineFrameEvidence.recordProgram(program, configuration: cameraConfig, budget: cameraBudget) { cameraLines.append($0) }
        cameraObserve.record(streamID: 10, frameIndex: 42, sceneTime: 1, snapshot: originalSnapshot)
        let cameraBytes = cameraBudget.consumedBytes
        cameraObserve.record(streamID: 10, frameIndex: 42, sceneTime: 1, snapshot: originalSnapshot)
        facts["cameraDuplicateNoBudget"] = cameraBudget.consumedBytes == cameraBytes
        cameraObserve.record(streamID: 10, frameIndex: 43, sceneTime: 1.25, snapshot: authored)
        facts["cameraIntervalNoBudget"] = cameraBudget.consumedBytes == cameraBytes
        let overridden = SceneDynamicSnapshotResolver().resolve(frameIndex: 44, generation: 8,
            definitions: program.bindings.map(\.definition), timelineValues: values,
            sceneScriptValues: [cameraTarget: .scalar(2)]).snapshot
        cameraObserve.record(streamID: 10, frameIndex: 44, sceneTime: 1.5, snapshot: overridden)
        cameraObserve.record(streamID: 10, frameIndex: 45, sceneTime: 2, snapshot: .empty(frameIndex: 45, generation: 8))
        cameraObserve.finish()
        let cameraOutput = try records(cameraLines)
        let cameraFrames = cameraOutput.filter { $0["kind"] as? String == "frame" }
        let cameraRows = cameraFrames.map { ($0["values"] as! [[String: Any]])[0] }
        let cameraBindings = cameraOutput[0]["bindings"] as! [[String: Any]]
        let cameraIdentity = ["owner": "camera", "field": "zoom"]
        facts["cameraOnlySelection"] = cameraConfig.layerIDs.isEmpty && cameraRows.count == 3
            && cameraFrames.allSatisfy { ($0["values"] as! [[String: Any]]).count == 2 }
            && cameraRows.allSatisfy { $0["target"] as? [String: String] == cameraIdentity }
        facts["cameraProgramProjection"] = cameraOutput[0]["cameraZoom"] as? Bool == true
            && cameraBindings.count == 2 && cameraBindings[0]["target"] as? [String: String] == cameraIdentity
            && cameraBindings[0]["owner"] as? [String: String] == cameraIdentity
            && cameraBindings[0]["keyframeCounts"] as? [Int] == [2]
            && (cameraBindings[0]["authored"] as! [String: Any])["value"] as? Double == 3
        facts["cameraTimelineAndWriterSource"] = cameraRows[0]["source"] as? String == "timeline"
            && (cameraRows[0]["resolved"] as! [String: Any])["value"] as? Double == 1
            && cameraRows[1]["source"] as? String == "sceneScript"
            && (cameraRows[1]["resolved"] as! [String: Any])["value"] as? Double == 2
            && cameraRows.prefix(2).allSatisfy { ($0["resolved"] as! [String: Any])["type"] as? String == "scalar" }
            && cameraRows.prefix(2).allSatisfy { ($0["authored"] as! [String: Any])["value"] as? Double == 3 }
        let generalRows = cameraFrames.map { ($0["values"] as! [[String: Any]])[1] }
        facts["cameraGeneralIdentityAndIndependentSource"] = generalRows.allSatisfy {
            $0["target"] as? [String: String] == ["owner": "camera", "field": "generalZoom"]
        } && generalRows.prefix(2).allSatisfy {
            $0["source"] as? String == "timeline"
                && ($0["resolved"] as! [String: Any])["value"] as? Double == 1
                && ($0["authored"] as! [String: Any])["value"] as? Double == 3
        } && (cameraBindings[1]["target"] as? [String: String])?["field"] == "generalZoom"
        facts["cameraMissingIsNotUnitZoom"] = cameraRows[2]["source"] is NSNull
            && (cameraRows[2]["resolved"] as! [String: Any])["state"] as? String == "missing"
            && (cameraRows[2]["authored"] as! [String: Any])["state"] as? String == "missing"
        facts["cameraSingleCadenceAndBorrowedClock"] = cameraOutput.last?["samples"] as? Int == 3
            && before == playback.observationSnapshot() && originalSnapshot == resolution.snapshot
        var mixedLines: [String] = []
        let mixed = SceneTimelineFrameEvidence(configuration: try configuration(["cameraZoom": true]),
            budget: cameraBudget) { mixedLines.append($0) }
        mixed.record(streamID: 11, frameIndex: 42, sceneTime: 1, snapshot: originalSnapshot)
        mixed.finish()
        facts["cameraMixedAddsTwoInputRows"] = (try records(mixedLines)[0]["values"] as? [[String: Any]])?.count == 8
        var invalidCount = 0
        for bad in [["layerIDs": [Int]()], ["layerIDs": [layerID, layerID]],
                    ["layerIDs": Array(0..<9)],
                    ["sceneTimeWindow": [0, 11]], ["interval": 0.1], ["maxSamples": 33],
                    ["maxSamples": true], ["unrecognized": 1]] as [[String: Any]] {
            do { _ = try configuration(bad) } catch { invalidCount += 1 }
        }
        facts["strictConfiguration"] = invalidCount == 8
        var edgeLines: [String] = []
        let edgeBudget = SceneTimelineFrameEvidence.OutputBudget(maximumStreams: 1)
        let disabled = SceneTimelineFrameEvidence(configuration: nil, budget: edgeBudget) { edgeLines.append($0) }
        disabled.record(streamID: 1, frameIndex: 42, sceneTime: 1, snapshot: originalSnapshot)
        disabled.finish()
        facts["disabledNoOutput"] = edgeLines.isEmpty && edgeBudget.consumedBytes == 0
        let invalid = SceneTimelineFrameEvidence(configuration: config, budget: edgeBudget) { edgeLines.append($0) }
        invalid.record(streamID: 1, frameIndex: 41, sceneTime: 1, snapshot: originalSnapshot)
        facts["invalidFrameNoCadence"] = edgeBudget.consumedBytes == 0
        invalid.finish()
        let invalidRow = try records(edgeLines).last!
        facts["invalidAndEmptyIncomplete"] = invalidRow["observationComplete"] as? Bool == false
            && (invalidRow["reasons"] as? [String])?.contains("frame-identity") == true
            && (invalidRow["reasons"] as? [String])?.contains("no-window-samples") == true
        edgeLines = []
        let outside = SceneTimelineFrameEvidence(configuration: config, budget: edgeBudget) { edgeLines.append($0) }
        outside.record(streamID: 1, frameIndex: 42, sceneTime: 3, snapshot: originalSnapshot)
        outside.finish()
        let next = SceneTimelineFrameEvidence(configuration: config, budget: edgeBudget) { edgeLines.append($0) }
        next.record(streamID: 2, frameIndex: 42, sceneTime: 1, snapshot: originalSnapshot)
        next.finish()
        let edgeRows = try records(edgeLines)
        facts["windowAndRetirement"] = edgeRows.contains {
            ($0["reasons"] as? [String])?.contains("no-window-samples") == true
        } && !edgeRows.contains { $0["kind"] as? String == "frame" }
        facts["streamBudgetNotRefunded"] = edgeRows.contains { $0["reason"] as? String == "stream-limit" }
        var boundedLines: [String] = []
        let tiny = SceneTimelineFrameEvidence.OutputBudget(maximumBytes: 1_024)
        let bounded = SceneTimelineFrameEvidence(configuration: config, budget: tiny) { boundedLines.append($0) }
        bounded.record(streamID: 1, frameIndex: 42, sceneTime: 1, snapshot: originalSnapshot)
        bounded.finish()
        let boundedRows = try records(boundedLines)
        facts["totalByteBound"] = tiny.consumedBytes <= 1_024
            && boundedLines.reduce(0, { $0 + $1.utf8.count }) <= 1_024
            && boundedRows.contains { $0["reason"] as? String == "output-byte-limit" }
        var clipped: [String] = []
        let clippingBudget = SceneTimelineFrameEvidence.OutputBudget()
        for diagnostics in [Array(repeating: "bounded diagnostic", count: 65), [String(repeating: "x", count: 70_000)]] {
            SceneTimelineFrameEvidence.recordProgram(.init(bindings: program.bindings, diagnostics: diagnostics),
                configuration: config, budget: clippingBudget) { clipped.append($0) }
        }
        let clippedRows = try records(clipped)
        facts["programTruncationIncomplete"] = clippedRows.allSatisfy { $0["observationComplete"] as? Bool == false }
            && (clippedRows[0]["diagnostics"] as? [String])?.count == 64
            && clippedRows[1]["reason"] as? String == "program-byte-limit-or-encoding"
        var duplicated: [String] = []
        SceneTimelineFrameEvidence.recordProgram(.init(bindings: Array(repeating: binding, count: 25), diagnostics: []),
            configuration: config, budget: clippingBudget) { duplicated.append($0) }
        let duplicateRow = try records(duplicated)[0]
        facts["bindingLimitIncomplete"] = duplicateRow["observationComplete"] as? Bool == false
            && (duplicateRow["bindings"] as? [[String: Any]])?.count == 24
        let badDefinition = SceneDynamicTargetDefinition(target: binding.target,
            valueType: binding.definition.valueType, authoredValue: .vector3(.nan, 0, 0))
        let badBinding = SceneTimelineBinding(definition: badDefinition, animation: binding.animation,
            composition: binding.composition, playbackOwner: binding.playbackOwner)
        var nonfinite: [String] = []
        SceneTimelineFrameEvidence.recordProgram(.init(bindings: [badBinding], diagnostics: []),
            configuration: config, budget: clippingBudget) { nonfinite.append($0) }
        let badRecord = try records(nonfinite)[0]
        let badRow = (badRecord["bindings"] as! [[String: Any]])[0]
        facts["nonfiniteExplicit"] = badRecord["observationComplete"] as? Bool == false
            && (badRow["authored"] as! [String: Any])["state"] as? String == "nonfinite"
        return facts
    }
}

@main
enum TimelineFrameEvidenceHarness {
    static func main() throws {
        var results: [String: Any] = [:]
        for layerID in [71, 907] {
            // Self-authored curves enter the real parser; compiler admission is
            // outside this diagnostic cut, just as in the named-Timeline gate.
            func animation(vector: Bool) throws -> SceneTimelineAnimation {
                var authored: [String: Any] = ["relative": true,
                    "options": ["fps": 30, "length": 60, "mode": "loop", "startpaused": false]]
                for component in 0..<(vector ? 3 : 1) {
                    authored["c\(component)"] = [["frame": 0, "value": 0],
                        ["frame": 30, "value": Double(component + 1)]]
                }
                let parsed = SceneTimelineAnimationParser.parse(host: ["value": vector ? "10 20 30" : "1",
                    "animation": authored])
                guard parsed.diagnostics.isEmpty, let value = parsed.animation else {
                    throw NSError(domain: "self-authored animation did not parse", code: 1)
                }
                return value
            }
            let vector = try animation(vector: true)
            let root = SceneDynamicTarget.layer(layerID: layerID, field: .origin)
            var bindings = [SceneDynamicLayerField.origin, .angles, .scale].map { field in
                SceneTimelineBinding(definition: .init(target: .layer(layerID: layerID, field: field),
                    valueType: .vector3, authoredValue: .vector3(10, 20, 30)),
                    animation: vector, composition: .additive, playbackOwner: root)
            }
            bindings.append(SceneTimelineBinding(definition: .init(
                target: .layer(layerID: layerID + 1, field: .alpha), valueType: .scalar,
                authoredValue: .scalar(1)), animation: try animation(vector: false), composition: .absolute))
            results[String(layerID)] = try SceneTimelineFrameEvidenceChecks.frameEvidence(
                .init(bindings: bindings, diagnostics: []))
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), as: UTF8.self))
    }
}
