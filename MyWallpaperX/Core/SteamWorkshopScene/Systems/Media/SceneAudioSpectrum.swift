//
//  SceneAudioSpectrum.swift
//  MyWallpaperX
//

import Foundation
import os.lock

/// 一帧 Scene 音频频谱快照。
///
/// 官方 stock shader（`pulse.vert` / `shake.vert`）使用 16 档；Workshop shader
/// 还会明确声明 32/64 档。当前宿主同时承载三档、左右分离、由低到高、取正值。
///
/// 频段边界、幅度归一化与平滑策略官方均未公开，当前实现是工程选择而非官方合同，
/// 不能据此宣称与 Wallpaper Engine 数值等价。该唯一快照也发布给通用
/// SceneScript `registerAudioBuffers` 的 16/32/64 档 retained arrays；object
/// scale 与 particle-rate QuickJS owners 复用同一份 typed snapshot。
nonisolated struct SceneAudioSpectrumSnapshot: Equatable {
    static let bandCount = 16
    static let mediumBandCount = 32
    static let extendedBandCount = 64

    /// 左声道频段能量，索引 0 为最低频。
    let left: [Float]
    /// 右声道频段能量，索引 0 为最低频。
    let right: [Float]
    /// Workshop shader 的 32 档左声道频段能量。
    let left32: [Float]
    /// Workshop shader 的 32 档右声道频段能量。
    let right32: [Float]
    /// Workshop shader 与 SceneScript AudioBuffers 的 64 档左声道能量。
    let left64: [Float]
    /// Workshop shader 与受限 native property-script plan 的 64 档右声道能量。
    let right64: [Float]
    /// 每次发布递增；相同内容也会递增，用于区分「同一帧重复读取」与「新采样」。
    let generation: UInt64

    /// 采集不可用、静音或尚未产生数据时的稳定零输入。
    static let silent = SceneAudioSpectrumSnapshot(
        left: Array(repeating: 0, count: bandCount),
        right: Array(repeating: 0, count: bandCount),
        left32: Array(repeating: 0, count: mediumBandCount),
        right32: Array(repeating: 0, count: mediumBandCount),
        left64: Array(repeating: 0, count: extendedBandCount),
        right64: Array(repeating: 0, count: extendedBandCount),
        generation: 0
    )

    /// 全零判定。采集失败与真实静音在数值上等价，都必须是稳定零而不是假波形。
    nonisolated var isSilent: Bool {
        left.allSatisfy { $0 == 0 } && right.allSatisfy { $0 == 0 }
            && left32.allSatisfy { $0 == 0 } && right32.allSatisfy { $0 == 0 }
            && left64.allSatisfy { $0 == 0 } && right64.allSatisfy { $0 == 0 }
    }

    nonisolated init(left: [Float], right: [Float], generation: UInt64) {
        self.init(
            left: left,
            right: right,
            left32: Array(repeating: 0, count: Self.mediumBandCount),
            right32: Array(repeating: 0, count: Self.mediumBandCount),
            left64: Array(repeating: 0, count: Self.extendedBandCount),
            right64: Array(repeating: 0, count: Self.extendedBandCount),
            generation: generation
        )
    }

    nonisolated init(
        left: [Float],
        right: [Float],
        left32: [Float] = [],
        right32: [Float] = [],
        left64: [Float],
        right64: [Float],
        generation: UInt64
    ) {
        self.left = Self.sanitized(left, count: Self.bandCount)
        self.right = Self.sanitized(right, count: Self.bandCount)
        self.left32 = Self.sanitized(left32, count: Self.mediumBandCount)
        self.right32 = Self.sanitized(right32, count: Self.mediumBandCount)
        self.left64 = Self.sanitized(left64, count: Self.extendedBandCount)
        self.right64 = Self.sanitized(right64, count: Self.extendedBandCount)
        self.generation = generation
    }

    /// 长度不符或含非有限值一律退化为零，避免把坏数据送进 simulation 或 shader。
    private nonisolated static func sanitized(_ values: [Float], count: Int) -> [Float] {
        guard values.count == count else {
            return Array(repeating: 0, count: count)
        }
        return values.map { value in
            guard value.isFinite, value > 0 else { return 0 }
            return value
        }
    }
}

/// Atomic capture policy published by the active Scene runtime.
///
/// Sound playback is an input source, not a spectrum consumer. Including the
/// current process is therefore normalized to false unless a real Program, VM,
/// or particle consumer also requires the shared spectrum producer.
nonisolated struct SceneAudioSpectrumCaptureDemand: Equatable, Sendable {
    static let none = SceneAudioSpectrumCaptureDemand(
        requiresSpectrum: false,
        includesCurrentProcessOutput: false,
        scopeEpoch: 0
    )

    let requiresSpectrum: Bool
    let includesCurrentProcessOutput: Bool
    let scopeEpoch: UInt64

    nonisolated init(
        requiresSpectrum: Bool,
        includesCurrentProcessOutput: Bool,
        scopeEpoch: UInt64 = 0
    ) {
        self.requiresSpectrum = requiresSpectrum
        self.includesCurrentProcessOutput = requiresSpectrum
            && includesCurrentProcessOutput
        self.scopeEpoch = scopeEpoch
    }
}

/// Runtime-wide publication policy for system-audio spectrum frames.
///
/// Author demand remains independent from this setting. The daemon keeps the
/// demand so turning the setting back on can resume the existing consumer, but
/// it must reject frames while the public setting is disabled.
nonisolated struct SceneAudioSpectrumPublicationGate: Equatable, Sendable {
    private(set) var enabled = false

    mutating func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    var allowsPublication: Bool {
        enabled
    }
}

/// Immutable identity of the process set applied to one system-tap resource.
/// It travels with captured bands so a retiring tap cannot publish into a newer
/// requested scope, including a rapid exclude -> include -> exclude transition.
nonisolated struct SceneAudioSpectrumCaptureToken: Equatable, Sendable {
    let scopeEpoch: UInt64
    let includesCurrentProcessOutput: Bool
}

/// One bounded latest-only handoff. Producers can submit while the consumer
/// queue is blocked without accumulating one closure/value pair per frame.
final class LatestValueHandoff<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var latestValue: Value?
    private var drainScheduled = false

    func submit(_ value: Value, scheduleDrain: () -> Void) {
        lock.lock()
        latestValue = value
        let shouldSchedule = !drainScheduled
        drainScheduled = true
        lock.unlock()
        if shouldSchedule { scheduleDrain() }
    }

    func takeLatest() -> Value? {
        lock.lock()
        let value = latestValue
        latestValue = nil
        drainScheduled = false
        lock.unlock()
        return value
    }

    /// The already scheduled drain retains the single wakeup and may consume a
    /// newer value submitted after this invalidation.
    func discardPendingValue() {
        lock.lock()
        latestValue = nil
        lock.unlock()
    }
}

/// One mutually exclusive destination for the App-owned system capture.
nonisolated enum SceneAudioSpectrumCaptureRoute: Equatable, Sendable {
    case none
    case local(SceneAudioSpectrumCaptureDemand)
    case daemon(SceneAudioSpectrumCaptureDemand, generation: UInt64)

    /// This is the process running the system tap, not necessarily the process
    /// that owns the target inbox.
    var includesCaptureProcessOutput: Bool {
        switch self {
        case .none, .daemon: false
        case let .local(demand): demand.includesCurrentProcessOutput
        }
    }
}

/// Pure routing state for the single capture producer. Route changes receive an
/// App-owned epoch so callbacks from a retiring tap cannot publish into a new
/// local/daemon target even when daemon-local scope values coincide.
nonisolated struct SceneAudioSpectrumCaptureRoutingState: Equatable, Sendable {
    private(set) var route = SceneAudioSpectrumCaptureRoute.none
    private(set) var scopeEpoch: UInt64 = 0
    private var nextScopeEpoch: UInt64 = 1

    static func resolvedRoute(
        captureAllowed: Bool,
        debugFixtureOwnsInbox: Bool,
        localDemand: SceneAudioSpectrumCaptureDemand,
        daemonDemand: SceneAudioSpectrumCaptureDemand,
        daemonGeneration: UInt64?
    ) -> SceneAudioSpectrumCaptureRoute {
        guard captureAllowed, !debugFixtureOwnsInbox else { return .none }
        if daemonDemand.requiresSpectrum, let daemonGeneration {
            return .daemon(daemonDemand, generation: daemonGeneration)
        }
        if localDemand.requiresSpectrum {
            return .local(localDemand)
        }
        return .none
    }

    @discardableResult
    mutating func update(route requestedRoute: SceneAudioSpectrumCaptureRoute) -> Bool {
        guard route != requestedRoute else { return false }
        route = requestedRoute
        scopeEpoch = nextScopeEpoch
        nextScopeEpoch &+= 1
        return true
    }

    func accepts(_ token: SceneAudioSpectrumCaptureToken) -> Bool {
        route != .none
            && token.scopeEpoch == scopeEpoch
            && token.includesCurrentProcessOutput
                == route.includesCaptureProcessOutput
    }
}

/// 采集线程与渲染线程之间的单一交汇点。
///
/// 采集在 `SystemAudioSpectrumService` 的串行队列上产生快照，Scene 渲染在主线程读取。
/// 这里只保留「最近一帧」：Scene 消费者按渲染帧采样，不需要历史队列，
/// 掉帧时读到同一份快照而不是积压的旧数据。
final class SceneAudioSpectrumInbox: @unchecked Sendable {
    static let shared = SceneAudioSpectrumInbox()

    /// A frame-local read of the shared inbox.  When a producer has stopped
    /// publishing, the consumer may need a silent candidate, but the
    /// generation/last-publication transition must not become visible until
    /// the host submission barrier succeeds.
    nonisolated struct FrameSnapshot: Sendable {
        let snapshot: SceneAudioSpectrumSnapshot
        let sourceGeneration: UInt64
        fileprivate let sourcePublishedAtUptime: TimeInterval?
        let expiresStalePublication: Bool
    }

    /// At the expected 30 Hz producer cadence this permits eight missed
    /// publications. A stopped tap therefore becomes silence before a frozen
    /// spectrum can read as an authored static wave, without inventing motion.
    private static let maximumSnapshotAge: TimeInterval = 8.0 / 30.0

    private var lock = os_unfair_lock_s()
    private var snapshot = SceneAudioSpectrumSnapshot.silent
    private var nextGeneration: UInt64 = 1
    private var nextCaptureScopeEpoch: UInt64 = 1
    private var publishedAtUptime: TimeInterval?
    private var demand = SceneAudioSpectrumCaptureDemand.none
    private var demandObserver: ((SceneAudioSpectrumCaptureDemand) -> Void)?
    private var hasLoggedNonSilentPublication = false
    private let uptime: @Sendable () -> TimeInterval

    init(
        uptime: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.uptime = uptime
    }

    /// 是否有 Scene 消费者需要频谱。没有消费者时不应请求采集。
    var isDemanded: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return demand.requiresSpectrum
    }

    /// Whether the active Scene needs its own admitted Sound playback to enter
    /// the same system-audio producer. This is meaningful only while demanded.
    var requiresCurrentProcessAudioCapture: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return demand.includesCurrentProcessOutput
    }

    /// One lock acquisition returns both the consumer bit and source scope, so
    /// capture coordination cannot observe a mixed old/new policy.
    var captureDemand: SceneAudioSpectrumCaptureDemand {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return demand
    }

    /// 当前最近一帧快照。无数据时返回稳定零输入。
    func latest() -> SceneAudioSpectrumSnapshot {
        let frame = prepareFrame()
        commitFrame(frame)
        return frame.snapshot
    }

    /// Reads the current snapshot and, when it is stale, returns a silent
    /// candidate without mutating the shared publication.  The caller must
    /// commit the candidate only after its frame crosses the host barrier.
    func prepareFrame() -> FrameSnapshot {
        let now = uptime()
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        let expiresStalePublication: Bool
        if let publishedAtUptime,
           now >= publishedAtUptime,
           now - publishedAtUptime >= Self.maximumSnapshotAge {
            expiresStalePublication = !snapshot.isSilent
        } else {
            expiresStalePublication = false
        }
        let candidate = expiresStalePublication
            ? SceneAudioSpectrumSnapshot(
                left: SceneAudioSpectrumSnapshot.silent.left,
                right: SceneAudioSpectrumSnapshot.silent.right,
                left32: SceneAudioSpectrumSnapshot.silent.left32,
                right32: SceneAudioSpectrumSnapshot.silent.right32,
                left64: SceneAudioSpectrumSnapshot.silent.left64,
                right64: SceneAudioSpectrumSnapshot.silent.right64,
                generation: nextGeneration
            )
            : snapshot
        return FrameSnapshot(
            snapshot: candidate,
            sourceGeneration: snapshot.generation,
            sourcePublishedAtUptime: publishedAtUptime,
            expiresStalePublication: expiresStalePublication
        )
    }

    /// Publishes a prepared stale-to-silent transition only when the source
    /// observed by `prepareFrame` is still current.  A concurrent producer
    /// publication therefore wins and is never overwritten by a late frame
    /// commit.
    func commitFrame(_ frame: FrameSnapshot) {
        guard frame.expiresStalePublication else { return }
        os_unfair_lock_lock(&lock)
        guard snapshot.generation == frame.sourceGeneration,
              publishedAtUptime == frame.sourcePublishedAtUptime,
              !snapshot.isSilent else {
            os_unfair_lock_unlock(&lock)
            return
        }
        snapshot = SceneAudioSpectrumSnapshot(
            left: SceneAudioSpectrumSnapshot.silent.left,
            right: SceneAudioSpectrumSnapshot.silent.right,
            left32: SceneAudioSpectrumSnapshot.silent.left32,
            right32: SceneAudioSpectrumSnapshot.silent.right32,
            left64: SceneAudioSpectrumSnapshot.silent.left64,
            right64: SceneAudioSpectrumSnapshot.silent.right64,
            generation: nextGeneration
        )
        nextGeneration &+= 1
        publishedAtUptime = nil
        os_unfair_lock_unlock(&lock)
    }

    /// 由采集侧发布一帧。长度或数值非法时 `SceneAudioSpectrumSnapshot` 会归零。
    func publish(left: [Float], right: [Float]) {
        publish(
            left: left,
            right: right,
            left32: Array(repeating: 0, count: SceneAudioSpectrumSnapshot.mediumBandCount),
            right32: Array(repeating: 0, count: SceneAudioSpectrumSnapshot.mediumBandCount),
            left64: Array(repeating: 0, count: SceneAudioSpectrumSnapshot.extendedBandCount),
            right64: Array(repeating: 0, count: SceneAudioSpectrumSnapshot.extendedBandCount)
        )
    }

    func publish(left: [Float], right: [Float], left64: [Float], right64: [Float]) {
        publish(
            left: left,
            right: right,
            left32: Array(repeating: 0, count: SceneAudioSpectrumSnapshot.mediumBandCount),
            right32: Array(repeating: 0, count: SceneAudioSpectrumSnapshot.mediumBandCount),
            left64: left64,
            right64: right64
        )
    }

    func publish(
        left: [Float],
        right: [Float],
        left32: [Float],
        right32: [Float],
        left64: [Float],
        right64: [Float]
    ) {
        publish(
            left: left,
            right: right,
            left32: left32,
            right32: right32,
            left64: left64,
            right64: right64,
            requiredCaptureToken: nil
        )
    }

    /// Publishes one frame from the shared system tap only when its captured
    /// process set still matches the active Scene demand. A demand transition
    /// therefore rejects callbacks from the retiring tap before its async stop
    /// has completed, rather than relabeling an old-source frame as new input.
    @discardableResult
    func publishSystemCapture(
        left: [Float],
        right: [Float],
        left32: [Float],
        right32: [Float],
        left64: [Float],
        right64: [Float],
        token: SceneAudioSpectrumCaptureToken
    ) -> Bool {
        publish(
            left: left,
            right: right,
            left32: left32,
            right32: right32,
            left64: left64,
            right64: right64,
            requiredCaptureToken: token
        )
    }

    @discardableResult
    private func publish(
        left: [Float],
        right: [Float],
        left32: [Float],
        right32: [Float],
        left64: [Float],
        right64: [Float],
        requiredCaptureToken: SceneAudioSpectrumCaptureToken?
    ) -> Bool {
        os_unfair_lock_lock(&lock)
        if let requiredCaptureToken,
           (!demand.requiresSpectrum
            || demand.scopeEpoch != requiredCaptureToken.scopeEpoch
            || demand.includesCurrentProcessOutput
                != requiredCaptureToken.includesCurrentProcessOutput) {
            os_unfair_lock_unlock(&lock)
            return false
        }
        let generation = nextGeneration
        nextGeneration &+= 1
        let publishedSnapshot = SceneAudioSpectrumSnapshot(
            left: left,
            right: right,
            left32: left32,
            right32: right32,
            left64: left64,
            right64: right64,
            generation: generation
        )
        snapshot = publishedSnapshot
        publishedAtUptime = uptime()
        let shouldLogPublication = demand.requiresSpectrum
            && !publishedSnapshot.isSilent
            && !hasLoggedNonSilentPublication
        if shouldLogPublication {
            hasLoggedNonSilentPublication = true
        }
        let includesCurrentProcessOutput = demand.includesCurrentProcessOutput
        let captureScopeEpoch = demand.scopeEpoch
        os_unfair_lock_unlock(&lock)
        if shouldLogPublication {
            let peak = (publishedSnapshot.left64 + publishedSnapshot.right64).max() ?? 0
            NSLog(
                "MWX Scene audio inbox: generation=%llu scopeEpoch=%llu peak=%.6f includeCurrentProcess=%@",
                generation,
                captureScopeEpoch,
                peak,
                includesCurrentProcessOutput ? "true" : "false"
            )
        }
        return true
    }

    /// 声明/撤销 Scene 侧的采集需求。
    ///
    /// 当前没有任何 Scene 消费者，产品路径不会自动开启；接入第一个 effect 或
    /// particle consumer 时才由该 consumer 的存在驱动。撤销时立即归零，
    /// 避免停止采集后残留最后一帧非零数据。
    func setDemand(_ demanded: Bool) {
        setDemand(demanded, requiresCurrentProcessAudioCapture: false)
    }

    /// Atomically updates Scene demand and the capture scope needed by that
    /// demand. Every capture-lifecycle transition gets a fresh scope epoch,
    /// including stop -> start with the same process-inclusion policy, so a
    /// delayed callback from a retired tap cannot publish into the new demand.
    func setDemand(
        _ demanded: Bool,
        requiresCurrentProcessAudioCapture: Bool
    ) {
        os_unfair_lock_lock(&lock)
        let requestedIncludesCurrentProcessOutput = demanded
            && requiresCurrentProcessAudioCapture
        let captureLifecycleChanged = demand.requiresSpectrum != demanded
            || demand.includesCurrentProcessOutput
                != requestedIncludesCurrentProcessOutput
        let requestedScopeEpoch: UInt64
        if captureLifecycleChanged {
            requestedScopeEpoch = nextCaptureScopeEpoch
            nextCaptureScopeEpoch &+= 1
        } else {
            requestedScopeEpoch = demand.scopeEpoch
        }
        let requestedDemand = SceneAudioSpectrumCaptureDemand(
            requiresSpectrum: demanded,
            includesCurrentProcessOutput: requestedIncludesCurrentProcessOutput,
            scopeEpoch: requestedScopeEpoch
        )
        guard demand != requestedDemand else {
            os_unfair_lock_unlock(&lock)
            return
        }
        demand = requestedDemand
        if !requestedDemand.requiresSpectrum || captureLifecycleChanged {
            snapshot = .silent
            publishedAtUptime = nil
            hasLoggedNonSilentPublication = false
        }
        let observer = demandObserver
        os_unfair_lock_unlock(&lock)
        observer?(requestedDemand)
    }

    /// 由播放引擎注册，用于在需求变化时重新协调采集状态。
    func setDemandObserver(
        _ observer: ((SceneAudioSpectrumCaptureDemand) -> Void)?
    ) {
        os_unfair_lock_lock(&lock)
        demandObserver = observer
        os_unfair_lock_unlock(&lock)
    }

    /// 采集停止、Scene 停止或设备失效时调用：归零但保留需求声明。
    func clearSnapshot() {
        os_unfair_lock_lock(&lock)
        snapshot = .silent
        publishedAtUptime = nil
        hasLoggedNonSilentPublication = false
        os_unfair_lock_unlock(&lock)
    }

    /// 完整复位，供测试与 Scene teardown 使用。
    /// 与 `setDemand` 一致：需求本就为 false 时不重复通知，避免无谓的采集重协调。
    func reset() {
        os_unfair_lock_lock(&lock)
        snapshot = .silent
        publishedAtUptime = nil
        nextGeneration = 1
        hasLoggedNonSilentPublication = false
        let previousDemand = demand
        let scopeEpoch: UInt64
        if previousDemand.includesCurrentProcessOutput {
            scopeEpoch = nextCaptureScopeEpoch
            nextCaptureScopeEpoch &+= 1
        } else {
            scopeEpoch = previousDemand.scopeEpoch
        }
        let resetDemand = SceneAudioSpectrumCaptureDemand(
            requiresSpectrum: false,
            includesCurrentProcessOutput: false,
            scopeEpoch: scopeEpoch
        )
        demand = resetDemand
        let observer = demandObserver
        os_unfair_lock_unlock(&lock)
        if previousDemand.requiresSpectrum {
            observer?(resetDemand)
        }
    }
}
