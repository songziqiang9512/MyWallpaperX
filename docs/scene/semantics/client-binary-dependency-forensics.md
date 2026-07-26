# 官方客户端二进制与第三方依赖取证

审查日期：2026-07-26
取证快照：Wallpaper Engine 2.8.42 的 `bin/`、`ui/dist/videos/`、`assets/shaders/{base,editor,HLSL}`、`distribution/`
审查方式：静态检查

## 1. 结论先行

1. **音频频谱的 FFT 实现是 FFTS**（Anthony M. Blake，BSD）。项目 Audio 16/32/64 bins 系统（当前 `L0`）实现时的频域行为参照对象明确了。
2. **blend mode 数学的来源是 Romain Dura 的 Photoshop Blend Functions**（公开 MIT 库，即广为流传的 PhotoshopMath 系列 shader）。`common_blending.h` 的 `ApplyBlending` 32 模式表与该公开库同源；项目 Tint backend 的对照基准从「只读随包 GLSL」升级为「随包 GLSL + 其声明的上游公开库」。
3. **Advanced Fluid Simulation 的算法蓝本是 WebGL-Fluid-Simulation**（Pavel Dobryakov 的公开 MIT 项目）。该 effect 当前 `L2`（约 20 nodes/swap graph-only）；官方声明许可意味着其 pass 结构可与该公开实现对照解读（advection/divergence/pressure/gradient subtract 的标准分解）。
4. **粒子噪声栈**：CPU 侧 Perlin Simplex Noise（Sebastien Rombauts）+ FastNoise 2（Jordan Peck），GPU 侧 GLSL noise（Ashima Arts / Stefan Gustavson 的 webgl-noise）+ GLSL hash（David Hoskins）。turbulence/simplex/fbm 的官方噪声族全部有公开参照。
5. **字体栈是 FreeType2 + HarfBuzz + msdfgen**，与 [changelog 取证](client-changelog-forensics.md) §4 的 MSDF 结论互证（REV 4344 "Added msdfgen license" 对应的 license 就在本清单）。
6. **BC 纹理压缩使用 AMD Compressonator SDK**（2020 版）。项目 BC1/2/3/5 解码若需数值对照，Compressonator 的公开解码器是官方声明的实现来源。
7. **SceneScript VM 是 V8** 的第三重独立证据（license 清单 + `bin/scenescript32/64.dll` 独立模块 + changelog 10 条）。
8. **编辑器的深度图自动生成是 MiDaS/DPT 深度估计模型**（PyTorch 栈）。Depth Parallax 官方描述里的 "generate automatically" 是 AI 模型推理，属编辑器 authoring 能力，**播放器不需要实现**。
9. `ui/dist/videos/previews` 随包 165 个官方元素预览视频（webm，12 MB），是粒子组件与 effect 的**官方动态行为参考**，权威性高于 WaifuX SceneBake；文件名为 16 位十六进制哈希，静态检索未找到哈希到元素名的映射表。

## 2. 第三方依赖清单

### 2.1 主清单（`licenses_main.html`，34 项）

按 Scene 系统归组。HTML 中库名列表与文本块存在嵌套错位，两个泛名条目按关联信息归属到具体库。

| 库 | 身份确认 | 对应 Scene 系统 | 项目当前等级 |
|---|---|---|---|
| **V8** | — | SceneScript VM | `L0`，见 [changelog 取证](client-changelog-forensics.md) §3 |
| **FFTS** | Anthony M. Blake 2012-2013 | 音频频谱 FFT | Audio frame input `L0` |
| **Photoshop Blend Functions** | Romain Dura（romz）2012 | `common_blending.h` blend mode 数学 | Tint `L3`；[blend 名单](editor-string-table-forensics.md#4-blend-mode-官方名单35) |
| **WebGL-Fluid-Simulation** | Pavel Dobryakov（MIT） | Advanced Fluid Simulation effect | `L2` graph-only |
| **Perlin Simplex Noise** | Sebastien Rombauts（MIT） | CPU 粒子噪声 | turbulent velocity `L3` 非等价实现 |
| **FastNoise 2** | Jordan Peck 2020（MIT） | CPU 噪声（simplex/fbm 族） | 同上 |
| **GLSL noise** | Ashima Arts / Stefan Gustavson | shader 内 simplex/classic noise | shader 执行 `L0-L1` |
| **GLSL hash** | David Hoskins 2014 | shader hash 函数 | 同上 |
| **glsl-rotate** | Damien Seguin 2018 | shader 旋转工具 | 同上 |
| **Voronoi JCash** | MIT | Voronoi 纹理工具（changelog REV 4249-4251 的 voronoi utilities） | 编辑器 authoring，播放器无需实现 |
| **FreeType2** | — | 字体解析 | Text/Font `L3`（项目用 CoreText） |
| **HarfBuzz** | — | 文本 shaping | 同上 |
| **msdfgen** | MIT | MSDF 字形生成 | outline/shadow `L1`，见 changelog §4 |
| **SDF CPU Computation** | TKMI-kyon 2022 | puppet 深度 SDF 自动生成（REV 3974） | 编辑器 authoring |
| **AMD Compressonator SDK** | AMD 2020 | BC/DXT 纹理压缩编解码 | PKG/TEX `L3` |
| **LZ4** | Yann Collet 2011-2017 | TEX LZ4 解压 | 已实现 |
| **LodePNG** | Lode Vandevenne，version 20160118 | PNG 编解码 | 已实现（平台解码器） |
| **FreeImage** | — | 图像解码 | 同上 |
| **Wuffs** | — | 图像安全解码（Google） | 同上 |
| **CGif** | — | GIF 编解码 | gifscene 路径 |
| **nQuant.cs** | — | 调色板量化 | 编辑器侧 |
| **Assimp** | 3-clause BSD | 3D 模型导入 | 3D `L0`；对应 `bin/assimp-vc143-mt*.dll` |
| **GLM** | OpenGL Mathematics | 数学库（changelog 多条优化记录） | — |
| **JsonCpp** | 1.9.6（REV 4130） | JSON 解析 | — |
| **RapidJSON** | — | JSON 解析（与 JsonCpp 并存） | — |
| **Poly2Tri** | 2009-2018 | 三角剖分（puppet mesh/clipping） | Puppet `L2-L3` |
| **triangleraster** | — | 三角形光栅化 | — |
| **SFML 2** | — | 多媒体基础库 | — |
| **OpenCV** | — | 图像处理（编辑器） | 编辑器 authoring |
| **CEF** | Marshall A. Greenblatt / Google | UI 与 Web 壁纸 | Web 模块另册 |
| **Monaco Editor** | — | 脚本编辑器 | 编辑器 authoring |
| **Bodymovin** | — | UI Lottie 动画 | 与 Scene 无关 |

### 2.2 编辑器扩展清单（`licenses_editor_extensions.html`，14 项）

PyTorch、Torch Vision、Torch Audio、timm、**MiDaS**、**DPT**、OpenCV（含 External）、NumPy（含 External）、PIP、TCL、Python、Research。

这是编辑器「AI 深度图生成」功能的完整 Python 栈。**结论：Depth Parallax 的 depth map 在作者侧由 MiDaS/DPT 推理生成，产物是普通纹理**；播放器只消费纹理，不需要任何 AI 组件。这缩小了 Depth Parallax `L1 -> L3` 的实现范围：只需 depth 纹理采样位移，不需生成链。

## 3. `bin/` 磁盘模块清单

[Windows 取证记录](../../reviews/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md) §4 记录的是 Parallels 运行时**已加载**的 4 个模块（`d3d11`/`dxgi`/`d3dcompiler_47_x32`/`scenescript32`）。以下是磁盘上的完整装载面（62 个文件，511 MB；`.dll` 28 个）：

| 组 | 文件 | 推断（等级 C） |
|---|---|---|
| Scene 脚本 | `scenescript32.dll` / `scenescript64.dll` | V8 VM 独立模块边界 |
| Shader 编译 | `d3dcompiler_47.dll` / `d3dcompiler_47_x32.dll` | FXC，SM5 路径 |
| Shader 编译（新） | `dxcompiler.dll` / `dxil.dll` | **DXC/DXIL 存在于磁盘**，说明官方具备 SM6 编译链；但随包 blob 只有 `blobsSM40`（DXBC），运行时是否走 DXC 未证实 |
| 3D 模型 | `assimp-vc143-mt32.dll` / `-mt64.dll` | 与 licenses 的 Assimp 对应；VC143 工具链 |
| 图像 | `FreeImage32.dll` / `FreeImage64.dll` | — |
| 媒体 | `mediaextensions32/64.dll`、`steammdmp32/64.dll` | 媒体集成与 Steam 媒体桥 |
| 资源 | `resourceutil32/64.dll` | 资源编译/工具 |
| RGB 设备 | `CUESDK.x64_2017.dll` / `CUESDK_2017.dll` | Corsair iCUE；`plugins/led/` 另有 LED 插件（本机加载失败，错误码 126/183，见根 `log.txt`） |
| UI/Web | `libcef.dll`、`libEGL.dll`、`libGLESv2.dll`、`vk_swiftshader.dll`、`vulkan-1.dll`、`chrome_elf.dll`、`icudtl.dat`、`*.pak` | CEF/ANGLE/SwiftShader，全部属 UI 进程，与 `wallpaper32.exe` Scene 渲染无关（§4.2 已界定） |
| 桌面注入 | `applicationwallpaperinject32/64.exe`、`cloneextensions32/64.dll`、`edgewallpaper64.exe` | Windows 桌面集成，无 macOS 对应义务 |
| 诊断 | `diagnostics32/64.exe`、`apputil32.exe` | — |
| Steam | `steam_api.dll` / `steam_api64.dll` | — |

`distribution/` 与 `bin/`+`plugins/` 内容为同一套发行 payload（文件名集合仅差 3 个运行时状态文件：`playliststatetime.bin`、`workshopcache.json`、`workshopcache_editor.json`），无独立证据价值，后续不再检查。

## 4. `assets/shaders` 子目录补漏

[Shader Prelude 文档](shader-prelude-and-backend-abstraction.md) 的 census 口径覆盖 `assets/shaders` 顶层并明确排除 `HLSL/`；三个子目录在此登记完整面：

| 子目录 | 文件 | 性质 |
|---|---|---|
| `base/` | `model_fragment_v1.h`、`model_vertex_v1.h` | 3D model shader 基座；`model_vertex_v1.h` 被顶层 include 5 次（Prelude §3 已计数），fragment 侧此前未登记 |
| `editor/` | `editorparticlelayerdependency.{frag,vert}`、`meshviewportshading.{frag,vert}` | 编辑器专用视口 shader，播放器无义务 |
| `HLSL/` | `dx11fallback.{frag,vert}`、`dx11playlistgaussian.{frag,vert}`、`dx11playlisttransition.{frag,geom,vert}` | D3D11 专用回退与播放列表过渡（Prelude §10 已收录其 15 个 `g_` 符号） |

`declarations.json`（4.7 KB）已由 [Windows 取证记录](../../reviews/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md) §17 收录其 shader/texture format 声明结构。

## 5. 官方元素预览视频

`ui/dist/videos/previews/`：165 个 `.webm`，共 12 MB，文件名为 16 位十六进制哈希。changelog REV 4182-4187 记录其来源（"Added video previews for all element add dialogs" / "Added element preview videos"）。

- 定位：粒子 emitter/initializer/operator/renderer、effect 等「添加元素」对话框的官方动态演示。
- 价值：官方动态行为参考，可用于 V3 动态对照阶段人工比对组件行为方向（如 vortex 旋向、boids 聚群形态）；权威性高于第三方 SceneBake。
- 限制：文件名哈希到元素名的映射表未在 `scripts.js`、场景 JSON 或 CSS 中静态检索到（推断由编辑器运行时拼接，等级 C）；使用时需人工按内容识别。48 个 `assets/scenes/particleelementpreviews/<组件名>/` 官方预览工程已由 [官方默认工程 corpus](official-default-projects-fixture-inventory.md) 与 preset corpus census 收录，两者互补：工程给可解析的输入，视频给官方渲染的输出。

## 6. 不应从本文推出的结论

1. license 清单证明官方**使用**了某库，不证明某系统**只**由该库实现，也不证明未做修改；数值对照仍需运行门。
2. `dxcompiler.dll` 在磁盘存在不证明 Scene shader 走 SM6；已观测 blob 均为 `SHDV0069`+DXBC（SM4.0）。
3. UI 栈（CEF/ANGLE/Vulkan/SwiftShader）与 Scene 渲染进程无关，不得据此推断 Scene 后端。
4. 编辑器扩展的 PyTorch/MiDaS 栈属 authoring 工具；播放器兼容性不含任何 AI 推理义务。
5. 本文不改变 [覆盖台账](coverage-ledger.md) 任何等级；它只把若干 `L0`/`L1` 系统的「实现参照来源」从未知变为已知。
