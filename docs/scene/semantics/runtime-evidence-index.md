# Scene 运行证据索引

> 状态：现役证据入口
>
> 最近核对：2026-07-23
>
> 实现基线：`36bfef0`

本页给覆盖表中的 `L3` 子集提供可追溯证据包。每个证据包至少包含代码、自动测试和真实运行或 GPU 证据；缺少任一项的能力只能标 `L0-L2`，或在专项表中明确写 `gate incomplete`。`.codex` 报告是本机隔离运行产物，不提交 Git；报告路径、App 身份和摘要写入现役文档，避免将其误当源码 fixture。

## 1. 当前统一门

| 项目 | 当前证据 |
|---|---|
| 视觉矩阵 | `.codex/scene-particle-builtins-final13-r2-20260723/report.json`，13/13；只证明固定门内非黑、计数、GPU completion 和 teardown，不证明 WE parity |
| 最新合同门 | Scene tests 154 total / 153 pass / 1 skip；其中实现合同 145 项，新增语义文档治理门 9 项 |
| 签名 App | `2.0.8 (268)`，Team `H9QWU9XN8R`，CDHash `7b27f7f5d678a333f5db77d19936482a098404e8` |
| executable SHA-256 | `150348cb9dc9acebf5f8633ad2a64cc665fe4061832c75cbcb76701a71386687` |
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
- 运行门：`.codex/scene-property-text-day-gate-pass-20260722/report.json`、`.codex/scene-user-texture-final13-r2-20260723/report.json`；当前大部分 target 仍通过 180 ms 重建生效。

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

- 代码：[SceneFrameTextureRegistry.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneFrameTextureRegistry.swift)、[SceneDependencyRenderPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneDependencyRenderPlan.swift)、[SceneImageBlendPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneImageBlendPipeline.swift)
- 自动门：[test_scene_frame_texture_registry.py](../../../script/tests/test_scene_frame_texture_registry.py)、[test_scene_dependency_render_plan.py](../../../script/tests/test_scene_dependency_render_plan.py)、[test_scene_image_blend_plan.py](../../../script/tests/test_scene_image_blend_plan.py)、[test_scene_user_property_textures.py](../../../script/tests/test_scene_user_property_textures.py)
- 运行门：`.codex/scene-texture-fallback-293-v3-20260723/report.json`、`.codex/scene-texture-fallback-290-20260723/report.json`、`.codex/scene-user-texture-final13-r2-20260723/report.json`。

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

<a id="e-effect-inline"></a>
### E-EFFECT-INLINE: 受限手写 Effect profiles

- 代码：[SceneEffectRuntimePlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneEffectRuntimePlan.swift)、[SceneInlineEffectRuntime.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneInlineEffectRuntime.swift)、[SceneMetalPipeline.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneMetalPipeline.swift)
- 自动门：[test_scene_effect_mask_gating.py](../../../script/tests/test_scene_effect_mask_gating.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)
- 运行门：正式矩阵中的明确 runtime counters/summary。当前只是 Foliage/Iris/Water/Cursor/Chromatic/Perspective-Opacity 等表内子集，不执行 authored shader。

<a id="e-effect-blur"></a>
### E-EFFECT-BLUR: strict Blur graph profiles

- 代码：[SceneAuthoredEffectExecutionPlan.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredEffectExecutionPlan.swift)、[SceneAuthoredStandardBlurPlanner.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneAuthoredStandardBlurPlanner.swift)、[SceneStandardBlurRenderer.swift](../../../MyWallpaperX/Core/SteamWorkshopScene/SceneStandardBlurRenderer.swift)
- 自动门：[test_scene_authored_effect_execution.py](../../../script/tests/test_scene_authored_effect_execution.py)、[test_scene_framebuffer_capture.py](../../../script/tests/test_scene_framebuffer_capture.py)、[test_scene_wallpaper_benchmark.py](../../../script/tests/test_scene_wallpaper_benchmark.py)
- 运行门：`.codex/scene-authored-precise-final13-20260723/report.json`、`.codex/scene-standard-blur-alpha-final13-20260723/report.json` 和相应 negative reports；6 个 graph layer GPU succeeded，0 failed，3 个 legacy fallback 被阻断。

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
