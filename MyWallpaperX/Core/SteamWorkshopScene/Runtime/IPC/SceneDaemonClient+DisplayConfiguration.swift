import AppKit
import CoreGraphics
import Foundation

@MainActor
extension SceneDaemonClient {
    func updatePresentation(_ presentation: ScenePlaybackPresentation, recordID: String) {
        var requests: Set<UUID> = []
        if activeIntent?.recordID == recordID {
            activeIntent?.presentation = presentation
            if let activeRequestID { requests.insert(activeRequestID) }
        }
        if pendingIntent?.recordID == recordID {
            pendingIntent?.presentation = presentation
            if let pendingRequestID { requests.insert(pendingRequestID) }
        }
        if queuedSwitchPreparation?.request.recordID == recordID {
            queuedSwitchPreparation?.request.presentation = presentation
        }
        if committedSwitchRecovery?.request.recordID == recordID {
            committedSwitchRecovery?.request.presentation = presentation
        }
        for revision in Array(pendingTextureUpdates.keys)
        where pendingTextureUpdates[revision]?.fallbackBaseIntent?.recordID == recordID {
            pendingTextureUpdates[revision]?.fallbackBaseIntent?.presentation = presentation
        }
        guard endpointReady else { return }
        for requestID in requests {
            send(["v": SceneDaemonProtocol.version, "cmd": "setPresentation",
                  "requestID": requestID.uuidString,
                  "presentation": SceneDaemonProtocol.presentationObject(presentation)])
        }
    }

    func setCanvasFit(_ fits: Bool) {
        fitsCanvas = fits
        if endpointReady {
            send(["v": SceneDaemonProtocol.version, "cmd": "setCanvasFit", "fits": fits])
        }
    }

    func setMultiDisplayEnabled(_ enabled: Bool) {
        updateDisplayConfiguration(multiDisplayEnabled: enabled)
    }

    func updateDisplayConfiguration(multiDisplayEnabled: Bool) {
        self.multiDisplayEnabled = multiDisplayEnabled
        let screens = multiDisplayEnabled
            ? NSScreen.screens
            : Array(NSScreen.screens.prefix(1))
        let configuration = SceneScreenTopology.capture(screens: screens)
        guard !configuration.isEmpty,
              configuration != displayConfiguration else { return }
        if pendingSwitchExecution?.presented == true {
            // The product already accepted this output. Finish its retirement
            // barrier before topology is allowed to revoke its native cohort.
            deferredDisplayConfigurationUpdate = true
            return
        }
        let pending = pendingIntent
        let ticket = pendingSwitchTicket
        let lifetime = pendingResourceLifetime?.lifetime
        // Host topology changes revoke its prepared cohort. Revoke the same
        // parent identity before an already queued presentation can commit it.
        cancelPreparationForRuntimeSwitch()
        displayConfiguration = configuration
        if endpointReady { sendDisplayConfiguration() }
        if let pending, let ticket {
            // The old cohort's proof is revoked. Reprepare the same product
            // selection with a new wire identity; it is not another user intent.
            prepareSwitch(pending, ticket: ticket, resourceLifetime: lifetime)
        }
    }

    func flushDeferredDisplayConfigurationUpdate() {
        guard deferredDisplayConfigurationUpdate,
              pendingSwitchExecution?.presented != true else { return }
        deferredDisplayConfigurationUpdate = false
        updateDisplayConfiguration(multiDisplayEnabled: multiDisplayEnabled)
    }

    func sendDisplayConfiguration() {
        guard !displayConfiguration.isEmpty else { return }
        send([
            "v": SceneDaemonProtocol.version,
            "cmd": "setDisplayConfiguration",
            "screens": displayConfiguration.map { screen -> [String: Any] in
                [
                    "id": screen.displayID,
                    "frame": [
                        "x": screen.frame.origin.x,
                        "y": screen.frame.origin.y,
                        "width": screen.frame.width,
                        "height": screen.frame.height
                    ],
                    "scale": screen.backingScaleFactor
                ]
            }
        ])
    }
}
