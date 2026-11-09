# 运行输入、属性与 Timeline

<!-- document-role: current-state -->

<a id="properties"></a>
## 类型与求值

基本优先级为作者 fallback → 有效 user property → Timeline → SceneScript；实际目标 compiler 决定允许的来源组合，不把同名值合成无类型字典。缺值、错型或被拒 producer 保原已定义 fallback/current，不能用 resolver 的回退值覆盖一个健康播放状态。

<a id="visibility-typed-fallback"></a>
直接绑定的 layer、Puppet animation 与 effect 显隐沿相同 Bool 目标合同：已知非 Bool 属性不覆盖合法 authored Bool，冷 Document 与 BindingProgram 保同一 fallback；错型 writer 局部拒绝，不把 Slider 的0/1强转显隐，不伪造动态 producer 或 Puppet 准备标志。启动期 producer 冲突只核实际 instruction writers；fallback definition 继续提供原值，不冒充独立 Script 的竞争 writer。条件 Combo 仍走原比较域，Script/Timeline 与非法、缺失或冲突 fallback 的边界不变。退役原 Color→普通层显隐专门忽略路径，统一由真实目标类型拒绝 writer、保定义；该固定 fallback 不依赖启动 effective 值，因此不独立增加重建要求。同 key 其他真实消费者已有的重建标记和热更原子性继续保留，不能删除整个 key 或拆开通过。该合同兑现本引擎类型边界，不推断官方错型隐式转换。

BindingProgram 在构造/解码时形成验证结果与索引；LaunchContext.liveState 保存当前有效输入和 revision。value-only 更新只写对应状态；资源、combo 或 topology 变化触发原准备/重建边界。混合键按原事务接纳，不能拆开通过其中几项。

property key、原始 value、Combo value 和 condition 始终使用作者数据；本地化只作用于显示标题与选项 label，不回写运行输入。作者 text/group 是只读说明，unsupported 类型不生成可写运行能力。面板以已接纳的 effective value 显示当前值，fallback、用户 override 与资源替换状态分别保留；条件隐藏控件不删除其输入。资源更新沿原选择/准备/发布事务处理，失败保原选择，不把 UI 临时编辑值冒充热更新已生效。

| 用户属性 | 当前消费与边界 |
|---|---|
| Checkbox、Slider、Color、Combo、Text | 保定义、类型、默认值、显示条件及真实绑定；颜色值与显示色彩空间分开 |
| 直接 shader scalar/vector | 需要已准备的目标/ABI/来源证明，不因 material 有同名字段就获得值绑定 |
| Texture/variant | 保选择授权、asset/property identity、purpose 与 generation；坏替换保 last-ready |
| Effect visibility | 准备好的安全 activation 可热更；未准备/无消费者/不支持结构不因 Bool 字段存在而强行接纳 |
| User Shortcut | 原配置和真实输入 scope；不从合成 cursor 或脚本普通更新推定 OS 授权 |

<a id="startup-inactive-effect"></a>
### 冷启动关闭的 Effect 准备计划

原 Effect visibility 准备入口统一普通层的 DirectBool 与 SceneScript 候选：合法 Bool 初值为 false 时，普通层存在 named 读取或依赖声明不再整层取消其 effect 准备。原 Planner 仍证明实际 graph 与停用时的 previous-current 拓扑，Catalog 仍编译真实 Program、匹配 activation owner 和有序 named Binding；保留候选不等于创建当前帧需求，也不以 Bool 字段代替可执行 consumer。

Utility 冷准备的完整 effect target 先取得原层级准备与 SourceRoute 的实际输入，再交原 Planner/Capability 准备 Program；root 的 viewport/group 与成员闭包仍归现有消费者。Effect 入口只消费已有层级准备结果，不保留 fullscreen/composition/project 的独立提名或重复 source resolve。普通非 utility、依赖 consumer/provider 和实际 Program/资源边界保持，不新增 stage owner、持久显隐、资源表或帧内补准备。未覆盖的来源与拓扑边界由[问题队列](../roadmap/scene-open-breakpoint-queue.md#implementation-gaps)维护。

热更沿同一已准备 stage 和原事务接纳。当前 DynamicSnapshot 的一次 activation Decision 决定本帧实际 slot 与来源截点；关闭的 effect 不读取自己的 named 输入，同 provider 的其他活动 slot 继续消费。开启后使用原 Program，不运行时补编译、不新增状态、token 或缓存。坏层级、缺 source/Program、错误 carrier 或真实依赖冲突只使原消费者不可用；热开启仍由原整键事务拒绝并保 current，不能用源图复制冒充效果输出。

验收固定 Project 层恒 visible，只切 effect 的 DirectBool false→true→false，以同 window/Surface 的 white→gray→white、后置绿色 peer、实际 Program draw→main/seal/request/CB/GPU核资格，保资源/变量/等价表达式改名、缺 fragment 拒绝开启与活动启动邻例。原 fullscreen/composition 和成员资源门继续作为相邻边界；childless passthrough 沿原 source/Program 承接，不另按名称拒绝，空透明来源不能以主目标未变冒充效果执行。若旧 App 不能分、首错另属未实现 source/Program或需要新资源 owner，则停止此切片并重排。独立作者只授实际默认输入与已观测消费者，不将健康邻例称精确缺图恢复；当前结果见[运行证据](runtime-evidence-current.md)。

<a id="property-target-fallback"></a>
### 材质属性的目标局部 fallback 合同

effect pass 的数值常量从已有 authored pass 解析，保原 wrapper、fallback、Timeline 与来源声明。DocumentResolver 的启动 effective 投影继续服务显隐、资源、combo 等入口；有效数值由原 BindingProgram→liveState→DynamicSnapshot→uniform 消费，不再用 resolved pass 的启动属性值充当材质 authored fallback。沿 SceneDocument 原解析职责替换该投影，不增加值副本、类型推断器或每帧补偿；base-material 输入保持自身 owner。

BindingCompiler 已形成合法 effectConstant definition、但拒绝 writer 时，该固定数值 fallback 不再依赖 effective 启动投影，因此不为它新增 key 的重建要求。同 key 的其他资源、combo 或启动消费者已有的重建标记继续保留；不能从集合删 key、按部分 mutation 绕开事务，或把尚无合法 definition 的输入一起放宽。合法同 key Bool writer 可沿原 ready/expected-target 门热更，其他真实消费者未准备时仍整体拒绝更新。

准备阶段按完整 layer/effect/pass/name 查真实 writer。同 key 的合法 visibility、其他 layer/pass 或其他数值 target 不阻止本 target 使用已有合法 fallback；也不能借其值、类型或存在性作为本 target 的 producer。保原 authoredFallbackTargets 索引及直接 wrapper 合同，不另发许可、建立 registry 或复制状态。该索引只说明现有 definition 的目标归属；实际 type/ABI、来源和编码值与 fallback 对应仍由原 Program/uniform 消费者负责，不能把 Set membership 说成完整字节验证。

缺少、错型或被拒的属性 writer 保本 target 的合法原值；本 target 有冲突 writer、缺真实 definition/fallback、非法 wrapper、非有限数、错误 ABI/来源或多 contributor 未获资格时，失败仍局部。移除跨 target 的同 key 冲突判定及其重复扫描，不把 Bool 强转颜色、不用 shader 默认白色补作者原色。合法属性初值与热更继续生效，错误热更保原已提交状态；不改变原混合键事务和 Script/Timeline 优先级。官方错误类型的隐式行为尚未资格，本合同只兑现本引擎现有 typed fallback 语义。

验收须经过真实 Document/BindingProgram、producer catalog/capability、Program uniform 与最终 Metal 像素：同 key 的 Bool visibility 与 vec3 原色、改名/换资源/不同 pass、合法 Color 默认与热更、坏更新/冲突及健康 peer；冷索引与消费端的反例分别归实际阶段。不能以只执行 prepareUniformBindings 的门代替 capability 准入。原 DEBUG uniform 消费读口覆盖 authored fallback 和向量属性，复用现 frame/target/source/编码比对与身份集合；scalar/splat 保原 publication 读口，不重复记录或增加普通帧工作。原作者在默认与已接入的受控音频下核实际 material/输入/尾部消费，并用独立合法属性作者检查相邻链路；样本汇总 PASS 不替代目标层的准备、draw 或像素贡献。

源码：[BindingProgram](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingProgram.swift)、[当前状态](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyLiveUpdateState.swift)。

<a id="timeline"></a>
## Timeline

Program 保轨道、作者 key、FPS/length、曲线、relative/Combined 关系和事件。普通帧由唯一 PlaybackRuntime 采样已准备数据；play/pause/stop/setFrame 以及 API 快照共用该 state，不能另建第二 clock。

- 数值插值、Bézier 求根、wrap 与 relative 单位由现 evaluator 消费，不能用线性 key 索引替代作者时间。
- 非文字对象的绝对 `color` 三通道动画发布原 `.layer(.color)`/vector3，由既有 source tint/模型/灯消费者读取。冷准备复用 `colorRGB` 白缺省及原类型、来源优先级和关系检查，无新颜色状态；粒子 `instanceoverride.colorn` 保出生语义，文字 `.text(.color)` 保字形资源 owner。relative、错 lane 与未支持 host 继续局部拒绝。
- target 与 playback owner 不同。Combined/peer 可共享时间 anchor；销毁一个 target 只撤该活动轨道，幸存成员仍保 clock/命令/事件。
- 稳定 Program/C/named 索引不因压缩活动数组而改义；隐藏与暂停不退休轨道。
- 事件按实际时间区间与原确认边界派发，同 cadence 重读或无 drawable 不重复消费。
- 无真实 target/control owner 的 event-only 及部分类型组合仍有限制；不能只因解析到 track 就声称可播放。

源码：[PlaybackRuntime](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Timeline/SceneTimelinePlaybackRuntime.swift)、[TargetCompiler](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Timeline/SceneTimelineTargetCompiler.swift)。

<a id="effect-linked-timeline"></a>
### 数值联动的执行合同

effect instance 的数值常量在同一 layer/effect 内一次收集，再按作者 key 解析 parent/children；每个 pass 的完整 target、类型、fallback 与自身曲线分别保留，不按效果名、属性名或 pass 数准入。未联动的同名常量继续独立。联动可有多个实际 pass 成员、分叉或链式关系，只共享唯一根 clock，不制造子组偏移、独立响应或第二 state。关系解析复用原 TargetCompiler 的准备职责；layer 的值类型、relative 与响应消费边界保持。

同 key 的不同 lanes/fallback 不构成拒绝理由。各 pass 可分布声明 children，合并后须 reciprocal；多个根别名的实际 clock 设置须一致，canonical root 是真实且可执行 target。每个成员继承根时间；有 lanes 的成员读取自身曲线，无 lanes 的合法数值成员保留自己的 authored value。effect 不借 layer 的响应模式/UI 数值范围准入；未实现响应保原 descriptor 元数据并明确基础曲线近似。缺成员、矛盾、循环、无可执行根或缺真实值只使相连分量不发布，健康独立输入继续。无 lane 的成员不从 root、preview、user property 或 shader default 猜值；它必须有完整、有限且与目标类型相符的 authored 数值，并保留合法 options 和组关系。原 Parser 只把实际缺省的 lanes 保为空，不伪造 c0；显式空 lane、断号、坏关键帧与错 options 继续在原入口失败。材质 default 动画的解析与有效 consumer identity 另行接入，不由 instance 资格代验。

名称只服务既有动画 handle：同 owner 的相同根名字导出一次，不同名字保各自实际 target；其他 owner 同名沿原作用域/歧义处理。名称不决定数值资格。原 groupedAnimation 显式接收导出名，layer/camera 继续传其原根名；effect 的多个 pass 名称不能制造多个 clock。

无采样成员必须由原入口完整验证的作者数值形成；当前 effect constant 的原数值解析提供此事实，不能以其他 host 补齐或默认的 fallback 取得新准入。共享目标编译器只在冷期接收这一已有来源事实，缺事实的其他 host 保原 component 边界。成员沿原 Binding、stateIndices 和共享 playback owner 保持身份与命令/退休关系，原 typed 值入口直接消费已准备的 authoredValue；不把未通过关系分量的成员降为静态 uniform 绕过 producer 门，不新增常量 producer、clock、状态表或伪曲线。等价常量成员仍由原冷期取值分组去重，只做一次 fallback 投影和实际 target 写回，不运行 Bézier 数学。仅需数值的单通道观察不授常量句柄控制、relative、缺值或任意 host 组合的官方资格。

原 PlaybackRuntime 在准备时把同一 state 的实际等价取值成员归组，替换原 flat stateMembers；每帧每种曲线/类型/组合/fallback及有效采样选项求值一次，再写回全部原 target。仅忽略不参与取值的名称，曲线及数值 fallback 按实际 bit 保留 signed zero，不合并不同语义；不建并列 alias registry、帧缓存或整轨 hash。退休成员或代表后，幸存成员保原 owner animation/state、命令和观测；坏值保原分量原子失败，binding/handle ordinal 不改义。

验收沿真实 parser→TargetCompiler→PlaybackRuntime→DynamicSnapshot→prepared uniform bytes→Metal/terminal：不同曲线、跨 pass 别名、改名、同名其他 effect、冲突分量与健康 peer、play/pause/stop/setFrame/完成重启及退休；核实际时间下的动态颜色与独立作者活动相位。编译/绑定或晚相位零值不作可见效果证明；树形合同不冒充官方像素一致性。

<a id="camera"></a>
## 相机、world 与 Cursor

每阶段的 descriptor、layer map、world frames 来自原 FrameWorldProjection；cursor、Puppet 与 emission 复用同阶段数据。camera factory 消费当前成员与 render order；不再从 base descriptor 选已销毁相机。隐藏不等于销毁，parent 变换保持；当前 winner 缺 world/FOV 时回 general，不跳到任意邻 camera。

Default2D origin/zoom 的真实作者来源可能不同，不能用同一个 layer ID 代替两条输入。native perspective 与普通2D、camera parallax、depth parallax 各有自己的空间语义，不统一改成屏幕像素偏移。

普通二维画布的 `general.zoom` 沿[原相机输入合同](../architecture/runtime-architecture.md#default-2d-general-zoom)发布 `.camera(.generalZoom)`；静态值与 wrapper fallback、独立数值 Timeline、直接 user property、scene return-only Scalar Script 共用原 prepared definition。CameraTransforms及原path继续发布原 `.camera(.zoom)` 相对倍率，getter缺省1；完整记录改eye/center再回写只影响这个原通道。原CameraFrame factory一次组合General基准与相对倍率，再除cover世界范围，不另建时钟或setter状态。General缺省1、沿原相机0.01…100数值域；热更由原live consumer消费，Script失败保合法fallback/current及健康peer，HDR仅约束bloom。

存在作者camera声明时保原路径，不由General新增writer或替健康path制造冲突；General与path叠加、native perspective及未实现组合不列支持。linked、相对动画和动画混合Script/user保声明与局部诊断，不拆关系后发布独立轨；合法作者fallback仍可消费。General由原CameraInputProfile准备并按实际ortho消费者热更，原static CameraTransforms fallback1保留。实际画面及官方控制的证明范围归[运行证据](runtime-evidence-current.md#general-zoom)；官方显式相对倍率与General的组合公式、roundtrip晚段仍未获资格。

原 pointer owner 保存实际本屏坐标、按钮和边沿；命中使用最终输出 geometry/提交结果，不能用 source atlas 框代替。local/global monitor 按活动 owner 安装/移除，状态未变不反复重建或重置手势。

<a id="fullscreen-cursor"></a>
### Fullscreen 的鼠标事件

Fullscreen utility 的交互面是本屏 viewport，不要求作者 `size`，也不把普通图层的 origin/scale 套到全屏 raster 上。原 CursorHitAdmission 按实际 utility kind 接纳，原 Surface 的 cursor sample 为它提供命中与离屏 capture 投影；其他无尺寸图层保持原拒绝。standalone 与借用的 typed owner 使用同一几何职责，不另建全局监听或状态。

同一 sample 只生成一次原 `sceneScriptSurfaceInput`，world/input cursor 仍由当前 camera 反投影到作者世界；fullscreen event.localPosition 直接消费该 surface 的 top-left screen pixels，不能套普通图片 lower-left local pixels 或从 canonical raster 逆推世界。原 inside、solid、capture、leave/up、owner identity 与失败事务保持，缺 surface 只使该 fullscreen 投影不可用；普通卡片继续原 MVP 与本屏已提交文字几何。替换原“所有 cursor 层必须有 size”的关卡及其零尺寸 quad 路径，不给 descriptor 伪造尺寸。

验收核真实候选构造的 standalone/borrowed、改名、普通无尺寸/坏尺寸和健康 peer；原 Surface→事件→作者位移→named mask→最终输出须在原样本三点往返成立，另核独立真实邻例。官方单次 fullscreen move 只支持 top-left screen-local 与 camera world 的分工，点击、连续离屏与多屏仍独立取证，不借该观察改普通图片事件或 button。

<a id="text"></a>
## 文字

CoreText/CoreGraphics 负责字体、shaping、glyph advance、baseline、行距、对齐、padding 与 raster。字体 explicit-system-default 与当前值缺失分开；作者字体资源经同一路径解析，fallback 不证明字形等价。

Session 共享一个 DynamicTextTextureStore，按内容/样式签名和 generation 合并在途工作。普通稳定帧不重排/重栅格；每屏只采用 ready snapshot、prepared/submitted 纹理与几何。cursor 使用本屏最后提交的文字几何。

初始与动态文字均作为 layer source，raster 颜色与 layer tint 保原乘色语义。没有实际活 layer/clone/named/particle 消费者时退休活动 producer 并撤迟到发布权，保留准备模板与冻结/GPU 引用；hidden 不作为退出。Surface rebuild 复用共享 Store，完整 stop 排空已接纳任务。

隐藏文字的效果后 named 供货沿[原输入与发布 owner](render-graph-shader-coverage.md#named-input-ownership)接入。Store 只提供冻结的 ready raster、原 extent/几何和内容 generation；原 Program 消费它并发布实际最终图结果，不重栅格、另建 clock 或混用 glyph generation 与 named frame epoch。无效果文字保持原来源路径；已有 FramePlan 时核实际 graph 输出，缺资源的局部旁路与无 Program 的精确 base-source fail-soft 分别保原责任，不将它们称为效果执行。未绑定可选纹理的 Resolution 由[原 shader 准备合同](render-graph-shader-coverage.md#unbound-texture-resolution)供已资格的数值，不新增文字资源角色。当前边界与真实 CoreText 供货结果归[运行证据](runtime-evidence-current.md)，任意文字图与完整动画仍需独立验收。

<a id="text-raster-ink-extent"></a>
### 文字栅格的垂直墨迹范围

初始与更新文字沿原字号、换行、行数、对齐和装饰准备实际 CoreText frame。已定位的行基线与同一行的字形轮廓决定垂直墨迹范围。排印 ascent/descent 用于原行距和锚点，它会漏掉实际越界的墨迹。轮廓位于栅格内时沿原画布。实际越界时，按墨迹范围量化扩展画布，计入原生栅格边缘覆盖并留一行透明取样空间。背景及原装饰几何仍按名义框绘制。一次绘制复用原 frame，触及原纹理上限时缩放其位图映射，保留字号、布局和逻辑位置。

扩展行沿原逻辑单位/栅格行比例换算。原 layer source 发布原中心下降量和绘制锚点修正，后者仅用于实际栅格 quad，保上、中、下对齐与屏幕锚点。SceneScript 命中继续用作者几何及原中心下降量。纹理、实际 extent、绘制修正与 generation 同批发布，Graph 和 Resolution 消费完整扩展面。退出将名义测量框当作实际栅格边界的旧行为，保原不可用布局和取消边界。普通帧只用已准备几何。

验收核可重现的下越字形、合格在框字体、初始/更新同像素、资源改名、三种纵向锚点、原装饰及封顶情况，再核原作者的滚动和文字环、独立 named 文字及普通锚点文字。原作者和官方行为的已证范围归[运行证据](runtime-evidence-current.md#circular-text-edges)。

### 文字 HDR 亮度

文字前景 `brightness` 是 HDR gain，[官方作者说明](https://docs.wallpaperengine.io/en/scene/effects/bloom.html)也将文字列为此选项的消费者。Document 准备 TextStyle 时按已解析的 `hdrEnabled` 采用：非 HDR 为1、HDR保留声明值；原始对象和 Layer 继续保真。初始/动态栅格共用有效样式，替代无条件烘入亮度的采用方式，不向 Store/loader 传 general，也不加普通帧分支。

新 launch 重建样式，Surface rebuild 复用 Store，不新增缓存字段或迁移状态。`backgroundbrightness` 仍需独立语义资格；HDR开启保既有8bit栅格行为，不表示高光保真。验证使用非白色0/1/高亮、wrapper及改名的初始/动态纹理，核字色、alpha、几何与原声明，并保HDR原输出；固定扫描相位、真实邻例和官方截图各有独立证明边界。

源码：[DynamicTextTextureStore](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneDynamicTextTextureStore.swift)。字体/排版精确像素、所有样式与官方布局 parity 仍需逐输入比较。

<a id="providers"></a>
## Audio、Media 与纹理 provider

平台服务唯一生产，Session 冻结一次快照供 VM 与 Surface 消费。活动需求由真实 prepared material、脚本、Sound/粒子与 source consumer 决定，不从 project 声明或纯 launch 定义猜采集需求。

- Audio 的系统采集与本进程 Sound 播放需求分开；未授权、静音、无数据有明确输入状态，不伪造波形。AudioBuffers 的数组身份、采样时机与处理范围按实际 host 消费。
- 系统 Media 经原服务/系统宿主与 inbox 发布 metadata、状态、进度和封面；平台补充不能替换已选来源或用旧曲冒认新会话。真实播放器字段、权限及切换分别验收。
- current/previous thumbnail、fallback、pending、decode failure 与 accepted clear 分开。Session Store 唯一生产各 purpose；任一屏成功提交后消费单份 pending 输入，所有屏使用同一冻结 snapshot。
- accepted absent 清该 provider 的 current/previous 长期 publication；discard 还原基线；旧 snapshot/GPU 使用期不因订阅退出缩短。
- 需求只在 committed 拓扑或实际 owner 禁用/恢复边界重算；最后 consumer 退出撤采集/订阅。hidden、dormant、bad return 和活 alias 保留合法需求；source alias 依实际 consumer→prototype 关系判断。

视频的逻辑/解码需求与 Sound voice 见[媒体](material-video-assets.md)。普通帧不经 IPC 同步查询播放器、启动 helper 或传完整封面。

<a id="limits"></a>
## 当前限制与最近门

完整平台输入/播放器覆盖、全部 target 组合、原生屏幕映射、任意字体排版及所有跨 owner 事件顺序不能由单个合成输入门推出。开放项见[队列](../roadmap/scene-open-breakpoint-queue.md)。

最近行为入口：[属性准备复用](../../../script/tests/test_scene_property_preparation_reuse.py)、[Timeline](../../../script/tests/test_scene_timeline_runtime.py)、[Default2D](../../../script/tests/test_scene_default_2d_camera_inputs.py)、[动态文字](../../../script/tests/test_scene_dynamic_text_generation.py)、[媒体 Store](../../../script/tests/test_scene_media_thumbnail_provider.py)。
