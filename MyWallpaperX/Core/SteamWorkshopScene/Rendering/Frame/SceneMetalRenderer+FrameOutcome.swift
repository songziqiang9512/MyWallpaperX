import Foundation
import Metal

extension SceneMetalRenderer {
    /// The only frame result that the host scheduler may use to advance a
    /// frame plan. A drawable may be acquired and CPU/GPU work may be prepared
    /// without producing a presented frame, so `submitted` is kept distinct
    /// from deferred and rejected work.
    enum FrameOutcome: Equatable {
        case submitted
        case prepared(PreparedFrame)
        case deferred(reasonCode: String)
        case dropped(reasonCode: String)

        var isPrepared: Bool {
            if case .prepared = self { return true }
            return false
        }

        var isSubmitted: Bool {
            if case .submitted = self { return true }
            return false
        }

        var reasonCode: String? {
            switch self {
            case .submitted, .prepared:
                return nil
            case let .deferred(reasonCode), let .dropped(reasonCode):
                return reasonCode
            }
        }

        var isDeferred: Bool {
            if case .deferred = self { return true }
            return false
        }
    }

    /// A synchronous Host-owned candidate. No buffer is enqueued until every
    /// surface has encoded and sealed. Dropping a candidate releases its exact
    /// unsubmitted resources; GPU ownership starts only in submit().
    final class PreparedFrame: Equatable {
        private var commandBuffer: MTLCommandBuffer?
        private var submitActions: (() -> Void)?
        private var cancelActions: (() -> Void)?

        init(commandBuffer: MTLCommandBuffer,
             submit: @escaping () -> Void, cancel: @escaping () -> Void) {
            self.commandBuffer = commandBuffer
            submitActions = submit
            cancelActions = cancel
        }

        static func == (lhs: PreparedFrame, rhs: PreparedFrame) -> Bool { lhs === rhs }

        var isReady: Bool { commandBuffer?.status == .notEnqueued }
        fileprivate var commandBufferIdentity: ObjectIdentifier? {
            commandBuffer.map(ObjectIdentifier.init)
        }

#if DEBUG
        private var debugObservation: (frameIndex: UInt64, surfaceID: UInt32)?
        func observeCompletion(frameIndex: UInt64, surfaceID: UInt32) {
            debugObservation = (frameIndex, surfaceID)
            NSLog("MWX DEBUG SCENE: phase=surface-submission state=prepared frame=%llu surface=%u", frameIndex, surfaceID)
        }
#endif

        fileprivate func submit() {
            precondition(isReady)
#if DEBUG
            if let observation = debugObservation, let commandBuffer {
                commandBuffer.addCompletedHandler { buffer in
                    NSLog("MWX DEBUG SCENE: phase=surface-submission state=completed frame=%llu surface=%u gpu=%@", observation.frameIndex, observation.surfaceID, buffer.status == .completed ? "completed" : "failed")
                }
            }
#endif
            let action = submitActions
            // Consume ownership before callbacks; repeated resolution is inert.
            commandBuffer = nil
            submitActions = nil
            cancelActions = nil
            action?()
        }

        func cancel() {
            guard commandBuffer != nil else { return }
            precondition(isReady, "a submitted Metal buffer cannot be rolled back")
#if DEBUG
            if let observation = debugObservation {
                NSLog("MWX DEBUG SCENE: phase=surface-submission state=cancelled frame=%llu surface=%u submitted=false", observation.frameIndex, observation.surfaceID)
            }
#endif
            let action = cancelActions
            commandBuffer = nil
            submitActions = nil
            cancelActions = nil
            action?()
        }

        deinit { cancel() }
    }

    /// Called synchronously on the frame owner thread. Preparation can fail;
    /// after preflight the submit segment contains no fallible admission work.
    static func submitPreparedFrames(_ outcomes: inout [FrameOutcome], expectedCount: Int) -> Bool {
        let candidates = outcomes.compactMap { outcome -> PreparedFrame? in
            guard case let .prepared(candidate) = outcome else { return nil }
            return candidate
        }
        guard expectedCount > 0, outcomes.count == expectedCount,
              candidates.count == outcomes.count,
              Set(candidates.compactMap(\.commandBufferIdentity)).count == candidates.count,
              candidates.allSatisfy(\.isReady) else {
            candidates.reversed().forEach { $0.cancel() }
            return false
        }
        for index in outcomes.indices {
            candidates[index].submit()
            outcomes[index] = .submitted
        }
        return true
    }

    enum ResolvedMaterialFrameAdmission {
        case ready(plans: [Int: SceneResolvedMaterialFrameTargetPlan])
        case deferred(reasonCode: String)
        case rejected(reasonCode: String)
    }
}
