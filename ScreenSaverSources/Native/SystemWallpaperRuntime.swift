import AppKit
import IOKit.ps

@MainActor
final class SystemWallpaperRuntime {
    private struct Key: Hashable { let connection: UUID; let request: UUID }
    private struct Request { let surface: SystemWallpaperVideoSurface; var geometry: SystemWallpaperGeometry }
    private var contexts: [Key: Request] = [:]
    private var displays: [CGDirectDisplayID: SystemWallpaperVideoSurface] = [:]
    private(set) var media: SystemWallpaperMedia?
    private var screenSaverActive = false
    private var displaySleeping = false
    private var systemSleeping = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var distributed: [NSObjectProtocol] = []
    private var powerSource: CFRunLoopSource?
    private let activity: ScreenSaverActivityClient?
    private let configurationRoot: URL?

    init(root: URL? = nil) {
        configurationRoot = root ?? (try? ScreenSaverPaths.sharedRoot())
        activity = configurationRoot.map(ScreenSaverActivityClient.init(root:))
        observe()
        reload()
    }

    isolated deinit {
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }
        for (center, token) in observers { center.removeObserver(token) }
        for token in distributed { DistributedNotificationCenter.default().removeObserver(token) }
        for request in contexts.values { request.surface.stop() }
        activity?.stop()
    }

    func acquire(connection: UUID, request: UUID, geometry: SystemWallpaperGeometry) throws -> UInt32 {
        let surface: SystemWallpaperVideoSurface
        if !geometry.isPreview, let existing = displays[geometry.displayID] {
            surface = existing
        } else {
            surface = try SystemWallpaperVideoSurface(displayID: geometry.displayID, size: geometry.size,
                                                      scale: geometry.scale, isPreview: geometry.isPreview)
        }
        surface.resize(size: geometry.size, scale: geometry.scale)
        let key = Key(connection: connection, request: request)
        let previous = contexts.updateValue(Request(surface: surface, geometry: geometry), forKey: key)?.surface
        if !geometry.isPreview { displays[geometry.displayID] = surface }
        if let previous, previous !== surface { releaseIfUnused(previous) }
        refresh()
        CATransaction.flush()
        return surface.contextID
    }

    func invalidate(connection: UUID, request: UUID? = nil) {
        let keys = contexts.keys.filter { $0.connection == connection && (request == nil || $0.request == request) }
        let removed = keys.compactMap { contexts.removeValue(forKey: $0)?.surface }
        for surface in removed { releaseIfUnused(surface) }
        refresh()
    }

    func update(connection: UUID, request: UUID, geometry: SystemWallpaperGeometry) throws {
        let key = Key(connection: connection, request: request)
        guard let existing = contexts[key] else { return }
        // update cannot return a replacement context ID; display migration needs acquire.
        guard existing.surface.displayID == geometry.displayID else { throw CocoaError(.featureUnsupported) }
        var geometry = geometry
        geometry.isPreview = existing.surface.isPreview
        contexts[key]?.geometry = geometry
        refresh()
    }

    func reload() {
        guard let configurationRoot else { return }
        do {
            let previous = media?.configuration.publicationID
            media = try SystemWallpaperMedia.load(from: configurationRoot)
            refresh()
            if previous != media?.configuration.publicationID {
                NotificationCenter.default.post(name: ScreenSaverConfiguration.changedNotification, object: self)
            }
        }
        catch {
            // Keep the last complete atomic publication on a read failure.
#if DEBUG
            NSLog("MWX NativeWallpaper: configuration read failed %@", String(describing: error))
#endif
        }
    }

    private func releaseIfUnused(_ surface: SystemWallpaperVideoSurface) {
        guard !contexts.values.contains(where: { $0.surface === surface }) else { return }
        surface.stop()
        if displays[surface.displayID] === surface { displays.removeValue(forKey: surface.displayID) }
    }

    private var powerAllowsAnimation: Bool {
        guard !displaySleeping, !systemSleeping,
              !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }
        if media?.configuration.playsOnBattery == true { return true }
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return true }
        return (source as String) != kIOPSBatteryPowerValue
    }

    private func refresh() {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = session?["CGSSessionScreenIsLocked"] as? Bool
        var isShowingVideo = false
        for requests in Dictionary(grouping: contexts.values, by: { ObjectIdentifier($0.surface) }).values {
            let request = requests[0]
            let surface = request.surface
            let active = requests.filter { $0.geometry.isActive }
            let visible = active.first { $0.geometry.presentation == .screenSaver || $0.geometry.presentation == .locked }
                ?? active.first ?? request
            surface.resize(size: visible.geometry.size, scale: visible.geometry.scale)
            let showsVideo = surface.isPreview || (!active.isEmpty &&
                ((locked ?? active.contains { $0.geometry.presentation == .locked }) || screenSaverActive
                 || active.contains { $0.geometry.presentation == .screenSaver }))
            isShowingVideo = isShowingVideo || (showsVideo && !surface.isPreview && !active.isEmpty)
            do { try surface.apply(media, animate: showsVideo && !surface.isPreview && !active.isEmpty && powerAllowsAnimation) }
            catch { surface.suspend() }
        }
        if media != nil, isShowingVideo, !displaySleeping, !systemSleeping { activity?.start() }
        else { activity?.stop() }
    }

    private func observe() {
        let center = DistributedNotificationCenter.default()
        for (name, saverValue) in [
            ("com.apple.screenIsLocked", nil as Bool?),
            ("com.apple.screenIsUnlocked", nil),
            ("com.apple.screensaver.didstart", true),
            ("com.apple.screensaver.didstop", false)
        ] {
            distributed.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    if let saverValue { self?.screenSaverActive = saverValue }
                    self?.refresh()
                }
            })
        }
        distributed.append(center.addObserver(forName: ScreenSaverConfiguration.changedNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reload() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor (SystemWallpaperRuntime) -> Void) {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in if let self { action(self) } }
            }))
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displaySleeping = true; $0.refresh() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displaySleeping = false; $0.reload() }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.systemSleeping = true; $0.refresh() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.systemSleeping = false; $0.reload() }
        observe(.default, .NSProcessInfoPowerStateDidChange) { $0.refresh() }
        powerSource = IOPSNotificationCreateRunLoopSource({ pointer in
            MainActor.assumeIsolated {
                guard let pointer else { return }
                Unmanaged<SystemWallpaperRuntime>.fromOpaque(pointer).takeUnretainedValue().refresh()
            }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
    }
}
