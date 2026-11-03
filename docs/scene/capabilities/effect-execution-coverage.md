# Effect 与组合层执行

<!-- document-role: current-state -->

<a id="execution"></a>
## 当前执行方式

Effect 名称是作者内容与编辑器分类，不是渲染算法选择器。definition/material/shader 先进入共享准备链，GraphExecutor 编码其有序节点，再由唯一 compositor 输出。能读取某个 effect 定义或执行一个节点，不代表整套效果/样本已完成。

| 类别 | 当前共同消费 | 需要分别证明 |
|---|---|---|
| 动画、Pulse、Shake、Spin 等 | typed 参数、时间、UV/顶点与原材质 Program | 参数来源、坐标域、起点与所有动态组合 |
| Blur、Bloom、放射与多 pass | 原 target、source/previous 输入及有序图 | 工作尺寸、颜色/alpha、history 与末合成 |
| 交互、水波与扭曲 | 原 pointer/world/camera、采样与 Program | 输入命中、持续手势、依赖与真实输出几何 |
| 颜色、叠加与 mask | typed sampler purpose、颜色表示及 blend | 独立信号、数据通道、输出 alpha 与未支持表达 |
| 生成、光线、Fluid 等 | 已准入作者 Program、source carrier 或共享图 | 多输入、前后背景、反馈及官方同状态画面 |

材质和采样细节见[Shader/Graph](render-graph-shader-coverage.md)，不为每个效果建立独立 runtime、时钟、resource registry 或输出。

<a id="composition"></a>
## Composition、背景与依赖

固定 parent 分组在 topology 准备边界形成成员与执行顺序，当前 visibility 只门控真实消费。组根按作者位置合成，child 不在组外重复绘制。`copybackground` 缺省/true 使用当时 enclosing 背景，false 从透明源开始；不能改成全局最终画面或末后代 prefix。

嵌套组与 named provider 沿原 pool、reservation、typed dependency 和 pin 工作。隐藏 provider 仍可能被活 consumer 使用，不能因不可见清除其准备或发布。跨 consumer 的背景 prefix 依赖与独立 prepass 不是同一语义。

无 child 的 captured-main source Program 只在作者顺序截点捕获并编码，不移到整个层循环前批处理，不拿历史 framebuffer 充当当前背景。source capture MVP 与最终 output MVP 分开；透视、深度、passthrough 和带依赖 utility 的支持范围由原 SourceRoute/Camera/Dependency owner 决定，不强行改成普通 quad。

源码：[Composition runtime](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayerRuntimePlan.swift)、[Dependency runtime](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyFrameRuntime.swift)、[Graph composition](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneResolvedMaterialGraphComposition.swift)。

<a id="fallback"></a>
## 局部失败与显示权

- 普通 effect 视觉失败在已证明安全的边界保 previous-current/graph-final；错误来源、epoch、资源或 ABI 拒绝最小不安全单元，不能吞掉后继续读取陈旧资源。
- 未取得 effect 执行权时，合法静态 source 可由原 draw-only 降级绘制。绘制权与 named/publication 权分开，不能把 base source 冒称 effect 输出供其他层使用。
- alpha 脚本由真实 scalar VM owner 发布 typed 值，Timeline 与用户属性沿同一 resolver。准备期未取得 alpha 值 owner 时，只释放无 owner 的显示压制并保作者值，不运行另一套脚本文本解释器，不强制改 visible。
- bad return、异常或预算失败不以错误值覆盖已有健康 current；其他 owner 继续。JS heap 中已经发生的 shared 写入不能被宣称撤回。
- effect visibility 是 prepared activation 的消费者。已准备安全图可热切，未准备或不支持目标保原重建/拒绝边界；多节点 history 重新启用的首帧仍需独立资格。
- 保留背景 RGB 的文字 source 若在首阶段编码前被停用，或因 library、pipeline、局部视觉失败走旁路，先恢复普通字形 source，再绑定原 passthrough。input publication、generation 与颜色表示随同恢复，避免背景泄漏或末端重复合成。后续阶段不重取场景背景。

源码：[Source passthrough](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneLayerSourcePassthroughPlan.swift)、[effect activation](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+Preparation.swift)。

<a id="limits"></a>
## 明确限制

任意复杂 dependency/copy-background 前后关系、全部 passthrough/native perspective utility、跨 pass Combined、所有 Fluid/反馈和所有官方效果像素均未覆盖。现有条件或 profile 只限定其本身的能力，不能因名字相同复用未证明的数学。

新增输入沿原 generic preparation、typed binding、target、camera 和 compositor 扩展；先取得可区分正反例，再决定是缺能力、错误输入还是观测问题。开放项及下一资格见[队列](../roadmap/scene-open-breakpoint-queue.md)。
