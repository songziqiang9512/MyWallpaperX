import Foundation
import simd

nonisolated enum SceneResolvedMaterialUniformEncoder {
    typealias Program = SceneResolvedMaterialProgram

    static func hostUniform(
        _ field: SceneAuthoredShaderUniformLayout.Field,
        slots: [Program.TextureSlot?]
    ) -> Program.HostUniform? {
        switch (field.name, field.type) {
        case ("mwxRenderSize", .float2): .renderSize
        case ("g_ModelViewProjectionMatrix", .float4x4): .modelViewProjection
        case ("g_Time", .float): .time
        case ("g_Daytime", .float): .dayTime
        case ("g_Frametime", .float): .frameTime
        case ("g_PointerPosition", .float2): .pointerPosition
        case ("g_PointerPositionLast", .float2): .pointerPositionLast
        case ("g_Screen", .float3): .screen
        case ("g_TexelSize", .float2):
            .texelSize(scaleBitPattern: Double(1).bitPattern)
        case ("g_TexelSizeHalf", .float2):
            .texelSize(scaleBitPattern: Double(0.5).bitPattern)
        default:
            textureResolution(field, slots: slots)
        }
    }

    static func encodeHost(
        _ host: Program.HostUniform,
        type: SceneAuthoredShaderValueType,
        inputs: SceneAuthoredShaderUniformInputs,
        slots: [Program.TextureSlot?]
    ) -> Data? {
        switch host {
        case .renderSize:
            return encodeSize(inputs.renderSize, type: type)
        case .modelViewProjection:
            guard type == .float4x4 else { return nil }
            let matrix = inputs.modelViewProjection
            return encodeComponents([
                matrix.columns.0.x, matrix.columns.0.y,
                matrix.columns.0.z, matrix.columns.0.w,
                matrix.columns.1.x, matrix.columns.1.y,
                matrix.columns.1.z, matrix.columns.1.w,
                matrix.columns.2.x, matrix.columns.2.y,
                matrix.columns.2.z, matrix.columns.2.w,
                matrix.columns.3.x, matrix.columns.3.y,
                matrix.columns.3.z, matrix.columns.3.w,
            ].map(Double.init), as: type)
        case .time:
            return encodeScalar(inputs.sceneTime, type: type)
        case .dayTime:
            guard (0 ... 1).contains(inputs.dayTime) else { return nil }
            return encodeScalar(inputs.dayTime, type: type)
        case .frameTime:
            guard inputs.frameTime >= 0 else { return nil }
            return encodeScalar(inputs.frameTime, type: type)
        case .pointerPosition:
            return encodePointer(inputs.pointerCurrentNDC, type: type)
        case .pointerPositionLast:
            return encodePointer(inputs.pointerPreviousNDC, type: type)
        case .screen:
            guard type == .float3, valid(inputs.screenSize) else { return nil }
            let width = Double(inputs.screenSize.width)
            let height = Double(inputs.screenSize.height)
            return encodeComponents([width, height, width / height], as: type)
        case let .texelSize(scaleBits):
            guard type == .float2, valid(inputs.screenSize) else { return nil }
            let scale = Double(bitPattern: scaleBits)
            return encodeComponents([
                scale / Double(inputs.screenSize.width),
                scale / Double(inputs.screenSize.height),
            ], as: type)
        case let .textureResolution(slot):
            guard type == .float4,
                  slots.indices.contains(slot),
                  let candidate = slots[slot]?.resource.publication.candidate else {
                return nil
            }
            return encodeComponents([
                candidate.physicalSize.width,
                candidate.physicalSize.height,
                candidate.mappedSize.width,
                candidate.mappedSize.height,
            ].map(Double.init), as: type)
        }
    }

    static func encode(
        _ value: SceneResolvedMaterialTemplate.StaticUniformValue,
        as type: SceneAuthoredShaderValueType
    ) -> Data? {
        encodeComponents(
            value.componentBitPatterns.map { Double(bitPattern: $0) },
            as: type
        )
    }

    static func encode(
        _ value: SceneDynamicValue,
        as type: SceneAuthoredShaderValueType
    ) -> Data? {
        let components: [Double]
        switch value {
        case let .scalar(x): components = [x]
        case let .vector2(x, y): components = [x, y]
        case let .vector3(x, y, z): components = [x, y, z]
        case let .vector4(x, y, z, w): components = [x, y, z, w]
        case .bool, .string: return nil
        }
        return encodeComponents(components, as: type)
    }

    static func encodeComponents(
        _ components: [Double],
        as type: SceneAuthoredShaderValueType
    ) -> Data? {
        guard components.count == componentCount(type),
              components.allSatisfy(\.isFinite) else { return nil }
        switch type {
        case .bool:
            return nil
        case .int, .int2, .int3, .int4:
            guard components.allSatisfy({
                $0.rounded(.towardZero) == $0
                    && $0 >= Double(Int32.min) && $0 <= Double(Int32.max)
            }) else { return nil }
            return packed(components.map { Int32($0) }, byteSize: type.byteSize)
        case .uint, .uint2, .uint3, .uint4:
            guard components.allSatisfy({
                $0.rounded(.towardZero) == $0
                    && $0 >= 0 && $0 <= Double(UInt32.max)
            }) else { return nil }
            return packed(components.map { UInt32($0) }, byteSize: type.byteSize)
        case .float, .float2, .float3, .float4, .float2x2, .float4x4:
            let values = components.map(Float.init)
            guard values.allSatisfy(\.isFinite) else { return nil }
            return packed(values, byteSize: type.byteSize)
        case .float3x3:
            let values = components.map(Float.init)
            guard values.allSatisfy(\.isFinite) else { return nil }
            var data = Data(count: type.byteSize)
            for column in 0 ..< 3 {
                for row in 0 ..< 3 {
                    guard write(
                        values[column * 3 + row],
                        at: (column * 4 + row) * MemoryLayout<Float>.stride,
                        into: &data
                    ) else { return nil }
                }
            }
            return data
        }
    }

    private static func textureResolution(
        _ field: SceneAuthoredShaderUniformLayout.Field,
        slots: [Program.TextureSlot?]
    ) -> Program.HostUniform? {
        guard field.type == .float4,
              field.name.hasPrefix("g_Texture"),
              field.name.hasSuffix("Resolution") else { return nil }
        let start = field.name.index(field.name.startIndex, offsetBy: "g_Texture".count)
        let end = field.name.index(field.name.endIndex, offsetBy: -"Resolution".count)
        guard start < end, let slot = Int(field.name[start ..< end]),
              slots.indices.contains(slot), slots[slot] != nil else { return nil }
        return .textureResolution(slot: slot)
    }

    private static func encodeSize(
        _ size: CGSize,
        type: SceneAuthoredShaderValueType
    ) -> Data? {
        guard type == .float2, valid(size) else { return nil }
        return encodeComponents([size.width, size.height].map(Double.init), as: type)
    }

    private static func encodeScalar(
        _ value: Float,
        type: SceneAuthoredShaderValueType
    ) -> Data? {
        guard type == .float else { return nil }
        return encodeComponents([Double(value)], as: type)
    }

    private static func encodePointer(
        _ value: SIMD2<Float>,
        type: SceneAuthoredShaderValueType
    ) -> Data? {
        guard type == .float2, value.x.isFinite, value.y.isFinite else { return nil }
        return encodeComponents([
            Double((min(1, max(-1, value.x)) + 1) * 0.5),
            Double((1 - min(1, max(-1, value.y))) * 0.5),
        ], as: type)
    }

    private static func valid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private static func packed<T>(_ values: [T], byteSize: Int) -> Data? {
        var data = Data(count: byteSize)
        for (index, value) in values.enumerated() {
            guard write(
                value,
                at: index * MemoryLayout<T>.stride,
                into: &data
            ) else { return nil }
        }
        return data
    }

    private static func write<T>(
        _ value: T,
        at offset: Int,
        into data: inout Data
    ) -> Bool {
        var value = value
        return withUnsafeBytes(of: &value) { source in
            guard offset >= 0, offset <= data.count,
                  source.count <= data.count - offset else { return false }
            data.replaceSubrange(offset ..< offset + source.count, with: source)
            return true
        }
    }

    private static func componentCount(_ type: SceneAuthoredShaderValueType) -> Int {
        switch type {
        case .bool, .int, .uint, .float: 1
        case .int2, .uint2, .float2: 2
        case .int3, .uint3, .float3: 3
        case .int4, .uint4, .float4, .float2x2: 4
        case .float3x3: 9
        case .float4x4: 16
        }
    }
}
