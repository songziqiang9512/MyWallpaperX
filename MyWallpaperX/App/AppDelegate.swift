//
// AppDelegate.swift
// MyWallpaperX
//

import Foundation
import AppKit
import QuartzCore

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
 private var statusBarController: StatusBarController?
 private var pendingInitialWindowOpen: DispatchWorkItem?
 private var didPrepareProductTermination = false
 private var terminationReplyPending = false

 private func normalizedMenuTitle(_ menuItem: NSMenuItem) -> String {
 menuItem.title.replacingOccurrences(of: " ", with: "")
 }

 private func textViewFirstResponder() -> NSTextView? {
 guard let keyWindow = NSApp.keyWindow else { return nil }
 return keyWindow.firstResponder as? NSTextView
 }

 private func editableTextViewFirstResponder() -> NSTextView? {
 guard let textView = textViewFirstResponder(), textView.isEditable else { return nil }
 return textView
 }

 // MARK: - 菜单验证（AppKit 每次菜单显示前自动调用，正确处理模块切换后的可用状态）
 func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
 let module = MainWindowCoordinator.activeModule

 // 导入菜单项标题随模块动态变化，在线库下禁用
 if menuItem.title == "导入" || menuItem.title == "导入视频" || menuItem.title == "导入图片" {
 if module == .staticImageLibrary {
 menuItem.title = "导入图片"
 return true
 } else if module == .onlineLibrary || module == .steamWorkshop {
 menuItem.title = "导入"
 return false
 } else {
 menuItem.title = "导入视频"
 return true
 }
 }

 if normalizedMenuTitle(menuItem) == "查看文件" || normalizedMenuTitle(menuItem) == "刷新" {
 menuItem.title = MainWindowCoordinator.revealInFinderMenuTitle
 return MainWindowCoordinator.canRevealInFinder
 }

 switch normalizedMenuTitle(menuItem) {
 case "切换下一张", "切换上一张":
 // 跨引擎统一轮换（视频库+工坊 web/scene），与热键/状态栏同源，
 // 不再受视频库激活状态门控。
 // 必须保持启用：菜单键等价匹配后事件即被菜单系统消费，禁用项并不能把
 // Cmd+←/→ 作为 keyDown 还给文本系统；文本焦点下的光标移动路由
 // 在对应 action 内完成（同「全选/删除选中」的既有转发模式）。
 return true

 case "设为当前壁纸", "收藏/取消收藏":
 return MainWindowCoordinator.canUseVideoLibraryOnlyCommands

 case "进入/退出多选":
 return MainWindowCoordinator.canToggleMultiSelect

 case "全选":
 if textViewFirstResponder() != nil {
 return true
 }
 return MainWindowCoordinator.canSelectAll

 case "删除选中":
 if editableTextViewFirstResponder() != nil {
 return true
 }
 return MainWindowCoordinator.canDeleteSelected

 case "添加标签":
 return MainWindowCoordinator.canAddTag

 case "查看信息":
 return MainWindowCoordinator.canShowInfo

 case "预览":
 return MainWindowCoordinator.canPreview

 default:
 return true
 }
 }

 func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
 if DebugSceneDaemonClientRunner.isRequested {
 DebugSceneDaemonClientRunner.scheduleIfRequested()
 return
 }
 if DebugScenePlaybackRunner.runsIsolatedSceneSample {
 DebugScenePlaybackRunner.scheduleScenePlaybackIfRequested()
 return
 }
 if DebugWebPlaybackRunner.runsIsolatedWebWorkshopSample {
 DebugWebPlaybackRunner.scheduleWebWorkshopRuntimeIfRequested()
 return
 }
#endif
 // 启动时先隐藏 Dock 图标，再按"先播放链路、后主窗口"的顺序把界面拉起来。
 MainMenuBuilder.installMainMenu()
 MainWindowCoordinator.setDockIconVisible(false)
 // 注册本地 Help Book，确保帮助菜单能找到文档。
 if let helpPath = Bundle.main.path(forResource: "MyWallpaperXHelp", ofType: nil) {
 NSHelpManager.shared.registerBooks(in: Bundle(path: helpPath) ?? .main)
 }
 // 启动重放：上次是 web/scene 壁纸时按单品身份走原工坊入口恢复
 // （Modules 不直呼 SteamWorkshop 单例，装配层执行；单品已删除时由
 // manager 回落降级路径）。
 replayWorkshopLaunchIfPlanned()
 scheduleInitialMainWindowActivation()
#if DEBUG
 DebugWebPlaybackRunner.scheduleWorkshopPlaybackIfRequested()
 DebugWebPlaybackRunner.scheduleWebWorkshopRuntimeIfRequested()
#endif
 // 避开启动期布局敏感窗口，延后创建状态栏项，降低触发 AppKit 布局递归的概率。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
 guard let self, self.statusBarController == nil else { return }
 self.statusBarController = StatusBarController()
 }
 // daemon 预热（best-effort）：启动 3 秒后孵化热 daemon，真实 Scene 切换
 // 复用热 transport；失败静默、不重试、零可见状态。warmSession 自带守卫
 // （已有热 transport / 已有 pending intent 时跳过）。
 NotificationCenter.default.addObserver(
     forName: .steamWorkshopSceneDownloadCompleted,
     object: nil,
     queue: .main
 ) { _ in
     SceneDaemonClient.shared.warmSession()
 }
 DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
     guard self != nil else { return }
     SceneDaemonClient.shared.warmSession()
 }
 }

 @objc func showAboutMenuAction(_ sender: Any?) {
 AboutWindowController.shared.show()
 }

 func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
 false
 }

 func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
 false
 }

 func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
 false
 }

 func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
 false
 }

 func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
#if DEBUG
 if !DebugSceneDaemonClientRunner.isRequested
     && (DebugScenePlaybackRunner.runsIsolatedSceneSample
         || DebugWebPlaybackRunner.runsIsolatedWebWorkshopSample) {
 return .terminateNow
 }
#endif
 guard !terminationReplyPending else { return .terminateLater }
 terminationReplyPending = true
 prepareProductTermination()
 SceneDaemonClient.shared.shutdown {
 sender.reply(toApplicationShouldTerminate: true)
 }
 return .terminateLater
 }

 func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
 // 点击 Dock 图标/重新打开时直接激活主窗口，不重新走启动分支。
 MainWindowCoordinator.activateMainWindow()
 return true
 }

 func applicationWillTerminate(_ notification: Notification) {
#if DEBUG
 if DebugSceneDaemonClientRunner.isRequested {
 SceneDaemonClient.shared.shutdown()
 return
 }
 if DebugScenePlaybackRunner.runsIsolatedSceneSample {
 DebugScenePlaybackRunner.stop()
 return
 }
 if DebugWebPlaybackRunner.runsIsolatedWebWorkshopSample {
 WallpaperEngine.shared.cleanup()
 return
 }
#endif
 prepareProductTermination()
 SceneDaemonClient.shared.shutdown()
 }

 private func prepareProductTermination() {
 guard !didPrepareProductTermination else { return }
 didPrepareProductTermination = true
 //终止时先刷盘再清引擎，避免最近使用、当前壁纸和播放状态丢失。
 pendingInitialWindowOpen?.cancel()
 pendingInitialWindowOpen = nil
 statusBarController = nil
 WallpaperManager.shared.flushPersistentState()
 WallpaperEngine.shared.cleanup()
 }

 /// 消费 manager 在启动恢复期产出的 web/scene 重放计划：按 recordID 走
 /// SteamWorkshopService.setAsWallpaper 统一入口（依赖检查/资源生命
 /// 周期/通知发射全复用）；退出前暂停的意图随启动投影（scene 侧
 /// isPaused 记录 + replay 补发，web 侧引擎在 host ready 后补暂停）。
 private func replayWorkshopLaunchIfPlanned() {
 guard let plan = WallpaperManager.shared.consumeWorkshopLaunchReplayPlan() else {
 return
 }
 let workshop = SteamWorkshopService.shared
 if let record = workshop.downloadRecord(for: plan.recordID),
 record.contentType == .web || record.contentType == .scene {
 workshop.setAsWallpaper(record)
 if plan.restorePausedIntent {
 PlaybackCommandMultiplexer.shared.dispatch(.pause)
 WallpaperManager.shared.isPlaying = false
 }
 return
 }
 WallpaperManager.shared.fallBackToMostRecentVideoAfterWorkshopReplay(
 restorePausedIntent: plan.restorePausedIntent
 )
 }

 // 启动分阶段：优先让壁纸播放链路起稳，再激活主窗口，降低冷启动"同时抢占"造成的卡顿感。
 private func scheduleInitialMainWindowActivation() {
 #if DEBUG
 if DebugWebPlaybackRunner.shouldSuppressInitialMainWindow {
 return
 }
 #endif
 // 启动分阶段：先让播放引擎稳定，再激活主窗口，减少冷启动时 UI 和 daemon 同时争抢资源。
 pendingInitialWindowOpen?.cancel()

 let launchStart = CACurrentMediaTime()
        let timeout: CFTimeInterval = 0.45

 func tryActivate() {
 //进程即将退出/已退出时，不再触发窗口激活。
 guard NSApp.isRunning else { return }

 let elapsed = CACurrentMediaTime() - launchStart
 if WallpaperEngine.shared.isPlaying() || elapsed >= timeout {
 MainWindowCoordinator.activateMainWindow()
 return
 }

 let retry = DispatchWorkItem { tryActivate() }
 pendingInitialWindowOpen = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: retry)
 }

 let firstTry = DispatchWorkItem { tryActivate() }
 pendingInitialWindowOpen = firstTry
 DispatchQueue.main.async(execute: firstTry)
 }

 @objc func showSettingsMenuAction(_ sender: Any?) {
 SettingsWindowController.shared.showWindow()
 }

 @objc func createTagMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuCreateTag()
 }

 @objc func importMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuImport()
 }

 @objc func selectAllMenuAction(_ sender: Any?) {
 if let textView = textViewFirstResponder() {
 textView.selectAll(sender)
 return
 }
 MainWindowCoordinator.menuSelectAll()
 }

 @objc func toggleMultiSelectMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuToggleMultiSelect()
 }

 @objc func deleteSelectedMenuAction(_ sender: Any?) {
 if let textView = editableTextViewFirstResponder() {
 textView.delete(sender)
 return
 }
 MainWindowCoordinator.menuDeleteSelected()
 }

 @objc func focusSearchMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuFocusSearch()
 }

 @objc func zoomInMenuAction(_ sender: Any?) {
 MainWindowCoordinator.performZoom(delta: 1)
 }

 @objc func zoomOutMenuAction(_ sender: Any?) {
 MainWindowCoordinator.performZoom(delta: -1)
 }

 @objc func setAsWallpaperMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuSetAsWallpaper()
 }

 @objc func nextWallpaperMenuAction(_ sender: Any?) {
 // Cmd+→ 在可编辑文本框内是标准「移到行尾」光标移动，路由给文本视图，
 // 不劫持为切换壁纸。
 if let textView = editableTextViewFirstResponder() {
 textView.moveToEndOfLine(sender)
 return
 }
 MainWindowCoordinator.menuNavigate(.next)
 }

 @objc func previousWallpaperMenuAction(_ sender: Any?) {
 // Cmd+← 在可编辑文本框内是标准「移到行首」光标移动，路由给文本视图。
 if let textView = editableTextViewFirstResponder() {
 textView.moveToBeginningOfLine(sender)
 return
 }
 MainWindowCoordinator.menuNavigate(.previous)
 }

 @objc func toggleFavoriteMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuToggleFavorite()
 }

 @objc func addTagMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuAddTag()
 }

 @objc func showInfoMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuShowInfo()
 }

 @objc func previewMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuPreview()
 }

 @objc func revealInFinderMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuRevealInFinder()
 }

 @objc func closeWindowMenuAction(_ sender: Any?) {
 NSApp.keyWindow?.performClose(nil)
 }
}
