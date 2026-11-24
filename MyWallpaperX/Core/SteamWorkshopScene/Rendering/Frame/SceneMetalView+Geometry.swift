import AppKit

extension SceneMetalView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
        refreshDisplayOutputForScreenChange()
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

    @objc func displayEnvironmentChanged(_ notification: Notification) {
        if let changedWindow = notification.object as? NSWindow, changedWindow !== window { return }
        refreshDisplayOutputForScreenChange()
    }

    func refreshDisplayOutputForScreenChange() {
        if refreshDisplayOutput() { onDisplayOutputChanged?() }
    }

    /// Potential admits the request; current headroom bounds this frame. The
    /// current value can be one before any app has requested EDR content.
    @discardableResult
    func refreshDisplayOutput() -> Bool {
        guard usesLinearDisplayOutput else { return false }
        let screen = window?.screen
        let potential = screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1
        let enabled = hdrDisplayRequested && potential.isFinite && potential > 1
        let changedRequest = metalLayer.wantsExtendedDynamicRangeContent != enabled
        if changedRequest {
            metalLayer.wantsExtendedDynamicRangeContent = enabled
        }
        let current = enabled ? Float(screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1) : 1
        let next = SceneDisplayMappingPostProcess.Output.extendedLinearSRGB(headroom: current)
        let changed = changedRequest || displayOutput != next
        #if DEBUG
        if changed {
            NSLog("MWX Scene display: window=%ld linear=true requested=%@ enabled=%@ headroom=%.4f potential=%.4f colorspace=%@ format=%lu",
                window?.windowNumber ?? 0, hdrDisplayRequested ? "true" : "false", enabled ? "true" : "false",
                next.uniform, potential, metalLayer.colorspace?.name as String? ?? "nil", metalLayer.pixelFormat.rawValue)
        }
        #endif
        displayOutput = next
        return changed
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
            if (renderer.renderDescriptor.persistsSceneColor && !renderer.renderDescriptor.camera.clearEnabled)
                || renderer.hasPreparedReflectionConsumers {
                invalidateResolvedMaterialRuntime(reason: .allocationReprepare)
            } else {
                onRenderInvalidated?()
            }
        }
    }
}
