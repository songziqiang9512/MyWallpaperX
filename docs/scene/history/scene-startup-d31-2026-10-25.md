# Scene 启动 D31–D39：RAM、机制收益与产品采用

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。2026-10-25；步骤与后继裁决归[启动专项](../../development/wallpaper-startup-optimization-plan.md)。D31/D32/D35旧RAM失败与D33失败永保；D34准备/磁盘收益促成D36产品接入。D35候选准确撤回；D36已过8方法/Debug/阶段近上限RAM，时间只保观察；375原采样失败与候选功能补验分别保留。D37进一步消除复用命中前完整读取；原D7对照暖RAM五对均低但噪声失败、375短命helper覆盖未齐，新版功能另补。D38以新独立完整观测另测同产品，近上限RAM三门通过；375短命PID已覆盖，但连续gone导致100.484ms完整轮缺口而STOP。D39退出重核使七App采样间隔全部合格，但短命helper首次query即gone而原coverage失败；按先验停止375统计并明确未覆盖。最终当前视频长跑及真实OS/P7仍待，旧失败不改。

## 测前政策、身份与准备

沿 D30 事前设计，保持原 30FPS、C0/C1/W0、五组 AB/BA、隔离 HOME/cache、原产品入口和截止期；首个登记 A/B 兼资格，不额外 pilot。原非目标 `max(5%,2×本项噪声)`、两臂各自不超过 5% 的噪声门及绝对预算同时保留。所测场景绝对预算为 `min(物理 RAM/4,4GiB)`；本机 M4/16GiB 为 4GiB。这只是事前验收余量，非系统空闲 RAM 保证，不更改合法内容或产品 GPU/decoded/磁盘额度，GPU 账本不加到 footprint。M1/8GiB 仍是设计假设，未在最低设备实测。

基线复用实际 D7 全包展开直接前驱 App，executable `725b8e9c…ad766`；候选复用实际 D28 App `bb658162…a2099`，不把 D7 当作已不存在的原 P0 App。两份实际 staging 同名 `MyWallpaperX.app`，原签名和 binary 身份前后核等。旧 App 没有 admittedSource 观测；以其原产品入口/根/item/呈现、完整出版守卫及实际解包产物核资格，不伪造旧 IPC 字段。候选逐 row 严格核完整 admittedSource。

V4 ABI 已真实编译并执行核对：结构 296B、对齐 8B、pid_t/int 各 4B；resident/current footprint/startAbs/lifetime footprint 的 offset 分别为 64/72/80/240。该工具资格不是 App RAM 结果。观察按预定 20ms 调用 kernel，保逐 PID UUID/startAbs、原 PID 发现及实际查询 span；同轮 current footprint 才求和，逐 PID lifetime 高水位另列，禁止相加为同期总峰。D31 的 30 次原 native entry→finalize 采样质量检查均通过。结果仍只是已发现 root/descendants 的串行轮次采样集合，非原子/连续峰值、唯一物理 RAM、全部瞬态/共享 XPC 或 GPU 总容量证明。

三项输入都由保留的真实 D8 importer binary `06b77c83…113134` 经原 Transaction/Publication、实际 metadata/完整 marker/receipt 认证核独立出版；同一输入的两臂 author facts/tree digest 相同、generation 不同。出版在测量前完成，不手造 marker/ref，不混入原 live 源重编。own-longgop 是原 320×180、130 包/17ms、唯一首关键帧的 10,389,608B 自有 VP9/TEX 输入。375 原作者内容只读保留。near-cap 则仅生成一次：**264,096,939B**，SHA `ea83faf22162bc13b8d00bfd56d9d601063c20c897a74c3b4e9e646273edce33`；原 parser 实际核 3300 包、每包 17ms、仅首关键帧及全部 range 合法。沿原 D28 TEX/PKG 函数组成 item `900000009`，scene.pkg 264,097,638B，再完成两臂真实 v3 出版。它仍不是 RAM/AV 或完整最大输入矩阵通过。

## D31：首输入五组与噪声 STOP

预定顺序为 own-longgop→375→near-cap。第一个输入跑完原五组，共 **30 App / 40 请求**；30 次来源/行为/采样资格和普通退出均通过，五组的两臂都合格。正式偏好、冻结工具/输入守卫、两 App 的签名与执行文件未变。全部原生 App 批次用时61.408秒。60个实际root/daemon身份连续并最终全部明确ESRCH，原flock可重取；没有强制退出/重跑或删慢点。2274轮中2060完整、214为终态边界partial；关键区间无partial/error，最大完整采样gap25.674ms、round span2.292ms，均满足事前100ms上限。

下表来自实际报告的同条件五个采样集合峰值，单位 MiB（1,048,576B）。配对列先逐 iteration 求 candidate−baseline，再取中位；百分比同样先逐对计算后取中位，**不是“各臂中位数之差÷基线中位数”**。

| 条件 | 基线峰值中位 MiB | 候选峰值中位 MiB | 配对差中位 MiB | 配对变化中位 | 基线/候选噪声 | 原门 |
|---|---:|---:|---:|---:|---:|---|
| C0 | 190.721 | 185.314 | +0.016 | +0.008432% | 2.965725% / 11.905446% | 未通过 |
| C1 | 188.064 | 179.424 | -12.453 | -6.627254% | 13.226843% / 3.587876% | 未通过 |
| W0 | 253.486 | 259.143 | -6.766 | -2.669031% | 13.825966% / 6.933935% | 未通过 |

C0 是候选噪声超门；C1 是基线超门；W0 两臂均超门，即三个条件都未通过（六组噪声中四组超门）。候选各点虽低于预登记 4GiB 绝对预算，不能抵消噪声失败，不能据负配对数值宣称稳定减内存。C0/W0 也显示独立中位和配对变化可能方向不同，不混用口径。

实际总报告 `passed=false`，错误为 `STOP original relative/noise/absolute memory gate`；这是原验收门失败，不能改称整批成功。D31按当时协议不重采、不补组，**当时375和near-cap各0 App / 0请求**，只有真实出版与 parser/输入准备资格，未测 RAM 或启动。这些输入的未执行不能被 own-longgop 结果代验。启动时序摘要也未授正式性能。30 份 native 的 `daemonFinalizeAndDrainObserved` 全为 false；普通退出不升级为 typed GPU/AV drain。首呈现与 parent finalize 不自动证明持续视频解码或全媒体等价。

## D31 原件与边界

实际产品协议 SHA `9149c0dfa94d35b51494646f7dc9c3bc750fd872f13108cb5b11fcb5dc378a74`；产品总报告 SHA `84af5281a887a0634df3ebf94a8cbf668a2799aaa3bc25b9f713d79bc140c2a1`。真实 ABI/准备报告 SHA `285be7b85b28e2460e9985e3b4ac9e651253dc90bf0b97ce4d8c2263e2a37473`；3300 包生成/parser 报告 SHA `044331f8a668bfabf064b32564ab9c961c51eb028e4e74fd02d0e79b16513de6`；near-cap 打包/出版报告 SHA `bb6714f5f35f41f0ed172e400407c3f69e4e0a0f8b2792c50d7a116b3b8b8340`。实际 argv、ABI、原始 native/app/采样数据、各出版完整事实及全部原点均属本批必要证据；必要证据归`.artifacts/scene-evidence/runs/wallpaper-startup-scene-d31-20261025-checkpoint/`；真实raw双独审、归档及精确清理以实际终态收据登记。

本批没有新的 App 产品构建，辅助 ABI/原 parser 薄工具编译单列；没有产品/长期测试改动、没有新优化采用，全部专项改动仍未提交。用户已选择把 OS 恢复操作延期，未做实际 resize/睡眠/唤醒/解锁/压力。D27–D29 的新增媒体 leaf 峰值风险、历史 seek 间歇未归因、原累计噪声失败及约 39ms 交接完成成本不被本批关闭；本机结果也不授最低设备、多屏或 Release。

## D32：剩余输入独立矩阵在稳定 W0 回退处停止

本节补充 D31 原结果，不重跑、替换或冲销 D31 `own-longgop` 的噪声失败。事前登记剩余 `near-cap → 375` 两个独立一次协议，各保原五组 AB/BA、C0/C1/W0、30 FPS、90s 外界、20ms 观察器与原 RAM 算子。仅当完整 30 App 行/五组的 native、来源、采样、预算、退出、偏好、输入及 helper 均合格，原错误仅为 memory gate，且相对/绝对门均通过、唯一失败为任一臂噪声 >5%，才允许继续下一个尚未运行的输入；partial、相对回退、绝对超额或其他失败全局 STOP。

`near-cap` 一次执行 **30 App / 40 请求，30 行全部 qualified**，五组完整，原偏好与冻结输入/helper 不变，退出及实际终态读取合格；原 driver 80.83103585243225s（外层 80.908s）。候选实际 admittedSource 精确核对 20 请求；基线缺此遥测，另保 15 个真实展开缓存核验，不能把旧路径能力等同新 managed 信任。输入是 264,096,939B、3300 packet、320×180 的已获原 parser 准入 WebM，封装 TEX 264,097,026B、PKG 264,097,638B；不是实际最大内容/全内容容量资格。

| 条件 | baseline 峰中位 MiB | candidate 峰中位 MiB | 配对差中位 MiB | 配对差中位 % | 噪声 baseline / candidate | 原门 |
|---|---:|---:|---:|---:|---:|---|
| C0 | 932.486778 | 920.189903 | -14.968773 | -1.6013088379% | 2.2872234580% / 2.6319295522% | 通过 |
| C1 | 929.361710 | 916.283607 | -13.187477 | -1.4184098198% | 0.6876359263% / 0.8270526534% | 通过 |
| W0 | 1023.705482 | 1138.174347 | +113.156319 | +11.0394466775% | 0.2945771185% / 1.0254949787% | 失败 |

MiB=2²⁰B；各臂中位数之差与“配对差中位”是两个不同量，表未混用。原 W0 配对差为 `[10.887238979982914, 12.13374783134189, 10.925137583459652, 11.03944667751034, 12.653832453217229]%`，五对均增加；其噪声原值为 baseline `0.29457711846011814%`、candidate `1.0254949786834657%`，不是噪声超门。W0 配对中位 **+11.03944667751034% >5%**；绝对 4GiB 门通过不能抵消相对失败。因此原 case report `passed=false`，adapter `matrixCompleted=false / passed=false`，`globalStop=relative or absolute gate failed`；**375 为 0 App**，不把未执行输入列为通过。

离线核现有十份 W0 轨迹：五个候选 sampled aggregate 最大值均在第二次 `preparingSurfaces` 后约 246.186–451.328ms、第二次 presented 前约 9.428–19.678ms，daemon 当轮约 1.174–1.189GB，parent 约 16.7MB；两臂 parent 差远小于总差。基线峰也位于 surface 后。此为同 tick 串行读取的 current footprint 合计，不相加独立 lifetime high-water，不证明连续峰、所有瞬态或 unique physical pages。现有记录没有 idle plateau，不能将回退归作退出噪声，也不能据此指认某个资源 owner、AV SDK 泄漏或 worker 已终态。

资源/AV 静审未发现可确证的新常驻 whole-package Data、全局 payload cache 或强引用环。package Root 保 FD、索引与摘要，snapshot Data 属调用者；TextureLoader、TEX parser、材质目录、decoded-cache eviction 与相关准备/清理链多处与 D7 实际 before 字节相同。旧、新作者纹理均走 `.resource(handle)` 的 heap snapshot；先前“旧 externalFile mmap 仅一份 heap、新 package 两份”的解释已纠正，不能据此归因。本机公开 Foundation interface 显示 `Data(nonzeroSlice)` 为归零会复制，而直接 COW slice 保非零索引；改一行 `subdata` 既不能保证无复制，也可能破坏 MP4 sniff。共享 backing 还须计入 prefix/tail；任意非同步 fragment flush 不能绕过现有 VP9/timing/seek 约束。本批均未采用这些推测修法，无新产品改动或 App build。

后续静审已排除本例两个运行中的 remux worker 重叠：普通可见视频必须先经首次 writeWebM/worker.result 成功终态→installItem→实际帧publication→完整初始cohort/GPU完成→首呈现，才会开始第二次选择。旧 active Player、decoded buffer、private file 可与候选准备并存；Task终态不等于SDK/对象内存即时回收，额外持有成因仍未知，不据此归因泄漏。该worker-overlap假设STOP，不再为它加观测或cache。其后任务机制及停止结算见D33–D34；不据本假设采用缓存或宣称完整App修复。不重开packet借用/池微调、不先加cache或强等，原P6强驻留/长期转换缓存STOP保留。

证据绑定（`T=/private/tmp/mwx-startup-optimization-fbRhFY`）：

- 矩阵协议 `d32-product-memory/product-protocol.json` SHA256 `d4b282e083bd3afbb30e88ec31ecb58acad0cd4c0c4e37ec9a68733a3372197d`；near-cap 原协议 `near-cap/product-protocol.json` SHA256 `be838a25a72468c4ac00ac6b20a9db2f4c5678cd569eb617c842fa8e07658658`。
- 原 case `d32-product-memory/near-cap/product-execution-once/report.json` SHA256 `7bf8ae0b6ff05d47086fe2eee3ca1e7aa714e6643c34a20c04bff3c517052552`；总 STOP `d32-product-memory/execution-once/report.json` SHA256 `69a3a1e9f3ac1cfb1c12a9df4c821b89ff57d4e6a9cfdbaf5d8e12fcdaef0319`。
- 独立结果 `d32-result-independent-review.json` SHA256 `68b4eeed0749653d98162dc0a7cfe857184802a9e0e020fcc728b22f81596a4e`；资源审查 `d32-resource-lifetime-review.json` SHA256 `ee90fb8829f77e3bca9682378267bca78e6ba392157172f0fb84f0ca001c2aeb`；AV 审查 `d32-av-warm-retention-review.json` SHA256 `50686a0f9210bbf20be005deac2e7501c0fda0ca4da8ab167f85bb2575b127ed`；slice 限制 `d32-video-slice-readonly-review.json` SHA256 `a4730eb10e7a0f52be70e43bc73e427e88a476658c464039f4aef2c5e2af9239`。

本补遗只写实际观察及 STOP；归档、受保护依赖和 exact cleanup 的实际状态归同批 Root 收口收据；历史正文不替代执行收据。不授 P2/P7 RAM、M1/8GiB、完整最大输入、持续解码或真实 OS 恢复验收。

补充普通可见视频链的静态反证：`d32-worker-overlap-hypothesis-review.json`，SHA256 `5d6b83089626873386b299de3f6d94a210a88209fa4c5f9e7589726fd8c0345d`；该结论限本例，不外推隐藏/失败fallback或其他provider。

## D33–D34：独立时基 oracle 与完成文件机制停止

D33仅task机制，clang/Swift均exit0；A实际两帧及不同Source/Player/item、源身份、文件/预约、暂停独立性等前序事实通过，但首个raw-target `0.697` 的新增1µs比较失败即STOP，native exit1、B零执行。Source:869–881的requested是实际媒体CMTime量化秒数，不承诺raw Double精确，原oracle无合同依据。D33未记录actual requested/scale，不得用后续scale=600追认本次原因；原协议、binary、A的native.*和失败永保，无完整机制/安全/内存比较结论。

D34新一次协议只改独立oracle：真实numeric正duration/正timescale、三target在duration内，实际snapshot paused/held==rawtarget、AVPlayer.rate0及item/duration(value/scale/flags/epoch)/loop前后稳定，使loop/clamp恒等；expected仅公开CMTime(rawtarget,实际timescale)→seconds，仍严格1µs，不复制私有clamp/用600 fallback/candidate自证。原输入、像素/generation、decoded±1/30、4/.4/.5/20/30s及两采样窗不变。实际A后B各一次、各33 checks全true；12个seek context的duration均33660/600，有效requested误差0，实际同时间像素、generation、独立player与最后实际AVAsset borrower释放→unlink+budget0通过。

| 单对原生机制指标 | A 再转换 | B 借用已完成文件 | B−A |
|---|---:|---:|---:|
| 第二Source ready ms | 183.358375041 | 18.825749983 | −164.532625058 / −89.7328115% |
| 第二ready磁盘预约 B | 528176898 | 264088449 | −264088449 / −50% |
| 功能窗current峰 B（MiB） | 887407984（846.298203） | 886605144（845.532555） | −802840 / −0.0904702% |
| ready窗current峰 B | 833373480 | 819791096 | −13582384 / −1.6298076% |

功能窗完整round为31/25，ready窗为7/1；B仅一个ready内部round，不能将该峰差宣称连续峰、独占workspace或正式性能。ready/磁盘只证此单对原生机制减工；功能窗RAM没有明显下降，按事前规则**STOP作为RAM修复的产品采用，不补跑/cache变体**。本任务不经过完整Model/Registry/Host来源准入，不授managed cache、完整App修复/正式performance/最大输入或OS资格。D33新失败不追认已修，D32 +11.0394%产品暖RAM阻断、375未跑、D31噪声及旧seek证据仍保；产品保持D28，没有产品改动或Debug build，原P6强驻留/长期转换cache STOP不变。

两次实际等待终态后Root核精确ps已无自身PID、flock可取并明确归还peer；D34两native exit0，observer末记录exited并非ESRCH，不冒充typed AV drain。下一责任点仅是整产品内存持有/分配路径，额外SDK/对象持有原因未定，先据证再修；不新增未证mmap/池/缓存方案。

原件：D33协议SHA `c4c55b67cd10e9003d2d2a4ac2d4e47b0f3570bb7b047f90c6ad9b2df129df26`、报告 `26833c6ba823f53a30fce9aa703fa91175c0ab4b3689cad90c1b39cdce81d1ff`、独审 `faa2d2ae7f01a3e840f605c63acc26b36d072beb6c8bc530039acfc8c0bceb3e`、语义审查 `a29b6bd7e62c23ce81bbd2eef93aa31cdbf363b24e255fcc7f2cf2e6c85193f2`。D34协议 `8429034c9f7276cafb31bf2740db5ede80429e66c3ba5e53d1d2231c3008c12f`、报告 `5a1528ff4daf0f2f7419d686ea0c397648bc693c87f7efe452ee4d56b4b310ff`、独审 `edb3eed332da40133912e1d981f1818d1dedffead24f6054b6fd81f1a0b2bca3`；实际事前plan/health另存`d34-prior-plan-source`，不以最终文档冒充先验。原记录路径归T下`d33-completed-video-mechanism`、`d34-completed-video-mechanism`与独审收据；实际归档/保护/清理状态归Root收口收据。

主要启动链开发已落地，可信来源、按需包读取及切换退出已有有界功能证据；带有效 receipt 主路已退出每次整包展开，旧 managed 无 ref 的完整认证与合法 builtin fallback 仍保原职责。用户所问真正剩余是三项：**整产品 RAM/输入覆盖的验收与失败结算、延期的真实 OS/显示/压力恢复、最终性能/旧失败/文档证据及精确清理汇总**。已 STOP 的缓存框架、Web Host 复用与媒体微调不是欠开发；本批不能说“全部顺畅/全链等价/旧链全删”或 P2/P7 已完成，也不为填满清单无限重采。

## 后继裁决更正（2026-10-25用户反馈）

D34停止的是“用完成文件复用修复RAM”，并非否定其准备183.358→18.826ms及磁盘预约减半的原生收益。此前把下一责任点限定为内存、因此暂不推进产品接入，取舍过窄。用户明确任何方面有收益均可考虑接入；现方案将有界完成文件复用列入后继产品集成，补来源/完整identity、原预算、独立取消与最后AV借用释放及真实App收益验证。D34原一次机制结果与D32内存回归原样保留；长期强驻留cache仍停止。

## D35：共享视频TEX候选验证后撤回

按事前方案，仅独立Root捕获的单image/单2D mip/非sprite非volume、compression0、视频magic成立且payload≥64KiB、整个捕获overhead≤64KiB/原budget许可时使用Data COW slice；外部mapped文件、未知backing及不合资格内容走原copy/decompress。完整保留逻辑bytes计原Reader/Loader预算，MP4 sniff相对startIndex。目的为减少大块复制；不是更改输入准入或播放器。

新3方法加原8方法与最近WebM非零range、真实Loader、volume/parse gate共20方法、7选择器，全部exit0、无skip、2333依赖bytes/modes前后稳定。它们证明可见range、实际作用域内共享布尔、双向COW、父值退出后可用、预算exact/fallback及邻近输入；不证明整产品收益。固定5966源Debug成功408.418秒、strict深签名exit0、冻结源无变化；构建耗时不是启动收益。

实际原near-cap五组AB/BA、30FPS、原20ms kernel observer/90s外界和全部原门不变。30App/40请求的来源、原生呈现/提交、采样、偏好、输入与正常退出全部qualified。各条件如下（每臂5值，独立median仅作描述，裁决使用原配对median）：

| 条件 | baseline采样峰中位MiB | candidate采样峰中位MiB | 配对RAM中位变化 | 双臂noise | 原门 |
|---|---:|---:|---:|---|---|
| C0 | 934.706 | 921.581 | -0.015274% | 2.2734% / 3.0773% | 通过 |
| C1 | 933.190 | 920.659 | -1.351094% | 2.2219% / 2.2538% | 通过 |
| W0 | 1018.112 | 1170.299 | +15.437981% | 2.5737% / 2.0654% | 失败 |

W0五对全为正，配对中位+15.4379808739%超原允许5.1474009923%；绝对4GiB过不能抵消。adapter正确全局STOP，375零App。启动摘要C0/C1/W0配对中位分别++64.769ms/+5.251%、+74.894ms/+6.560%、+105.713ms/+27.883%，没有净提速证据；原performanceAccepted=false，不升格正式时序，也不将D32与D35跨批差额归因为本片。

依据“任何方面实际收益均可考虑”的用户原则，本候选没有已证产品净收益，按先验停止，不补组/调门或继续COW微调。三产品/三测试逐SHA核当前冻结字节后，仅以本片actual-before准确还原；原D28改动及并行D36保留，新增3方法随已退役API退出，原8方法全部保留。当前live代码不含此候选，DerivedData的D35 App仍仅作该次证据；不能当D36或live源码验收。D34文件复用的已证准备/磁盘收益不受此撤回影响，D36继续产品接入，RAM问题另行结算。

- D35实际protocol `d35-product-memory/product-protocol.json` SHA `146c460610b80b23cfc95733753d512479a2315f7800a14a50271ae43ec52c2c`。
- actual near-cap report `d35-product-memory/near-cap/product-execution-once/report.json` SHA `ec224f4ae4e8b2bfa21767e019d16bfbcc595c60abe70f4682eb87471362af1f`。
- 全局STOP `d35-product-memory/execution-once/report.json` SHA `8ed42b0483bcb43829972616dcc1d9b5d162afb3a80d421309452b138687eabc`。
- 20方法报告 `d35-regressions/report.json` SHA `d99409736c5044f0250ba4b19b1afbbeb05fa1e00a7e44a1d9e05a40fd005bbf`。
- Debug `d35-product-build/build.json` SHA `93f992a6b34c1f055718e67d8118dee41ab2c5d19c742cbb78aa5121ffcc6a8d`。
- 六源准确撤回 `d35-withdrawal.json` SHA `26d43e396cc09c85c0a4905a3c9a2f486773e285f3798fbbc454254e173aad07`。

计时后已核本轮App/compiler/probe全退出、legacy lock无、flock可取并释放，明确归还peer。D35成功构建exe SHA `36ae6f905f7ea588c5ae0b824bebcbc1d5d3eeabc3c23257db3a173a7532480b`，actual source map SHA `fe870c7a63852d815ecd092fa2c99550be38f0e0d5c4785a9513a01f365384de`；D28原App另保精确副本。归档/精确清理归本批收口收据；未提交、推送、发布。

## D36：完成转换文件接入当前产品候选

用户明确任何方面的实际收益均可考虑接入；不以“RAM未下降”否定已证准备/磁盘收益。按事前设计沿现OwnedFile.SuccessfulFiles弱表加用途分区，Registry在原声明/来源前后fence后借完成WebM文件；miss仍各自原转换。登记仅纯PackageIdentity/cache目录与closed Writer/output revision，不授权来源，不留Root/Handle/lease；并发取消与独立Source/Player/clock、原AVAsset最后借用/预算不变。v1捕Handle冲突在编译前修为v2，原件保留；无额外长期缓存、播放器或任务池。

实际8方法、3组全部通过，无skip，71输入稳定；新26事实包括两个独立Player/真实GPU红帧、同file/单预约、停A后B继续、actual asset-only→最后unlink/预算0；原storage27事实、Sound旧4及OwnedFile旧2保。仅两个material方法本轮执行，未冒称完整3方法或旧seek全矩阵重跑。5966输入冻结Debug成功406.899秒/strict0，无源变化；它是构建成功事实而非启动耗时。D28/App与D36/App的产品map仅三个provider字节不同，项目、flags/toolchain一致；两臂都核真实managed admittedSource，原D7提取marker不适用本片，不伪称旧提取基线。

近上限输入沿原真实出版pair、五组AB/BA、C0/C1/W0、30FPS、20ms kernel observer与90s，30App/40请求全部qualified。原偏好、真实来源/呈现/提交、采样及退出全部通过，阶段RAM三门通过（绝对预算4GiB）。本片的独立中位及原配对算子分别列出：

| 条件 | 等待中位before→after ms | 等待配对变化 | RAM中位before→after MiB | RAM配对变化 |
|---|---:|---:|---:|---:|
| C0 | 1288.705→1251.144 | -37.561ms / -2.914631% | 932.815→920.159 | -0.098408% |
| C1 | 1237.271→1265.163 | +27.892ms / +2.254316% | 917.174→916.315 | -0.146515% |
| W0 | 440.071→302.654 | -134.855ms / -30.643919% | 1148.268→1008.377 | -12.587175% |

W0五对等待均减少；RAM三条件双臂noise皆≤5%，原相对与绝对门均过。时间C0/C1/W0的baseline noise分别37.8876/18.8582/28.5377%，各超5%（共4/6 arm失败），故不授正式提速或overall performanceAccepted，只保限定观察和已证机制减工。D28→D36阶段RAM改善不能直接取消D7全链旧失败，仍须最终同条件确认。

375原仅D28 baseline C0一App实际呈现/退出/来源全合格，但采样完整round gap116.816125ms超原100ms；首次资格失败即全局STOP，candidate零App，原报告passed=false/总矩阵false永久保。随后另行事前冻结candidate-only功能协议，原core/30FPS/90s及来源/偏好/正常退出不变，仅跑此前未执行的D36 C0/C1/W0共3App/4请求，全部合格；没有observer或RAM/时序统计资格，不重采baseline、不补原五组、不调门。此补验只证明真实作者输入的当前功能，不把原375统计失败改绿。

独审结论GO保留未提交产品候选。它使用原读取/Registry/Source、未命中原转换，原已完成成功文件为弱索引；不产生竞争播放owner。当前App exe SHA `b8c5421e2cd6f336bf4c67c7b9ff150ee8c9ef8bc1790f44c0ee24612b676b60`，source-map SHA `61910ab2fd9b7750346093822e119e5508234be6c0ffd3e3dc0b5cdf199aba48`。所有本轮79个已知owned PID已核ps gone、flock可取释放，明确交还后恢复原同一签名UI试用App/同HOME和偏好；不借此宣称typed AV drain或全部OS恢复。

- 8方法 `d36-regressions/report.json` SHA `73ed96c9cacd0e365194a2a1b0b0a22d10f33529e5336ee5e15e6b53342dc04b`。
- Debug `d36-product-build/build.json` SHA `0c71f50bdbdb0ecb1188ee9f163c6b40790bb61eb9eee4b46533358a97ab0487`。
- 阶段protocol `d36-product-memory/product-protocol.json` SHA `5166bc1c47eb26fb0e7ad7e2612c8c6270605cb6315fad41159cfe6756ad00e2`。
- 近上限实际报告 `d36-product-memory/near-cap/product-execution-once/report.json` SHA `ddd1f3cd5227e5f9198dbac1cb4bd0f6764c80e43d93820aa565af480860f26b`。
- 375原采样失败 `d36-product-memory/375/product-execution-once/report.json` SHA `fc05bb461cfa837dfc733defd2350a8953719c3672eecd07daa6c413c6f969b1`。
- 新候选375功能协议 `d36-product-memory/375-candidate-functional-protocol.json` SHA `896472ee37b8be79cf3e4af935820544b22ad5bd6391da616c2d17924c3b36d9`。
- 新候选375功能实际报告 `d36-product-memory/375-candidate-functional-once/report.json` SHA `2ebae0d3a06cf233f20d5913b05c60e9e7962957b8023161735ade0f83fa1a33`。
- 实际结果独审 `d36-product-result-independent-review.json` SHA `1201712b9e26218e96fec377f197b74a34f7e2c08f474c7078c37cf7f6eecda5`。
- 逐raw复算 `d36-result-recalculation.json` SHA `d3c9f4f9ffade672ce153e9bdbff0013b5bd1c9efbc8c933cabd7870aa5d7727`。
- 窗口终态 `d36-window-return.json` SHA `71da7e8ec264c8baffe45b09e95d5690567252a187955a87187bbc46d88d350f`。

P2后继仅原Registry中有实际依据的声明前查找重排及全D7最终RAM确认；没有长期保存payload的免费交接。375内存、延期真实OS/显示/压力、原时序噪声与旧seek边界保留。阶段以已证收益采用，整体仍未授P2/P7完成；精确归档/清理归本批收口回执，全部未提交。

## D37：原Registry先复用后读取，统计资格继续分列

仅改原Registry一个产品文件，439行，SHA `9c5d3dd83c9a237a8696c8da04ec52756bc5bdbedc5efe35fc2447044deb7e33`。已选package TEX的当前完整Root身份先核，原live Source/弱完成文件先查；同步闭包只在miss读取声明。一个核心继续负责失败、epoch/rebuild和唯一发布；完成文件构造失败原callback+nil，不二次转换。原Source/OwnedFile、独立player/clock、磁盘账本与AV最后借用不变，无新增常驻Data/Root/lease/flight。loose/external、非TEX及无成功凭据的坏内容保原路径。首次预算拒绝的跨metadata→GPU重读不在本片消除范围。

actual-before产品快照4352文件逐字匹配实际D36 build-map。共同新夹具使用同一份生成VP9，真实Reader/Root、decode预算0与explicit evict；独立C仅转发原pread并保errno，按实际FD+dev/inode+entry精确范围计数，mount后reset。冷读先给非零正控，再核命中，避免没接到钩子而报0。原4方法AST与删除D37新增部分后的旧Harness逐字保持。

| 实际entry payload读取 | D36实际before | D37 |
|---|---:|---:|
| 冷读正控 | 2101B | 2101B |
| 同Registry live Source命中 | 2101B | 0B |
| 独立Registry完成文件命中 | 2101B | 0B |
| 已取消请求 | 2101B后拒绝 | 0B即拒绝 |
| 不同generation / 最后AV借用释放后的miss | 各2101B | 各2101B |

两臂新13事实均真，current原D36复用26事实和storage27事实均真；合计4方法、132输入稳定、零skip/error/failure。候选5966固定文件Debug成功，440.589812s不作性能证据；strict签名0，源码无变化，actual executable `f075dca44ba637e5a23a28f9e95b2c160279f4e100fe93c81a59f31a6553ef68`，source-map `5cb2d669bcd95d8b77b861da5efd2b44ba930314b46981f2f4705258f0f19093`；仍原优化Debug flags/toolchain/Startup身份。构建早于最终测试和prose，等值声明仅覆盖实际产品/工程输入，不冒充所有最终测试文本都参与App编译。

原D7→当前D37为累计对照，非D28阶段对照。继续原真实出版两臂事实，仅换candidate executable ref；原五组AB/BA、30FPS、20ms、90s、100ms覆盖及相对/双噪声/4GiB门均不改。首次静态适配曾误改原D31 SHA常量，独审在import/prepare/执行前发现，恢复并逐项核所有原SHA常量，保原阻断记录。

near-cap原30App/40请求全部qualified，96.293s。表中RAM为已发现进程的串行轮次采样总和峰中位，非原子/连续/全部瞬态或GPU容量：

| 条件 | D7 RAM MiB | D37 RAM MiB | 配对RAM变化 | 原门 |
|---|---:|---:|---:|---|
| C0 | 970.830 | 959.721 | -1.144312% | 通过 |
| C1 | 965.643 | 954.455 | -1.145758% | 通过 |
| W0 | 1066.737 | 1038.627 | -2.873835% | 仅candidate噪声5.179615%失败 |

W0五对candidate全部低于baseline，相对/绝对条款均过，但原对称噪声门仍false；不删低点或将五对低直接改为正式通过。时间C0/C1/W0配对分别-56.145ms/-3.415659%、-82.539ms/-5.905129%、-461.705ms/-67.139513%；W0各臂中位672.928→225.975ms。六臂时间噪声分别34.764530/44.405987%、24.512844/14.067700%、28.440933/53.514769%，全部超5%，仅保观察。不与D36跨批差额归因本片减读，也不冲销D31/D32/D35旧失败。

按事前严格pure-noise proof仅续下一未测375。首个D7 baseline App正常呈现、来源与退出通过，samplingQuality也通过（最大gap88.770291ms）；但报告短命spirv-cross PID76401仅查到gone/ESRCH，没有成功RAM query，coverage partial，原row/matrix均false并STOP。D37 candidate在该矩阵零App；随后独立事前协议仅补此前未运行的新candidate C0/C1/W0三App/4请求，全功能通过。无RAM观察/统计、不重采旧baseline，不把本失败误写成D36的116.816ms gap失败。

80个已知PID原终态与物理ps均gone、无App/compiler/probe、公共锁可获取释放，运行窗口已归还UI会话；对方新UI实施不恢复旧试用App。正式偏好、作者/库与冻结工具守卫不变。独审支持保留已证重复读减工，正式global RAM/375仍未齐。后继先审观察覆盖方法，不继续改产品追统计绿；真实OS、最低设备、多屏、Release与旧seek未由本批覆盖。

本机原点位于任务根 `/private/tmp/mwx-startup-optimization-fbRhFY/`，受保护提取按本批collector保存，不能把可清理运行环境当永久文件权威：

| 原点相对任务根 | SHA256 |
|---|---|
| `d37-product-build/build.json` | `02479e3f81c0e9509baae5e0ae8c17c2d21ef7288d3d41d656abadf135f1c081` |
| `d37-regressions/report.json` | `afbfe58435c9fa52a52dedc33b203b06fa76654be2093c5c8bd5be4aad5161a6` |
| `d37-regressions/actual-D36-before/proof/input-io.json` | `2df121b056f4a9e53512d82601bc902b7eea0cb9c49be25116d560d4050afe7d` |
| `d37-regressions/current-D37/proof/input-io.json` | `a42536e36bf660cda708aaa21322dc0098968f704a56f884d2e00f37af12f261` |
| `d37-product-memory/near-cap/product-execution-once/report.json` | `275633c751f6e099e65c78e752a1937e5652e32034fb6055b1293213acb12ae2` |
| `d37-product-memory/375/product-execution-once/report.json` | `47aea94e84340197a68dd34828b3d839f395b4e42bd0c99c6f70253b93cd6152` |
| `d37-product-memory/375-candidate-functional-once/report.json` | `d4bd6ef67fd721108c5d249b3802f5f252d081d7eb0cbbaa09977d95f0207cb4` |
| `d37-product-memory/execution-once/report.json` | `12217a4c433d7f08a6ede330aef40448848fcad85ba33a4f5c7a268ac5201017` |
| `d37-runtime-independent-review.json` | `8e7e10ffc50efd536bd71cdef82d702e2a789d218cc2b19dd9f011f5e422624b` |
| `d37-window-return.json` | `d78788152a79d1899c401bde813f9304591637950b663ceeb39df6b025ee486c` |

## D38：新PID即时完整观测，近上限RAM正式通过

本片只改任务采样器，没有产品变更或App重建。D37原375 raw说明core note→首次kernel query19.445625ms，其中等下轮19.281583ms；libproc从未列到该helper，不能反推它在note时仍存活。D38在原唯一线程加入事件唤醒，固定20ms定时网格保持，新PID另触发完整round；原changed/partial/sums、identity、gone非0、原预算及100ms质量门不改。原报告保持原字节，不与新方法拼统计。

原observer两项真实kernel方法和current五项方法一次执行通过；真实Python子进程以pipe/ACK保持在实际完整读取之前存活，另验首次查询已gone保持partial。受控Reader明确只作边界oracle，覆盖未知/变更identity、gone后复用（含首次无token）、capacity、发现后成员变化、单线程、fresh通知、固定grid与stop接纳/drain/join。受控周期200ms的callback→首次查询201.272792→0.049541ms，仅证机制，不认App加速。静态审查与实际raw复算分别独立保存。

冻结新协议，两臂仍实际D7 `725b8e…766`/D37 `f075dca4…ef68`，当前4352产品/工程/daemon输入等值原D37 build-map。来源/真实出版v3库、五组AB/BA、30FPS、90s、原RAM算子及所有门保持。总计34App/45请求，33App全部qualified；余1App仅samplingQuality失败。全部native首呈现/来源/退出成立，不等于完整矩阵通过。

near-cap30App/40请求85.411892s全合格。表中为已发现进程同round串行读数总和的采样峰中位，非原子/连续/全部瞬态峰，不单独计GPU容量：

| 条件 | D7 RAM MiB | 当前D37 RAM MiB | 配对RAM变化 | 双臂噪声 B/C | 原RAM门 |
|---|---:|---:|---:|---:|---|
| C0 | 934.206 | 921.174 | -1.394904% | 2.165945%/2.583322% | 通过 |
| C1 | 932.299 | 915.987 | -1.749699% | 1.595520%/0.385516% | 通过 |
| W0 | 1033.987 | 1000.112 | -3.656962% | 2.440495%/1.551389% | 通过 |

三项相对/双臂原5%噪声/候选4GiB预算均通过；W0前两对candidate略高，不能写“五对均低”。本机M4/16GiB有界验收不外推M1/8GiB、多屏、持续解码或整个合法输入空间。时间C0/C1/W0配对-388.521ms/-23.517025%、-78.073ms/-5.851908%、-316.424ms/-62.859118%；W0独立中位503.386→186.962ms。六臂噪声依次B/C15.123807%/7.354410%、25.595764%/11.425804%、62.211702%/6.894449%，全超5%，仅保观察，不能冒用D37的-67.139513%。

375共4App/5请求14.518131s：旧baseline C0/C1/W0全部qualified，新candidate C0来源、首呈现、退出、报告PID成功查询均过，无missingSuccessfulQueryPIDs/identity变化/discovery或容量错误。native窗口最大round span2.108834ms，但完整round最大gap100.484ms超过原100ms，按协议立即STOP；本协议candidate C1/W0零执行、无完整RAM/时间统计。相同实际产品的D37三条件功能证据保留，无须为功能重复跑。本次candidate单点331253824B不授五对预算/回退验收。

原raw完整round126→131之间，127–130四round分别发现83519/83518/83521/83528 gone，原sums全部null；四次partial正确保留，不能当0或复用上轮parent值。前后间隔依次19.272583、34.774583、62.395583、78.577833、100.484ms。D38只在新增PID时补轮，gone后没有立即重核，故下一片仅考虑gone后的独立完整reconciliation round；仍须新事前方法、保固定周期和旧partial/原门，不能翻本次false或同型重跑。

独审复算全部34份raw，near-cap22个/375共5个额外非periodic完整round真实成立，未拼读数。88个已知App/daemon/compiler PID物理gone，原normalExit/ownedExit/knownPIDgone均真，公共flock已释放且明确交还UI会话；按对方新UI任务约定不恢复旧App。本批其后仅静态/文档/归档。原D31/D32/D35/D37失败均保留；P2剩375统计，真实OS恢复仍由用户延期，P7尚未完成。

必要证据提取至受保护包 `.artifacts/scene-evidence/runs/wallpaper-startup-scene-d38-20261025-checkpoint/`；对应375未解决完整轮缺口，精确归档/清理由Root终态收据说明。任务根原点如下：

| 原点相对任务根 | SHA256 |
|---|---|
| `d38-design.json` | `6503ef22143a7c53f549c4c1ee5490f55f0b18a04e331ff87a3c45b4e4a48bcc` |
| `d38-observer.py` | `9deb3b9aa57b4e0cb2458c7932950ef7f680e161c7356a213429c6d45cee09f0` |
| `d38-test-observer.py` | `c333e5b9f75518f11386ece8718d14bb9c3c293fdd85d65a672a2df2d5e28aaa` |
| `d38-observer-test-results.json` | `69adbc25020ff699e4028b073a029847618b885655b048cff8428f22c4a15bca` |
| `d38-observer-independent-review.json` | `df13995d4fa6a02aa2ccb085b4682a707f8434c2284400e1df106104b23d0ecd` |
| `d38-product-memory/product-protocol.json` | `de94dd6b6f6e205866969ebdb4690669f8af82be4a30ac3df43b2af6988ddf9b` |
| `d38-product-memory/near-cap/product-execution-once/report.json` | `059feeb83d38ced48c63c65b9bab5a85d7ec8247fb76f1da5db216bfb0db3f9d` |
| `d38-product-memory/375/product-execution-once/report.json` | `4038b705ff822d1f68c0b723feeb6678d6c564fc1106683492d63ae58835bb2e` |
| `d38-product-memory/execution-once/report.json` | `0110620db4d818f7a5a20c4dc0a2a2557b76a9636a887a8a24b0737a894bcb30` |
| `d38-runtime-independent-review.json` | `bfc44624a0dcc1746e6ffe351b46bedb0ddeba809faade48ddd0b961c8bbe223` |
| `d38-window-return.json` | `7840b588e2b235563fdf8e4c3c213541e52ad0284bf0c1cd0f2d10c1d642c42c` |

## D39：gone后完整重核生效，375统计按先验停止

无产品变更/新构建，仍同D7/D37实际App及原375真实出版两臂。observer仅在实际移除gone后补独立完整轮，stop排空postGone，固定20ms周期、完整sum/coverage/identity/预算和100ms门均保原算子；原gone/empty轮partial/null不变，exited/unavailable不删除。实际受控before2/current5方法单次全部通过、源码稳定；200ms受控周期真实gone→新完整轮200.589792→0.385792ms，同确定性连续gone序列405.065875→0.091583ms，只证观察机制，不是App提速。

新事前375-only协议，两臂统一新方法，原五组AB/BA、C0/C1/W0、30FPS、来源/首呈现/退出/双噪声/相对/4GiB/100ms门不改；不重跑D38已合格near-cap，不拼旧统计。实际21.454144秒、7App/9请求，全部native/来源/正常退出及samplingQuality通过，前6row qualified；第7为candidate第二组C0，仅reportedPID88867缺成功query触发原组/matrix false并STOP。七row完整round最大gap42.075ms，无原100ms失败；正式五组未完成，没有375 RAM或时间验收。

88867仅一次core note在448426956102666ns，新coreDiscovery round在其后0.039917ms开始，首次query在448426956237833ns（延迟0.135167ms），已ESRCH/gone；kernelIdentity=null、successfulReads=0，所有childlist从未列到。无法证明note时仍可查询，不补零/回填/放宽门。按D39事前“仍不能有效取数则停止未覆盖”结算，不再采样器变体、同binary功能补跑或产品微调；该限制不是已知当前RAM回退，亦不是合格证据。

独审复算全部7raw、grid/sums/peak/quality，41个postGone轮中28个完整、7个空集合仍partial，其余按原规则partial；原gone轮sum均null，未混旧parent值。41个已知App/daemon/compiler PID物理gone，原normalExit/ownedExit/knownPIDgone全true、公共flock释放，明确归还UI连续回归/构建/试用，不恢复旧App。D38 near-cap独立RAM通过、旧D31–D38全部false/噪声/seek仍保。

最终审计另确认：D24的1810.109秒/20切换仅旧fc023…App和314↔375，不能转授D36/37视频长期借用。D24与D37 actual maps仅8产品/工程路径不同；Host/Session/Manager/IPC等值的旧限定行为保留，但新媒体寿命仍需当前App补验。后继D40仅复用原普通UI工具、真实出版自有WebM与轻样本、20切换/30分钟及用户实际OS操作；尚未出版、运行或做手动操作，设计步骤归现役专项。

必要结果提取至受保护 `.artifacts/scene-evidence/runs/wallpaper-startup-scene-d39-20261025-checkpoint/`，保留375未解决短命PID覆盖边界。对应任务根原点：

| 原点 | SHA256 |
|---|---|
| `d39-design.json` | `d906020844ae166f9e3efefa548e2a6051e4597d08567269a441dcff61d55176` |
| `d39-observer.py` | `ef99242781809c6cacbbda421f68a439596e63171dfc819171ed3113d3f0b34d` |
| `d39-test-observer.py` | `e9eefd28302b9444dbc1782b73a36d8be64d9f6cef2b53d23c979ed1083de43a` |
| `d39-observer-test-results.json` | `3d6be6636f7ae1f7a1cfe2d677fa0cff7192af6b49993ba68052d7da7f2fbe2f` |
| `d39-observer-independent-review.json` | `5428ead7711f6847c2ca2003ec6c3898d1facbc284e27072fbdb7339903957ff` |
| `d39-product-memory/product-protocol.json` | `4ba6f90a4614217b78eb74c9ebd6f7e26698a19177787e005a708ee591507eef` |
| `d39-product-memory/375/product-execution-once/report.json` | `81394252f47bf2f3ff334a37f8f8e0cfe7ac7dafab0370cac57575a10f0b9e6b` |
| `d39-product-memory/execution-once/report.json` | `18832b94c61e9a8193c69ba5f3afd8742a194a81ede10ad629de60dafc98068c` |
| `d39-runtime-independent-review.json` | `f0f740c778a34f3d5d21e0061d3b0b3766060a0707f4986018ae15679c22267a` |
| `d39-window-return.json` | `1fc93e31231b4238467c42346a5f5693c19f1c2cfe31ac5ae1fe5f0bc22e91bc` |
| `d39-final-endurance-gap-review.json` | `41be4045aec9d5a012edd1f00f2b7bcb59559b8964a58fe3bd791102301117f8` |
