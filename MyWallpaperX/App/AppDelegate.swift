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
 private(set) var terminationReplyPending = false

 // Native validation follows stable identifiers/selectors and current PageID.
 func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
 MainWindowMenuCommands.validate(menuItem)
 }

 func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
 if DebugSystemMediaRunner.isRequested {
 DebugSystemMediaRunner.scheduleIfRequested()
 return
 }
 if DebugSceneDaemonClientRunner.isRequested {
 if DebugSceneDaemonClientRunner.requiresProductCoordinator {
 MainMenuBuilder.installMainMenu()
 }
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
 // 启动时先隐藏 Dock 图标，再按"先播放链路、后主窗口"的顺序把界面拉起来
 // （激活门判定 isPlaying 或 scene 意图已在途）。
 MainMenuBuilder.installMainMenu()
 MainWindowCoordinator.setDockIconVisible(false)
 // 注册本地 Help Book，确保帮助菜单能找到文档。
 if let helpPath = Bundle.main.path(forResource: "MyWallpaperXHelp", ofType: nil) {
 NSHelpManager.shared.registerBooks(in: Bundle(path: helpPath) ?? .main)
 }
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
 // Best-effort warmup follows the actual engine. Web may hold one empty
 // renderer for 30s; it never starts Scene just because a Web record exists.
 NotificationCenter.default.addObserver(
     forName: .steamWorkshopSceneDownloadCompleted,
     object: nil,
     queue: .main
 ) { _ in
     MainActor.assumeIsolated { SceneDaemonClient.shared.warmSession() }
 }
 let warmupIntentEpoch = WallpaperManager.shared.playbackIntentEpoch
 DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
     guard let self, !self.didPrepareProductTermination else { return }
     let manager = WallpaperManager.shared
     guard manager.playbackIntentEpoch == warmupIntentEpoch else { return }
     let runtime = manager.activeWallpaperRuntime
     if runtime == .scene || manager.requestedRuntime == .scene {
         SceneDaemonClient.shared.warmSession()
     }
     if SteamWorkshopService.shared.downloads.contains(where: { $0.contentType == .web && $0.status == .ready }) {
         (WallpaperEngine.shared.dedicatedWebHostAdapter as? WebDaemonHostAdapter)?.prepareIdleProcess()
     }
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
 if !DebugSceneDaemonClientRunner.isRequested {
 if DebugScenePlaybackRunner.runsIsolatedSceneSample {
 if DebugScenePlaybackRunner.isFinished { return .terminateNow }
 guard !terminationReplyPending else { return .terminateLater }
 terminationReplyPending = true
 DaemonPlaybackProcessRegistry.shared.closeAdmission()
 DebugScenePlaybackRunner.finish { [weak self] _ in
 self?.replyAfterPlaybackProcessesExit(sender)
 }
 return .terminateLater
 }
 if DebugWebPlaybackRunner.runsIsolatedWebWorkshopSample {
 guard !terminationReplyPending else { return .terminateLater }
 terminationReplyPending = true
 DaemonPlaybackProcessRegistry.shared.closeAdmission()
 WallpaperEngine.shared.cleanup()
 SceneDaemonClient.shared.shutdown()
 replyAfterPlaybackProcessesExit(sender)
 return .terminateLater
 }
 }
#endif
 guard !terminationReplyPending else { return .terminateLater }
 terminationReplyPending = true
 MyWallpaperXApplication.prepareLibraryForTermination()
 Task { @MainActor [weak self] in
 guard let self else {
 MyWallpaperXApplication.cancelLibraryTermination()
 sender.reply(toApplicationShouldTerminate: false)
 return
 }
 if let error = await MyWallpaperXApplication.flushLibraryBeforeTermination() {
 self.terminationReplyPending = false
 MyWallpaperXApplication.cancelLibraryTermination()
 sender.reply(toApplicationShouldTerminate: false)
 presentAppAlert(makeAppAlert(title: "资料库尚未保存", message: error + "\n请重试退出。"), in: MainWindowCoordinator.mainWindow())
 return
 }
 // No await separates the successful metadata barrier from revoking the
 // original playback authority. A cancelled quit never closes admission.
 DaemonPlaybackProcessRegistry.shared.closeAdmission()
 self.prepareProductTermination()
 SceneDaemonClient.shared.shutdown()
 self.replyAfterPlaybackProcessesExit(sender)
 }
 return .terminateLater
 }

 // The registry delivers in common/modal modes after actual process exit,
 // independently of protocol EOF and dictionaries removed by engine cleanup.
 private func replyAfterPlaybackProcessesExit(_ sender: NSApplication) {
 DaemonPlaybackProcessRegistry.shared.waitForExit { [weak self] result in
 MainActor.assumeIsolated {
 if !result.allExited {
#if DEBUG
 NSLog("MWX playback termination deadline exceeded; remaining pids=%@",
       result.remainingProcessIdentifiers.description)
#endif
 self?.terminationReplyPending = false
 }
 sender.reply(toApplicationShouldTerminate: result.allExited)
 }
 }
 }

 func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
 // 点击 Dock 图标/重新打开时直接激活主窗口，不重新走启动分支。
 // 初始激活被跳过（如 DEBUG 隔离运行）时在此兜底补跑延后的整库扫描；
 // 已补跑过则为 no-op。
 SteamWorkshopService.shared.performStartupLibraryReloadIfNeeded()
 MainWindowCoordinator.activateMainWindow()
 return true
 }

 func applicationWillTerminate(_ notification: Notification) {
 DaemonPlaybackProcessRegistry.shared.closeAdmission()
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
 ScreenSaverCoordinator.shared.cancel()
 // Revoke accepted async work before a Scene drain enters terminateLater.
 // Engine cleanup alone does not invalidate the selection authority's epoch.
 let epoch = WallpaperManager.shared.beginPlaybackIntent()
 WallpaperEngine.shared.adoptIntentEpoch(epoch)
 SteamWorkshopService.shared.advanceWebLaunchIntentGeneration()
 WallpaperManager.shared.restoreSystemDesktopWallpaperOnTermination()
 WallpaperManager.shared.flushPersistentState()
 WallpaperEngine.shared.cleanup()
 ScreenSaverActivityMonitor.shared.stop()
 }

 /// 工坊整库扫描延后补跑：主窗口激活后让出一轮 runloop（首帧先起），
 /// 再执行完整 reloadInstalledItems()。补跑前 downloads 投影只含重放快
 /// 路径并入的单条记录；菜单验证在工坊下载页之外短路，下载页另有
 /// viewDidMoveToWindow 的空投影自愈重载，均不依赖此处先行完成。
 private func performDeferredStartupLibraryReload() {
 DispatchQueue.main.async {
 SteamWorkshopService.shared.performStartupLibraryReloadIfNeeded()
 }
 }

 // 启动分阶段：优先让壁纸播放链路起稳（isPlaying，或 scene 意图已在
 // 途），再激活主窗口，降低冷启动"同时抢占"造成的卡顿感。
 private func scheduleInitialMainWindowActivation() {
 #if DEBUG
 if DebugWebPlaybackRunner.shouldSuppressInitialMainWindow {
 return
 }
 #endif
 // 启动分阶段：先让播放引擎稳定（isPlaying 或 scene 意图在途），再激
 // 活主窗口，减少冷启动时 UI 和 daemon 同时争抢资源。
 pendingInitialWindowOpen?.cancel()

 let launchStart = CACurrentMediaTime()
        let timeout: CFTimeInterval = 0.45

 func tryActivate() {
 //进程即将退出/已退出时，不再触发窗口激活。
 guard NSApp.isRunning else { return }

 let elapsed = CACurrentMediaTime() - launchStart
 // scene 意图在启动重放同步链内置位（warmSession 只预热不置 intent，
 // 不会误触发）；意图在途即视为播放链路已起稳，不再等满 timeout。
 let sceneIntentInFlight = SceneDaemonClient.shared.pendingIntent != nil
     || SceneDaemonClient.shared.activeIntent != nil
 if WallpaperEngine.shared.isPlaying() || sceneIntentInFlight || elapsed >= timeout {
 MainWindowCoordinator.activateMainWindow()
 performDeferredStartupLibraryReload()
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

 @objc func createPlaylistMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuCreatePlaylist() }
 @objc func importMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuImport() }
 @objc func undoMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuUndo() }
 @objc func redoMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuRedo() }
 @objc func toggleMultiSelectMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuToggleSelection() }
 @objc func deleteSelectedMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuDeleteSelected(sender) }
 @objc func focusSearchMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuSearch() }
 @objc func zoomInMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuZoom(1) }
 @objc func zoomOutMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuZoom(-1) }
 @objc func setAsWallpaperMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuApplyWallpaper(sender) }
 @objc func nextWallpaperMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuNavigate(.next, sender: sender) }
 @objc func previousWallpaperMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuNavigate(.previous, sender: sender) }
 @objc func toggleFavoriteMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuFavorite(sender) }
 @objc func addToPlaylistMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuAddToPlaylist(sender) }
 @objc func showInfoMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuInfo(sender) }
 @objc func previewMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuPreview(sender) }
 @objc func revealInFinderMenuAction(_ sender: Any?) { MainWindowMenuCommands.menuRevealOrRefresh(sender) }
 @objc func navigateLibraryPageMenuAction(_ sender: NSMenuItem) { MainWindowMenuCommands.menuNavigatePage(sender) }

 @objc func closeWindowMenuAction(_ sender: Any?) {
 // Popover owners precede their host window; borderless sheets also handle this action.
 NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSWindow.performClose(_:)), with: sender)
 }
}
