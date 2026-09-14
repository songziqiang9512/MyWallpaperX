import Foundation
@preconcurrency import Metal

nonisolated enum SceneGPUCompletionTelemetryEvent: Sendable {
    case encodingFailed
    case commandBufferCompleted(succeeded: Bool)
}

nonisolated enum SceneGPUCompletionTelemetryLogStatus: String, Sendable {
    case failed
    case succeeded
}

nonisolated struct SceneGPUCompletionTelemetrySnapshot: Equatable, Sendable {
    let encodingFailureObserved: Bool
    let commandBufferSuccessObserved: Bool
    let commandBufferFailureObserved: Bool
    let reportedSuccess: Bool
    let reportedFailure: Bool

    static let empty = SceneGPUCompletionTelemetrySnapshot(
        encodingFailureObserved: false,
        commandBufferSuccessObserved: false,
        commandBufferFailureObserved: false,
        reportedSuccess: false,
        reportedFailure: false
    )
}

nonisolated struct SceneGPUCompletionTelemetryReducer: Sendable {
    private var encodingFailureObserved = false
    private var commandBufferSuccessObserved = false
    private var commandBufferFailureObserved = false
    private var reportedSuccess = false
    private var reportedFailure = false

    var snapshot: SceneGPUCompletionTelemetrySnapshot {
        SceneGPUCompletionTelemetrySnapshot(
            encodingFailureObserved: encodingFailureObserved,
            commandBufferSuccessObserved: commandBufferSuccessObserved,
            commandBufferFailureObserved: commandBufferFailureObserved,
            reportedSuccess: reportedSuccess,
            reportedFailure: reportedFailure
        )
    }

    /// M2 Patch A：首次终态观测（成功或失败任一）后即停止注册
    /// completed handler。旧行为要求 success+failure 双观测才停，
    /// 健康层永不失败 → 每帧注册一个 handler（无界增长）。代价：
    /// 成功后再失败的层不再补记失败日志（sticky 首发诊断的保真度
    /// 让步，换取每层恰一次 handler 注册）。
    var needsCommandBufferObservation: Bool {
        !(commandBufferSuccessObserved || commandBufferFailureObserved)
    }

    mutating func reduce(
        _ event: SceneGPUCompletionTelemetryEvent
    ) -> SceneGPUCompletionTelemetryLogStatus? {
        switch event {
        case .encodingFailed:
            encodingFailureObserved = true
            return reportFailureOnce()
        case .commandBufferCompleted(let succeeded):
            if succeeded {
                commandBufferSuccessObserved = true
                return reportSuccessOnce()
            }
            commandBufferFailureObserved = true
            return reportFailureOnce()
        }
    }

    private mutating func reportSuccessOnce() -> SceneGPUCompletionTelemetryLogStatus? {
        guard !reportedSuccess else { return nil }
        reportedSuccess = true
        return .succeeded
    }

    private mutating func reportFailureOnce() -> SceneGPUCompletionTelemetryLogStatus? {
        guard !reportedFailure else { return nil }
        reportedFailure = true
        return .failed
    }
}

nonisolated final class SceneGPUCompletionTelemetry: @unchecked Sendable {
    private let lock = NSLock()
    private let phase: String
    private var reducers: [Int: SceneGPUCompletionTelemetryReducer] = [:]

    init(phase: String) {
        self.phase = phase
    }

    func record(layerID: Int, encoded: Bool, on commandBuffer: MTLCommandBuffer) {
        guard encoded else {
            recordFailure(layerID: layerID)
            return
        }
        let shouldObserve = withLock {
            reducers[layerID]?.needsCommandBufferObservation ?? true
        }
        guard shouldObserve else { return }
        commandBuffer.addCompletedHandler { [weak self] completed in
            self?.consume(
                layerID: layerID,
                event: .commandBufferCompleted(succeeded: completed.status == .completed)
            )
        }
    }

    func recordFailure(layerID: Int) {
        consume(layerID: layerID, event: .encodingFailed)
    }

    func snapshot(layerID: Int) -> SceneGPUCompletionTelemetrySnapshot {
        withLock {
            reducers[layerID]?.snapshot ?? .empty
        }
    }

    private func consume(layerID: Int, event: SceneGPUCompletionTelemetryEvent) {
        let status = withLock {
            var reducer = reducers[layerID] ?? SceneGPUCompletionTelemetryReducer()
            let status = reducer.reduce(event)
            reducers[layerID] = reducer
            return status
        }
        guard let status else { return }
        NSLog(
            "MWX DEBUG SCENE: phase=%@ layer=%d status=%@",
            phase,
            layerID,
            status.rawValue
        )
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
