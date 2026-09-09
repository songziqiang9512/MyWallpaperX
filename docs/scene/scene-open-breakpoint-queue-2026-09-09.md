<!-- document-role: active-plan -->

# Scene 现存断点修复队列（2026-09-09，现役 P1 派生执行入口）

> 状态：现役高优先级 P1 派生计划队列。本文不拥有阶段顺序或完成门；唯一现役路线仍是[Scene 兼容执行路线](scene-compatibility-roadmap.md)，队列仅提供按当前证据排序的执行入口。

> 本文是给修复实施者的**可执行队列**。每一条都在当前代码中核实过 owner 位置（文件 + 行号 + 符号），不是从旧文档转述。样本 ID 只用于复现证据，不得进入产品代码。
>
> **与执行路线的关系**：[执行路线](scene-compatibility-roadmap.md)拥有阶段顺序和完成门；本文是 2026-09-09 当时事实下 P1（公共首断点清零）的**派生批次队列**，不拥有当前顺序权威。路线的 P1 子顺序（`unified-capability-unavailable` → `admitted-fallback` passthrough → `graph-execution-missing`）中，近期代表批次已处理，剩余数量以最新台账和后继复跑为准（见 §0）；本文的 B1→B9 是把当时断点映射回该框架后的执行入口（映射见 §0.2）。
>
> **队列规则**：默认按 B1 → B2 → … 处理；若两个条目的 owner、验证样本和文档职责边界互不重叠，可并行推进，但必须在合入前分别完成各自的最小正反门，并串行处理共享 owner 或前置结果依赖。动手前先核对“状态”列与当前代码是否仍然一致（并行会话可能已合入修复）。每修完一条：
> 1. 在本文档把该条状态改为 `已修复（<日期>，<commit/证据链接>）`，或整条删除；
> 2. 按工作流更新权威文档（能力台账 / 专项表 / 样本调试台账），本文不替代它们；
> 3. 按路线 §4 记录完成状态（`slice-visible` / `owner-migration`），样本可见结果变化写入样本调试台账、人工裁决变化写入验收覆盖层；路线正文只在阶段状态或完成门改变时更新；
> 4. 若修复过程中发现新的共享断点，按同一条目格式追加到队列尾部。
>
> 本文与权威文档冲突时以权威文档和当前代码为准。

## 0. 证据基础

- 复现环境：隔离样本副本 + 隔离 HOME，`script/scene_wallpaper_benchmark.py`，真实 `requestLaunch` 异步入口，12 秒 / after 9 秒，`--audio-spectrum-silence-fixture`，identity-only 矩阵。09-09 的 48 样本探测是全量历史快照；当前可复核的后继结果是同一工作树签名包的 12 样本串行复跑（每个样本独立 runtime root）。
- 被测 App：48 样本历史快照使用 CDHash `0764dc19bb535571c621f0bbfc0322a4d77db924`（2.0.9 (277)，构建于 09-08 23:29）；当前 12 样本复跑使用 CDHash `7ce6a2fff1b12f8771c4fc768f9a2f204107e1c1`、executable SHA-256 `6edd66b54bbf6486560efe92e270a8bba616faf0b5619c6b9c504bf01c3570e5`。两者均只作对应快照的 provenance，当前状态以 12 样本报告和现役台账为准。
- 口径：队列中的"复现"指结构门 FAIL 或日志中出现对应 passthrough/reason，**不等于视觉验收**。结构 PASS 但人工裁决 fail 的样本清单见附录 C。
- 09-07 归档中 `texture-load`、`particle-load`、`scenescript` 三个集群与 `effect-chain` 的 9 个样本（2824109832、3233141951、3287715210、3470948192、3477054430、3554161528、3750813609、3754630802、3788897599）**在该归档快照中结构 PASS**；这不代表今日 P1 完成，新的首断点仍须回到现役台账核对。

### 0.1 当前续跑状态（2026-09-10）

当前仍在 P1 公共断点修复。最新结构增量：B3 的 `3448845950` 四处 attachment 清零，`3665307769` 从 NON-PASS 恢复 strict PASS；B5 已越过 varying 和 float→int 编译错误，首断点推进至 terminal data/color 合同；B9 只补齐骨骼身份/frame 合同，VM→mesh 未接。下面 09-09 的 12 样本 `5/12` 与 159 个视觉 verdict 都是原始快照，不用两次后继回放改写总数。详见 [B3 当前证据](semantics/runtime-evidence-current.md#e-2026-09-10-b3-property-vector-input)。

#### 2026-09-09 接手与 12 样本历史基线

这是接手时的可续跑状态，供下一次开发直接定位；它不替代下面各条的最终证据。接手时分支 `codex/scene-capability-baseline` 的 `HEAD=a99d96eab3cbf6687f1b75ad09d8c7d8dab2192e`，工作树有 **97 个 tracked 修改、18 个新文件、0 个 staged 路径**，尚未提交。改动按职责分成 B1（shader backend arithmetic）、B2（multi-provider dependency）、B4/B5（material envelope/owner）、B7（Puppet 与 surface teardown）四组；B3/B6 目前只完成 fail-closed 归类和诊断边界。接手后的代码与治理已按职责集群固化为 `fdf430b7`、`82ef0133`、`1626ce42`、`14fe586c`、`50d2a2be`；本次证据文档提交后，下一轮开发从这些提交和下方的 residual 条目续跑。

#### 验收台账基线（生成于 2026-09-08，未由本批重生成）

真实 numeric corpus 为 159 个样本：视觉裁决 `pass=0`、`fail=19`、`unreviewed=140`、`platform-unsupported=0`。旧隔离运行的首断点分布为 `effect-chain=25`、`particle-load=9`、`texture-load=3`、`scenescript=5`，另有 `visual-review=117`、`not-run=0`；因此按最终完成门仍有 **159/159** 个样本未完成视觉验收（19 个待修复/复裁，140 个未裁决）。这是生成页的时间快照，不是本日 exact corpus verdict；例如 B8 的后继运行已观察到 provider readiness 恢复，但旧生成页仍记为 `blocked/graph-execution-missing`，在生成器刷新前保留两者并明确时间差。

| 集群 | 当前阶段 | 已有门 / 当前首断点 | 下一步 |
| --- | --- | --- | --- |
| B1 | 代表与两例扩面均结构闭合，视觉待复核 | 当前 Developer ID 包的 `3749463715`、`3754639143`、`3782740481` 均严格 PASS；三例 active effect / graph layer 均有 GPU、compositor、next-frame 证据。当前批次总报告列为 5/12 PASS（report SHA `0104f3fec84c489bc8645e0163d1c9294d959cf8a89f3a62b61c3e2efa6109e6`） | B1 的结构首断点可关闭；转入三例视觉/参数复核，若发现新 exact failure 再开后继条目 |
| B2 | 代表依赖/publication 已闭合，扩展样本按原因拆分 | `2959875782` 当前运行中 aggregate admission、utility `[520]`、named publication `[19,134,138]` 与 visible publication `[130,1413]` 均保留；唯一 graph contract 缺口是 layer 813 的 SceneScript/Puppet visibility，归 B9。`3448845950` 的 dependency-stage passthrough 与 `3792249095` 的 layer 254 不再混写成代表 B2 失败 | B2 代表可关闭；继续核对 3448845950 的多 provider/未认领 effect 与 3792249095 的 sampler/owner，均以公共 owner 修复 |
| B3 | 三分量 user→script 切片已执行，event-only 分支开放 | 3448845950 四层八个 uniform 完成 VM/material/GPU/compositor/next-frame；3665307769 strict PASS | 扩面 3601964477，再补 2902406982 的 media-event/Timeline producer；不扩大 scalar/vec2 或不明 wrapper |
| B4/B5 | B4 结构闭合但 geodraw/视觉开放，B5 与后继 owner 开放 | 当前包 `3662790108` 严格结构 PASS（35/35 active effect、81/81 GraphExecutor），但 8 个 geodraw2_1 request 仍走 `generatedStraightAlpha/colorTransfer → boundedSwift`；`3792249095` 仍有 layer 254 `degraded-layer-source-passthrough`，09-10 `3448845950` 已推进到 terminal data/color 合同。09-09 包的 366 启动约 48.09s、7.49 FPS（总报告 SHA `0104f3…`） | 修 geodraw 通用 color-transfer，再独立处理 sampler-schema/owner-revoked；结构 PASS 不等于视觉闭合 |
| B6 | 开放（作者类型不匹配） | `3747492842` 的 string-as-Vec3 与 scalar `.add` 错误已由 payload 复核；QuickJS 保持 fail-closed | 补合法 Vec3/scalar 正例及可重复异常 payload；不做字符串强转或伪造 API |
| B9 | 开放（09-10 已补 bone identity/frame 合同，VM 事务待接） | `2959875782` layer 813 的 visibility 脚本同时依赖 `thisLayer` Puppet bone API、cursor callbacks 与 `Date`；当前没有相应投影 owner，作者 seed=false 保持休眠 | 在同一 SceneScript vector/cursor 事务 owner 内补 Puppet bone handle 与 visibility publication；先做 identity-free 正反门，再做跨时间窗口和交互实跑 |
| B7 | teardown/启动闭合，稳定帧 CPU 待降 | 当前包 `3665307769` exit 0、teardown `surfaces=0`，09-10 后继 B3 layer 412 已执行且样本 strict PASS；CPU p95 `35.667 ms`、GPU p95 `10.160 ms`、driver `26.57 FPS` | 对 Puppet source-update CPU 做 profile/通用降本，目标回到 16.67ms 帧预算；B3 独立处理 |
| B8 | 记录完成，严格观察门仍保留 FAIL | 当前包 `3775355045` / `3775373546` 均在首帧记录 `22:layer-source-not-ready`，随后 frame 10/12 起 Program、GPU、compositor、next-frame 成立；strict benchmark 仍 FAIL | 不改门禁；若改变等待策略另立产品/门禁条目，并把旧 ledger 行标为 snapshot conflict |

聚焦门当前已通过：B2 post-fix runtime/plan 26 项（此前 B2 集群 32 项也通过）、B4/B5 233 项（1 skip）、B7 61 项，以及 source-set/code-health/diff-check。统一 checkpoint 选择 122 个模块，**121 个并行通过**；唯一失败为 `test_scene_shader_compiler_harness` 在 8-way glslang 竞争下触发 2 秒 timeout，隔离 `-j1` **20/20 通过**。`run_checkpoint_build.sh` 的隔离 unsigned Debug build 为 **BUILD SUCCEEDED**。随后由当前工作树构建的 Developer ID Debug 包也通过 deep/strict codesign：CDHash `7ce6a2fff1b12f8771c4fc768f9a2f204107e1c1`，executable SHA-256 `6edd66b54bbf6486560efe92e270a8bba616faf0b5619c6b9c504bf01c3570e5`，Team `H9QWU9XN8R`。12 样本串行复跑的 matrix SHA-256 为 `fd5f7fd4b52729115cd6f5e6120e80fc3a5dc8992237804f08ec1ed311b7d745`，report SHA-256 为 `0104f3fec84c489bc8645e0163d1c9294d959cf8a89f3a62b61c3e2efa6109e6`，结果为 **5/12 strict PASS、7/12 NON-PASS**（2959875782、3448845950、3792249095、3665307769、2775915974、3775355045、3775373546）。这组结果只描述结构/执行门，不改变 ledger 的 0 visual pass；运行输出在 `/private/tmp/mwx-handoff-current-runtime-20260909-1945`，仅作 provenance。

### 0.2 队列条目与路线框架的映射

| 条目 | 路线 P1 子顺序类别 / 阶段 | 排序理由 |
| --- | --- | --- |
| B1 | `effect-chain` · `admitted-fallback` passthrough（library-compilation） | 共享度最高（3 样本同源），当前三例结构门已闭合，转视觉/参数复核 |
| B4/B5 | `effect-chain` · `admitted-fallback` passthrough（envelope / owner-revoked） | 同为 effect-local passthrough，B4 的 `3662790108` 用户可见影响最大 |
| B3 | `effect-chain` · `admitted-fallback` passthrough（dynamic-uniform） | 同上；依赖 V4 producer 能力，跨样本共因 |
| B2 | `effect-chain` · 依赖引用 binding（capability/dependency 边界） | 代表 aggregate/publication 已闭合；扩展样本需按 dependency、B3、B5 真实 owner 拆分 |
| B6 | `scenescript` | 集群已清空后仅存的 SceneScript 运行时异常 |
| B9 | `scenescript` / Puppet interaction | B2 实跑暴露的独立产品 owner 缺口；不应继续归因于已闭合的 dependency publication |
| B7 | P5（播放稳定性） | 进程被杀属硬失败，保留在队列内但可由维护者按路线延后 |
| B8 | 首帧瞬时观察门 | 需维护者裁决方向（产品等待策略 or 门禁合同），非首断点 |

---

## 修复队列

### B1 `mwx-metal` 产物 MSL 编译失败：`vec3/vec4 ± vec2` 混合尺寸算术未收窄

- **状态**：`结构集群已闭合，视觉待复核（2026-09-09）` —— 当前 Developer ID 包对 `3749463715`、`3754639143`、`3782740481` 三个命中样本均严格 PASS；各自的 active effect、accepted graph layer、GPU completion、唯一 compositor 与 next-frame 均齐全。12 样本同批报告为 `5/12 PASS`，这三例的 report 细节由总报告固定。该结论只关闭 B1 的结构首断点，不宣称视觉 parity；见 [E-P1-VECTOR2-INTERFACE-ARITHMETIC](semantics/scene-sample-debug-ledger.md#e-p1-vector2-interface-arithmetic)。
- **问题**：`backend=mwx-metal` 的 prepared artifact 在 `MTLLibrary` 构建时报
  `error: implicit conversions between vector types ('float3' and 'float2') are not permitted`，
  effect 走 `material-pass-preparation-library-compilation` 局部 passthrough。
- **已核实 owner**：
  - 产物构建失败点：`SceneResolvedMaterialPassEncoder.compileUncachedPipeline`（`RenderGraph/EffectExecution/SceneResolvedMaterialPassEncoder.swift:443-451`），`device.makeLibrary(source:)` → `PreparationFailure.libraryCompilationRejected`；日志 reason 映射在 `SceneResolvedMaterialPassEncoder+Failure.swift:24`。
  - passthrough 准入：`SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift:79`（`material-pass-preparation-library-compilation` 白名单）。
  - 触发源（authored）：`shaders/workshop/2138904733/effects/cutout_vignette.frag:106` — `abs(v_TexCoord - CAST2(u_offset))`，`v_TexCoord` 为 `varying vec3`。`CAST2` 宏定义在 `SceneGenericShaderSourceNormalizer.swift:324`（`#define CAST2(x) vec2(x)`）。
  - 现有收窄逻辑（已合入部分）：`SceneGenericShaderSourceNormalizer.swift:752`（generic normalizer 路径）与 `SceneAuthoredShaderBackendCanonicalizer.swift:101`（backend canonicalizer 路径）。
- **命中样本**：`3754639143`（L211e2，warmup ×10）、`3749463715`（L467e0，×8）、`3782740481`（L17e0，×9）。
- **离线复现（无需起 App）**：从隔离 HOME 的 `Library/Caches/MyWallpaperX/SceneShaderPreparation-v1/` 取 cacheKey `f4388d48…` 的 stage source，`SceneAuthoredShaderFrontend.compile(vertexSource:fragmentSource:)` → `device.makeLibrary(source:)`。已验证该路径能复现同一错误文本。
- **剩余额提示**：收窄只覆盖"声明过的 uniform/attribute/varying 向量 ± CAST2/vec2"这一形状；局部变量、函数调用结果、复合值的混合尺寸算术仍 fail-closed。修复合入后用三个样本重验，若仍有 library-compilation 再按剩余额开新条目。
- **完工动作**：结构门已满足三样本正例；把三例转入视觉/作者参数复核，若复核发现新的 exact failure，再按共享形状建立后继条目。生成验收台账时同步刷新当前首断点。

### B2 composelayer 多 provider 依赖引用无 binding 合同

- **状态**：`代表 dependency / publication 断点已闭合；其余三样本待扩面（2026-09-09）`
- **问题**：composelayer（utility composition consumer）的多个 effect 各自引用**不同**依赖层 `_rt_imageLayerComposite_<N>_a`，admission 整层 not-admitted，effect 走 `effect-local-passthrough-dependency-stage-reference-unsupported`。
- **已核实 owner**：
  - 单 provider 假设：`SceneDependencyRenderPlan.executableBinding`（`RenderGraph/LayerDependencies/SceneDependencyRenderPlan+BindingCompilation.swift`）——五种 binding 合同（solidLayer/imageLayerBlend/materialProgram/visibleImageGraphOutput/resolvedMaterial）全部只产出一个 `Binding`；`resolvedMaterialReference`（`RenderGraph/LayerDependencies/SceneDependencyRenderPlan+Aggregate.swift`）要求所有引用同 provider；`singleSlot3SolidLayerReference` 要求 `dependencyLayerIDs == [provider]`。
  - 消费侧同样单 binding：`SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift` `compile`（`:53`，要求所有 candidate `providerLayerID == binding.providerLayerID`）；runtime 每层仅一份 `SceneDependencyEffectInput`（`Rendering/SceneImageLayerDrawRequest.swift:188`；`SceneResolvedMaterialSubmissionCoordinator+Execution.swift:253` 的 `dependencyReservationMatches`）。
  - 遏制落点：同文件 `unsupportedReferenceEffectKeys`（`:239`）→ passthrough 白名单 `SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift`（`dependency-stage-reference-unsupported`）。
- **最小代表例**：`2959875782` layer 520（composelayer `ranger_wed`，`dependencies=[19,63,130,134,138]`）：effect 0 = blend（slot1 → 层 19 composite），effect 2/3/4 = xray（slot1 → 层 138/130/134 composite）。utility capture 已成功（日志 `phase=utility-capture … succeeded`），缺口只在 per-effect 引用绑定。
- **其他命中**：`3448845950`（×7）、`3792249095`（L254e2）、`2775915974`（L28e0，composelayer xray 引用隐藏层 24）。
- **表现**：aggregate 入口保留 layer 63/520 的 3/4 个 provider 引用；provider reservation 现按 target kind 归一化，visible main-loop 与 named prepass 由调用点显式选择 publication role。最终包复跑 `2959875782` 后 utility capture 成功 `[520]`，named graph publication 成功 `[19,134,138]`、visible graph publication 成功 `[130,1413]`，所有 publication/binding failure 集合为空，109/108/0 submitted/completed/failed。旧 `prepared-provider-output-install-rejected` / `final-composite-failed` 不再出现。
- **验收 parser 对齐**：`layer-graph-route-v1` 已把产品现有 `external-aggregate` 纳入同一 route parser；`none` 仍要求 `refs=0`，两类 external route 均要求正引用数，未知类别仍 malformed。benchmark 全模块 132 项通过。对保留日志重新解析后 malformed route 从 2 降为 0，layers 63/520/813 均保留 accepted；没有修改 expected set、样本矩阵、失败文案或 schema 版本。
- **当前剩余边界**：原始 report 仍是不可改写的 NON-PASS 证据，但 B2 的 aggregate admission、provider publication、binding、GPU completion 与 compositor 链已闭合。当前 Developer ID 复跑的 `2959875782` accepted graph layer 为 58 个，required exact backend 32 个中 31 个完成，utility `[520]`、named publication `[19,134,138]` 与 visible publication `[130,1413]` 均有记录；唯一缺口是 layer 813 的 dynamic visibility / Puppet owner。其脚本同时使用 `thisLayer.getBoneTransform/setBoneTransform/getBoneIndex`、cursor callbacks 与 `Date`，当前 `visibilityProjection` 没有对应 owner，且本次运行时间 09:23:48–09:24:01 位于作者 true 窗口 03–39 秒之外。该问题已拆为 B9，缺口不再是 dependency binding，不通过删 expected layer 或放宽门禁掩盖。post-fix report/app.log/runtime SHA 分别为 `6f2ee6c6ebbf2c6933465601136abfa486ba1a5a4ed495f390608d30185003d8` / `4a7f786d9a81a59bb967f363779844ee1c5f88b0809b779cd3bf8a5ec8ab49c4` / `315e8a92ab4760037bd146d50453a1796762f73326c00a6219e9cf7ab284fbee`；当前 12 样本总报告 SHA-256 为 `0104f3fec84c489bc8645e0163d1c9294d959cf8a89f3a62b61c3e2efa6109e6`。
- **定位提示**：能力台账把"multi-dependency/reference"明确登记为 primary named provider 的未闭合形状（coverage-ledger L790、render-graph L267 的 nested cascade 仅覆盖 single-dependency）。
- **完工动作**：代表依赖/publication 切片已满足；继续把 3448845950 的 dependency-stage effect 与 3792249095 的 layer 254 分别归入其真实 owner，不能用代表 PASS 覆盖扩展失败。生成验收台账时刷新四个样本的首断点。

### B3 SceneScript→material uniform 的 script attachment 无 typed producer

- **状态**：`user-color→SceneScript 切片 S3；其余 producer 仍 open（2026-09-10）`
- **修复前问题**：动态 uniform 的 `scriptAttachments == [.unproven]`（SceneScript 写入该 uniform，但无 typed 投影 owner 认领该 target），effect 拒绝并走局部 passthrough。前序核对的 payload 表明这是 attachment/owner 证据缺口，不是可直接放宽的通用 producer：`2902406982` layer 702/e0 `multiply` 是 `animation+script+value` 且脚本只有 `mediaThumbnailChanged`；`3601964477` layer 383/e0、`3665307769` layer 412/e0 以及 `3448845950` layers 57/227/627/1341 的 Color 均为 `script+scriptproperties+user+value`，外层 user 与脚本 producer 混合。
- **已核实 owner**：`SceneResolvedMaterialExecutionCapability.swift:763-765`（有 producer 但 attachment unproven → `material-dynamic-uniform-script-attachment-unproven`）；`:726-729`（无 contributor 且 attachment unproven 的同码分支）。target 执行侧：`SceneScriptScalarRuntime.swift:358`（`effectConstant` 分支）。passthrough 白名单见 B1 文件 `:79` 区域。
- **命中样本**：`2902406982`（`material-finalizer-dynamic-uniform-binding`，L702e0，finalizer 变体，producer `SceneResolvedMaterialGraphExecutor+Preparation.swift:267`）；`3601964477`（L383e0）；`3665307769`（L412e0）；`3448845950`（×4：L57e6/L227e7/L627e7/L1341e7）。
- **表现**：script 驱动的动态 uniform 不更新，相关视觉保持 authored fallback/previous-current。09-10 已补 named user 的 typed input identity，不再将 resolver 当前值与原始 fallback 误比较。3448845950 四层八个 uniform 与 3665307769 layer 412 均有实际 VM→uniform→GPU/compositor/next-frame；后者 strict PASS。详情见 [最新证据](semantics/runtime-evidence-current.md#e-2026-09-10-b3-property-vector-input)。
- **关联债**：能力台账 V4 shader-constant family（122 条 census）与 script instance properties（43 条）均已登记为 L1 未接线。
- **下一步**：先复跑 3601964477 的相同 typed color 合同；2902406982 的 event-only + Timeline 要在现有 media/vector transaction 内建立 producer 顺序，不能把只有事件回调的 wrapper 当作普通 update producer。标量/vec2、未知 wrapper、owner/key/type 错配保持拒绝。

### B4 material variant envelope 拒绝（frontend / color-contract / sampler-schema）

- **状态**：`3662790108 / 3768020435 的结构切片已闭合；geodraw、sampler-schema、owner-revoked 与视觉/性能开放（2026-09-09）`
- **问题**：launch envelope 在不同 stage 拒绝 variant，对应 effect 走 `material-variant-envelope-*` 局部 passthrough。**注意日志中该 reason 无 detail 字段，需先重建诊断 payload 才能逐样本归因**——这是本条的第一步。
- **已核实 owner**：
  - reason 构造：`SceneResolvedMaterialExecutionCapability+Stages.swift:522-531`（`envelopeRejection`，`"material-variant-envelope-\(failure.kind.rawValue)"`）；kind ← `Failure.code` 映射：`SceneResolvedMaterialExecutionCapabilityVariant+LaunchEnvelope.swift:162-189`（`.shaderFrontendFailed → frontend`、`.colorContractUnproven → color-contract`、`.authoredSamplerSchemaInvalid → sampler-schema`、`.uniformBindingInvalid → uniform-schema` 等）。
  - sampler-schema 另一来源：`SceneResolvedMaterialExecutionCapability+Stages.swift:513-517`（`ResourceDemandIssue.samplerSchemaUnavailable`）。
  - passthrough 准入：`SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift:380-400`（`visualFailureMayPassthrough` 白名单）。
- **命中样本**：frontend：`3472940912` L50e0、`3323988600` L65e0、`3395777145` L338e0+L392e0、`3782740481` ×3（L305/453/466）；color-contract：`3768020435` L382e0、`3662790108` ×8（L2901/2908/2914/3175）；sampler-schema：`3792249095` L254e3。
- **表现**：`3662790108` 的 8 次集中在轨道/球体着色器链（与其"球体缺失"用户可见问题直接相关）；其余样本单个 effect 缺失。
- **当前复跑**：Developer ID 包对 `3662790108` 与 `3768020435` 均为严格结构 PASS；`3662790108` 的 8 个 geodraw2_1 authored request 仍使用 `generatedStraightAlpha/colorTransfer → boundedSwift`，因此画面仍需人工核对。`3792249095` 的 layer 254 四个 effect 仍是 `unified-capability-unavailable`，并伴随 `degraded-layer-source-passthrough`；`3448845950` 的 `material-generic-owner-revoked` 位于 layer 1475。当前总报告 SHA-256 `0104f3fec84c489bc8645e0163d1c9294d959cf8a89f3a62b61c3e2efa6109e6`。
- **建议顺序**：先处理 `3662790108` 的通用 color-transfer 证明（8 次同因、用户可见影响最大）；再分别处理 `3792249095` sampler/owner-revoked 与 3448845950 的 admitted-fallback。frontend 类可复用 B1 的共享 frontend owner，但必须保留未见组合反例。
- **完工动作**：同 B2。

### B5 generic owner 撤权

- **状态**：`open（09-10：编译已恢复，1475 首断点为 terminal data/color 合同）`
- **问题**：generic route 内 `materialFailure.mapsToGenericOwnerRevokedVisualFailure` 成立时撤权到 previous-current。
- **已核实 owner**：产生点 `SceneResolvedMaterialExecutionCapability+Stages.swift:397-404`；消费/回滚语义 `SceneResolvedMaterialGraphComposition.swift:294/430/461`；白名单 `ProgramFirstStages.swift:388`。
- **命中样本**：`3792249095` L254e0（与 B2/B4 同层叠加，建议并入 B4 的 3792249095 归因批次）；`3448845950` L1475e0（solid 辅助层）。
- **表现**：单 effect previous-current；`3448845950` 该层是零面积 solid 层（E-V4-TEX-MEDIA-IDENTITY 曾修过其准备尺寸，此处是其后的又一拒绝）。
- **当前复跑**：`3792249095` 的 `degraded-layer-source-passthrough` 是唯一 route operation，六个其它 accepted layer 均有 GPU/compositor/next-frame；09-10 `3448845950` 的 layer 1475 已不再因 varying/float→int 编译撤权，现为 node 2 `material-variant-envelope-color-contract`。这两项应作为 owner-local 修复，不能并入 B2 代表结论。
- **进一步归因与已修部分**：`3448845950` 的 accumulation 是 material/copy/material 的 history seed/state 结构，已补精确 plan profile、copy content fact、反向 varying-prefix 和标量 rounding→int 编译；compiler artifact 为 generic-only accepted。合法 corpus 的 terminal combine 只传 packed RGBA，随后 layer 322 按 dependency texture 消费，因此真正剩余是 **typed data provider publication**，不是 generic-owner veto 应放宽。154 项 shader/frontend（1 skip）与 31 项 graph/source-set/environment 门、signed build/fresh 回放见 [B5 最新证据](semantics/runtime-evidence-current.md#e-2026-09-10-b5-feedback-frontend)。3792249095 的 self-composite/sampler 继续归 B2/B4。
- **下一组 owned paths / 合同**：`SceneResolvedMaterialExecutionCapability+Stages.attachment(.effectOutput)`、`SceneResolvedMaterialProgram+ColorDerivation`、`SceneResolvedMaterialGraphExecutor.PairAtom` 与 `+Preparation/+Validation`、`SceneGraphRenderTargetLease+Publication.fullFrameResource`、submission ticket、`SceneDependencyFrameRuntime`/registry publication 及下游 texture purpose。按同一 content atom 传 `.data`，保持 generation/epoch/completion；compositor 不接受数据。不得在 passthrough 中伪造 premultiplied 输出，也不得为该 sample/layer 加分支。
- **完工动作**：补齐 owner-revoked 的公共正例、局部失败反例和恢复帧，再做两样本复跑。

### B6 SceneScript 运行时异常：Vec3 回调返回值与 effectConstant 输出类型不匹配

- **状态**：`open`
- **问题**：`3747492842` 四个 layer（796/152/265/186）的 `angles` Vec3 回调返回值无法被宿主解析（`badReturn`）；原始 `scene.pkg` 显示这些脚本先执行 `value = scriptProperties.myText`（`"LEON"`），最后 `return value`，因此返回 string 而非 Vec3。layer 173 effect 1 pass 0 的 `speed` authored value 为标量 `0`，脚本维护 Vec3 `currentOffset` 并执行 `return value.add(currentOffset)`，故抛 `value.add is not a function`；这不是宿主缺少 Vec3 API。
- **已核实 owner**：
  - Vec3 校验：`Runtime/SceneScript/SceneQuickJS.c:1010-1021`——回调返回后 `read_vec3()` 不通过即 `write_diagnostic("callback returned invalid Vec3 value")` + `MWX_SCENE_QUICKJS_BAD_RETURN`。宿主入参用 `JS_CallConstructor(vec3_constructor,…)`（`:960`），返回值必须同样是可被 `read_vec3` 读取的形状（宿主 Vec3 实例或可解析结构）；作者返回普通对象/数组/含非数值字段时被拒。Swift 侧 result 映射 `SceneScriptQuickJSDomain+FrameTransaction.swift:32`。
  - effectConstant 执行：`SceneScriptScalarRuntime.swift:358`、`SceneScriptScalarProgram+Projection.swift:174`；当前 scalar runtime 会把 authored numeric input 传给脚本，QuickJS 原生异常透传。宿主 Vec3 的 `add/subtract/multiply` 已在 `SceneQuickJSValueHost.c` 实现；focused harness 也要求 string/array/non-finite Vec3 返回维持 `MWX_SCENE_QUICKJS_BAD_RETURN`。
- **表现**：四层物体角度不动；该样本还有 layer 186 `layer-source-not-ready` 瞬时（并入 B8 类观察，不单列）。
- **定位提示**：保持现有 typed output 合同与 fail-closed；不要把字符串强转 Vec3，也不要把 scalar input 包装成 Vec3。若要继续推进，只需补充不同 output-shape 的可重复 QuickJS payload/诊断与官方或固定黑盒语义证据。
- **完工动作**：将该样本记为作者脚本 output-shape/type mismatch；只有独立正例证明同一 target 的合法 Vec3/scalar producer 与 frame consumption 后，才考虑 generic contract 变更。

### B7 运行稳定性：极慢启动 + 停止时 surface 未释放

- **状态**：`teardown 与极慢启动已闭合；稳定帧 CPU 仍 open（2026-09-09）`
- **09-10 后继**：playback 已复用 local/skin matrix scratch，26 项通过 / 1 real-fixture skip；尚无新增性能消融，不关闭 CPU 预算，见 [证据](semantics/runtime-evidence-current.md#e-2026-09-10-puppet-bone-frame)。
- **问题**：`3665307769` 启动 `startupElapsedMS=56245`（56 秒，其余样本约 8–17 秒），播放与截图正常，但 benchmark 停止窗口内 surface 未归零，进程被 SIGKILL（`process exit -15`）。
- **已核实 owner**：
  - 判定来源：benchmark `script/scene_wallpaper_benchmark.py:6921-6924`——app 日志 `phase=surface-teardown` 的 `surfaces=` 值必须为 0，否则 "Scene surfaces not released"。
  - 产品侧 teardown 链：`phase=surface-teardown` 日志的发出点（surface teardown owner，`MyWallpaperX/Core/SteamWorkshopScene/Runtime/` 内 surfaceStop 路径）；该样本播放期 audit `claimed=9 encoded=9 failures=0`，无渲染失败，怀疑点在 teardown 等待/挂起而非 encode。
- **当前真实结果**：最终统一签名包（CDHash `7019384b…`）隔离复跑 exit 0，ready `17722.143 ms`；启动前清场与停止后 teardown 均记录 `surfaces=0`，无 timeout/SIGKILL。两层 Puppet 共 34,936 vertices / 66,049 triangles，193/192/0 submitted/completed/failed，driver `27.237 FPS`；CPU p95 `34.540 ms`、main-frame p95 `34.832 ms`，pre-encode p95 `0.095 ms`、GPU p95 `10.476 ms`。report/app.log/runtime SHA 分别为 `8acf2feaa37d08215dcdf778715a1dab114f5f08e00f040ce1029a1dbea51ba3` / `a7f31187212c06d665ec00f8eec29b4681e814a59e8d6cfcabf88c7b62adf4cf` / `5611196f477bd54ae7278a1b7d03077b13242a1f2c07b7a50eb91cc41a402a2d`。严格报告仍因 B3 layer 412 的 `material-dynamic-uniform-script-attachment-unproven` 非 B7 原因而 NON-PASS。
- **定位提示**：Puppet 的 load-time coverage 批处理、prepared vertex/animation、重复帧 signature 与 caller-owned scratch 已把旧 56 秒启动和约 3.69 FPS 大幅收敛。当前剩余集中在 source-update 的 CPU main-frame，而非 drawable/pre-encode/GPU/teardown；下一步应先对两层 skinning/vertex upload 分段 profile，再决定 CPU 并行、GPU skinning 或更小的通用数据布局修正。
- **完工动作**：同 B2；此条属于 P5 范畴时按路线降级处理，但进程被杀属于硬失败，建议保持队列内。

### B8 首帧视频源瞬时 fallback 触发观察门

- **状态**：`已重分类为记录完成（2026-09-09；见 [E-V4-TEX-MEDIA-IDENTITY](semantics/scene-sample-debug-ledger.md#e-v4-tex-media-identity图片身份与首帧资源准入2026-09-08)）`
- **问题**：`3775355045`、`3775373546` frame 0 出现 `diagnostic=layer-local-fallback entries=22:layer-source-not-ready`（视频层首帧源未就绪），当前包分别在 frame 12 / frame 10 起 Program 恢复，GPU/compositor/next-frame 全部成立。benchmark 因此仍记 "resolved material graph observation diagnostic reported" FAIL。
- **已核实 owner**：benchmark 解析 `layer-local-fallback`（`scene_wallpaper_benchmark.py:625、:2875`）并把观察诊断计为失败（`:3506` 在 allowlist token 集合中，但该 token 属于"记录"而非豁免，最终仍计入 failures）。
- **表现**：两样本的首帧结构观察仍会记录 FAIL，但播放已恢复；现有 E-V4-TEX-MEDIA-IDENTITY 已证明第 10 帧恢复 Program、第 11 帧继续，publication、GPU completion、compositor 与下一帧成立。当前代码的等待/重试和 layer-local fallback 已有定向覆盖，且没有伪造 source 或扩大失败豁免。
- **裁决**：这是可观察的 provider readiness 瞬态，不是当前公共执行首断点。产品等待策略与 benchmark 观察合同仍是独立后续决策；本条不改 benchmark 门禁，也不把该瞬态改写为 PASS。
- **完工动作**：保留现有证据与严格 FAIL 事实；若未来要改变首帧等待或观察合同，另立有明确产品/门禁授权的条目。当前版本的两例运行详情已纳入 2026-09-09 总报告，不把它们计为现役 P1 清零。

### B9 Puppet visibility 脚本缺少 `thisLayer` bone/cursor 事务 owner

- **状态**：`open（2026-09-10：骨骼身份与 typed frame 已补；QuickJS→mesh 事务仍待接线）`
- **问题**：`2959875782` layer 813（Puppet layer `S2rboob`）的 `visible` authored wrapper seed 为 `false`，脚本的 `update(value)`、`cursorDown`、`cursorUp` 与 `init` 共同使用 `input.cursorWorldPosition`、`thisLayer.getBoneIndex/getBoneTransform/setBoneTransform` 和 `Date.getSeconds()`。当前 binding 没有投影为 `.layer(813, .visibility)`，因此没有 VM、dynamic visibility 或 graph execution 记录，预览日志为 `disposition=previous-current reason=awaiting-scenescript-publication`。
- **已核实 owner**：`SceneScriptVectorCandidateCatalog.visibilityProjection` 的 independent boolean route 明确排除 `thisLayer`，stateful route 要求 `shared` 或 `thisScene`；standalone cursor route 又把含 `update(value)` 的 image binding留给 vector owner。现有 QuickJS 已有 `thisLayer` identity/effect/部分 transform bridge 与 cursor transaction 基础，但没有 Puppet bone handle 的 typed mutation/publication 合同。
- **进一步归因**：当前 `SceneQuickJSLayerHost/HandleHost` 没有 `getBoneIndex/getBoneTransform/setBoneTransform`，`MWXSceneQuickJSLayerMutation` journal 也没有 bone mutation；MDLS reader 已补 name 保留，catalog 与带 layer-to-world 的原子 frame helper 已通过正反门；见 [B7/B9 最新证据](semantics/runtime-evidence-current.md#e-2026-09-10-puppet-bone-frame)。QuickJS 与 mesh 尚未消费该 helper，因此这不是单个 visibility flag 的漏接，而是约 26 个 census 对象共用的 bone handle/typed Mat4 owner 缺口。实现应保留 name→index identity、有限 Mat4/translation 读写和原子 rollback，仍复用现有 vector/cursor transaction owner。
- **表现**：作者 seed=false 时该 Puppet layer 保持休眠；当前运行窗口 09:23:48–09:24:01 也在脚本 true 窗口 03–39 秒之外，所以不能仅凭该次无执行判为 graph failure。缺失的是同一 owner 对 visibility、cursor capture 与 bone transform mutation 的有序提交。
- **边界**：不得为 layer 813、名字、时间窗口或样本 ID 加特例；不得在 Puppet evaluator 外再建骨骼状态。失败时只丢弃该 owner 当帧 mutation，保留 previous-current visibility/mesh 与唯一 compositor。
- **完工动作**：先用 identity-free fixture 锁定 bone name/index lookup、transform read/write、cursor down/up、update 顺序、generation rollback 与非法/stale handle 反例；再用隔离真实样本跨 hidden/visible 秒窗和一次 cursor drag，证明 typed mutation → Puppet evaluator → graph execution → GPU/publication/compositor/next-frame。

---

## 附录 A：未核实线索索引（文档登记债，未逐条对照代码，仅供队列清空后深挖）

> 以下内容摘自语义文档，**未逐一用代码核实**，可能过期。使用前必须先按条目在当前代码中确认 owner 与现状再立项：
>
> - Effect family 余量：coverage-ledger.md §1 各 family 段落（Blur/X-Ray/Pulse/Water 族/Depth Parallax/Bloom/Iris/Film Grain/Shine/God Rays/Local Contrast/Precise/Bokeh/Color Grading/Blend associated-over/Tone Mapping/Lens Distortion/audio shader 通用准入）。
> - Shader frontend 合同：render-graph-shader-coverage.md §4–§5（预处理器、跨语言头文件、sampler annotation、uniform producer、render state、built-in uniforms、varying/fragment output）。
> - Graph/provider/资源：coverage-ledger §1 与 render-graph §5（secondary `_b`、nested cascade、FBO command、history RT、preserved-channel、extent/clear/UV、copy/swap/compose、PKG/TEX/BC/LUT/animated atlas）。
> - 输入/属性：runtime-input-property-coverage.md（Texture Variants 全 L0、usershortcut L0、camera binding family L1、shader constant family L1、script instance L1、particle override L1、Timeline Animation Events L0、pointer multi-surface）。
> - SceneScript API：scenescript-api-coverage.md（Vec4/Mat 全 L0、`IAnimation`/`ICamera`/`IMaterial`/`IParticleSystem` 等 handle L0、`resizeScreen`/`animationEvent` L0、localStorage/timer 语义）。
> - 媒体/音频：status event L0、live platform media producer L0、embedded video seek/parity、audio 数值官方合同未证。
> - 粒子：particle-component-coverage.md（L0×11 / L1×18 / L2×17，重点 Collision response、Layer Image 继承/位图更新、Cutout/Lighting 材质、跨空间转换、pause 状态机；性能首断点为逐帧 advance + preflight，重样本 7–8 FPS）。
> - Puppet/3D/光照/HDR：advanced-object-coverage.md（Puppet 整页 L0 子项、3D node/multi-mesh、2D lighting 与 Scene Bloom runtime L0、target FPS driver L0、RGB 与离线烘焙全 L0）。

## 附录 B：09-09 全量探测明细

> 本表是 09-09 pre-fix census 的不可改写历史快照；当前以后续 §0.1、B 条目和 2026-09-09 Developer ID 复跑为准。生成验收台账前，不把本表的 `PASS*` 或 `FAIL` 直接当作今日 exact 状态。

| 样本 | 结构结果 | 断点（对应队列条目） |
| --- | --- | --- |
| 1315486372 | PASS | -（视觉待复裁） |
| 2775915974 | PASS* | pre-fix B2[L28e0]；当前 identity-only 复跑未取得 required graph execution，顶部灰边仍为用户可见问题 |
| 2824109832 | PASS | - |
| 2902406982 | PASS* | B3-finalizer[L702e0] |
| 2959875782 | FAIL | pre-fix B2[L520e0/e2/e3/e4]；post-fix aggregate/publication 已闭合，剩余 layer 813 转 B9 |
| 2974757317 / 2986218263 / 3396722575 | PASS | - |
| 3233141951 / 3287715210 | PASS | -（视觉待复裁） |
| 3238423642 / 3264246690 / 3437487219 | PASS | -（视觉待复裁） |
| 3323988600 | PASS* | B4-frontend[L65e0] |
| 3395777145 | PASS* | B4-frontend[L338e0,L392e0] |
| 3448845950 | FAIL | pre-fix B2×7 + B3×4 + B5[L1475e0]；当前复跑仍有 dependency-stage / B3 / owner-revoked，需按 owner 拆分 |
| 3470948192 / 3477054430 / 3509243656 | PASS | -（视觉待复裁） |
| 3472940912 | FAIL | B4-frontend[L50e0] |
| 3601964477 | FAIL | B3[L383e0] |
| 3610154602 / 3612199597 / 3612795410 / 3629927359 | PASS | - |
| 3662790108 | FAIL | pre-fix B4-color-contract×8[L2901/2908/2914/3175]；post-fix B4 结构 PASS，geodraw/视觉/性能仍开放 |
| 3665307769 | FAIL | pre-fix B7（56s 启动 + surfaces not released）+ B3[L412e0]；post-fix teardown/启动闭合，B3 与 CPU 预算仍开放 |
| 3690859128 / 3712499998 / 3779904456 / 3788467391 | PASS | -（部分视觉待复裁） |
| 3747492842 | FAIL | B6（Vec3 badReturn×4 + effectConstant TypeError）+ layer186 source-not-ready |
| 3749463715 | FAIL | pre-fix B1[L467e0]；post-fix 当前 identity 严格 PASS |
| 3750813609 / 3754630802 | PASS | -（视觉待复裁） |
| 3754639143 | FAIL | pre-fix B1[L211e2]；post-fix 当前 identity 严格 PASS |
| 3765760121 / 3766387484 | PASS | -（视觉待复裁） |
| 3768020435 | FAIL | B4-color-contract[L382e0] |
| 3775355045 / 3775373546 | FAIL | B8（首帧瞬时，已恢复；仅作观察记录，不再作为公共首断点） |
| 3780119725 / 3788734811 / 3554161528 / 3788897599 | PASS | -（视觉待复裁） |
| 3782740481 | FAIL | pre-fix B1[L17e0] + B4-frontend×3[L305/453/466]；post-fix 当前 identity 严格 PASS |
| 3784012236 | PASS | - |
| 3792249095 | FAIL | B5[L254e0] + B2[L254e2] + B4-sampler-schema[L254e3]；当前复跑仍有 layer 254 degraded source passthrough |

带 `*`：来自被中断的首轮 census（无 report.json），判定依据为 app.log 的 audit `failures=0` + reason 存在性，未过完整 benchmark 门。

## 附录 C：结构 PASS 但人工裁决仍 fail 的样本（验收覆盖层 2026-09-08，未复裁）

1315486372（水波位置/光线生硬）、3238423642（约 18.7 FPS 未验收）、3264246690（左肘缺块）、3287715210（真实系统音频未验收）、3437487219（cursor owner collision）、3470948192（NaN/文字碎片/异常背景，待复裁）、3477054430（月亮/球体/文字布局、远景过亮）、3509243656（待复裁）、3662790108（球体/曲率/点击交互、约 8.8 FPS）、3712499998（WEVector unsupported、重复文字）、3750813609（时钟灰黑渐变、雨丝偏淡）、3765760121（待全面验收）、3766387484（其余 effect 未验收）、3780119725（脸部黑线/缺块、动画层 unsupported）、3788734811（待复裁）、2775915974（顶部灰边）。

另有两项**显式登记、暂停修复**的开放视觉债（coverage-ledger.md L129）：`3787382101`（Water Waves 未限制在作者 mask 内）、`3264246690`（Puppet 左肘缺三角）。
