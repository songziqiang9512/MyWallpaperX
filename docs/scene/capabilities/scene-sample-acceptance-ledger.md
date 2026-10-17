# Scene 样本验收台账

> 状态：现役验收事实。本页由 `script/scene_sample_acceptance_ledger.py` 生成；视觉裁决只来自 `script/scene_sample_acceptance_verdicts.json` 的人工记录，不要手工编辑本页。
>
> 最终验收门：每个样本在真实播放中正确显示与播放，且作者参数（project.json user properties）全部进入播放链路。
>
> 归档运行状态和首断点只描述对应执行身份的安全/结构事实，不是视觉正确性；`structural-chain-complete-visual-review` 仍需人工验收。集群只用于排序公共首断点，样本身份不得进入产品代码或现役路线正文。

## 1. 来源

- 样本根：`/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Scene`（301 个 sample 目录）。
- 运行归档：`scene_sample_debug_archive.json` SHA-256 `41f778a837d307291a408edeb1a472a4fd933913ce47fb722073b7093d23e26f`（生成于 2026-10-17T03:20:28.462529+00:00）。
- 归档运行身份：CDHash `918475e7b5ab8933c1d54c9a0b4caef9ff291521`、CDHash `a31bd68aa2e84050c26bb5aa1a8d8383b85c743a`、CDHash `29c3c09c573ec0803ce9ab44434578d1ae6fd3bf`、CDHash `d8e9aa707027fa62e4081cc10202aea9a8e76e7e`、CDHash `9fe554ffa22e9ace078be9b6cc385a40cec899cb`、CDHash `46aff1be5b9026dd015fb14a7e07fbdd0c204a9e`；**归档内不止一个执行身份**，运行状态与首断点因此是混合身份事实，单样本结论必须回到该样本自己的 report 身份。
- 裁决覆盖层：`scene_sample_acceptance_verdicts.json` SHA-256 `4961820756f357629455aeb47547237b3ea60d6e6de78a280d2824ddf428ca3d`。
- 本页生成于 2026-10-17T07:05:32.751568+00:00。

本页生成日仅表示台账生成，不表示归档运行或人工裁决已重新验收。旧归档首断点可能已在后续开发中修复；最新技术状态以[断点队列](../roadmap/scene-open-breakpoint-queue.md)和[运行证据](runtime-evidence-current.md)为准。`not-run` 仅表示本归档未关联运行证据，不表示样本从未运行；归档中的失败状态也不等于当前 HEAD 的失败。

## 2. 汇总

| 原人工裁决 | 样本数 |
|---|---:|
| `unreviewed` | 282 |
| `pass` | 0 |
| `fail` | 19 |
| `platform-unsupported` | 0 |

| 官方对照状态 | 样本数 |
|---|---:|
| `unknown` | 280 |
| `not-run` | 0 |
| `blocked` | 0 |
| `compared` | 21 |

- 已裁决但缺观看者身份的条目：**19**；已裁决但缺截图/视频身份的条目：**19**（P0.2 `sample → verdict` 关系要求的字段；缺项保持 `unknown`，不由生成器补写）。此处只统计**裁决自己引用的** run/截图身份，与 corpus 清单（docs/scene/capabilities/scene-corpus-capability-inventory.md）的「人工对照」列（样本目录自带的用户截图 `截屏*.png` 与 `用户观察说明.md`）不是同一事实，两页不可互相替代。

| 归档首断点集群 | 含义 | 样本数 |
|---|---|---:|
| `effect-chain` | effect 准入 / 颜色合同 / graph 执行 | 11 |
| `particle-load` | 粒子层资源加载 | 11 |
| `texture-load` | 基础图片纹理加载 | 6 |
| `scenescript` | SceneScript 异常 | 12 |
| `terminal-output` | terminal compositor / 输出链 | 0 |
| `visual-review` | 结构链完整，待视觉验收 | 140 |
| `not-run` | 未关联本归档运行证据 | 121 |

| 归档运行状态 | 样本数 |
|---|---:|
| `blocked` | 2 |
| `degraded-runtime` | 39 |
| `not-run` | 121 |
| `runtime-evidence-incomplete` | 1 |
| `structural-chain-complete-visual-review` | 138 |

作者参数：222 个样本声明了 schemecolor 之外的用户参数，共 7289 项，其中 2547 项带 `condition`。参数进入播放链路的验收随各样本的视觉裁决一起记录，不单独计数。

## 3. 逐样本

归档首断点格式为 `stage / owner / reasonCode / profile`。作者参数列为 `总数(condition 数) 类型分布`。

| 样本 | 标题 | 作者参数 | 归档运行状态 | 归档首断点 | 归档集群 | 原人工裁决（日期） | 备注 |
|---|---|---|---|---|---|---|---|
| `1195626192` | Gaze | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `1300076567` | 阳光少女 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1315486372` | 貂蝉拜月 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 水波位置不正确、光线贴图效果生硬 |
| `1439846152` | 腿 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1480826543` | Emilia X-ray NSFW | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1507413154` | 百褶裙 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1507593643` | 蕾丝吊带 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1511889295` | 死库水 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1553008362` | [Jidan Hua] Ichigo and 002 (Darling in … | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1636394814` | [Jaku Denpa] Shigure (Kantai Collection… | 4(0) bool 1 color 1 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1695673397` | 白发少女 4k动漫壁纸 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 当前仅补登/同构建回归；主体、羽毛和雪呈现，顶部灰带沿用已锁同宽高比官方也有的边界，不重新排故障。 与目录官方截屏仅作基础构图对照；viewport、时相、媒… |
| `1926190458` | Morning_4k | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `1937925563` | Tropical Paradise 4K [Customizable Colo… | 8(0) color 6 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1989767609` | Black tights（透视） | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1994794519` | D.VA_OVERWATCH[X-Ray] | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2067939514` | Windows Visualizer | 34(27) bool 12 color 9 combo 5 scenetexture 2 slider 6 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2069136288` | [R18] Lexaiduer DOA Nagisa x Tamaki X-R… | 3(0) color 1 combo 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2112262451` | [R18] Sakimi Chan Azur Lane Belfast X-R… | 4(0) color 1 combo 2 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2131872317` | Night Market by 俊伦 何 in 4K | 7(0) bool 3 color 1 slider 3 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2134765860` | Bunk | 34(18) bool 14 color 7 combo 3 group 4 slider 5 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2163522240` | [18+] jk x-ray 🔞😍 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2179185481` | Azur Lane / 18+ X-ray NSFW & SFW (3 Ver… | 4(0) bool 3 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2181251652` | Mio Tokisaki (X-Ray) | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2231088993` | Ahri X-Ray | 2(0) color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2241938645` | KDA Akali [4k Version] | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2269193950` | WLOP - Nap | 4(0) bool 2 color 1 combo 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2304304373` | Don't Die | 5(0) color 2 combo 1 slider 1 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2347762662` | 18+ X-Ray │NSFW & SFW│ ♥ 여대생♡ PT 2 ♥ ( … | 6(0) bool 4 color 1 slider 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2356604986` | 1265079-1322607782 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2419444134` | Nier Reincarnation - Akeha | 6(0) bool 5 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2470144420` | 女孩独享的宁静傍晚 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2473638329` | Genshin Impact \| +18 / NSFW & SFW | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2505351195` | Nier Automata / +21 \| NSFW & SFW | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2524111047` | Liu Meryl Wei wei（被举报下架-重发） | 5(0) bool 4 color 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2607203340` | Tomb Raider +18 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2616828675` | 【R18】别看了，快点啦~#4K#动态#16:9 | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `2684431262` | 麻匪 炫酷音频律动 Windows | 28(0) bool 4 color 12 slider 1 text 11 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2775915974` | R18*JK(escalator)エスカレーターJKさんX-ray | 4(0) bool 1 color 1 combo 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 鼠标纵向与顶部边界已修，顶部极限仍露灰边；整样本未通过 |
| `2776912698` | 麻匪 洛天依 Android | 29(0) bool 11 color 15 slider 1 text 1 textinput 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2780710296` | 麻匪 miku 初音ミク 初音未来 Windows | 27(0) bool 9 color 5 slider 1 text 11 textinput 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2794098047` | 麻匪 是姐姐还是妹妹 windows | 34(12) bool 5 color 10 combo 2 slider 5 text 12 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2797913147` | 【R18】连体黑丝#4K#视差#可互动臀部#动态 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2802243144` | 冰公主-by Wlop 时间日期已修复 16:9 -music 订阅后点赞，养… | 14(0) bool 7 color 2 slider 5 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2804817823` | Yor Forger \| Spy x Family | 4(0) bool 2 color 1 slider 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2807058277` | 麻匪 森美声 森カリオペ  Windows | 28(0) bool 8 color 6 slider 3 text 10 textinput 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2808874251` | youer | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2811643059` | 原神 | 4(0) bool 2 color 1 slider 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2813231542` | 清新美女 R-18 | 9(0) bool 7 color 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2815826216` | 麻匪 约尔·福杰 间谍过家家 SPY×FAMILY | 34(13) bool 7 color 13 slider 2 text 11 textinput 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2824109832` | Yor Forger - NIXEU 4K | 16(7) bool 12 color 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2824690710` | 麻匪 原神 雷电将军 Windows 16:9 21:9 | 36(18) bool 11 color 19 slider 4 text 1 textinput 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2834973884` | 麻匪 wlop-鬼刀 重置版 | 22(0) bool 5 color 3 slider 3 text 11 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2837223712` | 李擎洲：阿狸[4K] | 2(0) bool 1 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2849382252` | 麻匪 死亡笔记  L·Lawliet | 16(0) bool 2 color 3 text 11 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2877855240` | 麻匪 雷电将军 泳装 | 57(34) bool 13 color 20 combo 1 slider 12 text 3 textinput 8 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2884628849` | 麻匪 小姐姐 | 29(0) bool 4 color 4 combo 5 slider 4 text 12 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2887542690` | 麻匪 礼服斯卡蒂 3D版 | 28(0) bool 9 color 9 combo 1 slider 3 text 5 textinput 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2890473419` | 麻匪 肉肉的雷电将军 3D 21:9 16:9 | 29(0) bool 8 color 7 combo 2 slider 9 text 3 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2896873092` | Genshin Impact: Thicc Girls Spread Coll… | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2902406982` | 麻匪 月半与鬼哭 所有元素自定义 | 173(103) bool 20 color 45 combo 8 scenetexture 2 slider 35 … | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2913492057` | 麻匪 粒子音频互动 | 16(0) bool 5 color 3 text 8 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2917306763` | [4K/动态/R18/衣服透视可调]碧蓝航线-独角兽妹妹「天使的护理时间」-B… | 3(0) bool 1 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2932157836` | [4K \| 可自定义] 星浴 \| Hoshi-yoku | 123(101) bool 36 color 13 combo 1 slider 71 textinput 2 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2932631210` | 欧派-音乐乱动 | 13(0) bool 8 color 3 combo 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2938612768` | 麻匪 音频识别 Media Player | 79(35) bool 16 color 11 combo 5 scenetexture 4 slider 13 te… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2942486721` | R18 Ishtar And Ereshkigal / 遠坂  凛 Tohsa… | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2949019513` | [4K \| 可自定义] A.R.O.N.A.    (碧蓝档案) | 41(20) bool 23 color 3 slider 15 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2959875782` | [R18] Lexaiduer Last Origin Dark Elven … | 4(0) color 1 combo 2 slider 1 | `degraded-runtime` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` |  |
| `2960821850` | Media Player (2.0) | 5(0) bool 4 color 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2964778792` | [4K/动态/R18-3.0版]碧蓝航线-莱莎琳·斯托特「熬夜的炼金术士」补档… | 4(0) bool 1 color 1 slider 2 | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` 2026-10-17 | 主体呈现；active世界空间粒子63的动态origin拒绝，74 cursor播放调用随后失败，属同一上游缺口。 与目录官方截屏仅作基础构图对照；viewp… |
| `2974757317` | 麻匪 音频识别 悬浮窗 Media Player | 80(35) bool 13 color 17 combo 3 scenetexture 5 slider 16 te… | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` |  |
| `2981249186` | 4K SCI-FI Black Hole | 8(0) bool 5 color 1 slider 2 | `not-run` | - | `not-run` | `unreviewed` |  |
| `2983846453` | 麻匪 自定义双背景开关 - Customizable Day/Night Sw… | 40(15) bool 3 color 8 combo 2 scenetexture 2 slider 10 text… | `not-run` | - | `not-run` | `unreviewed` |  |
| `2986218263` | Tokisaki Asaba & Tokisaki Mio │18+ X-Ra… | 6(0) bool 5 color 1 | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` |  |
| `2998757800` | 碧蓝航线-利托里奥【R18版/可触摸/天气变化】-B站慕慕慕慕斯小蛋糕 | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3002649614` | 纯欲少女 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3021013015` | 赛博color-墨侠客行 | 2(0) color 1 slider 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3022080536` | 赛博color-宣纸国画-紫罗兰永恒花园 | 2(0) bool 1 color 1 | `degraded-runtime` | `resource-load / BaseImageTextureStore / base-image-texture-load-incomplete / image-layer` | `texture-load` | `unreviewed` 2026-10-17 | 10-17静态format9/20B mesh修正后，原包奶油纸底、书法与双红印已恢复，主体18旧52B动画保持；不再列背景灰底/装饰缺失。与目录官方仅基础构… |
| `3025969015` | 黑龙闹海 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3028090166` | WLOP [Tian Nan2] | 2(0) bool 1 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3039882306` | 麻匪 音频识别 抽签 Media Player | 49(10) bool 11 color 9 combo 1 scenetexture 2 slider 2 text… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3042492564` | [4K \| Customizable] Hoshi-Tele \| 星屑テレ… | 249(203) bool 76 color 18 combo 8 slider 127 text 10 textin… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3078285611` | 麻匪 金克丝 jinx 音频识别 Media Player | 53(13) bool 10 color 10 slider 11 text 22 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3088601835` | Winter Wanderer Xayah - League of Legen… | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3113287126` | Dome 4k {Artwork by WLOP} | 8(0) bool 6 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3113554287` | 【可随时间变化】窗旁の伊蕾娜   （优化版本） | 7(1) bool 3 color 3 combo 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3115163440` | Shadow Garden (X-Ray) | 4(0) bool 2 color 1 slider 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3122339805` | Pixels | 39(0) bool 9 color 6 combo 1 scenetexture 3 slider 1 text 7… | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-bad-return / target:text:content` | `scenescript` | `unreviewed` |  |
| `3141421197` | GraspOfTheAbyss | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3146507587` | こきん【吉罗】 | 3(0) bool 1 color 1 slider 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3147346398` | ⛏🧱Minecraft Lo-Fi Fireplace [4k HDR] WE… | 21(12) bool 8 color 3 combo 1 slider 5 untyped 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3167210190` | [Blue Archive] 奶牛装明日奈 | 7(0) bool 5 color 1 group 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3173418061` | Persona 5/女神异闻录5 音乐播放器 | 2(0) color 1 slider 1 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:effectConstant` | `scenescript` | `unreviewed` 2026-10-17 | 已修mix首错：7条effect scale恢复；56标题按下/释放反馈可见，hover保持。主体与文字正常，其他播放/交互及官方同phase未验。 |
| `3211615441` | 捆绑悬挂 \| Bind & Suspend [ 可交互/interactiv… | 26(12) bool 7 color 1 combo 5 group 4 slider 4 text 4 texti… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3219398263` | Acheron Black Hole (StarchaserArt) | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3226487183` | 麻匪 花火 五角色自定义 崩坏星穹铁道 Sparkle Honkai: Sta… | 55(9) bool 14 color 8 combo 1 slider 5 text 27 | `not-run` | - | `not-run` | `unreviewed` 2026-10-17 | 10-17原包三批恢复：合法reference保留侧脸主体组装，MDLV19命名挂点使中央脸颈接合及右面具归位；本批严格读取MDLA5逐骨alpha，单贡献轨… |
| `3232289987` | 【4k 高度自定义】流萤&萨姆  丝袜可更改——夜莺Night【崩坏星穹铁道】 | 116(60) bool 34 color 18 combo 4 scenetexture 2 slider 41 t… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3233141951` | 熠烛 御剑驭龙-红鸾樱落 高度自定义Red Warbler-Sakura fa… | 67(0) bool 18 color 7 combo 3 group 1 scenetexture 1 slider… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3238423642` | Katana Girl with Hologram (Adjustable; … | 90(0) bool 35 color 25 combo 9 group 12 slider 8 untyped 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 头部错位已修，整体视觉与约 18.7 FPS 帧时间未验收 |
| `3248220186` | 麻匪 音频粒子球 Audio Particle Ball 16:9 16:10… | 44(8) bool 6 color 6 combo 4 slider 7 text 19 textinput 2 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3264246690` | 麻匪 wlop 鬼刀 月牙儿 16:9 16:10 21:9 32:9 | 70(21) bool 16 color 7 combo 2 slider 14 text 25 textinput 6 | `degraded-runtime` | `resource-load / BaseImageTextureStore / base-image-texture-load-incomplete / image-layer` | `texture-load` | `fail` 2026-09-08 | 人物左肘缺块；构图未验收 |
| `3287715210` | 发光少女 4K动态壁纸 | 17(1) bool 1 color 1 group 1 slider 14 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 音频条已恢复（PCM fixture），真实系统音频与整体未验收 |
| `3290491250` | frieren | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3291326967` | 蒙眼少女 4K动态壁纸 | 18(0) bool 1 color 1 group 1 slider 15 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 人物、雪粒子、日期与频谱呈现；未定位大面积主体缺失，完整参数与同状态细节未验。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状… |
| `3299228616` | Lonely Cat: Audio visualizer , Clock , … | 64(60) bool 26 color 13 combo 13 slider 12 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3323988600` | Hentai Goddess of Victory Nikke ANIMATE… | 9(0) bool 4 color 1 slider 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3337494481` | 麻匪 3D交互音频模块 媒体识别 Media Player 16:9 16:1… | 82(59) bool 17 color 20 combo 6 scenetexture 1 slider 9 tex… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3341111071` | 麻匪 初音未来 MIKU 海边 32:9 21:9 16:9 16:10 | 32(8) bool 7 color 4 slider 2 text 18 textinput 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3351163962` | [高度自定义] 樱花庄的宠物女孩 椎名真白 | 187(154) bool 31 color 26 combo 22 scenetexture 4 slider 86… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3351179520` | 麻匪 東京喰种 高槻泉 媒体识别 Media Player 16:9 16:1… | 74(46) bool 13 color 9 combo 5 scenetexture 1 slider 12 tex… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3357627941` | 麻匪 开门见喜 鼠标交互 自定义本地文件 Windows door 16:9 … | 30(1) bool 4 color 2 combo 1 scenetexture 2 slider 1 text 20 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3363252053` | 【Parallax视差】Hatsune Miku 初音未来 光与影——夜莺Ni… | 97(39) bool 28 color 15 combo 4 group 6 slider 33 text 8 te… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3374523158` | 麻匪 极光音频响应式 交互壁纸 Aurora audio-responsive… | 87(54) bool 7 color 25 combo 5 slider 25 text 23 textinput 2 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3389974179` | 落日与白皙的大腿 | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3395392965` | 请叫我帅锅-小姨定制 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3395777145` | 麻匪 光 音频识别 Media Player 16:9 16:10 21:9 | 74(26) bool 14 color 10 combo 5 scenetexture 1 slider 11 te… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3396722575` | 麻匪 NIXEU 黄泉 超多自定义模块 音频识别 Media Player 1… | 132(71) bool 22 color 17 combo 3 slider 47 text 40 textinpu… | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` |  |
| `3420215721` | 麻匪 圈 媒体识别交互壁纸 Circle Media Player | 87(21) bool 12 color 9 combo 3 scenetexture 1 slider 21 tex… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3435573282` | 麻匪 巳蛇 自定义动画 音频识别 Media Player | 82(23) bool 14 color 10 combo 2 slider 16 text 39 textinput… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3437487219` | 3D Earth - Close Orbit   [HDR10 Optimiz… | 15(2) bool 3 color 1 combo 2 group 3 slider 6 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 日期时间恢复，cursor owner collision 未闭合 |
| `3446316682` | 【完美世界】柳神 无敌道 | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3448845950` | 麻匪 媒体音频标签【148项自定义】Media Player 16:9 16:… | 152(35) bool 22 color 17 combo 14 scenetexture 2 slider 20 … | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:effectConstant` | `scenescript` | `fail` 2026-09-08 | 黑屏已解除，脚本效果与整体布局未通过 |
| `3448877775` | 【Time Variation 时间变化】Alone 孤独の少女——夜莺Nig… | 145(62) bool 38 color 19 combo 6 group 9 scenetexture 1 sli… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3470948192` | 水滴 三体 \| Droplet -SYKM | 37(0) bool 7 color 4 combo 2 group 7 slider 13 untyped 4 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-bad-return / target:layer:scale` | `scenescript` | `fail` 2026-09-08 | 开场/文字错位部分修复，仍有 NaN、文字碎片与异常背景 |
| `3471294034` | 麻匪 巳 UnclePanda [3大UI布局切换] | 86(44) bool 10 color 21 combo 4 slider 7 text 37 textinput 7 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3472940912` | -Tsukatsuki Rio [ blue archive ] - 4K | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3476868923` | 麻匪 索泰ZOTAC 天启姬 (角色双动画 点击互动) 120项自定义 | 131(49) bool 15 color 36 combo 3 slider 19 text 54 textinpu… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3477054430` | Cat with headphones on the roof | 25(0) bool 4 color 6 group 6 slider 9 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 画面显示不全；mask 已恢复，月亮/球体与文字布局仍开放 |
| `3486887298` | 风景系列-真4K【流星、夜晚】-B站慕慕慕慕斯小蛋糕 | 14(0) bool 3 color 2 group 1 scenetexture 5 slider 1 textin… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 彗星与时钟呈现；未定位大面积主体缺失，时相/布局细节及完整参数未验。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状态验收。 |
| `3487629864` | 云曦老婆 (18+) | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3507496797` | 麻匪 龙吟锦鲤赋 32:9 | 46(4) bool 10 color 4 combo 1 slider 1 text 30 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3509243656` | 三体实时演算 \| Three-Body problem - SYKM | 233(2) bool 27 color 20 combo 3 group 21 scenetexture 1 sli… | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 开场/模拟画面不正常，坐标文字异常 |
| `3549827466` | 【完美世界 火灵儿】盛典妆容 | 2(0) bool 1 color 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3554161528` | Blue Archive-Sorasaki Hina 空崎日奈[4K] | 35(16) bool 15 color 4 combo 1 group 5 slider 7 untyped 3 | `degraded-runtime` | `effect-admission / EffectStageAdmission / unified-capability-unavailable / backend:effect-family:blend` | `effect-chain` | `unreviewed` |  |
| `3562021804` | 【完美世界】石昊 以身为种 | 3(0) bool 1 color 1 slider 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3563038726` | 【凡人修仙传】梅凝  乖巧可怜 | 7(0) bool 4 color 2 slider 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3566880847` | 【凡人修仙传】紫灵 白色限定 | 7(0) bool 1 color 3 combo 1 slider 2 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3577990983` | Chainsaw Man-Reze 蕾塞[4K] | 48(33) bool 12 color 3 combo 1 group 4 slider 9 untyped 3 u… | `blocked` | `resource-load / BaseImageTextureStore / base-image-texture-load-incomplete / image-layer` | `texture-load` | `unreviewed` 2026-10-17 | 10-17中央Reze/手臂/身体经多target修正已恢复，后继原包16白块已沿同一typed source链恢复透明花叶图案；烟火/栏杆保持、最终正常退出… |
| `3581882134` | 【凡人修仙传】紫灵 冰清玉洁 | 21(0) bool 8 color 4 slider 9 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3585542943` | 【凡人修仙传】元瑶 灵泉沐浴 | 13(0) bool 6 color 4 slider 3 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3585875739` | Miku Monitoring | 6(0) bool 5 color 1 | `degraded-runtime` | `graph-execution / GraphExecutor / layer-source-not-ready / resolved-material-graph` | `effect-chain` | `unreviewed` |  |
| `3586705329` | [甜蜜女友3]柳木诗梦 | 46(5) bool 9 color 8 combo 3 scenetexture 8 slider 13 text … | `degraded-runtime` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` 2026-10-17 | 人物与拼贴主体呈现；七个active clipping效果slot1纹理用途proof拒绝；具体遮罩ROI尚未对齐。 与目录官方截屏仅作基础构图对照；view… |
| `3587571382` | 【凡人修仙传】宋玉  璀璨夺目 | 15(0) bool 5 color 3 slider 7 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3589454154` | 土星 \| Saturn - Sykm | 113(2) bool 29 color 1 group 7 scenetexture 17 slider 26 te… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3597772384` | Lost Landscape \| northway. | 138(116) bool 65 color 2 combo 3 group 4 scenetexture 24 sl… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 山景、雨和时钟呈现；active鸟粒子部分控制点force未准入，非整个粒子层失败。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚… |
| `3599986633` | 麻匪 杉泽 观山海 | 28(2) bool 3 color 2 combo 1 slider 1 text 21 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 10-17基线主幅黑幕经177.visible单次消融定位；修正空effect查询合同后，原包默认初始化自行解除遮挡，九凤人物和彩色主幅已恢复。702独立de… |
| `3601801724` | ash一爪布鲁托 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 主体已呈现；边侧裁切较紧，尚未同viewport对齐。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状态验收。 |
| `3601964477` | 千咲 \|\| 鸣潮  \|\| 枫 \|\| 4K | 44(19) bool 19 color 5 group 3 slider 7 text 10 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` |  |
| `3603711180` | 【凡人修仙传】慕沛灵 金屋藏娇 | 21(0) bool 8 color 5 slider 8 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3605502569` | 顾州-暗影魅眸｜Shadow · Charming Eyes | 33(21) bool 15 color 4 combo 1 group 3 slider 10 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3605722997` | [假装4K]魔王-追悼【可交互壁纸】（喜欢的点个赞呗） | 43(27) bool 22 color 4 combo 3 scenetexture 2 slider 9 text… | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` 2026-10-17 | 默认5s after处于入场视频；仅animation=false即恢复完整人物/建筑、camera不变，巨大取景差异退出相机故障候选。另49脚本与196/2… |
| `3609108600` | 千咲 \|\| 鸣潮 \|\| 4K | 9(4) bool 4 color 1 slider 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3610154602` | 千咲 \|\| 鸣潮 \|\| 高塔 \|\| 4K | 42(16) bool 15 color 4 group 4 slider 6 text 10 textinput 3 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` |  |
| `3612058080` | 吞噬星空-星幻王 | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3612199597` | 千咲 \|\| 鸣潮 \|\| 与千咲的穗波散步 \|\| 咖啡厅天台 \|\… | 40(17) bool 19 color 4 group 3 slider 5 text 9 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` |  |
| `3612795410` | 千咲 \|\| 鸣潮 \|\| 与千咲的穗波散步 \|\| 喷泉广场 \|\|… | 35(15) bool 16 color 4 group 2 slider 3 text 10 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` |  |
| `3616389236` | Aesthetic Media Visualizer (Shortcut) \… | 179(165) bool 74 color 13 combo 7 scenetexture 26 slider 26… | `blocked` | `process / DebugScenePlaybackRunner / process-timeout / scene-process` | `visual-review` | `unreviewed` 2026-10-17 | 10-17同公共shortcut底图修复的实际受益验收：默认8个顶部白块恢复透明链环，主幅/时钟/装饰保持；复用既有签名App单次direct运行64.200… |
| `3617056047` | 麻匪 模型音频互动 Model - audio interaction | 49(14) bool 4 color 6 combo 2 scenetexture 1 slider 7 text … | `not-run` | - | `not-run` | `unreviewed` |  |
| `3627973226` | [Sakiko Togawa]snowy night - It's MyGO!… | 18(0) bool 17 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 人物、雪景、日期与底部频谱呈现；未定位大面积主体缺失，完整参数未验。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状态验收。 |
| `3629927359` | 奶牛大鸭鸭 2 | 2(0) color 1 combo 1 | `degraded-runtime` | `resource-load / BaseImageTextureStore / base-image-texture-load-incomplete / image-layer` | `texture-load` | `unreviewed` |  |
| `3632513108` | 千咲 不散的春之花——夜莺Night《鸣潮 Wuthering Waves》 | 242(150) bool 74 color 44 combo 10 group 9 scenetexture 24 … | `not-run` | - | `not-run` | `unreviewed` |  |
| `3632522893` | Widescreen Mount Fuji Visualiser | 28(4) bool 9 color 2 group 2 slider 15 | `degraded-runtime` | `resource-load / SceneSolidTextureLoader / solid-texture-load-incomplete / solid-layer` | `texture-load` | `unreviewed` 2026-10-17 | 富士山、文字、前景呈现；active Blur whole-stage被composition childless准入拒绝，836无hook/默认隐藏独立保留… |
| `3641200550` | 樱羽艾玛 | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3655958892` | R18 Acheron & Black Swan 黄泉&黑天鹅 [Honkai… | 5(0) bool 4 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3662245960` | Wuthering Waves - Aemeath | 4(0) bool 3 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 人物与故障风格效果呈现；动态阶段及同状态精度未验。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状态验收。 |
| `3662390671` | 【Angels of Delusion】\| Sunna \| Aria \|… | 51(0) bool 11 color 7 combo 2 slider 18 textinput 1 untyped… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3662790108` | 实时太阳系 Live Solar System - SYKM | 198(26) bool 71 color 9 combo 3 group 12 scenetexture 24 sl… | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 轨道/布局已恢复，球体与曲率画面、点击交互未验收；约 8.8 FPS |
| `3663810817` | 鎏金狮影映娇颜 | 8(0) bool 6 color 1 text 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3665307769` | 爱弥斯1 \|\| 鸣潮 \|\| 4K | 51(19) bool 18 color 7 group 4 slider 10 text 10 textinput 2 | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` |  |
| `3666041758` | 麻匪 磁流体 Magnetofluid 音频相应 | 101(32) bool 3 color 14 combo 5 scenetexture 1 slider 31 te… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3680252478` | SUPRA A80 \| GREY HORIZON | 13(0) bool 11 color 1 slider 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3690065713` | 老人-棕发女孩 [带鱼屏4K] | 7(0) bool 5 color 1 combo 1 | `degraded-runtime` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` 2026-10-17 | 人物、眼部背景和默认文本均呈现；边框、媒体与视窗差异待同状态对齐。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状态验收。 |
| `3690859128` | 爱弥斯2 \|\| 鸣潮 \|\| 4K | 42(17) bool 10 color 8 group 3 slider 11 text 10 | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` |  |
| `3694697894` | 星街すいせい  星街彗星（第二版） | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3695791724` | Angel (Commission; Adjustable; 4k) MX | 51(0) bool 21 color 10 combo 3 group 6 scenetexture 1 slide… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3698459055` | 凡人修仙传-梅凝·暗系[4K] | 47(29) bool 15 color 6 combo 1 group 5 slider 20 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3699213569` | 碧蓝航线Azurlane-斯特拉斯堡&克莱蒙梭（By Adramahlihk） | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3703104370` | Rio&菲比-adoc(涟) | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3708363772` | 麻匪 3D磨砂 音频识别 Media Player | 68(15) bool 8 color 4 combo 5 scenetexture 1 slider 19 text… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3712499998` | 鸣潮 \|\| 3.3pv \| 自星海尽处回响 | 40(16) bool 12 color 8 group 2 slider 8 text 10 | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `fail` 2026-09-08 | 日期/时钟恢复，WEVector unsupported，重复文字未裁决 |
| `3719111841` | 【明日方舟/Arknights】凯尔希•思衡托——Kal'tsit·Esper… | 22(0) bool 13 color 3 combo 1 group 1 slider 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 人物和绿色横线呈现；未把横线据图猜成故障，完整参数与同状态细节未验。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状态验收。 |
| `3721456868` | 绯雪1 \|\| 鸣潮 | 44(17) bool 15 color 7 group 4 slider 6 text 10 textinput 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3722749868` | Porsche GT3 RS | 4(0) bool 3 color 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3723344874` | 【凡人修仙传】玄骨 借尸还魂 | 25(0) bool 7 color 4 slider 14 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3738202317` | Albedo. | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3742133044` | 凌霄·双司镇命·无常<1>-[深空之眼] | 3(2) color 1 combo 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3743305891` | 战双 | 仅 schemecolor | `degraded-runtime` | `graph-execution / GraphExecutor / layer-source-not-ready / resolved-material-graph` | `effect-chain` | `unreviewed` |  |
| `3747190633` | 【凡人修仙传】银月 惹人怜惜 | 16(0) bool 4 color 3 combo 1 slider 8 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3747492842` | [4k]Leon S Kennedy X-ray \| Resident Ev… | 67(33) bool 20 color 11 combo 1 group 6 scenetexture 4 slid… | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:effectConstant` | `scenescript` | `fail` 2026-09-08 | 文字错位部分修复；额外闪烁、光束位置与 viewport 裁切未通过 |
| `3748311238` | 大 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3749463715` | 还能在大 ∑ 2 | 3(0) bool 1 color 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3750342273` | Night snowy mountains | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3750813609` | Asian Temple in the Mountains | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 山寺构图、雾与落叶与预览一致；时钟数字呈灰黑渐变而预览为白色发光，雨丝更淡 |
| `3754630802` | WLOP [ChineseNewYear 7] | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3754639143` | WLOP 银月 | 2(0) color 1 combo 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3754908581` | DJGun Making Noise!(Lite) | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` 2026-10-17 | 人物、时钟、背景文字呈现；未把作者绿色脸框当引擎故障，交互与参数完整性未验。 与目录官方截屏仅作基础构图对照；viewport、时相、媒体和全部属性尚未同状态… |
| `3757555836` | 名将杀【兰汤春酽_赵姬】限制级8K | 3(0) bool 1 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3761159935` | 【诛仙】陆雪琪 等待的沉默 | 8(0) bool 4 color 2 slider 2 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3761619125` | 麻匪 雪竹 | 78(16) bool 8 color 7 combo 2 slider 11 text 47 textinput 3 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3762312138` | Elf x Goth | 2(0) bool 1 color 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3763323436` | 3763323436 | `missing-project` | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` | 行政入库备注（2026-10-17）：当前同ID目录仅见shaders残留，缺project.json与scene.pkg，本轮未运行。保留旧archive的… |
| `3763428294` | 秧秧·玄翎1\|\|穗穗\|\|舟行画中，心随风远\|\|鸣潮 | 48(22) bool 16 color 7 group 4 slider 9 text 10 textinput 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3764725758` | Lumine_HuuOliv | 2(0) bool 1 color 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3765760121` | 【4K】三色堇与她 | 9(5) bool 5 color 1 combo 1 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 倒置已修，整样本未全面验收 |
| `3765904723` | 调月莉音 | 8(0) bool 5 color 1 slider 1 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3766310551` | 【完美世界】柳神 九劫焚天 | 6(1) bool 4 color 1 combo 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3766387484` | ARKNIGHTS ENDFIELD ARCANE CHEN XIANGYU | 15(1) bool 11 color 1 group 3 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 日期/星期/时钟恢复，其余 effect 未验收 |
| `3766403294` | 仪玄(AI) | 4(0) bool 3 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3766415113` | The last pour | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3767232084` | 谬因 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3767343314` | Universe Abstract - By: CroSsHaiR-> | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3767460992` | Magic mushroom | 14(0) bool 9 color 3 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3768020435` | Silver Wolf with media integration | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3768229922` | 麻匪 赤芒 音频互动 | 34(0) bool 7 color 1 text 25 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3768724269` | ARKNIGHTS ENDFIELD 4K GILBERTA IN CLOUDS | 23(1) bool 18 color 1 group 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3768903841` | Naha Gaze at Firework \| northway. | 10(0) bool 7 color 1 slider 1 text 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3769364482` | 戴拿奥特曼 强壮型【Ultraman Dyna Strong Type】dy柊明 | 6(0) bool 5 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3769688830` | Spirit Blossom Springs Ahri (Adjustable… | 21(0) bool 13 color 3 group 3 scenetexture 1 untyped 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3769761761` | Yoru and Mitaka asa | 8(0) bool 6 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3770444459` | 三国杀【节气 夏至 2026】8K | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3770462923` | gt3rs@d4rk | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3775355045` | 交错战线_DAIBLOS CORE_x-ray_4K_1 | 2(0) color 1 slider 1 | `degraded-runtime` | `graph-execution / GraphExecutor / layer-source-not-ready / resolved-material-graph` | `effect-chain` | `unreviewed` |  |
| `3775373546` | 交错战线_DAIBLOS CORE_x-ray_4K_2 | 2(0) color 1 slider 1 | `degraded-runtime` | `graph-execution / GraphExecutor / layer-source-not-ready / resolved-material-graph` | `effect-chain` | `unreviewed` |  |
| `3777761326` | I do Anything | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3779026256` | [魔法少女的魔女审判] 月代雪 X 樱羽艾玛 音频识别 | 13(0) bool 4 color 1 group 2 slider 6 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-reference-error / target:layer:visibility` | `scenescript` | `unreviewed` |  |
| `3779904456` | 尤诺2 \|\| 鸣潮 | 47(21) bool 15 color 7 group 4 slider 9 text 10 textinput 2 | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` |  |
| `3780119725` | in the rain V 31 | 13(0) bool 9 color 2 slider 2 | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `fail` 2026-09-08 | 人物压缩已修；脸部黑线/缺块、动画层 unsupported、光照与闪烁未通过 |
| `3780391264` | Agnes Tachyon Umamusume Neon | 7(0) bool 6 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3780940857` | 枕澜 蒂法 电脑动态壁纸 最终幻想7 TIFA Final Fantasy V… | 仅 schemecolor | `degraded-runtime` | `graph-execution / GraphExecutor / layer-source-not-ready / resolved-material-graph` | `effect-chain` | `unreviewed` |  |
| `3781307553` | Look this | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3781757083` | 羽毛笔-天国来信・Arknights | 40(27) bool 22 color 5 combo 3 slider 6 textinput 4 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3782650329` | 我们三 X-ray | 3(0) bool 1 color 1 slider 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3782740481` | WLOP Violet 紫 | 9(0) bool 2 color 2 slider 5 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3784012236` | >R-18< 蔚蓝档案 Blue_Archive\|06\|飛鳥馬 トキ 时 … | 4(2) bool 1 color 1 combo 1 slider 1 | `degraded-runtime` | `resource-load / BaseImageTextureStore / base-image-texture-load-incomplete / image-layer` | `texture-load` | `unreviewed` |  |
| `3786048634` | 2B and A2 | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3786185473` | ELF PARADISE～欢迎来到性夜♪色情精灵们的淫乱圣诞节特别篇～ \| … | 6(0) bool 2 color 1 combo 1 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3786641495` | Albedo - Look at here my master | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3787355076` | 维琳娜-申请入股 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3787382101` | 清宵 \|\| 万剑 \|\| 鸣潮 | 49(23) bool 15 color 8 group 4 slider 10 text 10 textinput 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-06 | Water Waves 扭曲人物全身，未限制在作者 mask 内 |
| `3788066613` | [Hajily-1825][R-18]2025-07-04 Fleurdely… | 25(0) bool 6 color 4 group 4 slider 10 textinput 1 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:visibility` | `scenescript` | `unreviewed` |  |
| `3788467391` | Miku and Monster | 3(0) bool 2 color 1 | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` |  |
| `3788645041` | 奥黛塔(破洞版) | 4(0) color 1 combo 2 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3788698200` | NFFA画风 维琳娜2（可去防封马赛克+可去时钟） | 5(3) bool 3 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3788734811` | 庄方宜-1 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 倒置已修，整体视觉等价未验收 |
| `3788897599` | ArT丨R18丨4K丨Red Q | 9(0) bool 7 color 1 group 1 | `degraded-runtime` | `effect-admission / EffectStageAdmission / unified-capability-unavailable / backend:effect-family:opacity` | `effect-chain` | `unreviewed` |  |
| `3789316755` | Fern_Frieren | 仅 schemecolor | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-range-error / target:layer:visibility` | `scenescript` | `unreviewed` |  |
| `3790631363` | 三国杀【水殿香来 曹金玉】限制级 4K | 3(0) bool 1 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3790726145` | 周于希54 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3790806929` | Winter Artoria Pendragon \| Fate/Zero [… | 2(0) bool 1 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3790956325` | 骚暖暖 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3791905266` | Dohrn's  Vision | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3791967416` | 麻匪 虎符电竞 兰 16:9 21:9 | 55(5) bool 10 color 8 combo 1 slider 2 text 33 textinput 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3792249095` | Beth's Wallpaper | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3792400801` | Girl \| Dark Background \| Dark / Color… | 9(0) bool 7 color 1 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3792817546` | 小羊不吃草 (地雷系)#滕子京大王 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3793328876` | 大凤Taihou&白凤Hakuhou-HanAI | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3793978239` | 埃吉尔掰穴 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3793998447` | 枕中梦 | 8(0) color 2 slider 6 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3796588443` | ZZZ 薇薇安 法厄同 Vivian Belle 鼠标互动揉胸 | 15(0) bool 11 color 2 group 2 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3797217144` | 迪迦奥特曼 出场动画 镜头视差【Ultraman Tiga】dy柊明 | 10(0) bool 5 color 2 group 1 slider 2 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3800075350` | 三角洲三小只-RX | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3800356808` | Warmth Valley Misty \| northway. | 15(0) bool 9 color 1 combo 1 slider 3 text 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3800572533` | [4K \| Day/Night] Neuro and Evil (by Ar… | 9(6) bool 2 color 1 combo 1 slider 5 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3800728730` | 浮士德ego穴 | 2(0) bool 1 color 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3801294161` | Reze - Let's turn off the lights | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3801984224` | 粉红护士 | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3802005866` | 绝区零 维琳娜 西域风 Zenless Zone Zero Velina | 3(0) bool 2 color 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3803087940` | 原神 少女黑丝玉足 X - ray NSFW 差分 | 4(0) bool 1 color 1 slider 2 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3803482159` | Black Morpho | 6(0) bool 5 color 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3803576671` | NFFA画风 冰雪公主（可去防封马赛克+可去时钟） | 5(3) bool 3 color 1 slider 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3804441338` | Misty Summit 2 \| northway. | 7(0) bool 4 color 1 slider 1 text 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3804906814` | 瞳中星火 新约能天使 明日方舟 4k60fps 组件自定义 【bilibili… | 40(12) bool 8 color 7 combo 2 group 6 slider 17 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3804971850` | Mobius梅比乌斯4 | 8(0) bool 7 color 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3805449677` | 御图网-浅雾藏山语 | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3805547608` | 碧蓝航线 金鹿号【R18版/语音/多功能壁纸】-B站慕慕慕慕斯小蛋糕1.0 | 30(0) bool 12 color 3 combo 1 group 2 scenetexture 7 slider… | `not-run` | - | `not-run` | `unreviewed` |  |
| `3806006894` | 三角洲行动露娜天际线_LUNA_4K动态初版FLYSMALLPIG | 2(0) bool 1 color 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3806016969` | 三角洲行动红狼蚀金玫瑰_黑金_动态版4K_FLYSMALLPIG | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3806202923` | Azur Lane 碧蓝航线光辉 | 6(0) bool 5 color 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3806337293` | 初音未来 hatsune miku 3d视差 4k | 17(0) bool 5 color 2 group 2 slider 8 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3807013762` | Frieren | 7(0) bool 5 color 1 combo 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3807121855` | 鸣潮今汐-桃花鸢 | 10(0) color 2 group 1 scenetexture 1 slider 6 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3807151772` | MyGO 长崎素世 Soyo 鼠标互动 捧脸 | 4(0) bool 2 color 1 slider 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3807239614` | 清霄&心 | 4(0) bool 2 color 1 textinput 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3807436394` | Ronova | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3807553861` | Albedo - After the bath | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3807668787` | 霜翼剑使 | 2(0) color 1 text 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3807861954` | 鬼方 カヨコ | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3809034761` | 白丝·斜身侧立[4K] | 24(19) bool 10 color 3 group 2 slider 9 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3809541486` | Moon Princess | 6(0) bool 5 color 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3809609151` | League of Legends Gwen \| 6 character p… | 9(0) bool 6 color 2 combo 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3809618616` | 芒果青青 | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3810943704` | Empress of Grace (Commission; Adjustabl… | 38(0) bool 30 color 4 combo 1 group 3 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3811154012` | 麻匪 Uncle Panda 残叙 | 36(0) bool 4 color 1 slider 2 text 28 textinput 1 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3811216799` | Nikke - Guilty (Mighty Bunny) Desktop A… | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3812249745` | 完美世界-九劫柳神 | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3812473896` | 原神芙宁娜-水畔芙谣[Furina's Ballad by the Water… | 52(0) bool 3 color 7 group 6 scenetexture 1 slider 35 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3814040466` | Nikke - Privaty - Sharp Lesson | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
| `3815761795` | 明日方舟・夕｜画桥（4K） | 13(0) bool 7 color 3 combo 1 textinput 2 | `not-run` | - | `not-run` | `unreviewed` |  |
| `3818943255` | 美女肚兜 | 3(0) color 1 slider 2 | `runtime-evidence-incomplete` | - | `visual-review` | `unreviewed` 2026-10-17 | 新发现后复用同签名App单次默认direct短播放：1image/0effects、0.971s ready，实际图像呈现、exit0/stop1→0/GPU… |
| `3820312181` | Void Edge Theme R6S [High Resolution] | 4(0) bool 2 color 1 slider 1 | `degraded-runtime` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` 2026-10-17 | 10-17原包默认参数的右上缺光已恢复：sampler presence误用editor条件的首错退出，17/effect1真实Program/GPU/末合成… |
| `833227004` | 星云变换t001 | 仅 schemecolor | `not-run` | - | `not-run` | `unreviewed` |  |
