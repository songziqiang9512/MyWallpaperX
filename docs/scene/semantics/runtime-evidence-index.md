# Scene 运行证据索引

> 状态：现役证据入口
>
> 最近核对：2026-07-25
>
> 实现基线：`678a052`

本页给覆盖表中的 `L3` 子集提供可追溯证据包。每个证据包至少包含代码、自动测试和真实运行或 GPU 证据；缺少任一项的能力只能标 `L0-L2`，或在专项表中明确写 `gate incomplete`。`.codex` 报告是本机隔离运行产物，不提交 Git；报告路径、App 身份和摘要写入现役文档，避免将其误当源码 fixture。

## 1. 当前统一门

| 项目 | 当前证据 |
|---|---|
| 当前完整快照门 | `.codex/scene-static-origin-full45-20260725/report.json` 为 45/45、particle `101/131`、strict stage 91、chain 15、failed 0；报告 SHA-256 `8d578f2b8bb39e8f62fb0a64cfc1e0f6fd2018b578752afd3a555d8fb141e6a0`，仓库矩阵 `script/scene_wallpaper_full_sample_matrix.json` SHA-256 `b005da924cfefbcd08410d298f8795af67086f62c7df95ca802988fcfabea38e` |
| 固定回归门 | `678a052` 签名 App 的 `.codex/scene-static-origin-fixed13-20260725/report.json` 为 13/13、particle `19/27`、strict stage 24、chain 2、failed 0；报告 SHA-256 `6537c945963e2005d9354113036602e57357a57ece44769e68aef3291252b07d`，矩阵 SHA-256 `479b794d64b48369348b4b8e6583599e5ac70161a4f670102332f5cd1e2d653c` |
| Static-origin 定向门 | `.codex/scene-static-origin-targeted-20260725/report.json` 为 1/1、particle `17/19`；报告 SHA-256 `febd6e14feba2bb74251d1f513d89be0baa72084f6ddf8bfdf89f0791b9c3a4f`，定向矩阵 SHA-256 `4f68c1655eec246c6a94093c82a098bbe03a161997b1aec46175d9612e169c9e`；`3088601835:513/534` 的 `snowstormfog` child 由真实缓存门确认执行，preview 未出现 Smoke 洗白 |
| 最新合同门 | interpretation v25；完整 Scene suite 377 项：374 通过、3 跳过；代码健康 443 Swift files、44 locked legacy files、400-line limit |
| ShaderContract | 173 contracts = 143 authored + 30 host built-in；286 stages、0 diagnostics；source/IR include 155、annotation 1523、declaration 2660，见 E-SHADER-CONTRACT |
| Live property | layer alpha、solid color、strict Local Contrast/Opacity 与 direct text content/point-size/color 均由 per-surface snapshot 消费，accepted 且 surface/window identity 不变；报告见 E-LIVE-PROPERTY / E-DYNAMIC-TEXT |
| Provider 双代 | `2938612768` static image blend 5/5；`2902406982` named capture 6/6、binding 7/7；报告见 E-PROVIDER |
| Puppet/BC 合成正确性 | bind-pose/静态 MDAT 继续有效；`f1ee79b` 新增严格单 clip MDLA/full-TRS/LBS 播放，`3747492842` 六层与完整门中的其他受限层执行，unsupported mixing/visibility/profile 回退 bind pose；`18d0056` 为超预算/多 image BC1/2/3 增加 GPU premultiply，并为跨 image sprite 提供静态 authored 首帧 fallback；完整动画未实现；见 E-PUPPET-BC |
| Particle runtime | `f4173ea`/`7d53c10` 的 strict depth-one eventspawn/natural-eventdeath child 已由真实缓存、离屏 Metal 和 `2131872317` 延迟桌面截图验证；`928acca` 为 identity/no-CP Sprite `eventfollow` 建立 parent-ID owner、逐帧 follow 与 parent-death 回收；`2f897bc` 执行持续/混合/duration child emitter 与 root child aggregate budget；`899704b` 执行 strict static/default-static child；`8a27089` 将 built-in registry 扩到 20-key；`678a052` 仅为 static/default-static 接受有限 origin translation，使 `3088601835` layers `513/534` 的 `snowstormfog` child 执行，angles/scale/CP/非法值与 event transform 继续 fail closed；`4a17ee6` 的非音频 turbulent velocity 有 seed/time/scale/audio 正反门与 5 个真实样本定向门；见 E-PARTICLE |
| 方向性视觉证据 | 样本自带 preview GIF 是当前第一视觉依据；固定门均生成 preview reference 与中心裁切并排图，六样本人工校准见 E-PREVIEW-VISUAL。WaifuX SceneBake MP4 只作辅助动态参考，出现冲突时不能覆盖样本 preview；两者均非 Windows WE golden |
| 签名 App | 当前定向、固定与完整门均为 `2.0.8 (268)`，Team `H9QWU9XN8R`，CDHash `8661db034136a4030592f6e2f3190b08de4c448a`，executable SHA-256 `1ddea5e09f45e45828b5e1003debb56e92fcb82cfef4f0428e7cde45ac70d004`；benchmark staged App 运行前后签名均验证 |
| executable SHA-256 | `1ddea5e09f45e45828b5e1003debb56e92fcb82cfef4f0428e7cde45ac70d004` |
| 样本边界 | 真实 Workshop root 只读；报告均来自隔离 sample root 与临时 HOME |

当前真实目录有 46 个数字目录；其中 `3770500543` 缺少 package，source manifest 明确跳过，45 个可运行副本在隔离 root/HOME 下完成正式快照。`678a052` 完整门加载 image `449/451`、text `244/244`、solid `140/140`，particle 为 `101/131`；strict graph 为 91 stage、15 条 multi-effect chain、Water Flow 10、Water Waves 11、Shake 24、Opacity 8、Local Contrast 2、0 failed、113 个 route-only effect。固定 13 样本门单独保护 particle `19/27`、24 stage、2 条 chain、Water Flow 1、Water Waves 6、Shake 1、Workshop Shadow 1、Opacity 4、Local Contrast 2、0 failed；两门互补，均不证明完整兼容或 WE parity。20-key 完整门中 `builtInTextureUnavailable` 为 24 次，15-key 历史门为 37 次；该对比只说明精确资源阻断减少，不等价于执行所有 effect/child。

## 2. 证据包

<a id="e-ingest"></a>
### E-INGEST: Scene / PKG / TEX / resource ingest

- 代码：[SceneProject.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneProject.swift)、[ScenePkgReader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/ScenePkgReader.swift)、[SceneTextureLoader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneTextureLoader.swift)、[SceneResourceReferenceIndex.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneResourceReferenceIndex.swift)
- 自动门：[test_scene_resource_reference_index.py](../../../script/tests/test_scene_resource_reference_index.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)
- 运行门：正式 13 样本报告记录 interpretation/resource diagnostics、loaded/candidate counts 和 stop lifecycle。

<a id="e-base"></a>
### E-BASE: 基础 layer、层级、cover 与合成

- 代码：[SceneRenderDescriptor.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneRenderDescriptor.swift)、[SceneMetalRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalRenderer.swift)、[SceneImageLayerCompositor.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneImageLayerCompositor.swift)
- 自动门：[test_scene_solid_layers.py](../../../script/tests/test_scene_solid_layers.py)、[test_scene_capture_geometry.py](../../../script/tests/test_scene_capture_geometry.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)
- 运行门：正式矩阵的 layer/image/solid/text/particle 计数、cover projection、非黑截图和 GPU completion。

<a id="e-preview-visual"></a>
### E-PREVIEW-VISUAL: Steam preview 方向性视觉证据

- 实现提交：`3194ac5`。代码：[scene_preview_visual_evidence.py](../../../script/scene_preview_visual_evidence.py)、[scene_wallpaper_benchmark.py](../../../script/scene_wallpaper_benchmark.py)、[web_benchmark_capture.py](../../../script/web_benchmark_capture.py)。
- 自动门：[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py) 新增 5 项，覆盖 preview 路径逃逸拒绝、按参考比例中心裁切、分项指标、拼图生成、缺失 preview 非阻断和汇总合同；聚焦 benchmark/capture 测试 43/43，宿主 GPU Scene 全量 297/294/3。
- 固定运行门：`.codex/scene-preview-visual-20260724/fixed13-final/report.json` 为 13/13，13 个样本视觉证据全部 available，9 个 GIF 使用 `first-frame-via-sips`，4 个 JPG 使用静帧；报告 SHA-256 `9ccfb3a8c760ebb8f868d489471e78ddc83a862e59e41105566130a9f38fbf62`。该报告为对应阶段的签名 App 证据；当前固定门（final-v2）继续逐样本生成 preview 并排图。
- 人工校准门：`.codex/scene-preview-visual-20260724/calibration6-final/report.json` 为 6/6，报告 SHA-256 `3f9f9f08d641a6f27b2e43bdb9a11380c54dd55423a047e31952b61ce31830f2`。并排图直接暴露 `2902406982` 的构图错乱、`2938612768` 的过度水波形变和 `3750813609` 的字体/颜色差异；`3742133044` 画面完整但因作者 preview 采用不同近景裁切取得较低分项值，证明数值不能跨样本排序。
- 合同边界：benchmark 不改变播放 viewport 或 cover 投影，只把运行截图中心裁到 preview 比例。报告明确 `gating=false`、`comparison_scope=same-sample-change-only`、`cross_sample_ranking=false`、`absolute_threshold=null`；分项色彩、亮度、直方图和显著性中心仅用于同一样本跨提交对照，拼图仍需人工复核。Steam preview 不能验证动画速度、Shake 相位、粒子轨迹、音频响应、字体像素或 WE parity，缺失/解码失败只记 `unavailable`，不改变样本 PASS。

<a id="e-frame"></a>
### E-FRAME: Frame Context

- 代码：[SceneDesktopWallpaperHost.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost.swift)、[SceneFrameContext.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneFrameContext.swift)、[SceneMetalView.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalView.swift)
- 自动门：[test_scene_frame_context.py](../../../script/tests/test_scene_frame_context.py)、[test_scene_dynamic_snapshot.py](../../../script/tests/test_scene_dynamic_snapshot.py)
- 运行门：`.codex/scene-frame-context-final13-20260723/report.json` 13/13；同一 host frame 采样后广播，stop 后 surface=0。

<a id="e-parallax"></a>
### E-PARALLAX: Camera Parallax 与受限 pointer 投影

- 代码：[SceneLayerParallax.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneLayerParallax.swift)、[SceneMetalView.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalView.swift)
- 自动门：[test_scene_layer_parallax.py](../../../script/tests/test_scene_layer_parallax.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)
- 运行门：`.codex/scene-parallax-correction-formal13-20260723/report.json` 与 `.codex/scene-property-parallax-off-gate-20260722/report.json`；显式开启和 author-off 分开验证。

<a id="e-property"></a>
### E-PROPERTY: User Properties 与受限 target

- 代码：[SceneUserProperty.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneUserProperty.swift)、[SceneUserPropertyBindings.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneUserPropertyBindings.swift)、[SceneUserPropertyResolver.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneUserPropertyResolver.swift)
- 自动门：[test_scene_user_properties.py](../../../script/tests/test_scene_user_properties.py)、[test_scene_user_property_textures.py](../../../script/tests/test_scene_user_property_textures.py)
- 运行门：`.codex/scene-property-text-day-gate-pass-20260722/report.json`、`.codex/scene-user-texture-final13-r2-20260723/report.json`；layer alpha/solid color 的 live 子集见下一证据包，其余 target 仍按 consumer 能力回退整场重建。

<a id="e-live-property"></a>
### E-LIVE-PROPERTY: B0 binding program 与已注册 live consumers

- 代码：[ScenePropertyBindingProgram.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/ScenePropertyBindingProgram.swift)、[ScenePropertyLiveUpdateState.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/ScenePropertyLiveUpdateState.swift)、[SceneSurfaceEvaluationTransaction.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneSurfaceEvaluationTransaction.swift)、[SceneDynamicLayerValues.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneDynamicLayerValues.swift)、[SceneDesktopWallpaperHost.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost.swift)
- 自动门：[test_scene_property_binding_program.py](../../../script/tests/test_scene_property_binding_program.py)、[test_scene_interpretation_file.py](../../../script/tests/test_scene_interpretation_file.py)、[test_scene_surface_evaluation_transaction.py](../../../script/tests/test_scene_surface_evaluation_transaction.py)、[test_scene_property_live_update_state.py](../../../script/tests/test_scene_property_live_update_state.py)、[test_scene_dynamic_layer_values.py](../../../script/tests/test_scene_dynamic_layer_values.py)、[test_scene_property_live_routing.py](../../../script/tests/test_scene_property_live_routing.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)
- 运行门：alpha/solid color/Local Contrast/Opacity 沿用既有定向报告；direct text 的 `2134765860:customtext/textcolor/textsize` 见 `.codex/scene-dynamic-text-targeted-213-final-20260723-1907/report.json`。各项均 `accepted=true` 且 surface/window identity 不变。
- 负向门：`.codex/scene-live-solid-color-312-20260723-1006/report.json` 中 `basecolor` 被拒绝，因为同键除 48 条 solid color 指令外还有未支持目标；状态没有部分提交。
- 边界：证明 layer alpha、solid color、有效可见 direct text 三字段，以及 strict Local Contrast/Opacity。SceneScript、hidden/no-consumer text、particle、container、non-solid color、其他 effect constant 或 unsupported mixed key 必须返回整场重建。program 可编译本身不构成 live 证据。

<a id="e-text"></a>
### E-TEXT: 静态文字

- 代码：[SceneTextTextureLoader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Text/SceneTextTextureLoader.swift)
- 自动门：[test_scene_text_rendering.py](../../../script/tests/test_scene_text_rendering.py)、[test_scene_user_properties.py](../../../script/tests/test_scene_user_properties.py)
- 运行门：`.codex/scene-text-fixed-20260722/report.json` 和正式矩阵的 text loaded/candidate 结构门；没有 Windows 字体/基线 golden。

<a id="e-dynamic-text"></a>
### E-DYNAMIC-TEXT: direct property 动态文字与 generation lifecycle

- 代码：[SceneDynamicTextTextureStore.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Text/SceneDynamicTextTextureStore.swift)、[SceneDynamicTextGenerationState.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Text/SceneDynamicTextGenerationState.swift)、[ScenePropertyBindingCompiler+TargetMapping.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/ScenePropertyBindingCompiler+TargetMapping.swift)、[SceneTextTextureLoader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Text/SceneTextTextureLoader.swift)
- 自动门：[test_scene_dynamic_text_binding.py](../../../script/tests/test_scene_dynamic_text_binding.py)、[test_scene_dynamic_text_generation.py](../../../script/tests/test_scene_dynamic_text_generation.py)、[test_scene_frame_context.py](../../../script/tests/test_scene_frame_context.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)。覆盖三类 typed value、错误 kind/conditional fail closed、重复值去重、A->B->C stale completion 拒绝、失败保留 last-ready 和 reset。
- 运行门：`.codex/scene-dynamic-text-targeted-213-final-20260723-1907/report.json`；隔离 `2134765860` 先以 `text=2` 启用作者 Custom 模式，再 live 更新 `customtext/textcolor/textsize`，surface `1 -> 1`、window `[94398] -> [94398]`、changed ratio `0.003541478640192539`、text `6/6`。正式回归 `.codex/scene-dynamic-text-final13-20260723-1915/report.json` 为 13/13、sample root residue 0。
- 边界：只接受 direct user property；有效可见且有 text/style 的 layer 才是活动 consumer。SceneScript、clock/date/media、hidden/no-consumer layer、静态 `text` label、conditional binding、Windows font/layout parity 均不在本证据包内。

<a id="e-particle"></a>
### E-PARTICLE: 2D Particle 子集

- 实现提交：strict eventspawn `f4173ea`，birth/natural-death event queue、Sprite Trail child 与 1,024 粒子预算 `7d53c10`，Event Follow parent-ID owner/逐帧跟随/parent-death 回收 `928acca`，持续/混合/duration child lifecycle 与 root aggregate budget `2f897bc`，strict static/default-static child `899704b`，有限 static origin translation `678a052`，可配置延迟截图门 `4e64232`，`rosepetals`/`beam_1` 程序化预乘纹理 `c654571`，`particle/fire/fire1` 程序化预乘纹理 `f02f41d`，`particle/light/light_shafts_0` 程序化预乘纹理 `a5a951f`，Flare 三张程序化预乘纹理 `9748a8c`，Snow/Smoke 程序化预乘纹理 `8a27089`，非音频 Turbulent Velocity Random `4a17ee6`。代码：[SceneParticleRuntime.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleRuntime.swift)、[SceneParticleChildRuntime.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleChildRuntime.swift)、[SceneParticleChildTemplateSupport.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleChildTemplateSupport.swift)、[SceneParticleChildLifecycle.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleChildLifecycle.swift)、[SceneParticleSimulator.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleSimulator.swift)、[SceneParticleSimulationSupport.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleSimulationSupport.swift)、[SceneParticleTextureSource.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleTextureSource.swift)、[SceneParticleBuiltInTextureRegistry.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleBuiltInTextureRegistry.swift)、[SceneParticleMetalPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Particles/SceneParticleMetalPipeline.swift)
- 自动门：[test_scene_particle_definitions.py](../../../script/tests/test_scene_particle_definitions.py)、[test_scene_particle_simulator.py](../../../script/tests/test_scene_particle_simulator.py)、[test_scene_particle_assets.py](../../../script/tests/test_scene_particle_assets.py)、[test_scene_particle_builtin_textures.py](../../../script/tests/test_scene_particle_builtin_textures.py)、[test_scene_particle_rendering.py](../../../script/tests/test_scene_particle_rendering.py)、[test_scene_particle_runtime.py](../../../script/tests/test_scene_particle_runtime.py)
- 运行门：`c654571`/`f02f41d`/`a5a951f` 依次把 registry 扩到 15-key，`9748a8c` 扩到 18-key，`8a27089` 扩到 20-key。当前完整、固定、定向报告分别为 45/45 particle `101/131`、13/13 particle `19/27`、1/1 particle `17/19`，三门 sample-root residue 0。`3088601835` 的 Snow layers `513/534` 继续以 `64x64 additive` 执行，root particle 口径保持 `17/19`；`test_scene_particle_runtime.py` 的真实缓存门确认两层各生成 `snowstormfog` child instance、纹理宽 128，且不再产生对应 `childSystemsUnsupported`。定向 preview 对照保留主体、色调和背景细节，没有低能量 Smoke 洗白。合成门同时锁定 origin `1 2 3` 正例，以及 angles、scale、event origin、`nan` origin、probability 反例；continuous、instantaneous+rate、有限/无限 duration、完成回收、Event Follow parent-death 回收与 64-system/65,536-capacity aggregate budget 均继续通过。程序纹理不是官方资产，也不是 WE pixel parity；`.codex/scene-fog1-zero-299-20260725/report.json` 仍证明右下亮边与 `fog1` 无关。默认隐藏的 `3742133044:189` 与 `3765760121:161` 仍不创建。真实缓存门中 `3768903841` layer 264 执行 eventspawn child；`2131872317` layer 529 在 fixed 60 Hz 第 233 帧生成 1,024 个 eventdeath trail instance，离屏 Metal 覆盖超过 1,000 像素。隔离 45 样本 census 记录 static/default-static 119 条（显式 63、缺失 type 56），14 条 identity declaration 与 `snowstormfog` 有限 origin declaration 已执行；其余 104 条 non-identity static 仍先受 nested profile 阻断，collision/delete、inherit-value-from-event、非空 child CP mapping 均为 0。
- 视觉门：eventdeath 证据仍为 `.codex/scene-eventdeath-current-v25-delayed-20260725/report.json` 的 1/1 与 4.5 秒可见烟花。新定向报告中 `2470144420` after 帧可见天空花瓣，`3769688830` after 帧可见顶部和主体周围花瓣，whole-frame motion 分别为 `changed_ratio=0.084723/0.607483`、`mean_delta=0.003124/0.037777`；这些 motion 同时包含其他动态层，只用于证明画面活跃，不归因成单一粒子层。两样本均 sample-root residue 0，preview 对照 available；当前 App 身份见统一门。
- 边界：Turbulent Velocity 仅执行非音频 profile，使用项目自建确定性 gradient noise 消费 forward/right/up、phase、scale、time 和 speed range；它不是 WE 数值或像素等价实现，audio profile 继续 `unsupportedInitializer` + `audioResponseIgnored`。Child 仍仅接受 depth-one、无 control-point mapping、static probability=1、event probability 合法、child system limit 1...512、Sphere/Box、有限合法 schedule、非 audio profile、已知 emitter flag 和 Sprite/Sprite Trail renderer；static/default-static 额外允许有限 origin translation，但仍要求零 angles 和单位 scale，event child 继续要求完整 identity transform。Event Follow 以 parent ID 更新 origin 并随 parent death 回收，static/default-static 在 authored local origin 创建一次且不消费 event `nextSeed`。每 child system 最多 1,024 粒子，每 root child runtime 最多 64 systems/65,536 capacity。20 个项目自建程序纹理均不是官方资产。两条 event scale probe 分别被 world-space root 与 world-space Rope Trail root 先行阻断；`3769364482` 的 torch turbulence 已执行，但 ember child 仍有其他 profile/资源边界；`2131872317` layer 1375 的缺纹理/复杂 profile 继续 `childSystemsUnsupported`，collision/delete/nested child、event value/CP inheritance、static angles/scale、event transform、跨层/递归总预算和 Windows WE pixel golden 均未完成。

<a id="e-puppet-bc"></a>
### E-PUPPET-BC: Puppet bind-pose/静态 attachment/严格 MDLA 播放、BC premultiplied 解码与 REFRACT fail-closed

- 实现提交：mesh/预算内 BC/REFRACT `8bac86e`，超预算/多 image BC GPU 归一 `18d0056`，静态 attachment `49ee89a`，MDLA IR/rig/full-TRS `ca6d841`/`56f92a2`/`2be2b44`，严格播放 `f1ee79b`。代码：[SceneMdlPuppetAnimationReader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneMdlPuppetAnimationReader.swift)、[SceneMdlPuppetRigReader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneMdlPuppetRigReader.swift)、[ScenePuppetAnimationEvaluator.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/ScenePuppetAnimationEvaluator.swift)、[ScenePuppetPlaybackState.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/ScenePuppetPlaybackState.swift)、[SceneCompressedTextureUploader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneCompressedTextureUploader.swift)，以及既有 mesh/attachment/BC/particle asset readers。
- 自动门：[test_scene_puppet_animation.py](../../../script/tests/test_scene_puppet_animation.py)、[test_scene_puppet_mesh.py](../../../script/tests/test_scene_puppet_mesh.py)、[test_scene_puppet_playback.py](../../../script/tests/test_scene_puppet_playback.py)、[test_scene_layer_world_frame.py](../../../script/tests/test_scene_layer_world_frame.py)、[test_scene_bc_texture_decoder.py](../../../script/tests/test_scene_bc_texture_decoder.py)、[test_scene_bc_texture_uploader.py](../../../script/tests/test_scene_bc_texture_uploader.py) 与 [test_scene_particle_assets.py](../../../script/tests/test_scene_particle_assets.py)。播放门锁定 full TRS、`T * Rz * Ry * Rx * S`、hierarchical world、`animatedWorld * inverse(bindWorld)`、normalized four-weight LBS、source-FPS 离散 loop，以及 mixing/dynamic visibility/malformed declaration 的 bind-pose 回退；BC uploader 门锁定超预算、多 image BC3 的 GPU straight->premultiplied 像素、静态首帧裁切与旋转 frame fail-closed；缺失可选数字的 parser 栈溢出也有回归。
- 定向运行门：`.codex/scene-puppet-animation-20260725/targeted-v1/report.json` PASS，SHA-256 `d656addbbdec26d70a4e3b57c9c1195b042701a10fce51f1eb421f8fa073fbce`；`3747492842` 六层记录 `puppet animation OK`，interpretation v25，whole-frame `changed_ratio=0.238523`。同一样本旧 v24 无 hover 对照 `.codex/scene-puppet-animation-20260725/control-v24-v1/report.json` SHA-256 `75ab9cde8df0d9ededa4e13534f550f2834d928e2d8252f7c22c837de11406f0`，既有 effect 仍产生 `0.177934` 运动；因此约 `0.060589` 的增量只作方向性证据，不能把全帧变化全部归因于 Puppet。
- BC 真实证据：完整 45 样本 TEX census `.codex/scene-bc-census-full45-20260725.json`（SHA-256 `29decdec2e3de8acb1c31e4a9ecba8b2e759288d16ade43f517a78fcb6237268`）只发现一个超预算/多 image BC 载荷：`3768903841` 的 BC3 `7680x7560`、5 images、140 sprite frames，由 image layers 195/198/199/200/201 共用；每 image 是 4x7 atlas、28 帧。`18d0056` 后这些层各加载 `1920x1080` authored 首帧，不再绘制整张 atlas 或 straight-alpha matte。定向 `.codex/scene-bc-targeted-20260725/report.json` 1/1（SHA-256 `8f747d699c7ad006c62b981fc8d0510bc6826d8eecddfba5dbcd7d53164a8107`）、固定与完整两层统一门均通过。
- 正反运行门：完整 45/45 与固定 13/13 均为 v25、surface `1 -> 0`、sample-root residue 0。`3768229922` 两层进入 30 FPS animation，blend 1.3 层回退；`3769688830` 一层进入 30 FPS animation，additive/property-bound/multi-layer 声明回退。首轮完整门暴露 `doubleValue(nil)` 递归崩溃；修复后 `2998757800`/`3028090166` 定向 2/2 与完整门均通过，旧 MDLV0016 仍 fail closed。
- 边界：当前是 `L3 executed-degraded` 的严格单 clip CPU LBS，只接受已验证的 MDLV0023/MDLS0004/MDLA0006、loop、静态 visibility、non-additive、blend/rate=1 且无 blend-in/out。没有插值、rate/blend/mixing、动态 attachment follow、constraint/IK/physics/channels/clipping、GPU skinning 或 Windows WE golden。REFRACT 材质仍在真实 refraction pass 前整层 fail closed；BC 解码性能门为未优化 Debug 构建 4K BC1 约 0.3 s（行级并发）。跨 image BC sprite 当前只提供可表达的 authored 首帧静态 fallback，5-image/140-frame 动画播放、旋转 frame 与完整 sequence 生命周期均未实现。

<a id="e-provider"></a>
### E-PROVIDER: Texture provider、named target 与静态 dependency blend

- 代码：[SceneFrameTextureRegistry.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneFrameTextureRegistry.swift)、[SceneDependencyRenderPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneDependencyRenderPlan.swift)、[SceneImageBlendRuntime.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneImageBlendRuntime.swift)、[SceneImageBlendPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneImageBlendPipeline.swift)
- 自动门：[test_scene_frame_texture_registry.py](../../../script/tests/test_scene_frame_texture_registry.py)、[test_scene_dependency_render_plan.py](../../../script/tests/test_scene_dependency_render_plan.py)、[test_scene_image_blend_plan.py](../../../script/tests/test_scene_image_blend_plan.py)、[test_scene_user_property_textures.py](../../../script/tests/test_scene_user_property_textures.py)
- 运行门：fallback/file 证据为 `.codex/scene-texture-fallback-293-v3-20260723/report.json`、`.codex/scene-user-texture-final13-r2-20260723/report.json`；双代修复后的定向证据为 `.codex/scene-provider-generation-293-20260723-1035/report.json` 与 `.codex/scene-provider-generation-290-20260723-1036/report.json`。
- 边界：连续帧同 identity、同 `MTLTexture` 的 layer/property/system publication 保持 resource generation；替换或缺席后重现会换代。named target 是当帧重写资源，继续使用 frame epoch。system/media/video 的显式内容 generation、metadata、异步取消和通用 consumer 尚未完成。

<a id="e-utility"></a>
### E-UTILITY: Utility capture 与 named primary target

- 代码：[SceneUtilityLayer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneUtilityLayer.swift)、[SceneNamedRenderTargetPool.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneNamedRenderTargetPool.swift)、[SceneDependencyFrameRuntime.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneDependencyFrameRuntime.swift)
- 自动门：[test_scene_utility_layers.py](../../../script/tests/test_scene_utility_layers.py)、[test_scene_named_render_target_pool.py](../../../script/tests/test_scene_named_render_target_pool.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)
- 运行门：正式矩阵和 `2902406982` 定向报告记录 utility capture、named producer/consumer 与 GPU completion。

<a id="e-effect-ir"></a>
### E-EFFECT-IR: EffectDefinition / Material / authored graph

- 代码：[SceneEffectDefinition.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneEffectDefinition.swift)、[SceneAuthoredEffectRenderPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredEffectRenderPlan.swift)、[SceneAuthoredEffectRenderPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredEffectRenderPlanner.swift)
- 自动门：[test_scene_effect_definition.py](../../../script/tests/test_scene_effect_definition.py)、[test_scene_effect_render_graph.py](../../../script/tests/test_scene_effect_render_graph.py)、[test_scene_authored_effect_execution.py](../../../script/tests/test_scene_authored_effect_execution.py)
- 运行门：`.codex/scene-effect-ir-formal13-final-20260723/report.json` 与 `.codex/scene-effect-graph-canonical-final-20260723/report.json`；只证明结构和 canonical identity，不证明 GPU execution。

<a id="e-shader-contract"></a>
### E-SHADER-CONTRACT: Shader source contract IR v1

- 代码：[SceneShaderContract.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneShaderContract.swift)、[SceneShaderContractLoader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneShaderContractLoader.swift)、[SceneAssetCatalog.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneAssetCatalog.swift)、[SceneInterpretationFile.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneInterpretationFile.swift)
- 自动门：[test_scene_shader_contract.py](../../../script/tests/test_scene_shader_contract.py)、[test_scene_interpretation_file.py](../../../script/tests/test_scene_interpretation_file.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)。loader 门覆盖 absolute/`..`/root-stage-include symlink escape、invalid UTF-8、missing/unreadable stage、malformed annotation 和 duplicate identity；benchmark 门覆盖 wire 必填字段、source/raw hash、stage kind/path/nested arrays、diagnostic schema、host built-in 空 stage 与 canonical SHA。
- 运行门：`.codex/scene-shader-contract-final13-v2-20260723/report.json` 为 13/13；173 contracts（143 authored + 30 host built-in）、286 stages、0 diagnostics。独立 source/IR 复核中 include、annotation、declaration 数完全一致，分别为 `155/1523/2660`。
- 构建门：Scene tests 223 total / 222 pass / 1 skip；签名 App `2.0.8 (268)`，Team `H9QWU9XN8R`，CDHash `033bc40a5ee8dbf0d6bd0e478e9a8c5a875b90b4`，executable SHA-256 `2b6a8d6ee9863de41fd91792f682c2ff0c49ecf1dd15a9909d3d6e924f76bab8`。
- 边界：本证据只把 source/include/annotation/declaration 升为 L1 recognized/preserved；没有 include expansion、macro/permutation preprocessing、translation、stage link、compile、typed uniform/default consumption、uniform upload 或 authored shader GPU execution。

<a id="e-effect-inline"></a>
### E-EFFECT-INLINE: 受限手写 Effect profiles

- Water Waves 顺序边界提交：`1766c76`。
- 代码：[SceneEffectRuntimePlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneEffectRuntimePlan.swift)、[SceneInlineEffectRuntime.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneInlineEffectRuntime.swift)、[SceneMetalPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalPipeline.swift)
- 自动门：[test_scene_effect_mask_gating.py](../../../script/tests/test_scene_effect_mask_gating.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)
- 运行门：`.codex/scene-waterwaves-ordered-chain-targeted-20260724/report.json` 为 5/5，`1766c76` 阶段固定门 `.codex/scene-waterwaves-ordered-chain-fixed13-final-20260724/report.json` 为 13/13。Water Waves 精确计数为 `3722933264=4`、`3723344874=2`、`3724553795=0`、`2902406982=0`、`2938612768=0`；矩阵同时锁定最小值和最大值。当前固定门由本页顶部的 Water Flow 报告定义。
- legacy Water Waves 边界：共享 inline uniforms 只能表达一个 effect，不能保持 Blend/Water Flow/Iris 等前序 stage、多个 Water Waves 的独立参数或作者顺序，因此只有唯一可见 Effect 为 Water Waves 时才准入；隐藏 sibling 不阻断，缺失声明 mask 继续 fail closed。`2938612768` 从 legacy count 1 降为 0 后不再全屏夸张扭曲，主要人物构图恢复。`31ae557` 后 exact stock profile 已改走 strict authored-chain backend，但不符合精确指纹的其他声明仍受本边界约束。
- 总边界：当前只是 Foliage/Iris/Water/Cursor/Chromatic/Perspective-Opacity 等表内子集，不执行 authored shader；Steam preview 指标没有可靠反映 293 的几何改善，人工 montage 仍是本次视觉判定依据。

<a id="e-effect-water-motion"></a>
### E-EFFECT-WATER-MOTION: exact stock Foliage Sway / Water Ripple / Water Waves / Water Flow profiles

- 实现提交：Water Waves `31ae557`，Water Flow `94aebc5`，Foliage Sway / Water Ripple strict profile `3baf1fc`。代码：[SceneAuthoredWaterWavesPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredWaterWavesPlanner.swift)、[SceneAuthoredWaterFlowPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredWaterFlowPlanner.swift)、[SceneAuthoredFoliageSwayPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredFoliageSwayPlanner.swift)、[SceneAuthoredWaterRipplePlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredWaterRipplePlanner.swift)、[SceneFoliageSwayRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneFoliageSwayRenderer.swift)、[SceneWaterRipplePipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneWaterRipplePipeline.swift)。
- 自动门：[test_scene_authored_effect_chain_planner.py](../../../script/tests/test_scene_authored_effect_chain_planner.py)、[test_scene_authored_effect_execution.py](../../../script/tests/test_scene_authored_effect_execution.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)、[test_scene_opacity_planner.py](../../../script/tests/test_scene_opacity_planner.py)、[test_scene_waterflow_builtin_phase.py](../../../script/tests/test_scene_waterflow_builtin_phase.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)。当前完整 Scene suite 为 377 项：374 通过、3 跳过；代码健康为 443 Swift files、44 locked legacy files、400-line limit。
- 运行门：`.codex/scene-waterflow-20260724/full26-final/report.json` 与 `.codex/scene-waterflow-20260724/fixed13-final/report.json` 分别为 26/26、13/13，报告 SHA-256 分别为 `7753412293b17b71a1db966910ed3e2dbbcc4b7fd66d342d5d316f8731f16cf6`、`7488830cc5df8b2012cee10893b162427e64104075ac3045e32f827e6f8ceb74`，矩阵 SHA-256 分别为 `5bc2300aca22a32d31b64d9d19c2d6619a841eeaba672aae5a3e05768143f2e2`、`8e0dd0aa296be3130ea5f9313194c71d76885165dc24938af415ce6eecf25ce5`。签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `a37d51608519fed9d5ae86307654f9aba590357c`、executable SHA-256 `f6ae1d08a294e0e19221537b5864d23157032f3ebd763dbc94dc9db49624ffe4`，staged App 运行前后签名均验证。
- 关键样本：`3028090166` 为 succeeded `[86,129]`、Water Flow 2、Opacity 1、chains 1、stages 3；`3768903841` 为 succeeded `[33,37,41,181,188,202,211,220,232]`、Water Waves 4、chains 1、stages 10；`3768229922` 的六段 Water Waves 链需要 12 个全尺寸 texture unit，超过默认 96 MiB 池保证的 6 unit，规划阶段保持 stages 0 而非运行时分配失败；graph failed layer 均为空。
- profile 边界：两者都只接受 exact stock definition/material/raw shader fingerprint、单 material stage、精确 slot/constant/render-state 合同，并执行项目内 MSL，不编译 authored shader。Water Flow 缺失 phase 时只为精确 `particle/normal_ring_smooth` 生成 64x64 R8 项目自有径向纹理；其他缺失路径继续失败关闭。`MASK=0` Opacity 可接受 dormant `[nil, mask]` authored slot，但不会读取该 mask。
- 视觉边界：`3028090166` 与 WaifuX SceneBake MP4 的同时间帧 SSIM 约为 `0.798/0.786`，构图和主体位置大致一致，云层、龙身和水面扰动的相位/强度仍有差异。该 MP4 和 Steam preview 都只是方向性参考，不是 Windows Wallpaper Engine pixel golden；四类 profile 均为 `L3 executed-degraded`。

<a id="e-effect-xray"></a>
### E-EFFECT-XRAY: pointer-driven exact stock X-Ray profile

- 实现提交：`3baf1fc`。代码：[SceneAuthoredXRayPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredXRayPlanner.swift)、[SceneXRayRuntimePlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneXRayRuntimePlan.swift)、[SceneXRayPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneXRayPipeline.swift)、[SceneXRayEffectTextureLoader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneXRayEffectTextureLoader.swift)、[SceneMetalView+Pointer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalView+Pointer.swift)。
- 自动门：[test_scene_xray_planner.py](../../../script/tests/test_scene_xray_planner.py)、[test_scene_layer_cursor_geometry.py](../../../script/tests/test_scene_layer_cursor_geometry.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)、[test_scene_property_binding_program.py](../../../script/tests/test_scene_property_binding_program.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)。覆盖 exact fingerprint、layer-local pointer、组合区域 source UV、blend/halo/opacity texture、property live target、pointer outside/资源缺失失败关闭及受限前缀。
- 运行门：`.codex/scene-xray-composition-20260724/results-pass3/report.json` 为 3/3；用户在真实桌面壁纸路径手动确认 `2998757800`、`3747492842`、`3757555836` 三个鼠标遮罩均正常。当前完整/固定两层正式门见本页顶部。
- 关键修复：X-Ray 不再直接把整屏 framebuffer 当作 layer source，而是先按组合区域和原 `sourceUV/sourceUniforms` 捕获到 chain input，再以局部 pointer 执行。`3747492842` 因此不再把 authored 3840x2160 下层图错投到屏幕坐标；TEXB0004 metadata 读取也让 400x400 halo 使用作者映射尺寸。
- 边界：`3747492842` 只执行 X-Ray 受限前缀，后续 Film Grain/Bloom/Iris 等 unsupported effect 明确省略并保留诊断；没有 Windows pointer/像素 golden，不能宣称通用 mixed chain、完整 sampler/aspect 或 WE parity。

<a id="e-effect-blur"></a>
### E-EFFECT-BLUR: strict Blur graph profiles

- 代码：[SceneAuthoredEffectExecutionPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredEffectExecutionPlan.swift)、[SceneAuthoredStandardBlurPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredStandardBlurPlanner.swift)、[SceneOffscreenEffectRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneOffscreenEffectRenderer.swift)、[SceneStandardBlurRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneStandardBlurRenderer.swift)
- 自动门：[test_scene_authored_effect_execution.py](../../../script/tests/test_scene_authored_effect_execution.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)、[test_scene_offscreen_texture_pool.py](../../../script/tests/test_scene_offscreen_texture_pool.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)
- 运行门：`.codex/scene-graph-target-positive-final-20260723/report.json` 为 3/3，6 个 graph layer GPU succeeded、0 failed；`.codex/scene-graph-target-negative-final-20260723/report.json` 为 3/3，unsupported graph 未误执行。旧 formal13 报告仍是历史全矩阵证据。

<a id="e-effect-local-contrast"></a>
### E-EFFECT-LOCAL-CONTRAST: strict stock Local Contrast graph profile

- 实现提交：`136d35c`。代码：[SceneAuthoredLocalContrastPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredLocalContrastPlanner.swift)、[SceneLocalContrastPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneLocalContrastPipeline.swift)、[SceneLocalContrastRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneLocalContrastRenderer.swift)、[SceneAuthoredEffectExecutionPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredEffectExecutionPlan.swift)。
- 自动门：[test_scene_local_contrast_planner.py](../../../script/tests/test_scene_local_contrast_planner.py)、[test_scene_local_contrast_rendering.py](../../../script/tests/test_scene_local_contrast_rendering.py)、[test_scene_property_binding_program.py](../../../script/tests/test_scene_property_binding_program.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)。固定 stage golden 覆盖 alpha-weighted 4-tap downsample、13-tap X/Y Gaussian、BGRA source/output、RGBA quarter targets、original alpha 与 strength `0/0.32/1`。
- 运行门：定向报告 `.codex/scene-local-contrast-targeted-20260723/report.json` 为 2/2；正式报告 `.codex/scene-local-contrast-final13-20260723/report.json` 为 13/13。`2902406982` layers `167/177` 执行 Local Contrast，graph succeeded 为 `[167,177,530]`、failed 为空、Local Contrast count 为 2；`2938612768` 的可见 4/5-effect mixed chains 保持 count 0，既有 image blend 5/5。两样本退出均为 `surface 1 -> 0`。
- profile 边界：每个 stage 只接受 exact stock 4 material pass、两个 FBO `scale=4` non-unique `rgba8888` RT、KERNEL0/GREYSCALE0/MASK0、Gaussian `scale=(1,1)`（含官方缺省）和三份 exact authored shader contract fingerprint。mask、greyscale、KERNEL1/2、非默认 Gaussian scale、包含 unsupported stage 的 mixed chain、未知/变更 shader、condition/function 均 fail closed；fingerprint 只用于准入，authored source 不被编译或执行，也没有 generic shader translation。
- parity 边界：Metal backend 采用 stock shader 的非 `HLSL_SM30` 采样语义，没有该分支的 `0.75 / resolution` 偏移；没有 Windows golden，因此状态为 `L3 executed-degraded`，不能宣称跨后端逐像素一致。

<a id="e-effect-workshop-shadow"></a>
### E-EFFECT-WORKSHOP-SHADOW: exact Workshop single-pass Shadow profile

- 实现提交：`809b75e`。代码：[SceneAuthoredWorkshopShadowPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredWorkshopShadowPlanner.swift)、[SceneWorkshopShadowPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneWorkshopShadowPipeline.swift)、[SceneWorkshopShadowRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneWorkshopShadowRenderer.swift)。
- 自动门：[test_scene_workshop_shadow_planner.py](../../../script/tests/test_scene_workshop_shadow_planner.py)、[test_scene_workshop_shadow_rendering.py](../../../script/tests/test_scene_workshop_shadow_rendering.py)。planner 门锁定完整 definition/material/vertex+fragment ShaderContract fingerprint、单 material stage、零 authored FBO/bind/slot、`MASK=0`、`BLENDMODE=0`、normal/nocull/depth disabled、black color、静态有限 alpha/border/offset，并验证 prior-effect input role；未知 hash/combo/state/constant/user binding 均失败关闭。独立 Shadow GPU 门覆盖 premultiplied alpha、border/offset、clamp-to-edge、零 alpha identity 与非法资源/常量失败关闭。
- 运行门：定向 `.codex/scene-workshop-shadow-targeted-20260723-1536/report.json` 为 1/1；正式 `.codex/scene-workshop-shadow-final13-20260723-1540/report.json` 为 13/13。`3724289844` 为 stages 4/chains 1/Shadow 1、succeeded `[20,28,36]`、blocked/failed 为空；全矩阵为 10 stage、1 real chain、Shadow 1、failed 0、legacy blocked 2、route-only 34。
- target/FBO 边界：该 definition 没有 authored FBO；executor 复用 `SceneGraphRenderTargetTable` 的 synthetic full-size input/output texture，并在 ordered chain 中把 precise Blur 输出作为 Shadow 输入。这只证明零-FBO strict profile 与既有 table/transaction 能协作，不升级 authored extent/format/clear/history。
- parity/产品边界：执行器运行仓内手写 MSL，不预处理、翻译或编译 authored shader。它是 Workshop `3488490208/shadow_____________` 的 exact profile，不是官方 45 项 Effect、generic Shadow 或 lighting shadow；`BLENDMODE=0` 没有合法官方 Windows 像素 oracle，因此仍是 `L3 executed-degraded`，不等于 WE 像素等价。当前 GPU 单测使用整数 X offset，尚未像素锁定样本实际 `(2,-2)` 的亚像素插值/Y 方向，也没有 Blur -> Shadow compositor 像素 golden；定向真实样本矩阵是当前集成门。Shadow 常量保持静态，没有新增 live target。

<a id="e-effect-opacity"></a>
### E-EFFECT-OPACITY: exact stock `MASK=0` Opacity profile

- 实现提交：`b8842d8`。代码：[SceneAuthoredOpacityPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredOpacityPlanner.swift)、[SceneOpacityPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneOpacityPipeline.swift)、[SceneOpacityRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneOpacityRenderer.swift)。
- 自动门：[test_scene_opacity_planner.py](../../../script/tests/test_scene_opacity_planner.py)、[test_scene_opacity_rendering.py](../../../script/tests/test_scene_opacity_rendering.py)、[test_scene_property_binding_program.py](../../../script/tests/test_scene_property_binding_program.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)。planner 锁定 stock definition/material raw SHA、vertex/fragment ShaderContract fingerprint、单 material stage、`MASK=0`、零额外资源/命令/condition 和有限静态或 direct-binding alpha；snapshot -> ordered chain -> GPU 像素门锁定预乘 RGBA 同比缩放。
- 正向运行门：`.codex/scene-opacity-targeted-290-final-20260723-1722/report.json` 中 `2902406982:[365,372,647,664]` 精确执行，`newproperty50=0.2` accepted 且 surface/window identity 不变。负向 `.codex/scene-opacity-failclosed-293-final-20260723-1725/report.json` 中 candidates `[165,454,626,629,924]` 因 SceneScript 保持 Opacity/stages 0。正式 `.codex/scene-opacity-final13-20260723-1730/report.json` 为 13/13，矩阵 SHA-256 `47d01b05a60368cddc679393fb5dd11d562cd4b69cc9d4bd1f559c179fff4e23`，合计 14 stage、Opacity 4、failed 0、legacy blocked 2、route-only 30。
- 边界：只证明 exact stock `MASK=0`；MASK1、SceneScript 计算值、Workshop variants、额外纹理/命令/condition、未知 hash/combo/state 和 unsupported mixed chain 均失败关闭。手写 Metal backend 没有 Windows pixel golden，不等于 generic authored shader 或 WE parity。

<a id="e-effect-shake"></a>
### E-EFFECT-SHAKE: exact stock flow-map Shake profile

- 实现提交：`e505a9e`。代码：[SceneAuthoredShakePlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredShakePlanner.swift)、[SceneShakePipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneShakePipeline.swift)、[SceneShakeRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneShakeRenderer.swift)、[SceneAuthoredEffectExecutionPlan+Backend.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredEffectExecutionPlan+Backend.swift)。
- 自动门：[test_scene_shake_planner.py](../../../script/tests/test_scene_shake_planner.py)、[test_scene_shake_rendering.py](../../../script/tests/test_scene_shake_rendering.py)、[test_scene_authored_effect_chain_planner.py](../../../script/tests/test_scene_authored_effect_chain_planner.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)。覆盖 exact definition/material/raw shader fingerprint、RG8 flow、R8 phase 或 authored white fallback、scene time、Blur 前后顺序、未知 fingerprint 和动态 audio/speed 失败关闭。
- 运行门：`.codex/scene-shake-20260724/targeted-contract-final/report.json` 为 2/2，报告 SHA-256 `6658a772cf3f66d2f52704c5b89ebb0afd35fc6df664c6f30067728ecbc65f23`。未修改 `2802243144` 的 layers `[41,64,115]` succeeded、failed `[]`、Shake 3、chains 3、stages 6，warm-run changed ratio 稳定在约 `0.00977...0.01031`；`2134765860` 的动态 audio/speed variant 保持 Shake/stage 0，changed ratio 约 `0.00042`。
- 边界：只接受 exact stock 单 pass `MASK=0/AUDIOPROCESSING=0/NOISETEXTURE=0`、当前固定 direction/speed profile 和已验证纹理槽；dynamic speed/audio/noise/direction、MASK1、未知 shader/combo/state 和 unsupported sibling 整链失败关闭。当前执行项目内 MSL，不编译 authored shader，也没有 Windows pixel golden。

<a id="e-effect-chain"></a>
### E-EFFECT-CHAIN: ordered strict effect-chain scheduler

- 实现提交：scheduler `b541867`，首条真实链 backend `809b75e`，Water Waves/Water Flow 扩展为 `31ae557`/`94aebc5`。代码：[SceneAuthoredEffectExecutionChain.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredEffectExecutionChain.swift)、[SceneAuthoredEffectChainRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredEffectChainRenderer.swift)、[SceneOffscreenTexturePool.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneOffscreenTexturePool.swift)、[SceneImageLayerCompositor.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneImageLayerCompositor.swift)。
- 自动门：[test_scene_authored_effect_chain_planner.py](../../../script/tests/test_scene_authored_effect_chain_planner.py)、[test_scene_offscreen_texture_pool.py](../../../script/tests/test_scene_offscreen_texture_pool.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)、[test_scene_workshop_shadow_planner.py](../../../script/tests/test_scene_workshop_shadow_planner.py)、[test_scene_workshop_shadow_rendering.py](../../../script/tests/test_scene_workshop_shadow_rendering.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)。planner/pool 门覆盖 identity、连续输入、Shadow prior-effect role、Water resource 仅跨 stage 保留，以及整链预算/LRU 原子回滚；synthetic precise -> precise GPU 门覆盖实际 stage texture transfer、末段合成和失败不泄漏，独立 Shadow GPU 门覆盖该 backend 的像素公式。
- 集成门：首段只应用一次 layer masks/UV/alpha，后段使用 neutral uniforms 并仅保留 strict effect 自有资源。真实 `3724289844:20` 的 `Blur Precise -> Shadow`、`3028090166:86` 的 `Water Flow -> Opacity` 以及 `3768903841` 的重复 Water Waves 均在同一 ordered scheduler 执行；当前没有这些真实 compositor 链的逐 stage 像素 readback，因此整链像素原子性仍由 synthetic GPU 门约束，不把真实矩阵写成 Windows golden。
- 运行门：当前完整快照与固定门分别为 45/45、13/13。完整门共 15 条真实 multi-effect strict chain、91 个 strict stage、Water Flow 10、Water Waves 11、Shake 24；固定门保护 2 条 chain、24 stage、Water Flow 1、Water Waves 6、Shake 1、Opacity 4、Workshop Shadow 1；graph failures 均为空。
- 边界：只调度十一类 strict backend；默认 96 MiB pool 只保证六个 2048x2048 BGRA texture unit，超预算链在规划阶段整链拒绝。Precise Blur 可在两个 material node 之间执行一个 copy 或 swap，Shake/Foliage Sway/Water Ripple/Water Flow/Water Waves/X-Ray 只在精确 profile 和连续输入成立时参与链；X-Ray 受限前缀会明确省略后续 unsupported effect。generic compose/condition/function、跨帧 logical swap、真实 history consumer、authored shader preprocessing/translation/compile、未支持 mask/variant、SceneScript 和动态 profile 继续失败关闭。

<a id="e-effect-rt"></a>
### E-EFFECT-RT: effect-instance render-target foundation and strict consumer

- 代码：[SceneGraphRenderTargetPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneGraphRenderTargetPlan.swift)、[SceneGraphRenderTargetTable.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneGraphRenderTargetTable.swift)、[SceneOffscreenTexturePool.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneOffscreenTexturePool.swift)、[SceneImageLayerCompositor.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneImageLayerCompositor.swift)
- 自动门：[test_scene_graph_render_target_plan.py](../../../script/tests/test_scene_graph_render_target_plan.py)、[test_scene_graph_render_target_table.py](../../../script/tests/test_scene_graph_render_target_table.py)、[test_scene_authored_effect_chain_planner.py](../../../script/tests/test_scene_authored_effect_chain_planner.py)、[test_scene_offscreen_texture_pool.py](../../../script/tests/test_scene_offscreen_texture_pool.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)；覆盖 identity/extent/lifetime、history-required、预算/别名、cache/LRU/resize/format/reset、整链 allocation transaction，以及 precise/standard/Local Contrast staged GPU pixels。
- 运行门：旧 graph-target 正向/负向报告各 3/3；最新 `.codex/scene-opacity-final13-20260723-1730/report.json` 为 13/13，继续验证签名、BGRA/RGBA target consumer、零 authored FBO Shadow/Opacity、真实整链 exact count 与失败关闭。
- 边界：resident budget 只限制 cache transaction 提交后的驻留记账，候选创建时瞬时驱动分配可更高。真实样本报告不输出 `historyRequired` 原因；该分类由 plan 单元门证明。RGBA8888 已由 stock Local Contrast strict profile 消费；Workshop Shadow 只复用 synthetic BGRA input/output，不升级其他 authored target。只有 Precise Blur 两种白名单 material-command 拓扑进入 scheduler；真实 history consumer、compose、condition/function 仍未执行。

<a id="e-graph-command"></a>
### E-GRAPH-COMMAND: same-frame copy/swap foundation

- 实现提交：`f1c6a10`。代码：[SceneGraphRenderTargetPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneGraphRenderTargetPlan.swift)、[SceneGraphRenderTargetTable.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneGraphRenderTargetTable.swift)、[SceneGraphCommandRuntime.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneGraphCommandRuntime.swift)。
- 自动门：[test_scene_graph_render_target_plan.py](../../../script/tests/test_scene_graph_render_target_plan.py)、[test_scene_graph_render_target_table.py](../../../script/tests/test_scene_graph_render_target_table.py)。plan 按作者顺序保留 command，要求 source/target 已声明且已写入、descriptor 完全一致，并拒绝 condition/compose、读前写、未知 command 与整数/预算错误；Metal runtime 验证 logical map 完整、物理纹理不 alias，copy 后字节一致，swap 后 logical identity 映射交换。
- 运行门：定向 `.codex/scene-copy-swap-targeted-372-20260723-1945/results-pass/report.json` 为 1/1；正式 `.codex/scene-copy-swap-final13-20260723-1955/report.json` 为 13/13，报告 SHA-256 `1399d3ea4a4c00bb5529dc6db7b0fd80e810003c945e04d6a26200944f18fe74`。`3723344874` 记录 copy definition 1、swap definition 2、graph swap node 2，但 function 1/condition 4 继续阻断，stage/chain 仍为 0。
- 边界：这只证明同帧 RT 命令的计划、Metal copy 和身份交换合同；现有 strict material scheduler 尚未消费 command list，copy/swap 不跨帧保留资源，也不意味着 Fluid/Motion Blur、compose、condition/function 或 generic authored shader 可执行。

<a id="e-graph-history"></a>
### E-GRAPH-HISTORY: persistent history render-target seed

- 实现提交：`dcedc2e`。代码：[SceneGraphRenderTargetPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneGraphRenderTargetPlan.swift)、[SceneGraphRenderTargetTable.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneGraphRenderTargetTable.swift)、[SceneAuthoredEffectChainRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredEffectChainRenderer.swift)、[SceneImageLayerCompositor.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneImageLayerCompositor.swift)。
- 自动门：[test_scene_graph_render_target_plan.py](../../../script/tests/test_scene_graph_render_target_plan.py)、[test_scene_graph_render_target_table.py](../../../script/tests/test_scene_graph_render_target_table.py)。非 unique FBO 的读前写仍返回 `historyRequired`；显式 `unique:true` FBO 才能通过，并在 lifetime 记录 `requiresHistorySeed`。真实 Metal table 门验证首次 history seed 经过 render-pass clear 后 readback 为全零；clear 只有在 command buffer 完成后才标记已初始化，GPU 失败可重试。
- 真实隔离门：最终签名 Debug App 使用当前真实 Workshop `Scene` 目录的 26 个副本，在隔离 sample root/HOME 下运行 `.codex/scene-history-full26-final-20260723-2332/results-pass/report.json`，26/26 通过、sample root residue 0、strict stage 24、failed 0。样本没有合法的正向 history consumer，因此该门只证明新 table 生命周期没有回归，不把真实 Motion Blur/Fluid stage 计为执行。
- 边界：pool 的现有 effect/plan cache 负责跨帧表复用，reset/resize/switch 会丢弃并重建 table；当前不保存跨帧 logical swap 映射，不实现 seek/pause/fixed-step history、真实 history consumer、generic compose、condition/function 或通用 authored shader。Precise Blur 的同帧 interleave 与 exact legacy compose 归一化不改变本项 `L2 wired/routed` 等级。

<a id="e-graph-interleave"></a>
### E-GRAPH-INTERLEAVE: bounded material-command scheduling

- 实现提交：`ebf44a9`。代码：[SceneGraphNodeScheduler.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneGraphNodeScheduler.swift)、[SceneAuthoredPreciseBlurPlanner+Topology.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredPreciseBlurPlanner+Topology.swift)、[SceneOffscreenEffectRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneOffscreenEffectRenderer.swift)。
- 自动门：[test_scene_authored_effect_execution.py](../../../script/tests/test_scene_authored_effect_execution.py)、[test_scene_graph_render_target_table.py](../../../script/tests/test_scene_graph_render_target_table.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)、[test_scene_authored_effect_chain_planner.py](../../../script/tests/test_scene_authored_effect_chain_planner.py)。定向 graph/runtime/Metal/semantics 共 72/72；GPU 门锁定 pure material、copy interleave 和 swap interleave 输出差异在阈值内、非空且保持 premultiplied alpha。
- 真实隔离门：当前真实目录 26 个副本的 `.codex/scene-command-interleave-20260724-003051/full26-results-pass2/report.json` 为 26/26、residue 0、strict stage 24、failed 0；固定 `.codex/scene-command-interleave-20260724-003051/final13-results-pass/report.json` 为 13/13、residue 0、stage 14、chain 1、failed 0。`3723344874` 仍为 stage/chain 0，`unsupportedFunctions:1` 与 `unsupportedCondition:4` 继续阻断。
- 边界：Precise Blur 只接受 `material0 -> copy -> material1` 或 `material0 -> swap -> material1`。copy 要求两个 descriptor 匹配的非 unique BGRA target；swap 要求 destination `unique:true`。当前真实 Workshop 集合没有合法正向 interleave 样本，因此 `L3 executed-degraded` 来自 synthetic GPU 正反门；generic FBO command graph、跨帧 mapping/history、Motion Blur、Fluid、generic compose、condition/function 与 authored shader 仍未执行。

<a id="e-graph-legacy-compose"></a>
### E-GRAPH-LEGACY-COMPOSE: exact Blur Precise legacy two-pass normalization

- 实现提交：`4f13daf`。代码：[SceneAuthoredPreciseBlurPlanner+Topology.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredPreciseBlurPlanner+Topology.swift)、[SceneAuthoredEffectRenderPlanner+Resolution.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredEffectRenderPlanner+Resolution.swift)、[SceneAuthoredEffectExecutionPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredEffectExecutionPlan.swift)。只接受 exact `KERNEL=0` Blur Precise 的 `[{"material":"...gaussian_x.json","compose":true},{"material":"...gaussian_y.json"}]`，合成 `_rt_FullCompoBuffer1`，让横向 pass 读取 `previous@0` 并写入该 target，纵向 pass 从该 target slot 0 写 effect output。4K legacy profile 可使用 2048 offscreen cap，blur offset 仍按原始 source extent 归一；显式 authored FBO profile 继续要求 exact extent。
- 自动门：[test_scene_authored_effect_execution.py](../../../script/tests/test_scene_authored_effect_execution.py)、[test_scene_effect_render_graph.py](../../../script/tests/test_scene_effect_render_graph.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)。定向 planner/GPU 共 34/34；generic compose、非 Blur Precise、非 `KERNEL=0`、mixed shape、arbitrary kernel、Refraction 和 scene-background capture 均保持失败关闭。
- 原始样本门：`2067939514` 的 graph target `0 -> 16`、blocker `32 -> 0`、unblocked layer `12 -> 28`，最终 graph SHA-256 `332256f9c917608413e6a56453e36422c99f3e1bd874f833bf46553b53a7cba2`；`2802243144` 分别为 `0 -> 3`、`6 -> 0`、`1 -> 4`，SHA-256 `a2c038386e38447162f17c00c147f475782d2f93a84e448280164b889fd81923`。两者 strict stage 都仍为 0，完整 effect chain 继续被 Shake 等未支持 sibling 阻断，因此不能宣称原始画面已改善。
- 正向隔离 GPU 门：仅在 `2802243144` 副本中关闭 layer 41 的无关 Shake sibling，保留原 Blur definition/material/shader/参数不变；`.codex/scene-legacy-compose-20260724/positive-results-pass/report.json` 为 1/1，报告 SHA-256 `d09b531ba06d185c39ebabb6aa5d81069bc1b05e991aac9f3f49b6ba6f049546`，layer 41 precise Blur stage 1、failed 0，layers 64/115 继续 legacy blocked。该门证明 executor 可运行，不是未修改样本的视觉通过证据。
- 边界：generic `compose` 整体仍为 `L2`。本 profile 不提供 scene-behind-layer identity，不支持 Refraction、背景捕获、任意 compose 链或 WE 像素等价。

<a id="e-video"></a>
### E-VIDEO: 内嵌 MP4 image-layer 子集

- 代码：[SceneVideoTextureSource.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneVideoTextureSource.swift)、[SceneTextureLoader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneTextureLoader.swift)
- 自动门：[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py) 与现有 frame-context tests
- 运行门：固定矩阵中的 embedded video frame/candidate 计数和共享 host-time 运行日志；seek/pause/loop 精确门仍缺失。

<a id="e-lifecycle"></a>
### E-LIFECYCLE: switch / stop / diagnostics

- 代码：[SceneDesktopWallpaperHost.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost.swift)、[SceneDiagnostics.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDiagnostics.swift)
- 自动门：[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)
- 运行门：所有正式矩阵样本退出后 `surface=0`，并记录 timeout、resource、graph、GPU 和 unsupported diagnostics；尚无 30 分钟交互或 2 小时 soak。

## 3. 使用规则

1. 专项表的 `L3` 行必须直接链接本页某个证据包，或自行给出代码、自动测试和运行证据三联。
2. 一个证据包只能证明标题和边界中写明的子集；不能横向给同名但未消费的官方能力升级。
3. 更新运行实现后先生成新的隔离报告，再更新本页、本专题表、总台账和现役计划。
4. 报告丢失、样本集变化或 App 身份变化时，保留历史数字但不得写成当前已复核事实。
