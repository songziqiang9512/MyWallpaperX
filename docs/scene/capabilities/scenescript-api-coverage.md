# SceneScript 当前接口与语义

<!-- document-role: current-state -->

<a id="contract"></a>
## 作者合同与运行模型

SceneScript 是 property-bound ECMAScript：脚本附着于一个有类型的属性，`init(value)`/`update(value)` 的返回值可写回该目标，直接 setter 可修改其他准入目标。返回值按属性类型校验（本项目合同；官方三列/六色 alpha 探针已验证数值标量的取值行为：仅 Number 生效，字符串 `'0.5'`、`false`、`null`、`[]` 返回均保留 alpha；Number 的 NaN 与 `-Infinity` 渲染不可见（alpha 0），`+Infinity` 与 1.0 不透明（alpha 1））：数值标量只接受 Number；字符串、Bool、`null`、数组/对象（含 Vec3）保留当前值并报 typed bad-return，不做 JS 强转（`[]` 不再变成 0）；`undefined`/无返回保留当前值；布尔属性只接受 Bool，其他返回保留当前值且不报 bad-return。非有限 Number 只经 SceneScript 来源进入 typed snapshot，渲染 alpha（`SceneDynamicLayerValues`）按上述官方映射；粒子 alpha/rate/count 与亮度等 domain 目标保持严格有限，`thisLayer.alpha` getter/runtime field 仍按有限回退；非TRS目标上一帧值原样供 update；authored TRS沿下述当前值交接，authored/user/Timeline 入口仍严格有限。诊断、布尔及非 alpha 目标为项目合同，官方探针未覆盖。`update` 可选；init-only/休眠沿同一脚本数值域投影，仅导出的 update 逐帧调用。声明面见[SceneScript v2.8 类型声明](../development/reference/lib.sceneScript-v2.8.d.ts)；声明存在不表示本项目全部 host API 已实现。

当前使用真实 QuickJS-NG、模块解析和同一 domain 的 heap；不以源码形状、小解释器或 Swift 字典复制 JS 对象。绑定记录 source、owner、target、作者初值及值类型；模块、shared、闭包和脚本 owner 是不同寿命对象。

初始化、属性事件、输入、媒体、动画和 destroy 由实际导出及当前 owner 调度。事件型/idle owner 不因缺 update 被当作不存在。数组、对象别名、RegExp 等语言行为归真实 VM；用户 API 和模块数学归项目 host/value 实现。

<a id="script-instance-property-input"></a>
### 脚本实例属性供货

`scriptProperties` 由原模块或隐式实例对象持有。原 ValueHost 在首次收到宿主输入时供初值，后续只覆盖有效宿主值实际变化的键。相同输入保留作者赋值和对象别名。其他键的面板变化不重置这些值，真实变化仍在原属性事件或值回调之前生效。导出的对象若被脚本换掉，变化的宿主键写入新对象。

原 owner 只保最近一次成功输入的编码字节，与可变 JS 值分开。相同字节直接退出。不同输入按键比较上一份宿主值，包含结构值，沿原 Vec2/Vec3 赋值和失败入口交接。替换每次回调重解析、全量回填的旧路径。对象、回调顺序、用户属性 revision 和 typed 输出仍由原职责持有。验收核未改宿主值的本地写入、相邻键实际热更、被更新的同键、嵌套对象与改名变体，并复验原作者持续切歌和独立真实热更。

<a id="cursor-primary-button"></a>
### Cursor 的主键编号

Session 在原 AppKit 入口保留每条鼠标事件的位置。有窗口的事件转换到屏幕坐标，无窗口的事件已携带屏幕坐标。实时鼠标位置用于原 Surface 轮询。下游沿现有 world/local、命中和 capture 消费 primary 左键的移动、按下、释放和 click。C cursor 参数在同一 frozen 对象内提供数值 `button=0`，up/click 后仍是0，按下状态继续归 `input.cursorLeftDown`。当前入口覆盖 primary，secondary 未接入。

有原生监视器时，原 FIFO 中的主键按下和释放决定 cursor 回调的按钮状态，移动和帧末样本沿已消费的状态投影。轮询仍供应当前位置、普通脚本输入和渲染。无监视器时保留原轮询入口，Debug 显式输入继续沿原 FIFO。切换监视器来源时取消旧 capture，退出时丢弃未分派输入。队列溢出沿原无回调同步；以上均保已识别待重试的回调。窗口和 Surface 路由、快捷方式凭据与事务继续由原 owner 持有。

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

内置图片模型的直接请求与普通层资源复用共享冷准备目录。该目录识别内置版本字段的 `VERSION:2` 和 `version:2` 两种单独拼写，沿原材质配方和已准备纹理发布动态图层；同时声明两种拼写或未知字段仍局部拒绝。版本判定在冷准备完成，作者 shader 的 combo 名按原大小写解释。

<a id="layer-color-values"></a>
Layer `color` setter接受有限三分量原值；[公开颜色教程](https://docs.wallpaperengine.io/en/scene/scenescript/tutorial/colors.html)中的RGB255不能被内部0…1范围门拒绝。原getter、journal、authored read baseline与typed snapshot保同一Double值，text/image显示端继续原clamp后转Float，不按幅度猜÷255、改变单位或写回归一值。原C入口、baseline、Swift bridge与Runtime的重复范围许可退出；finite/shape、owner原子提交、回滚及健康peer边界保持，不新增状态或转换owner。createLayer初始seed与addColor的String类型不由setter资格扩张。

验收核红/白255赋值后的真实文本返回、普通归一值与改名等价表达、authored/dynamic text/image的立即getter及次帧原值、同帧baseline与后续写入、非有限/缺分量/String拒绝和失败owner回滚；极大有限值在现text/image显示消费者中仍须有限；灯的独立raw/非负能量ABI保原局部不可用边界。真实作者按各自显隐和实际raster/末合成验收，不以少一条异常授全部画面、HDR或官方单位parity。

普通命令在既有 commit/下一 cadence 可见；camera、authored TRS、visibility、particle 的当帧投影各沿已实现消费者，不能推广到所有 setter。同字段跨 owner 按真实回调顺序消费，不能恢复额外仲裁或镜像状态；非法 owner bundle 原子拒绝，健康 peer 保持。

<a id="authored-text-current-value"></a>
层句柄写入的文字沿原提交进入后继 `update(value)` 和 Layer getter。已接纳的文字求值实际把它改为另一个值后，提交时从原 `authoredLayerValues` 退掉这笔旧写入，后续由已有 Evaluation snapshot 持有当前值。保留目标定义供后续写入复用。同批有新 `.text` 写入时，其值仍按原阶段供下次 cadence，重复写相同字符串也算新写入。无输出、拒绝或只使用 setter 的层继续持有原值。不扩展同帧 setter 投影，不新增回调、字段 epoch、状态或资源。

验收沿真实 App 验证一次跨层写入、有状态文字继续增长、句柄读到当前文字、后续定时替换及纯 setter 邻例，保资源及目标改名。原播放器用未改包的媒体事件链核完整两行与剩余时间，保封面和作者布局。失败写入不替换健康文字的原值。

<a id="current-frame-authored-transforms"></a>
### 作者变换与派生画面的同帧设计

同一次脚本更新的authored origin/scale/angles与派生投影、环或大气须消费同一帧。旧FrameDriver将变换留到下一cadence，Main写变换与shared后，后继投影却已读当前shared；不能以改作者quad投影、父级或材质补偿此错相。

继续沿原回调顺序、owner journal/准入、typed snapshot及唯一world resolver执行。后继变换回调的update(value)应读它开始时的当前值；同一目标的局部TRS getter与该入参一致，pre-script getTransformMatrix/骨骼观察保原阶段。前一回调setter与后一回调主动返回按真实先后写入同一变换职责，同次值回调中新setter仍保原优先规则；不能在末端无条件令setter覆盖后来主动返回，也不能按return value的源码形状识别passthrough。最终准入后的变换进入本帧世界/相机与原渲染消费者，原下一cadence仍保已提交状态；退出变换的额外一帧延迟及其旧冻结入参。不能另加时钟、模型/大气同步缓存、名称派发、shader延时或改作者层级；现pre-script骨骼/getTransformMatrix观察和其它命令的阶段各自保持，不统一改成全部立即可见。

Coordinator增量折入成功TRS journal，供后继回调入参；有效init/返回归同owner journal。passive Timeline仍投影动画，当帧准入值取自layerPlan。首次跨层写入缺定义时，最终typed overlay从已收敛的plan取该定义及seed，同帧发布值与world变换资格；其余目标复用原索引，提交后按revision刷新。未知目标、阶段前缀及拓扑生效时机保持。

原vector C入口在update前消费timer/事件前缀并统一getter。仅当前序写入实际改变TRS init入参时，用脚本单位暂置原owner读基线，退出即清。回调内setter优先，返回沿原journal。初始化内timer/video-ended改同字段的入参同步待证；骨骼/getTransformMatrix保原阶段。

当前callback抛错/bad-return或本地提交失败的写入不折入后继输入；最终沿原owner原子拒绝、依赖拒绝和commit/discard，健康peer及重绘重试保持。前序成功回调输入只是本cadence候选，不新增跨owner回放或全局反事实事务，shared堆副作用也不冒充typed回滚。旧按诊断字符串吞掉angles坏返回的分支退出；真实write-only合法setter由原C入口处理。

验收先保旧源可区分失败：直接变换setter与共享投影同帧、同target回传并发布shared、后来主动返回的先后、同owner多次写入和拒绝反例；覆盖改名与等价表达，不复制调度逻辑进测试。真实Titan及蓝色母体须看过渡序列而非只看HOLD，保稳定帧、独立真实作者与原camera/显隐/owner事务最近门。当前红绿、实际画面和未闭范围只归[模型运行证据](model-runtime-evidence.md#current-authored-transforms)，不外推完整官方同步或全部镜头。

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

<a id="object-color-admission"></a>solid 与无 effect 的 image 由启动准备确定颜色消费者，生成 `.layer(.color)` Vec3 owner。准入的初始隐藏层仍执行 init 和媒体事件，帧快照决定绘制。solid 复用白纹理，typed 颜色由合成 uniform 或 effect 首端消费一次。依赖、named、错误 seed 及无消费者沿原准入边界。

| 领域 | 当前实际入口 |
|---|---|
| Property Animation | 原 animation handle → TimelinePlaybackRuntime；play/pause/stop/setFrame 与同一轨道 state |
| TEX animation | `getTextureAnimation` → TextureAnimationPlaybackRuntime；typed handle 入口检查存活一次，命令保原 next-frame 顺序 |
| Particle | 原 Layer/ParticleInstance host 的 play/pause/stop/isPlaying/emitParticles 与 typed override；真实出生和预算由原模拟器处理 |
| Puppet | 原 animation/bone handle、会话 animation runtime 与每屏 pose；未接入 clip/channel 不从 handle 存在推定可播 |
| 视频 | 原 material/layer video handle → 视频 registry/source；命令目标与被选资源身份保持，不能按路径广播 |
| Sound | 原声音定义与 voice registry，volume/播放命令消费既有 typed 值 |
| Cursor/媒体/用户属性事件 | 原入口快照与 owner 回调；一次性事件不能因 GPU 重试重复派发 |

<a id="image-single-animation"></a>
### 图片创建一次性 Puppet 动画

[公开 IImageLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IImageLayer.html)规定 `playSingleAnimation` 创建新动画层、播放一次、自动移除并返回 IAnimationLayer；本批基本接入以真实准备资源名 String 和省略 config 为范围。`getAnimationLayer` 的数字参数按当前 stack ordinal 查询，count 读同一成员集合；具名查询使用当前实例显示名，创建只解析真实资源名，不以作者自定义层名兜底资源，不按样本/脚本文本分派。准备、pose 与退休归[原 Puppet 合同](advanced-object-coverage.md#puppet-instances)。

原 image host → Puppet command journal → 原候选准入/apply → 会话 runtime → frozen Domain snapshot/Surface。Cursor 成功回调也必须把同一次提取的 Puppet commands/registrations 经原汇总传入同一 ownerEffects；失败/存储拒绝撤销同 owner 候选，原 finalize 一次消费，不增加 pending mirror。回调返回成功不能代替命令进入准入。返回句柄以原 epoch+ordinal 标识创建，未提交前从同一 journal 的 create 及后继命令投影读取，不另造 pending map；同 owner 可控制刚创建的句柄，失败整体回滚，跨 owner 只读原已发布成员。count 不设独立状态；新成员没有假 editor ID、属性 owner 或 ended owner。原句柄存活、重复消费、父退休和健康 peer 的失败范围保持。

[公开 IAnimationLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IAnimationLayer.html)列出的 metadata、play/pause/stop/isPlaying/getFrame/setFrame 与 rate/blend/visible 沿原桥接承接可用部分。rate1/blend1、可见播放、无额外包络及创建实例沿原源名 fallback 的显示名只记本项目基本选择；官方默认 config/排序、精确出生/结束/过期边界仍 UNKNOWN。显式 Object/config、创建实例的 visible 写入与 Single JS ended 不由这次能力升级；官方窗口未获得有效 native 观察时保 STOP，不据 shader 产物或旧桌面调算法。

验收走真实 VM→journal→coordinator→runtime→pose，核零 authored、改名/等价调用、create 后控制/计数、throw/非法后继回滚及自然移除，保原 authored/Loop/bone 邻例；实际签名 App 再核独立真实资源内点与原作者事件后继。不以 API 不抛错认定完整页面动画或官方视觉一致。

<a id="component-animation-scope"></a>
### 组件属性动画的名称作用域与交接

[公开接口](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IThisPropertyObject.html)允许省略name取得当前属性动画。本机effect pass的当前/具名查询沿原动画句柄执行，同pass其他属性可查，跨pass/effect/layer不兜底；固定官方2.8.0.42和同输入App的九卡资格见[运行证据](runtime-evidence-current.md#component-animation-scope)。观察只覆盖该pass场景，不扩大其他组件或原ILayer/scene查询范围；本pass歧义仍保原局部拒绝，不据跨pass重名卡推一般first-match。

已编译Timeline bindings→原冷catalog→C handle→原有序animation journal→同PlaybackRuntime preview/commit→typed snapshot保持唯一链。原完整target的layer/effect/pass只在冷配置投影，target index与压缩catalog index、current-property sentinel各保身份。一个C动画target配置入口取代旧current-only ABI，原named许可位退为component scope身份；不新增registry、clock、播放状态或逐帧作者树查询，保原目标存活、句柄/owner寿命和事务失败范围。

pass Combined wrapper依原timelineTargets精确匹配已编译目标，供hasCurrentAnimation，不把animation字段当已准备轨。原ValueOwner用真实exports和当次init/pending消费区分值返回与无update的input转发；原coordinator保同一角色，vector与scalar沿原preview在admission回接真实Timeline输入。仅转发输入的事件/idle owner不造值writer；真实init本次返回和真实update（包括return input）仍是值writer。已提交无Timeline值归原EvaluationTransaction，pending初始化寿命不延长，无持久输入副本或值相等猜测。两lane只遍历本帧实际转发target集合，退出无关Timeline全表扫描，保原scalar合法域和拒绝过滤。

最近真实C/VM与共享coordinator/Playback/Transaction核同pass/改名、current无参/同名、跨域/missing/duplicate、保留句柄/退休/回滚、精确冷目标、Vec2/Vec3、init/事件/timer及真正update角色；App复用冻结九卡和既有官方oracle。作者后继输入、材质与事件资格统一见[运行证据](runtime-evidence-current.md#component-animation-scope)，静态九卡不升级为完整作者动画、其他组件或持续播放；不强制显隐或重复旧矩阵。

<a id="animation-events"></a>
### Property 与 Puppet 的共同 animationEvent 接收

[官方事件教程](https://docs.wallpaperengine.io/en/scene/timeline/animationevents.html)给出`animationEvent(event, value)`及同layer监听；此scope不同于组件当前pass的具名动画查询。自然property事件以原prepared target归属的layer投递给实际导出该函数的存活owner，覆盖本属性、同pass其他属性、其他pass/effect及同层visibility/alpha；接收者不必自带Timeline，隐藏不等于退休。首批值域为原Bool/Number/Vec2/Vec3 typed entry；来源和限定运行范围由[证据](runtime-evidence-current.md#property-timeline-events)拥有，不扩大到未资格类型/来源。

共用原Domain的intrusive owner链、pending队列、cursor/epoch及commit/discard；Puppet实record身份/incarnation/sequence与property来源使用不同tag，不给property伪造Puppet catalog记录或另建listener/source registry。构造末端按真实exports/Puppet控制需求统一注册，旧Puppet configure退出隐式listener注册；无export的Puppet控制仍保原rebind。只有receiver真实退休清整队列，Puppet source过期按原逐项身份检查省略，不能因receiver自身clip暂缺清掉其他property pending。原Puppet控制/ended callback合法域保持。

原共同C drain恢复该owner handles/engine，调用真实export并沿原jobs、journal和typed decode交接。第一参为事件name/frame，第二参为接收属性的当前typed值，不把source轨的Vec2发给所有人或压成Number。Number/Vec2/Vec3只在本次调用栈报告实际返回/写值角色，经既有`valueFollowsInput`及coordinator/admission接numeric Timeline preview；无返回且无自身写入保输入转发，真返回即使等值也不能据值相等猜角色。Bool保持当前Bool并由原visibility journal归一，本身无numeric Timeline来源，不声称同一role metadata。自身setter归原journal/current，原init/update角色保持；Number alpha只消费匹配的旧setter字段、返回仍走原scalar域，复用原Bool字段清理/空record压缩，保其他字段、effect与后继setter，不把NaN/±Infinity写入严格setter运输。scalar永久源码类别与media回调识别器退出，不新增持久role、last-event值或setter overlay；Number对置setter/return只要求已资格的首次getter观察，不外推其他类型或永久覆盖顺序。

自然producer与确认顺序见[Timeline合同](runtime-input-property-coverage.md#timeline-events)。事件内play下一动画仍走原有序journal/preview/apply，不递归flush新事件或另加timer。多listener/callback-update精确次序、相反Bool/Vec setter-return、向量原地改后undefined等边界只随实际证据扩展；沿原局部异常/失败半径，不修改作者逻辑。旧Puppet-only pending/dispatch/publisher职责同批退出，共同部分由原Animation bridge/host承接，Puppet专有身份与控制继续原owner。

<a id="particle-instance-scalars"></a>
### Particle instance 数值

`IParticleLayer.instance` 的 `alpha/rate/count` 复用原 Layer 身份、owner journal、snapshot/commit/discard 与 typed particle target。默认均为1；alpha 供后续出生，count 为自然发射倍数，rate 在原模拟步中缩放时间一次。它们不是粒子存量或绝对发射率；`emitParticles(n)` 保精确请求数量及调用点 alpha 前缀，不能被 count 缩放，也不能让晚 setter 重写早先出生。

接入只一般化现有 alpha 访问器和原 C/Swift 记录中的独立字段位；原 publication 一次供三个当前值，替换并退役 alpha-only publication，不新增 owner、缓存、命令或模拟器。原 typed snapshot 和 root/child 的 override 消费者承接数值；getter 按本 owner 当前写入、读值 baseline、已冻结 snapshot 取值，setter 只在原入口检查真实有限 Number。C publication/baseline 的外部入口保 finite，Swift bridge、baseline 准备和 replay 只传已定型值，退出原 alpha 三处重复检查。非粒子、已退休或无实际 instance 消费者的句柄沿原局部失败，不新增幅度、整数或源码形状许可；现有 preparation 集合复用到当帧 admission，不重复扫描每屏资源。

当次接纳的 instance journal 进入原 frame projection，附着 scalar 返回继续按原 property-bound 合并次序覆盖同 target；已提交句柄值进入下一 preliminary。相反的自身 setter/返回及隐式 init 的输入交接尚无官方排序资格，不能由既有 alpha 行为升级为官方合同，也不为避开未知组合拒绝合法赋值。该范围不改通用 callback 仲裁或 C primitive 调度；需要改变这些职责时先返回独立设计。

验收复用真实 QuickJS→journal/ABI→Runtime→当帧 snapshot→原 Simulator/Metal，核零/.5/1/2、自然数量与时间/运动、字段互不覆盖、baseline/后继读取、失败 owner/健康 peer、缓存句柄与改名等价表达；保显式 emit 精确 n、调用点 alpha 和 root/child 原继承/禁用位。真实 App 以可区分自有控制及独立作者回归限定结果；未定位可归因作者赋值前不报作者恢复，不以当前 VM 数值授官方 parity。证据和未闭范围分别归运行证据与开放队列。

<a id="sound-handle-volume"></a>
### Sound 句柄音量

`ISoundLayer.volume`沿[公开属性](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ISoundLayer.html#volume-float)接入普通authored Sound的真实音量消费者；缓存引用与shared函数继续由当前执行owner写入原journal。getter按当前写入、owner baseline、已冻结snapshot读值，setter只发布scalar，不直接操作AV。原C入口核数值/finite，原Sound计划与gain消费者保既有数值域；不追加幅度许可或猜官方异常域，不扩动态Sound创建。

prepared Sound binding只提供`.layer(id,.volume)`及其真实seed，在原authored definition map补缺，保已有property、timeline与Script定义，不从render alpha或常量1造基线。C staging、ABI与Swift mutation复用原snapshot/commit/discard，不新增音量表、命令或缓存作为第二权威。音量供值缺失只使该getter/目标不可用；原playback-only snapshot仍可供play/pause/isPlaying，不因新字段拒整份发布。普通帧按原authored→user→timeline→script优先级合并：已提交句柄值进入preliminary，当次接纳的附着scalar返回仍覆盖同target，不把历史setter永久钉在其上。

同一Registry继续持有baseVolume和真实player，并在其后应用master/mute。原无property与已构造附着Script的消费资格不变；新增句柄来源必须同时满足原Runtime已提交authoredLayerValues确有该volume target、且本snapshot entry为`.sceneScript`。source标签自身不能让未构造Script抢占direct property。Session在提交layerPlan后从原值map提取临时layer ID集合，向两条Registry lane只传这一来源事实，不增持久mask/缓存或传完整Runtime。即时property lane跳过同一交集及原静态附着Script目标；没有snapshot值不重置声音。原限量DEBUG回执记录base/master/mute的实际变更，即使effective未变；AV属性仍仅在Float位改变时写入。play/pause/stop、clock、资源和退休仍归原owner。

暂停属性刷新保持原mixed owner集合与冻结clock；已进入该入口的回调可提交仅含volume字段的authored upsert。沿原fixedPoint承接这些prepared Sound target，最终scoped snapshot先取接纳的layerPlan音量，再叠当前合法scalar返回；不启动外部origin writer或新增回调cadence。错型、缺消费者、无效混合写入或失败bundle沿原owner原子拒绝，健康peer保持。

验收复用真实QuickJS→journal→Runtime→snapshot→AVQueuePlayer，核即时/后继getter、0/.5/1、改名、缓存引用/shared执行owner、失败回滚与缺源/退休，保直接property、附着Script、暂停、master/mute和同player/clock。真实3603711180按anyPlaying实际前缀核base与master后effective gain，3555523865保通用C ABI与向量环；不以R0无异常、单一effective数值或PNG证明听感、物理声卡/音频标定或官方像素。

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

最近行为入口：[真实 QuickJS](../../../script/tests/scene/test_scene_script_quickjs.py)、[owner 预算](../../../script/tests/scene/test_scene_script_quickjs_owner_budget.py)、[动画](../../../script/tests/scene/test_scene_timeline_runtime.py)、[TEX 播放](../../../script/tests/scene/test_scene_texture_animation_script.py)。
