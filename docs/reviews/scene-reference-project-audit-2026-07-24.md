# Scene 参考项目只读审查

日期：2026-07-24

审查范围：`Reference Project/` 下全部四个本地参考项目。

目标：为 MyWallpaperX 自研 Wallpaper Engine Scene 播放引擎提取可缩短开发路线的格式事实、运行语义、架构线索和测试策略。

## 1. 使用边界

本文件是研究记录，不是当前能力状态入口，也不覆盖以下现役文档：

- `docs/scene/semantics/coverage-ledger.md`
- `docs/scene/semantics/capability-dependency-map.md`
- `docs/scene/scene-capability-development-plan-2026-07-22.md`

审查时 MyWallpaperX 位于：

- 分支：`codex/scene-capability-baseline`
- HEAD：`31ae5573f81b9ce63ed5d58ff02dbd46bcfe520b`
- 工作区存在未提交的 Water Flow 实现；本次没有修改、构建或评价该实现。

本次只运行读取、搜索、版本和哈希检查：

- 没有修改参考项目或 MyWallpaperX 源码。
- 没有运行会写入仓库的构建。
- 没有启动 WaifuX 的 `wallpaper-wgpu`、DXC 或其他预编译 renderer。
- 没有把第三方代码、shader、material、texture 或 binary 复制进 MyWallpaperX。

## 2. 总结

四个项目不能直接提供一个可移植、可信、接近官方的完整 Scene 引擎，但能分别解决不同问题：

1. `linux-wallpaperengine` 提供最完整的 material/pass/FBO、纹理优先级、effect 顺序、粒子和脚本宿主实现线索。
2. RePKG 提供最适合转成独立 Swift fixture 的 PKG/TEX 格式事实和测试矩阵。
3. WaifuX 提供 per-screen 外部进程、控制文件、离线 bake 和成品 MP4 管理经验，但 renderer 本身不可审查。
4. RenderDoc 1.46 的 Metal 后端仍属未完成实验代码，不适合作为 MyWallpaperX 的 Metal 调试依赖。

对 MyWallpaperX 路线最重要的结论是：

- 当前缺口已经不是 Scene IR 或基础 target identity，而是通用 material/pass 执行与 shader 合同的消费。
- 不应继续为每个 stock effect 重复搭一套纹理解析、render state 和 pass 调度基础设施。
- 也不应立即挑战任意 authored shader 全自动转换；应先建立共享 pass executor、stock shader registry、预处理合同和 shader fixture。
- PKG/TEX 当前主路径已经较完整，近期收益主要来自补 fixture、sampler flag、边界格式和损坏输入，不是重写解析器。
- 粒子已有可见 `L3` 子集，应按真实样本频率补组件，不应照搬第三方粒子系统。
- SceneScript、音频、输入、Puppet 和 3D 都不能从这些参考项目得到官方精确语义，只能取得宿主边界或早期里程碑线索。

## 3. 项目与版本

### 3.1 WaifuX-main

快照事实：

- 本地目录没有独立 `.git`，无法确认来源 commit。
- App 版本：`38.0.136`
  - `Reference Project/WaifuX-main/WaifuX.xcodeproj/project.pbxproj:1450`
  - `Reference Project/WaifuX-main/WaifuX.xcodeproj/project.pbxproj:1460`
- 两份 `wallpaper-wgpu` 均为 arm64 Mach-O，内容相同：
  - `Reference Project/WaifuX-main/wallpaper-wgpu`
  - `Reference Project/WaifuX-main/Resources/wallpaper-wgpu`
  - SHA-256：`0c170c6830227dc6b29e0dc3054e3cc858a493cc4f6756192a1da488b19dec6d`

可用范围：

- 可以研究宿主进程生命周期、参数合同、控制文件和 bake artifact 管理。
- 可以把已经生成的 MP4 当作本机视觉对照。
- 不能把 opaque renderer 的输出反推为官方精确语义。

### 3.2 linux-wallpaperengine-reference

快照事实：

- commit：`b016d7d1fdcf4e5fd2f9c9fa420a8aaa07fee02d`
- commit 日期：2026-06-09
- commit message：`refactor: remove subprocess in favor of dbus and wire up to javascript (#606)`
- 没有可用 release tag，`git describe` 为 `b016d7d`。
- 字段关系、执行顺序和失败模式可作为第三方行为线索。

### 3.3 renderdoc-1.x

快照事实：

- 本地目录没有独立 `.git`，无法确认 commit。
- 版本：1.46
  - `Reference Project/renderdoc-1.x/renderdoc/api/replay/version.h:93-98`
产品判断：
- 当前 Metal 支持默认关闭：
  - `Reference Project/renderdoc-1.x/CMakeLists.txt:203-208`
- 官方 FAQ 仍把 Metal 列为未来可能支持的 API：
  - `Reference Project/renderdoc-1.x/docs/getting_started/faq.rst:58-65`
- Metal replay 对象只有最小资源描述框架：
  - `Reference Project/renderdoc-1.x/renderdoc/driver/metal/metal_replay.cpp:27-44`
- Metal driver 中存在大量 `TODO: implement RD MTL replay`。
- 多个 `MTLLibrary` function/constant API 仍直接 `METAL_NOT_HOOKED()`：
  - `Reference Project/renderdoc-1.x/renderdoc/driver/metal/metal_library_bridge.mm:83-142`

结论：

- 不把 RenderDoc 纳入近期 Scene 路线。
- 继续使用 Xcode GPU Capture、Metal validation 和 MyWallpaperX 自有 frame capture/diagnostics。

### 3.4 repkg-master

快照事实：

- 本地目录没有独立 `.git`，无法确认 commit。
- 版本：`0.4.0`
  - `Reference Project/repkg-master/RePKG/RePKG.csproj:5-7`
- 更推荐根据格式事实和自有 fixture 独立实现 Swift 测试，避免逐行翻译。
- 当前快照的 `RePKG.Tests` 没有附带其命名所指向的完整二进制 fixture，因此不能直接运行或迁移原测试。

## 4. Material、Pass、FBO 与 Effect 顺序

### 4.1 参考实现揭示的结构

`linux-wallpaperengine` 的 material pass 保存：

- shader
- blending
- cull mode
- depth test/write
- textures
- user textures
- combos
- constants

证据：

- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Data/Parsers/MaterialParser.cpp:39-56`

Effect 保存：

- dependencies
- ordered passes
- named FBOs
- material/bind/command/source/target
- FBO name/format/scale/unique

证据：

- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Data/Parsers/EffectParser.cpp:19-31`
- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Data/Parsers/EffectParser.cpp:48-79`
- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Data/Parsers/EffectParser.cpp:99-114`

它的 texture candidate 顺序是：

1. shader default texture
2. material textures/user textures
3. effect instance override
4. explicit bind

`bind == "previous"` 被解释为前一输入：

- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/Effects/CPass.cpp:86-118`
- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/Effects/CPass.cpp:697-819`

Pass 执行会配置 destination、viewport、blend、depth、cull，然后绑定纹理并绘制：

- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/Effects/CPass.cpp:121-178`
- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/Effects/CPass.cpp:279-325`
- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/Effects/CPass.cpp:454-507`

Image effect 执行包含：

- 作者 effect 顺序
- 每个 effect 的 FBO 创建
- copy command
- 多 pass ping-pong
- effect 间 previous output 传递

证据：

- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/CImage.cpp:627-720`
- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/CImage.cpp:784-907`

### 4.2 与 MyWallpaperX 的对应

MyWallpaperX 已经有：

- effect、texture、framebuffer 和 unresolved identity：
  - `MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift:3-22`
- render target extent/format/unique/clear/UV/condition：
  - `MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift:24-46`
- material/copy/swap node：
  - `MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift:55-77`
- blocker 和 fail-closed graph：
  - `MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift:87-128`
- author-order planner：
  - `MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlanner.swift:6-34`
- copy/swap 解析：
  - `MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlanner.swift:238-285`
- target lifetime、history seed 和 command plan：
  - `MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/GraphTargets/SceneGraphRenderTargetPlan.swift:16-41`
- material、instance、user texture、explicit bind 的覆盖链：
  - `MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneAuthoredMaterialResolver.swift:84-104`

因此不应重新设计 effect IR。近期缺口是：

- 共享 `MaterialPassExecutor`
- 通用 stock shader registry
- render state 到 Metal pipeline state 的统一映射
- 通用 texture slot/provider 消费
- generic compose
- scene-background capture
- 跨帧 logical swap/history
- condition/function evaluator
- 完整 resize/switch/pause/seek/reset 生命周期

推荐结构：

```text
SceneAuthoredEffectRenderPlan
    -> SceneAuthoredMaterialResolver
    -> MaterialPassExecutor
        -> StockShaderRegistry
        -> TextureProvider/NamedTargetTable
        -> RenderStateResolver
        -> UniformFrameSnapshot
```

这不是立即删除现有 strict backend。正确迁移方式是让已验证 backend 逐步复用共享 texture/state/target executor，同时保留其严格 profile 和视觉门。

## 5. Shader 预处理与执行

### 5.1 可参考的处理阶段

`linux-wallpaperengine` 的顺序是：

1. include
2. require
3. variables/compatibility substitution
4. combo default 和 override
5. final defines

证据：

- aliases 和兼容声明：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Shaders/ShaderUnit.cpp:22-59`
- 处理顺序：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Shaders/ShaderUnit.cpp:77-94`
- include：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Shaders/ShaderUnit.cpp:136-305`
- require：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Shaders/ShaderUnit.cpp:313-364`
- combo metadata/default/override：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Shaders/ShaderUnit.cpp:442-479`
- final defines：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Shaders/ShaderUnit.cpp:648-718`

### 5.2 不能照搬的部分

- 预处理主要依赖 regex 和字符串替换，不是可靠 lexer/preprocessor。
- sampler slot 提取只匹配单个数字：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Shaders/ShaderUnit.cpp:537-543`
- float/string combo 会被拒绝：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Shaders/ShaderUnit.cpp:470-476`
- `LightingV1` 因无 lighting runtime 直接返回零：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Shaders/ShaderUnit.cpp:357-376`

### 5.3 与 MyWallpaperX 的对应

MyWallpaperX 已保存：

- stage kind
- authored/host-builtin identity
- raw source 和 SHA-256
- include reference
- annotation raw/structured value
- uniform/attribute/varying declaration
- canonical hash 和路径安全诊断

证据：

- `MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneShaderContract.swift:3-77`
- `MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneShaderContract.swift:79-180`
- `MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneShaderContractLoader.swift:29-112`
- `MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneShaderContractLoader.swift:204-250`

下一步应先建立真实 shader 合同测试：

- nested include 和 include cycle
- `#require`
- combo default、material override、instance override
- parameter annotation 和 typed default
- sampler slot 0...7 与 slot hole
- stage declaration/link mismatch
- built-in uniforms
- invalid path、symlink escape、invalid UTF-8
- unsupported feature fail-closed

在这些合同稳定前，不进入任意 authored GLSL/HLSL 到 MSL 的全自动转换。

## 6. PKG、TEX 与纹理资源

### 6.1 RePKG 可直接转成测试的事实

PKG index：

- length-prefixed magic
- entry count
- path、offset、length
- payload offset 相对 index 末尾

证据：

- `Reference Project/repkg-master/RePKG.Application/Package/PackageReader.cs:13-60`

TEX：

- 外层 magic：`TEXV0005`、`TEXI0001`
  - `Reference Project/repkg-master/RePKG.Application/Texture/TexReader.cs:38-58`
- container：`TEXB0001` 到 `TEXB0004`
  - `Reference Project/repkg-master/RePKG.Application/Texture/TexImageContainerReader.cs:24-66`
- mip V1/V2/V3/V4：
  - `Reference Project/repkg-master/RePKG.Application/Texture/TexImageReader.cs:30-149`
- 格式：
  - RGBA8888 = 0
  - DXT5 = 4
  - DXT3 = 6
  - DXT1 = 7
  - RG88 = 8
  - R8 = 9
  - `Reference Project/repkg-master/RePKG.Core/Texture/Enums/TexFormat.cs:3-11`
- flags：
  - no interpolation
  - clamp
  - GIF
  - video
  - `Reference Project/repkg-master/RePKG.Core/Texture/Enums/TexFlags.cs:5-18`

测试矩阵名称覆盖：

- V1/V2/V3/V4
- RGBA8888
- DXT1/3/5
- R8/RG88
- GIF/TEXS0001/TEXS0003
- MP4

证据：

- `Reference Project/repkg-master/RePKG.Tests/TexDecompressingTests.cs:28-47`

### 6.2 不确定部分

RePKG 明确承认 V4 的三个参数含义未确认：

- `Reference Project/repkg-master/RePKG.Application/Texture/TexImageReader.cs:75-97`

这些字段只能保真保存或用真实样本验证，不能把 RePKG 的常量判断当官方语义。

### 6.3 与 MyWallpaperX 的对应

当前 MyWallpaperX 已有：

- PKG index 和 payload-relative offset：
  - `MyWallpaperX/Core/SteamWorkshopScene/Format/ScenePkgReader.swift:59-119`
- TEXB0001-4：
  - `MyWallpaperX/Core/SteamWorkshopScene/Format/SceneTexContainer.swift:5-11`
- BC1/BC2/BC3/BC5、RG8、R8：
  - `MyWallpaperX/Core/SteamWorkshopScene/Format/SceneTexContainer.swift:44-79`
- TEXV/TEXI header、image/mip 安全上限：
  - `MyWallpaperX/Core/SteamWorkshopScene/Format/SceneTexContainer.swift:82-140`
- MP4 和 V4：
  - `MyWallpaperX/Core/SteamWorkshopScene/Format/SceneTexContainer.swift:143-166`
- animated sprite frames：
  - `MyWallpaperX/Core/SteamWorkshopScene/Format/SceneTexContainer.swift:203-281`
- LZ4 和 mip 解析：
  - `MyWallpaperX/Core/SteamWorkshopScene/Format/SceneTexContainer.swift:284`
- compressed/raw upload、内嵌 PNG/JPEG 和 MP4：
  - `MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneCompressedTextureUploader.swift`
  - `MyWallpaperX/Core/SteamWorkshopScene/Resources/SceneTextureLoader.swift:30-130`

近期动作应是补 fixture，而不是移植 RePKG：

- 每个 container version 的合法最小样本
- truncation、overflow、invalid count、invalid byte length
- RG/R8 channel interpretation
- BC block padding 和 logical/physical extent
- no interpolation/clamp sampler
- multi-image animated TEX
- rotated sprite frame
- MP4 detection、loop、pause、seek 和 teardown

## 7. 粒子

### 7.1 linux-wallpaperengine 的可用线索

它包含：

- sprite
- rope / rope trail declaration
- sprite trail
- texture/spritesheet
- control point
- box random / sphere random emitter
- color、size、alpha、lifetime、velocity、rotation、angular velocity、turbulence 和 map-sequence initializer

证据：

- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/CParticle.cpp:33-169`
- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/CParticle.cpp:351-367`
- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/CParticle.cpp:670-709`

明确缺口：

- audio emitter 仍为 TODO：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/CParticle.cpp:439`
- unknown emitter/initializer 会被记录后跳过。
- 没有证据表明 rope、child、collision、audio、dynamic control point 已达到官方语义。

### 7.2 与 MyWallpaperX 的对应

MyWallpaperX 已有独立：

- definition/parser
- deterministic simulator
- Metal pipeline
- texture source
- sprite trail plan
- built-in texture registry
- child asset graph
- fixed step 和 seed

目录：

- `MyWallpaperX/Core/SteamWorkshopScene/Particles/`

当前准确状态以：

- `docs/scene/semantics/particle-component-coverage.md`
- `docs/scene/semantics/coverage-ledger.md:95-134`

为准。

参考项目的正确用途：

- 对 box/sphere distribution、initializer 默认值和 operator 曲线做公式交叉检查。
- 用真实样本 census 决定下一组件。
- 为 unknown/unsupported 建 fail-closed fixture。

不应：

- 用 Linux 的类结构重写现有粒子模块。
- 因 parser 识别某个名称就标记为 rendered。
- 在没有 audio snapshot/control-point provider 时伪造其动态结果。

## 8. SceneScript、输入、音频和媒体

### 8.1 SceneScript 宿主线索

`linux-wallpaperengine` 使用 QuickJS，注册：

- `engine`
- `input`
- `thisScene`
- vectors
- math/color

证据：

- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Scripting/ScriptEngine.cpp:179-249`

动态 value script 每帧执行 `update()`：

- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Scripting/ScriptEngine.cpp:567-638`

媒体事件包含 properties、playback、timeline 和 thumbnail：

- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Scripting/ScriptEngine.cpp:641-689`

这些只说明宿主边界，不说明 API 完整：

- text-layer bridge 注释明确是 “provide just enough”：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Scripting/ScriptEngine.cpp:365-423`
- builtins 仅 16 行：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Scripting/resources/builtins.js:1-16`
- world position 是 stub，click 恒为 false：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Scripting/InputObject.cpp:9-35`
- Scene setter 抛异常，多项 method 仍 TODO：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Scripting/SceneObject.cpp:136-190`
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Scripting/SceneObject.cpp:303-307`
- script property builder 基本无操作：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Scripting/ScriptPropertiesObject.cpp:50-83`

### 8.2 Audio 和输入

Linux 实现向 shader 提供：

- time
- matrices
- pointer
- texel size
- audio spectra

证据：

- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/Effects/CPass.cpp:848-890`

但左右声道 uniform 指向同一组 spectrum 数据，不能复制其 stereo 语义。

Mouse 坐标转换可作为第三方测试假设：

- GLFW top-left 到 OpenGL bottom-left：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Input/Drivers/GLFWMouseInput.cpp:10-30`
- scene UV/crop：
  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Wallpapers/CScene.cpp:364-390`

DBus/MPRIS 是 Linux 平台实现，不能移植到 macOS，但事件合同可映射到 Now Playing：

- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Media/MediaSource.h:9-60`
- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Media/DBusMediaSource.cpp:87-218`

### 8.3 与 MyWallpaperX 的对应

当前状态：

- SceneScript presence：`L1`
- SceneScript source/VM/API：`L0`
- current pointer：`L3` 极窄子集
- previous pointer：`L2`，renderer 未消费
- pointer button/events：`L0`
- audio declaration：`L1`
- audio frame input：`L0`
- media thumbnail identity：`L1`

证据：

- `docs/scene/semantics/coverage-ledger.md:56-65`
- `docs/scene/semantics/scenescript-api-coverage.md`
- `docs/scene/semantics/runtime-input-property-coverage.md`

建议顺序：

1. source/target loss-preserving IR
2. per-surface input/audio/media snapshot
3. button/event queue 和 previous/current pointer
4. stereo 16/32/64-bin audio snapshot
5. typed shader/effect/particle consumers
6. 预算受限 JavaScriptCore VM
7. sample-driven SceneScript API

不应先接 VM 再补输入和 target identity，否则脚本只能运行但无法可靠地产生官方行为。

## 9. Puppet、3D 与 Lighting

### 9.1 linux-wallpaperengine 的实际边界

Scene object dispatch 只明确支持：

- Image
- Sound
- Text
- Particle

未知对象会成为 empty placeholder：

  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Wallpapers/CScene.cpp:228-249`

Camera 虽解析 perspective 值，最终仍强制 orthographic：

  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Wallpapers/CScene.cpp:37-74`
- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Camera.cpp:42-51`

Lighting 不存在，`LightingV1` 返回零：

  - `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Shaders/ShaderUnit.cpp:366-376`

所谓 Puppet/model 支持只包含静态 mesh：

- MDLV0021 / MDLV0023
- 80-byte vertex stride
- position offset 0
- UV offset 72
- indexed triangle draw

证据：

- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/CImage.cpp:425-519`
- `Reference Project/linux-wallpaperengine-reference/src/WallpaperEngine/Render/Objects/CImage.cpp:548-593`

没有找到：

- bone
- skin weight
- skeleton
- animation clip
- deformation
- blend shape
- IK
- physics/constraint
- clipping/channel

因此它只能为静态 mesh milestone 提供格式假设，不能作为 Puppet 播放参考。

### 9.2 MyWallpaperX 路线

当前：

- Puppet asset identity：`L1`
- Puppet runtime：`L0`
- 2D lighting/HDR：`L0`
- 3D model/camera/physics：`L0`

证据：

- `docs/scene/semantics/coverage-ledger.md:81-84`
- `docs/scene/semantics/advanced-object-coverage.md`

短期只建议：

- 对真实样本做 model/puppet 格式 census。
- 建立 malformed asset 和 resource identity fixture。
- 在收益明确时尝试静态 mesh，不把它标记为 Puppet runtime。

完整 Puppet/3D/Lighting 应继续延后到 B0-B4 公共 runtime、provider、graph 和 script/input 生命周期稳定之后。

## 10. WaifuX 宿主与离线 Bake

### 10.1 可参考部分

实时 renderer：

- per-screen 独立进程
- assets/background 参数
- screen/fps/crop/audio/control/property 参数
- control file 热更新
- SIGSTOP/SIGCONT per-screen pause/resume

证据：

- `Reference Project/WaifuX-main/Services/WallpaperEngineXBridge.swift:527-553`
- `Reference Project/WaifuX-main/Services/WallpaperEngineXBridge.swift:730-783`
- `Reference Project/WaifuX-main/Services/WallpaperEngineXBridge.swift:915-954`
- `Reference Project/WaifuX-main/Services/WallpaperEngineXBridge.swift:1092-1130`

离线 bake：

- 固定 size/fps/duration
- 临时 MP4
- 完成后验证
- atomic move
- sidecar extraction

证据：

- `Reference Project/WaifuX-main/Services/SceneOfflineBakeService.swift:1329-1381`
- `Reference Project/WaifuX-main/Services/SceneOfflineBakeService.swift:1618-1683`

可借鉴的是：

- realtime 和 offline 使用同一 renderer core。
- fixed-time adapter 与 artifact validation 分离。
- 失败时不覆盖已有成品。
- MP4 与动态 sidecar 使用同一 generation identity。

### 10.2 不可作为语义依据的部分

Bake eligibility 使用：

- effect filename string
- user property key
- 特定 sample ID
- deduction score

证据：

- `Reference Project/WaifuX-main/Services/SceneBakeEligibilityService.swift:497-614`

这是产品启发式，不是 Scene 能力检测：

- 烘焙会冻结交互、音频、媒体和 wall-clock。
- filename 命中不等于该 effect 的真实 runtime 依赖。
- sample ID 规则不能迁移到通用播放器。

### 10.3 对 MyWallpaperX 的价值

WaifuX 已生成的 SceneBakes MP4 可以作为：

- 固定关键样本的动态视觉参考
- 相同 timestamp 的抽帧对照
- effect 启用/禁用前后粗粒度方向门
- 人工 montage 的候选来源

不能作为：

- 官方 Windows WE pixel golden
- shader 数值真值
- 输入、音频、Timeline 或 SceneScript 动态真值

## 11. 直接采用、架构参考和拒绝项

### 11.1 可转成自有 fixture 或待验证假设

- PKG index 和 payload-relative offset。
- TEXV/TEXI、TEXB0001-4、mip 结构和安全边界。
- DXT1/3/5、RGBA、R8、RG88、GIF、MP4 fixture 分类。
- texture slot hole 和 0...7 边界。
- material -> instance -> explicit bind 的候选覆盖顺序，只作为待真实样本验证的合同。
- `previous`、named target、copy、swap、history 的身份和生命周期分类，只作为 D 级测试假设。
- top-left/view/scene coordinate conversion的正反 fixture 分类。
- WaifuX SceneBakes 的固定 timestamp 抽帧流程。

### 11.2 只能作为架构参考

- `CPass` 式通用 pass executor。
- effect-scoped FBO provider 和 ordered pass chain。
- QuickJS/VM host 的隔离边界。
- media event producer/consumer 分层。
- per-screen process/control file。
- realtime/offline 共用 renderer core。
- atomic bake artifact 与 sidecar generation。

### 11.3 过时、错误或不完整，不得固化

- 未知 command 自动映射成 `swap`。
- effect visibility 只在 setup 时求值。
- 只实现 copy，却把其他 command 当 swap。
- regex/string shader preprocessor。
- 单数字 sampler slot。
- float/string combo 拒绝。
- `LightingV1` 返回零。
- 左右声道共用 mono spectrum。
- click 恒为 false、world position stub。
- Scene setter 全部抛错。
- text SceneScript “just enough” shim。
- 强制 orthographic camera。
- static mesh 冒充 Puppet。
- parser recognized format 冒充 uploader rendered format。
- RePKG 未确认的 V4 参数。
- WaifuX sample-ID/string bake eligibility。
- RenderDoc Metal TODO 路径。

## 12. 行动建议

按可见画面收益和实现成本综合排序：

| 排名 | 行动 | 可见画面收益 | 实现成本 |
|---|---|---:|---:|
| 1 | 在现有 graph/resolver 上建立共享 `MaterialPassExecutor`，再逐步让 strict backend 复用 | 高 | 中高 |
| 2 | 闭合 `previous`、generic compose、named target、跨帧 ping-pong/history 与完整生命周期 | 高 | 中高 |
| 3 | 用真实样本 shader 建 include/require/combo/default/annotation/slot 合同门，再实现 tokenizer/preprocessor IR | 高 | 中 |
| 4 | 从 WaifuX SceneBakes 为固定关键样本抽同时间点帧，纳入人工并排视觉门 | 高，主要是验证收益 | 低 |
| 5 | 补 TEX V1-V4、R8/RG88、DXT、animated TEX、MP4、clamp/nearest fixture | 中高 | 低中 |
| 6 | 按真实样本 census 补高频 particle emitter/initializer/operator、dynamic control point 和多纹理 material | 中高 | 中 |
| 7 | 先实现双声道 audio snapshot、pointer button/event 和统一 shader built-ins，再接 effect/particle consumer | 高 | 中 |
| 8 | SceneScript 先保存 source/target IR，再以 JavaScriptCore 建预算受限、样本驱动 API | 中高 | 高 |
| 9 | Puppet 先做格式 census 和静态 mesh 实验；骨骼、IK、lighting、完整 3D 暂缓 | 中低 | 很高 |

## 13. 下一阶段决策

近期 Scene 开发应把重点从“再新增一个孤立 effect renderer”逐步转为：

1. 继续完成当前已经开始且有真实样本收益的 Water Flow 批次。
2. 为现有 strict effect backend 提取真实重复的 texture/state/target 执行职责。
3. 建立共享 material pass executor 的最小切入点。
4. 用 SceneBakes 抽帧和当前预览做同样本视觉比较。
5. 每次只升级一类共享合同，并运行对应固定样本和相关回归门。

以下事项不进入近期实现：

- 引入 WaifuX `wallpaper-wgpu`
- 复制 GPL renderer 代码
- 接入 RenderDoc Metal
- 一次性实现任意 custom shader transpiler
- 在输入/provider/runtime 未成立前先做完整 SceneScript
- 把静态 mesh 标记为 Puppet
- 为低频高级对象提前建立大规模 3D 框架

## 14. 文档有效期

这些结论绑定于本文件记录的本地快照：

- `linux-wallpaperengine` 的 commit 可重复定位。
- WaifuX、RenderDoc 和 RePKG 没有本地 `.git`，未来替换目录后必须重新确认版本和实现。
- MyWallpaperX 能力状态会持续变化；实现前应重新查看 `coverage-ledger.md` 和专项能力表，不能用本审查覆盖更新后的代码事实。
- 若未来取得 Windows Wallpaper Engine 同配置录屏或合法官方 assets，应以其更新当前第三方行为假设。
