//
//  SteamHelperIdleReaper.swift
//  MyWallpaperX
//

import Foundation

/// SK-helper-idle-reap：Steam helper 空闲回收。
///
/// 合同：策略归属模块 owner（SteamWorkshopService 装配，见
/// `SteamWorkshopService+HelperIdleReaping.swift`）；回收复用既有 `stop()` 通道
/// （isStopping 路径，不触发自动重启），不新增协议命令，C# 侧零改动。
/// 门全部满足且在 MainActor 上与 `stop()` 调用同一原子时机评估；登录态绝不回收
/// （宁漏勿误）。回收后每条意图入口必须能恢复：匿名读在
/// `SteamServiceClient.anonymousReadCommands` 内透明重启，账号/订阅/下载经
/// `SteamAuthRoute.ensureHelperReady` 与 `SteamWorkshopQueryClient.ensureHelperStarted`
/// 显式重启，浏览面板打开期间（`SteamWorkshopService.isBrowsePanelOpen`，由
/// 浏览视图进出窗口事件维护的挂载计数）根本不会回收。
///
/// 默认参数依据：idleTimeout 600s ≫ 请求超时 30s 与握手超时 12s，在途工作不可能
/// 被回收截断（pending 门同时拦住）；又远小于整机闲置时 helper 进程 + Steam 连接
/// 的常驻开销所值得的保留时间。回收代价只由闲置 ≥10 分钟后的下一条意图支付
/// （亚秒级 spawn，且全部意图入口已可恢复）。pollInterval 60s 使回收延迟上界为
/// timeout + poll；轮询只在 MainActor 上读几个状态字段，且与超时语义解耦——
/// 「持续空闲 ≥ idleTimeout」以请求活动时钟为准，不受轮询漂移影响。
@MainActor
final class SteamHelperIdleReaper {
    /// 回收门（组合语义唯一，见 allSatisfied；产品装配在
    /// `SteamWorkshopService+HelperIdleReaping.swift` 读真实状态 owner，离线
    /// harness 注入同转移规则的 owner 复制品）。
    struct Gates {
        /// helper ready 且无在途 pending（client 静默信号）。
        var helperQuiet: () -> Bool
        /// 未登录且无进行中认证（steamAuth 实际状态字段）。
        var accountDormant: () -> Bool
        /// 无活动下载作业（JobStore/任务表实际状态）。
        var downloadsDormant: () -> Bool
        /// 浏览 UI 不活跃（浏览面板挂载计数为 0；owner：
        /// `SteamWorkshopService.isBrowsePanelOpen`）。
        var browseDormant: () -> Bool

        func allSatisfied() -> Bool {
            helperQuiet() && accountDormant() && downloadsDormant() && browseDormant()
        }
    }

    let idleTimeout: TimeInterval
    let pollInterval: TimeInterval
    private let now: () -> Date
    private let timing: any SteamIdleReapTiming
    private let gates: Gates
    private let lastActivity: () -> Date
    /// 回收动作必须是 @MainActor 闭包：否则 nonisolated async 闭包在调用点
    /// （SE-0338）真实跳出 MainActor，门复核与回收启动之间出现挂起窗口，
    /// 原子时机合同失效。@MainActor 使调用为同执行者直调，复核后同步进入
    /// 闭包体（stop() 的同步前奏即刻落地），主线程用户意图无法插队。
    private let reap: @MainActor () async -> Void
    private var isRunning = false

    init(
        idleTimeout: TimeInterval = 600,
        pollInterval: TimeInterval = 60,
        now: @escaping () -> Date = { Date() },
        timing: any SteamIdleReapTiming,
        gates: Gates,
        lastActivity: @escaping () -> Date,
        reap: @escaping @MainActor () async -> Void
    ) {
        self.idleTimeout = idleTimeout
        self.pollInterval = pollInterval
        self.now = now
        self.timing = timing
        self.gates = gates
        self.lastActivity = lastActivity
        self.reap = reap
    }

    /// 开始轮询（首次评估在 pollInterval 之后；无活动钩子，全靠周期评估）。
    func begin() {
        guard !isRunning else { return }
        isRunning = true
        scheduleNextPoll()
    }

    /// 停止轮询（测试与关停用；不再评估、不再回收）。
    func end() {
        isRunning = false
        timing.cancelScheduled()
    }

    private func isDormant(at date: Date) -> Bool {
        gates.allSatisfied() && date.timeIntervalSince(lastActivity()) >= idleTimeout
    }

    private func evaluate() {
        guard isRunning else { return }
        scheduleNextPoll()
        guard isDormant(at: now()) else { return }
        Task { @MainActor [weak self] in
            // 与 stop() 同一 MainActor 原子时机：reap 为 @MainActor 闭包，门复核
            // 后同执行者直调，复核与 reap 启动之间无挂起点、无执行者切换。
            guard let self, self.isDormant(at: self.now()) else { return }
            await self.reap()
        }
    }

    private func scheduleNextPoll() {
        timing.schedule(after: pollInterval) { [weak self] in self?.evaluate() }
    }
}

/// 空闲回收的计时注入点：生产用 main-queue DispatchWorkItem（与 client 的
/// 超时工作项同一模式）；离线 harness 注入可手动点火的 fake scheduler。
@MainActor
protocol SteamIdleReapTiming: AnyObject {
    /// 以 delay 后触发 handler 重新调度（重复调用以最后一次为准）。
    func schedule(after delay: TimeInterval, _ handler: @escaping @MainActor () -> Void)
    func cancelScheduled()
}

/// 生产时钟实现：main queue 上的可取消工作项。
@MainActor
final class MainQueueSteamIdleReapTiming: SteamIdleReapTiming {
    private var workItem: DispatchWorkItem?

    func schedule(after delay: TimeInterval, _ handler: @escaping @MainActor () -> Void) {
        cancelScheduled()
        let item = DispatchWorkItem {
            MainActor.assumeIsolated { handler() }
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancelScheduled() {
        workItem?.cancel()
        workItem = nil
    }
}
