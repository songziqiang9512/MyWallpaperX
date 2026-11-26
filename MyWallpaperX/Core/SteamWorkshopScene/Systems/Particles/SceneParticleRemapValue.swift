import Foundation

nonisolated enum SceneParticleRemapPlan: Equatable, Sendable {
    case velocityNoise(VectorNoise)
    case scalar(Scalar)

    struct VectorNoise: Equatable, Sendable {
        let minimum: SIMD3<Double>
        let maximum: SIMD3<Double>
        let inputScale: Double
    }

    struct Scalar: Equatable, Sendable {
        enum Consumer: Equatable, Sendable {
            case speedNoise(inputScale: Double)
            case opacity(TimeInput, Operation)
        }

        let minimum: Double
        let maximum: Double
        let consumer: Consumer

        func value(at amount: Double) -> Double {
            minimum + (maximum - minimum) * amount
        }
    }

    enum Operation: String, Equatable, Sendable {
        case remap
        case multiply
    }

    struct TimeInput: Equatable, Sendable {
        let minimum: Double
        let span: Double
        let sineScale: Double?

        func amount(at sceneTime: Double) -> Double {
            let normalized = (sceneTime - minimum) / span
            guard let sineScale else { return normalized }
            return (1 - cos(.pi * (normalized * sineScale))) * 0.5
        }
    }

    // The two approximated noise consumers retain their existing authored scope.
    private static let noiseFields: Set<String> = [
        "id", "name", "flags", "operation", "output", "outputrangemin",
        "outputrangemax", "transformfunction", "transforminputscale",
    ]

    init?(root: [String: Any], flags: Int?) {
        let operation = Self.name(root["operation"])
        let transform = Self.name(root["transformfunction"])
        switch Self.name(root["output"]) {
        case "velocity":
            guard root["flags"] == nil, operation == "remap", transform == "simplexnoise",
                  root.keys.allSatisfy(Self.noiseFields.contains),
                  let minimum = Self.noiseVector(root["outputrangemin"]),
                  let maximum = Self.noiseVector(root["outputrangemax"]),
                  let scale = SceneParticleDefinitionParser.number(root["transforminputscale"]),
                  scale > 0, scale <= 1_000_000 else { return nil }
            self = .velocityNoise(.init(minimum: minimum, maximum: maximum, inputScale: scale))
        case "speed":
            guard flags == 3, root["operation"] == nil || operation == "multiply",
                  transform == "fbmnoise", root.keys.allSatisfy(Self.noiseFields.contains),
                  let minimum = Self.scalar(root["outputrangemin"]), abs(minimum) <= 1_000_000,
                  let maximum = Self.scalar(root["outputrangemax"]), abs(maximum) <= 1_000_000,
                  let scale = Self.scalar(root["transforminputscale"]),
                  scale > 0, scale <= 1_000_000 else { return nil }
            self = .scalar(.init(minimum: minimum, maximum: maximum, consumer: .speedNoise(inputScale: scale)))
        case "opacity":
            guard root["flags"] == nil || flags == 0,
                  Self.name(root["input"]) == "particlesystemtime",
                  let operation = root["operation"] == nil ? .multiply : Operation(rawValue: operation ?? ""),
                  let input = Self.timeInput(root, transform: transform),
                  let minimum = Self.scalar(root["outputrangemin"], default: 0),
                  let maximum = Self.scalar(root["outputrangemax"], default: 1),
                  (maximum - minimum).isFinite else { return nil }
            self = .scalar(.init(minimum: minimum, maximum: maximum, consumer: .opacity(input, operation)))
        default:
            return nil
        }
    }

    static func flags(_ raw: Any?) -> Int? {
        scalar(raw).flatMap { Int(exactly: $0) }
    }

    private static func timeInput(_ root: [String: Any], transform: String?) -> TimeInput? {
        guard let minimum = scalar(root["inputrangemin"], default: 0),
              let maximum = scalar(root["inputrangemax"], default: 1) else { return nil }
        let span = maximum - minimum
        guard span.isFinite, span != 0 else { return nil }
        if transform == "sine" {
            guard let scale = scalar(root["transforminputscale"], default: 2) else { return nil }
            return .init(minimum: minimum, span: span, sineScale: scale)
        }
        guard root["transformfunction"] == nil, root["transforminputscale"] == nil else { return nil }
        return .init(minimum: minimum, span: span, sineScale: nil)
    }

    private static func name(_ raw: Any?) -> String? {
        (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func scalar(_ raw: Any?, default fallback: Double? = nil) -> Double? {
        guard var value = raw else { return fallback }
        while let wrapper = value as? [String: Any], let wrapped = wrapper["value"] {
            value = wrapped
        }
        if let values = value as? [Any] {
            // The general decoder may drop malformed or missing vector elements.
            guard values.count == 1, !(values[0] is [Any]), !(values[0] is [String: Any]) else { return nil }
            value = values[0]
        }
        guard let number = SceneParticleDefinitionParser.number(value), number.isFinite else { return nil }
        return number
    }

    private static func noiseVector(_ raw: Any?) -> SIMD3<Double>? {
        guard case let .vector(values) = SceneParticleDefinitionParser.numericValue(raw),
              values.count == 3, values.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else { return nil }
        return SIMD3(values[0], values[1], values[2])
    }
}
