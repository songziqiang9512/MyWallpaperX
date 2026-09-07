# Scene authored sample debug ledger

> 这是一份可复查的运行首断点档案，不是视觉通过矩阵。样本根只读，档案只记录 authored corpus 的 identity、运行状态和可定位证据；最终“正确显示和播放”仍须逐样本人工/ROI 验收。

## 2026-09-08 current corpus probe

### 用户可见失败待办（按当前复现更新，不以公共修复代替逐项验收）

以下均以真实播放截图/事件恢复正常为验收，不以历史 probe 状态覆盖用户反馈。每项修复须补共享首断点及 next-frame/event 证据。

| 样本 | 待修复的用户可见问题 | 首轮区分证据 | 状态 |
|---|---|---|---|
| 3264246690 | 人物偏上、头部出画；左肘缺块 | 当前截图头部在画内、左肘缺块仍在；不能据此判定构图正确 | 未通过 |
| 3765760121 | 上下颠倒 | utility model/投影策略不一致已修；默认鱼眼开启的当前截图恢复正向，见 E-V4-UTILITY-CAMERA-CONSISTENCY | 倒置修复，整样本未全面验收 |
| 3780119725 | 人物压缩/缺块、脸部疑似遮罩线外露 | fallback extent 与 fractional additive selector 已修；当前运行已选中 7 个动画片段且人物不再压缩，脸部黑线/缺块仍在 | 部分修复，未通过 |
| 1315486372 | 水波位置不正确、光线贴图效果生硬 | 已留当前播放截图，effect-local 坐标与辅助纹理仍待定位 | 未通过 |
| 2775915974 | 鼠标纵向响应反向；顶部边缘失去识别并回中 | 两个公共输入错误已修并有实际鼠标事件/截图；顶部极限露灰边仍未解决，见下方 anchor | 输入修复，整样本未通过 |
| 3747492842 | 文字错位、额外闪烁、光束应在顶部却在中间 | 静态文字已部分修复；音频静音/真实输入及 quad 几何分开检查 | 未通过 |
| 3470948192 | 开场/文字错位、后续 NaN 与异常背景 | 日期和初始字形已部分修复；共享坐标 producer→consumer | 未通过 |
| 3509243656 | 开场/模拟画面不正常、坐标文字异常 | 延长播放及 MAIN producer→共享状态→文字 | 未通过 |

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

## E-V4-PUPPET-FRACTIONAL-ADDITIVE：动画权重进入 selector（2026-09-08）

`3780119725` 的 authored layer21 含 blend `0.63` 与 `0.19` 的可见 additive animation。旧 selector 只接受 `blend == 1`，在真实 producer→selector→evaluator 链上提前拒绝该层组合；现改为接受有限 `0 < blend <= 1`，保留 blendIn/blendOut、rate、visibility 与 unknown-animation 的硬边界，evaluator 继续按权重叠加。41 个 puppet animation/mesh tests（2 个环境跳过）通过；隔离异步运行日志显示 layer21 选中 7 个片段、GPU completion/compositor publication/next-frame 成立，人物不再压缩。脸部黑线与缺块仍存在，尚未证明 mesh UV、mask/effect 或 authored 内容等后续 owner 正确。

补充的最小网格观测：该样本 MDLV0023 layer21 网格为 13,782 顶点，UV 约为 `0.014..1.0025`；同目录其他 MDLV0023 Puppet 资产观测范围约为 `-0.0045..1.005`。这排除了“UV 全局解析成异常范围”作为当前黑线首断点，但不排除 atlas 边缘采样、重组后 logical extent 与 mask/effect 坐标不一致。

当前 after 截图显示黑线直接叠在人物面部、躯干及右下枝条区域，而 authored 参考截图没有同样的整段黑色笔画；这使“重组 source 已含黑线”与“后续 opacity/shake/waterwaves/foliagesway mask/effect 错误消费 source”仍需隔离，尚不能关闭任一 owner。下一次实验应只比较重组 source 的 publication 与 effect graph consumer，不通过关闭作者效果来伪造验收。

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

159 个样本有可复查 triage，不等于正确播放。异步线程交接修复只关闭上面有截图支持的日期文字首断点；继续检查 shared-state producer 未进入 Program、静态文字布局及用户新增的光照/闪烁，不以同步 probe、构建成功或离开开场宣称通过。尚无必要启动官方客户端逆向研究。
