# Scene 官方语义与实现覆盖台账

> 状态：现役系统汇总；逐项等级以各专项能力表为准
>
> 最近核对：2026-07-24
>
> Scene 实现基线：当前 HEAD（前置安全整数提交 `10401d7`）
>
> 当前完整快照门：`.codex/scene-chromaticdot-20260724/full26-final/report.json`；固定回归门：`.codex/scene-chromaticdot-20260724/fixed13-final/report.json`
>
> 最新运行门：真实目录 26 样本完整快照 26/26、particle 52/68；固定 13 样本门 13/13、particle 15/27，仍单独保留且不能互相替代。完整 Scene suite 302 项：299 通过、3 项跳过；语义覆盖 11/11。聚合缺口、视觉证据边界和签名身份见 [运行证据索引](runtime-evidence-index.md)。

本表把已收集的 Wallpaper Engine 作者语义逐项映射到 MyWallpaperX 当前代码、运行证据和下一道验收门。详细语义仍以同目录专题文档为准；这里回答三个问题：官方是否有这项能力、当前播放器走到哪一级、下一步补什么公共能力。

## 1. 口径

| 等级 | 含义 | 允许的结论 |
|---|---|---|
| `L0 absent` | 当前 Scene 管线没有结构或运行入口 | 未实现 |
| `L1 recognized/preserved` | 能识别声明、保留部分字段或输出诊断 | 已识别，不能宣称可播放 |
| `L2 wired/routed` | 已进入 IR、资源或 Render Graph 路由，但没有可靠执行结果 | 已接线，不能宣称有效果 |
| `L3 executed-degraded` | 有受限执行器和正反测试，仍有明确语义或视觉偏差 | 可用子集，必须同时写明边界 |
| `L4 semantics-verified` | 作者启用、输入、顺序、生命周期和视觉/数值门均与 WE 基准核验 | 该合同可宣称语义兼容 |

系统等级取 schema 保留、作者启用、运行消费、生命周期和语义/视觉门中的最低值，不做平均。某一子集达到 `L3` 不会把同名系统整体升级；`26/26` 当前完整快照门和 `13/13` 固定回归门都只代表各自矩阵通过运行门，不是样本兼容率或 WE 还原率。

当前没有任何完整系统达到 `L4`。官方公开的作者能力已经建立完整索引，但 Wallpaper Engine 没有公开完整稳定的私有 Scene/PKG/TEX 序列化规范，也没有公开 Windows 渲染器实现；未知字段仍须用合法样本、官方 assets 或 Windows golden 继续核验。

## 2. 官方资料覆盖

| 资料面 | 收集状态 | 权威入口 | 仍未知 |
|---|---|---|---|
| Scene 官方页面 | 179 个 `/en/scene/` 页面已建目录并逐页映射到唯一合同 anchor，2026-07-22 经代理核验 | [官方页面全目录](official-page-catalog.md)、[逐页映射](official-page-map.md)、[分组映射](official-page-crosswalk.md) | 官方未来页面变化 |
| 官方 Effect | 45 个用户可见 effect + `_empty` 内部占位已整理 | [内置 Effects 语义全集](effects-reference.md)、[执行覆盖表](effect-execution-coverage.md) | 私有 shader 精确算法和全部历史版本 |
| SceneScript | 官方 `lib.sceneScript.d.ts` VERSION 2.8 已逐 API 建账 | [SceneScript API 覆盖表](scenescript-api-coverage.md) | Windows VM 的非公开行为和预算细节 |
| Scene/Effect/Material/Shader/RT | 作者合同与 IR/executor 状态已拆分记录 | [场景格式与 Render Graph](scene-format-and-render-graph.md)、[Graph/Shader 覆盖表](render-graph-shader-coverage.md) | 完整私有 schema、默认值和所有 combo |
| Particle | 官方组件、子类型和执行阶段已逐项建账 | [粒子组件覆盖表](particle-component-coverage.md) | 未公开 preset 资产内容和平台精确视觉 |
| Timeline/属性/输入/Provider | 官方求值顺序与 target 状态已逐项建账 | [运行输入与属性覆盖表](runtime-input-property-coverage.md) | 私有序列化字段和 Windows 精确数值 |
| Puppet/3D/Lighting/性能/RGB/离线 | 高级对象与产品策略已逐项建账 | [高级对象覆盖表](advanced-object-coverage.md) | 私有资产格式、设备和渲染器内部行为 |
| 来源与许可证 | 官方、样本、WaifuX、linux-wallpaperengine、当前代码分级 | [资料来源与证据索引](source-index.md) | 第三方实现不能替代官方真值 |

因此，后续一般不再猜“这个能力是什么”；实现前先查上述合同。仍需研究的部分应明确标为私有格式/算法未知，不能用视觉近似反向定义官方语义。

## 3. 系统总表

| 系统 | 当前级别 | 当前真实能力 | 主要缺口 / 升级门 | 批次 |
|---|---|---|---|---|
| PKG/TEX/资源索引 | `L3` | loose/PKG 查找、常见 TEX、内嵌 MP4、诊断式失败 | case/symlink/duplicate/多格式边界与完整 VFS golden | B0 |
| Scene IR 与基础层级 | `L3` | 基础对象、顺序、父子 transform/visibility、常见 image/text/solid/particle | 模型、复杂 object component 和全部动态字段 | B0 |
| Utility composition | `L3` | typed composition/project/fullscreen、受限 current prefix 与 `_a` named target | nested/effectful/child、`_b` 数据流、RGB 语义 | B2/B3 |
| 画布/cover/背景 | `L3` | cover 投影和作者声明视差门，未覆盖区域不再暴露灰底 | 多比例、多屏和 Windows 像素基准 | B5 |
| Frame Context | `L3` | host 单一 60 Hz driver；shader/video/particle/parallax 同帧 timing | pause/resume、delta clamp、fixed step、目标 FPS、离线 adapter | B0 |
| Dynamic target/value 与 property binding program | `L3` | 六类 value、主要 target、固定优先级；v22 保存 layer alpha/color、direct text 三字段、strict Local Contrast/Opacity definitions/instructions/effective values；mixed/invalid/SceneScript key 标记重建 | direct text 已有 per-layer generation/stale cancellation；hidden/no-consumer text 与其他 effect constant 仍重建 | **B0/B4** |
| Per-surface dynamic snapshot | `L3` | host 共享 property 输入，每个 surface 独立 evaluation transaction、snapshot 与 generation；相同 payload 不增 generation | pointer/size/provider/Timeline/SceneScript 等 local producer 接入后继续扩充隔离门 | **B0/B4** |
| Atomic live property state/routing | `L3` | layer alpha、纯 solid color、strict Local Contrast strength 与 stock Opacity alpha 先原子求值并直接供 renderer 消费；失败、mixed、SceneScript、unsupported 或无 consumer 时保留整场重建 fallback | 扩展 target 前必须补类型、eligibility、consumer、fallback 和 identity 门 | **B0/B4** |
| Timeline runtime | `L0` | 没有 Timeline target/keyframe/mode/tangent/event IR | 保真 IR、确定性 evaluator、target 写回 | **B4** |
| SceneScript presence | `L1` | 只保留对象是否含 inline `script` 的布尔值 | source path/inline source 与绑定 IR | **B0/B4** |
| SceneScript source/VM/API | `L0` | 源码和绑定目标会丢失；无执行器 | source IR、安全 ECMAScript、生命周期、API/events、预算隔离 | **B4** |
| Current pointer | `L3` | view-normalized -> scene world 与 axis-aligned authored layer UV 极窄子集；parallax/受限 effect 消费 | parent/rotation/scale/parallax 逆变换与 effect/control-point/script golden | B0/B4 |
| Previous pointer | `L2` | Frame Context 保存，但 renderer 未消费 | shader built-in 与事件 delta | B0/B4 |
| Pointer buttons/events | `L0` | 无 button/down/up/click snapshot 或 dispatch | 同帧输入队列与 author-off | B0/B4 |
| Audio declarations | `L1` | 部分 effect/particle 字段可保留 | 不等于频谱 producer 或 consumer | B0/B4 |
| Audio frame input | `L0` | Scene 不消费频谱 | 16/32/64 双声道 snapshot、注册和设备生命周期 | B0/B4 |
| 内嵌视频纹理 | `L3` | TEX 内嵌 MP4 image-layer 播放，消费共享 host time | seek/pause/switch/loop 精确合同及更多容器 | B1 |
| 系统媒体 identity | `L1` | `$mediaThumbnail` typed 引用存在 | producer/consumer、事件、缩略图 generation | B1/B4 |
| Particle runtime | `L3` | 作者 sprite、常见组件、Sprite Trail、10 个精确 built-in key；固定门 `15/27`、完整门 `52/68` | 逐项状态见粒子专项表 | **B4** |
| Text/Font runtime | `L3` | CoreText 静态栅格和部分 font/pointsize/padding/scale；结构门 `79/108` | 动态 text、Windows baseline/fallback、outline/shadow/effect | B4/B5 |
| Camera Parallax | `L3` | 仅作者开启且非零 depth 时启用，含层级传播/阻断 | WE 数值 golden、camera shake/zoom、3D camera | B5 |
| User Properties | `L3` | 独立窗口、条件、持久化、PNG/JPEG `sceneTexture`；layer alpha、纯 solid color、strict Local Contrast strength 与 stock Opacity alpha 已无重建 live 更新 | unsupported/mixed/SceneScript bindings、Texture Variants、shortcut、跨重启 UI 门；精确 census 见 runtime-input 专项表 | **B0/B1** |
| Typed texture provider | `L3` | layer/named/property identity、status/fallback；静态 resource generation 与 named frame epoch 已分离 | 显式 dynamic generation、metadata、cancel、system/media/video/variant、通用 material、nested/effectful/child | **B1** |
| EffectDefinition/Material IR | `L2` | definition/pass/RT/material/slot hole/combo/constant 可保留并建图；ShaderContract 保存 source identity | 完整 schema、typed shader defaults、condition/function | B2 |
| Bounded effect executors | `L3` | 两个严格 Blur 图、strict stock Local Contrast、exact Workshop Shadow、exact stock Opacity、Shake、Water Waves 与 Water Flow 八类 backend 的 ordered strict chain 与若干受限手写 executor | 其余官方 Effect、variant、mask、SceneScript/unsupported mixed chain 与 visual golden | B3/B4 |
| Current-frame capture | `L3` | bounded utility prefix capture 可执行 | 通用 capture/extent/format/mask | B2/B3 |
| Named primary target | `L3` | bounded `_a` producer/consumer 可执行 | 通用 authored identity 和依赖环检测 | B2 |
| Named secondary identity | `L2` | registry 区分完整 variant；无 `_b` producer/consumer flow | secondary 数据流、copy/swap/history | B2 |
| Generic FBO command graph | `L2` | target/bind/compose/copy/swap/condition/function 可保留或 blocker；effect-scoped target/lifetime table 已由八个 strict backend 与 ordered strict chain 消费；同帧 copy/swap 已有严格 plan/runtime 门；显式 unique FBO 的 history seed 已进入 table 初始化；Precise Blur 的 `material -> copy/swap -> material` 白名单拓扑可按 authored nodeIndex 交错执行；exact legacy Blur Precise `compose:true` 两遍语法可归一为单个 full-size 中间 target；exact Shake、重复 Water Waves 与 `Water Flow -> Opacity` 均可按作者顺序执行 | Precise Blur 两种严格 interleave、exact legacy compose、exact stock Shake、Water Waves 与 Water Flow profile 为受限 `L3`；generic compose、Refraction scene-background capture、真实 history consumer、condition/function、typed state、跨帧 logical swap 和完整生命周期仍缺失 | B2 |
| History RT | `L2` | `unique:true` framebuffer 可通过读前写 hazard，plan 记录 history seed；缓存 table 首次消费时对 seed texture 做一次 GPU clear，pool 复用与 reset/resize 生命周期继续成立 | 真实 history consumer、跨帧 ping-pong/logical swap、seek/pause/resize/switch/stop 确定性和真实样本正向 GPU 门 | B2 |
| Authored shader path/source identity | `L1` | material path 与 ShaderContract stage/source/raw hash/canonical identity 已安全保存 | 尚无 include expansion、translation、compile 或 executor | B2 |
| Shader source/include/annotation/declaration contract | `L1` | 完整 source、include reference、annotation raw/structured value、uniform/attribute/varying declaration 已 loss-preserving 保存并诊断 | typed default/combo consumer、include expansion、macro/permutation preprocessor、stage link/translation/compile | B2 |
| Arbitrary custom shader execution | `L0` | 自有受限 Metal shader 不等于作者 shader | 通用受控翻译/映射、安全与产品门 | P3 |
| Puppet asset identity | `L1` | 可发现部分 model/material/puppet 资源 | mesh/bone/weight/animation schema | P2 |
| Puppet runtime | `L0` | 无 mesh/bone/physics executor | animation、constraint/IK、spring/rope/wind/events | P2 |
| 2D lighting/Scene HDR | `L0` | layer Bloom 近似不等于官方 lighting/HDR pipeline | PBR maps、light、shadow/reflection/volumetric、scene post | P2 |
| 3D model/camera/physics | `L0` | 无 Scene 3D runtime | model/node/material/skeleton/attachment/camera/physics | P3 |
| RGB device integration | `L0` | 无 Scene RGB provider/output | macOS 策略、授权和 fail-closed | P3 |
| Debug PNG readback | `L2` | benchmark 可生成 GPU 截图，并按 Steam preview 比例中心裁切、输出非阻断分项指标和并排图 | 只允许同一样本跨提交比较；不能跨样本排名、替代 Windows golden 或标成 offline bake | P3 |
| Offline bake | `L0` | 无固定步进产品 adapter | fixed clock/seed、provider replay、编码器 | P3 |
| Stop/switch lifecycle | `L3` | surface=0 和部分资源释放门 | VM/provider/GPU 细粒度计数、系统暂停与长稳 | B0-B4 |
| Performance budgets | `L0` | 无统一 CPU/GPU/显存/帧时长期阈值 | 30 分钟交互、2 小时 soak、多屏和压力门 | B0-B4 |

## 4. 官方 Effect 覆盖摘要

45 项的作者条件、执行通道、公共依赖、当前证据和下一验收门统一维护在 [官方 Effect 执行覆盖表](effect-execution-coverage.md)。汇总为 `L1=26`、`L2=5`、`L3=14`、`L4=0`；所有 `L3` 都是表内明确限定的 profile，不是 WE parity。内部 `_empty`、Workshop `gradient_color` 和 layer Bloom 另列，不能替代任何官方 Effect。

## 5. Particle 子系统覆盖

逐 initializer、operator、renderer、control point 和 child 类型的证据见 [粒子组件覆盖表](particle-component-coverage.md)。本节只保留系统级摘要，不能替代逐项表。

| 官方组件 | 当前级别 | 当前边界 | 升级门 |
|---|---|---|---|
| General 字段 IR | `L2` | 常见 material、maxcount、starttime 与 world-space/perspective/frame-blend system flags 可保留 | 五种 author allow-override gate 仍为 `L0`；补显式 wire schema |
| General 执行子集 | `L3` | max count、prewarm、perspective、frame blend 分支可消费 | runtime change、prewarm cap 定向门与 WE 数值门 |
| Emitter schedule | `L3` | rate、instantaneous、duration、one-per-frame | delay/periodic 和 WE 时间门 |
| Sphere Random emitter | `L3` | 可执行子集 | 全参数、distribution golden |
| Box Random emitter | `L3` | 可执行子集 | 全参数、distribution golden |
| Layer Image/其他 emitter | `L1` | 名称可诊断，字段和执行不足 | 独立 fixture 和作者条件 |
| 已接 initializer 子集 | `L3` | lifetime/size/velocity/color/alpha/angular velocity 常见路径 | 每一项 range/distribution/seed golden |
| Rotation Random initializer | `L2` | 字段与 simulation 分支已接线；无最终 rotation 断言 | renderer orientation 数值门 |
| 未接 initializer | `L1` | turbulent/control-point/remap 等可诊断或字段不足 | 逐项 fixture 与创建时语义 |
| 已接 operator 子集 | `L3` | movement/angular、alpha/size/color change、部分 oscillate | timestep/curve/phase 数值门 |
| 未接 force/operator | `L1` | attract/turbulence/vortex 等明确 unsupported | control-point/world-space 力场 |
| Sprite renderer | `L3` | 作者纹理和程序化静态遮罩子集 | 全 material/blend/lighting/atlas |
| Sprite Trail | `L3` | 受限 trail 执行 | orientation/length/atlas/曲线精度 |
| Rope/Rope Trail declaration | `L1` | 结构/诊断不足 | topology、constraint 和 material IR |
| Rope/Rope Trail execution | `L0` | 无 renderer | geometry/history/lifecycle |
| Static control-point subset | `L2` | static local offset/instance override 有分支；缺最终位置断言 | emitter 位置、空间与 parent golden |
| Dynamic control-point declaration | `L1` | 可识别或诊断 object/cursor/script 需求 | typed target 和 binding IR |
| Dynamic control-point execution | `L0` | 无 object/cursor/script runtime | 坐标转换与每帧更新 |
| Child asset graph | `L2` | 可递归发现，已有 missing/cycle guard | runtime child identity、ownership 和 depth/total budget |
| Child execution/events | `L0` | runtime 报 `childSystemsUnsupported` | spawn/death/collision 生命周期 |
| Built-in textures | `L3` | 9 个精确 key；程序图形只保证确定性，不等于官方资产 | 剩余高频 key、atlas metadata、多纹理 material |
| World-space declaration | `L1` | 明确 `worldSpaceUnsupported` | 不能冒充执行 |
| World-space execution | `L0` | 无 camera/parent transform runtime | 多屏和 parent 语义 |
| Collision declaration | `L1` | 可诊断但无 solver | shape/depth/response/event IR |
| Collision execution | `L0` | 无 solver | fixed step 与 event dispatch |
| Audio-response declaration | `L1` | 参数可见但 simulation 不消费 | frequency/channel/bounds/exponent IR |
| Audio-response execution | `L0` | 无频谱 snapshot | mapping 和确定性 fixture |
| Sprite Sheet | `L3` | Sequence/Random frame/frame blend 子集可执行 | 全 atlas metadata、loop/edge 和多纹理 material |
| Static instance overrides | `L3` | alpha/size/lifetime/rate/speed/count/brightness/normalizedColor 有运行断言 | 完整类型/range 门 |
| Direct color/control-point position override | `L2` | parser/simulation 分支已接线，最终值门不足 | direct color 与 CP position/angle 断言 |
| Dynamic instance overrides | `L1` | wrapper 只诊断 | typed live target、generation 和逐帧应用 |
| Material/blend | `L3` | `genericparticle` 首纹理、additive/translucent 子集；unsupported shader/blend 尚可能回退 | 先严格 fail-closed，再补多纹理/combo/render state |
| Fixed step/seed/maxcount | `L3` | fixed simulation step、deterministic seed、maxcount 有运行门 | pause/discontinuity 与 WE 数值 golden |
| Delta clamp/prewarm cap | `L2` | 代码有上限分支，缺定向预算断言 | 长帧和高 prewarm 压力门 |

当前固定矩阵可见粒子为 `15/27`，完整矩阵为 `52/68`；`3750813609` 是 `7/9`，另外两层因 world-space 不支持而保持 fail closed。这些数字只度量对应矩阵实际加载的 layer，不代表粒子组件覆盖率。

## 6. 动态运行系统覆盖

### 6.1 Timeline 与 SceneScript

| 能力 | 当前级别 | 升级门 |
|---|---|---|
| Particle `animation` wrapper presence | `L1` | 与正式 Timeline IR 分开，只作为动态值诊断 |
| Timeline object/property target | `L0` | typed target ID 与完整 authored base value |
| Keyframe/value/tangent | `L0` | 当前不保留内容；需保真 IR、Bézier/step/linear evaluator |
| Loop/Mirror/Single/paused | `L0` | 绝对 scene time、wrap、seek/pause tests |
| Animation Events | `L0` | frame crossing、loop、同 layer script dispatch |
| Script presence | `L1` | 仅保存对象是否含 inline `script` 的布尔值 |
| Script source/binding IR | `L0` | 当前 inline/source path/绑定目标会丢失 |
| ECMAScript VM | `L0` | 安全隔离、确定性 budget、异常处理 |
| `init`/`update` 生命周期 | `L0` | 每屏实例、同帧 snapshot、stop teardown |
| `engine` globals/Date/Math | `L0` | frame context 和受控 host API |
| user/cursor/audio/media events | `L0` | generation queue、顺序、异常隔离 |
| component/object/particle API | `L0` | typed handles、只允许作者目标、失效语义 |
| timer/timeout/interval | `L0` | scene-time scheduler、pause/resume/预算 |

### 6.2 User Properties

完整控件和 target 计数见 [运行输入与属性覆盖表](runtime-input-property-coverage.md)。2026-07-22 的 21 样本 census 为 424 definitions、952 bindings、195 条 conditional bindings；本轮 26 样本完整运行门没有重做这项专项 census，因此不把旧计数冒充当前全集。layer alpha 73 条已编译并由当前 image/solid/text consumer live 执行；layer color 73 条全部指向 solid，其中 25 条属于纯 color key 可 live，`3122339805:basecolor` 的 48 条因同键还含未支持目标继续重建；exact Local Contrast strength 1 条与 `2902406982` 的 stock Opacity direct binding 已由 strict consumer live 执行。SceneScript Opacity candidates 继续计入 unsupported/fail-closed，不冒充 direct binding。

| 类型/行为 | 当前级别 | 当前边界或升级门 |
|---|---|---|
| Catalog/bindings | `L3` | 2026-07-22 的 21 样本专项 census、format 22 binding program 与受控 fallback；direct text content/point-size/color、Local Contrast/Opacity live，mixed/hidden/no-consumer/SceneScript fail closed |
| `color` | `L3` | UI/持久化/solid-only live consumer；补颜色空间、non-solid 与全部 target |
| `slider` | `L3` | min/max/default/step/fraction/precision UI；layer alpha、exact Local Contrast strength 与 exact stock Opacity alpha 已 live，其他 target 依 consumer 决定重建 |
| `bool` | `L3` | 条件/部分 target；不得按名称自动启用 effect |
| `combo` | `L3` | option value/条件；补全部 authored target |
| `textinput` | `L3` | 可编辑/持久化；动态 text 仍以重建应用 |
| `texture`/`scenetexture` | `L3` | PNG/JPEG picker/bookmark/static consumer 极窄子集；补 video/variant/general material |
| `usershortcut` | `L0` | parser 当前归为 unsupported；需 macOS 授权和安全降级 |
| group/order/condition | `L3` | 独立窗口已支持；补嵌套/全条件和负向门 |
| reset/default/override | `L3` | layer alpha reset/override 可原子 live 提交；texture bookmark 或非 live key 仍重建；补跨重启 UI 门 |
| Texture Variants | `L0` | 补 schema、checkbox/combo 选择和 provider identity；脚本不得切换 |
| property update event | `L0` | typed snapshot 后再派发给 SceneScript |

### 6.3 Text、Audio、Media 与 Provider

| 能力 | 当前级别 | 当前边界或升级门 |
|---|---|---|
| 静态文字内容 | `L3` | CoreText 可见；结构样本 `79/108` |
| 字体解析/fallback | `L3` | macOS 字体近似子集；补 Windows family/weight/CJK/emoji golden |
| point size | `L3` | `pointsize * 4` 为经验近似；需官方/Windows 标定 |
| baseline/alignment | `L2` | 部分字段/geometry 已接线，执行门不足 |
| outline/shadow/text effects | `L1` | 字段或 effect 可保留，未形成完整绘制链 |
| property-driven text | `L2` | 通过 Scene 重建应用；需 per-frame target 和按 layer 纹理 generation |
| SceneScript clock/text | `L0` | 先有 VM、Date 和 typed text target |
| Audio declaration | `L1` | 部分 effect/particle 参数可见，不等于输入可用 |
| Audio 16/32/64 bins | `L0` | Scene 无可注入 frame snapshot |
| Audio effect/particle/script consumer | `L0` | 每个 consumer 正反 fixture |
| Sound layer | `L0` | 补 sound content IR、播放、volume 和生命周期 |
| Embedded MP4 frame | `L3` | image-layer 子集；不同于系统媒体 provider |
| Media status/metadata/timeline | `L0` | injectable snapshot 和 lifecycle |
| Media thumbnail identity | `L1` | `$mediaThumbnail` typed reference 已分类；不等于 producer |
| Media thumbnail producer/consumer | `L0` | typed texture provider/generation/fallback |
| Layer/named target provider | `L3` | bounded current-frame graph；补 nested/effectful/child |
| Named secondary identity | `L2` | registry 已区分完整 `_b` variant |
| Named secondary producer/consumer | `L1` | executor 识别后拒绝；需真实数据流 |
| Property file provider | `L3` | PNG/JPEG 静态 consumer 极窄子集；补通用 material/video/variant |
| Video/system provider identity | `L1` | enum/reference 脚手架存在 |
| Video/system generic producer | `L0` | 尚无通用 provider lifecycle |
| Generic material slots 0...7 | `L2` | 保留 hole/候选；补按 shader combo 的通用 consumer |

## 7. 高级对象与输出覆盖

逐 Puppet、Model、Lighting、产品预算、RGB 和 offline 项见 [高级对象覆盖表](advanced-object-coverage.md)。

| 能力族 | 当前级别 | 最小可用门 |
|---|---|---|
| Puppet asset identity | `L1` | 独立 schema fixture 和完整资源图 |
| Puppet mesh/bones/weights runtime | `L0` | parse、GPU skinning、层级/遮罩 |
| Puppet spring/rigid/rope/wind | `L0` | fixed timestep solver、events、确定性 golden |
| 2D PBR maps | `L0` | normal/roughness/metalness/emissive slot 与 color space |
| Point/spot/tube/directional light | `L0` | light IR、排序、坐标和至少一条渲染路径 |
| Shadow/reflection/volumetric | `L0` | RT graph、depth/occlusion、预算和像素门 |
| Official Scene Bloom target identity | `L1` | typed scene target 已定义；binding 尚未分类 |
| Official Scene HDR/Bloom post runtime | `L0` | HDR targets、tone mapping、scene ordering |
| Workshop layer Bloom approximation | `L3` | 受限 layer effect pipeline；不得冒充 Scene post |
| 3D model/node/material | `L0` | asset loader、scene graph、camera、PBR material |
| Skeleton/attachment/animation | `L0` | animation evaluator、skin/attachment 生命周期 |
| 3D physics | `L0` | fixed timestep、collision、determinism |
| Custom shader reference/path/source identity | `L1` | material path 与 authored stage source/raw hash/canonical identity 已保存；不代表执行 |
| ShaderContract/source contract | `L1` | source/include/annotation/declaration/stage 已保留；仍需 typed AST、preprocessor、translation/compile 与 executor |
| Custom shader execution | `L0` | 需受控编译/映射、uniform/slot/render-state 与安全产品合同 |
| RGB device | `L0` | macOS 产品策略、授权、设备 adapter |
| Debug PNG readback | `L2` | 可生成 benchmark 截图证据；不得标成 offline bake |
| Offline bake | `L0` | 与实时共用 IR/evaluator/render graph，固定时钟和编码输出 |

## 8. Coverage-first 实施批次

| 覆盖批次 | 开发计划映射 | 目标 | 完成判据 |
|---|---|---|---|
| **B0 Contract/Runtime Kernel** | `S3 第 1-4 项` | v22 binding program、per-surface transaction、atomic state、alpha/solid-color/direct-text/strict Local Contrast/Opacity consumer 与 rebuild fallback 已闭合 | 新 live target 继续要求 compiler、consumer、原子失败与不换 surface/window；pause/fixed-time 单列 |
| **B1 Provider Core** | `S2 第 5 项 + S3` | dynamic text 已完成 per-layer generation、stale cancellation、last-ready fallback；frame registry 双代已完成 | 把 status/metadata/cancel/teardown 推广到 Texture Variants、video/system/media 与 material candidate；不含 nested graph source |
| **B2 Graph Resource Runtime** | `S2 第 1-5 项` | strict Blur、stock Local Contrast、exact Workshop `shadow_____________`、exact stock Opacity、exact stock Shake 与 ordered strict effect-chain 已消费 target table；cache/resize/reset、整链原子 allocation、D7 ShaderContract IR v1、BGRA/RGBA/RG/R8 format、exact shader fingerprint、同帧 copy/swap foundation、受限 history seed/clear、Precise Blur 两种 material-command interleave 与 exact legacy compose 归一化已完成；generic compose/scene-background、真实 history consumer 与 typed shader defaults/built-ins/state 未完成 | read/write、RT lifecycle、slot/combo/state 和 resize/switch/stop 门；下一批用 preview 并排图和同样本分项变化验证画面收益 |
| **B3 Provider-Graph Integration** | `S2 第 5-6 项` | nested/effectful/scene-background source、通用 material consumer、45 Effect 严格 profile family | B1+B2 均完成后接入；不得新增 effect-name 视觉旁路 |
| **B4 Feature Breadth** | `S3-S4` | direct dynamic text 已完成首个子集；Timeline、SceneScript core、system/media text、cursor/audio/media、按依赖排序的 particle breadth仍待推进 | 每族正向、默认关闭、unsupported、determinism 和 lifecycle 门 |
| **B5 Fidelity** | `S2-S4` 广度完成后 | 字体、视差、粒子、常用 Effect 与 WE Windows golden 对齐 | 固定输入逐像素/数值阈值、性能预算、长稳和多屏门 |
| **Advanced** | `S5` | Puppet、2D light/HDR、3D、arbitrary custom shader、RGB、offline bake | 每个系统有完整 IR/runtime/lifecycle/product gate 后再升级 |

研究可以并行，产品执行不能倒置：B0 live-property、direct dynamic text generation、B2 ordered strict chain、Workshop Shadow、stock Opacity、exact stock Shake、exact stock Water Waves/Water Flow、同帧 copy/swap foundation、受限 history seed/clear、Precise Blur 两种 material-command interleave 与 exact legacy compose 归一化已合龙。`31ae557`/`94aebc5` 已把精确 Water Waves/Water Flow profile 放入 ordered strict scheduler；非 exact Water Waves 的 legacy inline 仍只在 owner layer 唯一可见 Effect 时准入，mixed/repeated unsupported declarations fail closed。当前完整门为 38 stage/5 chain/0 failed，固定门为 20 stage/1 chain/0 failed；超出默认 96 MiB 纹理预算的长链在规划阶段拒绝。后续从逐 effect 重复实现转向共享 material pass executor、texture/state/target 生命周期和 shader preprocessing IR；样本自带 preview 是当前第一视觉依据，WaifuX MP4 只作辅助动态参考，均不能替代 Windows WE 动态/像素 golden。

## 9. 更新规则

1. 每次 Scene 能力提交必须更新本表对应行和精确边界；只更新开发流水账不算完成。
2. 升级到 `L2` 必须有结构/路由测试；升级到 `L3` 必须有实际执行正例、作者关闭反例、失败降级和生命周期门；升级到 `L4` 必须有官方行为或 Windows golden。
3. 新发现的官方能力先补 [官方页面全目录](official-page-catalog.md)、[页面能力映射](official-page-crosswalk.md) 和专题语义，再进入本表；私有字段按 [资料来源与证据索引](source-index.md) 标证据等级。
4. 最新矩阵报告、测试总数、签名 App 身份以现役计划、路线图、本表头和运行证据索引为主答案；其他含“当前/现役/下一步”的被引用文档由语义同步测试锁定同一 baseline/report/route，历史评估不得反向覆盖。
5. 开发开始顺序：先看本表选择最低公共依赖，再查专题合同和 source index，最后查看样本命中；不得先凭截图写视觉特判。
6. 总表只允许单一 `L0` 到 `L4` 等级；若同一能力同时存在 IR 与 executor 子集，必须拆成两行或下沉专项表。
7. 每行至少要能追溯到专项表中的代码、测试和运行证据；只有 parser 或结构时不得写成执行支持。
