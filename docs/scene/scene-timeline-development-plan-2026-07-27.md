# Scene 时间能力（Timeline）开发计划

> 建立日期：2026-07-27
>
> 实现基线：`daa6936`（interpretation v29）
>
> 作用：定义 Scene 时间能力从当前 `L0/L1` 到可运行、可诊断、fail-closed 最小闭环的实施顺序、样本门与验收标准。
>
> 依赖约束见 [公共能力依赖图](semantics/capability-dependency-map.md)；等级口径与当前事实见 [总覆盖台账](semantics/coverage-ledger.md)；逐项官方合同见 [运行输入、Timeline 与属性覆盖表](semantics/runtime-input-property-coverage.md) 第 4 节。本计划是 [Scene 播放能力开发计划](scene-capability-development-plan-2026-07-22.md) 中 `D10 System runtimes / Timeline` 与 `B4 Feature Breadth` 的展开，不改变任何现有能力等级。

## 0. 范围界定

本计划覆盖 `TIMELINE-001..004` 四个官方页面对应的能力，以及支撑它们的 frame-time 底座：

| 在范围内 | 不在范围内 |
|---|---|
| Timeline IR（identity、target、keyframe、mode、tangent、combined lane、event） | SceneScript VM 与 `IAnimation` 句柄（`SCRIPT-008`） |
| 绝对 scene-time evaluator 与 Loop/Mirror/Single | Puppet animation clip 播放（已有独立受限子集） |
| Bézier tangent 求值、wrap-loop | `MediaTimelineEvent` 媒体进度（`SCRIPT-036`） |
| Timeline → `SceneDynamicSnapshot` 的 typed 写回 | Model animation（`MODEL-003`） |
| frame context 的 pause/resume、delta clamp、fixed-time 注入 | 音频驱动值（并行批次，见音频频谱开发计划） |

Animation Event（`TIMELINE-004`）的 **IR 与 crossing 检测**在范围内，**dispatch 到脚本**不在范围内 —— 没有 VM 时事件只能入队并计数，不能声称已执行。

## 1. 当前事实

### 1.1 已有能力

| 位置 | 当前状态 |
|---|---|
| Timeline IR | `L0`：`SceneRenderDescriptor` 无 Timeline 结构；`scene.json` 的 `animation` 对象在 IR 构建时被整体丢弃 |
| Timeline evaluator | `L0`：无 |
| 粒子 `animation` wrapper presence | `L1`：`SceneParticleDefinitionParser.swift:303` 只记 `hasAnimation: wrapper?["animation"] != nil`，`SceneParticleSimulationSupport.swift:262` 据此把该值排除出静态 override，不解析内容 |
| Effect constant 的 `animation` 形态 | `L1` fail-closed：`SceneAuthoredTintPlanner.swift:282` 的注释明确记录 `script`/`animation` 形态的 `valueKind == "binding"` 但 `userBinding == nil`，在 `constantSource` 处被拒绝 |
| **动态值写回通道** | **已存在**：`SceneDynamicSource` 已定义 `.timeline`，优先级 `authored(0) < userProperty(1) < timeline(2) < sceneScript(3)`；`SceneDynamicSnapshotResolver.resolve` 与 `SceneSurfaceEvaluationTransaction.evaluate` 都已带 `timelineValues` 形参 |
| **动态目标枚举** | **部分存在**：`SceneDynamicTarget` 已有 `.layer(alpha/origin/size/scale/angles/color/visibility/volume)`、`.effectConstant(layerID,effectIndex,passIndex,name)`、`.text(content/pointSize/color)`、`.camera(parallax*)` |
| Scene clock | `L3` 子集：`SceneClock` 产出 `frameIndex`/`hostTime`/`sceneTime`/`frameTime`/`wallDate`，60 Hz `Timer` 驱动 |
| Scene pause/resume | `L0`：播放控制不影响 scene clock |
| delta clamp / dropped time | `L0`：`frameTime` 只做单调差值，不区分 raw delta 与 simulation delta |
| offline fixed-time adapter | `L0` |

两条决定成本的架构事实：

1. **写回通道已经建好，缺的是 producer。** `SceneDesktopWallpaperHost.renderFrame()` 已经在每帧调用 `surface.evaluationTransaction.evaluate(frameIndex:definitions:userValues:)`，只要补 `timelineValues:` 实参即可接入，不需要新增快照层或新的原子提交路径。
2. **但 `definitions` 目前只来自 `propertyBindingProgram.definitions`。** resolver 对不在 `definitions` 里的 target 报 `unknownTarget` 并丢弃，所以 Timeline target 必须先编译成 `SceneDynamicTargetDefinition` 合并进同一份 definitions，否则塞进去的值会被静默丢掉。

第三条是接口缺口：`evaluate()` 目前只收 `frameIndex`，**不收 `sceneTime`**。官方要求 Timeline「按绝对 scene time 求值；不得按显示刷新逐步前进」，因此把 `SceneFrameTiming` 送进求值阶段是 T2 的硬前提。

### 1.2 官方数据合同（一手证据）

以下结构直接来自 45 样本隔离缓存中的作者 `scene.json`，不是推断：

```jsonc
"alpha": {                       // 宿主属性；同级 "value" 是作者基值
  "value": 1,
  "animation": {
    "c0": [ /* keyframes，component 0 */ ],
    "c1": [ ... ],               // 仅 vector 目标出现
    "c2": [ ... ],
    "options": {
      "fps": 30,                 // frame → 秒 的换算基，可为小数（样本中出现 1.2）
      "length": 60,              // 总帧数；时长 = length / fps
      "mode": "loop",            // single | loop | mirror
      "startpaused": true,       // 可选
      "wraploop": null           // 可选，true 时首尾平滑
    },
    "relative": true,            // 可选
    "previewvalue": 1            // 可选，编辑器预览值，运行时不得消费
  }
}
```

keyframe：

```jsonc
{
  "frame": 15,
  "value": 0,
  "front": { "enabled": true, "x":  1, "y": 0 },   // 右 Bézier handle
  "back":  { "enabled": true, "x": -1, "y": 0 },   // 左 Bézier handle
  "lockangle": true,                                // 编辑器 UI 状态
  "locklength": true                                // 编辑器 UI 状态
}
```

四点直接影响设计：

1. **时间基是 `frame / fps`，不是秒。** 三个样本交叉验证一致：`fps=15,length=15` → 1.0 s；`fps=4,length=2` → 0.5 s；`fps=120,length=60` → 0.5 s。IR 必须同时无损保存 `frame` 与 `fps`，求值时才换算，不能在解析期就把帧号折成秒。
2. **`front.enabled` / `back.enabled` 就是官方 Bézier `both/left/right/none` 的序列化形态**，与 `runtime-input-property-coverage.md` §4.3 的 mode 表一一对应。
3. **lane 以 `c0/c1/c2` 命名，不是按 property 名分组。** 官方 Combined Animation 的「同一 animation 复用一份 mode/时长」在数据上体现为：三个 lane 共享同一个 `options`。
4. **`animation` 挂在宿主属性对象上，与作者基值 `value` 同级**，所以 target 身份完全由宿主 JSON 路径决定，不需要额外的 animation ID —— 但 `TIMELINE-001` 要求的 optional name 在随包样本中未出现，见 §1.4。

### 1.3 真实样本 census（44 个已解包样本隔离缓存，只读扫描）

排除 `objects[].animationlayers[].animation`（那是 Puppet clip ID 的整数引用，共 30 处，不是 Timeline）。统计口径为「含 `options` 的 animation 对象」：

| 指标 | 结果 |
|---|---|
| 含 Timeline 的样本 | **11 / 44** |
| Timeline animation 总数 | **48** |
| mode | `single` 25、`loop` 17、`mirror` 6（**三种模式全部出现**） |
| lane 数 | 单分量 38、三分量 10 |
| `relative: true` | 10 |
| `startpaused: true` | 6 |
| `wraploop: true` | 9 |
| fps | 30(37)、15(6)、1.2(2)、4/60/120 各 1 |
| 时长 | 0.5 s ～ 120 s |
| 每 lane 关键帧数 | 2(33)、3(27)、4(7)、5(1) |
| tangent | `front=true,back=true` 178 处；`front=false,back=false` 仅 **2** 处 |
| 同级存在 `script` | 16 / 48 |

宿主属性与现有写回通道的可达性：

| 宿主 | 处数 | 现有 `SceneDynamicTarget` | 现有逐帧 consumer |
|---|---:|---|---|
| effect `constantshadervalues.*`（`multiply` 16、`alpha` 6、`rayintensity` 1） | **23** | `.effectConstant` ✓ | ✓ 已有 strict backend live 消费 |
| layer `alpha` | **12** | `.layer(.alpha)` ✓ | ✓ `SceneDynamicLayerValues.alpha` 每帧读快照 |
| layer `origin` / `angles` / `scale` | **10** | `.layer(.origin/.angles/.scale)` ✓ | ✗ `worldFramesByLayerID` 在 `SceneMetalRenderer.init` 一次性算好 |
| text `maxwidth` | 2 | ✗ 无 | ✗ |
| camera `zoom` | 1 | ✗ 无 | ✗ |

**35 / 48（73%）的 Timeline 目标落在已有 live consumer 上**，这是批次划分的主要依据。

逐样本分布（用于选门）：

| 样本 | n | mode | 宿主 | 特征 |
|---|---:|---|---|---|
| `2998757800` | 7 | 全 loop | layer alpha | 无 script、无 relative、无 wraploop、单 lane —— **最干净的正门** |
| `3769688830` | 6 | 全 loop | effect alpha | wraploop 全开 —— wrap-loop 门 |
| `3768903841` | 4 | 全 mirror | layer angles | relative 全开、三 lane —— **Mirror + relative + vector 门** |
| `3028090166` | 4 | 全 single | alpha ×3、scale ×1 | 1 个 relative —— Single 门 |
| `3768229922` | 5 | 全 single | alpha ×2、origin ×2、zoom ×1 | 含无 target 的 `zoom` |
| `2974757317` | 6 | single ×5、mirror ×1 | effect multiply ×5、origin ×1 | script ×5 |
| `2938612768` | 5 | single ×4、mirror ×1 | effect multiply ×4、origin ×1 | script ×4 |
| `2134765860` | 6 | single ×5、loop ×1 | effect multiply ×5、angles ×1 | **startpaused ×5** |
| `2902406982` | 3 | loop ×2、single ×1 | maxwidth ×2、effect multiply ×1 | wraploop ×2 |
| `3769364482` | 1 | loop | effect rayintensity | wraploop —— **最小 effectConstant 正门** |
| `2067939514` | 1 | single | effect multiply | **startpaused + script —— 负门** |

`2067939514` 的同级脚本是决定性的负门证据：

```js
export function mediaThumbnailChanged(event) {
    var anim = thisObject.getAnimation();
    anim.stop(); anim.play();
}
```

`startpaused: true` + 由 `mediaThumbnailChanged` 驱动播放。**没有 VM 时正确行为是停在首帧**，而不是自动播放。

### 1.4 未知项（必须标为推断，不得反向写成官方规则）

以下在官方页面和随包资产中都没有确定答案，第一实现批必须 fail-closed 或按保守默认执行，并在文档中标注为推断：

1. **Bézier handle 的 `x`/`y` 单位与坐标空间。** 样本中几乎全部是 `x=±1, y=0`。是「帧」还是「归一化段长」无法从数据区分，因为 y 恒为 0 时两种解释给出相同曲线。必须先按「x 为帧、y 为值增量」实现，并在 `y ≠ 0` 的作者数据出现前不宣称 tangent parity。
2. **`relative: true` 的确切合成语义。** 推断为「最终值 = 作者基值 + 动画值」，依据是 `2134765860` 的 `angles.value = "0 0 0"` 配 `c2` 末值 `6.2831855`（2π）。需要用 `3768903841` 的视觉证据反证，不能只靠数值自洽。
3. **`wraploop` 的精确算法。** 官方描述为首尾平滑过渡，但没有公开是「末帧向首帧插值一段」还是「切线跨边界连续」。第一批只保存 IR 并按普通 loop 执行，同时输出诊断，不冒充已实现。
4. **`length` 与末关键帧 `frame` 不一致时的截断规则。** 随包样本中两者恒等，无反例可依。
5. **同一 target 被多个 lane 或多个 animation 写入时的优先级。** 官方 Combined Animation 页面未定义，`runtime-input-property-coverage.md` §4.2 已要求「取得合法 fixture 前应拒绝歧义」，本计划沿用 fail-closed。
6. **`mirror` 在端点是否重复采样。** 影响端点是否卡顿一帧，需要数值门而非目测。

## 2. 依赖顺序

```
D2 frame context (sceneTime 送入求值阶段, pause/clamp)
  -> T0 时间底座
       -> T1 Timeline IR（无损解析 + 诊断，不执行）
            -> T2 evaluator + 已有 consumer 目标（alpha / effectConstant）
                 -> T3 layer transform 目标（origin / angles / scale）
                      -> T4 缺失 target 与 Animation Event IR
```

约束：

1. Timeline 求值结果只能经 `SceneSurfaceEvaluationTransaction` 一条路径写回，**不得在任何 renderer 内直接读 Timeline IR**（沿用 [公共能力依赖图](semantics/capability-dependency-map.md) 「不在各 renderer 内分别计算 user property、Timeline 或 SceneScript 优先级」的既有约束）。
2. Timeline 是 host-shared 输入（同一 scene time 对所有 surface 一致），但**求值必须在 per-surface transaction 内完成**，与 property 输入保持同一 scope 规则。
3. T3 之前不得改动 `worldFramesByLayerID` 的缓存策略；T3 必须同时给出改动前后的性能对比，不能默认每帧全量重算所有层。

## 3. 批次计划

### T0 时间底座（前置，最小改动）

- **目标**：让 Timeline 有一个可求值、可暂停、可注入的时间源。
- **改动**：
  1. `SceneSurfaceEvaluationTransaction.evaluate` 增加 `timing: SceneFrameTiming` 形参（或直接传 `sceneTime`），`SceneDesktopWallpaperHost.renderFrame()` 透传。
  2. `SceneClock` 区分 `rawFrameTime` 与 `simulationFrameTime`，后者做上限钳制（建议 100 ms，需与既有 particle/puppet 步进一起核对，不得单方面改变现有模拟结果）。
  3. `SceneClock` 增加 pause/resume，暂停期间 `sceneTime` 冻结、`frameIndex` 不前进。
- **不做**：不接 App 播放控制 UI，不改 60 Hz 驱动频率，不引入 offline adapter。
- **验证**：`script/tests/` 新增纯 CPU 单测（不进样本门）：单调性、暂停冻结、恢复不补长帧、clamp 边界。
- **验收**：既有 45 样本的 particle/puppet/sprite 运行结果与 `daa6936` 逐项一致（本批不得产生任何视觉差异）。

### T1 Timeline IR（无损解析，不执行）

- **目标**：把 48 个 animation 无损进 IR，并对未知形态 fail-closed。
- **改动**：新增 `SceneTimelineAnimation` / `SceneTimelineLane` / `SceneTimelineKeyframe` / `SceneTimelineOptions` 结构；在 `SceneDocument` 解析宿主属性时保留 animation；`SceneRenderDescriptor` 增加 `timelines` 与 `timelineDiagnostics`；interpretation format 升 v30。
- **必须保真**：`frame`、`value`、`front/back` 的 `enabled/x/y`、`lockangle`、`locklength`、`fps`、`length`、`mode`、`startpaused`、`wraploop`、`relative`、lane 顺序、宿主 JSON 路径。`previewvalue` 单独保存并标记为不可消费。
- **fail-closed**：未知 `mode`、非有限数值、`frame` 逆序、lane 数不匹配目标类型、同一 target 重复动画 —— 全部记诊断且不产出 target definition。
- **验证**：11 个含 Timeline 样本 + 3 个不含 Timeline 的样本（确认零误报）；矩阵新增 `expected_timeline_count` / `expected_timeline_lane_count` / `expected_timeline_diagnostic_count`。
- **验收**：48 个 animation 全部进 IR；`animation` 字段的 canonical re-encode 与作者原文逐字段等价；**本批不改变任何一帧画面**。

### T2 evaluator + 已有 consumer 目标（第一个可见批次）

- **目标**：`alpha` 与 `effectConstant` 两类共 **35** 处 Timeline 真正驱动画面。
- **改动**：
  1. `SceneTimelineEvaluator`：绝对 scene time → lane 值。实现 Loop / Mirror / Single 三种 mode、Bézier 分段求值（`enabled=false` 退化为线性）、`startpaused` 保持首帧。
  2. Timeline target 编译成 `SceneDynamicTargetDefinition`，与 `propertyBindingProgram.definitions` 合并（重复 target fail-closed）。
  3. `renderFrame()` 产出 `timelineValues` 并传入 `evaluate`。
- **不做**：不实现 `wraploop`（按普通 loop 执行 + 诊断）、不实现 `relative`（含 `relative: true` 的动画本批 fail-closed）、不碰 layer transform。
- **样本门**：
  - 正门 `2998757800`（7 × loop × layer alpha，最干净）
  - 正门 `3769364482`（1 × loop × effect rayintensity，最小 effectConstant）
  - 正门 `3028090166`（single，验证末态保持）
  - 负门 `2067939514`（`startpaused` + script → 必须停在首帧，不得自动播放）
  - 回归 固定 13 样本门
- **验收**：正门样本在两个不同 scene time 采样点的 GPU 截图有确定性差异且可复现；负门样本首帧与末帧像素一致；`relative`/`wraploop` 样本出现明确诊断而不是错误画面。

### T3 layer transform 目标

- **目标**：`origin` / `angles` / `scale` 共 **10** 处生效。
- **改动**：`worldFramesByLayerID` 由 init 期常量改为按帧解析，且只在相关层存在 Timeline/动态写入时重算（父链传播必须一并失效）；`SceneMetalRenderer` 改为消费逐帧世界矩阵。
- **同时处理**：`relative: true` 的合成语义（10 处中多数在此批），先按「基值 + 动画值」实现并用 `3768903841` 的视觉证据验证。
- **样本门**：正门 `3768903841`（mirror + relative + 三 lane angles）、`3768229922`、`2938612768`、`2974757317`；回归固定 13 门 + 完整 45 门（本批触碰公共 transform 路径）。
- **验收**：`3768903841` 的往复旋转可见且端点无跳变；未含 Timeline 的样本 world frame 与 T2 逐位一致；每帧重算的耗时增量有实测数字。

### T4 缺失 target 与 Animation Event IR

- **目标**：补 `text.maxwidth`（2 处）与 `camera.zoom`（1 处）target；Animation Event 的 IR 与 crossing 检测。
- **边界**：Event **只入队并计数**，不派发。没有 VM 时不得声称 `TIMELINE-004` 已执行。
- **样本门**：`2902406982`（maxwidth）、`3768229922`（zoom）。
- **验收**：crossing 检测在大 delta、Loop 边界与 Mirror 换向下不漏发不重发（纯 CPU 数值门）。

### 不排期项

`wraploop` 精确算法、Combined lane 冲突优先级、SceneScript 驱动的 play/stop/rate、Puppet clip 与 Timeline 的统一时钟、offline fixed-time adapter —— 全部保持当前等级，等 §1.4 的未知项取得合法 fixture 或 VM 就绪后再单独排期。

## 4. 等级预期

| 能力 | 当前 | T1 后 | T2 后 | T3 后 |
|---|---|---|---|---|
| Timeline IR / identity / keyframe / mode / tangent | `L0` | `L2` | `L2` | `L2` |
| scene-time evaluation | `L0` | `L0` | `L3`（限 alpha + effectConstant） | `L3`（+ transform） |
| Loop / Single | `L0` | `L0` | `L3` | `L3` |
| Mirror | `L0` | `L0` | `L1`（IR + 诊断） | `L3` |
| Bézier tangent | `L0` | `L1` | `L3`（限 `y=0` 形态，见 §1.4-1） | 同左 |
| `relative` | `L0` | `L1` | `L1`（fail-closed） | `L3`（推断语义 + 视觉验证） |
| `wraploop` | `L0` | `L1` | `L1` | `L1` |
| Animation Event | `L0` | `L0` | `L0` | `L0`（T4 后 `L1`） |
| Scene pause/resume | `L0` | `L3`（T0） | — | — |
| delta clamp | `L0` | `L3`（T0） | — | — |

任何批次都不得把 `L3` 写成 WE parity：全部缺少 Windows 逐像素 golden。

## 5. 验证范围规则

按 `AGENTS.md` 第 6 节的两层矩阵口径：

- **T0**：纯 CPU 单测 + 固定 13 门（证明零视觉变化）。
- **T1**：11 个含 Timeline 样本 + 3 个反例样本；解析层改动触及 interpretation format，需刷新完整矩阵合同。
- **T2**：4 个定向样本（含 1 个负门）+ 固定 13 门。
- **T3**：4 个定向样本 + 固定 13 门 + **完整 45 门**（触碰公共 transform 路径）。
- **T4**：2 个定向样本 + 固定 13 门。

每批必须同时给出正向样本与「作者关闭/未声明」反例，且不得用 preview 方向性对比替代逐项断言。

## 6. 风险与对策

| 风险 | 对策 |
|---|---|
| Bézier handle 单位判断错误，曲线整体走形 | §1.4-1 已标为推断；`y=0` 时两种解释等价，先只在 `y=0` 形态宣称正确，出现 `y≠0` 作者数据前不扩大声明 |
| `relative` 语义猜错，导致旋转/位移叠加到错误基准 | T2 对 `relative` fail-closed，推迟到 T3 与视觉证据一起验证 |
| `worldFramesByLayerID` 改为逐帧后性能回退 | T3 要求实测耗时增量，且只对存在动态写入的层及其父链失效 |
| 无 VM 时对 `startpaused`/script 驱动的动画误自动播放 | `2067939514` 固定为负门，首末帧像素必须一致 |
| Timeline target 与 user property 写同一 target 造成抖动 | resolver 已有固定优先级（timeline > userProperty），T2 需补一个双写 target 的定向断言 |
| interpretation format 升版影响完整矩阵 | T1 单独一批提交并刷新矩阵合同，不与 T2 混提交 |

## 7. 与并行开发的边界

本计划实施期间需避让的在改文件（截至 `daa6936` 工作区状态）：`Core/Playback/SystemAudio*`、`Effects/SceneShakePipeline.swift`、`Effects/SceneWaterWaves*`、`RenderGraph/SceneAuthored{Shake,Tint,WaterRipple,WaterWaves}Planner.swift`、`RenderGraph/SceneAuthoredEffectChainRenderer.swift`、`RenderGraph/Scene*ShaderProfile.swift`、`Resources/SceneLayerEffectTextureLoader.swift`、`semantics/effect-execution-coverage.md`、`semantics/runtime-evidence-index.md`、`script/scene_wallpaper_sample_matrix.json`。

其中 `script/scene_wallpaper_sample_matrix.json` 与 `effectConstant` 的 strict backend 是**真实交叉点**：T2 要驱动 effect constant，而音频批次同时在改这些 planner 的 constant 解析。T2 开工前必须先确认音频批次的 constant source 改动是否已落地，避免两边同时改 `constantSource` 的准入判断。

## 8. 待补的仓库入口

以下条目在对应批次落地后补写，本文不预先声明：

1. `semantics/coverage-ledger.md` 的 `Timeline runtime` 行与 §6.1「Timeline 与 SceneScript」表的等级刷新。
2. `semantics/runtime-input-property-coverage.md` §4 各表「当前事实」列。
3. `semantics/runtime-evidence-index.md` 新增 `E-TIMELINE` 证据锚点。
4. `semantics/official-page-map.md` 中 `TIMELINE-001..004` 的归属状态。
5. `scene-capability-development-plan-2026-07-22.md` 第 8 节批次索引。
