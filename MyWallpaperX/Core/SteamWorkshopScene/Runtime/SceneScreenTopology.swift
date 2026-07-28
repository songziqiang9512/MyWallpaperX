import AppKit
import CoreGraphics

struct SceneScreenTopology: Equatable {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let backingScaleFactor: CGFloat

    static func capture(screens: [NSScreen] = NSScreen.screens) -> [Self] {
        screens.compactMap { screen in
            guard let displayID = (
                screen.deviceDescription[
                    NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
                ] as? NSNumber
            )?.uint32Value else {
                return nil
            }
            return Self(
                displayID: displayID,
                frame: screen.frame,
                backingScaleFactor: screen.backingScaleFactor
            )
        }.sorted { $0.displayID < $1.displayID }
    }
}
