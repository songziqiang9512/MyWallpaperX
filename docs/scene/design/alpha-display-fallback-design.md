# inline alpha 脚本显示权保守修复设计（d1-1，fmod-alpha）

状态：approved（2026-10-01，同批实施）。本文件是 `script/design_gated_areas.json` 条目 `scene-alpha-display-fallback` 的 tracked 设计文档；原始裁决写于本机证据缓存 `docs/scene/evidence/20261001-capability-audit/fmod-alpha-design.md`（git-ignored），内容以该裁决为准，本副本为其实施态镜像。对应缺口：`gaps.json` d1-1「inline 脚本 alpha owner 无 committed publication 整层抑制」，21 样本 / 16 真实，sev=high，status=confirmed。

## 0. 判定程序回答（design-gate 五问）

① 横切多个 owner/主链节点：是——launch 构建链（SceneRuntimeModel.swift:103-155）、显示权 owner（SceneScriptScalarDisplayProjection）、可见性 guard（SceneLayerVisibility）三个节点。
② 触碰唯一权威合同：是——display-authority 的 alpha 释放语义（displayScriptOwnership.alpha 是唯一产品权威，SceneScriptBindingDefinition.swift 标记、SceneRuntimeModel 链释放、SceneLayerVisibility 消费）。
③ 用户可见难回退：层整层消失 vs 整层出现，均用户可见；但本设计无持久化格式/缓存 schema 变化，回滚单点（见 §6）。
④ 机器基线冻结家族：不新增分析器家族（无 JS 文本分析，见 §3），不改 scene_source_layout/defense_baseline。
⑤ 外部取证：官方语义只有间接锚点（绑定位置即 target、writeback、非法返回不覆盖旧值；无 alpha 显示权直接记载）——本设计不宣称官方 parity。

五问命中①②③⑤，属设计前置能力。

## 1. 结论：三桶一览

判定主轴不是表达式分类本身，而是**一个可证明命题**：该 alpha 绑定在当前运行时里是否存在任何可达的 publication 路径。

- 存在（被 14 条准入条件接纳，或被 shared-alpha incumbent 认领）→ **admit**：脚本进 QuickJS scalar owner 每帧执行；本设计对准入规则零放宽。
- 不存在，且该命题可由已解析结构证明（无需读脚本文本）→ **downgrade**：launch 期把 `displayScriptOwnership.alpha` 释放为 false，保留 authored alpha，层可见、无脚本动画。
- 无 alpha 压制面可处置（形态本身不经 alpha 显示权链），或依赖当前运行时未闭合的供应门 → **suppress**：维持现状，台账登记，本修复不触碰。

依据：`.layer(id,.alpha)` 的 publication 路径在当前运行时只有三条——scalar owner（SceneRuntimeModel.swift:136-140 准入 + :141-144 释放）、shared-alpha producer（:103-110 编译、:120-123 释放）、Timeline（:111-114 编译 alpha target）。一个绑定若被 14 条准入条件（SceneScriptScalarProgram+Projection.swift:70-166 + projectedDefinitions :16-44）拒绝，则 scalar owner 不会为它构造；shared 与 Timeline 各有独立严格语法门。因此「未被任何一方认领」⇔「本运行时内永久无 publication」⇔「压制剂永不解除」——此时维持压制不产生任何显示权收益，只产生 d1-1 的整层消失。

## 2. 决策不对称性（宁保守勿错放的具体化）

- 错 downgrade（本应动画的形态被静态化）：层以 authored alpha 可见、无动画。这正是官方合同「非法返回/无返回不得覆盖旧值」的既定退化形态（scenescript-runtime-implementation-contract.md:349，ask 材料），也是 Scene 硬边界「视觉失败默认局部 fail soft，保留 previous-current」的 sanctioned 形态。后果轻且自愈（未来供应卡落地、准入接纳后自动恢复动画）。
- 错 admit（不可重放形态被接入 owner）：owner 构造/每帧 callback 失败走既有 typed fail-soft（失败保留 current，runtime-input-property-coverage.md:424「失败保留current」），视觉后果同为静态；残余风险是半执行副作用（alpha 槽脚本写 `thisLayer.visible`、`getAnimation().play()`——形态清单实证存在 4 处 play 站点）与每帧异常预算消耗。因此本设计**不放宽任何准入条件**，admit 桶只钉死既有准入行为。
- 错 suppress（可处置形态维持压制）：即 d1-1 主症状，层消失，后果最重。故 suppress 桶必须收窄到有正面证据的形态（§3 F6/F7），不允许作为兜底默认。

## 3. 形态 → 桶映射（16 真实样本 + 119-corpus 口径）

形态编号对齐任务材料的形态清单（alpha-shapes.json：constant 200 / other 132 / time 108 / user-property 54，共 494 位点；119-corpus 全量口径见 coverage-ledger.md:596：114 条 alpha wrapper = 8 A 形 + 74 B 形 + 32 C 形，其中 66 条引用 shared）。

### admit（接入既有 scalar owner；准入规则零改动）

| 形态 | 内容 | 确定性重放论证 |
|---|---|---|
| F1 | A 形 `animation/script/value` 且 Timeline 编译出该 alpha target（3779026256 layers 140/240/322、3610154602 layer 419） | `isTimelineWrapper` 分支要求 `timelineTargets.contains(target)`（SceneScriptScalarProgram+Projection.swift:148-151），Timeline 值由 SceneTimelineTargetCompiler 从 authored animation 确定性编译（SceneRuntimeModel.swift:111-114）；scalar owner 读 Timeline current。准入路径既有且有 owner-executed 证据。 |
| F3 | B 形 `script/value`，表达式 ∈ {constant, time, user-property, `return value` 直通}（3509243656 步进/淡出族、2974757317、2938612768、2902406982 'touming' 族、3768020435、3610154602:435、3768724269:170） | 值函数只读 `value`/`scriptProperties`/`engine.frametime`/`engine.runtime`。供应源逐项在产品代码：帧输入 `SceneScriptFrameInput`（timeOfDay/frameTime/runtime，SceneScriptScalarRuntime.swift:180-205；QuickJS engine 挂载 SceneQuickJS.c:382-409）；scriptProperties/userProperties 经 typed JSON 注入（SceneScriptValueRuntime.swift:295-311）；当前值经 typed 输入。现役记录：真实 3509243656=60、2902406982=8 个 alpha completion（runtime-input-property-coverage.md:424）。 |
| F5 | C 形 `script/scriptproperties/value` 且 properties 可编码（3509243656 easing/slider 族、2974757317:842、2938612768:842） | 同 F3 供应面 + `SceneScriptPropertyInputCodec.inputs` 编码门（projectedDefinitions 条件④，SceneScriptScalarProgram+Projection.swift:24）。运行期 TypeError（3768724269:163 缺 getParent）按既有 fail-soft 落回 current，属「已准入的运行期失败」，不是压制，不在本修复范围。 |
| F8 | 结构上已准入、表达式受指针/音频影响但 alpha 值本身是常量/时间形（3779026256 obj26 音频可视化器：alpha 仅 init 复制 baseAlpha 常量，频谱驱动 scale；3768724269 obj6 光标距离控制流，右端为 frametime 斜坡） | 轮询式指针输入已供应（`SceneScriptSurfaceInput.cursorWorldPosition/...`，SceneScriptScalarRuntime.swift:207-233；QuickJS `cursorWorldPosition` 等 SceneQuickJS.c:121-147；台账「SceneScript polling pointer/canvas snapshot L3 bounded」）；音频经 `registerAudioBuffers` + `refreshAudio`（SceneScriptValueRuntime.swift:254-268）。scalar owner 的构造限制只针对 bool target（SceneScriptValueRuntime.swift:215-229 的 guard 限定 `valueType == .bool`），scalar 不受限。任务材料断言「scalar 运行时无音频/指针供应源」与代码事实不符，此处按实测代码修正：真正未闭合的是 **scalar cursor event callback 传递**与 **shared initializer/global authored order**（runtime-input-property-coverage.md:424 下一门原文）；凡 alpha 值本身可由已供应输入决定的形态不因此 suppress，未触发的 event 修饰退化为静态基值，属 fail-soft。 |

admit 桶的本设计工作量 = 零准入改动 + 红先行钉死（§5）。admitted 死绑定（脚本从不写 alpha 但结构获准，owner 每帧空转）**不**在本批摘除：摘除会连带停掉其可见副作用（`getAnimation().play()` 4 处），须待副作用证明卡，本文只登记。

### downgrade（launch 期降级为 authored alpha，层可见、无脚本动画）

| 形态 | 内容 | 可证明无 publication 的结构证据 |
|---|---|---|
| F2 | A 形 wrapper 但 Timeline 未编译出该 alpha target（含死绑定 3779026256 obj25/27/28、3610154602 obj14、3768724269 obj9——只写 visible/动画从不产出 alpha） | A 形 scalar 分支以 `timelineTargets.contains(target)` 为前置（+Projection.swift:148-151）；Timeline 拒绝（duplicateTarget 等）⇒ 该分支必拒 ⇒ 无 scalar owner；Timeline 自身也无 target ⇒ 无任何驱动。 |
| F4 | 任何 B/C 形被 14 条准入的结构条件拒绝：value:null（无有限种子，projectedDefinitions 条件⑤ +Projection.swift:25-26）、scriptproperties 不可编码（条件④）、同 target 重复绑定（条件⑥ :34-37）、object identity 失配（条件⑨ :78-82）、bit-exact 失配（条件⑬ :164-165）、wrapper 形态出白名单（条件⑫，objectScalar 合同 SceneScriptDynamicProviderHostContract.swift:33-46，objectScalar 不收外层 user :17-24） | 每一拒绝条件都是「owner 不会为它构造」的直接结构证明；IR 解析失败（外层 user 冲突、script 非 String、properties 解析失败，SceneScriptBindingDefinition.swift:400-413）则绑定根本不入 scriptBindings，同样无 owner 可构造。descriptor 上的 alpha 值由 SceneDocument.doubleValue 独立解出（ask 考古 :303-314/:224），降级后即为显示值。 |

降级值取 wrapper 的 authored `value` 字段（即 descriptor 现值），**不做表达式静态求值**：任何产品侧 JS 表达式分析都会构成新的 shape-analyzer 家族（scene_source_layout 冻结方向为收缩），且无必要——authored value 是作者声明的基态，descriptor 已在使用它。同族先例：`SceneIdentityDisplayScriptProjection`（Systems/Properties/SceneIdentityDisplayScriptProjection.swift:3-9）就是「静态可证 no-op ⇒ 释放 display 所有权」的既家族成员，本设计是该家族在 alpha 域的第二-tier 推广（家族内新增入口，不新增第二套权威）。

### suppress（维持现状 + 台账登记；本修复不触碰）

| 形态 | 内容 | 维持理由 |
|---|---|---|
| F6 | 无 alpha wrapper 的 visibility-only 样本（2241938645、3743305891、3749463715、3767460992、3768229922、3768903841 等 8 样本） | 其 corpus 旗标来自 text/visible/color 槽脚本；现行 reportLines 已走 previous-current/awaiting-scenescript-publication（SceneLayerVisibility.swift:80-82），**不存在 alpha 压制面**。visible 权语义按任务边界不动。台账行记「不适用」。 |
| F7 | visible 槽脚本经 `thisScene.getLayer(...).alpha = 常量` 跨层写 alpha（3122339805、3211615441） | 目标层无 alpha wrapper ⇒ 无 alpha 压制；写入路径是动态层 mutation journal（SceneScriptDynamicLayerRuntime.swift:209-217），其「跨属性 mutation」门现役未闭合（runtime-input-property-coverage.md:424 下一门原文）。接入=扩权，剔除=触碰 visible 槽脚本语义，均越界。台账登记为跨属性 mutation 能力卡的输入。 |

F6/F7 之外**不设表达式级 suppress 默认**：任务材料设想的「音频/指针依赖且无供应源」形态在 16 真实样本的表达式层面为零（形态清单：random/音频频谱/指针三类右端为零；指针经事件写常量、音频驱动 scale 不驱动 alpha），且轮询指针/音频供应在产品代码中实测存在（F8 论证）。若未来语料出现 alpha 值 genuinely 依赖无供应源的形态，走新能力卡定供应源，不在本设计内预置分析器。

## 4. 修复机制与 owned paths

机制：launch 一次性、纯 derived、无 schema 变化。在 builder 计算「已认领集合」claimed = sharedAlphaTargets ∪ projectedScalarTargets ∪ timelineTargets，对每个 `displayScriptOwnership.alpha == true` 且 `.layer(id,.alpha) ∉ claimed` 的层把 ownership 释放为 `alpha:false`（visible 位不动）。所有下游消费者（每帧可见集 SceneMetalRenderer.swift:152-154、launch 准入 SceneMetalRenderer+Initialization.swift:41、source passthrough、SceneUtilityLayerSourceRoute.swift:146-149、deferred base-image 排除 SceneDesktopWallpaperHost+DeferredBaseImages.swift:24、reportLines）读的都是同一 `renderDescriptor`（SceneRuntimeModel.swift:13/:218-219 存 runtime descriptor），降级自动贯通，无需逐点修改。

owned paths（精确到文件）：

1. `MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptScalarDisplayProjection.swift`：第二入口 `applyUnclaimedFallback(claimedTargets:to:)`（同文件同 owner，不改既有 `apply(admittedTargets:to:)` 语义），文件头 doc comment 分第一-tier/第二-tier 两段。
2. `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRuntimeModel.swift`：scalar display projection 与 particle projection 之间接线 `alphaClaimedTargets = sharedAlphaTargets ∪ projectedScalarTargets ∪ timelineTargets`，`particleProjectedDescriptor`/`runtimeDescriptor` 改消费 `fallbackProjectedDescriptor`。timelineTargets 入 claimed 的理由：Timeline 驱动的 alpha 层是活驱动，集合是超集不影响正确性（仅用于成员判定）。
3. `MyWallpaperX/Core/SteamWorkshopScene/Format/SceneScriptBindingDefinition.swift`：仅 doc comment 补记 d1-1 裁决——provenance 标记语义不变；「malformed 也保持 owned」的显式推翻面收敛到第二-tier fallback，回滚即恢复原文案语义。解析代码零改动。
4. `script/design_gated_areas.json`：登记 `scene-alpha-display-fallback`，status=approved，designDoc 指向本文件（evidence 原件在 git-ignored 目录，不能作 designDoc），matchPatterns 含 `applyUnclaimedFallback`。
5. 红先行测试：`script/tests/test_scene_script_scalar_display_projection.py`（downgrade 红先行 + admit 守护）、`script/tests/test_scene_script_binding_parser.py`（suppress 守护原文保留 + value:null 红例）、`script/tests/test_scene_property_vector_script.py`（admit 桶时钟重发布断言）。
6. `docs/scene/semantics/coverage-ledger.md`：suppress 桶台账行（F6「不适用」、F7 跨属性 mutation 卡输入）+ 降级批次的 non-parity 声明行。

明确不改：`SceneLayerVisibility.swift`（guard 与 reportLines 原样；suppressed 分支保留为回滚面与未来 suppress 形态的表达出口）、`SceneScriptScalarProgram+Projection.swift`、`SceneScriptDynamicProviderHostContract.swift`、`SceneSharedLayerAlpha*`、visible 权全部语义。

## 5. 红先行（模块名 + 断言文本）

### 5.1 admit 桶（既有断言即守护，先确认绿）

- `script/tests/test_scene_property_vector_script.py`：既有 timeline 形 `animatedAlpha`、时间形 `genericAlpha`（`value + engine.frametime`）、属性形 `genericPropertyAlpha`（`value + scriptProperties.step`）的 compile+evaluate 断言保持通过；新增 `test_layer_alpha_time_owner_republishes_each_frame_from_supplied_clocks`——断言文本：「alpha owner 以 engine.frametime 步进的 update 每帧产出严格递增 scalar，且第二轮 evaluate 不复用首轮返回值（无 publication 缓存）」。
- `script/tests/test_scene_script_scalar_display_projection.py` `test_only_admitted_alpha_releases_alpha_suppression`：既有文本作为「只有 admitted target 释放」的 admit 守护。

### 5.2 downgrade 桶（红：新入口不存在 ⇒ 编译失败即红）

`script/tests/test_scene_script_scalar_display_projection.py` 扩展 harness（沿用现 stub 风格），新增 `test_unclaimed_alpha_ownership_falls_back_to_authored_display`：

```python
self.assertEqual(fallback_payload[0], {"id": 10, "visible": True, "alpha": False})   # unclaimed 释放
self.assertEqual(fallback_payload[1], {"id": 20, "visible": True, "alpha": True})    # claimed 不动，admit 优先无双 owner
self.assertEqual(fallback_payload[2], {"id": 30, "visible": False, "alpha": False})  # alpha 释放但 visible 所有权保留
self.assertEqual(fallback_payload[3], {"id": 40, "visible": None, "alpha": None})    # 无 alpha 所有权零触碰反例
self.assertEqual(fallback_payload[4], {"id": 50, "visible": False, "alpha": False})  # visible-owned 零触碰反例
```

### 5.3 suppress 桶 + 既有压制行为守护（必须保持绿）

- `script/tests/test_scene_script_binding_parser.py` `test_visible_scripts_keep_previous_current_while_alpha_stays_suppressed`：原文原样，禁止迁移——layer 4 `{visible:false, alpha:true}` 在 guard 层仍返回 false、reportLines 仍输出 `disposition=suppressed reason=unproven-inline-scenescript-alpha`，钉死「SceneLayerVisibility 压制分支不变」。
- 同模块新增 `test_null_valued_alpha_wrapper_stays_unprojected_and_yields_to_fallback`：value:null 的 alpha wrapper（SCENE_FIXTURE objects[0].alpha）不产出 `.layer(10,.alpha)` 绑定目标（assertNotIn）——压制解除由 fallback 认领集合的补集负责，而不是由准入放宽负责。

builder 接线（SceneRuntimeModel.swift）的行为断言不进 python 门（现无 in-process builder 行测，源码文本断言违反「断言行为不断言形状」），归 checkpoint：Swift harness 以最小 fixture scene 跑 `SceneRuntimeModelBuilder.build`，断言 `model.renderDescriptor` 中 value:null alpha 层 `displayScriptOwnership.alpha == false` 且 claimed 层保持 true；随后按验证梯度做隔离代表样本 Debug build 的可见性证据。

## 6. 风险

**错放后果矩阵**
- downgrade 误纳（本应动画→静态可见）：官方合同的既定退化形态，轻；自愈路径存在（未来准入接纳即恢复动画）。最坏子例：作者 value=高alpha 而脚本意在事件前隐藏→层提前亮出。语料核查：16 样本 value 均为基态（1.0/0.5/0.0/属性滑条默认），无「占位亮值+隐藏意图」实例；缓解=首批只对 16 真实样本做隔离样本可见性核对后再全量。
- admit 误纳：本设计零准入改动，不产生新误纳面。既有 admitted 死绑定的空转 owner 与半执行副作用为现状，不在本批扩大。
- suppress 误留：即 d1-1 症状残留；F1-F5 规则已覆盖全部结构拒绝原因（拒绝条件与 F4 一一对应），无表达式级残留。
- 交互风险（named）：① 跨层 alpha mutation（F7 路径，SceneScriptDynamicLayerRuntime.swift:209-217）与降级层重叠时，降级会让外来 mutation 生效——16 样本中两集合零交集（形态清单：F7 样本均无 alpha wrapper）；实现后以 corpus 断言防回归。② Launch.swift:383-395 第二次 projectedTargets 及 bounded 冲突检查不受影响（fallback 不产出 target）；bounded producer 认领的 alpha target 落在 scalar 集合外但被 bounded 驱动，释放仍正确。

**官方语义偏差面**
- 降级=「无 publication ⇒ current（authored）持续」与官方 writeback/非法返回不覆盖合同同向（scenescript-runtime-implementation-contract.md:349），但「加载期显示权」官方无取证（PROPERTY-002 明确 alpha 页不定义、默认工程 13 处内联零 alpha 绑定）——本设计是自有保守策略的**收敛**（fail-closed→fail-soft），台账必须写「无官方 parity」，不得宣称对齐官方行为。
- shared 引用形态（119-corpus 66/114）：admitted 的照旧运行（shared ordering 保真度是既有未闭合门，非本批引入）；bounced 的降级为静态，比半保真仿真更确定。

**回滚**
- 单点：删除 SceneRuntimeModel.swift 的 `applyUnclaimedFallback` 调用（唯一 call site）即完整恢复现行 fail-closed 行为；reportLines suppressed 分支未删，诊断语义即时复原。无 descriptor/缓存/持久化 schema 变化，无迁移；测试回退同批 revert。design-gate 条目随设计被否决时改回 blocked-pending-design 并留否决记录。

## 7. 验证梯度

inner：§5 三个模块（swiftc harness，非 App 构建）——实施批已运行（见台账行）；checkpoint：builder fixture harness + Debug build；integration：16 真实样本隔离副本的可见性/截图证据（每样本记 layer 数、suppressed 行清零、无新黑屏）；milestone：corpus 重扫 `unproven-inline-scenescript-alpha` 行数对照（基线：corpus.json byReason 792 行/21 样本/143 文件，历史旧键口径）。checkpoint 及以上梯度不在 inner 实施批内，按所属卡推进。
