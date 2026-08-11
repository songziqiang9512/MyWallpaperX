# Scene 解析到合成链路重构计划

> 建立日期：2026-08-03
>
> 文档状态：现役执行计划；更新至 2026-08-11。R4-A 四类 partial recovery 已删除，R4-C 的 rejected-authored-graph legacy neutralization 切片已落地，R4-B1 pair chain、R4-B2 exact X-Ray identity-output、R4-B3 bounded non-legacy Precise Blur、R4-B4 exact stock Standard Blur与R4-B5 exact stock Local Contrast logical-target stage 已闭环；R4 仍为 `partial`，R5 为 `not_started`。
>
> 事实边界：本文记录问题假设、迁移顺序、验收门和进度，不是当前能力等级或运行基线的权威入口。能力事实仍以 [`semantics/coverage-ledger.md`](semantics/coverage-ledger.md)、专项覆盖表和 [`semantics/runtime-evidence-index.md`](semantics/runtime-evidence-index.md) 为准。
>
> 工作分支：`codex/scene-capability-baseline`。计划建立快照为 `896cbb1b`；R0 已由独立阶段提交 `a1d469f3` 闭合，R1 已由独立阶段提交 `9d655ce2` 闭合，R2 已由独立阶段提交 `57cc94dc` 闭合，R3 已由独立阶段提交 `588faf40` 闭合。R4 partial checkpoint 已在其上提交；R4 仍未完成，现役状态与证据见第 0、5、8、9 节，R4-A+C 后 fresh full45 待整合者完成后补入。

## 0. 快速接手

- **能力与运行事实**：继续从 [`semantics/README.md`](semantics/README.md) 进入专项表，并以 [`semantics/coverage-ledger.md`](semantics/coverage-ledger.md) 和 [`semantics/runtime-evidence-index.md`](semantics/runtime-evidence-index.md) 的 R4 partial checkpoint 为准；本文只记录重构路线、剩余迁移和复验门。
- **Git 断点**：分支 `codex/scene-capability-baseline`；恢复时先核对`git status`、最近提交和本页最末checkpoint。现役提交链已越过统一材质pass方向回归、Tint/Film Grain、authored Program九段链与Light Shafts当前正例；同批后续又闭合bounded orthographic Scene Camera Shake。不得从旧`2b2b03df`或历史计划重开已完成波次。
- **架构判断**：capability直接来自raw authored graph admission，rejected graph不回落legacy planner，四类partial recovery已删除。R4-B1又把完整accepted chain改为逐stage Program-first；Program失败段只有满足单node、无target、exact identity与typed readiness时才可使用pair adapter，Program/adapter保持作者顺序。R4-B2已让exact stock、单node、无logical target的X-Ray以typed identity/render preflight进入同一unified pair leaf；R4-B3至B5又依次让bounded non-legacy-compose Precise Blur、exact stock Standard Blur与exact stock Local Contrast的多node/logical-target stage在相同Program-first规则下由统一executor编码，沿用既有严格像素backend，不改变blur/contrast math。ImageBlend source preparation、typed named dependency、无图legacy planner与其他未迁移owner仍独立可达，因此产品整体尚未形成唯一能力池。
- **阶段边界**：当前停在 R4，不进入 R5。B1已迁移普通pair-only完整链，B2已闭合X-Ray identity-output子集，B3只闭合bounded non-legacy Precise Blur logical-target stage，B4只闭合exact stock Standard Blur的同类子集，B5只闭合当前两条exact stock Local Contrast ordinary-image正例。legacy-compose Precise Blur、captured-main Standard Blur、含未迁移兄弟stage的atomic chain、未知Standard Blur combine、非stock/captured-main Local Contrast、Cursor Ripple history、cross-layer/dependency与Light Shafts仍需后续R4。旧whole-chain root、无图legacy planner GPU authority、ImageBlend/typed dependency、Light Shafts main-pass bypass及script/profile selector仍未撤权。后续从本页最末checkpoint与第9节逐项收口，不能把定向正门写成R4完成、fixed13/full45 PASS或视觉parity。

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

本节是 2026-08-03 的审计快照，后续数字变化时必须追加进度记录，不覆盖成“从未存在”。来源为当时的隔离 45 样本副本、`.codex/scene-waterwaves-relocated-full45-20260803-v2/report.json`、各样本 schema 1 runtime evidence、应用日志和当时源码静态统计。其 recovery/fallback 权限、计数与运行结论均是历史证据，已被 2026-08-10 R4-A+C 静态合同 supersede，不得作为现役 authority 或 fresh full45 基线。

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

- `3766387484` layer 17 的作者顺序为 `Foliage Sway -> Water Flow -> Shimmer -> Workshop Iris -> Depth Parallax -> Twirl x4`。在 2026-08-03 快照中 strict planner 于 `Shimmer` 首断，完整链不执行，随后 legacy `foliagesway-uv` 接管；这是历史失败现场，不是现役 owner 合同。用户实际看到过“整块头发”以及实验放宽后的“整个头”运动。
- `3768724269` 与上者具有相同的六类局部动态 effect signature，可作为跨作品同合同正门，不能只修 `3766387484`。
- `3769688830` 同时覆盖多段 Water Waves / Water Flow / Ripple / Tint / Puppet / particle；尾巴颜色当前正常，本重构不得重新调整颜色。其鱼群水流仍需在统一链路上做最终视觉门。
- `3768903841` 当前结构上 14/14 stage 可进入 strict，但烟花仍有过曝、锁相和历史视觉回归记录，证明“stage 数完整”也不能替代时序与像素方向性验收。

## 3. 已确认的架构断点

本节保留计划建立时确认的断点与推理链；其中 partial recovery 和 rejected-graph legacy fallback 已在 2026-08-10 撤销，现役剩余项以第 0、8、9 节为准。

### 3.1 双执行平面

计划建立时有两套会竞争同一 authored layer 的执行语义：

1. authored graph 通过完整 profile 后进入 ordered strict chain；
2. chain 为空时，`SceneEffectRuntimePlanner` 再扫描 `layer.effects` 的路径和首个 pass，把多种 effect 压入固定 `SceneLayerEffectInputs` flags/参数数组，或只按 pass 数进入 offscreen copy。

第二条路径会丢失重复实例、完整 effect 顺序、material identity、slot provenance、combo、render state、RT 与 command 语义。它只能作为历史过渡实现，不能继续充当 authored graph 拒绝后的默认兼容层。

### 3.2 All-or-nothing 放大

计划建立时，`SceneAuthoredEffectChainPlanner` 对每个 effect 依次选择专用 backend；首个不支持 stage 通常使整个 layer chain 返回 `nil`。当时的 Iris suffix、Cursor Ripple / Shine isolation、X-Ray prefix 会显式省略兄弟 stage，不能作为通用 graph executor；这些 recovery 产品路径现已删除，任何 active stage 拒绝都会拒绝整图并中和 `SceneEffectRuntimePlanner` 的 legacy effect fallback。

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
6. **Legacy migration convergence**：已存在 graph 的 layer 不得因 strict 准入失败而静默转成整层近似；旧 planner/backend/fallback 必须按公共 capability family 逐批接入同一 executor，并在同批撤销等价执行权限。R4 结束前迁完产品执行权限，R5 不再承接行为迁移。

### 4.3 架构方向复核门

目标不是猜测或复刻官方客户端的内部算法，而是在 clean-room 边界内达到相同的架构性质：样本只提供版本化数据、资源、shader、graph 和属性，播放器通过一条公共能力链解释并执行；新增样本或历史 revision 应优先由兼容归一与既有能力自动覆盖，不能要求为 workshop、layer、资源内容单独写播放逻辑。

当前状态必须诚实表述为“R1-R3已把compile、source/variant与atomic material Program串成公共L2地基，R4正在撤销旧产品执行权”，不能表述为“已经与官方底层完全一致”。现役库存与完成目标以`script/scene_source_layout.json`的schema3 ratchet/completion contract为准：compiler/backend、main-pass allowlist、revision attestation与真正的legacy product owner必须分类统计，不能从case、SHA或Workshop字面总数反推owner数。四类 partial recovery 已归零，所有 rejected authored graph 现会中和 `SceneEffectRuntimePlanner` 的 legacy effect plan/inputs；但严格独立准入的 ImageBlend source preparation 与 typed named dependency 仍保持各自 owner/telemetry，完整 accepted graph 的旧 whole-chain renderer、无 authored graph 的 legacy planner、Light Shafts main-pass fallback 与 script/profile 行为 selector 也仍可达，因此产品GPU执行层尚未收敛。R4-R5的目的正是把这些并行执行面收敛为以下唯一主链：

`compatibility normalization -> typed effect/material IR -> VFS/source schema -> material/provider readiness -> variant/preprocess -> active frontend/reflection -> atomic material program -> typed logical resource -> unified graph executor -> compositor/evidence`

R4/R5 的 completion 只证明产品 owner、scheduler、resource 与 compositor 已收敛到这条主链，并且旧链完成撤权/清理；它不等于作者算法、时序或官方像素等价。算法与视觉 parity 在后续独立阶段内，继续以官方客户端/合法语料和独立参考项目作 clean-room 交叉核验。

其中 material readiness、texture-derived combo、active variant 与 reflection 形成有界回路，不得把“先 variant、后 binder”误写成互不相干的线性步骤：source/include annotation 先给出候选 schema，resolver 只计算候选 readiness，variant 据此选择 active source，frontend/reflection 再与最终 texture/uniform/state 一起原子编译成 material program。任何一步未知都保持 fail closed，不能回退到 effect 路径或样本身份选择另一套算法。

每个大阶段提交前必须回答并在进度记录中留下证据：

1. 本阶段消除的是哪一个公共瓶颈，是否至少由一个项目自有 fixture 和两个共享同一合同的不同样本或 revision 证明；语料确实只有一个实例时，必须记录语料边界，不能把单例验证写成普适兼容。
2. workshop/sample ID、layer ID、资源 hash/fingerprint 只可用于测试定位、内容身份、缓存或 fail-closed revision 准入，不得选择可见算法；effect 路径只可用于兼容识别，不得成为绕开 typed program 与统一 executor 的第二套执行器。
3. 新增能力是否进入上述唯一主链，是否同时减少或明确排期替代等价的 dedicated/legacy 权限；若 dedicated、legacy 或 effect 专用分支数量净增长且没有对应退役证据，暂停下一阶段并重新审查方向。
4. 重新统计 generic compiled/executed、dedicated、legacy、route-only、unsupported 与稳定失败原因的样本/阶段分布；结构门通过只证明链路守恒，真实样本还必须按风险补多相位视觉证据。
5. 官方资料、公开文档或必要的 Ghidra 只用于核对控制流、数据形状、版本选择、资源优先级和失败边界；不得把观察到的官方算法表达、shader、payload 或资产带入实现。
6. 阶段是否扩大了生产 GPU 准入面；若颜色表示、typed binding 或 graph lifecycle 仍未闭合，新 parser/preprocessor 能力只能产出可审计的 prepared program 与稳定拒绝，不得因为“现在能编译”就提前进入 renderer。
7. 新主链取代旧权限时必须在迁移族同一提交登记并撤销对应旧产品owner、fallback dispatch、`fallbackGraph`、`.legacyContract`、旧 root projection/source adapter 与重复 telemetry/projection 的产品执行权；能安全删除的实现和只服务旧路径的测试同批删除，仍承担像素 oracle 的代码只能进入明确不可达的验证隔离。提交前分别统计legacy product owner、legacy recovery、behavior selector、runtime dispatch四类完成门，以及typed leaf/compiler、revision attestation、main-pass allowlist三类库存。后者用于证明净收敛和防止无说明增长，不以字面归零作为R4完成条件；前四类任一仍可达、同一stage有双owner，或sample/layer/path/hash仍选择可见算法时，R4不得完成，R5不得开始。

R2-R4 允许的有界双轨只用于保持 R1 像素 oracle、逐族迁移和证明接纳不漂移；同一产品 frame/stage 在任何时刻都只能有一个执行 owner，不得借迁移期新增另一套 effect/sample/path/hash 专用执行分支。每个迁移波次必须以“公共 capability 接管、旧 owner 撤权、双写与 fallback 为零、跨样本或跨 revision 正反例通过”的独立提交闭合。最后一个旧产品 owner 撤权且静态门确认无样本身份算法分支之后，才允许结束 R4。

R5 是纯删除、合并和最终证据收口门，不再修改 stage 的产品执行 owner，也不再迁移像素行为：同一生命周期、同一调用者且合并后仍满足 400 行合同的薄 planner/plan/renderer 应收回完整职责文件；独立 IR、IO、安全边界或会把文件推过 400 行的类型不得为减少文件数机械合并，更不得新建 `Common`/`Helpers` 式兜底文件。R5以删除量、product/observation零门、Scene文件/LOC/小文件数及typed leaf/compiler保留清单分类证明净收敛；合法typed leaf/compiler、main-pass allowlist或declarative revision attestation可以非零，但必须记录唯一产品入口和保留职责。若R5才发现仍需迁移旧owner，立即退回R4，不得以收尾名义继续双轨。

只有 R4 建成唯一 graph executor、把全部旧产品执行权限迁移并撤权，R5 删除残留脚手架和重复结构，并由跨版本跨样本证据证明同一 typed program 路径实际执行后，才可把执行架构描述为“基本收敛”。在此之前，每次汇报都应区分方向一致、结构迁移完成与视觉兼容完成，不能用其中一项替代另外两项。

## 5. 实施批次

| 批次 | 状态 | 产物 | 完成标准 |
|---|---|---|---|
| R0 端到端证据合同 | **已完成**（admission、static disposition、CPU invocation、route operation 与 shared-frame status 已分轴；修复后 full45 为 44/45，唯一红项是独立 particle baseline 偏差） | typed chain admission、descriptor stage ledger、runtime report 聚合、守恒测试 | 1296 个 descriptor effect 在当前 full45 快照中逐个有唯一 activity/strict admission；legacy/route-only/execution 分轴且不重复计数；矩阵 PASS 不能掩盖 unsupported/route-only |
| R1 统一 compile/admission model | **已完成**（统一 typed input/result/program、planner-owned family classification、完整身份守恒与可持久化的有界失败汇总已落地；没有扩大准入或修改像素 backend） | `SceneEffectStageProgram`、共享 compile input/result，专用与 authored shader backend 的有序 probe 与稳定失败原因 | 现有 strict execution plan 与 GPU fixture 保持；chain planner 不再把 34 次无原因 Optional 作为最终诊断，完整顺序、首个命中与 recovery 合同有自动门 |
| R2 compatibility/source/variant/frontend preparation | **已完成**（独立提交 `57cc94dc`） | typed compatibility context（只保存已声明版本、字段存在性与 provenance，不猜默认）、VFS source graph、directive/include evaluator、typed environment/combo variant、active source/schema/source map/cache key、frontend preparation handoff、shader input/output color representation 类型与 fail-closed 准入门 | 项目自有 fixture 覆盖嵌套条件、`#undef`、缺 include、循环 include、VFS 同名候选冲突、未知 directive/环境 define、exact numeric、active-only metadata、macro 所有权、词法隔离与 fixed-point 歧义/预算；45 样本可复现 census 证明 raw/canonical 与 planner compile admission 相对 R1 无扩大/丢失；在 R3 颜色/binder 合同闭合前不扩大现役 renderer 准入 |
| R3 原子 material binder / color contract | **已完成，由本页所在独立阶段提交闭合** | 固定 8 槽 `SceneResolvedMaterialTemplate`、同代 `SceneResolvedMaterialProgram`、exact/semantic identity、typed graph/asset/user/system provider publication、sampler/physical/mapped/UV/generation、constant/dynamic uniform、typed state 与 conservative color transfer；生产链只做一次性 CPU 审计，`gpuEncoded=0` | nullable slot 不压缩；只有显式 absent 才允许较低优先级作者资源，missing/pending/unavailable/incomplete/未知 purpose/state/color 全部失败关闭；45 样本 census、跨 provider fixture、完整 Scene 测试、签名构建与四样本运行证明结构和性能守恒，R4 前不扩大 GPU 准入 |
| R4 unified graph executor / 旧 owner 迁移 | **`partial`；R4-A 已完成，R4-C 只完成 rejected-graph neutralization 切片，旧 owner 未迁完** | condition/function、material、shader `[PASS]`、copy/swap/compose 的唯一执行入口，logical target/history lifecycle 与 scene final-output 边界；既有 dedicated/legacy 产品执行 owner 按公共 capability family 分波次接入并撤权 | authored 顺序、effect input/output、command ordinal、RT extent/format/clear/unique、persistent swap/history、read/write hazard、compose pair、resize/reparse/reset generation 与 final output 守恒；每族同时有正例、版本变体和坏 slot/state 反例；同一 stage 无双 owner、无旧 fallback 重解释、无 sample/layer/path/hash 算法分支；最后一个旧产品 owner 撤权后才完成 |
| R5 删除残留 / 合并薄层 / 最终证据收口 | **`not_started`；不得承接产品行为迁移** | 删除已经不可达的 planner/backend、`fallbackGraph`、`.legacyContract`、旧 root projection/source adapter、重复 telemetry/projection 与旧链测试；合并同生命周期薄文件；同步权威语义文档和最终矩阵 | R5 开始时产品执行已是单一权威；按删除量、product/observation零门、Scene文件与LOC/`<3 KiB`/`<1 KiB`、typed leaf/compiler保留清单分类证明净收敛，不要求合法typed leaf或attestation字面归零；完整门与代表性多相位视觉证据通过；若发现仍需迁移owner则退回R4 |
| R6 全画面动态与水流视觉闭环 | 待开始 | Twirl/Shimmer/Iris/Foliage/Water/Depth/Light等在公共executor上按作者顺序、区域和相对幅度共同执行 | `3766387484`与`3768724269`同时恢复人物多区域、双眼、叶片/粒子、光线和全景流动，而不是把“头发整块移动”单列成头发bug；`3769688830`鱼群/水流跨相位可见且尾巴颜色不回归；外部mask ROI、逐段输入和全系统多相位方向稳定 |

R0 是防止继续误判的基础，但不能被表述为视觉修复；R1-R5 也不能用“frontend 能编译”替代实际 GPU pass 和合成证据。R0-R6 当前收敛的是 2D authored effect 主链，不等于把 Particle、Text、SceneScript、Puppet、Video 与 Lighting/HDR 强塞进同一 material executor；这些系统可保留各自 runtime，但必须共用 identity、compatibility、resource、frame/provider、typed graph 与 lifecycle 地基。

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

本节按日期保留每个波次当时的代码、运行与权限快照；较早条目中的“当前”“现役”“fallback”“prefix/isolated”只描述该日期的源码。凡与 2026-08-10 R4-A+C 合同冲突者均视为 superseded 历史证据，不得反推现役 owner 或运行基线。

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

### 2026-08-03：R1 统一 compile/admission model 闭环

- 单 stage 现在统一进入 `SceneEffectStageCompileInput -> SceneEffectStageCompileResult`。成功结果由 `SceneEffectStageProgram` 同时保存作者 ordinal、完整 `EffectKey`、definition path、input role、原 stage graph、compiler selection 与既有 execution plan；完整 graph 以 canonical Codable 表示核对，compiler backend 与 runtime backend 精确配对，两个 Audio Bars profile 是唯一的一对多 runtime backend 例外。
- 33 个 dedicated planner 的旧 `plan -> Optional` 仅保留为各 planner 的 exact fail-closed implementation；同一 planner 现在通过共享 typed `compile` 入口先执行 `plan` 一次，只有 `nil` 才惰性调用自身 family matcher。明确不属于该族返回 `notApplicable`；路径或 definition metadata 表明同族但 exact profile 未通过时返回稳定的 `compatibility/dedicated-profile-rejected`。Color Grading 原先会把任意非空 effect 当候选的过宽判断已改为 authored definition 的 replacement key / canonical metadata，Tint relocated 形态也按相同公共 metadata 合同识别。该 coarse code 只表示同族 strict profile 拒绝，不伪造 planner 内部每个 guard 的细原因。
- 第 34 个 authored-shader fallback 以 typed compile 为唯一权威，旧 `plan` 只投影 `acceptedPlan`，并按 graph、topology、material、shader contract/frontend、texture/uniform binding 与 invariant 输出稳定 phase/code/details。accepted program 在返回值中保留前置 ordered probe provenance；生产 static report 只聚合最终未被 recovery 消化的 unsupported stage，不把成功链 provenance、details 或逐帧数据塞进矩阵合同。外层 `unsupported-stage`、Iris -> Cursor Ripple -> Shine -> X-Ray recovery 顺序、失败前缀丢弃和后续 stage 不再求值的现役 admission 合同不变。
- benchmark 新增独立 schema 1 `runtime.authored_effect_stage_compile`，从 `scene-preview.log` 有界解析 stage aggregate code、`not-applicable/rejected` 与排序后的 `backend/phase/code` 计数，校验四行唯一性、键和值形状、34 compiler 上界与两组计数守恒，再生成 canonical SHA-256。它是 admission schema 的 sibling，不改变现役矩阵 expectation 或顶层 report schema；旧 App 无四行时保持 backward-compatible，无完整四行或守恒失败则当前运行失败。
- 独立机械复核对比 R0 提交确认 33 个 dedicated planner 的顺序、实参、runtime backend、material/logical-RT 计数、input role 和 recovery 函数体没有漂移。自动门进一步锁定完整 34 项 exact order、两个 Audio Bars 同时 accepted 时前者命中且后者零调用、generic fallback provenance、三 stage 首断短路，以及错误 backend/完整 graph 投影的 invariant 拒绝。
- 定向 `test_scene_authored_effect_chain_planner.py`、`test_scene_authored_effect_execution.py` 与 `test_scene_authored_shader_execution_planner.py` 共 **21 tests PASS**，benchmark parser/runner **90 tests PASS**；Scene 全量 `python3 script/run_scene_tests.py --scope scene -j 4` 为 **169 modules / 110.2 s / ALL OK**。Swift code health 为 **773 files / 44 locked legacy / 400-line limit**，`script/build_and_run.sh verify` 与 Developer ID 签名构建通过；本批新增 typed compiler 不再产生 actor warning，构建仍保留与本批无关的既有 Shine warning。
- 最终签名 App executable SHA-256 为 `4bb1685668cee05480ff1565952e26da394dc901141ac99dd2d7086faf00c204`，CDHash `0564cf430e42693f8aa98a7e84a76bd3f8675067`、Team `H9QWU9XN8R`。隔离报告 `.codex/scene-chain-r1-typed-20260803-v2/report.json` 对 strict 控制组 `1937925563`、`3738202317`、`3767232084` 及已知缺口样本 `3766387484`、`3769688830`、`3768903841` 为 **6/6 PASS**，loaded ratio 均为 1，报告 SHA-256 `d58efbdbb26c7a8f174e5738d2bd8dfa76a0edbd6c323603aa35630ddce59c4b`，并继续匹配现役 full-matrix admission/disposition/execution 合同 SHA-256 `6ba6f188a467669b139a29cd135ea0603c0cafa9fadfa370384ec44739351072`。
- 两个真实首断反例现在由持久 report 直接给出稳定最终诊断：`3766387484` 为 1 个 `no-backend-accepted`、probe `not-applicable=33,rejected=1`，唯一拒绝是 `authored-shader/material/material-texture-slot-unsupported=1`，compile canonical SHA-256 `5ad1c6825bd844468491728e8dc62fcb7e7aef457384554f13c438cc20976441`；`3769688830` 为 6 个同类首断、probe `not-applicable=198,rejected=6`，同一 generic code 为 6，compile canonical SHA-256 `f7eaca8e97e5ad59795a34f7ae539cfabbb04ab8a3943eec477ed8d56ac1c18c`。其余四个样本 stage compile failure 均为 0。该结果只把断点变得可审计，没有恢复局部头发、人物整体动态、鱼群水流或烟花方向性，也没有触碰已恢复正常的尾巴颜色。预览比较仍是 same-sample advisory；没有同相位 Windows golden，不能宣称 Wallpaper Engine 像素等价。
- 本批没有改变样本集合、矩阵合同、effect 准入面、renderer、Metal shader、纹理绑定或 compositor，也没有修改 fixed13/full45 expectation。完整顺序/投影门、全 Scene GPU fixtures 与六样本现役 consumer 已覆盖 R1 的共享风险，因此没有惯性重跑 fixed13/full45；R0 的 full45 仍是 44/45 overall FAIL。现有资料足以完成 typed 边界，本阶段没有启动 Ghidra。
- R1 提交前架构方向复核结论：本阶段消除了 dedicated 与 generic 之间 compile/admission 结果不可比较、失败不可持久审计的公共瓶颈，并以项目自有 harness 和六个不同真实样本证明同一 typed 边界；生产代码没有新增 workshop/sample ID、layer ID 或资源 hash 的算法分派。但 33 个 dedicated planner、legacy fallback 和多套 GPU 执行入口均尚未退役，因此只能表述为“方向一致且完成一段结构迁移”，不能表述为“已与官方底层一致”或“视觉兼容完成”。R2 进入前按第 4.3 节硬门锁定唯一主链，若后续专用/legacy 权限净增长而没有等价退役证据，暂停实现并重新审查路线。

### 2026-08-03：R2 compatibility/source/variant preparation 闭环

- project 与 scene version 现在分别保留 missing/value/invalid-type/out-of-range 和 provenance；没有 `effectiveVersion`，也不按版本猜默认、注入 macro 或 compatibility patch。`SceneResourceView` 之上另建独立 source graph，保存 package/loose/stock 候选、stage root、include edge、内容 identity、冲突和预算；R1 的 vertex-first/same-root raw stage projection保持逐字同义，R2 graph不能改写它。package -> loose -> stock 是当前项目 VFS policy，不是已证明的官方全版本优先级。
- bounded preprocessor 支持 object-like `#define/#undef`、`#if/#ifdef/#ifndef/#else/#endif`、relational 高于 equality 的整数/布尔表达式与 include 展开，输出 dependency digest、逐行 source map、active annotation/declaration 和 prepared identity。macro expansion 区分 code/string/character/line-comment/block-comment，selected macro 保存 defined/undefined 三态，host-owned macro 的 define/undef 均不可由 authored source 改写；只有 active 行贡献诊断与 metadata。function-like macro、`#elif`、未知/畸形 directive、active directive-line annotation、缺失/冲突/循环 include、输入/输出/深度/token 预算超限均稳定失败关闭；backend/version/platform/texture-format define 为 host-owned requirement，当前没有 verified Metal provider。
- exact case-sensitive `[COMBO]`、material explicit value、annotation default/active options/`require/requireany` 与 sampler readiness 进入带 provenance 的 typed schema；annotation 数值以 Decimal-first exact Int64 carrier 保存，Int64 两端可接受、越界和 unsafe legacy Double 拒绝。fixed-point 以词法无条件 root/include schema 为 immutable base，对最多 8 个条件候选穷举所有非空子集；不同 stable prepared signature 报 `active-schema-ambiguous`，候选数或 `probe × 16 rounds × graph bytes` 估算超过 256 MiB 报 `active-schema-audit-budget`。positive/cross-include/readiness bootstrap、隐藏有效子集、互斥 fixed point、material/local define/undef anchor 与预算边界均有项目自有 fixture。
- prepared program 显式携带 input/output `opaque/straight-alpha/premultiplied-alpha` 与 resolved/unresolved 状态。普通 authored pass当前为 unresolved：旧 raw frontend失败但 preparation成功时仍以 `shader-color-contract-unproven` 拒绝；旧 raw frontend成功时，preparation失败只作诊断而不缩小R1 accepted subset。prepared cache identity尚未进入现役 execution plan/renderer/pipeline cache，这条双轨只服务迁移守恒，R3必须原子闭合 texture/provider/reflection/state/color后才能接管。
- 45 样本 planner/preparation census 覆盖 **434 contracts / 728 material passes**：R1 与 current planner compile admission 均为 **accepted 1 / rejected 727**，唯一 accepted identity 不变，new/lost accepted 均为 0；current preparation 为 **93 accepted / 635 rejected**。同一 current harness 连续两次原始结果逐字节一致，raw/canonical diff 均为 0；正式报告 `.codex/scene-chain-r2-preparation-census-20260803-v1/report.json` SHA-256 `2e535ccceb0fa381ca909217e7f1e4a16b434b3ea2b279a57c43d64b0ebf1b5e`。该口径使用真实 material/shader 加合成最小单-pass graph，不是完整 authored graph、App、GPU 或视觉证据。
- 最终 `python3 script/run_scene_tests.py --scope scene -j 4` 为 **173 modules / 119.4 s / ALL OK**，Swift code health 为 **784 files / 44 locked legacy / 400-line limit**，`script/build_and_run.sh verify` 成功。签名 App executable SHA-256 `c2b631a07b7dbe78b3d2aeb4d98d2cbfab462cd2fa33e05259009ca258072836`、CDHash `188f0b4483b0dda48ed3df6c81f8b4253d93bac1`、Team `H9QWU9XN8R`，`codesign --verify --deep --strict` 通过。
- 隔离报告 `.codex/scene-chain-r2-preparation-20260803-v1/report.json` SHA-256 `f478dac02e332d4f7e0fafd01482b539986fd69078f3cb6d53a82cae548f5d63`，对三个 strict 控制组及 `3766387484`、`3769688830`、`3768903841` 为 **6/6 PASS**、loaded ratio 均为 1、ready/after 均非黑且有运动、运行 failed frame 均为 0；preview 比较仅为 advisory、`gating=false`，admission/disposition/execution validation、exact execution demand gap、failed invocation/route/command-buffer frame 均为 0。`3766387484` / `3769688830` 仍分别保留 1 / 6 个 `no-backend-accepted` stage failure；报告只证明现役结构运行无回归，不证明局部头发、人物整体动态、鱼群水流、烟花方向性或 Windows 像素/动态一致，尾巴颜色未触碰。
- R1/HEAD 规模为 **499 Swift / 78,143 LOC / 185 `<3 KiB` / 59 `<1 KiB`**；R2 为 **510 / 81,746 / 186 / 59**，净增 11 文件 / 3,603 行 / +1 / 0。11 个新 Swift 文件贡献 3,406 行，没有 `<1 KiB`，只有 84 行 / 2,970 字节的 `SceneCompatibilityContext.swift` 小于 3 KiB，且它是跨 Project/Document/Runtime 使用的独立 IR；其余文件因独立 IO/IR/状态机边界或合并后会超过 400 行而不机械合并。33 个 dedicated probe、34 个 compiler identity、33 个 runtime backend 与 4 个旧 planner 顶层 authority 调用点均无净增长；旧 authority 尚未被 R2 取代，故本阶段不提前删除。
- R2 提交前已把原 `SceneShaderVariant.swift` 中 prepared/variant/color/digest DTO 并回 `SceneShaderVariantEnvironment.swift`，把 preprocessor diagnostic/expression syntax 并回 `SceneShaderDirective.swift`，删除一个职责混合文件；合并后两文件为 385 / 392 行，仍满足 400 行合同。R5 在新 VFS/program/executor 分别取得唯一权威后，按迁移族在同一提交删除 `fallbackGraph`、`.legacyContract` provenance、旧 root projection/source adapter、对应 dedicated/legacy planner/backend、重复 telemetry/projection 和只服务旧路径的测试，并刷新 dedicated probe、runtime backend、legacy authority、Scene 文件/LOC、两档小文件六轴，不能只把旧链改名保留。
- 本阶段现役文档、样本project/shader、既有官方公开资料与clean-room分析已足以界定parser -> source resolver -> variant preparation -> material/graph handoff边界，没有启动Ghidra。R2方向与官方公开的资源、preprocessor、material/variant、graph分层一致，但尚未建立官方等价实现、单一executor或跨版本向下兼容承诺。

### 2026-08-03：R3 原子 material binder / color contract 闭环

- `SceneResolvedMaterialTemplate` 现在只从 production raw authored plan、material resolver 与 ShaderContract 编译静态作者事实：固定保存 `0...7` 八个槽位及 hole，候选按低到高保留 material/instance/graph/user/system provenance，graph identity 精确到 effect/node/target。shader annotation 的 `material` 只作为 uniform/texture lookup key，不推导 texture purpose；普通 sampler 只有 graph color boundary 可得 `.premultipliedColor`，公开 `opacitymask/rgbmask/flowmask` 才提供对应 data purpose，numeric TEX format、`normalmap` 字样或资源路径都不能自行证明用途。
- `SceneFrameTextureIdentity.graph(TextureIdentity)`、`SceneTextureProviderPublication(requestIdentity,candidate,contentGeneration)` 与 immutable registry snapshot 把 request identity、candidate identity/generation/purpose/content、physical/mapped extent、UV、sampler raw flags 和 frame index 一起冻结。provider 的显式 `absent`、`pending`、`unavailable`、ready/incomplete 与字典中根本 missing 彼此不再混同；只有选中 override 的显式 `absent` 才允许继续取较低优先级作者候选，missing/pending/unavailable/incomplete/identity mismatch 均失败关闭。现役 bounded Blend loader及旧 `SceneImageBlendRenderPlan`/registry resolve也改为同一 absent-only 合同：bare authored resource只可作为 `.layerSource`，exact property override必须有完整publication，不再把 provider 故障伪装成“用户未选择”。
- `SceneResolvedMaterialProgramFinalizer` 在一个 resource/dynamic/frame snapshot 内完成 readiness -> active variant -> prepared source -> frontend/reflection -> texture slot -> uniform bytes -> typed render state -> color transfer 的唯一装配。Program 同时生成 semantic identity 与含 prepared/resource generation/uniform bytes 的 exact identity；caller 不能自行注入 cache key、颜色结论或半成品 buffer。颜色分析只接受 active fragment 中单一无条件 direct texture passthrough 或 alpha=1 opaque construction，其他控制流/表达式及 unresolved graph color 全部报 `colorContractUnproven`。
- dynamic uniform把“数值生产者”和“控制附件”分开：Timeline仍是数值来源，SceneScript stop/play 只在已观测的 guarded media restart 形态下作为 control attachment；官方公开 Album Cover示例当前只展示 `play()`，所以 stop/play 只是合法 Workshop corpus 的 bounded准入事实，不能写成通用官方状态机。unknown script、多个竞争值源、type/source不匹配继续失败关闭。
- production host 现在从 raw authored plan建立 launch-scoped runtime catalog，并从同一个只读 VFS/device 建立 purpose-proven asset publication；它不从 strict execution catalog反推普通 material，也不在 frame中读取文件。per-surface bridge只在首个活动帧做一次 CPU finalization audit，`endFrame` 清空快照；copy/swap command state、缺 target/provider及未证目的保持明确 disposition。该桥的所有报告固定 `gpuEncoded=0`，旧 renderer/pipeline/compositor像素权威未改变，R4 将在同一个 graph-node 边界接管实际编码。
- 45 样本正式 census `.codex/scene-chain-r3-material-census-20260803-v1/report.json` SHA-256 `394b7f8fd5f59a7d88eb307b26d7bcc739e0bb5eb58a84067bc180c36da09999`，独立运行两次字节一致。口径为 **1296 descriptor effects / 489 authored plans / 1400 material nodes**；Template **1392 accepted / 8 shaderContractInvalid**，R2 readiness bootstrap **340 / 1060**。362 个 active sampler 中 203 个只由 graph-color boundary证明、21 个由公开 `opacitymask` 证明、138 个 purpose仍未证；10 个 uniform同时出现 Timeline value 与 SceneScript control。由于 census没有伪造一份 runtime texture/dynamic snapshot，Program **0 attempted / 1400 notAttempted(runtime-snapshot-unavailable)**；其输入的旧 full45 report只用于取得逐样本 runtimeInput身份，不是当前运行基线，也不是 GPU/视觉证据。
- production 四样本启动目录证明同一 raw-plan路径为 `1553008362 / 1937925563 / 3767232084 / 3769688830` 建立 nodes/templates `4/4、103/103、11/11、58/58`，purpose-proven asset demands `8/8、7/7、6/6、35/35` ready。最初逐帧审计的 v1 报告虽然结构 4/4 PASS，却把 CPU p95推到最高 808 ms；这被判为阶段失败而非接受。改为 per-surface first-active-frame、闭合最终 Image Blend legacy bypass并把审计持久化后，`.codex/scene-chain-r3-material-atomic-20260804-v4/report.json` 为 **4/4 PASS**、loaded ratio全为 1、failed frame全为 0，报告 SHA-256 `23c6b2cc5c7c1d83db75dcfa848bb7d7234172c05ffe14578c7d658bad91c9fb`；四样本 driver FPS约 `59.992 / 59.950 / 59.980 / 29.985`，CPU p95 `1.913 / 5.407 / 2.942 / 6.955 ms`，GPU p95 `1.873 / 10.178 / 12.147 / 13.018 ms`，均保持目标帧率且没有 failed frame。
- v4 每个样本各有且仅有一条 `mode=first-active-frame` 审计，`nodes/finalizationAttempted/accepted/failures` 分别为 `4/0/0/4、103/103/0/103、11/11/0/11、58/30/0/58`，全部 `gpuEncoded=0`；failure category与disposition各自守恒到nodes，没有inactive或逐帧重复。真实样本accepted为0是本阶段必须保留的边界：它证明Program链在未证frontend/preparation/resource/purpose/target时明确失败关闭，不证明真实样本已经成功形成可执行Program。
- resource lifecycle、Program/census、frontend color与Blend/bridge聚焦门分别通过；修复全部受新增字段影响的 standalone Swift harness 后，最终 Scene全量为 **179 modules / 119.2 s / ALL OK**。Swift code health为 **795 files / 44 locked legacy / 400-line limit**，`script/build_and_run.sh verify`成功。签名 App executable SHA-256 `d7baf624214b62af4b757587988012367c0fedd18d45ea1dafb1b497a6db8a83`、CDHash `4f40a984f8fe52fe64c3b5f6940dc6ef22994ce7`、Team `H9QWU9XN8R`，深度严格验签通过。R3没有扩大GPU准入，完整Scene测试和四样本定向运行足以覆盖本阶段共享结构/性能风险，因此未惯性运行fixed13/full45；R0 full45仍是44/45 overall FAIL。
- Scene源码规模从R2的 **510 Swift / 81,746 LOC / 186 `<3 KiB` / 59 `<1 KiB`** 变为 **521 / 86,163 / 186 / 57**，净增11文件 / 4,417行 / 0 / -2。新增文件分别承载Template/Program/identity/finalizer/schema/derivation/uniform、launch VFS asset IO与per-surface runtime lifecycle，合并后会跨职责或超过400行；没有新增dedicated probe、compiler identity、runtime backend或legacy authority。33/34/33/4四轴保持不变，旧GPU权限尚未被R3取代，故本阶段不提前删除，R5的同提交退役门不变。
- 本阶段所需的资源优先级边界、8槽、variant/material分层、Texture property未选时回退原图、Timeline与SceneScript职责、sampler/purpose及graph lifecycle均已由现役文档、官方公开资料和既有clean-room分析支撑，因此没有启动Ghidra。结论只能写为“R3原子Program地基与官方公开分层方向一致”；R4唯一executor、graph FBO/effectOutput在command边界的typed publication、跨语言helper、更多purpose/state/color以及system/video/variant生命周期仍未完成。`3766387484`局部头发、`3769688830`人物/鱼群水流和`3768903841`烟花也未由R3修复，尾巴颜色未触碰，不能宣称官方或视觉等价。

### 2026-08-04：R4 统一 executor 进行中（架构复核断点）

- R4-A 已形成但尚未提交的可保留地基包括：planner compile-product 对象身份、catalog owner/capability token 的 O(1) claim、正负结果均缓存的有界 texture-readiness variant cache、以及 Finalizer 复用 cached frontend/schema 的路径。这些只解决静态能力声明和逐帧重编译，不代表 graph executor 已正确。
- 现役文档、stock Fluid/Refraction 结构与官网仍不足以决定 raw condition/function/compose 的运行顺序，因此仅对 source-index 已登记且哈希匹配的 2.8.42 64 位客户端做了 bounded clean-room 单点复核；没有复制地址、伪代码、shader、payload 或算法。临时 Ghidra project、脚本和日志在中性结论写回正式文档后均已删除。
- condition 的最小公共 provider 被收窄为 effect-scope immutable snapshot：每个 material 的显式 combos 先由同 ordinal instance override 覆盖，再跨 material 只接受唯一 provider或同值 provider；冲突、reserved host key、非零 shader default/readiness 来源不明均失败关闭。FBO/pass/bind 共用该 snapshot，并必须在 RT allocation、material construction 与 compose transition count 前裁掉 false 结构。
- raw compose 已确认不是 scene-background 特例，而是 layer-local 两成员 full-frame pair：有 active effect 时按 `active effect count + admitted compose transition count` 的奇偶选择初始 current，先把 layer base content 只渲染一次到 current；effect 写 opposite 并在 effect boundary 推进，实际执行的 ordinary `compose:true` pass 另在 effect 内推进；condition-false/copy/swap/function 不推进；最终 current 发布到正常 layer/compositor。`_rt_FullFrameBuffer` 是另一受控入口，raw compose 不建立该 provider。
- 提交前复核据此否决了第一版“每个 stage 重新 capture 到独立 input、再写另一个 output”的草案。即使该草案可用两个物理槽，它仍会为每个 effect 多做一次整帧 copy，无法表达 parity、多 compose 和 fixed final member，属于与已核实架构分叉；相关实现和旧断言不得进入 R4 提交。
- R4 当前改为先建立纯值 `current/opposite` pair plan，再让 whole-chain allocation、executor、submission coordinator 与 compositor 共同消费同一计划。history 必须使用 copy-on-write 或等价物理隔离，GPU 失败后不得把已经写坏的 current submission texture重新暴露为上一帧 committed history；condition/function、`[PASS]` 负门、pair、history、终态观察与真实样本证据全部闭合前不提交 R4。
- 当前未提交实现已把首批 GPU cohort 收窄到可见的 direct image/solid/text compositor layer，并排除 utility owner、named dependency consumer 与 SceneScript Audio Bars 专用路由；capability-owned claim 后任一失败均失败关闭，不回退旧 authored renderer。逐层运行门同时检查 `accepted -> GPU completed -> compositor consumed` 缺失、非 accepted layer 越权执行，以及 accepted layer 出现 legacy authored route；Scene 全量 **190 modules ALL OK**、benchmark **99/99**、代码健康 **826 Swift / 44 locked legacy / 400-line limit** 与签名 Debug verify 已通过。这些仍只是提交前结构证据。
- 隔离真实正例 `3141421197` 的首次 R4 GPU 门 `.codex/scene-chain-r4-graph-20260804-v2/report.json` 正确标为 **FAIL**：layer 20 被 capability 接纳并 claim，但 596 次 whole-chain preflight 全部拒绝，executor `claimed/encoded/failure/gpuEncoded=1/0/1/0`，逐层 GPU/compositor 守恒均缺失且画面为空。由该隔离副本的 `project.json`、effect/material 与 shader 倒查确认，material/graph 没有显式 slot binding，而 fragment sampler 通过 `material: "framebuffer"` 注解声明当前 full-frame input；旧公共 authored-shader planner能解析该语义，R4 Finalizer却只消费显式 graph bindings，导致 active sampler 0 无资源。根因属于共享 material annotation -> typed graph input 桥，不是样本特例；现役资料已足以支撑独立实现，本断点没有启动新的 Ghidra 分析。公共 implicit-framebuffer bridge 落地后的 `v3` App 日志仍只给出粗粒度 `whole-chain-preflight-material-rejected`，不能把该日志写成 typed 定位证据；随后通过 Finalizer/color analyzer 的定向测试与源码回溯，把第二个断点收敛到 `colorContractUnproven`：原 analyzer 因 `main` 中存在已闭合的循环或条件，错误否定后续函数根级唯一 `gl_FragColor` 写入。修复只放行已闭合的前置控制流；输出受条件/循环直接支配、`return`/`discard`、多次或分量写入仍失败关闭，且没有样本、shader hash 或路径分支。
- 重建后的 `.codex/scene-chain-r4-graph-20260804-v4/report.json` 整体仍标为 **FAIL**，但仅剩 `authored effect graph succeeded layer IDs mismatch` 和 `effect execution evidence missing` 两个旧证据合同问题；R4 执行本身已为 `accepted/claimed/encoded/failure/gpuEncoded=1/1/1/0/1`，layer 20 两个跨帧 transaction 均取得 terminal publication、`compositorConsumed=true`和 `gpuCompletion=completed`，无 legacy-route conflict。ready/after 均非黑，两相位画面显示完整链条旋涡且运动量 `meanDelta=0.0845 / changedRatio=0.9509`；这证明当前 bounded 正例已实际进入统一 executor，不等于旧 telemetry 权威已迁移或更广泛的视觉等价。无 effect candidate 哨兵 `.codex/scene-chain-r4-zero-20260804-v1/report.json` 为 **1/1 PASS**：capability/executor `0/0/0/0`、loaded ratio 1、failed frame/drawable miss 0，没有越权制造 graph 活动。
- exact-effect CPU evidence、`resolved-material-graph` backend 与逐层 next-frame 合同接入后，相关 18 个模块共 **250 tests PASS**，Swift code health、`git diff --check`、Python compile 与签名 Debug verify 均通过；这只证明合同和构建闭合。随后真实正例 `.codex/scene-chain-r4-graph-20260804-v5/report.json` 仍正确标为 **FAIL**：586 次 claim 中 293 次编码成功、293 次以 `graph-target-allocation-failed` 失败，成功与失败逐帧严格交替；driver callback 约 59.96 FPS，但 submitted/completed 只有 30.08/29.88 FPS。根因是 coordinator 已允许两个 submission 在途，而 persistent graph cache 仍把唯一 current generation 的 submission pin 当成不可再分配，属于公共多帧 target residency/lease 缺口；必须让 pinned generation 与新 writable generation 物理隔离并继续受 byte budget、generation、history/submission pin 和 reset 合同约束，不能通过降低门禁或样本绕过闭合。
- whole-frame residency dry-run、两代物理 ring、反序 release、reset invalidation 与 history demotion 落地后，`.codex/scene-chain-r4-graph-20260804-v6/report.json` 首次在 `--require-graph-execution` 下 **1/1 PASS**：149 submitted / 149 completed / 0 failed，统一 backend、GPU completion、compositor consumption、next-frame 与 exact effect 都闭合，ready/after 非黑且相位运动存在。它同时暴露性能尚未闭合：driver 59.968 FPS，但 submitted/completed 仍只有 **29.883 FPS**，149 个 GPU 样本全部超过 16.67 ms；预算只有一代时，dry-run 会在旧 generation 被 GPU pin 的每个间隔帧主动 defer，虽消除了 v5 的交替 allocation failure，却把吞吐串行化。因此 v6 只能作为正确性进展，不能作为 executor 核心检查点通过。
- 对 whole-frame dry-run 的独立审查又发现两个 fail-closed 缺口：短暂 submission pin 释放后若持久 history 与当前请求仍超过预算，应立即 hard reject，不能先 defer 一帧；capability preflight 的 `.rejected` 也不能因 route 只投影 optional claim 而被当成 legacy 跳过。两处已改为 residual-history 模拟和 reason-bearing rejected route，新增 mixed history + transient 正反例；驻留池 **24 tests PASS**、runtime bridge **11 tests PASS**。后续吞吐优化仅考虑无 history chain 在同一已排序 `MTLCommandQueue` 上复用 tracked 物理纹理；旧 buffer 未 enqueue、queue 不同/未知、history closure/pin 非空、untracked texture 或第三个在途 submission 一律继续 COW/失败关闭。该边界符合 Apple 公开的同 queue enqueue 顺序与 tracked resource 自动 hazard 同步合同，但仍须由实现、反序 release/GPU failure 门和真实正例复跑共同证明，不能仅凭 API 文档宣称安全。
- bounded same-queue 复用落地后的根审查又修正了两个公共合同漏洞：预检 reservation 的 ordering context 现在必须与 coordinator 实际编码的 `MTLCommandBuffer` 为同一对象且仍为 `.notEnqueued`，已提交/完成 context 在 empty 与 idle cache 均于纹理工厂前拒绝；同一 chain 的 current + retired 全 generation submission pin 总数在 pure preflight、reserve 与 commit 三层统一限制为 2，第三次提交不能通过 COW 绕开。共享 generation 的正反序 release、reset invalidation、stale reservation、history COW/GPU failure 组合门均保持闭合；共享上限从纯 `ChainPlan` 移到 lease/residency 所有权范围，未新增文件或放宽 private。offscreen pool、texture publication 与 runtime bridge 共 **39 tests PASS**，benchmark **103 tests PASS**，Swift code health为 **828 files / 44 locked legacy / 400-line limit**，`git diff --check` 与 `script/build_and_run.sh verify` 通过。
- `.codex/scene-chain-r4-graph-20260804-v7/report.json` 在正例 `3141421197` 上为 **1/1 PASS**：driver `60.028 FPS`，274 submitted / 272 completed / 0 failed，submitted/completed 为 **55.005 / 54.604 FPS**，两个 terminal transaction 使用同一 physical generation且 exact backend、GPU completion、compositor consumption、next-frame 全闭合；相比 v6 的约 29.9 FPS，隔帧 defer 已解除。GPU frame p50/p95 仍为 `26.246 / 30.612 ms`，因此这是 executor 吞吐检查点进展，不是性能或官方视觉收口。首次零候选复跑同时暴露 benchmark 的 flag/zero-contract 分叉：报告已经 `zero_contract_succeeded=true`，CLI 却仍无条件要求非零 accepted。公共修复改为只有矩阵显式声明空 succeeded-layer 期望且完整 zero contract 成立时才通过，缺矩阵期望、非空期望或任一越权活动继续失败关闭；`.codex/scene-chain-r4-graph-20260804-v7-zero-v2/report.json` 对 `3766415113` 为 **1/1 PASS**。当前仍需 Scene 全量、fixed13、full45、权威文档同步与 scoped commit，不能提前进入 R4-0 或 R5。
- Scene 全量随后已重跑并为 **190 modules / 190 ALL OK**；首轮 fixed13 `.codex/scene-chain-r4-core-fixed13-20260804-v1/report.json` 则正确停在 **7/13 PASS、6 FAIL**，因此 full45 未启动。失败不是六个样本特例，而是四组共享合同：`3122339805` 与 `3768903841` 的 capability 在 claim 后才发现 shader variant preparation 不可执行，`3747492842` 在 claim 后才发现 texture purpose 闭包未证明，三者又把其余 19 个 claim 连锁为 `frame-command-buffer-invalidated`；`2902406982` 的 34 层 cohort 因 R4 丢失普通 effect 的 2048 resolution class，被按 4096 级估成约 `156.881 MiB` 而超过 128 MiB，按现役普通等级应约 `54.881 MiB`；`2131872317:82` 是 0 authored-FBO、无 history 的 pair-only chain，合法 allocation generation 更换被空资源字典相等误判为 persistent-state mismatch；`2131872317:13` 与 `2998757800:23` 还证明旧 authored chain 已因逐 stage 独立 full-frame pair 从旧约 `27/33.15 MiB` 膨胀为约 `144/132.59 MiB` 并分配失败。snapshot、utility、named-target 与 live-property 红项均在首个 frame/target 失败后连锁，暂不单独修补。
- fixed13 据此新增提交前原子门：launch capability 只登记静态可达的 variant/schema 候选；frame admission 必须在任何 main-pass/legacy 写入前冻结同一 snapshot，完成全部 candidate 的 compositor 条件、实际 texture purpose/uniform/pipeline finalization、chain-wide target reservation 与有序 graph preparation，再一次性签发 frame-scoped prepared claim。纯模拟 target preflight 后逐层 reserve/commit 不够，因为多个 reservation 会共享旧 cache revision并互相变 stale；需要 batch reservation/commit/pin，pending 只 defer，静态不支持保持 `notMigrated`，claim 后不再动态回退 legacy。旧 authored chain 同时改用同一 chain-wide pair/lease allocator，不能继续每 stage 各配一套 full-frame pair。0-FBO pair generation 与 persistent-FBO generation 必须分责，非空 FBO/history/token/rehydrate 门不得放宽。以上都是 R4 executor/allocator 地基，不是 R5 清理，也不通过抬高预算、忽略门禁或样本/layer/hash 分支解决。
- 用户于本断点进一步收紧阶段边界：不赶进 R5，先把遗留产品执行 owner 全部安全迁入统一架构。只读权限审计确认同一 image/solid/text 仍有新 graph、old authored chain、standalone、legacy offscreen、legacy inline 五个产品执行面，另有 utility/dependency、Image Blend、quad Light Shafts、四类 recovery 与脚本/source exact profile。结构基线为 **33 dedicated probes / 34 compiler identities / 33 runtime backends / 4 recovery kinds**；生产源码另有 **50 个文件、251 个硬编码 64 位 SHA 字符串**，以及数字 Workshop path **13 文件/70 处**、Workshop 命名 profile **4 文件/34 处**，两类 Workshop selector 合计 16 个唯一文件。计算出的 digest 用于 identity/cache/integrity/evidence 可以保留；与硬编码 expected digest 或 Workshop namespace 比较并据此解锁 renderer、常量或 profile 的行为属于算法 dispatch，必须逐族退出产品选择。完整权限清单、零双 owner/零 sample-layer-path-hash 算法分支门、迁移波次回归和旧 owner 撤权仍是 R4 未完成工作，之后才执行 full45 里程碑与 R5 纯清理收口。

#### 2026-08-04 暂停交接点（历史）：R4 核心尚未提交

**冻结状态（已由下方 checkpoint supersede）**

- 用户要求先停下来收尾后，所有并行写入已经停止；本断点不再扩能力、不开始下一迁移波次、不运行 fixed13/full45，也不提交未闭合的 R4。
- 当时分支仍停在 R3 提交 `588faf40`，冻结盘点为 92 个 tracked modified、45 个 untracked；该数字仅是历史接手快照。之后 R4 lane 已完成复核并提交，当前以本 checkpoint 和权威语义文档为准。
- 当时两份权威文档刻意不登记 R4；本 checkpoint 已补登记结构证据，但不提升能力等级，也不把 fixed13 写成全量基线。三份 clean-room 资料 `client-runtime-static-forensics.md`、`scene-format-and-render-graph.md`、`source-index.md` 的中性研究增量仍不等于产品能力完成。
- 收尾只读审计 `python3 script/audit_codex_artifacts.py --fail-on-candidates` 报告 `.codex current=5.29 GiB`、**196 个 stale candidates / 22.62 GiB**，其中包括约 0.92 GiB 的本轮 fixed13 失败现场和多批历史矩阵。当前没有完成逐项归属、唯一证据与可重建性裁决，因此本次一个都未删除；恢复时先保留 R4 报告，其他候选待阶段检查点后的独立清场预览与用户确认。

**目标能力池与当前架构判断**

```text
sample declaration
  -> unified parser / typed IR
  -> typed capability demand
  -> public capability catalog admission
  -> shared frame scheduler / resource lifecycle / ordering
  -> public executor and compositor
  -> explicit runtime evidence
```

- 样本只能声明版本化数据、资源、shader、graph 和属性；不能选择产品代码路径。sample/workshop/layer/path/hash 只能承担测试定位、实例身份、缓存、完整性或 fail-closed provenance，不能解锁 renderer、常量或近似算法。
- 当时未提交的新链已经用结构、条件、资源与 typed program 形成 candidate/admitted layer、capability token、full-frame pair plan、whole-frame target batch、frame transaction、submission coordinator 与 GPU/compositor evidence；审计范围内没有按样本身份选择算法。旧 authored chain 也已开始复用 chain-wide allocator，并把 direct/utility 资源提交挂到共享 `SceneSourceUpdateTransaction`，claim 后主链失败会阻止本帧后续 legacy/utility 编码。
- 这只说明方向与官方公开的 data-driven 分层性质一致，不说明产品整体已经同构或向下兼容。以下旧权威仍阻止“唯一能力池”结论：
  1. launch 仍通过 `SceneEffectRuntimeDispositionCatalog` 在资源加载后投影 effect family 供 telemetry 使用；该 family 已不再是 new capability admission authority，但仍属于旧 evidence projection，后续可清理。
  2. `SceneResolvedMaterialFramePreflight` 的 target extent 已由 typed claim policy 提供，new capability 不再调用旧 `authoredEffectChain.authoredShaderOffscreenSize`；旧 authored chain/plan 仍作为 legacy draw request owner 可达。
  3. `.notMigrated -> .legacy` 和 old authored chain、standalone、legacy offscreen/inline、utility/dependency 等产品 owner 仍可达；R4 还没有完成“一阶段一个 owner”的迁移合同。
  4. launch `executableLayerIDs`、frame preflight 的 content/audio 排除和 runtime claim 分散决定准入；需要收敛成一个 typed capability admission。动态 visibility、condition schema、clear/function 与 SceneScript dynamic producer 当前保持 fail closed，后续只能作为公共能力补入。
  5. `markComposite` 当前已返回显式 `CompositeOutcome`，ticket/texture invariant 失败会立即形成 rejected route 并在 frame transaction 中回滚；后续 legacy/utility 编码由共享 source transaction 短路。仍需在 legacy authored frame batch 迁移中证明跨 owner 的终态守恒。

#### 2026-08-04 R4 partial checkpoint：统一 graph 地基已提交

- 本次 checkpoint 已将 raw authored graph admission、typed capability token/pair plan、frame snapshot freeze、variant/texture/uniform/pipeline finalization、whole-chain target preflight/batch reservation、prepared claim、统一 graph executor、terminal composition、GPU completion、rollback 与 next-frame evidence 串成同一主链。正例 `3141421197` 的 R4 graph report 已证明 accepted/claimed/encoded/GPU/compositor/next-frame 闭合；零候选样本保持 zero-contract 通过。
- 当前 fixed13 定向子集 `.codex/scene-chain-r4-core-fixed13-20260804-v2/report.json` 为 **4/6 PASS**。通过样本为 `2131872317`、`2998757800`、`3122339805`、`3747492842`；`2902406982` 的 layers `167/177/530` 与 `3768903841` 的 layers `181/188/202/211/220/232` 仍因 legacy authored route 的 `authored-target-allocation / graph-targets-unavailable` 失败。该红项指向旧路径逐 chain reserve/commit 的 persistent target allocation，不是新 graph validation 新增的样本特例。
- 同一 image/solid/text 仍有五个产品执行面：R4 resolved-material graph executor、old authored chain、standalone authored renderer、legacy offscreen、legacy inline/direct layer；utility/dependency capture、Image Blend、quad Light Shafts、四类 recovery、dedicated probes/compiler/backend 与 Workshop/hash selectors 仍未迁完。结构基线仍为 **33 / 34 / 33 / 4**，不能宣称 R4 完成，也不能进入 R5。
- 下次从公共 legacy authored frame batch 继续：先收集普通 image/solid/text 与 utility capture plans，统一 prepare/commit/pin，并把 tables 注入 compositor；完成后再按 R4-0 至 R4-6 逐族撤销旧 owner。full45 本次未运行，保留上述失败现场，不删除 `.codex` 报告。

**冻结前最后一轮已运行验证**

| 验证 | 结果 | 证据边界 |
|---|---:|---|
| `git diff --check` | PASS | 只证明 patch whitespace/marker 健康 |
| `python3 script/check_code_health.py --check --base-ref HEAD` | PASS：829 Swift / 44 locked legacy / 400-line limit | 覆盖最后一轮 Swift patch |
| `test_scene_source_update_transaction.py` | 3/3 PASS | source transaction exactly-once release 与失败关闭 |
| `test_scene_framebuffer_capture.py` | 42/42 PASS | frame transaction、claimed failure 短路与 capture 合同 |
| `test_scene_offscreen_texture_pool.py` | 27/27 PASS | whole-frame batch、revision replay、reset/history/pending isolation |
| `test_scene_resolved_material_runtime_bridge.py` | 12/12 PASS | batch prepare/commit 与 submission lifecycle |

以下证据**没有覆盖最后一轮 patch**，恢复时必须视为历史线索而不是当前 PASS：此前 Scene 全量 190/190、`script/build_and_run.sh verify`、`3141421197` 的 v7 正例/零候选样本结果。首轮 fixed13 报告 `.codex/scene-chain-r4-core-fixed13-20260804-v1/report.json` 为 **7/13 PASS、6 FAIL**，它产生在最后一轮公共修复之前且尚未复跑；full45 按门禁从未启动。当前 App 是否编译、完整 Scene 是否仍全绿、失败样本是否恢复及多相位视觉状态均为 **pending**。

**下次恢复顺序**

1. 先核对 `git status --short --branch`、全部 untracked 文件归属和 diff；确认没有新的并行 writer 后，审查最后一轮 transaction/batch patch，不能丢弃或机械重做。
2. 先消除上述旧 classification、old extent 和分散 admission 三个架构依赖，再让 `markComposite` 返回显式失败结果并立即短路；不得用 sample/layer/path/hash 分支绕过。
3. 重跑四个定向模块、Swift code health 与 `git diff --check`；随后按核心执行链风险运行 Scene 全量、`script/build_and_run.sh verify`，确认当前 App 真正加载该实现。
4. 先复跑 fixed13 中对应共享根因的定向样本，再跑 fixed13。只有 fixed13 通过且定向证据无法排除跨样本风险时，才运行 full45；固定门与完整门必须分别报告。
5. executor 核心检查点满足后，先同步语义权威文档并做独立 scoped commit；再按 R4-0 至 R4-6 逐族迁移，每族同提交撤销旧 owner。最后一个旧产品 owner 撤权、静态算法 selector 归零且 R4 里程碑证据闭合前，不进入 R5。

**恢复期间禁止**：不要把当前 dirty lane 宣称为现役能力；不要为 `3766387484`、`3769688830`、`3768903841` 增加专属适配；不要抬高显存预算、放宽 fail-closed 或用 hash 解锁算法制造矩阵通过；现役资料足够时不要启动 Ghidra；不要删除本段列出的 `.codex` 失败/交接现场，清理须先完成只读归属审计并另行确认。

#### R4 旧权限安全迁移波次

#### 2026-08-05 legacy authored frame batch checkpoint

- 本批已把生产普通 image/solid/text authored chain 与 utility composition/project/fullscreen capture 的 target 生命周期收敛为同一 frame batch：先做 shared-pair byte-cost 预检，再在同一 pending command buffer 下统一 reserve、实体化、收集 commit request，并一次性发布 pair、chain、pin、LRU 与 revision。pair-only chain 使用独立的两纹理 `sharedGraphPair` allocation；通用旧 `.pair` 三纹理兼容路径仍保留给未迁移入口。
- compositor 的 authored chain 路径现在只消费 frame-local render-target tables，不再 per-chain `graphTargets`/reserve/commit；renderer coordinator 统一准备 tables，并通过一个 `SceneSourceUpdateTransaction` resolution action 释放全部提交。utility 预分配 extent 与 dispatch 共用同一 `imageModelMatrix` 和 `SceneCaptureGeometryResolver`。
- 本批代码/测试验证：offscreen texture pool **30/30**、framebuffer capture **42/42**、source update transaction **3/3**、utility layers **10/10**、resolved material runtime bridge **13/13**；Scene 全量 **190 modules / ALL OK**；Swift code health **834 files / 44 locked legacy / 400-line limit**；`git diff --check` 与 `script/build_and_run.sh verify` 通过。
- 后续 owned-history follow-up 又让含 persistent FBO/history 的 chain 在同一 frame batch 中选择 owned pair，并从 lease 的 history closure 导出守恒 token set 一次性 pin；standalone authored plan 也纳入 renderer batch，compositor 不再调用 per-plan `graphTargets`。旧 pool `graphTargets` 与 `preparePersistentGraphTargets` 通用 API 仍保留给 allocator harness/未迁移调用，但不再是普通层或 utility 的 standalone 产品绘制入口。
- 运行补证：`.codex/scene-chain-r4-persistent-targeted-20260805-v1/report.json` 对原 persistent 红项 `2902406982` / `3768903841` 为 **2/2 PASS**；随后 `.codex/scene-chain-r4-persistent-fixed13-20260805-v1/report.json` 为完整 fixed13 **13/13 PASS**。两门均为 10 秒窗口并显式要求 admission、disposition、execution 三轴，loaded ratio 全 1、graph failed layer 与 report failure 均为空。full45 未运行，preview 只作 advisory，因此不能从本门宣称视觉等价或 R4 完成。
- legacy offscreen/inline、dedicated owner、通用 persistent API 与 selector 仍可达，下一批继续做 owner 迁移。

#### 2026-08-05 R4-1 generic material bridge follow-up

- 生产 image/solid/text 与 utility request 不再发布被 authored chain 遮蔽的 single-stage standalone projection；legacy frame batch 只为真实 authored chain 建立兼容 batch owner。旧 standalone renderer/backend 本身仍保留给尚未迁移入口，未做删除或隐式回退。
- `SceneResolvedMaterialShaderSchema` 新增结构性 implicit framebuffer 推断：仅当 authored texture slots、graph bindings、shader defaults/material annotation 均为空，且唯一 sampler 为 regular `g_Texture0` 时绑定当前 layer/effect graph input；多 sampler、候选、default、binding、命名 graph identity 均继续 fail closed。launch readiness 与 frame texture selection 使用同一 provenance/identity 合同，项目自有无 annotation fixture 已通过。
- 公共 color boundary 现只准 analyzer 证明的单源 root-local 形态：唯一 `vec4/float4 local = texSample2D/texture2D(g_TextureN, ...)`，local 在输出前无其他读取/修改，根级输出仅保留 `local.rgb` 并从 `local.a` 派生 alpha；其他采样、RGB 算术、分量/多写、条件控制、return/discard 与未知 alpha 来源继续 unresolved。对应 slot 入口解预乘、fragment wrapper 出口重新预乘，resolved contract 只接受 opaque/premultiplied 输入并输出 premultiplied；frontend schema 升至 3。
- 当前验证：Scene 全量 **190 modules / 153.7 s / ALL OK**；Swift code health **835 files / 44 locked legacy / 400-line limit**；straight-alpha、resolved derivation/finalizer/pass encoder/graph executor/capability、semantics 与 shader-preparation census 定向门均通过；`script/build_and_run.sh verify` 成功，当前签名 App executable SHA-256 `bd084f8bd8ece12e54ee7e0091c1920a795af304754b94159259f14ef43ad988`、CDHash `41fbc32adbe220b3afd17f411d3fe65c8bb2e1a2`、Team `H9QWU9XN8R`，签名前后 verified。
- 新鲜隔离三样本门 `.codex/scene-chain-r4-r1-straight-alpha-20260805-v1/report.json` 为 **3/3 PASS**：`3141421197` graph layer `20`、`3768020435` graph layer `389` 均形成 accepted/claimed/encoded/GPU/compositor/next-frame 闭合；`3769688830` graph accepted `0` 且旧 authored chain 保持成功。full45 `.codex/scene-chain-r4-r1-straight-alpha-full45-20260805-v1/report.json` 为 **44/45，非 PASS**，唯一红项为既有 `2067939514` particle candidate/skipped-transparent 基线偏差；报告 SHA-256 `5cac81f60d531bb3d91ee25d02d90fd377f8a78f0d19c3a22ca0e6d153f5dd42`，full matrix SHA-256 `10fa1e7995118e5455b4cf8f03b65b2568aa6732d9f13433ac691f4f67eb1475`。
- 本批已把 `3768020435` 的 owner 期望从旧 `authored_effect_graph` 字段迁到 `expected_resolved_material_graph_succeeded_layer_ids=[389]`；这只是当前公共 capability 的跨样本证据，不代表任意 shader、整条 Water Waves/Scroll 混合链或 Wallpaper Engine 视觉/像素等价已完成。旧 `.authoredShader` backend、pipeline cache、Scroll profile 与其他 legacy/dedicated/utility owner 仍保留，下一步按 R4-2 继续扩共享 material capability 后再同提交撤权。

#### 2026-08-05 R4-0 权限冻结门

- `script/scene_source_layout.json` 升为 schema 2，在既有 layout manifest 中加入 13 条 render-chain authority ratchet；`test_scene_semantics_coverage.py` 统一扫描 Swift 注释剥离后的调用与保留字符串 selector，不另建一次性脚本。当前冻结 1 个 canonical compositor entry、1 个 canonical runtime entry、legacy product/observation `4/3`、main-pass writer 7、dedicated probe/compiler/backend/recovery `33/34/33/4`、hardcoded SHA `251 / 50 files`、numeric Workshop path `70 / 13 files` 与 named Workshop profile `34 / 4 files`。
- 当前源码必须与 manifest 的 occurrence/file 集合精确相等；删除权限时必须同提交收紧 manifest，相对已提交 `HEAD` 增加 occurrence、allowed file 或 scope 会失败。项目自有合成负例验证新增 owner、recovery、selector 均被拒绝，并确认注释不制造假 owner。
- 自动门：semantics **5/5 tests PASS**（提交后 ratchet 基线比较已启用）、Scene 全量 **190 modules / 164.7 s / ALL OK**、Swift code health **834 files / 44 locked legacy / 400-line limit**、`git diff --check` 与 `script/build_and_run.sh verify` 通过。R4-0 没有迁移产品像素行为，故不重复 fixed13，也不运行 full45。
- 本门只冻结现状，不把 `33/34/33/4`、legacy authority、main-pass writer、SHA/Workshop selector 写成受支持能力。R4-1 至 R4-6 必须继续按 capability family 同提交接管与撤权；最后一个旧 owner 撤权前 R4 未完成，R5 不得开始。

#### 2026-08-05 R4-2 typed audio-spectrum uniform-array slice

- 本批从公共 RenderGraph 输入合同切入，不为任何 sample/layer/workshop/hash 增加分支：`SceneAudioSpectrumSnapshot` 的 16/32/64 左右声道值经 `SceneAuthoredShaderFrameInputs` 进入统一 `SceneResolvedMaterialProgramFinalizer`，由 host-uniform schema 识别 `g_AudioSpectrum{16|32|64}{Left|Right}`，并由同一 `SceneResolvedMaterialUniformEncoder` 按固定数组 ABI 写入 Program uniform bytes。frontend/Metal emitter/source、semantic/exact identity、pass encoder 和布局验证同时保留 array shape/byte size，未知数组名、非 float、非法长度与跨 stage 形状冲突继续 fail closed。
- 项目自有正反门已补入 `test_scene_authored_shader_frontend.py` 与 `test_scene_resolved_material_program_finalizer.py`：16/32/64 左右数组可生成 Metal、最终化并按索引读回非零 fixture；未知数组、15 档、非 float 和跨 stage 冲突均被拒绝。当前定向验证为 frontend **10/10**、finalizer **7/7**、execution capability **3/3**、graph executor **1/1**、runtime bridge **13/13**；code health **835 files / 44 locked legacy / 400-line limit**、`git diff --check` 与 `script/build_and_run.sh verify` 通过。
- 新鲜隔离运行 `.codex/scene-chain-r4-audio-3747492842-20260805-v1/report.json` 在 `--audio-spectrum-fixture` 下 **1/1 PASS**，driver FPS `60.0579`、startup ready `3545.3 ms`；但该样本的 capability 仍是 `accepted=0`，并保留 `dynamic-uniform-unavailable=1`、`execution-route-content-kind=4`、`material-variant-envelope-texture-purpose=2`。因此这次运行只证明输入注入与既有链路未回归，不能声称真实样本已由新 graph executor 编码，也不能把残余 rejection 归因于音频数组。后续需先完成公共动态 producer/purpose 合同，再以同一 executor 重新取得真实 GPU/compositor evidence。
- 该切片仍属于 R4-2 进行中：旧 authored/standalone/dedicated/audio profile owner 没有撤权，未新增 fallback 或双写；R4-2 只有在真实候选进入统一 executor、旧 owner 同提交撤权、跨样本正反门闭合后才可记为完成。R5 继续禁止启动。

#### 2026-08-05 R4-2 dynamic material owner / lifecycle follow-up

- 本批继续收缩公共权限，不做样本运行适配：用户属性的 `shaderValue` 目标现在只按 typed `layer/effect/pass/name` 身份与唯一属性种类/回退值形状编译为 dynamic effect constant，删除 Local Contrast、Opacity、X-Ray、Tint 和 Simple Audio Bars 的 effect path / Workshop namespace 选择器。类型冲突、非 direct binding、非法 target 与不可推导 shape 继续 fail closed。
- capability catalog 对全部 active `EffectKey` 作集合守恒后，才可向 static disposition catalog 发布 `resolved-material` owner；已被统一 executor 接管的 layer 不再同时归因给 old authored owner。这只改变公共 owner/disposition 权威，不用 layer ID 选择算法。
- frame batch 现在明确区分 `ready/deferred/rejected`；只有 frame 存在 resolved-material plan 时，legacy-only batch 的 defer/reject 才能记入 graph executor telemetry。launch capability 在 variant/readiness 与 texture binding 闭合后追加静态 color contract 门，`colorTransfer=.unresolved` 以 `material-variant-envelope-color-contract` 失败关闭，不再先 claim 后阻断同帧其他公共候选。
- 根因代表门 `.codex/scene-chain-r4-full45-rootcause-targeted-20260805-v2/report.json` 为 **6/6 PASS**；包含 `1937925563`、`2134765860`、`2902406982`、`3141421197`、`3747492842`、`3768020435`，报告 SHA-256 `2c5367e1a8a9d1453272b58125dad8caeb738943808199db765aa1506cfb4dc7`。三个公共 owner 期望同步为 `3141421197:20`、`3747492842:186`、`3768020435:389`；这些 ID 只存在矩阵证据，不进入生产 dispatch。
- fresh full45 `.codex/scene-chain-r4-resolved-owner-full45-20260805-v2/report.json` 为 **44/45，非 PASS**，唯一红项仍是 `2067939514` 的既有 particle candidate/skipped-transparent 偏差；R4 graph/disposition 新红项已清零。报告 SHA-256 `fa32d0a8b61b819aa5393820b75a69c713051f1c194c904e6d5f77bbdc7d8980`，full matrix SHA-256 `51ca2dfe1e8191913f0b1a7c9d329e90534a83fc65931c87852dccd0aa4ca1d3`。当前 Scene 全量 **190/190 ALL OK**，capability **3/3**、framebuffer **44/44**、offscreen **30/30**、code health **836 Swift / 44 locked legacy / 400-line limit** 与签名 `verify` 通过；App executable SHA-256 `bf532a9a04fdf836d437812379a3f3b9839fdd105264f80dbb533b9d8f353b19`，CDHash `e70392146290aa8de6dfac39c6b24c174bf6645f`，Team `H9QWU9XN8R`。
- 这批只闭合 dynamic material 的公共编译入口、resolved owner 归因和 frame lifecycle 边界；旧 `.authoredShader` backend/pipeline/Scroll、legacy offscreen/inline、dedicated/utility/audio profile owner 尚未按 capability family 全部撤权。R4-2 仍未完成，不进入 R5，也不将 44/45 写成 full45 PASS 或视觉等价。

#### 2026-08-06 R4-2 unified material graph ownership checkpoint

- 代码检查点 `07e8481e` 继续扩展同一 public Program/binder/executor，而不是为样本或 effect 名称增加适配：frontend 新增有界 static/float-uniform loop、固定 varying array 与 disabled-combo 合同；launch catalog 以 bounded sampler reachability 收集 typed asset/user/system/default 需求；straight-alpha preserving 与 graph-only independent-alpha signal 进入同一 color contract；相邻 effect output、multi-effect ingress 与 self/primary/`previous` graph-internal dependency 由 typed identity 接管。外部 layer dependency、named reference、未知 purpose/state/color、越界 loop/varying 和非 graph alpha-signal 继续失败关闭。
- 提交前审查修复了一个公共语义错误：bounded-loop 原实现会按 uniform 名称全局钳制上下界，连循环外颜色/归一化计算也会被改写；现只钳制已准入循环头的具体 token，循环外引用保持 authored value。新增回归断言与 Metal compile 门覆盖该边界。生产新增行没有 sample/layer/path/hash/Workshop selector，样本身份只用于下述隔离证据。
- 验证为受影响模块 **168/168 tests PASS**，Scene 全量 **190 modules / 194.5 s / ALL OK**，Swift code health **853 files / 44 locked legacy / 400-line limit**，`git diff --check` 与签名 `script/build_and_run.sh verify` 通过。提交候选 App executable SHA-256 `599e7b84cb5059b2eab49bc765899d606b6b9f5e6d3e93b97897778bb672a42e`，CDHash `562da514e94bf9d82a30d096e2ae3abbee07495c`，Team `H9QWU9XN8R`。
- 新鲜隔离报告 `.codex/scene-chain-r4-bounded-loop-20260806-v26/report.json` 的 overall 仍为 **FAIL**，仅因冻结 matrix 仍期待 old authored succeeded-layer 与旧 disposition kind/hash；本批刻意没有修改 fixed13/full45 matrix。报告内新链合同自身闭合：13/13 layer accepted，route 为 `r4-layer-route-v2`、malformed `0`；51 个 effect 全部归因 `strict-generic`；五次 executor observation 累计 claimed/encoded/GPU `65/65/65`、failure/deferred `0/0`；13 个 accepted layer 的 GPU completion、compositor consumption、next-frame 与 exact `resolved-material-graph` 集合完全一致，graph validation failure 为空。报告 SHA-256 `c2f88a87e589918101b65e861df759a410a1fe91f72f58ca62a49d16c40e1883`。这证明公共执行接管，不证明 matrix PASS、全样本兼容或视觉等价。
- 性能尚未闭合：同一 v26 的 GPU p50/p95 为 `13.615/13.615 ms`、failed frame `0`，但 CPU frame p50/p95 为 `1976.812/1984.826 ms`、main-frame p95 `1988.346 ms`，driver/submitted/completed 仅约 `0.503/0.503/0.335 FPS`。下批必须先定位公共 per-frame CPU 重复工作或缓存失效，不能以扩大预算、降低门禁或样本分支掩盖；在吞吐恢复并有跨 revision 正反门之前，本 checkpoint 只能视为所有权/正确性进展。
- `.codex` 收尾审计报告 current `5.33 GiB`、257 个 historical candidates / `42.20 GiB`；其中包含本批 v26 与多批仍可能是唯一失败现场的证据，未完成逐项归属裁决，因此本批没有删除任何候选。

#### 2026-08-07 R4-2 performance / ownership / lifecycle closure

- 公共 CPU 回退根因是 `SceneResolvedMaterialVariantCache.resolve` 每帧重复执行 immutable bootstrap sampler 的 shader preparation。cache 现在只在 launch envelope 的既有前置门通过后保存 bootstrap sampler schema，direct cache consumer 也只惰性求值一次；failure ordering、typed texture-purpose evidence 与 unknown fail-closed 均保持，没有引入 sample/layer/path/hash selector。`1937925563` 当前定向门 CPU p50/p95 从约 `1.98 s` 恢复到 `46.369/47.036 ms`，符合该样本约 20 FPS 的现役目标；13 layer / 51 effect 的 claimed/encoded/GPU 为 `130/130/130`，failure/deferred 为 `0/0`。
- ownership matrix 正式迁移 `1937925563` 的 13 层、`2131872317` 的 2 层、`3767460992` 的 1 层与 `3769688830` 的 3 层到 `resolved-material-graph`；生产 admission 仍只由 authored graph/Program capability 决定。四样本 accepted、resolved succeeded、GPU/compositor/next-frame 与 exact backend 集合一致，`legacy_conflict_layer_ids=[]`；其他旧 authored succeeded layers 仍属于未迁移 capability，不被本批误删。
- `2131872317` 首轮 ownership 门在第 45 帧暴露 `legacy-authored-batch-commit-rejected`：legacy batch 取得 cache revision 后，上一帧 GPU completion 合法释放 pin 并改变 revision，导致提交把正常 completion 竞态误记为 graph failure。legacy batch 现在只要 reset epoch 未变，就在同一提交锁内按当前 resident state 重建 reservation，并要求原 generation/history/shared-pair 身份完全相同；reset、资源替换、预算与材质化失败继续拒绝。项目自有 fixture 精确在 snapshot 后、commit 前释放无关 pin，连同 offscreen **30/30**、framebuffer/source transaction **47/47** 通过。
- `2131872317` 的 10 秒与 20 秒独立门均 **1/1 PASS**；长门 claimed/encoded/GPU `168/168/168`、failure `0`、正常背压 deferred `2`、graph diagnostic/failed/GPU failed `0/0/0`，920/920 frames completed，CPU/GPU p95 `5.044/8.595 ms`。另外三 owner 联合门 **3/3 PASS**。fixed13 `.codex/scene-chain-r4-owner-fixed13-rebase-20260807-v1/report.json` 为 **13/13 PASS**；fresh full45 `.codex/scene-chain-r4-owner-full45-rebase-20260807-v1/report.json` 为 **44/45，非 PASS**，唯一红项仍是 `2067939514` 的既有 particle candidate/skipped-transparent 偏差。full45 全部 resolved executor claimed/encoded/GPU `895/895/895`、failure `0`、graph diagnostic/failed/GPU failed `0/0/0`、failed frame/drawable miss/discontinuity `0/0/0`。报告 SHA-256 `eb7a85a8212e77ea645a17faa6d0655ab4fca3ef84f633cb5d5598f2e7fb8292`，fixed13/full45 matrix SHA-256 `6aee963539c1048f27c561766ed7c1dbefcd481af2a2ed3b20826979d05d0ed9` / `80df30408486d45ac848968eb82b65e080a711be1440d58d2d7277dcd3479e09`；签名 App executable SHA-256 `cdd7f08bb8c0c4a53cbf231cca079d1e2e126730edf6137754be1f36bea5ad86`、CDHash `96630fcc49c0aff4a542fa4d4fbfc26facd09797`、Team `H9QWU9XN8R`，deep strict verify 通过。
- 这个 checkpoint 只闭合当时的性能、owner evidence 和 coexistence lifecycle；其后仍须单独撤销旧 `.authoredShader` 产品 owner。dedicated planner/backend/profile、legacy inline/offscreen、utility/audio owner 继续可达，R4-2 与 R4 均未完成；44/45 不得写成 full45 PASS，R5 继续禁止启动。

#### 2026-08-07 R4-1 authored-shader product owner revocation closure

- resolved-material capability 现在是 generic stage 的静态 admission owner；每个 layer 的 descriptor graph、accepted key、resolved plan 与 effect subject 必须精确守恒，部分或错配接管继续失败关闭。已接管 generic stage 从旧 chain planning 中排除，静态记录固定为 `admitted-generic / resolved-material / program / complete`，旧 chain stage count 只守恒仍由 dedicated owner 执行的 stage。
- 旧 `.authoredShader` compiler/backend、execution plan/planner、uniform binder、pipeline cache、renderer branch 与 exact Scroll profile 已撤权删除；共享 frontend、preparation 与 frame inputs 保留为中性 Program 前置能力。authority ratchet 同批从 compiler identities **34 -> 33**、runtime backends **33 -> 32**、hardcoded expected SHA **251 -> 244**、numeric Workshop selectors **69 -> 59**、named Workshop selectors **34 -> 30**；dedicated probes 与 legacy authority 未被本波次伪降。
- benchmark 合同新增 exact generic owner/profile 负门，并把旧 chain stage 守恒改为 dedicated-only；`script/tests/test_scene_wallpaper_benchmark.py` **103/103 PASS**，Scene 全量 **188 modules / 156.3 s / ALL OK**，code health **849 Swift files / 44 locked legacy / 400-line limit**，`script/build_and_run.sh verify` 与 deep strict codesign 通过。签名 App executable SHA-256 `c7becba82fa0703dce587f808f1d247ab094f7ad8a7ca98e9b1cf1e4d4e93734`、CDHash `8ee117324a547bd6f5a43197706f9caa04c88bd6`、Team `H9QWU9XN8R`。
- `.codex/scene-chain-r4-authored-owner-revocation-targeted-20260807-v3/report.json` 对四个主要迁移样本为 **4/4 PASS**；`1636394814` 负例为 **1/1 PASS** 且 resolved accepted/exact backend 均为空；补充三样本 graph 强制门为 **3/3 PASS**；fixed13 为 **13/13 PASS**。fresh full45 `.codex/scene-chain-r4-authored-owner-revocation-full45-20260807-v2/report.json` 为 **44/45，非 PASS**，唯一红项仍是 `2067939514` 的 particle candidate/skipped-transparent 偏差。七个 resolved 样本共 22 层 / 68 stage 的 accepted、exact backend、compositor 与 next-frame 集合一致，legacy conflict 与 graph/admission/disposition/execution validation failure 均为 0；executor claimed/encoded/GPU 为 `648/648/648`、failure `0`。full45 报告 SHA-256 `c4ec84ae027b3d4f644c0cd6ca9408e4f9affa6d730bb859cb490a424f479a8b`，fixed13 报告 SHA-256 `2e0badb5d2d01094909a4d3ec9ba67b76ba002153fa940d84e5ce5ee53fb43e1`，full45/fixed13 matrix SHA-256 `15b51a6b02b7c983bddb493905b9dd3b9fa9a5ead814e775ce0c7a8140b41514` / `4286960e2311ad3acb61c867cd539165a5e438f89758f4751232be823556512e`。
- 这只闭合 authored-shader 产品 owner family 的 R4 迁移单元，不代表全部 effect、任意 GLSL、Windows 视觉等价或 R4 完成。dedicated、legacy inline/offscreen、utility/dependency、audio 与其他对象 writer 仍需按同一“接管 + 撤权 + 正反证”合同留在 R4 继续迁移；R5 仍未准入。

#### 2026-08-08 R4-2 Color Key mixed graph owner migration

- unified capability 现在按 authored effect order 编译 resolved stage 与 bounded pair-only dedicated leaf，mixed chain 必须以 resolved stage 开头，dedicated leaf 不得持有 logical target；stage identity、资源投影、frame pair、publication/completion transaction 与 runtime disposition subject 由同一 capability 守恒。旧 Color Key planner、execution plan、pipeline、renderer、chain backend 与只服务旧 owner 的测试已撤权删除，没有增加 sample/layer/path/hash dispatch。
- 生产运行修复了两个公共缺口：统一 owner 的 dedicated leaf 资源必须从 capability 投影到 loader；dedicated stage 的 Program identity 必须由 stage graph stable digest 构成，不能因旧 execution plan 撤权而失去稳定身份。dedicated-before-resolved 的项目自有两 effect fixture 精确拒绝为 `mixed-chain-resolved-prefix-required` 且不发布 claim；logical target dedicated leaf 继续失败关闭，R4-3 未提前进入。
- 最终验证为 capability 定向 **4/4 PASS**、benchmark **103/103 PASS**、matrix contract **32/32 PASS**、Scene 全量 **186 modules / 155.0 s / ALL OK**、code health **847 Swift / 44 locked legacy / 400-line limit**、semantics **5/5 PASS**、`git diff --check` 与 `script/build_and_run.sh verify` 通过。`3767460992` 定向报告 **1/1 PASS**；fresh full45 `.codex/scene-chain-r4-colorkey-mixed-full45-20260808-v3/report.json` 为 **44/45，非 PASS**，唯一红项仍是 `2067939514` 的既有 particle candidate/skipped-transparent 偏差。
- full45 中 `3767460992` 的 resolved `[20,945,994]` accepted/exact backend/GPU/compositor/next-frame 集合一致，legacy conflict、graph diagnostic/failed outcome 与 executor failure 均为 0；现役四个 resolved 样本共 6 层 / 7 stage，executor claimed/encoded/GPU `247/247/247`、failure `0`。报告/full matrix/App executable SHA-256 为 `734dc558e9e7f38f66d3c7b6f650b26e58bd2c0a1c272c141e3eeef122b01b48` / `f1b4912475f27ff15220e6fae11d24d02e495b49816a15638c71adb687cb427f` / `6177827d02f2c8803aab331eb246631da7ecce0d3a4690526159c048a5bd78c6`，CDHash `654b76282a794409e3b3821dc0a3f7928405163b`、Team `H9QWU9XN8R`，签名前后 verified。
- 该波次只迁移 Color Key mixed ownership；logical target/multi-pass、其他 ordinary material capability family、dedicated/legacy/utility/audio owner 仍待后续 R4 波次。R4-2/R4 未完成，R5 仍未准入，也不把 44/45、非黑输出或相同 owner 集合写成 Wallpaper Engine 视觉/像素等价。

#### 2026-08-08 R4-2 ordinary Opacity owner migration

- 普通 Opacity material 现在 generic-first：完整 Program 编译成功后由 resolved-material graph executor 唯一持有，并从旧 catalog 排除；统一编译失败的 composition、mixed、video/masked 等未迁移形态释放给既有 bounded fallback。旧 planner/renderer 与专用测试因此继续承担 fallback 和像素 oracle，不表示普通 Opacity 仍由旧链执行，也不允许同一 stage 双 owner。
- 公共编译补齐 dead sampler/resolution 数据流与 optional mask fixed-point：prepared variant 未引用 sampler 从 active schema 删除；只有 fragment 证明不消费的 varying 分量才允许连同 resolution 写入删除，活用 `g_TextureNResolution` 时必须保留真实 graph resource extent。optional mask 只由 reachable typed sampler purpose 与同代 resource readiness 选择 `MASK=0/1`；purpose 缺失、歧义、资源未 ready、未知 state/color 或 unsupported leaf 继续失败关闭，不伪造白纹理或 metadata。
- fresh 定向门中 `3141421197` 恢复 resolved executor、GPU/compositor/next-frame 与非黑窗口，`2902406982:[365,372,647,664]` 由普通 Opacity Program 接管，其他 family 没有被本批误迁移。刷新 owner 合同前的 full45 `.codex/scene-opacity-r4-2-full45-20260808-v2/report.json` 为 **36/45 直接 PASS**；8 项仅 owner/stage/disposition/chain 预期失配，均 loaded ratio `1.0`、failed frame `0`、graph/executor validation 无失败；唯一非 owner 红项仍是 `2067939514` 的既有 particle candidate/skipped-transparent 偏差。只据此刷新这 8 项，`2067939514` 保持不变；该预刷新报告不写成 44/45 或 PASS。
- 最终 milestone `.codex/scene-opacity-r4-2-milestone-full45-20260808-v1/report.json` 为 **44/45**，唯一失败仍是 `2067939514` 的 `particle candidate count mismatch` 与 `particle skipped transparent count mismatch`；其余 44 个样本 loaded ratio 均为 `1.0`、failed frame 为 `0`，没有新增 owner、graph、GPU 或 route 红项。报告 SHA-256 `6c4a0e45bd82cbccdaa938b53ce632eabda2f471e75c5e56d42ba77745695165`，full matrix SHA-256 `579a028dc998cca627a740482ddd5716a004a40d01f82b1482714d984b2b9b5f`；fixed13 base digest 同步为同一 `579a028dc998cca627a740482ddd5716a004a40d01f82b1482714d984b2b9b5f`，suite 文件 SHA-256 `6c9ef8b648d4ba209e50667178c9810dcf209c0b1fa88770039796debd6f0ef5`。固定 suite expand/compact/expand 语义无差异，matrix suite/contract **35/35 PASS**。
- 用户另报 `3743305891` 整体纹理 Y 轴倒置、`3088601835` 局部贴图疑似帽子倒置。当前 full45 只证明结构链、资源加载、GPU/compositor 和非黑输出，没有同相位方向视觉门，因此这两个问题明确未由 Opacity 批次修复。Opacity 提交后下一批必须沿 TEX/container orientation → upload/crop → physical/mapped UV → sampler → consumer 查公共根因，不得写 sample/layer/path/hash 分支。
- 在该 Opacity checkpoint，R4-2 只完成普通 Opacity 子集，Tint、Transform、Film Grain 与其他 ordinary material family 当时仍待后续独立波次；后续 Tint 与 Film Grain stock/no-mask 进展见下文。R4-3/R4-4 当时未开始，当前 R4 总体仍未完成，R5 未准入。

#### 2026-08-08 R4-2 resolved-material texture orientation regression closure

- 回归只出现在普通 Opacity 迁入统一 executor 后：公共 authored vertex wrapper 把同一组 coordinates 同时作为 texture UV 与 Metal full-target quad 几何，错误假定纹理 V 轴和 clip 几何 Y 同向，使 resolved-material 离屏 pass 每执行一次就垂直镜像一次。现役实现保持 `a_TexCoord` 不变，只对生成 `a_Position` 的几何 Y 做 `1-v`；没有改变 TEX/PNG/视频上传、physical/mapped extent、sampler、layer world transform，也没有样本、layer、路径或 hash 分支。该合同与 Mirage clean-room 资料中 source draw、effect pass、final composite 分层保真方向一致，但没有复制第三方源码或算法表达。
- `test_scene_resolved_material_pass_encoder.py` 的 GPU 输入改为红/绿/蓝/黄四象限 2×2 纹理，并逐字节断言输出行序，旧的同色集合断言不再能漏过垂直镜像。聚焦 GPU 门通过；统一 inner 门通过；Scene 全量 **188 modules / 135.7 s / ALL OK**；code health **849 Swift / 44 locked legacy / 400-line limit** 与 `script/build_and_run.sh verify` 的 `BUILD SUCCEEDED` 通过。
- 定向隔离报告 `.codex/scene-texture-orientation-r4-targeted-20260808-v3/report.json` 为 **2/2 PASS**：`3088601835` / `3743305891` loaded ratio 均 `1.0`、failed frame / drawable miss 均 `0`、sample-root residue 为空；resolved layer `54` 与视频 layer `23` 分别完成 claimed/encoded/GPU `64/64/64` 与 `6/6/6`，executor/graph/legacy conflict 均无失败。人工比较 Opacity 迁移前、回归后与本批 after 截图，确认前者后帽/兜帽重新贴合头脸，后者整体恢复头朝上。报告 SHA-256 `47c76a39eb4ad0e8bcce31af7f0b00fabcd7f3a2be32125483017b87f5ade917`。
- 这只闭合公共 resolved-material pass 行序和两个用户报告的方向回归，不证明所有 TEX、视频、effect、跨 API 坐标、Windows 同相位像素或 Wallpaper Engine 等价。该方向批没有升级 fixed13/full45：非对称 GPU 门与两个真实受影响样本已直接覆盖共享风险，扩大矩阵不能提供更强方向性证据。按当时用户要求，该批在提交、证据同步和临时产物审计后停止；后续 Tint 与 Film Grain stock/no-mask 进展见下文，Transform、R4-3、R4-4 与 R5 当前仍未闭合。

#### 2026-08-08 R4-2 ordinary Tint owner migration

- 普通 Tint 现在与 Opacity 共用同一个 owner-yield 合同：旧 dedicated plan 只在 ShaderContract → Template → Program 对整条 authored stage 完整编译成功时让出产品 owner；Program 失败、logical target、多 pass、未迁移 sibling 或整链不完整时继续由既有 bounded planner/pipeline/renderer 承担 fallback。同一 authored chain 不拆给两个 executor，也没有 sample、layer、path、hash 或 Workshop ID 分支。
- fresh full45 中 `2134765860`、`2902406982`、`3122339805`、`3768903841` 分别有 `1/28/11/1` 个 Tint exact subject 迁入统一 executor，共 **41** 个 Tint subject / 41 个 layer；`2134765860:206` 同链前置 Water Waves 也因 Tint blocker 解除而进入同一 Program。`1937925563`、`3769688830` 等 mixed/unmigrated chain 继续由旧 Tint fallback 执行。当前 full45 合计 **14 个样本 / 57 个 resolved layer / 75 个 exact subject** 由 `resolved-material-graph` 完成。
- fixed13 首轮同时暴露矩阵 owner override 陈旧和一个公共 lifecycle 回归：Tint 让出旧 catalog 后，host 仍只从旧 catalog 计算 live property consumer，导致 `2902406982` 的 `newproperty50` 更新整体拒绝。launch 现在合并 unified capability 投影的 user-property dynamic uniform target；只接受唯一 user-property producer，Timeline、SceneScript、多 producer 与未准入 Program 继续失败关闭。三样本恢复门 **3/3 PASS**，最终 fixed13 `.codex/scene-tint-r4-2-milestone-fixed13-20260808-v2/report.json` **13/13 PASS**。
- integration selector 对当前源码运行 Scene 全量 **188 modules / 136.5 s / ALL OK**，code health **849 Swift / 44 locked legacy / 400-line limit**，`script/build_and_run.sh verify` 为 `BUILD SUCCEEDED`，四个迁移样本 **4/4 PASS**。最终 full45 `.codex/scene-tint-r4-2-milestone-full45-20260808-v4-final/report.json` 为 **44/45，非 PASS**；唯一红项仍是 `2067939514` 的 `particle candidate count mismatch` 与 `particle skipped transparent count mismatch`。executor claimed/encoded/GPU `2084/2084/2084`、failure `0`，graph diagnostic/failed/GPU failed 与 failed frame/drawable miss 均为 `0/0/0`、`0/0`。报告/full matrix/fixed13 suite SHA-256 为 `fb5b0c36d0bc9117a056f020edc53c51298f827992a3f9ccf1d080d05eb5154d` / `70392048d1bac3d770f5ccdf0879573bcc4b22145a2fafb907541506632ceb70` / `fcbc573fbfe7b38a360b87f7b9a99cb26f04fb04e043a5ce5f500f1ae6505bb1`；App executable SHA-256 `1f0fefb474e242259fe9584632b07e59ab6192b5ad48759292ebdd312363caf7`、CDHash `8596ab9bb260523720a4604a324048f60c458652`、Team `H9QWU9XN8R`，签名前后 verified。
- 这只迁移 Program-compatible Tint 子集；旧 Tint planner/pipeline/renderer 仍服务 mixed/unmigrated fallback。在该 Tint checkpoint，Transform、Film Grain、其他 ordinary family、R4-3、R4-4 与 R4-5 仍待后续波次；Film Grain stock/no-mask 的后续迁移见下一节，mask/其他 revision仍未闭合。44/45、非黑输出、相同 owner 集合与 preview 指标都不证明 Windows 色彩/像素或 Wallpaper Engine 视觉等价；R4-2/R4 未完成，R5 未准入。

#### 2026-08-08 R4-2 Film Grain stock/no-mask owner migration

- 先按官方职责核对而不是从旧项目类型反推：Film Grain 是普通 image effect，路径为 ordered material pass → authored shader/source graph 与 `common_blending.h` helper → current framebuffer + stock noise + optional mask → `g_Time`/slot resolution/common uniforms → Program/pass executor → layer-local ping-pong → final composition。官网公开作者参数、`g_Time`、physical/mapped resolution 与 header职责；合法 stock metadata和 Mirage D级结构交叉确认 current revision 的单 pass、exact `util/noise` default 与 optional mask，但不提供私有 shader数学或 Windows golden。本批材料已足够，无需启动 Ghidra，也没有复制官方/第三方 shader、payload、纹理或算法表达。
- 公共缺口不是“缺 Film Grain renderer”，而是 generic schema不能证明 untyped auxiliary stock default 的 purpose，导致旧式未标注 `g_Texture0` 无法安全投影为 implicit framebuffer。现新增 closed stock registry，当前只登记 exact `util/noise -> .noise`；显式 mode/material purpose优先，和 registry冲突时返回 unproven，未知 default不解锁。Program finalizer从同一 immutable frame/resource snapshot原子保留 slot 0 graph与slot 1 noise的reference、registry identity、selection provenance、purpose、generation、physical/mapped、sampler/raw flags和独立texture atom；没有effect/sample/layer/path pattern/hash分支。
- `.filmGrain` 从 pair-only dedicated leaf优先集合移除并加入 Program-yield合同：整条 authored stage完整编译成功时由 unified capability/executor唯一持有，失败、整链不完整或 unsupported topology继续由旧 planner/loader/pipeline/renderer bounded fallback，同一 stage不双 owner。项目自有门覆盖 exact stock purpose、purpose冲突、registered/unknown default、implicit framebuffer与双texture atom；Film Grain planner/loader/rendering **1/1、1/1、1/1**，framebuffer **44/44**，capability **5/5**，统一 inner **49 modules ALL OK**。integration selector为 Scene **188 modules ALL OK**、code health **851 Swift / 44 locked legacy / 400-line limit**，`script/build_and_run.sh verify` 为 `BUILD SUCCEEDED`。
- `.codex/scene-filmgrain-r4-3-integration-20260808-v2/report.json` 对 `3767460992` / `3747492842` **2/2 PASS**，报告 SHA-256 `e77eb350f58f0b63ceeb9361a5ef14625a2805250f32ba12d8f4abecc915e2de`。正例 `3767460992:20#effect#702` 是唯一 `admitted-generic / resolved-material / program / strict-generic` owner，frame 0与next-frame均由 `resolved-material-graph` 编码并被 final compositor消费；layer 20前置stage顺序、physical ping-pong与publication generation连续。负例 `3747492842:434#effect#545` 仍 `not-admitted / prefix-omitted / omitted-by-strict-chain`，没有被Program误接管。
- 45样本 Program census `.codex/scene-filmgrain-r4-3-program-census-20260808-v1/report.json` 只有上述两个 Film Grain subject；Template **1392/8**，Program因没有 runtime snapshot为 **1400 notAttempted**，不是失败。报告 SHA-256 `c8d046780e3608acfd7d1293710f0864988b13a2500b7a5ac1089e8d1b95f472`。fresh full45 `.codex/scene-filmgrain-r4-3-milestone-full45-20260808-v1/report.json` 为 **44/45，非 PASS**，唯一红项仍是 `2067939514` 的既有 particle candidate/skipped-transparent偏差；报告/full matrix/fixed suite SHA-256为 `530156142934a2583ecb0219e83d9df50853878e20da197f348a144ac7ecca2d` / `4bba1108463593bb5528f910528b4db20ca7f634fd706a7776809b9fdda6da82` / `86f654ce55e4f85338e6e246804f64d1339b06d65ac8b05073bde1581136ccb1`。fixed suite只因 base digest变化按 expand/compact合同再生，没有重复运行13样本。当前 aggregate仍为 **14 samples / 57 layers / 75 exact subjects**，Film Grain只把一个 subject从 dedicated family转为 resolved-material family；executor claimed/encoded/GPU `2458/2458/2458`、failure `0`。
- 该波次只迁移 stock/no-mask current variant。MASK/opacity texture、其他 greyscale/blend/revision、未知 stock default、任意 path-to-purpose、logical target/multi-pass、unsupported mixed chain、官方噪声/混合数值、Windows动态/像素与Wallpaper Engine视觉等价仍未闭合。旧 dedicated fallback仍可达，因此 Film Grain family、R4-2/R4均未完成，R5未准入。

#### 2026-08-09 R4-3 authored Program 九段链 checkpoint

- `3766387484:17` 的九个 active effect stage 原本都能形成 resolved Program，但 Workshop Iris 的作者语句 `vec4 × vec2 × vec2 × scalar -> vec2` 被严格 Metal类型拒绝，导致整层 Program从未进入GPU。共享 frontend现只对静态可证明的浮点乘除链执行 HLSL分量缩窄：先按最小参与向量宽度缩窄较宽操作数，再按赋值或函数参数目标继续缩窄；歧义表达式保持失败关闭。vertex/fragment同名uniform改用stage-qualified Metal ABI，host仍按作者名/type统一解析，没有sample/layer/effect/path/hash分派。
- 同批补齐same-slot mix graph、bounded loop/source、sampler purpose、effect projection正逆矩阵与`g_ParallaxPosition`。Foliage Sway、Water Flow、Depth Parallax及Light Shafts旧plan都只在完整Program成功时让权；`3766387484:17` 的Foliage → Water Flow → Shimmer → Iris → Depth → Twirl×4现全部为`admitted-generic / resolved-material / program / complete`。本checkpoint当时的Light Shafts断点已由下一小节继续闭合。
- v25隔离门又发现Camera Parallax关闭时host仍无条件发布pointer smoother给Depth；frame context现按作者开关归零parallax，同时独立保留raw pointer。v26/v27两份相反极值指针运行各有18个成功graph transaction、terminal/compositor/next-frame、executor claimed/encoded/GPU大于0、diagnostic/GPU/failed-frame为0且三相非黑；脸部配准为`(0,0)`，两眼相对方向一致。两份报告只因故意未更新的临时矩阵旧精确计数锁而为非PASS，正式fixed/full矩阵未改也未运行。
- 该checkpoint只闭合当前可证明的单pass authored Program链与视觉方向门；其他HLSL隐式转换、logical target/multi-pass/history/compose、其他R4-3/R4-6对象路径和Windows同步像素仍未完成。Light Shafts follow-up见下一小节，不能据此进入R5。

#### 2026-08-09 R4-3 Light Shafts authored Program owner migration与combo-default修正

- 九段链闭合后，v38/v39把layer80的剩余阻塞精确定位为官方stock source中的`mat3 inverse(...)`、`inout vec3`与`BLENDMODE`值语义。文档库中的官方source/prelude和合法语料证明这些表达式应可运行，Mirage只交叉确认WE使用HLSL frontend处理混合方言；最初v42据此使用了“require-inactive ordinary-code zero”，但该临时规则没有官方player证据。
- 随后按既定顺序对官方2.8.42 `wallpaper64.exe`做bounded clean-room Ghidra复核，确认normal material-pass链保留material显式值，否则把active annotation的有效`default`写入统一compile map，再由define emitter进入WE HLSL translator与动态加载的`D3DCompile`；JSON `require/requireany`不参与player compile-map剪枝。现役实现因此保持Template explicit-only，由active schema验证全部同名default/options并统一供给条件、definedness、ordinary source和variant/prepared identity；missing-needed、conflicting、malformed继续失败关闭，sampler/format resource requirement独立求值。资源侧仍把13种已证TEX format、exact stock gradient/noise purpose、candidate format/sampler/UV与premultiplied output原子纳入同代Program。没有sample/layer/effect/path/hash算法分派。
- 真实`3766387484:80#effect#81`只显式写`DIRECTDRAW=1, RENDERING=1`，`RAYMODE`取default0，所以是Linear/Gradient而非旧文档所写Radial/Color。最终源码v48仍让它与layer17九段链同由`resolved-material-graph / program`执行：报告**1/1 PASS**，layers`[17,80]`取得20个terminal success / 20个成功transaction、GPU/compositor/next-frame与零graph diagnostic，executor为`170/170/170/0`，三相截图非黑，before→hover changed ratio`0.503683`。但`BLENDMODE 31`在该direct-draw零base分支与旧值0代数等价；截图中的宽幅暖橙/蓝白光带和整幅运动分布仍不正确，不能把本批写成光效或完整样本视觉修复。头发显得整块移动可能只是其他人物区域、双眼、Water/Shimmer/Depth/Twirl和光线缺失后的相对现象，后续验收必须按作者完整运动系统进行。
- frontend **41/41**、Program finalizer **8/8**、derivation/pass **1/1、1/1**、capability **6/6**、graph publication **2/2**、color contract **15/15**、preprocessor **3/3**、variant environment **1/1**、Template **5/5**、preparation census **3/3**、code health **856 Swift / 44 locked legacy / 400行**与签名build verify通过。本批不改正式矩阵、不跑fixed13/full45；其他Light Shafts revision/combo/topology、logical target/multi-pass/history/compose、完整画面动态及剩余旧owner仍未闭合，R4-3/R4未完成，R5未准入。

#### 2026-08-09 Scene Camera Shake bounded camera-frame checkpoint

- `3766387484` 的 `general` 明确开启 Camera Shake，但旧解析链只保留 Camera Parallax，四个 shake 字段在 `SceneDocument` 就被丢弃；因此此前即使九段Program与Light Shafts transaction全绿，整个Scene仍缺少作者定义的全场相机运动。该断点解释的是全画面共同运动缺失，不是“头发专项”或任一局部effect的替代修复。
- 按资料优先级，对哈希匹配的官方2.8.42 `wallpaper64.exe`和同包`wallpaperui.exe`做bounded clean-room Ghidra复核，确认author defaults/editor ranges、absolute scene-time确定性求值、eye/center同位移、orthographic authored-height尺度、真正perspective Scene的独立XYZ分支，以及base/path camera先与shake形成唯一working camera、parallax只读其XY且shared view也由同一状态构建的数据依赖。Mirage固定revision只支持“shake属于共享camera frame”的架构交叉；其min-dimension幅度和perspective suppression与官方证据冲突，未被照搬。仓库没有复制反编译表达、官方payload或GPL实现。
- 公共链现从`general` typed parse进入descriptor与有界admission，每个surface/frame只生成一个shake-adjusted camera frame，并把同一camera交给scene renderer、particle投影、pointer反投影和parallax。当前只准入有有限正数authored projection width/height的orthographic Scene；真正perspective Scene、畸形/越界参数继续失败关闭。particle `flags=4`只选择下游perspective VP，不会另算一套shake；属性修改当前通过rebuild重新解析，不冒充live target或SceneScript setter。
- author-on v49 `.codex/scene-camera-shake-3766387484-20260809-v49-positive/report.json`为**1/1 PASS**，报告SHA-256 `c8319a9be8f3a7ef8d9990b253f1f4d117ca29b2ea45c6def9224c572940d9d4`；property override关闭的v50 `.codex/scene-camera-shake-3766387484-20260809-v50-disabled-control/report.json`同为**1/1 PASS**，SHA-256 `ed5812c2ca7db1e9b59c24fee2dd60f88399df9b7b3b4c96815f770f476f49cb`。两次均有20个Program transaction、GPU/compositor/next-frame、零graph diagnostic与非黑截图；这些计数只证明其余chain健康，不是shake调用计数。全图与四象限高梯度配准中，author-on ready→after一致约为`(-4,+1)`像素，而author-off四区均为`(0,0)`，证明新增贡献是全场共同相机平移而非头发mask。
- Camera Shake、particle camera、parallax、property routing、frame-context、解析与benchmark定向门全部通过；code health为**859 Swift / 44 locked legacy / 400行**，签名build verify为`BUILD SUCCEEDED`。本批未跑fixed13/full45。真正perspective Scene、Windows同相位数值/像素、官方pause/seek策略与`3766387484`其余人物区域、双眼、Water Flow/Shimmer/Depth/Twirl、叶片/粒子、Light Shafts相对幅度和合成仍未闭合；Camera Shake不撤销旧effect owner，也不完成R4或准入R5。

#### 2026-08-09 R4-2 stock standalone Blend Program owner migration

- 先对现役文档和`2067939514`真实graph做只读census：45样本共有40个Blend subject、36个visible subject，至少包含dynamic visibility、media thumbnail、非零blend mode与多段chain等互不等价形态；本批只选择独立layer`342`的exact stock单pass形态。它使用`BLENDMODE=0`、`multiply=1`、slot 1 authored asset与`custombackground` property override，effect visibility静态true；生产准入不读取sample/layer/effect/path/hash。
- 根因不是Blend shader或纹理加载器缺失，而是旧`.blend` dedicated plan总是先持有owner，使已能完整形成的resolved-material Program从未取得claim。现将`.blend`加入共享Program-yield合同：完整Program成功时由`resolved-material-graph`唯一执行，失败、整链不完整或unsupported topology继续交回bounded strict fallback。同批项目自有frontend门锁two-texture RGB blend的straight/premultiplied边界，capability门锁yield与不双owner；`scene_shader_preparation_census.py`只同步此前拆分后遗漏的独立Swift source list，不改变产品语义。
- focused frontend **28/28**、capability **5/5**、Program finalizer **8/8**、pass/executor **1/1、1/1**、color **12/12**、Blend planner/loader **1/1、5/5**、最终checkpoint **26 modules ALL OK**，code health **861 Swift / 44 locked legacy / 400行**，签名`script/build_and_run.sh verify`为`BUILD SUCCEEDED`。定向v3对`2067939514`为**1/1 PASS**：layer`342` accepted，executor claimed/encoded/GPU `100/100/100`、failure 0，两次terminal success和两次成功transaction均被compositor/next-frame消费，graph diagnostic/GPU failure/failed frame为0，ready/after非黑且只见局部星点变化，没有全图翻转、黑帧或主体方向回退。
- v2按现役正式单样本matrix运行，因本次owner/count迁移与该样本既有particle ratchet而非PASS，保留为失败现场；v3只用临时定向matrix移除无关particle ratchet，正式fixed/full matrix未改，本批未跑fixed13/full45。报告与App身份见[E-EFFECT-BLEND-TRANSFORM](semantics/runtime-evidence-index.md#e-effect-blend-transform)。Transform候选因dynamic effect visibility、SceneScript audio scale及前置Blend/Precise Blur依赖暂不迁移；直接只换owner会重现“结构通过但画面不变”。其他Blend形态、Transform family、R4-2/R4仍未完成，R5未准入。

#### 2026-08-09 R4-2 Simple Audio Bars Program owner migration

- 提交`f009cdb9`把公共`material:"previous"`收窄为仅限当前effect input的typed graph-input alias，并增加单sample、normal blend、weight/alpha一致的straight-output静态证明；只有完整Program成功时`.workshopAudioBars`才让出owner。resolved Program variant的实际audio host uniform继续驱动采集需求，避免owner迁移后关闭输入。debug benchmark fixture也改为同帧发布16/32/64左右数组，旧16档重载导致64档全零的结构性假通过已由v4黑面板现场确认。
- `3122339805:64#effect#66`的`RESOLUTION=64 / SHAPE=bottom / TRANSPARENCY=replace / BLENDMODE=normal`现为`admitted-generic / resolved-material / program / strict-generic`。`.codex/scene-audio-program-r4-2-3122339805-20260809-v6/report.json`为**1/1 PASS**：claimed/encoded/GPU`12/12/12`、failure 0，首帧与next-frame transaction均由compositor消费且GPU completed，failed frame/drawable miss为0；错相局部截图肉眼确认66根紫色bottom条从低幅短柱增长为高幅长柱。v1-v5保留texture/color、旧matrix ratchet、64档零输入及同相位不足现场。
- 受影响自动门**105/105**、semantics **5/5**、code health **862 Swift / 44 locked legacy / 400行**与签名build verify通过；正式matrix未改，未跑fixed13/full45。composition`2938612768:563`与relocated 16-band profile的后续迁移分别见下方R4-4和relocated checkpoint；其他shape/transparency/blend/AA/topology仍保留bounded fallback或fail closed。这一节只闭合当时的ordinary Audio Bars Program子集，R4-2/R4仍未完成，R5未准入。

#### 2026-08-09 R4-4 utility composition main-target Program source migration

- 现役文档已明确composition/project/fullscreen消费的是此前已绘制的主framebuffer，而不是普通layer source；本批因此未启动Ghidra。旧路径虽然能capture utility layer，但完整resolved Program此前只准ordinary source，导致`2938612768:563`即使可编译仍由`.workshopAudioBars`持有产品owner。
- capability现增加通用、有界的`.capturedMainTargetTexture` source route，只接受内容类型匹配、可见、无child、dependency ownership为显式`.none`，且每个resolved material launch variant都有active audio-spectrum host consumer的完整Program；shape不确定、非audio utility Program、named/backward dependency或unsupported dedicated leaf均在claim前失败关闭。utility runtime plan为已迁移layer保留作者排序与触发点，frame preflight复用`SceneCaptureGeometryResolver`并在该层执行时把当前drawable作为source，把同一resolved frame target plan交给统一executor；compositor最终alpha只应用一次。实现不按sample/layer/effect/path/hash分派，也不提前复制空/旧framebuffer。
- 跨样本`3299228616`基线揭示仅按utility shape会把layer387的active Scroll误准入，产生官方preview与旧运行都没有的深色矩形拷贝；该结构绿、画面错的现场保留。新增`utility-source-program-unsupported`负门后，非audio Program在claim前拒绝，不能把这一错误计为新能力或刷新矩阵。
- 最终源码隔离`.codex/scene-utility-program-r4-4-2938612768-20260809-v3-final-audio-gate/report.json`为**1/1 PASS**（报告/临时matrix SHA-256 `d7bba00b144533887441f3ec49775c175b6f5b8ca0d8993b399226a345f5ed72`/`e550830e4a9d0dc656aae4f9b784bcf4da40e5f42dab4b6a5d0e9538ff257154`）：layer563与390均由resolved-material成功，executor claimed/encoded/GPU`142/142/142`、failure 0，6个成功transaction覆盖GPU/compositor/next-frame，graph diagnostic/failed outcome/GPU failure为0。105/104帧submitted/completed、driver`60.034 FPS`。ready/after非黑，肉眼可见底部15根黑色音频条从短横线增长为竖向柱，主图crop/placement正确。跨样本`.codex/scene-audio-relocated-r4-baseline-3299228616-20260809-v3-utility-negative/report.json`亦为**1/1 PASS**：layer387的active Scroll恢复`not-admitted / rejected-chain / unsupported-stage`，resolved集合精确为`[303,601]`，无误准入矩形；这些都不是Windows同步像素golden。
- 受影响capability/utility/framebuffer/runtime bridge/executor/publication/authored execution/dynamic/frame-context/live-routing共**124/124**，code health **862 Swift / 44 locked legacy / 400行**与签名build verify通过。本批未改正式matrix，未跑fixed13/full45。该checkpoint时relocated 16-band仍未迁移，后续见下一节；带child/dependency的composition、未证project/fullscreen、其他utility/dependency与legacy owner仍未迁完，R4-4/R4未完成，R5未准入。

#### 2026-08-09 R4-2 relocated 16-band Audio Bars + zero-distortion Fisheye chain migration

- 现役文档、官方样本source与既有dedicated renderer已共同给出exact语义：`RESOLUTION=16, SHAPE=9, ANTIALIAS=1, BLENDMODE=31, TRANSPARENCY=4`使用left/right形成上下条，source-alpha intersect后additive输出，再按作者顺序接strict zero-distortion Fisheye。已有证据足以定位公共frontend/color边界，本批无需启动Ghidra；参考项目只保留其“WE依赖HLSL frontend隐式转换”的交叉证据，不复制实现。
- v1修复additive/intersect straight-output静态证明后仍因旧helper匹配过严被`colorContractUnproven`拒绝；v2成功准入但Metal在作者`uint barFreq1 = frequency % 16`处拒绝float `%`。现役frontend只为简单标量声明赋值、静态可证scalar type且至少一侧为float的整句显式生成`fmod`并按目标构造，compound/vector/歧义形式继续失败关闭；color analyzer也只接受root `A + B * opacity`、唯一sample、精确mix/alpha/weight守恒。最终premultiply不在乘alpha前夹RGB，保留additive高光能量；UNORM target仍负责存储范围。实现不按sample/layer/effect/path/hash分派。
- `.codex/scene-audio-relocated-program-r4-2-3299228616-20260809-v3/report.json`为**1/1 PASS**：layer151为`Program -> Fisheye zero-distortion`完整链，resolved `[151,303,601]`，executor claimed/encoded/GPU `114/114/114`、failure 0，10个terminal success/成功transaction覆盖首帧、compositor与next-frame，graph diagnostic/failed outcome/GPU failure、failed frame与drawable miss均为0。ready/after非黑，肉眼确认上排条向上、下排向下逐条增长，未出现整块矩形。报告/临时matrix SHA-256为`c3b0cd1221dbf9b8177a1c63bf8c350891da27da308863e5ab77b34989299e7a`/`fd4cab05a34267ca557689ebe13ee96b1c6461cc368821b0b54523f65c323365`。
- 共享premultiply回归`.codex/scene-r4-premultiply-regression-20260809-v1/report.json`对`2938612768`/`3122339805`为**2/2 PASS**，两者既有音频条仍逐条增长且无新增黑块/泛白/整层染色。frontend **33/33**、color **12/12**、Program derivation/finalizer **1/1、8/8**、capability **5/5**、authored execution **13/13**、chain planner **14/14**、pass/executor **1/1、1/1**、code health **862 Swift / 44 locked legacy / 400行**与签名build verify通过。正式matrix未改，未跑fixed13/full45；其他Audio Bars combo/topology、非零Fisheye、带child/dependency utility及旧owner仍未闭合，R4-2/R4-4/R4未完成，R5未准入。

#### 2026-08-09 R4-2 Simple Audio Bars dedicated owner retirement

- 三个旧Simple专用profile现在均有统一Program正证据：`3122339805:64`为ordinary显式64-band，`2938612768:563`省略`RESOLUTION`并实际使用默认32-band composition，`3299228616:151`为relocated 16-band stereo up/down后接zero-distortion Fisheye。现有文档、作者source与三次真实Program执行足以界定撤权范围，本批无需启动Ghidra；生产实现不再按Workshop路径、raw/canonical SHA、sample/layer/effect或旧combo tuple选择Simple算法，未知形态必须形成完整Program，否则整链失败关闭。
- 删除Simple专用planner/profile、Metal pipeline、renderer dispatch四个产品文件和两个只服务旧链的测试；同时移除compiler identity、probe、runtime映射、pipeline repository入口及simple-only execution plan字段。增强版Audio Bars仍保留自己的`.workshopAudioBars` backend与renderer，因此dedicated probe/compiler `32→31`，runtime backend `31→31`，legacy authority sites `7→7`。Scene Swift文件`588→584`、物理行`104565→103404`、小于3 KiB文件`191→192`、小于1 KiB文件`53→54`；这是完整类型族删除，不是压行或搬运旧switch。
- 专用owner删除后的`.codex/scene-simple-audio-bars-owner-retirement-r4-2-20260809-v1/report.json`为**3/3 PASS**（报告/临时matrix SHA-256 `ecc320b016d461a487778190a913c9f9e7962f3da1b04532abba67ea8ebe4211`/`03e0e0361fcf03aa847163b0989bbc4cdd53601e5462c15b211061a4e13166c5`）。三个样本executor claimed/encoded/GPU依次`148/148/148`、`996/996/996`、`159/159/159`，failure均0；成功transaction `6/24/10`，terminal/compositor/next-frame齐全，graph diagnostic/failed outcome/GPU failure/failed frame/drawable miss全0，旧Simple Audio Bars执行计数全0。ready/after均非黑：默认32档黑条与64档紫条从短柱增长为独立竖柱，relocated 16档仍上排向上、下排向下，无整块黑矩形、泛白或整层染色；这不是Windows同步音频或像素golden。
- semantics **5/5**、chain planner **14/14**、authored execution **13/13**、pipeline repository **1/1**、audio demand **8/8**、utility layers **11/11**、framebuffer capture **44/44**、resolved-material capability **5/5**、code health **858 Swift / 44 locked legacy / 400行**及签名build verify通过。正式matrix未改，未跑fixed13/full45。该checkpoint只撤销Simple Audio Bars家族旧owner；其他音频、utility、dedicated/legacy owner仍可达，R4-2/R4未完成，R5未准入。

#### 2026-08-09 R4 mixed-chain resolved-prefix与增强版Audio Bars交叉修正

- 下一候选Spin的首轮试验暴露了典型“结构全绿、画面全黑”：layer17/79的首个active stage是dedicated Audio Hue Shift，Spin让权后capability仍接纳dedicated-first mixed chain；同时上一项把同名`.workshopAudioBars`从dedicated-leaf集合移除，使独立的增强版Audio Bars所在layer945丢失。v1 resolved `[17,20,79,994]`、claimed/encoded/GPU `24/24/24`、failure 0、34个成功transaction且无diagnostic，但ready/after只剩中央占位图标，changed ratio 0、flat-border 1。该失败现场保留，证明transaction成功不能替代视觉验收。
- 现役实现恢复仅增强版Audio Bars的dedicated leaf并从Program-yield集合移除；Simple专用profile仍保持删除。公共capability要求首个compiled active stage必须resolved，dedicated-first/以dedicated开头的交替链以`mixed-chain-resolved-prefix-required`失败关闭；resolved-first后接bounded dedicated leaf仍允许。Spin试验让权撤回，故本批不是Spin迁移。
- 修复后`.codex/scene-mixed-prefix-enhanced-audio-r4-20260809-v2/report.json` **1/1 PASS**：layer17/79回到dedicated fallback，layer945增强版Audio Bars恢复为resolved mixed leaf，resolved `[20,945,994]`、claimed/encoded/GPU `18/18/18`、failure 0，32个terminal/成功transaction且无validation failure。ready/after是完整彩色旋涡，changed ratio `0.90495`，肉眼可见多个局部旋转中心方向变化，无全黑或整层静止。26个focused模块ALL OK、code health **858 Swift / 44 locked legacy / 400行**与签名build verify通过；报告/临时matrix SHA-256 `d7e501c3d6eb95b5734ff68f456468c9a45805b24c56667101ef2d0c5fa571f1` / `f816aeac6549d3d89ab4a4ad391e04aa30b872f5bd43e62124b28d5fd60a77ae`。未跑fixed13/full45，R4未完成、R5未准入。

#### 2026-08-09 R4-2 Workshop Audio Hue authored Program与专用owner撤权

- 现役资料先解释了真实阻塞：Workshop `2193274282/hue_shift`作者source使用`vec4/vec3`混合的built-in `mix`，官方语料本身可运行；Mirage固定revision只作其HLSL frontend会处理WE隐式转换的独立交叉验证。资料已足够约束项目的有界规则，本批没有启动Ghidra，也没有复制参考实现。frontend只对built-in `mix/lerp`的独立浮点向量参数按共同最小宽度缩窄，user-defined/复合/歧义形态继续失败关闭；preprocessor后零引用的非sampler uniform不再进入ABI，实际引用与sampler不放宽。color analyzer只开放保持原alpha的root RGB mix。
- v1至v4依次保留color contract、finalizer、精确`g_ModelViewProjectionMatrixInverse` dead-uniform与Metal `float4/float3 mix`失败现场。v5首次证明作者Program可以GPU执行；随后删除Audio Hue专用planner、plan、renderer/backend及只服务旧路径的dispatch/mock。probe/compiler/runtime backend `31→30`，hardcoded expected SHA `237→233`，numeric Workshop selector `57→50`；Scene Swift `584→582`、LOC `103404→103271`。
- 删除后`.codex/scene-audio-hue-program-r4-2-3767460992-20260809-v6/report.json`为**1/1 PASS**：Audio Hue layers 17/20/79/945均为`strict-generic / resolved-material / program`且Program hash一致；resolved `[17,20,79,945,994]`，claimed/encoded/GPU `30/30/30`、failure 0，48个terminal/成功transaction覆盖GPU/compositor/next-frame，graph diagnostic与failed frame为0。报告/临时matrix SHA-256 `e4b4a66923e54ec8a0eb17abbfadff0b9b3f55d9b7c527c3e8bd27e82528a333` / `876d7d28905855e6f959824b618a2861dfb6da899e5d09c43cf225a144b0e376`。frontend **34/34**、expanded focused产品门通过、census **3/3**、code health **856 Swift / 44 locked legacy / 400行**与签名build verify通过；未跑fixed13/full45。
- 视觉验收明确不通过整景门：ready/after非黑且色相/相位变化明显，但中央仍是`X`占位资源、背景全局强扭曲，人物各区域、双眼与光照特效都没有达到作者完整系统的预期。当时后续仍需按作者顺序定位Spin、Procedural Noise、Scene Camera Shake与资源/光效链；其中bounded Scene Camera Shake现已在独立checkpoint闭合，但不能追溯证明本项或其他局部effect正确。R4-2/R4仍未完成，R5未准入。

#### 2026-08-09 R4-2 Spin authored Program与专用owner撤权

- 资料顺序先命中现役官方stock资产：`spin/effect.json`、material、vertex/fragment source已完整描述当前样本的单pass framebuffer输入、作者vertex坐标、`g_Time`、texture resolution、参数和combo。旧planner仅按四组SHA接受`ELLIPTICAL=1 / NOISE=0 / REPEAT=1 / MASK=0`，旧Metal pipeline是固定近似；统一Program已经能完整编译并执行同一作者source，因此没有新增Ghidra或参考实现取证。
- 第一轮在旧owner仍存在时，layers 17/20/79/945的Spin均转为`admitted-generic / resolved-material / program`，executor claimed/encoded/GPU `50/50/50`、failure 0，48个成功transaction且无graph diagnostic；正式full45旧owner/count/SHA断言如预期不匹配，报告保留作迁移前正证据。随后删除`SceneAuthoredSpinPlanner`、execution plan、`SceneSpinPipeline`、renderer extension、compiler/backend/chain/repository/reporting接线及两个专用测试，unknown Spin只能完整形成Program或失败关闭。probe/compiler/runtime backend `30→29`，hardcoded expected SHA `233→229`，Scene Swift `582→578`、LOC `103271→102664`。
- 删除后`.codex/scene-spin-program-r4-2-3767460992-20260809-v6-owner-retired/report.json`为**1/1 PASS**：四个Spin和四个Audio Hue stage均保持Program，resolved `[17,20,79,945,994]`，claimed/encoded/GPU `30/30/30`、failure/deferred 0，48个terminal/成功transaction覆盖五层GPU/compositor/next-frame，graph diagnostic/failed outcome/GPU failure为0。报告/临时matrix SHA-256 `3ff94beeb3a69b261b44e26925425f553a0984b1a3ace8a91dd5d245215a07f2` / `0643feb07667a5373f64e4cf9ec14d7d79900fdce7832ee15c7183de6a7007a7`；签名App executable SHA-256 `6e2582eb74663d39c35bc2f7557cc300c215b2d1a723595947b6e25c4d2afc4d`、CDHash `fa6b10ed9bd1cf6d65e610d2d264acdf3dda7b04`、Team `H9QWU9XN8R`，签名前后verified。focused 73用例、code health **852 Swift / 44 locked legacy / 400行**及签名build verify通过；正式matrix未改，未跑fixed13/full45。
- 视觉仍不通过整景门：ready/after非黑、changed ratio `0.86204`，但角色结构仍被整幅液化，中央是`X`占位资源，人物各区域、双眼、粒子与光照效果仍不正确。Spin owner迁移只排除了“旧Spin近似未被替代”这一项；后续Procedural Noise与bounded Scene Camera Shake已有独立能力证据，但整幅作者系统仍须按Water Flow/Shimmer/Depth/Twirl、叶片/粒子、Light Shafts及相对幅度/合成逐项验收。R4-2/R4仍未完成，R5未准入。

#### 2026-08-10 R4-A recovery retirement、R4-C rejected-graph neutralization 与 PreparedStage 静态合同

- R4-A 已删除 Iris terminal suffix、X-Ray prefix、Cursor Ripple isolation 与 Shine isolation/rebase 四类会省略兄弟 stage 的 partial recovery 产品路径及其 recovery-only 测试；schema3 的 `legacy-recovery-kinds` 已到 `0/0`。现役 `SceneAuthoredEffectChainAdmission` 只接纳完整 graph；任一 active stage 拒绝后，后续 stage 只记录稳定拒绝原因，不再形成可执行 prefix/suffix/isolation。
- R4-C 的 rejected-authored-graph neutralization 切片已落地：普通层与 utility 只要存在 chain admission rejection，就设置 `suppressesLegacyEffectFallback`，compositor 仅中和 `SceneEffectRuntimePlanner` 生成的 legacy effect plan/inputs，runtime disposition 记为 `authored-chain-<reason>` unsupported。它不抑制严格独立准入的 `SceneImageBlendRenderPlan` / `SceneImageBlendRuntime` source preparation，也不抑制 `SceneDependencyRenderPlan` / `SceneDependencyFrameRuntime` 的 typed named-target/dependency 路径；后二者保持独立 telemetry，既不提升 rejected authored-chain admission，也不恢复任何 unsupported sibling。没有 authored graph 的层不产生该 rejection，仍可进入旧 planner；完整 accepted graph 仍可由旧 whole-chain renderer 执行。GraphExecutor 的 `supportsUnifiedPairLeaf` 白名单仅有 Shift Hue、增强版 Audio Bars、Workshop Gradient、Workshop Shadow、Shake、zero-distortion Fisheye；Blend、Film Grain、Depth、Water 等不是统一 leaf。
- `d9f769de` 将统一 executor 的每个 material stage 固化为 `SceneResolvedMaterialGraphExecutor.PreparedStage`：同一对象持有 effect、graph、pair step、transition、program keys、frame/persistent resources、output resource 与 commands；prepare 按作者顺序验证并发布 stage output，encode 按同序编码 commands，stage observer 只在该 stage commands 之后触发。v51 Water/Shimmer stage-local 运行证据使用这一边界，仍是现役源码的最后一份 stage 像素证据；本静态合同同步没有生成新的运行报告。
- 旧 prefix/suffix/isolation、Tint/Film Grain/Opacity 等“拒绝后 bounded fallback”报告与矩阵数字保留为历史失败现场或像素 oracle，但其 authority 结论均已 supersede。R4-A+C 的 corrected full matrix 已按 v9 scoped runtime ledger 与最终 `2938612768` exact runtime 修正，fixed13 已用最终 A+C 快照 **13/13 PASS**；fresh full45 仍未用最终二进制重跑，不得宣称 full45 PASS、完成 R4 或准入 R5。

每个波次均以“公共 capability 接管、被替代 owner 同提交撤权、旧 exact/route 双写为零、跨样本或跨 revision 正反例通过”闭合。只增加新 executor 而保留旧默认 fallback 不算迁移。

1. **R4-0 权限冻结门（已完成）**：canonical executor调用点、legacy authority、main-pass writer、dedicated probe/compiler/backend、recovery、硬编码expected SHA与Workshop selector已进入现有layout/semantics机器门；schema3把规则明确分为`required`、`inventory`与`retirement`。inventory只ratchet、防止无说明增长，不是默认零目标；只有retirement参与R4/R5 completion state。未迁移的权限仍是R4工作，不得把冻结表述为撤权。
2. **R4-1 generic authored material（已完成）**：通用 frontend、implicit framebuffer、uniform、sampler、render state、color contract 与 Program 已覆盖原 authored-shader accepted subset；被 chain 遮蔽的 standalone 产品调用、旧 `.authoredShader` backend、旧 pipeline cache 与 Scroll exact profile 均已撤权，跨样本正反门与 authority ratchet 已闭合。
3. **R4-2 普通 material 能力族**：B1已建立逐stage Program-first与19类受限pair adapter；adapter只在Program失败且单node/无target/exact identity/readiness闭合时可用。B2已完成exact stock、单node、无logical target的X-Ray identity-output迁移；B3至B5已完成bounded non-legacy-compose Precise Blur、exact stock Standard Blur与exact stock Local Contrast logical-target stage迁移。后续继续处理其他multi-pass/logical-target，并在最后一个whole-chain consumer迁移后撤销compositor入口。rejected graph继续不得回落`SceneEffectRuntimePlanner`。
4. **R4-3 graph resource 与多 pass**：四类 omission/rebase recovery 已归零；Precise Blur的history-free non-legacy logical target/copy/swap、exact stock Standard Blur与Local Contrast的四pass/two-quarter-target映射已进入统一executor。继续闭合legacy compose、captured-main、含未迁移兄弟stage的atomic chain、未知combine/variant、其他logical target、persistent/history、clear/function/condition、compose pair、hazard、resize/reparse/reset generation，再迁移bloom/water/cursor/depth/xray/shine/godrays等族；完成后删除old chain renderer。
5. **R4-4 cross-layer/utility/dependency**：让 named target、dependency texture、clipping 与 utility composition/project/fullscreen 进入同一 graph scheduler；当前严格独立准入的 `SceneImageBlendRenderPlan` / `SceneImageBlendRuntime` source preparation 与 `SceneDependencyRenderPlan` / `SceneDependencyFrameRuntime` typed named dependency 仍分别拥有产品执行权和独立 telemetry，它们不是 rejected authored-chain admission 的一部分。完成本项时撤销这两类独立 owner、utility 对 old compositor/chain 的调用、legacy inline/offscreen planner/renderer 与 `SceneEffectRuntimePlanner` 的产品执行调用。最终 layer color blend 保留为共享 compositor 能力。
6. **R4-5 脚本与 source profile 去样本化**：Text、texture animation、media transition、Audio Bars exact source/asset profile分别迁到有界AST/interpreter、通用timer/event、typed source provider、SceneScript object/audio/instancing能力；未完成时保持unsupported/fail-closed，不再用exact profile近似。完成门是script/source hash profile selector、numeric/named Workshop runtime dispatch与固定profile行为分派归零。computed digest、cache/integrity/evidence identity和只用于fail-closed的declarative revision attestation可保留，但不得选择renderer、Metal算法、常量、topology或绕开typed program/executor。
7. **R4-6 对象路径统一调度**：Light Shafts 从 quad 特判直写迁入共享 effect/scheduler；Particle、SpotLight、Puppet、Video 可保留领域 runtime，但只能发布 typed source/draw packet 并共用 identity/frame/resource/lifecycle，不能成为 effect fallback 或样本 profile authority。所有 main-pass writer 必须进入显式 allowlist 并由公共 frame scheduler 唯一排序。

截至2026-08-11：**R4-A 已完成**；**R4-B1至B4已完成并独立提交**；**R4-B5 exact stock Local Contrast logical-target stage已由本批闭环**；**R4-C partial**；**R4-4/R4-D/R4-E未完成**。legacy-compose Precise Blur、captured-main/unsupported-sibling/unknown-combine Standard Blur、非stock Local Contrast、其他multi-pass/logical-target与X-Ray topology尚未迁移，whole-chain compositor入口、无图legacy planner、ImageBlend/typed dependency、Light Shafts fallback与script/profile selector仍可达。R4结束后R5只删除已经不可达的surface/adapter/observation与重复telemetry；发现行为迁移必须退回R4。

## 9. 下一动作

1. **已完成**：R0-C legacy direct/offscreen 实际编码点接入与 strict generic family 回连；pure reducer、legacy decision、framebuffer、authored execution、code health、App verify 与 Scene 全量均已重跑。
2. **已完成**：同一 8 样本动态门完成两次 10 秒与一次 20 秒复核，保留首轮 6/8 失败证据；exact/aggregate gap、CPU/route failure 与 shared frame status 已分别解释。
3. **已完成**：跨运行稳定性已核对并闭合 7 字段共享矩阵合同；不稳定 frame/canonical SHA 和未承诺稳定的 CPU/route count 均未注册。
4. **已完成但未通过**：首轮 full45 为 42/45，正确暴露一个合法空 execution 的 demand 判定错误和一个既有 X-Ray 灰屏缺口；矩阵未刷新。
5. **已完成**：公共 static demand、typed straight-albedo、embedded purpose 透传和 REFRACT 同源物理守恒已闭合；新签名 App 的 5 样本定向门、相关共享测试、Scene 全量与 verify 均通过，telemetry 保持 sticky。
6. **已完成**：修复后 full45 为 44/45；唯一红项是独立的 `2067939514` 粒子偏差。R0 scoped matrix 已按 45 admission / 45 disposition / 44 execution demand 刷新，刷新后正式 consumer 三样本门 3/3 通过；该结论不写成全矩阵 PASS。
7. **已完成**：R1 建立 dedicated 与 authored-shader 共享的 typed compile/admission result；34 项顺序、first-match、generic fallback、完整 program invariant 与有界失败报告均有门，现有 backend 像素路径继续作为迁移 oracle。
8. **已完成**：R2 建立 typed compatibility provenance、基于 `SceneResourceView` 的候选完整 source graph、include digest/source map、directive evaluator、typed variant environment 与 active frontend handoff；同名不同内容、未知版本/format/platform 语义保持可审计的 fail closed，没有新增按 effect/path/hash 分派的可见算法。
9. **已完成**：R2 只把 include/combo contract 准备到 active source/schema/cache identity；普通 authored pass 的 shader input/output color representation显式 unresolved，现役 generic renderer准入没有因预处理成功而扩大；独立阶段提交为 `57cc94dc`。
10. **已完成**：R3 把同代 texture/provider、active variant/reflection、uniform bytes、typed state与保守颜色合同原子编入 `SceneResolvedMaterialProgram`，并用45样本静态census、production一次性审计、完整Scene测试和四样本性能门验证；`gpuEncoded=0`，没有按effect/path/hash或样本ID分派，也没有宣称视觉修复。
11. **R4 partial checkpoint 已提交，R4 未完成**：raw graph capability admission、typed extent、whole-frame batch、frame/source transaction、显式 `CompositeOutcome`、统一 executor 与 GPU/compositor/next-frame evidence 已进入当前检查点；普通 image/solid/text、utility 与 standalone target 已统一 frame batch。R4-2 follow-up 又闭合通用 `shaderValue` dynamic target、resolved owner 归因、legacy-only defer/reject 隔离和 launch color 合同门。根因代表门 **6/6 PASS**，Scene 全量 **190/190 ALL OK**；fresh full45 为 **44/45，非 PASS**，唯一红项仍是既有粒子偏差。
12. **R4-2 bounded macro preparation checkpoint，owner 未迁移**：共享 preprocessor 现支持有界 function-like macro（普通/零参数、嵌套、宏作为实参、object alias 调用）和有界 object-like token sequence，并保持 variadic、stringize/paste、递归、引号、跨行 replacement、`#elif` 与预算越界失败关闭。45 样本 preparation 从 **93/728** 提升到 **116/728**，material census 的 R2 variant bootstrap 从 **340/1400** 提升到 **446/1400**，但 GPU admission 严格保持 **1/728**。四样本定向运行 **4/4 PASS**，统一 resolved graph 均为 `accepted=0`；因此本批只扩大公共 preparation 能力，没有撤销 Pulse、Audio Bars 或任何旧 owner，R4-2 仍未完成。
13. **R4-2 unified material graph ownership 性能/矩阵/lifecycle 已闭合，R4-2 未完成**：immutable bootstrap sampler 已改为 launch/cache-scoped，`1937925563` 恢复目标吞吐；七个 full45 样本共 22 层 / 68 stage 进入 resolved graph。`2131872317` 的 completion/revision 竞态由原 reservation identity 重验证闭合；定向 owner、fixed13 均 PASS，fresh full45 为 **44/45，非 PASS** 且只有既有粒子偏差。
14. **R4-1 authored-shader 产品 owner 撤权已完成**：旧 compiler/backend/plan/planner/binder/pipeline/renderer/Scroll profile 已删除，generic stage 不再计入旧 chain；七样本 accepted/exact backend/compositor/next-frame 守恒，负例零接管，authority ratchet 五轴下降。该结论不包含其他 dedicated/legacy/utility/audio owner。
15. **已完成：Opacity 后统一材质 pass 纹理方向回归**：`3743305891` 整体倒置与 `3088601835` 局部帽子/兜帽倒置已定位为公共 vertex wrapper 混用 texture UV 与 Metal quad 几何 Y；现役实现只分离几何坐标，四象限 GPU 门及两个隔离真实样本方向证据通过，没有样本 ID/layer/path/hash 算法分支；R4 仍未完成，R5 仍禁止启动。
16. **R4-2 ordinary Tint owner migration 已闭合，R4-2 未完成**：Program-compatible Tint 完整编译成功后由 unified executor 唯一持有，41 个 Tint subject / 41 层与相邻 Water Waves 进入同一 Program；该批次“mixed/unmigrated chain 保留 bounded fallback”只属 R4-A+C 前历史合同。现役有图路径必须整图完整 accepted，否则 rejected graph 中和 `SceneEffectRuntimePlanner` legacy effect fallback；无 authored graph 才保留旧 planner。owner 转移后的 live-property consumer lifecycle 已修复；当时 integration、fixed13 与 full45 均无新增红项，但这些数字不替代 R4-A+C 后 fresh full45。Transform、其他 ordinary family 与 R4-3/R4-4/R4-5 继续按独立波次推进。
17. **R4-2 Film Grain stock/no-mask owner migration 已闭合，Film Grain family 与 R4-2 未完成**：closed registry 只登记 exact `util/noise -> .noise`，旧式 implicit framebuffer与 stock noise从同一 snapshot进入 Program；正例由 unified executor唯一持有。R4-A+C 前 X-Ray 后缀省略与 rejected-graph dedicated fallback 已删除/失效；现役 Film Grain 不是 GraphExecutor leaf，完整 accepted graph 可走旧 whole-chain，rejected graph 不回落，无 authored graph 才可走旧 planner。当时 integration 与 full45 数字保留为历史证据，不替代 R4-A+C 后 fresh full45；不得因这一个 current variant进入R4-3或R5。
18. **R4-3 authored Program 九段链 checkpoint 已闭合，R4-3 未完成**：`3766387484:17` 的九段单pass authored chain已由统一Program/executor实际执行；HLSL分量缩窄、stage-qualified uniform ABI、effect matrix/pointer/parallax与Camera Parallax开关取得正反、GPU、compositor、next-frame和双眼方向证据。
19. **R4-3 Light Shafts当前Program正例与combo-default语义已闭合，视觉/family/旧fallback/R4-3未完成**：`3766387484:80`这一正例已从dedicated direct-draw转入authored Program；`mat3 inverse`、simple `inout`、有界`#elif`和官方2.8.42已证的active annotation default统一macro环境均有正反门，旧inactive code-zero规则已撤销。最终源码v48为PASS，但真实profile是Linear/Gradient，宽幅光带与整幅运动系统仍未视觉闭合；未形成resolved claim的quad目前仍可从旧single-stage Light Shafts计划直写main pass，所以不能把正例迁移写成family产品owner已撤权。其他revision/combo/topology、logical target/multi-pass/history/compose与剩余旧owner继续关闭；未跑fixed13/full45，不能进入R5。
20. **R4-2 stock standalone Blend Program owner migration已闭合，Blend family/R4-2未完成**：`2067939514:342`的完整Program由统一executor唯一持有，GPU/compositor/next-frame与非黑定向证据闭合。Blend 不是 GraphExecutor leaf；其他shape只能在无 authored graph 时走旧 planner，完整 accepted graph 可走旧 whole-chain，rejected graph 必须失败关闭。Transform因dynamic visibility、SceneScript audio scale与前置chain依赖暂停，不以identity copy冒充动态效果。
21. **R4-4 utility composition main-target source子集已闭合，R4-4未完成**：`2938612768:563`的无child/dependency composition Audio Bars现由统一executor在作者层触发点读取主framebuffer，dedicated owner已让权；GPU/compositor/next-frame及非零局部柱高方向门闭合。带dependency/child、relocated、project/fullscreen与其他utility/legacy owner仍按独立能力波次推进。
22. **R4-2 Simple Audio Bars ordinary 64-band Program正例迁移已闭合，family/R4-2未完成**：`3122339805:64`已由统一Program/executor唯一持有并取得64档非零输入下的可见柱高变化；`2938612768:563`的composition正例见上一条R4-4 checkpoint，且它实际是省略`RESOLUTION`后的默认32-band，不是64-band。
23. **R4-2 relocated 16-band Audio Bars Program链正例迁移已闭合，family/R4-2未完成**：`3299228616:151`作者Program现执行stereo上下条与additive/intersect输出，随后在统一链内顺序执行zero-distortion Fisheye；v3 GPU/compositor/next-frame与上下双向局部画面门闭合。非零Fisheye和未知combo/topology继续fail closed；正式matrix未改、未跑fixed13/full45。
24. **R4-2 Simple Audio Bars专用owner撤权已完成，R4-2未完成**：三个旧专用profile的Program正证据齐备后，Simple专用planner/profile/pipeline/renderer与旧链测试已删除；三样本删除后门3/3通过且旧Simple执行计数为0。增强版Audio Bars和其他音频/dedicated/legacy/utility owner不在本项范围，不能由此进入R5。
25. **R4 mixed-chain resolved-prefix安全门已闭合**：dedicated-first mixed chain曾产生GPU/transaction全绿但画面全黑，现以公共`mixed-chain-resolved-prefix-required`在claim前拒绝；增强版Audio Bars恢复为独立dedicated leaf，Simple owner仍保持删除。修复后`3767460992`彩色旋涡与动态恢复，失败现场保留。
26. **R4-2 Workshop Audio Hue专用owner撤权已完成，R4-2未完成**：有界`mix/lerp`分量转换、active-uniform ABI与alpha-preserving RGB mix使四层作者Program实际进入GPU；旧planner/plan/renderer/backend删除。截图仍有中央`X`、全局液化及人物其他区域、双眼、粒子/光效错误，不冒充整景完成。
27. **R4-2 Spin专用owner撤权已完成，R4-2未完成**：当前stock单pass四层Spin均由作者Program唯一持有，旧指纹planner、固定Metal近似、backend/renderer与专用测试删除；删除后GPU/compositor/next-frame门通过。其他combo及整景视觉仍未闭合；后续Procedural Noise与Scene Camera Shake证据不能替代Water Flow/Shimmer/Depth/Twirl、粒子和光线的像素贡献门。
28. **Scene Camera Shake bounded checkpoint已闭合，R4未完成**：正交Scene在作者开关、参数与投影均可证明时，每帧只求值一个全局camera frame并供renderer/particle/pointer/parallax共用；v49/v50的on/off全图配准锁定共同平移。真正perspective Scene、live/SceneScript、Windows golden及完整作品视觉仍关闭；该能力不撤销旧effect owner，也不改变R5准入条件。
29. **R4-3 Water/Shimmer stage-pixel checkpoint已闭合，R4未完成**：`3766387484`同帧stage 0/1/2/8 readback证明Water在七个目标秒产生约`1.0–1.22%`局部RGB贡献并逐秒变化，Shimmer在活跃相位只于右腕/饰带ROI增亮；二维项目自有GPU门另锁方向、时间、alpha与zero-mask。该证据排除两段“结构准入但未进GPU”，不证明整景、其他variant或Windows parity；永久产品代码没有保留磁盘capture系统。
30. **R4/R5 completion contract已纠正**：schema3把唯一入口、库存与待退役权限分开；29个compiler/backend case、229个SHA与50个numeric Workshop字面不再被误写成必须全部归零。R4 retirement 中 partial recovery 已到零，rejected-graph到`SceneEffectRuntimePlanner`的legacy yield已中和；ImageBlend source preparation、typed named dependency、legacy product planner、whole-chain product dispatch、Light Shafts bypass及script/profile behavior dispatch仍未到目标。R5零门是旧observation、whole-chain/standalone/frame-batch surface、fallback graph/provenance与重复telemetry。当前状态仍是`R4=partial / R5=not_started`。
31. **R5 准入门**：最后一个R4 retirement rule已到目标；新旧exact/route telemetry不双写；产品源码没有sample/layer/path/hash驱动的可见算法选择。准入前运行fresh full45：所有由本批owner/scheduler/resource/camera/composition/telemetry合同覆盖的断言必须通过且不得新增或扩大红项。只有红项已在本批前登记、sample/metric/reason/count/signature完全不变，且本批未触达该领域或共享上游时，才可记为unrelated baseline；它不单独阻断R4 owner收敛或R5纯整理，但full45 overall仍必须写为非PASS，禁止刷新期望、隐藏红项或宣称完整矩阵通过。若共享上游被触达或失败签名变化，该红项阻断准入；发布级overall PASS另属独立里程碑。R5此后只删除不可达脚手架、合并薄文件、同步权威文档和做最终证据收口，发现行为迁移缺口必须退回R4。
32. **2026-08-10 静态接手点**：R4-A 已完成；R4-C 只完成 rejected-authored-graph neutralization，未完成无图 planner 撤权。`PreparedStage`/v51 已登记为现役 stage 边界与最后运行证据；本轮没有生成新报告，R4-A+C 后 fresh full45 待整合者完成后补入。下一实现顺序仍是 R4-B、R4-C 剩余项、R4-D、R4-E；R4保持`partial`，R5保持`not_started`。
33. **2026-08-10 额度中断接手点（当前工作树未提交）**：独立的死观测清理已提交为`67ba4454`；R4-A recovery删除与R4-C rejected-graph neutralization仍保留在工作树，禁止把它们写成已落地主线。持久化接手目录为`.codex/scene-r4-ac-handoff-20260810/`：`293-v8-report.json` SHA-256 `9a20aa59d8907d41f251d3efcf30778ac8409b1c5f494f569c383acfead1ded4`证明293恢复ImageBlend 5个、named target/binding 2/2和flat-border `0.03865`；`full45-v9-report.json` SHA-256 `9639e657048663747ad2885db7c8ae2ab402c0f4114d89f394831f8209953300`为**39/45，非PASS**，11条失败中9条是错误broad-suppression矩阵的旧owner期望，另2条是既有`2067939514`粒子偏差。实际executor claimed/encoded/GPU为`1921/1921/1921`、failure 0、deferred 22，graph terminal/transaction `268/268`且diagnostic/GPU-failed均0。`corrected-full-matrix-candidate.json` SHA-256 `65fb988dd02bb2353e5157d108b16d94ed6eea31daf10c3178e91faf9e4561c6`已由该报告scoped生成，但**尚未写回正式矩阵**；`fixed13-expanded-desired.json`已把`2902406982:410`改为`unsupportedEffects`，尚未对新base compact或运行fixed13。full45二进制生成后，工作树又将utility `namedTargetLayerIDs`收窄为不按rejected consumer过滤，只有`test_scene_utility_layers.py` **12/12**覆盖，因此v9不是最后三行元数据修正的exact binary。下一接手者必须先保留三份DEBUG capability文件与三份authored-shader LOD文件不入本批，再用临时HEAD+精确补丁验证A提交快照、写回corrected full、compact fixed13、运行matrix/benchmark/focused/build verify和exact fixed13；通过后只提交R4-A+C因果链。随后按用户最新范围停止深挖算法：先改成**每stage Program-first，Program失败才选typed backend adapter**，再分pair-leaf、multi-pass/logical-target、utility/direct-draw、cross-layer四批迁入唯一GraphExecutor；R5只删除不可达旧链和治理目录，算法/官方视觉parity留到统一架构之后。
34. **2026-08-10 R4-A+C 恢复验证完成**：整合者在 detached HEAD `67ba4454` 上只重放 A+C 因果补丁，排除了三份 DEBUG capability 与三份 authored-shader LOD 并行文件。checkpoint 选中 **88 modules ALL OK**，milestone Scene 全量 **183 modules ALL OK**；code health 为 **851 Swift / 44 locked legacy / 400 行**，Developer ID 签名 build verify 成功。验证选择器同时修复删除测试仍被调度的问题，material Program census 补齐 `SceneShaderMalformedMetadataAdmission.swift` harness 依赖。corrected full matrix 已写回，fixed suite 对新 base 重新 compact；正式 `.codex/scene-r4-ac-fixed13-20260810-v1/report.json` 为 **13/13 PASS**，loaded ratio 全 1，failed frame / drawable miss / residue 均为 0，executor claimed/encoded/GPU `1004/1004/1004`、failure 0、deferred 10，graph terminal/transaction `126/126`且 diagnostic/failed/GPU-failed 均 0。`2938612768` exact runtime 保留 named consumers `7`、target/binding `2/2` 与 ImageBlend `5/5`。报告/full/fixed SHA-256 为 `fc413a320d3d133ea26f896fb9b83b85e647f3ab9901ebc796b0e8fab2f871d2` / `65fb988dd02bb2353e5157d108b16d94ed6eea31daf10c3178e91faf9e4561c6` / `d6c20cbe9b234931eb2092ce27a264c45cefb8af4c1f8b5d467d98c4a7bc0b8e`；App executable SHA-256 `b175d9f1f8b4585e906d82ccbcce5f108a8010932ce66cd3bae97dffddf8e91f`、CDHash `972cbd6798671445cdeb5c66f66b8f4c7354b55e`、Team `H9QWU9XN8R`，deep strict verify 通过。最终二进制的 fresh full45 未运行，v9 仍是 **39/45，非 PASS** 的校准现场；本项只闭合 R4-A+C，下一波仍从 R4-B 开始，R4 保持 `partial`、R5 保持 `not_started`。
35. **2026-08-11 R4-B1 Program-first pair chain闭环**：每stage先编译Program，失败段只在单node、无authored/logical target、exact EffectKey与typed readiness闭合时进入adapter；Program与adapter可交错。shared history-free pair 的物理 pair generation 与 chain allocation generation 已分离，publication 使用后者，避免提交前统一拒绝。精确 detached 产品快照 code health **853 Swift / 44 locked legacy / 400行**，签名 build verify 与 deep strict codesign 通过。fixed13 v4 原始报告 **8/13 PASS**，另 5 个仅为旧 owner/count 期望；13 个样本均有 ready/after 截图、完整 runtime evidence、GPU submission/completion，failed frames 为 0。按同一报告校准 5 个 owner/count 字段后，fixed13 合同为 **13/13**；最低 driver FPS `14.9973`（`3769688830`），不宣称性能或视觉 parity。B2 后续仍须迁移 multi-pass/logical-target，并在最后一个consumer迁移后撤销 whole-chain compositor 入口；exact X-Ray identity-output见下一项。R4 保持 `partial`，R5 保持 `not_started`。
36. **2026-08-11 R4-B2 X-Ray identity-output闭环**：exact stock、单node、无logical target的X-Ray已进入Program-first unified pair leaf。frame preflight按typed planner区分identity/render/unsupported；identity用Metal blit把input精确复制到stage output，render仍要求pipeline与匹配typed resources，unsupported继续失败关闭。`3757555836:69`的X-Ray、Water Flow、Water Ripple、Water Flow、Shake五段mixed链现由统一GraphExecutor唯一持有；定向v2为**1/1 PASS**，fixed13为**13/13 PASS**，executor `2863/2863/2863`、failure 0，failed frame/drawable miss 0。该门不覆盖multi-pass/logical-target、Cursor Ripple history、dependency、Light Shafts或full45；下一步仍在R4迁移这些公共合同，不能进入R5。
37. **2026-08-11 explicit LOD sampler frontend前置闭环，未撤owner**：bounded frontend只把built-in三参数`texSample2DLod`的直接sampler、可编译UV与number/唯一float identifier翻译为Metal explicit `level`，vertex/fragment正门都实际编译Metal；错参数数、间接/未知sampler、vector/matrix/compound/歧义LOD继续失败关闭，user-defined同名函数保持普通调用。Debug拒绝日志同时输出frontend source location/message与variant sampler/format failure，便于下一批从真实Program blocker选multi-pass/logical-target family。统一checkpoint为**25 modules / ALL OK**，代码健康**853 Swift / 44 locked legacy / 400行**，签名Debug build verify为`BUILD SUCCEEDED`。这只是公共编译前置，没有真实Workshop正执行、旧owner撤权或R4状态变化；fixed13/full45不因本项触发，R5仍未准入。
38. **2026-08-11 R4-B3 bounded Precise Blur logical-target stage闭环**：capability将exact `.preciseGaussian`、多node、非空logical target、history-free/non-unique、非captured-main的dedicated stage登记为独立`dedicatedGraphStageKeys`，不混入pair leaf；每stage仍Program-first，失败后才允许该typed graph adapter。GraphExecutor核对graph/pair node、state intent、logical mapping与terminal publication，复用现有strict Precise Blur pixel backend，不新增sample/layer/path/hash算法分支。owner迁移同时把SceneScript time-of-day consumer从新旧owner并集投影，避免Blend动态`multiply` producer随旧catalog撤权而丢失。Developer ID fresh正式矩阵单样本`2134765860`为**1/1 PASS**：resolved `[206,238,301,457]`，executor claimed/encoded/GPU `28/28/28`、failure 0、deferred 2，18个terminal transaction覆盖GPU/compositor/next-frame；surface 1、loaded ratio 1、ready/after非黑、changed ratio `0.000696`，4个time-of-day binding完整。报告/full/fixed SHA-256为`c79fb8dc078c7a069ed7edfdc24cc540eab387268aa05e21efa00f383646858d` / `5dac7ac4608ba2366b69d85d79b21144e5040cf97548df3ede6f0dcc457309d5` / `a2c4aa8df51a4113276824d94ad799b7ecd3ad48dbbbd951476999cc6a439b36`。正式checkpoint **36 modules / ALL OK**，文档同步后仓库测试 **200 modules / 113.7 s / ALL OK**，code health **853 Swift / 44 locked legacy / 400行**，`script/build_and_run.sh verify`与deep strict codesign通过；运行App executable SHA-256 `3d8b976ec63a6567323646e874bd36c4d1bb82260d589f117bbcaefedd0027c4`、CDHash `d0b4db6f22a75a905310a2136a0f4996dfb8884e`、Team `H9QWU9XN8R`，source/staged identity签名前后一致。legacy-compose Precise Blur、unique/history、Cursor Ripple、Standard Blur、Local Contrast及其他whole-chain consumer仍可达，R4保持`partial`，R5保持`not_started`。
39. **2026-08-11 R4-B4 exact stock Standard Blur logical-target stage闭环**：capability把exact stock `.standardBlur`、history-free/non-unique、非captured-main的四pass/two-quarter-target stage登记到与Precise Blur相同的`dedicatedGraphStageKeys`所有权面；每stage继续Program-first，失败后才允许typed graph adapter。GraphExecutor在claim前核对strict Standard Blur pipeline，并让无mask或`.mask` purpose、axis-aligned mapped UV、normalized path均匹配的typed mask candidate通过；wrong-purpose、missing candidate及不匹配plan以`standard-blur-resource-missing`失败关闭。该批只迁移owner并复用既有strict Standard Blur像素backend，没有修改blur weights、shader math，也没有sample/layer/path/asset-ID分支。Developer ID fresh正式矩阵单样本`2134765860`为**1/1 PASS**：layer `246`的两段Blend加四节点masked Standard Blur从旧whole-chain转入`resolved-material-graph`，resolved owner变为`[206,238,246,301,457]`，exact effect execution `12/12`，GPU/compositor/next-frame缺失与旧owner冲突均为0；submitted/completed `346/345`、failed frame/drawable miss 0，ready/after非黑，changed ratio `0.001116`。报告/full/fixed SHA-256为`674a18f5b49f5b1403ce8e56c39a93c19bc90f6201ab2f84f4d08ac4199400b2` / `18956db32da5d4abadd46bf63d91aa545b5147ea303a3568034b348d6093a951` / `c51ad9fffc2b9ad9012f004492e582d6259448f0bb4fd6366c63c1d65ac9d39d`。统一inner/checkpoint选中 **25 modules / ALL OK**，矩阵/semantics **47/47**，code health **853 Swift / 44 locked legacy / 400行**，`script/build_and_run.sh verify`与deep strict codesign通过；运行App executable SHA-256 `f681cfe8d0dc048f381cdbbfebec74b7f97a9fcbed87a0248b823168fbb8bd5b`、CDHash `52bcd12194172fe9a12e2d0da705a992efe0ac5e`、Team `H9QWU9XN8R`。`2902406982:530`因captured-main utility composition、`3028090166:13`因同一atomic chain仍含未迁移Godrays、`3750813609:358`因未知combine继续由旧owner处理或失败关闭；本批未跑fixed13/full45，不能把定向门写成整族完成、性能、Windows像素或Wallpaper Engine视觉等价。R4保持`partial`，R5保持`not_started`。
40. **2026-08-11 R4-B5 exact stock Local Contrast logical-target stage闭环**：capability把既有strict planner接受的`.localContrast`登记为Program-first logical-target adapter；GraphExecutor claim前要求Local Contrast pipeline与有限`0...5` static/live strength，继续核对四material node、两个scale-4 non-unique `rgba8888` target、history-free与非captured-main合同。该批只迁移owner，复用既有13-tap X/Y Gaussian与combine backend，没有修改权重、shader math或增加sample/layer/path/Workshop ID分支。Developer ID fresh正式矩阵单样本`2902406982`为**1/1 PASS**：layers `167/177`从旧whole-chain转入`resolved-material-graph`，resolved owner由32层增至34层；两层各4 material node的GPU/compositor/next-frame闭合，exact effect execution `42/42`、gap/failure/validation与legacy conflict均为0。submitted/completed `126/125`、failed frame/drawable miss 0，ready/after非黑，changed ratio `0.037877`；人工核对模糊背景、中央三角构图、日期/文字、人物与粒子完整可见。报告/full/fixed/after截图SHA-256为`20afaee19b9dee6066bbce5c2a43577409348d6cc32018df2df92b0042412d19` / `1b6a022be75c8d1446e4b34335126ec0ad024fdf947b4c76a5709526d785aa82` / `eb47112fe1e210a65b1f555d784eeea4b60d271933afc553719d50ab3d654440` / `c4956e51479fcccf801a15a0f0923d8048fa818874db60906bfa968806fe6065`。统一inner/checkpoint各 **25 modules / ALL OK**，矩阵/semantics **47/47**，code health **853 Swift / 44 locked legacy / 400行**，`script/build_and_run.sh verify`与deep strict codesign通过；运行App executable SHA-256 `1082061ea144f51252e4b8fad1e6cf874f57dd0e63236e7558e9c67ec99f39c0`、CDHash `1e781e4f1de2f179e9fae573afb51bf39bc405b9`、Team `H9QWU9XN8R`。mask/greyscale、KERNEL1/2、非默认Gaussian scale、captured-main、unsupported sibling、generic shader、fresh fixed13/full45与Windows/Wallpaper Engine像素等价未由本门证明；R4保持`partial`，R5保持`not_started`。
