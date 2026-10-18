import Foundation

nonisolated struct SceneAudioSpectrumRoutedFrame: Sendable {
    let left: [Float]
    let right: [Float]
    let left32: [Float]
    let right32: [Float]
    let left64: [Float]
    let right64: [Float]
    let captureToken: SceneAudioSpectrumCaptureToken
}


/// Control owners replace destinations; the capture worker publishes directly
/// to their bounded transports. No renderer needs an AppKit-main-thread tick.
nonisolated final class PlaybackSpectrumDelivery: @unchecked Sendable {
    struct WebTarget: Sendable {
        let requestID: UUID
        let transport: DaemonProcessTransport
    }

    struct SceneTarget: Sendable {
        let generation: UInt64
        let demand: SceneAudioSpectrumCaptureDemand
        let transport: DaemonProcessTransport
    }

    private let lock = NSLock()
    private var videoTargets: [DaemonProcessTransport] = []
    private var webTargets: [WebTarget] = []
    private var sceneTarget: SceneTarget?
    private var routing = SceneAudioSpectrumCaptureRoutingState()
    private var overlayEnabled = false
    private var webEnabled = false
    private var barCount = 28
    private var overlayLevels: [Float] = []
    private var webLevels: [Float] = []

    func setVideoTargets(_ targets: [DaemonProcessTransport]) {
        lock.lock(); defer { lock.unlock() }
        videoTargets = targets
    }

    func setWebTargets(_ targets: [WebTarget]) {
        lock.lock(); defer { lock.unlock() }
        webTargets = targets
    }

    func configure(overlay: Bool, web: Bool, barCount: Int,
                   routing: SceneAudioSpectrumCaptureRoutingState, scene: SceneTarget?) {
        lock.lock(); defer { lock.unlock() }
        // End the old stream with an ordered silence barrier before revoking
        // publication. A later capture callback must not refill paused bars.
        if overlayEnabled && !overlay {
            sendOverlay(Array(repeating: 0, count: self.barCount), required: true)
        }
        if webEnabled && !web {
            sendWeb(Array(repeating: 0, count: 128), required: true)
        }
        overlayEnabled = overlay; webEnabled = web; self.barCount = barCount
        self.routing = routing; sceneTarget = scene
        if !overlay { overlayLevels = [] }
        if !web { webLevels = [] }
    }

    var currentOverlayLevels: [Float] {
        lock.lock(); defer { lock.unlock() }
        return overlayLevels
    }

    var currentWebLevels: [Float] {
        lock.lock(); defer { lock.unlock() }
        return webLevels
    }

    func publishOverlay(_ levels: [Float]) {
        lock.lock(); defer { lock.unlock() }
        guard overlayEnabled, !levels.isEmpty, levels.allSatisfy(\.isFinite) else { return }
        overlayLevels = (0..<barCount).map {
            min(1, max(0, levels[min(levels.count - 1, $0 * levels.count / barCount)]))
        }
        sendOverlay(overlayLevels, required: false)
    }

    @discardableResult
    func publishWeb(_ levels: [Float]) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard webEnabled else { return false }
        let valid = levels.count == 128 && levels.allSatisfy(\.isFinite)
        webLevels = valid ? levels.map { max(0, $0) } : []
        let output = valid ? webLevels : Array(repeating: Float(0), count: 128)
        sendWeb(output, required: false)
        return valid
    }

    private func sendOverlay(_ levels: [Float], required: Bool) {
        guard let data = try? DaemonNewlineJSON.encodeJSONObject([
            "action": "setSpectrumLevels", "spectrumLevels": levels
        ]) else { return }
        for transport in videoTargets {
            if required { transport.sendRequired(data) }
            else { transport.sendLatest(data) }
        }
    }

    private func sendWeb(_ levels: [Float], required: Bool) {
        for target in webTargets {
            if let data = try? DaemonNewlineJSON.encode(WebDaemonEnvelope(
                requestID: target.requestID,
                payload: WebDaemonCommand.runtime(.pushAudioSpectrum(levels))
            )) {
                if required { target.transport.sendRequired(data) }
                else { target.transport.sendLatest(data) }
            }
        }
    }

    func publishScene(_ frame: SceneAudioSpectrumRoutedFrame) {
        lock.lock(); defer { lock.unlock() }
        guard routing.accepts(frame.captureToken) else { return }
        switch routing.route {
        case .none: return
        case let .local(demand):
            SceneAudioSpectrumInbox.shared.publishSystemCapture(
                left: frame.left, right: frame.right, left32: frame.left32,
                right32: frame.right32, left64: frame.left64, right64: frame.right64,
                token: .init(scopeEpoch: demand.scopeEpoch,
                             includesCurrentProcessOutput: demand.includesCurrentProcessOutput))
        case let .daemon(demand, generation):
            guard let target = sceneTarget, target.generation == generation,
                  target.demand == demand else { return }
            guard let data = try? DaemonNewlineJSON.encodeJSONObject([
                "v": 1, "cmd": "publishAudioSpectrum",
                "left": frame.left, "right": frame.right,
                "left32": frame.left32, "right32": frame.right32,
                "left64": frame.left64, "right64": frame.right64,
                "scopeEpoch": demand.scopeEpoch,
                "includesDaemonProcessOutput": demand.includesCurrentProcessOutput
            ]) else { return }
            target.transport.sendLatest(data)
        }
    }
}
