import AppKit
import ScreenCaptureKit

/// 产品级壁纸层截帧：为同步系统壁纸提供一帧画面。
/// 壁纸窗口（web 宿主或 Scene 表面）都位于 `desktopWindow + 1` 层且
/// 铺满屏幕；`SCShareableContent` 的 current-process 变体只枚举本进程
/// 窗口，捕获不需要屏幕录制权限。Web/Scene 表面都属独立播放进程，由各自的
/// captureFrame 命令处理复用本类型。Scene daemon 侧的
/// captureFrame 命令处理复用同一候选过滤与 SCK 流程。任一环节失败
/// 回调 nil，调用方 fail-soft 跳过本次同步（系统壁纸保持上一次的值）。
enum WallpaperRuntimeFrameCapture {
    /// 壁纸表面候选过滤的唯一实现：desktopWindow+1 层、可见、基本铺满
    /// 主屏的 NSApp 窗口。Web 与 Scene 播放进程共用。
    static func mainSurfaceWindowNumber() -> Int? {
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
        return candidates.first?.windowNumber
    }

    /// 截取本进程壁纸表面一帧（CGImage）。SCK 异步链全程回调主线程。
    static func captureWallpaperWindowCGImage(
        completion: @escaping (CGImage?) -> Void
    ) {
        guard let windowNumber = mainSurfaceWindowNumber() else {
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
                        completion(image)
                    }
                }
            }
        }
    }

}
