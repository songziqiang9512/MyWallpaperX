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
            barLayer.shadowOpacity = 0.12
            barLayer.shadowRadius = 1.5
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
        } else {
            applySpectrumLevels()
        }
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
        if spectrumLevels.allSatisfy({ $0 == 0 }) {
            // Capture revocation can be a single zero frame followed by no ticks.
            spectrumPeakLevels = Array(repeating: 0, count: spectrumBarCount)
        }
        applySpectrumLevels()
    }

    func updateSpectrumLayout() {
        guard let contentBounds = window.contentView?.bounds else { return }
        guard let screen = WallpaperDaemon.screen(for: displayID) else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let dockInset = max(0, screen.visibleFrame.minY - screen.frame.minY)
        let bottomInset: CGFloat = (dockInset > 0 ? dockInset + 12 : 22) + contentBounds.height * spectrumOffsetY
        let width = min(contentBounds.width * 0.48, 500)
        let height: CGFloat = 88
        let originX = (contentBounds.width - width) / 2 + contentBounds.width * spectrumOffsetX
        spectrumContainerLayer.frame = CGRect(x: originX, y: bottomInset, width: width, height: height)

        let pitch = min(13, width / CGFloat(spectrumBarCount))
        let barWidth = pitch * (8.5 / 13)
        let spacing = pitch - barWidth
        let totalBarsWidth = CGFloat(spectrumBarCount) * barWidth + CGFloat(spectrumBarCount - 1) * spacing
        let leadingX = (width - totalBarsWidth) / 2

        lastRenderedBarHeights = Array(repeating: -1, count: spectrumBarCount)
        lastRenderedPeakY = Array(repeating: -1, count: spectrumBarCount)
        var currentX = leadingX
        for (index, barLayer) in spectrumBarLayers.enumerated() {
            barLayer.frame = CGRect(x: currentX, y: 0, width: barWidth, height: 4)
            spectrumPeakLayers[index].frame = CGRect(x: currentX, y: 6, width: barWidth, height: 3)
            currentX += barWidth + spacing
        }
        // Video readiness and display changes also call layout without a later
        // audio tick. Restore current heights/caps immediately in that path.
        applySpectrumLevels()
    }

    func applySpectrumLevels() {
        let minimumHeight: CGFloat = 2
        let maximumHeight = max(20, spectrumContainerLayer.bounds.height - 6)
        let hasActiveSpectrum = spectrumEnabled && spectrumLevels.contains { $0 > 0 }

        let now = CACurrentMediaTime()
        let elapsed = lastSpectrumPresentationAt > 0 ? max(0, now - lastSpectrumPresentationAt) : 0
        lastSpectrumPresentationAt = now
        CATransaction.begin()
        // The shared producer already owns the envelope. Implicit 100ms layer
        // animations would add another tail and hide independent transients.
        CATransaction.setDisableActions(true)

        for (index, barLayer) in spectrumBarLayers.enumerated() {
            let level = index < spectrumLevels.count ? spectrumLevels[index] : 0
            let shouldHideBar = !hasActiveSpectrum
            let height = shouldHideBar ? 0 : (minimumHeight + (maximumHeight - minimumHeight) * CGFloat(level))
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

            let nextPeakLevel = max(CGFloat(level), max(0, spectrumPeakLevels[index] - CGFloat(elapsed) * 0.9))
            spectrumPeakLevels[index] = nextPeakLevel
            let peakHeight = nextPeakLevel <= 0 ? 0 : (minimumHeight + (maximumHeight - minimumHeight) * nextPeakLevel)
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
            let peakOpacity = (spectrumEnabled && spectrumPeakCapsEnabled && nextPeakLevel > 0) ? Float(0.5 + 0.4 * nextPeakLevel) : 0
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
