# Scene 官方语义与实现覆盖台账

> 状态：现役系统汇总；逐项等级以各专项能力表为准
>
> 最近核对：2026-07-27
>
> Scene 实现基线：`a77b875`（生产播放改为原始项目目录直达宿主并在内存构建 `SceneRuntimeInput`；`0ff96e0` 的 strict stock Radial God Rays 及此前 Timeline、16 档音频、Puppet、BC、strict particle child 与 stock 资源子集均包含在该提交祖先中；逐能力落地提交见专项表和运行证据索引）
>
> 最近一次完整快照门：`.codex/scene-runtime-input-full45-20260727/results/report.json`；当前固定回归门：`/private/tmp/mwx-scene-runtime-input-fixed13-20260727-v1/report.json`
>
> 最新运行门：`a77b875` 的同一签名 Debug App 在隔离 root/HOME 下完成原始目录直传完整快照 `45/45` 与固定回归 `13/13`；58 份 Debug runtime evidence 均为 schema 1，旧解释 JSON/preview log residue 0，固定门 stop 后 surface=0。完整门报告/matrix SHA-256 为 `2f3a92e30d906f875a570b56b3c1f87d17b988020626cebab0364a417619b3ac` / `d9ad98be0d27f2ca2d2afa75eff6b04279a917b8756c0fcda364dfdde2607abf`，固定门为 `41336701149c47bcae819a7a5af61a11de8aeb8bb24631ffb59a7fb35353ad4a` / `1cd9ee22ec1c8ccc84d9d2ac9fa37cf9734382c39da43a4ab5710c4b163c0f22`。完整门 particle `110/131`、strict stage 154、chain 21、Godrays 2、graph failed 0；固定门 particle `66/76`、stage 109、chain 14、graph failed 0。完整 Scene 测试 `100/100` 模块通过；代码健康 491 Swift files、44 个锁定历史文件、400 行上限。聚合缺口、视觉边界和签名身份见 [运行证据索引](runtime-evidence-index.md)。

本表把已收集的 Wallpaper Engine 作者语义逐项映射到 MyWallpaperX 当前代码、运行证据和下一道验收门。详细语义仍以同目录专题文档为准；这里回答三个问题：官方是否有这项能力、当前播放器走到哪一级、下一步补什么公共能力。

## 1. 口径

| 等级 | 含义 | 允许的结论 |
|---|---|---|
| `L0 absent` | 当前 Scene 管线没有结构或运行入口 | 未实现 |
| `L1 recognized/preserved` | 能识别声明、保留部分字段或输出诊断 | 已识别，不能宣称可播放 |
| `L2 wired/routed` | 已进入 IR、资源或 Render Graph 路由，但没有可靠执行结果 | 已接线，不能宣称有效果 |
| `L3 executed-degraded` | 有受限执行器和正反测试，仍有明确语义或视觉偏差 | 可用子集，必须同时写明边界 |
| `L4 semantics-verified` | 作者启用、输入、顺序、生命周期和视觉/数值门均与 WE 基准核验 | 该合同可宣称语义兼容 |

系统等级取 schema 保留、作者启用、运行消费、生命周期和语义/视觉门中的最低值，不做平均。某一子集达到 `L3` 不会把同名系统整体升级；`45/45` 当前完整快照门和 `13/13` 固定回归门都只代表各自矩阵通过运行门，不是样本兼容率或 WE 还原率。当前真实目录另有 `3770500543` 因缺少 `scene.pkg` 而未进入可运行矩阵。

当前没有任何完整系统达到 `L4`。官方公开的作者能力已经建立完整索引，但 Wallpaper Engine 没有公开完整稳定的私有 Scene/PKG/TEX 序列化规范，也没有公开 Windows 渲染器实现；未知字段仍须用合法样本、官方 assets 或 Windows golden 继续核验。

## 2. 官方资料覆盖

| 资料面 | 收集状态 | 权威入口 | 仍未知 |
|---|---|---|---|
| Scene 官方页面 | 179 个 `/en/scene/` 页面已建目录并逐页映射到唯一合同 anchor，2026-07-22 经代理核验 | [官方页面全目录](official-page-catalog.md)、[逐页映射](official-page-map.md)、[分组映射](official-page-crosswalk.md) | 官方未来页面变化 |
| 官方 Effect | 45 个用户可见 effect + `_empty` 内部占位已整理 | [内置 Effects 语义全集](effects-reference.md)、[执行覆盖表](effect-execution-coverage.md) | 私有 shader 精确算法和全部历史版本 |
| SceneScript | 官方 `lib.sceneScript.d.ts` VERSION 2.8 已逐 API 建账 | [SceneScript API 覆盖表](scenescript-api-coverage.md) | Windows VM 的非公开行为和预算细节 |
| Scene/Effect/Material/Shader/RT | 作者合同与 IR/executor 状态已拆分记录 | [场景格式与 Render Graph](scene-format-and-render-graph.md)、[Graph/Shader 覆盖表](render-graph-shader-coverage.md) | 完整私有 schema、默认值和所有 combo |
| Particle | 官方组件、子类型和执行阶段已逐项建账 | [粒子组件覆盖表](particle-component-coverage.md) | 未公开 preset 资产内容和平台精确视觉 |
| Timeline/属性/输入/Provider | 官方求值顺序与 target 状态已逐项建账 | [运行输入与属性覆盖表](runtime-input-property-coverage.md) | 私有序列化字段和 Windows 精确数值 |
| Puppet/3D/Lighting/性能/RGB/离线 | 高级对象与产品策略已逐项建账 | [高级对象覆盖表](advanced-object-coverage.md) | 私有资产格式、设备和渲染器内部行为 |
| 资料来源 | 官方、样本、WaifuX、linux-wallpaperengine、当前代码分级 | [资料来源与证据索引](source-index.md) | 第三方实现不能替代官方真值 |

因此，后续一般不再猜“这个能力是什么”；实现前先查上述合同。仍需研究的部分应明确标为私有格式/算法未知，不能用视觉近似反向定义官方语义。

## 3. 系统总表

| 系统 | 当前级别 | 当前真实能力 | 主要缺口 / 升级门 | 批次 |
|---|---|---|---|---|
| PKG/TEX/资源索引 | `L3` | loose/PKG 查找、常见 TEX、内嵌 MP4、诊断式失败；BC1/2/3 单 image 预算内 CPU premultiply，超预算/多 image GPU premultiply；跨 image sprite 当前只裁 authored 首帧作静态 fallback | 完整跨-image sprite animation、旋转 frame、case/symlink/duplicate/多格式边界与完整 VFS golden | B0 |
| Scene IR 与基础层级 | `L3` | 基础对象、顺序、父子 transform/visibility、受限 Puppet 静态 attachment frame 与 animation layer 声明、常见 image/text/solid/particle；作者 `brightness` 随 interpretation v27 进 layer IR，并由 image/solid 通道折进既有 `u.tint` 乘数（随包 292 个 object 中只有 `razer_bedroom` 的 4 个 wave layer 非 1，值为 3.0/4.0），`contentKind == "text"` 的 layer 跳过该乘法，交回 CoreText 栅格化阶段消费同一 key，有 GPU 像素正反门；作者 text layer `anchor`（编辑器 Screen anchor）随 interpretation v28 进 text IR，并与 parallax 折进同一个 layer 平移（随包 5 个 text layer 中 `dino_run` 的 231/177 为 `topright`，其余 3 个为 `none`），有 CPU 几何门与离屏 GPU 覆盖门；作者 `horizontalalign`/`verticalalign` 除了继续喂 CoreText 框内排版，还作为 text layer 的 quad pivot 折进同一个 model 矩阵（排在 `sizeScale` 之后），随包 5 个 text layer 中 `dino_run` 的 231/177 为 `right`/`center`，其余 3 个为 `center`/`center`；作者 text layer 的 `limitrows`/`maxrows`/`limitwidth`/`maxwidth`/`limituseellipsis` 随 interpretation v29 进 text IR，并在 CoreText 栅格化阶段决定换行宽度、行数与省略号（两个数值只在对应开关打开时生效），有逐像素正反门 | 模型、动态 attachment follow、复杂 object component 和全部动态字段；`brightness` 超过 1 的部分只由 render target 精度裁剪，没有 WE 像素标定，也未接 dynamic binding | B0 |
| Utility composition | `L3` | typed composition/project/fullscreen、受限 current prefix 与 `_a` named target | nested/effectful/child、`_b` 数据流、RGB 语义 | B2/B3 |
| 画布/cover/背景 | `L3` | cover 投影和作者声明视差门，未覆盖区域不再暴露灰底 | 多比例、多屏和 Windows 像素基准 | B5 |
| Frame Context | `L3` | host 单一 60 Hz driver；shader/video/particle/parallax 同帧 timing | pause/resume、delta clamp、fixed step、目标 FPS、离线 adapter | B0 |
| Dynamic target/value 与 property binding program | `L3` | 六类 value、主要 target、固定优先级；v22 保存 layer alpha/color、direct text 三字段、strict Local Contrast/Opacity definitions/instructions/effective values；mixed/invalid/SceneScript key 标记重建 | direct text 已有 per-layer generation/stale cancellation；hidden/no-consumer text 与其他 effect constant 仍重建 | **B0/B4** |
| Per-surface dynamic snapshot | `L3` | host 共享 property 输入，每个 surface 独立 evaluation transaction、snapshot 与 generation；相同 payload 不增 generation | pointer/size/provider/Timeline/SceneScript 等 local producer 接入后继续扩充隔离门 | **B0/B4** |
| Atomic live property state/routing | `L3` | layer alpha、纯 solid color、strict Local Contrast strength 与 stock Opacity alpha 先原子求值并直接供 renderer 消费；失败、mixed、SceneScript、unsupported 或无 consumer 时保留整场重建 fallback | 扩展 target 前必须补类型、eligibility、consumer、fallback 和 identity 门 | **B0/B4** |
| Timeline runtime | `L3` | 作者 `animation` 无损进 IR（lane/keyframe/tangent/options/combined 分组/`relative`/`previewvalue`），44 个真实 `scene.json` 的 48 处全部解析成功、0 诊断；纯函数 evaluator 按**绝对 scene time** 求值（Loop/Mirror/Single、`startpaused` 停首帧、端点保持不外推）；编译成 typed `SceneDynamicTargetDefinition` 后经既有 per-surface transaction 写回，`SceneDynamicSource.timeline` 优先级高于 userProperty。真实执行 **28/48**（effect constant 23 + layer alpha 5，散布 9 个样本），其中 mode 为 single 21、loop 7；`3769688830`/`3769364482`/`3028090166` 为正门，`2067939514` 的 `startpaused` 为负门（首帧与半程同值）。preview 日志输出确定性求值样本，不依赖像素归因 | **其余 20/48 全部 fail-closed 且留诊断**：`relative` 10（合成语义未定标）、`maxwidth`/`zoom` 3（无 target）、粒子 `instanceoverride` 7（粒子通路未接）；Bézier tangent 只保真不消费、插值走线性（handle 单位两种解释不等价，未定标）；`wraploop` 7 处按普通 loop 降级执行并记 `wrapLoopIgnored`；Mirror 有 evaluator 与单测但真实样本 0 处执行；Combined Animation 整组拒绝；Animation Event 仍 `L0`；无 Windows golden | **B4** |
| SceneScript presence | `L1` | 只保留对象是否含 inline `script` 的布尔值 | source path/inline source 与绑定 IR | **B0/B4** |
| SceneScript source/VM/API | `L0` | 源码和绑定目标会丢失；无执行器 | source IR、安全 ECMAScript、生命周期、API/events、预算隔离 | **B4** |
| Current pointer | `L3` | view-normalized -> scene world 与 axis-aligned authored layer UV 极窄子集；parallax/受限 effect 消费 | parent/rotation/scale/parallax 逆变换与 effect/control-point/script golden | B0/B4 |
| Previous pointer | `L2` | Frame Context 保存，但 renderer 未消费 | shader built-in 与事件 delta | B0/B4 |
| Pointer buttons/events | `L0` | 无 button/down/up/click snapshot 或 dispatch | 同帧输入队列与 author-off | B0/B4 |
| Audio declarations | `L3` | effect 侧 `AUDIOPROCESSING` combo 与五个 audio 常量已由共享准入层消费；粒子侧 `audioprocessingmode`/`audioprocessingbounds`/`audioprocessingexponent`/`audioprocessingfrequencystart`/`audioprocessingfrequencyend` 按粒子自身 schema 保真解析（此前误用 effect 字段名，`audioprocessingfrequencyend` 被静默丢弃） | 粒子声明可保真不等于可执行；workshop 自定义 audio shader 仍无 IR consumer | B0/B4 |
| Audio frame input | `L3` | 16 频段 × left/right host-shared 快照：系统音频 tap -> `SystemAudioSceneSpectrumAnalyzer` -> `SceneAudioSpectrumInbox` -> `SceneFrameContext`，host 每帧采样一次广播给所有 surface；采集由 consumer 存在性驱动，无 consumer/暂停/锁屏/休眠即停采并归零 | **只做 16 档**（stock effect 只用 `g_AudioSpectrum16*`）；32/64 档随 SceneScript 与 workshop shader 前置一并欠账。频段边界（32 Hz→16 kHz 对数）与 -80 dB 归一化是工程选择，非官方合同，无 Windows 数值 golden | B0/B4 |
| 内嵌视频纹理 | `L3` | TEX 内嵌 MP4 image-layer 播放，消费共享 host time | seek/pause/switch/loop 精确合同及更多容器 | B1 |
| 系统媒体 identity | `L1` | `$mediaThumbnail` typed 引用存在 | producer/consumer、事件、缩略图 generation | B1/B4 |
| Particle runtime | `L3` | 作者 sprite、常见组件、Sprite Trail；`SceneStockAssets.bundle` 保留内置资源的官方相对路径，particle material 按 exact identity 直接查找同路径 TEX，样本本地资源优先，22-key 程序纹理只作 bundle 缺失回退；素材原位替换，后续 consumer 必须复用这些物理路径 | 路径存在不等于执行完整：当前只有 Particle slot 0 是纹理 consumer；逐资产官方通道/mip/atlas/像素 parity 未证明；sidecar metadata 不进入 runtime，spritesheet 序列帧未逐帧播放；bundle 不设目录级库存门 | **B4** |
| Text/Font runtime | `L3` | CoreText 静态栅格、direct property 动态重栅格和部分 font/pointsize/padding/scale；结构门 `79/108` | time/SceneScript/system/media text、Windows baseline/fallback、outline/shadow/effect | B4/B5 |
| Camera Parallax | `L3` | 仅作者开启且非零 depth 时启用，含层级传播/阻断 | WE 数值 golden、camera shake/zoom、3D camera | B5 |
| User Properties | `L3` | 独立窗口、条件、持久化、PNG/JPEG `sceneTexture`；layer alpha、纯 solid color、direct text、strict Local Contrast/Opacity 与受限 X-Ray target 已无重建 live 更新 | unsupported/mixed/SceneScript bindings、Texture Variants、shortcut、跨重启 UI 门；精确 census 见 runtime-input 专项表 | **B0/B1** |
| Typed texture provider | `L3` | layer/named/property identity、status/fallback；静态 resource generation 与 named frame epoch 已分离 | 显式 dynamic generation、metadata、cancel、system/media/video/variant、通用 material、nested/effectful/child | **B1** |
| EffectDefinition/Material IR | `L2` | definition/pass/RT/material/slot hole/combo/constant 可保留并建图；ShaderContract 保存 source identity；material render state 已把随包并存的 `depthtest`/`depthtesting`、`depthwrite`/`depthwriting`、`cullmode`/`culling` 两套拼写归一到同一份 IR，规范拼写共存时优先；pass 级 `alphawriting`（随包 60 处，值域 `default`/`enabled`）与 `usershadervalues`（随包 36 处，`{shader 值名: 用户属性名}`，与 `constantshadervalues` key 不重叠）已 loss-preserving 进 IR 并随 interpretation v26 上线 | 完整 schema、typed shader defaults、condition/function；`alphawriting` 尚未驱动 color write mask，`usershadervalues` 尚无 executor 消费也未让 strict backend fail closed | B2 |
| Bounded effect executors | `L3` | 两个严格 Blur 图、strict stock Local Contrast、exact Workshop Shadow、exact stock Opacity（含 per-effect 遮罩槽，按 `descriptorID` 绑定，官方 `albedo.a *= mask * g_UserAlpha`，遮罩声明后取不到贴图整段拒绝）、Shake、Water Waves、Water Flow、Foliage Sway、Water Ripple、X-Ray、Tint、Pulse 与 God Rays（stock Radial 单指纹族：downsample2→cast→gaussian×2→combine 5-pass/双 half RT，混合链 RT 预算按 extent 折算与运行时字节口径一致）十四类 backend 的 ordered strict chain 与若干受限手写 executor；Pulse/Water Waves/Water Ripple/Tint/Shake 五类按多指纹白名单同时执行 stock 2.8.42 与逐版本 diff 过的 legacy 变体（可折算差异在 plan 侧参数化：基向量 +π 归一、exponent 恒 1、常量子集缺省回填） | 其余官方 Effect、variant、Shake `g_Texture3` 遮罩槽（仍整段拒绝；Tint `g_Texture1` 遮罩已按官方混合权重语义执行）、legacy 指纹与 workshop 自定义 shader 的 audio 驱动实例（stock Shake 两指纹与 stock Pulse `stock2842` 的 `AUDIOPROCESSING` 已执行，见 Effect 执行覆盖表）、label-as-key 与缺 `version`/`replacementkey` 的 definition 变体（definition 白名单欠账）、SceneScript/mixed chain 与 visual golden | B3/B4 |
| Current-frame capture | `L3` | bounded utility prefix capture 可执行 | 通用 capture/extent/format/mask | B2/B3 |
| Named primary target | `L3` | bounded `_a` producer/consumer 可执行 | 通用 authored identity 和依赖环检测 | B2 |
| Named secondary identity | `L2` | registry 区分完整 variant；无 `_b` producer/consumer flow | secondary 数据流、copy/swap/history | B2 |
| Generic FBO command graph | `L2` | target/bind/compose/copy/swap/condition/function 可保留或 blocker；effect-scoped target/lifetime table 已由十二类 strict backend 与 ordered strict chain 消费；同帧 copy/swap 已有严格 plan/runtime 门；显式 unique FBO 的 history seed 已进入 table 初始化；Precise Blur 的 `material -> copy/swap -> material` 白名单拓扑可按 authored nodeIndex 交错执行；exact legacy Blur Precise `compose:true` 两遍语法可归一为单个 full-size 中间 target；exact Shake、Foliage Sway、Water Ripple、重复 Water Waves、`Water Flow -> Opacity` 与 X-Ray 受限前缀均可按作者顺序执行 | 上述 exact profile 为受限 `L3`；generic compose、Refraction scene-background capture、真实 history consumer、condition/function、typed state、跨帧 logical swap 和完整生命周期仍缺失 | B2 |
| History RT | `L2` | `unique:true` framebuffer 可通过读前写 hazard，plan 记录 history seed；缓存 table 首次消费时对 seed texture 做一次 GPU clear，pool 复用与 reset/resize 生命周期继续成立 | 真实 history consumer、跨帧 ping-pong/logical swap、seek/pause/resize/switch/stop 确定性和真实样本正向 GPU 门 | B2 |
| Authored shader path/source identity | `L1` | material path 与 ShaderContract stage/source/raw hash/canonical identity 已安全保存 | 尚无 include expansion、translation、compile 或 executor | B2 |
| Shader source/include/annotation/declaration contract | `L1` | 完整 source、include reference、annotation raw/structured value、uniform/attribute/varying declaration 已 loss-preserving 保存并诊断；combo 标记覆盖随包并存的 `[COMBO]`/`[COMBO_OFF]`/`[OFF_COMBO]`/`[COMBO_DISABLED]` 四种拼写，`[PASS]` 的非 JSON operand 原样保留且不误报 malformed | typed default/combo consumer、include expansion、macro/permutation preprocessor、stage link/translation/compile | B2 |
| Arbitrary custom shader execution | `L0` | 自有受限 Metal shader 不等于作者 shader | 通用受控翻译/映射、安全与产品门 | P3 |
| Puppet asset identity | `L2` | MDLV0021/0023 mesh、受限 MDLV0023 + MDLS0004 + MDAT0001，以及三来源 MDLA0006/full-TRS/80+84-byte skin weights 已交叉核验并 fail closed；v25 保存 authored animation layers | 更多 MDL/MDLA 版本、完整辅助轨道与超出已验证形状的数据 | P2 |
| Puppet runtime | `L3 executed-degraded` | bind-pose 重组（`8bac86e`）、静态 attachment（`49ee89a`）和严格单可见 clip 的 loop/fixed-step/LBS 播放（`f1ee79b`）；混合、动态 visibility 或畸形声明整层回退 bind pose | 插值、非 loop mode、rate/blend/mixing、动画 attachment follow、constraint/IK/physics/events、Windows golden | P2 |
| 2D lighting/Scene HDR | `L0` | layer Bloom 近似不等于官方 lighting/HDR pipeline | PBR maps、light、shadow/reflection/volumetric、scene post | P2 |
| 3D model/camera/physics | `L0` | 无 Scene 3D runtime | model/node/material/skeleton/attachment/camera/physics | P3 |
| RGB device integration | `L0` | 无 Scene RGB provider/output | macOS 策略、授权和 fail-closed | P3 |
| Debug PNG readback | `L2` | benchmark 可生成 GPU 截图，并按 Steam preview 比例中心裁切、输出非阻断分项指标和并排图 | 只允许同一样本跨提交比较；不能跨样本排名、替代 Windows golden 或标成 offline bake | P3 |
| Offline bake | `L0` | 无固定步进产品 adapter | fixed clock/seed、provider replay、编码器 | P3 |
| Stop/switch lifecycle | `L3` | surface=0 和部分资源释放门 | VM/provider/GPU 细粒度计数、系统暂停与长稳 | B0-B4 |
| Performance budgets | `L0` | 无统一 CPU/GPU/显存/帧时长期阈值 | 30 分钟交互、2 小时 soak、多屏和压力门 | B0-B4 |

## 4. 官方 Effect 覆盖摘要

45 项的作者条件、执行通道、公共依赖、当前证据和下一验收门统一维护在 [官方 Effect 执行覆盖表](effect-execution-coverage.md)。汇总为 `L1=23`、`L2=4`、`L3=18`、`L4=0`；所有 `L3` 都是表内明确限定的 profile，不是 WE parity。内部 `_empty`、Workshop `gradient_color` 和 layer Bloom 另列，不能替代任何官方 Effect。

## 5. Particle 子系统覆盖

逐 initializer、operator、renderer、control point 和 child 类型的证据见 [粒子组件覆盖表](particle-component-coverage.md)。本节只保留系统级摘要，不能替代逐项表。

| 官方组件 | 当前级别 | 当前边界 | 升级门 |
|---|---|---|---|
| General 字段 IR | `L2` | 常见 material、maxcount、starttime 与 world-space/perspective/frame-blend system flags 可保留 | 五种 author allow-override gate 仍为 `L0`；补显式 wire schema |
| General 执行子集 | `L3` | max count、prewarm、perspective、frame blend 分支可消费 | runtime change、prewarm cap 定向门与 WE 数值门 |
| Emitter schedule | `L3` | rate、instantaneous、duration、one-per-frame | delay/periodic 和 WE 时间门 |
| Sphere Random emitter | `L3` | 可执行子集 | 全参数、distribution golden |
| Box Random emitter | `L3` | 可执行子集 | 全参数、distribution golden |
| Layer Image/其他 emitter | `L1` | 名称可诊断，字段和执行不足 | 独立 fixture 和作者条件 |
| 已接 initializer 子集 | `L3` | lifetime/size/velocity/color/alpha/angular velocity 常见路径 | 每一项 range/distribution/seed golden |
| Rotation Random initializer | `L2` | 字段与 simulation 分支已接线；无最终 rotation 断言 | renderer orientation 数值门 |
| 未接 initializer | `L1` | turbulent/control-point/remap 等可诊断或字段不足 | 逐项 fixture 与创建时语义 |
| 已接 operator 子集 | `L3` | movement/angular、alpha/size/color change、部分 oscillate | timestep/curve/phase 数值门 |
| 未接 force/operator | `L1` | attract/turbulence/vortex 等明确 unsupported | control-point/world-space 力场 |
| Sprite renderer | `L3` | 作者纹理和程序化静态遮罩子集 | 全 material/blend/lighting/atlas |
| Sprite Trail | `L3` | 受限 trail 执行 | orientation/length/atlas/曲线精度 |
| Rope/Rope Trail declaration | `L1` | 结构/诊断不足 | topology、constraint 和 material IR |
| Rope/Rope Trail execution | `L0` | 无 renderer | geometry/history/lifecycle |
| Static control-point subset | `L2` | static local offset/instance override 有分支；缺最终位置断言 | emitter 位置、空间与 parent golden |
| Dynamic control-point declaration | `L1` | 可识别或诊断 object/cursor/script 需求 | typed target 和 binding IR |
| Dynamic control-point execution | `L0` | 无 object/cursor/script runtime | 坐标转换与每帧更新 |
| Child asset graph | `L3` | 可递归发现并为 strict child 建立 runtime template 至层级 2：depth-one 每声明一个 template，depth-two 仅 event 触发且按 parent asset path 去重展开一次；missing/cycle/depth-three/nested-static fail closed | runtime cycle lifecycle、depth-two static 语义与 teardown 压力门 |
| Child execution/events | `L3` | deterministic birth/natural-death queue；strict static/default-static child 在有限 authored local origin 创建一次，仍要求零 angles、单位 scale、无 CP、probability=1，且目标定义自身含 event children 时不再被 nested 阻断；`eventspawn`、natural-`eventdeath` 与 identity/no-CP `eventfollow` strict child 独立模拟、绘制、跟随和回收，depth-two event child 以 (parent system, 粒子) 为 owner、事件跨层按帧串行传播；spawn/death 系统的 rate 发射窗口有界（authored duration 优先，否则以 child 粒子最大寿命为本地近似窗口），rate-only event child 不再无限累积；每 system 1,024 粒子，每 root runtime 每深度 64 systems、跨两层 128 systems/131,072 capacity | static angles/scale、event transform、collision/delete、CP/value inheritance、depth-two static、stop/switch 压力门 |
| Built-in textures | `L3` | 20 个精确 key；`particle/fire/fire1`、`particle/light/light_shafts_0`、Flare 三纹理、`particle/nature/snow` 与 `particle/smoke/smoke2` 等为项目自建确定性遮罩，不等于官方资产 | `rain_drops_sheet` 等剩余高频 key、atlas metadata、多纹理 material |
| World-space declaration | `L1` | 明确 `worldSpaceUnsupported` | 不能冒充执行 |
| World-space execution | `L0` | 无 camera/parent transform runtime | 多屏和 parent 语义 |
| Collision declaration | `L1` | 可诊断但无 solver | shape/depth/response/event IR |
| Collision execution | `L0` | 无 solver | fixed step 与 event dispatch |
| Audio-response declaration | `L1` | 五字段按粒子 schema 保真进 IR，emitter/turbulent velocity/operator 三类共用同一声明类型；启用后一律报 `audioResponseIgnored`（operator 此前无诊断、会静默按无音频路径模拟） | 声明保真不等于可执行；默认值官方未公开，IR 层不内置 |
| Audio-response execution | `L0` | frame snapshot 已可用，但**求值公式与调制目标无证据**：粒子侧无 shader 源码，第三方参考实现对应代码是 `audioAmplitude = 0.0` 的 TODO 占位，其默认值在 emitter/initializer 两处自相矛盾 | 需 Windows golden 或官方公开算法；在此之前不得按推测实现 |
| Sprite Sheet | `L3` | Sequence/Random frame/frame blend 子集可执行 | 全 atlas metadata、loop/edge 和多纹理 material |
| Static instance overrides | `L3` | alpha/size/lifetime/rate/speed/count/brightness/normalizedColor 有运行断言 | 完整类型/range 门 |
| Direct color/control-point position override | `L2` | parser/simulation 分支已接线，最终值门不足 | direct color 与 CP position/angle 断言 |
| Dynamic instance overrides | `L1` | wrapper 只诊断 | typed live target、generation 和逐帧应用 |
| Material/blend | `L3` | `genericparticle` 首纹理、additive/translucent 子集；additive 按官方 CPU premultiply + `(SRC_ALPHA, ONE)` 等效合同(作者 alpha 即 additive 强度),unsupported shader/blend 尚可能回退 | 先严格 fail-closed，再补多纹理/combo/render state 与 additive 的 Windows 像素标定 |
| Fixed step/seed/maxcount | `L3` | fixed simulation step、deterministic seed、maxcount 有运行门 | pause/discontinuity 与 WE 数值 golden |
| Turbulent velocity initializer | `L3` | 非音频 profile 消费 forward/right/up、phase、scale、time 与 speed range；audio profile 继续 fail closed——frame snapshot 已可用，缺的是粒子侧求值公式证据 | Windows WE 固定 seed 数值/视觉 golden；audio 分支另需官方算法或 golden |
| Delta clamp/prewarm cap | `L2` | 代码有上限分支，缺定向预算断言 | 长帧和高 prewarm 压力门 |

当前固定矩阵可见粒子为 `66/76`，完整矩阵为 `110/131`（REFRACT 材质层 fail closed 不计入）；`3088601835` 为 `19/19`，其中 Snow root layers `513/534` 已执行，static `snowstormfog` child 也已由真实缓存门确认在两层生成实例，matrix-code 两层随 `b86db59` 解除 nested 阻断进入执行。child 不增加 root loaded-layer 计数。`3769364482` 为 `3/3`、`3757555836` 为 `7/7`、`2974757317` 为 `3/3`（含 matrix 头层 85705），`3750813609` 是 `7/9`，后者另外两层因 world-space 不支持而保持 fail closed；`3724289844` 已不在当前真实目录。这些数字只度量对应矩阵实际加载的 layer，不代表粒子组件覆盖率。

## 6. 动态运行系统覆盖

### 6.1 Timeline 与 SceneScript

| 能力 | 当前级别 | 升级门 |
|---|---|---|
| Particle `animation` wrapper presence | `L1` | 与正式 Timeline IR 分开，只作为动态值诊断 |
| Timeline object/property target | `L3` | layer `alpha` 与 effect constant 已 typed 编译并写回（28 处）；`origin`/`angles`/`scale` 有 target 但随包 10 处全带 `relative`，整批 fail-closed；`maxwidth`/`zoom` 与粒子 `instanceoverride` 无对应 target |
| Keyframe/value/tangent | `L2` | 帧号/值/双侧 handle/`lockangle`/`locklength` 已无损保真；求值只走线性，tangent 未消费——handle 的「帧偏移」与「归一化段长」两种解释不等价（`2067939514` 段在 frame=3.75 处分别约 0.767 / 0.970，线性 0.5），需视觉定标后才能宣称 Bézier |
| Loop/Single | `L3` | 按绝对 scene time 求值，真实执行 loop 7、single 21；single 到末帧保持末值不回绕，loop 跨周期同相位，有单测与真实样本双证 |
| Mirror | `L2` | evaluator 与单测已覆盖三角波折返，但随包 6 处 mirror 全落在被 `relative` 拒绝的 layer transform 上，真实样本 0 处执行 |
| start paused | `L3` | 6 处执行且恒停首帧；`2067939514` 为负门——无 VM 时不存在能调 `play()` 的主体，自动播放会偏离作者意图 |
| wrap-loop | `L1` | IR 保真（随包 9 处声明），执行时按普通 loop 降级并记 `wrapLoopIgnored`（7 处）；官方未公开首尾平滑算法 |
| `relative` 合成 | `L1` | IR 保真（10 处），编译期整条拒绝；推断语义为「作者基值 + 动画值」，未取得官方定义也未做视觉验证 |
| Combined Animations | `L1` | `options.parent`/`children` 的双向 key 引用已保真（随包唯一实例为 `3768229922` object 55 的 `origin`↔`zoom`）；组内成员须共用持有方 clock，分组语义未实现，整组 fail-closed |
| Animation Events | `L0` | frame crossing、loop、同 layer script dispatch |
| Script presence | `L1` | 仅保存对象是否含 inline `script` 的布尔值 |
| Script source/binding IR | `L0` | 当前 inline/source path/绑定目标会丢失 |
| ECMAScript VM | `L0` | 安全隔离、确定性 budget、异常处理 |
| `init`/`update` 生命周期 | `L0` | 每屏实例、同帧 snapshot、stop teardown |
| `engine` globals/Date/Math | `L0` | frame context 和受控 host API |
| user/cursor/audio/media events | `L0` | generation queue、顺序、异常隔离 |
| component/object/particle API | `L0` | typed handles、只允许作者目标、失效语义 |
| timer/timeout/interval | `L0` | scene-time scheduler、pause/resume/预算 |

### 6.2 User Properties

完整控件和 target 计数见 [运行输入与属性覆盖表](runtime-input-property-coverage.md)。2026-07-22 的 21 样本 census 为 424 definitions、952 bindings、195 条 conditional bindings；本轮 26 样本完整运行门没有重做这项专项 census，因此不把旧计数冒充当前全集。layer alpha 73 条已编译并由当前 image/solid/text consumer live 执行；layer color 73 条全部指向 solid，其中 25 条属于纯 color key 可 live，`3122339805:basecolor` 的 48 条因同键还含未支持目标继续重建；exact Local Contrast strength 1 条与 `2902406982` 的 stock Opacity direct binding 已由 strict consumer live 执行。SceneScript Opacity candidates 继续计入 unsupported/fail-closed，不冒充 direct binding。

| 类型/行为 | 当前级别 | 当前边界或升级门 |
|---|---|---|
| Catalog/bindings | `L3` | 2026-07-22 的 21 样本专项 census、format 22 binding program 与受控 fallback；direct text content/point-size/color、Local Contrast/Opacity live，mixed/hidden/no-consumer/SceneScript fail closed |
| `color` | `L3` | UI/持久化/solid-only live consumer；补颜色空间、non-solid 与全部 target |
| `slider` | `L3` | min/max/default/step/fraction/precision UI；layer alpha、exact Local Contrast strength 与 exact stock Opacity alpha 已 live，其他 target 依 consumer 决定重建 |
| `bool` | `L3` | 条件/部分 target；不得按名称自动启用 effect |
| `combo` | `L3` | option value/条件；补全部 authored target |
| `textinput` | `L3` | 可编辑/持久化；有效可见 direct text consumer 可无重建更新，其他 target 仍重建 |
| `texture`/`scenetexture` | `L3` | PNG/JPEG picker/bookmark/static consumer 极窄子集；补 video/variant/general material |
| `usershortcut` | `L0` | parser 当前归为 unsupported；需 macOS 授权和安全降级 |
| group/order/condition | `L3` | 独立窗口已支持；补嵌套/全条件和负向门 |
| reset/default/override | `L3` | layer alpha reset/override 可原子 live 提交；texture bookmark 或非 live key 仍重建；补跨重启 UI 门 |
| Texture Variants | `L0` | 补 schema、checkbox/combo 选择和 provider identity；脚本不得切换 |
| property update event | `L0` | typed snapshot 后再派发给 SceneScript |

### 6.3 Text、Audio、Media 与 Provider

| 能力 | 当前级别 | 当前边界或升级门 |
|---|---|---|
| 静态文字内容 | `L3` | CoreText 可见；结构样本 `79/108` |
| 字体解析/fallback | `L3` | 解析顺序 alias → 包内文件 → 客户端自带（stock）→ 缺失，路径安全判定优先于后三层。官方 `systemfont_*` 别名共 8 个（`arial`/`verdana`/`segoe`/`sansserif`/`consolas`/`comicsans`/`cambria`/`calibri`），`consolas` 缺失时退到 Menlo 保住 fixed-pitch。客户端 `assets/fonts` 的 15 个官方名字全部物理位于 `SceneStockAssets.bundle/assets/fonts`：8 个原版报 `stockBundled`；7 个替代字体按官方文件名读取，报 `stockSubstituted` + `stockFontSubstituted:<category>`。包缺失或损坏才报 `stockApproximation`。**等级仍为 `L3`**：7 个替代字形的轮廓、advance 与 kerning 不是官方字形，8 个原版也无 Windows 栅格化逐像素对照，见 [E-TEXT-FONTREF](runtime-evidence-index.md#e-text-fontref) |
| point size | `L3` | 官方 `pointsize` 是 300 DPI 磅值（`lib.sceneScript.d.ts` 的 `ITextLayer`："Size of the font in points for 300 DPI"），栅格像素字号取 `pointsize * 300 / 72`，随包 `dino_run` 两个记分标签的作者 size `780x291`/`390x145` 四个数字逐位复现（此前的 `round(pointsize * 4)` 低 4%）。字号仍被夹在 `[1, 1024]` px，作者值 ≥ 245.76 磅起偏离官方换算，这是本地纹理保护不是官方合同；数值判据来自本机只读探针而非仓库内自动门，也无 Windows 逐像素对照，见 [E-TEXT-POINTSIZE](runtime-evidence-index.md#e-text-pointsize) |
| baseline/alignment | `L2` | 基线（baseline）本身未处理，`blockalign` 未解析；对齐字段的执行边界见下一行，溢出裁剪见 overflow limits 行 |
| text alignment pivot（`horizontalalign`/`verticalalign`） | `L3` | 官方取值域 left/center/right × center/top/bottom 全部参与 quad pivot：origin 落在被命名的那条边上，缺省与未知取值退回几何中心；同一组字段继续喂 CoreText 框内排版。离屏 GPU 门下 `dino_run` 231/177 的 `horizontalalign: right` 从"右边缘各自被裁在最后一列"变成"右边缘齐平在 `origin.x` 对应的第 254 列"（216→396 px、54→102 px），三个 `center`/`center` preset 摆位不变。框仍是作者 `size`+`padding` 的固定外框，不按运行时文本重新测量；`padding` 与 pivot 的交互随包全为 `padding: 0`，无反例可校；无 Windows 像素标定，见 [E-TEXT-PIVOT](runtime-evidence-index.md#e-text-pivot) |
| screen anchor（text layer） | `L3` | 官方 10 个取值全部解析并每帧折进 layer 平移，`none`/缺省/未知取值不偏移；离屏 GPU 门下 21:9 的 `dino_run` 记分标签从 0 覆盖像素回到与 16:9 完全一致的 396 px 右上角；只有 text layer 携带该字段，Windows 像素标定见 [E-TEXT-ANCHOR](runtime-evidence-index.md#e-text-anchor) |
| overflow limits（`limitrows`/`maxrows`/`limitwidth`/`maxwidth`/`limituseellipsis`） | `L3` | 五个字段随 interpretation v29 进 text IR 并由 CoreText 栅格化消费：`maxwidth`（官方注释 "Max width in pixels"）压窄换行宽度并跟随栅格降采样，`maxrows` 之外的行整行丢弃，`limituseellipsis` 在末行补 `…` 并按组合字符序列回退直到不越界。两个数值只在对应开关打开时生效——语料中的 452 个 text layer 有 393 个 `limitwidth: false` 且全带编辑器默认 `maxwidth: 500`，其中 79 个作者宽度已经超过 500，无条件套用会把它们错误压窄；正反门都锁了这一条。窄框按 `horizontalalign` 落在内容框内，避免 center/right layer 整块左移。像素门：两行内容在 `maxrows 1` 后只剩首行（4910→2190 覆盖像素、行区间 `[8,44]`），硬换行 `"A\nB\nC"` 在 `maxrows 2` 后只剩前两行（1767→1229），省略号把末行右边界从 133 推到 177，`maxwidth 100` 把 400 px 框里 274 px 的单行折成两行（右边界 ≤ 66），同一个 `maxwidth 100` 在开关关闭时仍保持 274 px 单行。外框仍是作者 `size`+`padding` 的固定框，不按运行时文本重新测量（见 text alignment pivot 行）；`maxwidth` 仍被夹在内容宽以内；官方省略号的回退粒度、字符与位置无 Windows 逐像素对照；`blockalign` 仍未解析，见 [E-TEXT-LIMITS](runtime-evidence-index.md#e-text-limits) |
| outline/shadow/text effects | `L1` | 字段或 effect 可保留，未形成完整绘制链 |
| property-driven text | `L2` | 通过 Scene 重建应用；需 per-frame target 和按 layer 纹理 generation |
| SceneScript clock/text | `L0` | 先有 VM、Date 和 typed text target |
| Audio declaration | `L3` | effect 与粒子两套 schema 分别保真解析；两者字段名不同，粒子无 `audioamount` |
| Audio 16 bins | `L3` | left/right host-shared 快照，静音/无权限/停采集稳定归零，可注入；频段与归一化为工程选择 |
| Audio 32/64 bins | `L0` | stock effect 不用；随 SceneScript `registerAudioBuffers` 与 workshop shader 前置一并欠账 |
| Audio effect consumer | `L3` | 仅 stock Shake（`whitePhaseFallback`/`timeOffsetCombo`）与 stock Pulse（`stock2842`）的 `AUDIOPROCESSING` 分支；legacy 指纹、workshop 自定义 audio shader、带 user binding 的 audio 常量全部 fail closed |
| Audio particle consumer | `L0` | 声明已保真但求值公式无证据；见 5 节 Audio-response execution |
| Audio script consumer | `L0` | 前置 VM 未闭合 |
| Sound layer | `L0` | 补 sound content IR、播放、volume 和生命周期 |
| Embedded MP4 frame | `L3` | image-layer 子集；不同于系统媒体 provider |
| Media status/metadata/timeline | `L0` | injectable snapshot 和 lifecycle |
| Media thumbnail identity | `L1` | `$mediaThumbnail` typed reference 已分类；不等于 producer |
| Media thumbnail producer/consumer | `L0` | typed texture provider/generation/fallback |
| Layer/named target provider | `L3` | bounded current-frame graph；补 nested/effectful/child |
| Named secondary identity | `L2` | registry 已区分完整 `_b` variant |
| Named secondary producer/consumer | `L1` | executor 识别后拒绝；需真实数据流 |
| Property file provider | `L3` | PNG/JPEG 静态 consumer 极窄子集；补通用 material/video/variant |
| Video/system provider identity | `L1` | enum/reference 脚手架存在 |
| Video/system generic producer | `L0` | 尚无通用 provider lifecycle |
| Generic material slots 0...7 | `L2` | 保留 hole/候选；补按 shader combo 的通用 consumer |

## 7. 高级对象与输出覆盖

逐 Puppet、Model、Lighting、产品预算、RGB 和 offline 项见 [高级对象覆盖表](advanced-object-coverage.md)。

| 能力族 | 当前级别 | 最小可用门 |
|---|---|---|
| Puppet asset identity | `L2` | 更多 MDL/MDLA 版本、辅助轨道和完整资源图 |
| Puppet mesh/bones/weights runtime | `L3` bind pose + 静态 attachment + 严格单 clip CPU LBS | 插值/mixing、GPU skinning、动态 attachment follow、层级/遮罩 |
| Puppet spring/rigid/rope/wind | `L0` | fixed timestep solver、events、确定性 golden |
| 2D PBR maps | `L0` | normal/roughness/metalness/emissive slot 与 color space |
| Point/spot/tube/directional light | `L0` | light IR、排序、坐标和至少一条渲染路径 |
| Shadow/reflection/volumetric | `L0` | RT graph、depth/occlusion、预算和像素门 |
| Official Scene Bloom target identity | `L1` | typed scene target 已定义；binding 尚未分类 |
| Official Scene HDR/Bloom post runtime | `L0` | HDR targets、tone mapping、scene ordering |
| Workshop layer Bloom approximation | `L3` | 受限 layer effect pipeline；不得冒充 Scene post |
| 3D model/node/material | `L0` | asset loader、scene graph、camera、PBR material |
| Skeleton/attachment/animation | `L0` | animation evaluator、skin/attachment 生命周期 |
| 3D physics | `L0` | fixed timestep、collision、determinism |
| Custom shader reference/path/source identity | `L1` | material path 与 authored stage source/raw hash/canonical identity 已保存；不代表执行 |
| ShaderContract/source contract | `L1` | source/include/annotation/declaration/stage 已保留；仍需 typed AST、preprocessor、translation/compile 与 executor |
| Custom shader execution | `L0` | 需受控编译/映射、uniform/slot/render-state 与安全产品合同 |
| RGB device | `L0` | macOS 产品策略、授权、设备 adapter |
| Debug PNG readback | `L2` | 可生成 benchmark 截图证据；不得标成 offline bake |
| Offline bake | `L0` | 与实时共用 IR/evaluator/render graph，固定时钟和编码输出 |

## 8. Coverage-first 实施批次

| 覆盖批次 | 开发计划映射 | 目标 | 完成判据 |
|---|---|---|---|
| **B0 Contract/Runtime Kernel** | `S3 第 1-4 项` | v22 binding program、per-surface transaction、atomic state、alpha/solid-color/direct-text/strict Local Contrast/Opacity consumer 与 rebuild fallback 已闭合 | 新 live target 继续要求 compiler、consumer、原子失败与不换 surface/window；pause/fixed-time 单列 |
| **B1 Provider Core** | `S2 第 5 项 + S3` | dynamic text 已完成 per-layer generation、stale cancellation、last-ready fallback；frame registry 双代已完成 | 把 status/metadata/cancel/teardown 推广到 Texture Variants、video/system/media 与 material candidate；不含 nested graph source |
| **B2 Graph Resource Runtime** | `S2 第 1-5 项` | strict Blur、stock Local Contrast、exact Workshop `shadow_____________`、exact stock Opacity、exact stock Shake 与 ordered strict effect-chain 已消费 target table；cache/resize/reset、整链原子 allocation、D7 ShaderContract IR v1、BGRA/RGBA/RG/R8 format、exact shader fingerprint、同帧 copy/swap foundation、受限 history seed/clear、Precise Blur 两种 material-command interleave 与 exact legacy compose 归一化已完成；generic compose/scene-background、真实 history consumer 与 typed shader defaults/built-ins/state 未完成 | read/write、RT lifecycle、slot/combo/state 和 resize/switch/stop 门；下一批用 preview 并排图和同样本分项变化验证画面收益 |
| **B3 Provider-Graph Integration** | `S2 第 5-6 项` | nested/effectful/scene-background source、通用 material consumer、45 Effect 严格 profile family | B1+B2 均完成后接入；不得新增 effect-name 视觉旁路 |
| **B4 Feature Breadth** | `S3-S4` | direct dynamic text、Timeline 28/48 typed target 子集、16 档 audio 输入与 stock Shake/Pulse consumer 已完成；SceneScript core、system/media text、cursor/media、其余 Timeline/audio 与按依赖排序的 particle breadth 仍待推进 | 每族正向、默认关闭、unsupported、determinism 和 lifecycle 门 |
| **B5 Fidelity** | `S2-S4` 广度完成后 | 字体、视差、粒子、常用 Effect 与 WE Windows golden 对齐 | 固定输入逐像素/数值阈值、性能预算、长稳和多屏门 |
| **Advanced** | `S5` | Puppet、2D light/HDR、3D、arbitrary custom shader、RGB、offline bake | 每个系统有完整 IR/runtime/lifecycle/product gate 后再升级 |

研究可以并行，产品执行不能倒置：B0 live-property、direct dynamic text generation、Timeline 的受限 typed target、16 档 Scene audio 输入与 stock Shake/Pulse consumer、B2 ordered strict chain、Workshop Shadow、stock Opacity、exact stock Shake/Foliage Sway/Water Ripple/Water Waves/Water Flow/X-Ray/God Rays、同帧 copy/swap foundation、受限 history seed/clear、Precise Blur 两种 material-command interleave 与 exact legacy compose 归一化已合龙；stock 资源子集、非音频 turbulent velocity、strict static/default-static/eventspawn/natural-eventdeath/eventfollow child（`b86db59` 起层级 ≤ 2）、持续/混合/duration child emitter、root child aggregate budget、有限 static origin translation，以及超预算/多 image BC1/2/3 的 GPU premultiply 与静态首帧 fallback已进入公共 runtime。unsupported Effect/Timeline/粒子/SceneScript 形态继续 fail closed。当前完整门为 154 stage/21 chain/0 failed，固定门为 109 stage/14 chain/0 failed；混合链纹理预算按实际 target extent 折算，超过默认 96 MiB 时仍在规划阶段整链拒绝。样本自带 preview 是当前第一视觉依据，人工检查 `3770462923` 的签名 App 截图为非黑画面，Day/Date 文字可见 Radial God Rays，车身和构图正常；该截图与 WaifuX MP4 都不能替代 Windows WE 动态/像素 golden。下一代码批仍须从开发计划和专项缺口重新选择，不从本次 Godrays 正门外推通用 shader 或 Effect 兼容。

## 9. 更新规则

1. 每次 Scene 能力提交必须更新本表对应行和精确边界；只更新开发流水账不算完成。
2. 升级到 `L2` 必须有结构/路由测试；升级到 `L3` 必须有实际执行正例、作者关闭反例、失败降级和生命周期门；升级到 `L4` 必须有官方行为或 Windows golden。
3. 新发现的官方能力先补 [官方页面全目录](official-page-catalog.md)、[页面能力映射](official-page-crosswalk.md) 和专题语义，再进入本表；私有字段按 [资料来源与证据索引](source-index.md) 标证据等级。
4. 最新矩阵报告、测试总数、签名 App 身份以现役计划、路线图、本表头和运行证据索引为主答案；其他含“当前/现役/下一步”的被引用文档由语义同步测试锁定同一 baseline/report/route，历史评估不得反向覆盖。
5. 开发开始顺序：先看本表选择最低公共依赖，再查专题合同和 source index，最后查看样本命中；不得先凭截图写视觉特判。
6. 总表只允许单一 `L0` 到 `L4` 等级；若同一能力同时存在 IR 与 executor 子集，必须拆成两行或下沉专项表。
7. 每行至少要能追溯到专项表中的代码、测试和运行证据；只有 parser 或结构时不得写成执行支持。
