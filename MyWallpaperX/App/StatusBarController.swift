//
//  StatusBarController.swift
//  MyWallpaperX
//
//  Created by 宋子强 on 2026/3/12.
//  本项目遵循macOS26设计规范，请尽量调用原生接口实现
//

import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var didSetupStatusBar = false
    private var isMenuOpen = false
    private let wallpaperManager: WallpaperManager = .shared

    /// 跨引擎播放态：video/scene 任一在播即视为"播放中"。
    private var anyEnginePlaying: Bool {
        PlaybackCommandMultiplexer.shared.isAnyEnginePlaying
            || WallpaperEngine.shared.isPlaying()
    }

    // 状态栏动态刷新定时器（每 2 秒更新一次图标上的 GPU%）
    private var iconRefreshTimer: DispatchSourceTimer?

    private lazy var menu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.showsStateColumn = true
        return menu
    }()
    
    override init() {
        super.init()
        setupStatusBar()
    }
    
    private func setupStatusBar() {
        guard !didSetupStatusBar else { return }
        didSetupStatusBar = true
        // 状态栏图标只初始化一次，避免重复创建导致菜单 / target 丢失。
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        // 首次用默认图标，定时器起来后会换成动态 GPU% 图标
        button.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "Wallpaper Control")
        statusItem?.menu = menu
        SystemMonitor.shared.refreshRuntimeStats()
        rebuildMenu()
        updateStatusBarIcon()
        startIconRefreshTimer()
    }

    // MARK: - 状态栏图标动态刷新

    private func startIconRefreshTimer() {
        // 首次采样（建立基线，第一次差值为 0 属正常）
        SystemMonitor.shared.refreshRuntimeStats()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            SystemMonitor.shared.refreshRuntimeStats()
            self.updateStatusBarIcon()
            if self.isMenuOpen {
                self.rebuildMenu()
            }
        }
        iconRefreshTimer = timer
        timer.resume()
    }

    /// 将 GPU% 渲染到状态栏图标（加粗等宽数字，保持轻量可读）
    private func updateStatusBarIcon() {
        let pct = Int(((SystemMonitor.shared.stats.gpuUsage ?? 0) * 100).rounded())
        let label = String(format: "%d%%", pct)

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        let imgSize = NSSize(width: max(size.width + 2, 28), height: 18)

        let img = NSImage(size: imgSize, flipped: false) { rect in
            let y = (rect.height - size.height) / 2
            (label as NSString).draw(
                at: NSPoint(x: (rect.width - size.width) / 2, y: y),
                withAttributes: attrs
            )
            return true
        }
        img.isTemplate = true
        statusItem?.button?.image = img
        statusItem?.button?.imagePosition = .imageOnly
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        // 菜单打开时先用最近一次采样结果重建，避免展开瞬间被同步采样拖慢。
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }
    
    private func rebuildMenu() {
        // 菜单动作尽量直接复用主窗口同一套入口，不另造一套状态机。
        menu.removeAllItems()

        // ── 系统状态监控区 ──────────────────────────────────────
        let s = SystemMonitor.shared.stats

        // 第一行：CPU + GPU 负载
        let line1 = "CPU \(s.cpuUsageString)   GPU \(s.gpuUsageString)"
        menu.addItem(makeInfoItem(title: line1, systemImageName: "cpu"))

        // 第二行：内存
        let memoryLine = "内存 \(s.memUsedString) / \(s.memTotalString)"
        menu.addItem(makeInfoItem(title: memoryLine, systemImageName: "memorychip"))

        // 第三行：网络
        let netLine = "↑ \(s.netUpString)   ↓ \(s.netDownString)"
        menu.addItem(makeInfoItem(title: netLine, systemImageName: "network"))

        menu.addItem(.separator())
        // ── 系统状态监控区结束 ──────────────────────────────────

        menu.addItem(makeItem(title: "打开主界面", systemImageName: "macwindow", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(makeItem(title: "导入视频", systemImageName: "plus.circle", action: #selector(importVideos), keyEquivalent: ""))
        
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "切换壁纸", systemImageName: "arrow.right.circle", action: #selector(switchWallpaper), keyEquivalent: ""))

        let playbackTitle = anyEnginePlaying ? "暂停播放" : "继续播放"
        let playbackIcon = anyEnginePlaying ? "pause.circle" : "play.circle"
        menu.addItem(makeItem(title: playbackTitle, systemImageName: playbackIcon, action: #selector(togglePlayback), keyEquivalent: ""))
        
        let muteTitle = wallpaperManager.isMuted ? "关闭静音" : "开启静音"
        let muteIcon = wallpaperManager.isMuted ? "volume.2" : "volume.slash"
        menu.addItem(makeItem(title: muteTitle, systemImageName: muteIcon, action: #selector(toggleMute), keyEquivalent: ""))
        
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "偏好设置", systemImageName: "gearshape", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        
        let quitItem = makeItem(title: "退出", systemImageName: "xmark.circle", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)
    }
    
    /// 纯展示行：无动作、灰色文字、带小图标
    private func makeInfoItem(title: String, systemImageName: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: nil) {
            image.isTemplate = true
            image.size = NSSize(width: 13, height: 13)
            item.image = image
        }
        return item
    }

    private func makeItem(title: String, systemImageName: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: title) {
            image.isTemplate = true
            image.size = NSSize(width: 14, height: 14)
            item.image = image
        }
        return item
    }
    
    @objc private func openMainWindow() {
        statusItem?.menu?.cancelTracking()
        DispatchQueue.main.async {
            MainWindowCoordinator.activateMainWindow()
        }
    }
    
    @objc private func importVideos() {
        wallpaperManager.importVideos(
            presentingIn: appModalHostWindow(),
            context: wallpaperManager.currentImportContext
        )
    }
    
    @objc private func switchWallpaper() {
        guard !wallpaperManager.wallpapers.isEmpty else { return }
        PlaybackCommandMultiplexer.shared.dispatch(.switchNext)
    }

    @objc private func togglePlayback() {
        // 状态栏播放按钮：跨引擎暂停/继续，状态以各引擎处理端为准。
        let command: WallpaperEngineCommand =
            PlaybackCommandMultiplexer.shared.isAnyEnginePlaying
            ? .pause : .resume
        PlaybackCommandMultiplexer.shared.dispatch(command)
        wallpaperManager.isPlaying = PlaybackCommandMultiplexer.shared
            .isAnyEnginePlaying
    }

    @objc private func toggleMute() {
        PlaybackCommandMultiplexer.shared.dispatch(
            .setMuted(!wallpaperManager.isMuted)
        )
    }
    
    @objc private func openSettings() {
        statusItem?.menu?.cancelTracking()
        DispatchQueue.main.async {
            SettingsWindowController.shared.showWindow()
        }
    }

    @objc private func quitApp() {
        let alert = makeAppAlert(
            title: "确定要退出吗？",
            message: "壁纸将停止播放。",
            buttons: ["退出", "取消"]
        )

        presentAppAlert(alert, in: appModalHostWindow()) { response in
            guard response == .alertFirstButtonReturn else { return }
            NSApp.terminate(nil)
        }
    }
}
