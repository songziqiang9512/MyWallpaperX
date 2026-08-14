import Foundation

/// Lossless source identity for every Scene JSON wrapper carrying a string
/// SceneScript source. Evidence is provenance only and never grants execution.
nonisolated struct SceneScriptSourceEvidenceIR: Equatable, Sendable {
    let source: String
    let owner: SceneScriptBindingOwner
    let targetPath: [SceneScriptBindingPathComponent]
    let wrapperKeys: [String]

    nonisolated var targetKey: String {
        guard case let .key(key) = targetPath.last else { return "" }
        return key
    }
}

/// Collects every inline SceneScript source independently from executable
/// binding admission. Nested payloads inherit the nearest exact owner while
/// retaining their complete JSON path.
nonisolated enum SceneScriptSourceEvidenceCollector {
    nonisolated static func collect(
        document root: [String: Any]
    ) -> [SceneScriptSourceEvidenceIR] {
        var result: [SceneScriptSourceEvidenceIR] = []
        let sceneOwner = owner(kind: .scene)
        appendSource(
            from: root,
            owner: sceneOwner,
            path: [],
            result: &result
        )

        for key in root.keys.sorted() where key != "objects" {
            collect(
                root[key],
                owner: sceneOwner,
                path: [.key(key)],
                result: &result
            )
        }
        guard let objects = root["objects"] as? [Any] else {
            collect(
                root["objects"],
                owner: sceneOwner,
                path: [.key("objects")],
                result: &result
            )
            return result
        }
        for (objectIndex, rawObject) in objects.enumerated() {
            let objectPath: [SceneScriptBindingPathComponent] = [
                .key("objects"), .index(objectIndex),
            ]
            guard let object = rawObject as? [String: Any] else {
                collect(
                    rawObject,
                    owner: sceneOwner,
                    path: objectPath,
                    result: &result
                )
                continue
            }
            let objectOwner = owner(
                kind: .object,
                objectIndex: objectIndex,
                objectID: object["id"] as? Int
            )
            appendSource(
                from: object,
                owner: objectOwner,
                path: objectPath,
                result: &result
            )
            for key in object.keys.sorted() where key != "effects" {
                collect(
                    object[key],
                    owner: objectOwner,
                    path: objectPath + [.key(key)],
                    result: &result
                )
            }
            collectEffects(
                object["effects"],
                objectOwner: objectOwner,
                objectPath: objectPath,
                result: &result
            )
        }
        return result
    }

    private nonisolated static func collectEffects(
        _ rawEffects: Any?,
        objectOwner: SceneScriptBindingOwner,
        objectPath: [SceneScriptBindingPathComponent],
        result: inout [SceneScriptSourceEvidenceIR]
    ) {
        guard let effects = rawEffects as? [Any] else {
            collect(
                rawEffects,
                owner: objectOwner,
                path: objectPath + [.key("effects")],
                result: &result
            )
            return
        }
        for (effectIndex, rawEffect) in effects.enumerated() {
            let effectPath = objectPath + [
                .key("effects"), .index(effectIndex),
            ]
            guard let effect = rawEffect as? [String: Any] else {
                collect(
                    rawEffect,
                    owner: objectOwner,
                    path: effectPath,
                    result: &result
                )
                continue
            }
            let effectOwner = owner(
                kind: .effect,
                objectIndex: objectOwner.objectIndex,
                objectID: objectOwner.objectID,
                effectIndex: effectIndex,
                effectID: effect["id"] as? Int
            )
            appendSource(
                from: effect,
                owner: effectOwner,
                path: effectPath,
                result: &result
            )
            for key in effect.keys.sorted() where key != "passes" {
                collect(
                    effect[key],
                    owner: effectOwner,
                    path: effectPath + [.key(key)],
                    result: &result
                )
            }
            guard let passes = effect["passes"] as? [Any] else {
                collect(
                    effect["passes"],
                    owner: effectOwner,
                    path: effectPath + [.key("passes")],
                    result: &result
                )
                continue
            }
            for (passIndex, rawPass) in passes.enumerated() {
                let passPath = effectPath + [
                    .key("passes"), .index(passIndex),
                ]
                guard let pass = rawPass as? [String: Any] else {
                    collect(
                        rawPass,
                        owner: effectOwner,
                        path: passPath,
                        result: &result
                    )
                    continue
                }
                let passOwner = owner(
                    kind: .pass,
                    objectIndex: objectOwner.objectIndex,
                    objectID: objectOwner.objectID,
                    effectIndex: effectIndex,
                    effectID: effect["id"] as? Int,
                    passIndex: passIndex,
                    passID: pass["id"] as? Int
                )
                collect(
                    pass,
                    owner: passOwner,
                    path: passPath,
                    result: &result
                )
            }
        }
    }

    private nonisolated static func collect(
        _ value: Any?,
        owner: SceneScriptBindingOwner,
        path: [SceneScriptBindingPathComponent],
        result: inout [SceneScriptSourceEvidenceIR]
    ) {
        if let object = value as? [String: Any] {
            appendSource(
                from: object,
                owner: owner,
                path: path,
                result: &result
            )
            for key in object.keys.sorted() {
                collect(
                    object[key],
                    owner: owner,
                    path: path + [.key(key)],
                    result: &result
                )
            }
        } else if let array = value as? [Any] {
            for (index, element) in array.enumerated() {
                collect(
                    element,
                    owner: owner,
                    path: path + [.index(index)],
                    result: &result
                )
            }
        }
    }

    private nonisolated static func appendSource(
        from object: [String: Any],
        owner: SceneScriptBindingOwner,
        path: [SceneScriptBindingPathComponent],
        result: inout [SceneScriptSourceEvidenceIR]
    ) {
        guard let source = object["script"] as? String else { return }
        result.append(SceneScriptSourceEvidenceIR(
            source: source,
            owner: owner,
            targetPath: path,
            wrapperKeys: object.keys.sorted()
        ))
    }

    private nonisolated static func owner(
        kind: SceneScriptBindingOwner.Kind,
        objectIndex: Int? = nil,
        objectID: Int? = nil,
        effectIndex: Int? = nil,
        effectID: Int? = nil,
        passIndex: Int? = nil,
        passID: Int? = nil
    ) -> SceneScriptBindingOwner {
        SceneScriptBindingOwner(
            kind: kind,
            objectIndex: objectIndex,
            objectID: objectID,
            effectIndex: effectIndex,
            effectID: effectID,
            passIndex: passIndex,
            passID: passID
        )
    }
}
