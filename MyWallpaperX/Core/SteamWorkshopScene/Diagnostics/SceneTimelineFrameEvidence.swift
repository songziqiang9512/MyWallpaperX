#if DEBUG
import Foundation

/// Opt-in input observations. Never samples playback or retains a prepared Scene.
nonisolated final class SceneTimelineFrameEvidence {
    static let environmentKey = "MYWALLPAPERX_SCENE_DEBUG_TIMELINE_EVIDENCE"
    static let prefix = "MWX DEBUG SCENE: phase=timeline-frame-input json="
    private static let maximumRecordBytes = 64 * 1_024

    nonisolated struct Configuration: Equatable, Sendable {
        let layerIDs: [Int]
        let start, end, interval: Double
        let maxSamples: Int

        private struct Payload: Decodable {
            let layerIDs: [Int]
            let sceneTimeWindow: [Double]
            let interval: Double
            let maxSamples: Int
        }

        enum Invalid: Error { case configuration }

        static func parse(_ raw: String) throws -> Configuration {
            let data = Data(raw.utf8)
            guard data.count <= 4_096,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == ["layerIDs", "sceneTimeWindow", "interval", "maxSamples"]
            else { throw Invalid.configuration }
            let value = try JSONDecoder().decode(Payload.self, from: data)
            guard (1...8).contains(value.layerIDs.count),
                  Set(value.layerIDs).count == value.layerIDs.count,
                  value.layerIDs.allSatisfy({ $0 >= 0 }),
                  value.sceneTimeWindow.count == 2,
                  value.sceneTimeWindow.allSatisfy(\.isFinite),
                  value.sceneTimeWindow[0] >= 0,
                  value.sceneTimeWindow[1] > value.sceneTimeWindow[0],
                  value.sceneTimeWindow[1] - value.sceneTimeWindow[0] <= 10,
                  value.interval.isFinite, value.interval >= 0.2,
                  (1...32).contains(value.maxSamples)
            else { throw Invalid.configuration }
            return Configuration(layerIDs: value.layerIDs.sorted(),
                start: value.sceneTimeWindow[0], end: value.sceneTimeWindow[1],
                interval: value.interval, maxSamples: value.maxSamples)
        }

        var targets: [SceneDynamicTarget] {
            layerIDs.flatMap { id in
                [SceneDynamicLayerField.origin, .angles, .scale].map {
                    .layer(layerID: id, field: $0)
                }
            }
        }
    }

    /// Process-cumulative scalar budgets. Retirement never refunds authority.
    nonisolated final class OutputBudget: @unchecked Sendable {
        private let lock = NSLock()
        private let maximumStreams: Int
        private let maximumBytes: Int
        private var streams = 0
        private var bytes = 0

        init(maximumStreams: Int = 8, maximumBytes: Int = 512 * 1_024) {
            self.maximumStreams = min(max(0, maximumStreams), 8)
            self.maximumBytes = min(max(0, maximumBytes), 512 * 1_024)
        }

        var consumedBytes: Int {
            lock.lock(); defer { lock.unlock() }
            return bytes
        }

        func admitStream(emit: (String) -> Void) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard streams < maximumStreams else {
                noticeLocked("stream-limit", emit: emit)
                return false
            }
            streams += 1
            return true
        }

        @discardableResult
        func write(_ object: [String: Any], emit: (String) -> Void) -> Bool {
            let line = SceneTimelineFrameEvidence.line(object)
            lock.lock(); defer { lock.unlock() }
            guard let line else {
                noticeLocked("record-limit-or-encoding", emit: emit)
                return false
            }
            // Reserve a terminal failure and conservatively account for NSLog framing.
            let cost = line.utf8.count + 256
            guard cost <= maximumBytes - bytes - min(512, maximumBytes / 2) else {
                noticeLocked("output-byte-limit", emit: emit)
                bytes = maximumBytes
                return false
            }
            bytes += cost
            emit(line)
            return true
        }

        private func noticeLocked(_ reason: String, emit: (String) -> Void) {
            guard let line = SceneTimelineFrameEvidence.line([
                "kind": "limit", "observationComplete": false, "reason": reason
            ]), line.utf8.count + 256 <= maximumBytes - bytes else { return }
            bytes += line.utf8.count + 256
            emit(line)
        }
    }

    private static let processBudget = OutputBudget()
    private static let liveConfiguration: Configuration? = {
        guard let raw = ProcessInfo.processInfo.environment[environmentKey] else { return nil }
        do { return try Configuration.parse(raw) }
        catch {
            processBudget.write(["kind": "configuration", "observationComplete": false,
                "reason": "invalid-configuration"], emit: log)
            return nil
        }
    }()

    static func make(evidenceWindow: Bool) -> SceneTimelineFrameEvidence? {
        guard evidenceWindow, let configuration = liveConfiguration else { return nil }
        return SceneTimelineFrameEvidence(configuration: configuration,
            budget: processBudget, emit: log)
    }

    static func recordProgram(_ program: SceneTimelineProgram, evidenceWindow: Bool) {
        guard evidenceWindow, let configuration = liveConfiguration else { return }
        recordProgram(program, configuration: configuration, budget: processBudget, emit: log)
    }

    @discardableResult
    static func recordProgram(_ program: SceneTimelineProgram, configuration: Configuration,
                              budget: OutputBudget, emit: (String) -> Void) -> Bool {
        let targets = Set(configuration.targets)
        var selectedCount = 0
        var rows: [[String: Any]] = []
        var invalidMetadata = false
        for binding in program.bindings where targets.contains(binding.target) {
            selectedCount += 1
            guard rows.count < 24 else { continue }
            let options = binding.animation.options
            let finiteOptions = [options.fps, options.length]
                + [options.smoothing, options.stiffness].compactMap { $0 }
            let nonfinite = !finiteOptions.allSatisfy(\.isFinite)
                || !binding.definition.authoredValue.isFinite
            invalidMetadata = invalidMetadata || nonfinite || binding.animation.lanes.count > 4
            rows.append([
                "target": targetRecord(binding.target),
                "valueType": binding.definition.valueType.rawValue,
                "authored": valueRecord(binding.definition.authoredValue),
                "composition": binding.composition.rawValue,
                "owner": targetRecord(binding.playbackOwnerTarget),
                "nonfiniteMetadata": nonfinite,
                "options": ["fps": number(options.fps), "length": number(options.length),
                    "mode": options.mode.rawValue, "startsPaused": options.startsPaused,
                    "wrapsLoop": options.wrapsLoop,
                    "smoothing": options.smoothing.map(number) ?? NSNull(),
                    "stiffness": options.stiffness.map(number) ?? NSNull()],
                "laneCount": binding.animation.lanes.count,
                "keyframeCounts": binding.animation.lanes.prefix(4).map(\.count)
            ])
        }
        var record: [String: Any] = ["kind": "program", "layerIDs": configuration.layerIDs,
            "bindingCount": program.bindings.count, "selectedBindingCount": selectedCount,
            "bindings": rows, "diagnosticCount": program.diagnostics.count,
            "diagnostics": Array(program.diagnostics.prefix(64)),
            "observationComplete": selectedCount <= 24 && program.diagnostics.count <= 64 && !invalidMetadata]
        if line(record) == nil {
            record = ["kind": "program", "observationComplete": false,
                "reason": "program-byte-limit-or-encoding", "layerIDs": configuration.layerIDs,
                "selectedBindingCount": selectedCount, "diagnosticCount": program.diagnostics.count]
        }
        return budget.write(record, emit: emit)
    }

    private let configuration: Configuration?
    private let budget: OutputBudget
    private let emit: (String) -> Void
    private var stream: UInt64?
    private var streamAdmitted = false
    private var lastFrame: UInt64?
    private var lastFrameTime: Double?
    private var lastGeneration: UInt64?
    private var lastSampleTime: Double?
    private var samples = 0
    private var incomplete: Set<String> = []
    private var finished = false

    init(configuration: Configuration?, budget: OutputBudget, emit: @escaping (String) -> Void) {
        self.configuration = configuration
        self.budget = budget
        self.emit = emit
    }

    deinit { finish() }

    func record(streamID: UInt64, frameIndex: UInt64, sceneTime: Double,
                snapshot: SceneDynamicSnapshot) {
        guard !finished, let configuration else { return }
        guard sceneTime.isFinite, sceneTime >= 0, snapshot.frameIndex == frameIndex,
              stream == nil || stream == streamID else {
            incomplete.insert("frame-identity")
            return
        }
        if lastFrame == frameIndex {
            if lastFrameTime != sceneTime || lastGeneration != snapshot.generation {
                incomplete.insert("frame-identity")
            }
            return
        }
        guard lastFrame.map({ frameIndex > $0 }) ?? true,
              lastFrameTime.map({ sceneTime >= $0 }) ?? true else {
            incomplete.insert("frame-order")
            return
        }
        if stream == nil {
            stream = streamID
            streamAdmitted = budget.admitStream(emit: emit)
        }
        guard streamAdmitted else { incomplete.insert("stream-limit"); return }
        lastFrame = frameIndex
        lastFrameTime = sceneTime
        lastGeneration = snapshot.generation
        guard (configuration.start...configuration.end).contains(sceneTime),
              lastSampleTime.map({ sceneTime - $0 >= configuration.interval }) ?? true else { return }
        guard samples < configuration.maxSamples else {
            incomplete.insert("sample-limit")
            return
        }
        var rows: [[String: Any]] = []
        for target in configuration.targets {
            let resolved = snapshot[target]
            let authored = snapshot.authoredValue(for: target)
            if resolved?.value.isFinite == false || authored?.isFinite == false {
                incomplete.insert("nonfinite-value")
            }
            rows.append(["target": Self.targetRecord(target),
                "resolved": Self.valueRecord(resolved?.value),
                "source": resolved.map { $0.source.rawValue as Any } ?? NSNull(),
                "authored": Self.valueRecord(authored)])
        }
        let written = budget.write(["kind": "frame", "stream": streamID,
            "frame": frameIndex, "sceneTime": sceneTime,
            "snapshotFrame": snapshot.frameIndex, "generation": snapshot.generation,
            "values": rows, "observationComplete": incomplete.isEmpty], emit: emit)
        if written { samples += 1; lastSampleTime = sceneTime }
        else { incomplete.insert("output-limit"); finished = true }
    }

    func finish() {
        guard !finished, configuration != nil else { return }
        finished = true
        if samples == 0 { incomplete.insert("no-window-samples") }
        budget.write(["kind": "retired", "stream": stream.map { $0 as Any } ?? NSNull(),
            "samples": samples, "observationComplete": incomplete.isEmpty,
            "reasons": incomplete.sorted()], emit: emit)
    }

    private static func valueRecord(_ value: SceneDynamicValue?) -> [String: Any] {
        guard let value else { return ["state": "missing", "type": NSNull(), "value": NSNull()] }
        guard value.isFinite else {
            return ["state": "nonfinite", "type": value.valueType.rawValue, "value": NSNull()]
        }
        let payload: Any
        switch value {
        case let .bool(value): payload = value
        case let .scalar(value): payload = value
        case let .vector2(x, y): payload = [x, y]
        case let .vector3(x, y, z): payload = [x, y, z]
        case let .vector4(x, y, z, w): payload = [x, y, z, w]
        case .string: return ["state": "unexpected-type", "type": "string", "value": NSNull()]
        }
        return ["state": "present", "type": value.valueType.rawValue, "value": payload]
    }

    private static func targetRecord(_ target: SceneDynamicTarget) -> [String: Any] {
        if case let .layer(layerID, field) = target {
            return ["layerID": layerID, "field": field.rawValue]
        }
        return ["unsupportedOwner": true]
    }

    private static func number(_ value: Double) -> Any { value.isFinite ? value as Any : NSNull() }

    private static func line(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              data.count + prefix.utf8.count <= maximumRecordBytes else { return nil }
        return prefix + String(decoding: data, as: UTF8.self)
    }

    private static func log(_ line: String) { NSLog("%@", line) }
}
#endif
