import Foundation
@preconcurrency import Metal

nonisolated final class SceneGPUCompletionTelemetry: @unchecked Sendable {
    private enum Status {
        case pending
        case failed
        case succeeded
    }

    private let lock = NSLock()
    private let phase: String
    private var statuses: [Int: Status] = [:]
    private var reportedFailures: Set<Int> = []

    init(phase: String) {
        self.phase = phase
    }

    func record(layerID: Int, encoded: Bool, on commandBuffer: MTLCommandBuffer) {
        guard encoded else {
            recordFailure(layerID: layerID)
            return
        }
        let shouldObserve = withLock {
            guard statuses[layerID] != .pending, statuses[layerID] != .succeeded else { return false }
            statuses[layerID] = .pending
            return true
        }
        guard shouldObserve else { return }
        commandBuffer.addCompletedHandler { [weak self] completed in
            self?.complete(layerID: layerID, succeeded: completed.status == .completed)
        }
    }

    func recordFailure(layerID: Int) {
        complete(layerID: layerID, succeeded: false)
    }

    private func complete(layerID: Int, succeeded: Bool) {
        let shouldReport = withLock {
            if succeeded {
                guard statuses[layerID] != .succeeded else { return false }
                statuses[layerID] = .succeeded
                return true
            }
            statuses[layerID] = .failed
            return reportedFailures.insert(layerID).inserted
        }
        guard shouldReport else { return }
        NSLog(
            "MWX DEBUG SCENE: phase=%@ layer=%d status=%@",
            phase,
            layerID,
            succeeded ? "succeeded" : "failed"
        )
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
