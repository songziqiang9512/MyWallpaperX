import AppKit
import CoreGraphics
import Foundation

/// A bounded handoff observation, never a render-loop or product-commit owner.
nonisolated enum PlaybackSurfaceVisibility {
    struct Rect: Codable, Equatable, Sendable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ rect: CGRect) {
            x = rect.minX; y = rect.minY; width = rect.width; height = rect.height
        }

        var isValid: Bool {
            [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0
        }

        func matches(_ other: Rect) -> Bool {
            isValid && other.isValid
                && abs(x - other.x) <= 1 && abs(y - other.y) <= 1
                && abs(width - other.width) <= 1 && abs(height - other.height) <= 1
        }
    }

    struct Evidence: Codable, Equatable, Sendable {
        let displayID: UInt32
        let windowID: UInt32
        let expectedPID: Int32
        let expectedLevel: Int
        let displayExists: Bool
        let localFrame: Rect
        let screenFrame: Rect
        let displayFrame: Rect
        let localLevel: Int
        let localAlpha: Double
        let visible: Bool
        let miniaturized: Bool
        let onActiveSpace: Bool
        let serverPID: Int32?
        let serverFrame: Rect?
        let serverLevel: Int?
        let serverAlpha: Double?
        let onscreen: Bool?
    }

    enum Decision: Equatable {
        case confirmed
        case deferredOffSpace
        case retry(String)
    }

    static func evaluate(_ value: Evidence) -> Decision {
        guard value.displayExists else { return .retry("target-display-unavailable") }
        guard value.windowID > 0, value.expectedPID > 0,
              value.serverPID == value.expectedPID else { return .retry("window-identity-unavailable") }
        guard value.localFrame.matches(value.screenFrame),
              value.serverFrame?.matches(value.displayFrame) == true else {
            return .retry("window-target-geometry-mismatch")
        }
        guard value.localLevel == value.expectedLevel,
              value.serverLevel == value.expectedLevel else { return .retry("window-level-mismatch") }
        guard value.localAlpha.isFinite, value.localAlpha >= 0.99,
              let alpha = value.serverAlpha, alpha.isFinite, alpha >= 0.99 else {
            return .retry("window-alpha-insufficient")
        }
        guard value.visible, !value.miniaturized else { return .retry("window-not-ordered") }
        // canJoinAllSpaces is a preference, not evidence that this window is on
        // the current Space. Full-screen/Space transitions may legitimately defer it.
        guard value.onActiveSpace else { return .deferredOffSpace }
        guard value.onscreen == true else { return .retry("window-not-onscreen") }
        return .confirmed
    }

    @MainActor
    static func observe(window: NSWindow, displayID: UInt32, expectedLevel: Int) -> Evidence {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
        let number = UInt32(exactly: window.windowNumber) ?? 0
        let info = number == 0 ? nil : (CGWindowListCopyWindowInfo(.optionIncludingWindow, number)
            as? [[String: Any]])?.first {
                ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == number
            }
        let bounds = (info?[kCGWindowBounds as String] as? NSDictionary).flatMap {
            CGRect(dictionaryRepresentation: $0 as CFDictionary)
        }
        return Evidence(displayID: displayID, windowID: number, expectedPID: getpid(),
            expectedLevel: expectedLevel, displayExists: screen != nil,
            localFrame: Rect(window.frame), screenFrame: Rect(screen?.frame ?? .zero),
            displayFrame: Rect(CGDisplayBounds(displayID)), localLevel: window.level.rawValue,
            localAlpha: Double(window.alphaValue), visible: window.isVisible,
            miniaturized: window.isMiniaturized, onActiveSpace: window.isOnActiveSpace,
            serverPID: (info?[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
            serverFrame: bounds.map(Rect.init),
            serverLevel: (info?[kCGWindowLayer as String] as? NSNumber)?.intValue,
            serverAlpha: (info?[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
            onscreen: (info?[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue)
    }

    /// Keep the previous wallpaper underneath the prepared candidate, including
    /// Web (+1) -> Video (+0), without covering Finder's desktop icons.
    static func activationLevel(normal: NSWindow.Level) -> NSWindow.Level {
        let desktop = Int(CGWindowLevelForKey(.desktopWindow))
        let icons = Int(CGWindowLevelForKey(.desktopIconWindow))
        return NSWindow.Level(rawValue: max(normal.rawValue, min(desktop + 2, icons - 1)))
    }
}
