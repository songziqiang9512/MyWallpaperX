#if DEBUG
import Foundation
@preconcurrency import Metal

nonisolated final class SceneEffectExecutionTelemetry: @unchecked Sendable {
    typealias LogSink = @Sendable (String) -> Void

    private struct StickyFacts {
        var encoded = false
        var failed = false

        mutating func insert(_ fact: SceneEffectOutcomeFact) -> Bool {
            switch fact {
            case .encoded:
                guard !encoded else { return false }
                encoded = true
            case .failed:
                guard !failed else { return false }
                failed = true
            }
            return true
        }
    }

    private let lock = NSLock()
    private let logSink: LogSink
    private var invocationFacts: [SceneEffectInvocationSubject: StickyFacts] = [:]
    private var routeFacts: [SceneEffectRouteSubject: StickyFacts] = [:]
    private var frameFacts: Set<SceneFrameCommandBufferStatus> = []
    private var admissionReportLines: [String] = []
    private var resolvedMaterialSummaryLayerIDs: Set<Int> = []

    init(logSink: @escaping LogSink = { NSLog("%@", $0) }) {
        self.logSink = logSink
    }

    func installPreparedAdmission(
        reportLines: [String],
        resolvedMaterialLayerIDs: Set<Int>
    ) {
        withLock {
            admissionReportLines = reportLines
            resolvedMaterialSummaryLayerIDs = resolvedMaterialLayerIDs
        }
    }

    var preparedRuntimeReportLines: [String] {
        withLock { admissionReportLines }
    }

    func effectRuntimeSummary(for layerID: Int) -> String? {
        withLock {
            resolvedMaterialSummaryLayerIDs.contains(layerID)
                ? "effect runtime resolved-material-graph; graph owner" : nil
        }
    }

    func makeFrame(frameIndex: UInt64, observesComposition: Bool = false,
                   commandBufferToken: String? = nil, captureRequestID: UInt64? = nil) -> SceneEffectExecutionFrameTrace {
        SceneEffectExecutionFrameTrace(frameIndex: frameIndex, telemetry: self,
            observesComposition: observesComposition, commandBufferToken: commandBufferToken,
            captureRequestID: captureRequestID)
    }

    @discardableResult
    func observeSharedCommandBuffer(
        for trace: SceneEffectExecutionFrameTrace,
        on commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard let cohort = trace.freeze() else { return false }
        let composition = trace.isCompositionSelected ? trace.frozenCompositionObservation() : nil
        commandBuffer.addCompletedHandler { [weak self] completed in
            let status: SceneFrameCommandBufferStatus = completed.status == .completed
                ? .completed
                : .failed
            self?.reduceSharedCommandBufferStatus(cohort: cohort, status: status)
            self?.emitComposition(composition, status: status.rawValue,
                error: completed.error.map { String(describing: $0) })
        }
        return true
    }

    @discardableResult
    func reduceSharedCommandBufferStatus(
        for trace: SceneEffectExecutionFrameTrace,
        status: SceneFrameCommandBufferStatus
    ) -> Bool {
        guard let cohort = trace.freeze() else { return false }
        return reduceSharedCommandBufferStatus(cohort: cohort, status: status)
    }

    func recordCompositionCancellation(for trace: SceneEffectExecutionFrameTrace) {
        guard trace.isCompositionSelected else { return }
        _ = trace.freeze()
        emitComposition(trace.frozenCompositionObservation(), status: "cancelled-not-submitted")
    }

    private func emitComposition(_ observation: SceneCompositionFrameObservation?,
                                 status: String, error: String? = nil) {
        guard var observation else { return }
        observation.gpuStatus = status
        observation.gpuError = error.map { String($0.prefix(512)) }
        guard let data = try? JSONEncoder().encode(observation),
              let json = String(data: data, encoding: .utf8) else { return }
        logSink("MWX SCENE COMPOSITION OBSERVATION: " + json)
    }

    func recordInvocationTransition(
        _ event: SceneEffectInvocationEvent,
        frameIndex: UInt64
    ) {
        let shouldLog = withLock {
            var facts = invocationFacts[event.subject, default: StickyFacts()]
            let inserted = facts.insert(event.outcome.details.fact)
            invocationFacts[event.subject] = facts
            return inserted
        }
        guard shouldLog else { return }
        logSink(
            "MWX DEBUG SCENE: schema=1 axis=effect-cpu-invocation "
                + "frame=\(frameIndex) \(event.logFields.joined(separator: " "))"
        )
    }

    func recordRouteTransition(
        _ event: SceneEffectRouteEvent,
        frameIndex: UInt64
    ) {
        let shouldLog = withLock {
            var facts = routeFacts[event.subject, default: StickyFacts()]
            let inserted = facts.insert(event.outcome.details.fact)
            routeFacts[event.subject] = facts
            return inserted
        }
        guard shouldLog else { return }
        logSink(
            "MWX DEBUG SCENE: schema=1 axis=effect-route-operation "
                + "frame=\(frameIndex) \(event.logFields.joined(separator: " "))"
        )
    }

    @discardableResult
    private func reduceSharedCommandBufferStatus(
        cohort: SceneEffectExecutionFrameCohort,
        status: SceneFrameCommandBufferStatus
    ) -> Bool {
        let shouldLog = withLock {
            frameFacts.insert(status).inserted
        }
        guard shouldLog else { return false }
        logSink(
            "MWX DEBUG SCENE: schema=1 axis=scene-frame-command-buffer "
                + "frame=\(cohort.frameIndex) attemptedEffects=\(cohort.attemptedEffects) "
                + "returnedOutputs=\(cohort.returnedOutputs) "
                + "failedInvocations=\(cohort.failedInvocations) "
                + "routeOperations=\(cohort.routeOperations) "
                + "cohortSHA256=\(cohort.cohortSHA256) status=\(status.rawValue)"
        )
        return true
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

extension SceneCompositionTextureObservation {
    init(_ texture: MTLTexture, role: String) {
        self.init(textureToken: String(UInt(bitPattern: ObjectIdentifier(texture))),
            width: texture.width, height: texture.height,
            pixelFormat: texture.pixelFormat.rawValue, role: role)
    }
}

#endif
