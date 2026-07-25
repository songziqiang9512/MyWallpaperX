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
5. 不支持的语义应显式降级，不能用整层位移、全局水波或静态占位冒充支持。

运行证据使用两层矩阵：`script/scene_wallpaper_sample_matrix.json` 是固定回归门，`script/scene_wallpaper_full_sample_matrix.json` 是当前真实 Scene 目录的完整快照门。日常改动按影响面跑定向或固定门；样本增加、完整矩阵合同变化或里程碑收口时重跑完整快照门。现役结果和聚合缺口只在 [运行证据索引](runtime-evidence-index.md) 维护，专项表只链接该入口，避免重复数字随代码演进失真。

这直接解释了此前的主要错误：

- 头发、山体整块晃动：把局部 UV/flow/mask 变形错做成 layer transform；
- 不需要水波或视差的样本也在动：播放器按“具备能力”启用，而不是按作者声明启用；
- 背景重复、层层叠加：`previous`、scene compose、named target、copy/swap 和历史 RT 被合并成同一种缓冲；
- 时钟、字体、雨和粒子缺失：把它们当附加装饰，而不是 text/particle/SceneScript 正式运行时对象。

## 2. 查阅入口

| 问题 | 先看 |
|---|---|
| 当前系统大盘、主要缺口和下一批次是什么 | [官方语义与实现覆盖台账](coverage-ledger.md) |
| 179 个官方页面逐页落到哪个稳定合同 anchor、哪些只属于编辑器或平台决策 | [官方页面逐页表](official-page-map.md) |
| 16 个官方目录组如何路由到专项能力表 | [官方页面分组映射](official-page-crosswalk.md) |
| 公共能力先后依赖、哪些系统必须共用底座 | [能力依赖图](capability-dependency-map.md) |
| `project.json`、`scene.json`、对象、动态值和资源如何组成场景 | [场景格式与 Render Graph](scene-format-and-render-graph.md) |
| effect 为什么启用、45 类效果各自是什么 | [内置 Effects 语义全集](effects-reference.md) |
| 45 类官方 effect 当前分别走哪条执行通道、证据和下一门 | [Effect 执行覆盖表](effect-execution-coverage.md) |
| EffectDefinition、Material、FBO、Shader 的 IR 与 executor 分别做到哪里 | [Render Graph 与 Shader 覆盖表](render-graph-shader-coverage.md) |
| 粒子每个 General/Emitter/Initializer/Operator/Renderer/Child 项做到哪里 | [粒子组件覆盖表](particle-component-coverage.md) |
| Frame Context、Timeline、属性 target、文字、cursor/audio/media/provider 做到哪里 | [运行输入与属性覆盖表](runtime-input-property-coverage.md) |
| SceneScript v2.8 每个生命周期、事件、handle 和 global 做到哪里 | [SceneScript API 覆盖表](scenescript-api-coverage.md) |
| Utility、Puppet、3D、Lighting、性能、RGB 和离线做到哪里 | [高级对象覆盖表](advanced-object-coverage.md) |
| 各运行系统的官方语义和正确执行顺序是什么 | [运行时系统语义](runtime-systems-reference.md) |
| VM 语言等级、宿主桥接协议、Vec/Mat 数值行为、自定义属性 UI 协议 | [SceneScript 运行时实现层合同](scenescript-runtime-implementation-contract.md) |
| 内联脚本绑定到 JSON 的哪个位置、`authoredValue` 怎么编码、导出哪些 hook | [内联脚本与 binding target 取证](scenescript-binding-target-forensics.md) |
| 官方 shader source 使用哪些未定义 token、哪些后端结论仍需实验 | [Shader source 前置合同与跨后端假设审查](shader-prelude-and-backend-abstraction.md) |
| 19 个随包工程各覆盖什么能力、哪些可作为隔离验证候选 | [官方默认工程 corpus](official-default-projects-fixture-inventory.md) |
| 随包 `zcompat` 有哪些 patch record、哪些 matcher/runtime 语义尚未确认 | [zcompat 向后兼容机制取证](zcompat-backward-compatibility-forensics.md) |
| 官方站当前有哪些 Scene 页面、某个 API 专页在哪里 | [官方页面全目录](official-page-catalog.md) |
| 某条结论来自官方、样本还是第三方实现 | [资料来源与证据索引](source-index.md) |
| 某条 `L3` 到底由哪些代码、自动测试和运行/GPU 结果支撑 | [运行证据索引](runtime-evidence-index.md) |
| 已选批次的详细实施顺序、样本和测试门 | [Scene 播放能力开发计划](../scene-capability-development-plan-2026-07-22.md) |
| Wallpaper Engine 的上层能力地图 | [Scene 兼容能力综述](../wallpaper_engine_scene_compatibility.md) |

### 2.1 源码目录导航

`MyWallpaperX/Core/SteamWorkshopScene` 按现有运行时职责分为九个一级目录，目录只负责导航和所有权，不改变 Swift Target 或访问边界：

| 目录 | 主要职责 |
|---|---|
| `Format` | Project、Document、PKG/TEX、JSON、interpretation |
| `Runtime` | Host、frame context、runtime model、descriptor、diagnostics |
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
| `B` | 用户合法取得的 Workshop 样本及其隔离解包结果 | 真实实例字段、顺序、override、资源引用和组合方式 | 字段在所有版本中的稳定性、官方内部默认算法 |
| `C` | WaifuX 内嵌的 WE-compatible asset payload | effect/material/shader 定义形态和具体高频效果的执行线索 | 资源来源、许可、版本和官方真实性；不得随项目复制或分发 |
| `D` | `Almamu/linux-wallpaperengine` 等开源播放器 | 一种可审计解释路径、常见陷阱、字段间关系 | 官方真值；项目中的 TODO、启发式和 bug 不能反向成为规范 |
| `E` | MyWallpaperX 当前代码、测试和样本矩阵 | 当前真实支持范围、已知降级和回归证据 | Wallpaper Engine parity 或未覆盖样本的正确性 |

冲突时按 `A -> 合法安装的官方 assets -> B -> C -> D -> E` 排查。本机现有 Wallpaper Engine 2.8.42 正版安装，其随包结构化证据与逐篇取证入口见 [资料来源与证据索引](source-index.md) §1.11；该层优先于 B/C，但仍不能证明运行时事件顺序、shader 数学与 Windows 像素 parity。WaifuX 的资源包**不因此提升**为“官方 assets”，仍留在 `C`。

注意本表的 `A`-`E` 与 [Windows 官方客户端取证记录](../../reviews/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md) 的 `A`/`B`/`C` 是**两套不同的标度**：后者的 `C` 指“根据字段名或常量作出的解释”，不是本表的 WaifuX payload。§1.11 登记的 5 篇随包取证文档使用后者。引用“等级 C”时必须指明出处标度。

## 4. 开发硬规则

### 4.1 能力存在不等于启用

- Camera Parallax 只在 `scene.general.cameraparallax` 解析为 true 时启用；逐层 `parallaxDepth` 缺失或两轴均为零时该层不移动，composition 类型本身不隐含任何视差深度。
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

### 4.4 许可证与来源边界

- 不复制或分发 WaifuX 的 `wallpaper-wgpu`、`zip_data.o`、shader、material 或 texture。
- 不直接复制 GPL-3.0 开源播放器实现；只把它们用于结构佐证和缺陷分析。
- 官方 assets 将来只能从用户合法安装位置读取，不打包进 MyWallpaperX。
- MyWallpaperX 的算法、Metal shader、fixtures 和测试必须独立实现，并保留来源说明。

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
6. 证据等级与仍未知项。

缺少其中任一项时，先补研究或标记 unsupported，不再靠整层动画和目测参数试错推进。

## 7. 维护约定

- 本目录记录稳定语义和实现合同，不记录单次调试流水账。
- [覆盖台账](coverage-ledger.md) 只做系统摘要；Effect、粒子、SceneScript、Graph/Shader、运行输入/属性和高级对象的专项能力表分别是其逐项等级事实来源。
- 实现前必须先查 [能力依赖图](capability-dependency-map.md)，再进入对应专项表查看作者条件、代码、测试、运行证据和下一门；不能从同系统某个 `L3` 子集推断整套能力。
- 资料入口完整性以 [179 页逐页表](official-page-map.md) 与自动门禁为准；16 组分组统计不能替代逐页映射。
- 专项表不写「实现基线：`<commit>`」。基线 commit 与 interpretation schema 版本只在 [覆盖台账](coverage-ledger.md)、[运行证据索引](runtime-evidence-index.md)、[开发计划](../scene-capability-development-plan-2026-07-22.md) 和 roadmap 维护（自动门禁只校验这四份）；专项表里出现的 commit 号一律理解为该能力的历史落地提交，不是当前基线。此前 7 份专项表各自复制基线，最旧的落后 42 个提交。
- 新发现的字段先标证据等级和样本来源，再判断是否进入实现。
- 官方文档或 `lib.sceneScript.d.ts` 版本变化时，更新 [资料来源与证据索引](source-index.md) 的核验日期和差异。
- 第三方播放器与官方资料冲突时，记录其偏差，不修正文档去迎合第三方行为。
- Scene 源码导航以本页九类目录为准；目录调整必须同步根 `AGENTS.md`、自动布局门、测试源码路径和文档代码链接。
