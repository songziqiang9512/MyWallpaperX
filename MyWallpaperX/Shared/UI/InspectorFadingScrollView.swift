//
//  InspectorFadingScrollView.swift
//  MyWallpaperX
//

import AppKit
import QuartzCore

class InspectorFadingScrollView: NSScrollView {
    private let fadeMask = CAGradientLayer()
    private let fadeRatio: CGFloat

    init(fadeRatio: CGFloat = 0.035) {
        self.fadeRatio = fadeRatio
        super.init(frame: .zero)
        setupFadeMask()
    }

    override init(frame frameRect: NSRect) {
        self.fadeRatio = 0.035
        super.init(frame: frameRect)
        setupFadeMask()
    }

    required init?(coder: NSCoder) {
        self.fadeRatio = 0.035
        super.init(coder: coder)
        setupFadeMask()
    }

    override func layout() {
        super.layout()
        fadeMask.frame = bounds
    }

    private func setupFadeMask() {
        wantsLayer = true
        contentView.wantsLayer = true
        fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        fadeMask.colors = [
            NSColor.clear.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.clear.cgColor
        ]
        layer?.mask = fadeMask
        fadeMask.locations = [
            0,
            NSNumber(value: Double(fadeRatio)),
            NSNumber(value: Double(1 - fadeRatio)),
            1
        ]
    }
}
