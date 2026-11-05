//
//  NSViewExtensions.swift
//  MyWallpaperX
//
//  三模块共用的 NSView 工具扩展，零业务依赖。
//

import AppKit

extension NSView {
    /// 当前视图是否处于深色外观模式。
    var isDarkAppearance: Bool {
        effectiveAppearance
            .bestMatch(from: [.darkAqua, .vibrantDark])
            .map { $0 == .darkAqua || $0 == .vibrantDark } ?? false
    }

}
