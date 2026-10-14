#if DEBUG
import Foundation
@preconcurrency import Metal
import Synchronization

// Temporary, one-frame public-counter qualification. Telemetry owns the only
// request. These helpers never authorize a draw, publication, or submission.
nonisolated enum SceneGPUStageTimestampHook {
    struct Configuration {
        let output: URL
        let delay: TimeInterval
    }

    static let configuration: Configuration? = {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["MWX_SCENE_GPU_STAGE_TIMESTAMPS_OUTPUT"],
              path.hasPrefix("/") else { return nil }
        let delay = Double(environment["MWX_SCENE_GPU_STAGE_TIMESTAMPS_DELAY_SECONDS"] ?? "30")
        guard let delay, delay.isFinite, (0 ... 600).contains(delay) else { return nil }
        return Configuration(output: URL(fileURLWithPath: path), delay: delay)
#else
        return nil
#endif
    }()

    static var enabled: Bool { configuration != nil }
    private static var owner: SceneFramePerformanceTelemetry { .debugEvidence }
    private static func key(_ buffer: MTLCommandBuffer) -> UInt {
        UInt(bitPattern: ObjectIdentifier(buffer))
    }
    static func isSelected(_ buffer: MTLCommandBuffer) -> Bool {
        guard enabled else { return false }
        return owner.gpuStageTimestampActiveCB.load(ordering: .acquiring) == key(buffer)
    }

    static func begin(_ buffer: MTLCommandBuffer, frameIndex: UInt64,
                      registryEpochBeforeBegin: UInt64) {
        guard let configuration else { return }
        let telemetry = owner
        telemetry.withGPUStageTimestampLock {
            if telemetry.gpuStageTimestampRequest == nil {
                telemetry.gpuStageTimestampRequest = .init(configuration: configuration)
            }
            guard let request = telemetry.gpuStageTimestampRequest,
                  !request.consumed,
                  ProcessInfo.processInfo.systemUptime - request.started >= configuration.delay else { return }
            request.consumed = true
            do {
                let record = try SceneGPUStageTimestampRecord(
                    buffer: buffer, frameIndex: frameIndex,
                    registryEpochBeforeBegin: registryEpochBeforeBegin
                )
                request.record = record
                telemetry.gpuStageTimestampActiveCB.store(key(buffer), ordering: .releasing)
            } catch {
                write(["status": "setup-failed", "reason": String(describing: error)], to: configuration.output)
            }
        }
    }

    static func frameEpoch(_ epoch: UInt64, on buffer: MTLCommandBuffer) {
        guard isSelected(buffer) else { return }
        owner.withGPUStageTimestampLock {
            guard let record = owner.gpuStageTimestampRequest?.record else { return }
            if let previous = record.frameEpoch, previous != epoch {
                record.validity.invalidate("frame-epoch-changed")
            }
            record.frameEpoch = epoch
        }
    }

    static func surface(_ buffer: MTLCommandBuffer, frameIndex: UInt64, surfaceID: UInt32) {
        guard isSelected(buffer) else { return }
        owner.withGPUStageTimestampLock {
            guard let record = owner.gpuStageTimestampRequest?.record else { return }
            guard record.frameIndex == frameIndex else {
                record.validity.invalidate("surface-frame-index-mismatch")
                return
            }
            if let previous = record.surfaceID, previous != surfaceID {
                record.validity.invalidate("surface-identity-changed")
            }
            record.surfaceID = surfaceID
        }
    }

    static func coordinator(_ buffer: MTLCommandBuffer, ownerIdentity: UInt,
                            observationID: UInt64,
                            resetGeneration: UInt64, effectGeneration: UInt64,
                            executionEpoch: UInt64, frameEpoch: UInt64) {
        guard isSelected(buffer) else { return }
        owner.withGPUStageTimestampLock {
            guard let record = owner.gpuStageTimestampRequest?.record else { return }
            let facts = ["ownerIdentity": String(ownerIdentity), "observationID": String(observationID),
                         "resetGeneration": String(resetGeneration),
                         "effectGeneration": String(effectGeneration),
                         "executionEpoch": String(executionEpoch),
                         "frameEpoch": String(frameEpoch)]
            if let previous = record.coordinatorFacts, previous != facts {
                record.validity.invalidate("coordinator-identity-changed")
            }
            if record.frameEpoch != frameEpoch { record.validity.invalidate("coordinator-frame-epoch-mismatch") }
            record.coordinatorFacts = facts
        }
    }

    static func invalidate(reason: String) {
        guard enabled else { return }
        owner.withGPUStageTimestampLock {
            let request = owner.gpuStageTimestampRequest
            request?.record?.validity.invalidate(reason)
            request?.inFlightRecord?.validity.invalidate(reason)
        }
    }

    static func invalidateCoordinator(_ identity: UInt, reason: String) {
        guard enabled else { return }
        owner.withGPUStageTimestampLock {
            let request = owner.gpuStageTimestampRequest
            for record in [request?.record, request?.inFlightRecord].compactMap({ $0 })
            where record.coordinatorFacts?["ownerIdentity"] == String(identity) {
                record.validity.invalidate("coordinator-" + reason)
            }
        }
    }

    static func graphScope<T>(_ buffer: MTLCommandBuffer, layerID: Int,
                              effectIndex: Int? = nil, commandOrdinal: Int? = nil,
                              ledgerID: UInt64? = nil,
                              _ operation: () -> T) -> T {
        guard isSelected(buffer) else { return operation() }
        let previous = owner.withGPUStageTimestampLock { () -> ([String: Int], UInt64?) in
            guard let record = owner.gpuStageTimestampRequest?.record else { return ([:], nil) }
            let previous = record.graphFacts
            let previousLedger = record.currentLedgerID
            record.graphFacts = ["layerID": layerID]
            if let effectIndex { record.graphFacts["effectIndex"] = effectIndex }
            if let commandOrdinal { record.graphFacts["commandOrdinal"] = commandOrdinal }
            if let ledgerID { record.currentLedgerID = ledgerID }
            return (previous, previousLedger)
        }
        defer {
            owner.withGPUStageTimestampLock {
                owner.gpuStageTimestampRequest?.record?.graphFacts = previous.0
                owner.gpuStageTimestampRequest?.record?.currentLedgerID = previous.1
            }
        }
        return operation()
    }

    static func render(_ buffer: MTLCommandBuffer, _ descriptor: MTLRenderPassDescriptor,
                       role: String, layerID: Int? = nil,
                       knownNoDraw: Bool = false,
                       expectsFragment: Bool = true) -> MTLRenderCommandEncoder? {
        guard isSelected(buffer) else {
            return buffer.makeRenderCommandEncoder(descriptor: descriptor)
        }
        let row = owner.withGPUStageTimestampLock { () -> Int? in
            guard let record = owner.gpuStageTimestampRequest?.record else { return nil }
            return record.configureRender(descriptor, role: role, layerID: layerID,
                                          knownNoDraw: knownNoDraw, expectsFragment: expectsFragment)
        }
        let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
        owner.withGPUStageTimestampLock {
            owner.gpuStageTimestampRequest?.record?.created(encoder, row: row)
        }
        return encoder
    }

    static func blit(_ buffer: MTLCommandBuffer, role: String) -> MTLBlitCommandEncoder? {
        guard isSelected(buffer) else { return buffer.makeBlitCommandEncoder() }
        let descriptor = MTLBlitPassDescriptor()
        let row = owner.withGPUStageTimestampLock { () -> Int? in
            owner.gpuStageTimestampRequest?.record?.configureBlit(descriptor, role: role)
        }
        let encoder = buffer.makeBlitCommandEncoder(descriptor: descriptor)
        owner.withGPUStageTimestampLock {
            owner.gpuStageTimestampRequest?.record?.created(encoder, row: row)
        }
        return encoder
    }

    // Called immediately after actual native draw commands. A foreign encoder
    // cannot borrow the selected CB's identity; weak identity rejects reuse.
    static func drew(_ encoder: MTLRenderCommandEncoder) {
        guard enabled,
              owner.gpuStageTimestampActiveCB.load(ordering: .acquiring) != 0 else { return }
        owner.withGPUStageTimestampLock {
            owner.gpuStageTimestampRequest?.record?.drew(encoder)
        }
    }

    static func endedMain(_ encoder: MTLRenderCommandEncoder) {
        guard enabled,
              owner.gpuStageTimestampActiveCB.load(ordering: .acquiring) != 0 else { return }
        owner.withGPUStageTimestampLock {
            owner.gpuStageTimestampRequest?.record?.endedMain(encoder)
        }
    }

    static func cancel(_ buffer: MTLCommandBuffer, reason: String) {
        guard isSelected(buffer) else { return }
        let output = owner.withGPUStageTimestampLock { () -> (URL, [String: Any])? in
            guard let request = owner.gpuStageTimestampRequest,
                  let record = request.record else { return nil }
            owner.gpuStageTimestampActiveCB.store(0, ordering: .releasing)
            request.record = nil
            return (request.configuration.output, record.cancelled(reason: reason))
        }
        if let output { write(output.1, to: output.0) }
    }

    static func submitted(_ buffer: MTLCommandBuffer) {
        guard isSelected(buffer) else { return }
        let observation = owner.withGPUStageTimestampLock { () -> (URL, SceneGPUStageTimestampRecord)? in
            guard let request = owner.gpuStageTimestampRequest,
                  let record = request.record else { return nil }
            owner.gpuStageTimestampActiveCB.store(0, ordering: .releasing)
            request.record = nil
            request.inFlightRecord = record
            if !record.validity.submit() { record.failures.append("invalid-diagnostic-submit") }
            record.encoders.removeAll()
            return (request.configuration.output, record)
        }
        guard let (url, record) = observation else { return }
        // No captured CB/renderer/session. The record owns only its bounded
        // metadata and sample buffer until this original completion fires.
        buffer.addCompletedHandler { completed in
            let final = record.sampleBuffer.device.sampleTimestamps()
            let succeeded = completed.status == .completed && completed.error == nil
            let result = owner.withGPUStageTimestampLock { () -> [String: Any] in
                guard let request = owner.gpuStageTimestampRequest,
                      request.inFlightRecord === record else {
                    return record.cancelled(reason: "late-retired-completion")
                }
                let result = record.completed(succeeded: succeeded, finalCPU: final.cpu,
                    finalGPU: final.gpu, gpuDuration: completed.gpuEndTime - completed.gpuStartTime)
                request.inFlightRecord = nil
                return result
            }
            write(result, to: url)
        }
    }

    private static func write(_ result: [String: Any], to url: URL) {
        // One bounded post-completion receipt; no per-pass log/IPC or GPU work.
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                guard data.count <= 512 * 1024 else { return }
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("MWX GPU stage timestamp receipt failed: %@", String(describing: error))
            }
        }
    }
}

nonisolated final class SceneGPUStageTimestampRequest {
    let configuration: SceneGPUStageTimestampHook.Configuration
    let started = ProcessInfo.processInfo.systemUptime
    var consumed = false
    var record: SceneGPUStageTimestampRecord?
    var inFlightRecord: SceneGPUStageTimestampRecord?
    init(configuration: SceneGPUStageTimestampHook.Configuration) { self.configuration = configuration }
}

nonisolated final class SceneGPUStageTimestampRecord: @unchecked Sendable {
    enum SetupFailure: Error { case timestampUnsupported, sampleBufferUnavailable }
    final class WeakEncoder {
        weak var encoder: AnyObject?
        let row: Int
        init(_ encoder: AnyObject, row: Int) { self.encoder = encoder; self.row = row }
    }
    static let maximumSamples = 1024
    let sampleBuffer: MTLCounterSampleBuffer
    let initialCPU, initialGPU: UInt64
    let frameIndex, registryEpochBeforeBegin, deviceRegistryID: UInt64
    let commandBufferIdentity, commandQueueIdentity: UInt
    var frameEpoch: UInt64?
    var surfaceID: UInt32?
    var coordinatorFacts: [String: String]?
    var graphFacts: [String: Int] = [:]
    var rows: [SceneGPUStageTimestampRow] = []
    var encoders: [ObjectIdentifier: WeakEncoder] = [:]
    var failures: [String] = []
    private var sampleRanges = SceneGPUStageTimestampSampleRanges()
    var usedSamples: Int { sampleRanges.used }
    var validity = SceneGPUStageTimestampValidity()
    var currentLedgerID: UInt64?

    init(buffer: MTLCommandBuffer, frameIndex: UInt64, registryEpochBeforeBegin: UInt64) throws {
        let device = buffer.commandQueue.device
        guard device.supportsCounterSampling(.atStageBoundary),
              let counterSet = device.counterSets?.first(where: { $0.name == MTLCommonCounterSet.timestamp.rawValue }),
              counterSet.counters.contains(where: { $0.name == MTLCommonCounter.timestamp.rawValue }) else {
            throw SetupFailure.timestampUnsupported
        }
        let descriptor = MTLCounterSampleBufferDescriptor()
        descriptor.counterSet = counterSet
        descriptor.storageMode = .shared
        descriptor.sampleCount = Self.maximumSamples
        descriptor.label = "MyWallpaperX one-frame timestamp qualification"
        guard let samples = try? device.makeCounterSampleBuffer(descriptor: descriptor) else {
            throw SetupFailure.sampleBufferUnavailable
        }
        sampleBuffer = samples
        let initial = device.sampleTimestamps()
        initialCPU = initial.cpu; initialGPU = initial.gpu
        self.frameIndex = frameIndex
        self.registryEpochBeforeBegin = registryEpochBeforeBegin
        deviceRegistryID = device.registryID
        commandBufferIdentity = UInt(bitPattern: ObjectIdentifier(buffer))
        commandQueueIdentity = UInt(bitPattern: ObjectIdentifier(buffer.commandQueue))
    }

    private func reserve(_ count: Int, role: String) -> Int? {
        guard let base = sampleRanges.reserve(count) else {
            if !failures.contains("sample-capacity-exceeded") { failures.append("sample-capacity-exceeded") }
            return nil
        }
        return base
    }

    func configureRender(_ descriptor: MTLRenderPassDescriptor, role: String,
                         layerID: Int?, knownNoDraw: Bool, expectsFragment: Bool) -> Int? {
        guard let base = reserve(4, role: role) else { return nil }
        guard let attachment = descriptor.sampleBufferAttachments[0],
              let color = descriptor.colorAttachments[0] else {
            failures.append("render-sample-attachment-unavailable")
            return nil
        }
        attachment.sampleBuffer = sampleBuffer
        attachment.startOfVertexSampleIndex = base
        attachment.endOfVertexSampleIndex = base + 1
        attachment.startOfFragmentSampleIndex = base + 2
        attachment.endOfFragmentSampleIndex = base + 3
        let target = color.texture ?? descriptor.depthAttachment.texture
        var facts = graphFacts
        if let layerID { facts["layerID"] = layerID }
        var row = SceneGPUStageTimestampRow(
            ordinal: rows.count, kind: "render", role: role, base: base, count: 4,
            drawPresence: knownNoDraw ? "no" : "unknown", facts: facts,
            target: target.map { ["width": $0.width, "height": $0.height,
                                 "pixelFormat": Int($0.pixelFormat.rawValue), "sampleCount": $0.sampleCount] } ?? [:],
            attachments: ["colorLoad": Int(color.loadAction.rawValue), "colorStore": Int(color.storeAction.rawValue),
                          "depthLoad": Int(descriptor.depthAttachment.loadAction.rawValue),
                          "depthStore": Int(descriptor.depthAttachment.storeAction.rawValue)],
            expectsFragment: expectsFragment
        )
        row.ledgerID = currentLedgerID.map(String.init)
        rows.append(row)
        return rows.count - 1
    }

    func configureBlit(_ descriptor: MTLBlitPassDescriptor, role: String) -> Int? {
        guard let base = reserve(2, role: role) else { return nil }
        guard let attachment = descriptor.sampleBufferAttachments[0] else {
            failures.append("blit-sample-attachment-unavailable")
            return nil
        }
        attachment.sampleBuffer = sampleBuffer
        attachment.startOfEncoderSampleIndex = base
        attachment.endOfEncoderSampleIndex = base + 1
        var row = SceneGPUStageTimestampRow(ordinal: rows.count, kind: "blit", role: role, base: base,
                          count: 2, drawPresence: "no", facts: graphFacts,
                          target: [:], attachments: [:])
        row.ledgerID = currentLedgerID.map(String.init)
        rows.append(row)
        return rows.count - 1
    }

    func created(_ encoder: MTLCommandEncoder?, row: Int?) {
        guard let row else { return }
        guard let encoder else { failures.append("encoder-creation-failed"); return }
        rows[row].created = true
        encoders[ObjectIdentifier(encoder)] = WeakEncoder(encoder, row: row)
    }

    func drew(_ encoder: MTLRenderCommandEncoder) {
        guard let entry = encoders[ObjectIdentifier(encoder)], entry.encoder === encoder else { return }
        rows[entry.row].drawPresence = "yes"
        rows[entry.row].encoderLabel = encoder.label
    }

    func endedMain(_ encoder: MTLRenderCommandEncoder) {
        guard let entry = encoders[ObjectIdentifier(encoder)], entry.encoder === encoder else { return }
        if rows[entry.row].drawPresence == "unknown" { rows[entry.row].drawPresence = "no" }
        rows[entry.row].encoderLabel = encoder.label
    }

    private func envelope(status: String) -> [String: Any] {
        var result: [String: Any] = [
            "status": status, "frameIndex": String(frameIndex),
            "registryEpochBeforeBegin": String(registryEpochBeforeBegin),
            "deviceRegistryID": String(deviceRegistryID),
            "commandBufferIdentity": String(commandBufferIdentity),
            "commandQueueIdentity": String(commandQueueIdentity),
            "initialCPU": String(initialCPU), "initialGPU": String(initialGPU),
            "usedSamples": usedSamples, "maximumSamples": Self.maximumSamples,
            "failures": failures,
            "scope": "One instrumented native CB; stage elapsed intervals may overlap; attachment load/store/clear costs are not fully covered.",
            "diagnosticReadbackSuppressed": true
        ]
        result["frameEpoch"] = frameEpoch.map(String.init)
        result["coordinator"] = coordinatorFacts
        result["surfaceID"] = surfaceID.map { String($0) }
        result["identityCoverage"] = coordinatorFacts != nil && surfaceID != nil
            ? "coordinator-and-surface-observed" : "not-observed"
        return result
    }

    func cancelled(reason: String) -> [String: Any] {
        validity.cancel(reason)
        var result = envelope(status: "cancelled")
        result["reason"] = reason
        result["passes"] = rows.map { $0.json() }
        return result
    }

    func completed(succeeded: Bool, finalCPU: UInt64, finalGPU: UInt64,
                   gpuDuration: Double) -> [String: Any] {
        let lifecycleValid = validity.complete(succeeded: succeeded)
        var result = envelope(status: "unqualified")
        result["lifecycleInvalidations"] = validity.invalidations
        result["finalCPU"] = String(finalCPU); result["finalGPU"] = String(finalGPU)
        if gpuDuration.isFinite, gpuDuration >= 0 { result["commandBufferGPUSeconds"] = gpuDuration }
        guard succeeded else { result["reason"] = "gpu-failed"; return result }
        guard usedSamples > 0,
              let data = try? sampleBuffer.resolveCounterRange(0 ..< usedSamples) else {
            result["reason"] = "resolve-failed"; return result
        }
        result["resolvedBytes"] = data.count
        guard data.count == usedSamples * MemoryLayout<MTLCounterResultTimestamp>.stride else {
            result["reason"] = "resolve-length-mismatch"; return result
        }
        let samples = data.withUnsafeBytes { raw in
            (0 ..< usedSamples).map { raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self) }
        }
        let assessment = SceneGPUStageTimestampAssessment.assess(
            rows: rows, samples: samples, initialCPU: initialCPU, initialGPU: initialGPU,
            finalCPU: finalCPU, finalGPU: finalGPU
        )
        result["passes"] = assessment.rows
        result["drawStageCoverageComplete"] = assessment.complete
        result["status"] = lifecycleValid && assessment.complete && failures.isEmpty
            && frameEpoch != nil && coordinatorFacts != nil && surfaceID != nil
            ? "qualified-stage-timing" : "unqualified"
        result["coverageOracle"] = "Successful instrumented descriptor creations plus actual draw hooks; existing census is incomplete and is only a cross-check."
        return result
    }
}

nonisolated struct SceneGPUStageTimestampRow {
    let ordinal: Int
    let kind, role: String
    let base, count: Int
    var drawPresence: String
    let facts, target, attachments: [String: Int]
    var created = false
    var expectsFragment = true
    var encoderLabel: String?
    var ledgerID: String?
    func json() -> [String: Any] {
        var result: [String: Any] = ["ordinal": ordinal, "kind": kind, "role": role,
         "sampleBase": base, "sampleCount": count, "created": created,
         "drawPresence": drawPresence, "facts": facts,
         "target": target, "attachments": attachments,
         "expectedStages": kind == "blit" ? ["blit"]
            : (expectsFragment ? ["vertex", "fragment"] : ["vertex"])]
        if let encoderLabel { result["encoderLabel"] = encoderLabel }
        if let ledgerID { result["ledgerID"] = ledgerID }
        return result
    }
}

// Diagnostic validity only; original owners still decide every real submit,
// cancel and release. Kept as a value so CPU-only counterexamples exercise it.
nonisolated struct SceneGPUStageTimestampValidity {
    private(set) var submitted = false
    private(set) var terminal = false
    private(set) var invalidations: [String] = []
    mutating func submit() -> Bool {
        guard !submitted, !terminal else { return false }
        submitted = true
        return true
    }
    mutating func invalidate(_ reason: String) {
        if !terminal, invalidations.count < 16, !invalidations.contains(reason) { invalidations.append(reason) }
    }
    mutating func cancel(_ reason: String) {
        invalidate(reason)
        terminal = true
    }
    mutating func complete(succeeded: Bool) -> Bool {
        guard submitted, !terminal else { return false }
        terminal = true
        return succeeded && invalidations.isEmpty
    }
}

nonisolated struct SceneGPUStageTimestampSampleRanges {
    private(set) var used = 0
    mutating func reserve(_ count: Int) -> Int? {
        guard count > 0, count <= SceneGPUStageTimestampRecord.maximumSamples,
              used <= SceneGPUStageTimestampRecord.maximumSamples - count else { return nil }
        let base = used
        used += count
        return base
    }
}

// Pure assessment is shared by the temporary CPU-only counterexample harness.
nonisolated enum SceneGPUStageTimestampAssessment {
    static func interval(_ begin: UInt64, _ end: UInt64, initialCPU: UInt64,
                         initialGPU: UInt64, finalCPU: UInt64, finalGPU: UInt64) -> Double? {
        guard finalCPU > initialCPU, finalGPU > initialGPU,
              begin != MTLCounterErrorValue, end != MTLCounterErrorValue,
              begin >= initialGPU, end >= begin, end <= finalGPU else { return nil }
        let value = Double(end - begin) * Double(finalCPU - initialCPU)
            / Double(finalGPU - initialGPU) / 1000
        return value.isFinite ? value : nil
    }

    static func assess(rows: [SceneGPUStageTimestampRow], samples: [UInt64],
                       initialCPU: UInt64, initialGPU: UInt64,
                       finalCPU: UInt64, finalGPU: UInt64) -> (complete: Bool, rows: [[String: Any]]) {
        var complete = !rows.isEmpty && finalCPU > initialCPU && finalGPU > initialGPU
        let output = rows.map { row -> [String: Any] in
            var output = row.json()
            guard row.created, row.base >= 0, row.count > 0,
                  row.base <= samples.count - row.count else {
                complete = false; output["timingState"] = "missing-samples"; return output
            }
            let values = Array(samples[row.base ..< row.base + row.count])
            output["rawTimestamps"] = values.map(String.init)
            // No draw was established independently. Even valid-looking stage
            // samples cannot prove that clear/load/store work was measured.
            if row.kind == "render", row.drawPresence != "yes" {
                if row.drawPresence == "unknown" { complete = false }
                output["timingState"] = row.drawPresence == "no"
                    ? "no-draw-attachment-cost-uncovered" : "draw-presence-unknown"
                return output
            }
            let pairs = row.kind == "render" ? (row.expectsFragment
                ? [(0, 1, "vertexUS"), (2, 3, "fragmentUS")] : [(0, 1, "vertexUS")])
                : [(0, 1, "blitUS")]
            var valid = true
            for (begin, end, key) in pairs {
                guard begin < values.count, end < values.count,
                      let value = interval(values[begin], values[end], initialCPU: initialCPU,
                                           initialGPU: initialGPU, finalCPU: finalCPU, finalGPU: finalGPU) else {
                    valid = false; continue
                }
                output[key] = value
            }
            if !valid { complete = false }
            output["timingState"] = valid ? "valid-stage-interval" : "invalid-stage-interval"
            return output
        }
        return (complete, output)
    }
}
#endif
