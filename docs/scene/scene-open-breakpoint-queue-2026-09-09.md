<!-- document-role: active-plan -->

# Scene 当前断点修复队列

> 核对：2026-09-16，依据全量工具/台账审计调整入口，未重跑样本。文件名日期仅保留链接身份。
> 本文是[兼容路线](scene-compatibility-roadmap.md)的短队列，不建立第二套阶段；工程性能工作按[重构计划](engine-refactor-program.md)执行。

## 1. 当前证据边界

样本身份只用于复现，不能进入产品分派。旧 corpus 计数和人工 verdict 不代表当前 HEAD 已重新验证；技术修复不能自动改写人工验收。当前能力查[能力台账](semantics/coverage-ledger.md)，运行身份查[运行证据](semantics/runtime-evidence-current.md)。

## 2. 现役执行顺序

### Q0 — 先完成兼容路线 P0 的全量关联与采集校准

按[兼容路线 §3.2](scene-compatibility-roadmap.md#32-p0-的四个有界批次)依次交付：盘点/fingerprint/守恒校验 → 既有表的声明/公共合同/代码 owner/场景/证据关联 → 普通产品启动采集校准与 fresh 全集基线 → 共享依赖及首批修复集合。工具扩展是待执行工作，不因本次计划修改视为完成。

每一步只改其完整职责；Q1 保留已有反馈作为复现候选，实际修复顺序由 fresh 首断点、公共依赖和影响面确定，不继续按旧报告的集群数字或以下样本顺序硬排。紧急可见回归可提前修复。

当前用户仅有现成截图或视频，先登记可用参考与控制变量缺口。固定官方客户端同输入动态对照是 P4 关闭依赖；缺环境不阻塞公共实现，但不能记官方一致性通过。

P0 续跑状态（2026-09-18 08:xx 更新，事实覆盖至 `c60d26a9` 及其后的文档清理批；历史过程记录查 git log 与运行证据页的 P03 证据包，不再在本块累积流水账）：

- **现役 Goal（2026-09-18 用户授权设定）**：遵照现役 Scene 兼容执行路线，从 P0.3 收尾态持续推进——修复剩余 blocked 样本（现役唯一 `3792249095` terminal divergence；已于本批按 reference-uncontrolled 豁免，见开放项 2）与 `2959875782` 残留的 `1315#effect#1326` effect-local-passthrough 降级链、按 P0.4 依赖排序进入 P1 公共能力修复主循环、P2 逐样本剩余缺口、P3 参数与条件闭环；每批改动经独立子代理审查，保持唯一运行主链并持续消融相关冗余。遇到外部依赖记录阻塞并继续不依赖它的工作；只有真实满足整体完成条件才标记完成。提交已获用户授权（单职责分批、不推送）。

- **当前身份覆盖已完整**：159/159 样本均具备当前身份（CDHash `a31bd68a…`、executable `34bdca21…`）的 fresh 运行证据（2026-09-17 的 76 个 + 2026-09-18 串行补齐的 83 个，全部 PASS）；identity-only PASS ≠ 视觉验收完成。归档 `script/scene_sample_debug_archive.json`（SHA-256 `49c14bc7…`）状态 `128 structural / 31 degraded / 0 blocked`；验收台账与调试台账已同步。
- **已落码修复（全部已提交、各含独立审查与真实样本验证）**：
  - `SceneGenericShaderTernaryScalarConditionNormalizer`：WE 方言数值三元条件 stage-link 拒绝 → 可编译（`3767343314` 恢复）。
  - `SceneMdlPuppetMeshReader` stride 表 +48：Puppet 网格解析失败 → 角色恢复（`3767232084` 恢复）。
  - resident-target 预算公式 `/32→/16`、顶 512MB→1.5GiB（`a8fea925` 抽为 policy owner）：重型 4K 场景整帧硬拒 → 正常渲染（`3754630802` 恢复）。
  - typed geometry named-provider publication（`07133cbf`/`aca7da40`）：`2959875782` 的 publication 链闭合（定向 PASS）。
  - text host 合同补 objectText（`cc69da74`）：`3747492842` 属性绑定 9→12。
  - benchmark 观测门恢复感知（`61a69b1a`）：frame-0 layer-source 瞬态+已恢复不再误判 FAIL。
- **现役开放项（按序，各含下一步）**：
  1. `2959875782` **观测缺口已闭合（2026-09-18）**：归档 blocked 的根因是基线跑用了**旧二进制 `918475e7…`（不含 typed geometry publication 修复 `07133cbf`）**——缺观测的 4 层（19/134/138/520）正是该缺口依赖链；当前身份 `a31bd68a…` fresh 运行 47 层全观测、PASS failures=[]，归档状态随之 blocked→degraded-runtime。**现役残留（降级）**：`1315#effect#1326` 仍走 effect-local-passthrough（radius=effect、severity=degraded），是新的更小待修缺口（P2 逐样本层）。probe（2026-09-18 首轮）=已定位为 layer 1315 的 X-Ray 效果（effects/xray/effect.json），该层为用户属性隐藏层（dynamic layer visibility: value=false effective=false），fresh 运行的 admission records 恰 1 条 admitted-fallback；app.log 无该效果的显式失败诊断（sticky 日志未捕获）。归因已闭合（2026-09-18 02:5x）:该效果是**用户属性门控的条件内容**——作者声明 `visible={user:{condition:"0", name:"xraylayer"}}`（默认关、用户可切换），其依赖引用（前一效果 1324 的输出）在依赖所有权编译器中无 binding 合同 → `dependency-stage-reference-unsupported` → effect-local-passthrough 保留 previous-current。按路线图 §2.3/§3.3 属条件内容缺口（P3 范围）：用户切换 xraylayer 后该效果不会执行。下一批 probe=读 `SceneResolvedMaterialDependencyOwnershipCompiler.unsupportedReferenceEffectKeys` 对该引用形态的判定，评估为效果间引用补 binding 合同，或以固定 toggle 的条件场景验收（P3 关闭门）。
  2. `3792249095`：terminal divergence 已按 reference-uncontrolled 豁免（实时时钟内容 vs 固化预览，oracle 不适用，登记于 `scene_sample_preview_oracle_registry.json`）——现役 **0 blocked**。若该样本再现非 oracle 类失败，按新证据重新归因。
  3. `3747492842`「额外闪烁」：需固定 phase 的动态对照（文字裁切=参考视口不可控、多余 Leon=用户 Picture 属性状态差异，均已归因，见 Q1 行 1）。
  4. P0.3b 产品路径采集：选型 (b)（client/daemon 显式可取消 evidence 命令，保持"诊断非播放前置"边界），须独立设计审查。
  5. **SceneScript host 对象模型面已补齐（2026-09-18 批 A）**：`thisObject` 对 `.layer`/`.text` 属性 = 层自身对象（同一 JS 对象、写入走既有 mutation journal）、层句柄 `getChildren()`、own-layer 句柄补 `alpha`/`color` 写与 `getAnimation`（官方 `ILayer extends IObject`）。验证=host harness 新断言全绿 + 注册门 `test_scene_property_vector_script` 20/20（含反例先行：临时移除自身层 `getAnimation` 即 FAIL）+ 隔离真实回放（`3788066613` 三次 PASS，异常从 `not a function` 推进到 authored `sortLayer` 拒绝）。证据见 [E-2026-09-18-SCENESCRIPT-OBJECT-MODEL-LAYER-OBJECT](semantics/runtime-evidence-current.md#e-2026-09-18-scenescript-object-model-layer-object)。
     **批 B 设计草案（下一轮，effect 绑定 `thisObject.visible`，8 样本）**：现状=effect 绑定 owner 的 `thisObject` 是仅含 `getAnimation` 的属性对象句柄（`getEffect()` 返回的 effect handle 也只有 `executeMaterialFunction`/`name`），`thisObject.visible = x` 只写 inert 自有属性；今天靠**脚本文本匹配** `SceneInitialMediaEffectVisibilityProjection`（只识别 `3601964477` 系列两种精确脚本形状，load 期预标记 effect `visible=false`）兜底。插入点已探明：C 侧需新增 effect-visibility mutation DTO/缓冲（与 layer mutation 同型，target = (layerID, effectIndex)），Swift 侧 DTO→`SceneScriptOwnerEffects` 新字段→`SceneDesktopWallpaperHost+FrameDriver.swift`（`admittedOwnerEffects` 展平处，现 ~L616-690 只展平 `materialFunctionMutations`）→ 与 authored 属性绑定同一 `.effectVisibility` typed channel / `SceneResolvedMaterialStageActivation`。**退役条件**：实时通道须先证明 launch 期（无封面，`hasThumbnail=false`）与事件期都与投影一致，且不得与投影静默双执行；投影退役需独立校验后再删。
     **下一步（按影响面排序）**：(a) authored `sortLayer`（18 样本使用，需渲染顺序权威设计）；(b) 批 B（上述设计草案，8 样本）；(c) `thisObject.solid` / `parallaxDepth` / audio `play/pause/stop` / `alignment` / `getEffect` / 子对象 `instance` / `volume` 等无消费方成员的显式边界登记。
  6. **benchmark 观察门对时间门控层的误报（2026-09-18 新记录）**：`2959875782` 三次同二进制运行 PASS/FAIL/PASS，FAIL 的机制是 layer 1654 的 authored `visible` 脚本按墙钟秒数门控（`new Date().getSeconds() ∈ (8,40)`）——7 秒观察窗被该区间截断时该层有 first-frame 无 next-frame 证据，`resolved material graph accepted layer next-frame evidence missing` 随即误报；三次运行的层观察覆盖为 34/43/41（本身非确定）。关闭门候选：把时间门控层纳入 reference-uncontrolled/oracle 登记（与 `scene_sample_preview_oracle_registry.json` 同源），或把 next-frame 证据要求限定为"窗口内复现"语义；须独立设计审查。
- **P1 下一批选定（2026-09-18，按公共集群影响面）**：`resource-load:particle-layer-load-incomplete` 集群——9 个样本（`2974757317`、`2986218263`、`3396722575`、`3665307769`、`3690859128`、`3712499998`、`3779904456`、`3780119725`、`3788467391`）的粒子层加载不完整共享同一机制。首轮 probe（2026-09-18，样本 2974757317）：particle_candidates=3、loaded=2（`particle_loaded_layer_ids=[5944,31057]`）、skipped_hidden=1（隐藏层 1991 按设计跳过）、未加载的可见层=**85705**。即集群机制=每个样本恰有一个**可见粒子层加载失败**（非按设计跳过）。首轮代码追踪（2026-09-18）：85705 的定义 `renderers=[]` → 走 child-only 容器路径（rootRender=nil、childRuntime 注册、`admitsChildOnlyContainer` 未拒绝——诊断列表无 missingSpriteRenderer）；childRuntime 有模板（43×matrix_code + eventfollow trails，genericparticle shader 受支持、sprite 贴图在包内、深度 2 ≤ 上限）。**drop 点在 child runtime 的 advance/batch 创建段**：该层注册后从未产生 draw batch。**census 仪器化已实施并定案（2026-09-18）**：child runtime 的 advance 路径加了 DEBUG census（`phase=particle-child-census`：templates/systems/systemParticles/spawnedTotal），运行证实**粒子系统正常 spawn**——5s 时 86 系统/385 实例、14s 时 214，sticky 证据（运行中曾产出 batch 的层集合）已加入 playback state 并入档。**根因定案**：preview log 的粒子摘要是 launch 时刻（advance by 0）写入的，child-only 容器在该时刻零粒子 → `2/3 + 85705: unavailable` 是启动时点测量伪影，非粒子系统失效。**修复已实施并验证（本批）**：①Host DEBUG 访问器 `debugParticleLoadReportLines()`（surface→metalView→particlePlayback）；②runner 的 after 点经 FileHandle **追加**当前 `loadReportLines(descriptor:)` 到 preview log（首版覆写 bug 已修）；③benchmark 粒子/sticky 解析改为 last-match（快照时刻状态）；④playback state 增加 `stickyBatchLayerIDs`（任意 advance 产出过 batch 的层 ID 并集）+ loadReportLines 的 sticky 行 + child runtime 的 expansionSummary/census（templates/systems/systemParticles）。**验证**：2974757317 重跑 PASS、preview log 含 sticky 行、sticky=2/3（85705 snapshot 瞬时无 batch——census 证明 5-27s 有 214-419 活跃粒子，快照时刻的瞬时缺位是 bursty 粒子系统的测量特性）。**遗留 probe（下一批）**：playback batches 为何在 snapshot 时刻缺 85705 的 child batch（per-frame batch 层 ID 仪器化），以及该层 child 粒子（matrix_code maxcount=1）的生命周期/重生节奏是否本身就有空窗。其余集群按规模排序：scenescript 异常族（type-error 7 + bad-return 2 + reference 1 + range 1）、layer-source-not-ready 5（视频瞬态已豁免，归档仍记首帧断点）、base-image-texture-load-incomplete 3。
- **P2 视觉保真缺口（2026-09-18 用户观察）**：粒子集群样本中**流星/拖尾效果的样式与官方不符**（用户实机观察）。已知线索：集群样本含 eventfollow trail 子粒子链（如 2974757317 的 matrix_code→matrix_trail，type=eventfollow）。视觉核验（2026-09-18 09:2x，serial probe）：已查看的集群样本 after 快照渲染完整——3396722575（闪电人物场景）、3779904456（星空水体）、3665307769（光翼魔法少女）、2974757317（matrix 字符雨+音频响应）、3792249095（时钟）、3743305891/3788467391 等均完整渲染。**样式差异需用户指认具体样本与时刻**（哪次播放、哪个效果、与官方的差距形态），拿到后按 sprite 形态/运动轨迹/生命周期/发射密度归因。
- **P1 下一批选定（2026-09-18，type-error 集群归因）**：scenescript type-error ×4（layer:alpha/visibility 子簇）的异常消息已捕获——
  ①`cannot read property 'scale' of undefined`（layer 332 visibility 脚本）
  ②`cannot set property 'text' of null`（layer 344 origin 脚本）
  ③`cannot read property 'getTextureAnimation' of null`（layer 344 alpha 链脚本）。
  **归因修正（2026-09-18 复核，撤回原“对象模型缺口”结论）**：三条异常逐条对回作者数据后，全部是**作者脚本引用本样本不存在的层**，不是 VM 缺口——
  ①visibility 异常来自 `thisLayer.getParent().getParent()`：layer 332 的作者父链只有两级（332 → 316「Drag & Drop (Left)」→ 顶层），第二级 `getParent()` 官方契约为 **undefined**（[ILayer 文档](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ILayer.html)：getParent“returns undefined if the layer is not parented”），故 `.scale` 抛错；我方实现返回 `JS_UNDEFINED`，与文档一致。
  ②origin 异常来自 `durationLayer = thisScene.getLayer("playerdurationexception"); durationLayer.text = ""`：`playerdurationexception`/`playerbackgroundprogbarexception`/`playeroutlineanim` 在 `3601964477` 的 scene.json 中**只有脚本里的字面引用、没有层定义**（raw 计数 = 1，即引用本身）。
  ③alpha 异常来自 `appearAnim = thisScene.getLayer("playeroutlineanim").getTextureAnimation()`：同上，层不存在 → `getLayer` 返回 null → 成员访问抛错。
  五个同族样本（`3601964477`/`3665307769`/`3610154602`/`3612199597`/`3612795410`）都是同一作者的曲库模板被裁剪后脚本未同步：任何引擎（含官方）都无法为缺失层返回值，故这些单元是**作者内容缺陷、参考引擎同样失败**，不是我方兼容缺口；`shared` 状态对象、`thisScene.getLayer(name/id)`、`getParent()` 在失败脚本中均已实际工作（异常发生在 shared 赋值之后的语句）。
  **同簇真正的产品缺口（本批修复，2026-09-18）**：`3788066613`（EasyTransitions+ v2.1.0 幻灯片脚本，报 `TypeError: not a function`）调用 `thisObject.getChildren()`；我方 `thisObject` 此前只是仅含 `getAnimation` 的桩对象 → 调用即抛。corpus 证据：`thisObject.getChildren` ×1 样本、`thisObject.visible` ×8 样本（effect 绑定，见批 B）、`thisObject.solid` ×1 样本（无消费方，边界）。**落地内容**：`thisObject` 对 `.layer`/`.text` 属性 = 层自身对象（与 `thisLayer` 同一 JS 对象）、`getChildren()` 返回 authored 渲染顺序子层句柄、own-layer 句柄补 `alpha`/`color` 写与 `getAnimation`。**准确结论（勿写成"样本已修复"）**：对象模型面缺口已闭合，该样本的 `init` 仍中止——断点推进到 `thisScene.sortLayer(authoredChild, index)` 被拒（`sortLayer target is not an owned dynamic layer`），幻灯片过渡仍不运行。
  **下一断点（新，有证据）**：authored 层重排 = 渲染顺序权威的脚本写入面（今天只支持 dynamic 层）；corpus 里 `sortLayer` 出现在 **18 个样本**（`2241938645`/`3002649614`/`3601964477`/`3609108600`/`3610154602`/`3665307769`/`3690859128`×2/`3712499998`/`3721456868`/`3743305891`/`3763428294`×2/`3779026256`/…），是比对象模型面更大的公共面，需独立设计（作者顺序单权威 + 拓扑 journal 扩展）。
  同簇收尾（2026-09-18 批 D）：scenescript 异常族在档案中的其余单元全部归因——
  ①`3122339805` text:content bad-return ×2（layer 628/675 世界时钟）：脚本在"日期≥10"时 `return day`（**Number**），我方按"非字符串"拒绝；官方 JS 属性赋值对 String property 做 ToString 强转 → **已修**（字符串回调返回 Number 走 `JS_ToString` 强转；对象/布尔等仍拒绝）。
  ②`3470948192` effectConstant type-error（layer 113 godrays 颜色常量）：`scriptProperties.minColor.mix(maxColor, sv)`——官方 Vec2/Vec3 契约的 `mix(other, amount: Number|Vec)` 未实现 → **已修**（corpus `.mix(` 331 次/13 样本，远超单样本）。
  ③`3779026256` reference-error ×3（layer 33/248/322）：作者把 `createScriptProperties` 写成了 `export function` 却从未赋值给 `scriptProperties` 变量 → `scriptProperties is not defined`；任何 JS 引擎同样抛错，**作者内容缺陷（parity），不修**。
  ④`3470948192` layer 115 scale 的 `non-finite Vec3 output` 仅 frame-0 一次：`shared.vvv` 由 layer 181 的 text 脚本同帧稍后写入，frame-0 顺序窗口内为 undefined → NaN 被有限门拒绝（正确的 fail-soft），但 **bad-return 会永久禁用 owner**（`owner->disabled = true`），瞬态失败变成永久冻结 → 新产品语义缺口，见批 E。
  ⑤新家族：`ownerConstruction=failed ... invalidSource` 的事件-only 脚本（只导出 `applyUserProperties` 无 update/init，用户属性切换因此静默失效）共 **13 个样本**（`2902406982`/`2938612768`/`2959875782`/`3122339805`/`3211615441`/`3238423642`/`3448845950`/`3477054430`/`3509243656`/`3767460992`/`3768724269`/`3779026256`/`3780391264`）→ 见批 F。
- **批 E 候选（2026-09-18 发现，owner 失败语义）**：SceneScript owner 一次 bad-return/异常即永久禁用（`SceneQuickJS.c` 各 callback 入口 `owner->disabled = true`）。对**数据型瞬态失败**（frame-0 shared 状态未就绪导致的 NaN/类型不符）这会把"一帧回退"放大成"永久冻结"——`3470948192` layer 115 的 scale 动画因此整场不运行，而该脚本从 frame-1 起数据完全有效。候选方案：数据型 bad-return 不禁用（跳过该帧值、保留 previous-current、owner 下帧重试），代码型异常维持禁用；或两类都加连续失败预算。改动横跨 C host 失败合同与既有"disabled fuse"测试，须独立设计审查。
- **批 F 候选（2026-09-18 发现，事件-only owner）**：只导出 `applyUserProperties`（官方用户属性变更钩子）而无 `update/init` 的脚本在 Swift vector runtime 的 value-only/bool 守卫下被判 `invalidSource` 拒绝构造，用户属性切换对这些层完全失效。13 个样本受影响（清单见上）。方向：为事件-only owner 建立合法构造路径（admit 为 event-listening owner，仅在 user-property 变化帧派发），复用既有 applyUserProperties 语义而非新增第二套属性通道。
- **基础设施与边界（操作纪律）**：基线数据 `/private/tmp/mwx-fullset-baseline/`（瞬态目录，关键结论已抄录运行证据页 P03 证据包）；presentation 遥测必须单实例串行+前台+caffeinate（并行/锁屏/遮挡都会全灭）；`launch-program-failure` NSLog 在默认救援成功时也打印，勿据此归因；新 Swift 文件须同步测试源清单与 `scene_swift_source_sets.json`；新 python compile+run 测试会被 Mimosa hook 误拦，走 evidence 手动门；`--phase inner` 跳过 semantics_coverage，文档批须显式跑。
- **残留小项**：样本根注入的 `shaders/blobsSM40` 写入者未查（低优先）；P0.2 引用门 5 条 P3（`97a179a9` 批记录，线上影响为零）；`3780119725` actual-present intervals 偶发（复检 PASS）。

### Q1 — 作者参数、视觉验收与 tracked matrix

| 复现索引（非修复优先级） | 尚未关闭的问题 | 下一次操作与关闭条件 |
|---|---|---|
| 1 | `3747492842`：**两个报告症状都已归因，均非引擎缺陷**——「文字裁切」是参考图视口不可控，「多出缩小版 Leon」是用户 Picture 属性状态差异；「额外闪烁」仍未归因 | 文字裁切：用户截图第 0..65 行纯黑 → 墙纸区域 3024×1898、cover 尺度 0.878704、水平裁切 175.1px，而证据窗口 3024×1964 / 0.909259 / 233.78px（相差 58.7px）；作者 layer 152 左端在我方落 −12.9（被裁）、参考图 +38.4（可见）。该参考图登记 `reference-uncontrolled`，不作绝对位置 oracle；两模型只在尺度上一致（0.878704 vs 0.878799，差 0.01%），平移差约 8px，故绝对落点只到 ±10px 量级。小 Leon：作者 `preview.gif` 含它，它由 **layer 186**（「Picture Import」槽位，`visible.user=visible` 默认 true）绘制；受控运行 `visible=false` 把 ROI（屏幕 (330,820)-(950,1330)）亮像素从 `1.879%` 打到 **`0.000%`** 并目视确认整块消失，与用户关闭或替换 Picture 一致，属属性状态差异。**同批撤回**：早先版本据同一 ROI 断言「嵌套复合层 `visible=false` 不抑制其子树」，该断言已证伪——该 ROI 落在 186 的包围盒（x 473..1451、y 627..1181）内，测的是 Picture 而非 273；隔离 186 后翻转 `leonmovement`，全幅差异 `>60` 为 0.207% / 0.224%，而两次同配置重复的噪声地板为 0.019%，即 **273 的可见性正常**；帧内 DEBUG 观测也显示 `frameVisibleLayerIDs` 确实排除 273 及其全部 7 个子层（layers=21 visible=13）。相关 corpus footprint 数字已作废。关闭条件：本条不再有产品缺陷待修；「额外闪烁」需固定 phase 的动态对照才可裁决。见 [E-2026-09-17-REFERENCE-VIEWPORT-UNCONTROLLED](semantics/runtime-evidence-current.md#e-2026-09-17-reference-viewport-uncontrolled) |
| 2 | `1315486372` 水波纹位置异常 | 先复现与归因，再修公共坐标/采样 owner；不从症状直接指定实现 |
| 3 | `2684431262` 紫色块 | 先复现与归因，验证 source→effect→output；不得按样本特判 |
| 4 | Scene Bloom enable/threshold 尚无完整 live consumer | 沿属性 producer→typed channel→全场 post consumer 闭合；若仍 unsupported 则保留待解决边界，不据此关闭全集目标 |
| 5 | 全 corpus identity-only matrix 与人工视觉复核 | 按路线 P0/P4 维护；人工重新观看后才改 verdict；每批先定向，公共能力关闭复测全部影响集合，最终候选全集复测 |

已关闭的 Puppet、双视频、Water Waves mask、TextureAnimation 等断点不再占队列行；新回归必须建立当前复现后重新入队。其余 authored target 按实际 consumer 缺口拉入，不再把已接通的整个 script/camera/particle family 标为缺失。

### Q2 — 稳定帧性能、长稳与发布

性能与资源批次排在架构完整性和真实样本画面正确性之后；只有崩溃、OOM、预算硬拒绝或已测明显阻塞正确运行时才提前。其余按重构计划 E0 基线与测量进入 E1/E3/E4，P5 只拥有最终验收。维持作者分辨率和正确构图，不能恢复缩小纹理等错误行为换取帧率。

## 3. 观察项与能力边界

异步 provider 的短暂 not-ready 按局部 previous-current 后自然恢复；持续不恢复才登记缺口。Puppet 跨层 geometry provider、IK、完整 3D 等能力按专项合同和真实需求拉入，不恢复压平纹理捷径。

## 4. B1–B9 退役索引

已完成批次的证据只按需从[历史索引](../history/README.md)追溯，不再作为当前任务。这里不复制 PASS 数、旧命令或退役 owner 清单。

## 5. 队列维护与批次门

每项只保留问题、下一操作和关闭条件；完成后从表中移除，证据写回唯一台账。落代码遵守[开发工作流](development/development-workflow.md)，一次闭合一个完整职责并完成相称验证；提交仍需用户授权。

当公共首断点关闭、仅剩路线系统性验收时，将本文归档，取消派生队列。
