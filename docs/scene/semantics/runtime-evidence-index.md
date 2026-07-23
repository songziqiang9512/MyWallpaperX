# Scene 运行证据索引

> 状态：现役证据入口
>
> 最近核对：2026-07-23
>
> 实现基线：`f1c6a10`

本页给覆盖表中的 `L3` 子集提供可追溯证据包。每个证据包至少包含代码、自动测试和真实运行或 GPU 证据；缺少任一项的能力只能标 `L0-L2`，或在专项表中明确写 `gate incomplete`。`.codex` 报告是本机隔离运行产物，不提交 Git；报告路径、App 身份和摘要写入现役文档，避免将其误当源码 fixture。

## 1. 当前统一门

| 项目 | 当前证据 |
|---|---|
| 视觉矩阵 | copy/swap 正式矩阵 `.codex/scene-copy-swap-final13-20260723-1955/report.json` 为 13/13；strict graph 仍为 14 stage、1 real chain、failed 0，均不证明 WE parity |
| 最新合同门 | Scene tests 275 total / 273 pass / 2 skip |
| ShaderContract | 173 contracts = 143 authored + 30 host built-in；286 stages、0 diagnostics；source/IR include 155、annotation 1523、declaration 2660，见 E-SHADER-CONTRACT |
| Live property | layer alpha、solid color、strict Local Contrast/Opacity 与 direct text content/point-size/color 均 accepted、surface/window identity 不变；报告见 E-LIVE-PROPERTY / E-DYNAMIC-TEXT |
| Provider 双代 | `2938612768` static image blend 5/5；`2902406982` named capture 6/6、binding 7/7；报告见 E-PROVIDER |
| 签名 App | `2.0.8 (268)`，Team `H9QWU9XN8R`，CDHash `c0940f2da38e653e338d829663ad3a0596c73b50`；正式矩阵运行前后签名均验证 |
| executable SHA-256 | `fe940c3d6706655d0a07556ef7570ab581c9ee000c5ec62344bd0df92c6d9827` |
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
- 运行门：alpha/solid color/Local Contrast/Opacity 沿用既有定向报告；direct text 的 `2134765860:customtext/textcolor/textsize` 见 `.codex/scene-dynamic-text-targeted-213-final-20260723-1907/report.json`。各项均 `accepted=true` 且 surface/window identity 不变。
- 负向门：`.codex/scene-live-solid-color-312-20260723-1006/report.json` 中 `basecolor` 被拒绝，因为同键除 48 条 solid color 指令外还有未支持目标；状态没有部分提交。
- 边界：证明 layer alpha、solid color、有效可见 direct text 三字段，以及 strict Local Contrast/Opacity。SceneScript、hidden/no-consumer text、particle、container、non-solid color、其他 effect constant 或 unsupported mixed key 必须返回整场重建。program 可编译本身不构成 live 证据。

<a id="e-text"></a>
### E-TEXT: 静态文字

- 代码：[SceneTextTextureLoader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneTextTextureLoader.swift)
- 自动门：[test_scene_text_rendering.py](../../../script/tests/test_scene_text_rendering.py)、[test_scene_user_properties.py](../../../script/tests/test_scene_user_properties.py)
- 运行门：`.codex/scene-text-fixed-20260722/report.json` 和正式矩阵的 text loaded/candidate 结构门；没有 Windows 字体/基线 golden。

<a id="e-dynamic-text"></a>
### E-DYNAMIC-TEXT: direct property 动态文字与 generation lifecycle

- 代码：[SceneDynamicTextTextureStore.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneDynamicTextTextureStore.swift)、[SceneDynamicTextGenerationState.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneDynamicTextGenerationState.swift)、[ScenePropertyBindingCompiler+TargetMapping.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/ScenePropertyBindingCompiler+TargetMapping.swift)、[SceneTextTextureLoader.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneTextTextureLoader.swift)
- 自动门：[test_scene_dynamic_text_binding.py](../../../script/tests/test_scene_dynamic_text_binding.py)、[test_scene_dynamic_text_generation.py](../../../script/tests/test_scene_dynamic_text_generation.py)、[test_scene_frame_context.py](../../../script/tests/test_scene_frame_context.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)。覆盖三类 typed value、错误 kind/conditional fail closed、重复值去重、A->B->C stale completion 拒绝、失败保留 last-ready 和 reset。
- 运行门：`.codex/scene-dynamic-text-targeted-213-final-20260723-1907/report.json`；隔离 `2134765860` 先以 `text=2` 启用作者 Custom 模式，再 live 更新 `customtext/textcolor/textsize`，surface `1 -> 1`、window `[94398] -> [94398]`、changed ratio `0.003541478640192539`、text `6/6`。正式回归 `.codex/scene-dynamic-text-final13-20260723-1915/report.json` 为 13/13、sample root residue 0。
- 边界：只接受 direct user property；有效可见且有 text/style 的 layer 才是活动 consumer。SceneScript、clock/date/media、hidden/no-consumer layer、静态 `text` label、conditional binding、Windows font/layout parity 均不在本证据包内。

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

<a id="e-effect-workshop-shadow"></a>
### E-EFFECT-WORKSHOP-SHADOW: exact Workshop single-pass Shadow profile

- 实现提交：`809b75e`。代码：[SceneAuthoredWorkshopShadowPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredWorkshopShadowPlanner.swift)、[SceneWorkshopShadowPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneWorkshopShadowPipeline.swift)、[SceneWorkshopShadowRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneWorkshopShadowRenderer.swift)。
- 自动门：[test_scene_workshop_shadow_planner.py](../../../script/tests/test_scene_workshop_shadow_planner.py)、[test_scene_workshop_shadow_rendering.py](../../../script/tests/test_scene_workshop_shadow_rendering.py)。planner 门锁定完整 definition/material/vertex+fragment ShaderContract fingerprint、单 material stage、零 authored FBO/bind/slot、`MASK=0`、`BLENDMODE=0`、normal/nocull/depth disabled、black color、静态有限 alpha/border/offset，并验证 prior-effect input role；未知 hash/combo/state/constant/user binding 均失败关闭。独立 Shadow GPU 门覆盖 premultiplied alpha、border/offset、clamp-to-edge、零 alpha identity 与非法资源/常量失败关闭。
- 运行门：定向 `.codex/scene-workshop-shadow-targeted-20260723-1536/report.json` 为 1/1；正式 `.codex/scene-workshop-shadow-final13-20260723-1540/report.json` 为 13/13。`3724289844` 为 stages 4/chains 1/Shadow 1、succeeded `[20,28,36]`、blocked/failed 为空；全矩阵为 10 stage、1 real chain、Shadow 1、failed 0、legacy blocked 2、route-only 34。
- target/FBO 边界：该 definition 没有 authored FBO；executor 复用 `SceneGraphRenderTargetTable` 的 synthetic full-size input/output texture，并在 ordered chain 中把 precise Blur 输出作为 Shadow 输入。这只证明零-FBO strict profile 与既有 table/transaction 能协作，不升级 authored extent/format/clear/history。
- parity/产品边界：执行器运行仓内手写 MSL，不预处理、翻译或编译 authored shader。它是 Workshop `3488490208/shadow_____________` 的 exact profile，不是官方 45 项 Effect、generic Shadow 或 lighting shadow；`BLENDMODE=0` 没有合法官方 Windows 像素 oracle，因此仍是 `L3 executed-degraded`，不等于 WE 像素等价。当前 GPU 单测使用整数 X offset，尚未像素锁定样本实际 `(2,-2)` 的亚像素插值/Y 方向，也没有 Blur -> Shadow compositor 像素 golden；定向真实样本矩阵是当前集成门。Shadow 常量保持静态，没有新增 live target。

<a id="e-effect-opacity"></a>
### E-EFFECT-OPACITY: exact stock `MASK=0` Opacity profile

- 实现提交：`b8842d8`。代码：[SceneAuthoredOpacityPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredOpacityPlanner.swift)、[SceneOpacityPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneOpacityPipeline.swift)、[SceneOpacityRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneOpacityRenderer.swift)。
- 自动门：[test_scene_opacity_planner.py](../../../script/tests/test_scene_opacity_planner.py)、[test_scene_opacity_rendering.py](../../../script/tests/test_scene_opacity_rendering.py)、[test_scene_property_binding_program.py](../../../script/tests/test_scene_property_binding_program.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)。planner 锁定 stock definition/material raw SHA、vertex/fragment ShaderContract fingerprint、单 material stage、`MASK=0`、零额外资源/命令/condition 和有限静态或 direct-binding alpha；snapshot -> ordered chain -> GPU 像素门锁定预乘 RGBA 同比缩放。
- 正向运行门：`.codex/scene-opacity-targeted-290-final-20260723-1722/report.json` 中 `2902406982:[365,372,647,664]` 精确执行，`newproperty50=0.2` accepted 且 surface/window identity 不变。负向 `.codex/scene-opacity-failclosed-293-final-20260723-1725/report.json` 中 candidates `[165,454,626,629,924]` 因 SceneScript 保持 Opacity/stages 0。正式 `.codex/scene-opacity-final13-20260723-1730/report.json` 为 13/13，矩阵 SHA-256 `47d01b05a60368cddc679393fb5dd11d562cd4b69cc9d4bd1f559c179fff4e23`，合计 14 stage、Opacity 4、failed 0、legacy blocked 2、route-only 30。
- 边界：只证明 exact stock `MASK=0`；MASK1、SceneScript 计算值、Workshop variants、额外纹理/命令/condition、未知 hash/combo/state 和 unsupported mixed chain 均失败关闭。手写 Metal backend 没有 Windows pixel golden，不等于 generic authored shader 或 WE parity。

<a id="e-effect-chain"></a>
### E-EFFECT-CHAIN: ordered strict effect-chain scheduler

- 实现提交：scheduler `b541867`，首条真实链 backend `809b75e`。代码：[SceneAuthoredEffectExecutionChain.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectExecutionChain.swift)、[SceneAuthoredEffectChainRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectChainRenderer.swift)、[SceneOffscreenTexturePool.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneOffscreenTexturePool.swift)、[SceneImageLayerCompositor.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneImageLayerCompositor.swift)。
- 自动门：[test_scene_authored_effect_chain_planner.py](../../../script/tests/test_scene_authored_effect_chain_planner.py)、[test_scene_offscreen_texture_pool.py](../../../script/tests/test_scene_offscreen_texture_pool.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)、[test_scene_workshop_shadow_planner.py](../../../script/tests/test_scene_workshop_shadow_planner.py)、[test_scene_workshop_shadow_rendering.py](../../../script/tests/test_scene_workshop_shadow_rendering.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)。planner/pool 门覆盖 identity、连续输入、Shadow prior-effect role 与整链预算/LRU 原子回滚；synthetic precise -> precise GPU 门覆盖实际 stage texture transfer、末段合成和失败不泄漏，独立 Shadow GPU 门覆盖该 backend 的像素公式。
- 集成门：代码路径把真实 `3724289844:20` 的 `Blur Precise -> Shadow` 放进同一 command buffer，首段只应用一次 layer masks/UV/alpha，后段使用 neutral uniforms/empty masks；定向矩阵记录两 stage 全部成功、画面非黑且发生变化。当前没有这条真实 compositor 链的逐 stage 像素 readback，因此整链像素原子性仍由 synthetic GPU 门约束，不把真实矩阵写成 Windows golden。
- 运行门：`.codex/scene-opacity-final13-20260723-1730/report.json` 为 13/13；当前共 1 条真实 multi-effect strict chain、14 个 strict stage、Opacity 4、Workshop Shadow 1，graph failures 为空。`3724289844` 为 chains 1/stages 4、succeeded `[20,28,36]`、blocked/failed 为空；`2938612768` 为 chains/stages 0，证明 unsupported mixed chains 没有被部分执行。
- 边界：只调度五个 strict material-only backends；新建的同帧 copy/swap runtime 尚未与这条 scheduler 交错执行，也不执行 compose/history/condition/function，不预处理、翻译或编译 authored shader。stock Opacity `MASK=0` direct alpha 已接入 per-surface snapshot；MASK1、SceneScript、Workshop variants、未知 hash/combo 与 unsupported 后续 stage 继续整链失败关闭。

<a id="e-effect-rt"></a>
### E-EFFECT-RT: effect-instance render-target foundation and strict consumer

- 代码：[SceneGraphRenderTargetPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneGraphRenderTargetPlan.swift)、[SceneGraphRenderTargetTable.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneGraphRenderTargetTable.swift)、[SceneOffscreenTexturePool.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneOffscreenTexturePool.swift)、[SceneImageLayerCompositor.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneImageLayerCompositor.swift)
- 自动门：[test_scene_graph_render_target_plan.py](../../../script/tests/test_scene_graph_render_target_plan.py)、[test_scene_graph_render_target_table.py](../../../script/tests/test_scene_graph_render_target_table.py)、[test_scene_authored_effect_chain_planner.py](../../../script/tests/test_scene_authored_effect_chain_planner.py)、[test_scene_offscreen_texture_pool.py](../../../script/tests/test_scene_offscreen_texture_pool.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)；覆盖 identity/extent/lifetime、history-required、预算/别名、cache/LRU/resize/format/reset、整链 allocation transaction，以及 precise/standard/Local Contrast staged GPU pixels。
- 运行门：旧 graph-target 正向/负向报告各 3/3；最新 `.codex/scene-opacity-final13-20260723-1730/report.json` 为 13/13，继续验证签名、BGRA/RGBA target consumer、零 authored FBO Shadow/Opacity、真实整链 exact count 与失败关闭。
- 边界：resident budget 只限制 cache transaction 提交后的驻留记账，候选创建时瞬时驱动分配可更高。真实样本报告不输出 `historyRequired` 原因；该分类由 plan 单元门证明。RGBA8888 已由 stock Local Contrast strict profile 消费；Workshop Shadow 只复用 synthetic BGRA input/output，不升级其他 authored target。history、compose、condition/function 和 material-command scheduler 均未执行。

<a id="e-graph-command"></a>
### E-GRAPH-COMMAND: same-frame copy/swap foundation

- 实现提交：`f1c6a10`。代码：[SceneGraphRenderTargetPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneGraphRenderTargetPlan.swift)、[SceneGraphRenderTargetTable.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneGraphRenderTargetTable.swift)、[SceneGraphCommandRuntime.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneGraphCommandRuntime.swift)。
- 自动门：[test_scene_graph_render_target_plan.py](../../../script/tests/test_scene_graph_render_target_plan.py)、[test_scene_graph_render_target_table.py](../../../script/tests/test_scene_graph_render_target_table.py)。plan 按作者顺序保留 command，要求 source/target 已声明且已写入、descriptor 完全一致，并拒绝 condition/compose、读前写、未知 command 与整数/预算错误；Metal runtime 验证 logical map 完整、物理纹理不 alias，copy 后字节一致，swap 后 logical identity 映射交换。
- 运行门：定向 `.codex/scene-copy-swap-targeted-372-20260723-1945/results-pass/report.json` 为 1/1；正式 `.codex/scene-copy-swap-final13-20260723-1955/report.json` 为 13/13，报告 SHA-256 `1399d3ea4a4c00bb5529dc6db7b0fd80e810003c945e04d6a26200944f18fe74`。`3723344874` 记录 copy definition 1、swap definition 2、graph swap node 2，但 function 1/condition 4 继续阻断，stage/chain 仍为 0。
- 边界：这只证明同帧 RT 命令的计划、Metal copy 和身份交换合同；现有 strict material scheduler 尚未消费 command list，copy/swap 不跨帧保留资源，也不意味着 Fluid/Motion Blur、compose、condition/function 或 generic authored shader 可执行。

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
