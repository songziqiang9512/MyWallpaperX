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

成员接纳以实际绘制所需的投影与输入为边界，不按类型许可名单。无 draw 的变换、相机元数据、声音和全局灯光成员保留完整 parent 闭包、作者顺序与显隐，由原 owner 消费；不要求它们产生颜色源。当前 model、spotLight 绘制尚未消费组的局部 raster，保持相关 source 局部拒绝。image/solid/text、particle 与 direct-draw quad 使用原 world frame、组 raster 与唯一 compositor；不新增容器 renderer 或资源/状态 owner。


<a id="source-free-quad"></a>
### 无原始图层源的 quad

quad 由已编译 launch envelope 的完整准备结果、实际 sampler 与 graph 输入决定可执行性；`DIRECTDRAW` 只选择作者 shader 分支。已具 typed 用途的显式资产位于 slot0 与其他 slot 使用同一 TextureResolver/Program/PassEncoder，不因编号0推定它读取图层源。真实 implicit framebuffer、graph alias/candidate 或 graph binding 仍需自身供货合同；缺资源、未准备或需要不存在的图层源时只拒受影响输出，不能将透明初始化冒充 source。

父层由原 hierarchy/world frame、direct-draw output geometry、nearest group raster 与唯一 compositor 消费，不是独立许可。结构接纳保 parent 闭包、成员/依赖与实际 source 约束，Host 仍须取得该 quad 已准备的 transparentDirectDraw capability/material 才发布显隐消费者。初始隐藏沿原准备与 activation 链恢复；显隐更新保原原子事务、window/Surface 与当前输入状态。移除 parentID=nil 和 sampler slot0 的整类限制，不增加 owner、许可表、缓存、资源副本或普通帧检查。

验收分别核真实 prepared slot0/其他slot资产与隐式graph反例，再以完整App验证嵌套/非均匀父变换、初始关闭后启用/再次关闭、改名、实际采样颜色与健康peer。截图须匹配原capture/CB/Surface/seal/GPU和该quad→组source→父Program→main的实际消费。已有可见父层quad与独立作者作为相邻回归；结构/prepare通过不代GPU或逐像素结果。

嵌套组与 named provider 沿原 pool、reservation、typed dependency 和 pin 工作。隐藏 provider 仍可能被活 consumer 使用，不能因不可见清除其准备或发布。跨 consumer 的背景 prefix 依赖与独立 prepass 不是同一语义。

Utility provider 在原 source 触发点执行一次，由同一 compositor 发布；当前可见输出继续主合成，隐藏输出只供 named consumer。资源与 ticket 合同见[Named 输入职责](render-graph-shader-coverage.md#named-input-ownership)。

无 child 的 captured-main source Program 只在作者顺序截点捕获并编码，不移到整个层循环前批处理，不拿历史 framebuffer 充当当前背景。source capture MVP 与最终 output MVP 分开；透视、深度、passthrough 和带依赖 utility 的支持范围由原 SourceRoute/Camera/Dependency owner 决定，不强行改成普通 quad。声明依赖与实际来源的区分见[Framebuffer 来源合同](render-graph-shader-coverage.md#framebuffer-source-declarations)。

源码：[Composition runtime](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayerRuntimePlan.swift)、[Dependency runtime](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyFrameRuntime.swift)、[Graph composition](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneResolvedMaterialGraphComposition.swift)。

<a id="project-subtree-source"></a>
### Project 子树来源

Project 的后代沿原 utility 组来源、执行顺序和合成职责接入。根之前的 enclosing 背景与该根的后代共同进入父级 effect；数组中位于根之后的无关层保持后置。省略 `copybackground` 的 project 保留背景输入，显式值仍由作者选择。官方有界观察仅涵盖顶层、可见、满画布、正交、identity 变换及省略 object config 的输入；stock model 的 passthrough/autosize 元数据本身不能证明来源截点或覆盖其他组合。

`SourceRoute` 在原准备边界选择来源并保 parent 闭包；`RuntimePlanner` 把同一成员集交给既有组排序与 capture 计划。`CaptureGeometry` 消费实际组源的局部 extent 或 enclosing viewport，`GroupFrameRuntime/MainPass` 负责原 target、背景复制和成员栅格；父 Program 读取这一来源，唯一 compositor 在根位置输出。资源、clock、粒子模拟、named publication 和 GPU pin 继续由各自原 owner 持有，普通帧不重新判断子树资格。Project 的 childless 绘制与 fullscreen 的来源职责分别保留。

来源、预约或 Program 失败沿原组的局部失败与输出释放处理，健康后继继续；模型或 spotlight 缺少局部 raster 消费者的边界另行定位。验收同时核背景、跨色底 child、中间非 child 与后置遮挡的真实像素，再核改名、静态 effect-off、无效果与背景字段反例；作者雨层须闭合粒子目标→父来源→mask Program→末合成，独立样本保相邻能力。动态显隐准备范围归[开放问题](../roadmap/scene-open-breakpoint-queue.md)，官方 hidden、named、嵌套、TRS、显式配置及 REFRACT 数学继续保持各自资格，不能由本观察外推。

<a id="particle-subtree-raster"></a>
### 粒子子树栅格合同

成员粒子进入作者指定的 composition source，父级 Program 消费该 source，并由原 compositor 输出一次。实际 pass 的栅格映射由原 MainPass 提供；没有独立容器 renderer、相机、模拟器、资源池、快照或准入认证状态。

- canonical camera VP、viewport、world/model 与 basis 继续决定粒子、SpriteTrail/RopeTrail 的几何和连接。不能把局部 target 像素尺寸代入拖尾的屏幕垂线解算；非均匀画布或物理尺寸缩减会改变该度量。
- MainPass 的既有 world-clip → source-clip 映射提供齐次归一后的 X/Y 两行。ParticleLayerUniforms 在原字段之后携带这两行；vertex 先完成原几何，再从同一个原 clip 计算目标 XY，保留原 Z/W。主画面和 viewport source 使用 identity，两行不产生另一个矩阵或状态 owner。局部组保持自身粒子的深度关系，最终组仍作为一个平面回绘。
- REFRACT 保留既有 normal 解包、原 screen tangent 排列与全局 screen-UV amount 语义；同两行给出 UV 位移映射 `[[X.x, -X.y], [-Y.x, Y.y]]`，不能归一化后丢失尺寸或镜像。实际 attachment 的 extent 继续只供 depth、snapshot、fragment 背景采样和分配使用。官方 composition 内 amount 单位尚未取得有效对照；该内部一致性合同不能冒称官方像素一致。
- 此两行合同消费 affine 的局部画布映射；任意 projective composition 并未由 authored orthographic 条件自动获得资格。MDL Rig 与 Attachment reader 已按 affine 合同接纳的四项 W 行容差在各自原解析入口规范为 `[0,0,0,1]`，其余十二项不变；bind、旧版 reference 和 attachment 沿原 world 链传递严格 affine 值。容差外仍由原格式入口拒绝，实际动态非法 pose 仍归原 Puppet owner，内部不重新认证同一输入或夹取已组合的 skin 矩阵。
- SourceRoute 的粒子成员由已接通的实际消费者处理；model、可见 spotlight 等未接通的消费者分别保持其明确缺口。已能准备 source 的 composition，初始关闭的 effect 沿同一 source/hierarchy 保留 stage，typed 开关启用既有 Program。依赖/provider 仍由其原所有权约束决定。

验收覆盖实际 production vertex 的非对称旋转/剪切/镜像、原 Z/W 与近远深度、非均匀拖尾及 REFRACT 正控/零强度/零遮罩；区分 authored canvas 与物理 allocation 尺寸，并保留无组的相邻行为。真实作者需核 source capture、成员实际目标、父级执行与末合成及画面，不能仅凭 route 或非黑通过；startup-inactive 的启用、隐藏/失败组与 peer 不泄漏另验。无法取得源/target 的情况沿原最小组降级和 pin 终态，不新增整体拒绝。

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
