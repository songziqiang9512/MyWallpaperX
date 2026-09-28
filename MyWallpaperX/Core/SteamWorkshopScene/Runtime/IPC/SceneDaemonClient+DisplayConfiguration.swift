import AppKit
import CoreGraphics
import Foundation

@MainActor
extension SceneDaemonClient {
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
        displayConfiguration = configuration
        if endpointReady { sendDisplayConfiguration() }
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
