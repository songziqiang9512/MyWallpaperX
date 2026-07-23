# Scene 运行证据索引

> 状态：现役证据入口
>
> 最近核对：2026-07-23
>
> 实现基线：`b541867`

本页给覆盖表中的 `L3` 子集提供可追溯证据包。每个证据包至少包含代码、自动测试和真实运行或 GPU 证据；缺少任一项的能力只能标 `L0-L2`，或在专项表中明确写 `gate incomplete`。`.codex` 报告是本机隔离运行产物，不提交 Git；报告路径、App 身份和摘要写入现役文档，避免将其误当源码 fixture。

## 1. 当前统一门

| 项目 | 当前证据 |
|---|---|
| 视觉矩阵 | ordered strict effect-chain 正式矩阵 `.codex/scene-effect-chain-gated-final13-20260723/report.json` 为 13/13；七个 effect-graph 代表样本锁定 exact chain/stage count，均不证明 WE parity |
| 最新合同门 | Scene tests 251 total / 250 pass / 1 skip |
| ShaderContract | 173 contracts = 143 authored + 30 host built-in；286 stages、0 diagnostics；source/IR include 155、annotation 1523、declaration 2660，见 E-SHADER-CONTRACT |
| Live property | alpha 两项、solid color 两项与 strict Local Contrast strength 均 accepted、surface/window identity 不变；报告见 E-LIVE-PROPERTY |
| Provider 双代 | `2938612768` static image blend 5/5；`2902406982` named capture 6/6、binding 7/7；报告见 E-PROVIDER |
| 签名 App | `2.0.8 (268)`，Team `H9QWU9XN8R`，CDHash `61fc420b6dc3c014d1e18f2cdf16fef1d127d5ec`；正式矩阵运行前后签名均验证 |
| executable SHA-256 | `629ae6daf23a6e62f2d9502042dc94b69a54419749e801b26c4743651bc12758` |
| 样本边界 | 真实 Workshop root 只读；报告均来自隔离 sample root 与临时 HOME |

## 2. 证据包

<a id="e-ingest"></a>
### E-INGEST: Scene / PKG / TEX / resource ingest

- 代码：[SceneProject.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneProject.swift)、[ScenePkgReader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/ScenePkgReader.swift)、[SceneTextureLoader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneTextureLoader.swift)、[SceneResourceReferenceIndex.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneResourceReferenceIndex.swift)
- 自动门：[test_scene_resource_reference_index.py](../../../script/tests/test_scene_resource_reference_index.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)
- 运行门：正式 13 样本报告记录 interpretation/resource diagnostics、loaded/candidate counts 和 stop lifecycle。

<a id="e-base"></a>
### E-BASE: 基础 layer、层级、cover 与合成

- 代码：[SceneRenderDescriptor.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneRenderDescriptor.swift)、[SceneMetalRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneMetalRenderer.swift)、[SceneImageLayerCompositor.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneImageLayerCompositor.swift)
- 自动门：[test_scene_solid_layers.py](../../../script/tests/test_scene_solid_layers.py)、[test_scene_capture_geometry.py](../../../script/tests/test_scene_capture_geometry.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)
- 运行门：正式矩阵的 layer/image/solid/text/particle 计数、cover projection、非黑截图和 GPU completion。

<a id="e-frame"></a>
### E-FRAME: Frame Context

- 代码：[SceneDesktopWallpaperHost.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneDesktopWallpaperHost.swift)、[SceneFrameContext.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneFrameContext.swift)、[SceneMetalView.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneMetalView.swift)
- 自动门：[test_scene_frame_context.py](../../../script/tests/test_scene_frame_context.py)、[test_scene_dynamic_snapshot.py](../../../script/tests/test_scene_dynamic_snapshot.py)
- 运行门：`.codex/scene-frame-context-final13-20260723/report.json` 13/13；同一 host frame 采样后广播，stop 后 surface=0。

<a id="e-parallax"></a>
### E-PARALLAX: Camera Parallax 与受限 pointer 投影

- 代码：[SceneLayerParallax.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneLayerParallax.swift)、[SceneMetalView.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneMetalView.swift)
- 自动门：[test_scene_layer_parallax.py](../../../script/tests/test_scene_layer_parallax.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)
- 运行门：`.codex/scene-parallax-correction-formal13-20260723/report.json` 与 `.codex/scene-property-parallax-off-gate-20260722/report.json`；显式开启和 author-off 分开验证。

<a id="e-property"></a>
### E-PROPERTY: User Properties 与受限 target

- 代码：[SceneUserProperty.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneUserProperty.swift)、[SceneUserPropertyBindings.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneUserPropertyBindings.swift)、[SceneUserPropertyResolver.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneUserPropertyResolver.swift)
- 自动门：[test_scene_user_properties.py](../../../script/tests/test_scene_user_properties.py)、[test_scene_user_property_textures.py](../../../script/tests/test_scene_user_property_textures.py)
- 运行门：`.codex/scene-property-text-day-gate-pass-20260722/report.json`、`.codex/scene-user-texture-final13-r2-20260723/report.json`；layer alpha/solid color 的 live 子集见下一证据包，其余 target 仍按 consumer 能力回退整场重建。

<a id="e-live-property"></a>
### E-LIVE-PROPERTY: B0 binding program 与已注册 live consumers

- 代码：[ScenePropertyBindingProgram.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/ScenePropertyBindingProgram.swift)、[ScenePropertyLiveUpdateState.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/ScenePropertyLiveUpdateState.swift)、[SceneSurfaceEvaluationTransaction.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneSurfaceEvaluationTransaction.swift)、[SceneDynamicLayerValues.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneDynamicLayerValues.swift)、[SceneDesktopWallpaperHost.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneDesktopWallpaperHost.swift)
- 自动门：[test_scene_property_binding_program.py](../../../script/tests/test_scene_property_binding_program.py)、[test_scene_interpretation_file.py](../../../script/tests/test_scene_interpretation_file.py)、[test_scene_surface_evaluation_transaction.py](../../../script/tests/test_scene_surface_evaluation_transaction.py)、[test_scene_property_live_update_state.py](../../../script/tests/test_scene_property_live_update_state.py)、[test_scene_dynamic_layer_values.py](../../../script/tests/test_scene_dynamic_layer_values.py)、[test_scene_property_live_routing.py](../../../script/tests/test_scene_property_live_routing.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)
- 运行门：alpha 的 `2902406982:newproperty11` 与 `2938612768:newproperty17` 分别见 `.codex/scene-b0-live-alpha-20260723-0941/report.json`、`.codex/scene-b0-live-alpha-293-20260723-0941/report.json`；solid color 的 `3122339805:accentcolourdefault800080` 与 `2902406982:newproperty33` 分别见 `.codex/scene-live-solid-color-312-accent-20260723-1011/report.json`、`.codex/scene-live-solid-color-290-20260723-1013/report.json`；strict Local Contrast 的 `2902406982:brcontraststrength=3.0` 见 `.codex/scene-local-contrast-targeted-20260723/report.json` 与正式 13 样本报告。各项均 `accepted=true` 且 surface/window identity 不变；Local Contrast 更新后画面 changed ratio 为 `0.7587968`。
- 负向门：`.codex/scene-live-solid-color-312-20260723-1006/report.json` 中 `basecolor` 被拒绝，因为同键除 48 条 solid color 指令外还有未支持目标；状态没有部分提交。
- 边界：只证明 image/solid/text 与 `shouldCapture` utility 的 layer alpha、纯 solid layer color，以及 strict execution catalog 中 stock Local Contrast pass 3 `strength`。ordered strict chain 中每个 Local Contrast stage 从同一 per-surface frame snapshot 单独解析 strength，链失败不会提交部分画面；这不扩展可 live 的 target 集合。Local Contrast 的真实样本证据是“更新被接受 + 同 surface/window + 画面变化”，结合 snapshot 与 GPU 像素单测证明消费路径；当前遥测没有直接记录 `3.0` uniform 上传。particle、container、non-solid color、其他 effect constant、unsupported mixed chain 或无活动 consumer 的 key 必须返回整场重建；program 可编译本身不构成 live 证据。

<a id="e-text"></a>
### E-TEXT: 静态文字

- 代码：[SceneTextTextureLoader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneTextTextureLoader.swift)
- 自动门：[test_scene_text_rendering.py](../../../script/tests/test_scene_text_rendering.py)、[test_scene_user_properties.py](../../../script/tests/test_scene_user_properties.py)
- 运行门：`.codex/scene-text-fixed-20260722/report.json` 和正式矩阵的 text loaded/candidate 结构门；没有 Windows 字体/基线 golden。

<a id="e-particle"></a>
### E-PARTICLE: 2D Particle 子集

- 代码：[SceneParticleRuntime.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneParticleRuntime.swift)、[SceneParticleSimulator.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneParticleSimulator.swift)、[SceneParticleMetalPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneParticleMetalPipeline.swift)
- 自动门：[test_scene_particle_definitions.py](../../../script/tests/test_scene_particle_definitions.py)、[test_scene_particle_simulator.py](../../../script/tests/test_scene_particle_simulator.py)、[test_scene_particle_rendering.py](../../../script/tests/test_scene_particle_rendering.py)、[test_scene_particle_runtime.py](../../../script/tests/test_scene_particle_runtime.py)
- 运行门：`.codex/scene-particle-builtins-final13-r2-20260723/report.json`；可见 runtime layer 14/27，`3750813609` 为 7/9，未支持层保持 fail-closed。

<a id="e-provider"></a>
### E-PROVIDER: Texture provider、named target 与静态 dependency blend

- 代码：[SceneFrameTextureRegistry.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneFrameTextureRegistry.swift)、[SceneDependencyRenderPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneDependencyRenderPlan.swift)、[SceneImageBlendRuntime.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneImageBlendRuntime.swift)、[SceneImageBlendPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneImageBlendPipeline.swift)
- 自动门：[test_scene_frame_texture_registry.py](../../../script/tests/test_scene_frame_texture_registry.py)、[test_scene_dependency_render_plan.py](../../../script/tests/test_scene_dependency_render_plan.py)、[test_scene_image_blend_plan.py](../../../script/tests/test_scene_image_blend_plan.py)、[test_scene_user_property_textures.py](../../../script/tests/test_scene_user_property_textures.py)
- 运行门：fallback/file 证据为 `.codex/scene-texture-fallback-293-v3-20260723/report.json`、`.codex/scene-user-texture-final13-r2-20260723/report.json`；双代修复后的定向证据为 `.codex/scene-provider-generation-293-20260723-1035/report.json` 与 `.codex/scene-provider-generation-290-20260723-1036/report.json`。
- 边界：连续帧同 identity、同 `MTLTexture` 的 layer/property/system publication 保持 resource generation；替换或缺席后重现会换代。named target 是当帧重写资源，继续使用 frame epoch。system/media/video 的显式内容 generation、metadata、异步取消和通用 consumer 尚未完成。

<a id="e-utility"></a>
### E-UTILITY: Utility capture 与 named primary target

- 代码：[SceneUtilityLayer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneUtilityLayer.swift)、[SceneNamedRenderTargetPool.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneNamedRenderTargetPool.swift)、[SceneDependencyFrameRuntime.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneDependencyFrameRuntime.swift)
- 自动门：[test_scene_utility_layers.py](../../../script/tests/test_scene_utility_layers.py)、[test_scene_named_render_target_pool.py](../../../script/tests/test_scene_named_render_target_pool.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)
- 运行门：正式矩阵和 `2902406982` 定向报告记录 utility capture、named producer/consumer 与 GPU completion。

<a id="e-effect-ir"></a>
### E-EFFECT-IR: EffectDefinition / Material / authored graph

- 代码：[SceneEffectDefinition.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneEffectDefinition.swift)、[SceneAuthoredEffectRenderPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlan.swift)、[SceneAuthoredEffectRenderPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectRenderPlanner.swift)
- 自动门：[test_scene_effect_definition.py](../../../script/tests/test_scene_effect_definition.py)、[test_scene_effect_render_graph.py](../../../script/tests/test_scene_effect_render_graph.py)、[test_scene_authored_effect_execution.py](../../../script/tests/test_scene_authored_effect_execution.py)
- 运行门：`.codex/scene-effect-ir-formal13-final-20260723/report.json` 与 `.codex/scene-effect-graph-canonical-final-20260723/report.json`；只证明结构和 canonical identity，不证明 GPU execution。

<a id="e-shader-contract"></a>
### E-SHADER-CONTRACT: Shader source contract IR v1

- 代码：[SceneShaderContract.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneShaderContract.swift)、[SceneShaderContractLoader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneShaderContractLoader.swift)、[SceneAssetCatalog.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAssetCatalog.swift)、[SceneInterpretationFile.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneInterpretationFile.swift)
- 自动门：[test_scene_shader_contract.py](../../../script/tests/test_scene_shader_contract.py)、[test_scene_interpretation_file.py](../../../script/tests/test_scene_interpretation_file.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)。loader 门覆盖 absolute/`..`/root-stage-include symlink escape、invalid UTF-8、missing/unreadable stage、malformed annotation 和 duplicate identity；benchmark 门覆盖 wire 必填字段、source/raw hash、stage kind/path/nested arrays、diagnostic schema、host built-in 空 stage 与 canonical SHA。
- 运行门：`.codex/scene-shader-contract-final13-v2-20260723/report.json` 为 13/13；173 contracts（143 authored + 30 host built-in）、286 stages、0 diagnostics。独立 source/IR 复核中 include、annotation、declaration 数完全一致，分别为 `155/1523/2660`。
- 构建门：Scene tests 223 total / 222 pass / 1 skip；签名 App `2.0.8 (268)`，Team `H9QWU9XN8R`，CDHash `033bc40a5ee8dbf0d6bd0e478e9a8c5a875b90b4`，executable SHA-256 `2b6a8d6ee9863de41fd91792f682c2ff0c49ecf1dd15a9909d3d6e924f76bab8`。
- 边界：本证据只把 source/include/annotation/declaration 升为 L1 recognized/preserved；没有 include expansion、macro/permutation preprocessing、translation、stage link、compile、typed uniform/default consumption、uniform upload 或 authored shader GPU execution。

<a id="e-effect-inline"></a>
### E-EFFECT-INLINE: 受限手写 Effect profiles

- 代码：[SceneEffectRuntimePlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneEffectRuntimePlan.swift)、[SceneInlineEffectRuntime.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneInlineEffectRuntime.swift)、[SceneMetalPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneMetalPipeline.swift)
- 自动门：[test_scene_effect_mask_gating.py](../../../script/tests/test_scene_effect_mask_gating.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)
- 运行门：正式矩阵中的明确 runtime counters/summary。当前只是 Foliage/Iris/Water/Cursor/Chromatic/Perspective-Opacity 等表内子集，不执行 authored shader。

<a id="e-effect-blur"></a>
### E-EFFECT-BLUR: strict Blur graph profiles

- 代码：[SceneAuthoredEffectExecutionPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectExecutionPlan.swift)、[SceneAuthoredStandardBlurPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredStandardBlurPlanner.swift)、[SceneOffscreenEffectRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneOffscreenEffectRenderer.swift)、[SceneStandardBlurRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneStandardBlurRenderer.swift)
- 自动门：[test_scene_authored_effect_execution.py](../../../script/tests/test_scene_authored_effect_execution.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)、[test_scene_offscreen_texture_pool.py](../../../script/tests/test_scene_offscreen_texture_pool.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)
- 运行门：`.codex/scene-graph-target-positive-final-20260723/report.json` 为 3/3，6 个 graph layer GPU succeeded、0 failed；`.codex/scene-graph-target-negative-final-20260723/report.json` 为 3/3，unsupported graph 未误执行。旧 formal13 报告仍是历史全矩阵证据。

<a id="e-effect-local-contrast"></a>
### E-EFFECT-LOCAL-CONTRAST: strict stock Local Contrast graph profile

- 实现提交：`136d35c`。代码：[SceneAuthoredLocalContrastPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredLocalContrastPlanner.swift)、[SceneLocalContrastPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneLocalContrastPipeline.swift)、[SceneLocalContrastRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneLocalContrastRenderer.swift)、[SceneAuthoredEffectExecutionPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectExecutionPlan.swift)。
- 自动门：[test_scene_local_contrast_planner.py](../../../script/tests/test_scene_local_contrast_planner.py)、[test_scene_local_contrast_rendering.py](../../../script/tests/test_scene_local_contrast_rendering.py)、[test_scene_property_binding_program.py](../../../script/tests/test_scene_property_binding_program.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)。固定 stage golden 覆盖 alpha-weighted 4-tap downsample、13-tap X/Y Gaussian、BGRA source/output、RGBA quarter targets、original alpha 与 strength `0/0.32/1`。
- 运行门：定向报告 `.codex/scene-local-contrast-targeted-20260723/report.json` 为 2/2；正式报告 `.codex/scene-local-contrast-final13-20260723/report.json` 为 13/13。`2902406982` layers `167/177` 执行 Local Contrast，graph succeeded 为 `[167,177,530]`、failed 为空、Local Contrast count 为 2；`2938612768` 的可见 4/5-effect mixed chains 保持 count 0，既有 image blend 5/5。两样本退出均为 `surface 1 -> 0`。
- profile 边界：每个 stage 只接受 exact stock 4 material pass、两个 FBO `scale=4` non-unique `rgba8888` RT、KERNEL0/GREYSCALE0/MASK0、Gaussian `scale=(1,1)`（含官方缺省）和三份 exact authored shader contract fingerprint。mask、greyscale、KERNEL1/2、非默认 Gaussian scale、包含 unsupported stage 的 mixed chain、未知/变更 shader、condition/function 均 fail closed；fingerprint 只用于准入，authored source 不被编译或执行，也没有 generic shader translation。
- parity 边界：Metal backend 采用 stock shader 的非 `HLSL_SM30` 采样语义，没有该分支的 `0.75 / resolution` 偏移；没有 Windows golden，因此状态为 `L3 executed-degraded`，不能宣称跨后端逐像素一致。

<a id="e-effect-chain"></a>
### E-EFFECT-CHAIN: ordered strict effect-chain scheduler

- 实现提交：`b541867`。代码：[SceneAuthoredEffectExecutionChain.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectExecutionChain.swift)、[SceneAuthoredEffectChainRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectChainRenderer.swift)、[SceneOffscreenTexturePool.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneOffscreenTexturePool.swift)、[SceneImageLayerCompositor.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneImageLayerCompositor.swift)。
- 自动门：[test_scene_authored_effect_chain_planner.py](../../../script/tests/test_scene_authored_effect_chain_planner.py)、[test_scene_offscreen_texture_pool.py](../../../script/tests/test_scene_offscreen_texture_pool.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)。planner 门覆盖 blocker、单 layer、严格 effect/node/target identity、连续 layerSource -> effectOutput 输入、全节点/target 归属、final output 与 all-supported backend；pool 门覆盖整链预算、victim selection、cache hit 与失败时 resident bytes/access/LRU 不变。
- GPU 门：synthetic 两段 Blur 在同一 command buffer 顺序执行，stage 0 output -> stage 1 input 的 channel delta 不大于 1，stage 1 确实改变像素，final -> main delta 不大于 2；首段只应用一次 layer masks/UV/alpha，后段使用 neutral uniforms/empty masks。强制第二段失败时第一段虽产生像素，main 仍为透明 `[0,0,0,0]`。
- 运行门：`.codex/scene-effect-chain-gated-final13-20260723/report.json` 为 13/13，七个代表样本对 chain/stage 数精确设门；当前共 0 条真实 multi-effect strict chain、8 个 strict stage，graph failures 均为空。`3724289844` 为 chains 0/stages 2、succeeded `[28,36]`、blocked `[20]`；`2938612768` 为 chains 0/stages 0，证明 unsupported mixed chains 没有被部分执行。
- 边界：只调度当前 strict material-only backends，不执行 copy/swap/compose/history/condition/function，也不预处理、翻译或编译 authored shader。当前没有真实 fully-supported multi-effect 正向链；synthetic 正向门不能替代 Workshop 运行证据。下一门是 `3724289844` layer `20` 的 exact Workshop single-pass shadow profile，它不是官方 45 项 Shadow 或 generic authored shader 能力。

<a id="e-effect-rt"></a>
### E-EFFECT-RT: effect-instance render-target foundation and strict consumer

- 代码：[SceneGraphRenderTargetPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneGraphRenderTargetPlan.swift)、[SceneGraphRenderTargetTable.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneGraphRenderTargetTable.swift)、[SceneOffscreenTexturePool.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneOffscreenTexturePool.swift)、[SceneImageLayerCompositor.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneImageLayerCompositor.swift)
- 自动门：[test_scene_graph_render_target_plan.py](../../../script/tests/test_scene_graph_render_target_plan.py)、[test_scene_graph_render_target_table.py](../../../script/tests/test_scene_graph_render_target_table.py)、[test_scene_authored_effect_chain_planner.py](../../../script/tests/test_scene_authored_effect_chain_planner.py)、[test_scene_offscreen_texture_pool.py](../../../script/tests/test_scene_offscreen_texture_pool.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)；覆盖 identity/extent/lifetime、history-required、预算/别名、cache/LRU/resize/format/reset、整链 allocation transaction，以及 precise/standard/Local Contrast staged GPU pixels。
- 运行门：旧 graph-target 正向/负向报告各 3/3；最新 `.codex/scene-effect-chain-gated-final13-20260723/report.json` 为 13/13，继续验证签名、BGRA/RGBA target consumer、整链 exact count 与失败关闭。
- 边界：resident budget 只限制 cache transaction 提交后的驻留记账，候选创建时瞬时驱动分配可更高。真实样本报告不输出 `historyRequired` 原因；该分类由 plan 单元门证明。RGBA8888 已由 stock Local Contrast strict profile 消费，ordered strict scheduler 已执行全支持 material-only chain 子集，但这不升级其他 RGBA graph；history、copy、swap、compose、condition/function 和 generic command scheduler 均未执行。

<a id="e-video"></a>
### E-VIDEO: 内嵌 MP4 image-layer 子集

- 代码：[SceneVideoTextureSource.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneVideoTextureSource.swift)、[SceneTextureLoader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneTextureLoader.swift)
- 自动门：[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py) 与现有 frame-context tests
- 运行门：固定矩阵中的 embedded video frame/candidate 计数和共享 host-time 运行日志；seek/pause/loop 精确门仍缺失。

<a id="e-lifecycle"></a>
### E-LIFECYCLE: switch / stop / diagnostics

- 代码：[SceneDesktopWallpaperHost.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneDesktopWallpaperHost.swift)、[SceneDiagnostics.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneDiagnostics.swift)
- 自动门：[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)
- 运行门：所有正式矩阵样本退出后 `surface=0`，并记录 timeout、resource、graph、GPU 和 unsupported diagnostics；尚无 30 分钟交互或 2 小时 soak。

## 3. 使用规则

1. 专项表的 `L3` 行必须直接链接本页某个证据包，或自行给出代码、自动测试和运行证据三联。
2. 一个证据包只能证明标题和边界中写明的子集；不能横向给同名但未消费的官方能力升级。
3. 更新运行实现后先生成新的隔离报告，再更新本页、本专题表、总台账和现役计划。
4. 报告丢失、样本集变化或 App 身份变化时，保留历史数字但不得写成当前已复核事实。
