import CoreGraphics
import Foundation
import simd

nonisolated struct SceneAuthoredShaderFrameInputs {
    let screenSize: CGSize
    let sceneTime: Float
    let dayTime: Float
    let frameTime: Float
    let pointerCurrentNDC: SIMD2<Float>
    let pointerPreviousNDC: SIMD2<Float>
}

nonisolated struct SceneAuthoredShaderUniformInputs {
    let renderSize: CGSize
    let screenSize: CGSize
    let modelViewProjection: simd_float4x4
    let sceneTime: Float
    let dayTime: Float
    let frameTime: Float
    let pointerCurrentNDC: SIMD2<Float>
    let pointerPreviousNDC: SIMD2<Float>
    let texturePhysicalSizes: [Int: CGSize]
}

nonisolated enum SceneAuthoredShaderUniformBinder {
    typealias Plan = SceneAuthoredShaderExecutionPlan

    static func encode(
        plan: Plan,
        inputs: SceneAuthoredShaderUniformInputs
    ) -> Data? {
        guard validSize(inputs.renderSize),
              validSize(inputs.screenSize),
              validMatrix(inputs.modelViewProjection),
              inputs.sceneTime.isFinite,
              inputs.dayTime.isFinite,
              (0 ... 1).contains(inputs.dayTime),
              inputs.frameTime.isFinite,
              inputs.frameTime >= 0,
              validPointer(inputs.pointerCurrentNDC),
              validPointer(inputs.pointerPreviousNDC),
              validSize(plan.mappedSize),
              plan.program.uniformLayout.byteSize >= 0 else {
            return nil
        }
        var data = Data(count: plan.program.uniformLayout.byteSize)
        let encoded = data.withUnsafeMutableBytes { destination in
            plan.uniformBindings.allSatisfy { binding in
                encode(
                    binding,
                    plan: plan,
                    inputs: inputs,
                    destination: destination
                )
            }
        }
        return encoded ? data : nil
    }

    static func canEncodeConstant(
        _ components: [Double],
        as type: SceneAuthoredShaderValueType
    ) -> Bool {
        guard components.count == componentCount(type),
              components.allSatisfy(\.isFinite) else {
            return false
        }
        switch type {
        case .bool, .float2x2, .float3x3, .float4x4:
            return false
        case .int, .int2, .int3, .int4:
            return components.allSatisfy {
                $0.rounded(.towardZero) == $0
                    && $0 >= Double(Int32.min)
                    && $0 <= Double(Int32.max)
            }
        case .uint, .uint2, .uint3, .uint4:
            return components.allSatisfy {
                $0.rounded(.towardZero) == $0
                    && $0 >= 0
                    && $0 <= Double(UInt32.max)
            }
        case .float, .float2, .float3, .float4:
            return components.allSatisfy { Float($0).isFinite }
        }
    }

    private static func encode(
        _ binding: Plan.UniformBinding,
        plan: Plan,
        inputs: SceneAuthoredShaderUniformInputs,
        destination: UnsafeMutableRawBufferPointer
    ) -> Bool {
        let offset = binding.field.offset
        switch binding.source {
        case .renderSize:
            return writeFloats(
                [Float(inputs.renderSize.width), Float(inputs.renderSize.height)],
                at: offset,
                destination: destination
            )
        case .modelViewProjection:
            return writeMatrix(
                inputs.modelViewProjection,
                at: offset,
                destination: destination
            )
        case .time:
            return write(inputs.sceneTime, at: offset, destination: destination)
        case .dayTime:
            return write(inputs.dayTime, at: offset, destination: destination)
        case .frameTime:
            return write(inputs.frameTime, at: offset, destination: destination)
        case .pointerPosition:
            return writeFloats(
                screenPosition(inputs.pointerCurrentNDC),
                at: offset,
                destination: destination
            )
        case .pointerPositionLast:
            return writeFloats(
                screenPosition(inputs.pointerPreviousNDC),
                at: offset,
                destination: destination
            )
        case .screen:
            let width = Float(inputs.screenSize.width)
            let height = Float(inputs.screenSize.height)
            return writeFloats(
                [width, height, width / height],
                at: offset,
                destination: destination
            )
        case .texelSize(let scale):
            let width = Double(inputs.screenSize.width)
            let height = Double(inputs.screenSize.height)
            return writeFloats(
                [Float(scale / width), Float(scale / height)],
                at: offset,
                destination: destination
            )
        case .textureResolution(let slot):
            guard let physical = inputs.texturePhysicalSizes[slot],
                  validSize(physical) else {
                return false
            }
            return writeFloats(
                [
                    Float(physical.width),
                    Float(physical.height),
                    Float(plan.mappedSize.width),
                    Float(plan.mappedSize.height),
                ],
                at: offset,
                destination: destination
            )
        case .constant(let components):
            return writeConstant(
                components,
                type: binding.field.type,
                at: offset,
                destination: destination
            )
        }
    }

    private static func writeConstant(
        _ components: [Double],
        type: SceneAuthoredShaderValueType,
        at offset: Int,
        destination: UnsafeMutableRawBufferPointer
    ) -> Bool {
        guard canEncodeConstant(components, as: type) else { return false }
        switch type {
        case .int, .int2, .int3, .int4:
            return writeValues(
                components.map { Int32($0) },
                at: offset,
                destination: destination
            )
        case .uint, .uint2, .uint3, .uint4:
            return writeValues(
                components.map { UInt32($0) },
                at: offset,
                destination: destination
            )
        case .float, .float2, .float3, .float4:
            return writeFloats(
                components.map(Float.init),
                at: offset,
                destination: destination
            )
        case .bool, .float2x2, .float3x3, .float4x4:
            return false
        }
    }

    private static func screenPosition(_ ndc: SIMD2<Float>) -> [Float] {
        let x = min(1, max(-1, ndc.x))
        let y = min(1, max(-1, ndc.y))
        return [(x + 1) * 0.5, (1 - y) * 0.5]
    }

    private static func writeMatrix(
        _ matrix: simd_float4x4,
        at offset: Int,
        destination: UnsafeMutableRawBufferPointer
    ) -> Bool {
        let components = [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w,
        ]
        return writeFloats(components, at: offset, destination: destination)
    }

    private static func writeFloats(
        _ values: [Float],
        at offset: Int,
        destination: UnsafeMutableRawBufferPointer
    ) -> Bool {
        writeValues(values, at: offset, destination: destination)
    }

    private static func writeValues<T>(
        _ values: [T],
        at offset: Int,
        destination: UnsafeMutableRawBufferPointer
    ) -> Bool {
        values.enumerated().allSatisfy { index, value in
            write(
                value,
                at: offset + index * MemoryLayout<T>.stride,
                destination: destination
            )
        }
    }

    private static func write<T>(
        _ value: T,
        at offset: Int,
        destination: UnsafeMutableRawBufferPointer
    ) -> Bool {
        var value = value
        return withUnsafeBytes(of: &value) { source in
            guard offset >= 0,
                  offset <= destination.count,
                  source.count <= destination.count - offset,
                  let sourceAddress = source.baseAddress,
                  let destinationAddress = destination.baseAddress else {
                return false
            }
            destinationAddress.advanced(by: offset).copyMemory(
                from: sourceAddress,
                byteCount: source.count
            )
            return true
        }
    }

    private static func validSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite
            && size.width > 0 && size.height > 0
            && Float(size.width).isFinite && Float(size.height).isFinite
    }

    private static func validPointer(_ pointer: SIMD2<Float>) -> Bool {
        pointer.x.isFinite && pointer.y.isFinite
    }

    private static func validMatrix(_ matrix: simd_float4x4) -> Bool {
        [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
            .allSatisfy { column in
                column.x.isFinite && column.y.isFinite
                    && column.z.isFinite && column.w.isFinite
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
