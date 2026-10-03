<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->
<!-- cutoffDate: 2026-10-03 -->
<!-- uniqueValue: 自有slot1的数值区间、尺寸差分、非sprite默认值与动画同屏一致性及原图身份；不构成产品实现或全profile合同。 -->

# RF02：公开纹理 companion 的有界官方呈现观察

> **历史证据 — 非现役入口**。捕获截止2026-10-03 03:17:39（Asia/Shanghai）；仓库基线`06ae4fce`，本批未改产品。当前方向查[RF02卡](../roadmap/batch2/reference-evidence-implementation-cards.md#rf02-companion)及[兼容路线](../roadmap/scene-compatibility-roadmap.md)。前置修前反例和探针准入过程见[上一检查点](rf02-companion-research-checkpoint-2026-10-03.md)。本机原始工件根为`/private/tmp/mwx-rf02/`；以下相对工件名均相对该目录，用户原图保留在`/Users/songziqiang/Desktop/`。

最终中性证据已晋升到 `.artifacts/scene-evidence/runs/rf02-companion-observations-20261003`，原始临时根已退役。90 张尺寸/默认值补证和360 张动画快照全部独审 ACCEPT，1111 个保留文件 SHA 已核对；目录另含协议共享控制图，450 是补证实验快照数。以下原路径只描述当时 provenance，现存身份以保留包 manifest 为准；实施结果另见[RF02 B](rf02-public-companion-implementation-2026-10-03.md)。

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


## 后续补证：mapped-width 差分与重复呈现

本节为同日后续批次的独立观察；上文的五组原始记录及其截止身份不变。后续全部 450 张原图、协议、自有输入、捕获身份日志和独审记录已按产物规则提取到 `.artifacts/scene-evidence/runs/rf02-companion-observations-20261003/`（约 12.3 MiB）；`official/report.json` 及 `manifest.json` 保存原相对路径到保留文件的映射。逐格派生报告可由原图与冻结 analyzer 重算，opaque vertex 表达未读取或提取。自有证据根为 `/private/tmp/mwx-scene-next-rf02/`，固定客户端及其 SHA 与上文相同。`protocol-freeze.json` 冻结 32 项输入、探针、协议和分析文件，SHA-256 `4fef873422b350acb72b590e5db5e52d6d56bb15ccd09b1e8a5d45c66afeacf7`；汇总 `dimension-results.json` SHA-256 `684971b09b70e2a09b4124a8690a90cdc0c6c0ae5e7a232803c633722ea68b6c`。

基准继续使用 axis 的 slot1、单 image、单帧 TEX。差分只把 mapped-width 候选字段 384 改为 192：295040 字节文件仅第 34、35 字节不同，像素 payload 与末尾 45 字节 sprite 表完全相同。基准 TEX SHA-256 `f2e15837e5e63d729fb696c5b4634014a906268ae5d7e25dd5ced8c2ece5e7b4`；差分 TEX `803bfc63c8e7114c5747cc8d1b36e5c0f83c895fe5940eb9fda09c63bd63fd86`。独立的自有 Resolution 探针 SHA-256 `2dee877e8de24a795b1c58506380d426574430997beeba1709361843d5306655`；companion 探针沿用上文 v1.3.1。Resolution 使用单独冻结的四未知行协议，其余行是已知控制，不能套用六未知行 companion 解码器。

| profile | Rotation.xyzw | Translation.xy | Resolution.xyzw |
| --- | --- | --- | --- |
| physical/mapped 均 384×192 | C, Z, Z, C | A, A | [384,384.015625), [192,192.015625), [384,384.015625), [192,192.015625) |
| physical 384×192、mapped 192×192 | C, Z, Z, C | A, A | [384,384.015625), [192,192.015625), [192,192.015625), [192,192.015625) |

四个程序/profile 各三次独立新窗口加载、每次三张间隔呈现快照，共 36 张全幅 768×384 原 PNG。每个 profile 的三次加载使用不同窗口 handle 和 command PID，主进程均为 7492；不是三个独立客户端进程。独审从原图重算 18432 格、2654208 个中心像素：全部命中预登记端点且 alpha=255，方向、八已知控制、Resolution 额外控制、guard/parity/tier 与 sampler 末行全匹配；逐格计数及半开区间与报告一致。原图字节与 host log 中的捕获载荷一致，32 项冻结文件无漂移。

**可采用的推断：** Resolution.z 的独立响应排除了该头字段被忽略；在这一已准入输入中，改变 mapped-width 未使 companion 离开原量化盒，排除当前 mapped-width 分母候选（Rotation.x≈0.5、Translation.x≈0.25），与按 384 宽度归一化的候选一致。header physical 与首 mip 尺寸在本轮相同，不能区分二者作为内部来源。RT 与 Resolution 分程序测量，同进程资源缓存未单独观察；间隔快照不等于连续 GPU completion，区间相同不等于逐位值相同。本节不证明高度、动画相位、非 sprite/provider 默认值或产品实现，这些由各自后续记录闭合。


## 后续补证：mapped-height 与非 sprite 默认值

同一后续证据根的 `supplement/` 冻结 29 项文件，`freeze.json` SHA-256 `3839725cfc03e4749a24bc745ab36544ee70d44721441dca7502f3be9c64c489`；`results.json` SHA-256 `70b69e1e0b346ac9aaf0f7e5a1990a958ab084172b27b540ebecf75a19e7f1a7`，`capture-index.json` SHA-256 `6d108905981f9fabdd44dd18e74fe108b2ece7616ff41ce5a1a758317c5b11d6`。客户端、物理/首 mip 尺寸、公开探针和端点准入沿用宽度实验；输入修改全部在自有 TEX 上完成。

| 输入 profile | 独立改动 | Rotation.xyzw / Translation.xy | Resolution 观察 |
| --- | --- | --- | --- |
| SPRITEY | axis 仅第 38 字节 mapped-height 192→96；payload/完整 sprite suffix 不变 | C,Z,Z,C / A,A | xy=[384,384.015625),[192,192.015625)，z=[384,384.015625)，w=[96,96.0009765625) |
| NSFULL | axis 清除 sprite flag 4→0，移除末 45 字节 sprite suffix；payload 不变 | Z,Z,Z,Z / Z,Z | xyzw 与 full 384×192 基准的四盒相同 |
| NSPAD | NSFULL 同时改 mapped pair 为 192×96；payload 不变 | Z,Z,Z,Z / Z,Z | xy 与 full 基准相同，z=[192,192.015625)，w=[96,96.0009765625) |

每组 RT/Resolution 分程序，各三次新窗口加载、每次三张间隔呈现快照，共 54 张。独审重算 27648 格、3981312 个中心像素，全部为对应端点且 alpha=255；所有已知控制、计数、转录和区间一致。每个 profile 三次加载的 handle/command PID 不同，主进程仍为 7492；原图、host 捕获载荷、输入和冻结身份全部一致。

**可采用的推断：** SPRITEY 的 Resolution.w 明确响应且 RT 保持原盒，排除本实验按 mapped-height 归一化的候选（Rotation.w≈0.5、Translation.y≈0.25）。NSFULL/NSPAD 的六个零盒排除单位或 padding 比例矩阵，可为本项目“非 sprite companion 取零”的实现合同提供有界依据，不能声称精确官方零值或全部 provider 已测。NSPAD 同时改变两个 mapped 轴，不能单独归因；96 使用 mid tier 的 1/1024 区间宽度，不可误写为 high tier 的 1/64。动画、其它格式、非有限值及产品可见验收仍独立待证。


## 后续补证：动画的同屏绑定一致性

`animation/` 使用自有双 image TEX，每个 image 为纯红或纯绿，两个 sprite 记录各持续 0.4 秒，Translation 候选分别为 (0.125,0.125) 与 (0.375,0.25)，Rotation 均为 (0.25,0,0,0.25)。片段探针同屏输出六个公开 companion 的量化网格和固定 literal 坐标的 raw sampler 颜色阈值码；颜色读取不使用 companion 坐标，因此可独立区分当前纹理与帧值是否错配。两组 header/mip 尺寸均 384×192。

自有 TEX SHA-256 `1c93f794ab044619851d28f97169be4f99c75cb68ace9680129717e5ffa97eea`；`animation/manifest.json` SHA-256 `613f6858d2d5db9e2a4598dffa7c08712c74d0aac7b233256a42780bffd9859c`；`animation/freeze.json` SHA-256 `3fb780cb56029e40ecdc6905179966effd248b0a1db3b7b5bbb43cf4ad66ed52`；`animation/results.json` SHA-256 `b4507a3714fe69ba9a31a9f498746417bc221925db677614662966e6cabf4202`。身份和捕获索引见同目录 `capture-index.json`。

三次新窗口加载各 120 张原 PNG，主进程仍为 7492，窗口 handle 分别 4916122、4456750、7340624。独审重算 184320 格、26542080 个中心像素，并核对所有原图与 host 捕获载荷、metadata、输入和索引身份；得到红色及对应 companion 183 对、绿色及对应 companion 177 对，每次加载各观察到 12 次状态切换；没有 invalid、unknown 或有效错配，512 格中心区均 100% 命中端点。三次采集实际间隔范围分别为 22.474–123.632、21.378–76.389、17.93–65.748 毫秒。

这只支持所采呈现状态中的绑定一致性，不证明内部 CPU/GPU 的精确更新阶段、连续或原子的 render frame、一个 GPU frame 内的时限或循环边界全部状态。双 image 是官方观察输入；MyWallpaperX 仍限定现有单 atlas 准入，产品帧事务及可见输出必须另行运行验证。18 项动画冻结、32 项原协议及 29 项补充冻结均无漂移，独审 ACCEPT；捕获索引 SHA-256 `043e9263611e3f30704b63a3b8e92ad3dee37f3129204c862b231933a29aa6d0`。
