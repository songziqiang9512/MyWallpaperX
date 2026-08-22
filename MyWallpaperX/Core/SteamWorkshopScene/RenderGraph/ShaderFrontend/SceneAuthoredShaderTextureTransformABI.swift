import Foundation

/// Shared host/shader ABI for one affine UV transform per active material
/// texture slot. Values are frame facts; field presence is a variant fact.
nonisolated enum SceneMaterialTextureTransformABI {
    enum Component: String, Hashable {
        case originAndXAxis, yAxis

        var identityValue: SIMD4<Float> {
            switch self {
            case .originAndXAxis: SIMD4(0, 0, 1, 0)
            case .yAxis: SIMD4(0, 1, 0, 0)
            }
        }
    }

    static func fieldName(slot: Int, component: Component) -> String {
        switch component {
        case .originAndXAxis: "mwxTexture\(slot)Transform0"
        case .yAxis: "mwxTexture\(slot)Transform1"
        }
    }

    static func component(
        forFieldName name: String
    ) -> (slot: Int, component: Component)? {
        for slot in 0 ..< 8 {
            for component in [Component.originAndXAxis, .yAxis]
            where name == fieldName(slot: slot, component: component) {
                return (slot, component)
            }
        }
        return nil
    }

    static func fields(
        activeSlots: [Int],
        startingAt initialOffset: Int
    ) -> (fields: [SceneAuthoredShaderUniformLayout.Field], endOffset: Int)? {
        guard activeSlots == activeSlots.sorted(),
              Set(activeSlots).count == activeSlots.count,
              activeSlots.allSatisfy({ (0 ..< 8).contains($0) }) else {
            return nil
        }
        var offset = initialOffset
        var result: [SceneAuthoredShaderUniformLayout.Field] = []
        for slot in activeSlots {
            for component in [Component.originAndXAxis, .yAxis] {
                let type = SceneAuthoredShaderValueType.float4
                let remainder = offset % type.alignment
                if remainder != 0 { offset += type.alignment - remainder }
                result.append(.init(
                    name: fieldName(slot: slot, component: component),
                    type: type,
                    offset: offset
                ))
                offset += type.byteSize
            }
        }
        return (result, offset)
    }

    static func validates(
        layout: SceneAuthoredShaderUniformLayout,
        activeSlots: Set<Int>
    ) -> Bool {
        let fields = layout.fields.filter {
            component(forFieldName: $0.authoredName) != nil
                || component(forFieldName: $0.name) != nil
        }
        guard fields.count == activeSlots.count * 2 else { return false }
        return activeSlots.allSatisfy { slot in
            [Component.originAndXAxis, .yAxis].allSatisfy { component in
                let name = fieldName(slot: slot, component: component)
                return fields.contains {
                    $0.name == name && $0.authoredName == name
                        && $0.stage == nil && $0.type == .float4
                        && $0.arrayCount == nil
                }
            }
        }
    }
}
