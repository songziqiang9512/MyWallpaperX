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

/// Immutable identity of the process set applied to one system-tap resource.
/// It travels with captured bands so a retiring tap cannot publish into a newer
/// requested scope, including a rapid exclude -> include -> exclude transition.
nonisolated struct SceneAudioSpectrumCaptureToken: Equatable, Sendable {
    let scopeEpoch: UInt64
    let includesCurrentProcessOutput: Bool
}

/// 采集线程与渲染线程之间的单一交汇点。
///
/// 采集在 `SystemAudioSpectrumService` 的串行队列上产生快照，Scene 渲染在主线程读取。
/// 这里只保留「最近一帧」：Scene 消费者按渲染帧采样，不需要历史队列，
/// 掉帧时读到同一份快照而不是积压的旧数据。
final class SceneAudioSpectrumInbox: @unchecked Sendable {
    static let shared = SceneAudioSpectrumInbox()

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
    private var demandObserver: ((Bool) -> Void)?
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
        let now = uptime()
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        if let publishedAtUptime,
           now >= publishedAtUptime,
           now - publishedAtUptime >= Self.maximumSnapshotAge {
            if !snapshot.isSilent {
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
            }
            self.publishedAtUptime = nil
        }
        return snapshot
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
    func publishSystemCapture(
        left: [Float],
        right: [Float],
        left32: [Float],
        right32: [Float],
        left64: [Float],
        right64: [Float],
        token: SceneAudioSpectrumCaptureToken
    ) {
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

    private func publish(
        left: [Float],
        right: [Float],
        left32: [Float],
        right32: [Float],
        left64: [Float],
        right64: [Float],
        requiredCaptureToken: SceneAudioSpectrumCaptureToken?
    ) {
        os_unfair_lock_lock(&lock)
        if let requiredCaptureToken,
           (!demand.requiresSpectrum
            || demand.scopeEpoch != requiredCaptureToken.scopeEpoch
            || demand.includesCurrentProcessOutput
                != requiredCaptureToken.includesCurrentProcessOutput) {
            os_unfair_lock_unlock(&lock)
            return
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
    /// demand. A scope change while demand remains active still notifies the
    /// observer so the single system tap can be restarted with the new scope.
    func setDemand(
        _ demanded: Bool,
        requiresCurrentProcessAudioCapture: Bool
    ) {
        os_unfair_lock_lock(&lock)
        let requestedIncludesCurrentProcessOutput = demanded
            && requiresCurrentProcessAudioCapture
        let sourceScopeChanged = demand.includesCurrentProcessOutput
            != requestedIncludesCurrentProcessOutput
        let requestedScopeEpoch: UInt64
        if sourceScopeChanged {
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
        if !requestedDemand.requiresSpectrum || sourceScopeChanged {
            snapshot = .silent
            publishedAtUptime = nil
            hasLoggedNonSilentPublication = false
        }
        let observer = demandObserver
        os_unfair_lock_unlock(&lock)
        observer?(requestedDemand.requiresSpectrum)
    }

    /// 由播放引擎注册，用于在需求变化时重新协调采集状态。
    func setDemandObserver(_ observer: ((Bool) -> Void)?) {
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
        demand = SceneAudioSpectrumCaptureDemand(
            requiresSpectrum: false,
            includesCurrentProcessOutput: false,
            scopeEpoch: scopeEpoch
        )
        let observer = demandObserver
        os_unfair_lock_unlock(&lock)
        if previousDemand.requiresSpectrum {
            observer?(false)
        }
    }
}
