//
//  WallpaperManager+ImportPresentation.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import UniformTypeIdentifiers

extension WallpaperManager {
    func reportMigrationReadOnly(in window: NSWindow? = nil) {
        guard let migrationRecoveryMessage else { return }
        let alert = makeAppAlert(title: "资料库需要恢复",
            message: migrationRecoveryMessage + "\n仍可浏览和播放，恢复资料库后再导入或整理。",
            style: .warning, buttons: ["知道了"])
        presentAppAlert(alert, in: window)
    }

    func importVideos(presentingIn window: NSWindow? = nil, context: ImportContext = .library) {
        guard allowsLibraryMutation else { reportMigrationReadOnly(in: window ?? appModalHostWindow()); return }
        // 这个入口只负责“选文件 + 启动导入”，真正的数据处理交给 ImportProcessing。
        let panel = makeImportOpenPanel()
        let hostWindow = window ?? appModalHostWindow()

        let handleSelection: ([URL]) -> Void = { [weak self] urls in
            self?.processImportedVideos(from: urls, presentingIn: hostWindow, context: context)
        }

        if let hostWindow {
            panel.beginSheetModal(for: hostWindow) { response in
                guard response == .OK else { return }
                handleSelection(panel.urls)
            }
            return
        }

        guard panel.runModal() == .OK else { return }
        handleSelection(panel.urls)
    }

    func importFailureBreakdown(
        duplicateCount: Int,
        missingFileCount: Int,
        unreadableFileCount: Int
    ) -> [String] {
        // 失败原因按用户能理解的语言拆行，避免只给一个笼统的“导入失败”。
        var lines: [String] = []

        if duplicateCount > 0 {
            lines.append("\(duplicateCount) 个文件已存在于列表中")
        }

        if missingFileCount > 0 {
            lines.append("\(missingFileCount) 个文件不存在")
        }

        if unreadableFileCount > 0 {
            lines.append("\(unreadableFileCount) 个文件无法读取")
        }

        return lines
    }

    func presentImportSummary(_ summary: ImportSummary, in window: NSWindow?) {
        // 导入结果只负责呈现，不在这里再改任何模型状态。
        let alert = makeAppAlert(
            title: "导入结果",
            message: summary.informativeText
        )
        presentAppAlert(alert, in: window ?? appModalHostWindow())
    }

    private func makeImportOpenPanel() -> NSOpenPanel {
        // 面板只负责选择视频文件，不允许目录导入，避免误选一整层非视频文件夹。
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        return panel
    }
}
