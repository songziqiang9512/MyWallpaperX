# Scene 现存断点修复队列（2026-09-09，代码已核实）

> **历史证据 — 非现役入口**

> 本文是给修复实施者的**可执行队列**。每一条都在当前代码中核实过 owner 位置（文件 + 行号 + 符号），不是从旧文档转述。样本 ID 只用于复现证据，不得进入产品代码。
>
> **与执行路线的关系**：[执行路线](../../scene/scene-compatibility-roadmap.md)拥有阶段顺序和完成门；本文是 2026-09-09 当时事实下 P1（公共首断点清零）的**派生批次队列**，不拥有当前顺序权威。路线的 P1 子顺序（`unified-capability-unavailable` → `admitted-fallback` passthrough → `graph-execution-missing`）中，前两类经近期批次后已基本清空（见 §0），本文的 B1→B8 是把当时剩余断点映射回该框架后的建议执行序（映射见 §0.1）；当前状态以现役路线、台账和运行证据为准。
>
> **队列规则**：按顺序一次修一条（B1 → B2 → …）。动手前先核对"状态"列与当前代码是否仍然一致（并行会话可能已合入修复）。每修完一条：
> 1. 在本文档把该条状态改为 `已修复（<日期>，<commit/证据链接>）`，或整条删除；
> 2. 按工作流更新权威文档（能力台账 / 专项表 / 样本调试台账），本文不替代它们；
> 3. 按路线 §4 记录完成状态（`slice-visible` / `owner-migration`），样本可见结果变化写入样本调试台账、人工裁决变化写入验收覆盖层；路线正文只在阶段状态或完成门改变时更新；
> 4. 若修复过程中发现新的共享断点，按同一条目格式追加到队列尾部。
>
> 本文与权威文档冲突时以权威文档和当前代码为准。

## 0. 证据基础

- 复现环境：隔离样本副本 + 隔离 HOME，`script/scene_wallpaper_benchmark.py`，真实 `requestLaunch` 异步入口，12 秒 / after 9 秒，`--audio-spectrum-silence-fixture`，identity-only 矩阵。48 个样本（09-07 归档中全部非 `visual-review` 样本 ∪ fail 裁决样本）已于 2026-09-09 重探（每批 4 个并行）。
- 被测 App：CDHash `0764dc19bb535571c621f0bbfc0322a4d77db924`（2.0.9 (277)，构建于 09-08 23:29）。这是 2026-09-09 全量探测快照；各条目的当前状态以现役运行证据和对应批次报告为准。
- 口径：队列中的"复现"指结构门 FAIL 或日志中出现对应 passthrough/reason，**不等于视觉验收**。结构 PASS 但人工裁决 fail 的样本清单见附录 C。
- 09-07 归档中 `texture-load`、`particle-load`、`scenescript` 三个集群与 `effect-chain` 的 9 个样本（2824109832、3233141951、3287715210、3470948192、3477054430、3554161528、3750813609、3754630802、3788897599）**结构已全部 PASS**，不再列队。

### 0.1 队列条目与路线框架的映射

| 条目 | 路线 P1 子顺序类别 / 阶段 | 排序理由 |
| --- | --- | --- |
| B1 | `effect-chain` · `admitted-fallback` passthrough（library-compilation） | 共享度最高（3 样本同源），且已有修复在途 |
| B4/B5 | `effect-chain` · `admitted-fallback` passthrough（envelope / owner-revoked） | 同为 effect-local passthrough，B4 的 `3662790108` 用户可见影响最大 |
| B3 | `effect-chain` · `admitted-fallback` passthrough（dynamic-uniform） | 同上；依赖 V4 producer 能力，跨样本共因 |
| B2 | `effect-chain` · 依赖引用 binding（capability/dependency 边界） | 4 样本共享；改动半径最大，放在 passthrough 类之后 |
| B6 | `scenescript` | 集群已清空后仅存的 SceneScript 运行时异常 |
| B7 | P5（播放稳定性） | 进程被杀属硬失败，保留在队列内但可由维护者按路线延后 |
| B8 | 首帧瞬时观察门 | 需维护者裁决方向（产品等待策略 or 门禁合同），非首断点 |

---

## 修复队列

### B1 `mwx-metal` 产物 MSL 编译失败：`vec3/vec4 ± vec2` 混合尺寸算术未收窄

- **状态**：`部分修复（2026-09-09）` —— `SceneAuthoredShaderBackendCanonicalizer.swift` 已新增 `rewriteVector2ArithmeticOperands`，把声明的 vec3/vec4 接口变量 `± CAST2(...)/vec2(...)` 收窄为 `.xy ± ...`；隔离样本 `3749463715` 的 `467#effect#480` 已跨过该 library compilation。三样本重验和 effect 1 颜色合同仍未闭合，当前边界与证据见 [E-P1-VECTOR2-INTERFACE-ARITHMETIC](../../scene/semantics/scene-sample-debug-ledger.md#e-p1-vector2-interface-arithmetic)。
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
- **完工动作**：三样本 benchmark 结构 PASS + 队列状态更新 + 台账登记。

### B2 composelayer 多 provider 依赖引用无 binding 合同

- **状态**：`open`
- **问题**：composelayer（utility composition consumer）的多个 effect 各自引用**不同**依赖层 `_rt_imageLayerComposite_<N>_a`，admission 整层 not-admitted，effect 走 `effect-local-passthrough-dependency-stage-reference-unsupported`。
- **已核实 owner**：
  - 单 provider 假设：`SceneDependencyRenderPlan.executableBinding`（`RenderGraph/LayerDependencies/SceneDependencyRenderPlan.swift:387`）——五种 binding 合同（solidLayer/imageLayerBlend/materialProgram/visibleImageGraphOutput/resolvedMaterial）全部只产出一个 `Binding`；`resolvedMaterialReference`（同文件 `:721`）要求所有引用同 provider；`singleSlot3SolidLayerReference` 要求 `dependencyLayerIDs == [provider]`。
  - 消费侧同样单 binding：`SceneResolvedMaterialExecutionCapability+DependencyOwnership.swift` `compile`（`:53`，要求所有 candidate `providerLayerID == binding.providerLayerID`）；runtime 每层仅一份 `SceneDependencyEffectInput`（`Rendering/SceneImageLayerDrawRequest.swift:188`；`SceneResolvedMaterialSubmissionCoordinator+Execution.swift:253` 的 `dependencyReservationMatches`）。
  - 遏制落点：同文件 `unsupportedReferenceEffectKeys`（`:239`）→ passthrough 白名单 `SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift`（`dependency-stage-reference-unsupported`）。
- **最小代表例**：`2959875782` layer 520（composelayer `ranger_wed`，`dependencies=[19,63,130,134,138]`）：effect 0 = blend（slot1 → 层 19 composite），effect 2/3/4 = xray（slot1 → 层 138/130/134 composite）。utility capture 已成功（日志 `phase=utility-capture … succeeded`），缺口只在 per-effect 引用绑定。
- **其他命中**：`3448845950`（×7）、`3792249095`（L254e2）、`2775915974`（L28e0，composelayer xray 引用隐藏层 24）。
- **表现**：对应 blend/xray 效果整段缺失（previous-current），层内其余 effect 正常。
- **定位提示**：能力台账把"multi-dependency/reference"明确登记为 primary named provider 的未闭合形状（coverage-ledger L790、render-graph L267 的 nested cascade 仅覆盖 single-dependency）。
- **完工动作**：按工作流补正反 fixture + 未见组合验证；按路线 §4 记录 `slice-visible` / `owner-migration`（含回滚演练）；更新 runtime-input-property-coverage / render-graph-shader-coverage 对应"multi-dependency 仍缺"句与样本调试台账；队列状态更新。

### B3 SceneScript→material uniform 的 script attachment 无 typed producer

- **状态**：`open`
- **问题**：动态 uniform 的 `scriptAttachments == [.unproven]`（SceneScript 写入该 uniform，但无 typed 投影 owner 认领该 target），effect 拒绝并走局部 passthrough。
- **已核实 owner**：`SceneResolvedMaterialExecutionCapability.swift:763-765`（有 producer 但 attachment unproven → `material-dynamic-uniform-script-attachment-unproven`）；`:726-729`（无 contributor 且 attachment unproven 的同码分支）。target 执行侧：`SceneScriptScalarRuntime.swift:358`（`effectConstant` 分支）。passthrough 白名单见 B1 文件 `:79` 区域。
- **命中样本**：`2902406982`（`material-finalizer-dynamic-uniform-binding`，L702e0，finalizer 变体，producer `SceneResolvedMaterialGraphExecutor+Preparation.swift:267`）；`3601964477`（L383e0）；`3665307769`（L412e0）；`3448845950`（×4：L57e6/L227e7/L627e7/L1341e7）。
- **表现**：script 驱动的动态 uniform 不更新，相关视觉保持 authored fallback/previous-current。
- **关联债**：能力台账 V4 shader-constant family（122 条 census）与 script instance properties（43 条）均已登记为 L1 未接线。
- **完工动作**：同 B2。

### B4 material variant envelope 拒绝（frontend / color-contract / sampler-schema）

- **状态**：`open`
- **问题**：launch envelope 在不同 stage 拒绝 variant，对应 effect 走 `material-variant-envelope-*` 局部 passthrough。**注意日志中该 reason 无 detail 字段，需先重建诊断 payload 才能逐样本归因**——这是本条的第一步。
- **已核实 owner**：
  - reason 构造：`SceneResolvedMaterialExecutionCapability+Stages.swift:522-531`（`envelopeRejection`，`"material-variant-envelope-\(failure.kind.rawValue)"`）；kind ← `Failure.code` 映射：`SceneResolvedMaterialExecutionCapabilityVariant+LaunchEnvelope.swift:162-189`（`.shaderFrontendFailed → frontend`、`.colorContractUnproven → color-contract`、`.authoredSamplerSchemaInvalid → sampler-schema`、`.uniformBindingInvalid → uniform-schema` 等）。
  - sampler-schema 另一来源：`SceneResolvedMaterialExecutionCapability+Stages.swift:513-517`（`ResourceDemandIssue.samplerSchemaUnavailable`）。
  - passthrough 准入：`SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift:380-400`（`visualFailureMayPassthrough` 白名单）。
- **命中样本**：frontend：`3472940912` L50e0、`3323988600` L65e0、`3395777145` L338e0+L392e0、`3782740481` ×3（L305/453/466）；color-contract：`3768020435` L382e0、`3662790108` ×8（L2901/2908/2914/3175）；sampler-schema：`3792249095` L254e3。
- **表现**：`3662790108` 的 8 次集中在轨道/球体着色器链（与其"球体缺失"用户可见问题直接相关）；其余样本单个 effect 缺失。
- **建议顺序**：先做 `3662790108`（8 次同因、用户可见影响最大）；frontend 类可能是 B1 同族 frontend 拒绝的另一形态（`shaderFrontendFailed`），修 B1 时顺带核对其余 frontend 命中样本。
- **完工动作**：同 B2。

### B5 generic owner 撤权

- **状态**：`open`
- **问题**：generic route 内 `materialFailure.mapsToGenericOwnerRevokedVisualFailure` 成立时撤权到 previous-current。
- **已核实 owner**：产生点 `SceneResolvedMaterialExecutionCapability+Stages.swift:397-404`；消费/回滚语义 `SceneResolvedMaterialGraphComposition.swift:294/430/461`；白名单 `ProgramFirstStages.swift:388`。
- **命中样本**：`3792249095` L254e0（与 B2/B4 同层叠加，建议并入 B4 的 3792249095 归因批次）；`3448845950` L1475e0（solid 辅助层）。
- **表现**：单 effect previous-current；`3448845950` 该层是零面积 solid 层（E-V4-TEX-MEDIA-IDENTITY 曾修过其准备尺寸，此处是其后的又一拒绝）。
- **完工动作**：同 B2。

### B6 SceneScript 运行时异常：Vec3 回调返回值校验失败 + effectConstant API 缺失

- **状态**：`open`
- **问题**：`3747492842` 四个 layer（796/152/265/186）的 `angles` Vec3 回调返回值无法被宿主解析（`badReturn`），以及 layer 173 effect 1 pass 0 的 `speed` effectConstant 回调抛 `TypeError: not a function`（脚本调用了未实现的 API/对象方法）。
- **已核实 owner**：
  - Vec3 校验：`Runtime/SceneScript/SceneQuickJS.c:1010-1021`——回调返回后 `read_vec3()` 不通过即 `write_diagnostic("callback returned invalid Vec3 value")` + `MWX_SCENE_QUICKJS_BAD_RETURN`。宿主入参用 `JS_CallConstructor(vec3_constructor,…)`（`:960`），返回值必须同样是可被 `read_vec3` 读取的形状（宿主 Vec3 实例或可解析结构）；作者返回普通对象/数组/含非数值字段时被拒。Swift 侧 result 映射 `SceneScriptQuickJSDomain+FrameTransaction.swift:32`。
  - effectConstant 执行：`SceneScriptScalarRuntime.swift:358`、`SceneScriptScalarProgram+Projection.swift:174`；`TypeError` 是 QuickJS 原生异常透传，**具体缺哪个 API 需要捕获脚本异常 payload**（当前诊断只有消息文本）。
- **表现**：四层物体角度不动；该样本还有 layer 186 `layer-source-not-ready` 瞬时（并入 B8 类观察，不单列）。
- **定位提示**：Vec3 一侧先核对 `read_vec3`（`SceneQuickJS.c`）接受哪些 JS 形状，再对照作者脚本实际返回的形状决定放宽还是补构造桥；不猜测官方语义，必要时走官方行为研究工作流。
- **完工动作**：同 B2。

### B7 运行稳定性：极慢启动 + 停止时 surface 未释放

- **状态**：`open`
- **问题**：`3665307769` 启动 `startupElapsedMS=56245`（56 秒，其余样本约 8–17 秒），播放与截图正常，但 benchmark 停止窗口内 surface 未归零，进程被 SIGKILL（`process exit -15`）。
- **已核实 owner**：
  - 判定来源：benchmark `script/scene_wallpaper_benchmark.py:6921-6924`——app 日志 `phase=surface-teardown` 的 `surfaces=` 值必须为 0，否则 "Scene surfaces not released"。
  - 产品侧 teardown 链：`phase=surface-teardown` 日志的发出点（surface teardown owner，`MyWallpaperX/Core/SteamWorkshopScene/Runtime/` 内 surfaceStop 路径）；该样本播放期 audit `claimed=9 encoded=9 failures=0`，无渲染失败，怀疑点在 teardown 等待/挂起而非 encode。
- **表现**：结构 FAIL（timeout + surfaces not released）；用户侧表现为停止/切换壁纸时进程卡死被杀。
- **定位提示**：单样本复现（12 秒 + stop）抓 teardown 线程栈；区分"启动准备过重（56s）"与"teardown 等待句柄"两个独立疑点，不要合并修复。
- **完工动作**：同 B2；此条属于 P5 范畴时按路线降级处理，但进程被杀属于硬失败，建议保持队列内。

### B8 首帧视频源瞬时 fallback 触发观察门

- **状态**：`open`（判定为"记录行为"，是否修门禁由维护者决定，未授权不要放宽 benchmark）
- **问题**：`3775355045`、`3775373546` frame 0 出现 `diagnostic=layer-local-fallback entries=22:layer-source-not-ready`（视频层首帧源未就绪），约 frame 30 起 Program 恢复、GPU/compositor/next-frame 全部成立。benchmark 因此记 "resolved material graph observation diagnostic reported" FAIL。
- **已核实 owner**：benchmark 解析 `layer-local-fallback`（`scene_wallpaper_benchmark.py:625、:2875`）并把观察诊断计为失败（`:3506` 在 allowlist token 集合中，但该 token 属于"记录"而非豁免，最终仍计入 failures）。
- **表现**：两样本结构 FAIL 但播放已恢复；E-V4-TEX-MEDIA-IDENTITY 明确"不修改门禁掩盖该事实"。
- **可选方向**（二选一，需维护者裁决）：a) 首帧视频源就绪前的等待策略（产品）；b) 观察门对"已恢复的启动瞬时"的显式合同（门禁）。两者都不是放宽 reason 白名单。
- **完工动作**：同 B2。

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

| 样本 | 结构结果 | 断点（对应队列条目） |
| --- | --- | --- |
| 1315486372 | PASS | -（视觉待复裁） |
| 2775915974 | PASS* | B2[L28e0]；顶部灰边为用户可见问题 |
| 2824109832 | PASS | - |
| 2902406982 | PASS* | B3-finalizer[L702e0] |
| 2959875782 | FAIL | B2[L520e0/e2/e3/e4] |
| 2974757317 / 2986218263 / 3396722575 | PASS | - |
| 3233141951 / 3287715210 | PASS | -（视觉待复裁） |
| 3238423642 / 3264246690 / 3437487219 | PASS | -（视觉待复裁） |
| 3323988600 | PASS* | B4-frontend[L65e0] |
| 3395777145 | PASS* | B4-frontend[L338e0,L392e0] |
| 3448845950 | FAIL | B2×7 + B3×4 + B5[L1475e0] |
| 3470948192 / 3477054430 / 3509243656 | PASS | -（视觉待复裁） |
| 3472940912 | FAIL | B4-frontend[L50e0] |
| 3601964477 | FAIL | B3[L383e0] |
| 3610154602 / 3612199597 / 3612795410 / 3629927359 | PASS | - |
| 3662790108 | FAIL | B4-color-contract×8[L2901/2908/2914/3175] |
| 3665307769 | FAIL | B7（56s 启动 + surfaces not released）+ B3[L412e0] |
| 3690859128 / 3712499998 / 3779904456 / 3788467391 | PASS | -（部分视觉待复裁） |
| 3747492842 | FAIL | B6（Vec3 badReturn×4 + effectConstant TypeError）+ layer186 source-not-ready |
| 3749463715 | FAIL | B1[L467e0] |
| 3750813609 / 3754630802 | PASS | -（视觉待复裁） |
| 3754639143 | FAIL | B1[L211e2] |
| 3765760121 / 3766387484 | PASS | -（视觉待复裁） |
| 3768020435 | FAIL | B4-color-contract[L382e0] |
| 3775355045 / 3775373546 | FAIL | B8（首帧瞬时，已恢复） |
| 3780119725 / 3788734811 / 3554161528 / 3788897599 | PASS | -（视觉待复裁） |
| 3782740481 | FAIL | B1[L17e0] + B4-frontend×3[L305/453/466] |
| 3784012236 | PASS | - |
| 3792249095 | FAIL | B5[L254e0] + B2[L254e2] + B4-sampler-schema[L254e3] |

带 `*`：来自被中断的首轮 census（无 report.json），判定依据为 app.log 的 audit `failures=0` + reason 存在性，未过完整 benchmark 门。

## 附录 C：结构 PASS 但人工裁决仍 fail 的样本（验收覆盖层 2026-09-08，未复裁）

1315486372（水波位置/光线生硬）、3238423642（约 18.7 FPS 未验收）、3264246690（左肘缺块）、3287715210（真实系统音频未验收）、3437487219（cursor owner collision）、3470948192（NaN/文字碎片/异常背景，待复裁）、3477054430（月亮/球体/文字布局、远景过亮）、3509243656（待复裁）、3662790108（球体/曲率/点击交互、约 8.8 FPS）、3712499998（WEVector unsupported、重复文字）、3750813609（时钟灰黑渐变、雨丝偏淡）、3765760121（待全面验收）、3766387484（其余 effect 未验收）、3780119725（脸部黑线/缺块、动画层 unsupported）、3788734811（待复裁）、2775915974（顶部灰边）。

另有两项**显式登记、暂停修复**的开放视觉债（coverage-ledger.md L129）：`3787382101`（Water Waves 未限制在作者 mask 内）、`3264246690`（Puppet 左肘缺三角）。
