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

## 0.3 现役待办（2026-09-10）

### 2026-09-11 回归断点修复（visibility owner / compiler contract / passthrough fixture）

当前工作树全量回归曾暴露三个可复现断点，已按公共 owner 修复并完成专项回归：SceneScript visibility owner 排除直接 `thisLayer.visible` 写入、effectful owner 保留视频句柄；generic straight-alpha default boundary 将 authored `directOutputFact` 纳入 strict compiler owner，避免额外 output component write 或 compiler sample 漂移被 fallback 掩盖；external primary passthrough harness 补齐当前 `FrameInputs.DependencyEffect.texture` 合同。专项三模块 `ALL OK`，checkpoint Debug build `BUILD SUCCEEDED`。全量回归尚未重新收尾，B7/B8/全样本视觉仍开放。

2026-09-11 B7 代码切片：`ScenePuppetPlaybackState` 复用 launch-stable 的 frame sample/signature scratch，避免每次 source-update 在 signature guard 前创建两个数组；动态 visibility、scene time、timeInvariant 和 bone revision 仍实时写入。Puppet animation/playback/rig 三模块回归通过，checkpoint Debug build 成功。当前签名 Debug app 对隔离只读样本 `3665307769` 的 fresh 25 秒回放严格 PASS（loaded=1.0、failures=[]、GPU/compositor/next-frame 成立），但 `cpu_frame_p95=34.815 ms`、`main_frame_p95=35.08 ms`、driver `26.425 FPS`，GPU p95 `10.608 ms`；scratch 改动保持可见正确性，16.67ms CPU 预算仍开放。

以下条目是本次交接时的实际修复队列，按共享 owner 依赖排序；每项完成后必须补充运行证据并提交一个完整职责批次：

1. **B2 扩展 / `3448845950` dependency-stage**（2026-09-11 全链闭合 ✅）：三处 binding 合同 + vec3 `a_TexCoord` + variant key 漂移 + sceneBackground 合同 + **207 隐藏 text provider 链**全部修复。最终回放 `claimed=13 encoded=13 failures=0`：13 个 accepted 层全部 GPU 完成（180/e10、691、247/524/416、**207**——binding/capture/utility 全 succeeded）。207 修复链：composition 消费者合同、隐藏 effects 的 text provider 放宽、utility 的 imageLayerBlend 路由、`SceneTextTextureLoader` 与 `SceneDynamicTextTextureStore` 两处 visible 过滤并入 authored 依赖源（隐藏 text 层作为 composite 源仍栅格+发布 layerSource publication）。剩余已登记：① ~~207/e0 circular_text `.vert`~~ **已闭合（2026-09-11）**——尾部悬挂单个 `#endif` 有界恢复（至多一个；候选后遇 `#endif/#else/#elif` 或"代码分隔+后续条件块"仍硬拒；新增 preprocessor 正例 `trailing_redundant_endif`，`207/e0` 已 encoded-output）；② ~~1475 gate 合同~~ **已闭合（2026-09-11）**——`SceneGraphExecutionObservation` 新增 `dependencyProviders` 字段（ledger 的 dependency 输入 provider，logFields 输出），benchmark 解析 `dependency_consumed_provider_layer_ids` 后仅对"存在下游依赖消费证据"的发布者豁免 compositor 消费要求；gate 合同测试扩展正反两例（下游消费→豁免、无任何消费→仍 missing）。344 复放 missing 清零（dependency_consumed=[102,474,495,571,660,1475]）；③ 偶发 `frame-target-plan-allocation-failed` reset 瞬态（B8 类观察，自愈）。
2. **B4/B5 剩余 owner**（2026-09-11 二次收敛）：**`3792249095` 严格 PASS 闭合**（failures=[]，audit `claimed=7 encoded=7 failures=0`，全程 outcome=failed 为 0；非黑 + 运动 mean_delta=0.061 证据齐；report SHA-256 `18ddbf63737fe4b9707ca28be0cb4515881fd230997c1963a7194e9b23c64ba2`，app.log SHA-256 `048f9f17b701a2b9ffc9a181566838228c9be7cf22027e6a68758706dc51f50e`，现场 `/private/tmp/mwx-b45-replay`）。闭合的第五个公共合同：**scene-background × graphInternal × compose 形状优先级**——target identity 合同（named namespace 不与 scene background alias）证明自引用与背景正交后，`dependencyIsCompatible` 接受 `.graphInternal`（aggregate 仍拒）；背景 slot 跟随 authored sampler（移除 Water Waves 时代的 `slot == 1` 残留，E-V4 Shine 任意 slot 前例）；compose 优先于 typed single-pass 分支（两者可同时满足）；多 effect generic-only 链走 per-effect 单写 ordered 路径。加上此前同批的 label 通道/passthrough 自引用颜色/source-carried 辅助数据槽/format 注解 purpose，379 全部 effect 执行。同批 **geodraw `3662790108` 严格 PASS**（详见 runtime evidence）。`same_slot::wrongCompilerSlotRejected` **已闭合（2026-09-11）**：探针证明该形状 authored 分类 unresolved 且全部 strict fact 未命中，产品默认边界回退吞掉编译器漂移拒绝——`hasStrictCompilerOwner` 补入 `SceneAuthoredShaderSameSlotColorBlendAlphaUnionAnalyzer` 后恢复拒绝（same_slot 3/3）。连带修复 `independent_signal_producer_lowering` HEAD 既有断裂（harness 补 `premultipliedColorInputSlots` 参数；route 断言同步产品 authority——ordinaryShader→generic-only 在 68dee38b 即如此，prefer-generic 为出生即错的过期期望）。
3. **B6 / 类型语义**（2026-09-11 闭环 ✅）：用含 B2 全链修复的当前签名包真实回放 `3747492842`——四个 angle target（796/152/265/186）全部 `callback=completed`（typed Vec3 输出）、`badReturn` 全程 0、effectConstant 无 `TypeError`；audit `claimed=7 encoded=7 failures=0`、missing/unexpected 全空。strict 报告仅剩的 2 项失败全部来自 1 次 `186:layer-source-not-ready` 首帧瞬态（B8 类观察，本条目原登记"不单列"）。quickjs 候选（authored_layer_mutation_count 收紧、同值 setter journal、string 返回诊断、launch property overlap）就此定案，错误类型保持 fail-closed。
4. **B7 / 稳定帧 CPU**：对 Puppet source-update 做 profile，按共享 owner 降低稳定帧 CPU；不以旧 FPS 快照代替新基线。
5. **B8 / readiness 观察合同**（2026-09-12 闭环 ✅）：官方证据三角（公开文档无 readiness API、静态取证内部 frame-ready 状态、二进制无首帧门字符串）定案为**异步就绪、无阻塞等待**；产品现行 layer-local fallback + 自然恢复与官方一致，不改等待策略、不放宽门禁，观察 FAIL 继续如实记录瞬态。
6. **全样本视觉收口**：重新生成验收台账，逐项裁决 `19 fail / 140 unreviewed`；任何新首断点回到 P1/P2。

B9（目标样本 Puppet 交互）已由 `36d8da06` 闭环，不再列入待办；旋转/重力/IK、多屏、parallax 和官方 parity 是 Puppet 的后续能力边界，不冒充 B9 未完成。

## 0. 证据基础

- 复现环境：隔离样本副本 + 隔离 HOME，`script/scene_wallpaper_benchmark.py`，真实 `requestLaunch` 异步入口，12 秒 / after 9 秒，`--audio-spectrum-silence-fixture`，identity-only 矩阵。09-09 的 48 样本探测是全量历史快照；当前可复核的后继结果是同一工作树签名包的 12 样本串行复跑（每个样本独立 runtime root）。
- 被测 App：48 样本历史快照使用 CDHash `0764dc19bb535571c621f0bbfc0322a4d77db924`（2.0.9 (277)，构建于 09-08 23:29）；当前 12 样本复跑使用 CDHash `7ce6a2fff1b12f8771c4fc768f9a2f204107e1c1`、executable SHA-256 `6edd66b54bbf6486560efe92e270a8bba616faf0b5619c6b9c504bf01c3570e5`。两者均只作对应快照的 provenance，当前状态以 12 样本报告和现役台账为准。
- 口径：队列中的"复现"指结构门 FAIL 或日志中出现对应 passthrough/reason，**不等于视觉验收**。结构 PASS 但人工裁决 fail 的样本清单见附录 C。
- 09-07 归档中 `texture-load`、`particle-load`、`scenescript` 三个集群与 `effect-chain` 的 9 个样本（2824109832、3233141951、3287715210、3470948192、3477054430、3554161528、3750813609、3754630802、3788897599）**在该归档快照中结构 PASS**；这不代表今日 P1 完成，新的首断点仍须回到现役台账核对。

### 0.1 当前续跑状态（2026-09-10）

当前仍在 P1 公共断点修复。B3 event-only 与 property→SceneScript→material 子切片均已闭合；B9 已完成同一 VM/cursor→bone journal→Puppet playback 的拖动、限幅、回弹及区域外不捕获闭环。B5 的 `3448845950` packed RGBA accumulation → typed named publication → layer 322 color consumer 已在最新签名回放中执行，原 terminal data/color 拒绝清零；该样本现在只剩 `180/e10`、`247/e0`、`691/e1` 三处 `dependency-stage-reference-unsupported`。B6 有未提交实现候选和 focused 38 项正反门，但尚未真实复跑 `3747492842`。详见 [B5 当前证据](semantics/runtime-evidence-current.md#e-2026-09-10-b5-feedback-frontend)、[B3 当前证据](semantics/runtime-evidence-current.md#e-2026-09-10-b3-property-vector-input)与[B9 当前证据](semantics/runtime-evidence-current.md#e-2026-09-10-b9-spring-closure)。下面 09-09 的 12 样本 `5/12` 与 159 个视觉 verdict 仍是原始快照，不用后继单样本回放改写总数。

#### 2026-09-10 交接现场

当前 `HEAD=0784085aa2a1864e2015102d3b7b2d17fa56727f`，分支 `codex/scene-capability-baseline` 相对远端 ahead 248。文档同步前工作树有 **42 个 tracked 修改、0 个 staged 路径**，主要是 B5 typed data 链、source-carried auxiliary data proof 与 B6 QuickJS 候选；这些修改尚未作为一个已完成职责批次提交。最新 build 为 `/private/tmp/mwx-b5-current-build/Build/Products/Debug/MyWallpaperX.app`，最新 B5 回放为 `/private/tmp/mwx-b5-provider-data-run`。此前 70 个精确开发缓存路径已移入废纸篓，未清空；根卷当前约有 137 GiB 可用。保留上述 build/run 是为了交接复核，完成后可按精确路径移入废纸篓。

#### 2026-09-09 接手与 12 样本历史基线

这是接手时的可续跑状态，供下一次开发直接定位；它不替代下面各条的最终证据。接手时分支 `codex/scene-capability-baseline` 的 `HEAD=a99d96eab3cbf6687f1b75ad09d8c7d8dab2192e`，工作树有 **97 个 tracked 修改、18 个新文件、0 个 staged 路径**，尚未提交。改动按职责分成 B1（shader backend arithmetic）、B2（multi-provider dependency）、B4/B5（material envelope/owner）、B7（Puppet 与 surface teardown）四组；B3/B6 目前只完成 fail-closed 归类和诊断边界。接手后的代码与治理已按职责集群固化为 `fdf430b7`、`82ef0133`、`1626ce42`、`14fe586c`、`50d2a2be`；本次证据文档提交后，下一轮开发从这些提交和下方的 residual 条目续跑。

- **2026-09-12 激活休眠观察合同修复（benchmark 侧）+ corpus 复验**：17 个真实 NON-PASS 中的两种同根形状——shape-1 整链激活休眠（3238423642 L299、3396722575 L120、3788897599 L17：typed user-property 激活全帧 `decision=inactive`，graph 按 authored 语义走 activation passthrough）与 shape-2 程序链止于休眠终态 effect（2134765860 L526/674、3788897599 L283：程序 effect 正常 encode，compositor 消费记录在休眠终态的 passthrough observation 上）——根因是 benchmark 观察合同未建模 authored-deactivated activation。修复：`scene_wallpaper_benchmark.py` 新增 `authored_deactivated_activation_identities`（解析产品每帧 `consumer=effect-activation ... decision=` 行，全帧 inactive 的 (layer, effect, descriptor) 不再作为 program demand/成功计入 exact backend）；`scene_wallpaper_graph_output_metrics.py` 把 activation-passthrough 终态上的 compositor 消费并入 `program_output_consumed_layer_ids`。首版"从 expected 里减掉全 passthrough 层"的方案被既有合同测试否决（startup passthrough joins terminal evidence 要求该层计入 succeeded），改为按 subject 身份过滤后全部 133 项 benchmark 测试通过。**全 corpus 5 路并行复验（同一签名包，仅 benchmark 脚本变化）：134/159 strict PASS（+4 恰为预测样本 2134765860/3238423642/3396722575/3788897599），PASS→FAIL 回归 0**；3743305891/3775355045 等 B8 瞬态样本按裁决保持 FAIL。剩余真实缺口收敛为 3 个：3448845950 L1475、3585875739 L17（25s 未恢复）、3749463715 全链缺失。报告 SHA-256 `c1b6538296a77321…`/`614a4c12d5458d70…`/`0c6c435b4da37c27…`/`f89e2234871ffe8a…`/`d1c80b831540b0a7…`，归档 `890397672ce261f2…`，现场 `/private/tmp/mwx-corpus-rerun-fixed`。

- **2026-09-12 L1475 依赖消费豁免接入 output evidence + corpus 终验**：`3448845950` 的 gap L1475 是 B4/B5 历史形状——typed `.data` publication 被下游 322 auxiliary 消费（`dependency_consumed=[102,474,495,571,660,1475]`），batch-6 的豁免只覆盖 route 级 `missing_compositor_consumed`，没有到达 succeeded 计算的 `output_evidence` 交集。修复：`output_evidence_layer_ids` 并入 `pure_program ∩ dependency_consumed`（同一豁免语义）。三样本验证（3448845950 **严格 PASS failures=[]**；3585875739 按裁决保持 B8 瞬态 FAIL；3749463715 为真实产品失败）。**全 corpus 5 路并行终验：135/159 strict PASS（+1 恰为 3448845950），PASS→FAIL 回归 0**。剩余 24 个 NON-PASS 全部归类：12 个 effects=0 门不可满足 + 3788066613 隐藏链（产品正确）+ 6 个 B8 瞬态（按裁决如实记录）+ 4 个 B3 类 effect-local passthrough/CPU invocation 严格观察（3323988600/3395777145/3472940912/3754630802）+ **3749463715 唯一真实产品缺口**：`independentAlphaSignalCompositing` 分类的 color-transfer artifact `fallback-rejected（filter=1 lowered=1）` + `prepare-failed` 导致 16 层全链失败 + utility-capture 467 失败 + 窗口快照失败——B3 color-transfer 同族的下一产品切片。报告 SHA-256 `6abf419f696e…`/`fe44ac68f0f9…`/`75220311ef62…`/`ad27ab727d14…`/`d205d7ecc26b…`，归档 `6a15950a1759…`，现场 `/private/tmp/mwx-corpus-final-verify`。

- **2026-09-12 3749463715 信号载体终态 lowering 修复（color-transfer artifact 首切片）**：根因——`independentAlphaSignalCompositing` 分类器在 authored 级证明的两种终态取向中，"signal 载体输出"取向（`signal.rgb = ApplyBlending(..., color.rgb, signal.rgb, alpha因子)`、`signal.a = saturate(color.a + signal.a)`、`gl_FragColor = signal`）被 `SceneGenericShaderIndependentSignalCompositingLowering` 的 MSL 终态合同错误拒绝（合同只接受 `mwxFragColor = <color变量>`），导致 `prepare-failed error=colorTransfer`、16 层全链失败。修复：终态合同按 MSL 级证据接受 signal 载体输出——spirv-cross 爆开后的 `float3 temp = color.xyz`、`float3 temp = signal.xyz`、`signal.[xyz] = temp.[xyz]` 三分量写、`signal.w = (fast::)?clamp(color.w + signal.w …)` 合并 alpha 四重证明齐全才接受（拼接/反向负例仍拒绝），premultiply 包裹实际输出变量。负例合同 `compilerReversedCarrierRejected` 保持通过。验证：checkpoint build 成功；independent-signal 5 模块 + benchmark 133 项 ALL OK；签名回放 `lowering-complete` 出现、`prepare-failed` 消失、runtime audit **0→claimed=16 encoded=15 failures=1**。剩余子断点登记：L477/L533 链 first-failure（encode 成功但 graph 观察 failure 触发）、utility-capture L467/488/560/536 failed、ready 快照 `snapshot-failed reason=ready stage=metal-command-0 error=unknown`——下一周期从这三个子断点读取新的首断点。

- **2026-09-12 视觉质量断点：直接图/木偶源无 mip 的缩小采样（用户观察 3780119725、3665307769）**：维护者报告"很多样本纹理像被压缩再拉大；木偶动画层边缘锯齿与摩尔纹"。取证：主视口用原生 drawableSize（无全局 upscale）；TEX 容器保留作者 mip 链；但**直接图片上传（`SceneImageTextureUploader`）与木偶 mesh recompose 源（`ScenePuppetMeshRecomposer`）都是单层纹理**，而产品 sampler 是 min/mag/mip linear——大纹理（如 3780119725 人物 3874×2000、3665307769 人物/武器木偶层）在约 0.5× 缩小采样下产生摩尔纹与软边。官方证据：TEX V5 writer 的 `nomip` 是"生成 mip"的**反向开关**（默认生成），默认 sampler 政策 min/mag/mip linear（scene-format-and-render-graph §11）。修复：两处新建纹理改为 mipmapped 并在命令缓冲内 `generateMipmaps`（rgba8/bgra8Unorm 均 blit 兼容；premultiplied texel 在标准 mip 滤波下平均正确）。验证：checkpoint build、puppet 3 模块 + texture uploader 2 模块 ALL OK；签名回放 3665307769 与 3780119725 均严格 PASS failures=[]（结构无回归）。**视觉确认（摩尔纹/清晰度改善）待维护者复核**；登记后继：人物层 authored renderSize 捕获（3874×2000）经 scale 1.24 显示的 1.24× 上采样路径与"压缩感"的 full-res 视觉归因（§10 final scale 警告与 canvas 政策证据已列），以及 `nomip`/`halfmip` authored 状态位接入。

#### 验收台账基线（2026-09-12 全 corpus 刷新，替换 2026-09-08 生成页）

真实 numeric corpus 为 159 个样本：视觉裁决 `pass=0`、`fail=19`、`unreviewed=140`、`platform-unsupported=0`（人工裁决层不变，运行时证据不写入裁决）。**2026-09-12 用当前签名包（含 B2/B3/B4-B8 全部修复与 B7 selection memoization）5 路并行重放全部 159 样本**（matrix `mwx-full-corpus-refresh-2026-09-12-part-1..5-of-5`，报告与归档在 `/private/tmp/mwx-corpus-refresh-20260912`，源只读、benchmark 自隔离）：**130/159 strict PASS**、29 NON-PASS。新首断点分布：`scenescript=20`、`effect-chain=15`、`particle-load=9`、`texture-load=3`、`visual-review=112`、`not-run=0`；运行状态 `structural-chain-complete-visual-review=112`、`degraded-runtime=44`、`blocked=3`。相比 09-08 生成页（effect-chain=25、visual-review=117、blocked=5）：effect-chain 收敛 25→15，blocked 5→3。

**scenescript 5→20 不是结构回归**：其中 15 个样本 strict PASS（failures=[]），新增可见项全部是 typed per-target VM 失败日志——作者脚本调用未实现的官方 API（实证：`3299228616` 等的 `thisLayer.getTextureAnimation().setFrame(...)` 触发 `TypeError: not a function`，`fallback=current-frame-lower-priority` 局部 fail-soft、composition 保持）。该 TypeError 一直存在，近期 typed QuickJS 诊断与 visibility/angles owner 工作使其进入首断点分类。登记为**新集群：SceneScript 官方 API surface 缺口**（getTextureAnimation/setFrame 等，影响脚本驱动的贴图动画等动态保真，不改安全边界）。剩余 5 个 NON-PASS 的 script 样本各有独立 graph/snapshot/capability 失败，归原集群处理。

按最终完成门仍是 **159/159 未完成视觉验收**（19 待人工复裁——其中多数现已 strict PASS，可优先人工复裁、140 未裁决）。

Provenance：签名 Debug App（Developer ID，Team `H9QWU9XN8R`）executable SHA-256 `42b2ec670ff56b01…`（同 B7 memo 切片回放包）；五份 report SHA-256 `1506443318c3c8de…`/`6bc897e017c59fff…`/`4eda1155c6bd6b91…`/`3d2c07688a07a89a…`/`c074adca5a49b09f…`；归档 `script/scene_sample_debug_archive.json` SHA-256 `8032a435298bbd26…`。

**29 NON-PASS 的构成复核（2026-09-12）**：12 个为 `effects=0` 的纯 composition/particle 样本（1300076567、1439846152、1507593643、2356604986、2808874251、3002649614、3629927359、3712499998、3766415113、3790726145、3792817546、3793978239）——本轮回放带了 `--require-effect-execution --require-graph-execution` 严格门，对无 material effect 的样本按构造不可满足，属**门选择造成的假 NON-PASS**（这些样本本身 55 FPS、非黑、teardown 干净）；17 个为真实结构失败（partial claim 的 effect-chain 尾部与首帧 B8 瞬态样本 3775355045/3775373546 等）。后续逐样本收敛针对这 17 个；corpus 级基线重放应去掉不可满足门或按样本能力选择门。

**17 个真实 NON-PASS 的最终分解（2026-09-12 逐样本证据）**：
- **B8 瞬态观察 FAIL（5 个， sanctioned）**：3743305891（L23）、3747492842（L186）、3775355045（L22）、3775373546（L22）、3780940857（L17）——全部为 `layer-source-not-ready` 首帧瞬态后完全恢复（failure_count=0、expected==succeeded）；corpus 内 `transient_recovered_fallback_layer_ids` 全程为空，按 B8 裁决"观察 FAIL 如实记录瞬态"不改门禁。
- **effect-local passthrough / CPU invocation 严格合同（4 个）**：3323988600、3395777145、3472940912、3754630802——`execution_succeeded=true`、`contract_succeeded=true`，仅剩 effect CPU invocation 与 effect-local passthrough 严格观察（B3 归属的 effect 合同类）。
- **真实执行缺口（7 个，下一批修复入口）**：2134765860（expected 14/succeeded 12，gap L526、L674）、3238423642（gap L299，该层日志 outcome=succeeded 但未计入 succeeded 集合——观察合同归因待查）、3396722575（gap L120）、3448845950（gap L1475——B4/B5 历史层，dependency 豁免链需复核）、3788897599（gap L17、L283，L17 同样日志 succeeded 未计入）、3585875739（expected 1/succeeded 0，L17 有 fallback 且 25s 未恢复，非纯瞬态）、3749463715（expected 16/succeeded 0 + window snapshot failed——整链未执行，独立调查）。
- **产品正确的隐藏链（1 个）**：3788066613——唯一 effect 链在 authored-hidden 层上，capability 正确拒绝（`execution-route-layer-hidden`），观察记录 `contract_succeeded=true`；严格门不可满足，归入门语义而非产品缺口。

| 集群 | 当前阶段 | 已有门 / 当前首断点 | 下一步 |
| --- | --- | --- | --- |
| B1 | 代表与两例扩面均结构闭合，视觉待复核 | 当前 Developer ID 包的 `3749463715`、`3754639143`、`3782740481` 均严格 PASS；三例 active effect / graph layer 均有 GPU、compositor、next-frame 证据。当前批次总报告列为 5/12 PASS（report SHA `0104f3fec84c489bc8645e0163d1c9294d959cf8a89f3a62b61c3e2efa6109e6`） | B1 的结构首断点可关闭；转入三例视觉/参数复核，若发现新 exact failure 再开后继条目 |
| B2 | 代表依赖/publication 已闭合，扩展 binding 开放 | `2959875782` 的 aggregate/publication 与 layer 813 后继 B9 均已闭合。最新 `3448845950` 只剩 `180/e10` 同层 primary、`247/e0 → 571` composition provider、`691/e1 → 660` text provider 三种精确 dependency-stage 形状 | 先为三种形状逐一证明公共 source/binding/publication owner；每次回放读取新的首断点，不扩大 legacy matcher |
| B3 | 已闭合：user→SceneScript→material 与 event-only producer | `3601964477`、`2902406982` 均在改后签名 Debug App 中 strict PASS；event-only `mediaThumbnailChanged` 不再伪装 uniform writer，含 `update/init` 的未知脚本仍 fail-closed | 仅保留更广泛 shader-constant/script-instance target family 的后续能力债，不回退本批 owner |
| B4/B5 | `3448845950` terminal data/color 子切片 S3；geodraw/379 owner 开放 | layer 1475 material/copy/material 已发布 typed `.data`，layer 322 以 auxiliary data slot 消费并取得 GPU/compositor/next-frame；样本 NON-PASS 由上行 B2 三处造成。`3662790108` 的 geodraw 与 `3792249095` layer 254 仍未闭合 | 不再改 1475/322；继续 geodraw 通用 color-transfer 与 379 sampler/owner，结构 PASS 不等于视觉闭合 |
| B6 | 实现候选待真实复跑 | 当前未提交 QuickJS/LayerHost/launch overlap 修改的 focused 38 项通过；`3747492842` 尚未用当前 App 复跑 | 先构建并真实回放，核对四个 angle target 的 mutation、frame consumption 与错误 payload；失败则按新首断点修复 |
| B9 | 已闭环：目标样本平移交互 S4 | 统一 0-based bone identity，MDLS Spring 参数进入唯一 playback；普通/限幅/outside/可见回弹对照 4/4 strict PASS | 证据见下方 B9；不再从此处重复接线。通用旋转/IK、多屏、parallax 和官方 parity 仍由专项表持有 |
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

**2026-09-10 progress:** `3448845950` 的 pair publication、typed named provider 与 layer 322 auxiliary-data consumer 已在同一签名 App 中执行；当前样本首断点已转到三处 B2 扩展 binding。`3792249095` layer 254 仍开放。

- **状态**：`部分关闭（09-10：3448845950 terminal data/color S3；3792249095 owner/sampler 仍 open）`
- **问题**：generic route 内 `materialFailure.mapsToGenericOwnerRevokedVisualFailure` 成立时撤权到 previous-current。
- **已核实 owner**：产生点 `SceneResolvedMaterialExecutionCapability+Stages.swift:397-404`；消费/回滚语义 `SceneResolvedMaterialGraphComposition.swift:294/430/461`；白名单 `ProgramFirstStages.swift:388`。
- **命中样本**：`3792249095` L254e0（与 B2/B4 同层叠加，建议并入 B4 的 3792249095 归因批次）；`3448845950` L1475e0（solid 辅助层）。
- **表现**：单 effect previous-current；`3448845950` 该层是零面积 solid 层（E-V4-TEX-MEDIA-IDENTITY 曾修过其准备尺寸，此处是其后的又一拒绝）。
- **当前复跑**：`3792249095` 的 `degraded-layer-source-passthrough` 仍待处理。`3448845950` 的 layer 1475 已不再出现 generic-owner、frontend、terminal color 或 launch projection 拒绝；两个 material node 均 generic-only 编码，history 在后继帧复用，typed graph output 发布给 layer 322，后者有 GPU/compositor/next-frame。该样本的 strict NON-PASS 来自三处 `dependency-stage-reference-unsupported`，已回归 B2 扩展条目。
- **进一步归因与已修部分**：`3448845950` 的 accumulation 是 material/copy/material 的 history seed/state 结构。现行合同保留 copy content fact、反向 varying-prefix、标量 rounding→int、`.data` effect-output attachment 与 named publication；source analyzer 只把逐分量标量读取的额外 sampled slot 证明为 auxiliary data，launch/runtime 不把它当颜色。source-carried 5 项、Program finalizer 25 项、frame registry/dependency runtime/bridge 27 项、graph executor 1 项、signed build/fresh 回放见 [B5 最新证据](semantics/runtime-evidence-current.md#e-2026-09-10-b5-feedback-frontend)。没有独立 ROI/官方音频数值 parity，不能升级为 S4/S5。3792249095 的 self-composite/sampler 继续归 B2/B4。
- **已闭合 owned paths / 合同**：`SceneResolvedMaterialExecutionCapability+Stages.attachment(.effectOutput)`、GraphExecutor PairAtom 与 `+Preparation/+Validation`、`SceneGraphRenderTargetLease+Publication.fullFrameResource`、submission ticket、`SceneDependencyFrameRuntime`/registry publication、下游 texture purpose 及 source-carried auxiliary data slot 共同保持 `.data`、generation/epoch/completion；compositor 只消费 layer 322 的最终颜色，不直接合成 provider 数据。
- **完工动作**：保留 `3448845950` 子切片的回归门；对 `3792249095` 补齐 owner-revoked 的公共正例、局部失败反例和恢复帧后复跑。三处 dependency-stage 按 B2 扩展单独处理。

### B6 SceneScript 运行时异常：Vec3 回调返回值与 effectConstant 输出类型不匹配

**2026-09-10 exact runtime value:** SHA-matched `--keep-runtime` replay (`b9c601618a31372cdac091edf7e16b72f7e02f318541c2100ac9743e6ec9d3b7`) records all four angle callbacks returning the literal string `LEON`; the effectConstant `speed` callback still raises `TypeError: not a function`. The failure is now reproducible at the authored callback payload, not a staging mismatch.

**2026-09-10 runtime evidence:** fresh signed Debug replay of `3747492842` reproduced four `badReturn` angle callbacks (returned string) and one `effectConstant speed` `TypeError: not a function`; report retained at `/private/tmp/mwx-b6-run/report.json`. The blocker is now isolated to SceneQuickJS callback return coercion/ABI, rather than property binding conversion.

- **状态**：`closed（2026-09-11：3747492842 真实回放四 angle target typed Vec3 completed、badReturn 0、effectConstant 无 TypeError；strict 残留仅 B8 类 186 首帧瞬态）`
- **问题**：`3747492842` 四个 layer（796/152/265/186）的 `angles` Vec3 回调返回值无法被宿主解析（`badReturn`）；原始 `scene.pkg` 显示这些脚本先执行 `value = scriptProperties.myText`（`"LEON"`），最后 `return value`，因此返回 string 而非 Vec3。layer 173 effect 1 pass 0 的 `speed` authored value 为标量 `0`，脚本维护 Vec3 `currentOffset` 并执行 `return value.add(currentOffset)`，故抛 `value.add is not a function`；这不是宿主缺少 Vec3 API。
- **已核实 owner**：
  - Vec3 校验：`Runtime/SceneScript/SceneQuickJS.c:1010-1021`——回调返回后 `read_vec3()` 不通过即 `write_diagnostic("callback returned invalid Vec3 value")` + `MWX_SCENE_QUICKJS_BAD_RETURN`。宿主入参用 `JS_CallConstructor(vec3_constructor,…)`（`:960`），返回值必须同样是可被 `read_vec3` 读取的形状（宿主 Vec3 实例或可解析结构）；作者返回普通对象/数组/含非数值字段时被拒。Swift 侧 result 映射 `SceneScriptQuickJSDomain+FrameTransaction.swift:32`。
  - effectConstant 执行：`SceneScriptScalarRuntime.swift:358`、`SceneScriptScalarProgram+Projection.swift:174`；当前 scalar runtime 会把 authored numeric input 传给脚本，QuickJS 原生异常透传。宿主 Vec3 的 `add/subtract/multiply` 已在 `SceneQuickJSValueHost.c` 实现；focused harness 也要求 string/array/non-finite Vec3 返回维持 `MWX_SCENE_QUICKJS_BAD_RETURN`。
- **表现**：四层物体角度不动；该样本还有 layer 186 `layer-source-not-ready` 瞬时（并入 B8 类观察，不单列）。
- **当前候选**：此前三个提交已把 angle mutation callback 的 typed result 归一化；未提交差异进一步要求 fallback 必须来自 `authored_layer_mutation_count`，并让 `thisLayer.angles` 的同值 setter 也留下 authored journal，避免无关宿主 mutation 取得返回值豁免。string 错误诊断保留 `(returned string)`，数组/非 finite/无 authored mutation 继续 `BAD_RETURN`。launch 的 property overlap 只允许已证明输入集合。focused 38 项通过，但这些事实尚无当前 App 的真实 `3747492842` 运行证据。
- **定位提示**：保持现有 typed output 合同与 fail-closed；不要把字符串强转 Vec3，也不要把 scalar input 包装成 Vec3。先用当前工作树构建签名 App，复跑四个 angle target，核对 authored journal、typed frame result 和最终消费；effectConstant `speed` 的 scalar `.add` TypeError 应继续作为独立作者类型错误报告。
- **完工动作**：只有真实回放证明四个合法 angle mutation target 执行、错误 target 仍局部 fail-closed，才能关闭 B6；否则读取新的最小首断点继续修复。

### B7 运行稳定性：极慢启动 + 停止时 surface 未释放

- **状态**：`teardown 与极慢启动已闭合；稳定帧 CPU 仍 open（2026-09-09）`
- **09-10 后继**：playback 已复用 local/skin matrix scratch，26 项通过 / 1 real-fixture skip；尚无新增性能消融，不关闭 CPU 预算，见 [证据](semantics/runtime-evidence-current.md#e-2026-09-10-puppet-bone-frame)。
- **问题**：`3665307769` 启动 `startupElapsedMS=56245`（56 秒，其余样本约 8–17 秒），播放与截图正常，但 benchmark 停止窗口内 surface 未归零，进程被 SIGKILL（`process exit -15`）。
- **已核实 owner**：
  - 判定来源：benchmark `script/scene_wallpaper_benchmark.py:6921-6924`——app 日志 `phase=surface-teardown` 的 `surfaces=` 值必须为 0，否则 "Scene surfaces not released"。
  - 产品侧 teardown 链：`phase=surface-teardown` 日志的发出点（surface teardown owner，`MyWallpaperX/Core/SteamWorkshopScene/Runtime/` 内 surfaceStop 路径）；该样本播放期 audit `claimed=9 encoded=9 failures=0`，无渲染失败，怀疑点在 teardown 等待/挂起而非 encode。
- **当前真实结果**：最终统一签名包（CDHash `7019384b…`）隔离复跑 exit 0，ready `17722.143 ms`；启动前清场与停止后 teardown 均记录 `surfaces=0`，无 timeout/SIGKILL。两层 Puppet 共 34,936 vertices / 66,049 triangles，193/192/0 submitted/completed/failed，driver `27.237 FPS`；CPU p95 `34.540 ms`、main-frame p95 `34.832 ms`，pre-encode p95 `0.095 ms`、GPU p95 `10.476 ms`。report/app.log/runtime SHA 分别为 `8acf2feaa37d08215dcdf778715a1dab114f5f08e00f040ce1029a1dbea51ba3` / `a7f31187212c06d665ec00f8eec29b4681e814a59e8d6cfcabf88c7b62adf4cf` / `5611196f477bd54ae7278a1b7d03077b13242a1f2c07b7a50eb91cc41a402a2d`。严格报告仍因 B3 layer 412 的 `material-dynamic-uniform-script-attachment-unproven` 非 B7 原因而 NON-PASS。
- **定位提示**：Puppet 的 load-time coverage 批处理、prepared vertex/animation、重复帧 signature 与 caller-owned scratch 已把旧 56 秒启动和约 3.69 FPS 大幅收敛。当前剩余集中在 source-update 的 CPU main-frame，而非 drawable/pre-encode/GPU/teardown；下一步应先对两层 skinning/vertex upload 分段 profile，再决定 CPU 并行、GPU skinning 或更小的通用数据布局修正。
- **最新公共修正（2026-09-11）**：普通帧没有 bone override 时跳过仅服务 override 事务的 world-matrix 解析，保留同一 `writeSkinMatrices` parent-first skinning owner；override 路径的有限性、奇异矩阵与局部失败校验不变。Puppet 三模块、generic shader artifact 80-test 与 checkpoint build 均通过；尚无新的签名样本 A/B profile，16.67ms 预算仍开放。
- **2026-09-12 回归纠偏**：`SceneScriptVectorEvaluation` 移入公共 vector model source，三个 Puppet bridge 登记到 source-layout，rollback guard 合同恢复；property-vector 19 项、source-update 与 semantics coverage 通过。全量回归仍有独立 fixture/source-set/template/alpha 合同失败，保持开放并逐项复现。
- **2026-09-12 当前签名回放**：新 Developer ID Debug 包对隔离 `3665307769` 复放 `527/526/0`，GPU/compositor/next-frame 成立；strict 剩余为 effect CPU invocation 与 effect-local passthrough（B3 归属）。CPU p95 `37.332 ms`、main p95 `37.680 ms`、driver `26.585 FPS`、GPU p95 `10.633 ms`，B7 预算仍开放。
- **B7 全链分段 profile（2026-09-12）**：`SceneFramePerformanceTelemetry` 新增 stage 归因（`beginStage/endStage/stageSummary`，仅 benchmark 证据模式激活，普通播放 telemetry 为 nil 零成本），renderer/preflight/coordinator/compositor 全链打点。`3665307769`（VHS 闭合后严格 PASS，failures=[]，CPU p50 `34.3ms`）热点图：**frame-admission 17.6ms**（其中 `admit-prepare-frame` 15.6ms = executor.prepare 每层调用 p50 0.74ms×9 层 ≈6.7ms + target-pool 0.8ms + preflight-targets 1.2ms + prep-requests 0.5ms + 循环依赖/ledger ≈6.4ms）+ **source-update 9.0ms** + compositor-seal 5.0ms + layer-loop 1.3ms + prepass 1.2ms。per-layer executor 计时（临时维度，已撤）证明贵层为多 effect 链：`153"人物"×10 effects 4.7ms`、`71"机甲"×7 3.4ms`、`23"背景"×3 1.7ms`——成本与 effect 数线性，每 effect 每帧重做完整 Program finalization（variant selection + texture resolution + uniform encoding + assembly identity），即 runtime-architecture 5.5 登记的"Program/variant preparation 应缓存于 generation"债。下一优化切片：per-generation finalization 缓存（或稳定帧 variant-selection memoization），目标把 frame-admission 17.6ms 压向 preparation-free 的 typed-state 更新。bridge harness 补 `SceneFramePerformanceTelemetry` stub；executor/finalizer/bridge/pipeline 四模块回归 ALL OK。
- **2026-09-12 全量回归续跑**：串行 Scene runner 已重新收尾至当前游标；发现三个 cursor/dependency visibility 模块的 vector harness 因 `SceneScriptVectorOwner+PuppetBones.swift` 重复列入 source set 而无法编译。删除重复 source entry 后，`test_scene_cursor_candidate_collision`、`test_scene_cursor_capture_continuity`、`test_scene_dependency_visibility_owner` 共 15 项全部通过。该修复属于测试 harness source-set 维护，不改变运行时 owner。
- **B3 首断点收敛 → 已闭合（2026-09-12）**：三个 passthrough 均来自共享 `effects/vhs` color-transfer artifact（`shaderFrontendFailed → artifact(colorTransfer) → bounded-frontend-owner-revoked`）。预处理后 authored 源（7969B）分类为 `straightAlphaPreserving(0)`，回退失败点由新增 `artifact-color-transfer-fallback-rejected` 诊断暴露（expected/permits/strictOwner/filter/lowered 五条件）；另一会话的 default boundary lowering 工作树扩展（`SceneGenericShaderDefaultStraightColorBoundaryLowering` 等 4 文件）经当前签名包回放验证闭合：`3665307769` **严格 PASS（failures=[]，audit `claimed=9 encoded=9 failures=0`，VHS 层 encoded-output、fallback-rejected 0 次）**，现场 `/private/tmp/mwx-vhs-replay`。
- **2026-09-12 B3 生产修复闭合**：删除 same-alpha lowering 中按变量名和 `).xy;` 文本拒绝的错误生产门，改为现有 slot/projection、alpha-lane、terminal-order 与 hidden-source 结构合同；strict owner 仍阻止未经证明的编译器漂移落入 default boundary。focused sampled-alpha 2/2、签名 Debug deep/strict、隔离只读 `3665307769` fresh replay 均通过；effect-stage `27/27 complete`、runtime `27 program/0 passthrough`、command buffer `27/27/0`、GPU/compositor/next-frame 成立。B3 VHS color-transfer breakpoint closed；B7 CPU budget、B8 readiness、全样本视觉仍开放。
- **完工动作**：同 B2；此条属于 P5 范畴时按路线降级处理，但进程被杀属于硬失败，建议保持队列内。
- **2026-09-12 B7 稳定帧 variant-selection memoization 切片**：`SceneFrameTextureRegistrySnapshot` 携带 selection digest（对 MaterialProgram 变体选择路径的快照读闭包——readiness/format/purpose/content class/publication completeness——做 128-bit XOR 折叠；overlay 只按 changed entries 增量折叠，`snapshot()` 每帧一次全量），`SceneResolvedMaterialVariantCache.resolveSelection` 以 (digest, implicitFramebufferIdentity) 为 key 记忆化成功与失败结果，envelope 重编与 variant 编译写入时整体失效。首版按全量 `Set<Fact>` 键实测**回退**（CPU p50 33.6→40.5ms：每次 overlay O(entries) 构造+哈希 ×每帧 ~40-60 次），改为增量 digest 后签名回放 `3665307769` **严格 PASS（failures=[]）**、CPU p50 `34.2ms` 与基线持平（p7 基线 34.2ms），stage p50 `admit-prepare-frame 15.4ms`、`admit-executor-prepare 0.746ms/调用` 与基线一致；临时 DEBUG 计数证明 **memo 命中率 99.8%（16354 hits / 30 misses，已撤）**。结论：variant selection 并非 executor.prepare 0.746ms 的主导成本——剩余成本在 `TextureResolver.resolve`（实时资源解析，刻意不缓存）、uniform encoding、`assembleCompiled` 与每 stage 结构字典（nodes/pairNodes/validate/target 解析）。该 memo 保留为 runtime-architecture 5.5 generation 缓存债的第一块地基（正确、无回退、为结构化 finalization 缓存提供同型 key）；下一 B7 切片重新定位：**结构/dynamic 拆分**——把 texture slot 结构解析与 color contract/graph role 结果按同 digest 缓存于 generation，仅 uniform 值编码留每帧，外加 coordinator 循环（~6.4ms）的 ledger/依赖账本降本。executor/finalizer/bridge/registry/publication/sampler-purpose/opaque-alpha 七模块回归 ALL OK。
- **2026-09-12 全量回归收尾（harness 漂移五模块修复）**：全量 254 模块后台续跑后，12 个失败模块中 7 个为并发竞争（与签名回放/构建同时运行）假象，隔离复跑通过；其余 5 个为已登记的 harness source-set 漂移，按产品事实逐一闭合：① `sample_debug_archive` 产品脚本补 script 目录 sys.path shim（同 census 模式），测试改 `script.` 包导入；② `script_layer_transform_projection` 为 `SceneScriptVectorEvaluation` 迁移补 5 个 opaque Equatable mutation payload stub；③ `timeline_target_compiler` 把超时字典字面量拆分为子表达式；④ `material_copy_history_rendering` SUPPORT 补 `SceneFramePerformanceTelemetry` begin/endStage stub（同 bridge 模式）；⑤ `standard_blur_unit_composite_default` purpose fixture 镜像产品枚举全 case 并同步 `validateTextureFormat`/`sourceTypedColorSamplers`/`permitsSourceStraightColorProjection` 等真实实现、编译真实 `SceneStockTextureSemanticRegistry`，并把 harness `prepare()` 的 `prepareShaderStages` 调用补上产品 stock 路径的 `compatibilityTarget: .windowsDX11ShaderModel4`——此前 unprofiled 缺省使 `HLSL_SM30` 环境宏 fail-closed，正是 stockFact/eligibility 五项失败的根因（SIGTRAP 即 harness 把 normalize 失败当 NSError 抛到顶层）。五模块并行 ALL OK；不改变任何运行时 owner，全量 254 模块在本批后闭合为无已知失败。

### B8 首帧视频源瞬时 fallback 触发观察门

- **状态**：`closed（2026-09-12：官方证据三角定案——产品异步模型与官方一致，不改等待策略，不放宽门禁）`
- **2026-09-12 官方证据定案**：三条独立证据均指向同一合同。
  ① **公开文档**：[IVideoTexture](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IVideoTexture.html) 全部 API 只有 duration/rate/loop/play/pause/stop/isPlaying/getCurrentTime/setCurrentTime/addEndedCallback——**没有任何 readiness、loading、first-frame 查询或等待 API**；作者无法也不需要阻塞首帧。
  ② **2.8.42 客户端静态取证 §5.3/5.4**：资源/视频 readiness 只影响内部 active/wait 渲染路径；requested-playing、实际 running、frame-ready/dirty 是分开的**内部状态**；stall recovery 从当前时间重启并退避——不存在对外的首帧门。
  ③ **wallpaper64.exe 二进制复核**（radare2 字符串与导入扫描）：无 first-frame/not-ready/preroll/wait-for-frame 类字符串；Media Foundation 事件处理只有失败/卡顿诊断（`Failed handling MF video event`、`Video stutter detected`、`videomfstutterhack` 配置），视频纹理按"类似 image layer texture 渲染"（`getVideoTexture` 桥接）。
- **裁决**：官方合同是**异步就绪、无阻塞等待**——层立即存在，纹理内容由 decoder 异步发布。MyWallpaperX 现行行为（首帧 layer-local fallback 保留 previous-current，frame 10/12 起 Program/GPU/compositor/next-frame 自然恢复）与该模型一致，**不需要产品等待策略变更**。strict benchmark 观察门的 FAIL 继续如实记录该瞬态（证据模式观察，非产品缺陷），保持不放宽。
- **问题**：`3775355045`、`3775373546` frame 0 出现 `diagnostic=layer-local-fallback entries=22:layer-source-not-ready`（视频层首帧源未就绪），当前包分别在 frame 12 / frame 10 起 Program 恢复，GPU/compositor/next-frame 全部成立。benchmark 因此仍记 "resolved material graph observation diagnostic reported" FAIL。
- **已核实 owner**：benchmark 解析 `layer-local-fallback`（`scene_wallpaper_benchmark.py:625、:2875`）并把观察诊断计为失败（`:3506` 在 allowlist token 集合中，但该 token 属于"记录"而非豁免，最终仍计入 failures）。
- **表现**：两样本的首帧结构观察仍会记录 FAIL，但播放已恢复；现有 E-V4-TEX-MEDIA-IDENTITY 已证明第 10 帧恢复 Program、第 11 帧继续，publication、GPU completion、compositor 与下一帧成立。当前代码的等待/重试和 layer-local fallback 已有定向覆盖，且没有伪造 source 或扩大失败豁免。
- **裁决**：这是可观察的 provider readiness 瞬态，不是当前公共执行首断点。产品等待策略与 benchmark 观察合同仍是独立后续决策；本条不改 benchmark 门禁，也不把该瞬态改写为 PASS。
- **完工动作**：保留现有证据与严格 FAIL 事实；若未来要改变首帧等待或观察合同，另立有明确产品/门禁授权的条目。当前版本的两例运行详情已纳入 2026-09-09 总报告，不把它们计为现役 P1 清零。

### B9 Puppet visibility、bone/cursor 事务与交互验收

- **状态**：`closed（2026-09-10：目标样本真实拖动、限幅、Spring 回弹与区域外不捕获闭环，S4 visible）`。
- **已修复职责链**：`thisLayer` visibility 进入现有 stateful vector owner；cursor 借用同一 owner。真实 MDL 名称/顺序/父索引在启动安装，帧 pose 使用当前动画、override 与 image model-to-world；world setter 原子转换为 local journal，更新后代，按 cursor→update 次序交给唯一 Puppet playback。无动画但含 inline script 的 Puppet 也创建既有 playback；bone revision 独立驱动空 clip 的 mesh 更新。
- **审核发现并修复**：真实 `thisLayer` 对象漏装 bone 方法；错误的 index−1 父关系；world setter 未逆变换父矩阵；失败回调/未提交帧未恢复 pose；cursor 丢失 bone journal；静态 Puppet 没有运行 owner；关闭 parallax 时非零 authored depth 被错拒；`Vec3.length()` 缺失。未改样本脚本或添加按 ID 分派。
- **动态 graph 联动**：provider 集合只证明静态可能性，实际 publication 必须来自当帧有效 reservation。现有 runtime 记录 demanded provider，动态可见层不再重复走隐藏 provider prepass；实际 demand 的身份、尺寸、epoch 拒绝保持。
- **最终纠正**：官方公开示例证明 bone 0-based/unknown=-1，旧 1-based 导致抓错骨骼；MDLS 平移物理此前被丢弃，现由原 playback 消费并与 pose/velocity 一同事务提交。Spring release 应回弹，不能沿用旧“保持拖后位置”合同。
- **证据与续跑入口**：[B9 回弹闭环](semantics/runtime-evidence-current.md#e-2026-09-10-b9-spring-closure) 固定四次 strict PASS、GPU 源像素/同帧 terminal、可见 ROI、参数测试、原失败与复现矩阵。此断点退役，不再重复上层接线；按路线继续其他 open 条目。
- **声明边界**：目标样本 authored 半径/限幅、release 回弹、Date 隐显及主体 ROI 已验证；专项通用能力的 parallax-enabled、multi-surface、旋转/重力/IK 和官方数值 parity 未在本批验证。不据此改写全 corpus 验收数量或关闭 B7 性能预算。

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
| 3448845950 | FAIL | B3 与 B5[L1475→322] 已闭合；当前只剩 B2 扩展 `180/e10`、`247/e0→571`、`691/e1→660` 三处 dependency-stage，视觉仍待复裁 |
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
