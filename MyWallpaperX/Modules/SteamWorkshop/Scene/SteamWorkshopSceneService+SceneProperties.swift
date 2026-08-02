import Combine
import Foundation

struct SteamWorkshopScenePropertyContext {
    let catalog: SceneUserPropertyCatalog
    let actionableKeys: Set<String>
    let effectiveValues: [String: SceneUserPropertyValue]

    var definitions: [SceneUserPropertyDefinition] {
        let definitions = catalog.definitions
        return definitions.enumerated().compactMap { index, definition in
            if actionableKeys.contains(definition.key) {
                switch definition.kind {
                case .bool, .slider, .color, .combo, .textInput, .text, .sceneTexture:
                    return definition
                case .group, .unsupported:
                    break
                }
            }

            switch definition.kind {
            case .group where sectionContainsActionableControl(after: index, in: definitions):
                return definition
            case .text where hasAdjacentActionableControl(at: index, in: definitions):
                return definition
            default:
                return nil
            }
        }
    }

    var actionableDefinitions: [SceneUserPropertyDefinition] {
        catalog.definitions.filter {
            actionableKeys.contains($0.key) && Self.supportsEditorControl($0.kind)
        }
    }

    private static func supportsEditorControl(_ kind: SceneUserPropertyKind) -> Bool {
        switch kind {
        case .bool, .slider, .color, .combo, .textInput, .sceneTexture:
            return true
        case .text, .group, .unsupported:
            return false
        }
    }

    private func hasAdjacentActionableControl(
        at index: Int,
        in definitions: [SceneUserPropertyDefinition]
    ) -> Bool {
        [index - 1, index + 1].contains { neighborIndex in
            guard definitions.indices.contains(neighborIndex) else { return false }
            let neighbor = definitions[neighborIndex]
            return actionableKeys.contains(neighbor.key)
                && Self.supportsEditorControl(neighbor.kind)
        }
    }

    private func sectionContainsActionableControl(
        after index: Int,
        in definitions: [SceneUserPropertyDefinition]
    ) -> Bool {
        guard index + 1 < definitions.count else { return false }
        for definition in definitions[(index + 1)...] {
            if definition.kind == .group { return false }
            if actionableKeys.contains(definition.key),
               Self.supportsEditorControl(definition.kind) {
                return true
            }
        }
        return false
    }
}

extension SteamWorkshopService {
    private enum ScenePropertyOverrideStore {
        static let defaultsPrefix = "SteamWorkshop.scenePropertyOverrides."
    }

    func scenePropertyOverrides(
        for record: SteamWorkshopDownloadRecord
    ) -> [String: SceneUserPropertyValue] {
        let key = ScenePropertyOverrideStore.defaultsPrefix + record.id
        guard let data = defaults.data(forKey: key),
              let values = try? JSONDecoder().decode([String: SceneUserPropertyValue].self, from: data) else {
            return [:]
        }
        return values
    }

    func scenePropertyContext(
        for record: SteamWorkshopDownloadRecord,
        report: SceneDiagnosticsReport
    ) -> SteamWorkshopScenePropertyContext? {
        guard record.contentType == .scene,
              let project = report.project,
              let document = report.sceneDocument,
              let renderDescriptor = report.renderDescriptor else {
            return nil
        }
        let authoredEffectCatalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: renderDescriptor,
            authoredPlans: SceneAuthoredEffectRenderPlanner.plans(for: renderDescriptor),
            shaderContracts: report.assetCatalog?.shaderContracts ?? []
        )
        var actionableKeys = Set(
            document.userPropertyResolution.bindingReport.bindings.compactMap { binding in
                supportsScenePropertyTarget(
                    binding.target,
                    in: renderDescriptor,
                    authoredEffectCatalog: authoredEffectCatalog
                ) ? binding.reference.key : nil
            }
        )
        let blendPlan = SceneImageBlendRenderPlan(
            descriptor: renderDescriptor,
            visibleLayerIDs: Set(renderDescriptor.layers.map(\.id))
        )
        actionableKeys.formUnion(authoredEffectCatalog.executedUserPropertyKeys)
        actionableKeys.formUnion(blendPlan.executedUserPropertyKeys)
        let catalog = project.userProperties
        let context = SteamWorkshopScenePropertyContext(
            catalog: catalog,
            actionableKeys: actionableKeys,
            effectiveValues: catalog.effectiveValues(overrides: scenePropertyOverrides(for: record))
        )
        return context.actionableDefinitions.isEmpty ? nil : context
    }

    func shouldDisplaySceneProperty(
        _ definition: SceneUserPropertyDefinition,
        values: [String: SceneUserPropertyValue],
        catalog: SceneUserPropertyCatalog
    ) -> Bool {
        guard let condition = definition.displayCondition else { return true }
        return Self.evaluateWebDisplayCondition(
            condition,
            values: Self.webPropertyValues(from: values),
            definitions: catalog.definitions.map(Self.webPropertyDefinition(from:))
        )
    }

    func visibleScenePropertyOptions(
        for definition: SceneUserPropertyDefinition,
        values: [String: SceneUserPropertyValue],
        catalog: SceneUserPropertyCatalog
    ) -> [SceneUserPropertyOption] {
        let webValues = Self.webPropertyValues(from: values)
        let webDefinitions = catalog.definitions.map(Self.webPropertyDefinition(from:))
        return definition.options.filter { option in
            guard let condition = option.displayCondition else { return true }
            return Self.evaluateWebDisplayCondition(
                condition,
                values: webValues,
                definitions: webDefinitions
            )
        }
    }

    func updateScenePropertyValue(
        _ value: SceneUserPropertyValue,
        definition: SceneUserPropertyDefinition,
        record: SteamWorkshopDownloadRecord
    ) {
        var overrides = scenePropertyOverrides(for: record)
        if definition.defaultValue == value {
            overrides.removeValue(forKey: definition.key)
        } else {
            overrides[definition.key] = value
        }
        saveScenePropertyOverrides(overrides, for: record)
        objectWillChange.send()
        if !SceneDesktopWallpaperHost.shared.applyUserPropertyValue(
            value,
            forPropertyKey: definition.key,
            recordID: record.id
        ) {
            scheduleActiveScenePropertyRender(for: record)
        }
    }

    func resetScenePropertyValues(
        for record: SteamWorkshopDownloadRecord,
        defaultValues: [String: SceneUserPropertyValue]
    ) {
        let overrides = scenePropertyOverrides(for: record)
        let changedPropertyKeys = Set(overrides.keys)
        let removedTextureBookmarks = clearSceneTexturePropertyBookmarks(for: record)
        saveScenePropertyOverrides([:], for: record)
        objectWillChange.send()
        guard removedTextureBookmarks || !changedPropertyKeys.isEmpty else { return }
        if !removedTextureBookmarks,
           SceneDesktopWallpaperHost.shared.applyUserPropertyValues(
               defaultValues,
               changedPropertyKeys: changedPropertyKeys,
               recordID: record.id
           ) {
            return
        }
        scheduleActiveScenePropertyRender(for: record)
    }

    private func saveScenePropertyOverrides(
        _ overrides: [String: SceneUserPropertyValue],
        for record: SteamWorkshopDownloadRecord
    ) {
        let key = ScenePropertyOverrideStore.defaultsPrefix + record.id
        guard !overrides.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        defaults.set(data, forKey: key)
    }

    private func scheduleActiveScenePropertyRender(for record: SteamWorkshopDownloadRecord) {
        guard SceneDesktopWallpaperHost.shared.activeRecordID == record.id else { return }
        scenePropertyRenderTask?.cancel()
        scenePropertyRenderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled,
                  SceneDesktopWallpaperHost.shared.activeRecordID == record.id else { return }
            self?.requestSceneRender(record)
        }
    }

    private func supportsScenePropertyTarget(
        _ target: SceneUserPropertyBindingTarget,
        in renderDescriptor: SceneRenderDescriptor,
        authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog
    ) -> Bool {
        switch target {
        case .layerVisibility, .layerAlpha, .text:
            return true
        case let .puppetAnimationVisibility(layerID, animationLayerID):
            return renderDescriptor.layers.contains { layer in
                layer.id == layerID && layer.puppetAnimationLayers.contains {
                    $0.id == animationLayerID && $0.visibilityBinding != nil
                }
            }
        case let .particle(layerID, _):
            return renderDescriptor.layers.contains {
                $0.id == layerID && $0.contentKind == "particle"
            }
        case let .layerColor(layerID):
            return renderDescriptor.layers.contains {
                $0.id == layerID && $0.contentKind == "solid"
            }
        case let .camera(field):
            return [
                "cameraparallax",
                "cameraparallaxamount",
                "cameraparallaxmouseinfluence"
            ].contains(field.localizedLowercase)
        case let .effectVisibility(_, _, effectPath):
            if Self.isStrictLocalContrastPath(effectPath) {
                return true
            }
            return Self.supportsSceneEffectProperty(path: effectPath, valueName: nil)
        case let .shaderValue(layerID, effectIndex, passIndex, name, effectPath):
            if Self.isStrictLocalContrastPath(effectPath) {
                return authoredEffectCatalog.liveConsumerTargets.contains(.effectConstant(
                    layerID: layerID,
                    effectIndex: effectIndex,
                    passIndex: passIndex,
                    name: name
                ))
            }
            return Self.supportsSceneEffectProperty(path: effectPath, valueName: name)
        case .unsupported:
            return false
        }
    }

    private static func isStrictLocalContrastPath(_ path: String?) -> Bool {
        path?.replacingOccurrences(of: "\\", with: "/").lowercased()
            == "effects/localcontrast/effect.json"
    }

    private static func supportsSceneEffectProperty(path: String?, valueName: String?) -> Bool {
        guard let path = path?.localizedLowercase else { return false }
        let name = valueName?.localizedLowercase
        let supportedNamesByPath: [(String, Set<String>?)] = [
            ("foliagesway", nil),
            ("cursorripple", nil),
            ("chromaticaberration", nil),
            ("waterwaves", ["scale", "speed", "animationspeed", "scrollspeed", "strength", "ripplestrength", "direction", "scrolldirection"]),
            ("waterripple", ["scale", "speed", "animationspeed", "scrollspeed", "strength", "ripplestrength", "direction", "scrolldirection"]),
            ("iris", ["scale", "speed", "phase", "rough", "noiseamount"]),
            ("blur", ["scale"]),
            ("bloom", ["threshold", "gamma", "radius", "opacity", "strength", "tint"]),
            ("perspective", ["top", "bottom", "left", "right"]),
            ("opacity", ["alpha"]),
            ("tint", ["alpha", "color"]),
            ("xray", ["size"])
        ]
        guard let supportedNames = supportedNamesByPath.first(where: { path.contains($0.0) })?.1 else {
            return supportedNamesByPath.contains { path.contains($0.0) && $0.1 == nil } && name == nil
        }
        return name == nil || name.map(supportedNames.contains) == true
    }

    private static func webPropertyValues(
        from values: [String: SceneUserPropertyValue]
    ) -> [String: SteamWorkshopWebPropertyValue] {
        values.mapValues(webPropertyValue(from:))
    }

    private static func webPropertyValue(
        from value: SceneUserPropertyValue
    ) -> SteamWorkshopWebPropertyValue {
        switch value {
        case let .string(value): .string(value)
        case let .number(value): .number(value)
        case let .bool(value): .bool(value)
        }
    }

    private static func webPropertyDefinition(
        from definition: SceneUserPropertyDefinition
    ) -> SteamWorkshopWebPropertyDefinition {
        SteamWorkshopWebPropertyDefinition(
            key: definition.key,
            title: definition.title,
            kind: webPropertyKind(from: definition.kind),
            runtimeType: definition.runtimeType,
            order: definition.order,
            minimumValue: definition.minimumValue,
            maximumValue: definition.maximumValue,
            allowsFractionalValues: definition.allowsFractionalValues,
            fractionalPrecision: definition.fractionalPrecision,
            displayCondition: definition.displayCondition,
            directoryMode: nil,
            fileType: nil,
            defaultValue: definition.defaultValue.map(webPropertyValue(from:)) ?? .string(""),
            options: definition.options.map {
                SteamWorkshopWebPropertyOption(
                    label: $0.label,
                    value: webPropertyValue(from: $0.value),
                    displayCondition: $0.displayCondition
                )
            }
        )
    }

    private static func webPropertyKind(
        from kind: SceneUserPropertyKind
    ) -> SteamWorkshopWebPropertyKind {
        switch kind {
        case .bool: .toggle
        case .slider: .slider
        case .color: .color
        case .combo: .combo
        case .textInput: .text
        case .text: .label
        case .group: .group
        case .sceneTexture: .file
        case .unsupported: .unknown
        }
    }
}
