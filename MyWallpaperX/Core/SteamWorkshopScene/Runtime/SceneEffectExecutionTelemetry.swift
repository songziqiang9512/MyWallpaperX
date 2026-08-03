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

    init(logSink: @escaping LogSink = { NSLog("%@", $0) }) {
        self.logSink = logSink
    }

    func makeFrame(frameIndex: UInt64) -> SceneEffectExecutionFrameTrace {
        SceneEffectExecutionFrameTrace(frameIndex: frameIndex, telemetry: self)
    }

    @discardableResult
    func observeSharedCommandBuffer(
        for trace: SceneEffectExecutionFrameTrace,
        on commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard let cohort = trace.freeze() else { return false }
        commandBuffer.addCompletedHandler { [weak self] completed in
            let status: SceneFrameCommandBufferStatus = completed.status == .completed
                ? .completed
                : .failed
            self?.reduceSharedCommandBufferStatus(cohort: cohort, status: status)
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
