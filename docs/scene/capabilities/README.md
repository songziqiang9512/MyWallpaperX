# Scene 当前能力

<!-- document-role: current-state -->

本目录说明当前代码能执行什么、关键作者语义和明确限制。职责与执行顺序由[运行时架构](../architecture/runtime-architecture.md)规定；实际运行范围见[当前证据](runtime-evidence-current.md)，未闭工作只在[开放队列](../roadmap/scene-open-breakpoint-queue.md)维护。

<a id="overview"></a>
## 能力总览

| 能力 | 当前实现 | 主要限制与入口 |
|---|---|---|
| 文件、资源与作者图 | project/scene、所选 loose/package/stock 资源、material/effect 和有序图准备 | 格式被读取不等于全部字段有执行消费者；见[格式](scene-format-and-render-graph.md) |
| Shader、材质与采样 | 准备变体、通用编译器、typed texture/uniform、PSO 预热与逐帧绑定 | 未准入的语言、资源角色和颜色闭包局部拒绝；见[Shader/Graph](render-graph-shader-coverage.md) |
| Effect 与 composition | 共享 MaterialProgram/GraphExecutor、copy/swap、history、named 输出及组合层 | 不按效果名称授予算法；复杂依赖与显示语义仍有边界；见[Effect](effect-execution-coverage.md) |
| SceneScript | QuickJS-NG、真实模块与 heap、属性回调、事件、typed host API | 官方声明面大于当前 host 实现；动态资源、句柄及副作用按实际入口限定；见[API](scenescript-api-coverage.md) |
| 属性、Timeline、相机与输入 | typed 属性更新、轨道与播放状态、当前相机投影、Cursor/Audio/Media | 并非所有目标或 producer 组合均可热更；见[运行输入](runtime-input-property-coverage.md) |
| 文字与图像动画 | 会话共享动态文字生产、CoreText 排版、Sprite 时间采样与逐屏消费 | 字体精确像素及完整布局组合仍需独立对照；见[输入与文字](runtime-input-property-coverage.md#text) |
| 粒子 | prepared 组件计划、真实 CPU 模拟、child、Sprite/Trail/Rope 与 GPU 提交 | 未支持操作、空间/flags 和 child 组合明确局部拒绝；见[粒子](particle-component-coverage.md) |
| 模型、Puppet、光照与显示 | bind 几何、有界骨骼动画/裁剪、共享 camera/light、模型阴影及 HDR 输出 | 附加通道、reference composition、部分几何/光照组合未覆盖；见[高级对象](advanced-object-coverage.md) |
| 视频与声音 | 原媒体 registry/source/voice、Scene 时钟意图、解码发布与退出 | 隐藏视频后台解码停用尚无完整语义资格；见[媒体](material-video-assets.md) |
| 生命周期 | 请求/候选、逐屏冻结帧、拓扑活动退休、GPU/worker/媒体 drain | 普通 App、DEBUG direct Host 和物理桌面是不同观察边界；见[组件职责](runtime-systems-reference.md) |

<a id="reading"></a>
## 修改入口

- 先确定作者输入、prepared 事实、当前值、资源发布及最终输出分别由谁持有，查[组件职责](runtime-systems-reference.md)。
- 参数变化进入原 typed 状态；结构和资源变化在原准备边界处理。普通帧不重新解析、编译或重建完整图。
- 使用现有最近行为门；构建、解析、非黑和少量样本均不证明完整能力。执行方法见[开发工作流](../development/development-workflow.md)。
- 官方 API 声明与固定客户端观察只说明相应来源；不能直接写成 MyWallpaperX 的执行事实。来源规则见[来源索引](../development/source-index.md)。

具体未支持项写在对应能力页；下一资格与优先级写开放队列。性能目标及可比较测量见[性能卡](../roadmap/performance-convergence-card.md)。
