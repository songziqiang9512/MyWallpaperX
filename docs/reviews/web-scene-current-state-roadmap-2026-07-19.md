# MyWallpaperX Web 与 Scene 当前状况评估及演进路线

> 评估日期：2026-07-19，Web 状态更新至 2026-07-22，Scene 状态更新至 2026-07-23
> 评估对象：当前仓库中的 Steam Workshop Web 与 Wallpaper Engine Scene 实现  
> 文档性质：当前事实、差距评估和后续验收路线。历史计划与历史回归记录只作为证据，不反向覆盖当前代码。

## 1. 执行摘要

### Web

Web 已经具备可持续回归的正式运行主链。文件属性类型推断与跨重启恢复、强 DOM/视觉/交互证据、纹理 WebGL 的 loopback 路由、旧式颜色数组兼容、空 `file:///` 占位符处理、境外远程样式降级恢复、真实 64+64 双声道频谱及 Wallpaper Engine 兼容幅度响应、固定样本矩阵、签名 Debug App 身份门、切换/停止释放门禁、重叠系统中断恢复门、CoreAudio 配置失效重建和 Space 通知路由均已落地。

当前固定矩阵包含 10 个真实 Workshop 样本，覆盖 file/directory、dependency、媒体、Canvas、WebGL/WebGL2、Live2D、WASM、iframe、持久化存储、音频、指针输入和动态画面。最新隔离运行结果为 **10 个 A，平均 98.2，证据覆盖 94.3%，矩阵门禁通过**。每个 App 进程使用唯一 Debug UserDefaults suite，日志必须确认 suite，结束后必须删除；因此结果不再继承用户在产品 UI 中保存的样本属性。另外 5 个作者公开源码样本的独立门覆盖属性密集、Worker、音频频谱、约 33 MB 生成脚本和复杂 WebGL 动画；其中 `1396475780` 的大型脚本还验证了 Service Worker 静态识别，当前最终结果为 **5 个 A，平均 98.8，证据覆盖 97.9%**；3 个 Steam CDN 代表样本覆盖响应式 Canvas、手工三视口 WebGL 和 CoinGecko 实时数据，当前最终结果为 **3 个 A，平均 98.0，证据覆盖 94.8%**。

当前本机 34 个 Web 样本已固化为完整基线。2026-07-20 构建的长批次为 **34 个 A，平均 98.2，证据覆盖 93.3%，完整门通过**；同一构建的作者源码和 Steam CDN 批次分别为 5A 与 3A。这组结果继续作为历史基线，但不再代表当前最终 HEAD。

2026-07-22 首轮 34 项完整门的 28A/6B 失败已完成归因和修正：4 个无 `applyUserProperties` listener 的样本移除错误 `properties` 标签；无需属性桥的样本不再被记为 weak coverage；当前 listener 与当前 payload 的 DOM 应用签名可作为正向属性证据；完整门最低观察窗提升为 18 秒；Debug evidence 窗口会进入当前 Space 并成为 key，避免 WebKit 因 `isOnScreen=0` 停止 `requestAnimationFrame`。这些修正没有放宽评分阈值、隐藏错误或修改样本源码。

当前最终签名 Debug App 的同构建结果为：**34/34 可运行、32A/2B、平均 97.7、证据覆盖 95.9%，完整门通过**；作者源码门为 **5A / 98.8 / 97.9%**，Steam CDN 门为 **3A / 98.0 / 94.8%**，三组 App 身份均为 Team ID `H9QWU9XN8R`、CDHash `f3eb94e6f511403263775b7ee8e04f3fdc0ceb30`、可执行文件 SHA-256 `5278316bbc5ca6d5b22c8b014380ebdb857c1635a107a04f2b38a52bd40bd7db`。`3700131876`、`3700928191` 仍保留样本脚本属性错误和 B 等级，只因矩阵明确允许该既有短板而不阻断批次；其余非空 shortfall 均与各样本允许例外一致。

Web 目前没有已确认的宿主 P0 阻断，当前 HEAD 的 34+5+3 已知样本功能兼容主链和系统音频到 JS 主链可以视为闭环，但仍不能称为发布级“最终完全闭环”。确定性锁屏、重叠休眠、采集配置失效恢复、Space 通知中心路由/观察者释放和当前非沙盒发行链的 file/directory 服务持久化已关闭；真实 OS 电源周期、物理 Space/显示器与音频设备变化、runtime 互切、性能和长期运行预算、真实文件选择器 UI 与签名沙盒授权回归，以及 CI/发布流程接入仍未完成。按本文八项能力门重算，当前工程成熟度仍约为 **90/100**。

### Scene

Scene 已建立独立模块、PKGV 读取、受控缓存、typed interpretation、纹理解码、Metal 渲染和桌面宿主。当前链路为 interpretation v20：v15 保真保存 EffectDefinition，v16 把可见 layer/effect 编译为 authored graph，v17 加入 provider/resource metadata，v18 持久化 property binding program 与 effective values，v19 加入 loss-preserving `ShaderContract`，v20 再把通过 strict execution catalog 的 Local Contrast strength scalar target 写入同一 binding program。`8474ace` 已安全保留 13 个隔离样本中 173 份 shader contract（143 authored、30 host built-in）、286 个 stage、155 个 include、1523 个 annotation 和 2660 个 declaration，原始 source/hash 与 canonical identity 均进入合同，诊断为 0；这些合同本身仍只是 L1 识别/保留。renderer 当前消费三个严格注册的 graph profile：precise Blur、standard-default Blur，以及 `136d35c` 新增的 stock Local Contrast。后者只接受 exact 单 effect、4 个 material pass、两个 scale=4 non-unique `rgba8888` RT、KERNEL0/GREYSCALE0/MASK0、Gaussian `scale=(1,1)`（含官方缺省）和三份 exact shader fingerprint；Metal 依次执行 alpha-weighted 4-tap downsample、13-tap Gaussian X/Y 与 `albedo + (albedo - blurred) * strength`，保留原 alpha，并让合法 strength `0...5` 从 per-surface snapshot 无重建进入 GPU。fingerprint 只用于准入，实际仍调用项目内手写 MSL，不预处理、翻译或编译 authored source。target table 按完整 effect identity、plan、extent 与 format 复用，跨 effect 隔离，resize/format 变化采用候选成功后再替换的事务；96 MiB 只表示事务提交后的 cache residency 上限，不是瞬时 VRAM 硬上限。typed texture registry 也已支持 layer/named/property/system identity、provider 状态、静态 resource generation、named frame epoch 和属性缺失时的 authored fallback。文件型 `sceneTexture` 的首个产品切片已经接通 PNG/JPEG 选择、按壁纸 bookmark、限时 security scope、逐屏 Metal 解码上传和失败回退，但只开放给当前实际可执行的静态 image-blend property consumer。其他 current-prefix、named dependency、静态 blend 和手写 effect 仍是 bounded GPU 路径。这不是任意 graph、material、shader 或完整 sceneTexture/media executor。

当前正式语义矩阵 `.codex/scene-local-contrast-final13-20260723/report.json` 为 **13/13 通过**，定向正反门 `.codex/scene-local-contrast-targeted-20260723/report.json` 为 **2/2**。definition/graph 结构基线仍为 106 definitions、182 passes、179 material passes、50 FBO，以及 197 layer plans、300 effects、411 nodes、76 RT；5 个 blocker 仍集中在 `3723344874` fluid layer。正式矩阵合计 8 个 authored graph layer GPU succeeded、0 failed、3 个 legacy blocked、35 个 route-only effect；`2902406982` 的 graph 成功层为 `[167,177,530]`，其中 `167/177` 是 2 个 stock Local Contrast，`brcontraststrength=3.0` live 更新保持同一 surface/window，前后画面 changed ratio 为 `0.7587968`。`2938612768` 的可见 4/5-effect mixed chains 保持 Local Contrast count 0、graph succeeded/failed 均为空，既有 static image blend 仍为 **5/5**，证明 strict profile 没有误吞混合链。宿主级 `SceneFrameTiming` / `SceneFrameContext` 已统一所有屏幕的 frame index、host/scene/wall time；B0 live-property 主链现已覆盖 layer alpha、solid-only layer color 与 exact strict Local Contrast strength consumer。当前 Scene 全量测试共运行 **239 项、238 项通过、1 项跳过**。签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `f1fb8e1a4f65f64e869d82c064f4f31f9f5faae5`、可执行文件 SHA-256 `54b2b8e56c4ed7deda640caddfbd379c366a54335cf1253291956f3d24a608fe`。现有运行报告证明 live update 被接受、identity 不变并产生可见变化，snapshot/GPU 单元门证明 strength 参与计算，但报告尚未直接遥测 `3.0` 的 uniform upload；Metal 采用 stock shader 的非 `HLSL_SM30` 采样语义，也没有 Windows pixel golden。pause/resume、delta clamp、fixed timestep、generic scheduler、history/copy/swap/compose/condition/function，以及 ShaderContract 的通用预处理与执行仍未完成。下一主切片先建设 B2 generic scheduler/effect-chain/read-write execution skeleton，B1 Provider Core 的 dynamic generation、metadata 与 cancellation 并行推进；逐项等级与缺口见 [Scene 官方语义与实现覆盖台账](../scene/semantics/coverage-ledger.md)，执行顺序见 [Scene 播放能力开发计划](../scene/scene-capability-development-plan-2026-07-22.md)。

## 2. 评估口径与证据边界

本评估采用以下证据：

1. 当前 Web/Scene 源码与模块调用路径。
2. [Web 壁纸运行能力评测标准](../web/web-wallpaper-benchmark-standard.md)。
3. [Web 样本 handoff](../web/regression/WEB_SAMPLE_HANDOFF_2026-06-19.md) 中尚未关闭的问题。
4. [Scene Runtime 技术设计](../scene/scene-runtime-design-2026-05-15.md) 保留的历史架构边界及其现役状态指针。
5. 2026-07-20 对当前 Debug App 的 10 项固定矩阵、5 项作者源码外部矩阵、3 项 Steam CDN 代表矩阵、34 项全量扫描和三段生命周期隔离运行结果。
6. [Web 外部代表样本基线](../web/regression/WEB_EXTERNAL_SAMPLE_BASELINE_2026-07-20.md) 中的来源、revision、能力覆盖和证据边界。
7. [Web Steam 代表样本基线](../web/regression/WEB_STEAM_REPRESENTATIVE_BASELINE_2026-07-20.md) 中的 Steam CDN 快照、响应式/多视口/联网能力和证据边界。
8. 提交 `3a5ef15` 的远程字体硬失败恢复、慢响应、iframe、HTTP HEAD/Range 和 34 项完整门报告。
9. 提交 `3b69614` 的纯信号测试、受控 `afplay` 双声道频率测试、音频需求生命周期、10 项固定门和 34 项完整门报告。
10. 2026-07-21 的 Web 音频幅度回归测试：`884307090` 圆环/直线两种属性模式分别为 96 / A，`1509243786` 确定性频谱和真实 `afplay` 两次均为 100 / A；报告保存在 `.codex/web-audio-calibration-20260721/`。
11. 2026-07-21 的系统中断恢复门：`1509243786` 在系统睡眠与显示器休眠重叠、部分唤醒、最终唤醒、锁屏/解锁后均按需停止和恢复采集；最终通过报告保存在 `.codex/web-system-state-final-20260721/results-pass2/`，首次失败口径报告也保留在同目录的 `results/` 供复核。
12. 2026-07-21 的 CoreAudio 配置失效恢复门：突发三次失效合并为一次重建，单次失效触发第二次重建，三代监听与真实 PCM 均恢复且最终资源归零；最终报告保存在 `.codex/web-audio-restart-final-20260721/results-pass/`。首次立即重建触发 CoreAudio `!obj` 的失败报告保存在同目录的 `results/`，用于证明 1 秒 teardown settle window 的根因，而不是删除失败证据。
13. 2026-07-21 的 file/directory 持久化门：生产更新、A/B/A 切换、外部 file/directory 实际改名、跨进程 bookmark 恢复、reset 和再次重启均通过；最终独立偏好域报告保存在 `.codex/web-property-persistence-final-20260721/results-suite-pass/`。
14. 2026-07-21 的 Debug 偏好隔离门：`HOME/CFFIXED_USER_HOME` 不能隔离进程外 `cfprefsd`，现改为每次 App 启动显式传唯一 Debug suite 并由 scorer 校验、结束后删除；最新 10 项矩阵为 10A / 98.2 / 94.3%，报告保存在 `.codex/web-defaults-isolation-final-20260721/matrix-regression/`，10/10 suite 均已删除且标准偏好摘要未变化。
15. 2026-07-21 的 Space/屏幕 observer 门：`NSWorkspace.activeSpaceDidChangeNotification` 改由 `NSWorkspace.shared.notificationCenter` 注册并从原 center 释放；default center 反向 0 次、两次 workspace 通知各 1 次、3 次屏幕参数通知合并为 1 次协调、stop 后回调为 0，最终报告保存在 `.codex/web-space-lifecycle-final-20260721/results-pass2/`。首轮 19 秒窗口在 `completed` 前约 0.4 秒结束的失败报告保存在 `results-pass/`，用于证明门禁时长修正，不删除失败证据。
16. 2026-07-21 的截图证据身份门：benchmark 先严格验证并隔离复制签名 Debug App，运行后复核 bundle ID、Team ID、CDHash、版本和可执行文件 SHA-256；`3700131876` 在隔离 Workshop root/HOME 下取得 ready 与 after-interaction 的 WebView、Canvas、当前进程窗口三源快照，窗口截图肉眼确认非空。单样本结果为 92 / A、coverage 90.3%，既有 `properties.error` 仍按短板保留；报告保存在 `.codex/web-wallpaper-benchmark-capture-final-20260721/`。
17. 2026-07-22 的当前 HEAD 34 项完整门：34/34 可运行，28A/6B，平均 96.3，coverage 94.7%，矩阵门失败；报告保存在 `.codex/web-full-final-20260722/`。
18. 2026-07-22 的 9 项属性证据定向复跑：完全复现 4 个属性 B、3 个 coverage-only 失败和 2 个既有允许例外，排除长批次偶发；报告保存在 `.codex/web-full-targeted-retry-20260722/`。
19. 2026-07-22 的当前最终 34 项完整门：32A/2B，平均 97.7，coverage 95.9%，矩阵门通过；报告保存在 `.codex/web-full-final-pass-20260722/`。
20. 2026-07-22 的当前最终作者源码门：5A，平均 98.8，coverage 97.9%，矩阵门通过；报告保存在 `.codex/web-external-final-pass2-20260722/`。
21. 2026-07-22 的当前最终 Steam CDN 门：3A，平均 98.0，coverage 94.8%，矩阵门通过；报告保存在 `.codex/web-steam-final-pass-20260722/`。
22. 2026-07-22 的首批 Scene 自动门：SteamCMD 隔离样本 `3723344874` 与 `3724095562` 均通过；前者 20/24 image texture、1 层真实 gaussian blur、2 层明确 route-only、两帧变化率 10.60%，后者 1/1 texture 且静态两帧一致；两者均有签名身份、非黑窗口和 stop 后 surface=0 证据。
23. 2026-07-22 的 Scene 扩充门：新增 `3722933264`、`3723230275`、`3723257973`、`3724289844`、`3724553795`，正式矩阵 7/7 通过；覆盖 126 层脚本密集场景、MP4 payload、particle layer 和音频声明。`3723230275` 的真实 Bloom GPU 链命中 1 层，另有 2 层 route-only；全矩阵加载率为 12.12% 到 100%，低值仍作为 built-in/SceneScript 缺口保留。
24. 2026-07-22 的 Scene 文本与相机门：包内字体静态 text layer 分别命中 3/3、10/10、4/4、3/3；7 项 projection 均为 cover，只有样本声明启用的 `3723230275`、`3723257973` 启用 parallax。静态样本变化率为 0，灰色边带已消失，边缘单色占比由 82.70% 降至 25.48%。
25. 2026-07-22 的 Scene precise blur 与复合链门：`3724289844` 三个文字层按作者 scale 命中真实两遍 precise blur；`3723230275` 的 2 个未完整支持复合层按可见 waterflow/waterripple/perspective/opacity pass 降级，不再读取层名或不可见 pulse。最终 7/7 通过。
26. 2026-07-22 的 Scene perspective/color blend 门：interpretation 升至 v6 并保留 layer `colorBlendMode`；`3723230275` 两层命中 perspective-opacity runtime 与 mode 9 additive composite，fallback 从 2 降至 0，截图无黑矩形。最终 7/7 通过。
27. 2026-07-22 的 Scene pass 元数据门：interpretation 升至 v7，effect/material 同时保留 nullable texture slots 与整数 combos。固定 `3723230275` 精确命中 effect 37 槽/20 空洞/17 combo、material 24 槽/8 空洞/12 combo；最终 7/7、83 个脚本测试、签名构建和代码健康门通过。
28. 2026-07-22 的 Scene normal-map waterripple 门：`3723230275` 两层从旧正弦切到作者 T2 normal 双采样，normal runtime 2、legacy 0，并继续通过 perspective/opacity/mode 9；`3724289844` 的 T1 mask 变体保持 legacy 1，没有被错误升级。最终 7/7、83 个脚本测试、签名构建和代码健康门通过。
29. 2026-07-22 的 Scene 真实用户样本入口与纹理门：`3766415113` 的 entry 同名 `gifscene.pkg`、TEX sequence 与单图 UV 路径通过，`3738202317` 的 BC2/DXT3 纹理为 1/1 加载；报告保存在 `.codex/scene-gifscene-sprite-gate-20260722/` 与 `.codex/scene-bc2-format6-final-20260722/`。
30. 2026-07-22 的 Scene 用户属性链：已解析 bool/slider/combo/color/textinput、group、display condition 与 combo option condition；当前可执行 target 覆盖 layer visibility、text、camera parallax 三项字段和已支持 effect 参数。覆盖值按 wallpaper 持久化，活动 Scene 受控重建，详情页通过独立可拖动窗口编辑；`3766387484` 的 parallax 关闭和 `2134765860` 的 text/day-night/custom text 定向门通过，报告保存在 `.codex/scene-property-parallax-off-gate-20260722/` 与 `.codex/scene-property-text-day-gate-pass-20260722/`。
31. 2026-07-22 的 Scene 作者粒子子集：parser、资源图、确定性 CPU simulation、Metal instancing、正交/透视相机和 layer 可见性/顺序/混合链已接通；当前支持包内 texture、sprite/sequence、continuous/burst initial、lifetime、opacity/color/size/rotation/velocity。`3742133044`、`3750813609`、`2998757800` 各有 1 个作者粒子层进入真实渲染，相关 7 项回归仍通过。
32. 2026-07-22 的 Scene 静态文字修正：文字 raster point size 按 authored `pointsize * 4`，vector padding 对称扩展 quad，系统字体别名、包内字体优先和缺失字体诊断已落地，interpretation 升至 v10。`3766387484` 的 3/3、`3122339805` 的 80/81、`2134765860` 的 4/6 text candidate 进入运行路径；画面尺寸已明显接近作者 preview，但动态时间/日期/媒体值仍缺 SceneScript。报告保存在 `.codex/scene-text-fixed-20260722/`。
33. 2026-07-22 的 Scene 证据截图修正：Debug benchmark 不再依赖 ScreenCaptureKit，而是在 renderer 完成当前帧编码后从 Metal drawable 回读 ready/after PNG；3 个文字样本和原 7 项矩阵均恢复稳定双帧证据。对应提交为 `f7293fb`。
34. 2026-07-22 的 Scene 当前正式语义门：矩阵扩至 11 个真实隔离样本，并对层级、有效可见性、作者/可见/隐藏粒子数、实际加载 layer ID、文字 layer ID、effect/resource 计数和 interpretation v10 建立逐样本合同。当前 **11/11 通过**，全部 `exit=0`、无 timeout、ready/after 非黑、stop 后 surface=0，样本副本无运行残留；对应提交为 `ca9bef8`。
35. 2026-07-22 的 Scene solid 主构图门：固定路径与 model JSON `solidlayer:true` 实例统一分类，interpretation 升至 v11；单个 1x1 白纹理通过通用 fragment 按作者 color/alpha 合成，不给普通 image/text 默认乘色。定向样本 **3/3**、正式矩阵 **11/11** 通过，solid `34/34`，image/solid 总加载从 `72/113` 提升到 `106/113`；`3122339805` 为 `90/90`，原中性灰底像素从 45.96% 降至 0.33%；对应提交为 `c8c463b`。
36. 2026-07-22 的 Scene utility current-frame capture 门：interpretation 升至 v12，typed composition/project/fullscreen、dependency ID、局部/full-frame geometry、受限离屏池、mask/partial fail-closed 和 GPU completion telemetry 已落地。四样本定向门 **4/4**，42 candidates 中 2 个 capture、26 dependency edges、18 named-target gaps；`2902406982` 的 layers `410/530` 均 GPU succeeded、0 failed。正式矩阵 **12/12**，17 candidates / 2 capture / 8 edges / 6 gaps，全部 ready/after 非黑、无 timeout、stop 后 surface=0、样本根无运行残留；对应提交为 `1517f4a`、`1f8f148`。这只证明受限 current-prefix 子集，不代表 named target 或 290 主构图已闭合。
37. 2026-07-22 的 Scene named dependency、effect 语义和粒子推进门：提交 `d881bb1`、`375c3ca`、`f223bd1`、`c2fd29b`、`b75a20f`、`f1493b2`、`ddd87e1`、`064c2e7` 依次落地 bounded named target/consumer、wrapped alpha、像素空间 coarse blur、作者参数驱动的单层 built-in UV foliage、typed effect `usertextures`、简单静态 image dependency blend、built-in drop 纹理和 velocity-aligned sprite trail；interpretation 升至 v14。当时的阶段矩阵 **13/13** 通过，image `180/181`、solid `54/54`、text `79/108`、particle `6/27`，named capture 7 成功/0 失败、binding 8 成功/1 失败，静态 image blend 1/1 成功。正式样本根为 `.codex/scene-matrix13-samples-20260722`，阶段报告保存在 `.codex/scene-particle-trail-formal13-projected-final-20260722/report.json`。这组门证明新增受限路径真实执行并未破坏矩阵合同，不证明任意 material/pass、完整 composition 或 Wallpaper Engine 画面一致性。
38. 2026-07-22 的 Scene binding、gradient clipping 与静态 blend 默认值闭环：提交 `b5a33f1`、`4ceb94d`、`687b45a` 依次保留数字型 shader binding components、执行严格的 gradient-color -> clipping-mask stack，并让符合边界的静态 image blend 服从作者默认值。当时的阶段矩阵为 **13/13**，named capture `8/8`、binding `9/9`、static image blend `3/3`，失败均为 0；仍有 1 个 named-target gap 和 34 个 route-only effect。阶段报告为 `.codex/scene-static-fallback-formal13-20260722/report.json`。
39. 2026-07-23 的 Scene composition parallax 纠偏：提交 `e635f11` 移除缺失 `parallaxDepth` 时伪造 `"1 1"` 的 fallback。包括 composition 在内，只有作者显式声明的非零 depth 才产生逐层位移；缺失和零值均不移动。
40. 2026-07-23 的 Scene EffectDefinition IR：提交 `6eadcf8` 将 interpretation 升至 v15，保真保存 106 个定义、182 个 pass、179 个 material pass、50 个 FBO，以及 copy/swap、compose、condition/function 和未知字段诊断；13/13 报告为 `.codex/scene-effect-ir-formal13-final-20260723/report.json`。这一步只证明定义可审计，不证明 pass 已执行。
41. 2026-07-23 的 Scene authored graph：提交 `c7a0745` 将 interpretation 升至 v16，在不改变现有 GPU 输出的前提下编译可见 effect graph；13/13 当前报告为 `.codex/scene-effect-graph-canonical-final-20260723/report.json`。矩阵以逐样本 canonical SHA 锁定图身份，共 411 个节点、76 个 RT、5 个明确 blocker；通用 Metal executor 尚未接入。
42. 2026-07-23 的 Scene precise-blur graph backend：material resolver、严格 topology/state/resource gate、GPU completion 和 legacy fail-closed 已接入。最终报告 `.codex/scene-authored-precise-final13-20260723/report.json` 为 13/13；成功层仅 `3724289844:[28,36]`、`3765760121:[68,76,82]`，失败 0，layer 20 的 blocked ID 已进入矩阵合同，隐藏候选不执行。签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `8ebc82484313c1435d1a914351b857438abeb167`、可执行文件 SHA-256 `42cbcfd0ccb954142636e1280e3db8dc48a350ea73c45503f55cbb224631e516`。
43. 2026-07-23 的 Scene standard Blur 默认 profile graph backend：严格 4-node/2-quarter-RT 图、alpha-aware downsample、13-tap 横纵 Gaussian、default combine、stock straight-alpha 到宿主 premultiplied 的边界转换、原子纹理预算与 legacy fail-closed 已接入。最终报告 `.codex/scene-standard-blur-alpha-final13-20260723/report.json` 为 13/13；graph GPU 成功层增至 `2902406982:[530]` 加既有 5 个 precise 层，失败 0，blocked layers 为 `20/348/358`，route-only effect 本轮观测合计 37。Scene 测试 123 项通过、1 项跳过，包含半透明端到端像素门；签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `213731693b84f258516bf669a62fc9c572874104`、可执行文件 SHA-256 `ad7319f137349474cc2c55879fc3b2f692a0e4719620428a4e9979f1dc5b279e`。这证明默认 profile 的受限 GPU 路径执行，不证明 WE 像素等价。
44. 2026-07-23 的 Scene typed texture registry/property fallback：interpretation 升至 v17，material usertexture 与每 slot 候选链、逐帧 typed registry、provider status/generation 和 runtime reference 分类已接入。`2938612768` 在空 `scenetexture` 属性下沿 authored fallback 执行 layers `[239,657,775,875,1509]`，5/5 成功；layers 775/875 分别回退 890/1174，775 仅使用 authored-initial alpha。`2902406982/2938612768` 的 missing resource 均为 0，但 293 仍有 named-target gap 1、route-only 18 和严重 waterwaves 视觉偏差。最终报告 `.codex/scene-texture-registry-final13-20260723/report.json` 为 13/13，Scene 测试 128 项通过、1 项跳过；签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `4cc52841ec1b938da574097a17f965fe4d410dc2`、可执行文件 SHA-256 `af632d2459225f803b252bd02cc493bddf2cf4dcc1982ce0e04f0c31d231c42b`。实际 sceneTexture 文件、`$mediaThumbnail`、Texture Variants 和 SceneScript 动态值仍未接入。
45. 2026-07-23 的 Scene file-backed `sceneTexture` 第一切片：属性窗口只为实际可执行的 texture property key 提供 PNG/JPEG picker；书签按 wallpaper/property 隔离，安全作用域只覆盖同步通知、逐屏解码/Metal 上传和后续屏幕重建，完成即释放。`2938612768` 隔离副本向 `newproperty25/26` 注入 200×200 PNG 后两张纹理均加载，static image blend 仍为 5/5、image 44/44；空值、坏图和不支持扩展名 fail closed 并保留 authored fallback。最终报告 `.codex/scene-user-texture-final13-r2-20260723/report.json` 为 13/13，Scene 测试共运行 134 项、133 项通过、1 项跳过。该报告保留为 file-property 定向证据，不再代表当前二进制身份。
46. 2026-07-23 的 Scene 统一帧上下文第一阶段：桌面宿主取代逐屏 Timer，每帧只采样一次 monotonic host time 与 wall date，并向所有 surface 广播相同 `SceneFrameTiming`；shader time、视频 host time、粒子 delta 和 parallax smoothing 统一消费该帧，屏幕参数重建不重置 runtime，切换 wallpaper 才重置。Scene 测试共运行 **138 项、137 项通过、1 项跳过**；最终 13 样本报告 `.codex/scene-frame-context-final13-20260723/report.json` 为 **13/13**，签名 App `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `f53f7d578e90afd3cb35934b2df1edd36cb95199`、可执行文件 SHA-256 `c6d9e6e75c9c3beab494a34cb98f73ebcb7fb119b4ef0d58b4a877b01ec628d7`。本阶段未实现 pause/resume、delta clamp、fixed timestep、Timeline、SceneScript 或动态文字。
47. 2026-07-23 的 Scene 程序化 built-in 粒子纹理第一批：对 `drop/fog1/leaves7/leaves8/light_shafts_6/lightning3/halo/halo_2/ripple_single` 只按精确 key 生成确定性的预乘 alpha 纹理，未知 key 继续 fail closed；程序纹理按 family 分形状并缓存，不复制 Wallpaper Engine 资产。21 样本资源图的 `builtInTextureUnavailable` 从 45 降至 22；正式 13 样本可见粒子运行层从 6/27 提升到 14/27，`3750813609` 从 2/9 提升到 7/9，`3765760121` 隐藏粒子仍为 0/0。最终报告 `.codex/scene-particle-builtins-final13-r2-20260723/report.json` 为 **13/13**；Scene 测试 **139 项、138 项通过、1 项跳过**；签名 App `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `7a469cd7aa7d39fc09a22fbd7310b2253655a7e9`、可执行文件 SHA-256 `5556523b76cb07d82e082977e5c890f3f064d90799878da23df0a88dabf3ca42`。新增层仍保留 child/world-space/control-point/turbulence 等诊断，状态是 `executed-degraded`，不是官方纹理或完整粒子语义。
48. 2026-07-23 的 Scene typed dynamic snapshot 第一阶段：提交 `36bfef0` 新增 bool/scalar/vector2/vector3/vector4/string 六类值、scene/camera/layer/effect/text/particle/script-instance target、`authored -> userProperty -> Timeline -> SceneScript` 固定优先级、类型/有限值/重复定义 fail-closed，以及 Host 每帧向所有 surface 广播的同一份空 immutable snapshot。Renderer 尚不读取该 snapshot，binding program、真实 producer、generation diff 和无重建 consumer 均未实现，所以本阶段没有改变画面，也没有重复跑 13 样本视觉矩阵。Scene 测试 **145 项、144 项通过、1 项跳过**；签名 App `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `7b27f7f5d678a333f5db77d19936482a098404e8`、可执行文件 SHA-256 `150348cb9dc9acebf5f8633ad2a64cc665fe4061832c75cbcb76701a71386687`。
49. 2026-07-23 的 Scene 官方能力表治理：179 个官方页面已由 `official-page-map.md` 逐 URL 映射到分类、合同 anchor 和产品决策，`official-page-crosswalk.md` 仅保留 16 组导航；Particle、45 Effect、SceneScript v2.8、Render Graph/Shader、Timeline/属性/输入/Provider、Puppet/3D/Lighting/RGB/离线分别建立逐项专项表。总台账纠正了 Timeline/SceneScript source、previous pointer、Scene Bloom/HDR、通用 graph primitive、utility composition、named `_b` variant 和粒子若干高估项；公共依赖与证据包已独立建图。新增 9 项治理门，当前 Scene 全量合同矩阵 **154 项、153 项通过、1 项跳过**。后续会话必须先选最低公共依赖，再进入专项行的代码/测试/运行证据，不能从样本截图、固定 strict profile 或同系统局部 `L3` 反推整体能力。
50. 2026-07-23 的 Scene B0 live-property 合龙：`00c5e9c` 建立每 surface evaluation transaction，`311e83d` 编译 alpha/color binding program 并标记 mixed/invalid rebuild key，`4da9492` 把合同写入 interpretation v18，`c3d60aa` 让各 display 独立求值，`29cf34b` 接入 layer alpha consumer，`3b4f4f4` 建立原子 live state，`cb2482a` 路由 Host/Service/属性窗口 update/reset，`dbf2c82` 增加 runtime identity 门。隔离 `2902406982:newproperty11` 与 `2938612768:newproperty17` 均 `accepted=true`，更新前后各保持 1 个 surface 与同一 window ID；293 ready/after changed ratio 为 `0.6397`。报告为 `.codex/scene-b0-live-alpha-20260723-0941/report.json`、`.codex/scene-b0-live-alpha-293-20260723-0941/report.json`。Scene 全量测试共运行 **194 项、193 项通过、1 项跳过**；签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `890abe09c9354c0eea6b3e11f6987b06fed2d485`、可执行文件 SHA-256 `0a8f20b610fe5638aa053c22ff2c5bbffb1561ad0e2605ed4f29fe63fc6fcdce`。这只证明当前 layer alpha 子集，不把 color、particle、container 或 compiler-only target 写成 live。
51. 2026-07-23 的 Scene solid-only live color：提交 `95e0d58` 让 finite vector3 color 经 snapshot、clamp 和既有 tint uniform 只供 solid layer 消费；image/text 保持白 tint，属性窗口也只为真实 solid target 开放 layer color。隔离 `3122339805:accentcolourdefault800080` 的 12 个 target 与 `2902406982:newproperty33` 的单 target 均 `accepted=true`，更新前后 surface=1 且 window ID 不变；报告为 `.codex/scene-live-solid-color-312-accent-20260723-1011/report.json` 与 `.codex/scene-live-solid-color-290-20260723-1013/report.json`。负向 `.codex/scene-live-solid-color-312-20260723-1006/report.json` 证明 `basecolor` 因 mixed target 被原子拒绝。全量 Scene 测试 **200 项、199 项通过、1 项跳过**；正式报告 `.codex/scene-live-solid-color-final13-20260723-1015/report.json` 为 **13/13**。签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `35ef1944b5de797f377f409a29c4005d1b4aaafc`、可执行文件 SHA-256 `612315e9eb6ff5bc15c43c03c97f4e90c05c0682f9b9272b01875d79d54facc0`。这不证明 non-solid tint、颜色空间或 WE 像素等价。
52. 2026-07-23 的 Scene provider resource/frame 双代：提交 `c86491e` 将静态 layer/property/system publication 的 resource generation 与 named target frame epoch 分离；连续帧同 identity、同纹理不再让 image-blend 缓存误失效，替换或缺席后重现仍换代，named target 继续逐帧失效。`.codex/scene-provider-generation-293-20260723-1035/report.json` 保持 static image blend **5/5**，`.codex/scene-provider-generation-290-20260723-1036/report.json` 保持 named capture **6/6**、binding **7/7**，两者 loaded ratio 均为 1.0。全量 Scene 测试 **201 项、200 项通过、1 项跳过**；签名 App `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `570cff17bbcdb1095a773fb4ead5921035b6cbf8`、可执行文件 SHA-256 `c90c616b5bdb93ebb6e7e40576a9c3dbe3de2b4d832fe12cdb17b9e119be6cc0`。这不证明 system/media/video 的显式 generation、metadata、cancel 或通用 consumer 已完成。
53. 2026-07-23 的 Scene graph render-target 基础：提交 `38e238d` 新增 effect-scoped logical target plan、input/scale 像素尺寸、读写 lifetime、`historyRequired` 分类，以及预算预检后整组创建的不可变 Metal target table。重复/残缺身份、首写前读取、unsupported descriptor、整数溢出、预算不足和资源别名均 fail closed；全量 Scene 测试 **211 项、210 项通过、1 项跳过**，unsigned Debug App 构建通过。本提交尚未接入 compositor，strict Blur 仍走旧 pool，因此不宣称新增 GPU layer、可见效果或通用 graph 执行；history/copy/swap/compose 仍未实现。
54. 2026-07-23 的 Scene strict Blur graph-target 迁移：提交 `73f415b` 让 precise/standard strict Blur 统一消费 effect-instance target table，并补齐 effect/plan/extent cache、跨 effect 隔离、LRU、resize 原子替换、失败保留旧 cache、reset 和 legacy Pair 自身超预算拒绝。非均匀 mixed-alpha GPU 门逐阶段核对 precise input/horizontal/output 与 standard input/quarter ping-pong/combine，能识别漏 pass、接反和预乘 alpha 错误。全量 Scene 测试 **218 项、217 项通过、1 项跳过**；正负隔离矩阵各 **3/3**。签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `944054ba89d01c67be2901b971091729a4b8dcf1`、可执行文件 SHA-256 `d5b0f5101656a921530c8acca5abf2e35748a5726cb3492f9767c6c6adf38be2`。这没有增加 strict profile 数量，也不证明通用 FBO、history 或 WE 像素等价。
55. 2026-07-23 的 Scene ShaderContract IR v1：提交 `8474ace` 把 authored shader stage 的完整 UTF-8 source、raw SHA-256、相对路径、include 引用、JSON annotation、uniform/attribute/varying declaration、逐项诊断和 canonical SHA 写入 interpretation v19；路径穿越、绝对路径、shader root/stage/include 符号链接逃逸、无效 UTF-8、缺失 stage、畸形 annotation 和重复 identity 均 fail closed。正式 13 样本报告 `.codex/scene-shader-contract-final13-v2-20260723/report.json` 为 **13/13**，共 173 contracts（143 authored + 30 host built-in）、286 stages、0 diagnostics；source 与 IR 的 include/annotation/declaration 数量均为 `155/1523/2660`。全量 Scene 测试 **223 项、222 项通过、1 项跳过**；签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `033bc40a5ee8dbf0d6bd0e478e9a8c5a875b90b4`、可执行文件 SHA-256 `2b6a8d6ee9863de41fd91792f682c2ff0c49ecf1dd15a9909d3d6e924f76bab8`。本阶段只证明 L1 识别/保留，不证明 include expansion、预处理、translation、compile、uniform upload 或 authored shader GPU execution。
56. 2026-07-23 的 Scene `rgba8888` graph-target 基础：提交 `228cdde` 让 logical FBO 严格保留 `rgba_backbuffer` 或 `rgba8888`，分别映射 `.bgra8Unorm` 与 `.rgba8Unorm`；synthetic input/output 继续固定 BGRA，两种格式均按 4 B/px 进入 checked budget。格式变化通过完整 plan equality 原子替换同 effect cache，未知格式仍 `unsupportedTargetDescriptor`。plan/table/pool 与 authored Blur/Metal framebuffer 相关 38 项通过，全量 Scene **225 项、224 项通过、1 项跳过**，签名构建通过。此提交不包含 Local Contrast pipeline、alpha 算法或新可见 layer，最新视觉矩阵仍是 `.codex/scene-shader-contract-final13-v2-20260723/report.json`。
57. 2026-07-23 的 Scene strict stock Local Contrast：提交 `136d35c` 将 interpretation 升至 v20，只接受 exact 单 effect、4 material pass、两个 scale=4 non-unique `rgba8888` RT、KERNEL0/GREYSCALE0/MASK0、Gaussian `scale=(1,1)`（显式或官方缺省）及三份 exact shader fingerprint。四阶段 Metal 路径执行 alpha-weighted 4-tap downsample、13-tap Gaussian X/Y 与 Local Contrast combine，并保留 original alpha；`strength` 以有限值 `0...5` 进入既有 binding program、per-surface snapshot 与 GPU，缺省为 1。定向报告 `.codex/scene-local-contrast-targeted-20260723/report.json` 为 **2/2**，正式报告 `.codex/scene-local-contrast-final13-20260723/report.json` 为 **13/13**；`2902406982:[167,177,530]` graph succeeded、Local Contrast count 2，`2938612768` 的 mixed chains 保持 count 0、static image blend 5/5。正式矩阵 aggregate 为 graph succeeded 8、failed 0、legacy blocked 3、route-only 35。全量 Scene 共运行 **239 项、238 项通过、1 项跳过**；签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `f1fb8e1a4f65f64e869d82c064f4f31f9f5faae5`、可执行文件 SHA-256 `54b2b8e56c4ed7deda640caddfbd379c366a54335cf1253291956f3d24a608fe`。fingerprint 只用于准入，执行器不编译 authored source；mask/greyscale/非默认 kernel 或 Gaussian scale/mixed chain/未知 shader 均 fail closed，且没有 Windows pixel golden。

前序专项报告保存在 `.codex/web-closure-final-20260720/`；作者源码、Steam CDN、34 项历史基线、系统中断门、音频配置失效门、文件持久化门、偏好隔离矩阵和 Space/屏幕门报告分别保存在 `.codex/web-external-final-20260720/results/`、`.codex/web-steam-final-20260720/results/`、`.codex/web-full-final-20260720/results/`、`.codex/web-system-state-final-20260721/results-pass2/`、`.codex/web-audio-restart-final-20260721/results-pass/`、`.codex/web-property-persistence-final-20260721/results-suite-pass/`、`.codex/web-defaults-isolation-final-20260721/matrix-regression/` 和 `.codex/web-space-lifecycle-final-20260721/results-pass2/`；作者源码和 Steam 样本副本分别保存在 `.codex/web-external-representative-samples-20260722/` 与 `.codex/web-steam-representative-samples-20260720/`。这些目录被 Git 忽略，只作为本地复核证据保留到分支合并，不替代仓库内的矩阵定义和生产测试。

本次 Web 固定矩阵结果：

| Workshop ID | 代表能力 | 得分/等级 | Evidence coverage | 结果说明 |
| --- | --- | ---: | ---: | --- |
| `923576681` | file、媒体、音频、Canvas | 100 / A | 95.5% | 隔离文件属性 fixture 生效，DOM、交互和两张 Web 快照齐全 |
| `1509243786` | 属性密集、file/directory、媒体 | 100 / A | 95.5% | 空文件根占位符不再产生 `__absolute__` 拒绝 |
| `2675660496` | dependency、颜色、音频 | 100 / A | 95.5% | dependency shell、资源、主动音频监听、交互和画面通过 |
| `2997985023` | Live2D、WebGL、媒体 | 93 / A | 100% | 延迟首帧后画面和交互通过；样本包缺少其声明的音频文件，本轮另有一次样本 AudioContext suspend 错误 |
| `3700131876` | 纹理 WebGL、loopback、属性恢复、动态画面 | 92 / A | 94.8% | 雨滴持续生成；两帧平均差 0.0070、显著变化 8.30%；样本自身仍有 1 个属性脚本错误 |
| `3726135866` | WASM、WebGL、存储、file | 100 / A | 95.5% | 通过 |
| `3740867386` | 存储、媒体、音频 | 100 / A | 95.5% | 主动音频监听、128-bin 分发和频谱变化通过 |
| `3752541815` | WASM、iframe、directory、存储 | 98 / A | 90.3% | 通过 |
| `3757331413` | WebGL、file、颜色、指针 | 98 / A | 90.3% | 通过 |
| `3762337744` | WebGL、Canvas、指针 | 98 / A | 90.3% | 通过 |

新增外部代表矩阵结果：

| Workshop ID | 代表能力 | 得分/等级 | Evidence coverage | 结果说明 |
| --- | --- | ---: | ---: | --- |
| `1748506393` | WebGL2、35 项属性、音频、指针 | 100 / A | 95.5% | 主动音频和持续流体动画通过 |
| `1396475780` | 174 项属性、WASM、Worker、音频 | 100 / A | 95.5% | production 构建、粒子画面和动画通过 |
| `2014502586` | WebGL 后处理、Worker、音频 | 100 / A | 95.5% | Canvas/窗口合成画面和运动证据通过 |
| `2119347960` | Canvas、约 33 MB 脚本、FPS | 96 / A | 90.3% | Service Worker 补扫去重并限制为单文件 1 MiB 后，进程口径 `host.ready` 为 6.5 秒；交互和动画通过 |
| `2553306714` | 74 项属性、WebGL、指针 | 98 / A | 94.8% | 属性、指针和持续动画通过 |

新增 Steam CDN 代表矩阵结果：

| Workshop ID | 代表能力 | 得分/等级 | Evidence coverage | 结果说明 |
| --- | --- | ---: | ---: | --- |
| `3733483918` | Canvas、属性、DPR、响应式布局 | 98 / A | 90.3% | 三源画面、交互和持续动画通过；不把标题中的 Multimonitor 当作真实多屏证据 |
| `3765959388` | WebGL、70 多项属性、三视口/三相机、FPS | 98 / A | 90.3% | loopback origin、复杂画面、交互和动画通过；仍需真实多屏验证 |
| `3764966764` | Canvas、外部 fetch、实时数据 | 98 / A | 90.3% | CoinGecko 数据在当前网络/代理下成功显示；未验证断网/恢复 |

当前 34 样本全量扫描的例外项：

| 类别 | 样本 | 当前结论 |
| --- | --- | --- |
| 样本脚本属性错误 | `3700131876`、`3700928191` | 颜色数组整包兼容重试后，各自在 `motionintervalmin` 的错误访问处按原回调顺序停止；不再越过错误修改雨滴默认参数。两者均为 92 / A，动态门通过 |
| 样本缺媒体 | `2731942107`、`2997985023`、`884307090` | 包内声明的音频文件不存在；归为 `sample_resource` / `media_audio`，不是宿主映射失败 |
| 样本缺图片或可选资源 | `3759146455` | 请求文件不在样本包内；当前归因规则按 `reason=missing` 归为 `sample_resource` |
| 稀疏暗色 WebGL | `3765286189` | OLED 黑底星空按声明的 `sparse-dark-output` 能力、非黑采样、方差和峰值亮度确认有效，A；普通纯黑、纯白和单点噪声反例仍失败 |
| 境外远程字体 | `1509243786`、`3696478440`、`3740867386`、`3763370103` | Google Fonts 不再阻塞 DOM/宿主就绪；无代理或网络失败时先使用后备字体并按 2/4/8/16/30 秒限界重试，网络恢复后激活。最新 34 项长批次全部为 A |

本次没有得到以下证据：

- 34 个本机样本、5 个外部作者源码样本和 3 个 Steam CDN 代表样本只代表 2026-07-20 当前快照，不代表所有公开 Workshop Web 壁纸，也不是未来新增样本的自动成功率。
- 34 项完整基线已有固定清单、能力标签、允许例外和失败退出条件，但尚未接入 CI 或发布 checklist；新增本机样本也不会自动进入清单。
- 外部 5 项来自作者公开源码的固定 revision，不是 Steam CDN 原始归档；第三方构建产物没有提交到仓库，因此它们是可选独立门，不是默认门的隐式依赖。
- Debug 音频 fixture 只用于确定性桥接门。受控 `afplay` 已证明系统采集到 JS 的主频、幅度和左右声道相关性，但本机当时仍有其他后台声音，未形成“系统绝对静音”实机证据，也未自动判定最终画面的逐帧音频相关性。
- 配置失效门通过生产调试入口触发与 CoreAudio 属性监听回调相同的重建路径，证明 debounce、teardown、重建和资源回收，不证明 AirPods、HDMI 等物理设备变化的系统通知一定到达；当前机器只有一个可用输出端点，无法完成该实机矩阵。
- 当前 Debug、Release 和已安装 App 均未启用 App Sandbox。文件门证明普通 bookmark 与当前非沙盒读取链，不等同于签名沙盒构建中的 security extension 授权；真实 NSOpenPanel 点击路径和重新启用 Sandbox 后仍需单独回归。
- 用户真实 Scene 目录当前已有 21 个已评估样本；运行和属性注入均只使用 `.codex` 隔离副本。首轮 21 样本有作者 preview 对照，但本机没有 Windows Wallpaper Engine 同配置逐帧录屏，因此仍不能给出逐像素兼容结论。
- Space 自动门使用真实 Web 宿主和生产 observer，但通过进程内投递确定通知中心路由；它不冒充 Mission Control 实际切换后的肉眼可见性，也不证明显示器热插拔或分辨率变化。
- 没有 30 分钟以上交互运行、2 小时 soak、真实休眠唤醒、屏幕热插拔、内存压力或发布包回归。
- 因而本文能说明当前已知样本的结果，但不能给出整个 Workshop Web 或 Scene 的总体成功率。

## 3. Web 当前实现状况

### 3.1 已形成的能力

#### 运行时与宿主

- Web 使用独立于 Video/Scene 的宿主接口和状态模型。
- 当前实际策略是每屏独立 `WKWebView` 的 `dedicatedHostPlaceholder`；daemon 已降级为诊断 harness。
- 宿主支持屏幕增删、运行状态广播和一次 WebContent 进程终止恢复。
- Space 变化监听使用 `NSWorkspace.shared.notificationCenter`；屏幕参数突发变化按 200 毫秒合并，observer token 始终从其注册 center 释放。
- 代码入口：[WebWallpaperHostTypes.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift)、[WallpaperEngine+WebWallpaper.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift)。

虽然类型名仍带 `Placeholder`，其实现已经承担正式播放职责。后续应在验收完成后重命名，避免代码语义继续误导维护者，但重命名不是当前 P0。

#### 资源加载与隔离

- `mwx-local://` scheme 支持 MIME、Range、受控可读根和符号链接越界检查。
- localhost profile 只绑定 `127.0.0.1`，用于 Service Worker、module、WASM 等对 origin 更敏感的样本。
- 支持按 Workshop/profile 选择 persistent、scoped 或 ephemeral data store。
- Google Fonts 等境外远程样式遵循系统网络/代理配置，但不再是页面就绪前提；主文档、iframe、动态 link 和嵌套 CSS import 均支持失败降级与网络恢复重试。
- loopback 的二进制 GET/HEAD/Range 保持 HTTP 语义；被转换的 HTML/CSS 明确不声明 Range，避免响应头与正文不一致。
- 代码入口：[WebWallpaperLocalSchemeHandler.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler.swift)、[WebWallpaperLoopbackServer.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLoopbackServer.swift)。

这部分架构方向正确，不应退回到扩大整个 Workshop 根目录读取权限的通用 `file://` 方案。

#### Wallpaper Engine API 兼容

- 支持 `applyUserProperties`、`applyGeneralProperties`、`setPaused`、`setPlaybackState`。
- 支持 listener 延迟注册后的状态重放，避免页面在 document-start 之后才赋值而丢失首轮属性。
- 已包含目录变更、媒体状态、媒体属性、缩略图、timeline、playback 和音频频谱接口。
- Web 音频使用保留符号的 PCM 分声道执行 4096 点 FFT，按 32 Hz 到 20 kHz 的 64 个对数频带输出 `left[0...63] + right[0...63]`；只有真实单声道输入才复制为左右两组。
- 兼容层按 foundation、resource rewriting、media、pointer、DOM lifecycle 和 host bridge 拆分。
- 代码入口：[DedicatedWebWallpaperHostCompatibilityScript+BootstrapFoundation.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+BootstrapFoundation.swift)、[DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift)。

#### 属性、输入和产品接入

- Web 属性定义、默认值、preset、用户覆盖、显示条件和本地化已经形成完整链路。
- 属性面板覆盖 slider、color、toggle、text、combo、file、directory、label、group 等主要类型。
- 外部 file/directory 用户覆盖不会读取或写入 execution payload cache；每次播放重新解析 bookmark 并恢复授权，静态 descriptor cache 仍可复用。非沙盒构建在 security-scoped bookmark 不可创建时保存普通 bookmark，文件或目录改名后仍可跟随。
- 输入层支持 pointer、wheel、点击、拖动和临时捕获，不依赖壁纸窗口直接抢占桌面事件。
- 代码入口：[SteamWorkshopService+WebPropertyParsing.swift](../../MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPropertyParsing.swift)、[DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding.swift)。

#### 诊断和评测

- Runtime 事件按 record、display、type 和 severity 记录。
- `script/web_wallpaper_benchmark.py` 可以启动真实 App、聚合日志、评分、生成 coverage，并与 baseline 比较；每次正式运行拒绝非空输出目录，只接受本次日志声明且位于当前样本目录内的截图路径。
- benchmark 会严格验证签名 App、复制到独立 runtime bundle，并在运行前后核对 bundle/Team/CDHash/版本/可执行文件 SHA-256；报告记录这组身份，不再把被原地改写或来源不明的 App 当作本轮证据。
- 已定义启动、导航、资源、属性、媒体、交互、视觉和性能八个评分维度。
- 代码入口：[WebRuntimeDiagnosticsStore.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/WebRuntimeDiagnosticsStore.swift)、[web_wallpaper_benchmark.py](../../script/web_wallpaper_benchmark.py)。

### 3.2 已关闭的问题与当前剩余风险

#### 已关闭：文件属性类型与资源路径闭环

- 属性解析会按定义和实际资源推断 file/directory 类型，类型不匹配的旧持久化值会被清理。
- benchmark 在隔离 Workshop 根之外创建文件属性 fixture，并使用唯一 Debug UserDefaults suite；仅设置 `HOME/CFFIXED_USER_HOME` 不再视为 bookmark/偏好隔离。
- `923576681` 已取得属性注入、DOM、资源、交互和非空快照证据。
- 空 `file:///` 不再被重写成无意义的 `mwx-local://wallpaper/__absolute__/` 请求。
- 持久化 gate 对 `1509243786` 的 file、directory 和目录模式调用生产更新，连续运行 A/B/A；首进程退出后把两类 fixture 改名，第二进程以旧 raw value 通过 bookmark 恢复到新 resolved/payload，随后 reset，第三进程确认 bookmark 不复活、值为空且模式回到 1。存在外部覆盖时不生成 execution cache，清除后普通 cache 恢复。

```bash
python3 script/web_property_persistence_gate.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --runtime-workshop-root <isolated-workshop-root> \
  --runtime-home <empty-temporary-home>
```

仍需保留一项产品 UI/签名回归：真实 NSOpenPanel 的点击选择，以及未来若重新启用 App Sandbox 后的 security-scoped 授权恢复，目前不是自动门禁。服务层的“选择值、立即生效、切换回来、重启恢复、清除授权”已经自动化，不再是已确认宿主缺陷。

#### 已关闭：视觉与交互强证据

benchmark 现在要求像素统计、DOM 状态和 pointer/click/drag/wheel 注入。视觉证据可来自 `WKWebView.takeSnapshot`、页面 Canvas 和 ScreenCaptureKit 当前进程窗口；窗口采集对限界瞬态错误重试，并结构化记录阶段、错误域、错误码、attempt、window ID 和是否终止。动画只比较同一来源的非空前后帧，避免 WebGL drawing buffer 清空时把黑帧误判成运动。普通画面按覆盖、方差和色彩判断；声明 `sparse-dark-output` 的 OLED 星空还要求非黑采样、方差和峰值亮度。纯黑、纯白、单点噪声和应动未动均形成关键短板；固定矩阵禁止 `interaction`、`visual_output` 和 `animation` 短板。系统整屏截图只作为人工复核附件，黑屏或采集失败时不写入报告，不能替代上述样本内强证据。

#### 已关闭：真实双声道频谱与 Web 监听需求

- 原实现先对 PCM 取绝对值，再把桌面 28 柱插值为 64 柱并复制左右声道；这会把 750 Hz 全波整流成约 1500 Hz，并制造重复的固定形状。现在同一采样拆成两条用途明确的路径：rectified mono 继续维持桌面覆盖层旧视觉，signed stereo 专供 Web FFT。
- Web 分析器使用固定 4096 点 FFT、Hann 窗、去直流和固定 dBFS 标尺，输出严格 128 个有限 `0...1` 值。生产测试覆盖静音、750 Hz 不倍频、125/500/2000/8000 Hz 递增频带、左 250 Hz/右 4 kHz、幅度单调、单声道复制、Float32/Int16/Int32、交错/非交错和非有限值。
- `3b69614` 首次引入真实双声道 FFT 时遗漏了旧宿主边界的兼容响应，导致常见输入从约 `0.10...0.18` 放大到约 `0.68...0.98`；`884307090` 等样本还会把输入乘以 `range * 100`，因此出现音频条过长、动作幅度过大的视觉回归。当前在 JS 分发前恢复 `pow(level, 1.35) * 0.18`，保留真实频率和左右声道，仅校准输出量级。生产测试直接编译该宿主扩展，锁定 128-bin、最大幅度、单调性和双声道独立性。
- `wallpaperRegisterAudioListener` 第一次有效注册会独立请求采集，不再依赖“桌面系统频谱”开关；导航、WebContent 终止、屏幕移除、Web 切换、Video 切换和 stop 都会释放需求，多屏按首个请求/最后释放聚合。
- 受控 `afplay` 实机证据中，左 250 Hz 稳定落在第 20 频带，中央 1 kHz 落在第 34 频带且 0.02 到 0.80 幅度明显上升，右 4 kHz 落在第 47/48 频带；样本 `1748506393` 为 100 / A。音频到无音频再到音频的生命周期序列证明采集按需启动、停止、重启和最终释放。
- 2026-07-21 回归中，`884307090` 的圆环和直线样式由样本属性 `visual_audio_model=1/2` 决定，不是宿主改变绘制类型；两种模式在确定性频谱下均为 96 / A，画布幅度受控。`1509243786` 的确定性频谱为 100 / A；关闭夹具后循环播放系统音效，日志从静音帧进入 `audio.spectrum.changed meanDelta=0.0224`，真实采集结果仍为 100 / A。
- Debug benchmark 仍只在显式参数下注入确定性 64+64 fixture，用来发现“注册但未分发”和“持续发送同一数组”；它不冒充真实系统采集证据。

确定性系统状态恢复已关闭：消费者需求与实际采集资源已经分离；暂停、系统睡眠、显示器休眠或锁屏会释放 CoreAudio tap，最后一个中断原因结束后再由统一播放策略恢复；失败保留需求并限界退避。采集还会监听 tap format 与 aggregate device alive，250 毫秒内的突发配置失效合并为一次重建；监听先移除再销毁 CoreAudio 对象，teardown 后等待 1 秒再创建新 tap，避免已由首轮失败门确认的 CoreAudio `!obj` 竞态。系统状态门和配置失效门都要求每一代恢复后出现非静音 PCM 数据，不能只以 CoreAudio 对象创建成功代替数据恢复。剩余边界是实际 OS 睡眠/唤醒、真正的系统静音、物理输出设备切换与蓝牙重连的真实通知投递，以及把 JS 频带与最终画面响应做自动时间对齐。

#### 已关闭：代表样本矩阵与单样本门禁

固定矩阵由 [web_wallpaper_sample_matrix.json](../../script/web_wallpaper_sample_matrix.json) 定义。每个样本有能力标签、最低等级和最低 coverage，批次还限制平均分、平均 coverage 和关键短板。矩阵自带 18 秒最低观察窗，避免大体积或冷启动样本在首帧与属性回放完成前被过早终止。

当前 34 样本已固化为 [web_wallpaper_full_baseline.json](../../script/web_wallpaper_full_baseline.json)，外部 5 样本由 [web_wallpaper_external_sample_matrix.json](../../script/web_wallpaper_external_sample_matrix.json) 定义，Steam CDN 3 样本由 [web_wallpaper_steam_representative_sample_matrix.json](../../script/web_wallpaper_steam_representative_sample_matrix.json) 定义。固定矩阵仍是公共 runtime 改动的快速门，完整基线用于高影响改动和发布候选，外部门用于扩展能力验证。大型脚本 Service Worker 静态识别已修复并由缓存版本 14 验证；补扫采用 64 KiB 分块匹配、单文件 1 MiB 上限，验证报告会复用描述符摘要，避免大批生成脚本重复拖慢冷启动。但 `1396475780` 在 Wallpaper Engine 分支实际注册数为 0；因此 Shadow DOM、Service Worker 真实注册、真实多屏 scale factor、外部网络失败/恢复等能力仍没有形成独立行为门。

#### 部分关闭：切换、停止和资源释放

生命周期模式会连续启动多个真实样本再 stop，并验证：

- 每个样本到达 `host.ready`。
- 每次 teardown 后 surface、loopback、directory watcher、鼠标 monitor 和 pointer timer 都为 0。
- 每个旧 `WKWebView` 通过弱引用确认已释放。
- 每个启动过的 loopback server 都有对应停止事件。
- 最终 phase 为 idle，lifecycle observer 为 0。

锁屏/解锁和重叠系统/显示器休眠的生产 handler、采集停止/恢复、部分唤醒抑制和最终释放已有自动门，但它通过直接调用生产 handler 注入事件，不冒充真实 OS 睡眠周期。Space/屏幕 observer 门已验证正确 notification center、重装不重复、屏幕 burst 合并和 stop 后零回调；它使用进程内通知，不冒充真实 Mission Control 或显示器热插拔。尚未覆盖真实 OS 休眠/唤醒、物理 Space/显示器增删与分辨率变化、Web/Video/Scene 快速互切、物理音频设备变化、系统代理启停、一般网络断开恢复和连续 WebContent 崩溃，因此生命周期仍只能算部分关闭。

#### P1：性能和长期稳定性预算尚未建立

需要记录首个 `host.ready`、可视首帧、稳定 CPU/GPU、App 与 WebContent 内存、音频采集负载、暂停功耗和缓存增长。常规大体积静态分析限制为每个文件最多 128 KiB 的首尾窗口；Service Worker 诊断补扫限制为单文件 1 MiB 并使用分块搜索。约 33 MB 生成脚本样本的最终进程口径 `host.ready` 为 6.5 秒，已通过 18 秒外部门，但仍有性能提醒；单次优化和释放证据也没有证明 30 分钟交互运行和 2 小时 soak 不持续增长。

验收标准：建立单屏和双屏基线；暂停后 CPU/GPU 明显下降；30 分钟和 2 小时曲线无单调增长；运行中 WebContent 恢复次数受控；超预算报告必须包含样本、profile 和进程级数据。

#### 部分关闭：全样本门禁已建立，尚未接入发布流程

2026-07-20 已对当前 34 个本机样本建立固定清单、能力标签、已知样本例外和失败退出条件，并增加 5 个作者源码样本和 3 个 Steam CDN 代表样本的独立门。固定矩阵用于每次公共 runtime 改动；涉及 parser、origin、资源、属性、缓存签名、音频或评分规则的改动，以及发布候选版本，再运行完整门。2026-07-22 当前 HEAD 已在同一签名 Debug App 上完成 34+5+3 刷新，三组矩阵门均通过；首轮 28A/6B 暴露的 scorer、能力标签和无 listener 页面属性证据合同不一致也已修正。下一步是把完整门接入发布 checklist；仍不能用平均分或失败项单独重跑通过替代批次关键短板判断。

#### P2：正式宿主契约和发布流程尚未收口

`dedicatedHostPlaceholder` 已是事实主力，但命名、接口稳定性和 daemon diagnostics harness 的边界仍未正式收口。固定矩阵和生命周期门禁尚未接入 CI/发布 checklist。

验收标准：正式命名当前宿主；明确 daemon harness 的保留理由；发布前固定运行兼容矩阵、生命周期、UI 文件授权回归和性能预算；失败报告保留样本 ID、profile、日志和截图。

## 4. Web 距离最终完全闭环还有多少

### 4.1 工程成熟度估值

| 能力门 | 权重 | 当前得分 | 说明 |
| --- | ---: | ---: | --- |
| 启动、分类与资源主链 | 20 | 20 | 34+5+3 已知样本可运行；双 origin、资源隔离、HTTP 语义、纹理 WebGL 和远程字体失败恢复已验证 |
| 属性与持久化 | 15 | 14 | file/directory 服务持久化、颜色和错误隔离已闭环；真实选择器和签名沙盒授权仍是发布回归 |
| 媒体与音频 | 10 | 9 | signed stereo 64+64、真实声音相关性、按需生命周期、确定性中断和配置失效恢复已验证；物理设备切换、系统静音和真实 OS 睡眠未完成 |
| 输入与交互 | 10 | 9 | 原生指针转发和自动 pointer/click/drag/wheel 证据已进入门禁 |
| 多屏与生命周期 | 15 | 14 | 切换/stop/释放、音频需求启停、重叠睡眠/锁屏状态机、Space 路由和屏幕 burst 合并通过；真实 OS/显示器事件与 runtime 互切未闭环 |
| 稳定性与性能 | 10 | 6 | 有恢复和释放证据；无正式 CPU/GPU/内存/功耗与 soak 预算 |
| 诊断与自动化验证 | 15 | 15 | 三源视觉、DOM、交互、主动音频、三级矩阵、归因自测和生命周期报告已具备 |
| 发布支持与故障降级 | 5 | 3 | 已有完整基线和失败退出规则；尚未接入 CI/发布 checklist，也没有正式降级标准 |
| **合计** | **100** | **90** | **已知样本、真实音频主链、确定性中断和配置失效恢复已闭环，真实设备/OS、长期性能和发布流程仍未闭环** |

### 4.2 剩余工作量的正确理解

剩余不是“再补 10% 兼容代码”，而是完成以下 3 个工作包：

1. **系统生命周期与异常恢复**：确定性睡眠/锁屏、CoreAudio 配置失效重建和 Space/屏幕通知路由已完成；继续覆盖真实 OS 电源周期、物理 Space/屏幕热插拔、runtime 互切、一般网络/系统代理变化、物理音频设备变化和连续崩溃；不得以静默重试掩盖首轮失败。
2. **性能与长期运行门禁**：首帧、CPU/GPU、内存、功耗、缓存增长、30 分钟交互与 2 小时 soak。
3. **产品与发布闭环**：维护 34+5+3 样本、revision 和允许例外；完成真实 NSOpenPanel 与签名沙盒授权回归；收口 placeholder/harness 边界，把矩阵、生命周期、性能和 UI 回归纳入发布验收。

工作包 1、2 完成前，不能称为系统稳定性闭环；工作包 3 完成前，文件授权产品链、样本扩展机制和发布流程仍不是持续兼容承诺。

### 4.3 推荐完成顺序

```text
已完成：文件属性与跨重启/reset -> Debug 偏好隔离 -> 签名身份与三源视觉/动态证据 -> 远程字体失败恢复 -> signed stereo 真实音频 -> 固定/作者源码/Steam CDN/34 项历史门 -> 按需采集与 stop 释放 -> 重叠睡眠/锁屏确定性恢复门 -> CoreAudio 配置失效重建门 -> Space/屏幕 observer 自动门
下一步：最终 HEAD 34+5+3 刷新 -> Web/Video runtime 互切矩阵 -> 真实 OS/物理设备变化
  -> 性能、泄漏和功耗预算
  -> 基线维护、文件授权回归、正式宿主与发布门禁
```

每个工作包应独立修改、独立验证、独立提交。不要同时改 origin、属性重写和缓存签名后再通过一个高平均分判断结果。

### 4.4 当前可复现门禁

这些命令要求 `--app` 指向签名有效的 `.app` 内可执行文件。benchmark 会在新鲜输出目录中复制并复核运行 App；显式 `--output-dir` 已有内容时直接拒绝，避免旧截图或旧报告混入本轮证据。

固定矩阵：

```bash
python3 script/web_wallpaper_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --workshop-root <isolated-workshop-root>/Web \
  --runtime-workshop-root <isolated-workshop-root> \
  --runtime-home <temporary-home> \
  --matrix script/web_wallpaper_sample_matrix.json \
  --screenshot
```

生命周期：

```bash
python3 script/web_wallpaper_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --workshop-root <isolated-workshop-root>/Web \
  --runtime-workshop-root <isolated-workshop-root> \
  --runtime-home <temporary-home> \
  --lifecycle-sequence 3700131876,3726135866,2675660496
```

系统中断与真实采集恢复：

```bash
python3 script/web_system_state_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --runtime-workshop-root <isolated-workshop-root> \
  --runtime-home <temporary-home> \
  --id 1509243786
```

Space 路由、屏幕 burst 与 observer 释放：

```bash
python3 script/web_space_lifecycle_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --runtime-workshop-root <isolated-workshop-root> \
  --runtime-home <temporary-home> \
  --id 1509243786
```

当前 34 样本完整门：

```bash
python3 script/web_wallpaper_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --workshop-root <isolated-workshop-root>/Web \
  --runtime-workshop-root <isolated-workshop-root> \
  --runtime-home <temporary-home> \
  --matrix script/web_wallpaper_full_baseline.json \
  --duration 12 \
  --screenshot
```

外部 5 样本能力门：

```bash
python3 script/web_wallpaper_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --workshop-root <external-sample-root>/Web \
  --runtime-workshop-root <external-sample-root> \
  --runtime-home <temporary-home> \
  --matrix script/web_wallpaper_external_sample_matrix.json \
  --duration 18 \
  --screenshot
```

Steam CDN 3 样本能力门：

```bash
python3 script/web_wallpaper_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --workshop-root <steam-sample-root>/Web \
  --runtime-workshop-root <steam-sample-root> \
  --runtime-home <temporary-home> \
  --matrix script/web_wallpaper_steam_representative_sample_matrix.json \
  --duration 20 \
  --screenshot
```

`<isolated-workshop-root>`、`<external-sample-root>` 和 `<steam-sample-root>` 必须是只用于测试的副本，包含 `Web/<id>` 和依赖目录；不得把真实 `~/Movies/MyWallpaperX/创意工坊` 直接作为 runtime root。外部样本的来源、revision 和准备方式见 [Web 外部代表样本基线](../web/regression/WEB_EXTERNAL_SAMPLE_BASELINE_2026-07-20.md)，Steam CDN 快照见 [Web Steam 代表样本基线](../web/regression/WEB_STEAM_REPRESENTATIVE_BASELINE_2026-07-20.md)。

Scene 当前 13 样本语义门：

```bash
python3 script/scene_wallpaper_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --sample-root <isolated-scene-sample-root> \
  --matrix script/scene_wallpaper_sample_matrix.json \
  --output-dir <fresh-output-directory> \
  --duration 3.0
```

`<isolated-scene-sample-root>` 必须包含测试副本 `Scene/<id>`；不得直接传入真实 `~/Movies/MyWallpaperX/创意工坊/Scene`。当前正式复核使用 `.codex/scene-matrix13-samples-20260722`，最新矩阵为 `.codex/scene-local-contrast-final13-20260723/report.json`，Local Contrast 正反样本定向门为 `.codex/scene-local-contrast-targeted-20260723/report.json`；`.codex/scene-shader-contract-final13-v2-20260723/report.json`、`.codex/scene-live-solid-color-final13-20260723-1015/report.json`、`.codex/scene-particle-builtins-final13-r2-20260723/report.json` 与 frame-context、file-property、v16 canonical graph、utility、particle-trail、static-fallback、v15 IR 报告只保留为对应阶段证据，不能反向覆盖当前结论。

## 5. Scene 当前实现状况

### 5.1 已形成的能力

- Scene 与 Web/Video 分离，parser、interpretation、renderer 和宿主边界明确。
- 支持 `scene.pkg` PKGV 索引、受控缓存解包和相对路径校验。
- 使用 versioned `.mywallpaperx-scene-interpretation.json` 作为稳定中间层；当前 format 为 v20。
- 能解析 scene、models、materials、effects、资源引用、层级、camera 和 typed shader constants。
- v16 graph 语义保留 EffectDefinition/FBO/ordered pass/bind/command/unknown fields，并编译 authored graph、明确 blocker 与 canonical SHA；v17 descriptor/cache 在此基础上增加 material usertexture、texture property keys 和 runtime-provided reference metadata；v18 保存 binding program 与 effective property values；v19 再保存完整 ShaderContract source/include/annotation/declaration 与 identity；v20 为通过 strict execution catalog 的 stock Local Contrast 保存 strength scalar target。底层作者/执行合同统一查 [Scene 语义手册](../scene/semantics/README.md)。
- material resolver 保留 8 个 nullable slot，并按低到高优先级保存 material asset -> material usertexture -> instance asset -> instance usertexture -> explicit bind；现有 strict backend 取末项，尚未通用接入 frame registry 的 ready/fallback 选择。严格 precise Blur、standard-default Blur 与 stock Local Contrast backend 共同使用 graph/effect identity、node order、RT、shader fingerprint、render state、combo、constant 和 binding 判定，不按样本 ID 或 layer 名称启用。Local Contrast 只用 exact shader fingerprint 准入，仍执行项目内手写 MSL，不执行 authored source。
- 支持 PNG/JPEG、部分 TEXB0001-4、BC1/BC2/BC3/BC5、RGBA/RG/R8、LZ4、MP4 payload 和 TEX sprite sequence；支持标准 `scene.pkg` 与 entry 同名 `gifscene.pkg`。
- 已有 Metal textured-quad、共享白纹理程序化 solid、静态 text texture、作者定义 2D sprite 粒子 instancing、层级 transform/visibility、基础混合、legacy coarse/precise Gaussian blur、standard Blur 默认 4-pass quarter-RT、stock Local Contrast 4-pass quarter-RGBA、Bloom threshold/blur/composite、cover 相机和声明驱动的 parallax。legacy coarse blur 仍是全尺寸 RT + 4 倍 texel step 近似，只服务尚未迁移路径；两个 strict Blur 与 stock Local Contrast 已消费 effect-instance logical target table。单层 built-in UV foliage 读取作者参数；粒子可解析包内纹理和 9 个精确 built-in key 的程序化纹理，`spritetrail` 按速度方向和作者 stretch 参数拉伸。
- 桌面宿主拥有单一 60 Hz frame driver；同一帧的 frame index、host/scene/wall time 向所有屏幕广播，shader、视频、粒子与 parallax 已迁移到 `SceneFrameContext`。property 输入由 host 共享捕获，但每个 surface 独立产生 dynamic snapshot/generation；pause/resume、delta clamp、fixed timestep 和其他 provider snapshot 仍是后续合同。
- Utility current-prefix capture 区分 composition 局部 quad 与 project/fullscreen 全画布，bounded named target/consumer 可把受支持 provider 转交给依赖 slot，简单静态普通 image provider 可进入 normal blend；逐帧 registry 以完整 identity 隔离 named target variant，并在 absent/pending/unavailable 时沿 authored candidates 选择首个 ready provider。文件型 `sceneTexture` 可在当前受限 image-blend 候选中替换作者 provider；这些路径都使用受限离屏池并在 GPU 完成后上报结果。
- 已有 Scene 用户属性解析、受支持 target 的默认值/override 应用、按 wallpaper 持久化、条件显示和独立属性编辑窗口；实际可执行的 `sceneTexture` key 可选择 PNG/JPEG，bookmark 授权只覆盖同步解码上传，UI 不显示当前 renderer 无法执行的属性 target。layer alpha、solid-only layer color 与 exact stock Local Contrast strength 已通过 v20 binding program 和 per-surface snapshot 无重建更新；新 target 只有 compiler mapping 与真实 consumer 同时存在才允许 live。
- benchmark 通过签名 App 身份、隔离样本/HOME、Metal ready/after 双帧、语义字段、utility/named/image-blend/particle planned 与 finished layer ID、authored graph canonical SHA、precise/standard/Local Contrast backend exact succeeded/failed/legacy-blocked layer ID、Local Contrast plan count、live identity/visible-change，以及 stop 后 surface=0 验证当前 13 样本；293 的五个 property blend layer 与 mixed Local Contrast fail-closed 继续锁定。
- 代码入口：[SceneDiagnostics.swift](../../MyWallpaperX/Core/SteamWorkshopScene/SceneDiagnostics.swift)、[SceneRenderDescriptor.swift](../../MyWallpaperX/Core/SteamWorkshopScene/SceneRenderDescriptor.swift)、[SceneMetalRenderer.swift](../../MyWallpaperX/Core/SteamWorkshopScene/SceneMetalRenderer.swift)、[SceneDesktopWallpaperHost.swift](../../MyWallpaperX/Core/SteamWorkshopScene/SceneDesktopWallpaperHost.swift)。

### 5.2 用户重点样本现状

- `2902406982`：image `30/30`、solid `9/9`、text `44/57`、particle `0/1`；6 个 named provider capture 与 7 个 consumer binding 成功。当前 authored graph GPU 成功层为 `[167,177,530]`：`530` 是 stock standard Blur，`167/177` 是 exact stock Local Contrast 4-pass；Local Contrast count 为 2、failed 为空，`brcontraststrength=3.0` live accepted 且不替换 surface/window。白三角和旧 coarse blur 导致的重复背景已消除，missing resource 为 0；仍有 7 个 route-only effect，以及动态内容、文字和剩余 effect 未闭合。
- `2938612768`：image `44/44`、solid `11/11`、text `8/24`、particle `0/1`；providers `141/1340` capture、consumers `299/322` binding 和 layers `239/657/775/875/1509` 静态 image blend 均成功，中央播放器/静态封面已出现，missing resource 为 0。隔离注入已证明 `newproperty25/26` 的实际 PNG 可替换对应静态 provider；它不等于系统媒体封面或 current/previous thumbnail 时序。可见 4/5-effect mixed chains 的 Local Contrast count 保持 0，graph succeeded/failed 均为空，没有被 strict 单效果 profile 误执行。仍有 named-target gap 1、18 个 route-only effect；authored waterwaves 当前由 legacy 算法近似，UV/幅度/采样/局部作用严重失真，导致全屏夸张扭曲。媒体动态封面/文字、音频和粒子尚未闭合。
- `3750813609`：image `2/2`、solid `1/1`、text `1/1`、particle `7/9`；layers `121/200/90/504/511/516/498` 已进入运行链，截图可见新增叶片、光束与雾。layers `523/530` 仍因 world-space fail closed，121/504/511 仍缺 child，叶片还缺 turbulent velocity；layer `358` 的非默认 Blur+Clouds 图仍明确 blocked，动态时钟和最终合成精度未闭合。

这些结果来自同一份最终 13 样本报告，描述的是当前实现相对作者 preview 的已知改善和缺口；没有 Windows Wallpaper Engine 同配置录屏，不能据此声称逐帧一致。

### 5.3 核心缺口

#### 渲染覆盖不足

descriptor 能识别 image、solid、particle、text、container 与 typed utility；v20 继承的 authored graph 中，严格 precise Blur、standard-default Blur 与 stock Local Contrast 三个 profile 已进入 GPU，typed frame registry、property authored fallback 和受限 PNG/JPEG property source 也已落地，但其余节点仍由 bounded executor 处理或保持未支持。当前不是通用 GPU DAG executor：尚无统一 effect-chain scheduler、copy/swap/compose/history 生命周期；system/media source、文件纹理的任意 material consumer、effectful provider、child/nested target、utility mask、复杂 blend、Texture Variants、child/world-space/其余粒子 renderer、puppet 和脚本驱动内容仍会缺失或降级。

#### shader/effect 不是兼容实现

当前 MSL effect 是对少量视觉特征的手写实现，不是 Wallpaper Engine HLSL、材质和 pass 语义的通用转换或执行；Local Contrast 虽精确核对 source fingerprint、pass 顺序、RT、combo、常量与 binding，fingerprint 仍只用于准入。utility、foliage 和 blend 也只覆盖经过正反样本约束的子集。下一步必须用 generic scheduler 保留 effect chain、读写顺序、输入纹理和 live uniform 合同，不能继续把多个 effect 压成一个按名称选取的近似分支。

#### 存在应先修复的正确性和健壮性问题

- 已移除旧的无作者声明 ripple/capability fallback 和 composition 缺省视差；precise Blur、standard-default Blur 与 stock Local Contrast 严格子图已迁到 graph 选路，规划失败后不再从旧文件名路径复活。其他受限执行器仍按 visibility/mask/combo/参数限界；禁止继续扩展名称分支，待对应 graph backend 取得证据后逐项迁移。
- legacy coarse blur 虽已按作者像素单位并消除早期重复背景，但仍是全尺寸 RT + 4 倍 texel step 近似，只能留在尚未迁移的受限路径。stock standard Blur 默认图已使用真实 4-pass/quarter-RT；stock Local Contrast 使用两个 scale=4 RGBA RT，但 mask/greyscale/KERNEL1/2、非默认 Gaussian scale、mixed chain 和 shader 变体继续 fail closed。两者都没有 Windows pixel golden。单层 built-in UV foliage 已服从作者 mask/参数，多 stack 和 vertex/workshop 变体继续 fail closed。
- 普通 image 与 composition 都只有显式非零 `parallaxDepth` 才产生逐层位移；缺失和零值不移动。位移归一化与 delay 曲线仍待 Windows golden 校准，zoom、shake 和更完整 interaction 语义也未闭合。
- PKG reader 每取一个 entry 会重新读取并解析整个包；cache extractor 也会先删除缓存，复杂度和重复 IO 较高。
- `entryCount` 缺少合理上限，损坏包可能触发异常内存分配。
- 每屏重复创建 renderer、解码、上传纹理和 particle simulation；frame timer 已收敛为宿主级单一主线程 60 Hz driver，但尚未接屏幕刷新率、目标 FPS 或后台节流策略。

#### 产品闭环不足

- Scene 用户属性已有独立编辑窗口、条件显示、持久化、活动壁纸 fallback 重建，以及 `texture`/`scenetexture` 内部类型归一；当前可执行的静态 image-blend texture key 已支持 PNG/JPEG picker、bookmark、解码上传、真实 override 和 authored fallback。layer alpha、纯 solid layer color 与 exact strict Local Contrast strength 已 live；non-solid/mixed color、Texture Variants、视频、system/media、通用 material consumer、transform、particle、puppet 和其他 effect uniform 等 target 仍隐藏或整场重建，因此不是完整属性兼容链。
- 没有按屏 pause/resume、FPS、音量、画质策略和独立 Scene 状态。
- 没有 SceneScript、动态文字、音频响应、puppet/mesh 和完整视频纹理生命周期；粒子现有作者包内 sprite、9 个精确 built-in 程序纹理与 sprite trail 子集，其余 13/27 visible candidate 仍未加载，已加载层也可能继续缺 child/world-space/control point/operator。
- 已有 13 个真实 Scene 样本的语义自动门，当前验证 image `180/181`、solid `54/54`、text `79/108`、particle `14/27`，named capture `8/8`、binding `9/9`、static image blend `5/5`；precise/standard Blur 与 stock Local Contrast 合计 8 个 authored graph layer GPU succeeded、0 failed，Local Contrast count 2、legacy blocked 3。但本轮仍观测到 35 个 route-only effect、1 个 named-target gap，没有完整性能预算，也没有与 Windows Wallpaper Engine 同配置录屏的图像差异门，因此不能把 13/13 等同于完整兼容或 WE parity。

## 6. Scene 演进方向

### 阶段 0：产品边界与执行门（已确定方向，进行中）

当前选择“可审计的兼容 Runtime”方向：不承诺私有格式 100% 复刻，但按官方行为合同、真实样本频率和 [Scene 语义手册](../scene/semantics/README.md) 推进。Effect-definition IR、authored graph planner、ShaderContract v1、BGRA/RGBA graph target、precise Blur、standard-default Blur、stock Local Contrast 三个 strict profile、resource identity/property authored-fallback、file-backed `sceneTexture`、统一 Frame Context 第一阶段、首批 built-in 粒子纹理，以及 B0 binding program/per-surface snapshot/atomic live consumer 已完成。下一主切片先做 B2 generic scheduler/effect-chain/read-write execution skeleton，使后续 effect 不再各自重建调度；B1 Provider Core 的 dynamic generation、metadata 与 cancellation 并行推进。Timeline、SceneScript、动态文字、audio/media 以后横向接入同一 target/frame 合同。既有 bounded executor 在新路径取得 GPU/golden 等价证据前保留，但不再扩展名称分支。完整等级以 [覆盖台账](../scene/semantics/coverage-ledger.md) 为准。

### 阶段 1：正确性、安全和性能基础

1. B0 property 主链已建立 typed DynamicValue/target registry、v20 binding program、per-surface snapshot、原子 live state，以及 layer alpha、solid-only color、strict Local Contrast strength consumer。新增 live target 必须同时注册 compiler target、真实 consumer、fallback 与 identity 门；dynamic text 和 visibility 不得仅靠现有 alpha 路径取消整场重建。
2. 先建立 B2 generic scheduler 的 effect-chain、target read/write、pass ordering 与失败原子性骨架，再在同一合同上扩 copy/swap/compose、RT history 和更多 effect backend；不能继续复制 strict profile 各自的调度代码。
3. B1 Provider Core 并行补 dynamic generation、metadata、cancellation，再接 Texture Variants、video/system/media、通用 material 与 effectful/nested/child source。
4. 在同一 target/frame 合同上横向接通 Timeline core、SceneScript core、cursor/audio/media snapshot，并补高频 particle atlas/multi-texture、world/child/control point/rope/audio/collision 最小闭环；每类都要有作者关闭反例和失败降级。
5. 最后用固定矩阵与 Windows golden 集中校准字体、视差、粒子和效果精度；在视觉主链之外继续补 PKG header/entry/解包边界、索引与纹理复用、按屏刷新率/FPS 和性能预算。

验收标准：无样本 ID/名称特例；effect/pass 顺序、live 输入和 dependency GPU 成败可审计；未声明能力保持关闭；逐步扩充的代表 Scene 矩阵在 image/solid/text/particle、位置、方向、alpha、层级和释放上无回归。损坏包仍须受控失败，同一 pkg 不应重复全量解析。

### 阶段 2：补齐 Scene Lite 产品链

1. 扩展现有 Scene 用户属性 target，补 sceneTexture、media、transform、particle/audio 参数和无重建热更新；保留独立编辑窗口。
2. 在 live value 主链上补齐动态 text/container 和可靠的视频纹理生命周期。
3. 接入按屏 pause/resume、睡眠/锁屏、Space、遮挡、电池和屏幕热插拔。
4. 增加 FPS、音量、画质/降级策略与 per-display 状态。
5. 建立 Scene 样本 fixture、截图 baseline、诊断报告和性能预算。

完成该阶段后可以稳定交付“Scene Lite”，但仍不能声明通用 shader、SceneScript、完整粒子兼容或 Wallpaper Engine parity。

### 阶段 3：兼容 Runtime 能力

如果产品目标是接近 Wallpaper Engine Scene，需要按依赖顺序建设：

1. 材质模型、shader translation/execution、render state 和真实多 pass。
2. 扩展 text、sprite、video、composite 与 particle renderer；当前静态 text、2D sprite、built-in drop/trail 和 bounded dependency 只作为已落地起点。
3. SceneScript 沙箱、事件、时间、输入和属性桥接。
4. 音频响应、puppet、内置 assets 和版本化兼容策略。
5. 每一类能力都必须用固定样本和图像差异验证，不能只凭“成功启动”验收。

这一阶段是独立渲染引擎项目，不应与普通 App 功能迭代混在同一里程碑。

## 7. 建议的近期里程碑

### M1：Web 用户可见阻断清零（已完成）

- 已关闭文件类型推断、纹理 WebGL 路由、旧式颜色数组和空文件根占位符问题。
- `923576681` 已具备隔离文件属性、DOM、资源、交互和截图证据。
- `3700131876` 和 `3700928191` 的雨滴回归已从属性回调顺序根因修复；两样本双帧动态证据通过。
- 当前没有已确认的宿主 P0 Web 问题。

### M2：Web 强证据回归门（已完成）

- 已固定 10 个代表样本并加入能力标签、最低等级、最低 coverage 和批次禁用短板。
- benchmark 已增加 WebView/Canvas/当前进程窗口视觉像素、同源运动、DOM、主动音频和自动 pointer/click/drag/wheel 断言。
- 当前独立偏好域固定门结果：平均 98.2、coverage 94.3%、10A；当前最终完整门为平均 97.7、coverage 95.9%、32A/2B；作者源码门为 98.8 / 97.9% / 5A；Steam CDN 门为 98.0 / 94.8% / 3A。四层门均通过。
- 音频生产链已按 Wallpaper Engine 契约输出 signed stereo 64+64 布局，并在分发边界应用兼容幅度响应；受控系统音源验证频率、幅度和声道，Debug fixture 只用于确定性桥接和样本视觉回归证据。
- coverage 未设为 95% 的原因是部分样本没有媒体节点或特定能力事件，不能用伪造事件抬高覆盖率；单样本关键门禁优先于平均 coverage。

### M3：Web 生命周期与性能闭环（进行中）

- 已完成 Web-to-Web 切换、loopback 启停、WKWebView 释放、Web 音频需求启停、重叠睡眠/锁屏恢复、CoreAudio 配置失效重建、Space/屏幕 observer 和最终 stop 零状态门禁。
- 2026-07-22 已刷新当前 HEAD 的 34+5+3，三组矩阵门均通过。随后完成真实 OS/设备状态、Web/Video/Scene 互切、30 分钟交互运行和 2 小时 soak。
- 建立单屏/双屏 CPU、GPU、内存、功耗和缓存预算。
- 验收：无持续资源增长、无窗口/端口/音频残留、暂停后负载下降、恢复序列可诊断。

### M4：Web 发布闭环（进行中）

- 已建立当前 34 样本完整基线、5 样本作者源码能力门和 3 样本 Steam CDN 代表门；后续维护样本、源码 revision/CDN 更新时间与例外复审。
- 已完成可控双声道真实音频到 JS bin 的频率、幅度、声道、确定性睡眠/锁屏和配置失效重建回归；后续补物理设备切换的真实通知、真正系统静音、实际 OS 睡眠及最终画面时间对齐。
- 已完成当前非沙盒发行链的 file/directory 更新、A/B/A、跨重启移动恢复、reset 和偏好隔离门；后续固定执行 NSOpenPanel 与签名沙盒授权 UI 回归。
- 将固定矩阵、生命周期和性能报告接入发布 checklist/CI。
- 正式收口 `dedicatedHostPlaceholder` 和 daemon diagnostics harness 的边界。

### M5：Scene 基础质量收口

- 已建立 13 个真实 Scene 样本、签名身份、Metal 非黑双帧、语义字段、动态像素、dependency GPU 完成和 surface 释放门，样本覆盖层级/有效可见性、MP4 payload、作者与 built-in sprite 粒子、静态文字、脚本密集图层、音频声明和更多 effect。
- 受限 legacy coarse/precise Gaussian blur、strict standard Blur 默认 4-pass、strict stock Local Contrast 4-pass、Bloom、程序化 solid、静态 text geometry/font、camera cover/显式 parallax、无 mask normal-map waterripple、perspective/opacity、mode 9 composite、单层 built-in UV foliage、9 个精确 built-in 粒子程序纹理/sprite trail、utility current-prefix、bounded named target、简单静态 image blend、typed provider fallback、file-backed `sceneTexture` 第一切片、统一 Frame Context 第一阶段，以及 B0 layer-alpha/solid-color/Local Contrast strength live 主链已落地；v20 继承 v19 loss-preserving ShaderContract，并把 exact strict Local Contrast strength 写入 property program。下一步以 [覆盖台账](../scene/semantics/coverage-ledger.md) 和 [Scene 播放能力开发计划](../scene/scene-capability-development-plan-2026-07-22.md) 为准，先做 B2 generic scheduler，B1 Provider Core 并行。
- Scene 属性当前通过独立窗口编辑受支持 target；实际可执行的 texture key 支持 PNG/JPEG 选择和恢复作者默认，不再把未实现 target 伪装成可调控件。
- 继续移除效果硬编码，修复 PKG 边界与重复解析，并建立 CPU/GPU/显存预算；样本只作验收，不新增 ID 适配。

## 8. 最终判断

Web 的运行主链已从“基本可用”推进到“有固定、作者源码、Steam CDN、完整四层兼容门、远程网络降级门、真实音频证据、文件跨重启恢复门、确定性系统中断恢复门、配置失效重建门、Space/屏幕 observer 门和释放门”。2026-07-22 当前 HEAD 的 34+5+3 与独立偏好域 10 项门均全绿；Google Fonts 在国内无直连或代理失效时不再阻塞启动，Web 音频也已从重复的桌面假波形改为按需 signed stereo FFT，并补回旧样本依赖的兼容幅度响应。当前可声明“当前构建 34+5+3 的已知样本功能兼容闭环、当前非沙盒发行链的 Web 文件服务持久化闭环、Web 音频宿主主链及确定性睡眠/锁屏、配置失效和 Space observer 恢复闭环”；仍不能声明“发布级最终完全闭环”或“以后所有样本都会成功”。后续应集中完成 runtime 互切、物理设备与真实 OS 状态、长期资源预算、真实 UI/签名沙盒授权回归和发布流程接入。当前专用 WKWebView 宿主、受控资源协议、按需 loopback 和结构化诊断路线应继续保留，不应改回宽权限 `file://` 或引入重复宿主。

Scene 的基础架构成立，运行能力仍是明确子集，并已有“签名 App + 13 个隔离真实样本 + Metal 双帧/语义/dependency/strict graph GPU/释放门”的可持续开发链。v20 继承 v18 binding program/effective values 与 v19 loss-preserving ShaderContract；B0 已把 property producer、per-surface snapshot、atomic routing，以及 layer alpha、solid-only color、exact strict Local Contrast strength consumer 合龙。strict precise Blur、standard-default Blur、stock Local Contrast、file-backed `sceneTexture` 静态 consumer 子集和统一 Frame Context 第一阶段已执行，实际画面仍主要来自 bounded renderer；三个 strict profile、5/5 静态 blend、三个 live consumer 子集和 ShaderContract source 保留都不等价于 authored shader execution、动态 sceneTexture 或完整属性系统。当前可以声明“受限能力可用、官方能力归属和逐项缺口可查、graph/target 与 shader source 合同已建立、首个文件型 property provider 及 B0 live 主链已闭环”，不能声明达到或接近 Wallpaper Engine parity。下一步先建设 B2 generic scheduler/effect-chain/read-write execution skeleton，B1 Provider Core 的 dynamic generation、metadata、cancellation 并行，随后接 B3/B4 的 Timeline/SceneScript、动态 text、audio/media、Particle 与更广 backend；增加样本硬编码、默认套用效果或把 compiler-only target 写成 live，仍不会形成兼容闭环。
