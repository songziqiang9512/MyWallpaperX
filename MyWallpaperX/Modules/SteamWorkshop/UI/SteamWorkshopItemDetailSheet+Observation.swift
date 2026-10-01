//
//  SteamWorkshopItemDetailSheet+Observation.swift
//  MyWallpaperX
//

import AppKit
import Combine

extension AppKitSteamWorkshopItemDetailView {
    /// 已下载条目的「文件大小」优先取本地样本目录合计（record.sizeText，
    /// 入库扫描时递归统计整个样本目录）；抓取的页面标称值仅作未下载时
    /// 的展示。
    var resolvedFileSizeText: String? {
        if let record = service.downloadRecord(for: currentItem.id),
           record.sizeText != "未知大小" {
            return record.sizeText
        }
        return currentItem.fileSizeText
    }

    /// Coalesces rebuild storms: a single download completion publishes
    /// several `objectWillChange` pulses in a row and a full rebuild tears
    /// down and recreates ~60-80 views each time. Sinks mark dirty here and
    /// one rebuild runs per main-queue pass with the latest state.
    func scheduleRebuild() {
        guard !isRebuildScheduled else { return }
        isRebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRebuildScheduled else { return }
            self.isRebuildScheduled = false
            self.currentItem = self.resolvedCurrentItem(fallback: self.currentItem)
            self.rebuild()
        }
    }

    func observeService() {
        WallpaperManager.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRebuild() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .sceneWallpaperLaunchStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRebuild() }
            .store(in: &cancellables)

        service.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRebuild() }
            .store(in: &cancellables)

        service.steamAuth.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.service.steamSubscriptions.synchronizeAccount()
                if self.service.steamAuth.isOnline { self.subscriptionHint = nil }
                self.scheduleRebuild()
            }
            .store(in: &cancellables)
        service.steamSubscriptions.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRebuild() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: WebRuntimeDiagnosticsStore.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      self.webDiagnosticsExpanded,
                      let webDownloadRecord = self.webDownloadRecord else {
                    return
                }
                if let changedRecordID = notification.object as? String,
                   changedRecordID != webDownloadRecord.id {
                    return
                }
                self.refreshDiagnosticsPanel()
            }
            .store(in: &cancellables)
    }
}
