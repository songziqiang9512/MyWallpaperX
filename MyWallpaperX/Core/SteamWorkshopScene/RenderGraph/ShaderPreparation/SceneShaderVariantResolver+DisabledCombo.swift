import Foundation

extension SceneShaderVariantResolver {
    nonisolated static func disabledComboSchema(
        annotation: SceneShaderContract.Annotation,
        object: [String: SceneShaderAnnotationValue],
        combo: String
    ) throws -> Schema? {
        guard isDisabledComboMarker(annotation.marker) else { return nil }

        let defaultValue: Int64
        if case let .integer(value)? = object["default"] {
            defaultValue = value
        } else {
            throw disabledComboFailure(combo)
        }
        let parsedOptions = try options(object["options"], combo: combo)
        guard defaultValue == 0,
              object["require"] == nil,
              object["requireany"] == nil,
              parsedOptions.map({ $0.contains(0) }) ?? true else {
            throw disabledComboFailure(combo)
        }
        return Schema(
            combo: combo,
            defaultValue: 0,
            options: parsedOptions,
            requirements: [:],
            requireAny: false,
            origin: .disabledCombo
        )
    }

    private nonisolated static func isDisabledComboMarker(_ marker: String?) -> Bool {
        guard let marker else { return false }
        return ["[COMBO_DISABLED]", "[OFF_COMBO]", "[COMBO_OFF]"]
            .contains(marker)
    }

    private nonisolated static func disabledComboFailure(_ combo: String) -> Failure {
        Failure(
            code: .disabledComboAnnotation,
            combo: combo,
            message: "Disabled shader combo requires an exact integer zero default without requirements."
        )
    }
}
