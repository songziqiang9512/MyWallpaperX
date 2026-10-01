<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF05 named provider 启动准备与显示分离（2026-10-02）

> **历史证据 — 非现役入口**。当前权威：[兼容路线](../../scene/scene-compatibility-roadmap.md)、[能力台账](../../scene/semantics/coverage-ledger.md)、[运行证据](../../scene/semantics/runtime-evidence-current.md)。后两份并行权威未改；本记录只保存本批冻结事实。

## 结果与职责

基线为接管后的主分支；本批三个产品文件：`SceneDesktopWallpaperHost+DeferredBaseImages.swift`、`SceneDependencyRenderPlan+ImageProgramReference.swift`、`SceneDependencyRenderPlan+BindingCompilation.swift`。设计见[启动资源准备合同](../../scene/design/scene-resource-admission.md)。没有新 registry、capture 或 publication owner。

1. Host 启动 defer 只豁免 static-model named providers，导致属性初值覆盖为隐藏的普通 image source 不加载，消费层显示白色原图。现复用唯一引用分析的普通及 potential optional named provider 集合，保证潜在 source 可准备；未消费隐藏图片仍 defer，terminal user texture 遮蔽不误加载，隐藏 consumer 的潜在来源可保守准备。
2. 已加载的普通图片初值可见时，又被 named composite 两入口拒绝。两入口共用现有 predicate，开放无 effects、无两类 dependencies、无 children、非 Puppet 普通图片，显示隐藏与 source 资格分离。旧 hidden 分支等价；generic 专属依赖约束保留在其调用处。可见 effectful image 仍走 graph-final，顺序、循环、purpose、预算及 generation 不放宽。

## 反例与实际验证

本机证据根 `/private/tmp/mwx-rf05-provider/`；自写 PNG、shader、scene/package，未改真实样本。最终 `manifest-final-v2.json` 固定三个产品、两个测试及20个 App payload 的 SHA256。签名 App 为 `frozen-v2.app`，CDHash `c944b19aa0ce46ea9c40230d404c40054ed573b6`；实际 Debug dylib SHA256 `c851a0f95f64b6d4145708338e6aea92456f054ed134cbbb4b14ec824d8c2e99`，metallib `991cdb9f9e431e782210cfeacb285fbf64d2d6736e13a27c59e7057c0718ffcc`。

- 修前冻结 App 三对照中，常量隐藏来源消费蓝色，无消费者保持黑色且 defer；属性隐藏来源却消费白色，绿色邻层正常。最终同输入 red 单门仍失败，输入 SHA 与修后一致。
- 首轮修后八门六过两败：初始可见→隐藏仍白；未声明用途的 optional RGBA shader 被现役用途准入拒绝。保留原日志，不把后者称为非法作者语法。
- visible 准入 Swift 红例成立；修后 dependency 模块28项通过，含显式/缺省可见、前向 capture、Puppet/children/deps 排除与 effectful 不进 raw。首次相邻 dependency/registry 37项通过（49.933s）；最终改动的 dependency 模块另跑28项。
- 最终同一 v2 App 七门通过（149.808s）加限定 exact-two-candidate rgbmask optional 门通过（20.603s）。七门执行时测试文件的 optional 分支尚未去掉重复 named，其余七门输入和断言未变；执行时源码另存 `integration-seven-run-source.py`，不能声称单次八门同一测试字节。覆盖常量隐藏、属性初值覆盖隐藏、无消费者 defer、隐藏 consumer 保守准备、live 双向、terminal shadow、optional unavailable 后 named fallback。中心蓝色/白色/黑色及绿色邻层按输入判定，provider 显示独立负 ROI；要求实际 named capture/binding、frame completion、terminal ready/after、next-frame 与 gpuDrained 退出。不是仅检查资源已加载。
- 完整 Debug build 与 strict/deep 签名通过；code-health 1047 Swift、0 error、237 review warnings；防御面0 dead/18 canonical/3 swallow保持，design-gate通过。独立终审结论另核同一源码、测试与冻结 App。

## 未关闭边界与下一批

optional 首次改用 rgbmask 后，真实解析产生 `material named → instance named → system userTexture` 三候选；它超出现役 mixed-provider 两候选 profile，并导致 `resourceSnapshotUnresolved` 阻断全场首帧。完整输入及 timeout 保存在 `optional-profile-v2/`。本批第八门仅移除材料层重复 named，保持 instance named + system 的既有合同与蓝色 oracle；没有将原三候选计为通过。

下一批先在现役 prepared/material 准入关闭这个未支持组合的失败半径：局部退化该 effect，保护健康层与终端，不泛吞 identity/snapshot 错误，不为通过扩大 matcher。该可见阻断修复后继续 D1 composition 层级与真实 source。任意 optional shader、三候选兼容、跨屏、性能提升及官方 parity 均未由本批证明。
