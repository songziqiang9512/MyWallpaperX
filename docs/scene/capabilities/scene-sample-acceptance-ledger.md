# Scene 样本验收台账

> 状态：现役验收事实。本页由 `script/scene_sample_acceptance_ledger.py` 生成；视觉裁决只来自 `script/scene_sample_acceptance_verdicts.json` 的人工记录，不要手工编辑本页。
>
> 最终验收门：每个样本在真实播放中正确显示与播放，且作者参数（project.json user properties）全部进入播放链路。
>
> 归档运行状态和首断点只描述对应执行身份的安全/结构事实，不是视觉正确性；`structural-chain-complete-visual-review` 仍需人工验收。集群只用于排序公共首断点，样本身份不得进入产品代码或现役路线正文。

## 1. 来源

- 样本根：`/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Scene`（453 个 sample 目录）。
- 运行归档：`scene_sample_debug_archive.json` SHA-256 `656769ceeb256acbbed4a50cc5ac85eba0b55f9bac3c46261fec8d512f37fe80`（生成于 2026-10-29T02:16:22.751422+00:00）。
- 归档运行身份：CDHash `f92774bdf124ae9f7bfae8f6f3e4d30a713c5036`、CDHash `edde7df24e63e3b9830a72900437596b3634c3dd`；**归档内不止一个执行身份**，运行状态与首断点因此是混合身份事实，单样本结论必须回到该样本自己的 report 身份。
- 裁决覆盖层：`scene_sample_acceptance_verdicts.json` SHA-256 `f7d9baf7c56d36ae8ce9e7a6c247b540ca043faaf12d89e47418941a4297bf78`。
- 仅历史归档保留、当前目录已移除的裁决：3806887870；不计当前目录表，原裁决不删除。
- 本页生成于 2026-10-29T05:59:21.578821+00:00。

本页生成日仅表示台账生成，不表示归档运行或人工裁决已重新验收。旧归档首断点可能已在后续开发中修复；最新技术状态以[断点队列](../roadmap/scene-open-breakpoint-queue.md)和[运行证据](runtime-evidence-current.md)为准。`not-run` 仅表示本归档未关联运行证据，不表示样本从未运行；归档中的失败状态也不等于当前 HEAD 的失败。
本机已清理的历史证据：68 个样本、222 个引用；原路径保留在裁决覆盖层的 `unavailableLocalRuns/unavailableLocalEvidence`，不计可用载荷。清理不撤销历史结论，也不代表当前重新验收；见[证据可用性](runtime-evidence-current.md#local-evidence-availability)。

## 2. 汇总

| 原人工裁决 | 样本数 |
|---|---:|
| `unreviewed` | 434 |
| `pass` | 0 |
| `fail` | 19 |
| `platform-unsupported` | 0 |

| 官方对照状态 | 样本数 |
|---|---:|
| `unknown` | 347 |
| `not-run` | 24 |
| `blocked` | 0 |
| `compared` | 82 |

- 已裁决但缺观看者身份的条目：**17**；已裁决但缺截图/视频身份的条目：**14**（P0.2 `sample → verdict` 关系要求的字段；缺项保持 `unknown`，不由生成器补写）。此处只统计**裁决自己引用的** run/截图身份，与 corpus 清单（docs/scene/capabilities/scene-corpus-capability-inventory.md）的「人工对照」列（样本目录自带的用户截图 `截屏*.png` 与 `用户观察说明.md`）不是同一事实，两页不可互相替代。

| 归档首断点集群 | 含义 | 样本数 |
|---|---|---:|
| `effect-chain` | effect 准入 / 颜色合同 / graph 执行 | 21 |
| `particle-load` | 粒子层资源加载 | 4 |
| `texture-load` | 基础图片纹理加载 | 63 |
| `scenescript` | SceneScript 异常 | 26 |
| `terminal-output` | terminal compositor / 输出链 | 0 |
| `visual-review` | 结构链完整，待视觉验收 | 339 |
| `not-run` | 未关联本归档运行证据 | 0 |

| 归档运行状态 | 样本数 |
|---|---:|
| `blocked` | 6 |
| `degraded-runtime` | 110 |
| `structural-chain-complete-visual-review` | 337 |

作者参数：329 个样本声明了 schemecolor 之外的用户参数，共 9505 项，其中 2995 项带 `condition`。参数进入播放链路的验收随各样本的视觉裁决一起记录，不单独计数。

## 3. 逐样本

归档首断点格式为 `stage / owner / reasonCode / profile`。作者参数列为 `总数(condition 数) 类型分布`。

| 样本 | 标题 | 作者参数 | 归档运行状态 | 归档首断点 | 归档集群 | 原人工裁决（日期） | 备注 |
|---|---|---|---|---|---|---|---|
| `1195626192` | Gaze | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1300076567` | 阳光少女 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1315486372` | 貂蝉拜月 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 10-19当前原包短播及独审，顶部/中段光束仍比官方宽软；52光卡、117雾与12水纹均实际执行。水纹大体限盆内，旧gross错位未定位。相位/viewpor… |
| `1439846152` | 腿 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1480826543` | Emilia X-ray NSFW | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1507413154` | 百褶裙 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1507593643` | 蕾丝吊带 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1511889295` | 死库水 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1553008362` | [Jidan Hua] Ichigo and 002 (Darling in … | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1636394814` | [Jaku Denpa] Shigure (Kantai Collection… | 4(0) bool 1 color 1 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1695673397` | 白发少女 4k动漫壁纸 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 当前仅补登/同构建回归；主体、羽毛和雪呈现，顶部灰带沿用已锁同宽高比官方也有的边界，不重新排故障。 与目录官方截屏仅作基础构图对照；viewport、时相、媒… |
| `1926190458` | Morning_4k | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 未参与OGG修法的独立FLAC对照：人物/床/装饰/早餐构图保留；FLAC admitted1/rejected0、ready/rate1、时钟0→0.407… |
| `1937925563` | Tropical Paradise 4K [Customizable Colo… | 8(0) color 6 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1943018087` | Prestige K/DA / League of Legends / X-R… | 13(4) bool 5 color 2 slider 5 untyped 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1989767609` | Black tights（透视） | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1994794519` | D.VA_OVERWATCH[X-Ray] | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-20 | 10-21同cover三点可逆已闭下游末材质放置偏移；物理入口/全profile/官方像素未扩。 历史观察：10-20用户报告上下层揭露位置在屏幕中心准确，越… |
| `2067939514` | Windows Visualizer | 34(27) bool 12 color 9 combo 5 scenetexture 2 slider 6 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2069136288` | [R18] Lexaiduer DOA Nagisa x Tamaki X-R… | 3(0) color 1 combo 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2112262451` | [R18] Sakimi Chan Azur Lane Belfast X-R… | 4(0) color 1 combo 2 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2131872317` | Night Market by 俊伦 何 in 4K | 7(0) bool 3 color 1 slider 3 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-20 | 当前22s原包blue热切及蓝放射/稀疏星点阶段可见，四child已准备且聚合GPU完成；未取得完整轨迹或官方连续正控，不关闭旧反馈。无产品修改。 |
| `2134765860` | Bunk | 34(18) bool 14 color 7 combo 3 group 4 slider 5 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 10-19 Gaussian零轴批健康相邻原包短窗exit0/FAIL[]、正常stop/GPU排空，房间/时钟/吊灯/窗/书架可见，右灰白poster仍在；… |
| `2163522240` | [18+] jk x-ray 🔞😍 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2179185481` | Azur Lane / 18+ X-ray NSFW & SFW (3 Ver… | 4(0) bool 3 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2181251652` | Mio Tokisaki (X-Ray) | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2231088993` | Ahri X-Ray | 2(0) color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2241938645` | KDA Akali [4k Version] | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2269193950` | WLOP - Nap | 4(0) bool 2 color 1 combo 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2304304373` | Don't Die | 5(0) color 2 combo 1 slider 1 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2347762662` | 18+ X-Ray │NSFW & SFW│ ♥ 여대생♡ PT 2 ♥ ( … | 6(0) bool 4 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2356604986` | 1265079-1322607782 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2419444134` | Nier Reincarnation - Akeha | 6(0) bool 5 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2470144420` | 女孩独享的宁静傍晚 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2473638329` | Genshin Impact \| +18 / NSFW & SFW | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2505351195` | Nier Automata / +21 \| NSFW & SFW | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2507971256` | 麻匪 骚气音频可视化 | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 两侧主体、黑白拼图和斜分隔可见；音频/视差输入未锁，未见主构图缺层。 |
| `2524111047` | Liu Meryl Wei wei（被举报下架-重发） | 5(0) bool 4 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2607203340` | Tomb Raider +18 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2616828675` | 【R18】别看了，快点啦~#4K#动态#16:9 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2684431262` | 麻匪 炫酷音频律动 Windows | 28(0) bool 4 color 12 slider 1 text 11 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 2026-10-18用户补报（待当前身份复验）：官方略有发光；并入整体合成差异，不以旧巨大紫块本窗未见关闭发光观察。 旧记录：10-18原包可见斜盘、代码与洋… |
| `2731896598` | 麻匪 A-SOUL | 16(0) bool 8 color 6 text 1 textinput 1 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-invalid-argument / target:layer:origin` | `scenescript` | `unreviewed` 2026-10-19 | 五竖卡及五圆头像可见；中央粒子点簇颜色/位置只作未控pointer、音频与phase观察，不判故障。 |
| `2735160334` | 麻匪 山景城 | 3(0) bool 1 color 1 text 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 雪山、云湖、两侧树与蓝光可见；未控相位/视差差异不判缺陷。 |
| `2745810856` | Jinx with gemstone [Arcane] | 24(0) bool 7 color 5 combo 1 group 5 slider 6 | `degraded-runtime` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` |  |
| `2775915974` | R18*JK(escalator)エスカレーターJKさんX-ray | 4(0) bool 1 color 1 combo 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 鼠标纵向与顶部边界已修，顶部极限仍露灰边；整样本未通过 |
| `2776912698` | 麻匪 洛天依 Android | 29(0) bool 11 color 15 slider 1 text 1 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2780710296` | 麻匪 miku 初音ミク 初音未来 Windows | 27(0) bool 9 color 5 slider 1 text 11 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2784267518` | 麻匪 D.Va 守望先锋 Windows | 27(5) bool 9 color 5 slider 2 text 11 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 10-21受控PCM与单变量旁路支持Pulse181贡献轻微眼内提亮；未验官方强度/halo/HDR或正常采集。 历史人工观察（原文保留）：Pulse181实… |
| `2787219305` | 麻匪 你的责任 Windows 4K 21:9 16:9 | 24(0) bool 6 color 5 slider 2 text 11 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 女像、玫瑰、左钟与青横线可见；横线/谱高度依赖音频，不据静音窗判缺失。 |
| `2794098047` | 麻匪 是姐姐还是妹妹 windows | 34(12) bool 5 color 10 combo 2 slider 5 text 12 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2797913147` | 【R18】连体黑丝#4K#视差#可互动臀部#动态 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2797943632` | 麻匪 僵尸女孩 Windows | 24(3) bool 5 color 7 slider 1 text 11 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 人物、黄蓝红三色背景、右上叉号和底部白色频谱均可见；未见大层缺失、异常黑块或明显混合破坏。 实际人物更大、右上符号方向及星星密度/透明度不同；这些与视口、动画… |
| `2802243144` | 冰公主-by Wlop 时间日期已修复 16:9 -music 订阅后点赞，养… | 14(0) bool 7 color 2 slider 5 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2804817823` | Yor Forger \| Spy x Family | 4(0) bool 2 color 1 slider 1 | `blocked` | `resource-load / BaseImageTextureStore / base-image-texture-load-incomplete / image-layer` | `texture-load` | `unreviewed` |  |
| `2807058277` | 麻匪 森美声 森カリオペ  Windows | 28(0) bool 8 color 6 slider 3 text 10 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2808874251` | youer | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2808936045` | (4K) Relaxing Ganyu [Genshin Impact (原神… | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2811643059` | 原神 | 4(0) bool 2 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2813231542` | 清新美女 R-18 | 9(0) bool 7 color 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2813240634` | 麻匪 NIXEU 九尾妖狐 | 9(0) bool 5 color 2 combo 1 text 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 主肖像、蓝色光照、雪点、NIXEU标题和右下频谱均存在；主画面接近，未见大范围黑块或缺层。 actual右上时钟被右边缘截断，肖像整体更大；应先剥离更窄视口及… |
| `2814167871` | 麻匪 明日方舟 凯尔希 Windows | 29(8) bool 7 color 7 combo 1 slider 2 text 11 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 白发人物、蓝底、水果与右钟可见；有短暂typed非零音频，但未与图精确关联，不据频谱高度判缺失。 |
| `2815826216` | 麻匪 约尔·福杰 间谍过家家 SPY×FAMILY | 34(13) bool 7 color 13 slider 2 text 11 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 10-19完整原包健康相邻短窗exit0/FAIL[]：人物、红底与时钟可见，target20 effect后继及正常排空成立；文字越右图缘未归因，无旧App… |
| `2819143171` | 麻匪 夜兰 原神 16:9 21:9 | 26(6) bool 5 color 6 slider 4 text 11 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 人物、飞扬白外套、天空云层、底部频谱和右侧时钟横线均存在；未见大缺层、黑块或明显混合破坏。 actual右侧时钟/日期被裁切、人物和杯子更大；当前更窄视口足以… |
| `2821634935` | 麻匪 德克萨斯 明日方舟 | 26(0) bool 8 color 7 text 11 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 沙发人物、笔电、蛋糕与手机钟可见；三环/频谱未同音频资格，不判合成错误。 |
| `2824109832` | Yor Forger - NIXEU 4K | 16(7) bool 12 color 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2824690710` | 麻匪 原神 雷电将军 Windows 16:9 21:9 | 36(18) bool 11 color 19 slider 4 text 1 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2831174267` | 麻匪 Lycoris Recoil 21:9 16:9 | 33(0) bool 9 color 9 slider 3 text 11 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 红底双人物、枪花、标题日期可见；ready提示在after已消失；底谱未锁音频，不判缺失。 |
| `2834973884` | 麻匪 wlop-鬼刀 重置版 | 22(0) bool 5 color 3 slider 3 text 11 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2835398595` | 麻匪 碧蓝航线 独角兽 Windows | 31(11) bool 4 color 13 combo 2 text 10 textinput 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 中央白框人物、樱花与右钟可见；框齿/频谱差异未与音频/phase对齐。 |
| `2837223712` | 李擎洲：阿狸[4K] | 2(0) bool 1 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2849382252` | 麻匪 死亡笔记  L·Lawliet | 16(0) bool 2 color 3 text 11 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 10-19原生attachment后继已闭三白弧低清（见#background-terminal-density-20261019）；本次独立原包非零PCM+… |
| `2850139759` | 麻匪 血妖姬  16:9 / 21:9 | 24(0) bool 6 color 4 combo 2 text 12 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 红白衣人物、灰底横线、文字与雪粒可见；光线形状/强度未控输入，不判故障。 |
| `2866086594` | 麻匪 赛博朋克 边缘行者 露西 Lucy | 19(0) bool 2 color 2 slider 3 text 12 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 露西肖像、青/洋红发光、右侧霓虹光带、Cyberpunk标志和底部音频柱可见；未见大缺层、黑块或混合破坏。 actual更窄视口将标志右端裁掉，头部更大；光带… |
| `2871175822` | 麻匪 猫 | 21(0) bool 4 color 4 slider 2 text 11 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 水猫、托猫双手、体内红鱼、液体轮廓和背景蓝点均存在；未见大缺层、异常黑块或明显混合破坏。 actual左侧多出白色横向频谱，官方该时相没有明显柱形；音频/默认… |
| `2871552691` | 麻匪 操 | 16(0) bool 1 color 4 text 11 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 白字可见，参考亮环在静音窗未见；advisory预览不能作为compositor阻断依据，旧自动误标已按通用oracle资格修正。 |
| `2877499944` | 麻匪 做什么壁纸？看美女不香？ | 19(0) bool 3 color 3 scenetexture 1 text 12 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 三联视频主体/街景可见且两图有帧变化；频谱未与音频对齐，不判未执行。 |
| `2877855240` | 麻匪 雷电将军 泳装 | 57(34) bool 13 color 20 combo 1 slider 12 text 3 textinput 8 | `degraded-runtime` | `resource-load / BaseImageTextureStore / base-image-texture-load-incomplete / image-layer` | `texture-load` | `unreviewed` |  |
| `2884170082` | 麻匪 wlop 小绿 | 18(0) bool 3 color 2 text 13 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 人物背部、纹身、半透明衣料、双刀、红绿飘带、水面倒影与两岸建筑均存在；主合成接近，未见大缺层、黑块或明显混合破坏。 人物/小船位置和飘带波形不同；actual… |
| `2884628849` | 麻匪 小姐姐 | 29(0) bool 4 color 4 combo 5 slider 4 text 12 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2887099508` | 猫猫的耳朵可以摸吗？\| Ever touch ear？【TIM】 | 37(0) bool 10 color 4 combo 3 scenetexture 2 slider 2 text … | `degraded-runtime` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` |  |
| `2887542690` | 麻匪 礼服斯卡蒂 3D版 | 28(0) bool 9 color 9 combo 1 slider 3 text 5 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2890473419` | 麻匪 肉肉的雷电将军 3D 21:9 16:9 | 29(0) bool 8 color 7 combo 2 slider 9 text 3 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:origin` | `scenescript` | `unreviewed` |  |
| `2896873092` | Genshin Impact: Thicc Girls Spread Coll… | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2902406982` | 麻匪 月半与鬼哭 所有元素自定义 | 173(103) bool 20 color 45 combo 8 scenetexture 2 slider 35 … | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2913492057` | 麻匪 粒子音频互动 | 16(0) bool 5 color 3 text 8 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2917306763` | [4K/动态/R18/衣服透视可调]碧蓝航线-独角兽妹妹「天使的护理时间」-B… | 3(0) bool 1 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2919854127` | 麻匪 辉夜 AHEGAO | 27(6) bool 6 color 5 slider 1 text 13 textinput 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 前景人物、暗色背景人物、文字和心形均存在，未见整层人物缺失或异常黑块。 官方蓝色音频环在人物周边清晰可见，当前after没有可见蓝环；先记音频驱动可见性候选，… |
| `2927205881` | 麻匪 音频识别 多素材自定义 | 51(16) bool 11 color 6 combo 7 scenetexture 5 slider 4 text… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 10-21当前候选保机器人、灰背景、时间日期、卡片与盘；默认1733与作者白色时间536分支四节点Bloom已从global const拒绝透传恢复实际Pro… |
| `2932157836` | [4K \| 可自定义] 星浴 \| Hoshi-yoku | 123(101) bool 36 color 13 combo 1 slider 71 textinput 2 | `degraded-runtime` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` |  |
| `2932631210` | 欧派-音乐乱动 | 13(0) bool 8 color 3 combo 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 2026-10-18用户补报（待当前身份复验）：背景圆环/漩涡差异大；旧人物缺失关闭证据保留，不关闭背景新范围。 |
| `2938612768` | 麻匪 音频识别 Media Player | 79(35) bool 16 color 11 combo 5 scenetexture 4 slider 13 te… | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `2942486721` | R18 Ishtar And Ereshkigal / 遠坂  凛 Tohsa… | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2949019513` | [4K \| 可自定义] A.R.O.N.A.    (碧蓝档案) | 41(20) bool 23 color 3 slider 15 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2951452910` | 麻匪 一伊那尔栖 21:9 16:9 | 29(10) bool 5 color 8 slider 2 text 13 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 雪林、人物、悬浮小生物、金色光环、雪点和右上时钟/日期/小频谱均可见；未见大缺层、黑块或明显混合破坏。 actual人物更大、树干位置与局部雪点不同；主体与背… |
| `2959875782` | [R18] Lexaiduer Last Origin Dark Elven … | 4(0) color 1 combo 2 slider 1 | `blocked` | `launch / SceneDesktopWallpaperHost / ready-event-missing / scene-surface` | `visual-review` | `unreviewed` | 2026-10-29几何命名输出表示修复：原持续dependency-input-mismatch已消失，1413 publication→134 bindi… |
| `2960821850` | Media Player (2.0) | 5(0) bool 4 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2964778792` | [4K/动态/R18-3.0版]碧蓝航线-莱莎琳·斯托特「熬夜的炼金术士」补档… | 4(0) bool 1 color 1 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 动态origin63的准备/74.stop首门已修，原包第一idle已实际可见黑色Z；与目录官方截屏基础构图相符。复用driver因explicit拖动不生成… |
| `2969308380` | 麻匪 三分钟一张流水线壁纸 简单且无聊 | 26(4) bool 6 color 6 slider 1 text 10 textinput 3 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 人物、粒子、时钟可见；日期右端裁切和STANDBY保留视口/媒体状态未知，不作适配根因。 |
| `2972071249` | 麻匪 宵剑 | 30(3) bool 8 color 2 slider 1 text 19 | `degraded-runtime` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` 2026-10-19 | 主体与刀可见；effect313的dependency-stage-reference-unavailable保留为执行缺口，白波纹与其因果未证。 |
| `2974757317` | 麻匪 音频识别 悬浮窗 Media Player | 80(35) bool 13 color 17 combo 3 scenetexture 5 slider 16 te… | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` | 10-18合法module-only Bool初始化保留于最终共享域后，原包两帧卡片下多余矩形消失、主卡/文字/背景保持；官方无CLI标记实验及改名/失败重建… |
| `2981249186` | 4K SCI-FI Black Hole | 8(0) bool 5 color 1 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2983846453` | 麻匪 自定义双背景开关 - Customizable Day/Night Sw… | 40(15) bool 3 color 8 combo 2 scenetexture 2 slider 10 text… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2986218263` | Tokisaki Asaba & Tokisaki Mio │18+ X-Ra… | 6(0) bool 5 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2987771245` | 麻匪 Wlop鬼刀画作 雨儿 | 27(6) bool 3 color 3 combo 1 text 19 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 人物、发簪、香炉/手中香、蓝色烟、窗格/光束、桌面书卷、前景架和水印均存在；主合成接近，未见大缺层、黑块或明显混合破坏。 烟雾位置/密度与局部光斑不同，act… |
| `2992924426` | 麻匪 炫彩男孩  16:9 21:9 | 18(0) bool 1 color 1 combo 2 text 13 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 人物、彩色头发/饰品、彩色水花带、Wall...per文字和粒子均存在，未见大层缺失、黑块或明显混合破坏。 actual标题偏青绿、官方偏浅蓝，人物肤色/高亮… |
| `2998757800` | 碧蓝航线-利托里奥【R18版/可触摸/天气变化】-B站慕慕慕慕斯小蛋糕 | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 2026-10-18用户补报（待当前身份复验）：重复拖动仍仅首次响应；与3749463715是否同一owner未证。 |
| `2999907577` | 麻匪 站姬 16:9 21:9 | 38(6) bool 3 color 6 combo 2 slider 4 text 22 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 默认7号金属流体背景与上方文字的最大缺失已修复，人物保留。共享opaque辅助颜色边界、alpha-only旁读反馈种子资格沿现Program/图/合成链修正… |
| `3002649614` | 纯欲少女 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3009275235` | Judy Cyerpunk 2077 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3021013015` | 赛博color-墨侠客行 | 2(0) color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3022080536` | 赛博color-宣纸国画-紫罗兰永恒花园 | 2(0) bool 1 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 10-17静态format9/20B mesh修正后，原包奶油纸底、书法与双红印已恢复，主体18旧52B动画保持；不再列背景灰底/装饰缺失。与目录官方仅基础构… |
| `3025969015` | 黑龙闹海 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3027056454` | 麻匪 多娜多娜 Dohna Dohna | 27(2) bool 5 color 4 combo 1 slider 1 text 16 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 群像人物、洋红/白色双背景、黑色点阵斜带、星形与几何图案均存在；未见人物大层缺失、异常黑块或明显混合破坏。 actual星形分布、背景几何姿态与官方不同，群像… |
| `3027068980` | 麻匪 Miku 初音未来 自定义音频识别 Media Player | 30(6) bool 5 color 6 combo 3 scenetexture 1 text 15 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-20 | 216/328旧准备守恒与命名绑定首拒已退出；同project/PKG的自有梯度当前封面由白占位恢复紫至蓝灰，白边/标题/人物/星环保持。无媒体正确无封面；2… |
| `3028090166` | WLOP [Tian Nan2] | 2(0) bool 1 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3039704323` | 赛博color-宣纸国画-紫罗兰永恒花园3 | 7(0) bool 5 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 米白水墨人物、竖字及双弧可见；主构图保持，完整动态/输入未验收。 |
| `3039882306` | 麻匪 音频识别 抽签 Media Player | 49(10) bool 11 color 9 combo 1 scenetexture 2 slider 2 text… | `blocked` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` |  |
| `3042492564` | [4K \| Customizable] Hoshi-Tele \| 星屑テレ… | 249(203) bool 76 color 18 combo 8 slider 127 text 10 textin… | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` 2026-10-22 | 10-22普通图片加法末合成恢复X白亮核心；默认/关Shine与GPU末消费有界通过，完整属性/光束/媒体及粒子738仍开放。 |
| `3047405322` | SandBlack [4k] | 15(0) bool 5 color 2 combo 2 group 1 text 5 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` |  |
| `3078285611` | 麻匪 金克丝 jinx 音频识别 Media Player | 53(13) bool 10 color 10 slider 11 text 22 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:effectConstant` | `scenescript` | `unreviewed` |  |
| `3086016320` | 麻匪 发如雪 21:9 16:9 | 28(1) bool 5 color 3 slider 2 text 18 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` 2026-10-21 | 实际为中部全身背影人物、浅灰背景和半透明巨幅面部；官方为右侧近景正面人物，底部白色柱状频谱本次截图未见。 画面有可见主体与背景，未见整屏黑块；构图、姿态和图像… |
| `3087231311` | 麻匪 明日方舟 凯尔希 | 55(0) bool 9 color 4 slider 4 text 37 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 荧绿人物、灰白斜条、文字与粒子可见；未见主构图缺层，不外推完整播放。 |
| `3088601835` | Winter Wanderer Xayah - League of Legen… | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3113287126` | Dome 4k {Artwork by WLOP} | 8(0) bool 6 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 10-22原包20s：小数Count拒绝已修，琴/手锚点保持；五系统实际绘制。方向/密度未闭，未改人工裁决。 |
| `3113554287` | 【可随时间变化】窗旁の伊蕾娜   （优化版本） | 7(1) bool 3 color 3 combo 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3114332546` | 麻匪 云兮 竹林的小师妹 | 53(21) bool 5 color 8 combo 1 slider 12 text 21 textinput 6 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 竹林、前景枝叶、持剑人物与右上时间/日期/农历均实际呈现，基础构图与官方参考相符；未见大块缺层、黑块或独立错位。 人物头发/粒子与时钟值不同；视口较窄使裁切与… |
| `3115163440` | Shadow Garden (X-Ray) | 4(0) bool 2 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3122339805` | Pixels | 39(0) bool 9 color 6 combo 1 scenetexture 3 slider 1 text 7… | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3137495261` | 麻匪 花姐 21:9 16:9 | 41(3) bool 7 color 6 slider 2 text 25 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 蓝色背景、中央人物、浅蓝旋转方块/白色斜边与跨中线频谱均呈现，未见大块缺层、黑块或独立错位。 实际频谱高度较低，方块粒子分布与人物/边框裁切不同；音源/pha… |
| `3141421197` | GraspOfTheAbyss | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3146507587` | こきん【吉罗】 | 3(0) bool 1 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3147346398` | ⛏🧱Minecraft Lo-Fi Fireplace [4k HDR] WE… | 21(12) bool 8 color 3 combo 1 slider 5 untyped 4 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3148125112` | 麻匪 薇薇安娜 明日方舟 4K | 41(6) bool 6 color 5 combo 2 slider 3 text 25 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 分组只读XY误拒已修：同PCM全分辨率前后对照中，2661/effect2663恢复顶部蓝窗内细星线/亮节点；角落星网原已存在。实际Program/GPU/末… |
| `3167210190` | [Blue Archive] 奶牛装明日奈 | 7(0) bool 5 color 1 group 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3173418061` | Persona 5/女神异闻录5 音乐播放器 | 2(0) color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 已修mix首错：7条effect scale恢复；56标题按下/释放反馈可见，hover保持。主体与文字正常，其他播放/交互及官方同phase未验。 |
| `3175039950` | 麻匪 音频节拍互动 Music beat interaction | 57(15) bool 11 color 6 combo 1 scenetexture 1 slider 8 text… | `blocked` | `launch / SceneDesktopWallpaperHost / ready-event-missing / scene-surface` | `visual-review` | `unreviewed` 2026-10-21 | 2026-10-29优化DEBUG补验：死varying的inverse准备需求退出，原未Ready/撤帧首门闭合，Ready4440.089ms；人物、雪人… |
| `3187857248` | 黑丝狱卒.4K.动态.视差.可拖拽 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-22 | 人物、背景和效果可见；骨0/1 unsupported-enabled-physics沿作者姿态回退。拖动/释放未测试，不归因U40或宣称人物不可用。 本轮2… |
| `3211615441` | 捆绑悬挂 \| Bind & Suspend [ 可交互/interactiv… | 26(12) bool 7 color 1 combo 5 group 4 slider 4 text 4 texti… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3219398263` | Acheron Black Hole (StarchaserArt) | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 2026-10-18用户补报（待当前身份复验）：背景圆环/漩涡差异大；并入旧方向疑似相反观察，不从单帧改符号。 |
| `3221354414` | dynamic Ginka 神轿银花 [GINKA OST: 祭神纸偶与愿望 … | 2(0) color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 原包默认短播银白发侧脸、蓝眼/蓝饰与橙红背景呈现，亮波带/细斜纹亦见作者预览，不据此报缺陷；11effects两帧22GPU完成，仅2终级末合成，dust/r… |
| `3226487183` | 麻匪 花火 五角色自定义 崩坏星穹铁道 Sparkle Honkai: Sta… | 55(9) bool 14 color 8 combo 1 slider 5 text 27 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 10-17最终原包4907点击后2522实际执行作者Program：白面具→整景RGB分离/重影→清晰黑面具，左右眼与脸颈/身体在。前序reference组装… |
| `3232289987` | 【4k 高度自定义】流萤&萨姆  丝袜可更改——夜莺Night【崩坏星穹铁道】 | 116(60) bool 34 color 18 combo 4 scenetexture 2 slider 41 t… | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3233141951` | 熠烛 御剑驭龙-红鸾樱落 高度自定义Red Warbler-Sakura fa… | 67(0) bool 18 color 7 combo 3 group 1 scenetexture 1 slider… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 10-19 mixed公共组后继：absolute alpha与relative origin/scale复用原owner，旧新原包各28s/native/默… |
| `3238423642` | Katana Girl with Hologram (Adjustable; … | 90(0) bool 35 color 25 combo 9 group 12 slider 8 untyped 1 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:color` | `scenescript` | `fail` 2026-09-08 | 头部错位已修，整体视觉与约 18.7 FPS 帧时间未验收 |
| `3248220186` | 麻匪 音频粒子球 Audio Particle Ball 16:9 16:10… | 44(8) bool 6 color 6 combo 4 slider 7 text 19 textinput 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3264246690` | 麻匪 wlop 鬼刀 月牙儿 16:9 16:10 21:9 32:9 | 70(21) bool 16 color 7 combo 2 slider 14 text 25 textinput 6 | `degraded-runtime` | `resource-load / BaseImageTextureStore / base-image-texture-load-incomplete / image-layer` | `texture-load` | `fail` 2026-09-08 | 旧头部出画/左肘缺块已退出；后继真实原包保持头、左肘和黑口罩完整，点击口罩亦有实际后验。AA与警戒带运动仍待当前画面对照；整体历史fail不升级。 |
| `3287715210` | 发光少女 4K动态壁纸 | 17(1) bool 1 color 1 group 1 slider 14 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 音频条已恢复（PCM fixture），真实系统音频与整体未验收 |
| `3290491250` | frieren | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3291326967` | 蒙眼少女 4K动态壁纸 | 18(0) bool 1 color 1 group 1 slider 15 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 人物、雪粒子、日期与频谱呈现；未定位大面积主体缺失，完整参数与同状态细节未验。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状… |
| `3292370168` | 麻匪 3D 自定义动态交互 骷髅 音频识别 Human Skeleton Me… | 99(52) bool 21 color 18 combo 5 scenetexture 2 slider 16 te… | `blocked` | `resource-load / BaseImageTextureStore / base-image-texture-load-incomplete / image-layer` | `texture-load` | `unreviewed` 2026-10-20 | 默认34与大角度背景有界修复保留；条件8请求准备、实际动作Combo恢复，用户确认切换动作生效及默认1未再见异常骨段。Root非默认2保存/重开与reset回… |
| `3299228616` | Lonely Cat: Audio visualizer , Clock , … | 64(60) bool 26 color 13 combo 13 slider 12 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-18 | 限定反馈后验：时钟上方滚动矩形已由childless copybackground=false优先修复；原包恢复387可见且scroll实际Program/G… |
| `3321237804` | 【4k 动态】初音未来  秋绪——夜莺Night [4k Dynamics] … | 101(45) bool 25 color 17 combo 5 scenetexture 1 slider 36 t… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-22 | 人物、视频、日期/星期与频谱保留；639主时钟原生字形坐标失效已修，静音/中心pointer的5/10/15s主HH:MM完整可读，旧小字是独立秒数，未跨分钟… |
| `3323988600` | Hentai Goddess of Victory Nikke ANIMATE… | 9(0) bool 4 color 1 slider 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3325624777` | 麻匪 修女 鼠标互动 nun 16:9 21:9 32:9 16:10 | 49(17) bool 7 color 5 combo 1 slider 11 text 25 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 主体、金环、金纹与字阵可见；原包字阵默认绿色，官方金色未锁属性，不记颜色故障。 |
| `3337494481` | 麻匪 3D交互音频模块 媒体识别 Media Player 16:9 16:1… | 82(59) bool 17 color 20 combo 6 scenetexture 1 slider 9 tex… | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` 2026-10-20 | 10-20当前App原包/clock-off两窗均App0/正常stop，侧clock穿正面随单开关消失，date仍透；原effect CPU/229 fal… |
| `3341111071` | 麻匪 初音未来 MIKU 海边 32:9 21:9 16:9 16:10 | 32(8) bool 7 color 4 slider 2 text 18 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3351163962` | [高度自定义] 樱花庄的宠物女孩 椎名真白 | 187(154) bool 31 color 26 combo 22 scenetexture 4 slider 86… | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` | 2026-10-18用户补报（待当前身份复验）：左上文字超出圆环，用户称官方在环内；确切文本/状态待确认。旧同viewport默认hour/seconds/g… |
| `3351179520` | 麻匪 東京喰种 高槻泉 媒体识别 Media Player 16:9 16:1… | 74(46) bool 13 color 9 combo 5 scenetexture 1 slider 12 tex… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 巨裂片/白环/2000²首门已闭；10-21恒定1500Hz自动播放，8张可见原图跨53.496s，固定左右文字弧带未见明显整圈平移/半径跳变，文字/盘相位继… |
| `3357627941` | 麻匪 开门见喜 鼠标交互 自定义本地文件 Windows door 16:9 … | 30(1) bool 4 color 2 combo 1 scenetexture 2 slider 1 text 20 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3363252053` | 【Parallax视差】Hatsune Miku 初音未来 光与影——夜莺Ni… | 97(39) bool 28 color 15 combo 4 group 6 slider 33 text 8 te… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3372715909` | 御坂美琴 旗袍 | 31(0) bool 2 color 4 combo 2 slider 4 text 19 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-29 | 本批a697候选已闭原控制器create/null及Boolean二次资源门、历史视频纹理强持有；默认/显式自动持续播放，12主题/时段热改全部接纳。直接主输… |
| `3374523158` | 麻匪 极光音频响应式 交互壁纸 Aurora audio-responsive… | 87(54) bool 7 color 25 combo 5 slider 25 text 23 textinput 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3383535304` | 麻匪 顶顶 音频感应自动场景切换 Audio monitoring scene… | 35(8) bool 7 color 6 combo 2 slider 1 text 16 textinput 3 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-20 | 酒吧人物、挂饰、枪酒杯与前景杯保持；306/effect364旧颜色启动/类型/packed音频编译首拒已退出，原Program实际GPU和末合成完成。_1开… |
| `3389974179` | 落日与白皙的大腿 | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3395392965` | 请叫我帅锅-小姨定制 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3395777145` | 麻匪 光 音频识别 Media Player 16:9 16:10 21:9 | 74(26) bool 14 color 10 combo 5 scenetexture 1 slider 11 te… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3396722575` | 麻匪 NIXEU 黄泉 超多自定义模块 音频识别 Media Player 1… | 132(71) bool 22 color 17 combo 3 slider 47 text 40 textinpu… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 10-18原包modern dense常量中性轨道首错已闭：头发/身体nested lookup恢复，实际init stop→event play、目标帧推进… |
| `3420215721` | 麻匪 圈 媒体识别交互壁纸 Circle Media Player | 87(21) bool 12 color 9 combo 3 scenetexture 1 slider 21 tex… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3435573282` | 麻匪 巳蛇 自定义动画 音频识别 Media Player | 82(23) bool 14 color 10 combo 2 slider 16 text 39 textinput… | `degraded-runtime` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` |  |
| `3436945972` | 麻匪 Wlop 远方来客 | 45(9) bool 3 color 2 combo 4 slider 6 text 27 textinput 3 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 补足启动余量后已见开场过渡及双人物桥景；旧70s工具超时保留，不判主体缺失。冷启动单次64.8s，非性能收益。 |
| `3437487219` | 3D Earth - Close Orbit   [HDR10 Optimiz… | 15(2) bool 3 color 1 combo 2 group 3 slider 6 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-10-19 | 10-19共享roughness零端点后原Earth圆白热点退出，地表/云层/蓝边/银河仍在；夜侧/光色、偶发闪烁及collision继续开放，整样本fail… |
| `3443450456` | 蛊真人-坚持（高度自定义） Reverend Insanity-Persist | 57(28) bool 10 color 9 combo 4 group 1 scenetexture 1 slide… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-22 | 默认文字主题与中央“坚持”可见，26/26 graph准入，默认活跃链完成输出；Puppet/walk主题默认隐藏，不算默认缺失。 本轮20s/30FPS固定… |
| `3446316682` | 【完美世界】柳神 无敌道 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-23 | 原包20s/after16静音，人物五官、发饰/玉珠与护甲、绿色背景及大范围光雾均呈现，十effect与四粒子实际执行；未发现可行动的active首错。 正常… |
| `3448845950` | 麻匪 媒体音频标签【148项自定义】Media Player 16:9 16:… | 152(35) bool 22 color 17 combo 14 scenetexture 2 slider 20 … | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 10-20首帧命名锚点首门已闭；10-21补共享Vec3.equals后，原180/effect10高亮回调由TypeError恢复持续typed颜色，真实背… |
| `3448877775` | 【Time Variation 时间变化】Alone 孤独の少女——夜莺Nig… | 145(62) bool 38 color 19 combo 6 group 9 scenetexture 1 sli… | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` 2026-10-19 | mixed组未参与修法原包独立8s/native/默认：人物、帘、城市、时钟实际呈现，App0、正常stop/GPU排空、输入/App无漂移。1733 alp… |
| `3454689854` | 晦光织梦-MPGB202508 | 7(0) bool 3 color 2 text 1 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-22 | 主体、环、线条及粒子可见；10个活跃graph执行，三拒绝text层作者显式隐藏。 本轮20s/30FPS固定PCM、中心pointer，核5/10/15s系… |
| `3470948192` | 水滴 三体 \| Droplet -SYKM | 37(0) bool 7 color 4 combo 2 group 7 slider 13 untyped 4 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `fail` 2026-09-08 | 仍黑水滴/缺亮边拖尾；旧NaN已修，反射原型已撤回；115.scale首个非有限返回仍在。 |
| `3471294034` | 麻匪 巳 UnclePanda [3大UI布局切换] | 86(44) bool 10 color 21 combo 4 slider 7 text 37 textinput 7 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 2026-10-18限定后验：原报告的背景菱形网格缺失已由根实际before/after/目录官方对照关闭；线与方形节点恢复，人物/文字/花瓣/频谱仍在。sh… |
| `3472940912` | -Tsukatsuki Rio [ blue archive ] - 4K | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3476868923` | 麻匪 索泰ZOTAC 天启姬 (角色双动画 点击互动) 120项自定义 | 131(49) bool 15 color 36 combo 3 slider 19 text 54 textinpu… | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3477054430` | Cat with headphones on the roof | 25(0) bool 4 color 6 group 6 slider 9 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 画面显示不全；mask 已恢复，月亮/球体与文字布局仍开放 |
| `3483662476` | 【哲风壁纸】二次元场景-动漫插画 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3486887298` | 风景系列-真4K【流星、夜晚】-B站慕慕慕慕斯小蛋糕 | 14(0) bool 3 color 2 group 1 scenetexture 5 slider 1 textin… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 彗星与时钟呈现；未定位大面积主体缺失，时相/布局细节及完整参数未验。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状态验收。 |
| `3487629864` | 云曦老婆 (18+) | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3507496797` | 麻匪 龙吟锦鲤赋 32:9 | 46(4) bool 10 color 4 combo 1 slider 1 text 30 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3509243656` | 三体实时演算 \| Three-Body problem - SYKM | 233(2) bool 27 color 20 combo 3 group 21 scenetexture 1 sli… | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `fail` 2026-09-08 | 开场/模拟画面不正常，坐标文字异常 |
| `3549827466` | 【完美世界 火灵儿】盛典妆容 | 2(0) bool 1 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | U02光束反馈未闭；本轮目标已执行，尚缺确定可归因ROI，不记新修复。 |
| `3554161528` | Blue Archive-Sorasaki Hina 空崎日奈[4K] | 35(16) bool 15 color 4 combo 1 group 5 slider 7 untyped 3 | `degraded-runtime` | `effect-admission / EffectStageAdmission / unified-capability-unavailable / backend:effect-family:blend` | `effect-chain` | `unreviewed` | 10-19原包镜头由始终全景恢复近→全，正常退出/GPU排空；开场镜头缺失反馈已闭。旧缺光观察独立保留；本轮仅同步既有后验，无新播放。 |
| `3562021804` | 【完美世界】石昊 以身为种 | 3(0) bool 1 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3563038726` | 【凡人修仙传】梅凝  乖巧可怜 | 7(0) bool 4 color 2 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3566880847` | 【凡人修仙传】紫灵 白色限定 | 7(0) bool 1 color 3 combo 1 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3575109244` | 蔚蓝档案 龙华妃咲 体操服丨 Kisaki丨Blue Archive | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3576374111` | 原神 甘雨 户型展示丨 Genshin impact ganyu | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-22 | 单图与三效果执行，三张晚图有变化；未定位默认明显缺层。 本轮20s/30FPS固定PCM、中心pointer，核5/10/15s系列；after为约2s早图，… |
| `3577990983` | Chainsaw Man-Reze 蕾塞[4K] | 48(33) bool 12 color 3 combo 1 group 4 slider 9 untyped 3 u… | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` 2026-10-20 | 10-20普通Release用户确认原Launcher目录/图片/音乐/App打开正常，遮挡无误触；此前原图中央Reze/手臂/身体、16透明花叶和210半透… |
| `3578843606` | 电锯人 蕾塞 -4K- Chainsaw Man Reze | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3581882134` | 【凡人修仙传】紫灵 冰清玉洁 | 21(0) bool 8 color 4 slider 9 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` 2026-10-19 | 10-19独立Single修复后实际近景→展开→末值保持，开场镜头完全缺失有界关闭。 旧记录：限定8.150s原图：人物/金带/背景保持；官方左上暖亮、nat… |
| `3585542943` | 【凡人修仙传】元瑶 灵泉沐浴 | 13(0) bool 6 color 4 slider 3 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` 2026-10-18 | 限定8.165s原图：上部/人物左上青绿扇状照明实际可辨，人物/水纹/右烟/头发高光保持，旧笼统缺光未重现。204有真实138/137批GPU完成，像素不独归… |
| `3585875739` | Miku Monitoring | 6(0) bool 5 color 1 | `degraded-runtime` | `graph-execution / GraphExecutor / layer-source-not-ready / resolved-material-graph` | `effect-chain` | `unreviewed` |  |
| `3586308277` | Tranquil Lake View - Outdoor Scenery | 7(0) bool 6 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3586705329` | [甜蜜女友3]柳木诗梦 | 46(5) bool 9 color 8 combo 3 scenetexture 8 slider 13 text … | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-24 | 2026-10-24：七个clipping默认效果的slot1用途与声明_1身份已修；真实启动选图、清空恢复、默认滚动PASS，两个固定ROI已证替换。旧归档… |
| `3587571382` | 【凡人修仙传】宋玉  璀璨夺目 | 15(0) bool 5 color 3 slider 7 | `degraded-runtime` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` |  |
| `3587930444` | 吹响吧上低音号 中川夏纪 铠冢霙 伞木希美 吉川优子丨Nakagawa Nat… | 5(0) color 1 slider 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3588027687` | BA 调月莉音 露背毛衣 珍珠内裤丨Blue Archive Tsukatsu… | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3589454154` | 土星 \| Saturn - Sykm | 113(2) bool 29 color 1 group 7 scenetexture 17 slider 26 te… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 10-19旧App与最终深度候选在请求sceneTime30下均呈现整颗土星、星环、时钟/底部图标；exit0/runner FAIL[]、输入/App无漂移… |
| `3589819394` | Scenery - Mountains and Rivers | 5(0) bool 4 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3593919489` | Miku - Princess of the skyscraper rooft… | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3595178660` | 原神-丝柯克 | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3597772384` | Lost Landscape \| northway. | 138(116) bool 65 color 2 combo 3 group 4 scenetexture 24 sl… | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` 2026-10-17 | 限定root正交CP world force与缺省距离已接通，自有正控成立；原包9秒/after5山景、雨和时钟保持，但270在current/committ… |
| `3598930685` | Hatsune Miku under the blue sky -- shh | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3599986633` | 麻匪 杉泽 观山海 | 28(2) bool 3 color 2 combo 1 slider 1 text 21 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-invalid-argument / target:layer:visibility` | `scenescript` | `unreviewed` 2026-10-17 | 10-17基线主幅黑幕经177.visible单次消融定位；修正空effect查询合同后，原包默认初始化自行解除遮挡，九凤人物和彩色主幅已恢复。702独立de… |
| `3600590272` | 芙莉莲 高跟勾丝丨 Frieren | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3600595499` | 蔚蓝档案 调月莉音 高跟勾丝丨Blue Archive Tsukatsuki … | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3600599916` | 初音未来 赛车初音 高跟勾丝丨Racing Miku レーシングミク | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3600610212` | 鸣潮 赞妮 高跟勾丝丨Wuthering Waves Zani | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3600636270` | MyGO 长崎素世 高跟勾丝丨Soyo Nagasaki | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3600642307` | 原神 阿蕾奇诺 仆人 高跟勾丝丨Genshin Arlecchino The … | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3600647083` | 碧蓝航线 能代 高跟勾丝丨Azur Lane IJN Noshiro | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3601801724` | ash一爪布鲁托 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 主体已呈现；边侧裁切较紧，尚未同viewport对齐。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状态验收。 |
| `3601964477` | 千咲 \|\| 鸣潮  \|\| 枫 \|\| 4K | 44(19) bool 19 color 5 group 3 slider 7 text 10 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` |  |
| `3603225398` | 蔚蓝档案 百合园圣娅 高跟勾丝丨Blue Archive Yurizono S… | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3603698851` | 蔚蓝档案 圣园未花 高跟勾丝 兔女郎丨Blue Archive MISONO … | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3603711180` | 【凡人修仙传】慕沛灵 金屋藏娇 | 21(0) bool 8 color 5 slider 8 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` 2026-10-19 | 10-19开场镜头完全缺失已闭；Gaussian零轴数值首拒后继退出，目标四Program/GPU执行、FAIL[]。细条受后画UI遮挡且相机phase不同，… |
| `3603812691` | 原神-八重神子 | 5(0) bool 4 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3603819103` | 崩坏：星穹铁道 昔涟 高跟勾丝丨Honkai：Star Rail Cyrene | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3603835830` | 赛博朋克：边缘行者 露西 高跟勾丝 兔女郎丨Cyberpunk：Edgerun… | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3604867866` | 蔚蓝档案 调月莉音 高跟勾丝丨Blue Archive Tsukatsuki … | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3604880711` | 蔚蓝档案 调月莉音丨Blue Archive Tsukatsuki Rio | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3604887305` | 蔚蓝档案 空崎日奈 高跟勾丝 兔女郎丨Blue Archive Sorasak… | 2(0) color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3605502569` | 顾州-暗影魅眸｜Shadow · Charming Eyes | 33(21) bool 15 color 4 combo 1 group 3 slider 10 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3605722997` | [假装4K]魔王-追悼【可交互壁纸】（喜欢的点个赞呗） | 43(27) bool 22 color 4 combo 3 scenetexture 2 slider 9 text… | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` 2026-10-17 | 默认25s/after22s人物与建筑完整；196/205单图atlas Rope加载及非空GPU完成已恢复，49.visibility TypeError仍… |
| `3609108600` | 千咲 \|\| 鸣潮 \|\| 4K | 9(4) bool 4 color 1 slider 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3610154602` | 千咲 \|\| 鸣潮 \|\| 高塔 \|\| 4K | 42(16) bool 15 color 4 group 4 slider 6 text 10 textinput 3 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` |  |
| `3612058080` | 吞噬星空-星幻王 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3612199597` | 千咲 \|\| 鸣潮 \|\| 与千咲的穗波散步 \|\| 咖啡厅天台 \|\… | 40(17) bool 19 color 4 group 3 slider 5 text 9 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` |  |
| `3612659809` | 原神 芙宁娜 高跟勾丝丨Genshin Impact Furina | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3612795410` | 千咲 \|\| 鸣潮 \|\| 与千咲的穗波散步 \|\| 喷泉广场 \|\|… | 35(15) bool 16 color 4 group 2 slider 3 text 10 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` |  |
| `3616019317` | MyGO 长崎素世 辣妹丨Soyo Nagasaki Gyaru | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3616389236` | Aesthetic Media Visualizer (Shortcut) \… | 179(165) bool 74 color 13 combo 7 scenetexture 26 slider 26… | `degraded-runtime` | `resource-load / BaseImageTextureStore / base-image-texture-load-incomplete / image-layer` | `texture-load` | `unreviewed` 2026-10-17 | 10-17同公共shortcut底图修复的实际受益验收：默认8个顶部白块恢复透明链环，主幅/时钟/装饰保持；复用既有签名App单次direct运行64.200… |
| `3616476797` | Zero Two | 仅 schemecolor | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` 2026-10-21 | 人物、角、水面倒影、雾暗背景与时钟均在；右下黑媒体面板稳定但无同控系统媒体，不能判黑块故障。113材质资格拒绝另保，未认独立可见损失。 本轮after实际约2… |
| `3617056047` | 麻匪 模型音频互动 Model - audio interaction | 49(14) bool 4 color 6 combo 2 scenetexture 1 slider 7 text … | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-18 | 限定后验：位置/倒置反馈已闭。同批行为等价前版758f9b原包9秒/after5/resize/noPCM回归，罐体正立位于虚线圈内、不压底字，背景文字保持；… |
| `3627973226` | [Sakiko Togawa]snowy night - It's MyGO!… | 18(0) bool 17 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 人物、雪景、日期与底部频谱呈现；未定位大面积主体缺失，完整参数未验。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状态验收。 |
| `3629927359` | 奶牛大鸭鸭 2 | 2(0) color 1 combo 1 | `degraded-runtime` | `resource-load / BaseImageTextureStore / base-image-texture-load-incomplete / image-layer` | `texture-load` | `unreviewed` |  |
| `3632513108` | 千咲 不散的春之花——夜莺Night《鸣潮 Wuthering Waves》 | 242(150) bool 74 color 44 combo 10 group 9 scenetexture 24 … | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3632522893` | Widescreen Mount Fuji Visualiser | 28(4) bool 9 color 2 group 2 slider 15 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` 2026-10-17 | 富士山、文字、前景呈现；active Blur whole-stage被composition childless准入拒绝，836无hook/默认隐藏独立保留… |
| `3641200550` | 樱羽艾玛 | 仅 schemecolor | `degraded-runtime` | `graph-execution / GraphExecutor / layer-source-not-ready / resolved-material-graph` | `effect-chain` | `unreviewed` |  |
| `3655958892` | R18 Acheron & Black Swan 黄泉&黑天鹅 [Honkai… | 5(0) bool 4 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3662245960` | Wuthering Waves - Aemeath | 4(0) bool 3 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 人物与故障风格效果呈现；动态阶段及同状态精度未验。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状态验收。 |
| `3662390671` | 【Angels of Delusion】\| Sunna \| Aria \|… | 51(0) bool 11 color 7 combo 2 slider 18 textinput 1 untyped… | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3662790108` | 实时太阳系 Live Solar System - SYKM | 198(26) bool 71 color 9 combo 3 group 12 scenetexture 24 sl… | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `fail` 2026-09-08 | 10-19仅Sun-4原资产隔离presentation有界后验：修前/后各exit0/FAIL[]，蓝色星芒保持、外围额外发光下降；不认完整366 read… |
| `3663810817` | 鎏金狮影映娇颜 | 8(0) bool 6 color 1 text 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3665307769` | 爱弥斯1 \|\| 鸣潮 \|\| 4K | 51(19) bool 18 color 7 group 4 slider 10 text 10 textinput 2 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` |  |
| `3666041758` | 麻匪 磁流体 Magnetofluid 音频相应 | 101(32) bool 3 color 14 combo 5 scenetexture 1 slider 31 te… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3679907516` | 老人-樱花-Porsche 718 Cayman | 8(0) bool 7 color 1 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` 2026-10-21 | 未参与分组prefix修法的独立原样本复验，908×590同PCM/中心pointer/resize设置，人物/花树/车/地面/标识保持，无明显新增缺层；so… |
| `3680252478` | SUPRA A80 \| GREY HORIZON | 13(0) bool 11 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3686637340` | MyGO 椎名立希 Shiina Taki | 2(0) color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3690065713` | 老人-棕发女孩 [带鱼屏4K] | 7(0) bool 5 color 1 combo 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 人物、眼部背景和默认文本均呈现；边框、媒体与视窗差异待同状态对齐。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状态验收。 |
| `3690859128` | 爱弥斯2 \|\| 鸣潮 \|\| 4K | 42(17) bool 10 color 8 group 3 slider 11 text 10 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3691275829` | 星穹铁道 花火 高跟勾丝 Honkai：Star Rail Sparkle | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3694697894` | 星街すいせい  星街彗星（第二版） | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3695791724` | Angel (Commission; Adjustable; 4k) MX | 51(0) bool 21 color 10 combo 3 group 6 scenetexture 1 slide… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3696646175` | 老人-海边少女 [3440x1440] | 5(0) bool 4 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-22 | synthVis波形可见；“delete this text”属作者queuedWord默认文本，无媒体事件的歌名/歌手空串不算故障。 本轮20s/30FPS… |
| `3698459055` | 凡人修仙传-梅凝·暗系[4K] | 47(29) bool 15 color 6 combo 1 group 5 slider 20 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3699213569` | 碧蓝航线Azurlane-斯特拉斯堡&克莱蒙梭（By Adramahlihk） | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3701177677` | 老人-夕阳女孩 [4K] | 4(0) bool 1 color 2 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-22 | 两组轨道音频与作者提示可见，三活跃graph执行，未定位默认明显缺层。 本轮20s/30FPS固定PCM、中心pointer，核5/10/15s系列；afte… |
| `3703104370` | Rio&菲比-adoc(涟) | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3707474273` | EVE | 13(0) bool 10 color 2 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 130/effect2分组只读XY误拒已修：同PCM全分辨率前后心形局部新增红橙连线，后effect/末合成及次帧消费。人物/背景/音频条/TV框保留；Com… |
| `3708363772` | 麻匪 3D磨砂 音频识别 Media Player | 68(15) bool 8 color 4 combo 5 scenetexture 1 slider 19 text… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3712499998` | 鸣潮 \|\| 3.3pv \| 自星海尽处回响 | 40(16) bool 12 color 8 group 2 slider 8 text 10 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-invalid-argument / target:layer:visibility` | `scenescript` | `fail` 2026-09-08 | 日期/时钟恢复，WEVector unsupported，重复文字未裁决 |
| `3716328771` | 老人-暗调少女 | 7(0) bool 5 color 1 combo 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-22 | 默认时钟/日期/星期和底部音频可见；time2备用104及子符号默认隐藏，不算缺失。 本轮20s/30FPS固定PCM、中心pointer，核5/10/15s… |
| `3719111841` | 【明日方舟/Arknights】凯尔希•思衡托——Kal'tsit·Esper… | 22(0) bool 13 color 3 combo 1 group 1 slider 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 人物和绿色横线呈现；未把横线据图猜成故障，完整参数与同状态细节未验。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状态验收。 |
| `3721456868` | 绯雪1 \|\| 鸣潮 | 44(17) bool 15 color 7 group 4 slider 6 text 10 textinput 2 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-invalid-argument / target:layer:visibility` | `scenescript` | `unreviewed` |  |
| `3721991999` | 无职转生 洛琪希 Mushoku Tensei Roxy | 5(0) bool 3 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-22 | 人物及水面波纹可见，14效果graph完成；眨眼/交互未测试，不认完整动画通过。 本轮20s/30FPS固定PCM、中心pointer，核5/10/15s系列… |
| `3722749868` | Porsche GT3 RS | 4(0) bool 3 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-23 | 原包20s/after16静音，车辆/轮胎尾翼、樱花树与富士山/塔楼、时钟日期和花瓣均呈现，六effect与七粒子实际执行；base-color回退未与缺图建… |
| `3723344874` | 【凡人修仙传】玄骨 借尸还魂 | 25(0) bool 7 color 4 slider 14 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` | 2026-10-18有界内容资格：10-17 numeric/carrier首门保持；固定64d6ac8c2+临时DEBUG观察器的原包frame31实际双D… |
| `3724289844` | 老人-水[4K] | 9(0) bool 6 color 1 group 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | sounds/下OGG漏提取已修；自然02.ogg从resourceUnavailable到admitted1/rejected0、ready/rate1、时… |
| `3725148661` | 电锯人 玛奇玛 闪光灯 Chainsaw Man Makima | 4(0) bool 2 color 1 slider 1 | `degraded-runtime` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` |  |
| `3726992337` | GIRLS BAND CRY 安和昴 486 SUBARU AWA | 8(0) bool 7 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3730622939` | MyGO 长崎素世 Soyo 深度视差 自定义大小和位置 | 5(0) bool 3 color 1 slider 1 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3737432178` | 老人-嘉宾身影 | 10(0) bool 7 color 1 combo 1 group 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-22 | 底图、时钟/日期、颜色变化及粒子可见；VHS/CRT/godrays和模式2音条默认关。无媒体事件时标题/alpha按作者回调清空。 本轮20s/30FPS固… |
| `3738202317` | Albedo. | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3742003469` | 点击嘴巴切换图片  Click the mouth to switch ima… | 3(0) bool 2 color 1 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3742133044` | 凌霄·双司镇命·无常<1>-[深空之眼] | 3(2) color 1 combo 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 本片未参与修法的独立回归：原perspective粒子196进入非空提交，实际雪花位置变化，人物/红月/花背景保持；只作基础构图对照，非完整官方parity。 |
| `3742497499` | 麻匪 白泽夢 | 75(24) bool 12 color 13 combo 4 slider 3 text 39 textinput 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 人物、水面波纹、鞋帽、黄色花瓣、透明块、右下白色频谱及字样均实际呈现，未见大块人物/背景缺失。 用户明确纠正：时钟是作者的鼠标移向右侧后左右拼合效果；用户既往… |
| `3743305891` | 战双 | 仅 schemecolor | `degraded-runtime` | `graph-execution / GraphExecutor / layer-source-not-ready / resolved-material-graph` | `effect-chain` | `unreviewed` 2026-10-19 | 10-19透视neutral材质证明接通统一动态模板：同PCM非零阶段从无频谱恢复底部白条，后续静音收回，63动态层实际发布/绘制；频谱缺失首门退出，背景十字… |
| `3744157078` | 老人-边缘行者 动态壁纸 [带鱼屏4K] | 18(0) bool 12 color 1 combo 2 group 3 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 宽屏人脸横幅、前景人物、暗周边、光线/粒子与时钟均在。作者预览彩条缺席已由相关父/子默认关闭解释，退出缺层候选；横幅短时撕裂有作者效果/phase因素，未定闪… |
| `3745828537` | 麻匪 xraypad-眠 | 76(45) bool 7 color 11 combo 4 slider 11 text 37 textinput 6 | `degraded-runtime` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` 2026-10-20 | 径向模糊1042保原恢复；10-20普通Sprite coverage准入后，51/65实际花簇恢复至左右/四角，人物与原花层保持，默认particle4/4… |
| `3746422401` | 麻匪 泠泠泉心 21:9 16:9 | 43(8) bool 5 color 3 combo 1 slider 6 text 28 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-20 | 450.visibility向image479写font的旧typed VM首拒已退出；默认同输入异常1→0，公开字体7→4同surface/window热切… |
| `3747190633` | 【凡人修仙传】银月 惹人怜惜 | 16(0) bool 4 color 3 combo 1 slider 8 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3747492842` | [4k]Leon S Kennedy X-ray \| Resident Ev… | 67(33) bool 20 color 11 combo 1 group 6 scenetexture 4 slid… | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:effectConstant` | `scenescript` | `fail` 2026-09-08 | 文字错位部分修复；额外闪烁、光束位置与 viewport 裁切未通过 |
| `3747595588` | 2K  芙莉莲 Frieren: Beyond Journey's End | 3(0) bool 2 color 1 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3748311238` | 大 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 10-19轴域后继已取得同动态宽频PCM修前/候选2/6/8s实图：柱盖高端平台退出、继续移动及圆角恢复，主体保持；用户最新App实测正常并撤回低/缺/卡观察… |
| `3748513141` | 补 深度视差 菲伦 Fern | 6(0) bool 2 color 3 slider 1 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3749463715` | 还能在大 ∑ 2 | 3(0) bool 1 color 2 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` | 2026-10-18用户补报（待当前身份复验）：观感帧率低，重复胸部拖动仍仅首次响应；交互与性能分开验，观感不等于已测FPS。 |
| `3749851384` | 朝凪 女月枫 水手服 | 6(0) bool 4 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3750312644` | 电锯人 蕾塞 Chainsaw Man Reze | 6(0) bool 5 color 1 | `degraded-runtime` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` |  |
| `3750342273` | Night snowy mountains | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 10-19当前0ea907d9a对应App原包全尺寸七点受控输入，山体左右/上下响应并回中心、零深度文字固定，独审一致；完全缺渲染视差未复现，无新产品修复。真… |
| `3750813609` | Asian Temple in the Mountains | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 2026-10-18用户补报（待当前身份复验）：雨弱、时钟样式不对；可能缺雷电但用户不确定，保持不确定性，不认定当前已证缺失。 旧记录：山寺构图、雾与落叶与预… |
| `3751548217` | 补 孤独摇滚！后藤一里 波奇酱 Bocchi The Rock! Gotoh … | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3751630571` | 补 孤独摇滚！伊地知虹夏 BOCCHI THE ROCK! Ijichi Ni… | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3751642956` | 补 孤独摇滚！比心 喜多郁代 BOCCHI THE ROCK! Kita Ik… | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3752078227` | 补 原神 八重神子 Yae Miko  X-Ray | 4(0) bool 2 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3752531443` | 补 小鸟游星野 Takanashi Hoshino | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3754630802` | WLOP [ChineseNewYear 7] | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 10-18通用蒙皮源XYZ保真修正：官方固定姿态仅Z清零与旧native对应，候选固定闭眼恢复，原包一次14s实际两次开→闭→开；此前34s未命中与旧协议失败… |
| `3754639143` | WLOP 银月 | 2(0) color 1 combo 1 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3754908581` | DJGun Making Noise!(Lite) | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 人物、时钟、背景文字呈现；未把作者绿色脸框当引擎故障，交互与参数完整性未验。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状态… |
| `3757555836` | 名将杀【兰汤春酽_赵姬】限制级8K | 3(0) bool 1 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3761050403` | 补 MyGO 长崎素世 Soyo Nagasaki 右上角防社死开关 | 2(0) bool 1 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3761159935` | 【诛仙】陆雪琪 等待的沉默 | 8(0) bool 4 color 2 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3761619125` | 麻匪 雪竹 | 78(16) bool 8 color 7 combo 2 slider 11 text 47 textinput 3 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3762312138` | Elf x Goth | 2(0) bool 1 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3763312650` | 补 素晴 惠惠 Konosuba Megumin めぐみん | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3763323436` | 3763323436 | `missing-project` | `blocked` | `resource-load / SceneProjectLoader / project-json-missing / project-entry` | `texture-load` | `unreviewed` | 行政入库备注（2026-10-17）：当前同ID目录仅见shaders残留，缺project.json与scene.pkg，本轮未运行。保留旧archive的… |
| `3763428294` | 秧秧·玄翎1\|\|穗穗\|\|舟行画中，心随风远\|\|鸣潮 | 48(22) bool 16 color 7 group 4 slider 9 text 10 textinput 2 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:visibility` | `scenescript` | `unreviewed` |  |
| `3764725758` | Lumine_HuuOliv | 2(0) bool 1 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 10-18最终App两成员组/上部构图保持；旧光束/眼睛未闭，非整景PASS。 原记录：U01光束与眼睛反馈未闭；本轮目标已执行，尚缺确定可归因ROI，不记新… |
| `3765760121` | 【4K】三色堇与她 | 9(5) bool 5 color 1 combo 1 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 倒置已修，整样本未全面验收；2026-10-17后验：同签名final App、作者选项newproperty=2单次9s/after5，reader/灯/蓝… |
| `3765904723` | 调月莉音 | 8(0) bool 5 color 1 slider 1 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3766299002` | 麻匪 皓风琦修罗 双主题切换 | 31(2) bool 6 color 1 combo 1 slider 1 text 22 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 默认构图与官方参考接近；theme1面具true→live false、theme2 false→live true均有226/370 typed visib… |
| `3766310551` | 【完美世界】柳神 九劫焚天 | 6(1) bool 4 color 1 combo 1 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3766387484` | ARKNIGHTS ENDFIELD ARCANE CHEN XIANGYU | 15(1) bool 11 color 1 group 3 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 日期/星期/时钟恢复，其余 effect 未验收 |
| `3766403294` | 仪玄(AI) | 4(0) bool 3 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3766415113` | The last pour | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3766831622` | MyGO 长崎素世 掀裙 Soyo Nagasaki（自定义剃毛） | 4(0) bool 2 color 1 combo 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3767232084` | 谬因 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3767343314` | Universe Abstract - By: CroSsHaiR-> | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3767460992` | Magic mushroom | 14(0) bool 9 color 3 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3768020435` | Silver Wolf with media integration | 仅 schemecolor | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3768229922` | 麻匪 赤芒 音频互动 | 34(0) bool 7 color 1 text 25 textinput 1 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-invalid-argument / target:layer:visibility` | `scenescript` | `unreviewed` | 2026-10-18用户补报（待当前身份复验）：开场标识/过渡不显示；需从加载开始锁完整开场窗口与属性。 10-19原包8s邻例已见PSYCHE GEAR标识… |
| `3768724269` | ARKNIGHTS ENDFIELD 4K GILBERTA IN CLOUDS | 23(1) bool 18 color 1 group 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-20 | sunrays整key因quad100被漏准入而拒绝的首门已修：100/54同代热切、startup-false恢复，原图光束随开关消失/恢复，窗口/surf… |
| `3768903841` | Naha Gaze at Firework \| northway. | 10(0) bool 7 color 1 slider 1 text 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3769364482` | 戴拿奥特曼 强壮型【Ultraman Dyna Strong Type】dy柊明 | 6(0) bool 5 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-18 | 限定基本标量播放后验：原包默认59/effect173/pass1 rayintensity实际负→.4499919→负进入Program，五node GPU… |
| `3769688830` | Spirit Blossom Springs Ahri (Adjustable… | 21(0) bool 13 color 3 group 3 scenetexture 1 untyped 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3769761761` | Yoru and Mitaka asa | 8(0) bool 6 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 2026-10-18用户补报（待当前身份复验）：左侧向右下斜光仍缺；并入旧目标斜光观察，实际来源仍unknown。 |
| `3770444459` | 三国杀【节气 夏至 2026】8K | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 2026-10-19原包8s/after6、native、静音/outside0短窗：Root与独审亲看ready/after/目录官方，未定位可归因黑色水花… |
| `3770462923` | gt3rs@d4rk | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3773747576` | 麻匪 棘 三模式切换 | 33(0) bool 4 color 2 combo 1 text 25 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | 修后原图人物/黑柱图标/曲线与碎片保持，手臂/刀身等四个noise由透传恢复实际Program并进入末合成链；125由后续effect消费。原mix编译首错已… |
| `3775355045` | 交错战线_DAIBLOS CORE_x-ray_4K_1 | 2(0) color 1 slider 1 | `degraded-runtime` | `graph-execution / GraphExecutor / layer-source-not-ready / resolved-material-graph` | `effect-chain` | `unreviewed` |  |
| `3775373546` | 交错战线_DAIBLOS CORE_x-ray_4K_2 | 2(0) color 1 slider 1 | `degraded-runtime` | `graph-execution / GraphExecutor / layer-source-not-ready / resolved-material-graph` | `effect-chain` | `unreviewed` |  |
| `3775655074` | 原神 | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-22 | 底图、TV框与运动粒子可见；四默认compose unsupportedChildren，12个pixelate/VHS/pulse效果未有执行owner。沿… |
| `3776193909` | 崩坏3 琪亚娜 Kiana Your bra strap is showing | 2(0) color 2 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3776842481` | 原神 莫娜 Genshin Mona 鼠标互动揉胸 | 2(0) color 1 slider 1 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3777761326` | I do Anything | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3779026256` | [魔法少女的魔女审判] 月代雪 X 樱羽艾玛 音频识别 | 13(0) bool 4 color 1 group 2 slider 6 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-reference-error / target:layer:visibility` | `scenescript` | `unreviewed` |  |
| `3779107475` | 麻匪 赛驴 音频识别互动 | 25(2) bool 4 color 2 scenetexture 1 text 17 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-19 | mixed-width mix修复的独立原包复验：NF墨框、二胡驴、中文、纸纹与飞墨构图保持；短窗ready/after相同不证明完整动态或音频响应。 |
| `3779904456` | 尤诺2 \|\| 鸣潮 | 47(21) bool 15 color 7 group 4 slider 9 text 10 textinput 2 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:visibility` | `scenescript` | `unreviewed` |  |
| `3780119725` | in the rain V 31 | 13(0) bool 9 color 2 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 2026-10-18用户补报（待当前身份复验）：人物/地面/摩托中层仍不随鼠标、摩托发光过强；重新开放此范围。旧短pointer窗口前摩托/人物响应的有界证据… |
| `3780247348` | 绝区零 朱鸢  Zenless Zone Zero Zhu Yuan | 仅 schemecolor | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3780391264` | Agnes Tachyon Umamusume Neon | 7(0) bool 6 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3780940857` | 枕澜 蒂法 电脑动态壁纸 最终幻想7 TIFA Final Fantasy V… | 仅 schemecolor | `degraded-runtime` | `graph-execution / GraphExecutor / layer-source-not-ready / resolved-material-graph` | `effect-chain` | `unreviewed` |  |
| `3781299603` | Pyrois and Belle (4k) | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3781307553` | Look this | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3781757083` | 羽毛笔-天国来信・Arknights | 40(27) bool 22 color 5 combo 3 slider 6 textinput 4 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3782614820` | MYGO 女上位 素世 立希 爱音 高松灯 要乐奈 Soyo Taki Ano… | 仅 schemecolor | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` 2026-10-22 | 10-22无根authored效果背景组沿局部源裁切后，同原包/3024×1964 cover/静音/中心pointer的五人物切片接缝与四黑分隔线对齐，5组… |
| `3782650329` | 我们三 X-ray | 3(0) bool 1 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3782740481` | WLOP Violet 紫 | 9(0) bool 2 color 2 slider 5 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3784012236` | >R-18< 蔚蓝档案 Blue_Archive\|06\|飛鳥馬 トキ 时 … | 4(2) bool 1 color 1 combo 1 slider 1 | `degraded-runtime` | `resource-load / BaseImageTextureStore / base-image-texture-load-incomplete / image-layer` | `texture-load` | `unreviewed` |  |
| `3786048634` | 2B and A2 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3786185473` | ELF PARADISE～欢迎来到性夜♪色情精灵们的淫乱圣诞节特别篇～ \| … | 6(0) bool 2 color 1 combo 1 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3786330502` | 麻匪 Astra GamingGear 含羞 | 53(21) bool 15 color 4 combo 1 slider 3 text 30 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-23 | 龙形左图、白发人物、中央青色裂缝、泡泡、右上文字与左下标志均呈现；未见大缺层或黑块。 实际右下有绿色圆角频谱/媒体面板，官方参考本窗未见；媒体状态与作者属性未… |
| `3786641495` | Albedo - Look at here my master | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3787355076` | 维琳娜-申请入股 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3787382101` | 清宵 \|\| 万剑 \|\| 鸣潮 | 49(23) bool 15 color 8 group 4 slider 10 text 10 textinput 2 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:visibility` | `scenescript` | `fail` 2026-09-06 | 旧Water Waves影响人物全身的理由已被六组同构A/B否定，实际效果限于对应作者mask；该精确反馈已退出。保留09-06历史整体fail，不把过时理由… |
| `3788066613` | [Hajily-1825][R-18]2025-07-04 Fleurdely… | 25(0) bool 6 color 4 group 4 slider 10 textinput 1 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:visibility` | `scenescript` | `unreviewed` |  |
| `3788129418` | 薇欧拉 Viola ビオラ 妖精花束 | 7(0) bool 5 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3788445539` | 补 原神 纳西妲 鼠标互动口交 | 仅 schemecolor | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3788467391` | Miku and Monster | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3788645041` | 奥黛塔(破洞版) | 4(0) color 1 combo 2 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3788698200` | NFFA画风 维琳娜2（可去防封马赛克+可去时钟） | 5(3) bool 3 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3788734811` | 庄方宜-1 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 倒置已修，整体视觉等价未验收 |
| `3788897599` | ArT丨R18丨4K丨Red Q | 9(0) bool 7 color 1 group 1 | `degraded-runtime` | `effect-admission / EffectStageAdmission / unified-capability-unavailable / backend:effect-family:opacity` | `effect-chain` | `unreviewed` |  |
| `3789316755` | Fern_Frieren | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3790631363` | 三国杀【水殿香来 曹金玉】限制级 4K | 3(0) bool 1 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3790726145` | 周于希54 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3790806929` | Winter Artoria Pendragon \| Fate/Zero [… | 2(0) bool 1 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3790956325` | 骚暖暖 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3791905266` | Dohrn's  Vision | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3791967416` | 麻匪 虎符电竞 兰 16:9 21:9 | 55(5) bool 10 color 8 combo 1 slider 2 text 33 textinput 1 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-invalid-argument / target:layer:visibility` | `scenescript` | `unreviewed` |  |
| `3792249095` | Beth's Wallpaper | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 2026-10-18用户补报（待当前身份复验）：外圈样式差异大；并入旧U11，尚未锁同声源/phase，不直接改半径或相机。 |
| `3792400801` | Girl \| Dark Background \| Dark / Color… | 9(0) bool 7 color 1 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3792745102` | 原神 莫娜 鼠标互动小黄油 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3792817546` | 小羊不吃草 (地雷系)#滕子京大王 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3793328876` | 大凤Taihou&白凤Hakuhou-HanAI | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3793978239` | 埃吉尔掰穴 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3793998447` | 枕中梦 | 8(0) color 2 slider 6 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3795384177` | 亡灵法师-马莫尼勒 | 4(0) bool 2 color 1 text 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-22 | 人物三clip实际叠加推进，五粒子层和音圈可见；122/116 count-only mapsequencearoundcontrolpoint因省略字段跳过… |
| `3796588443` | ZZZ 薇薇安 法厄同 Vivian Belle 鼠标互动揉胸 | 15(0) bool 11 color 2 group 2 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3797217144` | 迪迦奥特曼 出场动画 镜头视差【Ultraman Tiga】dy柊明 | 10(0) bool 5 color 2 group 1 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | U09整组冻结首反馈已闭：原响应选项保留，基本放大/转正入场恢复；平滑、时相和整样本未验。 |
| `3800075350` | 三角洲三小只-RX | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3800356808` | Warmth Valley Misty \| northway. | 15(0) bool 9 color 1 combo 1 slider 3 text 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3800572533` | [4K \| Day/Night] Neuro and Evil (by Ar… | 9(6) bool 2 color 1 combo 1 slider 5 | `degraded-runtime` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` |  |
| `3800728730` | 浮士德ego穴 | 2(0) bool 1 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3801294161` | Reze - Let's turn off the lights | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3801984224` | 粉红护士 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3802005866` | 绝区零 维琳娜 西域风 Zenless Zone Zero Velina | 3(0) bool 2 color 1 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` | 10-18父本地组源首门已修；原包蓝条/框外白细线消失、音频保持。整景/HDR/phase/性能未裁决。见#composition-member-bounds… |
| `3802537611` | 药屋少女的呢喃 猫猫 maomao The Apothecary Diarie… | 2(0) bool 1 color 1 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3803087940` | 原神 少女黑丝玉足 X - ray NSFW 差分 | 4(0) bool 1 color 1 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3803482159` | Black Morpho | 6(0) bool 5 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3803576671` | NFFA画风 冰雪公主（可去防封马赛克+可去时钟） | 5(3) bool 3 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3804171526` | 补补 女神异闻录5 芳泽霞 Persona 5 Yoshizawa Sumire | 仅 schemecolor | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3804441338` | Misty Summit 2 \| northway. | 7(0) bool 4 color 1 slider 1 text 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3804899284` | 英雄联盟 格温 LOL Gwen  冰雪节限定 口交 深度视差 | 仅 schemecolor | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3804906814` | 瞳中星火 新约能天使 明日方舟 4k60fps 组件自定义 【bilibili… | 40(12) bool 8 color 7 combo 2 group 6 slider 17 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3804930129` | 【代投稿@雪碧】英雄联盟 格温 LOL Gwen 调教/鼠标互动开关（开关默认… | 3(0) bool 1 color 1 slider 1 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3804971850` | Mobius梅比乌斯4 | 8(0) bool 7 color 1 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:visibility` | `scenescript` | `unreviewed` |  |
| `3805449677` | 御图网-浅雾藏山语 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3805547608` | 碧蓝航线 金鹿号【R18版/语音/多功能壁纸】-B站慕慕慕慕斯小蛋糕1.0 | 30(0) bool 12 color 3 combo 1 group 2 scenetexture 7 slider… | `degraded-runtime` | `graph-execution / GraphExecutor / layer-source-not-ready / resolved-material-graph` | `effect-chain` | `unreviewed` |  |
| `3806006894` | 三角洲行动露娜天际线_LUNA_4K动态初版FLYSMALLPIG | 2(0) bool 1 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3806016969` | 三角洲行动红狼蚀金玫瑰_黑金_动态版4K_FLYSMALLPIG | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3806202923` | Azur Lane 碧蓝航线光辉 | 6(0) bool 5 color 1 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3806222046` | 菲伦 Fern  深度视差！双背景图切换 Dual‑background to… | 5(0) bool 4 color 1 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3806337293` | 初音未来 hatsune miku 3d视差 4k | 17(0) bool 5 color 2 group 2 slider 8 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` 2026-10-18 | 2026-10-18灰层/过曝/缺环及后补路径整体自转已分别真实复现并修正；固定椭圆路径与条目移动保持，非完整样本/官方相位验收。 |
| `3806836928` | 老人-妆容少女暗黑系[4K] | 6(0) bool 5 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-22 | 底图、前景、音圈、时钟日期及尘埃可见；Consolas→Menlo为字体回退，精确字形未验。两Simple Audio Bars默认关闭。 本轮20s/30F… |
| `3807013762` | Frieren | 7(0) bool 5 color 1 combo 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3807121855` | 鸣潮今汐-桃花鸢 | 10(0) color 2 group 1 scenetexture 1 slider 6 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3807151772` | MyGO 长崎素世 Soyo 鼠标互动 捧脸 | 4(0) bool 2 color 1 slider 1 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3807239614` | 清霄&心 | 4(0) bool 2 color 1 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3807436394` | Ronova | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3807553861` | Albedo - After the bath | 仅 schemecolor | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3807668787` | 霜翼剑使 | 2(0) color 1 text 1 | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` | 2026-10-18头冠/音频原反馈保持已闭；958 A2C候选虽实际GPU绘制，未确认原包拖尾恢复。官方连续pointer末点短白线也未唯一归958；原型已… |
| `3807861954` | 鬼方 カヨコ | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3808121562` | Divine Rift | 7(0) bool 6 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3808922316` | 麻匪 Elisa | 38(14) bool 8 color 3 combo 1 slider 1 text 23 textinput 2 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-internal-error / target:layer:visibility` | `scenescript` | `unreviewed` 2026-10-19 | 2026-10-29 log-only短窗：原995/1763排序InternalError已退出，679/995/1763初始化均completed，纯SO… |
| `3809034761` | 白丝·斜身侧立[4K] | 24(19) bool 10 color 3 group 2 slider 9 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3809541486` | Moon Princess | 6(0) bool 5 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3809609151` | League of Legends Gwen \| 6 character p… | 9(0) bool 6 color 2 combo 1 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3809618616` | 芒果青青 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3810092560` | DeepSeek 鲸鱼娘 点击互动 | 仅 schemecolor | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` 2026-10-22 | 重复小图与右侧大图符合作者预览布局；25scale/cursor owner装载且无VM异常，未点击，不能判交互unsupported；隐藏hitbox不直接… |
| `3810943704` | Empress of Grace (Commission; Adjustabl… | 38(0) bool 30 color 4 combo 1 group 3 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3811154012` | 麻匪 Uncle Panda 残叙 | 36(0) bool 4 color 1 slider 2 text 28 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3811216799` | Nikke - Guilty (Mighty Bunny) Desktop A… | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3812249745` | 完美世界-九劫柳神 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3812473896` | 原神芙宁娜-水畔芙谣[Furina's Ballad by the Water… | 52(0) bool 3 color 7 group 6 scenetexture 1 slider 35 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:visibility` | `scenescript` | `unreviewed` |  |
| `3814040466` | Nikke - Privaty - Sharp Lesson | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3815761795` | 明日方舟・夕｜画桥（4K） | 13(0) bool 7 color 3 combo 1 textinput 2 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` 2026-10-23 | 原包20s/after16、30FPS/静音，人物、伞、雨、云景及右下青色装饰呈现并推进，未见明显主体/背景缺失；独立候选运行保持，正常stop1→0/GPU… |
| `3818943255` | 美女肚兜 | 3(0) color 1 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 新发现后复用同签名App单次默认direct短播放：1image/0effects、0.971s ready，实际图像呈现、exit0/stop1→0/GPU… |
| `3820312181` | Void Edge Theme R6S [High Resolution] | 4(0) bool 2 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 10-17原包默认参数的右上缺光已恢复：sampler presence误用editor条件的首错退出，17/effect1真实Program/GPU/末合成… |
| `3822255386` | 绝区零 X-ray/liang xing | 3(0) bool 1 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-22 | 单图X-ray在中心pointer默认参数下实际GPU/末消费，未定位该条件下明显缺陷；开关/size/鼠标轨迹尚未测试。 本轮20s/30FPS固定PCM、… |
| `3822822401` | 麻匪 穿云 | 59(12) bool 12 color 5 slider 9 text 32 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-21 | 戏曲人物、举扇、圆月、荷花、竖排中文时间/日期及红色印记均实际呈现，未见大片主体或背景缺失。 用户明确纠正：蝴蝶有延迟，本次早截时尚未出现；用户既往测试正常。… |
| `3823874401` | 消亡-小鸟游星野 | 5(1) bool 2 color 2 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3824039822` | 刀剑-红瞳落樱 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3824111011` | Melancholy Malfoy | 7(3) bool 3 color 3 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3824616954` | Maids 女仆的日常检查 | 4(0) bool 2 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3824617466` | Sunbringer (ZZZ) | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3824936757` | Talia Yang cyberpunk anime 4k | 4(0) bool 3 color 1 | `degraded-runtime` | `graph-execution / GraphExecutor / layer-source-not-ready / resolved-material-graph` | `effect-chain` | `unreviewed` |  |
| `3825170583` | 少女 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3825183869` | 超绝最可爱天使酱の性爱纪念Live 【代投稿@雪碧】超天酱，糖糖，主播女孩重度… | 3(0) color 1 slider 2 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `3825275744` | Saturn by Anwyse | 6(0) bool 5 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3825309870` | Kiana Kaslana | 5(0) bool 3 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3825819266` | 142705227_p0 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3826712704` | 碧蓝档案qos | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3826951629` | 148806710_p1 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3827026934` | cimoc 仪玄 | 3(0) bool 1 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3827042397` | Melowh Tatsumaki Witch (One Punch Man) … | 21(15) color 2 combo 4 slider 9 text 5 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3827071121` | Foyege-Draconia Malfoy | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3828725306` | MyGO 长崎素世 Soyo 拍立得 | 3(0) bool 1 color 1 slider 1 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` |  |
| `833227004` | 星云变换t001 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
