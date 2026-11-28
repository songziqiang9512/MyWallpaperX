import AppKit

extension AppKitSettingsContainerView {
    static func makeSceneEffectReadout() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    func refreshSceneRenderReadouts(_ requested: SceneRenderQuality = PlaybackQualityPreference.current.scene) {
        let daemon = SceneDaemonClient.shared
        let displays = daemon.activeRasterDisplayStatuses
        let prepared = daemon.activePreparedRenderQuality
        let screens = displays.isEmpty ? [] : AppKit.NSScreen.screens
        let displayScreens = displays.map { display in
            screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
            }
        }
        let names = zip(displays, displayScreens).map { display, screen in
            screen?.localizedName ?? String(localized: "Display \(display.displayID.formatted())", table: "SceneQuality")
        }
        let waiting = String(localized: "Awaiting render result", table: "SceneQuality")
        refreshSceneRasterSampleReadout(displays, names: names, waiting: waiting,
            pending: prepared.map { $0.antiAliasing != requested.antiAliasing } ?? false)
        let hidden = displays.isEmpty && prepared == nil
        let postColdPending = prepared.map {
            $0.postProcessing.preparationMode != requested.postProcessing.preparationMode
        } == true
        let requestsDisplayHDR = requested.postProcessing.requestsDisplayHDR
        let postReadouts = zip(displays, displayScreens).map { display, screen -> (detail: String, previous: Bool) in
            guard let use = display.postProcessing else { return (waiting, false) }
            let targetSupportsHDR = screen.map { $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1 }
            let canChangeOutput = use.hdrWorkingSpace && use.display != .unmapped
                && (targetSupportsHDR == true || use.display == .edr)
            let previous = postColdPending || (canChangeOutput && use.display.requestedHDR != requestsDisplayHDR)
            let detail = postProcessingUseDescription(use, requestsDisplayHDR: previous ? use.display.requestedHDR : requestsDisplayHDR,
                                                     targetSupportsHDR: targetSupportsHDR)
            return (detail, previous)
        }
        let allPostPrevious = !postReadouts.isEmpty && postReadouts.allSatisfy(\.previous)
        let postDetails = postReadouts.map { readout in
            readout.previous && !allPostPrevious
                ? sceneRenderReadoutTitle(readout.detail, previous: true) : readout.detail
        }
        refreshSceneEffectReadout(scenePostProcessingUseLabel, details: postDetails, names: names,
                                  waiting: waiting, previous: allPostPrevious, hidden: hidden)
        let textureDetails = displays.map { $0.textures.map(textureUseDescription) ?? waiting }
        let previousTextures = prepared.map { $0.textures != requested.textures } == true
            && displays.contains { $0.textures != nil }
        refreshSceneEffectReadout(sceneTextureUseLabel, details: textureDetails, names: names,
                                  waiting: waiting, previous: previousTextures, hidden: hidden)
        let shadowDetails = displays.map { $0.shadow.map(shadowUseDescription) ?? waiting }
        let previousShadow = prepared.map { $0.shadows != requested.shadows } == true && displays.contains { $0.shadow != nil }
        refreshSceneEffectReadout(sceneShadowUseLabel, details: shadowDetails, names: names,
                                  waiting: waiting, previous: previousShadow, hidden: hidden)
        let volumeDetails = displays.map { display in
            display.volume.map { volumeUseDescription($0, prepared: prepared?.volumeLighting) } ?? waiting
        }
        let previousVolume = prepared.map { $0.volumeLighting != requested.volumeLighting } == true
            && displays.contains { $0.volume != nil }
        refreshSceneEffectReadout(sceneVolumeUseLabel, details: volumeDetails, names: names,
                                  waiting: waiting, previous: previousVolume, hidden: hidden)
        let reflectionDetails = displays.map { $0.reflection.map(reflectionUseDescription) ?? waiting }
        let previousReflection = prepared.map { $0.reflections != requested.reflections } == true
            && displays.contains { $0.reflection != nil }
        refreshSceneEffectReadout(sceneReflectionUseLabel, details: reflectionDetails, names: names,
                                  waiting: waiting, previous: previousReflection, hidden: hidden)
    }

    private func reflectionUseDescription(_ use: SceneReflectionUse) -> String {
        switch use {
        case .disabled: String(localized: "Disabled")
        case .cleared: String(localized: "Reflection disabled · cleared environment", table: "SceneQuality")
        case .inactive: String(localized: "No scene reflection sampled", table: "SceneQuality")
        case .waitingForHistory: String(localized: "Waiting for reflection history", table: "SceneQuality")
        case .unavailable: String(localized: "Reflection input unavailable", table: "SceneQuality")
        case .live: String(localized: "Live scene reflection", table: "SceneQuality")
        }
    }

    private func refreshSceneEffectReadout(_ field: NSTextField, details: [String], names: [String],
                                           waiting: String, previous: Bool, hidden: Bool) {
        let summary = Set(details).count > 1 ? String(localized: "Varies by display", table: "SceneQuality") : details.first ?? waiting
        let title = previous ? sceneRenderReadoutTitle(summary, previous: true) : summary
        if hidden != field.isHidden || title != field.stringValue { scheduleDocumentFrameUpdate() }
        field.isHidden = hidden
        field.stringValue = title
        field.toolTip = details.isEmpty ? nil : zip(names, details).map { name, detail in
            "\(name): \(detail)"
        }.joined(separator: "\n")
    }

    private func refreshSceneRasterSampleReadout(_ displays: [SceneRasterDisplayStatus], names: [String],
                                                waiting: String, pending: Bool) {
        sceneRasterSamplesLabel.isHidden = displays.isEmpty
        sceneRasterSamplesLabel.toolTip = nil
        guard !displays.isEmpty else { return }

        let counts = Set(displays.compactMap(\.samples)).sorted()
        let values = counts.map { "\($0.formatted())×" }
        let awaitingResult = displays.contains { $0.samples == nil }
        let summary = (values + (awaitingResult ? [waiting] : [])).joined(separator: " / ")
        sceneRasterSamplesLabel.stringValue = values.isEmpty ? waiting : sceneRenderReadoutTitle(summary, previous: pending)

        let details = zip(displays, names).map { display, name in
            let detail = display.samples.map { "\($0.formatted())×" } ?? waiting
            let reason: String? = switch display.fallback {
            case .deviceUnsupported: String(localized: "Device limit for requested MSAA", table: "SceneQuality")
            case .compatiblePathUnavailable: String(localized: "Single-sample render path", table: "SceneQuality")
            case .preparationFailed: String(localized: "MSAA preparation failed", table: "SceneQuality")
            case nil: nil
            }
            let value = [detail, reason].compactMap { $0 }.joined(separator: " – ")
            return (reason, "\(name): \(value)")
        }
        if !pending {
            if displays.count == 1, let reason = details[0].0 {
                sceneRasterSamplesLabel.stringValue += " – \(reason)"
            } else if details.contains(where: { $0.0 != nil }) {
                sceneRasterSamplesLabel.stringValue += " – " + String(localized: "Fallback on some displays", table: "SceneQuality")
            }
        }
        sceneRasterSamplesLabel.toolTip = details.map { $0.1 }.joined(separator: "\n")
    }

    private func sceneRenderReadoutTitle(_ summary: String, previous: Bool) -> String {
        previous ? String(localized: "Previous setting in use: \(summary)", table: "SceneQuality")
                 : String(localized: "In use: \(summary)", table: "SceneQuality")
    }

    private func postProcessingUseDescription(_ use: ScenePostProcessingUse, requestsDisplayHDR: Bool,
                                              targetSupportsHDR: Bool?) -> String {
        let domain = use.hdrWorkingSpace ? String(localized: "HDR working space", table: "SceneQuality")
                                        : String(localized: "SDR working space", table: "SceneQuality")
        let bloom = switch use.bloom {
        case .disabled: String(localized: "Bloom disabled", table: "SceneQuality")
        case .inactive: String(localized: "No active Bloom", table: "SceneQuality")
        case .standard: String(localized: "Standard Bloom", table: "SceneQuality")
        case .hdr: String(localized: "HDR Bloom", table: "SceneQuality")
        case .unsupported: String(localized: "Bloom levels unsupported", table: "SceneQuality")
        case .unavailable: String(localized: "Bloom unavailable", table: "SceneQuality")
        }
        let display: ScenePostProcessingUse.Display = if use.display == .edr || use.display == .unmapped {
            use.display
        } else if !requestsDisplayHDR {
            .sdr
        } else if !use.hdrWorkingSpace {
            .noHDRContent
        } else if targetSupportsHDR == false {
            .targetUnavailable
        } else {
            use.display
        }
        let output = switch display {
        case .sdr: String(localized: "SDR output", table: "SceneQuality")
        case .noHDRContent: String(localized: "Scene has no HDR output", table: "SceneQuality")
        case .targetUnavailable: String(localized: "SDR output · display has no HDR support", table: "SceneQuality")
        case .limitedHeadroom: String(localized: "SDR output · HDR headroom limited", table: "SceneQuality")
        case .edr: String(localized: "HDR display output", table: "SceneQuality")
        case .unmapped: String(localized: "Display mapping unavailable", table: "SceneQuality")
        }
        return [domain, bloom, output].joined(separator: " · ")
    }

    private func textureUseDescription(_ use: SceneTextureUse) -> String {
        let bindings = [use.reduced, use.retained].compactMap { $0 }
        guard !bindings.isEmpty else { return String(localized: "No ordinary texture observed", table: "SceneQuality") }
        return bindings.map { binding in
            let width = binding.width.formatted()
            let height = binding.height.formatted()
            let mip = binding.baseMip.formatted()
            let levels = binding.mipCount.formatted()
            let dimensions = String(localized: "\(width) × \(height) · Base mip \(mip) · Mip levels \(levels)", table: "SceneQuality")
            let reason = switch binding.reason {
            case .highQuality: String(localized: "High Quality")
            case .authoredMip: String(localized: "Smaller authored mip", table: "SceneQuality")
            case .projection: String(localized: "Original size for projection", table: "SceneQuality")
            case .alreadyFits: String(localized: "Already within size limit", table: "SceneQuality")
            case .preservedPixels: String(localized: "Original sampling kept", table: "SceneQuality")
            case .noEligibleMip: String(localized: "No eligible smaller mip", table: "SceneQuality")
            case .smallerMipUnavailable: String(localized: "Smaller mip unavailable", table: "SceneQuality")
            }
            return "\(dimensions) – \(reason)"
        }.joined(separator: " / ")
    }

    private func volumeUseDescription(_ use: SceneVolumeUse, prepared: SceneVolumeLightingQuality?) -> String {
        guard case .rendered(let rendered) = use else { return String(localized: "Disabled") }
        if rendered.spot, rendered.point == nil {
            return String(localized: "Spotlight cone (same at High and Ultra)", table: "SceneQuality")
        }
        let point: String? = switch rendered.point {
        case .analytic: String(localized: "Analytic point volume", table: "SceneQuality")
        case .fourPoint:
            prepared == .ultra
                ? String(localized: "Four-point volume (reduced order)", table: "SceneQuality")
                : String(localized: "Four-point volume", table: "SceneQuality")
        case .sixPoint: String(localized: "Six-point volume", table: "SceneQuality")
        case .unavailable: String(localized: "Point volume unavailable", table: "SceneQuality")
        case nil: nil
        }
        let spot = rendered.spot ? String(localized: "Spotlight cone", table: "SceneQuality") : nil
        let details = [point, spot].compactMap { $0 }
        return details.isEmpty ? String(localized: "No volumetric lighting drawn", table: "SceneQuality")
            : details.joined(separator: " / ")
    }

    private func shadowUseDescription(_ use: SceneShadowUse) -> String {
        switch use {
        case .disabled: return String(localized: "Disabled")
        case .noReceiver: return String(localized: "No applicable shadows", table: "SceneQuality")
        case .unavailable: return String(localized: "Shadow maps unavailable", table: "SceneQuality")
        case .active(let maps): return maps.map { map in
            let light = switch map.family {
            case .directional: String(localized: "Directional", table: "SceneQuality")
            case .point: String(localized: "Point (each face)", table: "SceneQuality")
            case .spot: String(localized: "Spotlight", table: "SceneQuality")
            }
            let size = map.face.map { "\($0.formatted()) × \($0.formatted())" }
            let reason: String? = switch map.limit {
            case .receiverExtent: String(localized: "Receiver target size limit", table: "SceneQuality")
            case .lightFamily: String(localized: "Light type limit", table: "SceneQuality")
            case .reduced: String(localized: "Reduced resolution", table: "SceneQuality")
            case nil: nil
            }
            let detail = size ?? String(localized: "Unavailable", table: "SceneQuality")
            return ["\(light): \(detail)", reason].compactMap { $0 }.joined(separator: " – ")
        }.joined(separator: " / ")
        }
    }
}
