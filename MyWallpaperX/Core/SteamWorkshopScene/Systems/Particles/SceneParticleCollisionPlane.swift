import Foundation

nonisolated struct SceneParticleCollisionPlane: Equatable, Sendable {
    let plane: SceneParticleNumericValue?
    let distance: Double?
    let bounceFactor: Double?
    let hasMalformedFields: Bool
    let unsupportedFieldNames: [String]

    nonisolated init(root: [String: Any]) {
        plane = SceneParticleDefinitionParser.numericValue(root["plane"])
        distance = SceneParticleDefinitionParser.number(root["distance"])
        bounceFactor = SceneParticleDefinitionParser.number(root["bouncefactor"])

        let supported = Set([
            "id", "name", "flags", "plane", "distance", "bouncefactor",
        ])
        unsupportedFieldNames = root.keys.filter { !supported.contains($0) }.sorted()
        hasMalformedFields = Self.isMalformed(
            root, key: "plane", parsed: plane
        ) || Self.isMalformed(
            root, key: "distance", parsed: distance
        ) || Self.isMalformed(
            root, key: "bouncefactor", parsed: bounceFactor
        ) || Self.isMalformed(
            root, key: "flags", parsed: SceneParticleDefinitionParser.integer(root["flags"])
        )
    }

    private nonisolated static func isMalformed(
        _ root: [String: Any], key: String, parsed: Any?
    ) -> Bool {
        root[key] != nil && !(root[key] is NSNull) && parsed == nil
    }
}

nonisolated struct SceneParticleCollisionPlanePlan: Equatable, Sendable {
    let normal: SIMD3<Double>
    let distance: Double
    let bounceFactor: Double
}

extension SceneParticleOperator {
    nonisolated var collisionPlanePlan: SceneParticleCollisionPlanePlan? {
        guard case let .collisionPlane(value) = kind,
              rawFlags == 0,
              !value.hasMalformedFields,
              value.unsupportedFieldNames.isEmpty,
              let distance = value.distance,
              let bounceFactor = value.bounceFactor,
              distance.isFinite, abs(distance) <= 1_000_000,
              bounceFactor.isFinite, (0 ... 100).contains(bounceFactor),
              audioResponse == .none,
              blendInStart == nil, blendInEnd == nil,
              blendOutStart == nil, blendOutEnd == nil else { return nil }

        let authoredNormal: SIMD3<Double>
        switch value.plane {
        case let .vector(values) where values.count == 3:
            authoredNormal = SIMD3(values[0], values[1], values[2])
        case nil:
            // Stock-authored collision planes omit this public field. Keep the
            // bounded 2D default local to this component rather than inventing a
            // host/world-space plane provider.
            authoredNormal = SIMD3(0, 1, 0)
        case .scalar, .vector:
            return nil
        }
        guard authoredNormal.x.isFinite, authoredNormal.y.isFinite,
              authoredNormal.z.isFinite,
              abs(authoredNormal.x) <= 1_000_000,
              abs(authoredNormal.y) <= 1_000_000,
              abs(authoredNormal.z) <= 1_000_000 else { return nil }
        let length = sqrt(
            authoredNormal.x * authoredNormal.x
                + authoredNormal.y * authoredNormal.y
                + authoredNormal.z * authoredNormal.z
        )
        guard length.isFinite, length > 1e-12 else { return nil }
        return .init(
            normal: authoredNormal / length,
            distance: distance,
            bounceFactor: bounceFactor
        )
    }
}
