import AppKit

extension SceneMetalView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
        refreshDisplayOutput()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        metalLayer.frame = bounds
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    @objc func displayPreferenceChanged() {
        SceneHDRDisplayPreference.refresh()
        hdrDisplayRequested = SceneHDRDisplayPreference.isEnabled
        refreshDisplayOutput()
        onRenderInvalidated?(.surface)
    }

    @objc func displayEnvironmentChanged(_ notification: Notification) {
        if let changedWindow = notification.object as? NSWindow, changedWindow !== window { return }
        refreshDisplayOutput()
        onRenderInvalidated?(.surface)
    }

    /// Potential admits the request; current headroom bounds this frame. The
    /// current value can be one before any app has requested EDR content.
    func refreshDisplayOutput() {
        guard usesLinearDisplayOutput else { return }
        let screen = window?.screen
        let potential = screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1
        let enabled = hdrDisplayRequested && potential.isFinite && potential > 1
        if metalLayer.wantsExtendedDynamicRangeContent != enabled {
            metalLayer.wantsExtendedDynamicRangeContent = enabled
        }
        let current = enabled ? Float(screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1) : 1
        let next = SceneDisplayMappingPostProcess.Output.extendedLinearSRGB(headroom: current)
        #if DEBUG
        if displayOutput != next {
            NSLog("MWX Scene display: linear=true requested=%@ enabled=%@ headroom=%.4f potential=%.4f colorspace=%@ format=%lu",
                hdrDisplayRequested ? "true" : "false", enabled ? "true" : "false", next.uniform, potential, metalLayer.colorspace?.name as String? ?? "nil", metalLayer.pixelFormat.rawValue)
        }
        #endif
        displayOutput = next
    }

    func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        metalLayer.contentsScale = scale
        let pixelSize = CGSize(
            width: max(bounds.width, 1) * scale,
            height: max(bounds.height, 1) * scale
        )
        if metalLayer.drawableSize != pixelSize {
            metalLayer.drawableSize = pixelSize
            if (renderer.renderDescriptor.hdrEnabled && !renderer.renderDescriptor.camera.clearEnabled)
                || renderer.hasPreparedReflectionConsumers {
                invalidateResolvedMaterialRuntime(reason: .allocationReprepare)
            }
        }
    }
}
