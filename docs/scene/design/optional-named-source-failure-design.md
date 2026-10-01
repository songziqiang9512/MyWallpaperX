<!-- document-role: active-plan -->
<!-- retirementCondition: 未支持optional/named组合的launch局部失败、同输入真实输出与相邻支持profile反例通过，稳定材质失败合同接管后归档并删除临时门禁登记。 -->

# 未支持 optional/named 组合的失败半径

本卡 approved，属于[兼容路线](../scene-compatibility-roadmap.md) RF05 后继；五判据①②④命中：跨 prepared stage 与执行输出、唯一依赖/失败合同及冻结材质家族。只使用本项目源码与自写输入的行为证据，不扩作者 profile，不读取参考项目实现。

## 目标合同与现状

合法作者输入超出现役 mixed-provider profile 时，只退化已证明可安全跳过的 effect，保留其入口颜色、其他层和相邻有效效果。不能让局部视觉不支持反复阻断全场首帧；identity、cycle、range、history 与 target 生命周期错误继续硬拒绝最小 unsafe unit。

`SceneAuthoredMaterialResolver.swift:105–119,247` 依次保留 material named、instance named、system userTexture 三项 provenance；`SceneResolvedMaterialExecutionCapabilityVariant+ProviderSlots.swift:48–64` 的 exact mixed 合同只接受两候选。`SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift:582–608` 不申领该未证明 named dependency，stage却可继续准入。运行时选到 unavailable system 后，`SceneResolvedMaterialTextureResolver.swift:351–356` 产生 resourceSnapshotUnresolved；`SceneResolvedMaterialGraphExecutor+Preparation.swift:255–261` 缺局部失败证明，整帧反复拒绝。

真实修前输入与签名 App 见[RF05 执行记录](../../history/scene/rf05-named-provider-readiness-implementation-2026-10-02.md)的三候选边界；本机 package SHA256 为 `905a211c779383c75961e471d1f5495ab0b5e87263398218cb76af05e7c98274`，日志记录 rendered=0、151次尝试均drop。退出成功不等于呈现成功。路径行号为 `5f603403` 附近定位线索，实施需按冻结代码重核。

## owner、方案与备选

选现役 `SceneResolvedMaterialExecutionCapability+Stages`：先执行真实 variant、active demand、invariant验证，再检查 launchEnvelopeActiveTextureSlots 中没有 authoritative graph override、terminal candidate 为现typed OptionalInput且lower candidate有named的实际slot。复用现 exact mixed proof；未证明时产生可归因到node/slot的专用 launch rejection。全inactive、静态asset/graph终端遮蔽不触发。不修改候选IR、顺序、purpose或选择器，不新增 matcher/helper family。

`+ProgramFirstStages` 的现失败fold只将该专用reason送入既有 `dependencyStageFailureMayPassthrough`，保留no-clear约束；失败stage不安装materials或申领named执行，相邻支持stage沿原ownership/order守恒。`SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough` 消费同reason且复用相同无history窄拓扑，不能加入更宽的ordinary history-capable列表。

备选扩大frame-time吞错会混淆缺资源与identity错误；去重作者候选或放宽exact2会改变支持合同；引入新依赖结果类型会扩多个owner。本片均不选。新增拒绝的产生者是上述真实三候选模板，拒绝范围只能缩小到这个未证明的活跃optional/named责任。

## fallback、纠正门与退役

安全拓扑按现有effect-entry passthrough；clear/history/copy/swap等不满足安全证明时沿既有拒绝，不捏造history或publication。不得把局部白色原图称为三候选named fallback执行成功。

验收：真实作者解析保留三候选及provenance；launch仅该stage退化、零材料/依赖申领；同修前package在签名App出现首帧/next-frame completion、白consumer和绿peer、无timeout及虚假capture；相邻支持effect继续执行；exact2 system/property的ready/absent/pending/unavailable原合同不回退；inactive/terminal-shadow/graph override不误拒绝；不同provider、secondary、错误slot identity及unsafe拓扑不被归一化。Swift行为门、Debug build、code-health、防御/设计门和独立终审均按本片失败半径执行。

稳定材质失败合同接管且上述门通过后归档本设计并删除临时登记；未来扩大mixed profile必须另行设计，不能用本片安全输出当兼容性完成。
