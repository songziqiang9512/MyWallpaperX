import Foundation

/// D8 — RT 名称单点准入分派表（语义词汇表）。
///
/// WE 来源 `_rt_` 前缀 RT 名只在 prepare 阶段经本表解释一次，转换为 typed
/// 结果；下游消费者不再各自内联匹配 `_rt_` 字符串。本表是编译输入分类，
/// 不是资源 registry：allocation、publication 仍由现役资源 owner 决定。
///
/// 首批仅收录当前仓库内有直接证据的名字（设计裁决：不从 Mirage 抄完整名称
/// 表，其余前缀的官方行为规格须走官方客户端行为研究工作流定案后才准入）：
/// - `_rt_FullFrameBuffer`（精确名，任意大小写整名匹配且优先于 `_rt_` 前缀门
///   ——与 HEAD 基线纹理槽入口 caseInsensitiveCompare 的既有可观察行为一致，
///   大小写变体不得退化为磁盘资产引用）：命运 = 改写为既有 typed frame input，
///   必须绑定相应 frame/publication，不能映射成磁盘路径。
/// - `_rt_MipMappedFrameBuffer`（精确名）：引用现役 completed scene color
///   派生的 typed sceneEnvironment；资源不可用不造替代纹理。
/// - `_rt_imageLayerComposite_<layerID>[_a|_b]`（语法 family，唯一解析 owner
///   是 `SceneNamedTextureReference`）：命运 = 改写为 typed provider reference，
///   保留 provider ID 与 a/b variant；缺 producer 不造纹理。
///
/// Mirage 第三方结构参考（仅对照材料、不升官方语义）记载的 WE 来源全集另有
/// FullCompoBuffer/HalfCompoBuffer/QuarterCompoBuffer/EightBuffer/
/// shadowAtlas/Reflection/volumetrics/QuarterForceRG/
/// Bloom/QuarterFrameBuffer/EighthFrameBuffer 及 sr 自造名（`_rt_default`、
/// `_rt_link_`、effect_pingpong_a/b、bloom_mip）：在官方行为规格定案前一律
/// 不作为本表准入门，也不得被实现顺手裁决。
nonisolated enum SceneRenderTargetVocabulary {
    /// 内部 RT 前缀的唯一常量来源；运行期消费者不得再内联 `_rt_` 字面量。
    static let internalTargetPrefix = "_rt_"

    private static let fullFrameBufferName = "_rt_FullFrameBuffer"
    private static let sceneEnvironmentName = "_rt_MipMappedFrameBuffer"

    /// 作者显式 `_rt_` 名的四种命运。空/占位绑定（清空 binding）在 schema
    /// 空串门处理，不经本分派；作者显式声明的 FBO 经 graph binding 到达，
    /// 不走本字符串面。
    enum Fate: Hashable {
        /// 已证实 FullFrameBuffer 内建别名：改写为既有 typed frame input。
        case typedFrameInput
        /// Completed scene color, derived once into the frame's shared mip chain.
        case sceneEnvironment
        /// 已证实 imageLayerComposite 语法：改写为 typed provider reference。
        case namedLayerTarget(SceneNamedTextureReference)
        /// 未知/畸形 `_rt_`：不准入，保留诊断 token 交调用方硬拒绝；
        /// 不清空、不假装成功。
        case unadmitted(String)
    }

    /// 单点准入分派。输入是作者原样值。FullFrameBuffer 与既有可观察行为一致：
    /// 任意大小写的整名匹配优先于 `_rt_` 前缀门（`_RT_FullFrameBuffer` 等变体
    /// 同样是内建别名，绝不能退化为磁盘资产引用）；imageLayerComposite 语法
    /// family 按其解析 owner 的现行大小写敏感规则匹配；大小写冲突统一前不全局
    /// lowercasing。
    static func dispatch(authoredName: String) -> Fate {
        if authoredName.caseInsensitiveCompare(fullFrameBufferName) == .orderedSame {
            return .typedFrameInput
        }
        if authoredName == sceneEnvironmentName { return .sceneEnvironment }
        guard authoredName.hasPrefix(internalTargetPrefix) else {
            return .unadmitted(authoredName)
        }
        if let reference = SceneNamedTextureReference.parse(authoredName) {
            return .namedLayerTarget(reference)
        }
        return .unadmitted(authoredName)
    }
}
