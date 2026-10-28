import AppKit
import QuartzCore

extension AppKitSteamWorkshopBrowserItem {
    /// Local organization actions remain available to the original source menu.
    struct OrganizationPresentation {
        let isFavorite: Bool
        let canFavorite: Bool
        var isPlaying = false
        var isSwitching = false
        var canPlay = true
        var canDownload = true
        var canCancel = true
        var onFavorite: (() -> Void)?
        var onPrimary: (() -> Void)?
    }

    /// Shared appearance instances: `NSAppearance(named:)` was being rebuilt on
    /// every themed pass per card.
    static let darkAppearance = NSAppearance(named: .darkAqua)
    static let lightAppearance = NSAppearance(named: .aqua)

    func refreshTrackingArea() {
        hoverTracking.update(in: view, owner: self)
    }

    func buildHierarchy() {
        view.wantsLayer = true

        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = Layout.cardCornerRadius
        // 裁切到圆角内：修复 bar/进度填充在圆角四角溢出成直角的问题
        //（卡片阴影不透明度仅 0.03，裁切后视觉无感知差异）。
        cardView.layer?.masksToBounds = true
        cardView.layer?.borderWidth = 0.8
        cardView.layer?.shadowColor = NSColor.black.cgColor
        cardView.layer?.shadowOpacity = 0.03
        cardView.layer?.shadowRadius = 7
        cardView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        cardView.appearanceDidChangeHandler = { [weak self] in
            self?.refreshThemeAwareAppearance()
            self?.applyHoverStyle(animated: false)
        }
        view.addSubview(cardView)

        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = Layout.cardCornerRadius
        previewContainer.layer?.masksToBounds = true
        cardView.addSubview(previewContainer)

        hoverOutlineView.wantsLayer = true
        hoverOutlineView.layer?.cornerRadius = Layout.cardCornerRadius
        hoverOutlineView.layer?.borderWidth = 1
        hoverOutlineView.layer?.backgroundColor = NSColor.clear.cgColor
        hoverOutlineView.layer?.masksToBounds = true
        hoverOutlineView.alphaValue = 0
        cardView.addSubview(hoverOutlineView)

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignCenter
        syncPreviewAnimationState()
        previewContainer.addSubview(previewImageView)
        imageView = previewImageView
        previewContainer.addSubview(previewPlaceholderView)

        multiSelectBadgeView.wantsLayer = true
        multiSelectBadgeView.layer?.cornerRadius = 12
        multiSelectBadgeView.layer?.masksToBounds = true
        multiSelectBadgeView.isHidden = true
        cardView.addSubview(multiSelectBadgeView)

        multiSelectBadgeIcon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        multiSelectBadgeIcon.contentTintColor = .white
        multiSelectBadgeIcon.imageScaling = .scaleProportionallyDown
        multiSelectBadgeIcon.isHidden = true
        multiSelectBadgeView.addSubview(multiSelectBadgeIcon)

        controlBar.alphaValue = 0
        controlBar.glass.setAccessibilityElement(true)
        controlBar.glass.setAccessibilityRole(.progressIndicator)
        controlBar.glass.setAccessibilityLabel("下载进度")
        // Keep the shared glass bar detached until the original visibility policy reveals it.
        refreshThemeAwareAppearance()
    }

    /// Inputs that fully determine the themed card chrome. When none of them
    /// move, `refreshThemeAwareAppearance` is a no-op: download ticks re-enter
    /// it several times a second and every pass used to rebuild glass material
    /// state, button chrome and symbol images unconditionally.
    struct ThemedChromeInputs: Equatable {
        let isDarkMode: Bool
        let isHovering: Bool
        let isSelectionHighlighted: Bool
        let isMultiSelectMode: Bool
        let isDownloadsContext: Bool
        let barState: BarState
        let progressFraction: Double?
        let currentBarVisibility: Bool
    }

    func refreshThemeAwareAppearance() {
        guard let layer = cardView.layer else { return }
        let isDarkMode = cardView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let inputs = ThemedChromeInputs(
            isDarkMode: isDarkMode,
            isHovering: isHovering,
            isSelectionHighlighted: isSelectionHighlighted,
            isMultiSelectMode: isMultiSelectMode,
            isDownloadsContext: currentDisplayContext == .downloads,
            barState: currentBarState,
            progressFraction: currentProgressSnapshot?.fraction,
            currentBarVisibility: currentBarVisibility
        )
        guard inputs != lastThemedChromeInputs else { return }
        lastThemedChromeInputs = inputs
        let hoverOutlineColor = NSColor.white.withAlphaComponent(isDarkMode ? 0.56 : 0.72)
        cardView.effectiveAppearance.performAsCurrentDrawingAppearance {
            let selectedOutlineColor = NSColor.controlAccentColor.withAlphaComponent(isDarkMode ? 0.92 : 0.84)
            layer.backgroundColor = NSColor.clear.cgColor
            let ringColor = NSColor.white.withAlphaComponent(isHovering ? 0.12 : 0.028)
            layer.borderColor = ringColor.cgColor
            hoverOutlineView.layer?.borderColor = (isSelectionHighlighted ? selectedOutlineColor : hoverOutlineColor).cgColor
            previewContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.14).cgColor
            multiSelectBadgeView.layer?.backgroundColor = (isSelectionHighlighted
                ? NSColor.controlAccentColor : NSColor.black.withAlphaComponent(0.42)).cgColor
        }
        layer.shadowOpacity = isHovering ? 0.05 : 0.025
        layer.shadowRadius = isHovering ? 7 : 6
        layer.shadowOffset = CGSize(width: 0, height: -1)
        hoverOutlineView.layer?.borderWidth = isSelectionHighlighted ? 1.6 : 1

        let showsSelectionBadge = currentDisplayContext == .downloads && isMultiSelectMode
        multiSelectBadgeView.isHidden = !showsSelectionBadge
        if showsSelectionBadge {
            multiSelectBadgeView.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
            multiSelectBadgeView.layer?.borderWidth = isSelectionHighlighted ? 0 : 1
            multiSelectBadgeIcon.isHidden = !isSelectionHighlighted
        } else {
            multiSelectBadgeIcon.isHidden = true
        }

        let sharedAppearance = isDarkMode ? Self.darkAppearance : Self.lightAppearance
        controlBar.appearance = sharedAppearance
        controlBar.alphaValue = currentBarVisibility ? (isHovering ? 0.92 : 0.84) : 0
        controlBar.glass.layer?.borderWidth = 0.8
        controlBar.glass.layer?.shadowOpacity = 0
        controlBar.layer?.shadowOpacity = currentBarVisibility ? 0.11 : 0.08
        controlBar.layer?.shadowRadius = 18
        controlBar.layer?.shadowOffset = CGSize(width: 0, height: -1)
        let progressFraction = currentProgressSnapshot?.fraction
        let indeterminate = progressFraction == nil && {
            switch currentBarState {
            case .connecting, .preparing, .transferring, .validating:
                return true
            case .idle, .queued, .saving, .waiting, .ready, .failed:
                return false
            }
        }()
        controlBar.glass.applyProgress(
            style: barAccentStyle(for: currentBarState),
            fraction: progressFraction,
            indeterminate: indeterminate,
            animated: false
        )

        updateContinuousAnimationState()
    }

    func updateContinuousAnimationState(barVisible: Bool? = nil) {
        let isBarVisible = (barVisible ?? currentBarVisibility) && isPreviewVisible
        controlBar.setActive(isBarVisible)
        controlBar.glass.setProgressAnimationVisible(isBarVisible)
    }

    func setPreviewVisible(_ visible: Bool) {
        previewState.setImageDemandActive(visible)
        guard isPreviewVisible != visible else { return }
        isPreviewVisible = visible
        updateContinuousAnimationState()
        syncPreviewAnimationState()
    }

    func syncPreviewAnimationState() {
        previewState.setAnimationActive(isPreviewVisible && isHovering)
    }

    func applyPreviewState() {
        previewImageView.image = previewState.image
        previewImageView.animates = previewState.isAnimating
        previewPlaceholderView.setState(previewState.placeholder)
        updatePreviewImageFrame()
    }

    func applyHoverStyle(animated: Bool) {
        view.clipsToBounds = false
        cardView.applyGridHoverScale(isHovering, animated: animated)
        let suppressDownloadsBar = currentDisplayContext == .downloads && isMultiSelectMode
        let shouldRevealBar = !suppressDownloadsBar && (isHovering || shouldPersistBarVisibility)
        let shouldShowOutline = isHovering || isSelectionHighlighted
        barPresentationGeneration &+= 1
        let presentation = barPresentationGeneration
        if shouldRevealBar, controlBar.superview == nil {
            cardView.addSubview(controlBar)
        }
        refreshThemeAwareAppearance()
        let barDuration = shouldRevealBar
            ? UIInteractionAnimation.cardHoverExpandDuration
            : UIInteractionAnimation.cardHoverCollapseDuration
        let barTiming = shouldRevealBar
            ? UIInteractionAnimation.cardEnterTiming
            : UIInteractionAnimation.cardExitTiming

        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            controlBar.alphaValue = shouldRevealBar ? (isHovering ? 0.92 : 0.84) : 0
            controlBar.layer?.transform = CATransform3DMakeTranslation(0, shouldRevealBar ? 0 : 4, 0)
            CATransaction.commit()
            hoverOutlineView.alphaValue = shouldShowOutline ? 1 : 0
            currentBarVisibility = shouldRevealBar
            if !shouldRevealBar { controlBar.removeFromSuperview() }
            isHoverOutlineVisible = shouldShowOutline
            updateContinuousAnimationState(barVisible: shouldRevealBar)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = barDuration
            context.timingFunction = barTiming
            self.cardView.animator().alphaValue = 1
            self.controlBar.animator().alphaValue = shouldRevealBar ? (self.isHovering ? 0.92 : 0.84) : 0
            self.hoverOutlineView.animator().alphaValue = shouldShowOutline ? 1 : 0
        } completionHandler: { [weak self] in
            guard let self, self.barPresentationGeneration == presentation, !self.currentBarVisibility else { return }
            self.controlBar.removeFromSuperview()
        }

        applyBarTransform(isVisible: shouldRevealBar, duration: barDuration, timing: barTiming)
        currentBarVisibility = shouldRevealBar
        isHoverOutlineVisible = shouldShowOutline
        updateContinuousAnimationState(barVisible: shouldRevealBar)
    }

    private func barAccentStyle(for state: BarState) -> WallpaperCardGlassBarView.AccentStyle {
        switch state {
        case .connecting, .preparing, .transferring, .validating, .saving:
            return .downloading
        case .queued:
            return .queued
        case .waiting:
            return .waiting
        case .failed:
            return .failed
        case .ready:
            return currentDisplayContext == .downloads ? .ready : .neutral
        case .idle:
            return .neutral
        }
    }

    private func applyBarTransform(isVisible: Bool, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        guard let layer = controlBar.layer else { return }
        let targetTransform = CATransform3DMakeTranslation(0, isVisible ? 0 : 4, 0)
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = layer.transform
        animation.toValue = targetTransform
        animation.duration = duration
        animation.timingFunction = timing
        layer.add(animation, forKey: "steam.card.bar.transform")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = targetTransform
        CATransaction.commit()
    }

    func loadPreview(from url: URL?, fallbackImageURL: URL? = nil, fallbackVideoURL: URL?) {
        previewState.configure(previewURL: url, fallbackImageURL: fallbackImageURL, fallbackVideoURL: fallbackVideoURL)
    }

    func updatePreviewImageFrame() {
        let containerBounds = previewContainer.bounds
        guard
            containerBounds.width.isFinite,
            containerBounds.height.isFinite,
            containerBounds.width > 0,
            containerBounds.height > 0
        else {
            previewImageView.frame = .zero
            previewPlaceholderView.frame = .zero
            return
        }
        previewPlaceholderView.frame = containerBounds
        guard
            let image = previewImageView.image,
            image.size.width.isFinite,
            image.size.height.isFinite,
            image.size.width > 0,
            image.size.height > 0
        else {
            previewImageView.frame = containerBounds
            return
        }

        let widthScale = containerBounds.width / image.size.width
        let heightScale = containerBounds.height / image.size.height
        let fillScale = max(widthScale, heightScale)
        let fittedWidth = image.size.width * fillScale
        let fittedHeight = image.size.height * fillScale
        guard fittedWidth.isFinite, fittedHeight.isFinite else {
            previewImageView.frame = containerBounds
            return
        }
        previewImageView.frame = CGRect(
            x: floor((containerBounds.width - fittedWidth) * 0.5),
            y: floor((containerBounds.height - fittedHeight) * 0.5),
            width: ceil(fittedWidth),
            height: ceil(fittedHeight)
        )
    }

}
