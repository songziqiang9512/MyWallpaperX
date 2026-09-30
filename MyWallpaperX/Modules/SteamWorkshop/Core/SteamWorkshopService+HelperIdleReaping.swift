//
//  SteamWorkshopService+HelperIdleReaping.swift
//  MyWallpaperX
//

import Foundation

extension SteamWorkshopService {
    /// SK-helper-idle-reap 装配（策略归属模块 owner）：门全部读本服务与 client 的
    /// 真实状态 owner，回收动作复用既有 `stop()` 通道（isStopping 路径，不触发
    /// 自动重启）。计时器/时钟用生产实现；离线 harness 在 SteamHelperIdleReaper
    /// 上注入 fake transport/scheduler 验证同一策略类型。
    func installHelperIdleReaping() {
        guard helperIdleReaper == nil else { return }
        let reaper = SteamHelperIdleReaper(
            timing: MainQueueSteamIdleReapTiming(),
            gates: .init(
                helperQuiet: { [weak self] in self?.steamServiceClient.isReadyAndQuiet == true },
                accountDormant: { [weak self] in self?.steamAuth.isDormantForHelperReaping == true },
                downloadsDormant: { [weak self] in
                    guard let self else { return false }
                    // 任务表与 JobStore 双读：activeDownloadTasks 覆盖在飞执行，
                    // activeJobs 覆盖 queued/running 的持久真值。
                    return self.activeDownloadTasks.isEmpty && self.downloadJobStore.activeJobs.isEmpty
                },
                browseDormant: { [weak self] in self?.isBrowsePanelOpen == false }
            ),
            // 活动龄期以出站请求时钟戳为准；服务释放后按“永不 dormancy”处理（宁漏勿误）。
            lastActivity: { [weak self] in self?.steamServiceClient.lastRequestActivity ?? Date() },
            reap: { @MainActor [weak self] in await self?.steamServiceClient.stop() }
        )
        helperIdleReaper = reaper
        reaper.begin()
    }
}
