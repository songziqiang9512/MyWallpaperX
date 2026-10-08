<!-- document-role: active-plan -->
<!-- retirementCondition: 公开 API 的限定表面、生命周期与预算通过双侧事务门并归入唯一脚本合同后归档，设计登记随实施关闭。 -->

# D4 — SceneScript component、object 与 particle API

> 原设计基线2026-10-01 `93b1b85a`；2026-10-04实例alpha后继以主分支`10e3f889`及官方自有黑盒为准。设计批准不等于实施或运行验收，历史行号开工重核。

## 目标合同与设计判据

脚本只能通过当前 scene generation 的 typed handles 操作作者对象、经验证的动态对象和粒子系统；脚本调用进入现役 VM→typed mutation→frame transaction，不直接操作 GPU。API 表面一旦公开成为作者兼容合同，且跨 VM、拓扑、粒子和资源 owner。

五判据：横切多个 owner 或主链节点=是；触碰唯一权威合同=是；用户可见且难逆的 API/数据/发布合同=是；触碰机器冻结结构家族=是；依赖官方或平台外部证据=是。

## 当前事实与证据

- component/object/particle综合项仍有缺口，不能由综合等级推断各基础设施缺失；现`SceneScriptLayerHandleBridge`已有upsert/destroy、mutation commit/discard与scope隔离，`SceneScriptOwnerLifecycleBridge`已有生命周期及mutation预算。
- 2026-10-01核对官方[IScene](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IScene.html)、[IEngine](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html)、[IThisPropertyObject](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IThisPropertyObject.html)、[IParticleSystem](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IParticleSystem.html)。公开入口未证明作者可调用`registerSceneScriptComponent`。

## owner

QuickJS domain owns JS object 与 callback roots；现役 Script bridge owns handle 验证与 mutation 编码；host frame transaction owns commit 时机；graph/resources owns 动态对象准备与释放。粒子作者播放意图纳入现役 `SceneScriptDynamicLayerRuntime` 的 typed layer state、candidate plan 和 immutable committed snapshot，C 只保存已提交镜像与 callback journal；不另建 session 意图库。各 surface 的现役粒子 runtime 仍独占实际 emitter schedule、存活、粒子 ID 与随机流，按 [D11](particle-playback-state-design.md) 消费有序转移。注册内部组件不能建立第二份对象树、simulation 或 clock。

## 方案设计与选型

选择**公开表面白名单 + 现役 handle bridge 扩展**。不把内部注册符号暴露成自创官方 API，不让脚本携带 native pointer，也不通过 JSON 整图序列化同步每帧状态。

| 作者表面 | 类型/返回 | 第一阶段行为及边界 |
|---|---|---|
| `engine.registerAsset(file)` | String → IAssetHandle | load/preparation 期解析允许根内资源；普通帧不得同步加载/编译 |
| `thisScene.createLayer(configuration)` | String/Object/IAssetHandle → ILayer | 先支持已准备的 asset handle 与可验证的 bounded object 配置；未准备配置显式局部失败，不返回假成功对象 |
| `thisScene.destroyLayer(target)` | String/Number/ILayer → Boolean | 复用延迟销毁、现役作者 identity 解析；不能复用已撤销 handle |
| `thisObject` | 按绑定归属为 layer/effect/property object | 保持现役 scope；不能把 component 属性写到 layer 同名属性，也不能为调用粒子四方法将 property/component object 偷换为 layer |
| `thisLayer` / 现役 scene layer lookup | ILayer；粒子层提供 IParticleSystem 能力 | 四方法挂现役 layer handle，再按 prepared particle profile 准入；实例参数脚本可经 thisLayer 操作所属粒子系统 |
| `IParticleSystem.play/pause/stop` | 无参 → void | 首片限已准备 root、无任何 authored child、恰一 supported 确定性 emitter schedule（periodic disabled 的有限 duration/burst 或默认连续排放，或 supported 且 duration/delay 各自 min=max 的周期窗口）；随机周期拒绝，转移语义引用 D11 |
| `IParticleSystem.isPlaying` | 无参 → Boolean | session 对当前代有效实例作只读 OR projection；同 callback 叠加有序 journal，缺实例返回 unavailable 调用失败，不能伪装 false |
| `IParticleSystem.emitParticles(count?)` | 可选 Number → void | 限定交付显式整数 0…1024，取现役更小预算；真实出生、调用期输入、同 callback query 与全 surface 准入见 D11。省略、非整数/非有限/非 Number、额外参数仍局部失败；实际验证范围见[执行记录](../../history/rf03-particle-playback-implementation-2026-10-02.md#rf03-explicit-emission) |
| `IParticleSystem.instance` | IParticleSystemInstance | [公开实例表](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IParticleSystemInstance.html) 的 alpha/size/count/speed/lifetime/rate/colorn 为 Number，controlpoint0…7 为 Vec3；各字段消费相位单独验证 |

普通 JS 自定义对象仍由 VM 管理，不因此变为可渲染对象。2026-10-02 再核[公开 globals](https://docs.wallpaperengine.io/en/scene/scenescript/reference.html)及[IThisPropertyObject](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IThisPropertyObject.html)：thisLayer指当前层，thisObject随属性归属动态变化；不能用人工把thisObject设为layer的C夹具代替真实实例参数脚本。component callbacks 首片只接现役 init/update/destroy 生命周期。`registerSceneScriptComponent` / `sceneScriptComponentAPI` 是内部装配命名候选；未找到公开签名的“注册任意组件回调”保持 unsupported，后继须补官方声明与独立合同后才扩大表面。

handle 包含 scene generation、owner kind、object identity 与生命周期 epoch；C 与 Swift 两侧校验。create 先返回本事务 provisional handle，只在该事务内可见；准备失败回滚并撤销 handle，不能有部分 publication。destroy 在安全帧边界撤销，保留 GPU 资源到 completion；destroy callback 最多一次。

安装发生在 descriptor/resources/handles 准备后、首次 init 前。update 不得递归触发另一轮更新；callback 产生的命令按作者事件顺序 staged。成功 JS 调用不等于已消费：先通过现役 callback/owner admission 的 Swift 验证，C staged mutation 与 Swift typed command 同时接纳或局部 discard；不能只撤 Swift 结果而留下 C 状态。共享 session 已消费的 VM 回调、对象命令和模拟状态服从 [D10](frame-admission-retry-design.md)，后续任一或全部 surface 的 drawable/encode/GPU 失败都不能重放回调或恢复旧命令；JS heap 本身不作为可回滚快照。

显式发射调用期输入和最终准入由[D11](particle-playback-state-design.md#显式数量发射后继切片2026-10-02)拥有；native hook只借当前cadence实际runtime。instanceoverride脚本返回值在callback后overlay，不倒灌先前出生，不因最终参数不同拒绝emit。

**实例alpha后继（2026-10-04）。** 自有官方2.8.0.42黑盒已证`thisLayer.instance.alpha=.25`使灰128的新粒子变32；4秒切换后长寿命旧粒子仍128，绑定返回值同相位。沿现layer handle暴露只读instance句柄，首片仅alpha Number getter/setter；getter取当前代镜像及本callback overlay，缺省1，setter须有限Number并复用现因子消费，不借generic layer alpha。其他instance字段不得假成功写入；普通非粒子、已销毁/旧代句柄局部拒绝。粒子类型与实例可用性独立于播放命令的单emitter/无child准入，不因此拒绝已有正常粒子参数路径。

复用layer mutation journal增加独立particleAlpha字段，原owner effect bundle、预算及fixed-point同时接纳/撤回；Swift启动预注册`.particle(id,.alpha)`定义，以typed snapshot为唯一提交权威，C仅镜像。无authored instanceoverride时沿原resolver使用中性默认，不新增参数库。新值作用后续出生，旧粒子不重乘；root/child沿现override继承。`alpha=A;emit;alpha=B;emit`由既有同步hook捕获各调用前缀，后置属性return不改早先出生。本cadence已准入setter进入现snapshot再自动模拟，跨callback仍读cadence已提交镜像；throw/owner拒绝撤回C/Swift及出生候选，GPU失败不重放。getter写入字段不等于整套instance API已开放。不选择普通可写JS对象（无消费/回滚）或整层GPU乘数（误改旧粒子）。验收真实VM→Swift→Simulator的identity、无authored默认、0/.25/1、非法类型/非有限、旧句柄、samecallback读回、两次setter/emit次序、throw/late-owner拒绝及健康peer；App同输入灰32、无TypeError及Metal/drain成立，旧粒子与绑定控制保留。完成后归现脚本合同；其他实例字段、官方return顺序与完整样本parity继续单独验证。
同callback查询读取已验证overlay；stop/pause/play的query按D11实际存活及排放工作推导，不能直接返回playing Bool。其他callback含同owner的timer/event/update均读本cadence已提交镜像；本callback drain的microtask归当前journal。共享模拟后renderer观察结果，不等GPU。candidate保留domain.callback_epoch/ordinal顺序、转移及revision，不按owner分组猜序或把stop→play压扁；owner拒绝须移除其命令并重算。每surface模拟前消费一次；committed只留intent/revision供rebuild，旧transitions不重放。

首次init/cursor/update前，完整同代surface必须完成粒子准备并发布真实query projection；prepareLaunch模块装载不算init。各scalar/string/vector/cursor共用该顺序，不能从缺失屏或空集合发布假查询。首launch保留现warm-up的prepared-live：init.pause只阻止后续出生，init.stop在首次模拟前清live/batch/history。rebuild须在构造前注入committed paused/stopped，禁止先warm-up再补开关。官方warm-up/init次序未知，不声称parity。
预算沿现役 VM time/memory/stack 与 aggregate mutation cap，不另开无限队列。首片项目上限为每 owner/frame 256 条 mutation、每 scene/frame 1024 条新增 API 命令、每 scene 128 个动态渲染对象、单次 emit 1024 个、每 scene 65536 个存活粒子；同 owner 的 cursor、timer、event、update 等 effect bundle 合并计入 owner/frame 上限，不能靠拆 callback 重置预算；每个实际有效上限取此值与现役对应预算的较小者，绝不借本设计提高旧上限。待销毁对象占用对象配额及既有 resident-byte budget，GPU 未释放不能返还配额。数字是保守项目配置，不是官方限制；实施时进入既有机器预算并以临界值/超一值测试冻结，调高必须附压力证据与显式基线变更。回调注册计入既有 VM roots/内存与命令配额，未建立可计量预算的 profile 不准入。

## 作者图层跨层删除后继（2026-10-07）

真实首断点是开场控制脚本删除另一个已准备作者图层时被自层限制拒绝，导致淡出中的暗幕和Logo永久残留。公开[IScene](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IScene.html)允许按name/index/ILayer删除并明确延迟生效。本片已沿现authored mutation journal允许有副作用权限的owner删除已准备、有效、无子层的作者图层；只改两个guard会遗留死层脚本，不能作为交付。Boolean controller跨层删除不改自己的返回值，自毁才归并false；有效删除请求返回true。纯value-only、陈旧句柄、子层级联与未准备对象不借此开放。

唯一DynamicLayerRuntime在候选plan中保留动态层的创建owner归属，接受作者层删除时一并移除该层脚本创建的动态渲染对象；同一plan撤回全部相关变化。共同模拟commit先finalize所有peer journals，再按新接受的tombstone退休目标层scalar/string/vector/cursor cohort，复用现生命周期teardown清timer/jobs/ended roots与C动态层，销毁回调至多一次。共享owner不得重复退休；从后续update、media、cursor调度剔除。teardown沿现清理合同，不把destroy回调里新发出的绘制命令另开嵌套提交；其跨对象副作用完整语义仍待独立生命周期后继。资源保持launch/residency/completion所有权，不因删除释放在途GPU资源。当前cadence使用原topology，下一cadence投影移除；不等待surface/GPU成功，也不重放已消费脚本。

Scalar/String通过现生命周期bridge内的value-owner协议共用一个退休入口；Vector复用同一清理循环，Cursor只负责自有owner及借用注册注销，不新增生命周期owner。没有待退休owner时不重建binding属性表。

不新建对象树、clock或销毁队列。拒绝owner的删除不触发退休；先写后删、删后写、重复删除、带child拒绝、被删provider/组合成员不回生均需反例。已实施证据见[删除与退休记录](../../history/authored-layer-retirement-2026-10-07.md)。核心门为真实parser→VM→typed plan→下一帧descriptor，目标timer/update停止、健康peer保持、动态副本同步移除、throw/Swift拒绝无提前退休，以及原样本4秒后暗幕和Logo退出真实合成。官方精确callback先后、多屏呈现及父层级联另验，不能把局部leaf实现称为完整IScene。

## Puppet 动画层后继（2026-10-07）

目标是让作者 `animationlayers[].visible` 及其 `IAnimationLayer` 控制进入真实骨骼、alpha、挂点和合成。它不同于属性 Timeline，不能借 `getAnimation()` 冒充。固定官方 2.8.0.42 自有黑盒确认：隐藏层冻结帧位置而 `isPlaying` 仍为 true；恢复后继续。`play(); setFrame(frameCount*.93)` 同 callback 保留小数位置且继续播放；getter 即时变化、公开骨骼姿态下一 update 才变化。暂停定位的 raw getter 保留负值和超尾值，姿态采样钳位到首尾；自然循环仍取余。现有自然播放 TRS 小数插值已由 controlled 轨道 0/.5/1 验证，不替换数学。研究原件暂存 `/private/tmp/mwx-puppet-seek-20261007/official`，不将单版本实验外推完整 API。

**第一片已实施：共享播放位置与隐藏恢复。** LaunchContext唯一播放owner与所有surface共用采样已接通，旧三处独立取帧退出；相同定义重建保留位置，暂停重建新恢复层补入当前冻结快照。稳定合同归[高级对象覆盖](../../capabilities/advanced-object-coverage.md)，验证与限制归[完成记录](../../history/puppet-animation-visibility-2026-10-07.md)。不再作为待开发项；下一片沿现owner扩展，不重新建立播放状态或clock。

**第二片已实施：作者脚本入口与有界控制事务。** 精确解析 animation-layer wrapper 和稳定身份，Boolean 返回值只写该动画层，绝不能写父图层 visibility。首次 init 前安装由已准备 MDLA 提供的 metadata 与真正 IAnimationLayer handle；先闭合本层控制，再另验跨层 lookup/create/destroy。命令沿现 owner effect bundle 的有序 journal、预算、Swift fixed-point 验证和共同 commit/discard 接纳，应用于同一 session 播放 owner；C 只保存 committed mirror 与当前 callback overlay。phase seek 和自然推进分开，所有消费者仍使用一个快照。不得为了 `'addEndedCallback' in thisObject` 分支提供空方法；ended 注册必须有真实有界 roots、实际结束事件、teardown、失败原子性和不重放的 cadence 消费。自然loop ended已证在帧推进后、普通update前且读到wrap位置；最终GPU相位、mirror及跨多圈等未定行为先用有界实验裁决，不能凭方法名称猜测。真实 authored init→VM→typed command→次帧 pose→GPU/compositor、throw/Swift拒绝/stale handle已验；证据与未验的多surface联动、官方GPU相位见[完成记录](../../history/puppet-animation-control-2026-10-07.md)。

本片实施边界：nested owner 同时绑定父图层 ID、动画层 authored index 与 ID；首次 profile 只准入 ID 存在且父层内唯一的 `visible` Boolean wrapper，复用既有动画层 typed visibility target，避免另造动态值通道。Script properties 继续复用通用 codec。脚本静态隐藏的 clip 也必须准备，返回值与控制命令均不能误落到父层 visibility。跨层 lookup/create/destroy 不在此片。

控制数据由共享播放 owner 发布只读 metadata/state 快照，C handle 只持身份、镜像及有序 callback overlay。play/pause/stop/setFrame 和 rate/blend/visible 的写入进入同一个 owner effect bundle；原始帧位置与渲染采样位置分开，显式越界 seek 只在采样端钳位。普通帧先推进播放并发布骨骼，再执行脚本；本片以已证的下一帧姿态作为验收下限，最终 GPU 相位不冒称官方一致。ended 注册必须在现有事务成功时保留、失败时撤销，使用实际自然结束事件并在 update 前执行；重复 cadence 不再次消费，未知 mirror/跨多圈行为需明确有界 profile，不能用假回调掩盖。控制命令上限取既有 owner/frame 与场景通道预算较小者；失败拒绝整个 owner bundle，重算其他 owner，不扩大到整个父层或 scene。

## 属性 Timeline retained handle 后继（2026-10-08）

真实作者在 `init` 保存 `thisObject.getAnimation()`，随后在媒体事件调用 `stop/play`；原 callback epoch 限制使该合法同 owner 调用报 stale。公开 [IThisPropertyObject](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IThisPropertyObject.html) 返回当前属性的 [IAnimation](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IAnimation.html)，未规定 callback 临时寿命；此片不冒称已有官方缓存行为黑盒。沿现 property Timeline bridge 保持当前 target、play/pause/stop journal 与唯一 Timeline runtime，组件及图层的 accessor 和返回 handle 共用 domain、单调 owner identity 和 generation；每次调用从当前 active owner 解析并校验同身份、同代、未禁用和当前 Timeline 可用，不保存可能释放的 owner 指针。合法 init/event/timer/update 间复用成立，callback 外、跨 owner、销毁或同代重建均拒绝；JS throw 和 Swift 拒绝继续走既有 owner bundle 接纳/撤回，不因 handle 持久化重放命令或新增 clock。named lookup、rate 和其他 IAnimation 方法不在本片。真实 VM 及 ASan 门验证 init→media、事务拒绝、disabled、generation、销毁重建后保留的 handle、`thisObject` 和 detached accessor，以及健康 peer；实际原包运行另证。

含 `init` 的属性脚本仍可能变换值，不能仅因没有 `update` 改判为纯 Timeline 控制。已准入且带 Timeline 的 scalar 值管线在 idle 只投影当前 typed 输入和原有有限数据属性 overlay，保持 SceneScript 值发布而不重跑 VM。单次求值结果不可变地保留是否透传输入：本次实际 init、pending initialization、update 或有限 bound overlay 的主动值不标为透传，不按数值相等推断来源。现有 frame admission 在同一次已接纳 Timeline preview 上更新透传值，仍发布 SceneScript source；投影复用原 target scalar 校验，非法候选保留已验证当前值。固定点拒绝后沿原命令集合重算，不重放回调、再次读属性或新增 preview/clock。没有命令的普通帧保留原值，失败/disabled/退休和旧 snapshot 恢复继续遵守原 owner 生命周期；event-only Timeline 控制保持唯一 Timeline 值 producer，无 Timeline 的稳定 owner 保留原 idle 跳过。材质 finalizer 不放宽 source 校验，也不以 authored fallback 掩盖缺失输出。

## fallback / route

unsupported API/配置是局部脚本调用失败，保留先前有效对象和画面；stale handle/跨 generation、越界、OOM/timeout/预算超限硬拒绝该不安全事务。禁止将失败返回伪装成有效 native handle。迁移沿现役 bridge `prefer-generic`→`generic-only`，旧 setter 同批撤权。

## 纠正门

- 公共签名、thisObject scope、返回类型与方法副作用分别用真实 QuickJS+Swift 门验证，不用 Python 模型或符号存在性代验。
- create→修改→destroy 同事务、throw 后回滚、C 成功/Swift 拒绝、超时、mutation 溢出、销毁回调再次销毁、旧 generation 回调均有反例。
- 粒子以非零 startTime 验证首 launch init.pause 保留 prepared-live 且不新增排放、init.stop 首图清旧 batch/历史；rebuild 的 committed pause/stop 不先 warm-up。有限非周期 schedule 自然结束后 play、固定周期 pause/continue、跨 owner 交错 callback 顺序及 owner 拒绝重算分别验证；实际未准备/陈旧 runtime 必须 unavailable。动态对象验证 prepare 次数、GPU completion、publication 与唯一 compositor；两帧不能重复提交同一 command。
- 公开未说明的默认/相位用固定官方黑盒区分；无环境时该 API profile 保持未开放，设计批准不作完整 API 兼容声明。

## 退役条件

表面与事务已由唯一脚本语义合同接管，所有开放 profile 验收、旧重复 bridge 撤权后归档。未证实 API 不可借归档自动转为支持。
