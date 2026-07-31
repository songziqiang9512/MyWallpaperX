import simd

let sceneProceduralNoiseShaderSupportSource = """
float4 noiseHash44(float4 value) {
    value = fract(value * float4(0.1031, 0.1030, 0.0973, 444.129));
    value += dot(value, value.wzxy + 19.19);
    return fract((value.xxyz + value.yzzw) * value.zywx);
}

float2 noiseHash23(float3 value) {
    value = fract(value * float3(0.1031, 0.1030, 437.195));
    value += dot(value, value.yzx + 19.19);
    return fract((value.xx + value.yz) * value.zy);
}

float noiseValue2D(float2 coordinate, float seed) {
    float2 cell = floor(coordinate);
    float2 fraction = fract(coordinate);
    float2 blend = fraction * fraction * (3.0 - 2.0 * fraction);
    float a = noiseHash23(float3(cell, seed)).x;
    float b = noiseHash23(float3(cell + float2(1.0, 0.0), seed)).x;
    float c = noiseHash23(float3(cell + float2(0.0, 1.0), seed)).x;
    float d = noiseHash23(float3(cell + 1.0, seed)).x;
    return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}
"""

extension SceneProceduralNoisePipeline {
    struct Uniforms {
        var scale: SIMD2<Float>
        var offset: SIMD2<Float>
        var magnitude: SIMD2<Float>
        var thresholds: SIMD2<Float>
        var colorsMin: SIMD4<Float>
        var colorsMax: SIMD4<Float>
        var params0: SIMD4<Float>
        var params1: SIMD4<Float>
        var params2: SIMD4<Float>
        var perspective01: SIMD4<Float> = SIMD4(0, 0, 1, 0)
        var perspective23: SIMD4<Float> = SIMD4(1, 1, 0, 1)
        var params3: SIMD4<Float> = SIMD4(repeating: 1)
        var variant: UInt32
        var fractals: UInt32
        var padding: SIMD2<UInt32> = .zero
    }
}
