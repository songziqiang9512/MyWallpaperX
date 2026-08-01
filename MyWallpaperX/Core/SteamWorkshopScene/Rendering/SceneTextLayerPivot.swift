import simd

/// WE 的 text layer 用 `horizontalalign`/`verticalalign` 同时决定两件事：文本在栅格框
/// 内怎么排（已由 SceneTextTextureLoader 交给 CoreText），以及内容框相对 layer origin
/// 落在哪。作者 `size` 已包含 `padding`，所以边对齐时 origin 落在去掉 padding 后的
/// 内容边缘；外框还要越过 origin 延伸一圈 padding，供文字 effect 使用。
///
/// 取值域来自 lib.sceneScript.d.ts 的 ITextLayer：horizontalalign 为 left/center/right，
/// verticalalign 为 center/top/bottom。缺省和未知取值都按 center 处理，也就是不偏移。
///
/// 零 padding 判据来自随包 `dino_run`：`label_coins` 与 `label_top` 都是 `horizontalalign: right`
/// 且共用 `origin.x = 341.42999`（画布宽 343），但作者 size 相差一倍（780 与 390，
/// scale 同为 0.057，世界宽 44.46 与 22.23）。几何中心 pivot 会让两者右边缘相差 22.23
/// 并分别越过右边界 20.66 / 9.55；取右边缘 pivot 后两者右边缘齐平在 341.43，边距同为
/// 1.57。三个 preset text layer（previewcountdown/previewclock/preview3dclock）都是
/// `center`/`center` 且 `origin.x` 正好是 256 画布的中心 128，取中心 pivot 不动。
nonisolated enum SceneTextLayerPivot {
    /// 返回单位 quad 空间（x/y 各 ∈ [-0.5, 0.5]）里的平移量，要放在 sizeScale 之后，
    /// 这样它会被作者 size 与 layer scale 一起缩放，并留在 layer 旋转内部。
    nonisolated static func unitOffset(
        horizontal: String?,
        vertical: String?,
        renderSize: SIMD2<Float>,
        padding: Float
    ) -> SIMD2<Float> {
        let inset = max(0, padding)
        return SIMD2(
            horizontalOffset(horizontal, inset: normalizedInset(inset, extent: renderSize.x)),
            verticalOffset(vertical, inset: normalizedInset(inset, extent: renderSize.y))
        )
    }

    /// 把命名的内容边推到 origin；外框仍会在该边外侧保留 padding。
    private nonisolated static func horizontalOffset(_ value: String?, inset: Float) -> Float {
        switch value?.lowercased() {
        case "left": return 0.5 - inset
        case "right": return -0.5 + inset
        default: return 0
        }
    }

    /// sizeScale 的 -size.y 会把单位 quad 的 +y 翻成画面上边，所以 `top` 与 `right`
    /// 同向补偿：内容上边落在 origin，外框再越过它保留 padding。
    private nonisolated static func verticalOffset(_ value: String?, inset: Float) -> Float {
        switch value?.lowercased() {
        case "top": return -0.5 + inset
        case "bottom": return 0.5 - inset
        default: return 0
        }
    }

    private nonisolated static func normalizedInset(_ padding: Float, extent: Float) -> Float {
        guard extent.isFinite, extent > 0 else { return 0 }
        return min(0.5, padding / extent)
    }
}
