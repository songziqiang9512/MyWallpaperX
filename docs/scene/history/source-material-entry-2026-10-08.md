<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。当前合同见[运行架构](../architecture/runtime-architecture.md)，后续工作只从[断点队列](../roadmap/scene-open-breakpoint-queue.md)继续。

# 自定义图层源材质入口（2026-10-08）

起点 `015ff8d6`。243样本统计刷新后确认：model→material信息虽已保留，普通材质准备只枚举effects，833227004的双纹理flow源因此只显示静态底图。本片补共享入口，不增加flow、tint或样本专用算法，不复制参考项目实现。

## 实施与修正

Resolver/TemplateCompiler共用槽覆盖、uniform投影和ShaderSchema；source身份使用真实layer/model/material/pass，不能伪造EffectKey。source颜色叶与UV/weight数据闭包复用原分析器；data样本不能因RGBA载体而预乘，颜色输入也不能误读为数据。多义用途、branch/mutation/未知helper及颜色/alpha泄漏继续拒绝。DemandAnalysis v3、VariantAnalysis v12使旧purpose/transfer记录安全失效。

`ScenePreparedDeviceResources.makeMaterialRuntime`统一首surface worker与后续surface：同一executor完成variant/pipeline准备，再发布runtime。Rendering只持typed frame binder、资产域及格式；binder捕获原已编译VariantCache，普通帧不编译或建图。源输出复用offscreen pool、mandatory-capacity优先级、MainPass submission pin和原registry/compositor，隐藏且无消费者的源不分配。

实际App暴露并修正了域错误：普通底图已裁到1920×1080，而源Program的两张TEX物理域为2048²。源目标必须从所选slot0资产identity/purpose取得physical/mapped/UV，且全部variant一致；发布后effect capture更新同一UV。只把普通底图尺寸复制到源目标会出现大片灰色留白。rgba16Float也纳入原图像candidate消费合同。

## 有界验证

本机根 `/private/tmp/mwx-material-source-20261008`，完整命令、输入SHA及产品身份保存在各report/fixture manifest。正常签名Debug App，team `H9QWU9XN8R`，非发布或公证验收。

| 输入与身份 | 实际结果 | 证据上限 |
|---|---|---|
| 原833，`runtime-flow-verified`；executable SHA `91ab986037d16ac67bd687cd90f20dc1ae8e0f0cf4794a9aa9c4eb6426f2ca34`，CDHash `e7ec0c6c637899718a0d1b43fef67bdca9ab0c3f` | source prepared/encoded、2048²目标、留白消失；窗口中央60%区域相隔约10秒，93.62%像素变化超过2/255，RGB平均绝对差0.02361 | 源材质真实动态与构图恢复；官方用户截图仅非同步构图参考，不是同时间pixel parity |
| 原833仅新增RGB乘(0.5,0.75,1)后effect，`runtime-after-effect`；executable SHA `108453c0e0a07a708f96b40bc6de25608f855ff88f00dc7278cc3af95fde1f41` | source→effect→GPU completion→publication→compositor→next-frame；相对原源ROI均值比0.50565/0.75119/0.99882，仍有80.62%像素动态变化 | 此App与最终App只差私有可见性/注释整理；两个运行clock不同，仅验证染色方向与动态，不作逐像素等价 |
| 原833仅general.hdr=true，`runtime-hdr-verified`；同最终App | 16F source进入既有compositor，映射完整、多帧动态，benchmark PASS | 不是物理EDR亮度、外屏HDR或全部HDR样本正确 |
| 健康1439846152原pkg，`runtime-builtin-verified`；同最终App | 基础图与粒子继续显示，未产生custom source Program，benchmark PASS | 此输入非回退；不是全部builtin/粒子parity |

`visual-checks.json`记录完整ROI/图名/identity。旧`runtime-flow-1`因ad-hoc包编译工具签名不合合同降级；`runtime-flow-2`虽benchmark PASS但实图域错，均不算验收。首次HDR周期截图间隔2秒短于16F readback处理，出现snapshot失败；相同产品增加采样间隔为5秒后通过，未提高产品超时或修改运行算法。一次最终跑启动早于签名完成被前置检查拒绝，完成签名后重新验证。

独立generic MSL/GPU probe以非线性自有64²输入证明：正确边界的straight/premul结果误差约2.98e-8；数据纹理alpha0/1不改变结果；缺失颜色边界产生0.149468误差；time0/4输出差0.135812。该probe不冒充App PassEncoder证据。

最近合同门：pool 30、template 6、source-purpose 7及最近颜色/默认purpose反例、source transaction/texture candidate/finalizer 39、runtime bridge 14、material state/transform/source publication/source-set 5模块及persistent cache行为门通过。旧bridge harness只允许空source-entry，覆盖协调器回滚/实际Metal生命周期，不用stub宣称source渲染通过。Debug build、结构/依赖/代码与文档门按本次冻结清单检查；未执行全243运行矩阵或release suite。

独立只读审查发现并修正隐藏源预算、HDR candidate、display target预算、VariantAnalysis失效；随后复核域/UV、后effect消费、两个surface构造入口与binder持有关系，无剩余明确阻断。未验named组合、多surface实际运行及所有失败类型，不从静态审查外推运行正确。

## 剩余公共能力与受益边界

原有范围抽取的另外10样本11个custom tint层全部未准入，详见`cross-input/admission-matrix.json`（SHA `686f4a0aa2a8d2e33f1ba75e914f7c20957b430f7261c1af36ee001a3f36c023`）：3层translucent/alphawriting=default、7层动态material常量、1层perspective。不能把统计候选计为实际受益；此批实证受益是833真实源，通用性由共享入口、自有shader/GPU反例及新effect组合证明。

下一片优先裁决3层共同透明state与原compositor的职责，随后将7层动态常量接入已有materialConstant typed通道；不为每个样本新增算法。多pass、instance、user texture、named/history、Puppet/3D、更多UV/state依旧明确开放。全样本缺口全集及旧用户反馈由现役队列拥有，本文件不另建任务表。

## 产物

只保留最终报告、日志、identity、受控输入生成脚本/manifest、必要截图与GPU小probe。证据推广工具因现有cache总预算已满拒绝，`--prune-expired`没有可清已登记包；因此本批精简结果暂留上述任务根，未删除未知归属证据。停止的staged App、样本副本、临时HOME与重试截图清理；连续迭代仅保留 `/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d` 构建缓存。真实媒体只读。

## 后继更正：中性材质静态颜色入口

本片起点`8365a107`。上文“另外10样本11层未准入”仅描述新增source Program入口，不能据此断言旧消费者缺失：3792817546:20此前已有neutral-tint脚本→动态bar→compositor的S4证据；其余6个动态层涉及user Alpha/color、Power=.99或同model多source，静态归因仍须运行复现。3个静态tint层与此前运行shader字节相同，只缺常量颜色入口，增加Program pass会重复职责。

扩现`SceneBaseMaterialColorModulationCompiler`，共享prepared shader与neutral proof。静态RGB随既有catalog交给base-material Program，在原source uniforms乘material×layer color一次；动态创建图层按同model消费同prepared颜色，无新增VM、GPU pass或纹理缓存。`excludingTargets`保留静态metadata，launch拒绝instance覆盖并将已lowered model从generic source Program排除。named raw capture尚不消费材质颜色，因此用现reference分析排除所有同model的显式、隐藏和可选named参与层，未另建capture路径。

同步修复旧proof越界：完整raw-token检查拒绝`1 junk`等数字投影残缺；位置要求共享HostUniformSchema的无作者覆盖/default MVP及既有quad attributes；fragment只采样同vertex varying或`.xy`，拒绝offset/swizzle/未连接varying。角色重名在字典literal前局部拒绝，避免duplicate key启动trap。sampler经过共享schema，只有`permitsSourceStraightColorProjection`允许的无类型子集可补颜色事实，最终`purpose(for: actual slot0 asset)`必须为straightAlbedo；normalmap、typed auxiliary default、真实资产data用途及nil冲突均拒绝。不新增解析器，prepared源码缓存不保存此proof，无需变更缓存版本。

证据根`/private/tmp/mwx-source-state-20261008`，真实输入副本前后SHA一致。最终正常签名Debug App executable SHA`8e34583f82df27407f06fff5015ba0443b0062aedb5c16a67f0c836ac80abd49`，CDHash`7b0f7f93f9e698aceb39636fd02ac7d8a53062e2`，`build-accepted.log`成功。

| 运行 | 实际结果与上限 |
|---|---|
| `runtime-accepted-real` 原3800075350、3788734811、3002649614 | 全部PASS，各1个静态颜色、原层+63动态bar进入实际绘制；前两者按作者变黑，白色材质样本保持正常。测试PCM经捕获服务/分析/inbox驱动条形，不代表全部真实音源或整个样本官方一致 |
| `runtime-accepted-alpha`，自有scene复用原中性shader/slot0 | 原层+1个createLayer，layer RGB=(.5,.25,.75)、material=(.4,.8,.2)、layer alpha=.5，两块均RGB(26,26,19)，合计596232像素；`accepted-color-pixels.json`绑定图像SHA |
| `runtime-probe2-white/tint`，早期App SHA`3ac3471dd6647177b55770212cfee6159254a19248dd93ed58bd3c81ff98f41c` | 相同非白layer、alpha=1，白material输出(128,64,191)，tint输出(51,51,38)，原/动态层相同。早期身份用于颜色比例；最终App半透明组合另已验证 |
| `runtime-reviewed-named`，App SHA`269c5e5c9d654c1225aefb570833911ef1824f9b2d3666b8a6aa062573acdf9a` | 隐藏consumer及effect仍使静态颜色数为0，安全保留原源；该launch过滤此后未改。仅拒绝边界，不是named染色已支持 |

真实compiler 54输入与原neutral proof共14tests通过，收据`compiler-final-purpose-receipt.json` SHA`90aa599dfb8810ecbf2800b5c98a173c68a9378534aa5d6fcf353f51948e6292`。scalar与matrix/UV反例先红后绿；旧角色崩溃仅静态发现，新guard反例已执行安全拒绝。source uniforms/候选安全、provider、target projection、inactive named、动态layer、属性脚本、alpha、bridge及gate选择最近门通过；旧solid fixture漏rgba16Float导致一次编译失败，补齐link-only类型后通过，不冒充GPU。原始controlled probe的相对model路径未准备也已拒绝，改完整路径后重跑，失败不算验收。独立只读复核最终无剩余明确阻断。

官方黑盒另验证自有literal RGBA(.8,.2,.1,.5)：normal覆盖背景，translucent表现为一次.5覆盖，后identity不重复衰减；alphaWriting absent/default/enabled此矩阵屏幕RGB相同，不能推广为通用state等价或内部alpha mask结论。最终控制未采样slot0，不宣称白纹理已载入。本片未据此放开generic透明state。`official/behavior-contract.json` SHA`024d083b9343df5be1169515d6475e57c97b30d04e68b7a39282b0613a928391`；固定客户端2.8.0.42、自有输入、官方身份、24组重复ROI及失败原因俱存。本批窗口已关，VM恢复suspended。

本专项仅中性静态颜色3/3代表路径已实际接通。named实际染色、脚本tint与非白layer叠加、user Alpha/color、非中性Power、全部真实音源和完整官方parity仍未关闭；现役队列负责后续顺序。停止的样本副本、临时HOME/staged App、重复截图与临时编辑脚本清理；保留最小报告/日志/身份、输入生成脚本、必要图和官方自有输入，连续迭代仅沿用上节同一build缓存。`artifact-retention.json`登记保留与移除，不删除未知归属产物。


## 后继修正：脚本材质颜色与图层样式分离

本片基线`3290ad26`。旧neutral-tint脚本把材质值写到`.layer.color`，随后又在topology复制动态层并覆盖clone颜色；有非白图层样式时丢失应有乘色。改为实际material/pass/key的`materialConstant`，既有base-material Program保留作者fallback及target，原compositor消费同帧snapshot；原层与clone各自图层颜色独立。旧topology颜色复制、mapping及template字段退出，没有新VM家族、pass或当前值缓存。准备期仍按原instance/named边界排除；被排除的旧脚本候选尚可能无消费者执行，不宣称其VM退役。

隔离证据根`/private/tmp/mwx-material-dynamic-20261008`，最终正常签名Debug App SHA`7cff584259dd427f093b02a795640dd3bbdf07fed2104a19d04f71145895306c`；`built-product.json`冻结12产品文件。

| 输入与报告 | 实际结果和边界 |
|---|---|
| `runtime-baseline-controlled` / `runtime-final-controlled`，同受控PKG SHA`79f3d852189a7ea9a2961bc8dcfe3e118658dc31b2b9fd56c9020cde1a042f82` | 保留379作者材质脚本原bytes、关闭彩虹；material(.4,.8,.2)、layer(.5,.25,.75)、alpha.5，原层+1clone。旧App`8e34583f…abd49`输出(51,102,26)，新App(26,26,19)，两矩形共596232像素，符合逐分量乘色及一次alpha；两者benchmark均PASS，说明PASS本身不能裁决该视觉错误。颜色收据`color-comparison.json` |
| `runtime-final-original`，3792817546完整原包SHA`4776fca2d1e5804759a8cc41ec2916f2e64e62d5d06019083c9d744dbe3e023e` | PASS；实际materialConstant VM消费PCM，63clone encoded且passthrough0、GPU完成。频谱ROI的ready蓝(0,39,255)→after黄(255,216,0)，原彩虹仍动态。该ROI为运行后观察，不能当预注册parity；完整构图/交互/官方同声源未据此关闭 |

`3609108600`及`3610154602`仅准备输入，用户Alpha尚未准入，本片不记运行或受益。最近6模块46项CPU行为测试通过（`cpu-final.log`，91.761秒），覆盖真实编译器、target独立/冲突、原/动态图层样式、typed fallback及共享uniforms；三条退役源码形状断言已从棘轮删除。两份VM链接fixture已适配但未单独执行其VM门，实际脚本由上述App运行验证；未测性能量化。独立审查覆盖target/fallback/launch/schema与唯一消费者，提交前冻结证据复核。下一项仍为user Alpha/color公共入口，named实际乘色和非中性Power保持开放，顺序以现役队列为准。

停止使用的输入副本、baseline App及重复截图已清理；本片保留约11MiB报告/日志、输入生成脚本/逐条hash和4张必要PNG，`artifact-retention.json`登记范围。连续迭代仍仅沿用既有build缓存；结构、依赖、文档及代码门通过。一次误选冷构建已主动取消并由工具清理，正常签名增量build成功单独见`build.log`。


## 后继修正：材质Alpha复用属性与合成入口

本片基线`db9bc235`。中性shader的Alpha原先必须为1，真实3609108600/3610154602的严格`{user,value}`被挡在入口外，连带颜色证明也未消费。现在同份prepared proof保存实际schema key、作者fallback和属性引用；现属性编译器验证少量拟接入Alpha绑定，再结合整个同model的instance/named消费者范围准入。只有准入事实替换旧builtin writer，随后编译完整属性Program；launch消费同份事实，无新VM、shader pass或当前值缓存。原层与clone复用prototype target，最终原compositor乘材质Alpha×各自图层alpha一次。

独立审查修正三类反例：实际shader别名Opacity不能被旧名称Alpha抢占；slider完整声明域须在0–1内，缺失/宽域不接管；新路径被隐藏同model实例或named参与者拒绝时，必须先保留全部旧writer，不能到launch才撤销proof。小型预验证复用完整属性编译器，没有另写属性类型/范围解析，帧内无新增准备工作。脚本/Timeline Alpha、宽域Alpha、user color与更广source组合保持开放。

证据根`/private/tmp/mwx-material-alpha-20261008`。最终正常签名Debug App SHA`0475f8fd8acb981e823a5ce716a1b4e3e734e1a57ddbc6b84a77a373d395755c`，产品身份见`built-product-admission.json`、构建见`build-admission.log`。受控PKG SHA`07c0f3886af5ecb03e51fd91dcfee2dd37605a4e1e6741a65ff5297275c70471`保留真实shader及Alpha属性声明，只固定RGB、非白layer色、layer alpha=.5和一个clone。

| 运行 | 实际结果及边界 |
|---|---|
| `runtime-baseline-half`，旧App`7cff5842…5306c` | 同输入Alpha热切拒绝，材质色未消费，原/clone为RGB(64,32,96) |
| `runtime-admission-half/zero`，最终App | 热切1→.5：RGB(26,26,19)→(13,13,10)，两块合计596232像素；1→0后全黑符合自有输入期望，原surface/window不变。zero通用benchmark非黑门报FAIL，保留原报告，专用像素及accepted update验收；不篡改为通用PASS |
| `runtime-admission-original`，完整原3609108600/3610154602 | 两者基础纹理及63动态频谱层实际绘制。Debug PCM经过捕获服务、分析与VM输入，不表示实际声卡/音乐平台全覆盖，也不表示整个样本官方一致。361的layer435仍有`getTextureAnimation`接收null异常，作为独立脚本断点保持队列 |

早期`runtime-final-*`、`runtime-reviewed-*`和`runtime-accepted-original`分别绑定早期App，不能替代最终身份；最终运行在入口顺序修正后重做。7模块39项CPU回归通过（`cpu/tests-final-receipt.json`记录分阶段身份及未变测试复用），覆盖实际编译器、属性publisher→consumer、原/clone各自alpha、旧builtin健康及拒绝后回退；提交前独立复核按冻结差异与证据裁决。下一步优先user color/多source公共缺口；named实际染色及HDR剩余显示问题保持现役优先队列。当前完成的是两个Alpha候选的有界实际链路，不是两样本完整正确率。

本片停止使用的隔离输入、baseline App与重复截图已清理；保留约22MiB日志/报告/生成与身份收据、6张必要PNG，详见`artifact-retention.json`。连续迭代仍只沿用上述唯一build缓存；未知归属目录未动。


## 后继修正：混合用户颜色接入既有Vec3 owner

本片基线`132ac30d`。在余项中比较mixed user color、多source与Power=.99：前者缺接线但已有完整Vec3合同；多source需多prototype identity，Power非1不能假装普通tint，保留下一片。真实3665307769的材质color同时含user、script和scriptproperties，旧proof拒绝整个材质，颜色显示及热切均不正确。扩同prepared事实和现属性编译器，outer color成为唯一materialConstant的借用输入，内层ifchange复用统一typed path的scriptInstanceProperty producer/consumer。用户色与脚本返回合并、undefined处理均沿原effect Vec3机制，未新增VM、优先级算法、pass或值缓存；内层publisher缺失先拒绝proof，旧Alpha回退保留。颜色仍采用既有有限Vec3及compositor范围规则。

公开[update文档](https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/update.html)规定输入为当前属性值，无返回不修改；本次没有据此宣称全部官方user/script热切顺序。证据根`/private/tmp/mwx-material-user-color-20261008`，最终正常签名Debug App SHA`b84454d85483d5eaf7b2974492afd31401ddd7bf3fd3e191b42b347502aebc2c`，构建及7产品文件身份见`build-nested.log`/`built-product.json`。受控包仅替换scene几何与init，原材质、project、mixed脚本bytes不变（117条目中的116条不变）；原/clone各有非白layer色、alpha=.5。没有把真实mixed改成pure user输入来制造通过。

| 输入与运行 | 实际结果及边界 |
|---|---|
| `runtime-baseline-false-hot`，旧App`0475f8fd…755c` | 关闭彩虹后热切用户色被拒，原/clone均RGB(64,32,96)，材质色未消费 |
| `runtime-final-false-hot`，最终App | 用户色(.4,.8,.2)→(.8,.4,.6)，两块RGB(26,26,19)→(51,13,57)，共享材质与各自layer style一次相乘，窗口不重建 |
| `runtime-final-true-to-false`，最终App | 只改ifchange开关，不改用户色，原/clone从彩虹输出回到RGB(26,26,19)；没有停留旧脚本结果 |
| `runtime-final-true-hot`，最终App | 彩虹开启时只改用户色，现script返回继续优先，保持动态彩虹；没有让用户输入覆盖脚本返回 |
| `runtime-final-original`，完整366原PKG SHA`e720c8e15967aab51f75f721d49785b5d654e405f090390ababa99e141e430eb` | 原包彩虹材质实际VM→63动态bar encode/GPU完成。Debug PCM为测试输入，不代表真实音乐来源或全部视觉一致 |
| `runtime-original-false-hot`，同原PKG/最终App | **FAIL保留**：同key newproperty3还绑定layer146.visible，color→Bool类型冲突使整次颜色热切拒绝。受控通过不能代替该原包控件验收；官方混合类型合同待研究，未放宽事务或悄悄跳过consumer |

原包还保留374.visibility、386.origin的scale undefined/null和386.alpha的getTextureAnimation null异常；这些不是材质color接线成功的反证，也不能从全样本队列删除。当前收益为默认彩虹频谱与通用mixed材质接线；整个366仍未完成。下一步先裁决颜色跨类型绑定，再比较同model多source、named合成和HDR余项，不能因局部有界通过把原包热切标成已修。

8模块70项CPU/QuickJS方法的最近结果全部通过，含原Alpha回归；`cpu/tests-final-receipt.json`保留分阶段测试文件与产品SHA。首轮fixture不可变字段及重复source-list接线错误已修，仅重跑受影响门，未作为产品失败或伪报首轮全绿。独立产品复核未见P1/P2；最终证据另按冻结身份复核。

本片停止使用的输入副本和重复截图已清理，保留约24.0MiB报告/日志、输入生成与身份收据及9张必要PNG；`artifact-retention.json`登记范围。继续只沿用一份既有build缓存，未动未知归属产物。

## 后继修正：颜色与显隐错配局部保留

基线`8086c122`。两个原包均复现颜色控件被拒：366的`newproperty3`与3078285611的`newproperty8`既绑定合法颜色消费者，又绑定layer.visible。旧启动resolver把颜色字符串写入Bool fallback，typed编译则将整个key列为重建。现复用一条准备期绑定判定：唯一color定义、无condition的直连layerVisibility、合法ID及Bool fallback，启动保留Bool，编译记录`ignoredIncompatibleVisibility`并仅忽略这一不相容输入。合法颜色publisher、独立显隐脚本、snapshot优先级、所有消费者就绪及非法更新原子保旧均沿原owner；未增加渲染算法、VM、frame检查或样本分支。

证据根`/private/tmp/mwx-color-visibility-20261008`。官方2.8.0.42/SHA`daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`，自有true/false × 有/无无返回visible脚本 × 四色CLI热切共16阶段、32最终捕获：A颜色变化，B始终保留对应Bool，有脚本时回调也收到该Bool。ROI与重复捕获差0，预定容差2；`official/behavior-contract.json` SHA`473ce63c7f2d03b39ea6940652bf7eed6ff9a6fd3f7fae97738c0a6ad382793f`已独立clean-room审查。未访问私有实现；GUI、slider、缺定义、其他Bool target、有效脚本返回优先级未由该实验定义。研究窗口/guest目录已清理，VM恢复原suspended状态。

只读243样本的project与scene条目SHA均与当前census相同；直接layer.visible的非Bool/缺失类型引用共27样本48处，分为color 2处、slider 4处、缺定义40处及有声明但无type的2处（`census.json`）。仅color两处属于本批已证修复，不能将全部声明算作故障或受益量。

正常签名Debug构建通过，最终App SHA`729ba7279f1b5e208197eeb26ca035e9a435dbdaa4ff3b81639920cf7f8751a6`；四产品源身份见`built-product.json`。原始媒体只读，运行使用精确复制的PKG/project。输入颜色均从(.4,.8,.2)热切到(.8,.4,.6)：

| 运行 | 实际结果及边界 |
|---|---|
| `runtime-baseline-307`，旧App b84454d8 | accepted=false，同window343011；背景主色前后均RGB(102,204,51) |
| `runtime-final-307` | accepted=true，同window343024；背景从RGB(102,204,51)变为(204,102,153)。整体benchmark仍FAIL：layer192/effect2的optional named fallback未证及graph join失败；layer60的三处speed脚本仍有toPrimitive异常，均留队列 |
| `runtime-final-366` | 关闭彩虹时原包颜色accepted=true，同window343037；频谱柱从RGB(102,204,51)变为(204,102,153)，对应捕获精确色像素6560→10563，旧色不残留。benchmark PASS仅为这组运行门；374.visibility、386.origin及386.alpha的三处旧异常仍在 |

本片完成两个已证颜色显隐错配输入的准备→热切→实际画面链。Debug PCM为测试音源，不代表真实媒体平台、整样本视觉或全243兼容验收。下一片继续定位366剩余lookup/纹理动画脚本入口，并按全样本同类声明归并；源材质多source/named组合、HDR余项及其他特效缺口继续按共享职责排队。

6模块89项CPU/QuickJS方法的最近结果通过，覆盖启动Bool保留、实际compiler→live合法颜色链、无真实消费者仍拒绝、错误输入/不可用sibling/批量事务保旧，以及原Bool VM与snapshot回归；阶段日志保留fixture编译与no-op revision期待修正，不伪报首轮全绿。产品独立审查未见阻断，最终收据绑定代码、App、像素和原包未关闭问题。停止使用的输入副本和重复PNG清理，保留六张原生必要捕获及官方小型黑盒证据、日志/生成脚本/身份收据；`artifact-retention.json`记录去留。构建只沿用现有唯一缓存，不动其他任务产物。


## 后继归因：原包遗留断引用

在`d8d642d2`继续追踪上述366三处异常，未找到隐藏层lookup或资源准备缺陷。原包29层中`playerprogexception`唯一对应399；`playerbackgroundprogbarexception`与`playeroutlineanim`无声明；374的parent279没有parent。全包36份inline script没有生成这两个缺失名字：唯一材料脚本只产生HSV颜色，动态创建为bar及带null守卫的clone声明，后者引用的bar也缺失而提前返回。现C name lookup不按visible/provider过滤，descriptor与VM保留全部作者层。[公开getParent合同](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ILayer.html#getparent-ilayer)规定根层返回undefined，与374的祖父访问异常吻合。

证据`/private/tmp/mwx-scene-layer-lookup-20261008`：`reference-analysis.json`与`layer-metadata.json`保存作者输入；`prepare_probe.py`仅在隔离包386.origin.init首部插入自有诊断throw，117条目只有scene变化，还原该script后scene与原件相等。沿上一批最终App运行，`probe-receipt.json`记录实际lookup：progressName=playerprogexception、progressScale=0、backgroundMissing=true、outlineMissing=true、grandparentMissing=true；原生记录与独立只读包/脚本审查一致。这里不把diagnostic benchmark PASS当作无异常或官方视觉验收。

因此三条从疑似引擎lookup缺口改为作者断引用，保留局部脚本失败，不补假图层、不吞异常、不改真实媒体。完整媒体面板与官方画面仍未据此关闭；后续回到全样本公共纹理/合成首断点。运行停止后清理诊断输入、副本运行目录与无验收价值截图，保留原始日志、输入生成及SHA收据；产品代码无改动。

## 动态共享源与颜色范围后继

2026-10-10，T1有界完成。3601964477原包（PKG SHA `4959ac1c89fe3cfec7706d7eaf522894b7bd2ac7337e086e2861ff75897887ab`）层149因Power=.99不能neutral降低，完整源又拒动态声明；受控PCM下只有白柱。原neutral证明现同时给出输入接口与是否可降低，非中性静态Bright/Power沿既有完整Program求值；材质色/0–1 user Alpha沿原typed producer共享，旧compositor乘数退出。原层及63副本共用一份template与每帧一次源求值，各保自己的publication身份/尺寸，共用原submission pin。没有新增材质算法、纹理缓存或输出owner。

作者彩虹还因WEColor拒绝s=2.16/v=4.32报错。官方2.8.0.42自有12组有限HSV黑盒确认可返回负数/HDR（例如h=.25返回[-.3456,4.32,-5.0112]）；只删除s/v的0–1拒绝，原算法与typed非有限拒绝保持。另以自有不透明/半透明/半透明后接identity effect三卡核对源输出：官方无宿主style引用的shader不在外部再乘layer色/Alpha，改三层为白/1仍全图完全相同。因此完成的materialSource统一中和外部style，不改raw源及neutral降低；直接、源替换和模型named采集共用转换。曾遗漏DrawRequest转存identity导致直接两卡变暗，已修并重新构建/运行。

最终隔离Debug dylib SHA `142433aa5b4c48a901b9b52377dc962c393a6f4912939ae01f00a01261dfd284`，`build-candidate.json`绑定全部Scene源与App；隔离树Web基线较旧，不声称完整HEAD构建或发布验收。约21MB验收包`.artifacts/tmp/source-power-20261010/retained-evidence.zip`保存输入/源码身份、官方自有输入、关键截图与失败收据；正式提取因证据库总预算满而失败，prune无可清包，未抬预算/删除他人材料，后继腾出预算再提取。该目录另留复用构建脚本及小收据；已退出的临时HOME/样本副本/生成shader与重复截图清理，单份`.build-cache/solid-source-domains-recovery-20261009`供后继复用。只读原包，受控音频不是外部播放器验收。

| 实际输入/输出 | 验证结果与边界 |
|---|---|
| 原360 `final-pcm` / `final-alpha-hot` | 彩色频谱恢复，frame0=1、frame1=64消费者共用源。Alpha .5→0→1画面变淡→消失→恢复，三次accepted、同window9478及1surface，无重建；VM31/31静默、GPU排空。 |
| 官方三卡与 `final-three-card` | 80×80中心ROI native [51,59,85]/[34,68,126]/[34,68,126]，官方[50,59,86]/[34,68,126]/[34,68,126]，各max差1/0/0。只证此输入，非整幅/所有材质parity。 |
| 自有 `final-shared-clones` | 原层隐藏，两clone尺寸24/16像素、同材质纹理；4秒销毁左层、8秒销毁右层，画面2→1→0，无残留；单源encode consumers=2，VM1/1、dynamicLayers0、GPU排空。未注入GPU失败/取消。 |
| 健康3609108600 / 3690859128原包 | 同最终App仍有彩色频谱；前者VM5/5、后者VM12/12，均退出GPU排空。用于保护既有中性降低，非新增修复样本或完整parity。 |
| CPU与原publication/GPU门 | 32唯一CPU用例（含真实DrawRequest身份透传；去掉透传后4断言失败）；实际publication与source uniform GPU各1门，含外来layer身份/陈旧epoch拒绝、raw源保持样式及非有限HSV/下一帧恢复。生命周期原资源owner复用，静态审查不能冒充故障注入。 |

边界：其他source层320/323/328仍`render-state-unsupported`，媒体黑色占位与完整交互、整样本官方视觉未闭；0–1之外Alpha、perspective、multi-pass/provider、首作者引用销毁后的官方续跑合同继续开放。360整样本仅粗估约85%，非统计正确率；本片共享颜色/Alpha/副本主链已实际进入最终显示。失败尝试（sampler purpose拒绝、松散fixture缓存不可用、identity丢失）保留诊断收据，均不计通过。后继顺序归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

结构门6/8通过；已有HEAD的Web `DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift` 1008行及未知归属Scene `.mimosa`残留使两个全局门失败，均保留、不算本片通过。文档健康通过；全库导航仍有两个并行Web设计缺少入口反链，Scene本片链接无新增失败。ProviderBinding fixture已补入原验证映射，不增runner。
