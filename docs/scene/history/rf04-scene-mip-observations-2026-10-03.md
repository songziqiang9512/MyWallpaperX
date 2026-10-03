<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->
<!-- cutoffDate: 2026-10-03 -->
<!-- uniqueValue: 自有合法 sampler 的 mip 准入、scene scope 与同屏时间词邻接观察；原图独审身份及未证明边界。 -->

# RF04：Scene mip 输入的有界官方观察

> **历史证据 — 非现役入口**。本页不是产品能力或官方内部实现说明。后继归 [RF04 工作卡](../roadmap/batch2/reference-evidence-implementation-cards.md#rf04--d12-已完成画面的共享-mip-输入)和 [D12 设计](../roadmap/batch2/copy-pass-unification-design.md)。实验原根 `/private/tmp/mwx-scene-next-rf04`；所有下列工件名相对此根。产品实施独立验收，本页不授予实现已完成结论。

## 身份与方法

官方 Windows 11 ARM64 / Parallels 客户端 `wallpaper32.exe` 版本 2.8.0.42，SHA256 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`。自有项目、TEX、片段探针与捕获协议冻结；编辑器生成的 stock vertex 只在 guest 内 opaque 复制和核 hash，没有读取、下载或消费表达。没有读取参考项目代码或私有反编译表达。公开依据只提供 [Reflection 作者控制](https://docs.wallpaperengine.io/en/scene/lighting/introduction.html)，不规定目标读取相位。

数值网格固定 32×32，literal 控制、非对称 header、guard、parity 与量化 tier 分别校验。576×576 client 的每格 18px，仅取预登记中心 8×8；RGB≤5 或≥250 至少95%，alpha255，否则整条结果无效。所有正式已审格实际端点覆盖100%。量化值只表示半开盒，不能恢复精确浮点。校准中窗口大小、旧对话框遮挡/阴影失败保留，不纳入正式数值结论。

source 实验为 768×256 scene、1728×576 client，三个等宽列分别直接源、Mip consumer A、Full/第二 consumer B。时间词输入只由自有 source 读取公开 `g_Time`，consumer 不读时钟；编码16位词、header、guard、parity。窗口身份、client 坐标、输入 pre/post hash 和 PNG payload 均随捕获保存。宿主 Stopwatch 只测采集，不测 GPU 帧率或完成阶段。

## 可采用的观察

| 实验 | 差分与观察 | 证据上限 |
|---|---|---|
| C1 | 自有256×256、9级独立颜色 mip；3次加载9图正确区分 LOD0/1/2/4/8，Resolution 四分量均 `[256,256.015625)` | 探针实际读取不同 mip 的正控制 |
| N1/U1/F1 | 候选 `_rt_MipMappedFrameBuffer` 与未知名均6×6、所测LOD黄；FullFrameBuffer 为576×576、黑；各3次加载9图 | N/U 观察不可区分，不能据此证明候选已准入或 placeholder 身份 |
| 槽与 UV | C7/N7 各3图保持相应响应；五个固定UV的 UN/UU 同为黑/黄/黄/黄/黄，UF黑、UC红 | 已测 slot1/7 不改变对应响应；不推广任意槽/UV |
| Q0/Q1 | 同一自有 normal/灰 albedo/探针，只有 REFLECTION0→1；各3图。Q1 尺寸变576，LOD0/1/2 RGB `[.25,.250244140625)`，LOD4 `[.2412109375,.241455078125)`，LOD8 `[.1044921875,.104736328125)`，alpha 的盒含1 | 有界 prerequisite 响应；不是 source/kernel/内部资源身份证明 |
| SG/SY/SD | 换 receiver 灰→黄 albedo 不改读值；全局红→蓝改变外部UV响应，receiver位置仍黑 | 排除本组 local albedo 来源解释 |
| SN/SB | `[prefix,A,B]` 两 panel 五UV均红/黑/黑/红/黑；插入作者顺序晚于 A 的 blue 层后，两 panel 均蓝/黑/黑/蓝/黑 | 排除简单 authored-order 首消费前缀；不证明 GPU 编码次序或所有UV都蓝 |
| SC | A保持REFLECTION1，仅隔离B的material/model使B1→0；3图、两panel同SN | 在已有A生产资格时，B自身flag不是唯一消费条件；无producer等profile未证 |
| 初始时间词 | 8图 Full==可见源；Mip−可见词的有符号模差为−10,−10,−11,−11,−12,−9,−10,−10 | 先前源关系，不是GPU帧数 |
| 快速时间词 | 41图全部 Full==可见源；首图无先前观测匹配，其余40次Mip均等于紧邻上一个已观察 distinct 源词 | 该连续观察窗口的呈现邻接关系，不等于严格前一GPU帧 |

Q 前的 plain receiver、含真实红背景、背景单独正控制均保留：receiver ROI 未见反射外观变化不证明资源不存在；Q 的直接 sampler 才给出资源响应正证。UI 限定检查未产生可用控件后停止，没有据 UI 空白猜参数。

source L1 的五UV固定为 `(.125,.5),(.5,.5),(.8333333,.5),(.3125,.4375),(.95,.5)`。五case各3图，共15原图21panel；后续已排队的L2/L3完成后停止，虽然原图保留，独审仅覆盖L1。

快速窗口的首末2图为完整client，中间39图为事先冻结的全宽条带 `[0,256,1728,320]`，解码中心固定绝对y272…304，没有按未知值选crop。39条带达到12个不同且coherent词即早停；全部41图实际14个不同词、27个重复词，全部保留。40次可比结果没有更早匹配/未知/混合；signed模差−10共27次、−11共14次。实测strip capture-start间隔 min/median/max 为4.279/10.139/20.647ms；不据此声明连续GPU帧或官方更新频率。

## 独立复核与冻结

复核从原 PNG 重算端点、已知控制与词/量化盒，核 guest 输入、窗口身份、host payload 和冻结 hash，不只相信报告的 passed 字段。

| 复核记录 | 通过范围 | SHA256 |
|---|---|---|
| `review-C1-root-record.json` | C1 v6，9216格/589824中心像素；此文件为 root 转记独审结论 | 原始冻结 `protocol-freeze-v6.json`: `a4abf01305afd69afdca618935ecdc3bfcb63b85fd20beb9398c0e3262821941` |
| `review-admission-uv.json` | N/U/F/槽/UV 45图、46080格/2949120中心像素 | `b0ab6cd10b4ca71308615b9c271913cb4d57af393b1518573f7fd888ffb30069` |
| `review-reflection-prerequisite.json` | Q 6图、6144格/393216中心像素 | `f7cc36ea8d436aca826c1c617722956cff864969be617410764198bb312dab30` |
| `review-source-L1.json` | 15图21panel、21504格/1376256中心像素 | `1d3b32ba44076e8b862c7d59ac0b5b096554d62f9b19aca2bf27af6d5473f15d` |
| `review-temporal-initial.json` | 8图768lane/442368中心像素 | `0536157be955e2d3211e5895c18e4d5a0d94ff5cbae05361ff0f33c14ebe454b` |
| `review-scope-SC.json` | 3图6panel、6144格/393216中心像素 | `383fc9bd65d72f154af6636ba18998f3f9c0dcc76567a21470ef571c1d982b0a` |
| `review-temporal-sequence.json` | 41图3936lane/1007616中心像素；108项final和9项capture冻结零漂移 | `7cb10402ce943337c9edf7be2fc9a243c26e1c8aeb64edac1db71c6379a558a6` |

快速窗口最终packet为 `temporal-sequence-observed-packet-freeze-v1.json`，108项，SHA256 `e5cc8e8b251abf8758ecb9752851463d31597c51b4c4f05c0d058ca2c54edfb3`；结果 `temporal-sequence-results-v1.json` SHA256 `80ed0da4efddf05dcfeff2bad85dc76fbd1ccb8baef64a144ef890c33814df74`。43个实际guest输入前后不变。

## 采用与未证明

这些观察足以撤销本 profile 的当前 main 前缀假设，并支持本项目独立采用“最后成功完成 raw scene color”的实现策略。官方没有暴露 command-buffer identity，不能声称已恢复内部历史机制、严格一GPU帧延迟、失败后策略、首帧占位、HDR/alpha颜色域或 mip滤波公式。不能把可读候选推广为任意 `_rt_`、普通FBO自动mip、data/cube/array。

实验结束只关闭本轮自有窗口，核验残留计数0；VM恢复开工前 suspended。未知旧对话框/进程未动。原输入、协议、原图与审查记录在晋升核验前保留；报告不把未审L2/L3或失败校准计入正式通过数。

最终证据已晋升 `.artifacts/scene-evidence/runs/rf04-official-mip-consumer-observations-20261003`，整包999,009bytes，manifest SHA256 `895b71e2fd2d054c46e2224bb2b955798c589f96c2af177f58d9c7144fc484f6`。`final/samples/2026100304/runtime_evidence.tar.gz` 保留原相对树777项（payload11,273,341bytes），SHA256 `00b34c48e2797fcaf7cf59e7327be9799ffd353d7e4eb5d6d5ef8886696260e5`；所有member及promote副本逐文件身份复核通过。`2026100304` 仅是证据工具schema传输ID，不是WorkshopID。184原PNG、自有输入、协议/decoder、7审查记录、紧凑pre/post身份均保留；大体积逐格派生metrics可重算，Base64重复副本未复制。保留包默认14天，原冻结路径描述实验provenance，现存位置由tar内manifest映射。
