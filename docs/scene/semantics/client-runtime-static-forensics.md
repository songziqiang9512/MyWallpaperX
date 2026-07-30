# 官方客户端 Scene 运行机制静态取证（Ghidra）

> 初次审查：2026-07-30
>
> 32/64 位交叉复核：2026-07-31
>
> 取证快照：Wallpaper Engine 2.8.42 / Steam build `23967692`
>
> 工具：Ghidra 12.1.2 headless、OpenJDK 21.0.12
>
> 性质：clean-room 静态结构证据，不是运行时或像素等价证据

## 1. 目的与边界

本文只记录能迁移为 MyWallpaperX 公共合同的高层结构：

- 外部图像、离线资源编译、TEX 容器与运行时采样之间的职责边界；
- Scene parser、material/texture resolver、shader frontend、RenderGraph 和最终输出之间的关系；
- frame、device/surface reset、视频、声音、系统媒体与多显示器的生命周期边界；
- SceneScript module、engine、owner、event/timer/audio/property bridge 与 teardown 的分层；
- 32/64 位发行路径中上述结构是否对应。

本文没有运行 Windows 二进制，没有绕过许可、DRM、签名或账号机制，也没有读取用户配置、缓存或项目。项目不保存客户端地址、机器指令、反编译伪代码、函数体、私有算法表达、官方 shader、纹理、模型、JSON 或脚本 payload。

静态结果按以下口径使用：

- **高**：命名导出/依赖的正向可达路径，或 32/64 位独立二进制与结构化资产共同互证；
- **中**：字符串 xref、RTTI、有限调用邻域和多个相邻状态共同支持同一模块关系；
- **定位**：孤立字符串、import 存在或未解析间接调用，只能选择后续实验位置。

“未找到”不能证明能力不存在。D3D11、Media Foundation、WinRT 和宿主 adapter 大量使用 COM/vtable/函数指针，普通直接调用图无法覆盖全部路径。

## 2. 输入身份

本轮重新计算的关键输入身份如下：

| 文件 | 字节 | SHA-256 | 角色 |
|---|---:|---|---|
| `wallpaper32.exe` | 4,303,856 | `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07` | 实际历史运行记录涉及的 32 位 Scene 主程序 |
| `wallpaper64.exe` | 5,360,112 | `40e2ce021e9352324fadb3b8f72b8ba2a7ee95b71cc571d5b9f84be75cd993b0` | 64 位 Scene 主程序 |
| `bin/scenescript32.dll` | 22,725,104 | `6995b2f4e83580cfbc8fcc2a9d39c7bee8129b43ea43d8480c63240020398a22` | 32 位 SceneScript module |
| `bin/scenescript64.dll` | 28,730,352 | `58039ef912fcd51cd833540476e3798268158a06f63003fe94bff1b1cbeaad08` | 64 位 SceneScript module |
| `bin/resourceutil64.dll` | 1,322,480 | `153cb1e273984b5c7a77b10d62089d50fcde3e187787d839918b59a81c8bfc24` | 通用图像资源工具 |
| `bin/resourcecompiler64.exe` | 6,752,240 | `09957ab6cfdf206a0825ffc8c3306e2e11473b1d6136523fa689a707766ee00d` | 离线资源编译 |
| `bin/mediaextensions64.dll` | 3,484,144 | `898ffaa06ac56f46b7ac7e182fc0b6c750fc585f8554606713e0468977e0dbc3` | 音频设备/source 扩展 |
| `bin/winrtutil64.exe` | 3,965,424 | `42c4801b194bf06408e176d6869407c193e47ad995714ccdcfd5b4e7a0daf1e0` | 系统媒体辅助进程 |
| `bin/wallpaperservice64.exe` | 176,624 | `20f04b776a8e2799688aa1bca78a462e0795c95e197c9eee95a478275ec683c7` | Windows service/session 编排 |
| `bin/cloneextensions64.dll` | 657,392 | `69871bed52dc5af429fdedd04dad5d75d3b5c75944b41e03c0c59c18d7afc3c8` | clone/composition surface 扩展 |

根目录与 `distribution/` 的 `wallpaper64.exe` 哈希一致。`version.json` 与 `distribution/version.json` 都确认版本为 `2.8.42`。

## 3. 可复核方法

两轮分析使用同一条有界证据链：

```text
结构化资产或命名导出
  -> PE import/export
  -> 字符串/RTTI anchor 与 xref
  -> thunk-aware 有限调用邻域
  -> 选择性反编译只恢复模块职责
  -> 32/64 位结构交叉
  -> sidecar/TEX、官方公开文档和项目现有合同互证
  -> 只记录中性结构、风险和自有 fixture 要求
```

2026-07-31 的交叉复核为每个输入建立独立 `/private/tmp` Ghidra project，外部 library search 指向空目录；SceneScript 分析关闭全局 decompiler-switch、PDB、嵌入媒体和 Function ID 等与宿主合同无关的宽泛分析，避免把 V8 内部模板噪声混入证据。一次性 project、脚本和含地址的日志在文档核验后删除。

Ghidra 报告的 PDB 缺失、少量不可读地址、无效构造和控制流恢复失败保留为限制；这些警告没有被当成客户端缺陷。

## 4. 资源导入与纹理链

### 4.1 通用图片解码不是 Scene TEX 最终采样器

`resourceutil64.dll` 的命名导出包括 memory/path image loader、dominant color、GIF 生命周期和 JPEG 输出。三个命名 image loader 都能正向到达 FreeImage 32-bit 转换与垂直方向规范化；两个 memory loader 的直接/thunk-aware 路径没有未解析间接调用，证据为高。

可确认的职责是：

```text
外部图片输入
  -> 通用 decode / 32-bit normalize / orientation normalize
  -> 上层资源或离线编译 consumer
```

这不能推出“所有 Scene TEX 在 GPU 采样前都要再翻转”，也不能确定最终 RGBA/BGRA、sRGB/linear 或 straight/premultiplied alpha。外部图片、离线 TEX、sprite frame、shader UV 与最终 API 坐标是五个不同层次。

### 4.2 离线 compiler 决定存储形态，consumer 决定用途

`resourcecompiler64.exe` 同时引用 FreeImage 的 32-bit/flip/rescale/scanline、Assimp material 输入、Media Foundation，以及 sidecar 格式字段与 TEXB/TEXS 写入 marker。结合 272 个无歧义 sidecar/TEX 配对，可确认：

```text
sidecar / authoring input
  -> format 与编译策略
  -> TEXB 像素/mip payload
  -> TEXS frame metadata
```

关键反例是：

- `dxt5` 与 `dxt5n` 都映射 numeric format 4；
- `rgba8888`、`rgba8888n` 和 `rgb888` 都可能映射 numeric format 0；
- physical extent、mapped content 与最终上传 extent 在真实资产中不总相等。

因此 numeric format 只能标识存储，不能单独决定 color/data/normal purpose、alpha、swizzle 或 shader 解包。cache/upload/sampler/variant identity 必须包含 consumer purpose 和 physical/mapped metadata。

## 5. Scene 主程序的执行结构

### 5.1 Parser、resolver、frontend 与 graph admission

64 位深挖和 32/64 位交叉复核共同支持以下顺序：

1. Scene/effect parser 读取 condition、pass、target、compose、clear、unique、backbuffer format 和 material state；
2. condition 在受影响 pass/material/FBO/bind 纳入执行图前求值；
3. instance pass override 按定义 pass ordinal/index 归属，command 不能被当成普通 material pass；
4. indexed material resolver 保留槽位身份，并联合 authored texture、user/system/provider、显式尺寸和 fallback；
5. material constant/user shader values 与 shader default/reflection metadata 进入同一 resolved state；
6. shader frontend 识别 `uniform` inline metadata、`[COMBO]`、`[PASS]` 与多位数字的 `g_TextureN`；
7. normalized combo、typed render state 和 blend-to-variant 共同参与最终 pipeline identity；
8. graph 执行后再进入 scene/global final-output chain。

内部 resolver/built-in registry 为 `g_Texture0...9` 保留 resolution、mapped size、texel/mipmap、rotation 与 translation 家族。官方 authored shader 公开合同仍是 0...7；内部 8/9 的存在不是扩写作者 schema 的许可，只要求 IR 不应无声压缩或误绑这些身份。

### 5.2 32/64 位主程序交叉结果

2026-07-31 使用同一 Ghidra 探针对两份主程序独立恢复。下表只比较结构，不比较函数地址或数量：

| 主题 | 两个架构共同证据 | 差异与结论边界 |
|---|---|---|
| RenderGraph admission | `conditions/compose/target/unique/clear/rgb_backbuffer/rgba_backbuffer` 的核心共现集合一致；condition 与 graph 字段汇入同一 parser 邻域 | `clear` xref function 为 64 位 4、32 位 3；不能写逐函数等价 |
| Material values/state | `constantshadervalues/usershadervalues/usertextures` 共址；`alphawriting/depthtest/depthwrite/cullmode` 共址 | 只证明读取与汇合，不给出 blend factor、write mask 或 override 完整优先级 |
| TEX/built-ins | `TEXI/TEXB/TEXS` 与 resolution/mipmap/rotation/translation 家族对应 | 32 位未恢复到 64 位可见的独立 `TEXV`、`clampuvs` literal；不能用 literal 缺失否定代码路径 |
| Particle graph | `controlpoints/children/maxcount/starttime` 的全部 pair 共现集合一致 | factory 名称、数值公式、random seed 与逐帧阶段顺序仍未知 |
| Final output | `hdr/bloom/downsample/upsample/srgb/display` 的核心共现关系对应 | `hdr+downsample` xref 数不同；不证明 tone-map 数学或 HDR 像素结果 |
| GPU/text/media | 两边 `D3D11CreateDevice` 6 refs、`DWriteCreateFactory` 2 refs；URL/byte-stream source、media session、DXGI device manager 同时存在 | topology/renderer activation ref 数有 ABI/恢复差异；COM 间接调用未完整计入 |

这足以把 32 位路径从“只有 import 基本同构”提升为“关键 parser/resolver/particle/final-output 结构对应”。它仍不证明启动器选择条件、完整内部等价、像素、时序或性能一致。

### 5.3 Frame、readiness、reset 与 final output

主 render thread 使用高分辨率 counter 计算连续 frame delta，并把 local date/time 与 frame progression 分开；资源/视频 readiness 会影响 active/wait 路径。它不是每次循环固定加一帧的执行器。

device loss 或 scene rebuild 会按资源族释放并重建 render target、material/shader cache、texture/provider 与 scene state。这个形状要求项目使用 `reset(reason, generation)` 式跨资源事务，不能只依赖对象各自 deinit。

最终输出按 LDR、HDR、video-HDR 与 display-HDR 选择不同 combine/downsample/bloom/blur/upsample 参与者。静态证据确认 typed output-mode graph 的必要性，但没有给出 transfer function、色域、tone-map、bloom 数学或 Metal 等价参数。

## 6. SceneScript 的 module/engine/owner 机制

### 6.1 宿主层次

32/64 位 DLL 共同公开：

- `Init`
- `CreateSceneScriptEngine`
- `GetSceneScriptVersion`
- `Shutdown`

64 位主程序深挖确认：主程序动态装载 DLL，先要求 `GetSceneScriptVersion()` 与 `2.8.42.SceneScript` 精确匹配，再取得 init/engine factory；版本不符失败关闭。module 使用进程级 init/shutdown，engine 实例另有 isolate、script/timer/property/audio 表和宿主桥。

engine 还具有：

- 固定事件槽及每槽存在/禁用状态；
- frame-delta timer；
- frame tick 音频数组刷新；
- property return 的集中 typed conversion；
- 每回调耗时统计；
- 实例级 watchdog 与永久中断状态；
- host-owned destroy 和有序 teardown。

这些结构要求项目分开 module global、engine instance、owner script record 和 host event bridge。不能把 SceneScript 简化为 renderer draw 中无预算的一次 `eval`。

### 6.2 32/64 位 SceneScript 交叉结果

两份 DLL 的关键宿主字符串与共址关系对应：

| 项 | 32 位 | 64 位 | 可支持结论 |
|---|---:|---:|---|
| `thisScene` / `thisLayer` 字符串 | 1 / 1 | 1 / 1 | owner globals 在两条 ABI 路径都存在 |
| `engine` / `localStorage` 字符串 | 24 / 7 | 24 / 7 | engine 与 scoped storage surface 对应 |
| `registerAudioBuffers` | 2 | 2 | audio registration 不是 64 位特例 |
| `setTimeout` / `setInterval` | 2 / 2 | 2 / 2 | timer surface 对应 |
| shared host exports | 4 | 4 | module lifecycle/factory/version API 对应 |
| waitable timer / wait refs | 同时存在 | 同时存在 | timer/supervision 有独立 OS wait 参与者 |

更强的结构互证是：两个架构中同一类注册邻域都同时引用 `thisLayer`、`engine`、`localStorage`、`registerAudioBuffers`、`setTimeout` 与 `setInterval`，其有限调用邻域都可达独立 worker 与 SRW-lock 类同步参与者。它支持“owner handle + timer/audio/storage 属于 per-engine host bridge”，不是彼此无关的全局 helper。

64 位额外出现一个运行库异常导出和一个 TLS callback；函数数、xref 数与 CRT/API 细节也不同。这些差异不改变四个公开宿主导出的对应关系，但禁止宣称逐函数、ABI、异常或 GC 行为完全相同。

### 6.3 仍需动态或自有 fixture 的部分

静态路径不能无歧义确认：

- 全部 19 个事件的实际派发顺序、重入与跨帧可见性；
- `destroy -> record removal -> engine teardown` 的完整相对顺序；
- timer 在 pause/seek/长帧与 wall-clock 跳变下的运行结果；
- watchdog 阈值、预算与错误传播应如何跨平台取值；
- 全部 handle/API 的副作用、identity 与销毁语义。

MyWallpaperX 应先用自有 fake VM 锁定 owner lifecycle、事件队列、typed writeback、timer policy、budget 和 exactly-once destroy，再选择通用 VM。

## 7. 视频、声音、系统媒体与 surface

### 7.1 视频和 Scene Sound 是不同合同

`wallpaper32/64.exe` 都具有 Media Foundation URL/byte-stream source、media session/topology、audio/video renderer activation 与 DXGI device manager 参与者。这支持视频 provider 需要 scene clock、readiness、seek/loop/reset、generation 和 GPU frame 互操作边界，但不提供 A/V 同步、颜色矩阵、range、rotation 或首帧规则。

`mediaextensions64.dll` 经主程序 factory 动态取得，公开/静态边界覆盖 audio device/context、source play/pause/stop/rewind、buffer queue、capture、device pause/resume 和线程化 teardown。它更接近 Sound/device lifecycle，不是通用视频解码器。项目无需复制 OpenAL API，但 owner-scoped Sound 必须有 prepare/play/pause/resume/stop/dispose、loop/volume、预算和 device reset。

### 7.2 系统媒体是带 generation 的异步 producer

`winrtutil64.exe` 由主程序以辅助进程方式启动。其边界聚合系统媒体会话、storage stream、thumbnail/Shell image、FreeImage normalize/resize 与异步注册/注销。

跨平台可迁移合同不是复制 WinRT 进程拓扑，而是：

```text
media generation N
  -> metadata
  -> timeline/status
  -> thumbnail/derived color
  -> only publish while generation is still N
```

旧异步 thumbnail 或 metadata 不得覆盖新曲目。静态路径不能给出 Windows 事件先后或每张封面的精确像素变换。

### 7.3 Service 与 clone/composition 不属于 Scene 算法

`wallpaperservice64.exe` 负责 Windows Service、电源/会话通知、用户 token/environment 和登录用户进程编排。没有证据把它解释为 Scene clock 或 pause 算法；macOS 只需把 user pause、lock、sleep、display sleep 等输入归一为明确 interruption reasons。

`cloneextensions64.dll` 由主程序动态解析 clone/composition 入口，并维护独立 surface/window/swapchain create/update/destroy 边界。它支持稳定 surface identity、per-display policy 与 display hot-plug transaction，不能证明所有场景都走 clone，也不要求 macOS 复制 DirectComposition。

## 8. 对项目的直接约束

本取证只收窄公共设计，不更新任何 `L0-L4` 等级：

1. **纹理**：format、purpose、physical/mapped、UV、sampler、alpha/color 与 generation 必须共同进入 identity；
2. **RenderGraph**：condition 先于 admission；pass、command、target、copy/swap/history 保持不同身份；
3. **Material/shader**：indexed slot 不压缩；default/user/provider/state/variant 有来源可追踪的合并结果；
4. **Frame/output**：frame delta、wall date、readiness、surface 与 output mode 分离；
5. **Reset**：scene switch/device/surface/provider completion 受同一 generation 事务治理；
6. **SceneScript**：module、engine、owner 和 event bridge 分层，timer/audio/storage 与 owner 同寿命；
7. **Video/Sound/Media**：三者各有独立状态机，异步结果不能跨 generation 注入；
8. **跨架构结论**：结构对应只用于确认合同不是单一 ABI 偶然，不能替代 Windows dynamic trace 或 pixel golden。

当前实现、测试和真实样本证据分别以覆盖台账与运行证据索引为准；本文不证明 MyWallpaperX 已实现上述全部合同。

## 9. 后续证据队列

32/64 位主程序与 SceneScript 的第一轮结构差分已经完成。下一批静态分析仍可回答：

1. TEX flags/尺寸/mip 如何参与 sampler 与 fallback 的更多局部路径；
2. copy/swap/history/clear/unique/compose 的局部资源生命周期；
3. particle factory、child/control-point 与释放入口的阶段边界；
4. SceneScript 全部 host binding 的可恢复子集与 owner 类型；
5. video/Sound 主程序实际使用的状态参与者；
6. material authored/default/user/system/provider 的更多来源集合。

以下问题必须由项目自有 fixture、隔离 Windows trace 或像素/声音 golden 回答，不能继续靠反汇编猜测：

- shader/effect 数学、blend factor、write mask、alpha/color-space 与 HDR transfer；
- history 的完整跨帧顺序、alias/clear 值与 device-loss 可见结果；
- 粒子公式、随机种子、fixed-step 和视觉轨迹；
- SceneScript event order、重入、完整 API 副作用和销毁顺序；
- 视频 A/V 同步、颜色空间、首帧/loop/seek；
- 多显示器策略在所有 Windows 模式下的实际选择。

## 10. 关联入口

- [客户端二进制与第三方依赖取证](client-binary-dependency-forensics.md)
- [场景格式与 RenderGraph](scene-format-and-render-graph.md)
- [Shader source 前置合同与跨后端假设审查](shader-prelude-and-backend-abstraction.md)
- [SceneScript 运行时实现层合同](scenescript-runtime-implementation-contract.md)
- [运行时系统语义](runtime-systems-reference.md)
- [资料来源与证据索引](source-index.md)
- [覆盖台账](coverage-ledger.md)
- [运行证据索引](runtime-evidence-index.md)
