# 官方客户端 Scene 运行机制静态取证（Ghidra）

> 初次审查：2026-07-30
>
> 32/64 位交叉复核与 64 位机制深挖：2026-07-31
>
> R4 parser/executor 有界复核：2026-08-03
>
> 取证快照：Wallpaper Engine 2.8.42 / Steam build `23967692`
>
> 工具：Ghidra 12.1.2 headless、OpenJDK 21.0.12
>
> 性质：clean-room 静态结构证据，不是运行时或像素等价证据
>
> 文档角色：`official-client-static-observation / research-context-only`。本文不是官方公开规范、产品实现说明或算法说明。implementation agent 不得依据地址邻域、调用关系、字段偏移、客户端控制流描述或本文遗留的“必须/应/可指导”措辞直接落代码；这些措辞一律只表示审查时的研究假设。产品实现只能消费已经独立写入项目语义合同的行为边界、项目正反 fixture 与官方结果对照协议，当前能力与任务顺序只查现役台账、证据索引和路线。

## 1. 目的与边界

本文只记录可提交给 MyWallpaperX 项目合同评审的高层结构候选：

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

### 1.1 阅读顺序与当前项目边界

本文是证据记录，不是能力台账。后续开发按以下路径使用：

| 先回答 | 权威入口 |
|---|---|
| MyWallpaperX 当前是否实现、实现到哪一级 | [覆盖台账](coverage-ledger.md) 与对应专项覆盖表 |
| 当前等级由哪些代码、测试、隔离样本和 GPU 结果支撑 | [运行证据索引](runtime-evidence-index.md) |
| implementation agent 可消费的项目合同与失败边界 | [场景格式与 RenderGraph](scene-format-and-render-graph.md)、[SceneScript API 覆盖表的项目目标合同](scenescript-api-coverage.md#11-mywallpaperx-v2-目标运行时合同)和[兼容运行时架构](../runtime-architecture.md)；本文及 SceneScript 深层静态页只有待独立审查的研究候选 |
| 某个结论的输入身份、方法和静态限制 | 本文 §2–§7 |

2026-07-31 审查时曾在这里记录 RenderGraph、SceneScript、Particle、Video/Sound/Media 的项目等级解释；这些状态已经撤权且不再复制。当前实现和缺口只查[覆盖台账](coverage-ledger.md)与对应专项表，当前运行身份只查[运行证据索引](runtime-evidence-index.md)。

## 2. 输入身份

本轮重新计算的关键输入身份如下：

| 文件 | 字节 | SHA-256 | 角色 |
|---|---:|---|---|
| `wallpaper32.exe` | 4,303,856 | `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07` | 实际历史运行记录涉及的 32 位 Scene 主程序 |
| `wallpaper64.exe` | 5,360,112 | `40e2ce021e9352324fadb3b8f72b8ba2a7ee95b71cc571d5b9f84be75cd993b0` | 64 位 Scene 主程序 |
| `bin/wallpaperui.exe` | 12,742,640 | `dab38bfc017dd5fd4947a09706d23f27833870d1bbb87485677a3e67d1d55791` | Editor作者范围与Scene options描述器 |
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

2026-08-03 的 R4 复核没有扩大到 shader 数学或宽泛调用图。它只针对现有资料仍无法决定的四个公共边界重新分析同一哈希的 64 位主程序：condition 的合法结构、definition function 的目标展开与执行顺序、`[PASS]` 的归属，以及 raw `compose` 与普通 material pass 的关系。结论只以字段归属、节点类型、先后关系和 unknown 边界进入本文；临时 project、脚本、地址与反编译输出不属于仓库证据。

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

对 compiler 策略入口的有界反编译进一步确认，同一入口按类型读取 `format`、`nointerpolation`、`clampuvs`、`nomip` / `halfmip`、`imagesequence`、`spritesheetsequences`、crop/resize 与 `slice3d`。字段名不能直接按位照搬：例如 `nomip` 会被转换成内部“是否生成 mip”的反向状态，错误类型也会进入不同分支。

writer 的 V5 输出固定按 `TEXV0005 -> TEXI0001 -> TEXB0004` 组织，只有存在序列元数据时才追加 `TEXS0003`。64 位主程序 consumer 对 V5 走分块循环并按 `TEXI/TEXB/TEXS` marker 分派，对 V4 则走旧式直接 handler 组合。这个分支形状可以指导自有 reader 做 versioned dispatch，但不提供各 payload 的私有解码算法。

运行中另有一条与 sidecar parser 分离的 image-layer 属性注册路径：`nointerpolation` 与 `clampuvs` 各自接受布尔值或 `{value: ...}` 包装，分别写入 layer 状态位 `0x4000` 与 `0x8000`。image-layer 的构造默认状态含 `0x8000`，但 authored loader 仍可覆盖。两项 descriptor 的直接 property callback 都是 null，因此这里能确认“setter 会更新状态”，不能把“setter 自身立即触发 sampler 重建”写成事实。

resource preparation 到 D3D11 backend 的链已恢复为：

```text
TEX subtype + image-layer state
  -> two sampler policy bits
  -> material sampler cache lookup/create
  -> slot-indexed sampler bind
```

其中 sampler bit 0 由 TEX subtype 的 `nointerpolation` 或 layer `0x4000` 任一来源置位，bit 1 来自 layer `0x8000`。最终 D3D11 descriptor 对这两位的映射为：

| 状态 | D3D11 sampler |
| --- | --- |
| bit 0 = 0 | min/mag/mip linear |
| bit 0 = 1 | min/mag/mip point |
| bit 1 = 0 | U/V/W wrap |
| bit 1 = 1 | U/V/W clamp |

sampler cache key 保留完整状态字及额外 comparison/admission 位，cache miss 才由 device 创建 sampler；结果进入 material sampler state，并按低四位 slot index 绑定。另一 binding flag 会在两个 backend 入口之间选择，但静态路径尚不能无歧义命名为具体 shader stage。完整状态还存在超出上述两位的 filter/address 分支，所以该表只闭合 `nointerpolation/clampuvs`，不是完整 sampler schema。

image-layer 的资源准备方法会重新折叠这些状态并取得 sampler；现有静态调用点集中在初始资源准备、尺寸变化或 effect 重建邻域。运行期 property 写入如何保证该方法再次执行仍未闭合，因而不能据此宣称动态 sampling 已被端到端证明。另一个归属风险是：同一 accessor、对象偏移或位会被不同 property registry 复用；结论必须同时受 image/renderable registry、vtable family 和调用阶段约束，不能只凭 `+0x304` 或单个位值归因。

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

第二轮对 64 位 effect parser 的局部恢复把字段归属收窄为：

- FBO：`conditions/format/scale/width/height/fit/unique/clear/uvs`；
- pass：`conditions/command/source/target/compose/material`，其中 material 引用另保留 `index/conditions`；
- definition function：按名称登记的 `action/fbos`；当前可验证 action 只有 `clear`；
- typed backbuffer：`rgb_backbuffer/rgba_backbuffer`。

`repeat` 是 FBO `uvs` 的已观察取值，不是 function 字段；`index/conditions` 属于 pass 内 material 引用，也不能挂到 function 上。此前把四者合并成 function schema 是字段邻域误归属，本轮已由 parser 的有界控制流复核纠正。

condition 在 FBO、pass 或 material 引用纳入结构前由同一 evaluator 求值。可验证的作者形态是 condition array；每个 array 元素为以 combo 名称为 key 的 object，value 可为直接数值相等比较，或带数值和 `ge/gt/le/lt` 运算符的比较对象。所有有效条目共同决定准入，combo 表缺少 key 时客户端数值入口取零。客户端对非 array、非 object 和部分错误类型存在宽松行为；这些 malformed 路径不是公开兼容合同。合法 AST 与 malformed 输入的产品边界只由[现役 RenderGraph 合同](scene-format-and-render-graph.md)规定，本静态观察只提供黑盒差分候选。

`command` 与可选 `source/target` 保持独立字段；`compose:true` 设置独立状态并增加 compose 参与计数。`copy` / `swap` 被编译成与普通 material pass 不同的两个 command enum；未知 command literal 不产生新 enum，而落回 ordinary-pass shape。未知值的官方可观察结果仍需黑盒负向用例区分；项目的 fail-closed 与诊断策略只查现役 RenderGraph 合同。

executor 又把三类节点的结构区别闭合：

- ordinary pass 按已解析 bind index 取得 texture，绑定 target，执行 material，再释放 target；
- `copy` 先激活 source render target，再对 target 调用专用 copy operation，随后恢复 source；它不进入 material/bind 执行；
- `swap` 要求 source/target 都已解析，随后交换持久 runtime pass records 中所有非-swap pass 的 source、target 与 bind resource index。它不复制像素，也不执行 GPU material；同一 effect 后续节点和后续帧会观察到交换后的 logical identity，重复执行可形成 ping-pong/history rotation；
- `compose:true` 的 pass 执行完成后，外层按 authored pass 顺序推进 full-frame 输出对的当前 identity；它是 composition boundary，不是 material 名称或普通 blend flag。

FBO definition 到运行资源的准备链又闭合了以下合同：

- 缺省 `width/height` 取 layer 当前 extent，显式值覆盖对应轴；`fit` 在不放大原 extent 的前提下限制长边并保持宽高比；`scale` 作为后续 extent divisor，底层至少保留一个非零最小 target。这是三个字段在固定客户端路径中的不同阶段，不直接规定项目 IR 或 allocation API；
- 非 `unique` FBO 通过 authored name、resolved extent、format 等组成的 key 查询共享 render-target cache；`unique:true` 改走追加 effect identity 的 key。effect identity 优先使用实例 JSON 的 `id`，缺失时由 owner registry 分配，因此 unique 是实例隔离合同，不只是禁止同名；
- `uvs` 只有字符串精确为 `repeat` 时切换一项底层创建 policy，其他值保留默认 policy；静态路径尚未把这项 policy 闭合到最终 D3D/Metal sampler address mode；
- `clear` 只有成功解析四个分量时才置位。resource prepare 在 target 创建或尺寸更新后设置这四个分量并执行一次 clear；frame executor 不会因为 FBO 声明带 `clear` 而逐帧自动清屏。clear 的颜色空间、alpha 解释和共享非-unique target 的跨 owner 可见性仍需 dynamic golden；
- 已存在的 target 在 resolved extent 变化时原位触发资源重建并更新依赖 descriptor；这条资源准备路径不会重写 pass records 中被 `swap` 改过的 index。effect list reload 则先释放全部 pass/FBO records，再从 authored JSON 重建，所以 logical swap mapping 在资源 resize/reprepare 中保留，在 effect reparse 时复位；device-loss 是否同时触发 effect reparse 仍未闭合。

command 的负向路径也不是统一的“缺字段即 no-op”：

- 未解析 target 时 `copy` 不调用 target operation；未解析 source 时它跳过 source activation，但若 target 已解析仍会调用 target operation，因此会依赖当时的 ambient input。source/target 指向同一 identity 时也没有 alias guard；
- `swap` 在任一 identity 未解析时直接返回；两个 identity 相同时 logical rewrite 为 no-op。两个不同 identity 最终若因非-unique cache 指向同一底层 target，静态路径没有额外 hazard 保护证据。

compose 的对象与时序已由 R4 的最后一次单点复核收窄为 layer-local full-frame pair，而不是 scene-background alias 或任意 FBO copy：

- 没有 active effect 时，layer 直接走原有 base render 路径；至少一个 effect active 时才准备两个 full-frame 成员；
- layer 以 active effect transition 与实际纳入的 raw compose transition 总数决定初始 current 的奇偶成员，使完整链结束后仍落到固定 final-output 成员；condition-false 的 FBO/pass/material 引用在 runtime pass vector 与 transition count 形成前已被移除；
- effect 链开始前，layer 激活这个 parity-selected current，并调用一次 layer 自身的 base content render；这不是对已合成 scene background 的隐式捕获；
- 每个 active effect 以 current 的另一成员作为 effect output。ordinary material pass 的缺省或显式负 full-frame bind 读取当时的 current；只有该 ordinary pass 实际执行且带 `compose:true` 时，current 才在该 pass 后推进到刚写入的成员，因此同一 effect 的下一 pass 立即读取新 current；
- copy、swap 与 definition function 不推进 compose pair；effect 结束时其 output 成为下一 effect 的 current，所以无 raw compose 的普通 effect 也保持有序 chain handoff；
- 链结束后，最终 current 的底层资源进入 layer final-output 对象，再交给正常 layer/compositor 路径。单独的 `_rt_FullFrameBuffer` lookup 受另一 effect flag 控制，raw compose 本身不建立这个 ambient provider。

这些事实只形成 pair 初始选择、base capture、同 effect 与跨 effect 可见点及最终发布方向的版本有界观察；项目事务形态仍须由审定后的行为合同与黑盒正反门决定。静态路径不公开 material shader 数学、clear/alias 像素结果、另一个 ambient flag 的作者语义或跨版本实现细节。

definition function 与逐帧 graph command 也是两条不同路径。parser 只在 function action 为 `clear`、`fbos` 为可枚举目标且至少一个名称能解析到已登记 FBO 时形成 function record。运行时按 function 名称找到该 record 后，依目标顺序逐个激活 FBO、应用目标保存的四分量 clear state、执行 clear，再恢复目标；未知名称不产生 clear。可交接的问题是 function identity、显式调用与目标顺序是否属于作者可观察合同；静态路径没有证明 function 会自动挂到 create、resize、每帧或 compose 生命周期，也不规定项目 registry/command 类型。

shader frontend 的 R4 单点复核确认 `// [PASS]` 是 shader source metadata，不是 effect JSON pass、material ordinal 或 copy/swap/function command。2.8.42 可验证的 token 只有 `shadow`，解析结果与已编译 vertex/fragment shader metadata 一起缓存，并与独立的 3D shadow-caster 材质路径对应；有限调用邻域没有把二者闭合成可移植的通用 schedule。官方公开 [Shader Variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html) 只定义 `[COMBO]`，没有公开 `[PASS]` 的通用作者合同；静态证据也没有证明任意 token 或 2D effect schedule。可交接的问题仅是 metadata 是否需要 loss-preserving 携带，以及未知/active token 的官方失败结果；2D executor 的产品准入边界只查现役合同。

2026-08-09 又对同一 2.8.42 64 位主程序的 normal material-pass combo 编译链做了单点复核。高层可恢复顺序为：material pass汇集当前active shader声明和material显式combo → 对每个声明查询compile map → 已有显式值时保留 → 缺少时读取该声明的`default`并插入同一map → 统一define emitter生成宏 → WE HLSL translator → 动态解析的`D3DCompile`。因此annotation default不是只供editor展示的孤立字段，而是player实际编译输入；material显式值与相同default会得到相同最终宏值。反向检查中，JSON `require`没有被该声明/default binder读取，也没有参与normal pass compile-map剪枝；精确的`#require`字符串属于另一条preprocessor directive路径，不能与JSON成员混同。这个负面结论由已定位parser/binder和全可执行文件精确字符串交叉支持，但仍只覆盖当前版本的normal DirectX player链，不能外推editor、其他backend或所有版本。

这项静态路径观察到“material 显式值”和“active shader annotation default”来自不同 provenance，随后进入同一最终 macro environment；`#if`、`#ifdef`、`defined(...)` 与普通 source 展开读取该环境。variant digest、Program cache、冲突/畸形 default 的产品策略只查现役 shader 合同，本结论不授权复制客户端错误恢复，也不改变资源 require 的项目边界。

这些结果只证明固定客户端把 typed command、FBO allocation state 和 mutable logical-resource mapping 作为不同结构，并且观察到的 `swap` 交换 logical identity 而非执行像素 blit；它们不直接规定项目类型或算法。静态路径仍未给出 copy 的 exact D3D primitive、颜色/采样转换、同资源 copy 结果、device-loss 后 history 可见结果或 clear 的像素解释。

### 5.2 32/64 位主程序交叉结果

2026-07-31 使用同一 Ghidra 探针对两份主程序独立恢复。下表只比较结构，不比较函数地址或数量：

| 主题 | 两个架构共同证据 | 差异与结论边界 |
|---|---|---|
| RenderGraph admission | `conditions/compose/target/unique/clear/rgb_backbuffer/rgba_backbuffer` 的核心共现集合一致；condition 与 graph 字段汇入同一 parser 邻域 | `clear` xref function 为 64 位 4、32 位 3；不能写逐函数等价 |
| Material values/state | `constantshadervalues/usershadervalues/usertextures` 共址；`alphawriting/depthtest/depthwrite/cullmode` 共址 | 只证明读取与汇合，不给出 blend factor、write mask 或 override 完整优先级 |
| TEX/built-ins | `TEXI/TEXB/TEXS` 与 resolution/mipmap/rotation/translation 家族对应 | 32 位未恢复到 64 位可见的独立 `TEXV`、`clampuvs` literal；不能用 literal 缺失否定代码路径 |
| Particle graph | `controlpoints/children/maxcount/starttime` 的全部 pair 共现集合一致 | 64 位 factory/variant/lifecycle 与 dispatcher 编排已进一步恢复；32 位未做同深度复核，component 数学、random seed 与视觉轨迹仍未知 |
| Final output | `hdr/bloom/downsample/upsample/srgb/display` 的核心共现关系对应 | `hdr+downsample` xref 数不同；不证明 tone-map 数学或 HDR 像素结果 |
| GPU/text/media | 两边 `D3D11CreateDevice` 6 refs、`DWriteCreateFactory` 2 refs；URL/byte-stream source、media session、DXGI device manager 同时存在 | topology/renderer activation ref 数有 ABI/恢复差异；COM 间接调用未完整计入 |

这足以把 32 位路径从“只有 import 基本同构”提升为“关键 parser/resolver/particle/final-output 结构对应”。它仍不证明启动器选择条件、完整内部等价、像素、时序或性能一致。

### 5.3 Frame、readiness、reset 与 final output

主 render thread 使用高分辨率 counter 计算连续 frame delta，并把 local date/time 与 frame progression 分开；资源/视频 readiness 会影响 active/wait 路径。恢复出的 scene 时间链为：

```text
raw elapsed
  -> FPS / pause admission
  -> smoothed time scale
  -> authored playback scale
  -> clamp
  -> effective scene delta
```

`engine.frametime`、scene `runtime` 累计、SceneScript tick 与 timer 共用这个 effective-delta 时间域。pause 渐变阶段会随 time scale 同步减速；完全暂停后不再 tick 或累计。恢复时先重置性能计时基线，暂停期间的 wall time 不会进入首个恢复帧，也不会触发 timer catch-up。`engine.timeOfDay` 则每帧重新采样本地系统时间，不属于累计 scene runtime。静态路径没有给出可移植的 smoothing/clamp 数值；项目时间 policy 只由现役合同和自有 fixture 决定，客户端常量不进入中性交接。

device loss 或 scene rebuild 会按资源族释放并重建 render target、material/shader cache、texture/provider 与 scene state。这提供了“各资源族的 generation 与恢复顺序是否对外可见”的中性研究问题，不直接授权 `reset(reason, generation)` API 或任何具体跨资源事务形态。

最终输出按 LDR、HDR、video-HDR 与 display-HDR 选择不同 combine/downsample/bloom/blur/upsample 参与者。静态证据确认 typed output-mode graph 的必要性，但没有给出 transfer function、色域、tone-map、bloom 数学或 Metal 等价参数。

### 5.4 Pause/mute 与 renderer policy

pause 与 mute 是独立的 renderer 状态，不是同一个“不可见”开关。集中策略更新会遍历现有 renderer：pause 由全局 interruption reasons 与显示器 mask 联合计算，mute 由全局静音 reasons 集合计算；新建 renderer 立即继承当时的策略。renderer window 已存在时，状态会同步投递到 renderer thread；window 尚未建立时先保存为初始状态，待创建后生效。

这些观察可用于黑盒区分 lock/sleep/display sleep/user pause、静音与 per-display eligibility 是否独立影响 renderer，以及新旧 renderer 何时取得状态。跨平台 reasons、snapshot 和 IPC 形态只由项目现役运行时合同决定；最终 wire format 尚未闭合，本文不记录或推断消息号。

### 5.5 Particle factory、frame 与 teardown

64 位粒子 definition factory 的字段/组件引用集合覆盖 168 项标识，包括 emitter、initializer、operator、renderer、children、event spawn/death/follow、control point、collision、Rope/RopeTrail/SpriteTrail、turbulence 与 boids；initializer/operator 数组另由专门 helper 解析。这个数字表示 factory surface 的静态宽度，不表示 168 项都能执行，也不等于粒子能力台账的行数。

definition bitfield 会直接选择 renderer variant。可识别的 variant 维度包括 `TEX0FORMAT`、`THICKFORMAT`、`ORIENTATION`、sprite sheet、blend、NPOT、trail renderer、fade alpha/size、scroll 与 subdivision；`genericropeparticle` 进入独立 shader/material 分支。CP0...7 及 angle0...7 另有独立动态属性注册入口，证明 control point position 与 angle 都属于 live property surface，而不是只在加载时读取一次。

同版本官方编辑器的 Particle General 属性注册还把五个 instance-override 禁用项逐项绑定到 definition `flags`：color `0x08`、speed `0x10`、count `0x20`、lifetime `0x40`、size `0x80`。随包 fireworks refract 资产的 `flags=8` 与“禁用颜色覆盖”更新记录互证，lightning child spawner 的 `flags=248` 则是五个位的并集。这里记录的是公开 JSON wire bit 与编辑器控件的对应，不包含客户端执行算法；具体执行等级仍由粒子专项表和项目自有正反 fixture 决定。

definition 初始化会先递归实例化直接 child，并分别保存普通 child 与 event-follow/event-spawn/event-death group。非零 `starttime` 不是首次 frame 的时间偏移：runtime 会暂时切换运行标志，按粒子规模选择离散步长，反复调用正常的 per-runtime simulation dispatcher 覆盖预热区间，再恢复标志并刷新输出 buffer。具体步长和阈值不归档为跨平台参数。

单个 runtime 的 simulation dispatcher 已恢复为以下有序阶段：

1. 处理死亡/回收索引，并完成 event-death child 的创建或复用与 parent-state handoff；
2. 准备 transform、control-point 与 simulation context；
3. 在允许 emission 时，按 authored 顺序执行 emitter record stream；
4. 每个新粒子先写默认 channel，随后立即按 authored 顺序执行 initializer record stream；
5. 一个 emitter batch 完成后，再处理 event-follow/event-spawn child handoff；
6. operator 前复制需要 previous-state 的 channel；
7. 按 authored 顺序执行变长 operator record stream；
8. 保存本轮状态快照。

collision plane/sphere/box/bounds/quad/model 均编译为同一个 operator stream 内的变长 record，运行时与其他 operator 共用 type dispatch 和 record-size 前进合同；它们不是 operator 之外的独立末端阶段。这个结论只确定编排，不确定碰撞数学、反弹结果或与所有 event 的视觉等价。

operator dispatcher 还存在 mode-dependent substep policy：普通模式执行一个整步，另一组 host mode 把 frame delta 与相关 time scale 一致缩放后执行两个子步。可交接的黑盒问题是不同 mode 下 operator 获得的 effective delta 与结果；本观察不规定项目 operator stage 的参数或调用形态。

root/child 的普通帧顺序也已闭合：父 runtime 先完成上述 simulation 与 snapshot，再按 definition 容器顺序递归更新直接 child，随后按 event group 和组内活动实例顺序更新 event child；递归调用继承同一 frame delta 与更新标志。父 dispatcher 本帧新插入且通过 probability/capacity 等门的 event child 会进入稍后的 child 遍历，其中 event-death 的新建/复用路径得到直接确认。

更外层的 frame 顺序为：

1. active/pause/reset gating；
2. 必要时清空活动缓冲与 child runtime；
3. frame delta 乘 timescale 后累计 system time；
4. 取得 host transform/frame state；
5. 准备 control-point/transform context；
6. 进入 simulation dispatcher；
7. 标记输出缓冲 dirty。

reset/teardown 会归零活动计数和 CPU buffer，遍历 root 与分组 child，递归析构嵌套 child，并清空 vector/hash/index 容器。这支持项目为 particle runtime 建立显式递归 owner/reset 合同。仍未恢复的是随机状态/种子、各 component 的数学表达、所有 probability/capacity 边界、renderer 数学和视觉轨迹。

### 5.6 Particle Control Point angle 结构复核

2026-08-02 使用 Ghidra 12.1.2 对本资料库已记录且 SHA-256 匹配的 2.8.42 `wallpaper64.exe` 做单点复核。只记录可用于 clean-room 设计的高层结构：Sphere、Box、Vortex 与 Map Sequence 进入同一 particle component dispatcher；`controlpoint0...7` 与 `controlpointangle0...7` 在同一 instance property registry 内各自形成 typed vector family，并复用同类 typed accessor。它与 revision 4154 的 “emitter、vortex、map sequence around CP 可依赖 CP angles” 及 revision 4225 的 default CP angles 更新相互支持，表明 position/angle 应先组成共享 CP frame，再由合法 consumer 使用，而不应为每个样本建立单独旁路。

本次没有从二进制提取或归档 Euler 顺序、矩阵表达、随机/积分算法、覆盖规则或任何可移植 payload；也没有确认 32 位实现等价。Ghidra 原始地址、伪代码和临时 project 均未入库并在复核后清理。因此项目 `7cce5fde` 的 X→Y→Z authored-radian 顺序、有限预算、Sphere/Box consumer 范围和 instance-current 替换 default 的行为仍是项目自有 bounded 合同，只由自有 fixture、stock/Workshop 方向性运行证据支撑，不是官方算法或 Windows 数值/像素 truth。

### 5.7 Particle child transform 配置帧复核

2026-08-02 对同一哈希匹配的 2.8.42 `wallpaper64.exe` 做第二个单点 clean-room 复核。只保留高层结构结论：同一 child 配置归一化路径同时处理 `origin`、`angles`、`scale`、`probability`、`maxcount`、`type` 与 `controlpointstartindex`；缺省 transform 分别归一到零 origin、零 angles 与单位 scale。属性注册侧又把 origin/scale/angles 放入同类 typed property/accessor family。结合公开 Children 页同时列出 Offset、Angles 与 Scale，这支持项目先建立统一 child transform frame，再由各 renderer/profile 严格准入，而不是为特定 child 资源建立旁路。

该复核不提供矩阵顺序、Euler 约定、scale 对 position/size/velocity 的精确传播、镜像规则、renderer 差异或 Windows 数值/像素 golden。Ghidra 原始地址、伪代码和临时 project 均未入库，临时目录已清理。项目 `3fd77125` 的 uniform screen-plane scale、有限预算和对 local position/size/velocity 的传播是项目自有 bounded 近似，只由合法 corpus、项目 fixture 与隔离样本门约束，不是官方算法。

### 5.8 官方 effect/particle corpus 对开发排序的约束

本节只做字段与组合频率统计，不复制 payload。粒子范围与既有 corpus 一致：`assets/presets`、`assets/scenes/particleelementpreviews`、`assets/particles` 和默认 Scene，共 295 个路径、215 个不同 JSON payload。

去重后的 215 个 definition 显示：

- 212 个只有一个 emitter，3 个有两个 emitter；这与运行时 ordered emitter stream 互证，多 emitter 不能被合并成无序配置；
- 202 个使用 `movement`，184 个使用 `alphafade`，69 个使用 `sizechange`；公共 operator pipeline 的收益远高于为低频 component 建立旁路；
- 67 个具有正的 `starttime`，离散 prewarm 是常见 authored 合同，不是极端兼容项；
- 50 个含 child，共出现 static 36、event-death 17、event-follow 12、event-spawn 4 次；child graph、event owner 和递归 teardown 应作为同一能力族实现；
- 五类实际出现的 collision definition 都来自各自的官方 element preview，且未与 event child 共现；它们为隔离正向 fixture 提供输入，但不能据此推断真实复杂作品中的 collision/event 组合顺序；
- 204 个显式声明 renderer，11 个没有 renderer record；这证明 authored corpus 存在“缺省 renderer”和“显式 renderer”两种输入形态，但不直接规定 loader 或 parse IR。两者的官方可观察差异仍需运行对照。

46 个根 effect definition 另显示：

- 36 个为单 pass，10 个为多 pass；多 pass 中包含 3 条独立 command pass（1 次 copy、2 次 swap）；
- 9 个声明 offscreen buffer，39 个 pass 写显式 target；部分 target 在同一 effect 中重复写入，证明资源 identity 与 pass identity 不能合并；
- pass-level 与 bind-level `conditions` 都实际出现，bind slot 使用到稀疏 index 4；condition 必须先于 admission，slot 也不得压缩；
- `compose` 是独立 pass flag，不等于普通 material pass；
- 其中一个随包 effect 文件带单个 trailing comma，严格 JSON parser 会拒绝；这是输入兼容候选，不足以单独证明客户端所有 JSON 都宽松。它只提供“该固定输入是否被接受、诊断如何呈现”的黑盒问题；bounded normalization、source identity 和语法失败策略只由现役格式合同决定。

这些频率只用于开发排序和 fixture 选择，不把静态文件存在性提升为 MyWallpaperX 的执行等级，也不证明官方视觉结果。

### 5.9 Particle Audio Response 归一化结构复核

2026-08-02 对资料库已登记、SHA-256 为 `40e2ce021e9352324fadb3b8f72b8ba2a7ee95b71cc571d5b9f84be75cd993b0` 的官方 2.8.42 `wallpaper64.exe` 做一次范围明确的 Ghidra 12.1.2 clean-room 复核。该复核发生在本批证据顺序收紧之前；以后应先读现役专项表、资料库既有分析、官方网页与合法 corpus，只有结构性问题仍阻塞公共设计时才重复反编译。

本次只保留以下高层结构：五个 `audioprocessing*` 字段由同一归一化路径处理；mode 缺失时关闭，exponent 默认值呈现为 2，frequency start/end 默认呈现为 0/1，频段索引在 16-band 范围内约束并按序处理。Sphere、Box、Layer Image、Turbulent Velocity、Turbulence 与 Vortex 已在既有共同 particle component dispatcher 证据中出现，因此 audio declaration 应先进入共享 typed plan，再由合法 consumer 各自准入，而不是按样本或组件复制解析分支。

该复核没有恢复跨频段聚合、bounds 数值归一化、phase/rate/speed 的调制幅度、每帧采样时相或任何可移植 runtime 公式；也没有证明 32 位路径、Windows 轨迹或像素结果等价。原始地址、伪代码、函数体、临时 project 与日志均未入库，临时目录已清理。项目 `5cc7ee37` 的 frequency mean、linear bounds normalization、exponent、mode-only `0...1` bounds、`1 + response` phase 和 rate/speed scale 都是独立的 project-owned bounded approximation，只由公开行为、自有正反 fixture 与隔离样本证据约束，不是官方算法。

### 5.10 Particle Position Offset Random 字段注册复核

2026-08-02 在先读现役 Particle 专项表、既有 2.8.42 静态审计、官方 Initializer 页面与合法 stock corpus 后，仍无法判定 `directions/sign/octaves` 是否属于 `positionoffsetrandom` 的实际字段注册。本次只对资料库已登记、SHA-256 为 `40e2ce021e9352324fadb3b8f72b8ba2a7ee95b71cc571d5b9f84be75cd993b0` 的官方 2.8.42 `wallpaper64.exe` 做一个字段归属问题的 bounded Ghidra 12.1.2 clean-room 复核。

只保留以下高层结论：引用 `positionoffsetrandom` 的组件注册函数也直接引用 `directions`、`distance`、`octaves`、`scale` 与 `timescale`；`sign` 没有直接 code/data 引用，也没有可验证的一跳函数关联。结合随包 standalone 预览，这五个字段可进入中性交接的字段归属候选；`sign` 仍只能作为待黑盒区分的问题。项目 typed declaration 与失败边界只由现役粒子合同决定。

本次没有反编译、摘录或移植 Position Offset 的 FBM、随机、默认、空间、时间或数值公式，也没有恢复 32 位路径、运行顺序、Windows 轨迹或像素结果。原始地址、伪代码、函数体、临时 project、脚本和日志均未入库并已清理。项目 `968d86eb` 的字段预算、缺省 `1 1 0 / 3 / 1 / 1`、seed/particle/time/position 采样和 finite-octave gradient-noise 数学都是独立的 project-owned bounded approximation，只由公开行为、自有正反 fixture 与隔离 stock 运行约束，不是官方算法。

### 5.11 Particle event value inheritance 字段与模式复核

2026-08-02 在先读现役 Particle 专项表、资料库既有 initializer/operator field census、官方 Initializer/Operator 页面、editor string table、changelog 与合法 stock corpus 后，仍无法确认 `inheritinitialvaluefromevent` 和 `inheritvaluefromevent` 是否共用同一 `input` typed parser，也无法仅凭 stock omission 判定缺省 mode。本次只对资料库已登记、SHA-256 为 `40e2ce021e9352324fadb3b8f72b8ba2a7ee95b71cc571d5b9f84be75cd993b0` 的官方 2.8.42 `wallpaper64.exe` 做一个字段/模式归属问题的 bounded Ghidra 12.1.2 clean-room 复核。

只保留以下高层结论：两个 component 名称进入同一 particle component dispatcher；各自锚点后都存在对 `input` 的直接引用；两者进入同一套 14-value typed parser；该表首项为 `setcolor`，未知值走独立 sentinel。结合公开页、随包预览、editor string table 与 changelog，这些内容可进入“是否共用声明、缺省是否为 `setcolor`、其他 mode 如何失败”的中性交接问题；本页不授权任何 channel 进入产品执行。

本次没有恢复或摘录省略 `input` 的官方默认、枚举数值、event 同帧顺序、parent state 生命周期、色彩空间、每帧复制时机、其他 channel 的转换公式或任何可移植 runtime 算法，也没有证明 32 位路径、Windows 数值或像素等价。原始地址、伪代码、函数体、脚本和日志均未入库。项目 `b9e60059` 把省略 `input` 视作 `setcolor` 是 stock omission 与上述高层结构共同约束下的 project-owned bounded inference，不是已确认的官方默认；显式小写 `setcolor` 与省略形态之外全部 fail closed。

### 5.12 Camera Shake evaluator 与 camera composition

2026-08-09 在先读现役Camera/Frame专项表、editor strings、SceneScript声明、合法Workshop/stock corpus与Mirage固定revision后，公开资料仍不足以决定Camera Shake的幅度基准、projection selector、状态模型和parallax顺序。本次只对上表哈希匹配的2.8.42 `wallpaper64.exe`及同包`wallpaperui.exe`做Ghidra 12.1.2 bounded clean-room复核；以下只记录可由项目自有门验证的高层行为，不保存地址、伪代码、函数体或反编译表达式。

- Scene侧作者默认是disabled，speed/amplitude/roughness为`3 / .5 / 1`；editor描述器范围分别为speed`0...5`、amplitude`0...1`、roughness`0...2`。这些是authoring范围，player路径没有证明同点runtime clamp。
- evaluator直接读取共享scene/world absolute time，不持RNG、seed或逐帧积分状态；同一时间得到同一位移。基础周期在起始时X为正峰、Y/Z为0，roughness只作径向长度整形；roughness 0走保护分支并保留基础向量，不等于关闭。
- evaluator把同一个位移加到working eye和working center，因此保持视线方向，不改rotation、roll、zoom或FOV。base/default/active/path camera先产生eye/center/up，随后才叠shake。
- 分支由Scene `general.orthogonalprojection`形成的全局mode位选择，不读取particle/layer flags。orthographic先清零Z、以XY做roughness整形，再乘`amplitude × authored projection height × .01`；true perspective保留XYZ并使用独立scale。正交Scene中即使particle `flags=4`选择下游perspective VP，也不会再求第二套XYZ shake。随包orthographic Scene + flags4 Snow preset只作状态分层互证，不承担shake动态证明。
- shake写回working eye/center后，parallax算术明确读取刚写回的eye XY并与pointer平滑项组合；shared view同样只由这一shake后working camera构建，不回读base camera。Mirage固定revision在这里读取base camera并采用不同scale/suppression策略，不能作为官方真值。

该证据不足以证明 player 对越界脚本值的处理、官方 pause/seek 事件、其他版本/backend、Windows 同相位数值/像素或真正 perspective Scene 在 MyWallpaperX 已实现。项目当前的独立 2D orthographic bounded evaluator 及其证据只由 [E-CAMERA-SHAKE](runtime-evidence-index.md#e-camera-shake) 说明，本静态页不为其取得实现授权。临时 Ghidra 工程没有进入仓库，复核后已精确清理且当前不可恢复。

## 6. SceneScript 的 module/engine/owner 机制

### 6.1 宿主层次

32/64 位 DLL 共同公开：

- `Init`
- `CreateSceneScriptEngine`
- `GetSceneScriptVersion`
- `Shutdown`

64 位主程序深挖确认：主程序动态装载 DLL，先要求 `GetSceneScriptVersion()` 与 `2.8.42.SceneScript` 精确匹配，再取得 init/engine factory；版本不符失败关闭。module 使用进程级 init/shutdown。主程序在 scene 第一次准入脚本时按 scene 创建一次 engine，并把它保存在 scene owner 中；engine 实例另有 isolate、script/timer/property/audio 表和宿主桥，不是跨 scene 的进程单例。

engine 还具有：

- 固定事件槽及每槽存在/禁用状态；
- frame-delta timer；
- frame tick 音频数组刷新；
- property return 的集中 typed conversion；
- 每回调耗时统计；
- 实例级 watchdog 与永久中断状态；
- host-owned destroy 和有序 teardown。

这些静态结构把 module global、engine instance、owner script record 和 host event bridge 表现为不同对象；它们只形成生命周期与隔离的黑盒问题，不直接规定项目对象模型。项目 SceneScript 架构与预算边界只查[现役 SceneScript 目标合同](scenescript-api-coverage.md#11-mywallpaperx-v2-目标运行时合同)。

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

### 6.3 Frame tick、timer 与 owner teardown

主程序的 scene frame 路径给出了一个可迁移的有序合同：

1. 先消费已经排队的 media/provider 变化并派发对应事件；
2. 处理本帧 animation crossing，并派发 `animationEvent`；
3. 调用一次 engine frame tick；
4. engine tick 内先原地刷新 audio arrays，再遍历 timer 快照；
5. tick 返回后，主程序沿 script-record 双向链表直接向仍存活的 record 派发普通 `update`；
6. 普通 `update` 结束后，宿主才 drain pending destroy，再进入本帧后续 render preparation。

这闭合了 audio/timer 与普通 `update` 的相对顺序，但不代表所有 cursor、resize、user property 与 media producer 都在同一个函数中产生。

timer 是 owner-scoped record。每轮 scheduler 会先复制当前 timer 指针快照，因此回调中新建的 timer 不会在同一轮获得第二次执行机会，取消或删除也不会破坏当前遍历。one-shot 回调结束后按 record identity 删除；interval 到期后每帧最多触发一次，并从完整周期重新计时，不追补长帧遗漏的周期，也不累积 overshoot。owner removal 会逐条释放其 timer。

timer 接收的是 §5.3 的 effective scene delta，而不是独立 wall clock。完全暂停时 scene engine 不 tick，timer 也不累计；恢复时重置计时基线，不追补暂停期间的 interval 或 timeout。

`registerAudioBuffers` 只允许在 global evaluation phase。分辨率只接受 16/32/64，未提供时走 16；首次注册建立三档 left/right/average backing arrays，后续 tick 在原数组上更新，因此 VM 所见 array identity 跨帧稳定。静态证据没有给出可移植的音频归一化、平滑或缺设备 policy；这些项目策略只由现役合同和自有 fixture 决定。

普通 `update` 与 timer 不使用同一种 mutation admission。新 owner 的 script record 在创建时尾插到 live 链表，且 `init` 同步执行：

- cursor/media/timer 阶段创建的 owner 会在稍后的同帧普通 `update` 中被访问；
- 普通 `update` callback 创建的 owner 会同步取得 `init`，并因 live traversal 继续前进而在本轮后段获得第一次 `update`；
- callback 请求 destroy 只进入 pending queue，不会在当前 callback 中释放 record；
- destroy drain 中的 `destroy` callback 再创建 owner时，普通 `update` 已经结束，因此新 owner 要到下一帧才第一次 `update`。

最后一种 owner 在同步 `init` 前已经加入 native/render registry。destroy drain 后仍会运行 render preparation，因此只要类型和 effective visibility 满足，它可能在创建帧已经显示，而首次普通 `update` 位于下一帧。这是官方宿主的可观察 admission 边界，不是建议项目允许 callback 无限扩张工作量。

主程序的公共 owner removal 路径会在一个 engine batch 中先派发存在的 `destroy`，再从 engine 删除对应 script record，最后释放宿主 record。scene teardown 又先释放各类 owner，再释放 scene engine；因此当前路径的顺序已经闭合为：

```text
destroy callback
  -> engine record removal
  -> host owner record release
  -> after all scene owners: engine release
```

DLL 的 record removal 与 engine 析构本身仍不会替宿主派发 `destroy`；exactly-once 取决于宿主只让 owner 进入一次公共 removal 路径。

### 6.4 已恢复的 host binding 合同

以下事实只用于 research card 和项目自有 contract/fixture 的独立设计评审，不公开客户端内部 ABI，也不直接授权产品实现：

- **asset registry**：`registerAsset` 只允许 global phase，按传入路径去重；重复注册不改写第一次的 precache 选择。VM 边界能取得路径值，而 v2.8 公共声明暴露的是 opaque `IAssetHandle`。registry 随 owner 释放；路径 canonicalization、大小写、依赖展开与真实 precache 时点仍未知。项目 handle 形态只查现役 SceneScript 合同。
- **dynamic layer**：`createLayer` 同步进入宿主并立即取得 native identity；wrapper cache 按 native identity 复用 handle。bridge-managed identity vector 每项 8 bytes，已有字节长度大于 `0x3fff` 时创建返回空值，因此 2047 项可再创建一项，已有 2048 项时拒绝；该上限不能被解释为“只统计动态 layer”。`getLayerIndex` 对未知 identity 返回 `-1`，`sortLayer` 对未知 identity 返回失败；native sort 会把超过当前长度的目标 index 夹到尾部，负数在 VM 边界是否先被拒绝仍未闭合。sort 只改变 native/render topology，不改变 script-record 注册顺序。`destroyLayer` 同步返回请求结果，实际 removal 在普通 `update` 后的 pending-destroy drain 执行。wrapper 创建时还向 native object 注册 lifetime callback；对象真正销毁时 callback 同时清除 identity/index 两张表并释放 wrapper，旧 handle 不能继续命中 cache。`getInitialLayerConfig` 是宿主配置序列化后重新解析出的 detached object，不是 live alias。
- **layer parenting**：`setParent` 先把 string/number/handle 统一解析为 native parent identity，并把 attachment number 或 name 解析为 index；缺少 parent 表示解除父子关系。native core 同步从旧 parent 的 child vector 摘除并写入新 parent/attachment，不经过 pending-destroy queue。`adjustTransforms=false` 直接切换关系；`true` 会以切换前的 world transform 和新 parent/attachment transform 重算 local origin/angles/scale。相同 parent 与 attachment 是成功 no-op；显式 self-parent 或内部 flag/child complexity guard 失败时不会恢复旧 parent，而是保持 unparented 并报告 invalid configuration。`getParent` 直接返回当前 identity，`getChildren` 复制调用时 child vector 的 `[begin,end)`，不是 live collection。descendant cycle、缺失 parent/attachment 的 VM 负向行为以及 guard 的跨平台含义尚未闭合。
- **model data**：`createModelData` 返回带 token 的 VM handle；`applyData` / `replaceData` 共用一个 native update bridge，以 mode 区分，且 update phase 明确拒绝 `replaceData`。负向路径分别拒绝 buffer 增长、非 dynamic 更新、shape/buffer 增删、material 或 vertex-format 改变，以及 index type/lock/layout 不兼容。destroy 使用 token/handle；仍被 layer 引用时只登记销毁请求，释放延后到引用解除。
- **local storage**：set/get/delete/clear 均禁止 global evaluation phase。默认域是 screen，只有字符串精确等于 `global` 才切到 global，其他值回落 screen。key 必须为 string；`set(key, undefined)` 转为 delete。value 先经 VM 序列化再写入带版本 envelope，get 遇到 envelope/反序列化失败返回 `undefined`；delete/clear 透传宿主成功状态。namespace、quota、原子性与跨重启结果仍未知。

二进制内部注册了名为 `clearTimeout` 的 binding，但 v2.8 公共声明只记录 `setTimeout`/`setInterval` 返回的 cancel function。内部兼容入口不构成作者公开 API 证据；项目公开表面只查现役 SceneScript 合同。

### 6.5 Cursor 命中、传播与输入状态

cursor traversal 使用当前帧收集出的候选快照，并只对 layer flag word 中 `solid` bit 置位的对象调用 native layer hit-box/detail virtual。这里的 hit test 是宿主内部 layer 几何接口，不是 v2.8 SceneScript 公共 hook；官方声明中不存在 `cursorHitTest`。

同一 flag word 已闭合三项独立状态：

| 字段 | bit | 对 cursor 的作用 |
|---|---:|---|
| `visible` | 0 / `0x0001` | 不决定是否参加 solid hit test；只参与 effective-visible 与 propagation 判断 |
| `solid` | 13 / `0x2000` | 决定 layer 是否参加 hit test |
| `disablepropagation` | 14 / `0x4000` | 只有当前 layer 与祖先都可见时，命中后才阻断后续传播 |

由此得到以下高置信状态合同：

- `visible=false` 不会使 `solid=true` 的 layer 退出命中测试；隐藏 solid 仍可取得 enter/move/down/up/click，并保留 hover 与 pressed/capture 状态；
- 隐藏 solid 因不满足 propagation gate，不会挡住候选快照中后续命中对象，因此可形成透明交互区；
- visible setter 只改可见状态并触发常规属性变更，没有清除 hover、pressed/capture 的副作用；
- native object 真正销毁时会静默清除 hover 与 pressed/capture 引用，不为失效对象补发 leave/up/click；
- click 依赖同一 pressed/capture identity 完成 down/up 配对；销毁导致的 silent invalidation 必须先于后续 dispatch。

三个轮询 getter 也已闭合到主程序 host：

- `input.cursorWorldPosition` 从 scene 保存的 cursor pixel snapshot 经当前 view/projection 的逆变换得到 Vec3；2D policy 可把 z 强制为 0；
- `input.cursorScreenPosition` 使用同一 snapshot，按当前 canvas/viewport scale 输出像素坐标并根据当前坐标 policy 处理 Y 方向；
- `input.cursorLeftDown` 固定查询 left-button identity，读取 scene 输入记录中的当前布尔状态，其他 button identity 返回 false。

getter 都禁止 global phase，并读取调用时 host state；`CursorEvent` 的 world/local/hit-box 则在 native dispatch 前构造成独立事件快照，二者不能共用一个可变 JS object。当前静态证据仍没有把 event local 坐标的全部 parent/puppet 逆变换、边界容差、多按钮事件或候选快照内的完整前后顺序闭合为跨平台数值合同。

### 6.6 Camera、material、particle、video 与 animation handle

- **camera transforms**：`getCameraTransforms` / `setCameraTransforms` 都拒绝 global evaluation phase。DTO 固定为 `eye`、`center`、`up` 三个 Vec3 和 `zoom`；getter 读取 scene 保存的 base camera record，setter 对四项分别接受缺省，只覆盖实际提供的成员。构造默认是 `eye=(2,2,2)`、`center=(0,0,0)`、`up=(0,1,0)`、`zoom=1`；正交且没有 authored camera 时使用 `eye=(0,0,0)`、`center=(0,0,-1)`、`up=(0,1,0)`，authored camera 字段会覆盖同一 base record。finite/type 错误的 VM 边界和 2D/3D 冲突仍需自有 fixture。
- **material property**：`setMaterialProperty` 按存储顺序遍历 effect 的 material instance record，每个 instance 以 property name 查询自身 metadata，再执行 scalar、Vec2、Vec3 或 Vec4 typed write。scalar 可按 metadata 选择 int/float 转换，带角度单位的字段还会执行 degree-to-radian；缺失或不兼容 property 只使该 instance no-op，不阻断其他匹配 instance。
- **material function**：`executeMaterialFunction` 对缺失名称或空 descriptor no-op；否则按 descriptor-defined ordered record set 依次切换每条 material render record 的 active material/state，立即执行 function，再恢复此前状态。它不是无序广播或跨帧任务。descriptor index 与 authored pass 的完整映射尚未闭合。
- **particle emission**：`emitParticles()` 与 `emitParticles(0)` 都规范为一次 emission，正整数原样传入，负数 no-op；调用使用零时间偏移并进入正常 runtime 共用的 emitter/default-channel/initializer dispatcher，不建立脚本专用粒子路径。静态证据能确认调用时完成 CPU 侧分配与 initializer 流程，不能确认最终 GPU buffer 是否在同一 draw 可见。
- **video handle**：provider 缺失时操作 no-op、getter 返回默认值。`play` 遇到 ended 会先 seek 到 0 再播放，`pause` 只暂停，`stop` 暂停并 seek 到 0；`isPlaying` 同时要求 provider active/playing 且未 ended。非 loop 模式先观察到未结束才 arm，随后首次 ended 只派发一次并解除，重播后可再次 arm；loop 模式以当前时间小于上一帧识别自然回绕并派发 ended。主动 `setCurrentTime` 会清除待派发状态，避免把 seek 误报为 loop end。callback 由 owner 有序保存，经 scene engine 批量派发，owner teardown 后不得存活。
- **animation layer**：`playSingleAnimation` 与普通 `createAnimationLayer` 共用创建/验证/排序路径；配置未解析到已有 animation 时返回空 handle，成功后按 `autosort` / `index` 插入有序容器，再追加 one-shot 标记。evaluator 到达 end 的 frame 先派发该 layer 的全部 ended callbacks，此时 handle 仍存活；同一 frame 的第二遍遍历才移除已标记 layer。显式 `destroyAnimationLayer` 接受 handle identity、非负 index 或 name，name 会删除全部同名匹配；无效 identity、越界 index 和空 name 均 no-op/false，显式 destroy 不冒充自然 ended。
- **Puppet animation layer records（2026-08-02 bounded clean-room 复核）**：现役文档与公开 Animation Mixing 页面只能确认同一 Puppet 可启用多个 animation，不能回答冲突 bone 的合并公式。仅在这一缺口下对 source-index 所列同哈希官方客户端做最小静态核对：loader 把 `animationlayers` 作为有序数组逐条交给 layer 创建路径，每条记录读取 `animation`、`autosort` 与 `index`；create/play 继续复用上述验证、排序和生命周期。静态路径没有恢复 pose conflict、blend weight 或矩阵公式，也没有把它们写入项目合同。`0892e74b` 因此只实现项目自有的 bind-referenced/disjoint-bone additive 子集，任何重叠 bone 或扩展 profile 继续 fail closed；本节不保存地址、伪代码、函数体、payload 或官方算法表达。

这些都是中性生命周期和顺序合同，不证明 MyWallpaperX 已有相应 VM/handle，也不证明动画混合、视频像素、粒子轨迹或 material function 的视觉等价。

### 6.7 仍需动态或自有 fixture 的部分

静态路径不能无歧义确认：

- 全部 19 个事件的全局派发顺序、回调重入与跨帧可见性；
- timer 取消函数是否幂等、delay 下限以及 scene seek 是否影响 scheduler；
- watchdog 阈值、预算与错误传播应如何跨平台取值；
- storage namespace/quota/原子性、asset canonicalization/precache、model-data 精确引用计数；
- camera finite/type 负向行为、material descriptor/pass 完整映射、particle 同 draw 可见性、video provider/error/多屏时钟以及 animation conflict blend/root-motion；
- cursor event-local/puppet 坐标、候选顺序、边界容差、多按钮与 visible/solid/parent mutation 的同帧冲突；
- 未在 §6.4–§6.6 闭合的 handle/API 副作用与同帧冲突语义。

官方 live update traversal 允许 callback 不断尾插新 owner 并延长同一轮；这只形成 owner lifecycle、事件队列、typed writeback、timer、预算、exactly-once destroy 与下一帧准入的区分问题。fake VM、通用 VM 选型、有界队列和总预算属于[现役 SceneScript 目标合同](scenescript-api-coverage.md#11-mywallpaperx-v2-目标运行时合同)与[兼容运行时架构](../runtime-architecture.md)的项目策略；本页不授权其顺序或实现形态。

## 7. 视频、声音、系统媒体与 surface

### 7.1 视频和 Scene Sound 是不同合同

`wallpaper32/64.exe` 都具有 Media Foundation URL/byte-stream source、media session/topology、audio/video renderer activation 与 DXGI device manager 参与者。这支持视频 provider 需要 scene clock、readiness、seek/loop/reset、generation 和 GPU frame 互操作边界，但不提供 A/V 同步、颜色矩阵、range、rotation 或首帧规则。

64 位主程序的 controller 创建与析构路径把视频 producer 的 owner 边界进一步闭合：

- controller 创建时保存宿主 manager，并登记到 manager-owned pointer registry；它不是附着在某张 texture 上、随一次 draw 临时创建的 decoder；
- 初始化链同时建立 D3D11 device、Media Foundation、DXGI device manager 和媒体 engine，预探测 byte stream/source reader 的尺寸、帧率与媒体类型；
- requested-playing、实际 running、frame-ready/dirty 是分开的状态；seek 走 stop → seek → restart，stall recovery 会从当前时间重启并退避；
- controller 的输出侧方法分别承担媒体帧取得/发布、音量同步、原子 take-and-clear 状态和 provider pump/recovery；
- teardown 先停止并等待 worker，再从宿主 registry 退注册，随后释放 output、media engine、DXGI/D3D/MF 资源并执行 Media Foundation shutdown。

固定客户端路径呈现出 **host-owned producer registry + retained playback intent + 独立 frame publication** 的结构，并观察到 teardown 依次停止 worker、退注册、释放 GPU/media。provider/device generation 的项目表示和 teardown 实现只由现役资源/运行时合同规定；最后一轮静态扫描没有无歧义闭合宿主每帧如何遍历 registry，也没有证明 device reset 后由谁恢复 play/rate/loop/seek intent，这两项继续保持未验证。

`mediaextensions64.dll` 经主程序 factory 动态取得，公开/静态边界覆盖 audio device/context、source play/pause/stop/rewind、buffer queue、capture、device pause/resume 和线程化 teardown。它更接近 Sound/device lifecycle，不是通用视频解码器。

对 factory vtable 的完整恢复进一步闭合了资源与播放实例的分层：

```text
resource identity / bytes
  -> reference-counted cached payload
  -> source handle
  -> playing / paused / stopped
  -> stop-if-needed + dispose
```

- payload 按资源 identity/bytes 建立并缓存，释放最后一个引用时才从 cache 移除；
- source handle 由 payload 创建，独立保存 source、duration 与播放状态；状态检查分别对应 playing、paused、stopped，而不是用一个布尔值表达；
- play、pause、stop 显式改写三态；dispose 遇到非 stopped source 时先停止再释放；
- source 参数入口覆盖经全局缩放后的 gain、rolloff factor、reference distance、单 source position 与批量 position；clone 会复制 pitch、gain、position、source-relative、reference distance 和 rolloff factor；
- 这些 cache/source/parameter 操作共享递归 SRW lock、device/context sentinel 和空 source no-op 边界。

主程序的 Sound 参数链还确认，某个 Sound owner 的 `+0x304` 最终写入 source 的 rolloff factor；它与 image-layer 同偏移的 clamp 位没有语义关系。这再次说明偏移只能在明确 owner/vtable/call chain 内解释。

固定客户端把 immutable/cached audio payload、mutable source/voice、显式三态、参数快照和 device state 表现为不同结构，并为 prepare/play/pause/resume/stop/dispose、loop/volume、锁保护更新与 reset 呈现出不同生命周期。它们是项目合同评审的问题清单，不授权复制 OpenAL API，也不直接规定 owner-scoped Sound 的类型边界。静态路径仍没有闭合主程序的完整 provider admission、全局 gain 来源、设备重建时 source 状态恢复或声音 golden。

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

## 8. 静态观察支持的项目合同候选（非实现输入）

本节只归纳可供项目合同评审的关系，不更新任何 `L0-L4` 等级，也不是 implementation checklist。每一项只有在现役项目合同用独立措辞重新定义、配套项目正反 fixture，并按声明需要加入官方动态对照后，才能取得实现授权；未完成该转换时保持 research-context-only：

1. **纹理**：format、purpose、physical/mapped、UV、sampler、alpha/color 与 generation 必须共同进入 identity；`nointerpolation/clampuvs` 分别进入 filter/address policy，cache key 不得只取这两个布尔位；动态写入必须由显式 generation/reprepare 合同承接；
2. **RenderGraph**：condition 先于 admission；ordinary/copy/swap/compose 保持 typed node；copy 是 target operation，swap 改 logical mapping，compose 推进 layer-local full-frame pair；FBO 的 authored extent、fit、scale、unique、clear 与 UV policy 必须分别保真，resource mapping 必须受 effect/reset generation 治理；
3. **Material/shader**：indexed slot 不压缩；default/user/provider/state/variant 有来源可追踪的合并结果；`[PASS]` 是独立 shader metadata，未证明的 2D schedule 不得降级成普通 material draw；
4. **Frame/output**：frame delta、wall date、readiness、surface 与 output mode 分离；
5. **Reset**：scene switch/device/surface/provider completion 受同一 generation 事务治理；
6. **SceneScript**：module、engine、owner 和 event bridge 分层；frametime/runtime/timer 共用 effective delta，timer/audio/storage/callback 与 owner 同寿命；script-record 注册顺序与 render topology 分离，并对 callback mutation 设置预算；
7. **Video/Sound/Media**：三者各有独立状态机，异步结果不能跨 generation 注入；Video 使用 host-owned producer registry，播放意图、实际 running、frame publication 与 device/provider generation 分离，teardown 先停 worker、退注册再释放 GPU/media；Sound 的 cached payload、source handle、playing/paused/stopped 与 device owner 分层，dispose/reset 不能依赖对象析构碰运气；
8. **Particle**：definition、dynamic CP、simulation context、child owner、renderer variant 与递归 teardown 分层，不能把 factory 识别当成执行支持；
9. **Pause/mute**：先按 reasons 与 display eligibility 计算 per-renderer state，再投递线程；两者不能合并为 visibility；
10. **跨架构结论**：结构对应只用于确认合同不是单一 ABI 偶然，不能替代 Windows dynamic trace 或 pixel golden。

当前实现、测试和真实样本证据分别以覆盖台账与运行证据索引为准；本文不证明 MyWallpaperX 已实现上述全部合同。

## 9. 静态深挖收口与后续证据队列

截至 2026-07-31，能直接改变公共架构选择的高价值静态链已经闭合到 parser/resolver/graph、sampler、frame/reset、SceneScript owner/timer/handle、particle dispatcher、Sound source 与 Video host/provider 生命周期。继续逐个追 Media Foundation COM 常量、私有 vtable slot、shader/particle 数学或宽泛标量命中，预期只会增加 Windows 私有实现细节，不能可靠提升项目合同或视觉证据，因此本轮停止扩大 Ghidra 扫描。

仍值得保留、但只有出现具体实现决策或可验证 fixture 时才重新开启的静态问题是：

1. TEX 动态 property 写入到 resource reprepare 的完整触发链，以及其他 sampler 位如何汇入最终 descriptor；
2. copy/swap/history 在 device loss 前后的资源 identity 与持久范围；
3. SceneScript 未闭合高级 handle 的明确冲突顺序；
4. Video 的宿主 registry pump 顺序、device reset 后 retained intent 的恢复 owner，以及 Sound reset 后 source 状态恢复。

以下问题必须由项目自有 fixture、隔离 Windows trace 或像素/声音 golden 回答，不能继续靠反汇编猜测：

- shader/effect 数学、blend factor、write mask、alpha/color-space 与 HDR transfer；
- history 的完整跨帧顺序、copy/共享 target alias 结果、clear 的像素解释与 device-loss 可见结果；
- 粒子 component 公式、随机种子与视觉轨迹；
- SceneScript 全局 event order、预算后的 mutation admission、cursor 精确坐标/顺序、scene-seek timer、storage 持久性与未闭合 API 副作用；
- 视频 A/V 同步、颜色空间、首帧/loop/seek；
- 多显示器策略在所有 Windows 模式下的实际选择。

## 10. 关联入口

- [客户端二进制与第三方依赖取证](client-binary-dependency-forensics.md)
- [场景格式与 RenderGraph](scene-format-and-render-graph.md)
- [Shader source 前置合同与跨后端假设审查](shader-prelude-and-backend-abstraction.md)
- [SceneScript 2.8.42 固定客户端静态取证](scenescript-runtime-implementation-contract.md)（`research-context-only`）
- [运行时系统语义](runtime-systems-reference.md)
- [资料来源与证据索引](source-index.md)
- [覆盖台账](coverage-ledger.md)
- [运行证据索引](runtime-evidence-index.md)
