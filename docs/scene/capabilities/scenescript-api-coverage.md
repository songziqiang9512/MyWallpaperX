# SceneScript 当前接口与语义

<!-- document-role: current-state -->

<a id="contract"></a>
## 作者合同与运行模型

SceneScript 是 property-bound ECMAScript：脚本附着于一个有类型的属性，`init(value)`/`update(value)` 的返回值可写回该目标，直接 setter 可修改其他准入目标。`update` 可选，只有实际导出的 update consumer 进入逐帧调用。声明面见[SceneScript v2.8 类型声明](../development/reference/lib.sceneScript-v2.8.d.ts)；声明存在不表示本项目全部 host API 已实现。

当前使用真实 QuickJS-NG、模块解析和同一 domain 的 heap；不以源码形状、小解释器或 Swift 字典复制 JS 对象。绑定记录 source、owner、target、作者初值及值类型；模块、shared、闭包和脚本 owner 是不同寿命对象。

初始化、属性事件、输入、媒体、动画和 destroy 由实际导出及当前 owner 调度。事件型/idle owner 不因缺 update 被当作不存在。数组、对象别名、RegExp 等语言行为归真实 VM；用户 API 和模块数学归项目 host/value 实现。

<a id="cursor-primary-button"></a>
### Cursor 的主键编号

当前 Session/Surface 只接入 primary 左键及其移动、按下、释放和 click。原 C cursor 参数在同一 frozen 对象内提供数值 `button=0`；它表示按钮编号，up/click 后仍是0，按下状态继续归 `input.cursorLeftDown`。沿实际 primary 来源补齐元数据，不新增 ABI、状态、按钮推断或 secondary 事件，不按作者 guard 的源码形状选择供值。world/local、命中、capture、回调生成及 journal/commit 维持原职责，退出缺字段导致合法左键 guard 恒返的行为。

原官方move的[有界观察](runtime-evidence-current.md#fullscreen-cursor)不授官方click、右键/中键或完整parity。本项目以已有primary事件合同供货，验收用真实C/VM的严格数值与等价guard、down/up/click状态、outside/release-outside反例和健康peer；真实作者须闭合文字命中→click→已有图片显隐→最终画面，并保改名及另一事件能力的回归。

<a id="layers"></a>
## Layer、Scene 与当前值

| 接口面 | 当前消费者 | 边界 |
|---|---|---|
| `thisLayer`、`thisScene`、layer 查询/枚举 | 原 LayerHost/SceneHost 与 typed snapshot | 句柄必须属于当前 domain/generation 且对象仍活；查询不取得资源或 graph 执行权 |
| transform、visibility、alpha、color、文字等 | 原目标定义与 mutation journal | 仅已接入目标有 setter；属性类型和合法值在实际入口判定 |
| `createLayer` | 现有动态图层模板与 Mutation Runtime | 已准备 image/solid/text 和受限 composition 形态；不是任意对象复制器 |
| `destroyLayer` | committed topology 与原组件退休 | 不提前撤当前冻结帧/GPU 引用；重复 destroy 不复活实例 |
| `sortLayer` | 当前拓扑排序 | 使用实际 layer handle 与合法位置；名称字符串不能代替该 handle 参数 |
| 文字 clone/模板 | 原 String/Vector program、文本模板与 Store | definition 保留，活动实例有独立值和退出；不是复制 VM heap |

动态 Layer 仅保存出生资源、创建尺寸、根关系及作者 seed；完整 upsert 的当前变换/可见性/颜色/文字走原 typed 值通道。结构 revision 不因普通值 setter 推进，也不在稳定帧回填整份作者 Layer。

普通命令在既有 commit/下一 cadence 可见；camera、visibility、particle 的已实现当帧例外不能推广到所有 setter。同字段跨 owner 按真实回调顺序消费，不能恢复额外仲裁或镜像状态；非法 owner bundle 原子拒绝，健康 peer 保持。

<a id="initialization-current-value"></a>
初始化与当前值交接：分离调用的 `init` 对本属性的合法 setter 已归一为 typed 值时，下一次值求值/update 中的 `thisLayer.visible` 必须能读到它，不能只有 `update(value)` 的入参保留该值、getter 却退回作者初值。复用原 ValueOwner、pending 初始化值和 owner 读值入口；初始化结果只是读值基线，不再次作为本次 setter 发布。后来的合法 setter 或 update 返回仍可改变初始可见性，不把初始化隐藏钉住，也不补造媒体 STOPPED 事件。

原 cursor 结果中的同 owner 显隐写入晚于初始化、早于媒体/属性回调；由现有 owner effects 在本帧投影为最小 typed 前缀，update getter 按当前 journal、较晚 callback、cursor 前缀、初始化值、当前 snapshot 的次序读取。不改写 pending 初始化值来保存未提交的 cursor 结果，也不提前改共享 Layer catalog；此前缀供本次输入与 getter，不重放成新的 setter 或新增持久显隐副本。

该交接随原 owner 的 commit/discard 退出，值或提交失败的重试沿原初始化事务；普通暖帧无初始化或真实前缀写入时不配置基线。验收用真实 VM 的分离 init/update、相反初值、直接返回、别名/改名、指针/媒体写入及已提交初始化值的消费拒绝重试；真实作者的当前显隐、实际 draw 和终端区域必须一致。其余 callback/返回值次序的未闭边界由[问题队列](../roadmap/scene-open-breakpoint-queue.md#implementation-gaps)维护。

<a id="initialization-exception"></a>
### 初始化异常的失败范围

普通作者 `init` 同步调用抛错，只终结该次初始化；原 C owner 沿原失败出口清理未提交 journal/timer，并以既有 initialized 状态表明无需再执行 init，JS 局部状态仍保留，后继 update/事件继续沿原 owner 调度。沿原 C result 与 Swift failure 传递明确的 init-exception，保原初始化诊断和当帧局部拒绝，不新增 owner、持久 phase、重试链或空动画资源。它替换普通 init 异常导致整个 target 永久停用的旧行为；scalar/Bool、vector 与 string 的显式/隐式初始化使用同一阶段合同。

恢复只在真正作者 init 的 JS_Call 普通异常、host 恢复及 job 检查成功后成立。编译/模块求值、host 安装/恢复、job、预算/中断、内存和 mutation overflow 维持原拒绝；后继 update/事件自身异常仍熔断。正常 init 的 pending→commit/discard、bad-return 重试及 generation/退出保持原职责，失败初始化不提交 typed 写入，也不因后续帧回滚重跑。固定官方2.8.0.42自动探针已见 init 抛错一次后 update 继续，而抛错 update 只执行一次；不授同帧顺序、异常前副作用的官方提交规则或原生点击。

普通 text 的动画方法缺失不由本项补造控制器。验收复用原真实 C/VM 初始化事务和 cursor 门，覆盖一次失败后的局部状态、后继值/显隐写入、改名等价表达、健康 peer、outside/release-outside、正常 init 回滚及后继异常仍停用；真实作者须命中→click→已有图片显隐→最终帧，并保独立既有交互回归。证明范围及未闭项分别归运行证据和开放队列。

<a id="boolean-callback-order"></a>
Bool 的分离事件前缀与值求值按真实调用顺序消费：属性/媒体回调对本属性的合法 setter 是后继值求值的输入及 getter 基线；后继显式返回可以改变它，同一次值求值中新写的 setter 仍按原规则优先于返回。先前 setter 不在值求值结束后再次折入。没有新值、无 update 的事件 owner 保留该前缀；本 owner 的真实 destroy 始终为不可见，不能被晚返回复活。

原 VectorProgram 在进入 ValueOwner 前归一已分离的事件 layer journal 一次，原 ValueOwner 用同一读值基线供输入与 getter，并只归一其本次 C entry 导出的 journal。成功后只合并已归一副作用和原 coalescing/commit，不再重做全批 Bool 归一；真实 destroy 由合并后的命令保终值及原资源退休。其他目标/字段、跨 owner 顺序、event-only setter、异常与 commit/discard 沿原事务，不增 owner、持久可见性副本、phase flag 或每帧全局扫描。

验收以真实媒体 callback 的相反返回、同字段新 setter、undefined/no-update、destroy、失败 owner 与健康 peer 核值和副作用；App 用公开属性回调与实际热更新显示可区分色卡，保改名变体、同 update 新 setter 及终端/typed 输出一致。Swift 已分离的属性/媒体前缀到值求值沿上述链交接；C entry 内的后继值回调也必须在真正 JS_Call 前消费已有自身显隐，不能因共用 journal 重放先前 setter。同一次值回调新写的 setter 保原发布位；没有 update 的事件 owner 保真实 setter，不凭返回类型改变事件寿命。

C entry 的读取作用域归原 primitive owner：在 video-ended 前序分发成功后、实际值回调前，将真实自身 VIS 转为本次输入及既有 authored baseline；只清这个已消费的发布位，保其它字段、真实 destroy 与独立 topology/sort journal。仅因消费 VIS 变为空壳的记录随原计数退出，不能导出成伪 sort。隐式 init 的真实返回及本次 setter 在同一作用域交给后继 update；App 保既有 split init，不改调度入口或重复调用 init。

作用域只在 C 调用栈保存原 baseline 的 slot/count/fields/visible，按实际 target index 复用原数组，不改 domain catalog、pending 初始化值或公开 ABI，不增持久副本、字段 epoch 或通用事务层。正常、无 update 和失败出口均恢复 caller 的原 baseline；先保证读值交接成功再退发布位。原公开 primitive 入口统一负责失败的 discard/disable，私有回调只恢复本地 host/handles、释放 JSValue 并返回原错误，不再重复清 journal；timer snapshot/admission 保持，JS heap仍不回滚。无真实前缀或初始化值交接的普通暖帧不创建 baseline；专有 effect/Puppet visibility 保原消费者。

验收固定 App one-shot timer 的原图/改名色卡及独立 peer，用实际 timer 后的晚返回和同次新 setter 区分；native 补镜像、输入/getter、undefined/no-update、同值写入、destroy/其它字段/sort、caller baseline 恢复、异常/重试，并保 Swift 已分离前缀门。直接 ValueOwner 的隐式 init 不能冒称普通 App 复现；Puppet/video-ended 混合返回、嵌套回调完整次序和事件自身先读 pending getter仍由队列保未闭，不授精确作者 positive、完整动画或官方 parity。

<a id="prepared-group-visibility"></a>
层级显隐以原 `SourceRoute` 已接通的组来源和合法成员闭包决定准备范围，composition 与 project 共用这一事实；fullscreen 保留独立的 viewport 消费入口。作者 Bool 与脚本 visibility 目标经同一 `SceneDynamicLayerVisibilityRouteAdmission` 形成 targets、preparationLayerIDs、particleRequirements 和 liveConsumers。初值 false 保留实际可显示成员的 Program、几何和粒子资源准备，不发布子层可见值，也不覆盖 child 自己的 false；普通帧沿原 typed snapshot 更新，资源与 topology owner 分别保持其原失效边界。

运行资格须在同一 window/Surface 核 cold false→true→false、共享属性的父组与独立粒子、改名及健康后继；图像、实际成员目标→父来源→Program→末合成和输入 generation 同时匹配。依赖、坏树、未接 source 或缺实际资源仍沿原 owner 局部失败；不新增显隐状态、资源表或运行期补编译。此合同针对 layer visibility，effect 的 inactive stage 准备另归[运行输入](runtime-input-property-coverage.md)，不由层目标接纳推定热效果资格。

动态创建仍拒绝未接入的 Puppet animation/effects 以及复杂 composition 的 parent/children/dependency/copybackground 组合。普通动态 image 不自动继承作者 Sprite/Timeline/effect 能力；资源定义可供合法消费者复用，不等于实例已获全部组件。

源码：[SceneHost](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSLayerSceneHost.c)、[LayerHost](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSLayerHost.c)。

<a id="host-context"></a>
### 播放宿主的上下文查询

原 IEngine 宿主在模块初始化、init、update和已有事件阶段提供[公开查询 `isRunningInEditor(): Boolean`](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html#isrunningineditor-boolean)。本程序是Scene播放器、没有Scene编辑器，结果为false；DEBUG取证窗口、预览窗口和测试Host仍不是编辑器，不能以DEBUG/是否有窗口决定该值。查询由原engine安装与绑定owner提供，不猜脚本名称或源形状，不新增模式、配置、状态或普通帧诊断。

先在原ValueHost承接并复用已有宿主查询安装流程，保持engine既有只读查询属性及绑定/恢复、真实VM异常和未知API的局部失败；不为补一个查询复制宿主或增加假Puppet metadata。真实3504669359的543共享库在top-level调用此API，未构造会让后续shared.offsetedStartAni不存在；166的clip700辅助轨解析拒绝属于另一断点，不能因共享初始化恢复而宣称所有动画恢复。

验收使用原native VM/owner准入门核模块、init/update/事件中的严格Boolean、改名与等价调用、原isScreensaver和未知方法/写保护反例；实际App控制必须以共享初始化后的真实消费者输出或Puppet命令/pose到最终帧为结果。真实作者同输入复测精确543与下游target，不以整体report PASS或少一条异常授全部Puppet/完整画面一致；独立邻例保已有播放与资源寿命。

<a id="parent-destroy"></a>
### 父层销毁与存活子层

`destroyLayer` 沿原 owner journal、候选 topology、commit 与退休分发移除目标层；存在存活子层不构成非法请求，不递归销毁未声明的子孙。固定官方2.8.0.42的自有普通image平移链中，父和独立叶成功移除，直接子层脱父并保原local位置，孙层仍属于该子层；fresh枚举、getParent、destroy事件和双图回调见证相互核对。此观察不授rotation/scale/shear/attachment、其他类型或同callback延迟的完整一致性。

原 `SceneScriptDynamicLayerRuntime` 只接纳请求的真实销毁目标，不要求同owner显式销毁全部children。原事务的非法值、未知目标、请求次序与原子回滚保持；不跨owner补销毁请求，不把creator退休误作父子关系，不增加persistent脱父表或第二topology。原 `SceneRenderDescriptor.applying(topology)` 在采用revision时按已销毁parent集合脱开仍存活的直接child、修正root/child索引，保作者当前local变换及孙链；prepared/VM/模拟/render消费者必须采用这同一结果。原资源、Timeline、粒子、脚本与GPU寿命只退休真正销毁的层，存活子层继续原clock、RNG、回调及资源。已提交的断父在原完整catalog投影重建一次，索引和签名不变；只有新脱父的存活层请求原下一snapshot世界矩阵刷新，成功及回滚由原发布事务消费。不在稳定帧重建整图或遍历认证。

先用真实 journal→候选→commit、原VM及投影验证父子孙/peer和改名，核合法子层写入、同owner非法后继整体回滚、重复/先后销毁、跨owner及提交重试；再以签名App核完整帧与子层保local位置、孙链、被删层退出和健康peer。真实3599986633需Ready后约7秒进入销毁，四层更早已由Timeline透明，晚窗PNG不能代退休成功；按目标owner、同输入摘要、真实commit/后续回调和终端GPU核当前224次误拒是否消除，不把基础report PASS或透明画面记为修复。未得到资格的attachment、复杂utility拓扑及世界保持变换另保问题，不以该例新增类型/路径许可。

<a id="commands"></a>
## 播放、事件与副作用

独立可见 solid 与无 effect 的 image 颜色脚本在准备期取得真实消费者后，生成同一 `.layer(.color)` Vec3 owner。solid 的白纹理复用原资源，颜色由 typed snapshot 进入原合成 uniform；不为脚本颜色重建纹理。solid 的 effect 后缀沿原执行链消费 source 颜色，末端不重复乘色；依赖、named、隐藏及错误 seed 等尚未取得此准入的形态保持原边界。

| 领域 | 当前实际入口 |
|---|---|
| Property Animation | 原 animation handle → TimelinePlaybackRuntime；play/pause/stop/setFrame 与同一轨道 state |
| TEX animation | `getTextureAnimation` → TextureAnimationPlaybackRuntime；typed handle 入口检查存活一次，命令保原 next-frame 顺序 |
| Particle | 原 Layer/ParticleInstance host 的 play/pause/stop/isPlaying/emitParticles 与 typed override；真实出生和预算由原模拟器处理 |
| Puppet | 原 animation/bone handle、会话 animation runtime 与每屏 pose；未接入 clip/channel 不从 handle 存在推定可播 |
| 视频 | 原 material/layer video handle → 视频 registry/source；命令目标与被选资源身份保持，不能按路径广播 |
| Sound | 原声音定义与 voice registry，volume/播放命令消费既有 typed 值 |
| Cursor/媒体/用户属性事件 | 原入口快照与 owner 回调；一次性事件不能因 GPU 重试重复派发 |

已接入的外部用户快捷动作需要当前真实输入和现有授权 scope；init/update/伪造指针不取得用户手势。OS 动作与 JS heap 副作用不能随 typed admission 失败假装撤回。不同事件/API 的签名和返回值仍以实际 host 与声明对照，不以“返回 true”代替系统动作成功。

<a id="values"></a>
## 数值、模块与持久状态

当前 value host 提供 Vec2、Vec3 与有界 Mat4，模块数学沿现 module host；Vec4、Mat3 未安装。向量返回与赋值按各入口所需的 x/y/z 分量及数值合同读取，普通对象满足对应分量合同也可被接受。构造与矩阵操作只承诺实际 host 的子集；矩阵、相机和 world 输入共用 canonical frame。

`Vec3.cross(value)`沿原ValueHost值类承接[公开叉积合同](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/Vec3.html#cross-value-vec3-vec3)：返回右手叉积的新Vec3，不改变两个输入。它复用原数值运算与最终typed消费者的失败边界，不新增宿主、状态、归一化或幅度许可；未知方法和非法最终值仍局部失败。验收核轴向/反向、一般向量、零/平行、别名及连续两次cross的旋转调用，再核真实作者后继值/副作用及最终输出，不能以原TypeError退出授完整旋转或画面一致。

`setTimeout`/`setInterval` 和 jobs 归原 owner、Scene 时间及调用预算。零步长重绘不重复计时事件；清理 owner 时撤 timers/jobs 和句柄使用权。递归、非有限值、错误参数或预算耗尽只影响实际 owner/操作。

localStorage 使用同一 Session 的内存状态、candidate transaction 与原后台持久化。实际 owner 构造后、configure 之前准备一次；普通帧不首次打开或解析 JSON。候选激活会与前任最新 envelope 合并；取消不发布候选写入。screen scope 需要精确单屏身份，不能在多 Surface 时猜一个屏幕。

源码：[ValueHost](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSValueHost.c)、[ModuleHost](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSModuleHost.c)、[StorageHost](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSStorageHost.c)。

<a id="failure"></a>
## 失败与退出

错误返回类型、异常或中断拒绝本次受影响 typed 输出和 mutation，不覆盖健康 current；真实 heap 写入不被复制回滚。永久禁用、退休和可恢复失败分开，不能用一次 bad return 取消仍活事件或平台输入。

Destroy 从 committed owner 变化进入原程序退出；资源、VM、活动轨道、声音、粒子和平台订阅各在实际消费边界撤权。停场等待原 worker/媒体/GPU drain，不能因某个 JS callback 返回就宣称资源全部释放。

<a id="limits"></a>
## 当前限制与验证

全部官方 handle/API、任意动态资源 recipe、跨 pass/无真实 target 的 Combined/Event-only 动画、所有复杂骨骼/几何/媒体组合仍未覆盖。缺口和下一资格归[队列](../roadmap/scene-open-breakpoint-queue.md)，不由官方 d.ts 数量计算支持率。

最近行为入口：[真实 QuickJS](../../../script/tests/test_scene_script_quickjs.py)、[owner 预算](../../../script/tests/test_scene_script_quickjs_owner_budget.py)、[动画](../../../script/tests/test_scene_timeline_runtime.py)、[TEX 播放](../../../script/tests/test_scene_texture_animation_script.py)。
