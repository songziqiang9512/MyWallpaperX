<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->
<!-- cutoffDate: 2026-10-03 -->
<!-- uniqueValue: 五个自有slot1输入在固定官方客户端的完整量化区间及原图身份；不构成产品实现或自动采样合同。 -->

# RF02：五组公开纹理 companion 的官方呈现观察

> **历史证据 — 非现役入口**。捕获截止2026-10-03 03:17:39（Asia/Shanghai）；仓库基线`06ae4fce`，本批未改产品。当前方向查[RF02卡](../roadmap/batch2/reference-evidence-implementation-cards.md#rf02-companion)及[兼容路线](../roadmap/scene-compatibility-roadmap.md)。前置修前反例和探针准入过程见[上一检查点](rf02-companion-research-checkpoint-2026-10-03.md)。本机原始工件根为`/private/tmp/mwx-rf02/`；以下相对工件名均相对该目录，用户原图保留在`/Users/songziqiang/Desktop/`。

## 观察范围与准入

按[资料来源分类](../development/source-index.md)，原图输出属于`official-client-dynamic-golden`的有界观察；自有探针、阈值和判读方法属于`MyWallpaperX-strategy`，其合成测试属于`MyWallpaperX-current-evidence`。三者不互相替代。

固定运行的32位`wallpaper32.exe`为2.8.0.42，SHA-256 `DAAC1EA7C991207FDB6098616757E3DAE393850F6862845DB55D04921B6BDA07`，身份见`host/identity-32-v2.log`及`host/process-current-v5.log`。先前64位可执行文件的hash不用于这批观察。环境为Windows 11 ARM64、Parallels WDDM；保留官方编辑器为自建项目生成的vertex模板且未读取其表达。

输入均为项目自编384×192、单帧、未压缩RGBA8888 TEX，两个头部尺寸对均为384×192；独立更改自有sprite六字段。它们仅在effect的slot1绑定，项目、几何和输出链保持同源。片段探针只使用公开接口和自有编码，两个部署位置均核hash。三个原始macOS PNG由用户直接提供；不使用聊天缩略图进行测量。

slot1 v1.3.1探针SHA-256 `9426d94e9fdb27086077bfbada2314363c419cd37a38b2fe8b3980dc4d0e2e81`；`protocol-v1.3/v1.3.1/grid-contract.json` SHA-256 `397d012f7f0e5a9f230015ef31e705d79a2c282a8f4ffe7e299db99a820e79a1`。以可见内容边界定位32×16网格，每格24×24原始像素，仅取预登记中心12×12。阈值固定为RGB各通道≤16或≥239，所选端点覆盖率须≥95%；方向标记、八条已知控制、guard、parity、tier和sampler末行全部核对后才解未知行。不能按未知参数预期拟合ROI或阈值。

五个窗口的2560格内区均144/144为对应端点、alpha均255；40条控制行全部匹配。Windows圆角遮去最外沿部分像素，所以不声称整格全部完整；预登记中心内区均未被遮挡。图像解码器`image-analysis/analyze_grid.py` SHA-256 `9bac2f8e1058a36c34e70680f7c8b47e5bf16c637b986d76033a032ad28d7c94`，15项合成正反测试通过；独立审查另从原图逐像素重算，核对所有内区、计数、转录及区间端点，而非只采用工具的通过字段。

## 完整量化区间

下列标签仅为缩写，均保留完整区间，不能将左端点或区间中值当作精确官方数值：

| 标签 | 区间 |
| --- | --- |
| Z | [0, 0.000244140625) |
| A | [0.125, 0.125244140625) |
| B | [0.1875, 0.187744140625) |
| C | [0.25, 0.250244140625) |
| D | [0.375, 0.375244140625) |
| N | (−0.250244140625, −0.25] |
| I | [1, 1.000244140625) |

| 自有输入 | 原始六字段（自有fixture命名顺序） | Rotation.xyzw | Translation.xy |
| --- | --- | --- | --- |
| neutral | 0, 0, 384, 0, 0, 192 | I, Z, Z, I | Z, Z |
| axis | 48, 24, 96, 0, 0, 48 | C, Z, Z, C | A, A |
| move-x | 72, 24, 96, 0, 0, 48 | C, Z, Z, C | B, A |
| move-y | 48, 48, 96, 0, 0, 48 | C, Z, Z, C | A, C |
| off-diagonal | 144, 24, 0, 72, −96, 0 | Z, D, N, Z | D, A |

每组均是finite／single-frame／slot1的一次呈现观察。单因素move-x/move-y使平移分量分别改变；非对角输入区分了第二、第三Rotation分量的符号和位置，排除本次候选中交换它们的解释。按预先登记的column候选重排后，axis、move-x、move-y、off-diagonal的完整测量区间均处于原H1预测盒内，可继续原有稳定采样子集；这并不证明采样实际采用该变换，更不决定自动应用次数。

## 原图和输入身份

三个原图均2534×1948；ROI为原图像素`x,y,width,height`，不含标题栏。frame并未暴露内部GPU completion ID；呈现身份由窗口名、独立项目路径、启动记录、磁盘输入hash及通过的最终控制行组合约束，不声称已取得编译后二进制hash。

- **axis / `MWXRF02AXIS131`**：`截屏2026-10-03 03.06.32.png`，原图SHA-256 `494f628b252fbf4132772fc34ce0c4aa8842640a1d4cd0e165e2cef474047056`；ROI `392,773,768,384`。TEX `f2e15837e5e63d729fb696c5b4634014a906268ae5d7e25dd5ced8c2ece5e7b4`；scene `00bc6749bce813ad882408b2f3fdc0c36bcbb745c255c486046fa8530b616a47`。启动/核对记录：`host/axis-project-v131.log`, `host/launch-axis131.log`, `host/axis-grid-capture-identity.log`。
- **neutral / `MWXRF02GRID131`**：`截屏2026-10-03 03.13.26.png`，原图SHA-256 `7a83885f204a7c626895faebaabfece108f14edb3dec96c2a67c8a032b9eeb6b`；ROI `145,230,768,384`。TEX `ff48854ae0d573e994152023fc13e915afcff7c1e8aeb1a4ae3d70a0100d9700`；scene `7c8e1bcbef1daf15d716f1b938c3d8083b7ec7493e3ecc95396a2cf866171b06`。启动/核对记录：`host/open-neutral-after-axis.log`。
- **move-x / `MWXRF02MOVEX131`**：`截屏2026-10-03 03.17.39.png`，原图SHA-256 `e5113cbad56315f5c1ab777b11630f02b55e96f4f08756cd14e3adf3ef6d185d`；ROI `145,230,768,384`。TEX `f5dfa0d77d6a240b62fc6f7c2dd8454933c7c87c399106e662dbf3c0bfd27e11`；scene `256eb364839962d2f8d67ce951cece079b851c72963bf47732f81f48ed42a8db`。启动/核对记录：`host/prepare-move-x-grid-v131.log`, `host/launch-move-x-grid-v131.log`。
- **move-y / `MWXRF02MOVEY131`**：`截屏2026-10-03 03.17.39.png`，原图SHA-256 `e5113cbad56315f5c1ab777b11630f02b55e96f4f08756cd14e3adf3ef6d185d`；ROI `945,230,768,384`。TEX `4943d6ca1b04a46ffc3f9c340c52baed6a795f9ad66021b3caa0b1e9ed7355c4`；scene `ae55e085a4fcd053961883a3cbb0e262007ffad4da2c7622e09be6fce819a018`。启动/核对记录：`host/prepare-move-y-grid-v131.log`, `host/launch-move-y-grid-v131.log`。
- **off-diagonal / `MWXRF02OFFDIAG131`**：`截屏2026-10-03 03.17.39.png`，原图SHA-256 `e5113cbad56315f5c1ab777b11630f02b55e96f4f08756cd14e3adf3ef6d185d`；ROI `145,710,768,384`。TEX `c87fa97bf93cace57da639e3e8cc3a887253120ba234bcba60ff67612003cc2f`；scene `10be829d16f986c24fc07e6a7dd193aa75af160563590c10a64d69f9a3b794b8`。启动/核对记录：`host/prepare-off-diagonal-grid-v131.log`, `host/launch-off-diagonal-grid-v131.log`。

完整逐格统计和区间见`{axis,neutral,move-x,move-y,off-diagonal}-image-result.json`；输入manifest同前缀`-capture-input.json`。`capture-review-index.json`保留证据索引；独审记录为：

- `axis-capture-review.md` — SHA-256 `18c4186135acee8e4cee8cad0a091e7cab9c44a76cf60502b127b5fce45add12`。
- `neutral-capture-review.md` — SHA-256 `cb6e8294ca40f0657aa52a6f6263f55484ecddb0493317b37835943fe41a905b`。
- `three-variants-capture-review.md` — SHA-256 `2a20023c6ed1ba8fdd11fc09cbae8273b033f281e1daf81f7d2d3e1522b29ee3`。

## 结论上限与未完成项

- **未确定自动采样行为。** 六个uniform的值不证明texSample2D如何处理坐标。仍须同容器颜色基准、literal／active companion成对程序、独立可见count输入和冻结预测的采样实验；不得用输出颜色反推count，也不得把synthetic ABI直接别名为公开uniform。
- **未区分尺寸来源。** 本轮两组尺寸完全相同，不能判定按实际纹理尺寸还是映射尺寸归一化。单头字段差分仍须官方资源准入，并以Resolution等可观察响应排除该字段被忽略。
- **未闭合重复性、时序及其它profile。** 尚未完成三次重载与每次连续三帧稳定性；没有动画更新相位、非有限值、其它槽位、padding、RT/provider、顶点阶段或全程序兼容结论。
- **未完成产品实施。** 本轮没有MyWallpaperX GPU执行、completion/publication/terminal compositor/next-frame证据；先前真实Swift的active companion拒绝反例仍未修复。本记录不改变能力等级或宣布parity。

本轮只消费自有作者输入、公开接口和官方黑盒输出；未读取或复制stock/private shader、反编译表达或第三方实现。受保护的能力台账、运行证据总表和工程执行档案未修改；并行`script/scene_source_layout.json`保留。
