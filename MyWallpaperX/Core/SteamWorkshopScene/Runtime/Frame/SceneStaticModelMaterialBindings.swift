import Foundation

/// Immutable addressing for the static model renderer's existing material
/// channels. A missing descriptor value is inapplicable; rejected authored
/// metadata never becomes the host's opaque material fallback.
nonisolated struct SceneStaticModelMaterialBindings: Codable, Equatable, Sendable {
    enum State: String, Codable, Equatable, Sendable {
        case hostBuiltin
        case unavailable
        case authored
        case rejected
    }

    enum Channel: String, Codable, Equatable, Sendable {
        case alpha
        case color
        case brightness
    }

    enum ValueType: String, Codable, Equatable, Sendable {
        case scalar
        case vector3
    }

    struct Binding: Codable, Equatable, Sendable {
        let channel: Channel
        let uniformName: String
        /// Exact authored producer key. `nil` uses only the shader default.
        let materialKey: String?
        let components: [Double]

        var valueType: ValueType {
            channel == .color ? .vector3 : .scalar
        }
    }

    let state: State
    let bindings: [Binding]
    let rejectionReason: String?

    func binding(for channel: Channel) -> Binding? {
        var match: Binding?
        for binding in bindings where binding.channel == channel {
            guard match == nil else { return nil }
            match = binding
        }
        return match
    }
}
