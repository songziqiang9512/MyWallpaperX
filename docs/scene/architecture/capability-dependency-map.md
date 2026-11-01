# Scene 公共能力依赖参考

<!-- document-role: reference -->

本页帮助定位一个能力需要哪些公共数据和执行职责。总体规则归[运行架构](runtime-architecture.md)，组件生命周期归[组件合同](../capabilities/runtime-systems-reference.md)，当前接线归[事实地图](runtime-as-built-map.md)，支持范围与结果归[能力台账](../capabilities/coverage-ledger.md)和[运行证据](../capabilities/runtime-evidence-current.md)。这里不重复等级、提交、样本、准入形状或完成门。

## 1. 依赖图

```text
D0 作者来源与格式 → D1 身份、顺序与依赖
D2 时间、输入域与生命周期 → D3 类型化绑定与状态更新
                           → D4 输入快照与事件
D0 + D1 + D2 → D5 资源与 provider
D1 + D5 → D6 渲染图、目标与使用期
D0 + D3 + D5 → D7 材质与 Shader Program
D1 + D2 → D8 坐标、相机与几何
D3 + D4 + D5 + D6 + D7 + D8 → D9 图层与特效消费
对应数据与消费者 ↔ D10 行为、模拟与媒体
对应数据与消费者 → D11 高级对象与其他输出宿主
```

D0–D11 是阅读坐标，不是开发阶段、额外类型系统或严格拓扑。系统运行时与渲染消费者互相提供声明好的数据依赖；同帧 producer/consumer、历史与事件顺序由实际图和语义决定。一个切片只需闭合实际消费的部分，不能要求整层全部完成才允许出画面。

### 1.1 如何使用本图

从真实用户结果找到首个错误消费者，再沿其输入回到缺失的公共能力。优先修正通用数据、准备或执行职责，让同类作者内容共同受益。依赖图不按名称、样本数量或既有测试形状选择视觉算法。

## 2. 公共底座

<a id="d0"></a>
### D0 Source / VFS / Scene IR

保留 project、scene、包、纹理、材质、脚本与组件的作者事实和来源。外部格式、范围与必要类型在入口确定一次，再交付 typed 数据；未知可选字段不变成整场景播放许可。

来源与格式分别查[来源索引](../development/source-index.md)、[格式与渲染图](../capabilities/scene-format-and-render-graph.md)。资源路径只定位内容，不选择执行算法。

<a id="d1"></a>
### D1 Stable identity and dependency graph

身份、作者顺序、parent、资源引用、更新依赖和渲染读写各有明确作用。层级树不能替代更新顺序或 Pass 图；拓扑实际变化时才更新相关引用。

命名输出、历史与 provider 复用既有身份和发布链，具体语义查[格式与图合同](../capabilities/scene-format-and-render-graph.md)与[组件关系](../capabilities/runtime-systems-reference.md#02-数据与依赖方向)。

<a id="d2"></a>
### D2 Host/surface frame context and lifecycle

Session 的权威时间与共享模拟每 cadence 推进一次；viewport、pointer、必要的每屏 CPU 实例及 GPU 目标保留 surface identity。共享时间不要求共享全部状态，也不要求每屏独立 VM。暂停、重绘、GPU deferred 与恢复遵守[帧和退出合同](runtime-architecture.md#8-scene-播放生命周期与落代码合同)。

<a id="d3"></a>
### D3 Typed values, binding program and state update

属性、Timeline 与 SceneScript 指向同一实际状态。准备结果确定目标、类型和所需执行；本帧只求值与写入相应状态，不在 renderer 重解字符串或维护可写镜像。

scene 与 surface 输入在实际消费者处组合；共享模拟、局部状态、typed mutation 和每屏提交具有不同边界，不能统一假装可以回滚 VM heap。精确顺序查[组件合同](../capabilities/runtime-systems-reference.md)，当前 carrier 查[代码地图](runtime-as-built-map.md)。

<a id="d4"></a>
### D4 Input snapshots and event queues

pointer、音频、媒体、属性和动画事件由唯一来源生产。事件快照、实时 getter、按钮边沿与帧当前值分别表达，按真实 owner 和可观察顺序消费。

事件支持范围查[SceneScript API](../capabilities/scenescript-api-coverage.md)和[输入专项](../capabilities/runtime-input-property-coverage.md)；这里不再把不同事件合并为一个未实现等级。

<a id="d5"></a>
### D5 Texture, media and provider registry

来源/provider 生产资源，registry 在实际发布边界提供 typed 状态，图与 compositor 消费引用。资源身份、版本、颜色、采样、尺寸和使用期沿真实消费者传递，不靠文件名猜用途。

动态图片、文字、视频、封面和命名输出分别保留实例寿命；旧异步结果不能覆盖新请求。具体采样与视频合同查[sampler](../capabilities/sampler-alias-precedence.md)和[视频资源](../capabilities/material-video-assets.md)。

<a id="d6"></a>
### D6 Render-target graph and resource lifetime

Pass 顺序、读写、copy/swap/compose、target/history、发布及 GPU 完成共同决定资源使用期。history 不由某个特效私有维护，frame-local 与跨帧保留分别表达。

拓扑与目标语义查[格式与图](../capabilities/scene-format-and-render-graph.md)，预算归[资源合同](scene-resource-admission.md)。局部执行失败只影响真实依赖，不扩大到无关内容。

<a id="d7"></a>
### D7 Material and shader contract

源码、include、宏、注解、候选纹理、反射、参数与渲染状态在实际准备边界组成完整 Program。普通帧编码当前值及资源，已有上传能力不再列作未来阶段的完成门。

编译语义查[Shader 合同](../capabilities/shader-prelude-and-backend-abstraction.md)，槽位和采样查[sampler 合同](../capabilities/sampler-alias-precedence.md)，真实支持范围查[能力台账](../capabilities/coverage-ledger.md)。

<a id="d8"></a>
### D8 Coordinate spaces and geometry

canvas、view、world、layer、effect、particle 和 control point 空间明确转换。源采样域、effect 工作域、几何与最终投影各有用途；相机、parent、附件、命中和 skinning 消费同阶段 canonical frame。

几何合同查[模型与绑定](../capabilities/direct-model-bind-geometry.md)及[组件职责](../capabilities/runtime-systems-reference.md)，不能让各消费者另补一套坐标算法。

## 3. 消费层

<a id="d9"></a>
### D9 Generic layer and effect execution

图像、文本、视频、粒子与几何从已准备数据和本帧状态进入同一图与 compositor。新增作者组合优先补公共 primitive，不重建名称专属 renderer、私有时钟、history 或输出链。

<a id="d10"></a>
### D10 System runtimes

| 运行职责 | 主要依赖 | 语义 owner |
|---|---|---|
| Timeline、属性与 SceneScript | D2、D3、D4及实际资源消费者 | [行为与绑定](../capabilities/runtime-systems-reference.md#4-timeline) |
| 粒子、child 与事件 | D1–D5、D7、D8、D9中实际使用部分 | [粒子定义、模拟和绘制](../capabilities/runtime-systems-reference.md#2-particle-system) |
| 文本 | D3、D5、D9及实际行为输入 | [文本 producer](../capabilities/runtime-systems-reference.md#3-text) |
| 音频、媒体与动态资源 | D2、D4、D5及实际消费者 | [宿主输入与纹理](../capabilities/runtime-systems-reference.md#7-cursoraudiomedia-与动态纹理) |

这些职责按数据连接，不构成“先完成整个 VM、再做文本或粒子”的顺序。文本可执行语言归真实 VM，文字 producer 不另建解释器；现存双路径按[重构队列](../roadmap/scene-open-breakpoint-queue.md#51-顶层设计已裁决的代码职责重构)退出。

<a id="d11"></a>
### D11 Advanced runtimes and output hosts

Puppet、3D、光照、HDR、RGB 和离线输出复用相关身份、时间、资源、几何及合成职责。不同输出宿主可以采用不同时间和 provider 输入，不另建视觉算法；实时跑通不证明离线、锁屏或完整高级对象兼容。[组件合同](../capabilities/runtime-systems-reference.md#8-puppet3d-和-lighting)与[能力台账](../capabilities/coverage-ledger.md#7-高级对象与输出覆盖)分别维护目标和范围。

<a id="4-与现役-v0-v5-路线的关系"></a>
## 4. 与现役路线的关系

任务选序归[兼容路线](../roadmap/scene-compatibility-roadmap.md)，具体未闭项归[唯一队列](../roadmap/scene-open-breakpoint-queue.md)，工程职责迁移归[重构设计](../roadmap/engine-refactor-program.md)。D 节点只检查本次实际依赖，不复制任何路线阶段、当前缺口或验收表。

## 5. 禁止的冲突路径

公共禁止项由[总设计](runtime-architecture.md#3-基于上述证据的-mywallpaperx-处理策略)统一维护：不建立重复权威，不按样本选算法，不把可选资源或诊断变成播放许可，不在普通帧重做准备，不伪造发布、回滚或完成。本页不再维护第二份条款。

## 6. 使用顺序

先从现役任务及真实结果确定消费链，再用本图定位依赖；到对应合同、源码和证据检查其范围。只修改需要的公共职责，按实际变化选择最近验证，替换完成撤旧 owner。微小内部变化不触发全库文档刷新。

归整前的能力摘录、来源和旧阶段叙述保留在[固定快照](../history/capability-dependency-map-through-2026-11-01.md)，不作为当前状态。

<a id="dependency-map-before-convergence"></a> [归档记录](../history/capability-dependency-map-through-2026-11-01.md#dependency-map-before-convergence) <!-- archive-redirect -->
