# Wallpaper Engine Scene 语义手册

> 状态：现役开发参考
>
> 首次整理：2026-07-22
>
> 目标：先确定 Wallpaper Engine Scene 的作者语义和执行合同，再实现、调参和做样本验收。

## 1. 先说结论

Scene 兼容的核心不是不断增加“看起来差不多”的效果分支，而是按样本声明执行同一套数据驱动运行时：

1. 场景和对象决定能力是否存在、是否可见以及执行顺序；
2. effect 定义有序 pass、render target、输入绑定、复制/合成和 shader variant；
3. material 与 shader 决定每个 texture slot、combo、uniform 和 render state 的实际含义；
4. Timeline、SceneScript、用户属性、鼠标、音频和媒体只更新作者绑定的目标；
5. 不支持的局部语义应显式降级，不能用整层位移、全局水波或静态占位冒充支持；作者显式启用的 Scene Camera Shake 是独立的全局相机系统，不能与局部 effect 混同。

运行证据使用两层矩阵：`script/scene_wallpaper_sample_matrix.json` 是固定回归 suite，按 digest 锁定 `script/scene_wallpaper_full_sample_matrix.json` 并只保存 13 个成员及其明确 override；加载时无损展开成既有矩阵合同。后者的目标是当前真实 Scene 目录完整快照；authored census 发现样本增删时立即降为待扩容 tracked baseline，完成独立 milestone 运行扩容前不得称完整。日常改动按影响面跑定向门；fixed/full 只在 milestone 阶段按明确风险选择。现役结果和聚合缺口只在 [运行证据索引](runtime-evidence-index.md) 维护，专项表只链接该入口，避免重复数字随代码演进失真。用户可见回归的影响面由实际 render chain 决定，不由专题或源码目录决定；同一可见结果所依赖的 selection、Program、GPU、publication 与 composition 必须作为一个 correctness atom 闭合。

这直接解释了此前的主要错误：

- 头发、山体整块晃动可能来自把局部 UV/flow/mask 变形错做成 layer transform；但单一区域相对显眼也可能是其他作者效果缺失、幅度错误或合成顺序错误，必须按整幅作者动态系统验收，不能只凭“头发在动”锁定根因；
- 不需要水波或视差的样本也在动：播放器按“具备能力”启用，而不是按作者声明启用；
- 背景重复、层层叠加：`previous`、scene compose、named target、copy/swap 和历史 RT 被合并成同一种缓冲；
- 时钟、字体、雨和粒子缺失：把它们当附加装饰，而不是 text/particle/SceneScript 正式运行时对象。

## 2. 查阅入口

Scene 文档按四层使用，后续开发不要从取证记录直接跳到“已支持”：

```text
当前状态（覆盖台账 / 专项覆盖表）
  -> 当前证据（运行证据索引）
  -> 目标合同（格式、运行系统、SceneScript 等语义文档）
  -> 来源与边界（source-index / 客户端静态取证）
```

| 文档层 | 回答的问题 | 不回答的问题 |
|---|---|---|
| 覆盖台账与专项覆盖表 | MyWallpaperX 现在实现到哪一级、下一门是什么 | 官方客户端内部为什么这样组织 |
| 运行证据索引 | 哪些代码、测试、隔离样本和 GPU 结果支撑当前等级 | 未运行能力的目标设计 |
| 语义与实现合同 | 下一步需要保真的 IR、顺序、生命周期和失败边界 | 当前代码是否已经完成 |
| 资料来源与静态取证 | 结论来自官方声明、结构化资产、Ghidra、样本还是第三方 | MyWallpaperX 能力等级或 Windows 像素等价 |

| 问题 | 先看 |
|---|---|
| Swift、Metal、C/C++、JavaScript 与 Python 的长期职责，VM/compiler/XPC 何时允许接入 | [技术栈与架构路线边界](../../architecture/technology-stack-boundaries.md)；只规定路线与准入，不代表能力已实现 |
| 当前系统大盘、主要缺口和下一批次是什么 | [官方语义与实现覆盖台账](coverage-ledger.md) |
| 当前真实 Scene 样本声明了哪些纹理、Effect/Graph/FBO、粒子、动态输入和参数 family，某个公共修复影响哪些样本 | [全样本能力分类与修复台账](scene-corpus-capability-inventory.md)；它是 authored corpus 清单，不是运行支持等级 |
| 真实样本缺图、错误合成、黑窗或交互不生效，当前先修哪一项 | 先从[运行证据索引](runtime-evidence-index.md)和隔离复现确定第一个失败 identity，再用[能力依赖图](capability-dependency-map.md)与对应专项合同收敛同一可见链；不得按目录或 `L1/L2` 列表挑任务 |
| 179 个官方页面逐页落到哪个稳定合同 anchor、哪些只属于编辑器或平台决策 | [官方页面逐页表](official-page-map.md) |
| 16 个官方目录组如何路由到专项能力表 | [官方页面分组映射](official-page-crosswalk.md) |
| 公共能力先后依赖、哪些系统必须共用底座 | [能力依赖图](capability-dependency-map.md) |
| `project.json`、`scene.json`、对象、动态值和资源如何组成场景 | [场景格式与 Render Graph](scene-format-and-render-graph.md) |
| effect 为什么启用、45 类效果各自是什么 | [内置 Effects 语义全集](effects-reference.md) |
| 45 类官方 effect 当前分别走哪条执行通道、证据和下一门 | [Effect 执行覆盖表](effect-execution-coverage.md) |
| EffectDefinition、Material、FBO、Shader 的 IR 与 executor 分别做到哪里 | [Render Graph 与 Shader 覆盖表](render-graph-shader-coverage.md) |
| 粒子每个 General/Emitter/Initializer/Operator/Renderer/Child 项做到哪里 | [粒子组件覆盖表](particle-component-coverage.md) |
| 官方客户端有哪些播放端 stock 资产路径、项目素材如何一一对应 | [stock 播放资产包](stock-asset-bundle.md) |
| Frame Context、Timeline、属性 target、文字、cursor/audio/media/provider 做到哪里 | [运行输入与属性覆盖表](runtime-input-property-coverage.md) |
| SceneScript v2.8 每个生命周期、事件、handle 和 global 做到哪里 | [SceneScript API 覆盖表](scenescript-api-coverage.md) |
| Utility、Puppet、3D、Lighting、性能、RGB 和离线做到哪里 | [高级对象覆盖表](advanced-object-coverage.md) |
| 各运行系统的官方语义和正确执行顺序是什么 | [运行时系统语义](runtime-systems-reference.md) |
| VM 语言等级、宿主桥接协议、Vec/Mat 数值行为、自定义属性 UI 协议 | [SceneScript 运行时实现层合同](scenescript-runtime-implementation-contract.md) |
| 内联脚本绑定到 JSON 的哪个位置、`authoredValue` 怎么编码、导出哪些 hook | [内联脚本与 binding target 取证](scenescript-binding-target-forensics.md) |
| 官方 shader source 使用哪些未定义 token、哪些后端结论仍需实验 | [Shader source 前置合同与跨后端假设审查](shader-prelude-and-backend-abstraction.md) |
| 19 个随包工程各覆盖什么能力、哪些可作为隔离验证候选 | [官方默认工程 corpus](official-default-projects-fixture-inventory.md) |
| 随包 `zcompat` 有哪些 patch record、哪些 matcher/runtime 语义尚未确认 | [zcompat 向后兼容机制取证](zcompat-backward-compatibility-forensics.md) |
| 官方某能力哪个版本引入、改过什么、VM/字体/FBO 条件等实现事实 | [官方客户端 changelog 取证](client-changelog-forensics.md) |
| 某个 wire 字段在编辑器叫什么、粒子组件/blend/Timeline/scene options 的官方名称与定义 | [编辑器字符串表取证](editor-string-table-forensics.md) |
| 官方各系统的实现库来源、bin 模块清单、官方元素预览视频在哪 | [客户端二进制与第三方依赖取证](client-binary-dependency-forensics.md)，只作模块/来源导航 |
| 官方客户端的资源、resolver、RenderGraph、SceneScript、媒体与 surface 如何分层，32/64 位结构是否对应 | [官方客户端运行机制静态取证](client-runtime-static-forensics.md)，只作 clean-room 结构证据 |
| MirageWallpaper 如何组织纹理、effect/FBO 合成、相机、鼠标、动态输入与最终呈现，哪些实现缺口不能照抄 | [MirageWallpaper Scene 显示链路静态研究](miragewallpaper-rendering-reference.md)，只作等级 D 的 clean-room 架构对照 |
| 官方站当前有哪些 Scene 页面、某个 API 专页在哪里 | [官方页面全目录](official-page-catalog.md) |
| 某条结论来自官方、样本还是第三方实现 | [资料来源与证据索引](source-index.md) |
| 某条 `L3` 到底由哪些代码、自动测试和运行/GPU 结果支撑 | [运行证据索引](runtime-evidence-index.md) |
| 2026-07-22 早期能力批次当时采用的顺序、样本和测试门 | [Scene 播放能力开发计划](../scene-capability-development-plan-2026-07-22.md)（历史记录，不用于选下一任务） |
| R0-R5 owner 收敛和旧链删除当时的断点、决策与验收条件 | [Scene Render Chain 重构计划](../scene-render-chain-refactor-plan-2026-08-03.md)（已完成历史记录，不是现役计划或能力事实入口） |

### 2.1 源码目录导航

`MyWallpaperX/Core/SteamWorkshopScene` 按现有运行时职责分为九个一级目录，目录只负责导航和所有权，不改变 Swift Target 或访问边界：

| 目录 | 主要职责 |
|---|---|
| `Format` | Project、Document、PKG/TEX 与 JSON source format |
| `Runtime` | Host、frame context、runtime model/input、descriptor、diagnostics |
| `Properties` | 用户属性、binding program、dynamic snapshot、live update |
| `Resources` | asset/resource index、texture loader、path resolver、video source |
| `Rendering` | Metal 核心、compositor、layer、camera、geometry、utility |
| `RenderGraph` | authored graph、dependency、render target、offscreen pool、ShaderContract |
| `Effects` | 具体 effect pipeline、runtime plan、renderer |
| `Text` | descriptor、font、geometry、texture、dynamic text |
| `Particles` | definition、parser、simulation、pipeline、texture、trail |

新增 Swift 文件必须进入既有职责目录；主类型 extension 与主文件同目录，不使用 `Misc`、`Common` 或 `Helpers` 兜底，也不为未来能力建立空目录。Timeline/Animation、SceneScript/Scripting、system/media/audio provider 或 Puppet/3D/Lighting 等新系统只有形成多个共同生命周期或明确依赖边界的实际文件后，才评估新增一级目录。结构约束由 `test_scene_semantics_coverage.py` 自动检查。

## 3. 证据等级

Wallpaper Engine 没有公开稳定、完整的 Workshop Scene 序列化规范。本文必须区分“官方行为合同”和“观察到的数据格式”，不能混写成同等确定性。

| 等级 | 来源 | 可以证明什么 | 不能证明什么 |
|---|---|---|---|
| `A` | Wallpaper Engine 官方 Designer 文档、官方 SceneScript `lib.sceneScript.d.ts` | 作者可见能力、启用规则、参数含义、脚本 API 和生命周期 | 私有 JSON/PKG/TEX 的全部字段和内部 pass 调度 |
| `B` | Workshop 样本及其隔离解包结果 | 真实实例字段、顺序、override、资源引用和组合方式 | 字段在所有版本中的稳定性、官方内部默认算法 |
| `C` | WaifuX 内嵌的 WE-compatible asset payload | effect/material/shader 定义形态和具体高频效果的执行线索 | 资源来源、版本和官方真实性；不作为项目资产 |
| `D` | `Almamu/linux-wallpaperengine` 等开源播放器 | 一种可审计解释路径、常见陷阱、字段间关系 | 官方真值；项目中的 TODO、启发式和 bug 不能反向成为规范 |
| `E` | MyWallpaperX 当前代码、测试和样本矩阵 | 当前真实支持范围、已知降级和回归证据 | Wallpaper Engine parity 或未覆盖样本的正确性 |

冲突时按 `A -> 2.8.42 客户端快照静态取证 -> B -> C -> D -> E` 排查。客户端静态取证是单独标注版本和方法的证据通道，不占用本表字母等级；其逐篇入口见 [资料来源与证据索引](source-index.md) §1.11。它可收窄结构和生命周期假设，但仍不能证明完整运行时事件顺序、shader 数学或 Windows 像素 parity。WaifuX 的资源包仍留在 `C`。

注意本表的 `A`-`E` 与 [Windows 官方客户端取证记录](../../reviews/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md) 的 `A`/`B`/`C` 是**两套不同的标度**：后者的 `C` 指“根据字段名或常量作出的解释”，不是本表的 WaifuX payload。§1.11 中以该审计为等级源的随包取证文档使用后者。引用“等级 C”时必须指明出处标度。

## 4. 开发硬规则

### 4.1 能力存在不等于启用

- Camera Parallax 只在 `scene.general.cameraparallax` 解析为 true 时启用；逐层 `parallaxDepth` 缺失或两轴均为零时该层不移动，composition 类型本身不隐含任何视差深度。
- Scene Camera Shake 只在 `scene.general.camerashake` 最终解析为 true 时启用；作者关闭或 amplitude 为 0 时必须保持 identity，不得因为播放器具备 shake 能力而强开，也不得用对象级 `Shake` effect 代替它。
- Depth Parallax 是对象显式引用的独立 effect，并需要 depth map；它不是 Camera Parallax 的别名。
- 水波、摇摆、摆动、模糊、粒子、文字和脚本都必须由对象或属性绑定显式声明。
- effect 的 optional texture combo 只在对应资源真实绑定时启用。
- 用户属性、Timeline 或 SceneScript 可以在运行时改变值，但不能凭播放器能力凭空创建作者未声明的效果。

### 4.2 顺序和空槽都是合同

- 保留 scene object source order、effect order、pass order 和 material pass order。
- texture slot 数组中的 `null` 是占位，不得压缩；slot 语义由 shader/material 决定，不存在通用的“slot 1 永远是 mask”。
- `previous`、原始 layer、scene background、named target、临时 RT 和跨帧 history RT 必须是不同资源身份。
- `compose`、copy/swap command、显式 `bind` 和 pass `target` 必须进入 Render Graph，不能丢成编辑器元数据；command 不消耗实例 material-pass ordinal。

### 4.3 不支持必须可见

每个对象、effect、pass、RT 和 texture slot 至少要能输出以下状态之一：

- `supported-executed`
- `supported-inactive-by-author`
- `degraded-passthrough`
- `unsupported-schema`
- `missing-resource`
- `compile-or-pipeline-failed`

“成功启动”“非黑帧”和“route-only”不能记为视觉支持。

## 5. 统一运行模型

```text
project.json
  -> 入口与用户属性
scene.json / scene.pkg / assets
  -> Scene IR（对象、层级、资源、动态值）
  -> 作者状态求值（默认值、属性、可见性、Timeline、SceneScript）
  -> Resource Registry（image/video/text/particle/media/sceneTexture）
  -> Render Graph（base draw -> ordered effects -> object composite）
  -> Scene post process（Bloom/HDR 等）
  -> 实时 drawable 或离屏 readback
```

实时播放与离线烘焙应共用 Scene IR、时钟推进、资源注册表、效果图和绘制器，只替换输入源、时钟策略与输出目标。否则两条路径会在字体、粒子、随机数、音频和 effect history 上持续漂移。

## 6. 下一阶段的实现门

继续改代码前，目标能力必须先在本专题中具备：

1. 明确的作者启用条件；
2. 输入资源和 texture slot 含义；
3. pass、RT、history、compose/copy/swap 的执行要求；
4. 动态 uniform/provider 和生命周期；
5. 正向样本、默认关闭反例和失败降级；
6. 证据等级与仍未知项；
7. 已知可见回归从资源选择到 next-frame 的完整链、第一个断裂边、目标 ROI 和成功观测。
8. 官方合同之后的 MirageWallpaper 固定-revision 源码交叉检查：列出实际读取的模块/关键 symbol、`producer -> state/identity -> consumer -> frame order/lifecycle -> failure path` 与已知 divergence；专题总结、历史行号或第三方输出不能代替本批源码阅读。

缺少其中任一项时，先补研究或标记 unsupported，不再靠整层动画和目测参数试错推进。

## 7. 维护约定

- 验证选择统一使用 `python3.12 script/verify_scene_change.py --phase <inner|checkpoint|integration|milestone>`；同一未变化源码已经由较高阶段覆盖的 gate 不重复运行，固定/完整矩阵必须写明升级原因。
- 本目录记录稳定语义和实现合同，不记录单次调试流水账。
- [覆盖台账](coverage-ledger.md) 只做系统摘要；Effect、粒子、SceneScript、Graph/Shader、运行输入/属性和高级对象的专项能力表分别是其逐项等级事实来源。
- [全样本能力分类与修复台账](scene-corpus-capability-inventory.md) 保存当前 corpus 的静态 family、参数和资源清单。新增/删除样本或按公共类型立项时先刷新它；family 覆盖数只用于界定影响面，不能覆盖运行证据或第一个可见断裂边。
- 纹理/资源、Graph/FBO/composition、effect/shader、粒子和动态输入/SceneScript/交互均使用同一官方优先、Mirage 固定-revision 源码交叉检查规则；专项表只登记与该能力有关的模块、结构结论和 divergence，不在每张表复制一套治理文字。
- 实现前必须先查 [能力依赖图](capability-dependency-map.md)，再进入对应专项表查看作者条件、代码、测试、运行证据和下一门；依赖图限制可采用的实现顺序，能力等级描述覆盖强度，二者都不是用户可见问题的工作队列。存在真实回归时，由第一个共享断裂边决定当前优先级，允许同一 correctness atom 跨多个 D 节点和源码目录；不能从同系统某个 `L3` 子集推断整套能力。
- 资料入口完整性以 [179 页逐页表](official-page-map.md) 与自动门禁为准；16 组分组统计不能替代逐页映射。
- 专项表不写「当前实现基线：`<commit>`」。当前基线、生产播放输入边界、签名身份和 Debug runtime evidence schema 只在 [运行证据索引](runtime-evidence-index.md) 维护；覆盖台账只做系统摘要，能力依赖图只维护前置关系，带日期的 plan/roadmap 只表示历史批次快照。专项表里出现的 commit 号一律理解为对应能力的历史落地提交。
- 新发现的字段先标证据等级和样本来源，再判断是否进入实现。
- 官方文档或 `lib.sceneScript.d.ts` 版本变化时，更新 [资料来源与证据索引](source-index.md) 的核验日期和差异。
- 第三方播放器与官方资料冲突时，记录其偏差，不修正文档去迎合第三方行为。
- Scene 源码导航以根 `AGENTS.md` 的九类职责和 [`script/scene_source_layout.json`](../../../script/scene_source_layout.json) 为准。`RenderGraph/EffectExecution` 收纳统一 GraphExecutor 使用的 typed stage preparation、encoding 与 renderer 类型族；`RenderGraph/GraphTargets` 收纳 authored graph target 的计划、状态、Metal 分配、驻留、资源命令与 publication。named layer target 属于另一身份和生命周期，不并入 effect FBO/history。后续目录只按完整类型族和清晰生命周期增加，迁移时同步布局 manifest、自动门、standalone source list 与现役链接。
- `test_scene_semantics_coverage.py` 自动校验布局 manifest 与本目录相对 Markdown 链接，不复制或锁定动态基线、报告计数和路线结论。
