import Foundation
import QuartzCore

/// Exact first-present identity for one accepted Scene launch request.
/// The drawable callback is the committing observation; frame submission is
/// deliberately insufficient for this event.
nonisolated struct SceneFramePresentation: Equatable, Sendable {
    let requestID: UUID
    let recordID: String?
    let uptimeMicros: UInt64
}

extension Notification.Name {
    static let sceneWallpaperFirstFrameDidPresent = Notification.Name(
        "SceneWallpaperFirstFrameDidPresent"
    )
}

/// Shared by every surface created for one request. Surface rendering remains
/// main-thread-owned, so only the immutable callback crosses to Metal's
/// presentation completion thread.
final class SceneFirstFramePresentationRegistration {
    private let requestID: UUID
    private let recordID: String?
    private var isArmed = false

    init(requestID: UUID, recordID: String?) {
        self.requestID = requestID
        self.recordID = recordID
    }

    @discardableResult
    func arm(on drawable: CAMetalDrawable) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isArmed else { return false }
        isArmed = true
        let requestID = requestID
        let recordID = recordID
        drawable.addPresentedHandler { _ in
            let uptimeMicros = UInt64(
                ProcessInfo.processInfo.systemUptime * 1_000_000
            )
            let presentation = SceneFramePresentation(
                requestID: requestID,
                recordID: recordID,
                uptimeMicros: uptimeMicros
            )
            // The Core Animation presentation callback can run while holding
            // CAMetalLayer bookkeeping locks. A synchronous notification to a
            // main-queue observer can then deadlock against the nextDrawable
            // call on the main thread. Leave the callback before publication.
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .sceneWallpaperFirstFrameDidPresent,
                    object: presentation
                )
            }
        }
        return true
    }
}
