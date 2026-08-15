# Wallpaper Engine Scene 语义手册

> 状态：现役开发参考
>
> 首次整理：2026-07-22
>
> 目标：保真作者声明与关键执行合同，让声明式作者内容优先进入通用 compiler、VM、component runtime 和 Metal executor，并在局部失败时保住其余画面。

## 1. 先说结论

Scene 兼容的核心不是不断增加“看起来差不多”的效果分支，而是按样本声明执行同一套数据驱动运行时：

1. 场景和对象决定能力是否存在、是否可见以及执行顺序；
2. effect 定义有序 pass、render target、输入绑定、复制/合成和 shader variant；
3. material 与 shader 决定每个 texture slot、combo、uniform 和 render state 的实际含义；
4. Timeline、SceneScript、用户属性、鼠标、音频和媒体只更新作者绑定的目标；
5. 不支持的局部语义应显式降级，不能用整层位移、全局水波或静态占位冒充支持；作者显式启用的 Scene Camera Shake 是独立的全局相机系统，不能与局部 effect 混同。

运行证据使用两层矩阵：`script/scene_wallpaper_sample_matrix.json` 是固定回归 suite，按 digest 锁定 `script/scene_wallpaper_full_sample_matrix.json` 并只保存 13 个成员及其明确 override；加载时无损展开成既有矩阵合同。后者的目标是当前真实 Scene 目录完整快照；authored census 发现样本增删时立即降为待扩容 tracked baseline，完成独立 milestone 运行扩容前不得称完整。日常改动按影响面跑定向门；fixed/full 只在 milestone 阶段按明确风险选择。现役结果和聚合缺口只在 [运行证据索引](runtime-evidence-index.md) 维护。当前迁移优先级与批次边界由[兼容执行路线](../scene-compatibility-roadmap.md)决定：先让一个真实 authored unit 沿完整纵向链实际执行，再在 checkpoint 扩未见组合和撤权范围。

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
| Scene 的目标处理方式、官方/静态/第三方证据如何分层 | [Scene 兼容运行时架构](../runtime-architecture.md) |
| 当前先做哪个纵向结果、什么专用路线不得再扩张 | [Scene 兼容执行路线](../scene-compatibility-roadmap.md)；只决定迁移顺序，不覆盖能力事实 |
| 公开资料不足时，AI 何时研究官方客户端、怎样提炼独立合同并证明结果一致 | [官方客户端行为研究与一致性验证工作流](official-client-behavior-research-workflow.md)；Ghidra 只回答有界结构问题，官方黑盒对照才验证外部结果 |
| 当前系统大盘、主要缺口和待办是什么 | [官方语义与实现覆盖台账](coverage-ledger.md) |
| 当前真实 Scene 样本声明了哪些纹理、Effect/Graph/FBO、粒子、动态输入和参数 family，某个公共修复影响哪些样本 | [全样本能力分类与修复台账](scene-corpus-capability-inventory.md)；它是 authored corpus 清单，不是运行支持等级 |
| 真实样本缺图、错误合成、黑窗或交互不生效，当前先修哪一项 | 从[运行证据索引](runtime-evidence-index.md)和隔离复现确定第一个失败 identity；按现役路线闭合最短可见纵向链，并用[能力依赖图](capability-dependency-map.md)检查不可绕过的公共前置 |
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
| 研究任务需要核对 2.8.42 VM/宿主桥接的版本有界结构 | [SceneScript 固定客户端实现层静态取证](scenescript-runtime-implementation-contract.md)，只作 `research-context-only`；实现者查 SceneScript API 覆盖与兼容运行时架构 |
| 内联脚本绑定到 JSON 的哪个位置、`authoredValue` 怎么编码、导出哪些 hook | [内联脚本与 binding target 取证](scenescript-binding-target-forensics.md) |
| 研究任务需要核对官方 shader source/prelude 观察和待验证后端假设 | [Shader source/prelude 固定客户端与语料研究](shader-prelude-and-backend-abstraction.md)，只作 `research-context-only`；实现者只消费经审查的本批中性合同 |
| 19 个随包工程各覆盖什么能力、哪些可作为隔离验证候选 | [官方默认工程 corpus](official-default-projects-fixture-inventory.md) |
| 随包 `zcompat` 有哪些 patch record、哪些 matcher/runtime 语义尚未确认 | [zcompat 向后兼容机制取证](zcompat-backward-compatibility-forensics.md) |
| 官方某能力哪个版本引入、改过什么、VM/字体/FBO 条件等实现事实 | [官方客户端 changelog 取证](client-changelog-forensics.md) |
| 某个 wire 字段在编辑器叫什么、粒子组件/blend/Timeline/scene options 的官方名称与定义 | [编辑器字符串表取证](editor-string-table-forensics.md) |
| 官方各系统的实现库来源、bin 模块清单、官方元素预览视频在哪 | [客户端二进制与第三方依赖取证](client-binary-dependency-forensics.md)，只作模块/来源导航 |
| 官方客户端的资源、resolver、RenderGraph、SceneScript、媒体与 surface 如何分层，32/64 位结构是否对应 | [官方客户端运行机制静态取证](client-runtime-static-forensics.md)，只作 clean-room 结构证据 |
| MirageWallpaper 如何组织纹理、effect/FBO 合成、相机、鼠标、动态输入与最终呈现，哪些实现缺口不能照抄 | [MirageWallpaper Scene 显示链路静态研究](miragewallpaper-rendering-reference.md)，只作 `third-party-reference-pattern` clean-room 架构对照 |
| 官方站当前有哪些 Scene 页面、某个 API 专页在哪里 | [官方页面全目录](official-page-catalog.md) |
| 某条结论来自官方、样本还是第三方实现 | [资料来源与证据索引](source-index.md) |
| 某条 `L3` 到底由哪些代码、自动测试和运行/GPU 结果支撑 | [运行证据索引](runtime-evidence-index.md) |
| 早期能力批次、R0-R5、旧 G0-G5 计划和样本基线 | [历史文档索引](../../history/README.md)；只用于追溯，不用于选择下一任务 |

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

## 3. 来源分类与事实裁决

Wallpaper Engine 没有公开稳定、完整的 Workshop Scene 序列化规范。全库只使用[资料来源与证据索引](source-index.md)定义的 named source taxonomy；本手册不再维护第二套 `A`–`E` 全局等级，也不得用字母顺序把官方公开合同、固定客户端观察、作者语料、第三方参考和项目事实混成一条“可信度排名”。历史取证文件中的局部 `A/B/C` 只属于其固定快照，不能带回现役文档继续分类。

使用来源时必须同时写明输入身份和证明边界：官方公开合同回答作者可见语义；官方客户端动态对照回答固定条件下发生了什么；固定客户端静态观察只提供研究上下文；作者语料回答真实内容声明了什么；第三方实现只提供结构对照。静态取证或第三方代码都不是产品实现输入，必须先转写为项目自有的行为合同、正反 fixture 或官方结果对照协议，implementation agent 只消费这些项目合同。

MyWallpaperX 的当前代码与可复现运行证据回答“当前构建实际实现了什么”，项目 strategy 回答“准备怎样实现、验证和降级”；两者必须分开。strategy、计划或架构选择不能升级当前能力，旧 App/旧报告也不能覆盖当前代码与 fresh 运行事实。冲突裁决继续服从[项目文档入口](../../README.md#事实角色)的现役权威顺序。

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

### 4.3 失败必须分级且可见

每个对象、effect、pass、RT 和 texture slot 至少要能输出以下状态之一：

- `supported-executed`
- `supported-inactive-by-author`
- `degraded-passthrough`
- `unsupported-schema`
- `missing-resource`
- `compile-or-pipeline-failed`

“成功启动”“非黑帧”和“route-only”不能记为视觉支持。

状态不等于一律整层拒绝：安全/预算/identity/target hazard/lifecycle 错误 hard fail；单个 shader、pass、optional provider、script binding 或 particle system 失败默认 `degraded-passthrough`，保留可安全执行的 base layer 与其他对象；可选输入缺失使用作者默认或关闭 combo；未消费的未知非关键 metadata 保真并告警。任何 fallback 都必须带稳定诊断，不能静默换成语义不同的算法。

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

## 6. 通用执行实现门

继续改代码前，只需把本批真正会消费的合同闭合到足以安全执行，而不是预先穷举整个作者语义空间：

1. 写明当前没有执行的真实作者输入及统一链第一个失败 identity；
2. 写明本批要闭合到的可见/可执行结果和 previous-current fallback；
3. 保留作者启用条件、source/pass order、resource/slot/target identity 和 lifecycle；
4. 区分 hard fail、局部 effect/pass/script/component 降级、作者默认和 preserve-with-warning；
5. 提供项目自有正反 fixture，尽早运行一个代表性真实内容；未见内容或新组合在 checkpoint 加入，证明不是名称/hash 视觉特判；
6. compiler、VM 或 graph 接受输入后仍由 reflection/ABI/resource/target/budget 门校验，不能把 parse success 当视觉支持；
7. 涉及 GPU 或可见输出时证明实际执行、completion、publication、terminal compositor、next-frame 和局部失败隔离；具体 fidelity 声明再加预定义 ROI/事件断言；
8. 记录旧专用 fallback 和稳定后的撤销条件，但公共前置批次不强制同批撤权。

官方材料足以定义本批消费合同就直接实现。MirageWallpaper 等第三方源码只在官方材料不足、需要交叉检查 producer-to-consumer 结构时读取固定 revision；它不是每批前置门，也不能提供算法真值。未知但不会破坏安全或状态完整性的可选语义可以带诊断进入受控执行，不再因为缺少逐项证明自动整层 `unsupported`。

## 7. 维护约定

- 验证选择统一使用 `python3.12 script/verify_scene_change.py --phase <inner|checkpoint|integration|milestone>`；同一未变化源码已经由较高阶段覆盖的 gate 不重复运行，固定/完整矩阵必须写明升级原因。
- 本目录记录稳定语义和实现合同，不记录单次调试流水账。
- [覆盖台账](coverage-ledger.md) 只做系统摘要；Effect、粒子、SceneScript、Graph/Shader、运行输入/属性和高级对象的专项能力表分别是其逐项等级事实来源。
- [全样本能力分类与修复台账](scene-corpus-capability-inventory.md) 保存当前 corpus 的静态 family、参数和资源清单。新增/删除样本或按公共类型立项时先刷新它；family 覆盖数只用于界定影响面，不能覆盖运行证据或第一个可见断裂边。
- 纹理/资源、Graph/FBO/composition、effect/shader、粒子和动态输入/SceneScript/交互均以官方公开合同和项目 corpus 为主；Mirage 固定 revision 只在官方材料不足时作结构交叉检查，专项表不复制治理文字。
- 实现顺序先看[兼容执行路线](../scene-compatibility-roadmap.md)，再用[能力依赖图](capability-dependency-map.md)检查公共前置，并进入对应专项表核对当前事实。依赖图不是工作队列，专项表的 `L3 bounded` 也不是继续扩张专用 owner 的理由。
- 资料入口完整性以 [179 页逐页表](official-page-map.md) 与自动门禁为准；16 组分组统计不能替代逐页映射。
- 专项表不写「当前实现基线：`<commit>`」。当前基线、生产播放输入边界、签名身份和 Debug runtime evidence schema 只在 [运行证据索引](runtime-evidence-index.md) 维护；覆盖台账只做系统摘要，能力依赖图只维护前置关系，带日期的 plan/roadmap 只表示历史批次快照。专项表里出现的 commit 号一律理解为对应能力的历史落地提交。
- 新发现的字段先标 named source category、输入身份和证明边界，再判断是否进入项目自有合同；原始静态取证不直接进入实现。
- 官方文档或 `lib.sceneScript.d.ts` 版本变化时，更新 [资料来源与证据索引](source-index.md) 的核验日期和差异。
- 第三方播放器与官方资料冲突时，记录其偏差，不修正文档去迎合第三方行为。
- Scene 源码导航以根 `AGENTS.md` 和 [`script/scene_source_layout.json`](../../../script/scene_source_layout.json) 为准。新代码应把 authored source/metadata、统一 Program、通用 graph compilation、target/publication 生命周期和 GraphExecutor 保持为清晰职责；现有 bounded `ShaderFrontend`、dedicated candidate/admission 和 effect-specific planner 只作迁移期 oracle，不作为新 family 的目录或所有权模板。目录变化按完整类型族迁移，并同步布局 manifest、自动门、共享 source set 与现役链接。
- `test_scene_semantics_coverage.py` 自动校验布局 manifest 与本目录相对 Markdown 链接，不复制或锁定动态基线、报告计数和路线结论。
