import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import Darwin
import UniformTypeIdentifiers

extension WallpaperDaemon {
    func setupSpectrumLayers() {
        spectrumContainerLayer.zPosition = 50
        spectrumContainerLayer.opacity = 0
        spectrumContainerLayer.masksToBounds = false
        window.contentView?.layer?.addSublayer(spectrumContainerLayer)
        rebuildSpectrumLayers()
        updateSpectrumLayout()
        applySpectrumLevels(animated: false)
    }

    func rebuildSpectrumLayers() {
        spectrumBarLayers.forEach { $0.removeFromSuperlayer() }
        spectrumPeakLayers.forEach { $0.removeFromSuperlayer() }
        spectrumBarLayers.removeAll()
        spectrumPeakLayers.removeAll()
        spectrumLevels = Array(repeating: 0, count: spectrumBarCount)
        spectrumPeakLevels = Array(repeating: 0, count: spectrumBarCount)
        lastRenderedBarHeights = Array(repeating: -1, count: spectrumBarCount)
        lastRenderedBarOpacities = Array(repeating: -1, count: spectrumBarCount)
        lastRenderedPeakY = Array(repeating: -1, count: spectrumBarCount)
        lastRenderedPeakOpacities = Array(repeating: -1, count: spectrumBarCount)

        for _ in 0..<spectrumBarCount {
            let barLayer = CALayer()
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.0)
            barLayer.backgroundColor = spectrumBaseColor.cgColor
            barLayer.cornerRadius = 2
            barLayer.shadowOpacity = 0.18
            barLayer.shadowRadius = 6
            barLayer.shadowOffset = CGSize(width: 0, height: 1)
            barLayer.shadowColor = spectrumShadowColor.cgColor
            spectrumContainerLayer.addSublayer(barLayer)
            spectrumBarLayers.append(barLayer)

            let peakLayer = CALayer()
            peakLayer.anchorPoint = CGPoint(x: 0.5, y: 0.0)
            peakLayer.backgroundColor = spectrumBaseColor.cgColor
            peakLayer.cornerRadius = 1.5
            peakLayer.opacity = 0
            spectrumContainerLayer.addSublayer(peakLayer)
            spectrumPeakLayers.append(peakLayer)
        }
    }

    func applySpectrumConfiguration(from command: DaemonCommand) {
        var requiresLayout = false

        if let barCount = command.spectrumBarCount {
            let normalizedBarCount = max(12, min(48, barCount))
            if normalizedBarCount != spectrumBarCount {
                spectrumBarCount = normalizedBarCount
                rebuildSpectrumLayers()
                requiresLayout = true
            }
        }

        if let colorHex = command.spectrumColorHex {
            spectrumColorHex = colorHex
            let baseColor = nsColor(fromHex: colorHex) ?? NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 1.0)
            let convertedColor = baseColor.usingColorSpace(.deviceRGB) ?? baseColor
            spectrumBaseColor = NSColor(
                calibratedRed: convertedColor.redComponent,
                green: convertedColor.greenComponent,
                blue: convertedColor.blueComponent,
                alpha: 1
            )
            spectrumShadowColor = spectrumBaseColor.withAlphaComponent(0.65)
            for barLayer in spectrumBarLayers {
                barLayer.backgroundColor = spectrumBaseColor.cgColor
                barLayer.shadowColor = spectrumShadowColor.cgColor
            }
            for peakLayer in spectrumPeakLayers {
                peakLayer.backgroundColor = spectrumBaseColor.cgColor
            }
        }
        if let offsetX = command.spectrumOffsetX {
            spectrumOffsetX = CGFloat(max(-0.35, min(0.35, offsetX)))
            requiresLayout = true
        }
        if let offsetY = command.spectrumOffsetY {
            spectrumOffsetY = CGFloat(max(-0.35, min(0.35, offsetY)))
            requiresLayout = true
        }
        if let peakCapsEnabled = command.spectrumPeakCapsEnabled {
            spectrumPeakCapsEnabled = peakCapsEnabled
        }

        if requiresLayout {
            updateSpectrumLayout()
        }
        applySpectrumLevels(animated: false)
    }

    func setSpectrumEnabled(_ enabled: Bool) {
        spectrumEnabled = enabled
        if !enabled {
            spectrumPeakLevels = Array(repeating: 0, count: spectrumBarCount)
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        spectrumContainerLayer.opacity = enabled ? 1 : 0
        CATransaction.commit()
    }

    func updateSpectrumLevels(_ levels: [Float]) {
        if levels.isEmpty {
            spectrumLevels = Array(repeating: 0, count: spectrumBarCount)
        } else if levels.count == spectrumBarCount {
            spectrumLevels = levels.map { min(max($0, 0), 1) }
        } else {
            spectrumLevels = (0..<spectrumBarCount).map { index in
                let scale = Double(levels.count) / Double(spectrumBarCount)
                let sourceIndex = min(levels.count - 1, Int((Double(index) * scale).rounded(.down)))
                return min(max(levels[sourceIndex], 0), 1)
            }
        }
        applySpectrumLevels(animated: true)
    }

    func updateSpectrumLayout() {
        guard let contentBounds = window.contentView?.bounds else { return }
        guard let screen = WallpaperDaemon.screen(for: displayID) else { return }

        let dockInset = max(0, screen.visibleFrame.minY - screen.frame.minY)
        let bottomInset: CGFloat = (dockInset > 0 ? dockInset + 12 : 22) + contentBounds.height * spectrumOffsetY
        let width = min(contentBounds.width * 0.48, 500)
        let height: CGFloat = 56
        let originX = (contentBounds.width - width) / 2 + contentBounds.width * spectrumOffsetX
        spectrumContainerLayer.frame = CGRect(x: originX, y: bottomInset, width: width, height: height)

        let widths = Array(repeating: CGFloat(8.5), count: spectrumBarCount)
        let spacing: CGFloat = 4.5
        let totalBarsWidth = widths.reduce(0, +) + CGFloat(max(0, spectrumBarCount - 1)) * spacing
        let leadingX = max(0, (width - totalBarsWidth) / 2)

        var currentX = leadingX
        for (index, barLayer) in spectrumBarLayers.enumerated() {
            let barWidth = widths[index]
            barLayer.frame = CGRect(x: currentX, y: 0, width: barWidth, height: 4)
            spectrumPeakLayers[index].frame = CGRect(x: currentX, y: 6, width: barWidth, height: 3)
            currentX += barWidth + spacing
        }
    }

    func applySpectrumLevels(animated: Bool) {
        let minimumHeight: CGFloat = 0
        let maximumHeight = max(20, spectrumContainerLayer.bounds.height - 6)
        let visibleLevelThreshold: Float = 0.015

        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.10)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }

        for (index, barLayer) in spectrumBarLayers.enumerated() {
            let level = index < spectrumLevels.count ? spectrumLevels[index] : 0
            let shouldHideBar = !spectrumEnabled || level <= visibleLevelThreshold
            let eased = pow(CGFloat(level), 0.72)
            let height = shouldHideBar ? 0 : (minimumHeight + (maximumHeight - minimumHeight) * eased)
            if abs(lastRenderedBarHeights[index] - height) > 0.35 {
                barLayer.frame = CGRect(x: barLayer.frame.minX, y: 0, width: barLayer.frame.width, height: height)
                let cornerRadius = min(3, barLayer.frame.width * 0.5)
                barLayer.cornerRadius = cornerRadius
                barLayer.shadowPath = height > 0 ? CGPath(
                    roundedRect: barLayer.bounds,
                    cornerWidth: cornerRadius,
                    cornerHeight: cornerRadius,
                    transform: nil
                ) : nil
                lastRenderedBarHeights[index] = height
            }
            let barOpacity = shouldHideBar ? 0 : Float(0.30 + 0.70 * level)
            if abs(lastRenderedBarOpacities[index] - barOpacity) > 0.015 {
                barLayer.opacity = barOpacity
                lastRenderedBarOpacities[index] = barOpacity
            }

            let nextPeakLevel = max(CGFloat(level), max(0, spectrumPeakLevels[index] - 0.03))
            spectrumPeakLevels[index] = nextPeakLevel
            let peakHeight = nextPeakLevel <= CGFloat(visibleLevelThreshold) ? 0 : (minimumHeight + (maximumHeight - minimumHeight) * pow(nextPeakLevel, 0.82))
            let peakLayer = spectrumPeakLayers[index]
            let peakY = peakHeight > 0 ? min(maximumHeight, peakHeight + 2) : 0
            if abs(lastRenderedPeakY[index] - peakY) > 0.35 {
                peakLayer.frame = CGRect(
                    x: peakLayer.frame.minX,
                    y: peakY,
                    width: peakLayer.frame.width,
                    height: 2.5
                )
                peakLayer.cornerRadius = 1.25
                lastRenderedPeakY[index] = peakY
            }
            let peakOpacity = (spectrumEnabled && spectrumPeakCapsEnabled && nextPeakLevel > CGFloat(visibleLevelThreshold)) ? Float(0.5 + 0.4 * nextPeakLevel) : 0
            if abs(lastRenderedPeakOpacities[index] - peakOpacity) > 0.015 {
                peakLayer.opacity = peakOpacity
                lastRenderedPeakOpacities[index] = peakOpacity
            }
        }
        CATransaction.commit()
    }

    func nsColor(fromHex hex: String) -> NSColor? {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard trimmed.count == 6 || trimmed.count == 8 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: trimmed).scanHexInt64(&value) else { return nil }

        let red, green, blue, alpha: CGFloat
        if trimmed.count == 8 {
            red = CGFloat((value & 0xFF00_0000) >> 24) / 255
            green = CGFloat((value & 0x00FF_0000) >> 16) / 255
            blue = CGFloat((value & 0x0000_FF00) >> 8) / 255
            alpha = CGFloat(value & 0x0000_00FF) / 255
        } else {
            red = CGFloat((value & 0xFF0000) >> 16) / 255
            green = CGFloat((value & 0x00FF00) >> 8) / 255
            blue = CGFloat(value & 0x0000FF) / 255
            alpha = 1
        }
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}
