#if DEBUG
import Foundation
import Metal
import simd

private let sceneCursorRippleVisibleEvidenceShader = """
#include <metal_stdlib>
using namespace metal;

kernel void sceneCursorRippleVisibleDifference(
    texture2d<float, access::sample> source [[texture(0)]],
    texture2d<float, access::sample> output [[texture(1)]],
    device uchar2 *result [[buffer(0)]],
    uint2 position [[thread_position_in_grid]],
    uint2 gridSize [[threads_per_grid]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float2 uv = (float2(position) + 0.5) / float2(gridSize);
    float3 difference = abs(
        source.sample(linearClamp, uv).rgb
            - output.sample(linearClamp, uv).rgb
    );
    uint maximum = uint(round(saturate(max(
        difference.r,
        max(difference.g, difference.b)
    )) * 255.0));
    uint index = position.y * gridSize.x + position.x;
    result[index] = uchar2(uchar(maximum), uchar(maximum > 2));
}
"""

struct SceneCursorRippleVisibleOutputEvidence {
    private let pipeline: MTLComputePipelineState

    init?(device: MTLDevice) {
        guard let library = try? device.makeLibrary(
            source: sceneCursorRippleVisibleEvidenceShader,
            options: MTLCompileOptions()
        ),
              let function = library.makeFunction(
                  name: "sceneCursorRippleVisibleDifference"
              ),
              let pipeline = try? device.makeComputePipelineState(
                  function: function
              ) else { return nil }
        self.pipeline = pipeline
    }

    func encode(
        source: MTLTexture,
        output: MTLTexture,
        plan: SceneCursorRippleExecutionPlan,
        currentCursorUV: SIMD2<Float>,
        previousCursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        previousPointerIsInside: Bool,
        pointerMovement: Float,
        commandBuffer: MTLCommandBuffer
    ) {
        guard Self.enabled,
              source.width == output.width,
              source.height == output.height,
              source.pixelFormat == .bgra8Unorm,
              output.pixelFormat == .bgra8Unorm,
              source.usage.contains(.shaderRead),
              output.usage.contains(.shaderRead),
              let result = source.device.makeBuffer(
                  length: Self.byteCount,
                  options: .storageModeShared
              ),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(output, index: 1)
        encoder.setBuffer(result, offset: 0, index: 0)
        encoder.dispatchThreads(
            MTLSize(
                width: Self.gridWidth,
                height: Self.gridHeight,
                depth: 1
            ),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        encoder.endEncoding()

        commandBuffer.addCompletedHandler { buffer in
            guard buffer.status == .completed else {
                NSLog(
                    "MWX DEBUG SCENE: phase=cursor-ripple-visible layer=%d effect=%d descriptor=%@ status=gpu-%ld",
                    plan.layerID,
                    plan.effectKey.effectIndex,
                    plan.effectKey.descriptorID,
                    buffer.status.rawValue
                )
                return
            }
            let bytes = result.contents().assumingMemoryBound(to: UInt8.self)
            var minimumX = Self.gridWidth
            var minimumY = Self.gridHeight
            var maximumX = -1
            var maximumY = -1
            var changedPixels = 0
            var maximumDifference = 0
            var differenceSum: UInt64 = 0
            for y in 0 ..< Self.gridHeight {
                for x in 0 ..< Self.gridWidth {
                    let offset = (y * Self.gridWidth + x) * 2
                    guard bytes[offset + 1] != 0 else { continue }
                    let difference = Int(bytes[offset])
                    changedPixels += 1
                    minimumX = min(minimumX, x)
                    minimumY = min(minimumY, y)
                    maximumX = max(maximumX, x)
                    maximumY = max(maximumY, y)
                    maximumDifference = max(maximumDifference, difference)
                    differenceSum += UInt64(difference)
                }
            }
            NSLog(
                "MWX DEBUG SCENE: phase=cursor-ripple-visible layer=%d effect=%d descriptor=%@ status=completed width=%d height=%d changedPixels=%d bounds=%d,%d,%d,%d max=%d sum=%llu current=%.6f,%.6f previous=%.6f,%.6f inside=%@ previousInside=%@ movement=%.6f",
                plan.layerID,
                plan.effectKey.effectIndex,
                plan.effectKey.descriptorID,
                Self.gridWidth,
                Self.gridHeight,
                changedPixels,
                minimumX,
                minimumY,
                maximumX,
                maximumY,
                maximumDifference,
                differenceSum,
                currentCursorUV.x,
                currentCursorUV.y,
                previousCursorUV.x,
                previousCursorUV.y,
                pointerIsInside ? "true" : "false",
                previousPointerIsInside ? "true" : "false",
                pointerMovement
            )
        }
    }

    private static let gridWidth = 256
    private static let gridHeight = 256
    private static let byteCount = gridWidth * gridHeight * 2
    private static let enabled = ProcessInfo.processInfo.environment[
        "MYWALLPAPERX_SCENE_DEBUG_CURSOR_RIPPLE_EVIDENCE"
    ] == "1"
}
#endif
