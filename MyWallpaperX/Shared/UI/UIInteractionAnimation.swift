//
//  UIInteractionAnimation.swift
//  MyWallpaperX
//

import AppKit

enum UIInteractionAnimation {
    static let cardHoverExpandDuration: CFTimeInterval = 0.30
    static let cardHoverCollapseDuration: CFTimeInterval = 0.34

    static let sidebarReorderDuration: CFTimeInterval = 0.10
    static let minimumPressVisualDuration: TimeInterval = 0.05
    static let selectionFadeDuration: CFTimeInterval = 0.12

    static let cardEnterTiming = CAMediaTimingFunction(controlPoints: 0.22, 0.86, 0.26, 1.0)
    static let cardExitTiming = CAMediaTimingFunction(controlPoints: 0.26, 0.64, 0.30, 1.0)
    static let sidebarReorderTiming = CAMediaTimingFunction(controlPoints: 0.22, 0.86, 0.26, 1.0)
    static let selectionTiming = CAMediaTimingFunction(name: .easeInEaseOut)
}
