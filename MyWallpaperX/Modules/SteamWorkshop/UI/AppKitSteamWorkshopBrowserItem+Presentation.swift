import AppKit
import QuartzCore

extension AppKitSteamWorkshopBrowserItem {
    /// Shared appearance instances: `NSAppearance(named:)` was being rebuilt on
    /// every themed pass per card.
    static let darkAppearance = NSAppearance(named: .darkAqua)
    static let lightAppearance = NSAppearance(named: .aqua)

    func metrics(for cardSize: CGSize) -> Metrics {
        let scale = max(0.68, min(1.18, cardSize.width / Layout.referenceCardWidth))
        return Metrics(
            scale: scale,
            barHorizontalInset: round(Layout.barHorizontalInset * scale),
            barBottomInset: round(Layout.barBottomInset * scale),
            barHeight: round(Layout.barHeight * scale),
            iconButtonSize: round(Layout.iconButtonSize * scale),
            badgeSize: round(Layout.statusBadgeSize * scale),
            barEdgeInset: round(Layout.barEdgeInset * scale),
            barSpacing: round(Layout.barSpacing * scale),
            marqueeSideInset: round(Layout.marqueeSideInset * scale),
            titleFont: .systemFont(ofSize: 12.5 * scale, weight: .medium),
            buttonCornerRadius: max(8, min(12, 11 * scale))
        )
    }

    func applyMetrics(_ metrics: Metrics) {
        let targetBarRadius = max(
            8,
            min(Layout.cardCornerRadius, floor((metrics.barHeight - Layout.minBarCornerInset) * 0.5))
        )
        if abs((overlayBar.layer?.cornerRadius ?? 0) - targetBarRadius) > 0.001 {
            overlayBar.layer?.cornerRadius = targetBarRadius
        }
        overlayBarShadowView.layer?.cornerRadius = targetBarRadius
        overlayBarShadowView.layer?.shadowPath = CGPath(
            roundedRect: overlayBarShadowView.bounds,
            cornerWidth: targetBarRadius,
            cornerHeight: targetBarRadius,
            transform: nil
        )
        let targetButtonRadius = max(8, min(12, Layout.cardCornerRadius - 1))
        if abs(detailButton.cornerRadius - targetButtonRadius) > 0.001 {
            detailButton.cornerRadius = targetButtonRadius
        }
        let targetBadgeRadius = prefersCircularPlayBadge
            ? floor(metrics.badgeSize * 0.5)
            : targetButtonRadius
        if abs(statusBadgeButton.cornerRadius - targetBadgeRadius) > 0.001 {
            statusBadgeButton.cornerRadius = targetBadgeRadius
        }
        if abs(titleMarqueeView.font.pointSize - metrics.titleFont.pointSize) > 0.001 {
            titleMarqueeView.font = metrics.titleFont
        }
        let overlaySymbolConfig = NSImage.SymbolConfiguration(pointSize: max(11, metrics.iconButtonSize * 0.56), weight: .medium)
        detailButton.contentTintColor = detailButton.iconTintColor
        detailButton.image = detailButton.image?.withSymbolConfiguration(overlaySymbolConfig)
        statusBadgeButton.image = statusBadgeButton.image?.withSymbolConfiguration(overlaySymbolConfig)
    }

    func refreshTrackingArea() {
        if let trackingAreaRef {
            view.removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
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

        overlayBarShadowView.wantsLayer = true
        overlayBarShadowView.layer?.backgroundColor = NSColor.clear.cgColor
        overlayBarShadowView.layer?.shadowColor = NSColor.black.cgColor
        overlayBarShadowView.layer?.shadowOpacity = 0.16
        overlayBarShadowView.layer?.shadowRadius = 20
        overlayBarShadowView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        cardView.addSubview(overlayBarShadowView)

        overlayBar.alphaValue = 0
        overlayBar.wantsLayer = true
        overlayBar.setAccessibilityElement(true)
        overlayBar.setAccessibilityRole(.progressIndicator)
        overlayBar.setAccessibilityLabel("下载进度")
        cardView.addSubview(overlayBar)

        detailButton.image = NSImage(systemSymbolName: "heart", accessibilityDescription: "订阅")
        detailButton.target = self
        detailButton.action = #selector(handleSubscribeToggle)
        overlayBar.addSubview(detailButton)

        overlayBar.addSubview(titleMarqueeView)

        statusBadgeButton.target = self
        statusBadgeButton.action = #selector(handleStatusAction)
        overlayBar.addSubview(statusBadgeButton)


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
        let isDarkMode = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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
        let fixedForeground = isDarkMode
            ? NSColor(calibratedWhite: 1.0, alpha: 0.98)
            : NSColor(calibratedWhite: 0.08, alpha: 0.92)
        let hoverOutlineColor = NSColor.white.withAlphaComponent(isDarkMode ? 0.56 : 0.72)
        let selectedOutlineColor = NSColor.controlAccentColor.withAlphaComponent(isDarkMode ? 0.92 : 0.84)

        layer.backgroundColor = NSColor.clear.cgColor
        let ringColor: NSColor
        if isHovering {
            ringColor = NSColor.white.withAlphaComponent(0.12)
        } else {
            ringColor = NSColor.white.withAlphaComponent(0.028)
        }
        layer.borderColor = ringColor.cgColor
        layer.shadowOpacity = isHovering ? 0.05 : 0.025
        layer.shadowRadius = isHovering ? 7 : 6
        layer.shadowOffset = CGSize(width: 0, height: -1)
        hoverOutlineView.layer?.borderColor = (isSelectionHighlighted ? selectedOutlineColor : hoverOutlineColor).cgColor
        hoverOutlineView.layer?.borderWidth = isSelectionHighlighted ? 1.6 : 1

        previewContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.14).cgColor

        let showsSelectionBadge = currentDisplayContext == .downloads && isMultiSelectMode
        multiSelectBadgeView.isHidden = !showsSelectionBadge
        if showsSelectionBadge {
            multiSelectBadgeView.layer?.backgroundColor = isSelectionHighlighted
                ? NSColor.controlAccentColor.cgColor
                : NSColor.black.withAlphaComponent(0.42).cgColor
            multiSelectBadgeView.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
            multiSelectBadgeView.layer?.borderWidth = isSelectionHighlighted ? 0 : 1
            multiSelectBadgeIcon.isHidden = !isSelectionHighlighted
        } else {
            multiSelectBadgeIcon.isHidden = true
        }

        let sharedAppearance = isDarkMode ? Self.darkAppearance : Self.lightAppearance
        overlayBar.appearance = sharedAppearance
        overlayBar.alphaValue = currentBarVisibility ? (isHovering ? 0.92 : 0.84) : 0
        overlayBar.layer?.borderWidth = 0.8
        overlayBar.layer?.shadowOpacity = 0
        overlayBarShadowView.layer?.shadowOpacity = currentBarVisibility ? 0.11 : 0.08
        overlayBarShadowView.layer?.shadowRadius = 18
        overlayBarShadowView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        let progressFraction = currentProgressSnapshot?.fraction
        let indeterminate = progressFraction == nil && {
            switch currentBarState {
            case .connecting, .preparing, .transferring, .validating:
                return true
            case .idle, .queued, .saving, .waiting, .ready, .failed:
                return false
            }
        }()
        overlayBar.applyProgress(
            style: barAccentStyle(for: currentBarState),
            fraction: progressFraction,
            indeterminate: indeterminate,
            animated: false
        )

        detailButton.normalBackgroundColor = .clear
        detailButton.hoverBackgroundColor = .clear
        detailButton.pressedBackgroundColor = .clear
        detailButton.iconTintColor = fixedForeground
        detailButton.borderColor = .clear
        detailButton.borderWidth = 0
        detailButton.appearance = overlayBar.appearance

        titleMarqueeView.textColor = fixedForeground
        titleMarqueeView.appearance = overlayBar.appearance

        statusBadgeButton.normalBackgroundColor = .clear
        statusBadgeButton.hoverBackgroundColor = .clear
        statusBadgeButton.pressedBackgroundColor = .clear
        statusBadgeButton.borderColor = .clear
        statusBadgeButton.borderWidth = 0
        statusBadgeButton.iconTintColor = fixedForeground
        statusBadgeButton.appearance = overlayBar.appearance
        refreshSubscribeHeart()
        updateContinuousAnimationState()
    }

    func updateContinuousAnimationState(barVisible: Bool? = nil) {
        let isBarVisible = barVisible ?? currentBarVisibility
        titleMarqueeView.setActive(isBarVisible)
        overlayBar.setProgressAnimationVisible(isBarVisible)
    }

    func setPreviewVisible(_ visible: Bool) {
        guard isPreviewVisible != visible else { return }
        isPreviewVisible = visible
        syncPreviewAnimationState()
    }

    func syncPreviewAnimationState() {
        // 列表缩略图默认静态帧：进窗可见（isPreviewVisible）只解锁资格，
        // 悬停才真正播放动画。一张动画 GIF 是一个主线程定时器驱动的
        // 帧序列，整屏可见卡片同时播放会让浏览明显掉帧；详情面板的
        // 常驻动画由 SteamWorkshopPreviewImageContainerView 自持，不经
        // 此开关。共享缓存里只有静态首帧；hover 动画源由
        // syncHoverAnimationState 按需临时加载。
        previewImageView.animates = isPreviewVisible && isHovering
        syncHoverAnimationState()
    }

    /// Hover 动画源装载：进入卡片时把共享缓存里的静态首帧临时换成动画
    /// GIF（不进共享内存缓存，随 hover 结束释放）；离开时立即恢复静态帧。
    private func syncHoverAnimationState() {
        guard isPreviewVisible, isHovering, let url = currentPreviewURL else {
            cancelHoverAnimation()
            return
        }
        let generation = hoverAnimationGeneration
        // 同一 URL 的动画源已在位则不重复加载。
        if previewImageView.image === currentAnimatedPreviewImage { return }
        let cacheKey = url.isFileURL
            ? steamWorkshopLocalPreviewCacheKey(for: url)
            : steamWorkshopPreviewCacheKey(for: url)
        steamWorkshopLoadAnimatedPreview(from: url, cacheKey: cacheKey) { [weak self] animatedImage in
            guard let self else { return }
            // 不在此推进代数：快速 out-in 时先到的过期回调会误杀后到的
            // 有效回调。守卫只读代数，过期由 cancelHoverAnimation/重入推进。
            guard self.hoverAnimationGeneration == generation,
                  self.isHovering, self.isPreviewVisible,
                  self.currentPreviewURL == url,
                  let animatedImage else { return }
            self.currentAnimatedPreviewImage = animatedImage
            self.previewImageView.image = animatedImage
            self.previewImageView.animates = true
            self.updatePreviewImageFrame()
        }
    }

    private func cancelHoverAnimation() {
        hoverAnimationGeneration += 1
        guard currentAnimatedPreviewImage != nil else { return }
        currentAnimatedPreviewImage = nil
        // 恢复共享缓存里的静态首帧。
        if let url = currentPreviewURL {
            let cacheKey = url.isFileURL
                ? steamWorkshopLocalPreviewCacheKey(for: url)
                : steamWorkshopPreviewCacheKey(for: url)
            if let staticImage = SteamWorkshopPreviewImageCache.shared.cachedImage(forKey: cacheKey) {
                previewImageView.image = staticImage
                updatePreviewImageFrame()
                return
            }
        }
        previewImageView.image = nil
    }

    func applyHoverStyle(animated: Bool) {
        let suppressDownloadsBar = currentDisplayContext == .downloads && isMultiSelectMode
        let shouldRevealBar = !suppressDownloadsBar && (isHovering || shouldPersistBarVisibility)
        let shouldShowOutline = isHovering || isSelectionHighlighted
        let targetScale: CGFloat
        if isHovering {
            targetScale = isPressingCard ? Self.pressedScale : Self.hoverScale
        } else {
            targetScale = 1.0
        }

        refreshThemeAwareAppearance()
        let cardDuration = isHovering
            ? UIInteractionAnimation.cardHoverExpandDuration
            : UIInteractionAnimation.cardHoverCollapseDuration
        let cardTiming = isHovering
            ? UIInteractionAnimation.cardEnterTiming
            : UIInteractionAnimation.cardExitTiming
        let barDuration = shouldRevealBar
            ? UIInteractionAnimation.cardHoverExpandDuration
            : UIInteractionAnimation.cardHoverCollapseDuration
        let barTiming = shouldRevealBar
            ? UIInteractionAnimation.cardEnterTiming
            : UIInteractionAnimation.cardExitTiming

        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cardView.layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
            overlayBar.alphaValue = shouldRevealBar ? (isHovering ? 0.92 : 0.84) : 0
            overlayBar.layer?.transform = CATransform3DMakeTranslation(0, shouldRevealBar ? 0 : 4, 0)
            CATransaction.commit()
            hoverOutlineView.alphaValue = shouldShowOutline ? 1 : 0
            currentCardScale = targetScale
            currentBarVisibility = shouldRevealBar
            isHoverOutlineVisible = shouldShowOutline
            updateContinuousAnimationState(barVisible: shouldRevealBar)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = barDuration
            context.timingFunction = barTiming
            self.cardView.animator().alphaValue = 1
            self.overlayBar.animator().alphaValue = shouldRevealBar ? (self.isHovering ? 0.92 : 0.84) : 0
            self.hoverOutlineView.animator().alphaValue = shouldShowOutline ? 1 : 0
        }

        applyCardTransform(targetScale: targetScale, duration: cardDuration, timing: cardTiming)
        applyBarTransform(isVisible: shouldRevealBar, duration: barDuration, timing: barTiming)
        currentBarVisibility = shouldRevealBar
        isHoverOutlineVisible = shouldShowOutline
        updateContinuousAnimationState(barVisible: shouldRevealBar)
    }

    private func barAccentStyle(for state: BarState) -> SteamWorkshopGlassBarView.AccentStyle {
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

    func applyPressedState(_ pressed: Bool) {
        guard isPressingCard != pressed else { return }
        isPressingCard = pressed
        guard isHovering else { return }
        guard !(currentDisplayContext == .downloads && isMultiSelectMode) else { return }
        applyCardTransform(
            targetScale: pressed ? Self.pressedScale : Self.hoverScale,
            duration: pressed ? UIInteractionAnimation.cardPressDownDuration : UIInteractionAnimation.cardPressUpDuration,
            timing: pressed ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
        )
    }

    private func applyCardTransform(targetScale: CGFloat, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        guard let layer = cardView.layer else { return }
        ensureCardAnchorCenteredIfNeeded()
        guard abs(currentCardScale - targetScale) > 0.001 else { return }
        let fromScale = (layer.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat) ?? currentCardScale
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = fromScale
        animation.toValue = targetScale
        animation.duration = duration
        animation.timingFunction = timing
        layer.add(animation, forKey: "steam.card.hover.scale")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
        currentCardScale = targetScale
    }

    private func applyBarTransform(isVisible: Bool, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        guard let layer = overlayBar.layer else { return }
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

    func loadPreview(from url: URL?, fallbackVideoURL: URL?) {
        let requestURL = url ?? fallbackVideoURL
        if currentPreviewURL == requestURL {
            if previewImageView.image != nil || isPreviewLoadInFlight {
                return
            }
        }
        currentPreviewURL = requestURL
        isPreviewLoadInFlight = false
        previewLoadCancellation?.cancel()
        previewLoadCancellation = nil
        previewRetryTask?.cancel()

        if let url, url.isFileURL {
            loadLocalPreview(from: url, fallbackVideoURL: fallbackVideoURL)
            return
        }

        guard let url else {
            if let fallbackVideoURL {
                loadGeneratedDownloadPreview(from: fallbackVideoURL)
                return
            }
            previewImageView.image = nil
            previewPlaceholderView.setState(.unavailable)
            updatePreviewImageFrame()
            return
        }

        let cacheKey = steamWorkshopPreviewCacheKey(for: url)
        let bypassesCachedImage = SteamWorkshopPreviewRequestCoordinator.shared.shouldBypassCachedImage(forKey: cacheKey)
        if !bypassesCachedImage,
           let cached = SteamWorkshopPreviewImageCache.shared.cachedImage(forKey: cacheKey),
           steamWorkshopPreviewImageIsUsable(cached) {
            previewImageView.image = cached
            syncPreviewAnimationState()
            previewPlaceholderView.setState(.hidden)
            SteamWorkshopPreviewRequestCoordinator.shared.clearCachedImageSuspicion(forKey: cacheKey)
            updatePreviewImageFrame()
            return
        }
        if let cached = SteamWorkshopPreviewImageCache.shared.cachedImage(forKey: cacheKey),
           !steamWorkshopPreviewImageIsUsable(cached) {
            SteamWorkshopPreviewRequestCoordinator.shared.markCachedImageSuspicious(forKey: cacheKey)
        }

        previewImageView.image = nil
        previewPlaceholderView.setState(.loading)
        updatePreviewImageFrame()
        loadPreviewImage(url: url, cacheKey: cacheKey, bypassingCache: bypassesCachedImage)
    }

    private func loadLocalPreview(from localURL: URL, fallbackVideoURL: URL?) {
        let cacheKey = steamWorkshopLocalPreviewCacheKey(for: localURL)
        if let image = SteamWorkshopPreviewImageCache.shared.cachedImage(forKey: cacheKey) {
            previewImageView.image = image
            syncPreviewAnimationState()
            previewPlaceholderView.setState(.hidden)
            updatePreviewImageFrame()
            return
        }

        previewImageView.image = nil
        previewPlaceholderView.setState(.loading)
        updatePreviewImageFrame()
        isPreviewLoadInFlight = true
        steamWorkshopLoadLocalPreviewImage(from: localURL) { [weak self] image in
            guard let self, self.currentPreviewURL == localURL else { return }
            self.isPreviewLoadInFlight = false
            if let image {
                self.previewImageView.image = image
                self.syncPreviewAnimationState()
                self.previewPlaceholderView.setState(.hidden)
            } else if let fallbackVideoURL {
                self.loadGeneratedDownloadPreview(from: fallbackVideoURL)
                return
            } else {
                self.previewImageView.image = nil
                self.previewPlaceholderView.setState(.unavailable)
            }
            self.updatePreviewImageFrame()
        }
    }

    private func loadGeneratedDownloadPreview(from videoURL: URL) {
        let expectedPreviewURL = currentPreviewURL
        if let cached = SteamWorkshopDownloadThumbnailPipeline.shared.cachedThumbnail(for: videoURL) {
            previewImageView.image = cached
            previewPlaceholderView.setState(.hidden)
            updatePreviewImageFrame()
            return
        }

        previewImageView.image = nil
        previewPlaceholderView.setState(.loading)
        updatePreviewImageFrame()

        SteamWorkshopDownloadThumbnailPipeline.shared.generateThumbnail(for: videoURL) { [weak self] image in
            guard let self, self.currentPreviewURL == expectedPreviewURL else { return }
            if let image {
                self.previewImageView.image = image
                self.syncPreviewAnimationState()
                self.previewPlaceholderView.setState(.hidden)
            } else {
                self.previewImageView.image = nil
                self.previewPlaceholderView.setState(.unavailable)
            }
            self.updatePreviewImageFrame()
        }
    }

    private func loadPreviewImage(url: URL, cacheKey: String, bypassingCache: Bool) {
        if bypassingCache {
            SteamWorkshopPreviewImageCache.shared.remove(forKey: cacheKey)
        }
        let cancellation = SteamWorkshopPreviewLoadCancellation()
        previewLoadCancellation?.cancel()
        previewLoadCancellation = cancellation
        isPreviewLoadInFlight = true
        SteamWorkshopPreviewImageCache.shared.loadImageDataAsync(forKey: cacheKey, loader: {
            guard !cancellation.cancelled else { return nil }
            return await SteamWorkshopPreviewRequestCoordinator.shared.loadData(
                from: url,
                priority: .visible,
                ignoringBackoff: bypassingCache,
                cancellation: cancellation
            )
        }, decoder: steamWorkshopPreviewImage(from:)) { [weak self] image in
            guard let self,
                  self.currentPreviewURL == url,
                  self.previewLoadCancellation === cancellation else { return }
            self.previewLoadCancellation = nil
            self.isPreviewLoadInFlight = false
            self.applyResolvedPreviewImage(image, url: url, cacheKey: cacheKey)
        }
    }

    private func applyResolvedPreviewImage(_ image: NSImage?, url: URL, cacheKey: String) {
        if let image, steamWorkshopPreviewImageIsUsable(image) {
            previewImageView.image = image
            currentAnimatedPreviewImage = nil
            syncPreviewAnimationState()
            previewPlaceholderView.setState(.hidden)
            SteamWorkshopPreviewRequestCoordinator.shared.clearCachedImageSuspicion(forKey: cacheKey)
            updatePreviewImageFrame()
            return
        }

        previewImageView.image = nil
        if image != nil {
            SteamWorkshopPreviewRequestCoordinator.shared.markCachedImageSuspicious(forKey: cacheKey)
        }
        schedulePreviewRetry(url: url, cacheKey: cacheKey)
        updatePreviewImageFrame()
    }

    private func schedulePreviewRetry(url: URL, cacheKey: String) {
        previewRetryTask?.cancel()
        guard let retryDelay = SteamWorkshopPreviewRequestCoordinator.shared.nextRetryDelay(for: url, priority: .visible) else {
            previewPlaceholderView.setState(.unavailable)
            return
        }
        previewPlaceholderView.setState(.retrying)
        previewRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.5, retryDelay + 0.25) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.currentPreviewURL == url else { return }
                self.previewPlaceholderView.setState(.loading)
                self.loadPreviewImage(
                    url: url,
                    cacheKey: cacheKey,
                    bypassingCache: SteamWorkshopPreviewRequestCoordinator.shared.shouldBypassCachedImage(forKey: cacheKey)
                )
            }
        }
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
