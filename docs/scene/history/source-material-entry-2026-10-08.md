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
