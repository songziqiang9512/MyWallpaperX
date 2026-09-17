# Scene 样本验收台账

> 状态：现役验收事实。本页由 `script/scene_sample_acceptance_ledger.py` 生成；视觉裁决只来自 `script/scene_sample_acceptance_verdicts.json` 的人工记录，不要手工编辑本页。
>
> 最终验收门：每个样本在真实播放中正确显示与播放，且作者参数（project.json user properties）全部进入播放链路。
>
> 运行状态和首断点只描述隔离运行的安全/结构事实，不是视觉正确性；`structural-chain-complete-visual-review` 仍需人工验收。集群只用于排序公共首断点，样本身份不得进入产品代码或现役路线正文。

## 1. 来源

- 样本根：`/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Scene`（159 个 numeric sample）。
- 运行归档：`scene_sample_debug_archive.json` SHA-256 `3bd6b8230164f52d9ca47e5288de5cb2a910a49dfd5cec8b598bf8a9ffbde515`（生成于 2026-09-17T17:54:48.122872+00:00）。
- 归档运行身份：CDHash `918475e7b5ab8933c1d54c9a0b4caef9ff291521`、CDHash `a31bd68aa2e84050c26bb5aa1a8d8383b85c743a`；**归档内不止一个执行身份**，运行状态与首断点因此是混合身份事实，单样本结论必须回到该样本自己的 report 身份。
- 裁决覆盖层：`scene_sample_acceptance_verdicts.json` SHA-256 `2bf7c1d1992b9d215b5308e6e65a322013ee06fadb3c46d0cff04fc9c2b870c6`。
- 本页生成于 2026-09-17T17:57:06.147784+00:00。

## 2. 汇总

| 视觉裁决 | 样本数 |
|---|---:|
| `unreviewed` | 140 |
| `pass` | 0 |
| `fail` | 19 |
| `platform-unsupported` | 0 |

| 官方对照状态 | 样本数 |
|---|---:|
| `unknown` | 159 |
| `not-run` | 0 |
| `blocked` | 0 |
| `compared` | 0 |

- 已裁决但缺观看者身份的条目：**19**；已裁决但缺截图/视频身份的条目：**19**（P0.2 `sample → verdict` 关系要求的字段；缺项保持 `unknown`，不由生成器补写）。此处只统计**裁决自己引用的** run/截图身份，与 corpus 清单（docs/scene/semantics/scene-corpus-capability-inventory.md）的「人工对照」列（样本目录自带的用户截图 `截屏*.png` 与 `用户观察说明.md`）不是同一事实，两页不可互相替代。

| 首断点集群 | 含义 | 样本数 |
|---|---|---:|
| `effect-chain` | effect 准入 / 颜色合同 / graph 执行 | 8 |
| `particle-load` | 粒子层资源加载 | 9 |
| `texture-load` | 基础图片纹理加载 | 3 |
| `scenescript` | SceneScript 异常 | 11 |
| `terminal-output` | terminal compositor / 输出链 | 1 |
| `visual-review` | 结构链完整，待视觉验收 | 127 |
| `not-run` | 尚无隔离运行证据 | 0 |

| 运行状态 | 样本数 |
|---|---:|
| `blocked` | 2 |
| `degraded-runtime` | 30 |
| `structural-chain-complete-visual-review` | 127 |

作者参数：104 个样本声明了 schemecolor 之外的用户参数，共 2960 项，其中 814 项带 `condition`。参数进入播放链路的验收随各样本的视觉裁决一起记录，不单独计数。

## 3. 逐样本

首断点格式为 `stage / owner / reasonCode / profile`。作者参数列为 `总数(condition 数) 类型分布`。

| 样本 | 标题 | 作者参数 | 运行状态 | 首断点 | 集群 | 视觉裁决 | 备注 |
|---|---|---|---|---|---|---|---|
| `1300076567` | 阳光少女 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1315486372` | 貂蝉拜月 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 水波位置不正确、光线贴图效果生硬 |
| `1439846152` | 腿 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1480826543` | Emilia X-ray NSFW | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1507413154` | 百褶裙 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1507593643` | 蕾丝吊带 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1511889295` | 死库水 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1553008362` | [Jidan Hua] Ichigo and 002 (Darling in … | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `1636394814` | [Jaku Denpa] Shigure (Kantai Collection… | 4(0) bool 1 color 1 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
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
| `2356604986` | 1265079-1322607782 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2419444134` | Nier Reincarnation - Akeha | 6(0) bool 5 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2470144420` | 女孩独享的宁静傍晚 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2473638329` | Genshin Impact \| +18 / NSFW & SFW | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2505351195` | Nier Automata / +21 \| NSFW & SFW | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2607203340` | Tomb Raider +18 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2684431262` | 麻匪 炫酷音频律动 Windows | 28(0) bool 4 color 12 slider 1 text 11 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2775915974` | R18*JK(escalator)エスカレーターJKさんX-ray | 4(0) bool 1 color 1 combo 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 鼠标纵向与顶部边界已修，顶部极限仍露灰边；整样本未通过 |
| `2794098047` | 麻匪 是姐姐还是妹妹 windows | 34(12) bool 5 color 10 combo 2 slider 5 text 12 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2797913147` | 【R18】连体黑丝#4K#视差#可互动臀部#动态 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2802243144` | 冰公主-by Wlop 时间日期已修复 16:9 -music 订阅后点赞，养… | 14(0) bool 7 color 2 slider 5 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2808874251` | youer | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2813231542` | 清新美女 R-18 | 9(0) bool 7 color 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2824109832` | Yor Forger - NIXEU 4K | 16(7) bool 12 color 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2837223712` | 李擎洲：阿狸[4K] | 2(0) bool 1 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2884628849` | 麻匪 小姐姐 | 29(0) bool 4 color 4 combo 5 slider 4 text 12 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2896873092` | Genshin Impact: Thicc Girls Spread Coll… | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2902406982` | 麻匪 月半与鬼哭 所有元素自定义 | 173(103) bool 20 color 45 combo 8 scenetexture 2 slider 35 … | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2917306763` | [4K/动态/R18/衣服透视可调]碧蓝航线-独角兽妹妹「天使的护理时间」-B… | 3(0) bool 1 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2932631210` | 欧派-音乐乱动 | 13(0) bool 8 color 3 combo 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2938612768` | 麻匪 音频识别 Media Player | 79(35) bool 16 color 11 combo 5 scenetexture 4 slider 13 te… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2942486721` | R18 Ishtar And Ereshkigal / 遠坂  凛 Tohsa… | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `2959875782` | [R18] Lexaiduer Last Origin Dark Elven … | 4(0) color 1 combo 2 slider 1 | `blocked` | `effect-admission / EffectStageAdmission / admitted-fallback / effect-local-passthrough` | `effect-chain` | `unreviewed` |  |
| `2974757317` | 麻匪 音频识别 悬浮窗 Media Player | 80(35) bool 13 color 17 combo 3 scenetexture 5 slider 16 te… | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` |  |
| `2986218263` | Tokisaki Asaba & Tokisaki Mio │18+ X-Ra… | 6(0) bool 5 color 1 | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` |  |
| `2998757800` | 碧蓝航线-利托里奥【R18版/可触摸/天气变化】-B站慕慕慕慕斯小蛋糕 | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3002649614` | 纯欲少女 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3025969015` | 黑龙闹海 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3028090166` | WLOP [Tian Nan2] | 2(0) bool 1 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3088601835` | Winter Wanderer Xayah - League of Legen… | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3113287126` | Dome 4k {Artwork by WLOP} | 8(0) bool 6 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3113554287` | 【可随时间变化】窗旁の伊蕾娜   （优化版本） | 7(1) bool 3 color 3 combo 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3122339805` | Pixels | 39(0) bool 9 color 6 combo 1 scenetexture 3 slider 1 text 7… | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-bad-return / target:text:content` | `scenescript` | `unreviewed` |  |
| `3141421197` | GraspOfTheAbyss | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3147346398` | ⛏🧱Minecraft Lo-Fi Fireplace [4k HDR] WE… | 21(12) bool 8 color 3 combo 1 slider 5 untyped 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3167210190` | [Blue Archive] 奶牛装明日奈 | 7(0) bool 5 color 1 group 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3211615441` | 捆绑悬挂 \| Bind & Suspend [ 可交互/interactiv… | 26(12) bool 7 color 1 combo 5 group 4 slider 4 text 4 texti… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3219398263` | Acheron Black Hole (StarchaserArt) | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3233141951` | 熠烛 御剑驭龙-红鸾樱落 高度自定义Red Warbler-Sakura fa… | 67(0) bool 18 color 7 combo 3 group 1 scenetexture 1 slider… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3238423642` | Katana Girl with Hologram (Adjustable; … | 90(0) bool 35 color 25 combo 9 group 12 slider 8 untyped 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 头部错位已修，整体视觉与约 18.7 FPS 帧时间未验收 |
| `3264246690` | 麻匪 wlop 鬼刀 月牙儿 16:9 16:10 21:9 32:9 | 70(21) bool 16 color 7 combo 2 slider 14 text 25 textinput 6 | `degraded-runtime` | `resource-load / BaseImageTextureStore / base-image-texture-load-incomplete / image-layer` | `texture-load` | `fail` 2026-09-08 | 人物左肘缺块；构图未验收 |
| `3287715210` | 发光少女 4K动态壁纸 | 17(1) bool 1 color 1 group 1 slider 14 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 音频条已恢复（PCM fixture），真实系统音频与整体未验收 |
| `3290491250` | frieren | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3299228616` | Lonely Cat: Audio visualizer , Clock , … | 64(60) bool 26 color 13 combo 13 slider 12 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3323988600` | Hentai Goddess of Victory Nikke ANIMATE… | 9(0) bool 4 color 1 slider 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3363252053` | 【Parallax视差】Hatsune Miku 初音未来 光与影——夜莺Ni… | 97(39) bool 28 color 15 combo 4 group 6 slider 33 text 8 te… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3389974179` | 落日与白皙的大腿 | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3395392965` | 请叫我帅锅-小姨定制 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3395777145` | 麻匪 光 音频识别 Media Player 16:9 16:10 21:9 | 74(26) bool 14 color 10 combo 5 scenetexture 1 slider 11 te… | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3396722575` | 麻匪 NIXEU 黄泉 超多自定义模块 音频识别 Media Player 1… | 132(71) bool 22 color 17 combo 3 slider 47 text 40 textinpu… | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` |  |
| `3437487219` | 3D Earth - Close Orbit   [HDR10 Optimiz… | 15(2) bool 3 color 1 combo 2 group 3 slider 6 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 日期时间恢复，cursor owner collision 未闭合 |
| `3448845950` | 麻匪 媒体音频标签【148项自定义】Media Player 16:9 16:… | 152(35) bool 22 color 17 combo 14 scenetexture 2 slider 20 … | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:effectConstant` | `scenescript` | `fail` 2026-09-08 | 黑屏已解除，脚本效果与整体布局未通过 |
| `3470948192` | 水滴 三体 \| Droplet -SYKM | 37(0) bool 7 color 4 combo 2 group 7 slider 13 untyped 4 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-bad-return / target:layer:scale` | `scenescript` | `fail` 2026-09-08 | 开场/文字错位部分修复，仍有 NaN、文字碎片与异常背景 |
| `3472940912` | -Tsukatsuki Rio [ blue archive ] - 4K | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3477054430` | Cat with headphones on the roof | 25(0) bool 4 color 6 group 6 slider 9 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 画面显示不全；mask 已恢复，月亮/球体与文字布局仍开放 |
| `3487629864` | 云曦老婆 (18+) | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3509243656` | 三体实时演算 \| Three-Body problem - SYKM | 233(2) bool 27 color 20 combo 3 group 21 scenetexture 1 sli… | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 开场/模拟画面不正常，坐标文字异常 |
| `3554161528` | Blue Archive-Sorasaki Hina 空崎日奈[4K] | 35(16) bool 15 color 4 combo 1 group 5 slider 7 untyped 3 | `degraded-runtime` | `effect-admission / EffectStageAdmission / unified-capability-unavailable / backend:effect-family:blend` | `effect-chain` | `unreviewed` |  |
| `3585875739` | Miku Monitoring | 6(0) bool 5 color 1 | `degraded-runtime` | `graph-execution / GraphExecutor / layer-source-not-ready / resolved-material-graph` | `effect-chain` | `unreviewed` |  |
| `3601964477` | 千咲 \|\| 鸣潮  \|\| 枫 \|\| 4K | 44(19) bool 19 color 5 group 3 slider 7 text 10 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` |  |
| `3609108600` | 千咲 \|\| 鸣潮 \|\| 4K | 9(4) bool 4 color 1 slider 4 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3610154602` | 千咲 \|\| 鸣潮 \|\| 高塔 \|\| 4K | 42(16) bool 15 color 4 group 4 slider 6 text 10 textinput 3 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` |  |
| `3612199597` | 千咲 \|\| 鸣潮 \|\| 与千咲的穗波散步 \|\| 咖啡厅天台 \|\… | 40(17) bool 19 color 4 group 3 slider 5 text 9 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` |  |
| `3612795410` | 千咲 \|\| 鸣潮 \|\| 与千咲的穗波散步 \|\| 喷泉广场 \|\|… | 35(15) bool 16 color 4 group 2 slider 3 text 10 | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:layer:alpha` | `scenescript` | `unreviewed` |  |
| `3629927359` | 奶牛大鸭鸭 2 | 2(0) color 1 combo 1 | `degraded-runtime` | `resource-load / BaseImageTextureStore / base-image-texture-load-incomplete / image-layer` | `texture-load` | `unreviewed` |  |
| `3655958892` | R18 Acheron & Black Swan 黄泉&黑天鹅 [Honkai… | 5(0) bool 4 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3662790108` | 实时太阳系 Live Solar System - SYKM | 198(26) bool 71 color 9 combo 3 group 12 scenetexture 24 sl… | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 轨道/布局已恢复，球体与曲率画面、点击交互未验收；约 8.8 FPS |
| `3665307769` | 爱弥斯1 \|\| 鸣潮 \|\| 4K | 51(19) bool 18 color 7 group 4 slider 10 text 10 textinput 2 | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` |  |
| `3690859128` | 爱弥斯2 \|\| 鸣潮 \|\| 4K | 42(17) bool 10 color 8 group 3 slider 11 text 10 | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `unreviewed` |  |
| `3699213569` | 碧蓝航线Azurlane-斯特拉斯堡&克莱蒙梭（By Adramahlihk） | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3703104370` | Rio&菲比-adoc(涟) | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3712499998` | 鸣潮 \|\| 3.3pv \| 自星海尽处回响 | 40(16) bool 12 color 8 group 2 slider 8 text 10 | `degraded-runtime` | `resource-load / ParticleRuntime / particle-layer-load-incomplete / particle-layer` | `particle-load` | `fail` 2026-09-08 | 日期/时钟恢复，WEVector unsupported，重复文字未裁决 |
| `3721456868` | 绯雪1 \|\| 鸣潮 | 44(17) bool 15 color 7 group 4 slider 6 text 10 textinput 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3738202317` | Albedo. | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3742133044` | 凌霄·双司镇命·无常<1>-[深空之眼] | 3(2) color 1 combo 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3743305891` | 战双 | 仅 schemecolor | `degraded-runtime` | `graph-execution / GraphExecutor / layer-source-not-ready / resolved-material-graph` | `effect-chain` | `unreviewed` |  |
| `3747492842` | [4k]Leon S Kennedy X-ray \| Resident Ev… | 67(33) bool 20 color 11 combo 1 group 6 scenetexture 4 slid… | `degraded-runtime` | `script-execution / SceneScriptVM / scene-script-exception-type-error / target:effectConstant` | `scenescript` | `fail` 2026-09-08 | 文字错位部分修复；额外闪烁、光束位置与 viewport 裁切未通过 |
| `3748311238` | 大 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3749463715` | 还能在大 ∑ 2 | 3(0) bool 1 color 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3750342273` | Night snowy mountains | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3750813609` | Asian Temple in the Mountains | 3(0) bool 2 color 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 山寺构图、雾与落叶与预览一致；时钟数字呈灰黑渐变而预览为白色发光，雨丝更淡 |
| `3754630802` | WLOP [ChineseNewYear 7] | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3754639143` | WLOP 银月 | 2(0) color 1 combo 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3757555836` | 名将杀【兰汤春酽_赵姬】限制级8K | 3(0) bool 1 color 1 slider 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3763323436` | 补 碧蓝航线 拉菲 Azur lane Laffey | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3763428294` | 秧秧·玄翎1\|\|穗穗\|\|舟行画中，心随风远\|\|鸣潮 | 48(22) bool 16 color 7 group 4 slider 9 text 10 textinput 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3765760121` | 【4K】三色堇与她 | 9(5) bool 5 color 1 combo 1 slider 2 | `structural-chain-complete-visual-review` | - | `visual-review` | `fail` 2026-09-08 | 倒置已修，整样本未全面验收 |
| `3765904723` | 调月莉音 | 8(0) bool 5 color 1 slider 1 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
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
| `3782740481` | WLOP Violet 紫 | 9(0) bool 2 color 2 slider 5 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3784012236` | >R-18< 蔚蓝档案 Blue_Archive\|06\|飛鳥馬 トキ 时 … | 4(2) bool 1 color 1 combo 1 slider 1 | `degraded-runtime` | `resource-load / BaseImageTextureStore / base-image-texture-load-incomplete / image-layer` | `texture-load` | `unreviewed` |  |
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
| `3792249095` | Beth's Wallpaper | 仅 schemecolor | `blocked` | `terminal-compositor / SceneCompositor / terminal-output-flat-preview-divergence / captured-scene-output` | `terminal-output` | `unreviewed` |  |
| `3792400801` | Girl \| Dark Background \| Dark / Color… | 9(0) bool 7 color 1 textinput 1 | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3792817546` | 小羊不吃草 (地雷系)#滕子京大王 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3793328876` | 大凤Taihou&白凤Hakuhou-HanAI | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
| `3793978239` | 埃吉尔掰穴 | 仅 schemecolor | `structural-chain-complete-visual-review` | - | `visual-review` | `unreviewed` |  |
