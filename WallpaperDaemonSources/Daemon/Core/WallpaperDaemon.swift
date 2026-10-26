import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore

final class WallpaperDaemon: NSObject {
    final class HostContentView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }
    }

    enum Slot {
        case primary
        case secondary
    }

    struct VideoPreparation {
        let token: Int
        let requestID: Int?
        let videoPath: String
        let incomingSlot: Slot
        let previousSlot: Slot
        let previousVideoPath: String?
        let previousRequestID: Int?
        var previousFillMode: String
        var targetFrame: CGRect = .zero
        var isPrepared = false
        var isSeekingToStart = false
        var isCommitted = false
        var isFinalized = false
        var transitionComplete = false
        var activationID: UUID? = nil
        var cohortID: UUID? = nil
        var targetScreenFrame: CGRect? = nil
        var previousCohortID: UUID? = nil
        var visibilityConfirmed = false
    }

    let displayID: CGDirectDisplayID
    let window: NSWindow
    let fallbackLayer: CALayer
    let primaryPlayer: AVQueuePlayer
    let secondaryPlayer: AVQueuePlayer
    let primaryLayer: AVPlayerLayer
    let secondaryLayer: AVPlayerLayer
    let spectrumContainerLayer: CALayer

    var primaryLooper: AVPlayerLooper?
    var secondaryLooper: AVPlayerLooper?
    var pendingStatusObservation: NSKeyValueObservation?
    var primaryEndObservation: NSObjectProtocol?
    var secondaryEndObservation: NSObjectProtocol?
    var primaryLoopEndObservation: NSObjectProtocol?
    var secondaryLoopEndObservation: NSObjectProtocol?
    var videoPreparation: VideoPreparation?
    var pendingDisplayObservation: NSKeyValueObservation?
    var pendingDisplayFallbackWorkItem: DispatchWorkItem?
    var currentVideoPath: String?
    var currentVideoCohortID: UUID?
    var currentRequestID: Int?
    var activeSlot: Slot = .primary
    var switchToken: Int = 0
    var activationVisibilityWorkItem: DispatchWorkItem?
    var activationVisibilityDeadline: DispatchWorkItem?
    var outputActivityAllowed = true
    var lastVideoCancellation: DaemonCommand?
    var currentVolume: Float = 0.5
    var playbackRate: Float = 1.0
    var paused = false
    var currentFillMode: String = "填充屏幕"
    let crossfadeDuration: TimeInterval = 0.25
    var spectrumBarCount = 28
    var spectrumColorHex = "#F4FBFF"
    var spectrumOffsetX: CGFloat = 0
    var spectrumOffsetY: CGFloat = 0
    var spectrumPeakCapsEnabled = true
    var spectrumBaseColor = NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 1.0)
    var spectrumShadowColor = NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 0.65)
    var spectrumBarLayers: [CALayer] = []
    var spectrumPeakLayers: [CALayer] = []
    var spectrumEnabled = false
    var spectrumLevels: [Float] = Array(repeating: 0, count: 28)
    var spectrumPeakLevels: [CGFloat] = Array(repeating: 0, count: 28)
    var lastSpectrumPresentationAt: CFTimeInterval = 0
    var lastRenderedBarHeights: [CGFloat] = Array(repeating: -1, count: 28)
    var lastRenderedBarOpacities: [Float] = Array(repeating: -1, count: 28)
    var lastRenderedPeakY: [CGFloat] = Array(repeating: -1, count: 28)
    var lastRenderedPeakOpacities: [Float] = Array(repeating: -1, count: 28)

    init?(displayID: CGDirectDisplayID) {
        guard let screen = WallpaperDaemon.screen(for: displayID) else {
            daemonLog("screen not found for display \(displayID)")
            return nil
        }

        self.displayID = displayID
        self.primaryPlayer = WallpaperDaemon.makeQueuePlayer()
        self.secondaryPlayer = WallpaperDaemon.makeQueuePlayer()

        self.window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = NSWindow.Level(rawValue: WallpaperDaemon.desktopWindowLevel.rawValue - 2)
        window.backgroundColor = .black
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let contentView = HostContentView(frame: screen.frame)
        contentView.autoresizingMask = [.width, .height]
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = contentView

        self.fallbackLayer = CALayer()
        self.primaryLayer = AVPlayerLayer(player: primaryPlayer)
        self.secondaryLayer = AVPlayerLayer(player: secondaryPlayer)
        self.spectrumContainerLayer = CALayer()

        super.init()

        fallbackLayer.frame = window.contentView?.bounds ?? CGRect(origin: .zero, size: screen.frame.size)
        fallbackLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        fallbackLayer.opacity = 0
        fallbackLayer.contentsGravity = .resizeAspectFill
        window.contentView?.layer?.addSublayer(fallbackLayer)
        for layer in [primaryLayer, secondaryLayer] {
            layer.frame = window.contentView?.bounds ?? CGRect(origin: .zero, size: screen.frame.size)
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer.videoGravity = .resizeAspectFill
            layer.opacity = 0
            window.contentView?.layer?.addSublayer(layer)
        }
        setupSpectrumLayers()

        window.orderFrontRegardless()
#if DEBUG
        emit(type: "launched", requestID: nil, message: nil, videoPath: nil)
#endif

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
