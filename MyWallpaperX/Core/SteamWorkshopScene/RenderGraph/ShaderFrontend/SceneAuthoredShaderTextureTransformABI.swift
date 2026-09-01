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
        componentByFieldName[name]
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
        guard activeSlots.allSatisfy({ (0 ..< 8).contains($0) }) else {
            return false
        }
        var expectedMask: UInt16 = 0
        for slot in activeSlots {
            expectedMask |= UInt16(0b11) << UInt16(slot * 2)
        }
        var observedMask: UInt16 = 0
        for field in layout.fields {
            let authored = component(forFieldName: field.authoredName)
            let runtime = component(forFieldName: field.name)
            guard authored != nil || runtime != nil else { continue }
            guard let authored, let runtime,
                  authored.slot == runtime.slot,
                  authored.component == runtime.component,
                  activeSlots.contains(authored.slot),
                  field.stage == nil,
                  field.type == .float4,
                  field.arrayCount == nil else {
                return false
            }
            let componentOffset: Int = authored.component == .originAndXAxis ? 0 : 1
            let fieldMask = UInt16(1) << UInt16(authored.slot * 2 + componentOffset)
            guard observedMask & fieldMask == 0 else { return false }
            observedMask |= fieldMask
        }
        return observedMask == expectedMask
    }

    private static let componentByFieldName: [
        String: (slot: Int, component: Component)
    ] = {
        var result: [String: (slot: Int, component: Component)] = [:]
        result.reserveCapacity(16)
        for slot in 0 ..< 8 {
            result[fieldName(slot: slot, component: .originAndXAxis)] =
                (slot, .originAndXAxis)
            result[fieldName(slot: slot, component: .yAxis)] = (slot, .yAxis)
        }
        return result
    }()
}
