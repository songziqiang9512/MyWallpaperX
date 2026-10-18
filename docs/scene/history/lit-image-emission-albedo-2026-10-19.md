<!-- document-role: historical-evidence -->
# 2D lit image emission 的原图基色

> **历史证据 — 非现役入口**。截止2026-10-19。当前策略归[F3 emission合同](../roadmap/batch2/2d-lighting-material-design.md#lit-image-emission-albedo)，运行摘要归[当前证据](../capabilities/runtime-evidence-current.md#lit-image-emission-albedo-20261019)，343的Earth光影、间歇闪烁与collision余项归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。本批不关闭整样本或声明官方parity。

旧2D emission将alpha coverage当作每通道发光颜色，忽略原图RGB。此次仅在原`SceneLitImageLayer.metal`消费点把`sceneLitStoredTerm`的coveredColor由`color.a`改为已PMA的`color[channel]`；沿原七因素稳定乘积一次消费coverage、tint与opacity，保HDR有限结果和65504存储约束。straight association仍在原采样入口；direct/specular/reflection、最终alpha、map准入、资源与ABI均未扩展。

旧GPU门在黑基色、正mask/color/brightness且无灯时实际输出`(.2509765625,.501953125,1.00390625,1)`，旧oracle仍PASS，故旧通过不能证明基色语义正确。首次运行因共享`SceneImageLayerUniformValues`缺现役`Float? brightness`而编译ERROR，无产品结论；仅在原共享fixture补默认nil字段，保失败日志，修载体后旧22 vectors/27 contracts PASS（12.015s），未改旧shader或语义输入。

新门25 vectors/29 contracts一次PASS（12.361s），源无漂移。同alpha .5的黑/暗橙/白分别为RGB零、`(.125,.03125,.0078125)`、`(.5,.5,.5)`；保coverage/tint/opacity、straight/PMA与零alpha、HDR大值乘小coverage，以及mask0/brightness0/noheader/invalid反例，容差未放宽。原BC/atlas/sampler/provider检查改白carrier以维持mask采样原意；App oracle由实际128灰底与effect .5推导。独立静态审查GO只覆盖冻结五文件diff，不冒充App画面审查。

一次普通Debug从固定HEAD `75adb705145f6a092b7d1fb93d199945fa7b3f62`叠加唯一MSL `f387d0018fde549ac5b9303e5db4030bd47cdf334f87c7441fab6b26ad1baa6b`构建；4312输入无漂移、16.464s、严格签名0。最终App executable `eceb7e2628422b0e9191557d51ae4630f119ee1128502edf8c51ac97d41e8cd8`，debug dylib `f988a9f3559bc4e121e7b05391035c09cbb42d5edcd7c2b55733847a7671a3f8`。仅该固定产品闭包供后续实图，不吸入共享树中的其他Swift修改。

原343修后原生背板3024×1964短播exit0/FAIL[]，输入与App无漂移。根与独立审查实际看图确认银河由白恢复橙调、暗部回落；Earth白热点与暗侧问题仍在，不能把genericimage2/4的基色修正外推到generic4表面或关闭343。此前原包/仅Cloud114隐藏两臂也各exit0/FAIL[]，白热点均在，说明Cloud并非该热点必要条件；隐藏同时移除自身颜色、coverage与depth，不是只改颜色的BRDF实验，也未证某一灯或Chroma字段就是根因。配置sceneTime/wallDate没有冻结作者私有逐帧状态和VM `new Date()`，实际文字时间仍推进，故不作官方同phase或精确RGB对照。

官方2.8.0.42三色2D资格在保持输入哈希的传输/路径纠正后取得全黑图，白带正控未成立，按预登记STOP_UNKNOWN。保首传输失败、修正与原图，不把全黑认作基色依赖确认或反例，也不把旧3D研究升级为2D官方对照。

真正未参与修法的366 Sun-4以原model/material/albedo/slot2四份字节组成隔离presentation，原color/brightness/alpha与emission bit8保留；只固定摆放、移除parent/shared位置脚本与godrays，零灯/ambient/sky、关闭Bloom/HDR。源/副本逐项SHA与PKG VFS匹配。修前/修后各一次exit0/FAIL[]、输入/App无漂移，实际PNG均3024×1964；before曾配置无consumer的windowed环境名，未改变实际窗口，after移除该无效配置，保更正而未重跑。根与独立审查实看蓝色星芒主体/位置仍在，中心略暗/窄，外围额外发光下降；中心RGB `(97,125,158)→(94,121,153)`仅为SDR描述，不作物理HDR或官方像素验收。366完整冷准备失败与球体/曲率/交互旧余项仍保留，不把隔离资产认作整包ready。

2815826216完整原包仅作无emission的健康相邻，908×590短窗exit0/FAIL[]、原输入/App无漂移，根与独立审查看到黑发人物、红底与日期时钟；target20 effect后继到GPU和末合成，正常stop1→0且GPU排空。文字越右图缘，只有candidate after、无旧App配对或官方截图，未定是否新裁切，不认外观不变、完整布局/交互或parity。以上三类PNG度量未完全锁作者phase，只支持描述性观察。App integration首轮无灯emission、animated map两项PASS；effect方法先在旧metal/direct子场景得到ROI零而FAIL，尚未执行emission-effect。定位为共享`run_normal`载体旧灯类型`lpoint`仅适用于模型，现2D typed filter早已要求`point`；纠正该一行后MR约95、旧预期41.472仍FAIL。继而核明共享`pbr_expected`仍用3D距离且缺2D强度1.85，与[先存10-06合同](2d-lit-image-light-contract-2026-10-06.md)不符；仅迁移oracle两行为XY falloff与1.85，独立算得94.72，不按实际95拟合。BRDF、输入参数、容差2与断言均不改。产品未因这些失败追加修改；原两PASS和两次旧夹具FAIL照保，最终仅重跑受影响effect方法的MR/emission两次App调用，1/1 PASS（30.838s）、源无漂移；原先两PASS不重复。独立审查确认两项共享fixture迁移均符合先存合同，未把静态审查冒充这次执行。

普通14天正式包已提升：`.artifacts/scene-evidence/runs/lit-image-emission-before-20261019/`保原343与Sun-before，`lit-image-emission-after-20261019/`保原343-after、Sun-after与281相邻，`model-cloud-isolation-20261019/`保Cloud-off；各label有report及一份实际after PNG/日志，合计约21.96/22.41/14.89MB，不把选择包的`passed=null`改成整样本通过。原始失败、GPU/构建/独审及输入身份另保本机`.artifacts/tmp/343-model-lighting-20261019/`的`emission-gpu-before/`、`emission-gpu-before-fixed-fixture/`、`emission-gpu-after/`、`build-reviewed/receipt.json`、`independent-static-review.json`、`cloud-isolation-result.json`、`emission-official/final-result.json`、`heldout-sun-input/source-receipt.json`、`sun-transport-receipt.json`、`visual-result-summary.json`、`independent-visual-review.json`及三轮`app-integrations*`；实际PNG/日志以正式包为准。

精确清理已逐项核验三包30文件SHA，6例`result.json`无损压缩为`result.json.gz`；仅删已停止的各例results/runtime及retained重复副本13目录，共729777421B（695.97MiB）。candidate App、唯一共享DD与下一批arms/roughness输入保留，正式包未改；范围见`cleanup-emission-receipt.json`。本记录不认CPU/GPU、内存、启动或能耗收益。
