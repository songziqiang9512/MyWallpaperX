import Foundation

nonisolated enum SceneScriptBooleanVisibilityValidation {
    typealias Resolution = (
        value: SceneDynamicValue,
        mutations: [SceneScriptLayerMutation]
    )

    static func validate(
        valueType: SceneDynamicValueType,
        target: SceneDynamicTarget,
        allowsLayerSideEffects: Bool,
        dynamicImagePathsByAuthoredIdentity: [String: String],
        value publishedValue: SceneDynamicValue,
        mutations: [SceneScriptLayerMutation]
    ) -> Result<Resolution, SceneScriptScalarRuntimeFailure> {
        guard valueType == .bool,
              case let .bool(initialVisible) = publishedValue,
              case let .layer(layerID, .visibility) = target else {
            return .failure(.invalidArgument(
                "Boolean owner target/value contract is invalid"
            ))
        }
        if !allowsLayerSideEffects {
            guard mutations.allSatisfy({ mutation in
                mutation.kind == .upsert && !mutation.isDynamic
                    && mutation.layerID == layerID
                    && mutation.fields == .visibility
                    && mutation.visible == initialVisible
            }) else {
                return .failure(.invalidArgument(
                    "Boolean value owner produced out-of-cohort mutations"
                ))
            }
            return .success((publishedValue, []))
        }

        var visible = initialVisible
        var resolved: [SceneScriptLayerMutation] = []
        resolved.reserveCapacity(mutations.count)
        for mutation in mutations {
            if !mutation.isDynamic {
                if mutation.kind == .destroy {
                    guard mutation.layerID == layerID,
                          mutation.fields.isEmpty else {
                        return .failure(.invalidArgument(
                            "Boolean owner may only destroy its authored owner layer"
                        ))
                    }
                    visible = false
                    resolved.append(mutation)
                    continue
                }
                guard mutation.kind == .upsert,
                      !mutation.fields.isEmpty,
                      mutation.fields.isSubset(of: .authoredFields) else {
                    return .failure(.invalidArgument(
                        "Boolean owner produced an invalid authored mutation"
                    ))
                }
                if mutation.layerID != layerID {
                    resolved.append(mutation)
                    continue
                }
                if mutation.fields.contains(.visibility) {
                    visible = mutation.visible
                }
                let sideEffectFields = mutation.fields.subtracting(.visibility)
                if !sideEffectFields.isEmpty {
                    resolved.append(
                        mutation.selectingAuthoredFields(sideEffectFields)
                    )
                }
                continue
            }
            guard let assetPath = mutation.assetPath,
                  let modelPath = preparedModelPath(
                    for: assetPath,
                    in: dynamicImagePathsByAuthoredIdentity
                  ) else {
                return .failure(.invalidArgument(
                    "Boolean dynamic-layer owner requested an unprepared asset"
                ))
            }
            resolved.append(mutation.resolvingAssetPath(to: modelPath))
        }
        return .success((.bool(visible), resolved))
    }

    private static func preparedModelPath(
        for assetPath: String,
        in paths: [String: String]
    ) -> String? {
        let normalized = assetPath.lowercased()
        return paths[normalized]
            ?? paths.values.first { $0.lowercased() == normalized }
    }
}
