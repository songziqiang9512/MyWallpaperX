<!-- document-role: active-plan -->
<!-- retirementCondition: 公开 API 的限定表面、生命周期与预算通过双侧事务门并归入唯一脚本合同后归档，设计登记随实施关闭。 -->

# D4 — SceneScript component、object 与 particle API

> 复核基线：2026-10-01，独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；已合入 `codex/engine-refactor-program`；实施时按其最新代码重新核对所列 owner，以下行号仍指向原设计基线。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

脚本只能通过当前 scene generation 的 typed handles 操作作者对象、经验证的动态对象和粒子系统；脚本调用进入现役 VM→typed mutation→frame transaction，不直接操作 GPU。API 表面一旦公开成为作者兼容合同，且跨 VM、拓扑、粒子和资源 owner。

五判据：横切多个 owner 或主链节点=是；触碰唯一权威合同=是；用户可见且难逆的 API/数据/发布合同=是；触碰机器冻结结构家族=是；依赖官方或平台外部证据=是。

## 当前事实与证据

- `docs/scene/capabilities/coverage-ledger.md:1219` 的 component/object/particle 综合项仍是 L0，不表示所有 object 基础设施都不存在。
- `MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerHandleBridge.swift:224` 已有 upsert/destroy，`:404`/`:408` 已有 C mutation commit/discard，`:436` 区分 layer 与 property-object scope。
- `MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptOwnerLifecycleBridge.swift:60` 已桥接生命周期计数，`:95` 有 mutation overflow 失败。
- 官方公开 [IScene](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IScene.html)、[IEngine](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html)、[IThisPropertyObject](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IThisPropertyObject.html)、[IParticleSystem](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IParticleSystem.html) 于 2026-10-01 核对。公开入口未证明存在作者可调用的 `registerSceneScriptComponent`。

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

显式数量发射的调用期输入与最终 owner 准入由 [D11 的后继切片](particle-playback-state-design.md#显式数量发射后继切片2026-10-02)统一拥有。native hook 只借用当前 cadence 的实际 runtime；不增加第二模拟器或持久出生队列。当前粒子 instanceoverride 脚本返回值由 Swift 在 callback 后 overlay，C 尚无 `.instance` setter：不得为了新 API 把后置返回值倒灌到先前出生，也不得新增“最终参数不同就拒绝 emit”的限制。

同一 callback 内查询读取该事务已验证的 staged overlay，因此 stop 后 isPlaying 为 false，pause 后按尚存粒子判断，play 按 D11 的继续或重新 arm 结果判断，不能直接返回 playing Bool；create 后句柄访问能观察自己的操作。其他 callback（包括同 owner 的另一 timer、ended handler 或随后 update）读取本 cadence 的已提交镜像，不读取前 callback 的 journal；宿主 callback 内 drain 的 microtask 仍归该 callback。renderer 在共享模拟消费后观察，不等待任意一屏的 GPU 提交。overlay 不能跨拒绝存活，也不成为第二个持久对象库。现役 layer candidate plan 须保留本 cadence 已准入的有序 particle transitions 与 revision，不能将 stop→play 压成最终 playing。typed command 携现役 domain.callback_epoch 与 callback 内 ordinal，恢复实际 callback 调用顺序，不按 owner 分组后 flatMap 猜序，也不新增 clock；owner rejection 先移除该 owner 的命令，再重算 candidate intent、transitions 与 revision。每个现役 surface 在 updateSimulation 前消费一次，committed snapshot 仅保留当前作者意图及 revision，供 rebuild 初始化，旧 transitions 不重放。

首次任何 init/cursor/update callback 前，必须先完成各 surface 的 particle preparation，并经现役 layer snapshot publication 发布实际 query projection。当前 `SceneDesktopWallpaperSession.swift:140` 先 rebuild，`:553`/`:565` 调用 loadImageLayers，`SceneMetalView.swift:422` 创建 PlaybackState，随后 `SceneScriptScalarProgram.swift:430` 等执行 initializeIfNeeded；接线须保持这个顺序并覆盖 scalar/string/vector/cursor 共用域。prepareLaunch 的模块装载不是作者 init；准备与准入须验证完整同代 surface 集合，隐藏、静态 alpha=0 或资源失败导致缺 runtime 时明确 unavailable，不能跳过该屏或发布假查询。首 launch 保留现役 warm-up 已产生的真实 prepared-live；init.pause 经同帧 owner admission 后只阻止后续自动排放，保留已有粒子继续模拟，init.stop 在首个 updateSimulation 前清空 live、旧 batch 与历史。官方 warm-up 与 init 次序仍未知，此处是项目初始化边界，不宣称 parity。rebuild 已知 committed paused/stopped 意图才要求在新实例构造前注入，抑制 warm-up 发射。

预算沿现役 VM time/memory/stack 与 aggregate mutation cap，不另开无限队列。首片项目上限为每 owner/frame 256 条 mutation、每 scene/frame 1024 条新增 API 命令、每 scene 128 个动态渲染对象、单次 emit 1024 个、每 scene 65536 个存活粒子；同 owner 的 cursor、timer、event、update 等 effect bundle 合并计入 owner/frame 上限，不能靠拆 callback 重置预算；每个实际有效上限取此值与现役对应预算的较小者，绝不借本设计提高旧上限。待销毁对象占用对象配额及既有 resident-byte budget，GPU 未释放不能返还配额。数字是保守项目配置，不是官方限制；实施时进入既有机器预算并以临界值/超一值测试冻结，调高必须附压力证据与显式基线变更。回调注册计入既有 VM roots/内存与命令配额，未建立可计量预算的 profile 不准入。

## fallback / route

unsupported API/配置是局部脚本调用失败，保留先前有效对象和画面；stale handle/跨 generation、越界、OOM/timeout/预算超限硬拒绝该不安全事务。禁止将失败返回伪装成有效 native handle。迁移沿现役 bridge `prefer-generic`→`generic-only`，旧 setter 同批撤权。

## 纠正门

- 公共签名、thisObject scope、返回类型与方法副作用分别用真实 QuickJS+Swift 门验证，不用 Python 模型或符号存在性代验。
- create→修改→destroy 同事务、throw 后回滚、C 成功/Swift 拒绝、超时、mutation 溢出、销毁回调再次销毁、旧 generation 回调均有反例。
- 粒子以非零 startTime 验证首 launch init.pause 保留 prepared-live 且不新增排放、init.stop 首图清旧 batch/历史；rebuild 的 committed pause/stop 不先 warm-up。有限非周期 schedule 自然结束后 play、固定周期 pause/continue、跨 owner 交错 callback 顺序及 owner 拒绝重算分别验证；隐藏/alpha0/资源失败缺 runtime 必须 unavailable。动态对象验证 prepare 次数、GPU completion、publication 与唯一 compositor；两帧不能重复提交同一 command。
- 公开未说明的默认/相位用固定官方黑盒区分；无环境时该 API profile 保持未开放，设计批准不作完整 API 兼容声明。

## 退役条件

表面与事务已由唯一脚本语义合同接管，所有开放 profile 验收、旧重复 bridge 撤权后归档。未证实 API 不可借归档自动转为支持。
