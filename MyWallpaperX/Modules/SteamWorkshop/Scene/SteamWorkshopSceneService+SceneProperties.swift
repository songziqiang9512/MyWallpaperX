import Combine
import Foundation

struct SteamWorkshopScenePropertyContext {
    let catalog: SceneUserPropertyCatalog
    let actionableKeys: Set<String>
    let effectiveValues: [String: SceneUserPropertyValue]

    var definitions: [SceneUserPropertyDefinition] {
        catalog.definitions.filter { actionableKeys.contains($0.key) }
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
              let document = report.sceneDocument else {
            return nil
        }
        let actionableKeys = Set(
            document.userPropertyResolution.bindingReport.bindings.compactMap { binding in
                supportsScenePropertyTarget(binding.target) ? binding.reference.key : nil
            }
        )
        guard !actionableKeys.isEmpty else { return nil }
        let catalog = project.userProperties
        return SteamWorkshopScenePropertyContext(
            catalog: catalog,
            actionableKeys: actionableKeys,
            effectiveValues: catalog.effectiveValues(overrides: scenePropertyOverrides(for: record))
        )
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
        scheduleActiveScenePropertyRender(for: record)
    }

    func resetScenePropertyValues(for record: SteamWorkshopDownloadRecord) {
        saveScenePropertyOverrides([:], for: record)
        objectWillChange.send()
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
        scenePropertyRenderTask?.cancel()
        guard SceneDesktopWallpaperHost.shared.activeRecordID == record.id else { return }
        scenePropertyRenderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            self?.requestSceneRender(record)
        }
    }

    private func supportsScenePropertyTarget(_ target: SceneUserPropertyBindingTarget) -> Bool {
        switch target {
        case .layerVisibility, .text:
            return true
        case let .camera(field):
            return [
                "cameraparallax",
                "cameraparallaxamount",
                "cameraparallaxmouseinfluence"
            ].contains(field.localizedLowercase)
        case let .effectVisibility(_, _, effectPath):
            return Self.supportsSceneEffectProperty(path: effectPath, valueName: nil)
        case let .shaderValue(_, _, _, name, effectPath):
            return Self.supportsSceneEffectProperty(path: effectPath, valueName: name)
        case .unsupported:
            return false
        }
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
            ("opacity", ["alpha"])
        ]
        guard let supportedNames = supportedNamesByPath.first(where: { path.contains($0.0) })?.1 else {
            return supportedNamesByPath.contains { path.contains($0.0) && $0.1 == nil } && name == nil
        }
        return name == nil || name.map(supportedNames.contains) == true
    }
}
