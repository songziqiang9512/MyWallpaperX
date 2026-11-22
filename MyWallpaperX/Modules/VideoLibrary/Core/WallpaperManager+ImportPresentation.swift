//
//  WallpaperManager+ImportPresentation.swift
//  MyWallpaperX
//

import Foundation
import AppKit

extension WallpaperManager {


    func importFailureBreakdown(
        duplicateCount: Int,
        missingFileCount: Int,
        unreadableFileCount: Int
    ) -> [String] {
        // 失败原因按用户能理解的语言拆行，避免只给一个笼统的“导入失败”。
        var lines: [String] = []

        if duplicateCount > 0 {
            lines.append(String(localized: "\(duplicateCount) files are already in the list"))
        }

        if missingFileCount > 0 {
            lines.append(String(localized: "\(missingFileCount) files are missing"))
        }

        if unreadableFileCount > 0 {
            lines.append(String(localized: "\(unreadableFileCount) files can’t be read"))
        }

        return lines
    }

    func presentImportSummary(_ summary: ImportSummary, in window: NSWindow?) {
        // 导入结果只负责呈现，不在这里再改任何模型状态。
        let alert = makeAppAlert(
            title: String(localized: "Import Results"),
            message: summary.informativeText
        )
        presentAppAlert(alert, in: window ?? appModalHostWindow())
    }
}
