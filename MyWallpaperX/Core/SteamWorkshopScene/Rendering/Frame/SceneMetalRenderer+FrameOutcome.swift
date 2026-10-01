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

    /// A synchronous candidate for one display. Dropping it releases only its
    /// unsubmitted resources; GPU ownership starts only in submit().
    final class PreparedFrame: Equatable {
        private var commandBuffer: MTLCommandBuffer?
        private var submitActions: (() -> Void)?
        private var cancelActions: (() -> Void)?
        private var completionObservers: [(Bool) -> Void] = []

        init(commandBuffer: MTLCommandBuffer,
             submit: @escaping () -> Void, cancel: @escaping () -> Void) {
            self.commandBuffer = commandBuffer
            submitActions = submit
            cancelActions = cancel
        }

        static func == (lhs: PreparedFrame, rhs: PreparedFrame) -> Bool { lhs === rhs }

        var isReady: Bool { commandBuffer?.status == .notEnqueued }

#if DEBUG
        private var debugObservation: (frameIndex: UInt64, surfaceID: UInt32)?
        func observeCompletion(frameIndex: UInt64, surfaceID: UInt32) {
            debugObservation = (frameIndex, surfaceID)
            NSLog("MWX DEBUG SCENE: phase=surface-submission state=prepared frame=%llu surface=%u", frameIndex, surfaceID)
        }
#endif

        func whenCompleted(_ completion: @escaping (Bool) -> Void) {
            completionObservers.append(completion)
        }

        fileprivate func submit() {
            precondition(isReady)
#if DEBUG
            if let observation = debugObservation, let commandBuffer {
                commandBuffer.addCompletedHandler { buffer in
                    NSLog("MWX DEBUG SCENE: phase=surface-submission state=completed frame=%llu surface=%u gpu=%@", observation.frameIndex, observation.surfaceID, buffer.status == .completed ? "completed" : "failed")
                }
            }
#endif
            let observers = completionObservers
            if !observers.isEmpty {
                commandBuffer?.addCompletedHandler { buffer in
                    let succeeded = buffer.status == .completed && buffer.error == nil
                    observers.forEach { $0(succeeded) }
                }
            }
            completionObservers = []
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
            completionObservers = []
            let action = cancelActions
            commandBuffer = nil
            submitActions = nil
            cancelActions = nil
            action?()
        }

        deinit { cancel() }
    }

    /// Each display owns its submission. Resolve it before preparing another
    /// display so a shared-source FIFO never depends on an unsubmitted peer.
    static func submitPreparedFrame(_ outcome: FrameOutcome) -> FrameOutcome {
        guard case let .prepared(candidate) = outcome else { return outcome }
        guard candidate.isReady else {
            return .dropped(reasonCode: "prepared-frame-already-resolved")
        }
        candidate.submit()
        return .submitted
    }

    enum ResolvedMaterialFrameAdmission {
        case ready(plans: [Int: SceneResolvedMaterialFrameTargetPlan])
        case deferred(reasonCode: String)
        case rejected(reasonCode: String)
    }
}
