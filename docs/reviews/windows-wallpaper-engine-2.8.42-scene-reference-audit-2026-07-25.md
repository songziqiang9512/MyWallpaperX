# Windows Wallpaper Engine 2.8.42 Scene 官方客户端取证记录

审查日期：2026-07-25
审查方式：Parallels Windows 11，只读静态检查、进程检查和有限 UI 验证
官方安装目录：`C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine`
MyWallpaperX 审查基线：`678a0525c2adaa1eaed8be886aa68e7f3f680c4c`

> 本文是官方客户端随包资源与运行边界的研究记录，不是 MyWallpaperX 当前能力状态入口。当前实现等级仍以 [Scene 能力总账](../scene/semantics/coverage-ledger.md)、[能力依赖图](../scene/semantics/capability-dependency-map.md) 和 [Scene 开发计划](../scene/scene-capability-development-plan-2026-07-22.md) 为准。本文中的“官方”表示该文件或行为来自本机 Steam 正版 Wallpaper Engine 2.8.42 安装，不表示可以复制或再分发其 payload。

## 1. 目的与结论

本次检查的目标不是破解、替换或分发 Wallpaper Engine，而是为 MyWallpaperX 自研 Scene 播放器提取可独立验证的：

- 文件 schema 和解析宽容度；
- Effect、Material、Pass、FBO 的有序关系；
- history、`previous`、`copy`、`swap` 和 condition 的行为合同；
- 官方粒子组件的最小预览工程；
- Windows 官方播放器可用于 A/B 与 pixel golden 的边界。

最重要的结论：

1. Windows 正版安装包随附了大量结构化 stock Effect 和粒子预览工程。对 Scene 开发而言，它们比反推 WaifuX 的不透明 `wallpaper-wgpu` 更接近一手证据。
2. stock Effect 能直接确认 pass DAG、FBO 声明、纹理绑定、条件节点和 history 资源关系，但不能单凭 JSON 恢复 shader 算法。
3. `particleelementpreviews` 是官方提供的最小能力 fixture 集，尤其适合补 MyWallpaperX 当前 L1、fail-closed 或缺少真实正向门的粒子组件。
4. 后续应从官方文件中提取 schema、默认值和可观察行为，再编写自有 fixture 和 Metal 实现；不得复制官方 shader、JSON、纹理或算法表达进入仓库。
5. Windows 官方输出应作为动态行为和像素对照的优先基准；WaifuX bake 只能作为辅助方向证据。
6. 完整客户端副本补充确认了 SceneScript 随包基类、官方默认 Scene corpus、Material/TEX/MDL 版本分布和 shader annotation schema；这些证据能直接缩小自研实现的输入合同。
7. 当前 `SceneTexContainerReader` 会在 header gate 拒绝随包的 28 个 32x32x32 LUT TEX；这是已定位的官方格式缺口，但本轮只记录证据，不修改产品代码。

## 2. 证据等级与使用边界

| 等级 | 本文含义 | 可用于 |
|---|---|---|
| A | Steam 正版安装中的结构化文件、签名、manifest 或可重复运行结果直接确认 | 建立 schema、顺序、存在性和可观察行为合同 |
| B | 进程加载、命令行、日志或 UI 状态确认，但不能证明内部算法 | 建立宿主边界和待验证实现假设 |
| C | 根据字段名、D3D 常量或文件关系作出的解释 | 指导实验，不能直接写成完整兼容 |

Clean-room 规则：

- 可以记录字段名、字段类型、默认状态、执行顺序、DAG、资源生命周期和输出差异。
- 可以自行创建不含官方 payload 的最小 fixture，验证相同行为合同。
- 可以在用户本机合法安装中运行官方工程并采集截图、视频、像素统计和时间序列。
- 不复制官方 shader、完整 JSON、纹理、材质 payload、二进制代码或反编译算法表达进入 MyWallpaperX。
- 不把“文件可解析”“组件被识别”或“样本启动成功”写成组件已经执行或实现官方像素一致。
- 不把 `scenescript32.dll` 已加载推断为已掌握 SceneScript VM 的内部语义。

## 3. 客户端身份与安装事实

### 3.1 版本

| 项目 | 已确认值 |
|---|---|
| 产品版本 | `2.8.42` |
| Windows 文件版本 | `2.8.0.42` |
| Steam build ID | `23967692` |
| Steam manifest 更新时间 | `2026-07-24 15:37:27 +0800` |
| Steam `SizeOnDisk` | `826,275,581` bytes |
| 安装根 | `C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine` |

版本事实来自安装根的版本信息、Windows 文件元数据和 Steam app manifest。后续复核应同时记录 build ID，不能只写产品版本，因为同一 `2.8.x` 可能发生资源更新。

### 3.2 签名

本次抽查的官方核心二进制具有有效 Authenticode 签名：

- 签名主体：`Skutta Software GmbH`
- 签名状态：Windows 验证有效

这能确认被检查文件属于当前合法安装的签名发行物；它不授予复制、修改或再分发权利。

### 3.3 DirectX 能力标记

安装版本数据中：

```text
directxlevel = 45312
```

解释：

```text
45312 = 0xB100 = D3D_FEATURE_LEVEL_11_1
```

证据等级为 A+C：十进制值来自官方安装数据，`0xB100` 到 D3D feature level 11.1 的映射来自 Windows D3D 常量。它说明当前客户端请求/记录的 D3D 能力等级，不等于每个 Scene shader 都实际使用 11.1 独有特性。

## 4. 运行进程与模块边界

### 4.1 Scene 播放进程

当前桌面壁纸运行进程为：

```text
wallpaper32.exe
```

在该进程中确认加载：

```text
d3d11.dll
dxgi.dll
d3dcompiler_47_x32.dll
scenescript32.dll
```

可用于 MyWallpaperX 的结论：

- 官方 Windows Scene 路径在当前环境使用 D3D11/DXGI。
- runtime shader 路径至少依赖 D3DCompiler 47。
- SceneScript 有独立的 32 位模块边界。
- 这些模块存在性不能证明具体 pass 排程、blend 数学、shader 源码或 SceneScript 指令语义。

### 4.2 UI 与编辑器进程

Wallpaper Engine 主 UI 和编辑器由独立的 `wallpaperui.exe` 进程组承载：

```text
-window browsewallpapers
-messagehandler WPEhandlerBrowseWallpapers

-window editor
-messagehandler WPEhandlerEditor
```

UI 子进程包含 Chromium 风格的 GPU、renderer、network 和 storage 进程；GPU 子进程命令行包含：

```text
--use-angle=d3d11
```

浏览器 UI 和编辑器分别使用独立 cache root：

```text
ui\uicache\browsewallpapers\base
ui\uicache\editor\base
```

这对自动化的意义是：

- `wallpaperui.exe` 的 ANGLE/D3D11 只证明 UI 渲染路径，不应与 `wallpaper32.exe` 的 Scene 渲染合同混为一谈。
- 自动化应把主 UI、编辑器和实际壁纸 renderer 分开观测。
- 只看到编辑器 UI 正常不能证明 `wallpaper32.exe` 已加载或执行目标 Scene。

### 4.3 日志边界

安装根日志中发现的明确错误是 LED/RGB 插件加载失败，Windows 错误码为 `126`。本次没有发现它与 Scene renderer 失败相关的证据。

因此：

- 不应把该错误归类为 Scene 解析或渲染回归。
- 未来运行实验应分别保存 editor、UI、wallpaper renderer 和插件日志，避免按根日志中的单条错误误诊。

## 5. 官方 stock Effect 资源总览

资源根：

```text
C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\assets\effects
```

本次结构化统计：

| 项目 | 数量 |
|---|---:|
| stock Effect | 46 |
| 总 pass | 86 |
| `material` pass | 83 |
| `copy` pass | 1 |
| `swap` pass | 2 |

关键分布：

- 唯一的 `copy` 出现在 Motion Blur。
- 两个 `swap` 都出现在 Fluid Simulation。
- 这说明 `copy` 和 `swap` 是真实官方 graph command，不是第三方播放器臆造的扩展。
- 数量只描述当前 2.8.42 stock 资源快照，不代表 Workshop 自定义 Effect 的上限。

### 5.1 FBO 格式声明

stock Effect 中出现的 FBO 格式声明次数：

| 格式 | 次数 | 建议的 MyWallpaperX 合同 |
|---|---:|---|
| `r16f` | 4 | 单通道半精度浮点 target |
| `r8` | 1 | 单通道 8-bit target |
| `rg1616f` | 2 | 双通道半精度浮点 target |
| `rgba8888` | 5 | 四通道 8-bit target |
| `rgba_backbuffer` | 11 | 与 backbuffer 颜色合同相关的 target |

这里的数字是格式声明出现次数，不应直接等同于运行时同时存活的纹理数。实际显存预算必须结合 extent、scale、format、unique、ping-pong 和生命周期计算。

### 5.2 `previous` 输入

确认使用 `previous` 的 stock Effect：

```text
blur
blurprecise
cursorripple
fluidsimulation
glitter
godrays
localcontrast
motionblur
shine
```

对 MyWallpaperX 的直接要求：

- `previous` 必须绑定 graph 中定义的前一有效输出，不能简单固定为原图。
- pass 被 condition 跳过时，需要明确“前一有效输出”是否变化，并通过 Windows A/B 实验固定合同。
- effect 链切换、resize、seek、pause 和 renderer restart 都必须定义 history/previous 的失效和重建行为。

## 6. Motion Blur 官方 graph 合同

Motion Blur 是当前 stock Effect 中唯一包含 `copy` 的 Effect。其有序结构确认是：

```text
material -> copy -> material
```

同时确认：

- 声明两个 FBO；
- history FBO 带 `unique: true`；
- 后续 material pass 显式绑定 `previous`；
- copy 位于两个 material 阶段之间，不能在 planner 中被当作无副作用节点删除或重排。

可直接转化为自有合同：

1. history target 必须拥有跨帧身份，不能与普通临时 ping-pong target 混用。
2. `unique: true` 至少意味着该 logical target 不能被同帧无条件 alias；更精确生命周期仍需运行实验。
3. copy 完成前不能让后续 pass 读取旧 target 内容。
4. 首帧、resize、切换壁纸、seek 和设备重建时需要确定 history seed。
5. GPU command 失败时不能把 history 标记为已经成功初始化。

尚未由静态文件确认：

- 首帧 history 的精确颜色或复制来源；
- pause 后恢复是否保留 history；
- 不同 FPS 下的时间归一化规则；
- resize 后 history 是 clear、stretch 还是重新 seed。

这些应通过 Windows 官方固定时间序列实验确认，不能从字段名猜测。

## 7. Fluid Simulation 官方 graph 合同

Fluid Simulation 是当前 stock Effect 中 graph 语义最完整的官方 fixture：

| 项目 | 已确认值 |
|---|---:|
| pass | 20 |
| FBO | 9 |
| `swap` | 2 |

已确认行为结构：

- pressure 使用 ping-pong 多次迭代；
- graph 末尾存在两次 `swap`；
- stock Effect 中只有它同时使用 pass、bind 和 FBO condition；
- 暴露两个 function：`clearVelocity`、`clearDye`。

可直接转化为 MyWallpaperX 合同：

1. pass、bind 和 FBO condition 必须在正确层级分别求值，不能只在 Effect 入口做一次总开关。
2. ping-pong identity 应作为 logical target 状态维护；不能只交换两个本地变量后丢失跨节点身份。
3. `swap` 是有序 graph side effect，必须与 material pass 一起进入 command plan。
4. condition 为 false 时，资源分配、bind 和 previous 链如何处理需要保持 fail-closed，并由官方运行实验确认。
5. `clearVelocity`、`clearDye` 表明 Effect 可以暴露有状态清理入口；MyWallpaperX 在没有 function dispatcher 前不应声称完整 Fluid 支持。
6. 20-pass graph 是显存预算和 target alias 规划的高价值压力 fixture。

尚未由静态文件确认：

- pressure 的官方数值迭代精度与平台差异；
- function 调用时机和线程边界；
- condition 动态变化时 target 是否保留旧内容；
- swap 在 GPU failure、pause 或 resize 时的回滚行为。

## 8. Effect 文件解析兼容合同

至少一部分官方 `effect.json` 使用尾逗号。实际验证结果：

- PowerShell 严格 JSON parser 会拒绝这些文件；
- macOS `plutil` 能读取；
- Foundation 使用 `.json5Allowed` 能读取。

因此 MyWallpaperX 的格式合同应是：

- 对官方 Scene/Effect JSON 使用项目现有的宽容解析入口；
- 不要在进入 typed parser 前用严格 JSON 工具做强制合法性门；
- 宽容解析只允许解决语法兼容，不能吞掉字段类型错误、非有限数值或未知必需组件；
- fixture 必须包含尾逗号、缺字段、错类型、未知字段和损坏输入的独立测试。

“能解析官方文件”仍不等于已经执行其 shader、condition、function 或粒子组件。

## 9. 官方粒子最小预览工程

资源根：

```text
C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\assets\scenes\particleelementpreviews
```

本次统计：

| 项目 | 数量 |
|---|---:|
| 能力预览目录 | 48 |
| 粒子 JSON | 50 |
| 结构化解析失败 | 0 |
| emitter 类型 | 3 |
| initializer 类型 | 16 |
| operator 类型 | 25 |
| renderer 类型 | 4 |

确认的 child event 类型：

```text
eventdeath
eventfollow
```

### 9.1 对当前缺口最有价值的官方 fixture

碰撞：

```text
collisionbounds
collisionmodel
collisionplane
collisionquad
collisionsphere
```

父子事件与属性继承：

```text
inheritinitialvaluefromevent
inheritvaluefromevent
```

控制点与值映射：

```text
controlpointattract
remapinitialvalue
remapvalue
```

Trail/Rope：

```text
rope
ropetrail
spritetrail
```

群集和力场：

```text
boids
turbulence
vortex
```

空间尺度：

```text
particleeditor3dscale
```

这些目录的价值不是“可以复制官方工程进仓库”，而是每个目录都把一个能力缩小为可观察的最小场景，适合重建为自有 fixture，并用 Windows 官方输出建立 positive/negative golden。

### 9.2 `inheritvaluefromevent` 的明确结构

官方预览确认：

- parent 的 child 类型是 `eventfollow`；
- child 粒子包含 `inheritvaluefromevent` operator；
- parent 到 child 的边只需要 `id`、`name`、`type`；
- 被继承字段的具体解释属于 child operator，而不是强塞在 child edge 上。

这直接约束 MyWallpaperX 数据模型：

```text
parent child edge
    -> id / name / type

child particle definition
    -> inheritvaluefromevent operator
    -> inherited field/value semantics
```

不应为了让单一样本运行，把 operator 参数复制到 child edge 或按样本 ID 建特殊分支。

### 9.3 当前隔离副本

本次已将 `inheritvaluefromevent` 官方目录复制到 Windows 临时隔离位置：

```text
C:\Users\songziqiang\AppData\Local\Temp\MWXSceneProbe\20260725-inheritvaluefromevent
```

副本包含 7 个文件：

```text
project.json
scene.json
template.json
materials\particle\halo_1.json
materials\particle\halo_1_1.json
particles\new_particle_system.json
particles\new_particle_system_child.json
```

复制后使用 `robocopy /MIR /L` 对比源和目标，结果：

```text
ROBOCOPY_RC:0
```

即停止操作时，隔离副本与官方源无待复制、额外或差异文件。该目录位于 Windows 用户临时目录，不是仓库资产，也不应提交。

## 10. 对 MyWallpaperX 的开发映射

### 10.1 可立即固化为 parser/IR fixture

| 官方证据 | 自有 fixture 应验证 |
|---|---|
| Effect 尾逗号 | 宽容 JSON 入口与严格 typed validation 分层 |
| 83 material + 1 copy + 2 swap | node kind 保留、有序解析、未知 command fail-closed |
| FBO format 集 | format 映射、未知 format diagnostic、byte budget |
| `unique: true` history | logical identity 与 alias 禁止合同 |
| `previous` bind | 前一有效输出解析和缺失输入 blocker |
| pass/bind/FBO condition | 分层 condition IR，不压成 Effect 总开关 |
| child edge 只有 `id/name/type` | edge 与 child operator 职责分离 |
| `eventfollow` + inherit operator | 父子 lifecycle 和每帧继承时机 |

所有 fixture 必须使用自有数值、名称、纹理和场景组织，避免复制官方 payload。

### 10.2 需要 Windows official golden 的合同

以下内容不能靠静态 JSON 关闭：

| 能力 | 必须观测的数据 |
|---|---|
| Motion Blur | 首帧 seed、连续帧 history、pause/resume、resize、seek |
| Fluid Simulation | condition 切换、function clear、ping-pong/swap、状态保留 |
| `inheritvaluefromevent` | event 发生帧、继承发生帧、每帧/仅初始、parent death/follow |
| Rope/Rope Trail | segment 数、根节点、world/local space、death 后收尾 |
| `particleeditor3dscale` | editor scale 到 runtime world transform 的映射 |
| Collision family | 接触边界、反弹/终止、模型/平面/球/quad 坐标系 |
| Remap family | clamp、输入范围退化、随机/曲线值、非有限数值 |

推荐每个能力都建立：

1. 官方原始 baseline；
2. 只改一个参数的 A/B；
3. 固定分辨率；
4. 固定时间步或固定捕获时刻；
5. 截图、短视频、像素 coverage 和运动差；
6. 进程、build ID、项目 hash 和参数 manifest；
7. MyWallpaperX 自有 fixture 的相同观测项。

### 10.3 推荐实施顺序

1. `inheritvaluefromevent`：字段职责已经清楚，适合先验证 event timing 和 inherited property 更新。
2. `rope` / `ropetrail`：直接覆盖当前 trail fail-closed 与 root/world-space 风险。
3. `particleeditor3dscale`：校准 3D/editor scale、root translation 与 world-space 变换。
4. Motion Blur：验证 history FBO、copy 和首帧/resize lifecycle。
5. Fluid Simulation：最后作为 condition、function、20-pass、ping-pong 和 swap 的综合压力门。

这一顺序以“先产生真实可见增益，再扩展语义表”为原则。每批先完成一个官方 Windows 正向对照，再决定是否修改生产代码。

## 11. 不应从本次证据推出的结论

本次检查没有证明：

- MyWallpaperX 已支持 46 个 stock Effect；
- 解析 50 个粒子 JSON 等于执行了 50 个粒子系统；
- D3D11 feature level 11.1 能直接映射为某个 Metal feature set；
- `scenescript32.dll` 的内部 VM、字节码或事件顺序已经掌握；
- `wallpaper32.exe` 的资源生命周期、blend 数学和 shader 算法已经被反编译；
- Wallpaper Engine 编辑器预览与桌面实际 renderer 在所有状态下像素一致；
- 官方 payload 可以进入 MyWallpaperX 仓库或发行包；
- 固定截图相似即可宣称动态语义一致。

仍需保持 unknown 的关键项：

- authored/custom shader 的完整跨平台预处理合同；
- history 在所有生命周期事件下的精确初始化规则；
- condition/function 的线程、时序和失败语义；
- SceneScript VM 内部执行模型；
- 音频、系统媒体、输入和 3D/Puppet 的完整官方运行语义；
- 官方 renderer 与编辑器 preview 的所有差异。

## 12. 停止时的安全状态

用户要求停止控制后已停止所有 Parallels/Windows UI 输入。

停止时状态：

- Wallpaper Engine 主 UI 已成功打开过；
- Wallpaper Engine 编辑器停留在欢迎页；
- 欢迎页显示最近项目 `123`，本次没有打开或修改它；
- 官方安装资源没有被编辑、删除或覆盖；
- Windows 用户临时目录中保留一份 `inheritvaluefromevent` 隔离副本；
- MyWallpaperX 源码、测试和运行矩阵没有因本次取证发生变化；
- 截至用户要求暂停控制时，仓库改动仅为新增本文档；之后的 macOS 副本扩展审查另补了 §14-§21 与 SceneScript 专项文档。

## 13. 与现有研究记录的关系

本文提供 Windows 正版官方客户端的本机证据，优先级高于不透明 renderer 的二进制字符串推断，并与以下文档互补：

- [Scene 参考项目只读审查](scene-reference-project-audit-2026-07-24.md)：第三方参考项目、许可证和架构线索。
- [Scene 参考项目与官方语义证据审查](scene-reference-audit-effects-runtime-2026-07-24.md)：Effect/runtime 专项交叉审查。
- [Scene 资料来源与证据索引](../scene/semantics/source-index.md)：官方网页、真实样本和证据入口。
- [Effect 执行覆盖表](../scene/semantics/effect-execution-coverage.md)：MyWallpaperX 当前逐项实现等级。
- [粒子组件覆盖表](../scene/semantics/particle-component-coverage.md)：MyWallpaperX 当前粒子 parser/runtime/visual 等级。

冲突处理顺序：

1. 当前代码与可重复运行结果；
2. 现役 capability ledger 和专项覆盖表；
3. 当前 Windows 官方客户端结构化资源与 official golden；
4. 官方公开文档；
5. 第三方可审计源码线索；
6. WaifuX 等不透明 binary 或 bake 的辅助线索。

本文是 2.8.42 / build `23967692` 的时间点快照。Wallpaper Engine 更新后，应重新记录 build ID、stock Effect/particle census 和关键 fixture hash，再决定本记录是否仍适用。

## 14. macOS 完整客户端副本扩展审查

用户随后把完整客户端副本复制到：

```text
/Users/songziqiang/Downloads/wallpaper_engine
```

本轮继续只读静态检查，没有执行其中任何 Windows 二进制，也没有重新控制 Parallels。范围边界如下：

- 总目录约 `1.8 GiB`、6524 个文件；`assets` 约 86 MiB，`projects` 约 146 MiB，`ui/uicache` 约 491 MiB。
- 目录体积大于 Steam manifest 的 `826,275,581` bytes，因为副本包含 UI cache、运行状态和用户侧目录；不能把 1.8 GiB 写成官方发行 payload 的净大小。
- 实际内容检查限定在 `assets`、`projects/defaultprojects`、`projects/templates` 和与它们直接关联的声明/素材。
- 未读取或修改 `config.json`、`config_backups`、`projects/myprojects/123`；没有把 cache 或用户项目纳入 schema 统计。
- 没有复制官方 shader、JSON、纹理、模型或二进制 payload 进入 MyWallpaperX。

因此，下文统计是“本机 2.8.42 完整副本中官方候选资源”的快照，不是 Steam 全版本、Workshop 全体项目或跨平台统一 schema。

## 15. SceneScript 随包实现合同

完整副本包含：

```text
assets/scripts/jsclasses/baseclasses.js
assets/scripts/jsmodules/wemath.js
assets/scripts/jsmodules/wevector.js
assets/scripts/jsmodules/wecolor.js
ui/dist/monaco/autocomplete/lib.sceneScript.d.ts
```

实现级合同已单独整理到 [SceneScript 运行时实现层合同](../scene/semantics/scenescript-runtime-implementation-contract.md)。本节只保留对开发排序最有用的摘要：

| 合同 | 随包直接证据 |
|---|---|
| 数值类型 | `Vec2/Vec3/Vec4/Mat3/Mat4` 有随包 JS 实现；判等 epsilon 为 `0.00001`，且边界使用严格 `<` |
| 矩阵布局 | Mat3/Mat4 按 column-major 索引；translation 位于 `6/7` 与 `12/13/14` |
| compose | Mat3 为 translation -> rotation -> scale；Mat4 为 translation -> Euler rotation -> scale；角度 API 使用 degree |
| 媒体枚举 | stopped `0`、playing `1`、paused `2` |
| Model data token | `position`、`normal`、`uv`、`tangentSigned`、`color` |
| 用户属性桥 | 普通类型取 `.value`；`color` 转 `Vec3`；`usershortcut` 只投影 `isbound/commandtype/file` |
| script property 更新 | 只更新脚本已声明 key；目标原值为 `Vec3` 时重新构造 `Vec3` |
| 自定义 script property | slider/checkbox/text/combo/color；combo 默认取第一个 option；整数 slider 序列化为 `mode: "int"` |
| 官方模块 | `WEMath` 的 mix 不 clamp；`WEVector` 角度制；`WEColor` 的 RGB/HSV 均使用 `[0,1]` |
| 全局共享对象 | `shared` 初始化为空对象 |

Monaco 随包声明只装载 ES5 到 ES2019 的类型库，且没有 DOM/Node/WebWorker 类型库。这能确认**官方编辑器的 authoring/type surface**，但不能单凭文件缺席证明 VM 会拒绝全部 ES2020+ 语法或同名 runtime global；VM 语法、global allowlist 和异常行为仍需官方运行实验。

## 16. 官方默认项目 corpus

`projects/defaultprojects` 有 19 个项目：14 个 `project.json` 明确声明 `type: "scene"`，2 个 Web，2 个省略 `type` 但入口为 scene-shaped JSON 的旧工程，以及 1 个 EXE 项目。以下 census 仍只统计 14 个明确 Scene，避免把扩展名 fallback 当成已确认的官方 loader 规则；完整 16 个 scene-shaped 工程的逐项目输入清单见 [官方默认工程 corpus](../scene/semantics/official-default-projects-fixture-inventory.md)。

| 项目 | 数量 |
|---|---:|
| Scene object | 101 |
| Effect instance | 41 |
| image 字段 | 65（64 个非 null 引用） |
| model 字段 | 24（21 个非 null 引用） |
| particle 字段 | 10（8 个非 null 引用） |
| point light | 3 |
| sound layer | 2 |
| text layer | 2 |
| inline SceneScript | 13 |
| `user` binding | 36 |
| condition | 5 |

两个省略 `type` 的 JSON 工程各有 4 个 model object；若按受限 `.json` fallback 纳入，scene-shaped corpus 为 16 个、109 个 object、29 个非 null model 引用，其余上表计数不变。该 fallback 是兼容候选合同，不是本轮静态文件已经证明的官方优先级。

### 16.1 shipping SceneScript 使用面

13 个内联脚本实际绑定在：

```text
object.origin
object.visible
effect.visible
effect pass.constantshadervalues
scene general.bloomstrength
```

出现的导出函数计数为 `applyUserProperties` 6、`update` 8、`cursorDown` 1、`init` 1。Dino Run 还直接使用了以下运行 API：

```text
engine.frametime
engine.registerAsset
input.cursorWorldPosition
thisScene.getLayer / getLayerIndex
thisScene.createLayer / destroyLayer / sortLayer
soundLayer.play
textLayer.text assignment
localStorage.get / set with LOCATION_GLOBAL
Math.random
```

Razer Bedroom 的 shipping 脚本使用 `Date.now()` 和裸模块名 `WEColor`。这证明 SceneScript 的最小有用实现不能只停在“执行一段 JS”：source/binding IR、逐帧时间、层查找、动态层生命周期、文字/声音句柄、输入、storage 和官方 module registry 都是实际默认项目 consumer。

### 16.2 object 字段合同

默认项目给出三类紧凑正向 schema：

| object | 已确认字段 |
|---|---|
| point light | `light: "point"`、`color`、`intensity`、`radius`、`origin`、`angles`、`scale`；可带显式 null 的 `model/particle/sprite` |
| sound | `sound` 文件数组、`playbackmode: "single"`、`mintime/maxtime`、`startsilent`、`muteineditor`、`volume`、`origin` |
| text | `text/font/pointsize/color`、horizontal/vertical align、anchor、size/scale/origin、depthtest、background、padding、width/row/ellipsis gates、visible binding |

这些 object 以“判别字段存在”区分类型，没有统一的 `type` tag。typed parser 不能假定所有 object 都有显式 kind，也不能因为 light object 同时出现 null 的其他资源字段而误分类。

### 16.3 user property 到 shader 的映射

默认项目 material 中有 51 条 `usershadervalues` 映射：12 条 source/target 同名，39 条不同名；Flag 官方模板另有 1 条不同名映射，因此 default projects + templates 合计 52 条。默认项目高频映射包括：

```text
schemecolor -> tint          19
schemecolor -> ambientcolor  5
```

因此 user property 名称与 material/shader parameter 名称必须作为显式 mapping 保存，不能按字符串同名自动推导。默认项目还证明一个 property 可以同时驱动 layer visibility、effect constant、scene general 和 material uniform。

## 17. Effect、Material 与 shader corpus 扩展

### 17.1 stock Effect metadata

46 个 stock Effect 的额外分布：

| 维度 | 值 |
|---|---|
| version | v1 39 个；v2 7 个 |
| group | colorize 17、animate 12、distort 5、blur/enhance/interactive 各 4 |
| dependencies | 216 条：JSON 74、fragment 68、vertex 68、PNG 3、TEX sidecar 3 |
| performance | 9 个 `expensive`；Fluid Simulation 是唯一 `veryexpensive` |
| gizmo | PerspectiveUV 9、PointEmitter 4、LineEmitter 3、SpinUV 2、SwingUV 1 |

Effect `condition` 的实际形状是 object array，而不是一个扁平 map。parser/IR 应保留原层级和顺序。

Motion Blur 的精确 topology 为：

```text
pass 0: target _rt_FullCompoBuffer2, slot0=previous, slot1=_rt_FullCompoBuffer1
pass 1: copy _rt_FullCompoBuffer2 -> _rt_FullCompoBuffer1
pass 2: slot0=_rt_FullCompoBuffer2 -> combine
```

`_rt_FullCompoBuffer1` 为 `rgba_backbuffer`、scale 1、`unique:true`；buffer2 同 format/scale 但非 unique。

Fluid Simulation 的 20-pass topology 进一步确认：pressure 是 pass 4...12 共 9 次；pass 16 normal 只在 `LIGHTING=1`；combine 使用 slot 0 dye2、slot 1 previous、条件 slot 2 normal 和条件 slot 4 velocity2，slot 3 明确为空；pass 18/19 分别 swap velocity 与 dye。纹理 slot 必须保留稀疏 authored index，不能 compact。

### 17.2 Material/render state

官方候选根中统计到 451 个 material JSON，当前快照均为单 pass。451 个 pass 的 state 分布：

| state | 分布 |
|---|---|
| blend | normal 210、translucent 154、additive 29；其余为其他或缺省形态 |
| cull | nocull 369、normal 7 |
| depth test | disabled 384、enabled 13 |
| depth write | disabled 399、enabled 7 |

同时存在兼容字段。在 `assets/` 与 `projects/` 下 1927 个 JSON 的全部层级 `passes` 元素上实测：`alphawriting` 60 处（值域 `default`/`enabled`）、`usershadervalues` 36 处（`{shader 值名: 用户属性名}`，如 `schemecolor: tint`，与 `constantshadervalues` key 不重叠）、`depthtesting` 与 `depthwriting` 各 3 处（值 `disabled`，全部出自 `projects/defaultprojects/ricepod`）、`culling` 1 处（值 `nocull`，出自 `assets/materials/util`）。typed parser 应在保留原始字段的前提下统一到 state IR，不能只接受当前实现偏好的拼写。

随包 utility model/material 给出明确角色位：

| 文件 | 角色字段 |
|---|---|
| `projectlayer.json` | `autosize:true`、`passthrough:true`、`projectlayer:true` |
| `fullscreenlayer.json` | `fullscreen:true`、`passthrough:true` |
| `solidlayer.json` | `solidlayer:true` |

depth-test 和 non-depth-test compose material 是独立变体。内置 render target 名还包括 `_rt_FullFrameBuffer`、`_rt_Reflection`、`_rt_Bloom`、`_rt_volumetricsLightBuffer`、quarter/eighth aliases 与 editor-copy 变体；它们是系统资源身份，不应作为普通相对路径打开。

### 17.3 shader declaration 与 annotation

`assets/shaders/declarations.json` 明确声明：

- static/animated image、normal-map image、r8/rg88 image shader；
- `genericimage4` 与 `generic4`；
- import format：`rgba8888/dxt1/dxt5/rg88/r8/rgba8888n/dxt5n`；
- texture flag：`clampuvs/halfmip/nomip/nointerpolation/nonpoweroftwo`；
- animated image 通过 `SPRITESHEET=1` 进入变体；
- 默认 image state 为 translucent、nocull、depth disabled。

对 `assets/shaders` 与 `assets/effects` 的 482 个 shader/header 源文件做注释 census：共找到 1411 条行尾 JSON annotation，结构化解析失败为 0。高频键包括 `material` 1114、`default` 1093、`label` 788、`range` 607、`hidden` 289、`group` 195、`mode` 118、`combo` 93；还实际出现 `require/requireany/linked/conversion/format/formatcombo/nobindings` 等关系字段。

同一 corpus 有 368 个不同 uniform 标识符，sampler 使用 `g_Texture0` 到 `g_Texture8`；唯一一个 `sampler3D` 位于 color-correction/LUT 路径。这里的 stock slot 8 只证明官方内部 shader 使用面，不能据此把公开 custom-effect 的 T0...T7 合同擅自扩成 T0...T8。

候选 frontend token、format branch 与后端解释已单独整理到 [Shader source 前置合同与跨后端假设审查](../scene/semantics/shader-prelude-and-backend-abstraction.md)。其中 token 使用/本地定义缺席是 A 级，binary 注入者、矩阵转置和 Metal 坐标映射仍是 C 级，不进入现役兼容承诺。

## 18. TEX sidecar 与 3D LUT 缺口

### 18.1 sidecar census

388 个 `.tex-json` 全部可结构化解析。format 分布：

| format | 数量 |
|---|---:|
| `rgba8888` | 224 |
| `r8` | 60 |
| `rg88` | 50 |
| `rgba8888n` | 19 |
| `dxt5n` | 9 |
| `dxt5n+` | 6 |
| `dxt5` | 5 |
| `rgb888` | 4 |
| `rg88n` | 2 |

高频字段为 `format` 379、`clampuvs` 324、`nonpoweroftwo` 291、`nomip` 170、`alphachannelpriority` 82、`spritesheetsequences` 58、`bleedtransparentcolors` 51、`nointerpolation` 47、`srgb` 10。另有 `spritesheet`、`frameduration`、`imagesequence`、`forcerawcompression` 和 `halfmip`。

sidecar 到 TEX binary code 的当前 corpus 映射：

```text
rgba8888 / rgb888 / rgba8888n -> 0
dxt5 / dxt5n / dxt5n+         -> 4
rg88 / rg88n                   -> 8
r8                              -> 9
```

### 18.2 TEXV0005 binary census

440 个 `.tex` 中：

- 412 个符合当前普通 `TEXV0005/TEXI0001` header 位置；
- container version 为 TEXB0001 42、TEXB0002 29、TEXB0003 241、TEXB0004 100；
- binary format code 为 0:229、4:72、8:51、9:60；
- 61 个带 animated flag，44 个 physical/logical extent 不同；
- 当前 corpus 的普通文件均为 `imageCount=1`，最大 physical dimension 为 4096。

### 18.3 28 个 LUT 的额外维度字段

`assets/materials/lut` 的 28 个文件也是 `TEXV0005/TEXI0001`，但 header 在普通 imageHeight 后多一个 UInt32，使 `TEXB0004` marker 从 offset 46 移到 offset 50。所有 28 个文件一致表现为：

```text
flags          = 0x42
textureWidth   = 32
textureHeight  = 32
imageWidth     = 1024
imageHeight    = 32
extra UInt32   = 32
```

`assets/shaders/ccsimple.frag` 在 `LUT` 变体中把对应资源声明为 `sampler3D` 并以 RGB 三分量采样。由“32、1024=32x32、32、sampler3D”共同支持的高可信结构推断是：额外值参与 32x32x32 3D LUT 的维度/上传合同。**随包文件没有公开这个 UInt32 的字段名，本文不为它发明名称。**

当前 [SceneTexContainer.swift](../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneTexContainer.swift) 固定从 offset 46 读取 `TEXB0001...0004`，因此这 28 个文件会在 `invalidHeader` 前置门失败。即使只放宽 offset，也不能直接闭合能力：loader 还需保留 3D extent、创建 `MTLTextureType3D`、验证 row/image stride，并实现 LUT stock shader profile 和像素门。不能把 1024x32 当普通 2D 颜色图后声称兼容。

## 19. 完整粒子 preset corpus

统计范围为 `assets/presets`、`assets/scenes/particleelementpreviews`、`assets/particles` 与 14 个默认 Scene：

| 项目 | 数量 |
|---|---:|
| particle JSON 路径 | 295 |
| SHA-256 不同 payload | 215 |
| JSON 解析失败 | 0 |
| emitter / initializer / operator / renderer | 3 / 16 / 25 / 4 |

25 个 operator 是对前文 26 的校正，并与 48 个 `particleelementpreviews` 目录总数严格对齐。

### 19.1 component 字段 union

Emitter：

```text
boxrandom: directions, distancemax, origin, rate
layerimage: rate
sphererandom: cone, controlpoint, delay, directions, distancemin/max, duration,
              flags, instantaneous, periodic delay/duration, emit-per-period,
              origin, rate, sign, speedmin/max
```

Initializer：

```text
alpharandom / angularvelocityrandom / lifetimerandom / sizerandom:
  min, max, exponent
colorlist: colors
colorrandom: min, max, exponent
hsvcolorrandom: huemin/max/steps, saturationmin/max, valuemin/max
inheritcontrolpointvelocity: controlpoint, min, max
inheritinitialvaluefromevent: no extra field beyond id/name
mapsequencearoundcontrolpoint: axis, bounds, count, limitbehavior, speedmin/max
mapsequencebetweencontrolpoints: arcamount, controlpointstart/end, count, flags, limitbehavior
positionoffsetrandom: distance, scale, timescale
remapinitialvalue: input, inputcontrolpoint0, inputrangemax, operation,
                   output, outputrangemin/max
rotationrandom / velocityrandom: min, max
turbulentvelocityrandom: offset, phasemax, scale, speedmin/max, timescale
```

Operator：

```text
alphachange / colorchange / sizechange: starttime/value, endtime/value
alphafade: fadeintime, fadeouttime
angularmovement: drag, force
boids: alignment/cohesion/separation factors, flags, neighborthreshold
capvelocity: blendinstart/end, maxspeed
collisionbounds / collisionmodel: no extra field beyond id/name
collisionplane: bouncefactor, distance
collisionquad: collisionbehavior, origin, size
collisionsphere: collisionbehavior, origin
controlpointattract: blendinstart, controlpoint, flags, origin, scale, threshold
inheritvaluefromevent: no extra field beyond id/name
maintaindistancebetweencontrolpoints: no extra field beyond id/name
maintaindistancetocontrolpoint: variablestrength
movement: drag, flags, gravity
oscillatealpha / oscillateposition: blendinstart/end, frequencymin/max,
                                      phasemin/max, scalemin/max; position adds mask
oscillatesize: frequencymin/max, scalemin/max
reducemovementnearcontrolpoint: controlpoint, distanceinner/outer,
                                  reductioninner/outer
remapvalue: blendinstart/end, flags, input, inputcontrolpoint0,
            inputrangemin/max, operation, output, outputrangemin/max,
            transformfunction, transforminputscale
turbulence: blendin/out ranges, mask, phasemin/max, scale,
            speedmin/max, timescale
vortex: axis, distanceinner/outer, flags, speedinner/outer
vortex_v2: controlpoint, distanceinner/outer, flags, ringpull distance,
           ring radius/width, speedinner/outer
```

Renderer：

```text
sprite: axis, orientation
spritetrail: length, minlength, maxlength
rope: subdivision, uvscale, uvscrolling, uvsmoothing
ropetrail: fadealpha, length, segments
```

### 19.2 lifecycle/范围合同

完整 corpus 的 child type 为缺省、`eventdeath`、`eventfollow`、`eventspawn`、`static`。child edge 可出现 `angles/controlpointstartindex/flags/maxcount/origin/probability/scale/type`；control point 可出现 `flags/id/locktopointer/offset/parentcontrolpoint`，实际 flags 包含 0/1/2/4/16。

范围与枚举证据：

- `maxcount` 1...25000；`assets/particles/exampleturbolence.json` 达 25000；
- `starttime` 0...200；Shimmering Particles 的 child 达 200；
- `sequencemultiplier` 1...3；
- `animationmode` 包含显式 null、`randomframe`、`sequence`；
- preset 出现 `eventspawn/static` child；
- remap `transformfunction` 出现 `simplexnoise/fbmnoise/sine`；input 出现 `distancetocontrolpoint/particlesystemtime`，output 出现 `velocity/opacity/speed`，operation 出现 `remap/multiply`。

这些是容量、typed enum 和负向门的依据，不是建议把 25000 设为通用硬上限。运行 budget 仍应结合每粒子 state、trail segment、overdraw 和设备能力。

## 20. MDL、模板与编译 shader blob

### 20.1 官方默认 MDL 版本暴露的缺口

官方候选范围共有 28 个 MDL：

| magic | 数量 | 来源 |
|---|---:|---|
| `MDLV0004` | 8 | 默认项目 |
| `MDLV0014` | 15 | 默认项目 |
| `MDLV0017` | 1 | editor camera asset |
| `MDLV0023` | 4 | 默认项目 3 + particle collision preview 1 |

MyWallpaperX 当前 Puppet mesh reader 只接受 `MDLV0021/MDLV0023`，rig/animation/attachment 更严格只接受已验证的 `MDLV0023` block。默认项目中 23/26 个 MDL 是 `MDLV0004/0014`，会被当前 Puppet reader 拒绝；这与 [高级对象覆盖表](../scene/semantics/advanced-object-coverage.md) 的“3D model L0”一致。

这些旧 magic 是官方默认 3D model corpus，不应通过给 `supportedMagics` 加字符串直接放行。其布局、vertex/index/material/node/animation 合同尚未解析，且 Puppet reader 不是通用 3D model loader。正确路径是独立建立 3D model IR 和版本化 reader，并用默认项目做只读 corpus/自有 fixture 对照。

### 20.2 官方 project templates

随包有 Flag 与 Animated GIF 两个模板。结构化字段确认：

- template type 为 `scene2d`；project 使用 `templateoptions`；
- Flag 的 `replacetexture` 带 `adjustprojection:true`、`animated:true`，material 使用非同名 `usershadervalues`；
- GIF 的 replacement 还带 `parameters.animatedonly:true`；option 可修改 compression、point filtering、noise reduction 和 dominant-color scheme；
- GIF sidecar 同时使用 `nonpoweroftwo/nointerpolation/clampuvs/nomip`。

这些是 importer/property contract 的输入证据，不代表 MyWallpaperX 需要实现 Wallpaper Engine editor 的模板 UI。

### 20.3 compiled blob 身份边界

随包 `.dxs` 有 241 个路径、68 个 basename、56 个不同 payload；`.gxs` 有 58 个路径、49 个 basename、58 个不同 payload。目录名包含 `blobsSM40` 与 `blobsGES3`，且同 basename 存在不同 payload（DXS 1 组、GXS 5 组）。

因此 compiled shader identity 至少需要完整相对路径、stage/backend/variant 或 content hash，不能用 basename 全局去重。MyWallpaperX 不应执行或复制这些 blob；它们只证明官方 cache 有 SM4.0/GLES3 变体和路径级身份。

## 21. 对开发计划的新增优先级建议

以下是证据导出的候选工作，不改变现役 [Scene 能力总账](../scene/semantics/coverage-ledger.md) 的等级和既定批次：

1. **TEX 3D LUT ingest**：先写自有 2x2x2/4x4x4 fixture，扩展 header/extent IR、3D uploader、stride/budget 和 fail-closed 测试，再用本机官方 neutral LUT 做只读解析对照和 Windows pixel golden。
2. **SceneScript Source/Binding IR**：先保留 13 个默认脚本实际出现的 owner/property target，不再压成 Bool；随后才接受控 VM、Vec/Mat、官方 module registry 和最小 layer/text/sound handles。
3. **粒子 event/trail/collision**：以 `eventspawn/static`、inherit、rope/trail、collision family 的官方最小预览重建自有 fixture；按 60 Hz 生命周期、实例数和像素门验证。
4. **Material state/annotation IR**：兼容 state 字段别名、稀疏 slot、annotation relationship；优先做 parser/validator，不复制 stock shader 数学。
5. **3D model 独立边界**：把 MDLV0004/0014 记入 versioned ingest backlog，但保持 P3，除非当前可见样本或计划重新排序；不得借 Puppet reader 快速放行。
6. **Windows official golden**：每批只改一个变量，固定 build ID、项目 hash、分辨率、时间点和生命周期事件；静态资源 census 不能替代运行输出。

最直接、且当前代码已经暴露明确失败点的是 3D LUT header/texture-type 合同；最广泛影响默认项目能力的是 SceneScript Source/Binding IR。二者都应先做小型自有 fixture，再决定是否进入产品实现。

## 22. `zcompat` 随包兼容记录

`assets/zcompat` 有 11 个文件：2 组 scene shader 候选目录和 5 个 Web patch record，其中 4 个 Web JSON payload 逐字节相同。scene 配置的 `maximumprojectid` 按字符串保存，其中一个值为 `9223372036854775807`；任何 parser 都必须先保留原始字符串，不能经 `Double` 往返。

作者 shader 还声明了 16/32/64 三档、左右声道分别命名的 audio spectrum uniform。静态声明只约束 binder identity，不能证明 Windows renderer 实际填入独立 stereo 数据。

这批文件不能静态确认 ID 的身份、`maximumprojectid` 比较方向、Web replace 的首次/全量策略、缺文件/零匹配行为或补丁应用时机。详细 A/C 边界见 [zcompat 向后兼容机制取证](../scene/semantics/zcompat-backward-compatibility-forensics.md)。MyWallpaperX 若建立兼容层，应使用自有、版本化 manifest 与隔离 fixture，不复制官方或 Workshop shader/patch payload。
