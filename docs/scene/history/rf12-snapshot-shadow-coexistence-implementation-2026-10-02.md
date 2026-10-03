<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF12：背景快照与模型阴影共存（2026-10-02）

> **历史证据 — 非现役入口**。设计前置提交 `fe048ff3`；本片v2已获独立产品终审ACCEPT，按下列有界范围交付。稳定职责见[架构](../architecture/runtime-architecture.md)，后继顺序由[兼容路线](../roadmap/scene-compatibility-roadmap.md)决定。

同页历史分节：[已退役设计裁决](#rf12-retired-design)。

## 断点与实际改动

F6 为保护晚申请的 color-blend/refraction 背景纹理，在存在真实消费者时关闭 optional shadow。另有空粒子批次在原 update 返回成功后仍进入绘制集合，虽最终没有可绘 slot，仍先复制整帧；utility 的背景消费者也被旧 image/solid/text 白名单漏计。

本批沿原 SceneFramebufferSnapshot 单槽、两个 pipeline 原实例与唯一 SceneResourceBudget 准备实际 target 容量。Bloom 与模型/粒子必需资源先于快照，快照先于 optional shadow。嵌套同步作用域仅准备容量；后项失败整组恢复旧槽和计费，原作者顺序绘制仍可重新申请，不能把快照失败扩大为原层硬拒绝。成功准备不代表有像素，每个消费者仍在原位置复制当时背景，不能借环境反射的首次共享前缀。

上传仍先执行 update 以清除旧 current slot，再以该 buffer 的真实 currentDrawState 保留可绘批次；同一集合供后续需求、depth、draw 与取消消费。utility 从现役触发字典和 prepared plan 取实际 enclosing pass；该字典的唯一 producer 已过滤 shouldCapture，不新增同义防御。迟到 publication 不被提前判为 absent。两类实例仍各只有一个实际尺寸/格式槽；不能覆盖同帧实际目标时局部退回无影，不造多槽 registry。

## 反例和工程纠偏

本机证据根 `/private/tmp/mwx-rf12/`。预先冻结的160×96自有输入及camera cover ROI显示：旧App混合区域green64、非零折射blue/零值red均正常，阴影和控制区却均85；新合同要求仅阴影恢复9。停止后的empty粒子实际nonempty=[]，旧App55帧仍55次整帧复制，累计计数约1.3066GB，并关闭阴影；隐藏控制0复制且阴影正常。这是复制字节计数，不是性能测量。

早期大折射位移落黑区、ROI未采用实际cover相机的两次fixture错误保留，不当作产品失败。最终旧App合同测试4方法/6输入中2方法通过、2方法失败（mixed两子项与empty）；utility两输入既有输出通过，证明可达消费者但不证明已预留资源。独立修前/协议审查 `baseline-protocol-review.md` SHA `8e82a495401086853903026837860d33cbf83131d68c704ad3f85d12bf8c85b6` 已重算截图与身份。

v1 Debug构建通过但防御门失败：两个 pipeline 新增相同转发函数使重复组127→128。v2删除转发，内部只读访问原实例，未改基线或新增wrapper；防御门恢复127并通过。v2七产品manifest `implementation/checkpoint-v2-products.json` SHA `ead7a3bf1af75b0be7cc0d661956526cc07b5d190d95dfef62dadb3b33bab95a`；构建前后源码一致，`build-v2/identity.json`保存五项App/helper身份。隔离App已完成本机有效签名及两个编译helper固定Team requirement检查，不属于发布/公证验收。

## 验证与范围

实际新App 4方法/6输入与原F6单方法/3启动共5方法通过（83.247s）；`app-final-v2.log`、`snapshot-shadow-app-5g1d01uq`、`directional-shadow-app-7vdkd737`保存输出。mixed-active为52帧/104次capture/52次completed refraction，原混合green64、折射blue与控制85不变，阴影为9；empty52帧0capture、0refraction且阴影9。utility active/normal都实际完成合成，原控制像素分别64/100。root目检mixed-active截图与ROI一致。资源门如下，最终产品独审已接受。单槽native GPU门与真实App各自证明其范围；prepared输入壳不等同完整renderer admission。未验证完整原包画面、官方parity、性能、多屏、全部group/forward组合；point/spot、动态named caster等仍属后继，不因同帧共存关闭整个D3。

真实未改原包 `3589454154` 再验使用隔离副本及v2签名App：exit0、input/App五项身份不变、frame1完成及安全drain，仍22个模型prepared、零shadow事件，无helper签名拒绝。证据`original-v2/identity.json`、`summary.json`；不计完整原包阴影受益。

后继选已准入hidden image/solid source-only named albedo模型投影。其真实模型显示路径已有记录，但不代表原包开启shadow；先建立同帧named颜色正常而阴影关闭的反例，再经设计把当前publication前移到原dependency owner。未知模型reader差额和point/spot继续以实证定优先级，不能用缺少私有公式跳过。

最终资源组合首轮16方法为14通过/2失败（47.946s）：core4（含最后引用释放）、refraction6、旧F6 frame-owner3、实际upload1通过；新frame两方法在state.arm移交并清空shadow之后才读取布尔，错误记录为false。保留原日志与source，仅把观测移到arm前，不改产品、像素oracle或断言；单frame3方法复验通过（16.858s），日志`frame-final-v2-observation-fix.log`。这个fixture失败不能冒称产品回归，也不能将后续复验拼成首轮全绿。

App独审报告`implementation/app-stage-review-v2.md` SHA `b6c0bb73ba54a4e37b27c3474b2a9c3a5ecdef4ad14d6fe03f53c728beee332c`逐项核输入、包、App及PNG。F6 late-color-blend-active日志只提供surface frame0/1 completion，frame1另有实际graph next-frame/compositorConsumed/GPU completion，不能统一写所有9启动均有surface frame1/2。

最终测试源清单`test-source-final-v2.json`绑定4个本批测试文件。capacity共7方法（core4+frame3），折射邻接6与旧frame-owner3均取得相称通过证据；不会把3方法复验重复累加为新能力数量。core编译实际Snapshot/MainPass/ResourceBudget，验证SDR/HDR两次不同内容捕获、容量不编码、第二owner真实物理配额拒绝与整组回滚、旧identity/内容保留、原lazy capture恢复，以及同queue共享事件阻塞/resize/最终引用释放。frame门编译实际StaticModels/Particles扩展、两pipeline及原pool，prepared资源壳groups=nil；实际utility完整合成由App另验。all-invalid/healthy-peer只证明实际buffer上传结果，empty零复制另由完整App证明，不冒称全部非法输入经过App。

Debug构建、code-health、防御面、design-gate通过；文档门最初缺标准历史banner导致1项失败，补元数据后13方法通过，未修改测试或放宽规则。未增加结构预算。完整App构建和shader未因测试观测修正而变化；无须为测试壳观测点重跑全部App。

## 终审与职责移交

独立终审 **ACCEPT RF12 v2**：`implementation/product-final-review-v2.md` SHA `b98d69fa82c4c3fbc783cc7d460310fd4b39e0cfb2e1cebbee9e7e714346a2ac`，绑定上述7产品manifest与4最终测试SHA。16个不同资源/邻接方法取得有效通过证据，不能把有fixture失败的首轮写成全绿。稳定容量与顺序合同已移交架构，[前置设计](rf12-snapshot-shadow-coexistence-implementation-2026-10-02.md#rf12-retired-design)归档并删除唯一窄登记；整个D3不退役。并行历史文档、其角色/导航登记与layout排序不纳入本提交。未推送；证据保留本机精确目录，App/GPU执行已结束。

<a id="rf12-retired-design"></a>

## 已退役设计裁决

下文完整保留该阶段的历史裁决、证据身份和未验证边界；其中状态与后继顺序仅适用于原记录日期。

<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

<a id="rf12-retired-design--rf12-背景快照容量准备退役设计"></a>
### RF12 — 背景快照容量准备（退役设计）

> **历史证据 — 非现役入口**。RF12 v2 已通过实际资源/App门及独立产品终审；稳定合同由架构接管，执行证据见本目录 RF12 实施记录。本设计仅保留当时裁决，窄登记随职责交付退役。

基线 `49e34a6c`。本设计承接[RF12工作卡](../roadmap/batch2/reference-evidence-implementation-cards.md#rf12-late-snapshot-capacity)，已获独立设计ACCEPT；本机报告 `/private/tmp/mwx-rf12/design-review.md` SHA `3ece13fe16807cee5100dbae352c5bbbfe089d120eba65c7427961893e8f7ef9`，绑定批准前设计SHA `e59510f95dc45a9891dfa7a0a93441b21efc4ad896c8c172a8ada456287fb920` 与登记SHA `b32731f1890f527dd5f306c796c6d8d4baa7585fc97ff69c86cdf7032dcb1b99`。批准设计不等于产品验收。它修复现有 color-blend、refraction 和[D3 F6方向光阴影](../roadmap/batch2/2d-lighting-material-design.md#f6-model-directional-shadow)不能同帧共存的资源断点，不改变混合、折射或阴影的视觉算法。

<a id="rf12-retired-design--目标合同与当前事实"></a>
#### 目标合同与当前事实

实际有混合/折射消费者时，提前取得其原快照实例的真实纹理容量，随后才允许 optional shadow 分配。每个消费者仍在作者顺序的原位置复制当时背景；第二次捕获必须包含中间新绘制的内容，不能以F5共享首次反射前缀替代。没有真实可绘消费者时不增加快照分配。无shadow需求沿原绘制路径，不为未来用途预热。

以下路径相对 `MyWallpaperX/Core/SteamWorkshopScene/`：

- `Rendering/Composition/SceneFramebufferSnapshot.swift:14,29–75` 每实例只有一个尺寸/格式槽，capture在实际绘制时才创建背景纹理；allocation已经走唯一SceneResourceBudget。
- `Rendering/Composition/SceneLayerColorBlendPipeline.swift:74,95–105,204–209` 和 `Rendering/Particles/SceneParticleMetalPipeline.swift:26,102–105,184–188` 分别持有快照实例。它们共享类的行为，不共享同一纹理或第二个registry。
- `Rendering/Frame/SceneMetalRenderer+Particles.swift:60–65` 每个refraction batch在原MainPass可读点复制。`Rendering/Composition/SceneMainPassEncoder.swift:107–112` 先保证target已初始化并结束当前encoder，再交copy；容量准备不能调用该方法，以免提前clear或结束encoder。
- `Rendering/Frame/SceneMetalRenderer.swift:278–318` 现用refraction batch及image/solid/text source判据识别需求，但零上传实例仍被算入、utility consumer又被漏掉；命中其旧判据时不准备shadow候选；model/particle depth、scratch和Bloom已按F6合同保护。此次替换该排除，不另建eligibility解析器；旧判据不能升级为完整需求合同。`SceneMetalRenderer+EffectExecution.swift:25–35` 的ready utility plan经 `SceneUtilityPlanFrameRenderer.swift:99–147` 的enclosing composite pass进入同一color-blend owner，因此实际utility消费也须纳入准备。
- `Rendering/Frame/SceneMetalView+FrameContext.swift:24` 的screenSize来自drawableSize；`Rendering/Composition/SceneUtilityLayerRuntimePlan.swift:418–426` 的group尺寸随其准备；main raw来自实际drawable（`Rendering/Frame/SceneMetalRenderer+ClearColor.swift:118–120`）。当前尚无同帧多尺寸的作者触发；source crop和effect纹理尺寸不是背景target尺寸。
- `Rendering/Frame/SceneMetalRenderer+Initialization.swift:22–26` 创建每renderer的command queue，`Rendering/Frame/SceneMetalView.swift:122,424` 创建renderer及粒子playback；`Rendering/Composition/SceneImageLayerCompositor.swift:47–51` 创建其color-blend实例。复用仍服从各surface的原提交顺序。

另有修前真实反例：自造stopped-empty粒子场景已消费stop且live count为0，却55帧发生55次背景capture、没有completed refraction draw并使阴影关闭；hidden对照零capture且阴影成立。本机证据 `/private/tmp/mwx-rf12/baseline-refraction-cqslttaa/{empty,hidden}/result.json` 及具体app/preview日志。判定只看 `batch.refraction != nil` 不足：必须在原prepared batch/绘制owner一致排除零实例，既不预留背景也不在实际draw前做无效copy，保留原instance提交/取消合同。具体在现renderer上传filter中先执行update以清理stale current状态，再以同一instanceBuffer的currentDrawState是否存在确定可绘集合；该集合同时交需求、depth、render与取消路径，不在多个consumer抄count matcher。空数组与全非法上传均可能update成功而无current draw（SceneParticleMetalInstanceBuffer.swift:43–67），不得跳过update或拿模拟count替代实际上传结果。

五判据：①跨帧编排、两个consumer与资源分配，是；②触必需资源优先和GPU生命周期，是；③不改用户数据/持久格式，否；④接触现冻结Frame/Composition家族，是，但不增新家族或预算；⑤引用公开Metal生命周期保证，是，不需要私有公式或新官方视觉裁决。登记 `scene-framebuffer-snapshot-capacity`。

<a id="rf12-retired-design--owner准备与选型"></a>
#### owner、准备与选型

唯一owner仍是原SceneFramebufferSnapshot实例，两个pipeline只委托本实例；frame renderer依据已有prepared消费者安排准备。需求来自已完成group/source准入、可执行utility composite和实际非空refraction batch，目标取实际最终main/group pass的尺寸和格式，不取layer crop。root group合成使用原composite target，不能错取group source。utility需求依据现ready framePlan、现trigger可达和enclosing composite pass；layer-loop的defer即使普通层不可见仍可能执行该utility，故不得以普通层contentKind/visibility筛选代替这个owner的执行集合。utility依赖在prepass可能尚未publication而在作者顺序稍后ready，容量需求以现ready framePlan/可达trigger为依据，不能用此刻provider texture缺失否定未来消费；确实无法确定该已有计划消费容量时，只关闭本帧optional shadow并保原utility执行，不提前求值或建另一graph。当前所有消费目标可证明同一key时保留单槽；发现不同key不能静默覆盖一份准备结果或借用错误尺寸，须先用真实反例修订该owner的容量设计。

容量准备只做同步校验/真实分配，不编码copy、不开encoder、不改图层顺序。复用原尺寸/格式/预算检查以及texture allocation路径；capture随后命中同一容量，仍逐次拷贝。公开入口必须有真实consumer，不增加仅为测试的零调用API。

两个实例需同时准备时，选择在原owner内提供可回退的scoped准备：同步栈保留旧槽和resident计数，嵌套准备需要的实例；全部成功才保留新槽。任一分配/配额/原pipeline失败，在返回原绘制循环前还原所有本次已改变的快照槽并释放尚未编码的新纹理。回滚后原capture允许按原作者顺序正常申请，可能利用回滚归还的容量恢复；禁止的是保留partial新槽或在本帧重新尝试optional shadow准备，不能误套F6已失败depth lease不得重试的不同合同。continuation只做容量准备，不得隐藏GPU命令。这样部分成功不能先占预算挤掉原先可显示的另一消费者，也不需要新ticket、事务manager、注册表或frame epoch。成功后optional shadow自身失败可以保留本帧实际需要的完整容量。

准备位于F6必需depth/scratch保护之后、optional shadow分配之前。原terminal/Bloom准备先完成，再进入两个snapshot的scoped准备；snapshot continuation不包含其它owner的不可回退提交。旧槽与候选新槽暂时同持有会使紧预算下本帧shadow保守关闭，允许原lazy路径或下一帧恢复；不能为提高optional成功率先丢旧缓存。真实named-model绑定未ready的独立限制保留，不借本片提前消费provider。shadow关闭或准备失败时仍运行原consumer，不能把普通资源失败扩大为整帧拒绝，也不对合法声明但无可绘source的层预留。

备选：固定先分配color再particle但失败保留部分新槽，会改变紧预算下的原失败半径，拒绝；只估字节或留固定余量无法保证实际物理分配，拒绝；共享一份帧背景改变copy时序，拒绝；多尺寸cache及独立shadow快照pool无当前producer，拒绝。原owner的scoped准备能闭合真实缺口且不扩长期状态家族。

<a id="rf12-retired-design--生命周期fallback与新增guard依据"></a>
#### 生命周期、fallback与新增guard依据

原renderer用默认保留资源的command buffer；同一queue按enqueue次序执行。这些是[Apple command buffer合同](https://developer.apple.com/documentation/metal/mtlcommandbuffer)和[retainedReferences默认行为](https://developer.apple.com/documentation/metal/mtlcommandbufferdescriptor/retainedreferences)。实例不得跨surface/queue共享。同尺寸下一帧复用依赖原queue的GPU顺序，而非CPU已返回；允许CPU编码后继command buffer，不新增跨CB拒绝门；resize替换旧槽后，已编码旧纹理由原command buffer保留至完成，associated资源lease保持实际全局预算计费。无需另造pin registry，但必须用真实阻塞提交/resize证据验证。

未提交取消不发布捕获内容，下一次capture仍拷当前target；只准备未编码的纹理失败回滚可立即释放。成功准备后取消可保现实例可复用容量，不能假报为当前帧有效背景。residentByteCost只代表当前cache槽，不能假称它含所有在飞退休资源；真实全局预算由MTLResource关联lease负责。

fallback仍局部：快照容量不足则该次optional shadow关闭，原效果遵循原capture结果；copy encoder失败沿原consumer失败半径，不发布未写背景。原GPU range、generation/提交或target hazard安全门不被绕开。新guard只能对应真实producer：resize导致尺寸变化、实际target格式、全局配额/Metal分配失败、原pipeline不可用或真实消费者集合不确定。不能为假设cross-device/cross-queue调用增设常驻防御层。

<a id="rf12-retired-design--纠正门"></a>
#### 纠正门

1. 修前不可变F6 App：真实caster/receiver + 可见color-blend，以及真实refraction粒子（非零量与零量对照）。原效果本身必须显示、completion/terminal/next-frame成立，同时shadow关闭；隐藏/空batch对照恢复shadow。空实例对照必须同时证明零背景copy而非只有shadow恢复；加入实际utility composite与原enclosing target的需求正反例。用自造合法作者输入，不读取私有shader表达。
2. 修后实际App证明混合、折射分别与shadow同帧生效；两consumer之间加入不同背景，第二次必须读到新背景。固定ROI与输入、源码、App身份，避免把整帧变暗或无效粒子当成功。保alpha/HDR及健康邻层，至少一个组合经过后续帧。
3. 真实原snapshot GPU门：准备不改变target内容、不产生可消费的伪捕获；同key命中不二次申请；每次capture读不同当前背景；两实例第二项真实预算拒绝时首项回滚，旧内容/槽及物理预算不变，回原路径后健康consumer仍能执行。释放注入配额后重试成功。非真实OOM、故障注入与作者路径分开记录。
4. 跨帧不同extent、SDR/HDR、已提交但被共享事件阻塞、取消未提交、owner释放/替换、实际GPU completion且最后强引用/command buffer释放后的资源归还；不把waitUntilCompleted误认为所有CPU引用已经消失。验证原单queue次序，不用新模拟状态机代替。main/group实际target身份与尺寸需实测，不为了覆盖数字捏造产品多槽。
5. 相邻F6阴影、粒子refraction、color-blend及persistent output按失败半径选择；Swift/Metal实际编译、Debug build、code-health、scene-defense、design-gate、文档角色及独立产品终审。只承接输入协议不算完成；未覆盖group/forward、多屏、性能、完整原包和官方parity必须明示。

<a id="rf12-retired-design--退役与后继"></a>
#### 退役与后继

通过上述有界共存、预算失败及生命周期门后，稳定容量/内容时序合同移交[runtime architecture](../architecture/runtime-architecture.md)，真实红绿与执行身份归历史记录，本设计归档并删除窄登记。RF12关闭后按[唯一兼容路线](../roadmap/scene-compatibility-roadmap.md)选择真实受益的model spot/point或named caster，不把缺官方公式作为跳过理由。
