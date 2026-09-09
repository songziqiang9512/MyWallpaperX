# Scene authored sample debug ledger

> 这是一份可复查的运行首断点档案，不是视觉通过矩阵。样本根只读，档案只记录 authored corpus 的 identity、运行状态和可定位证据；最终“正确显示和播放”仍须逐样本人工/ROI 验收。

## 2026-09-09 current handoff rerun

为把工作树代码、运行身份和现役队列对齐，使用当前工作树构建的 Developer ID Debug App（2.0.9 (277)，Team `H9QWU9XN8R`，CDHash `7ce6a2fff1b12f8771c4fc768f9a2f204107e1c1`，executable SHA-256 `6edd66b54bbf6486560efe92e270a8bba616faf0b5619c6b9c504bf01c3570e5`）串行复跑 12 个断点样本。matrix SHA-256 为 `fd5f7fd4b52729115cd6f5e6120e80fc3a5dc8992237804f08ec1ed311b7d745`，总 report SHA-256 为 `0104f3fec84c489bc8645e0163d1c9294d959cf8a89f3a62b61c3e2efa6109e6`，现场目录为 `/private/tmp/mwx-handoff-current-runtime-20260909-1945`。

结构/执行门结果为 **5/12 strict PASS**：`3662790108`、`3768020435`、`3749463715`、`3754639143`、`3782740481`；**7/12 NON-PASS**：`2959875782`（只剩 layer 813 visibility/Puppet owner）、`3448845950`（dependency-stage、B3 attachment、owner-revoked）、`3792249095`（layer 254 degraded source passthrough）、`3665307769`（layer 412 B3 passthrough，CPU p95 34.535 ms）、`2775915974`（identity-only probe 未取得 required graph execution）、`3775355045`、`3775373546`（首帧 `layer-source-not-ready` 观察诊断，后继帧已恢复）。所有样本 loaded ratio 为 1.000，ready/after 截图均非黑；这些结果只证明结构/生命周期边界，不改变 159 样本的视觉裁决。

其中 B1 的三个命中样本均有完整 GPU/compositor/next-frame 证据，可把该公共编译首断点标为结构闭合；B2 代表的 aggregate/provider publication 在 `2959875782` 仍成立，缺口已从 dependency binding 拆到 B9。B8 两例分别在 frame 12/10 后恢复同一 Program 和唯一 compositor，但严格观察门仍保留 FAIL。该段是当前版本后继证据，旧 2026-09-08 archive 与验收生成页不被覆盖；生成器刷新前必须同时注明时间差。

当前代码集群已经提交为 `fdf430b7`、`82ef0133`、`1626ce42`、`14fe586c`、`50d2a2be`；本页记录的是这些提交构建出的 12 样本结构/执行复跑，不能把 `5/12` strict PASS 解释成视觉通过。视觉完成仍以 159 样本台账的 `0 pass / 19 fail / 140 unreviewed` 为准。

### 2026-09-10 B5 最终首断点

最终签名包复跑 `3448845950` 仍 NON-PASS：反向 varying 与 float→int 编译拒绝已消失，accumulation compiler artifact accepted；node 2 combine 现在拒绝于 terminal data/color 合同。三处 dependency-stage 保留，B3 八个 uniform 执行保持。此数据层必须经 typed provider publication 交给 layer 322，而非冒充 premultiplied compositor 颜色。最终 App/report/hash、正反门和下一组 owner 见 [B5 证据](runtime-evidence-current.md#e-2026-09-10-b5-feedback-frontend)。

### 2026-09-10 B3 颜色输入修复后继

`3448845950` 四层八个 scripted Color uniform 已完成 VM、frame 0/1 material 消费、GPU/publication/compositor/next-frame；整体仍 NON-PASS，当前 residual 为三处 dependency-stage、B5 terminal data/color 与 207/322/416/524 exact graph 缺口。`3665307769` layer 412 的同源 attachment 消失，9/9 graph layer 完整、72/72 GraphExecutor、55/55 transaction，**strict PASS**；CPU p95 35.667ms，视觉与性能仍未通过。App identity、复现参数、逐报告 hash 与边界统一见 [B3 当前证据](runtime-evidence-current.md#e-2026-09-10-b3-property-vector-input)。旧 12 样本总报告不覆盖；159 个视觉裁决未重生成。

### 用户可见失败待办（按当前复现更新，不以公共修复代替逐项验收）

以下均以真实播放截图/事件恢复正常为验收，不以历史 probe 状态覆盖用户反馈。每项修复须补共享首断点及 next-frame/event 证据。

| 样本 | 待修复的用户可见问题 | 首轮区分证据 | 状态 |
|---|---|---|---|
| 3264246690 | 人物偏上、头部出画；左肘缺块 | 当前截图头部在画内、左肘缺块仍在；不能据此判定构图正确 | 未通过 |
| 3765760121 | 上下颠倒 | utility model/投影策略不一致已修；默认鱼眼开启的当前截图恢复正向，见 E-V4-UTILITY-CAMERA-CONSISTENCY | 倒置修复，整样本未全面验收 |
| 3780119725 | 人物压缩/缺块、脸部疑似遮罩线外露 | fallback extent 与 fractional additive selector 已修；当前运行已选中 7 个动画片段且人物不再压缩，脸部黑线/缺块仍在 | 部分修复，未通过 |
| 1315486372 | 水波位置不正确、光线贴图效果生硬 | 已留当前播放截图，effect-local 坐标与辅助纹理仍待定位 | 未通过 |
| 2775915974 | 鼠标纵向响应反向；顶部边缘失去识别并回中 | 两个公共输入错误已修并有实际鼠标事件/截图；当前 identity-only 复跑仍未取得 required graph execution，顶部极限露灰边仍未解决，见下方 anchor | 输入修复，整样本未通过 |
| 3747492842 | 文字错位、额外闪烁、光束应在顶部却在中间 | 静态文字已部分修复；音频静音/真实输入及 quad 几何分开检查 | 未通过 |
| 3470948192 | 开场/文字错位、后续 NaN 与异常背景 | 日期和初始字形已部分修复；共享坐标 producer→consumer | 未通过 |
| 3509243656 | 开场/模拟画面不正常、坐标文字异常 | 延长播放及 MAIN producer→共享状态→文字 | 未通过 |
| 3788734811 | 画面上下反转 | 正交画布的perspective image保留Y-down卡片方向；新截图恢复正向，见E-V4-CANVAS-PERSPECTIVE-CARD | 倒置修复，整体视觉等价未验收 |
| 3238423642 | 人物头部错位 | Puppet atlas重组预算被前序图层耗尽，最后一层退回原图集；按候选层均衡预算后头部回到身体，见E-V4-PUPPET-BUDGET-FAIRNESS | 构图修复，整体验收未通过 |
| 3448845950 | 无法运行 | PNG被TEX metadata误判为MP4与solid准备尺寸不一致已修复，恢复蓝色卡片/时钟；09-10 已清除四层 B3 attachment，仍见 dependency-stage 与 layer 1475 terminal data/color 合同拒绝，脚本效果及整体布局仍未通过，见E-V4-TEX-MEDIA-IDENTITY | 黑屏解除，结构部分恢复，整体验收未通过 |
| 3477054430 | 画面显示不全 | 当前播放有CPU invocation failure及effect-local passthrough，待精确定位缺失区域 | 已运行，未通过 |
| 3662790108 | 启动卡在不正确的画面 | 当前复跑 35/35 active effect、81/81 GraphExecutor 严格结构 PASS；8 个 geodraw2_1 仍走 boundedSwift，启动约48.09秒、7.49 FPS，球体/曲率/交互与视觉仍未验收 | 结构通过，视觉/性能未通过 |
| 3287715210 | 音频条不显示 | 颜色合同中的已验证加法混合与replacement coverage已接通，PCM截图恢复底部变化的音频条，见E-V4-AUDIO-REPLACEMENT-COVERAGE | 有界修复，真实系统音频/整体验收未完成 |

## 2026-09-08 current corpus probe（archive snapshot）

以下内容保留 09-08 静态/隔离 probe 的原始时间边界；它不会覆盖上面的 09-09 handoff rerun。

权威样本根是 `/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Scene`。本次静态 census 发现 **159** 个 numeric sample，`159/159` 的 project、PKGV 和入口 JSON 可解析；sample-id manifest SHA-256 为 `dce37464a0d15c860e3bd8566784f227419d4b2f5e9f4e7f053e38139d760776`。对应的静态快照是 [`scene_capability_census_snapshot.json`](../../../script/scene_capability_census_snapshot.json)（SHA-256 `0346d55c384f90d4931984098e2fd5f01bba18849f952beac9049153747b8351`），摘要清单见[`全样本能力分类与修复台账`](scene-corpus-capability-inventory.md)。

四个隔离分片使用同一签名 Developer ID Debug executable（bundle `com.songziqiang.MyWallpaperX`，version `2.0.9 (277)`，Team `H9QWU9XN8R`，CDHash `610ab437185c4104392b30227afbea3744129ea0`，executable SHA-256 `10951960b67fd3a635f96846886d0829fb3aa6de68c5c771913cc0109d22e247`）。每个样本从只读根复制到独立 runtime root，运行时长 7 秒；该 probe 使用 identity-only matrix，因此没有把历史视觉期待误当成成功条件。四份 report 的 SHA-256 分别为：

| 分片 | 样本数 | report SHA-256 |
|---|---:|---|
| `mwx-v4-authored-sample-audit-part-1-of-4` | 40 | `0737c581457c452d5475b6579bffffe7103cf7820eacfc3dd02f29a8a2604019` |
| `mwx-v4-authored-sample-audit-part-2-of-4` | 40 | `5d31482e6f3e6d39ad7e9a3711fa5a343074425c7a943f2e99c6708939b076d2` |
| `mwx-v4-authored-sample-audit-part-3-of-4` | 40 | `f8fb14de3ae911c55e67f220a90d77b237ef0ba2c4e96ea1b053c0ea28c65075` |
| `mwx-v4-authored-sample-audit-part-4-of-4` | 39 | `e10934d7e2d116d66a7b6d9a70bd28c8d116349a87ca05101ea8a69cc3831751` |

机器可查询的合并档案是 [`scene_sample_debug_archive.json`](../../../script/scene_sample_debug_archive.json)（SHA-256 `36e8d7b1662414c73972742e4fb91e4afd14c48d1fed57f4af5dacf26b19268a`）。它覆盖 `159/159` 个样本，状态为 `117 structural-chain-complete-visual-review`、`37 degraded-runtime`、`5 blocked`。这些状态只描述运行安全和首断点，`structural-chain-complete-visual-review` 仍要求 authored preview/ROI 与 next-frame 视觉复核，不能写成“正确显示”。首断点计数为：

- `effect-admission:admitted-fallback` 12；`effect-admission:unified-capability-unavailable` 9。
- `resource-load:particle-layer-load-incomplete` 9；`resource-load:base-image-texture-load-incomplete` 3。
- `graph-execution:graph-execution-missing` 2。
- `script-execution:scene-script-exception-range-error` 3；`script-execution:scene-script-exception-type-error` 2。
- 另有 1 个 dynamic-uniform binding passthrough 和 1 个 material-pass preparation/library compilation passthrough。

五个需要先回到公共 owner 的 blocked 样本是 `2824109832`（effect admission 后仍有未认领 visible effect）、`3448845950`（GraphExecutor 缺失多层且无 terminal/next-frame）、`3470948192`（terminal flat-preview divergence）、`3775355045` 和 `3775373546`（layer 22 的 GraphExecutor execution missing）。`3509243656`、`3610154602`、`3612199597` 等真实样本还记录了 SceneScript typed exception；这说明“脚本路径更好”不能由全量 probe 推断。

本档案的生成器是 [`scene_sample_debug_archive.py`](../../../script/scene_sample_debug_archive.py)，测试为 [`test_scene_sample_debug_archive.py`](../../../script/tests/test_scene_sample_debug_archive.py)。它只合并样本静态事实与现有 report/diagnostic first breakpoint，不保存样本副本、截图或作者 payload；`/private/tmp` report 路径是 provenance，缓存消失后不能用本页代替重新运行。

截至 2026-09-09，shine-cast 样本 `3749463715` 的最新公共首断点已从 layer `467#effect#480` 的 Metal vector2 library compilation 收窄到同层 `467#effect#500` motionblur 的 `captured-main-color-contract-unproven`；layer `536` 的 default-boundary graph ingress 与两个 effect 的 frame0/next-frame 已有独立证据。后续开发从 [E-P1-VECTOR2-INTERFACE-ARITHMETIC](#e-p1-vector2-interface-arithmetic) 读取最新状态，再进入颜色合同 owner；不要回到旧的 `mwx-graphfix-run` 报告把已跨过的 float3/float2 编译错误当成当前首断点。

## E-V4-PUPPET-FRACTIONAL-ADDITIVE：动画权重进入 selector（2026-09-08）

`3780119725` 的 authored layer21 含 blend `0.63` 与 `0.19` 的可见 additive animation。旧 selector 只接受 `blend == 1`，在真实 producer→selector→evaluator 链上提前拒绝该层组合；现改为接受有限 `0 < blend <= 1`，保留 blendIn/blendOut、rate、visibility 与 unknown-animation 的硬边界，evaluator 继续按权重叠加。41 个 puppet animation/mesh tests（2 个环境跳过）通过；隔离异步运行日志显示 layer21 选中 7 个片段、GPU completion/compositor publication/next-frame 成立，人物不再压缩。脸部黑线与缺块仍存在，尚未证明 mesh UV、mask/effect 或 authored 内容等后续 owner 正确。

补充的最小网格观测：该样本 MDLV0023 layer21 网格为 13,782 顶点，UV 约为 `0.014..1.0025`；同目录其他 MDLV0023 Puppet 资产观测范围约为 `-0.0045..1.005`。这排除了“UV 全局解析成异常范围”作为当前黑线首断点，但不排除 atlas 边缘采样、重组后 logical extent 与 mask/effect 坐标不一致。

当前 after 截图显示黑线直接叠在人物面部、躯干及右下枝条区域，而 authored 参考截图没有同样的整段黑色笔画；这使“重组 source 已含黑线”与“后续 opacity/shake/waterwaves/foliagesway mask/effect 错误消费 source”仍需隔离，尚不能关闭任一 owner。下一次实验应只比较重组 source 的 publication 与 effect graph consumer，不通过关闭作者效果来伪造验收。

`f03b8125` 之后的隔离运行终于取得 source-stage 证据：layer21 publication 为物理纹理 `1804×4096`、logical extent `3874×8793.740`、generation `20`；同一运行的 authored layer 仍是 `3874×2000`，而正常 Puppet layer794 为 `555×310` logical `554.799×310`。这证明当前 Puppet coverage 被直接当作 source logical extent 发布，导致 Puppet layer21 的 source geometry/effect extent 与 authored 尺寸显著不一致；但尚未证明应把 effect extent 改回 authored 尺寸，因 model placement 仍需要 coverage 防止缺块。下一步应拆分 coverage（model geometry）与 effect logical extent 两个职责，先补正反测试再改 owner。

`95721137` 已完成该职责拆分：Puppet publication 保留 coverage logical size 给 model，另以 authored layer size 发布 effect logical extent；effect preflight/desired-size 使用后者。隔离运行 `/private/tmp/mwx-async-text.qmTbKj/3780119725/extent-split-run` 的 after 截图显示人物不再压缩，脸部/躯干黑色线条消失，构图恢复到 authored 参考的主要形态；layer21 的 6 个 graph effect 均 `outcome=succeeded`、`gpuCompletion=completed`，其输入由原先 `902×2048` 变为 authored-ratio 的 `2048×1057`。benchmark 仍因样本另一条 effect-local passthrough/CPU invocation 失败而整体 FAIL，故本条只证明 Puppet extent 首断点修复，不宣称整样本通过。

该剩余失败的首断点已进一步明确：layer380 的 authored workshop `Simple_Audio_Bars` shader 在准备阶段被 frontend owner 拒绝，日志为 `shaderFrontendFailed` / `compiler-tool-stage-link-rejected-exitcode--2` / `bounded-frontend-owner-revoked` / `compatibility-target-not-applicable`；随后唯一 graph owner 以 `visual-failure-passthrough` 发布安全输出。它不是 Puppet 或 publication 生命周期失败，也不能通过把 passthrough 改成成功来验收。下一项应针对 generic shader frontend 对该类 audio-array material 的公共兼容合同，保留失败半径局部化。

`5102d41b`/`0d189142` 的 diagnostic build 已在真实隔离运行中验证：stage-link diagnostic 只返回 helper 临时 workspace 路径（`/var/folders/...`），没有语义错误文本；因此当前证据不足以安全修改 audio-array lowering 或 stage wrapper。该观测本身证明 failure payload 仍不充分，下一步应改为保留 bounded normalized-source digest 与 helper invocation metadata，而不是猜测 shader 语义。

## E-V4-PUPPET-FALLBACK-PUBLICATION：重组成功与可缓存资格分离（2026-09-08）

`3780119725` 人物 layer21 的重组覆盖范围为 3874×6279，上传纹理为 2527×4096，但作者 atlas/layer 声明为 3874×2000。动画 layer1221 不在当前 bounded profile，已有逻辑成功生成 bind-pose fallback。首断点在 `SceneMetalView`：只有可缓存的静态重组或 active playback 才调用 `setPuppetSource`；这个有动画声明却降级为 bind-pose 的结果没有 cache identity，被错误送进 base atlas publication，旧高度继续驱动 model/effect source。现在只以成功重组返回的 coverage 决定既有 Puppet source publication，不再以 cache/playback 资格为门；缓存复用条件不变，解析、重组与 budget 全部仍在 load。

这是现有 provider 的纹理/逻辑尺寸提交修复，不是扩展 Puppet 动画或 V5。`setPuppetSource` 仍是唯一 source identity/generation/extent owner，普通 base atlas、重组失败 fallback、安全预算和 invalidation 未改。主链：authored mesh/atlas → prepared bind-pose texture + coverage → source publication → typed frame source/model → existing graph → Metal/compositor。

验证：Puppet mesh/playback 27 tests 中 26 PASS、1 个历史隔离资产 attachment 检查因资产不可用 skip；新增源代码防回归检查禁止以静态缓存标志限制 coverage publication，现有 coverage 数学测试不冒充 GPU 证明。texture-candidate/source-update-transaction 13 tests PASS；checkpoint Debug build 成功。App CDHash `cd9197ea93670d18079de103630fa2c9d2d811f0`、Debug dylib SHA-256 `0830c5fa91484e932885d34c464d94d4900197b8b9fbc3d3616cebc640bff1b4`。

隔离 runtime `/private/tmp/mwx-async-text.qmTbKj/3780119725/fallback-geometry-after`，异步 requestLaunch、默认属性、显式静音，14 秒/after11。after 截图 SHA-256 `c067443e7015c75022a063448a55d4ab5ff4608d03f9666129f85616e63d0925` 中人物恢复非压扁比例；相对前轮 `utility-camera-after`，layer21 graph input 2048×1057 变为 1263×2048，保持 coverage 比例。terminal effect6 frame0/1 均 succeeded、gpuCompletion=completed、compositorConsumed=true，publicationGeneration 38→89。**黑线、缺块、动画 layer1221 unsupported 仍在**；这只证明 fallback 几何正确送达，不证明 bind-pose 内容/动画完整或整样本正确。下一断点在 bind-pose mesh/atlas 重组和动画准入，不以遮掉黑线、删除图层或关闭作者效果验收。

## E-V4-UTILITY-CAMERA-CONSISTENCY：组合层资源准备与消费方向一致（2026-09-08）

`3765760121` 只有鱼眼组合层之前的图像倒置，后绘制日期仍正向。隔离 HOME 中关闭作者已有 `newproperty1` 可恢复方向，定位到该组合层而非图片解码、字体或 terminal output。首断点是 utility layer 保留了作者 `perspective=true`，现有 camera owner 的 `viewProjection(for:)` 却按 screen-space utility 策略选正交；preflight/source UV/model orientation 直接读 raw override，实际 utility draw 又强制正交，造成 capture UV 与输出朝向不一致。此问题不在鱼眼 shader，本批没有改 shader、资源、作者属性默认值或选择算法。

现有 camera frame 新增 `resolvesPerspective(for:)`，把既有 utility screen-space 策略与普通 image 的声明/default 决策一起提供给 model 和 projection。target-size reservation、source capture、普通绘制、utility 绘制、provider/fallback 和 cursor hit 的调用点统一消费该决策；没有新增 camera owner 或逐帧准备工作。普通 image 的显式 perspective 仍为 true。真正透视 utility 的语义/支持仍未证明，不能把本次纠正既有 screen-space 路径称为完整透视 utility 支持。

验证：`python3 -m unittest script.tests.test_scene_particle_camera_frame script.tests.test_scene_capture_geometry script.tests.test_scene_layer_cursor_geometry` 共 30 tests PASS；新增 utility raw-true 的 model/projection 一致性正例及普通 image raw-true 反例，保留 native/default/ortho、capture region、非法尺寸与命中投影门。checkpoint Debug build 成功，App CDHash `48a64bed37dd4d24fcbd151ace586707ec07ceb0`、Debug dylib SHA-256 `a2295044edc30cdc96a2c138b8e4715f73d6e858834ee123fba522d89516e9f2`。

本机 provenance `/private/tmp/mwx-async-text.qmTbKj/3765760121/`：`current/scene-after-window.png` SHA-256 `26397c34d53c71f4ed2133c1fff7c342510b6897d1eafc7e2df45ef25139106d` 为倒置负例；`no-fisheye/scene-after-window.png` SHA-256 `e79140bdb11dd179f4a827c05ab3be573b052b3fd754106e9998dc5db34e129c` 为关闭组合层的区分对照，不是验收。当前 `utility-camera-after` 使用隔离样本/HOME、异步 requestLaunch、显式 audio-silence、默认属性（鱼眼开启）、14 秒/after11。after 截图 SHA-256 `db38d7d8b0c592fdfed0c9ffb9f9738ba78b1dfd8939e354ac420000e0cbabdb` 中人物/背景与文字均正向，日期/时钟实时。layer96 原 Program `5b3e4a2321762b6b92fcb5b4ed3d314d0804717608829479d615d51578e0af51` 的 frame0/1 均 succeeded、gpuCompletion=completed、compositorConsumed=true，publicationGeneration 7→20；surfaceStop 时 VM owners6/quiescent6/failures0。主链仍是 authored utility/属性 → prepared graph/source geometry → typed frame/model → Metal → unique compositor/output。

结论只到默认样本的倒置修复，不是全部内容/音频/交互正确。相同构建重跑 `3780119725`、`3264246690`（各 13 秒/after10，目录均为 `utility-camera-after`）后，人物压缩/脸部黑线及左肘缺块仍存在，说明这些是独立首断点；不将它们算为回归通过。多屏、真实系统音频、透视 utility 和官方同输入像素对照未执行；完整样本验收仍开放。

## E-V4-POINTER-AXES-EDGE：实际鼠标纵向与顶部边界（2026-09-08）

两个首断点都在现有 owner 内：AppKit 的 Y-up normalized pointer 被 `SceneLayerParallax` 直接当作 Y-down world-frame offset，导致正交 Scene 的纵向与横向响应规则不一致；`SceneMetalView` 使用半开矩形 `contains`，将恰好位于顶部的实际屏幕位置判为 outside 并回中。现在在现有 surface event 类型中统一有限值、bounds origin 与闭边界采样，保留真实越界坐标给捕获拖拽；只在 parallax consumer 转换其 world Y 方向（与 world-frame resolver 的 orthoHeight 条件一致）。脚本/命中检测共享 pointer 不翻转，Y-up world、失败帧 rollback、outside fallback 和生命周期 owner 不变。无 sample dispatch、缓存重建或第二份 pointer state。

定向命令：`python3 -m unittest script.tests.test_scene_layer_parallax script.tests.test_scene_surface_pointer_event_buffer script.tests.test_scene_layer_cursor_geometry`，11 tests PASS；覆盖四角/顶部/非零 bounds origin、真正越界、NaN/空尺寸、FIFO/overflow/rollback、Y-down/Y-up/禁用/零深度与命中逆投影。checkpoint Debug build 成功。实际 App CDHash `9d2dc1cb5659be8c03dffede9e4dd9c96fe7008c`，Debug dylib SHA-256 `11e5ca621e13fb1e39c11f7a44b8f241e2d05200305a0d50cb20c749b1a5b688`。

本机证据仍在 `/private/tmp/mwx-async-text.qmTbKj/2775915974/`。隔离副本/HOME，真实 `requestLaunch` 异步入口，显式 audio-silence，**未设置 debug pointer override**。用 `CGWarpMouseCursorPosition` 在当前 1512×982 屏幕设置 Quartz `(756,0/200/780)`，AppKit 实际读回 `(756,982/782/202)`；`pointer-0/200/780` 各运行 11 秒，after delay 8 秒。顶部画面不再回中，三个位置沿一致纵向移动。`pointer-event` 在同一次 12 秒播放中于 5 秒从顶部移到下部，ready/after（after delay 9 秒）分别与独立顶部/下部截图逐像素相同（平均绝对通道差均 0）。两张事件截图 SHA-256：ready `3f4be0f7c058f130f184afe60dcc7cd22b4d2c7a03fd2edaf4f7d608944eab34`；after `c967d314839feb7f083e040fdbe0714560e8cc396022344534baf4355f733d73`。这是实际屏幕 producer → surface state → frame parallax → model/Metal → 最终 drawable 的 next-event 证据；截图由既有 terminal drawable readback 在 commandBuffer completed 后发布，退出记录 surface-stop/VM teardown failures=0。

**结论上限**：两个输入错误已修，不代表整个样本正确。顶部极限仍露灰色未覆盖条带，不能以裁剪或收窄鼠标范围隐藏；多显示器接缝、系统菜单/Spaces 交互、连续快速出入及官方同输入视觉对照未执行。其他四样本 `current/scene-after-window.png` 使用前一批 `ca1270bd` 对应 App，15 秒/after12、显式静音，只用于上述待办的当前复现，不是本批 pointer 的回归通过结论。

## E-V4-ASYNC-VM-THREAD-HANDOFF：普通 App 日期文字失败（2026-09-08）

**已定位的首断点不是旧缓存，也不是固定 clock。** 普通 UI 的 `requestLaunch` 在后台 prepare QuickJS domain，再交给主线程 `activate`；同步 probe 始终在主线程。QuickJS 保留创建线程的 native stack boundary，跨线程交接未调用 `JS_UpdateStackTop`，使正常 App 的属性赋值/脚本调用失败。`3766387484` 在隔离 HOME、`paused=false` 下仍复现 `SceneScript properties unavailable`，排除了持久化 overrides 和 pause 作为这次失败的必要条件。此前清除 overrides 的操作没有因果证据，不应重做；此前 `6c9dc01b` 的 paused activation 特例已撤回，不作为修复保留。

唯一 VM owner 在 preparation 完成、旧线程不再访问之后，由 `activate` 显式接管当前线程栈边界；保持原 stack/memory/instruction budget、generation 检查及局部失败语义。主链是 authored script → prepared shared domain → exclusive thread handoff → typed String update → text texture generation/publication → Metal → terminal compositor；普通帧不增加检查或第二个 VM。

可复现门：同一隔离样本副本/HOME，使用当前 Debug App 加 `--mwx-debug-scene-root <copy> --mwx-debug-scene-evidence-dir <output> --mwx-debug-scene-async-launch-smoke --mwx-debug-scene-duration 25 --mwx-debug-scene-after-snapshot-delay 22`。这条诊断入口使用真实 `requestLaunch`，但仍强制 resume / evidence window，因此不是完整普通窗口/暂停策略验收。C regression `test_scene_quickjs_thread_handoff.py` 用 pthread prepare、主线程两次更新、stale generation 反例，并在 macOS 跳过 handoff 复现失败；连同 QuickJS/owner-budget 共 4 tests 通过，checkpoint Debug build 成功。

本机证据根 `/private/tmp/mwx-async-text.qmTbKj`（仅 provenance，消失后重跑）：`before/scene-after-window.png` SHA-256 `10cdb94390389db59f9a79e74cb9fdab75705a57e8184eb782baeee23966359c` 为静态占位/碎片；`after/scene-after-window.png` SHA-256 `8981c697b7086c24946b427fb2f2f6a7caaf592350a3d17e28d9edcca71fe736` 显示完整 `8 SEP 2026`、`TUESDAY`、当前 `04:52`。`after.log` 有三 text callback completed、layers 55/62/68 texture publication、GPU completed、compositorConsumed、next-frame、teardown owners3/quiescent3/failures0。该次 Debug dylib SHA-256 `26d40c702fedaa0c837768a6699e8e05cdeb67c8624bce24645ba3a5521a777e`。随后仅扩展异步 smoke 时长参数后的签名 App：Team `H9QWU9XN8R`、CDHash `9d0f13361117f7839cf7680fcc9e22e1a67dda33`、Debug dylib SHA-256 `248e725c55b157e934c405e5451ef7f2ed7b2a4173ef503f1667d541ee7c75f4`。

| 样本 | 当前截图裁决 |
|---|---|
| 3766387484 | 日期、星期、时钟恢复完整；不代表所有 effect parity |
| 3712499998 | 日期/时钟恢复；仍有 WEVector unsupported，重复文字/装饰尚未全面裁决 |
| 3437487219 | 日期和时间单行完整；cursor owner collision 未闭合 |
| 3509243656 | 22 秒能离开开场；模拟 MAIN visibility producer 未执行，坐标 text 仍 undefined，不通过 |
| 3470948192 | 22 秒能离开开场；仍有 NaN、文字碎片和异常背景，不通过 |
| 3747492842 | 用户报告文字、额外闪烁与顶部光照错位；进入定向复验，未通过 |

前一次 159 样本 synchronous probe 不能代替此异步启动验收。

## E-V4-INITIAL-TEXT-GEOMETRY：静态文字与更新文字准备一致

`SceneTextTextureLoader` 原先仅在 `content != nil`（动态更新）时测量当前字体，初始文字却直接用保存的 editor `size`。这让 `limitwidth=false` 的静态标题/AM/公式仍隐式换行或裁断。初始与更新现在共用测量逻辑；初始 texture 与 measured logical size 一起传给唯一 `SceneDynamicTextTextureStore`，没有逐帧测量或第二 publication owner。显式 limitwidth/rows/ellipsis 仍保留，栅格上限及 generation 语义不变。

`test_scene_text_row_limit` 新门逐一比较初始/同内容更新的 ink statistics 和 logical size；原先依赖旧 size 隐式换行的三个 row-limit fixture 改为**显式** `limitwidth=200`，保留两行、截行和 ellipsis 的原反例，另要求不限宽时初始/更新一致且单行。Text geometry/row-limit/pivot 24 tests、resolved material runtime bridge 15 tests、Debug build 与 diff check 通过。

当前签名 CDHash `c6a8ee10d0d2deff3e91b2afeb9a5f1e1785863d`，Debug dylib SHA-256 `fe394e585d6528e7a8dc50b706eff7eb1121c093e1c4c76af69c28f5f75f24fd`。沿上述异步复现命令运行，证据根下 `3747492842/static-after/scene-after-window.png` SHA-256 `10d09b5d717cc57f6638c261ae15a3fa6e29959a293153e54e5f0244cfd1193c`：标题从纹理内多行碎片变成单行，当前 viewport 仍裁去左侧内容，光束位置未修。`3470948192/static-after/scene-after-window.png` SHA-256 `9d40412e84949c268cac19fbb7d5901596cc58ee4bebb8cd9441222180d0899e`：AM/公式字形完整，但公式 NaN 和异常背景仍不通过；对应日志有 GPU completion、next-frame 和 teardown owners51/quiescent51/failures0。

两样本均未整体验收。两次 `3747492842` 运行的真实系统音频不同，截图中的闪烁差异不能归功于文字修复；仍需静音/真实音频 producer 对照。几何修复不宣称解决光束或音频问题。

## E-V4-VECTOR-INPUT-SCHEMA：prepared owner 进入真实帧输入

Vector Program 先以空 bindings 构造，再安装 non-pass 与 admitted pass owners；其 `inputTargets/inputValueTypes` 却只在空构造时计算，导致 host `typedValues` 传空输入、所有 vector/bool owner 被跳过。现已在实际安装 owners 后同步冻结 schema，不把求集合移回普通帧。单元门改用真实 input schema 过滤后再 evaluate，覆盖 non-pass 及后装 pass；原先直接给 evaluate 填输入的门无法发现此断点。property-vector 18、Boolean visibility 10、frame VM routing 9 tests 通过。

`3470948192` 的隐形层 origin producer 现在真实执行，shared 坐标到 text consumer 后公式由 NaN 变成 `0.114`；`vector-after/scene-after-window.png` SHA-256 `efb0892637c36b698a490361b2ec3ca63eca108837512b9c504b50e2f1dd73bb`，日志首帧 vectorValues9/failures2。仍有独立 pass API exception、scale 非有限返回和异常背景。`3509243656` 的 `vector-after` 22 秒截图已出现推进中的文明记录，而不再只显示 0 年；此前“MAIN 未执行”应限定为旧空输入状态，不是静态不支持合同，整体模拟/视觉仍未验收。

恢复 vector 后必须同时关闭正交近裁面问题：旧 `SceneCameraProjection` 默认 eye Z=1，使几度 X/Y 倾斜的文字超出近裁面；`3747492842` motion=false 可见、motion=true 日期消失。正交画布现在放在现有 near/far 深度跨度中间，camera Z 平移同一跨度；不改 X/Y cover、透视相机或 authored 顺序。`test_scene_orthographic_depth` 要求正负倾斜顶点均在 clip 范围内，远超范围仍被裁切；连同 text pivot/screen anchor/particle camera 共 24 tests 通过。临时 projection/mutation probe 已移除。

checkpoint Debug build 成功；签名 CDHash `0cacbe9d909678b0c43043283cf92d91f7a0f24e`、Debug dylib SHA-256 `9562412db449eafb325408a087868ce0ff3815c8a7cd92707609cc6fec3269a3`。`3747492842/depth-after/scene-after-window.png` SHA-256 `6e85d12663caa2c565b63864eecc08be1b6e15fa96fe6466c0cd0b57c461c9a8` 在默认 motion=true、显式 audio-silence fixture 下恢复日期，日志含真实角度 mutation owner、text texture publication、GPU completed/compositor/next-frame 与 teardown。音频消融只控制输入，不算音频正确性验收；光束、viewport 裁切仍未修。新增五样本待办不因这些公共修复自动通过。

## 历史比较：手动启动与脚本运行不是同一实验

用户的 `xcodebuild ... .codex/DerivedData && open -n .../MyWallpaperX.app` 与上述 probe 的可见结果不能直接比较，至少有三项已由当前证据确认的输入差异：

1. **可执行文件身份不同。** 当前 `.codex/DerivedData` app 的 CDHash 是 `2d84e8322db54101cc519371a65b8ebf8da8493f`、executable SHA-256 是 `cae686f4523ba1c8244270995479db04f246bd349c581ee4147c5ec957f749e0`（2026-09-08 03:39 +0800 重新核对）；probe app 的 CDHash/SHA-256 是上面的 `610ab...`/`109519...`。bundle identifier/team/version 相同仍不能把两个 signed app 当成同一可复现 artifact。对两者去除签名后的主 executable 完全相同，Debug dylib 的 `__TEXT` 与 Swift metadata 代码段也相同；因此身份差异是比较前提，却尚无证据把它单独认定为日期或文字缺失的代码根因。
2. **有效输入不同。** probe 以每个样本的隔离副本和独立 `HOME` 启动，identity-only matrix 不带用户持久化 Scene property overrides；普通 App 从 Workshop record path 启动并读取 `com.songziqiang.MyWallpaperX` 的已保存 overrides（例如 `3396722575` 的 `newproperty3` 长文本），以及用户属性纹理 URL。值、路径、缓存和资源 ready 状态因此可能不同。
3. **启动/窗口/策略不同。** probe 传入 `--mwx-debug-scene-root`、evidence directory 和 duration，走同步 `SceneDesktopWallpaperHost.launch`，强制 resume 播放并使用 DEBUG evidence window；普通 App 走 UI/desktop request 的异步路径，使用实际 display/window 与持久化 pause policy。两条路径最终汇合现役 host、Program/VM、Metal encode 和唯一 compositor，但窗口尺寸和有效 property snapshot 会影响首帧布局与文字栅格。

已用两个 app 对同一 `3396722575`、同一只读样本副本和同一 identity-only matrix 做 A/B：两边都是 `61` layers、`30` image layers、`62` effects、`textScriptDiagnosticCount=0`、ready/after 非黑、`1/1 PASS`；当前 app ready 约 `16.415 s`，probe app 约 `17.067 s`，差异落在启动和帧采样抖动。这个 A/B 没有复现日期或文字差异，说明“脚本一定更好”尚未成立，仍需把普通 Workshop record 的 overrides、纹理 bookmark 和实际 display extent 纳入同一组实验。

当前 frame code 的 debug 与 production 都从同一 `Date()` 形成 `wallDate`；本次 probe 没有设置 debug wall-date override。这个结论可由 [`SceneDesktopWallpaperHost+FrameDriver.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+FrameDriver.swift)、[`DebugScenePlaybackRunner.swift`](../../../MyWallpaperX/App/DebugScenePlaybackRunner.swift) 和 [`SteamWorkshopSceneService+SceneProperties.swift`](../../../MyWallpaperX/Modules/SteamWorkshop/Scene/SteamWorkshopSceneService+SceneProperties.swift) 的当前实现复核。因此“手动启动拿不到时间/日期”目前不能归因为 debug clock 被注入。应先用**同一个 executable、同一个样本副本、同一个 effective property snapshot、同一个 display extent**各运行一次，并比较 SceneScript exception、text publication generation、terminal compositor 与 next-frame；只有这组 A/B 能把日期缺失区分为输入/路径差异、typed script contract 失败或文字 provider/layout 问题。

## 结论上限和下一步

## 用户新增样本待办（2026-09-08）

以下条目来自真实播放观察，当前仅作为待关闭的可见结果记录；尚未将现象提升为合同，也未用样本 ID 做运行时视觉分支。每项必须回到公共 producer → typed channel → consumer → Metal/compositor 链取得正反证据后才能关闭。

| 样本 | 待恢复的可见结果 | 当前状态与首断点 |
|---|---|---|
| 3264246690 | 人物头部不越界，左肘纹理完整 | 待定位 geometry/coverage 或资源裁剪首断点 |
| 3765760121 | 画面方向正确 | 待定位 authored transform/UV Y 合同 |
| 3780119725 | Audio Bars、光照位置和闪烁行为正确 | Puppet extent 已修；Audio Bars stage-link fallback、光照/闪烁未闭合 |
| 1315486372 | 水波位置与贴图光线符合 authored 布局 | 待定位 effect source extent/UV/transform |
| 2775915974 | 鼠标 Y 方向正确，顶部边缘仍保持 inside/事件连续 | 待定位 AppKit → typed pointer → consumer 边界 |

### 3765760121 运行追溯（2026-09-08）

单一 Scene host/runtime instance 的真实日志同时出现并完成 text callback：`68/76/82` 与 `190/196/202`。直接用现有 PKGV reader 核对当前 authored `scene.json` 后，确认六个 ID 均为作者对象：190 由默认 false 的 `newproperty5` 控制，196/202 是其子层；68 由默认 true 的 `newproperty6` 控制，76/82 是其子层。额外 callback 不是重复实例证据，也不能解释为旧缓存。preview 的旧 text subset binding count 为0，而通用 VM 的 completed callbacks 是6；两者不是同一统计职责，不能据此修改产品 consumer。原矩阵三 binding 期待仍 NON-PASS，未放宽；可见隐藏传播与切换需单独事件验收。

## E-V4-AUDIO-BOOLEAN-OPERAND：布尔数值操作恢复音频图形（2026-09-08）

`3780119725` layer380 的 Audio Bars 并非 audio provider 没有输入：准备阶段 glslang 拒绝 bool 变量到数值复合赋值的隐式转换。旧 `SceneGenericShaderBooleanScalarArithmeticNormalizer` 只转换内联比较，遗漏已声明 bool 标量。现有 owner 利用词法 token 和唯一声明类型，为 float/int/uint 的直接 bool 赋值/复合赋值补显式转换；重名遮蔽、成员、未知类型不猜测，控制流、bool 赋值和注释保持不变。只在 preparation 运行，不新增 provider/clock/renderer，不改变失败预算或 color/publication 合同。用于定位的临时编译错误观测已移除。

验证：artifact suite **76 tests PASS**（含 numeric/bool/control/comment/shadow/idempotence 反例），canonicalization **2 tests PASS**（实际 bundled glslang stage-link），source-set **11 tests PASS**，签名 Debug build 成功。全仓 code-health 仍被本批未改的 `SceneMetalRenderer.swift` baseline shrink 与 `SceneScriptScalarRuntime.swift` 803 行阻断，不记 PASS。

本机 provenance：负例 `/private/tmp/mwx-audio-current-diagnostic/report.json` SHA-256 `94997c84268bf77594fee154d8bb50022fd89706bde0f9f6200d9869e251de67`；静音正例 `/private/tmp/mwx-audio-bool-after/report.json` `671fadce96f60f3588e6159a33d666b4cdebdd30d7342fe6e093ed836141fa30`；移除临时观测后的 PCM 正例 `/private/tmp/mwx-audio-bool-pcm-final/report.json` `a2f1a1d4cf0c187043a08b6800b79172c11b5324e21012b5fa3b67be6307baf4`。最终 App Team `H9QWU9XN8R`、CDHash `f7e2370241715ab6e9cc321aca87a632d7fa215f`。layer380 的64-bin左右声道从frame0 generation0 silent变成frame3 generation2 nonzero（peak约0.366/0.374）；Program `ba0d6b8513ea0a9c1312b47a011cd7e124356e1a0262546c17e3914d7b897734` 实际 GPU completed、publication、compositor/next-frame成立，PCM截图可见新增音频条。after PNG SHA-256 `9da289ad657f516edd5803e58974bbd2e76f252d9333c2a7384270e1126efd0d`。

同一最终 App 另走真实异步 `requestLaunch`（隔离根 `/private/tmp/mwx-audio-async.8AEVC4`），相同 Program 在frame0/1 completed、compositorConsumed=true，publication49→100；surface teardown为owners7/quiescent7/failures0，surfaces1→0。异步 smoke 不调度 PCM fixture，因此此运行只证明真实 prepare→activate→GPU 生命周期，不冒充异步音频事件对照。该样本脸部黑线/构图仍未通过；新样本3287715210是独立 color-transfer 拒绝，不能由本修复宣称恢复。

## E-V4-PUPPET-BUDGET-FAIRNESS：Puppet图层共享预算与构图（2026-09-08）

`3238423642`的人物头部错位不是作者坐标错误：四个`katanabody`层和一个蝴蝶层共享128MiB重组预算，旧实现按遍历顺序消耗，前几个大目标后最后图层因剩余预算不足退回原始atlas，导致身体与头部使用了不同几何。现在在load阶段按潜在Puppet层数量建立均衡上限，并将`targetDimensions`按实际剩余字节预算等比降采样；仍保留4096维度、最小安全纹理和OOM/预算拒绝，不逐帧重建、不按sample分支。

Puppet mesh/source **31 tests（1个无Metal跳过）PASS**，签名Debug build成功。隔离运行`/private/tmp/mwx-puppet-budget-after` report严格PASS（SHA-256 `169db649186c11de9e07ae3250ae2fe6f9104463481f39146a31fc649a2da032`），after PNG（SHA-256 `bfc3b264dc396e4821d8883fe441ec3ca7d1db64bd436af33797fd62c87f8a43`）人工确认头部与身体对齐、日期时间可见；四个katanabody均报告`puppet animation OK → 3485×1925`，不再出现`animation target rejected`，GPU/Program/compositor连续帧成立，性能仍约18.7 FPS（CPU约49ms），因此不声称性能完成。该证据只证明共同预算与可见构图修复，不证明Puppet全部动作、3D/lighting、其他样本或官方等价。

## E-V4-TEX-MEDIA-IDENTITY：图片身份与首帧资源准入（2026-09-08）

`3448845950`的零提交首断点是layer57源纹理永远missing。实际AVPlayer返回-11829/-12848；只读检查`111.tex/111ying.tex`发现TEXB0004单条条件metadata下的payload是PNG，原reader把metadataCount=1标为MP4，registry据此提前抢走已准备的图片。现在按payload签名判别video，metadata数量不再决定producer身份，恢复现有PNG uploader→typed layerSource→Program。另一个同景首帧阻断是零面积solid辅助层1475：preflight已按投影准入最小target，preparation却重新要求有效图片尺寸；现在复用已准入solid target extent，普通图片的非法extent仍拒绝。

缺失/准备中的安全source走现有`layer-source-not-ready`局部fallback，既不伪造纹理，也不阻塞无关内容；下一帧重新选择source。能力/identity/ABI拒绝未改为fallback。真实video `3775355045`首次layer22暂缺，第10帧恢复Program `f9013c571a43bc9526a571ffbb9d3959a5929daead7c691e61fa9d5dbb8f76dd`，第11帧继续，publication2→4、GPU completed和compositorConsumed成立；390/390/0提交/完成/失败，停止surfaces1→0。其report因初始fallback诊断严格NON-PASS，不修改门禁掩盖该事实。新fixture覆盖PNG/JPEG/raw/MP4 signature × 0/1/2 metadata（signature fixture不是可播放视频）；coordinator门覆盖局部fallback、Metal完成和下一帧重试，既有错误token等负例不放宽。

验证：media/video **11 tests PASS**、bridge/video **25 PASS**、capture/local-fallback **12 PASS**、volume/source-set/doc-role **29 PASS**，签名Debug与deep/strict验签成功，CDHash `80b7891006348c3c1839ded6a31acf91bf1d7331`。最终三景报告`/private/tmp/mwx-tex-media-kind-after/report.json` SHA-256 `53d78adf9ba58605b551f288331ddd38dd7775db4dcdc6363711f34c99a2f6f6`；3448845950 after PNG `e1a141a8535f1a07e9f5becba071e17c1055d34cc7ebc3e02d331763d0c9dd8c`显示蓝色卡片与真实时钟，479/478/0提交/完成/失败，layer57终端包含明确script-unproven passthrough，publication18→38与next-frame成立。整景仍NON-PASS；3238423642虽结构PASS但头部错位未修，3662790108仍NON-PASS。video回归report SHA-256 `6fc409fdafaea5b7839844b214fb9e78f16ae41e55128ab8d8b45cbbf5bddda9`。负例现场为`mwx-black-source-diagnostic`、`mwx-video-solid-admission-after`和`mwx-video-decoder-diagnostic`，临时诊断均已移除。未证明条件metadata动态选图、全部脚本、视觉等价、长稳或性能改善。

## E-V4-CANVAS-PERSPECTIVE-CARD：透视选项不改变画布坐标方向（2026-09-08）

`3788734811` layer17在正交画布中开启perspective，现有world resolver和camera仍使用Y-down，而imageModelMatrix错误地采用原生透视的Y-up卡片；typed transform经过相同Program和compositor后整图倒置。`SceneCameraProjection.imageCardYDirection`区分画布坐标约定与投影选择，正交画布透视/正交卡片均保持负Y尺寸，原生透视保留正Y；无新renderer、sample分支或UV翻转补偿。

camera/screen-anchor **19 tests PASS**，签名Debug build成功。隔离运行`/private/tmp/mwx-perspective-card-after` report SHA-256 `5dc36a0bdd8227bf61e6ce05629aa463570a1684c522c49639d39290a4fcbdf6`，after PNG `37111cf24f597c6df28351473275f980d10198336f43d11ab280eae5df9c17bf`人工确认正向；修前负例在`/private/tmp/mwx-new-reports-current/results/3788734811`。layer17终端Program `9762a293a879c5b219d5ceed4795b975e31674eae294cd8093f663dee5faa731`的frame0/1有GPU completed、publication及compositorConsumed；测量窗599提交/598完成/0失败，停止后surfaces1→0。只证明倒置修正和下一帧执行，不证明所有效果、原生3D样本视觉等价、多显示器或性能改善。

## E-V4-AUDIO-REPLACEMENT-COVERAGE：音频权重成为输出透明度（2026-09-08）

`3287715210` layer277 的 shader 可编译，但 source-carried RGBA analyzer 仅允许默认混合与source/max透明度，拒绝作者已有的加法RGB混合及同一音频权重作为replacement alpha。现有 analyzer 复用 `SceneAuthoredShaderRGBBlendScalarAlphaAnalyzer.validBlendHelper` 的源代码语义证明，并要求replacement alpha逐token等于已验证RGB blend的权重；未知mode、错误helper和不相关source通道仍拒绝。输出沿现有straight boundary只premultiply一次，不增加Simple Audio Bars专用路由，也不调整作者默认值。

source-carried/RGB blend **6 tests PASS**，artifact **76 tests PASS**，Debug build成功。最终App CDHash `05f3cd9755416d5e0a1ce65c73a52c6b7100ce52`；PCM运行report SHA-256 `245034b20405a04c5e714585cb3853b616d98d5bd375fc920245dbfbc173c14d`，静音report `44b1b6a8e2a96401ba72574cc45062307a947f99bea79a23ed4bf206c1ed643d`。本机目录分别为`/private/tmp/mwx-3287715210-replacement-after`与`/private/tmp/mwx-3287715210-silence-final`。PCM after PNG `b8d3a46e66952ce077d356f8bb7fdae78d79525cfe8c6e969f7e6d1cc9b219fe`显示底部音频条；静音维持作者最小高度基线，PCM有变化高度。layer277在frame3消费generation2的64-bin非零左右声道，Program `29fe213ab6680ad3b8db50c29eb6994a6087be737d88f8418bdd583103b43ea2`有GPU completion、publication11→22与compositor/next-frame，teardown owners3/quiescent3/failures0。独立异步requestLaunch根`/private/tmp/mwx-bars-async.e54o12`验证相同Program生命周期；不冒充系统音频权限/捕获策略验收。

同批用户新增样本probe位于`/private/tmp/mwx-new-reports-current`：倒置与黑屏负例保留，上表未通过状态优先于benchmark结构PASS。人物头部错位、视口构图、长稳、多显示器及真实系统音频仍未验收。

## E-V4-SOLAR-AUTHORED-CONTROLLERS：布局控制器与标签样式发布（2026-09-08）

`3662790108`仍未验收。本批关闭的是作者控制器未执行/写入未发布的公共断点，而非太阳系完整视觉：可见性上的有状态Boolean脚本进入现有QuickJS owner；外层String user引用作为既有typed user-property输入交给Boolean脚本，保留其他未支持的双来源拒绝。作者`Page Indicator`的自动隐藏和`Clock`的定位脚本因此执行，最终截图不再有中心PAGE/圆点，时钟移到上方。标签实际是image layer，原先authored handle没有alpha/color setter，写入只停留在JS对象；现沿既有mutation journal、typed frame state和compositor发布，隐藏的中英文/卫星标签不再成堆显示。shared事务跟随提交/丢帧边界，直接shared投影在准备时排到producer之后；没有第二clock/property state。

鼠标准入不再把负零角度拒为旋转；有限旋转/镜像仍由已有逆变换与命中安全门校验。纯身份冲突未执行失败脚本，不再为其重建整个domain并耗尽4096构造预算；真正owner执行失败仍隔离重建，冲突负例保留。稳定owner集合在prepare缓存，实时hit/capture/disabled检查不省略。**本景仍有6个cursor层身份冲突，实际点击/拖动未验收**。28个style/Boolean/QuickJS/generated-RGBA定向测试通过；后继parser/Boolean/cursor 24测试通过。静态循环另有2个正反门：全局const int字面量可证明循环上界，局部遮蔽/修改/动态或超预算上界仍拒绝。轨道shader从dynamicLoop推进到colorContractUnproven，仍是局部passthrough，不能称轨道恢复。

最终签名Debug来自`.codex/DerivedData`，CDHash `9afb366bb3cf0582dcf31b48c674af5fe5bd747b`，executable SHA-256 `8ef8e5b6ecd14a163621534f4393a3a74383c59b001de016ac3632b6ff2b9c05`。隔离运行`/private/tmp/mwx-366-layout-checkpoint/report.json` SHA-256 `3fd06bfc2d453e461b13947eb4f0e5a8753a46090d6e4624af404a4e41b3b838`；after PNG `56f201f31001732e45411e8ef4f19da27dea2c804776701f227ae1c2769c7e5b`。复现使用现有benchmark、真实样本根的只读隔离副本、`newproperty1=false/newproperty48=true`、45秒/after delay40秒；该override不是作者默认状态。284/283/0提交/完成/失败，已有终端graph completion/publication/next-frame记录，但accepted-layer覆盖缺口与effect-local passthrough使报告保持NON-PASS。

**遗留首断点**：轨道及大气的颜色语义证明、球体可见尺寸/资源/变换、曲面与曲环的准确显示合同、真实点击仍开放。`coordinategrid=false`只指作者名为“网格”的天空球，不能用它推断另一组“曲面/曲面x”模型应隐藏。7.49 FPS、main-frame p95 61.59ms、CPU encode p95 50.25ms暴露明显稳定帧成本；没有可比性能改善结论，不能用本批多执行了脚本来豁免性能问题。保留`mwx-366-style-cursor-final`的domain预算负例和`mwx-366-preflight-auto-fixed`的中心布局负例用于回归，不以离开开场或时钟修复宣称整景完成。

结构收口后，vector/property/transform/Boolean 34测试及cursor/source-set/doc-role 24测试通过，code-health通过（只下调已有renderer体量基线，没有扩大上限）。最后注释修正重建的executable SHA-256为`4d1e5f0508f029dd1f45a31643dc9cc73219edb79a790f936dbe0708a4d5d0f4`；`/private/tmp/mwx-366-final-profile`的65秒运行428/427/0，report SHA-256 `55835484300ee1191227c5f855196cf0a23875f5d084d692338769b9a6fe4f19`。其最终after采集缺失，保持该负例；series-0004 PNG `c20d1de6f2d2e4ad75c6fe87045260b1ea8a9069b4a93e49b4619d70a5fdd31a`再次显示上方时钟、无中心PAGE和转动后的相机画面。该运行含3秒进程采样，不能与未采样运行作性能比较；采样定位到相机选择重复构造全场景visibility集合，是后继CPU整改候选，不是已完成优化。

这些条目不构成通过声明；在获得隔离截图、GPU completion、publication 与 next-frame/event 生命周期证据前，样本仍视为未验收。

## E-V4-STATIC-MODEL-WIDE-INDICES：大网格资源拒绝与小尺度绘制（2026-09-08）

### 后继 `3477054430` 多段几何首断点（2026-09-08）

该样本的 `little head`、`townfbx`、`billboard` 是合法 MDLV0023 多材质段。前序提交 `5a779cbd` 从拒绝推进到合并几何，却丢失材质段身份，产生猫脸/城市串用树叶贴图。后继已撤销该有损合并：bounded reader 保留逐段 material、局部 UInt16/UInt32 indices，校验段间零分隔和整个容器累计预算；只准入有证据的 MDLV0023 多段，MDLV0016 仍限单段。准备阶段为每段绑定自己的 material/texture/mesh，进入原 main pass、共享 depth 和唯一 compositor，没有第二输出链。

另一个首断点是 property compiler 的 `links.count == 1`：多材质会跳过全部 `{user,value}` 参数。现有 typed material target 增加规范化 material path，编译与模型 consumer 使用相同身份，避免同层同名参数串值。完全透明 texel 不再写深度遮挡后续材质；TINTMASKALPHA 不作为透明覆盖。资源/几何仅 launch 准备，值仍由原 snapshot 逐帧消费。

- 定向 40 tests PASS，覆盖分段局部索引、坏分隔/截断/越界、typed material identity、既有单材质/属性/模型 pipeline；Debug build 成功。真实隔离 `/private/tmp/mwx-parts-run2/report.json`，CDHash `4d74e5be69bf302ec1a6192ded687c3fece301d0`；默认 authored 属性，duration 12 / after delay 9。410/409/0 submitted/completed/failed，约 59.94 completed FPS，CPU p95 4.67ms / GPU p95 6.74ms，仅为该短窗，不是可比性能提升。
- `results/3477054430/scene-after-window.png` 已人工查看：猫脸、粉色耳机、建筑分别使用正确纹理，树木的矩形遮挡消失；prepared model layers `[14,23,47,68,77]`。整景 completion/publication 与 next-frame 有记录，但尚无每一材质 live 属性注入的像素证据，不能把单元 identity 门当完整 producer 生命周期验收。
- **仍 NON-PASS**：后处理 CPU invocation failure / effect-local passthrough；对照用户提供的 `截屏2026-09-08 19.26.03.png`，远景过亮、窗户发光和树缘仍不正确。作者 `general.fogdistance=true`、start 6.53/end 500、黑色、末端密度 0.98 当前未被读取，是下一构图断点；音频驱动材质脚本、完整 PBR/后处理仍未闭合。禁止以截图固定颜色代替 authored 参数，未宣称整景或官方等价。

- 真实运行 report `/private/tmp/mwx-347-firstmat-run/report.json`；截图 `/private/tmp/mwx-347-firstmat-run/results/3477054430/scene-after-window.png`。该临时目录仅作当前复查证据，后续清理时可重建。

<a id="e-347-distance-fog"></a>
#### 距离雾后继

2026-09-08：缺失的 authored distance fog 现经 GeneralDescriptor→LightingDescriptor→当前 SceneLightSnapshot→static-model uniforms→同一 Metal/main-pass 输出。仅完整、有限、end>start、density∈[0,1] 的定义准入；未定义/禁用/非法数据局部保持无雾，不拒绝整景。使用当前 camera/world position，不缓存相机距离或在普通帧重新解析。按公开起止密度语义采用有界线性混合；精确官方插值与颜色空间未证明，height fog、材质 opt-out 和 fog 的动态属性不在该闭合范围。

14 项 document/pipeline/rendering 测试 PASS、Debug build 与 code health PASS。隔离默认输入 `/private/tmp/mwx-fog-run/report.json`，CDHash `c29608bdae6576e3ea51be243fd7cf7c3cc3b9ae`，duration 12 / after delay 9；410/409/0 submitted/completed/failed。人工查看 after-window：远城明显按距离衰减，近猫和前景保留，纠正此前全城日间亮度；未对截图硬编码色调。整体 completion/publication/next-frame 仍沿原链，NON-PASS 的后处理失败保持不隐藏。窗户自发光/音频脚本、猫头角度脚本的 `TypeError: not a function`、dithering compiler stage-link rejection 为剩余精确断点；不能称预览等价或完整雾效果。

#### 猫头角度脚本恢复

后继定位 `TypeError` 来自 QuickJS value host 缺失公开 `Vec2.length/normalize`，并非作者角度数值或缓存。原 Vec2 类现提供稳定模长和返回新对象的归一化；零向量采用本项目安全零向量结果，不声称未公开的边缘值完全等价。原 C QuickJS 合同 harness（2 tests，含大量 owner/lifecycle 正反门）和 Debug build PASS，新增模长、非原地修改、零向量、大有限值门。

同一真实 producer→Vec2→作者 update→typed layer angles→原 model transform/Metal 链现完成：`/private/tmp/mwx-vec2-run/report.json` CDHash `035b3cd8ae8ad31e878de914a063cf427b49ba4e`，layer 14 从每帧 exception 改为 completed，frame 0 angles 输出 `(-0.06517,-0.51468,0)`，vectorFailures=0；410/409/0 帧。额外 `/private/tmp/mwx-vec2-hover-run` 以 normalized pointer `(0.9,0.8)` 运行，before/hover/after 三图已人工查看，猫头角度出现变化；406 completed，整体 changed ratio 0.04582/0.01186 也包含星空时间变化，不能单独当猫头 ROI 因果证据或真实桌面所有边缘输入验收。整景仍因 dithering 局部失败 NON-PASS；窗户发光与完整预览等价仍开放。

#### Dithering 后处理执行恢复

首断点进一步定位为 source-defined scalar `mod` 与 GLSL intrinsic 的重名声明冲突（stage-link 报 precision qualifier overload 错误）。现沿既有 bounded syntax normalizer，仅对唯一 `float mod(float,float)` 定义、全体调用参数均为可证标量叶子、无名称冲突/遮蔽的情形做符号改名；作者函数体不变，不用内建算法替换作者实现。中性 fixture 故意令函数返回加法，证明保留的是作者语义而非对模算法的猜测；vector/compound 参数仍不扩权。request key v11、frontend schema 33 强制普通 App 不复用旧编译身份，临时诊断日志已移除。

4 个 normalizer/link tests 与 1 个真实 artifact cache namespace 门 PASS，Debug build、code health PASS。`/private/tmp/mwx-mod-run/report.json`、CDHash `6c5d918177886411bb6f0b6069a9914e0eeb1704`、默认作者属性、12秒/after9秒；409 completed，严格执行 selection **1/1 PASS**。after-window 已人工查看，作者像素化/抖色后处理实际进入画面，原 effect-local passthrough 消失；Program completion/publication/next-frame 由该报告保存。月亮 effect 另有 float→int 编译问题但仍沿既有共享 fallback 安全输出，不能由 selection PASS 推断所有 compiler 路径成功。**窗户发光/音频材质 producer、精确照明和官方预览等价仍未验收**。

`3662790108` 主太阳控制器的子层 3694 在 prepare 首先失败：合法 authored `ray.mdl` 使用 flag 1 / UInt32 索引，旧 reader 只接受 flag 0。独立读取确认 500,596 顶点、606,204 三角形、最大索引 500,595、format 15、单 mesh/material 和七字节零尾部；不是缓存旧图。现沿原 reader → loss-preserving UInt32 IR → prepared mesh → Metal indexType 消费，能安全缩窄的索引仍上传 UInt16。未知 flag、非完整三角形、越界/截断及原预算继续拒绝最小模型。另修复 normal matrix 以绝对 determinant 阈值误拒合法小尺度的问题：Double 逆转置后共同正比例归一化，真正奇异/非有限矩阵仍拒绝。

- 正反门：`test_scene_static_model_reader` + `test_scene_static_model_pipeline` 14 tests PASS，包含超过 65535 的索引、UInt32.max 越界、未知 flag、短三角形，以及 `1e-30...1e30` uniform scale、镜像非等比和奇异矩阵；Debug build、code health PASS。临时逐模型 NSLog 已删除。
- 真实隔离运行：`/private/tmp/mwx-366-wide-model/report.json` SHA-256 `cb2a025070c8ae2cbcbcb93f78e7a32f5c3639931b62b2d1d6f98bc13d1f8215`；输入同前一轨道证据的两个属性、30 秒/26 秒截图。CDHash `e0c6efee4aaca929155a3e08cb104e67fe4a6a77`，executable SHA-256 `272636d87c5433fc9fc1e7c59f55e21ba60e596bb376f0219aac6fde13cc3f8b`。preview log 的 prepared static model layers 新增 3694；201/200/0 提交/完成/失败。
- 截图 `results/3662790108/scene-after-window.png` SHA-256 `77f8fcc8ffc7df8339e1e055803b0d7b3fcb9df8b17200a2b4b3b5f49322f419` 保持顶部时钟、分离标签和轨道拖尾；仍有曲率网格，不能宣称太阳/行星球体视觉闭合。当前遥测不单独证明 3694 的 completion/publication，资源修正证据为 S2，整景仍 NON-PASS。该轮不是性能对比；多 mesh/material、其他 vertex layout、点击焦点切换及近景球体仍开放。作者脚本会按尺寸/距离/焦点改变天体 visibility，应先检查实际输入与状态，不能无条件打开所有模型。

## E-V4-PROCEDURAL-SOURCE-RGBA：轨道输入恢复到实际 shader 输出（2026-09-08）

`3662790108` 的轨道不是缺失资产：作者 shader 从 framebuffer 分离 RGB/alpha，经 `inout` helper 做 RGB mix 与 coverage max，最后重组输出。首断点是现有 source-carried color proof 未覆盖该数据流；解除后暴露 Metal emitter 未转换 `out vec3` 参数，导致库编译失败。后继在原颜色分析 owner 中逐一核对 source/carrier/helper 的全部用途，复用语法 owner 的单循环与展开工作量预算；`out` 与 `inout` 都降低到现有 thread reference 参数。源码、资产、sample ID 不参与产品选择。撤回 `4ce6bbfc` 对纯生成颜色循环的无效放宽；缓存 key schema 6、preparation frontend schema 32 使普通 App 不复用旧编译语义。

- 复现输入：`scene_wallpaper_benchmark.py`、同一真实只读样本的隔离副本、`newproperty1=false/newproperty48=true`、duration 30 / after-snapshot-delay 26；保留目录 `/private/tmp/mwx-366-out-parameters`。运行 PID 82144 已退出，staged App 与运行材料为追溯暂留。
- 身份：CDHash `512865f237418593ca431f145e806fb8aafe1c49`；executable SHA-256 `7e4f2b07965909e3a5fe46f0356697def924546823b175b1a8b59e925059ff19`；report SHA-256 `bcf4047a38d9a30d68a6b48bd873cc4376dd4cadcc88066e1107523a70988e1a`。
- 实际链：脚本更新的轨道 material uniforms → source-proven prepared Program → 四个轨道层 517/1101/3054/3058 的 `encoded-output`。层 517 的 Program `c4483382c223555ad460ea603b6f28bb44a7a234d2b05921f17ad8b3eb8020da`，frame 0/1 均 `gpuCompletion=completed`、`compositorConsumed=true`，publication generation 2→72；不是 passthrough 冒充执行。
- 截图：`results/3662790108/scene-after-window.png` SHA-256 `8ea2e3e6fca56bfec2d2449fdc517619bf49f8a116dc42f45f149d8775b08526`，最终界面出现彩色轨道拖尾，顶部时钟及已分离标签保持。202/201/0 提交/完成/失败；此轮仅验正确性，不作为可比性能基准。
- 正反门：source-carried fixture 包含多次 helper 调用、有限循环、条件零重置及一次输出预乘；拒绝 carrier 预乘、alias、额外 source 颜色、非 max coverage 和超预算循环。`out` fixture 实际编译 Metal library，非法数组参数仍拒绝；Debug build 成功。
- 结论上限：仅恢复 bounded 轨道 shader 可见结果，整景仍 **NON-PASS**。球体缺失、轨道采样视觉、曲率网格、实际点击、性能和官方对照仍开放。作者 `coordinategrid` 默认 false 对应层 926；另有默认未声明 visibility 的曲面/曲环模型，不能把画面上所有线条都当成该布尔开关失效，更不能为截图直接隐藏它们。

## E-V4-CAMERA-VISIBILITY-HOTPATH：鼠标投影避免全场景可见性重建（2026-09-08）

鼠标投影原先每个输入样本都调用完整 `visibleLayerIDs`，递归检查全部作者层及父链；改为按候选相机逐项检查其父链，完整集合仍由合成/发布路径使用。该改变只减少重复集合构造，未跳过动态 snapshot、source authority、循环 identity 或命中安全检查。

同一 `3662790108`、同一隔离 benchmark 和 `newproperty1=false/newproperty48=true` 下，新的 Debug executable 运行 report `/private/tmp/mwx-366-camera-hotpath/report.json` SHA-256 `3d7c5cae44a7fdc5ce003e8bdce75d61a9664cac02d336622d5e6143fbf777eb`，截图 `scene-after-window.png` SHA-256 `2974ce0c51c28d2fdc8d46a3428802af97dfb42b4467191e3205192ed0fb6636`。251/250/0 提交/完成/失败，完成 FPS 8.844，main-frame p95 56.892ms、CPU p95 49.546ms；画面保持时钟上方和无中心PAGE/圆点。该数字只与本批前的同流程样本结果作有界比较，不能外推所有样本或稳定性能完成。轨道颜色合同、球体/曲面资源、实际点击和整景 NON-PASS 仍开放。

159 个样本有可复查 triage，不等于正确播放。异步线程交接修复只关闭上面有截图支持的日期文字首断点；继续检查 shared-state producer 未进入 Program、静态文字布局及用户新增的光照/闪烁，不以同步 probe、构建成功或离开开场宣称通过。尚无必要启动官方客户端逆向研究。

## E-V4-TEX-COMPONENT-SELECTOR：3477054430 mask 候选恢复（2026-09-08）

真实样本的 `Image_3_mask_3fc62503.tex` 携带 `0x00a00002`：低位是 sampler/sprite 选择，高位 20...23 是作者格式定义的 component-channel selector。旧 admission 只承认低三位，因而把合法 mask 当成未知 flags 丢弃；现收窄为承认低三位与 20...23 位，其余位仍 fail-closed。mask alpha 沿既有 texture candidate→material slot 2→static-model Metal 输出链消费，隔离截图恢复建筑窗户的绿色/橄榄色 authored 光效。

texture-registry 正反门、Debug build 与 code health PASS；`/private/tmp/mwx-maskflags-run/report.json` strict PASS，410/409/0 submitted/completed/failed，完成 FPS 约 59.93；截图 `/private/tmp/mwx-maskflags-run/results/3477054430/scene-after-window.png`。这证明 mask admission 与 publication/next-frame 链路成立，不等于官方预览完全等价：音频驱动的嵌套 `scriptproperties.minvalue.user` 尚未进入材质 typed owner，月亮/球体、精确构图与完整文字布局仍开放。

## E-P1-DEPENDENCY-REFERENCE-EFFECT-LOCAL：不支持的依赖引用只让持有它的 effect 退回 previous-current（2026-09-08）

隔离运行 `2775915974`（composelayer 28：xray 引用默认隐藏的 layer 24 composite，其后 4 个 shake、2 个 waterripple、waterwaves、waterflow）与 `3792249095`（image layer 254：crt_scan_line 引用自身 composite，另有 test_shader/pulse/refraction）时，`SceneDependencyRenderPlan` 对该 consumer 形状没有 binding 合同，`SceneResolvedMaterialDependencyOwnershipCompiler.compile` 返回 nil，整层以 `execution-route-dependency-owner` 拒绝，9 个与 4 个 effect 全部 `unified-capability-unavailable`；utility 运行计划同时因 `dependencyLayerIDs` 非空把 layer 28 记为 `unsupportedDependencies`，整层连 shake 都不执行。这不是颜色合同或 shader 失败，是层级 all-or-nothing 准入。

现在 `unsupportedReferenceEffectKeys` 把既有 forward/secondary 两种"单个 exact 单 pass material effect 退回 previous-current"的规则推广到任何没有 binding 的 owner-requiring 引用：只有持有引用的 effect 记为 `dependency-stage-reference-unsupported` passthrough，层 ownership 为 `.none`，其余 effect 照常进入 Program/GraphExecutor；multi-node、command、condition、compose、render-target 或 slot 未出现在 node binding 的 effect 仍让整层 fail-closed。执行器 passthrough 白名单接纳该拒因；utility 运行计划在没有 binding 且层已被 capability 准入时按普通 composition 捕获。没有 provider 授权、named target 发布或依赖顺序变化。

验证：`test_scene_resolved_material_graph_executor` 新增 backward 引用的实际 passthrough 执行正例（prepared/encoded/GPU completed/suffix continued）与两个反例（slot 不在 node binding、command 图）ALL OK；Debug build 成功，code health PASS。当前 App CDHash `70996ee0956e1bd1e564a4b93e2808ac0c8e3c97`、executable SHA-256 `7ef438fd01371d0a868894e9b5bfe97c2b58fb4e1ca1e00c5ccce735368c7f04`；report `78521106002904f9eeefadaf2c1ef92d7aea404d9e8dd031d927ee238cfc36a1`。`2775915974` 由 claimed 0 变为 layer 28 claimed/encoded/gpuEncoded 1，admission 为 8 个 `admitted-generic` + xray `admitted-fallback`，after PNG `675e00e2d25552ff13f0708cd6019fa304f237f75043470d18ce88ca669d1b5a`；`3792249095` layer 254 由整层拒绝变为 pulse 执行、test_shader/crt/refraction 三个 passthrough（后两者是独立的 owner-revoked 与 color-contract 拒因），claimed 7，after PNG `9c61f8da5b7f3c33f0465bbb2057e9431eb746f30bf3d59e70d612e541794f52`，截图中中心光环较修前更接近作者预览的亮度但仍远未等价。同一 App 重跑 `3554161528`、`3233141951`、`2824109832`，审计与准入计数与修前完全一致。

结论上限：只闭合"依赖引用不支持不再拖垮整层"这一公共首断点；xray 的隐藏 provider 消费、crt 自引用语义、脚本驱动 effect 可见性（`dynamic-effect-visibility`）与组合子树形状（`utility-composition-subtree-shape`）仍是独立首断点，两个样本的视觉裁决均未改变。另观察到单层 preflight 失败会让提交协调器拒绝整帧并黑屏（本批修 allowlist 前复现），这是下一个失败半径缺陷。

## E-P1-DYNAMIC-EFFECT-VISIBILITY-ADMISSION：脚本/Timeline 驱动的 effect 可见性不再整层拒绝（2026-09-08）

`3233141951` 的两个 composelayer（599/691：workshop audio bars 的 `visible` 由淡入淡出脚本驱动 + opacity）与 `2824109832` 的 layer 712（pulse_ 的 `visible` 由 12 小时制脚本驱动）此前在 `SceneResolvedMaterialExecutionCapabilityAdmission.compile` 被 `dynamic-effect-visibility` 整层拒绝，连同层内 opacity 一起不执行。当前没有任何 VM owner 投影 effect `visible`（标量投影只接受 number 目标，Timeline 对 bool 目标返回 nil），因此这些 effect 唯一可用的事实是作者 `value`。

现在该 guard 移除：frame-driven owner 只负责把层登记为执行候选，其 effect 按作者值执行；已准入的 pair chain 不因可见性变化而改 topology，用户属性 bool 的 activation 路径不变。harness 新增正例 `scriptOwnedEffectVisibilityKeepsLayerAdmitted`（脚本 owner 存在时层仍被 claim，所有 stage 为 resolved）。

验证：graph executor harness ALL OK，Debug build 成功；隔离运行 report SHA-256 `c49ed52e6d0505988c844f2ba747dce09ae1e2ea383ec755b6c0d867323593b8`：`3233141951` 由 32 个 admitted-generic + 4 个 not-admitted 变为 36 个 admitted-generic，executor claimed 16→18，严格 PASS；`2824109832` 由 15+1 变为 16 个 admitted-generic，claimed 2→3，严格 PASS；`2775915974` 与上一批一致。剩余债务：脚本对 effect 可见性的实时控制（静音淡出、12 小时制切换）仍未执行，需要一个 typed bool producer 才能进入 activation policy；两样本视觉裁决未改变。

<a id="e-p1-default-straight-color-boundary-graph-ingress"></a>
## E-P1-DEFAULT-STRAIGHT-COLOR-BOUNDARY-GRAPH-INGRESS：fallback 保持 dormant graph input 事实（2026-09-09）

### 首断点与收窄修正

本批承接上一节的 default straight boundary。`SceneResolvedMaterialShaderSchema` 在精确颜色降低失败后采用 `defaultStraightColorBoundary([0])` 时，fallback transfer 没有把单一 graph-input carrier 还原到 graph-input source facts；source 侧的 `straightAlphaPreserving(textureSlot: 0)` 因而与 frontend 侧的空事实发生 `samplerBindingIdentityMismatch`。修正位于 `MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/MaterialProgram/SceneResolvedMaterialShaderSchema+SamplerPurpose.swift`：只有 `defaultStraightColorBoundary` 恰好包含一个 slot 时才映射回该 carrier，multi-slot 仍返回未知；没有新增 sample/layer/path/hash 分支，也没有改动显式 graph、implicit sampler、resource registry、property、provider、GraphTargets、GraphExecutor 或 compositor owner。

回归门位于 `script/tests/test_scene_resolved_material_program_finalizer.py` 的 `dormantGraphInputFactTokens`，用同一个 template 对比 source `straightAlphaPreserving(0)` 与 frontend `defaultStraightColorBoundary([0])`，要求 facts 完全相等且 provenance 为 `dormantUnresolvedMaterialAlias`。本轮 finalizer **24/24 PASS**（`defaultBoundaryPreservesGraphFact=preserved`），generic artifact default-boundary 定向测试 **1/1 PASS**，template 测试 **5/5 PASS**；checkpoint Debug build **BUILD SUCCEEDED**。

### 隔离运行证据

输入为只读真实样本 `3749463715` 的隔离副本 `/private/tmp/mwx-graphfix-run`，matrix SHA-256 为 `2a2428fccd05051d433039a0b20ed210738aea430694bae8bff477c96ede3de8`。运行使用签名 Developer ID Debug App：bundle `com.songziqiang.MyWallpaperX`、version `2.0.9 (277)`、Team `H9QWU9XN8R`、CDHash `bdf87b1f5bcae7ee5d10e0a5cfad0cc99f85878e`、executable SHA-256 `d03b09c50d3c651127c792783ab5e15d3756f0b133861b0ad0a027ea6a1ae85a`。7 秒 benchmark 的 report 为 `/private/tmp/mwx-graphfix-run/report.json`，SHA-256 `98b09a9ce1fc0dd3efa4c8017b1f3bd6afa584caba75f1d7b862937e08f9012e`；app.log `b80f0ea8718cd8683cb7d0dd3e9675d3221c90f03baa8afb9ce511c4222217f8`，scene-preview.log `baa6ab0d046ae72fb8a8988f9f20dac2f5cde640d84c11d3f216f1092a568f`，scene-runtime-evidence.json `47d12c351140c379f5f3ceafbcfa8088413a1569564b424810e0d435344f9ccb`。

正式 matrix 仍为 **0/1 NON-PASS**，不是本批的失败证据：layer `467` effect 0 的 `cutout_vignette` 仍在 Metal library compilation 因 float3/float2 implicit conversion 失败，layer `536` effect 1 opacity 仍是 `effect-local-passthrough-material-generic-owner-revoked`。本批目标 `536#effect#553`（`effects/workshop/2342779250/test_shader/effect.json`）已经是 `admitted-generic / resolved-material / profile=program`；effect CPU invocation 是 `resolved-material-graph / encoded-output`。frame 0（transaction `r4:1:9:0`）和 next-frame（`r4:1:24:0`）均为 1 authored / 1 material / 0 copy / 0 swap / 0 compose / 0 rejected，`outcome=succeeded`、`gpuCompletion=completed`，两帧共用 Program identity `43ee766ff47f1df07b25121be9f51459b796e77ca32e013f18a9b0206fd5822f`，并完成 exact publication；graph input 记录为 `slot0:dormantUnresolvedMaterialAlias:layerSource:536`，目标日志没有 `samplerBindingIdentityMismatch` 或 `graph-input-source-fact-divergence`。整次 GraphExecutor 为 `90 claimed / 90 encoded / 90 GPU encoded / 0 failure / 0 local fallback`，15 个 required layer 全部进入 exact-backend complete 集合。

隔离 shader cache 没有提供 generic artifact，所以 frame execution 日志的 backend 是共享 `boundedSwift`；这条证据只证明共同 resolved-material graph executor 的 ingress、Program identity、publication、GPU completion 与 next-frame，不升级为 `genericCompilerArtifact`、独立 ROI、官方预览等价或视觉 parity。ready/after/preview 图片仅作为运行 provenance；当前下一项按真实首断点处理 layer `467` library compilation，另行追踪 layer `536` effect 1 的 opacity local fallback。证据来源分类为 `authored-corpus-observation`（只读样本）与 `MyWallpaperX-current-evidence`（当前代码、测试、构建和运行），本批不需要 Ghidra、Mirage 或官方黑盒研究。

<a id="e-p1-vector2-interface-arithmetic"></a>
## E-P1-VECTOR2-INTERFACE-ARITHMETIC：声明向量二维运算的 backend 收窄（2026-09-09）

### 首断点与公共修正

上一批把 layer `467#effect#480` 的 `cutout_vignette` 记录为 Metal library compilation：作者 shader 声明 `varying vec3 v_TexCoord`，却将它与 `CAST2(u_offset)` 直接相减，SPIRV-Cross 结果保留 float3/float2 implicit conversion。`SceneAuthoredShaderBackendCanonicalizer` 现在在统一 backend 输入阶段识别精确声明的 `uniform|attribute|varying vec3/vec4` 名称，对直接 `+/- CAST2(...)` 或 `vec2(...)` 操作使用 `.xy`；局部变量、复合表达式、未证明形状以及超出 512 KiB source budget 的输入不改写，仍返回原始 pair。该修正只触达共享 canonicalizer，不新增样本/图层/路径/hash 路由。

回归门是 `script/tests/test_scene_generic_shader_program_artifact.py` **78/78 PASS**（含 interface 收窄与 local/compound 保留）和 `script/tests/test_scene_shader_scalar_vector_builtin_canonicalization.py` **2/2 PASS**；同批 default-boundary 的 finalizer **24/24 PASS**、template **5/5 PASS**，checkpoint Debug build **BUILD SUCCEEDED**。针对真实 shader 的 normalized fragment 证据为 `9faadd66790a32a7af8651063eb237932d70a37b970842f3294527b63c06281e.fragment.normalized.glsl`，SHA-256 `d96212f4d1bbf65028d6030298944ded6787512c36361cdacc6be986189aed8f`，第 133 行已是 `length(abs(v_TexCoord.xy - CAST2(u_offset)) * 1.0)`。

### 隔离运行与下一断点

输入仍是只读真实样本 `3749463715`（runtime copy `/private/tmp/mwx-vector2-run/runtime/runtime-samples/3749463715`，project SHA-256 `35392a2d2b9fd901079f7c248a9e5a58850608b0e01cb7dd90dfcfec64603bbf`，package SHA-256 `777305ee38bdcdace9a7a6e0f942d01952e9318558de38c024336e662e985ae7`），运行输出 `/private/tmp/mwx-vector2-run`。实际 App 为 `com.songziqiang.MyWallpaperX`、version `2.0.9 (277)`、Team `H9QWU9XN8R`、CDHash `a35ce7e9574c39aec62c4a76075ae0c59664e3fa`、executable SHA-256 `8d7234a0d6cbab68818fa7bf7729f71f49b55c1c6bb3c4e04314b681a08f487c`；source bundle `/private/tmp/mwx-derived-vector2/Build/Products/Debug/MyWallpaperX.app`，runtime bundle 使用同一签名身份并通过 before/after verification。

7 秒 strict benchmark 仍为 **0/1 NON-PASS**，失败集合为 `effect execution route operation failed`、accepted layer `467` 缺 GPU/compositor/next-frame/exact-backend evidence、`resolved material graph observation diagnostic reported` 和 `utility capture execution below planned count`。effect admission 变为 **37/37 admitted-generic、37/37 complete**，resolved-material capability 为 **16 accepted / 0 rejected**；其中 layer `560` fluid-simulation 也因同一公共 canonicalizer 进入 generic graph，utility capture 成功，不能将 accepted 变化解释成 layer 467 单层 parity。utility planned `4`，succeeded `[488, 536, 560]`，failed `[467]`。

layer `467#effect#480` 的 runtime generic state 已是 `genericCompilerArtifact`，并且 app log 不再出现该 effect 的 float3/float2 library rejection；但同层 `467#effect#500` motionblur 在 frame preflight 触发 `captured-main-color-contract-unproven`，安装 layer-local fallback，最终 route operation 为 `unclaimed-effect-product-authority / unclaimed-visible-effects-route-unavailable`。因此 layer 467 整体仍没有 graph terminal evidence。GraphExecutor 汇总为 **15 claimed / 15 encoded / 15 GPU encoded / 0 failure / 1 local fallback**，其余 15 个 accepted layer 均有 GPU completion、compositor consumption、next-frame 和 exact backend 记录。

layer `536` 的 `536#effect#553` 与 `536#effect#555` 在 frame 0/next-frame 均成功：每个 graph 1 authored / 1 material / 0 rejected、`outcome=succeeded`、`gpuCompletion=completed`；Program identity 分别为 `43ee766ff47f1df07b25121be9f51459b796e77ca32e013f18a9b0206fd5822f` 与 `cc79a2f473514cb6bbbba415f3b15f2612ebde4d0cca39529304a2f77ee3a9a1`。报告为 `/private/tmp/mwx-vector2-run/report.json`（SHA-256 `bfb07181ad006b4570220158bfb7238c126563d526aab2b2739a512d81ab702b`），app.log `911298831e141bb5ad20a665e0134bfc62d9630a39e406aef4284d9f1d7a193b`，scene-preview.log `8cf1d37c14c3bcd88ba38e93cb4cd4aad8a59c9dd96cf694d8c60348f4a11a9b`，scene-runtime-evidence.json `47d12c351140c379f5f3ceafbcfa8088413a1569564b424810e0d435344f9ccb`。

结论上限：本批闭合了 `467#effect#480` 的 backend vector2 arithmetic library compilation 输入断点，并证明统一 canonicalizer 不破坏既有 lowering；没有闭合 layer 467 的 effect 1 颜色合同、整层 route、独立 ROI、官方预览等价或视觉 parity。下一次应以 `captured-main-color-contract-unproven` 为首断点，先取得该 motionblur 输出颜色事实和 owner 边界，再决定是否改公共颜色 analyzer；不要为恢复 layer 467 而加入样本专用分支。证据来源分类为 `authored-corpus-observation` 与 `MyWallpaperX-current-evidence`，本批不需要 Ghidra、Mirage 或官方黑盒研究。

## E-P1-DEFAULT-STRAIGHT-COLOR-BOUNDARY：未证明的普通颜色 pass 按官方默认 straight 边界执行（2026-09-08）

隔离运行 `3750813609`（text layer 358 的 effect 360）、`3662790108`（solar system 的 48 次 `compiler-artifact-colortransfer` 拒绝、9 个 effect passthrough）与 `3768020435`（2 次 colortransfer 拒绝）时，generic 路线的 SPIRV-Cross MSL 已经编译成功，但 `SceneGenericShaderArtifactBuilder` 只接受 analyzer 能精确证明的颜色形状（straight-alpha、straight-alpha-preserving、generated/opaque 等 profile 的逐形状降低），任何未被证明的 straight 家族形状都以 `Failure.colorTransfer` 拒绝整个 artifact，effect 退回 previous-current。这是路线 §5.1 已批准替换的"analyzer 证明优先"策略：普通 effect 的作者数学本来就按 straight 颜色输入与一次 premultiply 输出运行，不需要逐形状证明。

现在 `SceneShaderColorTransfer` 新增 `defaultStraightColorBoundary(textureSlots:)`，`permitsDefaultStraightColorBoundary` 只覆盖 straight 家族（unresolved/straightAlpha/straightAlphaPreserving/straightAlphaUNorm/generatedStraightAlpha/opaqueFromStraightColor）；`prepareColorTransfer` 先走原有精确降低（改名 `prepareProvenColorTransfer`），精确降低以 colorTransfer 失败且 expected 合同为空或 straight-alpha-preserving 时，由 `SceneGenericShaderDefaultStraightColorBoundaryLowering.lower` 接管：边界集合内每个 `g_TextureN.sample` 调用包 `mwxGenericUnpremultiply`，每个 `return out;` 前插入一次 `mwxGenericPremultiply(out.mwxFragColor)`，再插入既有 helper 对；已含 helper、缺 `return out;`、缺 `out.mwxFragColor` 或 `using namespace metal;` 不唯一的源不接管。边界集合由 artifact cache 按 analyzer 分类计算（graph input slots ∪ 已证明的 premultiplied provider slots），进入 request key（`mwx-generic-shader-request-v12`）、artifact 解码（`default-straight-color-boundary` + sorted unique slots ⊂ [0,8)）、Program identity（`default-straight-boundary-<slots>`）与 `resolveColor`（每个边界 slot 表示为 premultipliedAlpha 输入、输出 premultipliedAlpha）。独立 alpha 信号家族与 expected 信号 profile 仍 fail-closed；bounded Swift frontend 回退不变。

验证：`test_scene_generic_shader_program_artifact` 77 用例 ALL OK——新增 `test_product_builder_applies_default_straight_boundary_to_unproven_color`（正例：source 采样被 unpremultiply、mask 采样不动、两条 return 都 premultiply、helper 对存在、已证明形状保持精确 kind；反例：缺 return、helper 冲突、信号 expected 合同仍拒绝；analyzer 判为 straightAlpha 但精确降低失败时回退默认边界），原有 33 处 straight 家族"精确降低失败即拒绝"的反例改为 `exactColorTransferRejected`（精确 profile 未认领：colorTransfer 失败、默认边界接管或采样槽超出反射被判 textureUnused），provider spatial-weighted 的 request key 期待加入边界槽 `(0,)`；受影响 source set 映射的 45 个 focused 模块中 44 个 PASS：`test_scene_typed_data_rgb_filter` 的 9 个 compiler drift 反例同样改为 `exactTransferUnclaimed`（drift 后的 compiler 输出不再被 typed-data 精确 profile 认领，而是进入默认边界），`test_scene_standard_alpha_composite_generic_contract` 的 `normalizedOverlapPrefersPassthrough` 在 HEAD 干净 worktree 中同样失败，属并发提交造成的既有漂移，不在本批范围。Debug build 成功，code health PASS。当前 App CDHash `7336f3f561ff35e733130a4ef97a3c742481a55d`、executable SHA-256 `b74cb1c11976eb3b85b2ca6d32aac9f3d6c02a90abe3623f316a94592a62d33e`。三样本并行重跑：`3750813609` report `b89064e2fcf1b6f5ae4497ae78ce83c5fb7a0f001032b9aed9f781564888e82d` 由 2 次 colortransfer 拒绝 + 1 个 color-contract passthrough 变为 0 拒绝 0 passthrough，claimed/encoded 2，严格 PASS，after PNG `72c80fd0e26aa5073c38a6ad8d90f78dccd5250f4a4b9bffab227261a6f15a78`；`3662790108` report `2aa52b746c4d521ba27c63862c115acef20fc036b0feb13599f3cf17a840f64d` 的 colortransfer 拒绝 48→0，passthrough 9→8，剩余 8 个全部是 `compiler-artifact-loopunbounded`（8→24 次，越过颜色阶段后撞上 `SceneGenericShaderBoundedLoopWork` 的嵌套循环/64 上限预算），claimed 23；`3768020435` report `25f2557f52f69c0d299677a884397044ba79f2b6cbe124955afeb376eaa7a6d4` 的 colortransfer 拒绝 2→0，剩余 1 个 passthrough 来自 2 次 `compiler-tool-stage-link-rejected`（glslang stage link 失败，诊断只给临时路径），claimed 3。

截图裁决：`3750813609` 修前（fallback probe）与修后 after PNG 与作者 preview 对照，山寺构图、雾、落叶一致，但时钟数字在两次运行中都呈灰黑渐变而 preview 为白色发光、雨丝更淡；该 effect 由 passthrough 转为执行没有改变画面，说明数字颜色的首断点在 text layer 358 的 effect 链（360/391）输出而非颜色合同，人工裁决记为 fail（`scene_sample_acceptance_verdicts.json`）。结论上限：只闭合"未证明的 straight 颜色形状不再拒绝整个 artifact"这一公共首断点；loop 预算、glslang stage-link 与文本 effect 链是三个独立首断点。
