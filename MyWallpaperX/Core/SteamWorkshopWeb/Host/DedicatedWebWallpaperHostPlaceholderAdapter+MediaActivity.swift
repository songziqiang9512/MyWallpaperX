import AppKit
import Foundation
import WebKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func mediaPlaybackGate(for webView: WKWebView) -> WebMediaPlaybackGate? {
        surfaces.values.first { $0.webView === webView }?.mediaPlaybackGate
    }

    func advanceNavigationGeneration() -> UInt64 {
        navigationGeneration &+= 1
        return navigationGeneration
    }

    func invalidatePresentation(on surface: HostSurface) {
        surface.mediaPlaybackGate.resetForNavigation()
        presentationInvalidationHandler?()
    }

    var presentationSurfaceIdentities: [WebDaemonSurfaceIdentity] {
        surfaces.values.map { surface in
            .init(displayID: surface.screenID, surfaceID: surface.id,
                  navigationGeneration: navigationOwnershipByScreen[surface.screenID]?.generation ?? 0,
                  windowID: UInt32(exactly: surface.window.windowNumber) ?? 0)
        }.sorted { $0.displayID < $1.displayID }
    }

    /// Activity is an execution grant. It does not overwrite the user's paused,
    /// volume or playback-rate policy, nor hide the retained wallpaper picture.
    func setOutputActivity(_ active: Bool, completion: @escaping (Bool) -> Void) {
        outputActivityRevision &+= 1
        outputActivityAllowed = active
        requiresMediaSuspension = !active
        if active { startSyntheticInputForwardingIfNeeded() }
        else {
            resetTransientMouseCaptureState()
            stopGlobalMouseForwarding()
            for surface in surfaces.values { setTransientMouseCaptureEnabled(false, for: surface) }
        }
        for surface in surfaces.values { applyVolume(currentVolume, to: surface.webView) }
        awaitNativeMediaPolicy(completion: completion)
    }

    func awaitNativeMediaPolicy(completion: @escaping (Bool) -> Void) {
        let identity = presentationSurfaceIdentities
        let revision = outputActivityRevision
        let suspended = effectiveMediaSuspended
        let targets = Array(surfaces.values)
        guard !targets.isEmpty else { completion(false); return }
        var remaining = targets.count
        var succeeded = true
        for surface in targets {
            surface.mediaPlaybackGate.setSuspended(suspended) { [weak self] accepted in
                guard let self else { return }
                succeeded = succeeded && accepted && self.outputActivityRevision == revision
                    && self.effectiveMediaSuspended == suspended
                    && self.presentationSurfaceIdentities == identity
                remaining -= 1
                if remaining == 0 { completion(succeeded) }
            }
        }
    }
}
