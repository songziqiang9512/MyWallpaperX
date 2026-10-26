import AppKit
import Foundation
import QuartzCore

/// Real WallpaperDaemon/CALayer lifecycle checks. Call on a fresh daemon before
/// using it for the video-slot tests; no layer or presentation owner is replaced.
enum VideoSpectrumLayerLifecycleChecks {
    static func coldCounts(_ daemon: WallpaperDaemon) -> [String: Int] {
        ["bars": daemon.spectrumBarLayers.count, "peaks": daemon.spectrumPeakLayers.count,
         "children": daemon.spectrumContainerLayer.sublayers?.count ?? 0]
    }

    static func command(_ fields: [String: Any]) -> DaemonCommand {
        var object = fields
        object["action"] = "setSpectrumConfig"
        return try! JSONDecoder().decode(DaemonCommand.self,
            from: JSONSerialization.data(withJSONObject: object))
    }

    static func expectUnmaterialized(_ daemon: WallpaperDaemon) {
        precondition(coldCounts(daemon) == ["bars": 0, "peaks": 0, "children": 0],
            "disabled pre-enable configuration must not construct hidden layers")
        precondition(daemon.lastSpectrumPresentationAt == 0,
            "an empty overlay must not advance a presentation clock")
    }

    static func checkLayout(_ daemon: WallpaperDaemon) {
        let bounds = daemon.window.contentView!.bounds
        let screen = WallpaperDaemon.screen(for: daemon.displayID)!
        let width = min(bounds.width * 0.48, 500)
        let dock = max(0, screen.visibleFrame.minY - screen.frame.minY)
        let expected = CGRect(
            x: (bounds.width - width) / 2 + bounds.width * daemon.spectrumOffsetX,
            y: (dock > 0 ? dock + 12 : 22) + bounds.height * daemon.spectrumOffsetY,
            width: width, height: 88)
        precondition(daemon.spectrumContainerLayer.frame == expected,
            "layout must use the current screen, content bounds and accepted offsets")
        precondition(daemon.spectrumBarLayers.first!.frame.minX >= 0
            && daemon.spectrumBarLayers.last!.frame.maxX <= width + 0.000_001)
        for (bar, peak) in zip(daemon.spectrumBarLayers, daemon.spectrumPeakLayers) {
            precondition(bar.frame.width > 0 && peak.frame.width == bar.frame.width
                && peak.frame.minX == bar.frame.minX)
        }
    }

    static func waitForVisiblePresentation(_ layer: CALayer) {
        let deadline = CACurrentMediaTime() + 2
        repeat {
            CATransaction.flush()
            if let presentation = layer.presentation(), abs(presentation.opacity - 1) < 0.001 { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.002))
        } while CACurrentMediaTime() < deadline
        preconditionFailure("the real layer never presented its enabled opacity")
    }

    static func controlPoints(_ timing: CAMediaTimingFunction) -> [Float] {
        var result: [Float] = []
        for index in 0...3 {
            var point = [Float](repeating: 0, count: 2)
            point.withUnsafeMutableBufferPointer { timing.getControlPoint(at: index, values: $0.baseAddress!) }
            result.append(contentsOf: point)
        }
        return result
    }

    @discardableResult
    static func run(_ daemon: WallpaperDaemon) -> [String: Any] {
        let originalFrame = daemon.window.frame
        defer {
            daemon.setSpectrumEnabled(false)
            daemon.applySpectrumConfiguration(from: command([
                "spectrumBarCount": 28, "spectrumColorHex": "#F4FBFF",
                "spectrumOffsetX": 0, "spectrumOffsetY": 0, "spectrumPeakCapsEnabled": true]))
            daemon.updateSpectrumLevels([])
            daemon.window.setFrame(originalFrame, display: false)
            daemon.updateSpectrumLayout()
            daemon.spectrumContainerLayer.removeAllAnimations()
        }

        expectUnmaterialized(daemon)
        precondition(!daemon.spectrumEnabled && daemon.spectrumContainerLayer.opacity == 0
            && daemon.spectrumContainerLayer.superlayer === daemon.window.contentView!.layer)
        daemon.setSpectrumEnabled(false)
        daemon.applySpectrumConfiguration(from: command(["spectrumBarCount": 0]))
        precondition(daemon.spectrumBarCount == 12)
        expectUnmaterialized(daemon)
        daemon.applySpectrumConfiguration(from: command([
            "spectrumBarCount": 99, "spectrumColorHex": "#2A6BCD",
            "spectrumOffsetX": 0.17, "spectrumOffsetY": -0.12, "spectrumPeakCapsEnabled": false]))
        precondition(daemon.spectrumBarCount == 48 && daemon.spectrumColorHex == "#2A6BCD")
        expectUnmaterialized(daemon)
        daemon.applySpectrumConfiguration(from: command(["spectrumBarCount": 24]))
        daemon.updateSpectrumLevels([0.6])
        precondition(daemon.spectrumLevels == Array(repeating: Float(0.6), count: 24))
        daemon.applySpectrumConfiguration(from: command(["spectrumBarCount": 32]))
        daemon.window.setContentSize(NSSize(width: 960, height: 540))
        daemon.updateLayerFrames()
        daemon.applySpectrumLevels()
        expectUnmaterialized(daemon)

        daemon.setSpectrumEnabled(true)
        let firstBars = daemon.spectrumBarLayers
        let firstPeaks = daemon.spectrumPeakLayers
        precondition(firstBars.count == 32 && firstPeaks.count == 32
            && daemon.spectrumContainerLayer.sublayers?.count == 64)
        precondition(daemon.spectrumLevels == Array(repeating: Float(0.6), count: 32),
            "first materialization must preserve and resample already accepted pending levels")
        checkLayout(daemon)
        for (bar, peak) in zip(firstBars, firstPeaks) {
            precondition(bar.backgroundColor == daemon.spectrumBaseColor.cgColor
                && bar.shadowColor == daemon.spectrumShadowColor.cgColor
                && peak.backgroundColor == daemon.spectrumBaseColor.cgColor,
                "first layers must use the current accepted color")
            precondition(abs(bar.frame.height - 50) < 0.000_01 && bar.opacity > 0,
                "pending audio must produce visible heights immediately")
            precondition(peak.opacity == 0, "accepted caps-disabled state must apply on first enable")
        }
        daemon.setSpectrumEnabled(true)
        precondition(zip(firstBars, daemon.spectrumBarLayers).allSatisfy { $0 === $1 }
            && zip(firstPeaks, daemon.spectrumPeakLayers).allSatisfy { $0 === $1 },
            "repeated enable must keep the existing layer objects")

        daemon.applySpectrumConfiguration(from: command(["spectrumPeakCapsEnabled": true]))
        daemon.updateSpectrumLevels([0.8])
        precondition(daemon.spectrumPeakLayers.allSatisfy { $0.opacity > 0 }
            && daemon.spectrumPeakLevels.allSatisfy { $0 > 0 })
        waitForVisiblePresentation(daemon.spectrumContainerLayer)
        daemon.spectrumContainerLayer.removeAllAnimations()
        daemon.setSpectrumEnabled(false)
        CATransaction.flush()
        precondition(daemon.spectrumContainerLayer.opacity == 0
            && daemon.spectrumPeakLevels.allSatisfy { $0 == 0 })
        guard let fade = daemon.spectrumContainerLayer.animation(forKey: "opacity") as? CABasicAnimation,
              let timing = fade.timingFunction else {
            preconditionFailure("warm disable must schedule the real opacity fade")
        }
        precondition(abs(fade.duration - 0.18) < 0.000_001
            && controlPoints(timing) == controlPoints(CAMediaTimingFunction(name: .easeInEaseOut)),
            "the existing 0.18 second disable fade must remain")
        precondition(zip(firstBars, daemon.spectrumBarLayers).allSatisfy { $0 === $1 }
            && zip(firstPeaks, daemon.spectrumPeakLayers).allSatisfy { $0 === $1 },
            "disable must retain warm objects")
        daemon.setSpectrumEnabled(true)
        daemon.applySpectrumConfiguration(from: command(["spectrumPeakCapsEnabled": false]))
        precondition(daemon.spectrumPeakLayers.allSatisfy { $0.opacity == 0 })
        daemon.applySpectrumConfiguration(from: command(["spectrumPeakCapsEnabled": true]))
        precondition(daemon.spectrumPeakLayers.allSatisfy { $0.opacity > 0 })
        daemon.updateSpectrumLevels([])
        precondition(daemon.spectrumLevels.allSatisfy { $0 == 0 }
            && daemon.spectrumPeakLevels.allSatisfy { $0 == 0 }
            && daemon.spectrumBarLayers.allSatisfy { $0.frame.height == 0 && $0.opacity == 0 }
            && daemon.spectrumPeakLayers.allSatisfy { $0.opacity == 0 },
            "a single silence frame must clear bars and lingering caps")

        daemon.applySpectrumConfiguration(from: command(["spectrumBarCount": 99]))
        precondition(daemon.spectrumBarCount == 48 && coldCounts(daemon)["children"] == 96)
        precondition(firstBars.allSatisfy { $0.superlayer == nil }
            && firstPeaks.allSatisfy { $0.superlayer == nil }, "warm count replaces old objects")
        precondition(daemon.spectrumLevels.allSatisfy { $0 == 0 }, "warm count keeps the original level reset")
        daemon.applySpectrumConfiguration(from: command(["spectrumBarCount": 0]))
        precondition(daemon.spectrumBarCount == 12 && coldCounts(daemon)["children"] == 24)
        daemon.updateSpectrumLevels([-1, 0.4, 2])
        precondition(daemon.spectrumLevels == Array(repeating: Float(0), count: 4)
            + Array(repeating: Float(0.4), count: 4) + Array(repeating: Float(1), count: 4),
            "warm count keeps existing level clamping and resampling")
        let warmBars = daemon.spectrumBarLayers
        daemon.window.setContentSize(NSSize(width: 800, height: 450))
        daemon.updateLayerFrames()
        checkLayout(daemon)
        precondition(zip(warmBars, daemon.spectrumBarLayers).allSatisfy { $0 === $1 }
            && daemon.spectrumBarLayers[4].frame.height > 2,
            "warm resize relayouts the same objects and reapplies current audio")
        daemon.setSpectrumEnabled(false)
        daemon.applySpectrumConfiguration(from: command(["spectrumBarCount": 28]))
        precondition(coldCounts(daemon) == ["bars": 28, "peaks": 28, "children": 56],
            "after materialization hidden count changes retain the original warm lifecycle")
        return ["cold": ["bars": 0, "peaks": 0, "children": 0],
            "firstMaterialized": ["bars": firstBars.count, "peaks": firstPeaks.count],
            "warmFinal": coldCounts(daemon), "pendingPreserved": true, "identityStable": true,
            "disableFadeSeconds": fade.duration, "zeroClearsCaps": true]
    }
}
