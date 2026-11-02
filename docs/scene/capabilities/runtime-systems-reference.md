# Scene 组件与运行系统职责

<!-- document-role: stable-contract -->

本页规定组件分类、状态所有权、生命周期和作者语义。总体执行链、语言与失败合同归[运行时架构](../architecture/runtime-architecture.md)，实际接线归[代码地图](../architecture/runtime-as-built-map.md)。组件完成度归[能力台账](coverage-ledger.md)及专项表，运行结果归[运行证据](runtime-evidence-current.md)；本页不保存 commit、样本数量、能力等级或当前任务顺序。

公开作者语义以 Designer 文档与 [SceneScript v2.8 声明快照](../development/reference/lib.sceneScript-v2.8.d.ts)为来源。raw JSON、固定客户端静态观察和项目近似分别保留来源，不把它们合成未验证的官方数值合同。

## 0. 组件分类与责任

组件按承担的工作分类，作者文件、效果名称和预设不自动对应新 Swift 类型。复用已有数据和执行器表达组合；新的公共抽象须承担真实状态或复用职责。

| 类别 | 保存什么 | 负责什么 | 不承担什么 |
|---|---|---|---|
| 节点公共状态 | identity、作者顺序、parent、变换、可见性 | 空间关系与公共属性目标 | 每种内容的专属状态、GPU 资源 |
| 类型专属状态 | 粒子、文本、模型、相机、光源、媒体实例 | 各类内容的模拟与物化 | 另一套时钟、属性树或最终输出 |
| 行为 | Timeline、SceneScript、用户属性、输入绑定 | 按规定时机读写具体目标 | 保存可写的场景副本或直接操纵窗口 |
| 共享资源 | 纹理、网格、字体、声音数据、编译产物 | 来源解析、复用、驻留与失效 | 实例播放位置、随机状态、历史反馈 |
| 材质与渲染步骤 | 参数布局、资源槽、状态、Pass 与依赖 | 从准备结果完成 GPU 工作 | 逐帧解析作者配置或按特效名选择视觉算法 |
| 宿主输入与输出 | 显示、音频、媒体、窗口、播放意图 | 系统采集、策略与桌面展示 | 解释组件数学或建立第二 compositor |

### 0.1 从输入到释放

每个组件沿同一链路交付：**作者输入 → 准备好的定义与引用 → 当前实例状态 → 编码或资源发布 → 完成与释放**。这些是职责边界，不要求额外创建五个 wrapper。

| 能力族 | 准备阶段 | 可变状态 owner | 编码或发布 | 退出边界 |
|---|---|---|---|---|
| 属性与 Timeline | typed target、类型、曲线、播放分组 | live property state、Timeline playback runtime | immutable dynamic snapshot | 会话与对应 owner |
| SceneScript | source、绑定、模块、导出事件、handle | 单一 VM domain 及 property owner | typed mutation、事件与资源需求 | owner removal、timer/job 撤销、domain 销毁 |
| 粒子 | 定义图、组件操作、通道、资源与 child 模板 | 每个实际系统实例的 simulator 与 child 状态 | renderer-specific instance/rope geometry | root/child 停止、GPU 使用结束 |
| 文本 | 字体、样式、布局约束、动态字段 | 文本值及待生成/已完成 generation | 正常 layer source | 任务取消或排空、纹理退役 |
| Puppet/模型 | mesh、材质、骨骼、clip、attachment | 播放、pose、约束与实例 | GeometryProduct、mask 与同一图层合成 | 实例结束及相关 GPU completion |
| 视频与动态图片 | 来源、权限范围、格式与播放定义 | source/provider、播放意图、当前帧 | typed texture publication | source 停止、任务排空、旧帧失效 |
| 声音 | 音频资源、播放和空间参数 | voice/source 状态 | 音频输出与脚本状态投影 | 停止 voice 后释放资源 |
| 相机与光照 | 默认投影、路径、光源与材质需求 | 当前相机、参数与必要模拟 | shared camera frame、光照/阴影 Pass | 会话或相关资源失效 |
| 材质与图 | Program、binding、render state、target/history | graph execution、逻辑资源映射 | 唯一 compositor 的输入 | 资源/提交完成与会话结束 |

共享时间不等于共享全部实例。scene/surface 的具体域由[运行时架构](../architecture/runtime-architecture.md)规定；viewport、pointer、history 和 GPU 目标保留实际 surface identity。不可变资源可以共享，实例状态只在语义允许时共享。

### 0.2 数据与依赖方向

| 关系 | 权威与变化边界 |
|---|---|
| parent 层级 | canonical transform/visibility owner；创建、删除、换 parent 或相关状态改变时更新 |
| update 顺序 | 行为执行和回调可见点；按语义准备，不因组件类型批处理擅自重排 |
| render 依赖 | Pass 读写、资源版本和发布关系；拓扑、绑定或相关变体变化时更新，不从 parent 推断 |

专属作者格式可以保留在粒子、文本等类型族入口，完成准备后交 typed 状态；目录纯净不构成搬迁或新 wrapper 的理由。依赖屏幕输入、视口或 localStorage 的 CPU 状态可以由 Session 按 surface identity 隔离，只有语义允许的模拟才共享。

`Format` 保存作者事实；`Runtime/Frame` 的描述及 `Compilation` 准备消费者需要的类型；`Systems` 更新领域状态；`Resources` 提供资源；`Rendering` 消费准备数据和本帧状态。跨层只传当前消费者所需数据。

作者初值、准备引用与当前值分别有用途。动态Layer只保出生资源、不可变创建尺寸、根关系和seed；完整upsert经原typed值通道更新，不按authored局部写的字段标记丢弃其余当前值。创建、排序和退役改变结构revision，同revision的准备投影不回填live字段；perspective缺席保camera默认，首次实际Bool写入才增加typed lane。属性访问不另建可写layer tree，非法变换仍拒实际受影响owner包。

动态根变换只更新这些根；作者层级与attachment沿同一canonical局部矩阵算法。动态clone变化不要求重发全部作者catalog的Mat4。Session在回调前捕获已提交拓扑和值，末尾接纳Plan；首次采用拓扑的cadence同时采用其定义与当前值，不额外延迟，也不扩大原camera、visibility和particle当帧例外。

## 1. 统一 Frame Context

同一 host frame 只采样一次单调时间与现实日期。行为与内容消费明确的帧输入，不能由每个 effect、particle 或 script 自行读取系统时钟。

```text
Host frame
  frameIndex / sceneTime / wallDate / effective delta / discontinuity
  audio snapshot / media snapshot / property revision
    -> 实际 scene/surface 输入
       viewport / pointer / camera frame / resource publications
         -> 按兼容顺序更新状态与 typed mutation
         -> immutable dynamic snapshot
         -> GPU encode / publication / presentation
```

播放时间、图层或系统局部时间、现实 time-of-day 和资源 readiness 分开。局部速率和暂停从权威时间推导，不创建第二个全局时钟。具体 raw/simulation/dropped delta、暂停和确认行为归[运行时架构](../architecture/runtime-architecture.md)与[时钟现况](runtime-input-property-coverage.md)，本页不另定常数。

### 1.1 Frame timing、wall date 与 readiness 分离

frame delta 来自单调时间；wall date/time-of-day 独立采样；资源或视频未就绪影响实际消费者。暂停恢复先重设采样基线，避免把全部暂停时长注入恢复首帧。零步长重绘可以重新展示已准备内容，不因此重复派发一次性事件。

播放、离线和测试输入可使用不同时间来源，但经过同一更新和渲染入口。随机种子可控制只证明自有重放能力，不自动证明与参考客户端随机序列相同。

### 1.2 Reset 与 interruption 是跨资源事务

停止、资源重建与暂停分别表达。现有会话和宿主 owner 统一处理时钟、任务、target/history、媒体及脚本生命周期，不在各组件新增独立 reset coordinator。

异步结果在实际发布入口确认仍属于当前请求；GPU 资源按提交完成时机退役。暂停策略由唯一系统策略 owner 汇总，恢复重新考虑仍生效的原因，不无条件重启作者已停止的动画、发射器或 voice。

### 1.3 Surface 策略是请求合同

clone、span、per-display 与 selected/disabled display 是宿主请求策略。共享只读资产与 host time，保留各输出视口、输入、目标和释放身份。一个实例由一个 owner 推进；多个输出不重复累计同一时间，也不因一个表面暂时无法呈现而重放已消费的脚本。

## 2. Particle System

粒子按 General、Emitter、Initializer、Operator、Renderer、Control Point 和 Children 组织。prepared definition/plan 保持作者组件顺序，实例保存存活粒子、随机、发射和 child 状态，GPU 保存对应绘制数据。

官方入口：[Introduction](https://docs.wallpaperengine.io/en/scene/particles/introduction.html)、[General](https://docs.wallpaperengine.io/en/scene/particles/component/general.html)、[Emitter](https://docs.wallpaperengine.io/en/scene/particles/component/emitter.html)、[Initializer](https://docs.wallpaperengine.io/en/scene/particles/component/initializer.html)、[Operator](https://docs.wallpaperengine.io/en/scene/particles/component/operator.html)、[Renderer](https://docs.wallpaperengine.io/en/scene/particles/component/renderer.html)、[Control Point](https://docs.wallpaperengine.io/en/scene/particles/component/control_point.html)、[Children](https://docs.wallpaperengine.io/en/scene/particles/component/children.html)。具体字段、数值近似与已验范围只维护在[粒子专项](particle-component-coverage.md)。

### 2.1 General

General 包含 material/albedo/normal、cutout、lighting、refraction、overbright、blend、最大数量、预热、worldspace、perspective、sprite sheet 和实例覆盖规则。它决定所需通道、资源和绘制能力。

发射意图、存活粒子、显示资格与播放状态分开。`pause`、`stop` 和显隐不能简单共享一个布尔值。实例 override 按相应属性的出生/存活消费语义应用，不因重绘重复乘到既有状态。

### 2.2 Emitters

| Emitter | 作者语义 |
|---|---|
| Sphere random | 围绕 origin/control point 在球或圆范围发射 |
| Box random | 在矩形或盒范围发射 |
| Layer image | 从 image、text 或 puppet source 发射，可继承图层颜色与 motion |

Sphere/Box 的 offset、direction/sign、distance、control point、rate、instantaneous、duration、delay、periodic emission、speed 与 audio response 分别保留。多个 emitter 按声明顺序执行。

one-per-display-frame 的限制与固定模拟子步分开；instantaneous burst 不自动归并为 rate emission。Layer Image 在源内容需要时更新 emission 数据；文字变化或动态纹理变化不意味着每个渲染帧都重建 bitmap。不能为发射而常态读回整屏。

### 2.3 Initializers

Initializer 仅在出生时按作者顺序执行。能力族包括 Lifetime random、Size random、Color random、HSV color random、Color list、Alpha random、Velocity random、Inherit control point velocity、Turbulent velocity random、Rotation random、Position offset random、Angular velocity random、Position around control point、Position between control points、Remap initial value 与 Inherit value from event。

Random min/max 与 exponent bias 分别表达。`min=max` 是固定值，Velocity initializer 自身不推进位置。噪声、RNG、端点、色彩空间及缺省值按独立语义确认；组件名称和编辑器描述不能给出完整公式。

### 2.4 Operators

| 组 | Operators |
|---|---|
| 基础运动 | Movement、Angular movement、Cap velocity |
| 生命周期曲线 | Alpha fade、Size change、Color change、Alpha change |
| 振荡 | Oscillate position、Oscillate alpha、Oscillate size |
| Control Point | Force、Maintain distance、Reduce movement |
| 场与群集 | Turbulence、Vortex、Boids |
| 数据 | Remap value、Inherit value from event |
| 碰撞 | plane、sphere、bounds、quad、model |

blend-in/out window 使用相应 normalized lifetime 语义，不误当秒数。gravity、worldspace、drag、邻域、bounce/slide/stop/delete 和事件分别实现。碰撞在作者规定的 operator 位置参与，不能统一移至全部运算之后。

未知操作记录受影响组件，不能跳过后宣称整个系统完整兼容。已经确定的类型、常量和声明检查在准备时完成，运行时只保留动态值与实际状态所需检查。

### 2.5 Renderers

| Renderer | 几何与绘制语义 |
|---|---|
| Sprite | 独立 sprite，orientation/worldspace、图集与 frame blending |
| Sprite Trail | 沿速度拉伸，length 与速度及 min/max length 共同确定几何 |
| Rope | 按正确粒子顺序连接，subdivision、连续 UV、smoothing/scroll |
| Rope Trail | 为粒子保留独立轨迹，segments、subdivision、UV 与淡出 |

一个系统可能包含多个 renderer，共享粒子状态，各自生成需要的数据。不能只取首项，或把 Rope 替成 Sprite Trail。非方形纹理的宽高比、切线、法线、排序、birth identity 和轨迹归属沿绘制数据传播。

CPU 模拟与 GPU 打包/绘制职责分别明确。保留已有 prepared 操作、通道与发射计划；GPU 优化以相同输入和行为对照为依据，替换完成后移除无消费者旧路径。

### 2.6 Control Points

Control Point 0...7 可配置 relative offset、pointer lock、worldspace、parent copy/raw value 及编辑器显示信息。位置与角度是不同输入，均可被相应组件消费。

Emitter、Initializer、Operator、Collision 和 Children 按各自空间转换。screen cursor 不能直接当世界坐标。Control Point Force 的吸引/排斥、Maximum distance，与近中心减速或删除等独立操作分开；不额外叠加未声明的行为。

### 2.7 Children 与事件

| Type | 触发语义 |
|---|---|
| Static | 在系统 origin 创建一次 |
| Event follow | 创建并持续跟随 parent particle 的 child |
| Event spawn | parent particle 出生时在相应位置创建 |
| Event death | parent particle 结束或被删除时创建 |

Child 保留 offset、angles、scale、maximum count、probability、control point 与事件值继承。共享不可变定义，运行状态归具体 child 实例；池化复用需复位相关状态，不能重新解析整份定义。

创建、跟随、死亡、事件值捕获和同帧可见点按对应语义确定。生命周期与变换链使用同一实例身份，避免 child 间误连 Rope 或共享随机/历史状态。

### 2.8 正确的粒子执行顺序

准备阶段固定 emitter/initializer/operator 的作者顺序及通道需求；普通更新由既有模拟 owner 处理发射、初始化、顺序运算、事件和 child，再物化绘制数据。事件处理和 child 的精确相对时机服从已验证合同，不由通用示意图任意改序。

预热通过相同模拟路径形成初始分布；只提高累计时间无法得到等价粒子状态。root 与 child 的局部时间、动态 CP 和覆盖参数共享明确的本帧输入。

### 2.9 确定性和预算

存活数量、child 数量、预热和实际生成几何决定真实成本。工作限制只保护实际分配或执行风险，在对应入口处理，不为每种字段形态增加多层准入。

实时与离线记录所用步长与丢弃时间。暂停是否冻结、恢复是否 catch up、低 FPS trail 补偿与 operator 阻尼分别验证。停止后实例不再发布结果，GPU 使用中的资源在 completion 后释放。

## 3. Text

### 3.1 Text 是 Scene object

文本保留图层变换、alpha/color、parent、parallax、字体、point size、对齐、padding、背景、透视和布局约束。内容可以来自作者初值、属性、Timeline 或 SceneScript，输出进入同一 ordered effect stack 与 compositor。

脚本执行归通用SceneScript；文本系统消费字符串、样式和目标。literal动态文字沿完整record更新content；prepared wrapper的String producer保有当前结果，其普通upsert仅在显式text写入时更新content，outer-user优先级保持。出生seed固定后，模板初值取同Plan最终内容，不用旧record覆盖String结果。

### 3.2 macOS 文本运行时合同

CoreText/CoreGraphics负责字体解析、shaping、glyph advances、baseline、ascent/descent/leading与栅格。字体值复用原路径normalizer；显式系统默认与缺少当前值分开，前者不能回退出生字体。fallback来源与替代身份可诊断；stock同名不证明字形等价，等宽替代仍须保相应形态。

`ITextLayer.pointsize`公开单位为300 DPI下的point；typed current保合法原始Double，仅文字producer按原显示范围归一。作者像素padding扩大geometry，序列化size已包含时不重复增加。边对齐以内容边为据，中心对齐保持共同中心；raster backing scale、scene unit与Retina输出分别验证。

在 text-local 空间完成布局，再应用图层和场景变换。width/line/ellipsis、字体、字距和行距按作者开关与参数执行；关闭 width/row 限制时，保留的编辑器默认数值不能继续裁切文本。

内容或布局依赖改变时只重做受影响文本。会话共享producer、内容签名、generation及单在途合并；首次接纳动态层即消费同cadence typed值，不逐帧回写Layer。raster颜色与layer tint保各自既有乘色语义。每屏保存prepared/submitted纹理及几何，cursor读本屏最后提交结果；初始与动态文字走同一layer-source，不保旧base seed。单屏重建不关闭producer，会话停止排空任务并撤销迟到发布权。

字形呈现与布局分别设计。MSDF、轮廓、阴影和模糊的适用语义及与参考结果的差异查[文字专项](runtime-input-property-coverage.md)和[字体演进研究](../development/reference/client-changelog-forensics.md)，不从一个技术名推断全部字形质量或视觉等价。

### 3.3 Text 验收

同字体、字号、画布下比较 baseline、bounding box、glyph 位置、CJK/combining mark/emoji、对齐、换行、省略与 padding。保留公开 user-property 示例的 20pt/32px padding 对照及 12/24 小时、seconds、delimiter 等脚本属性用例。

文本效果与普通图层使用同一 graph。文字缩短、移动、连续更新与停止后不得残留旧内容或任务。多图层压力验证稳定性与释放，测试规模按实际风险选择。

## 4. Timeline

Timeline 绑定具体 component property；与 effect 自身动画分别表达。官方入口：[Introduction](https://docs.wallpaperengine.io/en/scene/timeline/introduction.html)、[Combined](https://docs.wallpaperengine.io/en/scene/timeline/combined.html)、[Modes](https://docs.wallpaperengine.io/en/scene/timeline/modes.html)、[Animation Events](https://docs.wallpaperengine.io/en/scene/timeline/animationevents.html)。

### 4.1 播放合同

| 项 | 语义 |
|---|---|
| Loop | 到末尾后循环 |
| Mirror | 到末尾后反向并循环 |
| Single | 一次播放后保持结束状态 |
| Seconds / Frames | 时长和作者关键帧网格分别保留 |
| Start paused | 等待显式播放意图 |
| Wrap loop frames | 按作者规则衔接首尾 |
| Bézier | 保留左右切线、自动或关闭插值等状态 |
| Combined animation | 不同属性可以共享播放 owner 与时间位置 |

播放位置归唯一 Timeline playback owner，成员绑定不各建时钟。play/pause/stop/setFrame 与脚本 setter 的同回调顺序进入 mutation；Single 完成后的 replay 及释放 setter 的边界查[现役行为与证据](runtime-input-property-coverage.md)，不把某组已验组合外推到任意播放冲突。

### 4.2 Animation Events

事件记录所属 animation frame 与名称，按跨越语义发送给同层 SceneScript `animationEvent`。声音、创建图层等后续行为由脚本决定。seek、反向、循环和长步长的重复或漏发分别验证。

### 4.3 求值与 FPS

曲线按明确的播放时间求值，不按每个显示 callback 加一个 keyframe step。同播放时间应得到一致属性；模拟及脚本调用频率按各自合同处理。

handle 编码、relative、wrap 单位和求根规则由[Timeline/输入专项](runtime-input-property-coverage.md)承接；本页不建立第二套数值解释。准备时解析轨道与目标，普通帧不重建绑定和动画分组。

## 5. SceneScript

### 5.1 官方合同

SceneScript 是 ECMAScript 基础上的 property-bound 环境，不含浏览器 DOM，增加 wallpaper API。官方入口：[Introduction](https://docs.wallpaperengine.io/en/scene/scenescript/introduction.html)、[Reference](https://docs.wallpaperengine.io/en/scene/scenescript/reference.html)、[声明文件](https://docs.wallpaperengine.io/reference/lib.sceneScript.d.ts)。

绑定记录包含 source、owner、目标属性、作者初值和类型。`init(value)`/`update(value)`接收当前 typed value，兼容返回值写回绑定目标；直接赋值允许修改其他属性。没有返回值时不擅自用 undefined 覆盖当前值。类型由目标属性确定，不因字符串含空格就推断向量。

### 5.2 生命周期和事件

| 组 | 事件 |
|---|---|
| 生命周期 | `init`、`update`、`destroy`、`resizeScreen` |
| 配置 | `applyUserProperties`、`applyGeneralSettings` |
| Cursor | `cursorEnter`、`cursorLeave`、`cursorMove`、`cursorDown`、`cursorUp`、`cursorClick` |
| Media | `mediaStatusChanged`、`mediaPlaybackChanged`、`mediaPropertiesChanged`、`mediaThumbnailChanged`、`mediaTimelineChanged` |
| Animation | `animationEvent` |

`animationEvent`由官方 Timeline 页面确认，本地 v2.8 `IComponent` 列表未列出，保留这一来源差异。`applyUserProperties`初次通知与后续仅携变化键的语义分别处理，不能把增量对象当完整属性表。`resizeScreen`不因创建而任意额外派发。

只注册实际导出的事件。纯事件绑定不逐帧空调用；timer、初始化及已排队事件按真实需求唤醒 owner。事件快照与可实时查询的 getter 分开，回调顺序和新建/销毁对象的同帧行为服从统一 frame 合同。

### 5.3 对象/API 面

| 能力族 | 主要表面 |
|---|---|
| 值与数学 | Vec2/3/4、Mat3/4、CameraTransforms、WEMath、WEVector、WEColor |
| 内容 | ILayer、Image/Text/Sound/Model、相机与场景 |
| 材质与特效 | IEffectLayer、IEffect、IMaterial、材质函数 |
| 模拟与播放 | ParticleSystem/Instance、Animation/Layer、TextureAnimation、VideoTexture |
| 宿主输入 | engine、input、renderContext、媒体与音频 |
| 共享与服务 | shared、localStorage、console、用户配置快捷方式 |

API 聚合不要求内部巨大对象。typed bridge 解析 handle 并访问同一状态；普通值、资源、geometry、Program variant 和拓扑变化分别按[最小失效域](../architecture/runtime-architecture.md)处理。VM 不持有 Metal 对象、窗口或第二个场景。

真实 VM 承担语言语义，Swift/C bridge 承担类型、handle 和生命周期。首个 API 切片需要从真实回调到既有 consumer，不等待完整平台，也不为固定源码增加专用执行器。

### 5.4 安全和资源边界

默认不暴露 Node、任意文件、网络、shell 或 native module。模块与资源读取使用已授权入口；组件内部不层层重验同一来源。

中断与内存控制保护真实的无限执行、栈或内存风险，预算和失败半径归 VM/会话 owner。类型与 handle 转换在桥接入口完成，内部消费已确定的数据。脚本异常局部处理，不能把所有视觉错误升级为整场拒绝。

stop/removal 撤销 timer、job、订阅与动态对象的发布权；destroy 由唯一生命周期入口派发一次。`shared` 和 JS heap 不假装能通过恢复 Swift snapshot 回滚。

### 5.5 SceneScript 模块边界静态互证

固定客户端研究区分 module、engine instance、property owner 与事件桥，其意义是核对生命周期，不要求复制 DLL、版本握手或线程结构。Timer 的播放时间、取消、长帧不追补与 owner 销毁用例独立验证；具体来源与限制见[客户端静态研究](../development/reference/client-runtime-static-forensics.md)。

项目 VM 与语言接入选择归[技术栈合同](../../architecture/technology-stack-boundaries.md)。已有合理的真实 VM、事件索引和 typed owner 继续复用，迁移只撤销重叠的手写语言路径，不为了独立方案的语言建议重新造一套 VM。

## 6. User Properties

| 类型 | 值与职责 |
|---|---|
| color | 颜色空间与 Vec/string 转换 |
| slider | 数值、范围、整数/小数与默认值 |
| bool | 具体绑定目标，不按同名 effect 推断行为 |
| combo | 保存和传递 option value，显示 label 分开 |
| textinput | 字符串与实际消费目标 |
| texture | 图片/视频来源、授权和解码生命周期 |
| usershortcut | 用户明确配置后由 macOS 宿主执行 |
| group / display condition | UI 分组与显示条件，不是运行值或销毁信号 |

项目定义、用户 override、有效值与 typed target 分别表达。属性窗口读 project 定义，Shader 编辑参数不自动成为用户属性。独立可拖动属性窗口继续属于产品设计，不进入 Scene 绘制树。

`texture`与样本中的`scenetexture`可在已确认范围归一为内部资源类型，同时保留原始来源；不能外推所有版本 raw schema 相同。Texture Variants 的 Checkbox/Combo 选择与普通文件替换分开，公开作者合同不授予 SceneScript 任意切换 variant。

文件授权只在入口取得，保持到实际读取完成。坏替换保旧资源，异步结果核对请求身份。value-only 更新只写对应状态，资源、combo 或拓扑变化才触发相应准备；不能一律 relaunch。

## 7. Cursor、Audio、Media 与动态纹理

### 7.1 Cursor

保留 screen-normalized、canvas/world、object-local、effect-local 坐标及 previous pointer。共用 canonical world frame 和 camera，不另做一套 parallax 或命中坐标。图层显隐、solid、传播、hover/capture 和销毁分别处理。

平台负责输入来源与桌面交互资格；Scene 负责几何命中、候选顺序、传播和事件。按实际几何和视口转换验证旋转、裁切、透视、Puppet 与多屏。输入保留事件顺序和按钮边沿，当前 pressed 状态不能代替所有事件。

### 7.2 Audio

采集与频谱分析由唯一共享平台服务提供，Scene 的脚本、Shader、粒子及 Web 根据需求消费。公开 SceneScript 档位为 16/32/64，提供 left/right/average；Shader 与粒子的参数 schema 各自解析。

无消费者时停用不必要采集；静音、无权限或无数据使用明确的稳定输入策略，不伪造波形。数组身份、采样保持、刷新时机、频率边界、幅度映射及动态音量处理分别验证。原始 FFT worker 的静态结果不能代表公开 AudioBuffers 全链，旧“无平滑/无动态处理”推断以研究中的后续更正为界。

分开验证注册需求、频谱数值和最终 consumer。具体分析与项目近似归[共享频谱设计](../../architecture/system-audio-spectrum-design.md)，当前接入和证据归[输入专项](runtime-input-property-coverage.md)。

Sound 与系统频谱是不同职责。声音资源可共享，voice 的播放位置、循环、gain、空间化与设备状态属于实例。prepare/play/pause/resume/stop/dispose 和 device reset 明确处理；自身 Sound 是否进入系统分析由采集范围决定。

### 7.3 Media

status、playback、properties、thumbnail 与 timeline 使用各自可用事件及变化身份。歌曲或流的切换关联元数据、封面、派生颜色与播放状态，旧异步结果在发布入口被丢弃。

`$mediaThumbnail`是系统 provider，不是普通路径。准备阶段确定需求，变化时解码和发布；last-ready、作者 fallback、清空和失败分开。无消费者时解除不必要订阅，停止后撤销 observer 和任务。

同一会话共享封面producer与就绪publication，每cadence一次snapshot供VM及各屏消费；请求沿会话待提交输入在任一表面提交后发出一次，全未提交保留。暂停只刷新输入generation匹配、完整且同frame的冻结cohort，不采新Inbox或重放VM；held候选保原输出。表面重建不关闭producer，完整停止撤权并排空已接纳任务。

macOS provider 的可用能力不能由内部事件模型的存在推导。A→B→C 且 B 延迟的用例应证明 B 不覆盖 C；真实系统切歌与合成输入测试分别报告。

### 7.4 Scene Texture

用户文件、variant、视频、文本、封面、图层输出与 named target 通过已有 typed publication 和消费边界连接。来源、授权、请求身份、logical/physical extent、UV、mip、sampler、颜色/alpha/purpose 与所需 slot 沿实际消费者传播。

源/provider 负责生产，frame registry 负责可用状态与发布，graph/compositor 消费已准备引用。统一合同不要求所有 provider 继承同一类，也不要求把来源检查搬进每帧采样。

视频保留播放意图、帧就绪和控制代次，seek/替换后旧帧不能回流。文字、视频、图片的更新不默认重建图；改变 extent、variant 或依赖时仅处理对应部分。局部 source-only 降级的精确条件归[专项合同](static-source-draw-only-degradation.md)，不能由本页扩大其视觉资格。

## 8. Puppet、3D 和 Lighting

模型与 Puppet 共享网格、材质、变换和最终合成，保留各自的动画与变形语义。准备阶段保留骨骼、weights、clip、附加通道、附件与子材质；实例更新 pose 和播放状态；GeometryProduct 向唯一输出提供实际几何。

- Puppet 包含部件顺序、depth、纹理通道、嵌套 mask、attachment、blend shape/rule、交互和 spring/rigid/rope/wind/IK；遮罩与主体消费同一变形状态。
- 3D 包含 model/node、材质、骨骼动画、attachment、camera、fog 与物理，不能由静态 mesh 可画推成全部兼容。
- 照明按作者启用的材质和光源准备 maps、shadow、reflection 与 volumetric，不在无消费者时默认打开高成本 Pass。

atlas 和 graph-final 是几何采样资源，不能冒充已组合输出。world frame、attachment、脚本投影、cursor 与 skinning 使用同阶段的 canonical pose。未知动画通道保留并定位到受影响动作，不猜测或直接丢弃后宣称播放正确。[模型与 Puppet 专项](advanced-object-coverage.md)及[骨骼动画合同](direct-model-skeletal-animation.md)维护格式和执行边界。

## 9. 实时播放与离线烘焙

实时、离屏测试和离线输出复用同一解析、prepared Program、时钟、状态更新、graph 与 compositor。

```text
同一 Scene 执行链
  实时：显示时间 + 实时输入/provider -> drawable
  离屏：指定时间 + 可重放输入/provider -> 纹理观察
  离线：固定步长 + 明确 provider replay -> 帧序列/编码
```

先比较同时间、属性、资源与 seed 的真实 GPU 输出，再增加编码和队列。没有 provider replay 时不承诺音频、在线媒体或交互内容离线等价。不能为 bake 另建一套视觉算法。

## 10. 当前实现映射

物理源码入口统一由[事实地图的组件表](../architecture/runtime-as-built-map.md#component-source-map)维护。本页 §0.2 规定职责方向，事实地图说明当前文件如何实现它；文件移动同步 standalone source lists、layout manifest 和最近行为门，不在稳定组件合同复制一份文件清单。

## 11. 现役推进与封存边界

组件规范不另建执行队列。[工程设计](../roadmap/engine-refactor-program.md)维护所有权迁移与退役要求，[兼容路线](../roadmap/scene-compatibility-roadmap.md)维护作者能力选序，专项表和运行证据维护完成度。

新增或替换组件时直接完成以下工作：

1. 明确作者语义及输入、准备、实例状态、消费与释放 owner，落在本页已有类别。
2. 在已有定义、typed target、Program 或操作表增加所需数据；常量与来源检查在入口完成。
3. 使用已有时钟、canonical frame、资源发布、graph 与 compositor；只新增确有必要的专属模拟或几何。
4. 为真实输入、变化、失败和退出增加最近行为用例，使用真实实现；可见变化补独立内容与实际输出。
5. 完成替换后撤销旧产品调用和重叠状态，同步专项、代码地图与索引；短期 fallback 明确对应缺口和退出条件。

重叠语言执行路径、surface 承担过多组件装配、宽泛 descriptor 的阶段/类型混合，以及粒子 CPU/GPU 状态边界等结构偏差，纳入工程设计统一处理；不通过新增总管理器、通用组件框架或重复状态树掩盖。每批检查产品、测试和文档净变化，保持职责直接。
