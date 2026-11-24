import AppKit
import CoreGraphics

nonisolated struct SceneScreenTopology: Equatable, Sendable {
    static let conservativeCadenceLimit: Double = 60

    let displayID: CGDirectDisplayID
    let frame: CGRect
    let backingScaleFactor: CGFloat
    let modeRefreshRate: Double?
    let unknownModeRefreshLimit: Double?

    init(displayID: CGDirectDisplayID, frame: CGRect, backingScaleFactor: CGFloat,
         modeRefreshRate: Double? = nil, unknownModeRefreshLimit: Double? = nil) {
        self.displayID = displayID
        self.frame = frame
        self.backingScaleFactor = backingScaleFactor
        self.modeRefreshRate = modeRefreshRate
        self.unknownModeRefreshLimit = unknownModeRefreshLimit
    }

    static func hasSameGeometry(_ lhs: [Self], _ rhs: [Self]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { left, right in
            left.displayID == right.displayID && left.frame == right.frame
                && left.backingScaleFactor == right.backingScaleFactor
        }
    }

    static func cadenceLimit(for screens: [Self]) -> Double {
        if let rate = screens.first?.modeRefreshRate,
           screens.allSatisfy({ $0.modeRefreshRate == rate }) {
            return rate
        }
        return screens.reduce(conservativeCadenceLimit) { limit, screen in
            min(limit, screen.modeRefreshRate ?? screen.unknownModeRefreshLimit ?? conservativeCadenceLimit)
        }
    }

    static func capture(screens: [NSScreen] = NSScreen.screens) -> [Self] {
        screens.compactMap { screen in
            guard let displayID = (
                screen.deviceDescription[
                    NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
                ] as? NSNumber
            )?.uint32Value else {
                return nil
            }
            let rate = CGDisplayCopyDisplayMode(displayID)?.refreshRate
            let modeRate = rate.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            let maximum = modeRate == nil ? Double(screen.maximumFramesPerSecond) : 0
            return Self(
                displayID: displayID,
                frame: screen.frame,
                backingScaleFactor: screen.backingScaleFactor,
                modeRefreshRate: modeRate,
                unknownModeRefreshLimit: maximum > 0 && maximum < conservativeCadenceLimit ? maximum : nil
            )
        }.sorted { $0.displayID < $1.displayID }
    }
}
