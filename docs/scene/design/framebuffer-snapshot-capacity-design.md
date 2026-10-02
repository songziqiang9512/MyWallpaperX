<!-- document-role: active-plan -->
<!-- retirementCondition: 背景快照必需容量与阴影共存通过实际GPU/App、资源失败和生命周期门，稳定职责移交架构、执行证据归历史后归档本文并删除窄设计登记。 -->

# RF12 — 背景快照容量准备

基线 `49e34a6c`。本设计承接[RF12工作卡](reference-evidence-implementation-cards.md#rf12-late-snapshot-capacity)，已获独立设计ACCEPT；本机报告 `/private/tmp/mwx-rf12/design-review.md` SHA `3ece13fe16807cee5100dbae352c5bbbfe089d120eba65c7427961893e8f7ef9`，绑定批准前设计SHA `e59510f95dc45a9891dfa7a0a93441b21efc4ad896c8c172a8ada456287fb920` 与登记SHA `b32731f1890f527dd5f306c796c6d8d4baa7585fc97ff69c86cdf7032dcb1b99`。批准设计不等于产品验收。它修复现有 color-blend、refraction 和[D3 F6方向光阴影](2d-lighting-material-design.md#f6-model-directional-shadow)不能同帧共存的资源断点，不改变混合、折射或阴影的视觉算法。

## 目标合同与当前事实

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

## owner、准备与选型

唯一owner仍是原SceneFramebufferSnapshot实例，两个pipeline只委托本实例；frame renderer依据已有prepared消费者安排准备。需求来自已完成group/source准入、可执行utility composite和实际非空refraction batch，目标取实际最终main/group pass的尺寸和格式，不取layer crop。root group合成使用原composite target，不能错取group source。utility需求依据现ready framePlan、现trigger可达和enclosing composite pass；layer-loop的defer即使普通层不可见仍可能执行该utility，故不得以普通层contentKind/visibility筛选代替这个owner的执行集合。utility依赖在prepass可能尚未publication而在作者顺序稍后ready，容量需求以现ready framePlan/可达trigger为依据，不能用此刻provider texture缺失否定未来消费；确实无法确定该已有计划消费容量时，只关闭本帧optional shadow并保原utility执行，不提前求值或建另一graph。当前所有消费目标可证明同一key时保留单槽；发现不同key不能静默覆盖一份准备结果或借用错误尺寸，须先用真实反例修订该owner的容量设计。

容量准备只做同步校验/真实分配，不编码copy、不开encoder、不改图层顺序。复用原尺寸/格式/预算检查以及texture allocation路径；capture随后命中同一容量，仍逐次拷贝。公开入口必须有真实consumer，不增加仅为测试的零调用API。

两个实例需同时准备时，选择在原owner内提供可回退的scoped准备：同步栈保留旧槽和resident计数，嵌套准备需要的实例；全部成功才保留新槽。任一分配/配额/原pipeline失败，在返回原绘制循环前还原所有本次已改变的快照槽并释放尚未编码的新纹理。回滚后原capture允许按原作者顺序正常申请，可能利用回滚归还的容量恢复；禁止的是保留partial新槽或在本帧重新尝试optional shadow准备，不能误套F6已失败depth lease不得重试的不同合同。continuation只做容量准备，不得隐藏GPU命令。这样部分成功不能先占预算挤掉原先可显示的另一消费者，也不需要新ticket、事务manager、注册表或frame epoch。成功后optional shadow自身失败可以保留本帧实际需要的完整容量。

准备位于F6必需depth/scratch保护之后、optional shadow分配之前。原terminal/Bloom准备先完成，再进入两个snapshot的scoped准备；snapshot continuation不包含其它owner的不可回退提交。旧槽与候选新槽暂时同持有会使紧预算下本帧shadow保守关闭，允许原lazy路径或下一帧恢复；不能为提高optional成功率先丢旧缓存。真实named-model绑定未ready的独立限制保留，不借本片提前消费provider。shadow关闭或准备失败时仍运行原consumer，不能把普通资源失败扩大为整帧拒绝，也不对合法声明但无可绘source的层预留。

备选：固定先分配color再particle但失败保留部分新槽，会改变紧预算下的原失败半径，拒绝；只估字节或留固定余量无法保证实际物理分配，拒绝；共享一份帧背景改变copy时序，拒绝；多尺寸cache及独立shadow快照pool无当前producer，拒绝。原owner的scoped准备能闭合真实缺口且不扩长期状态家族。

## 生命周期、fallback与新增guard依据

原renderer用默认保留资源的command buffer；同一queue按enqueue次序执行。这些是[Apple command buffer合同](https://developer.apple.com/documentation/metal/mtlcommandbuffer)和[retainedReferences默认行为](https://developer.apple.com/documentation/metal/mtlcommandbufferdescriptor/retainedreferences)。实例不得跨surface/queue共享。同尺寸下一帧复用依赖原queue的GPU顺序，而非CPU已返回；允许CPU编码后继command buffer，不新增跨CB拒绝门；resize替换旧槽后，已编码旧纹理由原command buffer保留至完成，associated资源lease保持实际全局预算计费。无需另造pin registry，但必须用真实阻塞提交/resize证据验证。

未提交取消不发布捕获内容，下一次capture仍拷当前target；只准备未编码的纹理失败回滚可立即释放。成功准备后取消可保现实例可复用容量，不能假报为当前帧有效背景。residentByteCost只代表当前cache槽，不能假称它含所有在飞退休资源；真实全局预算由MTLResource关联lease负责。

fallback仍局部：快照容量不足则该次optional shadow关闭，原效果遵循原capture结果；copy encoder失败沿原consumer失败半径，不发布未写背景。原GPU range、generation/提交或target hazard安全门不被绕开。新guard只能对应真实producer：resize导致尺寸变化、实际target格式、全局配额/Metal分配失败、原pipeline不可用或真实消费者集合不确定。不能为假设cross-device/cross-queue调用增设常驻防御层。

## 纠正门

1. 修前不可变F6 App：真实caster/receiver + 可见color-blend，以及真实refraction粒子（非零量与零量对照）。原效果本身必须显示、completion/terminal/next-frame成立，同时shadow关闭；隐藏/空batch对照恢复shadow。空实例对照必须同时证明零背景copy而非只有shadow恢复；加入实际utility composite与原enclosing target的需求正反例。用自造合法作者输入，不读取私有shader表达。
2. 修后实际App证明混合、折射分别与shadow同帧生效；两consumer之间加入不同背景，第二次必须读到新背景。固定ROI与输入、源码、App身份，避免把整帧变暗或无效粒子当成功。保alpha/HDR及健康邻层，至少一个组合经过后续帧。
3. 真实原snapshot GPU门：准备不改变target内容、不产生可消费的伪捕获；同key命中不二次申请；每次capture读不同当前背景；两实例第二项真实预算拒绝时首项回滚，旧内容/槽及物理预算不变，回原路径后健康consumer仍能执行。释放注入配额后重试成功。非真实OOM、故障注入与作者路径分开记录。
4. 跨帧不同extent、SDR/HDR、已提交但被共享事件阻塞、取消未提交、owner释放/替换、实际GPU completion且最后强引用/command buffer释放后的资源归还；不把waitUntilCompleted误认为所有CPU引用已经消失。验证原单queue次序，不用新模拟状态机代替。main/group实际target身份与尺寸需实测，不为了覆盖数字捏造产品多槽。
5. 相邻F6阴影、粒子refraction、color-blend及persistent output按失败半径选择；Swift/Metal实际编译、Debug build、code-health、scene-defense、design-gate、文档角色及独立产品终审。只承接输入协议不算完成；未覆盖group/forward、多屏、性能、完整原包和官方parity必须明示。

## 退役与后继

通过上述有界共存、预算失败及生命周期门后，稳定容量/内容时序合同移交[runtime architecture](runtime-architecture.md)，真实红绿与执行身份归历史记录，本设计归档并删除窄登记。RF12关闭后按[唯一兼容路线](../scene-compatibility-roadmap.md)选择真实受益的model spot/point或named caster，不把缺官方公式作为跳过理由。
