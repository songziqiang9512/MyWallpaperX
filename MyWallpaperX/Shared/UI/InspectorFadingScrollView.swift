//
//  InspectorFadingScrollView.swift
//  MyWallpaperX
//

import AppKit
import QuartzCore

class InspectorFadingScrollView: NSScrollView {
    static let contentTopInset: CGFloat = 8
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
        updateFadeMask()
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateFadeMask()
    }

    private func setupFadeMask() {
        wantsLayer = true
        contentView.wantsLayer = true
        layer?.mask = fadeMask
        fadeMask.locations = [
            0,
            NSNumber(value: Double(fadeRatio)),
            NSNumber(value: Double(1 - fadeRatio)),
            1
        ]
        updateFadeMask()
    }

    private func updateFadeMask() {
        var fadesTop = false
        var fadesBottom = false
        let inset = contentInsets
        var maskFrame = convert(contentView.bounds, from: contentView)
        maskFrame.origin.x += inset.left
        maskFrame.origin.y += isFlipped ? inset.top : inset.bottom
        maskFrame.size.width = max(0, maskFrame.width - inset.left - inset.right)
        maskFrame.size.height = max(0, maskFrame.height - inset.top - inset.bottom)
        if let document = documentView {
            let viewport = document.convert(contentView.bounds, from: contentView)
            let pixel = 0.5 / (window?.backingScaleFactor ?? 1)
            if viewport.height > inset.top + inset.bottom {
                if document.isFlipped {
                    fadesTop = viewport.minY + inset.top > document.bounds.minY + pixel
                    fadesBottom = viewport.maxY - inset.bottom < document.bounds.maxY - pixel
                } else {
                    fadesTop = viewport.maxY - inset.top < document.bounds.maxY - pixel
                    fadesBottom = viewport.minY + inset.bottom > document.bounds.minY + pixel
                }
            }
        }
        // The mask follows the scroll view's physical top, independently of
        // the document's coordinate direction. Header and footer are siblings.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = maskFrame
        fadeMask.startPoint = CGPoint(x: 0.5, y: isFlipped ? 0 : 1)
        fadeMask.endPoint = CGPoint(x: 0.5, y: isFlipped ? 1 : 0)
        fadeMask.colors = [
            fadesTop && fadeRatio > 0 ? NSColor.clear.cgColor : NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            fadesBottom && fadeRatio > 0 ? NSColor.clear.cgColor : NSColor.black.cgColor
        ]
        CATransaction.commit()
    }
}

/// A common document direction makes initial Inspector content start at its top.
final class InspectorContentDocumentView: NSView {
    override var isFlipped: Bool { true }
}
