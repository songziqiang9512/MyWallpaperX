# Scene 解析到合成链路重构计划

> 建立日期：2026-08-03
>
> 文档状态：现役执行计划，随本批工作持续更新。
>
> 事实边界：本文记录问题假设、迁移顺序、验收门和进度，不是当前能力等级或运行基线的权威入口。能力事实仍以 [`semantics/coverage-ledger.md`](semantics/coverage-ledger.md)、专项覆盖表和 [`semantics/runtime-evidence-index.md`](semantics/runtime-evidence-index.md) 为准。
>
> 工作分支：`codex/scene-capability-baseline`。计划建立快照为 HEAD `896cbb1b` 且工作区 clean；当前 R0 进展仍是同一 HEAD 上的未提交工作区，精确进度见第 8、9 节。

## 1. 重构目标

不再以逐个样本或逐个可见 effect 增加播放器侧近似为主要路线，而是系统核验并打通以下公共链路：

```text
project / scene.pkg / TEX / stock assets
  -> version-aware parse and normalization
  -> authored Scene / Effect / Material / Shader IR
  -> resource and texture-slot resolution
  -> ordered graph planning (material / copy / swap / compose)
  -> shader variant and pipeline compilation
  -> graph execution and render-target lifecycle
  -> premultiplied layer / object / scene composition
  -> explicit execution disposition and runtime evidence
```

最终要求：同一种作者合同由同一套公共逻辑执行；历史版本通过可审计的版本适配进入同一 typed IR；未知语义保持 fail closed；不得因完整 authored chain 中某一段未知而切换到整层位移、全局水波、顺序丢失或 route-only 假执行。

## 2. 计划建立时的证据基线

本节是 2026-08-03 的审计快照，后续数字变化时必须追加进度记录，不覆盖成“从未存在”。来源为现役隔离 45 样本副本、`.codex/scene-waterwaves-relocated-full45-20260803-v2/report.json`、各样本 schema 1 runtime evidence、应用日志和当前源码静态统计。

| 链路层 | 45 样本观测 | 当前判断 |
|---|---:|---|
| 基础纹理 candidate / loaded | `451 / 451` | 本批没有把主要根因指向基础纹理读取或上传 |
| missing resource | `0` | 不能解释现有大面积 effect 缺失 |
| authored graph | `489` | graph 结构已广泛建立 |
| authored effect stage | `1100` | effect 顺序和 stage identity 已进入 IR |
| graph blocker | `0` | 本批语料的首要断点不在 graph parser blocker |
| strict catalog stage | `350 / 1100`（`31.8%`） | 大部分已解析 stage 没有进入完整严格执行链 |
| `unsupported-stage` 首断 layer | `209` | 当前 chain planner 的首个未知 stage 会放大为整链拒绝 |
| `offscreen route-only` 日志 | `127` | 只发生 capture/copy，不能计为 effect 视觉执行 |
| clean authored shader contract | `161` | ShaderContract 保存面已明显大于执行面 |
| 当前 frontend 无诊断产出 program | `8 / 161` | preprocessor/include/variant/material binder 是公共前置缺口 |
| 结构上完整 strict 的样本 | `11 / 45` | 只表示 stage 数守恒，不代表官方视觉等价 |
| 部分或完全未进入 strict 的样本 | `33 / 45` | 不能继续依靠单样本 profile 累加收敛 |

源码静态快照：`SceneAuthoredEffectChainPlanner.resolveStage` 顺序尝试 34 个 planner，映射到 33 个 execution backend case（两个 Audio Bars planner 共用一个 backend）；RenderGraph 下 55 个 Swift 文件引用 fingerprint/hash，约 230 个 64 位十六进制字面量。生产代码中未发现按本批四个样本 ID 选择 effect 实现的分支；这些 hash 多数是资产 revision 的 fail-closed 准入证据，但数量表明 exact profile 已承担过多主分发职责。

### 2.1 关键样本反例

- `3766387484` layer 17 的作者顺序为 `Foliage Sway -> Water Flow -> Shimmer -> Workshop Iris -> Depth Parallax -> Twirl x4`。当前 strict planner 在 `Shimmer` 首断，完整链不执行；随后 legacy `foliagesway-uv` 接管。用户实际看到过“整块头发”以及实验放宽后的“整个头”运动。
- `3768724269` 与上者具有相同的六类局部动态 effect signature，可作为跨作品同合同正门，不能只修 `3766387484`。
- `3769688830` 同时覆盖多段 Water Waves / Water Flow / Ripple / Tint / Puppet / particle；尾巴颜色当前正常，本重构不得重新调整颜色。其鱼群水流仍需在统一链路上做最终视觉门。
- `3768903841` 当前结构上 14/14 stage 可进入 strict，但烟花仍有过曝、锁相和历史视觉回归记录，证明“stage 数完整”也不能替代时序与像素方向性验收。

## 3. 已确认的架构断点

### 3.1 双执行平面

当前有两套会竞争同一 authored layer 的执行语义：

1. authored graph 通过完整 profile 后进入 ordered strict chain；
2. chain 为空时，`SceneEffectRuntimePlanner` 再扫描 `layer.effects` 的路径和首个 pass，把多种 effect 压入固定 `SceneLayerEffectInputs` flags/参数数组，或只按 pass 数进入 offscreen copy。

第二条路径会丢失重复实例、完整 effect 顺序、material identity、slot provenance、combo、render state、RT 与 command 语义。它只能作为历史过渡实现，不能继续充当 authored graph 拒绝后的默认兼容层。

### 3.2 All-or-nothing 放大

`SceneAuthoredEffectChainPlanner` 对每个 effect 依次选择专用 backend；首个不支持 stage 通常使整个 layer chain 返回 `nil`。Iris suffix、Cursor Ripple / Shine isolation、X-Ray prefix 是局部例外，但它们会显式省略兄弟 stage，不能作为通用 graph executor。

### 3.3 ShaderContract 与执行器之间缺桥

当前 IR 已保存 source、declaration、annotation、material、nullable slot、combo、constant 和 render state，但 bounded authored frontend 仍缺：

- `#if/#ifdef/#else/#endif/#define/#undef` 等自定义预处理；
- include graph 与可追踪 source map；
- combo/default/require 形成的 variant；
- authored asset texture、graph texture、provider readiness 和 `g_TextureN*` built-in；
- 通用 material state/pipeline key 与 dynamic uniform provider。

对 `3766387484` 六类局部效果的实测表明：Foliage、Shimmer、Iris、Depth Parallax、Twirl 先被 directive/include 阻断，Water Flow 先出现 stage-link mismatch。此时直接再写一组手工 MSL 只会绕过公共缺口。

### 3.4 版本兼容位置不正确

45 样本 `project.json` 的 version 取值跨多个历史档位；98 条 effect definition path 中至少 13 条在语料中存在多个内容 revision。官方现役资料又确认：

- shader 使用独立预编译器与跨后端 translator；
- combo、typed state 和 material variant 共同决定 pipeline；
- 默认值可能从 JSON 中裁剪；
- 一些行为按作品新旧分叉，并存在随包 `zcompat` 数据层。

因此 fingerprint 应用于确认“这是已验证 revision”，而不是决定“只为这个 revision 手写哪套算法”。版本默认值、字段升级和合法兼容差异应在 graph/material execution 前归一化，并保留 provenance。

### 3.5 Shader 与 compositor 之间缺少颜色表示合同

当前 authored source 路径直接采样宿主的 premultiplied texture，并把 shader 输出原样写回。现役可执行的 rounded-mask shader 只降低 alpha、不同比例降低 RGB，静态上会制造 alpha 外非零 RGB；而 strict Opacity 已明确按 premultiplied 语义四通道同乘。

因此 R2 不能只补 preprocessor 和 texture slot。必须先定义并门禁：shader-visible input 是 straight 还是 premultiplied、不同 texture purpose 的表示、shader output 如何回到 graph/compositor，以及 blending/write-mask 的表示前提。在该合同闭合前，generic authored shader 只准入可证明 opaque 或 premultiplied-preserving 的子集；不得在某个 Opacity、mask 或样本分支里局部补乘 RGB。

### 3.6 Include 与 logical texture metadata 尚未进入统一资源链

- 当前 ShaderContract loader 只读取项目 `shaders/` 下的根 stage；include 只做词法 containment，不读取依赖、不检查 missing/cycle，也没有 source map 和 dependency digest。真实 stock include 位于 stock VFS，不能在现 loader 上直接做字符串拼接。
- shader source resolver 必须走 `SceneResourceView` 的 package -> loose -> stock 候选链，并保存候选、active dependency、hash、source map 与冲突诊断；尚未证实的同目录/根目录优先级保持 fail closed。
- graph target table 与 command runtime 当前主要携带裸 `MTLTexture`。通用 binder 需要 texture、generation、purpose、color representation、physical/mapped extent、UV、sampler、format 同代移动；copy/swap 后 metadata 也必须随 logical resource 一起推进。

## 4. 保留与重构边界

### 4.1 优先保留并复用

- PKG/TEX/JSON reader、受控资源路径和 typed runtime input；
- EffectDefinition、ShaderContract 和 authored render-plan IR；
- `SceneAuthoredMaterialResolver` 的 slot precedence 与 provenance；
- `SceneGraphRenderTargetPlan/Table`、offscreen pool 和 extent/budget；
- `SceneGraphNodeScheduler` 对 material/copy/swap nodeIndex 的顺序模型；
- 已有 strict backend 的像素门、资源候选和 fail-closed 校验。

### 4.2 需要重构的公共中枢

1. **Compatibility normalization**：按声明版本、字段存在性、source contract 和自有 manifest 归一默认值/历史形态；不修改 Workshop 文件。
2. **Shader preprocessing and variant**：include、directive、combo、环境 define、source map 和确定性 variant key。
3. **Resolved material program**：把 graph source、asset/user/provider texture、nullable slot、sampler、built-in、constant、dynamic uniform 和 render state 原子编译成可执行 pass。
4. **Unified graph executor**：唯一负责 authored material/copy/swap/compose 顺序和 logical target 推进；专用 backend 只实现已验证 pass/program，不改变 graph 拓扑。
5. **Stage disposition ledger**：每个 authored stage 必须唯一归类并记录 reason/provenance，且总数守恒。
6. **Legacy quarantine**：已存在 graph 的 layer 不得因 strict 准入失败而静默转成整层近似；迁移期间只按已验证 family 逐步关闭 legacy，避免一次性制造不可诊断的大面积回退。

## 5. 实施批次

| 批次 | 状态 | 产物 | 完成标准 |
|---|---|---|---|
| R0 端到端证据合同 | **已完成**（admission、static disposition、CPU invocation、route operation 与 shared-frame status 已分轴；修复后 full45 为 44/45，唯一红项是独立 particle baseline 偏差） | typed chain admission、descriptor stage ledger、runtime report 聚合、守恒测试 | 1296 个 descriptor effect 在当前 full45 快照中逐个有唯一 activity/strict admission；legacy/route-only/execution 分轴且不重复计数；矩阵 PASS 不能掩盖 unsupported/route-only |
| R1 统一 compile/admission model | **当前批次** | `SceneEffectStageProgram` 或等价 typed result，专用与 authored shader backend 共享输入/失败原因 | 现有 strict 输出字节/像素不变；chain planner 不再靠 34 次无原因的 Optional 探测形成最终诊断 |
| R2 shader preprocessor/variant | 待开始 | directive AST/evaluator、include resolver、combo/default variant、source map/cache key | 项目自有 fixture 覆盖嵌套条件、`#undef`、缺 include、循环 include、未知 directive；真实 contract 的 frontend 通过率按 feature 分类提升，不以放宽错误为目标 |
| R3 通用 material binder | 待开始 | slot 0...7、graph/asset/user/provider、sampler、resolution/mapped/UV、constant/dynamic uniform、typed state | nullable slot 不压缩；candidate generation/metadata 原子；跨 revision 同语义得到同一 typed program，未知 purpose/state 失败关闭 |
| R4 unified graph executor | 待开始 | material/copy/swap/compose 的唯一执行入口和 logical target lifecycle | authored 顺序、effect input/output、command ordinal、RT extent/format/clear/unique 守恒；不通过 legacy planner 重新解释 layer |
| R5 迁移 strict backend / 隔离 legacy | 待开始 | 既有 dedicated backend 逐族接入 unified executor，删除相应 fallback 权限 | 每迁移一族同时有正例、版本变体、默认关闭/坏 slot/坏 state 反例；同族多个样本受益后才移除旧路径 |
| R6 局部动态与水流视觉闭环 | 待开始 | Twirl/Shimmer/Iris/Foliage/Water/Depth 等在公共 executor 上执行 | `3766387484` 与 `3768724269` 同时恢复局部而非整头运动；`3769688830` 鱼群/水流跨相位可见且尾巴颜色不回归；外部 mask ROI 稳定 |

R0 是防止继续误判的基础，但不能被表述为视觉修复；R1-R5 也不能用“frontend 能编译”替代实际 GPU pass 和合成证据。

## 6. 验收矩阵

### 6.1 结构守恒

- 每个 visible authored stage 恰有一个 disposition：`executed-dedicated`、`executed-authored-shader`、`degraded-passthrough`、`legacy-approximation`、`route-only`、`unsupported-*` 或明确 author-inactive；最终枚举以实现审查为准。
- graph/effect/node/material/texture identity、effect order、nullable slot 和 command ordinal 不因 backend 选择改变。
- unsupported stage 不得使同 layer 被另一套 planner 无诊断重复执行。
- `route-only`、非黑帧、GPU frame 完成和 stage recognized 均不得计作视觉支持。

### 6.2 跨版本与跨样本

- 高频 family 至少覆盖两个不同内容 revision 或两个不同作品，优先使用现役语料中的 Shake、Water Waves、Pulse、Water Ripple、Water Flow。
- `3766387484` / `3768724269`：相同局部动态 signature 的跨作品正门。
- `1937925563`、`3738202317`、`3767232084`：当前结构完整 strict 的回归控制组。
- `3299228616`：216 个 stage 的大图压力与混合支持面反例。
- `3769688830`：水、鱼群、Tint、Puppet、particle 交叉系统门。
- `3768903841`：stage 数完整但视觉/时序仍可能错误的反作弊门。

样本 ID 只进入矩阵与证据，不进入生产能力选择。

### 6.3 视觉与运行时

- 局部 effect 至少检查 mask 内变化、mask 外稳定、双侧覆盖、alpha/premultiplied 和 3 个以上相位。
- 顺序敏感链必须有顺序扰动负例；重复 effect 不能被合并成一个 flags 位。
- 定向样本通过后按影响面选择相关测试与 fixed gate；只有跨样本风险无法由定向和 fixed gate排除时才运行 full45。
- 没有合法 Windows 同相位 golden 时，只报告结构执行与方向性接近，不宣称 Wallpaper Engine 像素等价。

## 7. Ghidra 使用门

优先顺序固定为：现役语义文档与专项表 -> 已归档官方静态取证/变更日志/zcompat -> 官方公开文档 -> 真实样本结构和黑盒运行证据。只有以下问题仍无法判定时才补做 Ghidra：

- compatibility patch 的匹配对象、应用顺序或 fallback；
- compose/full-frame pair 与 scene background 的关键运行顺序；
- shader default/reflection、material function 或 persistent swap 的生命周期；
- 同一问题存在两种都会导致不同公共架构的合理解释。

Ghidra 只记录控制流、数据形状、顺序和失败边界；不复制官方算法、payload、shader 或资产。

## 8. 进度记录

### 2026-08-03：计划建立

- 已撤回并重新构建验证此前导致 `3766387484` 整头运动的 experimental masked-local 代码；当前 HEAD 与签名 Debug build 回到干净基线。
- 已完成 45 样本第一轮 end-to-end census，确认基础纹理/graph IR 不是本批主断点，execution/composition 是主要缺口。
- 已对照 `render-graph-shader-coverage.md`、`capability-dependency-map.md`、`client-runtime-static-forensics.md`、`client-changelog-forensics.md` 与 `zcompat-backward-compatibility-forensics.md`。
- 已用当前 frontend 对 161 个唯一、无 loader diagnostic 的 authored shader contract 做只读编译探测：8 个无 frontend diagnostic，153 个在 directive、define、type 或 stage link 阶段失败。
- 已决定不继续修改尾巴颜色，不为 Twirl/Shimmer 增加样本专用或整层近似 backend。
- 正在设计 R0 stage disposition 的正式 schema、运行报告聚合与总数守恒门；本步不改变渲染输出。

### 2026-08-03：R0-A typed admission 与 stage ledger 落地

- `SceneAuthoredEffectChainPlanner` 已新增 typed `admit` 入口；旧 `plan -> Optional` 仅投影 `admission.chain`，renderer/compositor 的像素路径暂未改签。
- 稳定拒绝码已区分 graph blocker、缺失/重复 layer descriptor、outer-chain identity/topology、stage-node identity 与 `unsupported-stage`；新 stage ledger 对 Iris terminal suffix、X-Ray prefix、Cursor Ripple / Shine isolation 使用带完整 `EffectKey` 的 typed coverage，不再由 stage 数猜测。旧 `authoredEffectGraphXRayPrefix*` 投影随后也已改为只消费 typed `.xRayPrefix`，不再把 Iris/isolation 误报成 X-Ray。
- stage ledger 改从 descriptor 枚举全部 effect，分离 `activity` 与 `strictAdmission`；作者关闭、layer effective invisibility（自身、祖先或可见性环）、strict dedicated、strict generic 和 not-admitted 不再混成一个执行枚举。`ParsedCount` 当前等于成功建立的 ledger record 数，不表示 stage 已进入 authored graph parser。backend/profile 由 Swift 输出稳定名称，Python 不根据日志路径猜测。
- Swift 侧以独立 descriptor key set 与 visible chain stage key set 检查身份守恒，并校验 descriptor/graph/stage definition path 一致；benchmark 会拒绝重复 identity、计数漂移、非法轴组合、结构性 graph/invariant rejection、缺 chain-stage count，并生成逐样本 canonical SHA-256。旧报告解析仍可兼容无新 evidence；定向门新增 `--require-effect-stage-admission` 后会强制当前二进制产出台账。fixed/full 矩阵字段注册仍属于 R0-B。
- 最终源码已通过 `test_scene_authored_effect_chain_planner.py` 7 项、`test_scene_authored_effect_execution.py` 11 项、`test_scene_wallpaper_benchmark.py` 69 项；Scene 全量 167 modules ALL OK；Swift code health 为 754 files / 44 locked legacy / 400-line limit，`script/build_and_run.sh verify` 与 Developer ID 签名构建通过。四个历史 standalone harness 同步补齐了现役 `MaterialAsset.shaderPathIndependentSHA256` mock 字段，消除了此前 full-suite 编译漂移。
- shader/material 审查确认容器/descriptor、effect identity、graph topology 与 scheduler 骨架可保留，需公共重构的是 compatibility/source/variant -> prepared material pass -> typed texture resource -> offscreen/composite；这不证明现有 shader frontend、绑定和颜色表示正确。现有资料已足以定架构边界，本阶段不需要补做 Ghidra。

### 2026-08-03：R0-A 最终定向运行闭环

- 最终签名 App executable SHA-256 为 `01d13bf8a641cb7e06740f0fecfae6ae957e4a8743443aa4ca0439d54473658e`，CDHash `6552b1aed695ea83772755ffe99d8d7838d8f250`。当前报告为 `.codex/scene-chain-r0a-final-v2-20260803/report.json`，命令显式启用 `--require-effect-stage-admission`，6/6 样本 PASS、loaded ratio 均为 1、stage ledger `validation_failures` 均为空、authored GPU failed layer 均为空。
- `1937925563` 完整控制组保持 `13 chains / 51 stages`，51 个 descriptor effect 全部是 `admitted-dedicated + complete`；旧 GPU succeeded layer 集合不变。
- `2470144420` 精确记录 `5 terminal-inline-prefix + 1 terminal-inline-suffix`；`2974757317` 精确记录 `1 isolated-accepted + 6 isolated-omitted`。两者的旧 X-Ray prefix count 已从错误的 1 修正为 0，strict stage/GPU succeeded 集合保持不变。
- `3747492842` 是真正的 X-Ray prefix 控制组：layer 434 为 `1 prefix-accepted + 3 prefix-omitted`，旧 utility `captureAfterChildrenXRayPrefix` 仍成立，X-Ray prefix count 保持 1。
- `3769688830` 的三个 Scroll stage（layers 245/297/574）明确记录为 `admitted-generic / authored-shader / scroll / complete`；本步只证明现有 generic 路由被准确记账，不表示鱼群水流已经恢复。
- `3766387484` 共 13 条唯一 ledger：3 author-disabled、10 active。layer 17 的 Foliage/Water Flow 是 `discarded-strict-prefix`，Shimmer 是首个 `unsupported-stage`，其后 Iris、Depth Parallax 与 4 个 Twirl 均为 `not-evaluated-after-chain-rejection`；既有 layer 80 Light Shafts 仍是唯一 strict succeeded stage。该证据解释“整块/整头近似”的链路原因，但没有改变像素执行或修复局部头发。
- 本轮 6 个样本共覆盖 209 个 descriptor effect，不替代 1296 effect 的 full45 总账。截图/motion 指标是 advisory，只能说明结构和 GPU 路径未出现明显退化；没有同相位 Windows golden，不能声称像素不变或与官方等价。旧 full45 仍是 44/45，不能写成 PASS。

### 2026-08-03：R0-A 矩阵合同与刷新防护闭环

- stage admission 在 benchmark report 内新增独立 `schema_version: 1`，顶层 report 仍保持 schema 2，launch-time `scene-runtime-evidence.json` 仍保持 schema 1；三层 schema 不再混用。矩阵合同独立注册 schema、descriptor/parsed 数、activity/strict/coverage 三组计数和 canonical SHA-256，完整 records 不写入矩阵。
- 旧矩阵完全没有该字段族时继续兼容；一旦任一 stage admission 字段进入矩阵，整组字段必须同时存在，缺 evidence、schema 漂移、计数/哈希不一致或 Swift/Python 守恒失败都会 fail closed。
- full-matrix generator 新增 `--scope effect-stage-admission`。该模式即使接受因无关能力导致 overall FAIL 的完整报告，也只允许更新注册字段，并强制核对 report schema、矩阵 name/path/SHA、完整 sample ID 集、project/package hash、package file 和每个样本的内部 stage evidence；目标样本报告不能缩写 full matrix。
- 默认全量刷新现在必须使用 overall PASS 且通过同一身份前置门，避免把失败运行中的 particle、visual 或其他能力漂移写回基线。当前 6 样本定向报告已实测被 scoped generator 以“sample IDs differ”拒绝，未修改 fixed13/full45 矩阵。
- 新增/更新的 Python 合同测试共 80 项通过，另通过 `py_compile` 与 `git diff --check`。本步没有改变 Swift 像素路径，也没有运行或声称 full45 PASS。

### 2026-08-03：R0-B static disposition 与 route group 闭环

- descriptor ledger 现在逐条输出独立的 static runtime disposition：strict dedicated/generic/inline suffix、strict omission、legacy exact/coalesced inline、legacy exact/coalesced offscreen、structural member、shadowed、route-only、composite-refused、unsupported 和 inactive。每条记录保留完整 `EffectKey`、definition path、attribution、role 与稳定 reason；`unattributed` 会被 benchmark 拒绝。
- layer route group 明确命名为 `effect-induced-static`，只描述 effect 导致的静态分组，不冒充完整 compositor route。完整 route 仍可能由 utility/source copy/color blend/dependency 等非 effect 条件改变。
- legacy selector 已按 effect index 保留精确 identity；Water 多实例的 flag 触发者与参数写入者、首参数/首可解析 normal hybrid、Perspective+Opacity 组合 mask、Iris 优先于 Opacity、Gradient clipping structural member、Blur family specific-before-general 均进入可审计归类。没有加入样本 ID、layer ID 或资产 hash 分支。
- Swift 侧 full admission -> disposition 守恒已覆盖 inactive、dedicated/generic、terminal suffix 与 strict omission，不再只比较 strict chain owners。CPU route harness 覆盖重复 descriptor ID、禁用/hidden、route-only、composite refusal、coalesced Water/Iris、资源 hybrid、Blur precedence 等 15 个公共正反例。
- benchmark report 新增嵌套 `runtime.effect_runtime_disposition` schema 1，验证 group/record 计数、所有状态组合、完整 EffectKey + path join、守恒和 canonical SHA-256；CLI 新增 `--require-effect-runtime-disposition`。矩阵合同注册 8 个聚合字段，generator 新增 `--scope r0-effect-ledgers`，只允许原子刷新 admission + disposition，不修改无关基线。
- 首次定向报告 `.codex/scene-chain-r0b-targeted-20260803-v1/report.json` 将 `2974757317` 的合法 inline-Opacity + capture passthrough 误判为失败。校验器已精确改为要求 passthrough 至少含 route-only 或实际 legacy inline contributor，并保留“只有 unsupported 不得通过”的反例；不是放宽所有 passthrough。
- 替代报告 `.codex/scene-chain-r0b-targeted-20260803-v2/report.json` 使用 executable SHA-256 `9088fe5c1f7bf8ea47416672f412cc2df98ba80ea38422a256f06ea69f1b58f9`、CDHash `4b79370092f7a674d8ab3183b2663203f6638942`，显式要求 admission + disposition，6/6 定向样本 PASS，所有 disposition `validation_failures` 为空。91 项 benchmark/matrix 合同测试通过；Scene 全量 168 modules、Swift code health 和 `script/build_and_run.sh verify` 已通过。
- `3766387484` 的 13 条 descriptor 中，3 inactive、1 strict dedicated、2 legacy exact inline、7 unsupported。layer 17 可精确看到 Foliage 与 Iris owner，同时 Water Flow、Shimmer、Depth Parallax 和 Twirl 仍未进入可执行公共路径；该结构解释为什么现有 legacy 近似不能恢复局部头发，但本步没有修改像素。
- `3769688830` 的 59 条 descriptor 中，30 strict、6 legacy inline、5 legacy offscreen、17 unsupported、1 inactive；12 authored group 与 5 legacy offscreen group 并存。人物复合 layer 21 的 Water Waves/Water Flow 等仍 unsupported，五个 workshop WaterRipple/WaterFlow/Opacity group 只有 Ripple normal 与 Opacity 被记为 owner；这为后续统一 executor 的迁移顺序提供反例，不表示鱼群水流已恢复。
- 仍有两个明确 residual：legacy offscreen precedence 目前在 decision builder 与 renderer 各维护一份；当前 harness 证明本版两者相同，不能保证未来自动防漂移。其次，本节只建立 static planning truth，尚未证明 backend 在帧内被 CPU 调用，更不能从共享 command buffer 推出逐 stage GPU/视觉成功。

### 2026-08-03：R0-C CPU / route / shared-frame 动态证据（已完成）

- 新增独立的 `effect-cpu-invocation`、`effect-route-operation` 与 `scene-frame-command-buffer` schema 1 轴。exact subject 使用完整 `layerID + effectIndex + descriptorID`；真实 coalesced legacy subject 只允许 `layer + family` aggregate。CPU 成功/失败、route 成功/失败、共享 command-buffer 完成/失败均为独立 sticky 事实，后续成功不会删除历史失败。
- shared frame command-buffer 完成只说明包含该 cohort 的共享提交完成；不得回写成单 stage GPU 成功，更不能表述为视觉正确。旧 `authored-effect-graph` layer 级混合指标暂时保留兼容，不作为 stage truth。
- strict chain、standalone authored plan、Iris terminal suffix、quad Light Shafts 与 utility origin 已接入真实编码点。为保持文件职责与 400 行合同，原有 stage dispatch、standalone branch、utility frame 执行和 quad Light Shafts 分别拆成完整类型/职责文件；本次拆分不改变 shader、blend、顺序或纹理算法。
- benchmark 新增 `runtime.effect_execution` 与 `--require-effect-execution`，按 static disposition 回连 exact/aggregate，拒绝 unsupported、inactive、omitted、structural、shadowed、composite-refused、route-only 或无归因 subject 冒充执行。eligible/observed/gap 分开输出，未观察不伪装成成功或失败。
- 第一阶段接入后的正式 `script/build_and_run.sh verify` 通过，Scene 全量重跑 169 modules ALL OK；这组结论早于下述 legacy 接入修正，legacy 修正完成后必须再次跑相关测试、verify 与 Scene 全量，不能复用旧结果。
- 首轮动态报告为 `.codex/scene-chain-r0c-targeted-20260803-v1/report.json`，8 个样本中 6 个 PASS。`3768724269` 因只有 2 个 legacy exact inline owner 而没有动态 axis，正确暴露 legacy 执行尚未接入；`3769688830` 因三个 Scroll 的 static family 为 `scroll`、dynamic 错写为 backend 名 `authored-shader` 而失败。两项都不得通过放宽 benchmark 解决。
- 当前修正方向与原计划一致：strict generic 动态 family 改从 authored shader profile 取值而 backend 仍保留实际 backend；legacy 非 authored compositor 改为只构造一次 `SceneLegacyEffectPlanningDecision` 并直接消费其 `runtimePlan`，随后在 direct inline、source capture 和各真实 offscreen stage 编码点记录 invocation/route。unsupported、shadowed 与 structural disposition 永不生成 invocation。
- 本节仍不是视觉修复：`3766387484` 局部头发、`3769688830` 鱼群水流、`3768903841` 烟花方向性尚未闭环；尾巴颜色逻辑没有触碰。

#### R0-C 定向修正与稳定性复核

- 修正后的 `.codex/scene-chain-r0c-targeted-20260803-v2/report.json`、`v3/report.json` 与 `v4-long/report.json` 使用同一签名 App；两次 10 秒和一次 20 秒均为 8/8 PASS，loaded ratio 均为 1，CPU/route failure、shared-frame failure 与 validation failure 均为空。
- `3768724269` 现在观察到 2/2 eligible exact：Iris 与 Foliage 分别回连 `17#effect#174`、`17#effect#42`；`3769688830` 观察到 41/41 eligible exact，其中三个 Scroll 均为 `family=scroll`、`backend=authored-shader`，五组 legacy Water Ripple Normal + Opacity owner 也从真实 capture/offscreen 编码点回连。
- 三轮 exact/aggregate eligible、observed、gap 及 CPU/route transition count 逐样本一致。`3747492842` 稳定保留 1 个未观察的 chromatic-aberration eligible gap，说明 eligible 是静态可执行 subject 集，不等于该运行窗口必然调度；该 gap 必须显式保留，不能伪造 invocation 消除。
- 现有 dynamic canonical SHA 不稳定：`3747492842` 的同一 `legacy-direct-layer` route 首次出现于 frame 25 与 frame 4，虽然 subject、CPU/route count、eligible/observed/gap 完全一致。故 matrix 不得注册现有 canonical SHA、frame ID、frame 数组或 completed/failed frame ID；首批只允许 schema 与 exact/aggregate 三元守恒字段。CPU/route count 继续作为报告证据，暂不锁定为矩阵基线。
- 当前签名 App executable SHA-256 为 `b4145097e365166b14e487722c195de46d73cdec75fd79d7b70c8d30af90c8ed`，CDHash 为 `42dd22212b517007a26f700aab2d4a55053c11d4`。legacy 修正后 `script/build_and_run.sh verify`、Swift code health（767 files / 44 locked legacy / 400-line limit）与 Scene 全量 169 modules ALL OK。
- 矩阵合同已用共享 `EFFECT_EXECUTION_EXPECTATIONS` registry 闭合生成端、benchmark 消费端与 scoped refresh：只注册 schema、exact eligible/observed/gap 与 aggregate eligible/observed/gap 共 7 个稳定字段。旧矩阵不含字段时继续兼容；字段族部分存在、值漂移或注册字段要求却缺少 evidence 时 fail-closed。CPU/route transition count、frame 数据与 canonical SHA 明确不参与矩阵比较。
- benchmark/matrix 合同测试现为 113/113 PASS，另通过 `py_compile` 与 scoped `git diff --check`。本步只补证据合同，不改变 Scene 像素路径；下一步才是唯一一次 full45 里程碑核验。

#### R0-C full45 首轮里程碑核验

- `.codex/scene-chain-r0c-full45-20260803-v1/report.json` 使用上述同一签名 App 与完整 45 样本矩阵，10 秒窗口并显式要求 admission、disposition、execution。结果为 **42/45，FAIL**；App identity、矩阵 45 样本集合、project/package identity 与签名前后验证均完整，报告不能写成 PASS，也未触发 scoped matrix refresh。
- `2067939514` 仍是既有独立 particle baseline 漂移：candidate 与 skipped-transparent 不匹配，不属于本轮 R0 effect chain 修复范围。
- `3766415113` 没有 effect descriptor、static disposition group、exact/aggregate eligible subject 或 route demand；它没有 execution 日志是合法空执行。失败来自 `--require-effect-execution` 被无条件套用到所有样本。公共修复应由同代 static disposition 判断 execution demand：非 inactive route group 或 exact/aggregate eligible 非零才强制日志；missing/invalid disposition 继续 fail-closed，不能按样本豁免。
- `3757555836` 暴露的是既有真实 X-Ray 资源/合成缺口，不是 telemetry 误报。slot 1 指向 `兰汤春酽_原画h` 的 8024×4566 opaque TEX/JPEG；当前按 generic `preservedChannels` 载入时因 4096 上限缩放而失败。pointer outside 的 identity 帧随后成功，旧聚合把先前失败从集合中抵消；sticky 三轴正确保留了失败。hover 截图中主体图层整块消失成灰底，只剩粒子，故不得通过关闭 sticky、忽略启动帧或放宽门禁解决。
- 现役 X-Ray shader/slot 分析已足够确定：slot 1 是替代画面的 straight color + alpha，而不是 flow/normal 等任意 data texture；slot 2 halo 仍需保留 R×A 通道，slot 3 仍是 mask。下一步只允许建立语义化 straight-color 路径，并仅对可证明 opaque 的输入允许安全 raster/resize；不得恢复对任意预乘/缩放 data texture 的有损反推。现有资料足以支撑本修复，未启动 Ghidra。

#### R0-C 公共修复与定向复核

- execution evidence 的需求改由同代、有效的 static disposition 统一推导：exact/aggregate eligible 非零或存在非 inactive route group 时必须有 evidence；真正空 effect/纯 inactive 合法无日志；missing、schema/validation 无效和未知 group kind 继续失败关闭。benchmark 与 matrix generator 共用同一函数，旧七字段合同仍严格生效。
- X-Ray slot 1 改为 typed `straightAlbedo`，slot 2 halo 继续 `preservedChannels`，slot 3 opacity 继续 `mask`；只有 CGImage 明确无 alpha 时才允许 bounded raster/resize，并固定输出 alpha 为 1。format-0 embedded mip 路径透传实际 purpose，alpha-bearing、premultiplied 与其他 data purpose 的严格拒绝不变。
- `.straightAlbedo` 的共享影响已在 REFRACT 同源 color/normal 复用处守住：只有 texture 尺寸和 mip 数与 authored container 完全一致才可复用；发生 resize/raster 导致物理形态改变时拒绝，不能把颜色纹理静默当 normal。
- `.codex/scene-chain-r0c-targeted-xray-demand-20260803-v1/report.json` 使用新签名 App，对 `3757555836`、`3766415113`、`2998757800`、`3747492842`、`2884628849` 为 **5/5 PASS**。`3757555836` frame 0 的 X-Ray → Water Flow → Ripple → Water Flow → Shake 为 5/5 exact encoded-output，零 sticky failure；before/hover/after 人工核对不再灰屏。`3766415113` 保持 0 records / 0 groups / 无 execution evidence 的合法 no-demand；`2884628849` 大尺寸 opaque X-Ray 资源可加载，但 mixed chain 未被误准入。
- 当前候选 App executable SHA-256 为 `aad3d4cfec1542361099dea7ea18f3c513eeb75691cb6a7740bdda375a349e3d`，CDHash 为 `f900eb2bff5696f5a9be3139ed31eb3991914b9e`。相关共享回归 61/61、benchmark/matrix 合同 117/117、Scene 全量 994 tests（11 skipped）与 `script/build_and_run.sh verify` 均通过；代码健康为 767 files / 44 locked legacy / 400-line limit。
- 因两项修复都影响完整语料的 evidence gate 或共享纹理用途，5 样本定向门不能替代 full45。下一步运行一次修复后 full45 复核；该运行用于检查其余 route-only/X-Ray/REFRACT 样本无漂移，不会把既有 `2067939514` 粒子偏差隐藏为 R0 PASS。

#### R0-C 修复后 full45 与矩阵收口

- 修复后里程碑报告 `.codex/scene-chain-r0c-full45-20260803-v2/report.json` 为 **44/45，overall FAIL**，报告 SHA-256 `219036a306a629d76876894b0e318b42d1c0b53dc9750f7be28618ceca5f2219`。唯一失败仍是 `2067939514` 的 particle candidate / skipped-transparent 基线偏差；其余 44 个样本均通过同代 admission、disposition 与 execution 合同，包括合法 no-demand 的 `3766415113`、X-Ray 控制组以及三个已知视觉缺口样本。后者通过只表示当前结构/运行门通过，不表示局部头发、鱼群水流或烟花已与官方视觉一致。
- full45 的 45 个样本均产出有效 admission 与 disposition；execution demand 为 44 个样本，唯一无 demand 的 `3766415113` 没有写入 execution expectation。R0 scoped refresh 只更新 admission、disposition 与 7 个稳定 execution 字段，过滤掉这些字段后的旧/新矩阵 canonical 内容完全一致；现役 full matrix SHA-256 为 `6ba6f188a467669b139a29cd135ea0603c0cafa9fadfa370384ec44739351072`，fixed13 未修改。
- 矩阵刷新后又以正式 consumer 对 route-demand 控制组 `2241938645`、X-Ray `3757555836` 与 no-demand `3766415113` 运行 `.codex/scene-chain-r0c-post-refresh-20260803-v1/report.json`，结果 **3/3 PASS**，报告 SHA-256 `492b4072d6b0625e2505740c3f89b7614f4b91aa9a45d6fe34dabbda2e295c80`。最终 benchmark/matrix 合同测试 117/117、Scene 全量 994 tests（11 skipped）、Swift code health 与 `script/build_and_run.sh verify` 均通过。
- R0 到此只完成“样本声明被怎样解析、准入、路由和实际编码”的可信证据地基；没有扩大 effect 准入，也没有把 shared command-buffer 完成写成逐 stage GPU/视觉成功。R1 从统一 typed compile/admission result 开始，已知三项视觉缺口继续保留到公共 executor 与视觉闭环阶段。

## 9. 下一动作

1. **已完成**：R0-C legacy direct/offscreen 实际编码点接入与 strict generic family 回连；pure reducer、legacy decision、framebuffer、authored execution、code health、App verify 与 Scene 全量均已重跑。
2. **已完成**：同一 8 样本动态门完成两次 10 秒与一次 20 秒复核，保留首轮 6/8 失败证据；exact/aggregate gap、CPU/route failure 与 shared frame status 已分别解释。
3. **已完成**：跨运行稳定性已核对并闭合 7 字段共享矩阵合同；不稳定 frame/canonical SHA 和未承诺稳定的 CPU/route count 均未注册。
4. **已完成但未通过**：首轮 full45 为 42/45，正确暴露一个合法空 execution 的 demand 判定错误和一个既有 X-Ray 灰屏缺口；矩阵未刷新。
5. **已完成**：公共 static demand、typed straight-albedo、embedded purpose 透传和 REFRACT 同源物理守恒已闭合；新签名 App 的 5 样本定向门、相关共享测试、Scene 全量与 verify 均通过，telemetry 保持 sticky。
6. **已完成**：修复后 full45 为 44/45；唯一红项是独立的 `2067939514` 粒子偏差。R0 scoped matrix 已按 45 admission / 45 disposition / 44 execution demand 刷新，刷新后正式 consumer 三样本门 3/3 通过；该结论不写成全矩阵 PASS。
7. **当前动作**：R1 建立 dedicated 与 authored-shader 共享的 typed compile/admission result，逐步替代 34 次无原因 Optional probe；现有 backend 像素路径暂保持为迁移 oracle。
8. R2 再建立基于 `SceneResourceView` 的 shader source graph、include digest/source map、directive evaluator 和 typed variant environment，不新增按 effect/path/hash 分派的可见算法。
9. R3 在 prepared material pass 前闭合 shader input/output color representation 与同代 texture metadata；随后用普通单 material pass 跨路径/跨样本验证，不按 Opacity、ColorKey、hash 或样本 ID 分派。
