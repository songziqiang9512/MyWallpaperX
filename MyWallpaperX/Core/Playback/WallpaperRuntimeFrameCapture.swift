import AppKit
import ScreenCaptureKit

/// 产品级壁纸层截帧：为 web 壁纸同步系统壁纸提供一帧画面。
/// web 宿主（WKWebView 窗口）运行在主 App 进程内，壁纸窗口位于
/// `desktopWindow + 1` 层；`SCShareableContent` 的 current-process 变体
/// 只枚举本进程窗口，捕获不需要屏幕录制权限。Scene 表面属 daemon 子
/// 进程，走 SceneDaemonClient 的自截回传通道，不经本类型。
/// 任一环节失败回调 nil，调用方 fail-soft 跳过本次同步（系统壁纸保持
/// 上一次的值）。
enum WallpaperRuntimeFrameCapture {
    static func captureInProcessWallpaperFrame(
        completion: @escaping (NSImage?) -> Void
    ) {
        let wallpaperLevel = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1
        )
        let mainScreenFrame = NSScreen.screens.first?.frame
        let candidates = NSApp.windows.filter { window in
            window.level == wallpaperLevel
                && window.isVisible
                && window.frame.width > 0
                && (mainScreenFrame.map {
                    window.frame.width >= $0.width * 0.9
                        && window.frame.height >= $0.height * 0.9
                } ?? true)
        }
        guard let windowNumber = candidates.first?.windowNumber else {
            completion(nil)
            return
        }
        SCShareableContent.getCurrentProcessShareableContent { content, _ in
            DispatchQueue.main.async {
                guard let content,
                      let scWindow = content.windows.first(where: {
                          $0.windowID == CGWindowID(windowNumber)
                      }) else {
                    completion(nil)
                    return
                }
                let configuration = SCStreamConfiguration()
                configuration.showsCursor = false
                configuration.width = max(1, Int(scWindow.frame.width))
                configuration.height = max(1, Int(scWindow.frame.height))
                SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(
                        desktopIndependentWindow: scWindow
                    ),
                    configuration: configuration
                ) { image, _ in
                    DispatchQueue.main.async {
                        completion(image.map {
                            NSImage(
                                cgImage: $0,
                                size: NSSize(width: $0.width, height: $0.height)
                            )
                        })
                    }
                }
            }
        }
    }
}
