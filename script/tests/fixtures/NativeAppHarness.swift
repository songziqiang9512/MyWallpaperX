import AppKit

/// Standard initialization for a LaunchServices-backed test App.
@MainActor func initializeNativeAppHarness() {
    if let path = ProcessInfo.processInfo.environment["MWX_NATIVE_HARNESS_PID_PATH"] {
        try! String(ProcessInfo.processInfo.processIdentifier).write(toFile: path, atomically: true, encoding: .utf8)
    }
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    application.finishLaunching()
}
