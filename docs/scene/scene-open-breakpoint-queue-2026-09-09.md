<!-- document-role: active-plan -->

# Scene 当前断点修复队列

> 2026-09-25 精简重排（用户授权）：只保留开放项与其参考事实；已关闭项的过程流水一律退役，历史证据查 [运行证据](semantics/runtime-evidence-current.md) 与 git log。文件名日期仅保留链接身份。
> 本文是[兼容路线](scene-compatibility-roadmap.md)的短队列，不建立第二套阶段；工程性能工作按[重构计划](engine-refactor-program.md)执行。
> 用户优先级（2026-09-25）：鼠标/指针交互最高；音频频谱节奏感与流星/trail 样式**搁置**后续再修。

## 1. 当前证据边界

样本身份只用于复现，不能进入产品分派。旧 corpus 计数和人工 verdict 不代表当前 HEAD 已重新验证；技术修复不能自动改写人工验收。当前能力查[能力台账](semantics/coverage-ledger.md)，运行身份查[运行证据](semantics/runtime-evidence-current.md)。语料分母 **172**（159 bare-id + 13 v2 布局；后者无身份/归档/矩阵条目，合并条件=全样本当前身份重跑）。

## 2. 现役执行顺序

### Q1 — 鼠标/指针交互簇（用户 2026-09-25 重排为最高优先）

**Q1-A 粒子控制点鼠标跟随缺失（2026-09-25 已修复，待用户实机验收）**

- 症状：`3792817546` 作者心形应跟随鼠标、`3790726145` 应有鼠标拖尾，均不动；同类"鼠标跟随"效果广泛缺失（census：CP0 `flags=1` 形态 **26 定义/14 样本**）。
- 取证事实（2026-09-25，全部已核实）：
  - 两样本粒子定义均声明 `controlpoint[0] flags=1` 且**无任何组件显式引用控制点**：心形 = `controlpointattract` **省略 `controlpoint` 字段**（官方默认 CP0）+ sphererandom 发射；拖尾 = `rope` 渲染器（默认 subdivision，不撞预算门）+ 原点发射。
  - 引擎 `SceneParticleControlPointForce.hasBoundedPointerInput` 守卫 `(1...7).contains(id)` **显式排除 CP0**；parser 对省略 `controlpoint` 无默认 0；`emitterPointerControlPointIdentities` 要求显式 `emitter.controlPoint`。
  - 官方文档示例用 CP1+ Lock-to-pointer（source-index 2026-08-01 复核），但官方 patch note 证实控制点可 "follow the cursor"，且用户实机观察证实 CP0-flags-1 样本在官方客户端跟随鼠标——旧 census "CP0 按合同无效" 结论被推翻。
- 根因定性：官方语义 = **CP0 `flags` bit0 时系统原点跟随鼠标**（发射与默认 CP 消费随动）；引擎设计把 CP0 固定为原点、指针输入只给 CP1+。
- 修复方向：①`hasBoundedPointerInput` 放行 id 0（其余约束不变）；②operator/initializer/emitter 省略 `controlpoint` 时默认 0；③CP0 指针输入驱动系统原点（含 attract 消费与发射）。
- 已实施（2026-09-25）：三处编辑（两谓词 `(1...7)`→`(0...7)`；emitter 省略源默认指针驱动 CP0，范围与 demand 收集的 sphere/box 锁定；identities 同步默认）。**影响面复核口径：28 定义/15 样本**（复扫 172 语料根，旧 census 26/14 已过期）。positionAround 路径经既有 `controlPoint ?? 0` 默认同批扩展（无样本实证，登记）。
- 验证：心形/拖尾受控指针回放视觉确认跟随；15 影响样本全复跑（10+1 遥测抖动 PASS + 3363252053 PASS + sentinel `3238423642` 四点轨迹夹具 PASS failures=[]）；`test_scene_particle_simulator` 55 用例（两处旧语义断言已迁移）+ particle_runtime/boids/refraction 全绿；独立审查 P1/P2 已闭环（测试迁移、覆盖声明更正、positionAround 登记）。
- 余量：用户实机鼠标验收；Q1-B（同批样本的镜头问题）另修。

**Q1-B 镜头视差幅度过大 + 垂直方向反转（2026-09-25 已修复，待用户实机验收）**

- 症状：`3750813609`、`3363252053` 鼠标移动时内景晃动幅度过大；上下移动鼠标时镜头变化方向与鼠标相反。
- 取证事实（2026-09-25）：
  - `3750813609`：ortho 3840×2160、amount=0.1、mouseinfluence=0.15、delay=2.0，层 parallaxDepth 为 **-2/-1/0（负深度为主）**；`3363252053` 类似且 parallax 属性门控（27 层带 depth）。
  - 现行公式 `SceneLayerParallax.offset`：`shift = (layerPos − cameraPos + mouseOffset) × depth × amount`，`mouseOffset = −mouseInWorldAxes × halfSize × influence`——含**层绝对位置的常量项**（与官方"层按 depth×镜头位移"行为不符，疑造成永久错位放大感知幅度）；负 depth 翻转方向；Y 经 `worldYDown` 取负后再乘负 depth，方向链未验。
  - 官方公开页只给 amount/delay/influence 语义，不公开公式与方向（source-index §1.3）；数值 parity 依赖 P4 固定同输入官方对照。
- 修复方向：重审 offset 公式的常量项与符号链（先修可达子集：常量项去留、Y 符号在负 depth 下的正确性）；受控指针 A/B 定位幅度/方向的量化修正。
- 已实施（2026-09-25）：实测定案——120px 反向伪影来自公式常量项 `(layerPos−cameraPos)`：cameraPosition 含动态相机原点，样本脚本读鼠标驱动相机 → 常量项被指针放大；鼠标项符号本来就对。修复=移除常量项与 cameraPosition 字段（Configuration/构造点/死参数清理），shift=−mouseInWorldAxes×halfSize×influence×depth×amount。
- 验证：受控指针 A/B 摆动 120px→≤8px（3750813609）、3363252053 复测 (2,0)≈零漂移；fixed13 门禁与基线逐样本对比除已知项外零新增（2938612768 两项波动经无本批构建对照排除）；2163522240 非 parallax 样本且 fixed13 PASS；layer_parallax/camera_shake/particle_runtime 测试绿；独立审查（P1 证据补齐+P2 死参数清理均已闭环）。
- 可见变化登记：全语料 36 个 parallax 样本 rest 态层回 authored 位；动态相机移动时视差层不再按 depth 缩放随动（两通道解耦，shake 仍经相机帧生效）。
- 余量：用户实机验收方向/幅度观感；数值 parity 仍依赖 P4 官方固定同输入对照。

**Q1-C 点击/拖动已闭合项的余量**：真实 AppKit 鼠标录屏验收、多步连续 move、compositor 窗口切片（仪器=from-launch 开关+命中盒探针；退役条件=Q1-C 收口）。**Q1-D previous-pointer 作者效果**：连续轨迹批已修正 current-only；previous 侧作者效果未验收。点击拖放本身用户已确认正确（2026-09-25）。

### Q0 — 兼容路线 P0 尾项

- SteamKit 安装身份：等用户安装签名 2.0.9 (277) 候选后冻结 bundle identity，再跑真实 QR/授权下载/三引擎播放门（用户动作）。
- 13 个 v2 布局样本：11 PASS / 2 FAIL——`2849382252`（效果首断点，见 Q3）、`3357627941`（层 55 见 Q3）。
- `2959875782` X-Ray：跨层 813 提供链已修复落地（outfit=4 验证门全过）。剩余：①同层 effectOutput 引用排除（方案已定稿未落码——落码前先扫语料该形态真实实例，XRPROBE 曾推翻同层归因）；②`.resolvedMaterial` 隐藏提供者 extent 分支的 Python 桩覆盖（审查 P2-1）。
- benchmark 时间门控层误报（`2959875782` 层 1654 墙钟门控）：关闭门候选=oracle 登记或 next-frame 窗口语义，需设计审查。

### Q3 — 效果/依赖能力缺口

- `crt_scan_line` 同层合成引用 `_rt_imageLayerComposite_<id>_{a,b}`（`2849382252` 层 205，效果整体 passthrough）——公共能力扩展，**2026-09-25 侦察完成，需三协调切片一次落地**：
  ①ownership：`+DependencyOwnership.swift` 同层分支放宽 `$0.variant == .primary` 为 primary|secondary（已验证可改，但**不可单独落地**——单独改会把层 205 从 effect-local-passthrough 推进整层 `utility-source-program-unsupported` 能力拒绝，比现状更差）；
  ②变体分类：`ShaderSchema+SamplerPurpose.graphInputSourceSlotFacts` 增加同层合成默认纹理的 provenance（`defaultTexture == .internalTarget("_rt_imageLayerComposite_<self>_{a,b}")` 且 `SceneNamedTextureReference.parse` 的 provider == effectContext.key.layerID）；`CapturedMainSourceConservation.variantRole` 的 `sourceSampler.defaultTexture == nil` 与 else 分支 bindings 守卫需同步放宽，使 `capturedMainTargetSourceSlot != nil`（现状分类为 internalFramebufferOnly → 计数 0 → :534 拒绝，已插桩证实）；
  ③运行时选择：`TextureSelection` 对 `.internalTarget` 非场景背景默认目前落 `internalDefault(name)`——需对同层合成命名改走帧快照 named target 解析（执行器 graphInternal overlay 需同时发布 primary+secondary 两变体，基准纹理=base capture）。
  验证门：2849382252 回放 crt_scan_line 从 passthrough 变真实 program 执行 + 2815826216 层 184（同形态第二实例）+ 既有 composition 样本无回归。
- `sine_wave_circle` varyingUnsupported = 作者内容限制（激活变体下读未初始化分量）；恢复需先决定"未定义分量语义"（零填充 vs 未定义），属官方对照语义决定，不得猜测放宽。
- `3357627941` 层 55 可见性脚本 `invalidSource`：已定位到 cursor route 守卫（`SceneScriptCursorProgram+Construction.swift:145-152` 的 `events.isEmpty`/`requiresFrameEvaluation`），未闭合；不得为通过放宽守卫。
- `2938612768` execution contract not satisfied + passthrough 激活证据缺失（2026-09-25 新登记，未查）。

### Q4 — 登记边界/暂缓

- `2986218263` rope trail：三处放宽全部 A/B 证据回退（flag bit0 造成 `3665307769` 红烟回归；预算放宽可见收益为零）。前置=世界空间 rope 支持设计（登记 Ⅰ/Ⅱ/Ⅲ 假设）；rope 批须同批补"粒子加载完整性"PASS 门（0/1 仍 PASS 的测量缺口）。
- `3662790108` 动态 point 光：aggregate construction-work 4096/4096 真实累积耗尽（owner 失败污染域后重建 surviving owners），未闭合。
- 音频频谱节奏感（Q1.4x 线）：**用户 2026-09-25 搁置**。恢复时下步=冻结可重放 PCM+时间轴 A/B（Q1.4y 候选已审查；勿再无依据 gain/warp 试探）。音频线其余状态见运行证据页 Q1.4 各条。
- 流星/trail 样式：**搁置**，等用户指认样本与时刻。
- `3747492842` 额外闪烁：需固定 phase 动态对照。

### Q1T — 作者参数、视觉验收与 tracked matrix

| 尚未关闭的问题 | 下一步与关闭条件 |
|---|---|
| Scene Bloom enable/threshold 无完整 live consumer | 沿属性 producer→typed channel→全场 post consumer 闭合；否则登记边界 |
| 全 corpus identity-only matrix 与人工视觉复核 | 按 P0/P4 维护；矩阵期望漂移用 `generate_scene_full_matrix.py` 正规流程（fixed13 sha pin 同步）；人工重看后才改 verdict |

### Q2 — 稳定帧性能

性能批次排在真实样本画面正确性之后（用户 2026-09-25 重申）。现役热点地图与已修项见 git（`e5b38f32` 池去重 -2.5ms/帧）；剩余增量项均 <2ms/项，下一杠杆=跨帧 program/derivation 复用（架构级，需专项设计批）。维持作者分辨率与正确构图，不以缩小纹理换帧率。

## 3. 观察项与能力边界

异步 provider 的短暂 not-ready 按局部 previous-current 恢复；持续不恢复才登记缺口。Puppet 跨层 geometry provider、IK、完整 3D 按专项合同拉入。操作纪律：presentation 遥测单实例串行+前台+caffeinate；新 Swift 文件同步测试源清单与 `scene_swift_source_sets.json`；新 python compile+run 测试走 evidence 手动门（Mimosa hook）。

## 4. B1–B9 退役索引

已完成批次的证据按需从[历史索引](../history/README.md)追溯。本表不复制 PASS 数、旧命令或退役 owner 清单。

## 5. 队列维护与批次门

每项只保留问题、根因、下一步和关闭门；完成后从表中移除，证据写回唯一台账。落码遵守[开发工作流](development/development-workflow.md)，一次闭合一个完整职责并完成相称验证；提交仍需用户授权。当公共首断点关闭、仅剩路线系统性验收时，将本文归档。
