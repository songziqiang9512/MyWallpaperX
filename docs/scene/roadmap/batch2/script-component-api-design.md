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

<a id="named-user-pass-scalar"></a>

## Named-user pass scalar 输入（2026-10-16，有界已实施）

目标是让 effect pass 的有限 Number `script/user/value` 包装进入现有 Scalar owner；outer user 是当前属性输入，脚本返回值是唯一高优先级 uniform producer。真实 slider 包装已定位，原入口仅允许 named-user Vec3，故在 binding 解析即丢失 scalar owner。选择补接现有输入链，不加 VM、属性状态、frame writer 或特殊 shader profile。

Binding reader 只扩有限非 Bool Number 与规范化命名 user；Scalar projection 校验完整 owner/path/source、wrapper、user identity 及单分量类型。matching named input 的 resolved descriptor 可以与 raw authored fallback 不同，owner definition 仍保 raw seed；无 user 分支保原 seed 一致性。Material classifier 仅消费 exact target proof，将 user 留作输入，不能忽略脚本或登记并行输出。原 property compiler→preliminary snapshot→Scalar VM→settled snapshot→Program uniform/graph/唯一 compositor 全链复用，普通帧不增加解析或全图扫描。

首片只扩无 animation 的 `script/user/value` Number；scriptproperties 混合、数值 String、Bool、Vec2、其他 host 与 Timeline 控制不扩。缺失/错误/重复定义的属性仍由原 property compiler 诊断并提供原 authored/current fallback；没有 VM proof 保留 unproven attachment，失败返回、事务拒绝与退休沿原局部回退，不提前确认事件或发布部分结果。

验收用改名及等价表达式确认真实输入被脚本变换，覆盖非默认保存值启动、连续热改、错误类型/非有限返回、缺失或重复 owner、未知 wrapper/竞争 Timeline及健康旧 scalar/Vec3/property-only。最终隔离 App 须直接确认 target identity、typed 输入/输出与 encoded uniform、GPU/末合成/下一帧及实际旋转响应；未参与修法内容另作真实渲染。若没有实际 owner/consumer 或画面响应，保留未证边界，不扩大 wrapper 或颜色域；一个有效构建和最近门可复用。

<a id="camera-layer-fov-scalar"></a>

## Camera layer FOV scalar（2026-10-15）

合法 native-perspective default-camera layer 的 FOV 属性脚本复用原 scalar Program、QuickJS domain、typed snapshot和唯一 camera-frame。现役准入、数值、来源、失败/退休与未覆盖合同统一见[Property-bound 核心合同](../../capabilities/scenescript-api-coverage.md#2-property-bound-核心合同)；实现与验证身份、原生结果及未验边界只记[限定证据](../../history/camera-layer-fov-live-2026-10-15.md)。本段不另维护状态或测试清单，`ICamera` JS handle仍不因此开放。

取舍保留：Bindings只分类原object-scalar wrapper，不从raw JSON重算camera资格；prepared projection复用原camera owner的ortho/clip条件，实际layer world-frame/FOV override继续由同一consumer验证，不能以scene fallback完整性替代真实layer-camera资格。内部属性只更新原VM输入，不按样本/脚本文本猜消费，不扩direct FOV user、Timeline/animation或其他相机字段，不新造VM、camera、clock、last-value cache或投影公式。

真正topology退休只在原已提交lifecycle沿binding owner.layerID撤唯一Schema登记；失败禁用继续保previous-current，不能混作退休。累计墓碑在全部quiescent后不再新增bindings收集，cleanup重试仍可撤权；held snapshot、健康peer和原Scene代际屏障保持。该后继独立于其他历史D4批次，不将其重新设为串行前置。

## Legacy RegExp capture 后继（2026-10-13）

原native intrinsic的capture/realm/GC与失败边界已实施；唯一可观察合同见[API表](../../capabilities/scenescript-api-coverage.md#native-regexp-captures)，设计取舍、成本及真实时钟证据见[冻结记录](../../history/native-regexp-capture-2026-10-13.md)。不新增wrapper/正则算法或clock，未证完整提案与官方parity；普通编辑重建仍归属性卡。


## 共享 VM 容量与安装失败后继（2026-10-13，实施中）

原包隔离 App 在第 742 个 owner 的 layer handle 安装处实际耗尽共享 VM 的 16 MiB heap；记录为 memory-exceeded，分配量 16,777,168 / 16,777,216 bytes，计划上界为 935 个 owner。首个真实内存错误已沿现候选域 fatal 路径退出，旧逐 identity 重试耗尽 4096 的扩大失败已排除；该 16 MiB 版本原包开场仍未恢复。该证据说明容量不足，不定位症状的引入提交。32 MiB 前一候选的隔离原包已完成自动开场、后续运动与网格切换；本片最新安装失败边界仍须固定源码重建重验，不能沿用旧候选的运行结论。冻结身份及播放验收归[本轮中性历史记录](../../history/scenescript-host-heap-admission-2026-10-13.md)，不由此设计登记替代。

比较三个方向：共享 native handle 载荷可减少外部分配，但当前 QuickJS 每函数仍有独立函数对象与 closure record，不能单独消除 VM heap 缺口；按读取生成方法可减少 eager 函数，却将现 own data property 改成 accessor，属性描述符及 writable 行为的迁移证据不足；本片选择全局默认共享 JS heap 的有限 32 MiB 候选，保持现方法和 handle 语义，并以真实原包及自有高 owner 数验证。失败后不自动扩容，不按样本身份调度容量。

唯一预算 owner 仍是 SceneScriptScalarBudget：准备阶段将 JS heap/stack/interrupt/source 限额交给现 QuickJS domain，将独立 native transient 限额交给原 particle host boundary。默认 JS heap 为 32 MiB，默认 native transient 保持 16 MiB；存储两个独立字段。显式 initializer 的 native 参数可省略，省略时继承该调用者原 heap 限额，以保留现自有 custom budget 语义；生产 .default 显式指定 native 16 MiB。owner 构造工作 4096、单 owner/aggregate source、stack、interrupt 与现候选域重建规则均不变，不新增预算、identity、cache 或生命周期 owner。

handle 安装失败在清理前保留真实异常及 effect/layer/object 阶段、heap 分配快照，失败 owner 释放后分类；compile-only、engine-bind、namespace 与 handle 安装共用 native 异常分类，仅读取 Error 自有 data message，不执行可被此前 owner 改写的 formatter、accessor 或 Symbol.toPrimitive。这些 native 构造均不执行作者代码，四个 caller 均分离调用前旧异常与新 native 异常；成功恢复原旧异常，返回成功值同时留下新异常仍拒绝并清理已转交资源。失败 return 未留下新异常时只释放旧异常，不把旧 null/Error 当成新 OOM；compile 保留 compile-error 映射，其他未知失败为普通异常。真实新内存错误进入 memory-exceeded；compile 释放返回 module 且不进入作者 evaluation，bind 撤回原 active engine，namespace 释放返回对象，install 沿原 handles/audio/module/owner destroy 链退出。SDK compile-only 顶层尚未找到已证成功值伴新异常；对应自有注入只验证 caller 合同，不写成 SDK 实证。作者 module evaluation、rejected Promise 及 getter/setter 的原异常语义保留。成功构造与普通帧不扫描 heap。共享 heap OOM 仍立即拒绝该候选域，原 active Scene 的生命周期不由此更改；32 MiB 仍失败时先重新测失败 owner、分配和未执行接口，不连续提高上限。

相邻 layer/particle instance factory 的 native payload 分配失败在 producer 抛出现 OutOfMemory，closure/getter/setter/atom 逐步检查后转交。现 layer access payload 只在同步 closure 构造时持有临时 finalizer 标记；早期失败由 caller 释放一次，晚期失败由现 finalizer 释放一次，成功后清除临时指针，后续生命周期仍由原 closure 独占。当前 vendored API 返回 function 同时留下新 native 异常也按失败释放；调用前已有异常与新分配失败分离，不被成功构造覆盖，不新增异常系统或持久 owner。

验收分两层：自有真实 VM 证明 935 及更高 owner 数构造/更新，有限 heap 超限、低预算、作者 null/accessor、peer/stale/detached handle 与清理反例继续成立；Swift 最近门证明默认 native 16 MiB 和 custom/native override 相互独立。随后固定源码/App/未改作者字节的隔离原包验证开场退出、后续动画/显隐与交互，并用未参与修复的样本检查邻接行为。只有真实画面链成立才记本片完成；Debug build、owner 数、ready 或非黑不能替代播放验收。

## 初始图层配置后继（2026-10-12，实施中）

N06 真实脚本通过 `getInitialLayerConfig` 读取作者配置，再提取 image/size 或 text 字段交给既有 createLayer；本片优先恢复可由现役普通图片资源消费的原层脚本，不承诺完整 clone、Puppet 或 composition。官方 2.8.0.42 自有黑盒已证 String 名称、Number 顺序、ILayer 三入口返回原作者字段的独立对象，保留 script/value wrapper、string size 和未知作者字段，去除顶层 id；运行中的属性写入不改变初始配置；找不到名称或序号返回 null。同一 R2 实验已证嵌套数组/对象的副本隔离，动态 createLayer 的普通 Object 配置亦保留创建时深副本。不得推测 wrapper 展开。

数据沿现 `SceneObject.authoredValue → SceneRenderDescriptor.Layer → QuickJS layer catalog`；保留原始配置，不从当前帧逆构造。配置参与 load/configuration 阶段 catalog identity，初始化期间解析一次并保存 QuickJS 自有的对象序列化快照；getter 用 VM 原生对象反序列化返回独立对象，不重新解析作者 JSON、编译脚本或建立场景图。只复制调用者请求的配置，不做普通帧整图序列化。快照归现 domain/layer record，跟随其销毁释放，不新增状态库、renderer 或 lifecycle owner。缺少配置证据的合成 descriptor 不伪造作者配置。

本片仅开放 prepared 作者层配置读取；动态层 getter 明确报告 unavailable，旧 createLayer 不增加配置遍历或新的准入要求。官方已证动态 Object 的创建时深副本，但暂不实施：直接对任意动态参数调用 VM 序列化会读取数组 index getter（含稀疏数组原型上的 getter），为旧 create 引入额外脚本副作用；当前目标脚本不读取动态层初始配置，为此新增递归对象图准入收益不足。后继须先证明无新增 getter/Proxy 副作用及事务兼容，再复用当前接口开放，不能用当前值回填。

接口复用现层名称/顺序解析及带代次的 handle 校验。现值、事务和资源仍由原 owner 负责；读取初始配置不代表 createLayer 已能消费其中所有字段。对不支持的资源保持局部拒绝，不能把 Puppet 扁平化或对缺少 provider 返回假成功。验收覆盖三入口、嵌套副本隔离、实时值不污染初始值、缺层/旧句柄、配置 identity 变化、现 create/destroy/rollback；真实 App 则核对原 34 个失败 target 的实际分布、普通图片模板复用与实际脚本角度输出，不以方法存在或截图非黑计完成。

<a id="prepared-text-clone"></a>

## 已准备文字 wrapper 动态实例（2026-10-15，有界实施）

**目标与范围。** `createLayer({text: …})`应区分String、静态value、user绑定和script wrapper；有状态脚本的两个clone必须各自持有模块状态、init/update、输入修订和退休状态，不能把wrapper字符串化、只取fallback或共享原namespace。现真实缺口包含一个已准备时钟脚本与两个纯user wrapper；后者应走原property typed链，不为其创建空VM owner。初片仅复用本launch成功准备的作者文字模板，不接任意新源码、Puppet/composition、动态配置getter或新的资源发现。官方自有中性实验已证独立init/update及create返回后立即`.text`可见init结果；user/throw/destroy沿项目既有合同验收，不称官方parity。

**唯一准备与身份。** 原domain layer catalog持有作者wrapper及其String/property准备资格；script模板在原compile-only结果执行前保存可信进程内字节载体，原source owner仍消费同一次编译，clone经原VM读入为fresh模块，普通cadence不解析或编译源码。模板不是磁盘bytecode cache，跟launch/domain预算和退出释放；源层退休不销毁已被合法clone使用的模板。载体仅在当前可信domain内读入，不从不可信包或磁盘bytecode取得执行权。来源需完整value/user/script/scriptproperties及宿主准备语义匹配，不用名字、当前文字或源码hash猜模板，不给getInitial返回值加可观察token。不确定、修改后未准备或歧义配置在journal分配前局部拒绝。候选为原catalog内有界own-data匹配：先拒Proxy/accessor/不支持class，再用自有数据字段比较；须先证不触发getter、原型稀疏项或额外序列化副作用，不能直接递归JSON任意调用参数。

**同步激活。** 原create journal分配provisional层后，由原domain实例化prepared子owner，绑定新layer target及原codec解析的当前输入，在返回handle前执行现String init并写同一临时record。父callback续行须恢复原owner、有效callback epoch、engine/thisLayer/thisObject、frame输入、value-only权限、异常及job归属；身份分配保持单调，子工作计入父剩余interrupt/native/heap预算，不因nested入口重置。只开放这一受限激活边界，不能全局删除callback guards。现动态写入检查把creator等同active owner，需保留record creator及其连带退休权，另让该层已授权String property owner访问自己的target；不将creator改成子owner，也不放开跨owner句柄。

**事务与typed输出。** 子实例是creator bundle的provisional贡献。init期间的typed写入和命令必须进入同一可验证贡献，不能只返回文字而漏副作用；子init失败、父throw、预算失败或后置Swift/fixed-point拒绝时，原子拒绝依赖此次创建的creator bundle并撤回子owner、timer、roots、命令及文字；父catch不能把不完整创建重新接纳，清理期间的destroy副作用也不发布，健康peer继续。已接纳clone后续update失败沿原String previous-current/禁用与重试边界处理，不重新初始化source或peer。这里只保证项目原typed/host事务，不承诺回滚任意JS共享堆。接纳后原StringProgram持有script clone及其ledger；纯user/value复用原property codec与binding producer；script与outer user共存时，沿原objectText合同将user作为低优先级typed输入，String owner仍是唯一最终producer，不能并排登记两个输出。原DynamicLayerRuntime plan发布新增target定义/生产者及实际删除事件差量，frame schema按该revision刷新；原typed snapshot→TextTextureStore→publication/compositor继续唯一消费。作者fallback、init输出与当前值分开；无首帧整景重建或逐帧catalog扫描。

**ABI与持有转移。** 模板只登记原String/property准备成功的catalog层及完整wrapper；String构造从同一次compile-only保存可信字节。C原create/journal暂持fresh子VM handle及其creator依赖，采用原frame的user输入和模板当前已解析script-properties；接纳前的typed贡献归creator bundle，共同commit/discard。原StringProgram在已提交队列中接管handle与prepared元数据，C退出持有，随后仅存property-owner身份授权；不能在普通帧扫描全catalog找新owner。StringProgram在各族VM执行前刷新模板输入，按属性revision复用原codec结果。纯user/value只携带prepared binding身份和作者seed，原property producer输出投影到新target，不为它建立脚本owner。DynamicLayerRuntime负责接纳/删除binding与定义，StringProgram负责脚本状态；二者经原plan/schema revision进入typed snapshot，不新增服务、VM或输出链。

**退出与回调边界。** 单clone销毁、creator退休连带删除和launch退出，沿原retire/destroy/cleanup retry恰好撤一次贡献，陈旧异步raster不得复活；仅传destroyedAuthoredLayerIDs不足。初片覆盖init/update/applyUserProperties/destroy及现typed输入，不静默漏media/cursor/audio：按实际exports/注册资格明确拒绝尚未接线的模板，或在原coordinator按接纳revision更新，禁止第二dispatcher。现job drain/discard作用于整个runtime；在父已有pending job时直接嵌套会误消费/删除父队列。这是实施前资格门，不能仅save/restore active_owner掩盖。首片只核同步范围：所有可能执行JS的字段读取结束后，在journal/birth前要求parent无job residue（含pending queue、active rejection和overflow）及待决VM异常；不满足仅局部拒绝本次wrapper create，不能清父队列，旧String入口不加此限制。nested activation depth限1，子init再创建script wrapper不开放；子模块/init如排job，在执行这些job前拒绝并仅清当前子队列，避免每次drain重置64-job计数绕过父callback预算。未来若开放子job，必须共享最外callback剩余计数及原owner/frame命令/变更总预算。恢复后父新增jobs仍由原流程处理。父job/rejection、嵌套create及异常完整性须保持这些资格门，不扩大vendored job机制作为默认前置。

**实施与后继验收。** 本片限定范围已沿[冻结后验](../../history/prepared-text-clones-2026-10-15.md)完成真实C/Swift、隔离作者shadow选项、独立文字样本及退出验证。后继仍须保变量/资源改名与等价wrapper、双clone独立init/update/user、父throw/晚拒绝、坏返回与健康peer、单clone/creator退休/旧generation及原particle cadence作用域。值变化须到实际文字/画面，门通过、模块数和非黑不替代验收。任意新源码、未接事件、特殊clone与完整样本parity继续开放，不把本窄片等同N06完成。

动态String binding在原retire边界清理quiescent负ID owner及其定义、输入索引和派生缓存，避免反复创建/销毁积累至launch结束。原timer frame snapshot须强持捕获时的准确owner，restore/discard不再与可变bindings按位置zip；已退休owner不恢复，snapshot释放后owner自然退出。作者source模板保留到domain退出。原frame ledger与JSON cache按同一删除target清理，不新建退休队列；schema按已提交删除事件移除stateful target。验收包含持有旧snapshot时删除中间clone、健康peer恢复/丢弃及多轮创建退休后owner数量回落。

队列take只按已共同接纳的DynamicLayerRuntime plan中`layerID→template identity`移交：同帧新生又随creator删除、无live成员或身份不符的子handle直接释放，不注册String binding/stateful target。接管不等于新的拓扑接纳权。init中的topology operation沿原creator journal，接纳后的自身sort沿已有property owner授权重放；creator身份和删除权不转移。动态TEXT dirty ABI只区分显式setter与完整record镜像，其余动态字段不因此开放。`user:null`与省略user保持同一无绑定语义，完整wrapper比较仍保真。

动态文字沿原layer ABI限制为最多4096 UTF-8字节且无嵌入NUL，统一在typed mutation合同校验。同步init、已接管clone的输入/返回值及纯user投影均在最早target边界局部拒绝越界；普通作者String原65536返回合同不缩小。非法user输入保留唯一evaluation transaction的上一安全current，首次无值用作者seed；镜像继续做完整性校验，不吞错或跳过坏target来伪造成功。需验证4096/4097及NUL、坏clone后健康peer仍更新，不能因一个视觉值让共享VM停止。该限制是现动态layer ABI边界，不是官方文字上限。

产品原particle frame是整个cadence的共享native预算/事务作用域，开启它不能拒绝普通文字创建。同步子模块构造、init与失败销毁期间，在上述词法激活scope暂存并抑制原emission/boundary hooks，所有出口恢复原hooks/opaque；不重置active、work、limit或reserved。子init的particle播放/emit命令在原native入口、任何Swift preview/reserve或可捕获错误之前设sticky失败并拒绝creator，即使module阶段尚无provisional指针也按原nested激活身份拒绝；查询如被允许仍扣原共享work。父先前prefix/query候选不能被child end/discard边界清除。验收以原particle scope包围create并核前后父输入/预算、正常与失败出口、健康suffix；禁止为绕过此门关闭产品particle事务或新增第二模拟owner。

<a id="prepared-puppet-clone"></a>

## 已准备特殊实例（2026-10-15，默认Puppet几何有界已接）

**选题与资格。** 首片为已准备Puppet模型的默认几何实例，其次为空composition实例；文字显式style先需已证请求，不沿外观猜font或继承padding。实际原包31次create有25次普通命中、6次特殊模型缺失；六请求的own及完整已核原型链均没有animations/puppetAnimationLayers/effects，五Puppet源的mesh已成功准备。source声明不代表请求继承：不复制源动画、脚本或effects，不为本片新建子VM owner。[IScene](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IScene.html)公开配置创建，[IAnimationLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IAnimationLayer.html)公开播放控制；两页未裁决clone出生相位、配置省略或source销毁后的关系。只为实际影响首片的unknown做自有黑盒，不取私有算法。本片准入限静态atlas与原普通单pass builtin image材质、已准备model/mesh和无动画/effect请求；其他配置继续局部拒绝，动画/graph后继仍未裁决。

**职责与旧链退出。** 在原prepared-device/launch资源内形成可信Puppet模板：已验证mesh/rig/reference/attachments、按实际配置准备的pose/evaluator、静态atlas logical extent及创建资格。PreparedAsset不固化source selected clips；原作者配置与默认创建分别准备pose，无动画请求沿原empty-selection reference skinning或exact bind几何，保shear/小行列式及局部fallback。静态作者层和clone共用同一准备结果，退出重复MDL/轨道解析；不另建独立资源registry或clock。mesh/indices/UV/不可变轨道与采样资源可共享，PlaybackState、clip位置/显隐/blend、bone overrides、physics/scratch、vertex ring、clipping临时目标及publication/FIFO每实例独立。GeometryProduct绑定新实例state，不能复制捕获原state的闭包；atlas只作mesh采样，不能以quad或bind-pose冒充请求的动画。

**数据流与提交。** 原catalog模板资格→create journal携新layer identity/template identity与typed配置→原DynamicLayerRuntime候选/fixed-point→共同commit→原AnimationPlaybackRuntime及surface安装→同一typed LayerFrame/GeometryProduct/唯一compositor。出生/退休是已有plan的差量，普通帧不解析或扫描catalog。首次动画相位按取得的行为合同处理，不把原sceneTime初始化擅改成birth-zero。现负ID动画bridge和bone owner权限不能全局移除；实际需要的clone脚本/控制应沿原owner授权、回调与退休接通，未消费字段在出生前拒绝，不静默丢弃。本片遇到动画/effect字段沿原异常/事务规则局部拒绝，不忽略非空配置。未来请求effects时须给新identity实例化原graph/target/history，不能借模板成功伪装可用。

**失败与退出。** 模板缺失/配置漂移在journal分配前局部拒绝；父throw、预算或Swift晚拒绝、同帧生灭均不留下clip/surface登记。只在原共同接纳后安装实例；surface资源失败局部不可用，不回滚已执行JS或伪造geometry。单clone与creator连带退休撤原动画、surface及授权，in-flight资源按原completion释放；source退休不得提前销毁仍被合法实例使用的模板。空composition如后继实施，只复用原utility source/ordering/graph/pool出口，不复制source最终纹理，也不预设子成员复制。

**最近验收与停止。** 实施与未验边界见[默认实例记录](../../history/prepared-puppet-default-instances-2026-10-15.md)。本片用自有双实例验证真实mesh轮廓/默认reference或bind几何、独立state/变换、throw/晚拒绝无残留及退休一个后peer继续，另验真实候选与未参与修法样本；动画字段不复制source，用失败反例锁定。未来动画实例另须非静态mesh位移与独立播放事实。改名/等价配置和缺template、错误代次、用途冲突保邻反例。若真实请求依赖首片外脚本/graph或没有可消费的prepared结果，收口资格并重新排队，不以无可见收益的基础设施扩张计交付。性能只在重复准备确有可比收益时单独验收。

<a id="prepared-empty-composition"></a>

### 空 composition 创建资格（2026-10-15，原型撤回）

**当前裁决。** [隔离原型](../../history/prepared-empty-composition-2026-10-15.md)证明省略特殊配置/透视时可沿原catalog、create journal、DynamicLayerRuntime与utility plan建立独立空组，并控制真实可见peer；但真实288请求携constructor透视override，且target286的authored setter写true。前者早拒绝返回null，允许它则后者仍使原共同bundle拒绝。省略窄片未改善真实请求，产品与测试原型已撤回，不新增支持，不以自有fixture替代收益。

**保留的职责设计。** 如后继取得真实可消费profile，泛化原资源层template/kind与同一domain catalog；image/Puppet保原device资源，composition只携可信utility资格，不伪Loaded图片、不复制source成员/effects/脚本或最终纹理。原身份、事务/fixed-point、typed topology、排序与退休继续唯一；无effect空组只规范顺序，不新增capture/graph/target。普通帧不解析或扫描资源。显式动画/effects、背景/config、成员/dependency及透视配置必须有typed消费者后才开放，getter/Proxy异常保原owner撤回。

**重启门。** 公开IScene只有通用创建/排序/延迟销毁合同；composition透视、动态背景默认及成员复制仍unknown。当前utility固定screen-space，采集UV仅三角affine，不能只删除perspective guard或强置false冒充支持true。重启先取得自有正控制与透视false/true、非零深度/倾角、第四角/采集回绘/cursor的可区分合同，保存新设计并同步登记。保省略C2→Swift nil和普通image/text的继承语义；明确未消费override在出生前拒绝、ABI/后续setter在共同接纳前复核。无可见差异或无合格真实请求就停止扩域，按现役队列重选。

## 图层 perspective typed setter 后继（2026-10-12）

真实作者在图层 init 设置 `thisLayer.perspective`，随后只更新 angles/origin/scale；原桥接没有此 accessor，赋值成为无渲染消费者的 JS 自有属性。公开 [SceneScript 类型声明](https://docs.wallpaperengine.io/reference/lib.sceneScript.d.ts) 的 IEffectLayer（image/text 的共同表面）及 model 图层声明可读写 Boolean perspective，含义为透视而非平面绘制；公开 HTML ILayer 简表未完整列出派生属性。此次先闭合已准备图层及现动态 image/text handle 的 setter/getter，不扩 createLayer Object 配置、size、资源 profile 或文字克隆。

复用 layer catalog/mutation journal、Swift owner bundle 固定点、DynamicLayerRuntime 和 typed snapshot，增加现 layer Bool 字段；C 只保存已提交镜像、同 callback overlay 和既有 rollback baseline。当前相机帧持有同一不可变 typed snapshot 的值引用，唯一 `resolvesPerspective(for:)` 在现静态 override/default 之前消费该字段，Geometry、Program/MVP、lighting/fallback、cursor 和 Puppet attachment 共用它，不逐帧复制整图、解析作者配置或失效 shader/graph。动态层的完整值记录仅在 setter 后携带显式 override，未写值继续继承既有相机默认，不将省略改成 false；现 dynamic descriptor projection 继续消费该记录，不新增拓扑 owner。

准入范围按公开表面和现实际 camera/geometry 消费者确定；改变或首次显式设置 perspective 的 mutation 在 particle、sound、camera、utility 等无消费者层按原 owner bundle 拒绝。所有 catalog 层可读已有相机策略；已显式值的同值写沿现 setter 规则不生成 mutation，这类 getter/no-op 不计绘制支持。继承记录即使写当前默认同值 Bool 也生成显式 override，避免后续 camera 切换吞掉作者意图。value-only Boolean owner保留原权限边界；跨 owner/旧代/已删除 handle、throw、C 成功而 Swift 拒绝均走现拒绝/撤回。官方 2.8.0.42 自有同输入正交 image/text fixture 已证省略值为 false，Bool 同 callback/跨 lookup 即时读回，所测 1/0/string-false 非 Bool 写入忽略且不抛错，动态 false→true→false 的声明 ROI 与各静态参照一致。官方该 fixture 的 setter 后 throw 留下 true；本项目继续保留既有整个 owner bundle 原子撤回，这是项目事务约束，不能宣称这项官方 parity。native 默认、Puppet 黑盒和特殊组合仍未验证。CPU 门覆盖 VM→ABI→typed admission/commit/discard、同帧读回、健康 peer、镜像 rollback、动态层值及相机矩阵/命中一致性；Debug build 与隔离 App 运行另验真实原包和未见 fixture。该范围不证明原包全部特效、Puppet/composition克隆、完整官方parity或能耗验收。

## 动态图片创建几何配置后继（2026-10-12，实施中）

目标是让已准备普通图片的 createLayer Object 几何配置进入原 typed mutation、候选事务、descriptor 与真实绘制。固定官方 2.8.0.42 自有输入已证 String `"200 100"` 与 `new Vec2(200,100)` 的 size 同 callback 和第30帧均读回200×100，真实颜色边界同尺寸。最终普通图片矩阵（自有200×100纹理，模型仅 material/autosize 字段）已证：model.autosize=true 覆盖显式 String/Vec2，采用资源自然尺寸；false 或省略 autosize 消费显式尺寸，省略 size 的 getter/真实图均为1×1。追加公共黑盒已分别验证 Path String、仅 image 的 Object 和 registerAsset Handle 三个 overload 的省略默认均服从同一模型策略，即时与第30帧读数及真实边界一致；模型 width/height 声明仍未证，不按作者层尺寸推导默认。创建配置 angles 的 String/Vec3 均按 scene JSON radians 输入，公开 getter 为 degrees，仅在既有 VM 边界转换。constructor perspective=true 与同配置静态 true 已逐像素复核一致；此前多图目视误判已撤回，不形成产品债务。字符串 origin/scale 复用现 VM 通用向量读取器，不按脚本形状或资源名选择行为。

size 是只读创建几何：C 原 layer record/journal 保存已验证的创建尺寸，原 mutation ABI 携带其可用性和两个分量，Swift 原 LayerMutation 值保留该字段。DynamicLayerRuntime 仍独占身份、资源模板验证和候选提交；LayerTopologyProjection 采用创建尺寸，DynamicImageTextureProvider 用该层逻辑尺寸发布同一个 prepared texture/candidate，原 matrix、cursor 与 compositor 共用此出版物。不能只改 descriptor 而让 provider 再覆盖为纹理尺寸，也不能为尺寸重复加载、重采样或新增输出 owner。perspective 沿已存在的可继承 Bool 字段，省略保留当前继承状态，显式 false/true 进入原相机策略。普通字符串文字仍沿已有消费者；text value/user/script wrapper、Puppet、composition 和动态初始配置不随此片开放。

模型 autosize 与已准备自然尺寸在原设备资源 join 后一次投影进现 template 与 domain catalog，首次 init 前完成，绑定同 launch 身份、只读且随 domain 清理；不从当前作者层反构造、不在普通帧解析资产或维护第二份资源状态。自然尺寸由现 loader 准备结果提供：TEX 的 image extent，PNG/JPEG 的原始 CGImage extent，在上传尺寸归一化之前保存；即使 decoded cache 的 lease 被拒绝，准备资源仍保留该小型元数据，在 decoded cache 退出前捕获进原 prepared resource。资源缺失或不支持的创建在原 journal/handle 分配前返回 null，其他健康 create/setter 继续进入原事务；真实作者 getter/Proxy 抛错沿 JS_EXCEPTION 传播并撤回原 owner，不吞为局部 null。同 callback、提交后读回及 throw/Swift 拒绝/销毁仍服从原 C 与 Swift 共同接纳和撤回。静态图片 autosize 原缺口由下述同 owner 准备几何后继接入，不以动态创建替代静态层。

在模型已由现资源 owner 成功准备、canonical source 与普通图片 profile 接纳条件均成立时，限定尺寸表面包含 String、nominal Vec2、正有限 Number 标量及不含 script/user 的静态 value wrapper；这项字段消费不扩大 Program 的资源发现范围。现预准备分析的公共 owner 接线由下述 Program 资源需求后继负责；有限 literal 与已准备 authored image alias 之外的 helper/变量路径、registered handle 资源需求及嵌套配置发现仍未闭合；缺 prepared 资源返回 null，不能把字段解析成功当资源准备成功。普通 x/y Object 与 Array 沿官方默认尺寸邻域，不冒充 Vec2。constructor perspective 非 Bool 沿公开创建事实回落 false，不能套 setter 的强类型策略。官方合法 zero/negative 几何与物理资源正尺寸是不同合同；现 publication/capture/cursor 尚无完整有符号或退化几何消费者，本片不取 abs 伪造镜像，autoSize=false 时该 create 局部返回 null，明确为 unsupported 后继，不称非法参数。含 script/user 的尺寸包装同样不能仅消费 value 宣称完整支持。

创建前资源查找必须先采用现准备 Program 的作者资源身份映射。每个 owner 的 `dynamicImagePathsByAuthoredIdentity` 在构造阶段只读投影到其原 C owner，create 将已解析的作者路径转为 canonical model identity，再查询同 domain 的自然尺寸/autosize catalog；完整 upsert 继续携带该 canonical identity。既有 Swift Boolean admission 仍负责权限与共同提交，其解析接受相同 canonical 值，不建立竞争 namespace 规则。不能将 alias 放进全局表：不同 owner 可以用同一作者 literal 指向不同已准备模型。映射随原 owner 销毁；未知路径保持局部 null，getter 异常及 owner 失败仍沿原撤回。此接点以两 owner 同 literal/不同 canonical、直接 canonical 邻居、资源和变量改名、完整 upsert 与失败撤回作反例，避免提前资源检查收窄既有直接路径创建。

路径身份仍由现 Swift `String.lowercased()` 与 String 的 Unicode 规范等价比较定义；native 接口仅将该身份编码为 lowercase 后的 canonical-composed UTF-8 比较键，C 的 ASCII `strcasecmp` 或未规范编码的 `strcmp` 不能替代该身份规则。原 domain 在构造时安装无捕获状态的 native 规范化函数，配置 alias/catalog 和 create 查询使用同一函数，创建记录保留原 canonical model 拼写。接口必须在任何 owner/catalog 之前一次安装；未安装时不能配置新身份表，也不能静默切换到 C 的另一套 casefold。规范键按实际输出字节数分配，内部键不套原作者路径字节上限，公开路径仍沿原安全验证。函数只做现身份转换与独立字符串分配，不查资源、不调度、不持 owner/Swift 对象；C 消费后释放结果，domain 清理指针。普通 full upsert 不重新规范或查 catalog。不能调用作者可篡改的 String.prototype 方法，也不另建 Unicode/namespace resolver；真实 VM 覆盖非 ASCII 大小写资源改名、Unicode 规范等价拼写及污染 String.prototype 的邻居。

验收使用真实 VM→ABI→Swift mutation 和实际 descriptor/provider 消费；autoSize=false 正例尺寸刻意不同于纹理自然尺寸，并覆盖 String、Vec2、scalar、静态 value、变量和资源改名、等价表达式。相邻 Array/plain Object/script-user wrapper/非有限/越界、同资源不同作者尺寸、合法省略与显式值、健康 peer 和失败撤回分别断言。隔离 App 用同输入几何 fixture 看真实尺寸与倾斜；288 原包默认只作回归，开启已有 shadow 参数的隔离派生包仅作触发 fixture，不能把默认关闭画面或自然尺寸相同记作新增尺寸收益；heldout 由独立运行侧保留、只验真实结果。不计完整样本、parity 或性能验收。

## Program 公共图片资源需求准备后继（2026-10-12）

本片闭合相同直接图片请求只因 owner 返回类型不同而缺少 prepared 资源的断链。现 Boolean visibility 来源分析独占 DeviceResourcesTask 的动态 model 集合；Scalar、Vector、String 与 standalone Cursor 已有合法 VM mutation 消费者，却没有同等资源准备和作者 canonical 映射。文字 script/user wrapper 的独立动态绑定另有生命周期职责；本片不取 value 冒充完整支持。资源发现是准备期依赖，不改变任何 owner 的副作用权限。

选用原 SceneScriptValueOwner 共同构造入口，复用唯一 ReferenceAnalysis 与 domain 的现 layer catalog model identity；仅成功构造、通过原各族 projection/冲突与 route 过滤的 owner 将 canonical model 需求并入该 domain。每个 owner 的原 alias 配置同时保留其自己的作者路径映射，不设置全局 alias。Boolean effect/Puppet 等既有 value-only/禁止层命令边界不因发现资源而变为 effectful。失败候选 domain 整体退出，最终 construction report 与 media-route 固定点选出的 domain 才提供资源需求，不扫描所有 bindings 或预加载全目录。模块顶层 create 仍早于 owner/catalog 安装，不宣称支持。

原 DeviceResourcesTask 保留 metadata 阶段、静态 GPU 准备与 CPU Program 编译重叠；原 condition 接收最终 Program 需求一次，原 BaseImageResources 动态准备循环继续使用同 loader/device/generation。该等待只在 launch worker，不进入普通帧；空集合也明确完成。失败/取消唤醒等待者并沿原 task join 清理，不发布半准备 context；不另建资源任务、loader、namespace 或 registry。现 QuickJS candidate 的四族 plannedOwnerSources 目录共用原各族 projection/unique/exclusion，准备期依赖上界通过同 ReferenceAnalysis 提供给原 material color lowering；带脚本颜色的同模型请求得到原唯一颜色 owner，不重编整个 owner。原 Vector visibility 直接引用退出其作为唯一材质依赖、GPU 需求和 owner alias 的角色。上界只表示可准备候选，最终成功 domain 决定实际 GPU 需求。

ReferenceAnalysis 保留原有限 literal grammar（直接 String、平面 Object image 字段与现 workshop identity），由现 lexer 的 reference-token mode 排除注释/字符串伪请求，原请求 regex 退出；transition 子集 grammar 不变；该模式只服务所列 literal lane，不声明完整 JavaScript 词法或复杂 regexp/template 依赖分析。同 owner 的 helper/未知引用不再清空独立合法 literal。无法静态发现的参数、变量路径、registered handle、嵌套配置与模板表达式仍未闭合，缺 prepared 资源返回原局部 null。不得通过新 regex 分支或源码执行补这些语法。每个请求独立做原根内路径与可用 model 解析，未知请求不扩失败半径。

验收从原 Program→真实 VM→canonical mutation→原 prepared 动态资源消费者贯通四族；覆盖变量/资源改名与等价表达式、同 owner 合法 literal 加未知 helper、注释/字符串/text-only 假引用、不接纳/冲突 owner、两 owner 相同 raw literal 不同 canonical、原 Boolean 能力隔离。原 task 的 CPU 受控后端门覆盖 metadata 后等待与最终需求交接、空需求、取消和早失败；该门不运行 Metal，也不证明实际 load 次数。唯一动态 GPU 准备循环由源码职责审查及独立实际运行验证。独立运行侧用四族同材质图片和冻结变体检验真实四格像素，另保留未参与修改的真实输入。本片不证明完整 JS 依赖发现、动态文字 wrapper、官方全域兼容或性能验收。

## 静态普通图片的准备几何后继（2026-10-12）

模型策略仍由已解析 asset catalog 提供。原静态 descriptor 只采用作者 size/model width-height，忽略 autosize；原 GPU 上传尺寸不能替代资源自然尺寸。对现资源解析器已解析到普通静态图片的层，model.autosize=true 使用原 loader 的源图像自然尺寸；false 或省略保留显式作者 size，没有作者 size 且模型 width/height 两字段均缺席时采用已证 1×1。原 asset 解析 owner 保留字段存在性；在 false/省略的缺省1×1分支，单维或非法声明不冒充两字段缺席，保留其存量 fallback。true 仍使用有效 prepared 自然尺寸；官方宽高补测只覆盖合法正值 pair，未测单维/非法声明，不能把这两类产品行为称为官方 parity。原 initialConfiguration object 的 size 键必须真正缺席才能采用缺省；null/Array/不支持的 value 包装、显式 zero/negative 不冒充省略，仍保其存量解析值。追加官方自有静态矩阵已证模型 width=80、height=40 时：autosize=true 对显式120×60与省略均采用自然200×100；false/省略对显式保留120×60，省略继承声明80×40。故 true 的自然尺寸优先于模型声明，false/省略仍保持原模型声明 fallback；动态创建带 width/height 未测，不外推。named output、文字、Puppet、solid、video（复用现 TEX isVideoMp4，不以 isAnimated 代替）、sprite/animation 和其它专用资源保持原责任与尺寸域；不借动态 alias 资格收窄既有静态普通路径。

原 TextureLoader 的 preparation-only 自然尺寸入口复用 TEX 容器 metadata；PNG/JPEG 在同 ImageIO owner 读取 pixel-width/height 属性，不创建 CGImage、不上传纹理。读取前后校验同 SourceKey，读到的小型 metadata 写入原 PreparedBaseImageResources.Entry，在 decoded eviction 前保留。Entry 的 metadata 可先准备，outcome 缺席不计 GPU ready；deferred 请求继续原 pending/loading/ready/failed 生命周期，隐藏图片不会仅为几何而提前上传。原资源 task 在同一队列/condition 上先发布几何结果，再继续 GPU 准备；launch 等待 metadata 后继续 Program 编译与 GPU 准备重叠，最终仍由原资源 join 接纳。取消/失败沿原 task 退出，不能发布半准备 context，也不建立第二资源 registry 或几何生命周期。

同一 prepared size 结果一次覆盖 runtime/authored descriptor 的 sizeWH，保持 initialConfiguration 作者快照、size 原字段及其它属性不变。RuntimeInput 从准备后的 descriptor 构造现计划；所有 Script catalog、只读 getter、Cursor admission/local pixel、matrix、capture/effect/direct draw 消费相同几何值。普通帧不查文件、重读 header、重新解析模型、重建 Program 或维护额外图层状态。资源失败仍由原最小层资源消费者局部降级，metadata 成功不等于纹理或绘制成功。

验收沿原准备 owner、原真实 descriptor builder 和 VM catalog，覆盖自然尺寸不同于上传尺寸、同资源不同作者尺寸、显式/省略、资源与变量改名、等价表达式以及相邻专用资源/模型声明/显式零尺寸不误命中。deferred 必须证明 metadata 可用于几何而加载次数仍为零、outcome 缺席且状态 pending，随后原 worker ready/失败/取消保持原生命周期。真实 App 使用既有合法自有普通模型矩阵与独立 heldout，仅声明实测范围，不从大部分作者 size 恰等于自然尺寸推断新增画面收益或性能结论。

## 图层排序与共同候选同步

排序与其他属性更新互不覆盖，并保持原 domain 内真实调用顺序。真实 VM 反例已确认：同 callback 的 authored sort 与 alpha 合成一个属性 DTO 后，Swift 以 fields 为空识别 sort 而漏排序；先创建 X 排 C 前，再创建 Y 排 A 前时，早先 callback 复制的绝对 index 已陈旧；既有 dynamic X 只改 alpha 的完整 upsert 也不应贡献排序。不能只补 coalescing 标志或在 Swift 另建一次排序命令重放：init/events/update、Cursor 的多次合并和 owner 分组会改变 DTO 顺序，后置 owner 拒绝还会改变健康操作的上下文。

正常移动完成后返回 Boolean true，依据 [IScene 公开 Boolean 声明](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IScene.html)与已批准的固定官方普通新层移动黑盒结果，使作者可按成功返回继续写属性或排序。只改完成移动的成功出口；same-index/no-op 的返回、非法/越界和其它未测邻域保持原处理，不能扩成完整返回/失败语义 parity。真实 VM 须用严格 ===true 控制后续合法属性写入和第二次排序，并保留 TypeError 与 throw/撤回反例。

沿现 C topology journal 保持唯一排序执行权威，将其已有 baseline+有序操作重放提取为同一个可供 rebuild 与只读候选投影使用的实现。候选投影在 callback 全部完成后、共同提交之前，根据已接纳的 VM owner identity 过滤 pending 操作，保留 committed 操作与原全 domain 调用顺序；不修改 record、journal 或 VM heap，也不重跑作者 callback。没有 topology journal 时返回缺席，不在普通值帧构造完整顺序、解析或散列。安全错误沿原 owner/fixed-point 接纳失败，不能静默采用陈旧 DTO 的 index；固定点验证须包括只有 topology 参与身份而属性 mutation 已被合法裁剪的 effect 包。

原 C owner 仅导出 pending topology 的 owner identity，原 evaluation/owner-effect 包独立保留该参与身份；它不依赖会被 Boolean 返回合法裁剪的属性 DTO，也不受 coalescing/Cursor merging 影响，不是新的排序命令或 owner registry。原 domain 提供有界 typed raw order 查询，launch frame schema 将该纯投影交给现 DynamicLayerRuntime。原 runtime 仍独占属性/资源验证和 owner 候选：先验证 owner bundles，按接纳集合取得 C raw order，在原 finalizeTopology 内消费；普通动态完整 upsert 不再隐式排序。raw order 必须包含共同提交前的 authored tombstone 槽，随后沿原统一退休阶段移除 authored 层与其动态副本；不能提前删除再重放 index。外部命令拒绝和存储依赖 fixed-point 每次使用最终候选接纳集合重新投影，使被拒 owner 不影响健康 owner 排序。投影绑定同 launch/domain 生命周期，不跨 reload，也不持新对象树、namespace 或资源状态。

验收覆盖真实 VM→ABI→Swift candidate：sort 前/后写 alpha、两个 callback 创建顺序及不陈旧的相邻顺序、property-only dynamic upsert、变量/资源改名和等价调用、同 owner 多 callback/peer 交错、throw 与后置 typed/external rejection、dynamic destroy 和 authored 延迟退休。隔离普通图片 fixture 用有重叠的不同颜色层检验实际遮挡顺序，并由独立运行侧保留未参与修复的真实输入。测试 stub 仅供应外部 descriptor 元数据，不能替代排序、journal、mutation 验证或候选事务；构建与 VM 通过不计最终图像或全域兼容。

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


## 命名属性 Timeline 入口后继（2026-10-10，已实施，有界验收）

U22实机副本点击命中后，`getLayer(...).getAnimation(name)` 缺方法，整个cursor owner事务失败，两个已编译alpha动画没有收到play。公开[ILayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ILayer.html)规定按名返回属性Timeline；[IAnimation](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IAnimation.html)的play/pause/stop语义与当前播放owner一致。选择保留动画options.name，由已经编译的Timeline Program在准备期发布不可变名称→typed target索引，QuickJS layer accessor与current-property accessor共用原animation handle/journal；Swift仅将稳定索引还原原target，沿现owner bundle、固定点、preview/commit执行，不增播放状态、clock或每帧解析。

首片覆盖layer/text自身属性动画；effect/material对象的命名范围、rate/seek等仍未实现，不扩大方法声明。缺名或同对象同名多target没有明确裁决时拒绝该lookup；不同layer同名必须隔离。句柄绑定domain、owner identity/generation与已准备target，合法同owner跨callback/timer复用；跨owner、退休/删除目标、越界索引、回调外及throw继续原拒绝/撤回。没有name的旧Timeline与无参数当前属性入口保持原样。动态创建层尚无Timeline编译来源，不能把静态索引套到clone身份。

验收：真实VM的异层同名隔离、retained/timer play-pause-stop、无名/歧义/过期/失败反例；同一Timeline runtime消费并生成alpha值。实际U22两次点击在同窗口驱动背景/水印alpha、视频持续播放；未验证官方完整逐帧交互与长时间性能不得关闭。新入口稳定后无需迁移owner，现役唯一Timeline runtime始终保留。

- 后继反例：独立cursor-only owner在点击内创建timer后不再求值；U22实际由借用的stateful Bool owner持有，timer到期后被typed cohort无条件拒绝animation。允许已有stateful Bool权限消费同一typed Timeline命令，纯只读Bool及material function边界不放宽。独立cursor timer缺口由自有VM门验证。该owner仍由CursorProgram唯一持有，仅在已有active timer时、cursor事件前调用既有typed evaluation并并入同owner effects；沿现有cadence消费与共同commit，不新增clock/调度器。构造继续拒绝init/update需求，借用owner仍由原Program推进，避免双跑。验收覆盖无新pointer事件时timer到期、snapshot helper恢复（不等于产品GPU丢帧重放）及借用owner不重复执行。

实施及反例统一归[历史记录](../../history/named-timeline-interaction-2026-10-10.md)，当前范围由API台账维护，不以局部交互代替完整样本验收。

## 已准备普通图片的动态复用（2026-10-12）

作者通过初始配置取得 image model 路径后，createLayer 仍消费既有 dynamicImageResources、LaunchFrameSchema 模板和 DynamicImageTextureProvider；不扫描脚本表达式、不新增加载或 provider。ScenePreparedBaseImageResources 在原上传完成/失败回收之后，只将成功普通 image Entry 的 Loaded 引用投影到现动态资源表。model 默认纹理的 SourceKey 必须与该 Entry 相同，保留原 candidate、采样元数据及 texture 身份；layer slot0 override 不能污染 model 默认源，已有显式动态资源优先保留。新别名仅接受唯一 model/material/pass、既有 builtin image 身份、唯一 slot0、无常量/用户/provider 输入，combo 仅允许 VERSION=2，render state 为 translucent/disabled/disabled/nocull 且 alphawriting 未指定；未知、自定义和多pass材质不借纹理成功伪装为普通 quad。ColorModulationCompiler 负责源 shader Program 的语义 lowering，不是资源引用资格，本片不重复调用它准备 shader。

缺失、失败、延迟尚未准备的 Entry，以及 Puppet、composition、动画等特殊 provider 不借此开放。动态创建仍由原模板与拓扑事务检查，失败不返回假资源；资源随原 launch owner 保留，删除和 GPU completion 生命周期不新增权威。反例验证同 model 不同 layer override、没有原始成功 Entry、特殊来源和上传失败；正例验证共享实际引用且 load 次数不增加。初始配置的返回副本由 catalog/ABI/VM 合同负责，clone 的作者 size、perspective、text wrapper 和任意 model/material 语义不由该资源投影扩域；真实画面需另验，不把资源可用当成整样本通过。

## Sound 播放控制接入（2026-10-12）

目标是把作者对已准备 Sound 层的 play/pause/stop/isPlaying 接到唯一 SceneSoundPlaybackRegistry，首验 MP3 loop/single 与 startsilent。公开ISoundLayer描述启动、pause保留位置与stop重置计时，未明确重复play位置；本次黑盒对照补足single重复play和同回调查询，宿主暂停仍按产品生命周期合同验证。本次播放方法不扩volume脚本属性（后继见下节）；random/spatial/OGG不借此准入，失败仍只影响相应脚本owner或声音资源，不改变视觉算法。

复用现video command buffer/owner effects/frame validation/commit链，将其显式泛化为media playback command，携带videoTexture/soundLayer destination；保留一个64条预算与一次收集，不复制Sound回调/事件/遍历。旧Video名称迁移后退出，不保留alias或第二命令buffer。Video纹理handle沿原接口，Sound方法复用普通layer handle身份/过期检查；只对prepared registry有来源的层开放。查询读取当帧已发布状态，并在公开/黑盒合同要求时投影当前callback暂存命令；只读Bool仅可查询，不获得播放权限；异常、捕获后的预算超额和owner拒绝均随原事务丢弃，不在VM调用中操作AVPlayer。

帧前发布registry状态，现owner fixed-point admission分别交video/sound唯一registry无副作用验证，完整owner成功后才按命令顺序执行。play/pause/stop是可逆作者意图，宿主pause独立阻止实际播放，resume不得把脚本停止/暂停或startsilent对象改为播放；ready回调也服从同一意图。Sound registry stop仍是epoch销毁，不作为脚本stop复用。官方自有2秒MP3双层对照确认：single正在播放时再次play从头，pause后play续播；single播完后play可重建同player的item。loop重复play位置未证，保持原连续行为并登记边界。停止重置用现AVFoundation定位，不新增时钟或PCM播放器；已提交的authored layer销毁按ID从同registry撤observers/looper/queue，其他层继续；场景退役清整registry，迟到事件不能复活。首帧会在surface安装内同步执行，故registry必须在rebuildSurfaces之前建立并继承候选暂停/静音，失败由原session stop回收。

Vector applyUserProperties原已执行，但live state仅登记Scalar/String导致属性切换fallback重建；沿同一consumer map给Vector补真实callback owner/已声明key，失效owner仍由all−active拒绝，不新增属性解析器。

验收：真实VM方法→typed destination→owner提交/拒绝→AVQueuePlayer时钟与查询；startsilent、重复play、pause位置、stop归零重播、single自然结束、宿主暂停/恢复与停止后恢复、stale句柄/跨owner/throw/超额回滚，Video原方法回归。真实3761619125选曲脚本四MP3进入链，其他样本仅报告准入子集。Debug构建、独审及隔离运行，不把方法存在或player ready当成已播放；无法验证的模式继续记录首断点。


<a id="sound-volume-script"></a>

## Sound volume标量脚本接续（2026-10-16，有界实施）

**目标与边界。** 普通Sound的`script/value`或`script/scriptproperties/value`音量经现Scalar VM→最终typed `.layer(.volume)` snapshot→唯一Sound Registry/AVQueuePlayer，改变实际增益而不重建播放器或场景。公开[ISoundLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ISoundLayer.html)只定义volume为播放音量，[update](https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/update.html)定义当前属性值与返回更新值；越界/clamp及mixed user/script未获官方合同。本片沿现Sound的有限`[0,1]`项目准入，越界走owner局部失败，不擅自夹取；非空outer-user冲突、Timeline、OGG、spatial/random与volume setter不扩。

**准备与种子。** IR `authoredValue`是raw fallback唯一事实；Sound定义和原Program的`authoredVolume`是property resolver后的启动种子，不能冒充raw。无outer-user首片以object/path/wrapper/typed输入形成结构候选，原Sound Program纯compile前移到QuickJS前，按真实资源/模式准入及同layer raw seed一致性迟判，通过既有`scalarExcludedTargets`统一planned/requested/constructed/fallback。缺binding、音源、种子不符拒绝该owner；不新增descriptor soundVolume或第二种子owner，不创建player提前消费脚本。Device资源最终需求仍只来自committed domain。

**消费与迁移选择。** 选择首片按target分离：Registry新snapshot入口仅处理`volumePropertyKey == nil`且snapshot实际有标量的binding；旧property-only入口只访问`volumePropertyKey != nil`，两集合互斥，避免无关属性编辑把脚本音量重置为authored。二者最终调用原Source/baseVolume及master/mute乘积，不加override map、时钟或第二player。普通cadence完成原fixed-point admission后消费settled snapshot，排除当轮退休Sound IDs；遵循现CPU输入提交，不另加GPU成功barrier。重复相同volume/effective gain在原Source内避免无意义的AV属性写入，不新增缓存owner；连续音量的详细日志只在DEBUG诊断入口限量导出，配置只解析一次，普通帧不刷逐帧日志。失败沿既有lower-priority当前值，其他声音/画面继续。

**暂停及退出。** candidate Source仍在首帧前创建并继承宿主pause/mute；增益更新不改变作者play/pause/stop/startsilent、rate/queue/seek。暂停时旧direct volume属性必须继续即时生效；脚本仍遵守原冻结cadence，master/mute只作用于已消费baseVolume。未选择全面删除property-only入口：现setProperty仅改LiveState/Registry，paused frame复用画面而不重新求值snapshot，直接迁移会退化暂停调音量。未来准入mixed outer-user前，必须设计唯一SceneEvaluationTransaction的暂停属性publication与generation/优先级，再让旧writer退出对应target，不能以并行override缓存补偿。资源decode失败仅Sound局部，Sound epoch/owner退休和stop撤observer/queue，迟到结果不能复活。

**验收与停止。** 先真实Scalar VM反证及变量/资源/等价表达式变体，再沿同snapshot验证同一个真实AVQueuePlayer gain和下一cadence；覆盖无关属性不重置、暂停direct-volume编辑、master/mute、作者暂停/停止不复活、错误返回/缺音源/seed冲突、retire/取消及健康peer。现Sound Program/命令门复用，仅新失败重验。真实MP3 primary与独立内容分别核owner/提交值/播放器进展及画面，admitted/ready不当作可听或完整样本通过；默认只一次最终Debug、独审和相称运行。公开/neutral schema候选3800728730:23及3662790108:2989只用于验证，不进入算法或准入。4处outer-user冲突及3处OGG保持缺口，不为增加覆盖放宽本片；若无实际增益链或出现生命周期回退，先撤该volume route，不扩参数/格式矩阵。

实施边界与真实增益、原包/独立内容、超时及未验入口统一见[Sound volume后验](../../history/sound-script-control-2026-10-12.md#sound-volume-script)；本节保留职责和退出选择，不复制运行状态。
