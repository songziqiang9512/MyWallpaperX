# Scene 官方语义与实现覆盖台账

> 状态：现役系统汇总；逐项等级以各专项能力表为准
>
> 最近核对：2026-07-31
>
> Scene 实现基线：`c73aa0b0`（`69cc7f01` 保留 FBO `width`/`height`/`fit`/`scale` 的独立与组合声明，并让 allocation 与 2048² preflight budget 共用 override -> fit -> scale -> floor/min-1 算法；`7866dbc0` 建立普通文件 generation/revision 复核；`e7797c97` 与 `137dd86a` 收紧粒子 shader/renderer fail-closed；`c73aa0b0` 只准入 string/array 的精确透明零 FBO clear，并在 target 首次创建或重建后执行一次初始化。generic executor、非零 clear、未知 metadata 与未证形态继续失败关闭）
>
> 最近完整快照门：对应 `df9e3ef3` 源码的最终签名 Debug App 在 2026-07-30 的 45 样本隔离副本上运行 `.codex/scene-authored-material-annotation-full45-20260730-v2/report.json`，**45/45 PASS**、image texture **451/451**、particle **127/130**、strict stage/chain **310/56**、authored shader **2**、Foliage Sway **17**、Water Flow **14**、Water Waves **25**、Water Ripple **11**、Godrays **16**，graph succeeded/failed layer **159/0**、failed frame、drawable miss 与 sample residue 均为 0。报告/full matrix SHA-256 为 `d59ce8112787197ebe76609356e0ef95532d8ef5ab4fa58290452563c707bbe4` / `bc92b3886c1e4f82e53f5f1a211fe0a21e1bbb17580d61d7704b1adc6b933e7e`。particle 缺口是 `3088601835:550/558` 与 `3750813609:200` 的 `cullmode=normal` 被现役 typed-state 合同有意拒绝，矩阵分别锁定 **17/19** 与 **8/9**，不是本批 shader 回归。历史 fixed13 仍为 `.codex/scene-fixed13-ropetrail-20260729-v1/report.json` 的 **13/13 PASS**，没有在当前构建上重跑；两门互不替代。
>
> 最新聚焦门：`0fc38b59` 的最终签名 Debug App 对隔离 `2974757317`、`3299228616` 运行 `/private/tmp/mwx-scroll-targeted-20260731.Zbe0UC/run-final/report.json`，**2/2 PASS**；loaded ratio 均为 1，Scroll/authored shader 均为 `0/0`。297 的 Scroll 被前置 unsupported Simple Audio Bars 阻断；329 的 utility capture 只成功 layer 151，空 composition layer 387 保持 `unsupportedEffects`，ready/after 人工核对未见错误硬矩形。报告/matrix SHA-256 为 `23339bdf81eb728ff7773d553482342914d9a86129f27dd87fcf253e204e0ab5` / `625358487ad8c1ea7faf394c758718ccd9c2638f991fed890fdb0017dcd67c05`；App executable SHA-256 `d47a426cdf732359d776383f82e344a0bdd000e606795b83d45d43f662d9afb3`、CDHash `ca57a7ba81ecf6750860ba2f81afe7c4e331121b`，签名前后 verified。三组 exact profile 的正向执行由 planner GPU fixture 锁定时间变化与正 X 向左滚动；当前 full45 语料没有真实 Scroll 正执行样本，因此这不是用户可见解锁或 Windows parity。该 Scroll 批次定向 **80 tests OK**，没有重跑 fixed13/full45。
>
> 最新公共合同门：`c73aa0b0` 的 effect graph / target plan / target table / offscreen pool / Cursor Ripple / chain planner / execution / framebuffer GPU / Local Contrast 聚焦门合计 **101 tests OK**；Scene **150 modules ALL OK**，代码健康 678 Swift files / 44 locked legacy / 400-line limit，`script/build_and_run.sh verify` 无新增 actor warning并通过。最终签名 Debug App 对隔离 `3299228616`、`3767343314` 运行 `.codex/scene-authored-zero-clear-targeted-20260731-v4/report.json`，**2/2 PASS**、loaded/particle ratio 均为 1，failed frame、drawable miss 与 sample residue 均为 0；报告/full matrix SHA-256 为 `798b62644def58da93e251ec7baef9a70e9ad530d603b00fe216e3efdf8147a3` / `bc92b3886c1e4f82e53f5f1a211fe0a21e1bbb17580d61d7704b1adc6b933e7e`，App executable SHA-256 `6b9758a5d49d21950c6e66427b6e3529899ce31b393f2f29ad033244d323d9b4`、CDHash `09bdb6dafa3d19536d44e15d1355953543c15165`，签名前后 verified。三样本首轮 v2 中 `2974757317` 仍因现役 full matrix 的 utility/authored-graph 与 particle 期望陈旧而失败，实际 loaded ratio 1、failed frame/drawable/residue 为 0；该失败与本次 clear 路径无因果证据，现场保留且不计为 PASS。本批没有重跑 fixed13/full45；真实门只证明已有 strict FBO/history consumer 在共享初始化改动后无回归，不是非零 clear、arbitrary FBO、Fluid/Motion Blur 或 Windows parity。Generic FBO command graph 仍为 `L2`。

本表把已收集的 Wallpaper Engine 作者语义逐项映射到 MyWallpaperX 当前代码、运行证据和下一道验收门。详细语义仍以同目录专题文档为准；这里回答三个问题：官方是否有这项能力、当前播放器走到哪一级、下一步补什么公共能力。

## 1. 口径

| 等级 | 含义 | 允许的结论 |
|---|---|---|
| `L0 absent` | 当前 Scene 管线没有结构或运行入口 | 未实现 |
| `L1 recognized/preserved` | 能识别声明、保留部分字段或输出诊断 | 已识别，不能宣称可播放 |
| `L2 wired/routed` | 已进入 IR、资源或 Render Graph 路由，但没有可靠执行结果 | 已接线，不能宣称有效果 |
| `L3 executed-degraded` | 有受限执行器和正反测试，仍有明确语义或视觉偏差 | 可用子集，必须同时写明边界 |
| `L4 semantics-verified` | 作者启用、输入、顺序、生命周期和视觉/数值门均与 WE 基准核验 | 该合同可宣称语义兼容 |

系统等级取 schema 保留、作者启用、运行消费、生命周期和语义/视觉门中的最低值，不做平均。某一子集达到 `L3` 不会把同名系统整体升级；`45/45` 当前完整快照门和 `13/13` 历史 fixed13 都只代表各自矩阵在对应实现上通过运行门，不是样本兼容率或 WE 还原率。当前真实目录有 45 个数字目录，本轮 source manifest `skipped=[]`，全部进入可运行矩阵。

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
| PKG/TEX/资源索引 | `L3` | loose/PKG/stock 查找、常见 TEX、内嵌 MP4、诊断式失败；PKG extraction 以 package/content SHA 和 exact file set 校验损坏/陈旧 cache，单次读取包体；同一 surface 复用 TEX parse 与 device texture，本机普通文件以 canonical path/size/mtime/device/inode/ctime 区分 generation，并在 image/TEX/video 读取或发布前后复核同一 revision；metadata 不可得或非普通文件失败关闭；PNG/JPEG、raw/embedded format 0 与 BC1/2/3 的九类 typed purpose（premultiplied color、straight albedo、generic preserved、mask、noise、flow、phase、normal、depth）进入独立 cache/upload identity，全部 33 个 Effect 辅助纹理调用已显式选用途；唯一 Blend color 预乘，其余 32 个按当前 purpose 保持源通道，其中 3 个仍是 generic preserved；data 图片只接受原尺寸、无 decode 映射、integer packed、明确非预乘 alpha 或无 alpha（skip）且使用受控 32-bit byte order 的 RGB(A/X) provider，并归一为 RGBA；其他 layout/预乘/缩放 fallback 失败关闭，避免把隐藏 RGB 静默改写；Water Flow flow/phase 与 Standard Blur mask 已从同一 source generation 原子取得 identity、purpose、实际 physical/已验证 mapped size、UV transform、sampler 和 pixel format；Shake flow/phase/mask、Foliage Sway mask/noise、Water Ripple mask/normal、Depth Parallax R8 depth 与 exact legacy Blend overlay 共九槽进一步经共享 authored `0...7` binding，把每个 texture 与各自 candidate 的 generation/metadata 原子绑定；普通 PNG/JPEG property color 与 authored TEX 均发布 typed candidate，非法尺寸/变换、错误 slot/purpose/format 与 clamp-border 均失败关闭；跨 image color sprite 当前只裁 authored 首帧作静态 fallback | 跨进程 extraction lock、跨网络文件系统或粗粒度/陈旧 ctime 下的强内容证明（当前无 content digest）、完整跨-image sprite animation、旋转 frame、受支持 decoder 的 straight-RGBA 来源与 Windows 通道 golden、BC5 consumer/encoding、未迁移 Effect 与 generic material slot 的候选 population/readiness、system/media/variant 动态 generation、case/symlink/duplicate/多格式边界及完整 VFS golden | B0 |
| Scene IR 与基础层级 | `L3` | 基础对象、顺序、父子 transform/visibility、受限 Puppet 静态 attachment frame 与 animation layer 声明、常见 image/text/solid/particle；Scene loader 与 descriptor admission 双重拒绝重复 authored object ID，把排序后的冲突 ID 作为 blocking 诊断并沿 launch error 保留具体原因，避免下游 `Dictionary(uniqueKeysWithValues:)` runtime trap；image/solid 作者 `alignment` 随 Scene JSON 进入 layer IR，并以独立于 text alignment 的 quad pivot 放进 `sizeScale` 之后，支持 center/top/right/bottom/left 与四角、缺省/未知值保持中心。44 份已解包真实 Scene 中 16 个样本声明 135 次，52 次为非中心；作者 `brightness` 随 interpretation v27 进 layer IR，并由 image/solid 通道折进既有 `u.tint` 乘数（随包 292 个 object 中只有 `razer_bedroom` 的 4 个 wave layer 非 1，值为 3.0/4.0），`contentKind == "text"` 的 layer 跳过该乘法，交回 CoreText 栅格化阶段消费同一 key，有 GPU 像素正反门；作者 text layer `anchor`（编辑器 Screen anchor）随 interpretation v28 进 text IR，并与 parallax 折进同一个 layer 平移（随包 5 个 text layer 中 `dino_run` 的 231/177 为 `topright`，其余 3 个为 `none`），有 CPU 几何门与离屏 GPU 覆盖门；作者 `horizontalalign`/`verticalalign` 除了继续喂 CoreText 框内排版，还作为 text layer 的 quad pivot 折进同一个 model 矩阵（排在 `sizeScale` 之后），随包 5 个 text layer 中 `dino_run` 的 231/177 为 `right`/`center`，其余 3 个为 `center`/`center`；作者 text layer 的 `limitrows`/`maxrows`/`limitwidth`/`maxwidth`/`limituseellipsis` 随 interpretation v29 进 text IR，并在 CoreText 栅格化阶段决定换行宽度、行数与省略号（两个数值只在对应开关打开时生效），有逐像素正反门 | effect/pass/material/target duplicate、模型、动态 attachment follow、复杂 object component 和全部动态字段；image/solid alignment 尚无 Windows 逐像素 golden；`brightness` 超过 1 的部分只由 render target 精度裁剪，没有 WE 像素标定，也未接 dynamic binding | B0 |
| Utility composition | `L3` | typed composition/project/fullscreen、受限 current prefix 与 `_a` named target；exact composition Clipping Mask 和 `Clipping Mask -> static Opacity` 共用完整 chain/单 backward dependency 门 | effectful/nested/child provider、project/child/multi-dependency consumer、SceneScript/dynamic alpha、weighted hidden profile、generic material、`_b` 数据流与 RGB 语义 | B2/B3 |
| 画布/cover/背景 | `L3` | cover 投影和作者声明视差门，未覆盖区域不再暴露灰底 | 多比例、多屏和 Windows 像素基准 | B5 |
| Frame Context | `L3` | host 单一 60 Hz driver；shader/video/particle/parallax 同帧 timing；Scene pause 冻结 scene time 和 frame index，resume 首帧 `frameTime=0` 且不补暂停长帧；Debug benchmark 结构化记录 startup、callback、drawable、encode、CPU/GPU 分位数，缺失/非法事件失败关闭 | delta clamp、fixed step、目标 FPS、系统 pause 真实运行门、长期阈值、离线 adapter | B0 |
| Dynamic target/value 与 property binding program | `L3` | 六类 value、主要 target、固定优先级；v22 保存 layer alpha/color、direct text 三字段、strict Local Contrast/Opacity definitions/instructions/effective values；mixed/invalid/SceneScript key 标记重建 | direct text 已有 per-layer generation/stale cancellation；hidden/no-consumer text 与其他 effect constant 仍重建 | **B0/B4** |
| Per-surface dynamic snapshot | `L3` | host 共享 property 输入，每个 surface 独立 evaluation transaction、snapshot 与 generation；相同 payload 不增 generation | pointer/size/provider/Timeline/SceneScript 等 local producer 接入后继续扩充隔离门 | **B0/B4** |
| Atomic live property state/routing | `L3` | layer alpha、纯 solid color、strict Local Contrast strength 与 stock Opacity alpha 先原子求值并直接供 renderer 消费；失败、mixed、SceneScript、unsupported 或无 consumer 时保留整场重建 fallback | 扩展 target 前必须补类型、eligibility、consumer、fallback 和 identity 门 | **B0/B4** |
| Timeline runtime | `L3` | 作者 `animation` 无损进 IR（lane/keyframe/tangent/options/combined 分组/`relative`/`previewvalue`），44 个真实 `scene.json` 的 48 处全部解析成功、0 诊断；纯函数 evaluator 按**绝对 scene time** 求值（Loop/Mirror/Single、`startpaused` 停首帧、端点保持不外推）；编译成 typed `SceneDynamicTargetDefinition` 后经既有 per-surface transaction 写回，`SceneDynamicSource.timeline` 优先级高于 userProperty。真实执行 **28/48**（effect constant 23 + layer alpha 5，散布 9 个样本），其中 mode 为 single 21、loop 7；`3769688830`/`3769364482`/`3028090166` 为正门，`2067939514` 的 `startpaused` 为负门（首帧与半程同值）。preview 日志输出确定性求值样本，不依赖像素归因 | **其余 20/48 全部 fail-closed 且留诊断**：`relative` 10（合成语义未定标）、`maxwidth`/`zoom` 3（无 target）、粒子 `instanceoverride` 7（粒子通路未接）；Bézier tangent 只保真不消费、插值走线性（handle 单位两种解释不等价，未定标）；`wraploop` 7 处按普通 loop 降级执行并记 `wrapLoopIgnored`；Mirror 有 evaluator 与单测但真实样本 0 处执行；Combined Animation 整组拒绝；Animation Event 仍 `L0`；无 Windows golden | **B4** |
| SceneScript property binding IR | `L1` | 文档级 IR 无损保存 inline `source`、owner、完整 JSON target path、`scriptproperties`、authored fallback 与 JSON value type；覆盖正式取证的 scene general、object transform、layer visibility、effect visibility、effect-pass constant 五类位置，单 wrapper 的 `script + user` 冲突诊断并拒绝；既有 layer 顶层 binding 继续随 descriptor/cache 传递，旧 cache 缺字段仍可解码 | nested/未知 owner 不提升；file/module、schema-resolved Vec/value type、handle、VM 与 lifecycle 仍缺 | **B4** |
| Exact native text-script profiles | `L3 bounded` | 三个 source SHA + 完整 property shape 双重准入；6 样本 16 个有效可见 clock/day/date binding 每帧进入 typed snapshot 与动态文字 consumer，未知/变异 profile fail closed | 不执行 JavaScript，不开放 `Date`/engine/lifecycle/handle/event；其余 38 个可见 text-script 实例仍只诊断，见 [E-TEXT-SCRIPT](runtime-evidence-index.md#e-text-script) | **B4** |
| Exact native SceneScript 64-band Audio Bars profiles | `L3 bounded` | 两个 raw source SHA 与完整 binding/property/layer/asset/shader/render-state 合同双重准入；复用 host 64 档左右声道，逐 bin 求算术平均并以单纹理 64 draw 执行；未知或变异 profile 整体 fail closed | 不执行 JavaScript，不开放 `registerAudioBuffers`、`AudioBuffers`、`createLayer`、`ILayer` 或 dynamic-layer lifecycle；renderer instance 不等于 Scene layer；无同步非零音频或 Windows golden，见 [E-SCENESCRIPT-AUDIO-BARS](runtime-evidence-index.md#e-scenescript-audio-bars) | **B4** |
| Generic SceneScript VM/API | `L0` | 无 ECMAScript VM、通用 file/module loader、host object/API bridge 或事件/lifecycle runtime | 完整 source/binding/value-type IR、安全 ECMAScript、生命周期、API/events、预算隔离 | **B4** |
| Current pointer | `L3` | view-normalized -> scene world 与 axis-aligned authored layer UV 极窄子集；parallax/受限 effect 消费 | parent/rotation/scale/parallax 逆变换与 effect/control-point/script golden | B0/B4 |
| Previous pointer | `L2` | Frame Context 保存，但 renderer 未消费 | shader built-in 与事件 delta | B0/B4 |
| Pointer buttons/events | `L0` | 无 button/down/up/click snapshot 或 dispatch | 同帧输入队列与 author-off | B0/B4 |
| Audio declarations | `L3` | effect 侧 `AUDIOPROCESSING` combo 与五个 audio 常量已由共享准入层消费；exact Workshop `2084198056/Simple_Audio_Bars` 的 16/32/64 数组与三个严格 combo tuple 有独立 consumer；粒子侧 audio schema 保真解析 | 粒子声明可保真不等于可执行；其他 Workshop audio shader、SceneScript `AudioBuffers` bridge 和未准入 combo/指纹继续失败关闭 | B0/B4 |
| Audio frame input | `L3` | 16/32/64 频段 × left/right host-shared 快照：系统音频 tap -> 单次 FFT 的 `SystemAudioSceneSpectrumAnalyzer` -> `SceneAudioSpectrumInbox` -> `SceneFrameContext`，host 每帧采样一次广播给所有 surface；采集由 consumer 存在性驱动，无 consumer/暂停/锁屏/休眠即停采并归零 | stock/effect profiles 消费 16/32/64；两个 exact native property-script profile 消费 64 档并在 renderer 内派生算术平均。频段边界、归一化和平滑是工程选择，非官方合同；native average 不等于 SceneScript `AudioBuffers` bridge/object | B0/B4 |
| 内嵌视频纹理 | `L3 bounded` | TEX 内嵌 MP4 image-layer 以共享 `SceneFrameTiming` 映射 item time；launch-scoped registry 按 layer/source/device 复用 provider，surface rebuild 保留连续 item time，pause 保帧、resume 不补暂停时长，按成功 publication 增 content generation，同 frame 去重并拒绝 stale/mismatched publication，stop 释放 player/output/cache/临时文件；真实样本证明启动、连续非黑画面和 stop | seek、真实系统 pause/screen hot-plug 运行门、loop 首帧/首帧黑场策略、codec/device-loss 恢复、variant/generic material consumer 与 Windows A/V parity | B1 |
| 系统媒体 identity | `L1` | `$mediaThumbnail` typed 引用存在 | producer/consumer、事件、缩略图 generation | B1/B4 |
| Particle runtime | `L3` | 作者 Sprite、常见组件、Sprite Trail，以及严格单 renderer、Screen orientation、renderer world-space 关闭的 RopeTrail 子集；RopeTrail 要求 finite `length`，`segments` 缺省 4 且只准 1...8，可选 `fadealpha`，以 fixed-step/prewarm snapshot 和 live particle ID 保存有界轨迹，复用现有 TEX、blend 与 strict REFRACT pipeline。`e7797c97` 让 material shader executor admission 与 blend/state 分离，custom 或缺失 shader 只诊断 `unsupportedShader` 并在 root/child 公共路径失败关闭；`137dd86a` 让显式空 `renderer: []` 不再被当作 implicit Sprite，沿 `missingSpriteRenderer` 公共路径 fail closed。项目准入预算为 `length <= 4`、`maxcount <= 512`、`maxcount × segments <= 4096`，不是官方数值边界。其余既有 root/child、TEX sampler/mip、Random/Box/Oscillation/Turbulence、strict REFRACT 与静态 world-space 子集不变 | Rope 仍未执行；RopeTrail 的 subdivision、UV scale/scroll、animated TEX、非 Screen/world-space、multi renderer、`fadesize`、死亡尾迹、pause/seek/reset 与 whole-scene 聚合预算未实现。上述 RopeTrail 几何、fade 与预算都是有界 clean-room 合同；官方没有公开数值默认值、Length 单位、节点/插值/接缝或精确 UV，仍无 Windows golden。粒子 live override、动态 world-space transform、Lighting、sidecar nominal geometry/rotated/trimmed atlas 等缺口不变；custom shader executor 仍缺失，不因此提升兼容等级 | **B4** |
| Text/Font runtime | `L3` | CoreText 静态栅格、direct property 动态重栅格、exact clock/day/date native profile 和部分 font/pointsize/padding/scale；动态内容在 `limitwidth=false` 时按 intrinsic size 扩框并贯穿 capture/effect/final quad；结构门 `79/108` | 通用 SceneScript/system/media text、Windows baseline/fallback、outline/shadow/effect；动态扩框无 Windows 像素 golden | B4/B5 |
| Camera Parallax | `L3` | 仅作者开启且非零 depth 时启用，含层级传播/阻断 | WE 数值 golden、camera shake/zoom、3D camera | B5 |
| User Properties | `L3` | 独立窗口、条件、持久化、PNG/JPEG `sceneTexture`；layer alpha、纯 solid color、direct text、strict Local Contrast/Opacity 与受限 X-Ray target 已无重建 live 更新；同一 property texture 可按消费者建立 premultiplied generic/Blend candidate 与 preserved-channel X-Ray identity；exact legacy Blend slot 1 的 property candidate 优先，缺失时回退 authored asset，候选与 UV/sampler/format 同代进入 renderer；exact Simple Audio Bars `Bar Color` 与 relocated 16-band profile 的 `Opacity` 已有 typed compiler/snapshot/GPU consumer | Audio Bars 尚无真实 live override 门；unsupported/mixed/SceneScript bindings、Texture Variants、shortcut、跨重启 UI 门；精确 census 见 runtime-input 专项表 | **B0/B1** |
| Typed texture provider | `L3` | layer/named/property identity、status/fallback；静态 resource generation 与 named frame epoch 已分离；本机普通文件 generation 还携带 device/inode/ctime，cache hit、candidate、TEX 与 video source publication 均复核完整 revision，metadata 不可得时不发布；direct text 与 embedded MP4 使用显式 content generation publication，frame registry 拒绝 stale generation、同代换纹理和 publication/texture 不匹配；Water Flow flow/phase、Standard Blur mask、static plain/effectful base image、bounded REFRACT normal 与 Depth Parallax R8 depth 已用共享 typed candidate 原子携带 generation、purpose、actual physical/mapped、UV、sampler 与 pixel format；静态 base candidate 无论 direct、inline 还是 offscreen/authored-effect 路由，都在最终 GPU split 复核 texture identity/purpose/UV/sampler/format；其上新增公开 authored `0...7` 的共享 slot-binding 原子，Shake 1/2/3、Foliage Sway 1/2、Water Ripple 1/2、Depth Parallax 1 与 exact legacy Blend 1 共九个 bounded 槽进一步原子携带 slot、identity/generation、purpose、完整 UV、sampler、format、mip/resolution/texel；Blend 的 PNG/JPEG property 与 authored TEX 共用最终 ready candidate 选择，已选 candidate 不合合同时失败关闭；TEXB0003 embedded image 按 payload-class 尺寸合同准入 | system/media/variant、通用异步取消、跨网络/粗粒度 metadata 的 content digest、其余 Effect 与 generic material 的 slot population/readiness、effectful/nested/child provider、sprite rotation、BC5 与 clamp-border parity | **B1** |
| EffectDefinition/Material IR | `L2` | definition/pass/RT/material/slot hole/combo/constant 可保留并建图；ShaderContract 保存 source identity；material render state 已把随包并存的 `depthtest`/`depthtesting`、`depthwrite`/`depthwriting`、`cullmode`/`culling` 两套拼写归一到同一份 IR，规范拼写共存时优先；pass 级 `alphawriting`（随包 60 处，值域 `default`/`enabled`）与 `usershadervalues`（随包 36 处，`{shader 值名: 用户属性名}`，与 `constantshadervalues` key 不重叠）已 loss-preserving 进 IR 并随 interpretation v26 上线；共享 `SceneMaterialRenderState` 现在同时保留五项 raw 值并把当前语料观测到的 blend/depth/cull/alpha 值编译为 typed enum，未知或不完整状态返回 nil，resolved material 不再丢失 `alphaWriting`；受限 authored shader 已消费 uniform 声明同行的精确字符串 `material` 键来定位静态常量 | 完整 schema、typed shader defaults、condition/function 与通用 Metal state translator/cache 仍缺；精确 constant-key 映射不消费 annotation default/UI metadata、sampler slot 或 provider readiness；`alphawriting=default` 只保真并在受限粒子路径作为准入值，尚无通用 color write mask 映射；`usershadervalues` 尚无通用 executor 消费 | B2 |
| Bounded effect executors | `L3` | 两个严格 Blur 图、strict stock Local Contrast、exact Workshop Shadow、exact stock Opacity、exact Scroll authored source、Shake、Water Waves、Water Flow、Foliage Sway、Water Ripple、strict stock Depth Parallax、X-Ray、Tint、Pulse、God Rays、modern static Shine、Cursor Ripple、exact single-texture Blend、identity-only Transform、exact Simple Audio Bars、strict zero-distortion stock Fisheye、strict Linear/DirectDraw/Gradient Light Shafts 与 exact Workshop Clipping Mask 共二十四类 bounded backend 的 ordered strict chain；Light Shafts 保留作者 perspective quad、radius/noise/scale/feather/speed/intensity 等参数，以项目独立的持续双侧多光束近似执行；严格终止 Iris 可作为无独立 draw 的已验证内联后缀衔接旧版 Water/Foliage 链；Shake/Foliage/Water Ripple/Depth Parallax 的 mask/noise/normal/depth 已按 effect `descriptorID` 分离，Foliage modern/legacy 两个 exact 指纹均逐 stage 准入；exact Foliage 完整链可从匹配 typed utility kind 的 composition/project/fullscreen current-frame capture 执行；`0a0c67ad` 进一步让无 child、单 backward dependency、完整 chain 的 exact composition Clipping Mask 与 `Clipping Mask -> static Opacity` 进入同一 capture/binding 原子；33 个 Effect 辅助纹理调用均显式声明上传用途：mask 16、noise 6、flow 2、phase 2、normal 2、depth 1、generic preserved 3、premultiplied Blend color 1；Water Flow flow/phase 与 Standard Blur mask 复用共享 typed candidate；Shake 1/2/3、Foliage Sway 1/2、Water Ripple 1/2、Depth Parallax 1 与 exact legacy Blend slot 1 又复用共享 slot-binding 原子并把 candidate TEX sampler 实际送入各自 pipeline；Blend 的 property candidate 优先、缺失 property authored fallback 由同一最终选择器完成；Cursor Ripple apply/simulate 只接受 `normal/disabled/disabled/nocull/enabled`，combine 只接受同 tuple 加 alpha unspecified；受限 authored shader 只接受 `normal/disabled/disabled/nocull/unspecified`，Scroll 的未注解 framebuffer slot 只在三组完整 profile 下推断，state 随 plan 进入 pipeline cache identity；一次 launch 的 immutable effect pipelines 按需构造并跨 surface/rebuild 复用，失败缓存 | Fisheye 只接受 exact `center=(0.5,0.5)`、`distortion=0`、`size=1.2`、`BACKGROUND=0`，不代表非零变形；Iris 仅接受精确终止无独立输出后缀，不代表通用 Iris executor；Light Shafts 的 Radial/Corner/Color/mask/non-direct-draw 与 exact 动态/像素语义仍缺；Depth Parallax 只接受单 image/effect/pass、slot 1 R8 depth、静态 `scale/sens/center` 与 quality 0/1/2，项目位移系数 `0.04` 不是官方数值合同，mask、动态 binding、其他拓扑/state/combo 与整场方向视觉门仍缺；typed utility source 只开放 exact Foliage 完整链，不代表任意 project/composition Effect；Scroll composition、其他 Effect/variant、legacy/dynamic/`COPYBG` Shine 与其完整 mixed chain、Cursor Ripple 完整 mixed chain、其他 composition effect consumer、SceneScript/dynamic alpha、非 identity Transform、其他 Blend/Audio Bars mode、任意 include/combo/material texture，以及上述 Cursor/authored-shader exact tuple 之外的 render state、`alphawriting=default`、动态/递归控制流、SceneScript/mixed graph 与 Windows visual golden；binding carrier 保留完整 UV，但当前五个 bounded consumer 只准各自已证 axis-aligned 子集，Foliage noise/Water Ripple normal 还要求 identity；rotation/translation、clamp-border、BC5、动态 generation、未迁移 Effect 与 generic material slot 继续失败关闭；pipeline repository 未证明单屏启动加速，真实双屏运行门仍缺 | B3/B4 |
| Current-frame capture | `L3` | bounded utility prefix capture；普通完整 capture 仍要求无 child/dependency，exact composition Clipping Mask 可在无 child、单 backward dependency 且完整 chain 每 stage 显式允许时执行 | 通用 composition/nested capture、extent/format/mask、SceneScript/dynamic alpha 与 scene-background | B2/B3 |
| Named primary target | `L3` | bounded `_a` producer/consumer 可执行；composition capture 与 dependency plan 共用显式可执行 consumer 集合 | 通用 authored identity、effectful/nested/child provider 和更多 dependency topology | B2 |
| Named secondary identity | `L2` | registry 区分完整 variant；无 `_b` producer/consumer flow | secondary 数据流、copy/swap/history | B2 |
| Generic FBO command graph | `L2` | target/bind/compose/copy/swap/condition/function 可保留或 blocker；FBO `width`/`height`/`fit`/`scale` 现按独立字段保真并支持组合形态，公共 extent resolver 依次执行单轴/双轴 override、fit 不放大、scale divisor、floor/min-1，allocation 与 2048² preflight budget 共用该算法；`c73aa0b0` 又让 string/array 的精确 `[0,0,0,0]` clear 进入 logical target，并与 history seed 共用首次创建/重建后一次性 GPU 初始化；effect-scoped target/lifetime table 已由 bounded strict backend 与 ordered chain 消费；同帧 copy/swap、Cursor Ripple exact 非 unique history 白名单、Precise Blur material-command interleave 与 legacy compose 归一化已有严格门 | 上述 exact profile 为受限 `L3`；非零/畸形 clear 继续失败关闭，composed extent 仍没有 generic material/FBO executor 或真实正向 consumer；particle REFRACT 使用独立的前序 framebuffer snapshot，不代表 generic FBO 已接 scene-background；generic compose、Effect Refraction、condition/function、通用 render-state translator/cache、未映射 state、通用跨帧 logical swap 和完整生命周期仍缺失 | B2 |
| History RT | `L3 executed-degraded` | 既有 `unique:true` history seed/clear 仍成立；Cursor Ripple 严格白名单允许 exact `_rt_EightBuffer2` 非 unique 读前写，两个 `fit 256|512` RGBA8 target 在跨帧 table 中轮转；`c73aa0b0` 将 authored transparent-zero clear 与 history seed 合并为同一只执行一次的初始化事务，重建新 table 后重新初始化，普通下一帧不重复 clear；真实 GPU 门验证移动注入、静止续波与白色 collision mask 阻断，三个真实样本执行成功 | 只覆盖 Cursor Ripple 两组完整指纹；点击注入、pause/seek 固定步进、通用跨帧 copy/swap、其他 history effect 与 Windows 动态/像素 golden 仍缺 | B2 |
| Authored shader path/source identity | `L3 executed-degraded` | material path 与 ShaderContract identity 保真；严格单 effect/单 material、无 include/combo/material texture、typed `normal/disabled/disabled/nocull/unspecified`、framebuffer sampler-only 子集可经有界 GLSL frontend 翻译、编译并执行；静态常量可按 uniform 名或其声明同行的精确字符串 `material` 键读取，二者同时存在或 alias 冲突时拒绝；stock 2.8.42、Workshop `3302578859`/`3387825383` 的 exact Scroll 完整匹配时可把唯一未注解 `g_Texture0` 推断为 framebuffer，动态 repeat/speed、额外 slot、composition 或任一指纹差异均拒绝；state 随 plan 进入 pipeline cache key，并在 pipeline/encoder 边界再次核对；solid 使用 drawable 投影 extent，`3141421197` 与 `3768020435:389` 已有真实正门，Scroll 三 profile 目前只有 GPU 正门 | include/preprocessor、非 framebuffer slot、exact Scroll 之外的未注解 sampler、additive/translucent 或 alpha enabled/default/unknown 等其他 render state、FBO/多 pass、动态 user/timeline uniform、annotation default/slot/provider、更多语法与 Windows golden | B2 |
| Shader source/include/annotation/declaration contract | `L2` | 完整 source/include/annotation/declaration 保真；受限 framebuffer-only frontend 已消费 stage link、静态循环预算、typed uniform layout、同一 capture source 的 `g_TextureNResolution.xy/zw`、time/pointer/matrix、静态常量及 uniform 同行 `material` constant-key 映射；这不是 typed annotation schema 或 material candidate 驱动的逐槽 binder | include expansion、macro/permutation、完整 GLSL、combo/default/condition、逐 material slot candidate 与任意 sampler/render-state consumer | B2 |
| Arbitrary custom shader execution | `L0` | 上述严格 framebuffer-only 单 pass 子集不等于 arbitrary shader | 通用受控翻译/映射、安全、资源分级与产品门 | P3 |
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

45 项的作者条件、执行通道、公共依赖、当前证据和下一验收门统一维护在 [官方 Effect 执行覆盖表](effect-execution-coverage.md)。按逐行单值现状汇总为 `L1=18`、`L2=3`、`L3=24`、`L4=0`；Fisheye 的 `L3` 只指 zero-distortion/background-off exact profile，Transform 的 `L3` 只指 identity-only exact profile，Depth Parallax 的 `L3` 只指 exact stock 单 image/effect/pass 与 R8 depth 子集，所有 `L3` 都是表内明确限定的子集，不是 WE parity。内部 `_empty`、Workshop `gradient_color` 和 layer Bloom 另列，不能替代任何官方 Effect。

## 5. Particle 子系统覆盖

逐 initializer、operator、renderer、control point 和 child 类型的证据见 [粒子组件覆盖表](particle-component-coverage.md)。本节只保留系统级摘要，不能替代逐项表。

| 官方组件 | 当前级别 | 当前边界 | 升级门 |
|---|---|---|---|
| General 字段 IR | `L2` | 常见 material、maxcount、starttime 与 world-space/perspective/frame-blend system flags 可保留 | 五种 author allow-override gate 仍为 `L0`；补显式 wire schema |
| General 执行子集 | `L3` | max count、prewarm、perspective、frame blend 分支可消费 | runtime change、prewarm cap 定向门与 WE 数值门 |
| Emitter schedule | `L3` | rate、instantaneous、duration、one-per-frame | delay/periodic 和 WE 时间门 |
| Sphere Random emitter | `L3` | 可执行子集 | 全参数、distribution golden |
| Box Random emitter | `L3` | zero/absent `distancemin` 的各轴按 `±abs(max)` 围绕 origin 采样；非零 min/max 保留作者区间路径 | directions/sign、反向范围与 Windows distribution golden |
| Layer Image/其他 emitter | `L1` | 名称可诊断，字段和执行不足 | 独立 fixture 和作者条件 |
| 已接 initializer 子集 | `L3` | lifetime/size/velocity/color/alpha/angular velocity 常见路径；finite nonnegative exponent 以 `pow(U,e)` 施加到 scalar、vector 各轴和 color 共用插值因子 | 默认/非法/极值分布、WE RNG/seed golden |
| Rotation Random initializer | `L2` | 字段与 simulation 分支已接线；无最终 rotation 断言 | renderer orientation 数值门 |
| 其他未接 initializer | `L1` | control-point/remap 等可诊断或字段不足 | 逐项 fixture 与创建时语义 |
| 已接 operator 子集 | `L3` | movement/angular、alpha/size/color change、部分 oscillate 与非音频 Turbulence；Oscillate Alpha/Size/Position 按单粒子 normalized lifetime 解释 frequency；Position 从 birth-phase 基线计算波形、按当前/上一时相差值叠加，并消费 axis mask 数值权重 | 默认 phase/system seed、curve 与 Windows 数值/轨迹门 |
| Turbulence operator | `L3 executed-degraded` | 非音频 profile 按作者顺序消费 mask/phase/scale/time scale/speed/blend/fixed dt/static speed override，非有限写入失败关闭；audio profile 零执行 | Windows 固定 seed 轨迹/像素 golden；audio phase 调制公式 |
| 其他未接 force/operator | `L1` | attract/vortex 等明确 unsupported | control-point/world-space 力场 |
| Sprite renderer | `L3` | 作者纹理和程序化静态遮罩子集；TEX filter/address/mip 进入真实 Metal sampler，UV>1 repeat、minification 与单 mip 均有 GPU 门 | clamp-border 精确值、全 material/blend/lighting/atlas 与像素 golden |
| Sprite Trail | `L3` | 受限 trail 执行 | orientation/length/atlas/曲线精度 |
| Rope declaration | `L1` | typed kind/字段可见，runtime 明确拒绝 | topology、constraint、material IR 和 lifecycle |
| Rope execution | `L0` | 无 renderer | geometry/topology/连续 UV/lifecycle |
| Rope Trail strict execution | `L3` | 严格 Screen 单 renderer 子集以有界历史生成 quad 段；非准入字段、组合和预算全部 fail closed | 官方数值/UV/接缝/死亡尾迹/暂停恢复语义与 Windows golden |
| Static control-point subset | `L2` | static local offset/instance override 有分支；缺最终位置断言 | emitter 位置、空间与 parent golden |
| Dynamic control-point declaration | `L1` | 可识别或诊断 object/cursor/script 需求 | typed target 和 binding IR |
| Dynamic control-point execution | `L0` | 无 object/cursor/script runtime | 坐标转换与每帧更新 |
| Child asset graph | `L3` | 可递归发现并为 strict child 建立 runtime template 至层级 2：depth-one 每声明一个 template，depth-two 仅 event 触发且按 parent asset path 去重展开一次；missing/cycle/depth-three/nested-static fail closed | runtime cycle lifecycle、depth-two static 语义与 teardown 压力门 |
| Child execution/events | `L3` | deterministic birth/natural-death queue；strict static/default-static child 在有限 authored local origin 创建一次，仍要求零 angles、单位 scale、无 CP、probability=1，且目标定义自身含 event children 时不再被 nested 阻断；`eventspawn`、natural-`eventdeath` 与 identity/no-CP `eventfollow` strict child 独立模拟、绘制、跟随和回收，depth-two event child 以 (parent system, 粒子) 为 owner、事件跨层按帧串行传播；spawn/death 系统的 rate 发射窗口有界（authored duration 优先，否则以 child 粒子最大寿命为本地近似窗口），rate-only event child 不再无限累积；每 system 1,024 粒子，每 root runtime 每深度 64 systems、跨两层 128 systems/131,072 capacity | static angles/scale、event transform、collision/delete、CP/value inheritance、depth-two static、stop/switch 压力门 |
| Built-in textures | `L3` | 20 个精确 key；`particle/fire/fire1`、`particle/light/light_shafts_0`、Flare 三纹理、`particle/nature/snow` 与 `particle/smoke/smoke2` 等为项目自建确定性遮罩，不等于官方资产 | `rain_drops_sheet` 等剩余高频 key、atlas metadata、多纹理 material |
| World-space declaration | `L3` | General、Movement 与 Renderer flag 分开保真和准入；不再因 renderer-only world flag 拒绝整层 | Control Point world-space 仍只有声明 |
| World-space execution | `L3` | 静态可逆 layer/ancestor world frame 下，General 固定 birth origin、Movement 逆变换作者 velocity/gravity、Renderer orientation 不继承 system rotation/scale；inline script、transform Timeline/诊断、有效 parallax、循环/奇异 frame 失败关闭 | 动态 parent/Timeline、multi-screen/camera 与 Windows 数值/像素 golden |
| Collision declaration | `L1` | 可诊断但无 solver | shape/depth/response/event IR |
| Collision execution | `L0` | 无 solver | fixed step 与 event dispatch |
| Audio-response declaration | `L1` | 五字段按粒子 schema 保真进 IR，emitter/turbulent velocity/operator 三类共用同一声明类型；启用后一律报 `audioResponseIgnored`（operator 此前无诊断、会静默按无音频路径模拟） | 声明保真不等于可执行；默认值官方未公开，IR 层不内置 |
| Audio-response execution | `L0` | frame snapshot 已可用，但**求值公式与调制目标无证据**：粒子侧无 shader 源码，第三方参考实现对应代码是 `audioAmplitude = 0.0` 的 TODO 占位，其默认值在 emitter/initializer 两处自相矛盾 | 需 Windows golden 或官方公开算法；在此之前不得按推测实现 |
| Sprite Sheet | `L3` | Sequence/Random frame/frame blend 子集可执行；repeat sampler 不再把超 1 UV 拉成边缘条 | sidecar nominal frame aspect、rotated/trimmed metadata、loop/edge 和多纹理 material |
| Static instance overrides | `L3` | alpha/size/lifetime/rate/speed/count/brightness/normalizedColor 有运行断言 | 完整类型/range 门 |
| Direct color/control-point position override | `L2` | parser/simulation 分支已接线，最终值门不足 | direct color 与 CP position/angle 断言 |
| Dynamic instance overrides | `L1` | wrapper 只诊断 | typed live target、generation 和逐帧应用 |
| Material/blend | `L3` | `genericparticle` slot 0、additive/translucent 子集；共享 typed state 只准入 `disabled/disabled/nocull` 与 alpha unspecified/default，未知 blend/state 产生 `unsupportedBlendMode`/`unsupportedRenderState`，root 不执行、child graph 拒绝，不再静默回退 translucent；color TEX sampler 显式传到 renderer，strict REFRACT 的 slot 0 使用 `.straightAlbedo`、slot 1 使用 `.normal` typed identity，各自使用独立 sampler，background 固定 linear-clamp；同一 authored 文件仅因两者当前都逐字节保留通道而复用物理上传；普通 color/additive 的既有 premultiply 合同不变。项目自建 GPU 门已锁定 format-4 packed normal 的 CPU decode/native BC 两路径与 byte-equivalent format-0 RGBA 位移一致，并锁定 translucent/additive 的 fractional albedo × particle alpha coverage 只作用一次 | `alphawriting=default` 目前只是 bounded admission，不控制固定粒子 pipeline 的 Metal write mask；unsupported custom shader 仍可能误走自有 pipeline；官方/Windows DXT5n 恢复公式与法线数值/像素 golden、多纹理/combo、其他 render state、HDR/Lighting/Cutout、clamp-border 与 Windows 像素标定仍缺 |
| Fixed step/seed/maxcount | `L3` | fixed simulation step、deterministic seed、maxcount 有运行门 | pause/discontinuity 与 WE 数值 golden |
| Turbulent velocity initializer | `L3` | 非音频 profile 消费 forward/right/up、phase、scale、time、speed range；finite offset 作为 forward→tangent 平面方向旋转，`scale=0` 仍保留 offset；audio profile 继续 fail closed | right/up/noise mapping 与 offset 弧度解释仍属 clean-room；Windows 固定 seed 数值/视觉 golden 与 audio 公式 |
| Delta clamp/prewarm cap | `L2` | 代码有上限分支，缺定向预算断言 | 长帧和高 prewarm 压力门 |

当前完整矩阵可见粒子为 `127/130`，fixed13 历史门为 `76/76`；两门的初始 REFRACT root batch 分别为 14 与 7。当前三个未加载 root 是 `3088601835:550/558` 与 `3750813609:200`，其 material `cullmode=normal` 不满足只准 `nocull` 的现役粒子 typed-state 合同，因此矩阵显式锁定前者 `17/19`、后者 `8/9`，不是静默丢层或本批 shader 回归。RopeTrail 三个目标样本仍为 `3299228616=7/7`、`3743305891=1/1`、`3770444459=5/5`，后者 REFRACT 为 4。这不等于粒子组件完整兼容，`3299228616` 的音频响应、`3743305891` 的 child transform、`3770444459` 的 Boids/滴水与 splash children，以及 Rope、动态 world-space、Lighting 等 unsupported component 仍在。`2131872317` 的 event-death child REFRACT 继续由独立 7 秒延迟 runtime 门证明，child 不增加 root loaded-layer 计数。上述数字只度量对应矩阵实际加载的 root layer，不代表 Windows 视觉等价。

`8b06538d` 修复 strict REFRACT 的 BC3 purpose 丢失；`d432d4d5` 再把 slot 0/1 分别绑定 `.straightAlbedo` / `.normal`，并以自建 GPU fixture 锁定单 image CPU BC3 decode、多 image native BC3 直传与 byte-equivalent format-0 RGBA 的位移一致、G/A swapped 与 neutral normal 负对照，以及 translucent/additive 的 coverage 单次作用。`3770444459` 的 8 秒固定步长历史门确认 layers 239/245/248 分别有 72/77/56 个非空 REFRACT 活动帧；当前隔离签名 App 门仍为 5/5 particle、REFRACT 4、failed frame/drawable miss 0。等级保持 `L3`：这只闭合项目内部存储/合成合同；当前没有官方/Windows DXT5n 恢复公式、法线位移 golden，也没有证明水花密度、生命周期或像素等价。

`7b1d36f` 的 Turbulence 定向门为 5/5，覆盖旧 full45 日志中 19 条 `unsupportedOperator:turbulence` 的 14 条；另 3 个命中样本没有在新实现上复跑。该批没有改变 particle root loaded 计数，也没有重跑 fixed13/full45。

`d19e76b` / `d792296` / `f4e8a0c` 依次补齐 TEX sampler、常见随机分布/Box/lifetime oscillation 与实际 mip 链。分布构建对 `2470144420`、`1937925563`、`3742133044` 各 1/1；最终 mip 构建对 `2470144420`、`3742133044` 各 1/1。`2470144420` 的 Sakura 命中 repeat、Turbulent Velocity offset、size exponent 2 与 7-level mip，Stars 命中 centered Box/Oscillate Alpha、但其 `halo_6` 是作者单 mip，因此 mip 修复不应改变星点。`3742133044` 的默认可见雪花命中 RG88 多 mip 保留；隐藏樱花不计入该门。该批没有样本 ID 分支，也没有重跑 fixed13/full45。

`5911049` 把 Oscillate Position 从按秒龄逐帧积分的 velocity-like 增量改为每个粒子 normalized lifetime 的精确波形差值，并让 mask 的非 0/1 数值成为轴向幅度权重。保留 full45 提取中该 operator 命中 16 样本、38 个 root layer usage、24 个 sample-definition path；定向 `2067939514`、`3088601835`、`3299228616`、`3742133044` 为 4/4。数值门锁定 lifespan independence、1 秒与 1/60 秒 fixed-step 同时相一致、完整周期无漂移和半权重 mask；没有 Windows fixed-seed trajectory golden，不能升级为 `L4`。`2470144420` 的 Sakura/Stars 都不使用该 operator，因此本批不宣称修正其剩余花瓣/星点残差。

## 6. 动态运行系统覆盖

### 6.1 Timeline 与 SceneScript

| 能力 | 当前级别 | 升级门 |
|---|---|---|
| Particle `animation` wrapper presence | `L1` | 与正式 Timeline IR 分开，只作为动态值诊断 |
| Timeline object/property target | `L3` | layer `alpha` 与 effect constant 已 typed 编译并写回（28 处）；`origin`/`angles`/`scale` 有 target 但随包 10 处全带 `relative`，整批 fail-closed；`maxwidth`/`zoom` 与粒子 `instanceoverride` 无对应 target |
| Keyframe/value/tangent | `L2` | 帧号/值/双侧 handle/`lockangle`/`locklength` 已无损保真；缺失/`null` handle 合法，存在但非 object 的 handle 报 `invalidTangent` 并整条 fail-closed；求值只走线性，tangent 未消费——handle 的「帧偏移」与「归一化段长」两种解释不等价（`2067939514` 段在 frame=3.75 处分别约 0.767 / 0.970，线性 0.5），需视觉定标后才能宣称 Bézier |
| Loop/Single | `L3` | 按绝对 scene time 求值，真实执行 loop 7、single 21；single 到末帧保持末值不回绕，loop 跨周期同相位，有单测与真实样本双证 |
| Mirror | `L2` | evaluator 与单测已覆盖三角波折返，但随包 6 处 mirror 全落在被 `relative` 拒绝的 layer transform 上，真实样本 0 处执行 |
| start paused | `L3` | 6 处执行且恒停首帧；`2067939514` 为负门——无 VM 时不存在能调 `play()` 的主体，自动播放会偏离作者意图 |
| wrap-loop | `L1` | IR 保真（随包 9 处声明），执行时按普通 loop 降级并记 `wrapLoopIgnored`（7 处）；官方未公开首尾平滑算法 |
| `relative` 合成 | `L1` | IR 保真（10 处），编译期整条拒绝；推断语义为「作者基值 + 动画值」，未取得官方定义也未做视觉验证 |
| Combined Animations | `L1` | `options.parent`/`children` 的双向 key 引用已保真（随包唯一实例为 `3768229922` object 55 的 `origin`↔`zoom`）；坏 parent/children 引用报 `invalidGroupReference` 并在 IR 阶段整条拒绝，不会脱组执行；组内成员须共用持有方 clock，分组语义未实现，整组 fail-closed |
| Animation Events | `L0` | frame crossing、loop、同 layer script dispatch |
| Property binding IR | `L1` | 文档级保存 inline source、scene/object/effect/pass owner、完整 target path、properties、authored fallback 与 JSON value type；已证五类 target 有 13-shape 自建门；nested/未知 owner 不提升，`script + user` 冲突 fail-closed |
| Exact native text profile | `L3 bounded` | 三个 exact source/property profile 直接编译为 typed text target；不执行 JavaScript |
| Exact native 64-band Audio Bars profile | `L3 bounded` | 两个 exact source/profile 直接编译为 64 个 renderer draw；不执行 JavaScript，也不创建动态 layer |
| Generic file/module/schema-type/handle IR | `L0-L1` | inline binding 的 owner、完整 path 与 JSON value type 为 `L1`；file/module dependency、schema-resolved Vec/value type、runtime handle identity 仍为 `L0` |
| ECMAScript VM | `L0` | 安全隔离、确定性 budget、异常处理 |
| `init`/`update` 生命周期 | `L0` | 每屏实例、同帧 snapshot、stop teardown |
| `engine` globals/Date/Math | `L0` | exact native text formatter 只读取 host wall date，不暴露这些 API |
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
| text alignment pivot（`horizontalalign`/`verticalalign`） | `L3` | 官方取值域 left/center/right × center/top/bottom 全部参与 quad pivot：origin 落在被命名的那条边上，缺省与未知值退回几何中心；同一组字段继续喂 CoreText。静态文字仍用作者 `size`+`padding` 固定框；动态内容仅在 `limitwidth=false` 时取不小于作者框的 intrinsic size，并把同一 render size 传给 provider capture、effect/FBO 与最终 quad，见 [E-TEXT-PIVOT](runtime-evidence-index.md#e-text-pivot) / [E-TEXT-SCRIPT](runtime-evidence-index.md#e-text-script) |
| screen anchor（text layer） | `L3` | 官方 10 个取值全部解析并每帧折进 layer 平移，`none`/缺省/未知取值不偏移；离屏 GPU 门下 21:9 的 `dino_run` 记分标签从 0 覆盖像素回到与 16:9 完全一致的 396 px 右上角；只有 text layer 携带该字段，Windows 像素标定见 [E-TEXT-ANCHOR](runtime-evidence-index.md#e-text-anchor) |
| overflow limits（`limitrows`/`maxrows`/`limitwidth`/`maxwidth`/`limituseellipsis`） | `L3` | 五个字段随 interpretation v29 进 text IR 并由 CoreText 栅格化消费；两个数值只在对应开关打开时生效。`limitwidth=true` 的动态文字继续遵守作者/`maxwidth` 限制；`limitwidth=false` 的动态内容按 intrinsic size 扩到不小于作者框，避免 clock/date/day 被占位符框裁断。静态文字布局不变；官方省略号和动态外框无 Windows 逐像素对照，见 [E-TEXT-LIMITS](runtime-evidence-index.md#e-text-limits) / [E-TEXT-SCRIPT](runtime-evidence-index.md#e-text-script) |
| outline/shadow/text effects | `L1` | 字段或 effect 可保留，未形成完整绘制链 |
| property-driven text | `L3` | direct user property 与 exact native text profile 都经 per-frame typed snapshot、按 layer generation/stale cancellation 和动态纹理 consumer；其他 target 仍依 consumer 决定重建 |
| SceneScript clock/text | `L3 bounded` | exact clock/spaced-day/date 三 profile 在 6 样本 16 个可见绑定执行；通用 VM/Date API 仍为 `L0` |
| Audio declaration | `L3` | effect 与粒子两套 schema 分别保真解析；两者字段名不同，粒子无 `audioamount` |
| Audio 16 bins | `L3` | left/right host-shared 快照，静音/无权限/停采集稳定归零，可注入；当前 Scene 分析器以 -60 dB 下限扩大相邻条幅度差，频段、下限与归一化仍为工程选择 |
| Audio 32/64 bins | `L3` bounded | left/right host-shared snapshot 与同次 FFT 已接；供 exact Workshop Simple Audio Bars 的 `32+CLIP_LOW` / `64+CLIP_HIGH` profile及两个 exact native property-script 64-band profile，其他 Workshop/SceneScript 不外推 |
| Audio effect consumer | `L3` | stock Shake（`whitePhaseFallback`/`timeOffsetCombo`）、exact old-editor Shake（`legacyUnconditionalPhase`）、stock Pulse（`stock2842`，并接受同一精确旧版 profile 缺省 `replacementkey`）与 exact Workshop Simple Audio Bars 三 profile（含可重定位 16-band stereo up/down）；其余 legacy 指纹、其他 Workshop audio shader、未支持 combo 与 SceneScript binding fail closed |
| Audio particle consumer | `L0` | 声明已保真但求值公式无证据；见 5 节 Audio-response execution |
| Exact native property-script audio bars | `L3 bounded` | 两个严格 source profile；64 档逐 bin average、单纹理 64 draw、完整准入与失败关闭；不产生 JS object 或 Scene layer handle |
| Generic SceneScript audio API | `L0` | 无 VM、`registerAudioBuffers`、`AudioBuffers` object/array identity 或订阅 lifecycle |
| Sound layer | `L0` | `3743305891` authored FLAC 尚未解码/播放，也未成为 Scene 频谱输入；当前 system tap 排除本进程。需补 sound content IR、提取/播放、volume、生命周期与自有频谱合同 |
| Embedded MP4 frame | `L3` | image-layer 子集；不同于系统媒体 provider |
| Media status/metadata/timeline | `L0` | injectable snapshot 和 lifecycle |
| Media thumbnail identity | `L1` | `$mediaThumbnail` typed reference 已分类；不等于 producer |
| Media thumbnail producer/consumer | `L0` | typed texture provider/generation/fallback |
| Layer/named target provider | `L3` | bounded current-frame graph；exact composition Clipping Mask 只为完整-chain consumer 捕获 hidden static provider；effectful/nested/child、system/media/variant 与 generic material provider 仍缺 |
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
| Custom shader reference/path/source identity | `L3 executed-degraded` bounded subset | material path 与 authored stage source/raw hash/canonical identity 已保存；严格 framebuffer-only 子集已有两个真实 executor consumer，三组 exact Scroll 另有 GPU 正门但尚无真实正执行样本；不代表任意路径/source 可执行 |
| ShaderContract/source contract | `L2` | source/include/annotation/declaration/stage 已保留；bounded frontend 已消费 stage link、typed uniform layout 与精确 `material` constant-key annotation；完整 typed AST、preprocessor、slot/provider schema 仍缺 |
| Custom shader execution | bounded subset `L3 executed-degraded`；arbitrary `L0` | 当前只准单 pass、显式 framebuffer sampler 或三组 exact Scroll 隐藏 slot、静态常量与 exact typed state；通用受控编译/映射、material slot、动态 uniform 与安全产品合同仍缺 |
| RGB device | `L0` | macOS 产品策略、授权、设备 adapter |
| Debug PNG readback | `L2` | 可生成 benchmark 截图证据；不得标成 offline bake |
| Offline bake | `L0` | 与实时共用 IR/evaluator/render graph，固定时钟和编码输出 |

## 8. Coverage-first 实施批次

| 覆盖批次 | 开发计划映射 | 目标 | 完成判据 |
|---|---|---|---|
| **B0 Contract/Runtime Kernel** | `S3 第 1-4 项` | v22 binding program、per-surface transaction、atomic state、alpha/solid-color/direct-text/strict Local Contrast/Opacity consumer 与 rebuild fallback 已闭合 | 新 live target 继续要求 compiler、consumer、原子失败与不换 surface/window；pause/fixed-time 单列 |
| **B1 Provider Core** | `S2 第 5 项 + S3` | dynamic text 已完成 per-layer generation、stale cancellation、last-ready fallback；embedded MP4 已完成受限 launch-scoped provider、SceneClock mapping、显式 publication generation、pause/rebuild/stop 状态合同；frame registry 双代已完成；静态 typed texture candidate 已在 Water Flow 2 槽、Standard Blur 1 槽、plain/effectful base image、bounded REFRACT normal 与 Depth Parallax R8 depth 复用，base direct/effect/offscreen 路由共用最终原子校验；Shake/Foliage Sway/Water Ripple/Depth Parallax 与 exact legacy Blend 共九个 bounded 槽进一步消费共享 slot-binding 原子，Blend 的 PNG/JPEG property 与 authored TEX 共用最终 ready candidate 选择 | 把 status/metadata/cancel/teardown 推广到 Texture Variants、system/media、其余 Effect 与 generic material candidate；补 video 真实 pause/hot-plug/seek/loop/恢复门；不含 nested/effectful graph provider |
| **B2 Graph Resource Runtime** | `S2 第 1-5 项` | strict Blur、stock Local Contrast、exact Workshop `shadow_____________`、exact stock Opacity、exact stock Shake、strict stock Depth Parallax、exact Workshop Clipping Mask、exact modern static Shine、exact Cursor Ripple 与 ordered strict effect-chain 已消费 target table；cache/resize/reset、整链原子 allocation、D7 ShaderContract IR v1、BGRA/RGBA/RG/R8 format、exact shader fingerprint、同帧 copy/swap foundation、受限 history seed/clear、Cursor Ripple 跨帧 history、Precise Blur 两种 material-command interleave、exact legacy compose 归一化、exact Foliage typed utility capture 与 exact composition Clipping Mask/静态 Opacity dependency capture 已完成；Water Flow/Blur 三槽消费 B1 typed candidate，Shake/Foliage Sway/Water Ripple/Depth Parallax/Blend 九槽进一步消费公开 `0...7` slot-binding 原子；observed-enum typed render-state admission 已由 Cursor Ripple、受限 authored shader 与 particle 三类 exact consumer 使用；受限 authored shader 已消费精确 uniform `material` constant-key annotation，并只为三组完整 Scroll profile 推断隐藏 framebuffer slot；generic compose/scene-background、其他 composition effect consumer、SceneScript/dynamic alpha、通用 history consumer、generic material slot population、typed shader default/slot/provider、generic state translator/cache 与 `alphawriting=default` 语义仍未完成 | read/write、RT lifecycle、slot/combo/state 和 resize/switch/stop 门；下一批用 preview 并排图和同样本分项变化验证画面收益 |
| **B3 Provider-Graph Integration** | `S2 第 5-6 项` | nested/effectful/scene-background source、通用 material consumer、45 Effect 严格 profile family | B1+B2 均完成后接入；不得新增 effect-name 视觉旁路 |
| **B4 Feature Breadth** | `S3-S4` | direct dynamic text、exact native clock/day/date、两个 exact native 64-band property-script Audio Bars、Timeline 28/48 typed target 子集、16/32/64 档 host audio、stock Shake/Pulse 与 exact Workshop Simple Audio Bars consumer 已完成；通用 SceneScript core、Sound、system/media text、cursor/media、其余 Timeline/audio 与按依赖排序的 particle breadth 仍待推进 | 每族正向、默认关闭、unsupported、determinism 和 lifecycle 门 |
| **B5 Fidelity** | `S2-S4` 广度完成后 | 字体、视差、粒子、常用 Effect 与 WE Windows golden 对齐 | 固定输入逐像素/数值阈值、性能预算、长稳和多屏门 |
| **Advanced** | `S5` | Puppet、2D light/HDR、3D、arbitrary custom shader、RGB、offline bake | 每个系统有完整 IR/runtime/lifecycle/product gate 后再升级 |

研究可以并行，产品执行不能倒置：B0 live-property、direct dynamic text generation、exact native clock/day/date、两个 exact native 64-band property-script Audio Bars、Timeline 受限 typed target、Scene audio 和既有 bounded effect/particle/resource runtime 已形成各自正向门；unsupported Effect/Timeline/粒子/通用 SceneScript 形态继续 fail closed。当前完整门与聚合计数见页首及运行证据索引；`3299228616` 的新增两 stage、`1937925563` 的 Pulse/Water Ripple/Directional Godrays、`2470144420` 与 `3742133044` 的严格 Iris 终止后缀都只属于 exact profile。三个 text profile 与两个 audio profile 不外推为通用 SceneScript、`Date`/`AudioBuffers` API、动态 layer 或同类格式脚本支持；其他可见未知 script 继续诊断并保留作者 fallback。官方图与当前帧只作方向性检查，没有同步非零音频或 Windows pixel golden 时不宣称视觉等价。下一代码批须从专项缺口重新选择，不从任一 bounded 正门外推通用兼容。

## 9. 更新规则

1. 每次 Scene 能力提交必须更新本表对应行和精确边界；只更新开发流水账不算完成。
2. 升级到 `L2` 必须有结构/路由测试；升级到 `L3` 必须有实际执行正例、作者关闭反例、失败降级和生命周期门；升级到 `L4` 必须有官方行为或 Windows golden。
3. 新发现的官方能力先补 [官方页面全目录](official-page-catalog.md)、[页面能力映射](official-page-crosswalk.md) 和专题语义，再进入本表；私有字段按 [资料来源与证据索引](source-index.md) 标证据等级。
4. 当前 baseline、矩阵报告、测试总数和签名 App 身份只以 [运行证据索引](runtime-evidence-index.md) 为主答案；本表只维护系统摘要与专项入口，带日期的计划和路线图是批次快照。语义自动门校验布局合同与相对链接，不假装同步这些动态事实。
5. 开发开始顺序：先看本表选择最低公共依赖，再查专题合同和 source index，最后查看样本命中；不得先凭截图写视觉特判。
6. 总表只允许单一 `L0` 到 `L4` 等级；若同一能力同时存在 IR 与 executor 子集，必须拆成两行或下沉专项表。
7. 每行至少要能追溯到专项表中的代码、测试和运行证据；只有 parser 或结构时不得写成执行支持。
