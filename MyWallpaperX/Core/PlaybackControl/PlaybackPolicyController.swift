import AppKit
import CoreGraphics
import IOKit.ps

/// One macOS policy observer for every wallpaper runtime. Engines consume only
/// the effective pause command; they do not interpret settings or system events.
final class PlaybackPolicyController: NSObject {
    static let shared = PlaybackPolicyController()

    struct Settings: Equatable {
        let focused: Bool
        let fullscreen: Bool
        let battery: Bool
        let idle: Bool
        let idleMinutes: Int

        init(_ settings: WallpaperSettings) {
            focused = settings.pauseWhenOtherAppFocused
            fullscreen = settings.pauseWhenOtherAppFullscreen
            battery = settings.pauseWhenUnplugged
            idle = settings.pauseWhenIdle
            idleMinutes = settings.idleTimeoutMinutes
        }

        var idleTimeout: TimeInterval { Double(max(1, idleMinutes)) * 60 }

        func requiresPause(otherAppFocused: Bool, otherAppFullscreen: Bool,
                           onBattery: Bool, idleSeconds: TimeInterval) -> Bool {
            (focused && otherAppFocused) || (fullscreen && otherAppFullscreen)
                || (battery && onBattery)
                || (idle && idleSeconds.isFinite && idleSeconds >= idleTimeout)
        }
    }

    enum Interruption: Hashable { case screenLock, systemSleep, displaySleep }
    private var interruptions: Set<Interruption> = []
    private var settings: Settings?
    private var refreshWork: DispatchWorkItem?
    private var pollTimer: DispatchSourceTimer?
    private var powerSource: CFRunLoopSource?
    private var fullscreenSpace: Bool?

    override init() {
        super.init()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(applicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(spaceChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DistributedNotificationCenter.default.addObserver(self, selector: #selector(screenLocked), name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default.addObserver(self, selector: #selector(screenUnlocked), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    deinit {
        refreshWork?.cancel()
        pollTimer?.cancel()
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default.removeObserver(self)
    }

    func updateSettings(_ value: WallpaperSettings) {
        let next = Settings(value)
        guard settings != next else { return }
        settings = next
        fullscreenSpace = nil
        if next.battery && powerSource == nil {
            powerSource = IOPSNotificationCreateRunLoopSource({ context in
                guard let context else { return }
                Unmanaged<PlaybackPolicyController>.fromOpaque(context).takeUnretainedValue().refresh()
            }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
            if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        } else if !next.battery, let source = powerSource {
            CFRunLoopSourceInvalidate(source)
            powerSource = nil
        }
        refresh()
    }

    /// Settings and explicit playback admission can evaluate immediately. macOS
    /// activation/Space bursts are coalesced; no frame-loop policy work is needed.
    func refresh() {
        refreshWork?.cancel()
        refreshWork = nil
        guard let settings else { return }
        let idleSeconds = settings.idle
            ? CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: UInt32.max)!) : 0
        let otherAppFocused = settings.focused && isOtherApplicationFocused()
        let fullscreen = settings.fullscreen && isOtherAppFullscreenSpaceActive()
        let paused = !interruptions.isEmpty || settings.requiresPause(
            otherAppFocused: otherAppFocused, otherAppFullscreen: fullscreen,
            onBattery: settings.battery && isRunningOnBattery(), idleSeconds: idleSeconds)
        PlaybackCommandMultiplexer.shared.setSystemPaused(paused)

        // Sleep until the idle deadline. Once idle, check for resumed activity at
        // most once a second. Battery normally uses IOKit's event source.
        pollTimer?.cancel()
        pollTimer = nil
        guard interruptions.isEmpty else { return }
        var delay: TimeInterval?
        if settings.idle {
            delay = idleSeconds.isFinite && idleSeconds >= 0
                ? max(1, settings.idleTimeout - idleSeconds) : 1
        }
        if settings.battery && powerSource == nil { delay = min(delay ?? 2, 2) }
        if let delay {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + delay, leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in self?.refresh() }
            pollTimer = timer
            timer.resume()
        }
    }

    @objc private func applicationChanged() {
        guard settings?.focused == true || settings?.fullscreen == true else { return }
        scheduleRefresh(after: 0.08)
    }

    @objc private func spaceChanged() {
        guard settings?.fullscreen == true else { return }
        // Wait for the Space animation to settle instead of issuing a temporary resume.
        scheduleRefresh(after: 0.36)
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        fullscreenSpace = nil
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func setInterruption(_ reason: Interruption, active: Bool) {
        if active { interruptions.insert(reason) } else { interruptions.remove(reason) }
        fullscreenSpace = nil
        refresh()
    }

    @objc private func screenLocked() { setInterruption(.screenLock, active: true) }
    @objc private func screenUnlocked() { setInterruption(.screenLock, active: false) }
    @objc private func willSleep() { setInterruption(.systemSleep, active: true) }
    @objc private func didWake() { setInterruption(.systemSleep, active: false) }
    @objc private func screensSleep() { setInterruption(.displaySleep, active: true) }
    @objc private func screensWake() { setInterruption(.displaySleep, active: false) }

    private func isOtherApplicationFocused() -> Bool {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.activationPolicy == .regular,
              let id = application.bundleIdentifier else { return false }
        // Finder owns the desktop; system agents and this app are not foreground work.
        return id != Bundle.main.bundleIdentifier && id != "com.apple.finder"
    }

    private func isRunningOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return source as String == kIOPMBatteryPowerKey
    }

    private func isOtherAppFullscreenSpaceActive() -> Bool {
        if let fullscreenSpace { return fullscreenSpace }
        let state = isOtherAppFullscreenSpaceActiveViaSpaceAPI() ?? false
        fullscreenSpace = state
        return state
    }
    private func isOtherAppFullscreenSpaceActiveViaSpaceAPI() -> Bool? {
        // Best-effort private Space lookup.
        // If Apple changes this structure, callers should still fail safely via the nil fallback.
        let connection = CGSMainConnectionID()
        guard let displaySpaces = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            return nil
        }

        for displayInfo in displaySpaces {
            if let currentSpace = displayInfo["Current Space"] as? [String: Any],
               isFullscreenSpaceDictionary(currentSpace),
               isOtherApplicationSpace(currentSpace, display: displayInfo) {
                return true
            }

            guard let spaces = displayInfo["Spaces"] as? [[String: Any]],
                  let currentSpace = displayInfo["Current Space"] as? [String: Any],
                  let currentSpaceID = intValue(from: currentSpace["ManagedSpaceID"]) else {
                continue
            }

            guard let matchedSpace = spaces.first(where: { intValue(from: $0["ManagedSpaceID"]) == currentSpaceID }) else {
                continue
            }

            if isFullscreenSpaceDictionary(matchedSpace),
               isOtherApplicationSpace(matchedSpace, display: displayInfo) {
                return true
            }
        }

        return false
    }

    private func isOtherApplicationSpace(_ space: [String: Any], display: [String: Any]) -> Bool {
        if space["TileLayoutManager"] != nil { return true }
        if let rawWindowID = intValue(from: space["fs_wid"]),
           let windowID = CGWindowID(exactly: rawWindowID), windowID > 0,
           let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
           let owner = windows.first?[kCGWindowOwnerPID as String] as? Int {
            return owner != Int(ProcessInfo.processInfo.processIdentifier)
        }
        // Space metadata is private and fs_wid is not always available. Exclude
        // our own confirmed full-screen window on this display, not all displays
        // just because this app currently has focus. Split View may include others.
        guard space["TileLayoutManager"] == nil,
              let displayID = display["Display Identifier"] as? String else { return true }
        return !NSApp.windows.contains { window in
            guard window.styleMask.contains(.fullScreen), window.isOnActiveSpace,
                  let screen = window.screen,
                  let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return false }
            let identifier = CFUUIDCreateString(nil, uuid) as String
            return identifier == displayID || (displayID == "Main" && number == CGMainDisplayID())
        }
    }

    private func intValue(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func isFullscreenSpaceDictionary(_ space: [String: Any]) -> Bool {
        let spaceType = intValue(from: space["type"]) ?? intValue(from: space["Type"])
        if spaceType == 4 {
            return true
        }

        if space["TileLayoutManager"] != nil && space["WallSpace"] != nil {
            return true
        }

        if space["fs_wid"] != nil {
            return true
        }

        return false
    }

}
