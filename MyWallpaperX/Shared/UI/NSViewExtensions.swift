//
//  NSViewExtensions.swift
//  MyWallpaperX
//
//  三模块共用的 NSView 工具扩展，零业务依赖。
//

import AppKit
import QuartzCore

extension NSView {
    /// 当前视图是否处于深色外观模式。
    var isDarkAppearance: Bool {
        effectiveAppearance
            .bestMatch(from: [.darkAqua, .vibrantDark])
            .map { $0 == .darkAqua || $0 == .vibrantDark } ?? false
    }

    /// 将 layer 的 anchorPoint 修正为中心点 (0.5, 0.5)，同时保持 frame 不变。
    /// 为需要围绕中心变换的图层保持稳定的锚点。
    func ensureLayerAnchorCentered() {
        guard let layer, !bounds.isEmpty else { return }
        guard abs(layer.anchorPoint.x - 0.5) > 0.0001
           || abs(layer.anchorPoint.y - 0.5) > 0.0001 else { return }
        let preservedFrame = layer.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = preservedFrame
        CATransaction.commit()
    }
}
