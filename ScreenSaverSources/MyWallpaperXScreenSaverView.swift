import AppKit
import AVFoundation
import Darwin
import ImageIO
import IOKit.ps
import ScreenSaver
#if DEBUG
import OSLog
#endif

/// macOS owns the window; AVFoundation owns the video clock.
@objc(MyWallpaperXScreenSaverView)
@MainActor final class MyWallpaperXScreenSaverView: ScreenSaverView {
    private let configurationRoot: URL?
    private let posterView = ScreenSaverPosterView()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let playbackView = NSView()
    private var activityClient: ScreenSaverActivityClient?
    private var configuration: ScreenSaverConfiguration?
    private var animationRequested = false
    private var displaySleeping = false
    private var systemSleeping = false
    private var requestGeneration: UInt64 = 0
    private var mediaLease: ScreenSaverMediaLease?
    private var playbackFailed = false
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playbackObservers: [NSKeyValueObservation] = []
    private var videoView: NSView?
    private var playerLayer: AVPlayerLayer?
    private var preparation: Task<Void, Never>?
    private var posterPreparation: Task<Void, Never>?
    private var notifications: [(NotificationCenter, NSObjectProtocol)] = []
    private var distributedObserver: NSObjectProtocol?
    private var powerSource: CFRunLoopSource?
#if DEBUG
    private static let lifecycleLogger = Logger(subsystem: "com.songziqiang.MyWallpaperX.ScreenSaver", category: "lifecycle")
#endif

    override init?(frame: NSRect, isPreview: Bool) {
        configurationRoot = try? ScreenSaverPaths.currentUserRoot()
        super.init(frame: frame, isPreview: isPreview)
        buildView()
    }

    required init?(coder: NSCoder) {
        configurationRoot = try? ScreenSaverPaths.currentUserRoot()
        super.init(coder: coder)
        buildView()
    }

    isolated deinit {
        removeObservers()
        activityClient?.stop()
        stopRendering()
    }

    private func buildView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        for view in [posterView, playbackView] {
            view.autoresizingMask = [.width, .height]
            view.frame = bounds
            addSubview(view)
        }
        playbackView.wantsLayer = true
        message.textColor = .secondaryLabelColor
        message.alignment = .center
        message.font = .systemFont(ofSize: 14)
        message.translatesAutoresizingMaskIntoConstraints = false
        addSubview(message)
        NSLayoutConstraint.activate([
            message.centerXAnchor.constraint(equalTo: centerXAnchor),
            message.centerYAnchor.constraint(equalTo: centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8)
        ])
        // Keep the framework lifecycle active without a second video clock.
        animationTimeInterval = 3_600
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoView?.frame = playbackView.bounds
        playerLayer?.frame = videoView?.bounds ?? playbackView.bounds
        CATransaction.commit()
    }

    override func startAnimation() {
        guard !animationRequested else { return }
        animationRequested = true
        displaySleeping = false
        systemSleeping = false
        super.startAnimation()
#if DEBUG
        debugLogState("start")
#endif
        installObservers()
        if !isPreview, let root = configurationRoot {
            let client = ScreenSaverActivityClient(root: root)
            activityClient = client
            client.start()
        }
        reloadConfiguration()
    }

    override func stopAnimation() {
#if DEBUG
        debugLogState("stop")
#endif
        animationRequested = false
        super.stopAnimation()
        removeObservers()
        activityClient?.stop()
        activityClient = nil
        stopRendering()
        configuration = nil
        posterView.image = nil
        message.stringValue = ""
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil && animationRequested { stopAnimation() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func animateOneFrame() {} // AVPlayer advances independently.

    private func reloadConfiguration() {
        guard animationRequested, let root = configurationRoot else { return }
        do {
            let file = root.appendingPathComponent("current.json")
            guard FileManager.default.fileExists(atPath: file.path) else {
                configuration = nil
                stopRendering()
                posterView.image = nil
                showMessage("请在 MyWallpaperX 中选择屏保视频")
                return
            }
            let incoming = try JSONDecoder().decode(ScreenSaverConfiguration.self, from: Data(contentsOf: file))
            guard incoming.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
            if incoming.publicationID == configuration?.publicationID, mediaLease != nil { return }
            let sameMedia = incoming.content == configuration?.content
            configuration = incoming
            if sameMedia, mediaLease != nil {
                updateFillMode()
                applyPowerPolicy()
            } else { loadContent() }
        } catch {
            if mediaLease == nil { showMessage("屏保视频暂不可用\n请在新版 MyWallpaperX 中重新选择视频") }
        }
    }

    private func loadContent() {
        stopRendering()
        posterView.image = nil
        guard animationRequested, !displaySleeping, !systemSleeping else { return }
        guard let root = configurationRoot, let content = configuration?.content else {
            showMessage("请在 MyWallpaperX 中选择屏保视频")
            return
        }
        do {
            let media = try ScreenSaverPaths.mediaRoot(in: root, generation: content.mediaGeneration)
            mediaLease = try ScreenSaverMediaLease(root: media)
            showMessage("")
            decodePoster(try ScreenSaverPaths.resource(content.posterRelativePath, in: media))
            updateFillMode()
            if canPlayVideo { beginVideo(try ScreenSaverPaths.resource(content.entryRelativePath, in: media)) }
            synchronizeAnimationState()
        } catch {
            stopRendering()
            showMessage("屏保视频暂不可用\n请在 MyWallpaperX 中重新选择")
        }
    }

    private func beginVideo(_ entry: URL) {
        guard player == nil, preparation == nil else { return }
        let generation = requestGeneration
        let lease = mediaLease
        let asset = AVURLAsset(url: entry)
        showMessage("")
        preparation = Task { [weak self] in
            defer {
                if let self, self.requestGeneration == generation { self.preparation = nil }
                withExtendedLifetime(lease) {}
            }
            do {
                let duration = try await asset.load(.duration)
                try Task.checkCancellation()
                guard let self, self.animationRequested, self.requestGeneration == generation,
                      self.canPlayVideo else { return }
                guard duration.seconds.isFinite, duration.seconds > 0 else { throw CocoaError(.fileReadCorruptFile) }
                let player = AVQueuePlayer()
                player.isMuted = true
                player.volume = 0
                player.preventsDisplaySleepDuringVideoPlayback = false
                let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
                self.looper = looper
                let layer = AVPlayerLayer(player: player)
                let view = NSView(frame: self.playbackView.bounds)
                view.autoresizingMask = [.width, .height]
                layer.frame = view.bounds
                view.layer = layer
                view.wantsLayer = true
                self.playbackView.addSubview(view)
                self.videoView = view
                self.playerLayer = layer
                self.player = player
                self.playbackObservers = [
                    player.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
                        Task { @MainActor [weak self] in self?.playbackStatusChanged(generation: generation) }
                    },
                    looper.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
                        Task { @MainActor [weak self] in self?.playbackStatusChanged(generation: generation) }
                    }
                ]
                self.updateFillMode()
                player.play()
            } catch {
                guard let self, self.requestGeneration == generation else { return }
                self.playbackFailed = true
                if self.posterView.image == nil { self.showMessage("此视频暂时无法作为屏保播放") }
            }
        }
    }

    private func playbackStatusChanged(generation: UInt64) {
        guard requestGeneration == generation,
              player?.status == .failed || looper?.status == .failed else { return }
        playbackFailed = true
        stopRendering(releaseContent: false)
        showMessage("此视频暂时无法继续播放")
    }

    private func stopRendering(releaseContent: Bool = true) {
        requestGeneration &+= 1
        preparation?.cancel()
        preparation = nil
        if releaseContent {
            posterPreparation?.cancel()
            posterPreparation = nil
            playbackFailed = false
        }
        playbackObservers.forEach { $0.invalidate() }
        playbackObservers.removeAll()
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        playerLayer?.player = nil
        playerLayer = nil
        player = nil
        videoView?.removeFromSuperview()
        videoView = nil
        if releaseContent { mediaLease = nil }
        synchronizeAnimationState()
    }

    private func updateFillMode() {
        let fit = configuration?.fillMode == "aspectFit"
        posterView.fitsContent = fit
        playerLayer?.videoGravity = fit ? .resizeAspect : .resizeAspectFill
    }

    private func decodePoster(_ url: URL) {
        let lease = mediaLease
        let pixelSize = max(bounds.width, bounds.height) * (window?.backingScaleFactor ?? 2)
        posterPreparation = Task { [weak self] in
            let image = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(1, Int(pixelSize)),
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary)
            }.value
            guard let self, !Task.isCancelled, self.mediaLease === lease else { return }
            if let image { self.posterView.image = NSImage(cgImage: image, size: .zero) }
            else if !self.canPlayVideo { self.showMessage("屏保视频封面暂不可用") }
            self.posterPreparation = nil
        }
    }

    private func showMessage(_ text: String) { message.stringValue = text }

    private var canPlayVideo: Bool {
        guard animationRequested, !playbackFailed, !displaySleeping, !systemSleeping,
              !isPreview,
              !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }
        if configuration?.playsOnBattery == true { return true }
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return true }
        return (source as String) != kIOPSBatteryPowerValue
    }

    private func applyPowerPolicy() {
#if DEBUG
        debugLogState("power-policy")
#endif
        guard let root = configurationRoot, let content = configuration?.content else { return }
        if canPlayVideo {
            if mediaLease == nil { loadContent() }
            else if let media = try? ScreenSaverPaths.mediaRoot(in: root, generation: content.mediaGeneration) {
                if let entry = try? ScreenSaverPaths.resource(content.entryRelativePath, in: media) { beginVideo(entry) }
            }
        } else { stopRendering(releaseContent: false) }
        synchronizeAnimationState()
    }

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        func observe(_ name: Notification.Name, _ body: @escaping @MainActor (MyWallpaperXScreenSaverView) -> Void) {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { body(self) } }
            }
            notifications.append((workspace, token))
        }
        observe(NSWorkspace.screensDidSleepNotification) { $0.displaySleeping = true; $0.applyPowerPolicy() }
        observe(NSWorkspace.screensDidWakeNotification) { $0.displaySleeping = false; $0.applyPowerPolicy() }
        observe(NSWorkspace.willSleepNotification) { $0.systemSleeping = true; $0.applyPowerPolicy() }
        observe(NSWorkspace.didWakeNotification) { $0.systemSleeping = false; $0.applyPowerPolicy() }
        let center = NotificationCenter.default
        let token = center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPowerPolicy() }
        }
        notifications.append((center, token))
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: ScreenSaverConfiguration.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.reloadConfiguration() } }
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            MainActor.assumeIsolated {
                guard let context else { return }
                Unmanaged<MyWallpaperXScreenSaverView>.fromOpaque(context).takeUnretainedValue().applyPowerPolicy()
            }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
    }

    private func synchronizeAnimationState() {
        let running = animationRequested && !displaySleeping && !systemSleeping
        if running {
            if !isAnimating { super.startAnimation() }
        } else if isAnimating { super.stopAnimation() }
    }

#if DEBUG
    private func debugLogState(_ phase: String) {
        Self.lifecycleLogger.notice("phase=\(phase, privacy: .public) preview=\(self.isPreview) animating=\(self.isAnimating) bounds=\(NSStringFromRect(self.bounds), privacy: .public) scale=\(self.window?.backingScaleFactor ?? 0, privacy: .public) displaySleep=\(self.displaySleeping) systemSleep=\(self.systemSleeping)")
    }
#endif

    private func removeObservers() {
        for (center, token) in notifications { center.removeObserver(token) }
        notifications.removeAll()
        if let token = distributedObserver { DistributedNotificationCenter.default().removeObserver(token) }
        distributedObserver = nil
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        powerSource = nil
    }
}

/// A lifetime lease, not playback authorization.
@MainActor final class ScreenSaverMediaLease {
    private let descriptor: Int32
    init(root: URL) throws {
        let fd = Darwin.open(root.appendingPathComponent(".lease").path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        guard flock(fd, LOCK_SH | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw CocoaError(.fileReadUnknown)
        }
        descriptor = fd
    }
    deinit { Darwin.close(descriptor) }
}

@MainActor private final class ScreenSaverPosterView: NSView {
    var image: NSImage? {
        didSet { layer?.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    }
    var fitsContent = false {
        didSet { layer?.contentsGravity = fitsContent ? .resizeAspect : .resizeAspectFill }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.contentsGravity = .resizeAspectFill
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}
