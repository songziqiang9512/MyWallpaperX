# Scene 通用执行重构计划

> 状态：现役执行计划
>
> 启动日期：2026-08-15
>
> 当前阶段：G0 治理转向与基线准备

## 1. 目标

把 Scene 主线从“为已知 effect、表达式或样本逐项建立严格准入路径”转为“解析作者数据，由少数通用编译器、VM 和执行器覆盖未见内容”。Swift + AppKit、Swift + Metal 和现有资源/生命周期底座继续保留；重构重点是减少产品执行 owner、消除按已知 family 扩张的专用路线，并让失败尽量局部降级。

目标运行链为：

```text
project / scene / package / assets
  -> loss-preserving Scene IR
  -> authored state evaluation
  -> generic shader/material compiler
  -> generic RenderGraph compiler
  -> SceneScript ECMAScript VM / particle component interpreter
  -> one Metal graph executor and compositor
```

这不是完整重写，也不承诺 Wallpaper Engine 像素等价。当前能力真值仍由[覆盖台账](semantics/coverage-ledger.md)和[运行证据索引](semantics/runtime-evidence-index.md)给出；本文只决定迁移顺序、停止项和验收方式。

## 2. 不做什么

- 不引入 Vulkan/MoltenVK、完整 C++ renderer、第二套 UI 或第二条 compositor 主链。
- 不按 sample、layer、path、asset ID、hash 或已知 stock 名称选择算法。它们只可用于 identity、缓存、provenance、诊断和回归定位。
- 不再默认新增 `SceneAuthored*Planner`、effect-specific native renderer、固定脚本解释器或每种 family 的产品准入 catalog。只有无法由现有通用 IR 表达的真实新 primitive 才能例外，并须在批次说明中写清复用面和退役条件。
- 不为了“架构整齐”先删除现役 fallback；旧路径只在新路径取得对应产品执行权后按精确清单退役。
- 不用 compiler 接受源码、非黑帧、进程存活或单样本通过宣称完整兼容。

## 3. 产品失败策略

| 失败类型 | 产品行为 | 例子 |
|---|---|---|
| 安全或状态完整性风险 | 硬拒绝相关 scene/layer，记录稳定诊断 | 路径逃逸、越界 GPU range、target hazard、资源预算溢出、VM/compiler timeout/OOM、stale handle、生命周期破坏 |
| 局部视觉能力失败 | 只停用失败的 pass/effect/script binding/particle system，保留可安全执行的 base layer 和其他对象 | shader 编译失败、未知 optional state、单个 provider 不可用、单个粒子 renderer 不支持 |
| 可选输入缺失 | 使用作者默认值、关闭相应 combo 或保持原始输入 | optional texture、可选 uniform、媒体状态暂缺 |
| 非关键未知元数据 | 保真、告警、继续通用执行 | 编辑器 metadata、未知但未被执行路径消费的字段 |

不得伪造资源、绑定、history 或 target 来换取非黑画面。局部降级必须有 typed status 和诊断，不能静默切换到另一个算法。

## 4. 保留、收敛与退役

### 4.1 继续作为公共底座

- Project/Scene/PKG/TEX/VFS 解析和 loss-preserving typed IR；
- host、surface、frame clock、属性 snapshot、资源/provider generation 与生命周期；
- Metal target pool、GraphTargets、layer dependency、publication、compositor；
- image/video/text/audio/media 等已经通用化的 producer；
- 现有测试 fixture、隔离样本工具和运行证据格式。

### 4.2 收敛为少数产品 owner

- authored shader compatibility preparation + 一个可替换的通用 compiler backend；
- material/texture/state/reflection 到统一 Program 的解析器；
- effect/FBO/copy/swap/compose/condition/history 到统一 RenderGraph 的编译器；
- 一个 GraphExecutor 负责 ordered preparation、encoding、publication 和 compositor handoff；
- 一个真实 ECMAScript VM 加 typed host bridge；
- 一个按 authored component/schema 分发的粒子解释器和少数通用 GPU/CPU primitive。

### 4.3 迁移期 oracle，之后退役

现有 bounded Swift shader frontend、exact planner、effect-specific renderer、固定 SceneScript compiler 和严格 family catalog 可以在迁移期用于差分、fixture 和明确 fallback。它们不得继续决定新内容是否获得产品执行权；每个迁移批次应撤销至少一个被替代的专用 owner，或明确说明该批为什么只是建立尚不能撤销 owner 的公共前置。

## 5. 快速纠偏机制

每个实现批次开工前只回答四个问题：

1. 本批新增或扩展的通用 primitive 是什么？
2. 一个从未见过的合法内容是否能自动受益？
3. 失败时能否只降级局部而不破坏状态完整性？
4. 哪个旧专用 owner、dispatch 或 admission 将被撤销；若暂时不能，阻塞条件是什么？

若第 1 或第 2 项没有具体答案，停止实现并改写任务；不得把更多已知名称加入表、planner 或 switch。若验证发现通用路径扩大 crash、整层拒绝或明显视觉回退，则先回滚该批的产品路由，保留诊断和 fixture，再缩小公共 primitive 重做。不得通过收窄 corpus、删除反例或把失败改成 `unsupported` 来制造通过。

批次状态只使用 `planned / running / passed / failed / rolled-back`。一个批次保持可独立回滚、可独立提交；不把 shader、VM、粒子和 3D 多条迁移同时堆在未验证工作区。

## 6. 执行波次

### G0：治理转向与基线

交付：

- 顶层规则、长期技术边界、Scene 导航和本计划采用同一通用执行口径；
- 把覆盖台账、专项表和能力依赖图重新限定为事实/依赖入口，不再充当逐项专用实现队列；
- 在不覆盖现有脏改的前提下，后续实现批次先记录 scene 启动、base layer 可见、shader/material/graph/script/particle 成功与局部降级的可取得基线。

完成门：规则/文档链接门通过，本治理批次独立提交。G0 不声称运行能力变化。

### G1：通用 shader 与 material 执行

先完成作者 dialect 的 loss-preserving preparation、通用 compiler backend、reflection/ABI/state 校验、pipeline cache/取消/预算和统一 Program。现有 Swift frontend 作为已验证子集 oracle；新 backend 可以在受控开关下取得代表 corpus 的产品执行权，不要求在第一次执行前穷举所有作者语义。

完成门：项目自有正反 fixture、未见内容 fixture、只读隔离 corpus compile census、代表样本 GPU/terminal compositor/next-frame；compile 失败能局部 passthrough；新能力不依赖 exact effect/sample dispatch。

### G2：通用 Effect/FBO RenderGraph

把 authored pass、bind、target、clear、copy、swap、compose、condition、named target 和 history 编译到统一 graph IR，由单一 executor 执行。专用 planner 逐步退为 oracle 或删除。

完成门：顺序、slot hole、target identity、hazard、resize/reset 和局部失败隔离有项目 fixture；代表普通链、FBO 链和复合链可见运行；相同结构的新 effect 不需要新增 Swift planner。

### G3：真实 SceneScript VM

选定并集成 QuickJS-NG 或经同等评估的 ECMAScript VM，建立 per-surface domain、module allowlist、typed handle、批量 mutation、event/timer/time、预算和 teardown。停止扩展 Swift 自制 JavaScript parser/compiler。

完成门：语言/模块/host API 代表 fixture、无限循环/异常/OOM/stale handle 负门、代表 corpus 运行和性能基线；单个脚本失败只回退其作者值或 binding，不终止整场景。

### G4：粒子组件解释器

按 authored General/Emitter/Initializer/Operator/Renderer/Child schema 解释组件，把差异压到数据和少数通用 primitive；不为每个效果名建立 renderer。

完成门：未知 optional component 可诊断降级，非法状态硬拒绝对应 particle system；代表 emitter/operator/renderer 组合和 child/event 生命周期通过；新组合无需新增名称分支。

### G5：高级通用 primitive

在 G1-G4 稳定后按真实 corpus 影响面增加 3D mesh/skinning、camera、lighting/HDR、Puppet 和离线输出所需 primitive。仍遵守数据驱动、局部降级和单一 executor。

## 7. 验证与指标

验证按风险分层，不再要求每个微小语义改动都刷新全 corpus 或写一轮台账：

- `inner`：受影响 parser/compiler/VM/executor fixture，包含至少一个未见内容或组合反例；
- `checkpoint`：定向测试、build verify、代表 corpus 的 compile/plan census；
- `integration`：涉及 GPU、生命周期或可见输出时，运行少量代表隔离样本，检查局部降级、publication、terminal compositor 和 next-frame；
- `milestone`：跨 family、矩阵合同或发布节点才运行 fixed/full，并记录 corpus fingerprint。

持续指标按可取得基线逐步建立，不预写没有测量来源的百分比目标：

- scene 启动、base layer 可见、shader stage compile、material pass 与 graph node 执行率；
- SceneScript module/API、particle component 与 provider 的执行/局部降级分布；
- 整场拒绝、局部降级、crash-free、首帧、CPU/GPU frame time 和内存；
- 专用产品 owner、按名称 dispatch 和 Swift 自制语言解释代码的净减少量。

用户可见 fidelity 修复仍需预定义 ROI/事件断言；架构批次或广度迁移可用代表多样性、结构化 diagnostics 和链路证据验收，不能把所有任务都变成单样本像素证明。

## 8. 文档与提交纪律

- 本计划决定迁移顺序；[能力依赖图](semantics/capability-dependency-map.md)只表达前置关系，[覆盖台账](semantics/coverage-ledger.md)和专项表只表达当前事实，[运行证据索引](semantics/runtime-evidence-index.md)只表达已运行证据。
- 小批次不重复改写所有专项表；只有能力等级、产品 owner、matrix 合同或现役运行事实变化时才同步对应权威文档。
- 目录移动与功能迁移分开提交；功能批次必须显式列出取得产品执行权的通用 owner、被撤销的旧 owner、fallback 和实际门。
- MirageWallpaper 等第三方项目只作 clean-room 结构对照；不得把其实现细节、shader、资产、常量组合、算法表达或测试 payload 复制进本项目。

## 9. 退役条件

同时满足以下条件后，把本文在 `docs/document-role-index.json` 中改为 `historical-evidence`：

1. 通用 shader/material compiler、RenderGraph compiler/executor、SceneScript VM 和粒子组件解释器均已取得各自产品执行权；
2. 产品路径不再用 exact effect/source/sample/path/hash 作为 capability admission 或算法 dispatch；
3. 被替代的 exact planner、effect-specific renderer 和 Swift 固定脚本 compiler 已删除，或明确隔离为不参与产品路由的测试 oracle；
4. fixed matrix、与当前 fingerprint 一致的 full snapshot、故障隔离和性能基线共同证明迁移没有扩大 crash/整场拒绝；
5. 当前架构与运行事实已回写长期合同、覆盖台账和运行证据索引。
