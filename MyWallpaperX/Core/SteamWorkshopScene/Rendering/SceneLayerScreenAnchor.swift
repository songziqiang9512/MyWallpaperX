import simd

/// WE 的 text layer `anchor`（编辑器里的 "Screen anchor"）把 layer 钉在可见屏幕矩形的
/// 某个边角上，而不是钉在作者画布上：画布宽高比和实际 drawable 不一致时，cover 投影会
/// 裁掉长边，没有 anchor 的 HUD 文本就会跟着被裁到屏幕外。随包 `dino_run` 的两个记分
/// 标签（`label_coins`/`label_top`）就是官方给出的用例，两者都是 `topright`。
///
/// 取值域来自 lib.sceneScript.d.ts 的 ITextLayer：none/center/top/topright/right/
/// bottomright/bottom/bottomleft/left/topleft。`none`、缺省和未知取值都不偏移。
///
/// 注意渲染世界空间是 y 向下的：SceneLayerWorldFrameResolver 用 `orthoHeight - origin.y`
/// 把作者的 y 向上坐标翻过来，所以 "top" 取可见矩形的 minY、"bottom" 取 maxY。
nonisolated enum SceneLayerScreenAnchor {
    /// 偏移量 = 可见矩形上的锚点 - 作者画布上的同名锚点。作者宽高比下两者相等，偏移为
    /// 零，也就是完全保留作者摆位；宽高比变化时 layer 跟着可见边角走，锚定边距不变。
    nonisolated static func offset(
        anchor: String?,
        orthoSize: SIMD2<Float>,
        cameraEyeOffset: SIMD2<Float>,
        visibleHalfExtents: SIMD2<Float>
    ) -> SIMD2<Float> {
        guard let factors = factors(anchor),
              orthoSize.x > 0, orthoSize.y > 0,
              visibleHalfExtents.x > 0, visibleHalfExtents.y > 0
        else {
            return .zero
        }
        let designHalf = orthoSize * 0.5
        let designAnchor = designHalf + factors * designHalf
        let visibleAnchor = designHalf + cameraEyeOffset + factors * visibleHalfExtents
        let shift = visibleAnchor - designAnchor
        guard shift.x.isFinite, shift.y.isFinite else { return .zero }
        return shift
    }

    // x: -1 左 / 0 中 / +1 右；y: -1 上 / 0 中 / +1 下（世界 y 向下）。
    private nonisolated static func factors(_ anchor: String?) -> SIMD2<Float>? {
        switch anchor?.lowercased() {
        case "center": return SIMD2(0, 0)
        case "top": return SIMD2(0, -1)
        case "topright": return SIMD2(1, -1)
        case "right": return SIMD2(1, 0)
        case "bottomright": return SIMD2(1, 1)
        case "bottom": return SIMD2(0, 1)
        case "bottomleft": return SIMD2(-1, 1)
        case "left": return SIMD2(-1, 0)
        case "topleft": return SIMD2(-1, -1)
        default: return nil
        }
    }
}
