//
//  SceneAudioSpectrum.swift
//  MyWallpaperX
//

import Foundation
import os.lock

/// 一帧 Scene 音频频谱快照。
///
/// 官方 stock shader（`pulse.vert` / `shake.vert`）使用 16 档；Workshop shader
/// 还会明确声明 32/64 档。当前宿主同时承载 16 与 64 档、左右分离、由低到高、取正值。
///
/// 频段边界、幅度归一化与平滑策略官方均未公开，当前实现是工程选择而非官方合同，
/// 不能据此宣称与 Wallpaper Engine 数值等价。32 档与 SceneScript audio buffer
/// 仍未接入；64 档仅供严格准入的 Workshop shader consumer 使用。
nonisolated struct SceneAudioSpectrumSnapshot: Equatable {
    static let bandCount = 16
    static let extendedBandCount = 64

    /// 左声道频段能量，索引 0 为最低频。
    let left: [Float]
    /// 右声道频段能量，索引 0 为最低频。
    let right: [Float]
    /// Workshop shader 的 64 档左声道频段能量。
    let left64: [Float]
    /// Workshop shader 的 64 档右声道频段能量。
    let right64: [Float]
    /// 每次发布递增；相同内容也会递增，用于区分「同一帧重复读取」与「新采样」。
    let generation: UInt64

    /// 采集不可用、静音或尚未产生数据时的稳定零输入。
    static let silent = SceneAudioSpectrumSnapshot(
        left: Array(repeating: 0, count: bandCount),
        right: Array(repeating: 0, count: bandCount),
        left64: Array(repeating: 0, count: extendedBandCount),
        right64: Array(repeating: 0, count: extendedBandCount),
        generation: 0
    )

    /// 全零判定。采集失败与真实静音在数值上等价，都必须是稳定零而不是假波形。
    nonisolated var isSilent: Bool {
        left.allSatisfy { $0 == 0 } && right.allSatisfy { $0 == 0 }
            && left64.allSatisfy { $0 == 0 } && right64.allSatisfy { $0 == 0 }
    }

    nonisolated init(left: [Float], right: [Float], generation: UInt64) {
        self.init(
            left: left,
            right: right,
            left64: Array(repeating: 0, count: Self.extendedBandCount),
            right64: Array(repeating: 0, count: Self.extendedBandCount),
            generation: generation
        )
    }

    nonisolated init(
        left: [Float],
        right: [Float],
        left64: [Float],
        right64: [Float],
        generation: UInt64
    ) {
        self.left = Self.sanitized(left, count: Self.bandCount)
        self.right = Self.sanitized(right, count: Self.bandCount)
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

/// 采集线程与渲染线程之间的单一交汇点。
///
/// 采集在 `SystemAudioSpectrumService` 的串行队列上产生快照，Scene 渲染在主线程读取。
/// 这里只保留「最近一帧」：Scene 消费者按渲染帧采样，不需要历史队列，
/// 掉帧时读到同一份快照而不是积压的旧数据。
final class SceneAudioSpectrumInbox: @unchecked Sendable {
    static let shared = SceneAudioSpectrumInbox()

    private var lock = os_unfair_lock_s()
    private var snapshot = SceneAudioSpectrumSnapshot.silent
    private var nextGeneration: UInt64 = 1
    private var demanded = false
    private var demandObserver: ((Bool) -> Void)?

    init() {}

    /// 是否有 Scene 消费者需要频谱。没有消费者时不应请求采集。
    var isDemanded: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return demanded
    }

    /// 当前最近一帧快照。无数据时返回稳定零输入。
    func latest() -> SceneAudioSpectrumSnapshot {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return snapshot
    }

    /// 由采集侧发布一帧。长度或数值非法时 `SceneAudioSpectrumSnapshot` 会归零。
    func publish(left: [Float], right: [Float]) {
        publish(
            left: left,
            right: right,
            left64: Array(repeating: 0, count: SceneAudioSpectrumSnapshot.extendedBandCount),
            right64: Array(repeating: 0, count: SceneAudioSpectrumSnapshot.extendedBandCount)
        )
    }

    func publish(left: [Float], right: [Float], left64: [Float], right64: [Float]) {
        os_unfair_lock_lock(&lock)
        let generation = nextGeneration
        nextGeneration &+= 1
        snapshot = SceneAudioSpectrumSnapshot(
            left: left,
            right: right,
            left64: left64,
            right64: right64,
            generation: generation
        )
        os_unfair_lock_unlock(&lock)
    }

    /// 声明/撤销 Scene 侧的采集需求。
    ///
    /// 当前没有任何 Scene 消费者，产品路径不会自动开启；接入第一个 effect 或
    /// particle consumer 时才由该 consumer 的存在驱动。撤销时立即归零，
    /// 避免停止采集后残留最后一帧非零数据。
    func setDemand(_ demanded: Bool) {
        os_unfair_lock_lock(&lock)
        guard self.demanded != demanded else {
            os_unfair_lock_unlock(&lock)
            return
        }
        self.demanded = demanded
        if !demanded {
            snapshot = .silent
        }
        let observer = demandObserver
        os_unfair_lock_unlock(&lock)
        observer?(demanded)
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
        os_unfair_lock_unlock(&lock)
    }

    /// 完整复位，供测试与 Scene teardown 使用。
    /// 与 `setDemand` 一致：需求本就为 false 时不重复通知，避免无谓的采集重协调。
    func reset() {
        os_unfair_lock_lock(&lock)
        snapshot = .silent
        nextGeneration = 1
        let wasDemanded = demanded
        demanded = false
        let observer = demandObserver
        os_unfair_lock_unlock(&lock)
        if wasDemanded {
            observer?(false)
        }
    }
}
