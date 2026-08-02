/// WE `common_blending.h` 的 `ApplyBlending` imageblending 语义等价实现。
///
/// 模式编号取自官方 `ApplyBlending` 的 `BLENDMODE` 分派表（接口契约）；混合数学本身
/// 是公开的 Photoshop/PDF 混合模式定义，这里是自研 Metal 实现，未搬运官方 shader。
///
/// 官方用 `#if BLENDMODE == N` 预处理器为每个模式编译独立变体，这里改为运行时 uniform
/// switch —— 全屏 quad 上分支开销可忽略，换取单一 pipeline。
///
/// 三个模式与"mix(A, f(A,B), o)"的通式不同，照官方原样保留：
/// - 模式 5 `min(A,B)` 与模式 10 `max(A,B)` 完全忽略 opacity；
/// - 模式 31 是 `A + B*o`，不是 mix。
enum SceneBlendModeShaderSource {
    static let blendFunctions = """
    #include <metal_stdlib>
    using namespace metal;

    static inline float weLinearDodge(float b, float s) { return b + s; }
    static inline float weLinearBurn(float b, float s) { return max(b + s - 1.0, 0.0); }
    static inline float weScreen(float b, float s) { return 1.0 - (1.0 - b) * (1.0 - s); }

    static inline float weOverlay(float b, float s) {
        return b < 0.5 ? (2.0 * b * s) : (1.0 - 2.0 * (1.0 - b) * (1.0 - s));
    }

    static inline float weSoftLight(float b, float s) {
        return s < 0.5 ? (2.0 * b * s + b * b * (1.0 - 2.0 * s))
                       : (sqrt(b) * (2.0 * s - 1.0) + 2.0 * b * (1.0 - s));
    }

    static inline float weColorDodge(float b, float s) {
        return s == 1.0 ? s : min(b / (1.0 - s), 1.0);
    }

    static inline float weColorBurn(float b, float s) {
        return s == 0.0 ? s : max(1.0 - (1.0 - b) / s, 0.0);
    }

    static inline float weLinearLight(float b, float s) {
        return s < 0.5 ? weLinearBurn(b, 2.0 * s) : weLinearDodge(b, 2.0 * (s - 0.5));
    }

    static inline float weVividLight(float b, float s) {
        return s < 0.5 ? weColorBurn(b, 2.0 * s) : weColorDodge(b, 2.0 * (s - 0.5));
    }

    static inline float wePinLight(float b, float s) {
        return s < 0.5 ? min(b, 2.0 * s) : max(b, 2.0 * (s - 0.5));
    }

    static inline float weHardMix(float b, float s) {
        return weVividLight(b, s) < 0.5 ? 0.0 : 1.0;
    }

    static inline float weReflect(float b, float s) {
        return s == 1.0 ? s : min(b * b / (1.0 - s), 1.0);
    }

    // 逐分量展开成 float3 版本。宏参数名必须避开 r/g/b，否则 (b).b 会被展开成 (b).B。
    #define WE_VEC3_OF(name, fn) \\
    static inline float3 name(float3 p, float3 q) { \\
        return float3(fn(p.r, q.r), fn(p.g, q.g), fn(p.b, q.b)); \\
    }

    WE_VEC3_OF(weScreen3, weScreen)
    WE_VEC3_OF(weOverlay3, weOverlay)
    WE_VEC3_OF(weSoftLight3, weSoftLight)
    WE_VEC3_OF(weColorDodge3, weColorDodge)
    WE_VEC3_OF(weColorBurn3, weColorBurn)
    WE_VEC3_OF(weLinearLight3, weLinearLight)
    WE_VEC3_OF(weVividLight3, weVividLight)
    WE_VEC3_OF(wePinLight3, wePinLight)
    WE_VEC3_OF(weHardMix3, weHardMix)
    WE_VEC3_OF(weReflect3, weReflect)

    static inline float3 weRGBToHSL(float3 c) {
        float lo = min(min(c.r, c.g), c.b);
        float hi = max(max(c.r, c.g), c.b);
        float delta = hi - lo;
        float3 hsl = float3(0.0, 0.0, (hi + lo) / 2.0);
        if (delta == 0.0) { return hsl; }
        hsl.y = hsl.z < 0.5 ? (delta / (hi + lo)) : (delta / (2.0 - hi - lo));
        float dR = (((hi - c.r) / 6.0) + (delta / 2.0)) / delta;
        float dG = (((hi - c.g) / 6.0) + (delta / 2.0)) / delta;
        float dB = (((hi - c.b) / 6.0) + (delta / 2.0)) / delta;
        if (c.r == hi) { hsl.x = dB - dG; }
        else if (c.g == hi) { hsl.x = (1.0 / 3.0) + dR - dB; }
        else if (c.b == hi) { hsl.x = (2.0 / 3.0) + dG - dR; }
        if (hsl.x < 0.0) { hsl.x += 1.0; }
        else if (hsl.x > 1.0) { hsl.x -= 1.0; }
        return hsl;
    }

    static inline float weHueToRGB(float f1, float f2, float hue) {
        if (hue < 0.0) { hue += 1.0; }
        else if (hue > 1.0) { hue -= 1.0; }
        if ((6.0 * hue) < 1.0) { return f1 + (f2 - f1) * 6.0 * hue; }
        if ((2.0 * hue) < 1.0) { return f2; }
        if ((3.0 * hue) < 2.0) { return f1 + (f2 - f1) * ((2.0 / 3.0) - hue) * 6.0; }
        return f1;
    }

    static inline float3 weHSLToRGB(float3 hsl) {
        if (hsl.y == 0.0) { return float3(hsl.z); }
        float f2 = hsl.z < 0.5 ? (hsl.z * (1.0 + hsl.y))
                               : ((hsl.z + hsl.y) - (hsl.y * hsl.z));
        float f1 = 2.0 * hsl.z - f2;
        return float3(weHueToRGB(f1, f2, hsl.x + (1.0 / 3.0)),
                      weHueToRGB(f1, f2, hsl.x),
                      weHueToRGB(f1, f2, hsl.x - (1.0 / 3.0)));
    }

    static inline float3 weBlendHue(float3 base, float3 blend) {
        float3 baseHSL = weRGBToHSL(base);
        return weHSLToRGB(float3(weRGBToHSL(blend).x, baseHSL.y, baseHSL.z));
    }

    static inline float3 weBlendSaturation(float3 base, float3 blend) {
        float3 baseHSL = weRGBToHSL(base);
        return weHSLToRGB(float3(baseHSL.x, weRGBToHSL(blend).y, baseHSL.z));
    }

    static inline float3 weBlendColor(float3 base, float3 blend) {
        float3 blendHSL = weRGBToHSL(blend);
        return weHSLToRGB(float3(blendHSL.x, blendHSL.y, weRGBToHSL(base).z));
    }

    static inline float3 weBlendLuminosity(float3 base, float3 blend) {
        float3 baseHSL = weRGBToHSL(base);
        return weHSLToRGB(float3(baseHSL.x, baseHSL.y, weRGBToHSL(blend).z));
    }

    float3 sceneApplyBlending(int mode, float3 A, float3 B, float o) {
        switch (mode) {
        case 1:  return mix(A, min(B, A), o);
        case 2:  return mix(A, A * B, o);
        case 3:  return mix(A, weColorBurn3(A, B), o);
        case 4:  return mix(A, max(A + B - 1.0, 0.0), o);
        case 5:  return min(A, B);
        case 6:  return mix(A, max(B, A), o);
        case 7:  return mix(A, weScreen3(A, B), o);
        case 8:  return mix(A, weColorDodge3(A, B), o);
        case 9:  return mix(A, min(A + B, 1.0), o);
        case 10: return max(A, B);
        case 11: return mix(A, weOverlay3(A, B), o);
        case 12: return mix(A, weSoftLight3(A, B), o);
        case 13: return mix(A, weOverlay3(B, A), o);
        case 14: return mix(A, weVividLight3(A, B), o);
        case 15: return mix(A, weLinearLight3(A, B), o);
        case 16: return mix(A, wePinLight3(A, B), o);
        case 17: return mix(A, weHardMix3(A, B), o);
        case 18: return mix(A, abs(A - B), o);
        case 19: return mix(A, A + B - 2.0 * A * B, o);
        case 20: return mix(A, max(A + B - 1.0, 0.0), o);
        case 21: return mix(A, weReflect3(A, B), o);
        case 22: return mix(A, weReflect3(B, A), o);
        case 23: return mix(A, min(A, B) - max(A, B) + 1.0, o);
        case 24: return mix(A, (A + B) / 2.0, o);
        case 25: return mix(A, 1.0 - abs(1.0 - A - B), o);
        case 26: return mix(A, weBlendHue(A, B), o);
        case 27: return mix(A, weBlendSaturation(A, B), o);
        case 28: return mix(A, weBlendColor(A, B), o);
        case 29: return mix(A, weBlendLuminosity(A, B), o);
        case 30: return mix(A, max(A.x, max(A.y, A.z)) * B, o);
        case 31: return A + B * o;
        case 32: return mix(A, A + A * B, o);
        default: return mix(A, B, o);
        }
    }
    """

    /// 官方 `ApplyBlending` 分派表覆盖的模式编号上界；超出一律落回 Normal。
    nonisolated static let maximumMode = 32
}
