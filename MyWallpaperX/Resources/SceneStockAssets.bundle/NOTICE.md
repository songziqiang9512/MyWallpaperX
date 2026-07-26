# SceneStockAssets 字体署名与许可

Scene 壁纸作者可以写 `fonts/<Name>` 引用 Wallpaper Engine 客户端自带的字体。
本 bundle 让 MyWallpaperX 在作者没有把字体打进壁纸包时也能用真实字形渲染，
而不是退化成 Helvetica / Menlo 这类通用家族。

客户端 `assets/fonts` 共有 15 个字体。Wallpaper Engine 有权随自己分发它们，这个权利
不传递给 MyWallpaperX，因此这里只搬许可允许再分发的原版，其余换成外形接近的自由字体。
`assets/fonts/` 完整保持官方 15 个相对路径和文件名。替代字形也直接复制到对应官方文件名，
运行时只按作者写入的路径读取文件，不维护另一套替代文件名映射；字体内部 PostScript 名和
`stockSubstituted` 诊断仍明确说明它不是官方字形。

`Licenses/` 下是各字体要求随附的完整许可文本，删除它们会使本 bundle 的再分发失去授权。
所有字体 payload 均未修改；7 个替代文件只改变了磁盘文件名。

## 原版字体（8 个）

| 文件 | 版权 | 许可 | 许可文本 |
|---|---|---|---|
| `8bitOperatorPlus8-Regular.ttf` | © 2009–2014 Grand Chaos Productions (GrandChaos9000) | CC-BY-SA 4.0 与 SIL Open Font License 1.1 双许可 | `Licenses/SIL-Open-Font-License-1.1.txt` |
| `Blackout 2 AM.ttf` | Copyright (c) 2012 Tyler Finck，保留名称 "Blackout" | SIL Open Font License 1.1 | `Licenses/OFL-1.1-Blackout.txt` |
| `Monofur-PK7og.ttf` | monofur © 2000 tobias b köhler | Freeware，条件是必须随附作者的说明文本 | `Licenses/monofur-readme.txt` |
| `NotoSans-Regular.ttf` | Copyright 2015 Google Inc. | SIL Open Font License 1.1 | `Licenses/SIL-Open-Font-License-1.1.txt` |
| `RobotoMono-Regular.ttf` | Copyright 2015 The Roboto Mono Project Authors | Apache License 2.0 | `Licenses/Apache-License-2.0-RobotoMono.txt` |
| `Segment7Standard.otf` | © Cedric Knight 2014，保留名称 Segment7 | SIL Open Font License 1.1 | `Licenses/SIL-Open-Font-License-1.1.txt` |
| `TwemojiMozilla.ttf` | Mozilla | CC-BY 4.0 | `Licenses/TwemojiMozilla-CC-BY-4.0.txt` |
| `opensticks.ttf` | Copyright (c) 2014 Apocalypse Laboratories，声明可商用 | Freeware（可商用） | 无独立文本，声明写在字体自身的 copyright 字段 |

`Blackout 2 AM.ttf` 的内嵌 copyright 字段写的是 "All rights reserved"，但
[The League of Moveable Type](https://github.com/theleagueof/blackout) 以 OFL 发布的
同名文件与客户端那份 SHA-256 逐字节相同（`48e96e2a…cea2d0`），所以按原版随包，
许可以 League 仓库的 OFL 文本为准。

## 替代字体（覆盖 7 个禁止再分发的原版）

原版禁止再分发（例如 Atami 的 EULA 明确写不得重新打包或收录进任何压缩包与网站）。
替代字体是把原版与候选逐个并排渲染 "Hamburg 0123" 比对字形后选定的，不是按名字或
类别硬凑；命中时解析器报 `stockSubstituted`，不会把它说成官方字形。

| 官方物理文件名 | 替代 payload | 选择依据 |
|---|---|---|
| `Atami-Regular.otf` | Poppins Medium | 同为几何无衬线，单层 a、圆形 O、字重与比例吻合 |
| `Alcubierre.otf` | Poppins ExtraLight | 同为极细几何无衬线，线宽与圆形结构接近 |
| `spincycle_3d_ot.otf` | Bungee Shade | 同为宽扁立体描边大写字 |
| `summer85.ttf` | Permanent Marker | 同为粗马克笔 display，笔触质感与字重接近 |
| `Lazer84.ttf` | Permanent Marker | 同为粗笔刷全大写 display |
| `kust.ttf` | Bangers | 同为粗大写手绘 display |
| `CursedTimerUlil-Aznm.ttf` | Segment7 Standard | 同为七段数码管字体，直接复用已随包的原版 |

| 替代文件 | 版权 | 许可 | 许可文本 |
|---|---|---|---|
| `Poppins-Medium.ttf`、`Poppins-ExtraLight.ttf` | Copyright 2020 The Poppins Project Authors | SIL Open Font License 1.1 | `Licenses/OFL-1.1-Poppins.txt` |
| `BungeeShade-Regular.ttf` | Copyright 2023 The Bungee Project Authors (David Jonathan Ross) | SIL Open Font License 1.1 | `Licenses/OFL-1.1-Bungee.txt` |
| `Bangers-Regular.ttf` | Copyright 2010 The Bangers Project Authors | SIL Open Font License 1.1 | `Licenses/OFL-1.1-Bangers.txt` |
| `PermanentMarker-Regular.ttf` | Font Diner, Inc. | Apache License 2.0 | `Licenses/Apache-License-2.0-PermanentMarker.txt` |

`PermanentMarker-Regular.ttf` 的内嵌 copyright 字段同样是未更新的
"All rights reserved"；它位于 Google Fonts 仓库的 `apache/` 目录并随附 Apache 2.0
许可文本，以该文本为准。

## 不涉及本 bundle 的引用

`systemfont_arial` 等 8 个官方别名指向 Windows 系统字体，本来就不在 `assets/fonts` 里，
仍走本机字体家族解析。
