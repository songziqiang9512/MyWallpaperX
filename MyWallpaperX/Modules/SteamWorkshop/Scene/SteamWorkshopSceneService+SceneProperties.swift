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
        sourceFacts: SceneRuntimeSourceFacts
    ) -> SteamWorkshopScenePropertyContext? {
        guard record.contentType == .scene,
              let project = sourceFacts.project,
              let document = sourceFacts.sceneDocument,
              let renderDescriptor = sourceFacts.renderDescriptor else {
            return nil
        }
        let materialBindings =
            SceneStaticModelMaterialPropertyBindingCompiler.compile(
                descriptor: renderDescriptor
            )
        let actionableKeys = Set(
            (
                document.userPropertyResolution.bindingReport.bindings
                    + materialBindings
            ).compactMap { binding in
                supportsScenePropertyTarget(
                    binding.target,
                    in: renderDescriptor
                ) ? binding.reference.key : nil
            }
        )
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
        in renderDescriptor: SceneRenderDescriptor
    ) -> Bool {
        switch target {
        case .layerVisibility, .layerAlpha, .text, .soundVolume:
            return true
        case let .layerScale(layerID):
            return renderDescriptor.layers.contains { $0.id == layerID }
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
                $0.id == layerID && $0.supportsDirectLayerColorConsumer
            }
        case let .camera(field):
            let normalizedField = field.localizedLowercase
            if [
                "cameraparallax",
                "cameraparallaxamount",
                "cameraparallaxmouseinfluence"
            ].contains(normalizedField) {
                return true
            }
            guard [
                "camerashake",
                "camerashakeamplitude",
                "camerashakeroughness",
                "camerashakespeed"
            ].contains(normalizedField),
                  let orthoWidth = renderDescriptor.camera.orthoWidth,
                  let orthoHeight = renderDescriptor.camera.orthoHeight,
                  orthoWidth.isFinite,
                  orthoHeight.isFinite,
                  orthoWidth > 0,
                  orthoHeight > 0 else {
                return false
            }
            return true
        case let .effectVisibility(layerID, effectIndex, effectPath),
             let .shaderValue(layerID, effectIndex, _, _, effectPath):
            return Self.hasAuthoredEffect(
                layerID: layerID,
                effectIndex: effectIndex,
                effectPath: effectPath,
                in: renderDescriptor
            )
        case .materialShaderValue:
            return SceneStaticModelMaterialPropertyBindingCompiler.compile(
                descriptor: renderDescriptor
            ).contains { $0.target == target }
        case let .scriptProperty(layerID, _):
            return renderDescriptor.layers.contains { $0.id == layerID }
        case .unsupported:
            return false
        }
    }

    private static func hasAuthoredEffect(
        layerID: Int,
        effectIndex: Int,
        effectPath: String?,
        in descriptor: SceneRenderDescriptor
    ) -> Bool {
        guard let layer = descriptor.layers.first(where: { $0.id == layerID }),
              layer.effects.indices.contains(effectIndex) else { return false }
        guard let effectPath else { return true }
        let normalize: (String) -> String = {
            $0.replacingOccurrences(of: "\\", with: "/").lowercased()
        }
        return normalize(layer.effects[effectIndex].file) == normalize(effectPath)
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
