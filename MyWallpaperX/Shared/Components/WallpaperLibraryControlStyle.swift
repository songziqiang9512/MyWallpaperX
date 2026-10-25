import AppKit

/// Native shape only; action, state, default keys and source color stay with their owners.
@MainActor enum WallpaperLibraryControlStyle {
    static func capsule(_ button: NSButton, bezelStyle: NSButton.BezelStyle = .push) {
        button.bezelStyle = bezelStyle
        button.borderShape = .capsule
        button.isBordered = true
    }

    /// Sheet forms have their own native size; Header, toolbar and card bar
    /// callers keep the existing compact style above.
    static func sheetCapsule(_ button: NSButton) {
        button.controlSize = .large
        button.bezelStyle = .glass
        button.borderShape = .capsule
        button.isBordered = true
    }
}
