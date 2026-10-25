<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

# 壁纸启动第二批：Web 同次准备与 Scene FD 读取基础

> 2026-10-24 第二批记录：行为门、签名Debug和代表性真实设置回归通过；正式提速证据未通过。P1b/P2b及后续阶段未完成，所有实施改动保持未提交。步骤与取舍唯一维护于[启动专项](../../development/wallpaper-startup-optimization-plan.md)。

## 本批边界与前驱

继续使用初始文档提交 `ae0ac798c` 派生的独立工作树；保留首批未提交改动，本批同样不暂存、提交、推送或安装 App。主工作区保持干净。直接前驱是首批已验证的 P0b 签名优化 Debug：executable SHA-256 `d2f8da18e69dfb220bd8cc5f14aaa080100a178b912fc63414211aef1b4c5057`，专用 bundle `com.songziqiang.MyWallpaperX.Debug.Startup` / Team `H9QWU9XN8R`，`2.11.0 (283)`。比较 App 另存任务根 `p0b-baseline-app/MyWallpaperX.app`；更早 P3a App 已退出保留集合，其身份及原始结果仍在首批证据包，原 P0 App 继续留作专项终验。

本批三条职责分别为：P1a execution/analysis/保存共用同次作者依赖事实；P2a 一个 Reader codec 支持 FD 与既有 extractor 兼容 snapshot；DEBUG 观测细分 Web prepared 前等待。它们都延续原产品切换和输出 owner。

## Web 准备观测

首批600.186ms暖原点尚无更细归因，新字段不能回填解释旧运行。新增被动时间沿原 DEBUG observation 传递：父端 launch enqueue、子端接受、surface 完整创建/load/首次 ready 来源、当前 cohort 的 snapshot 与剩余媒体策略等待。didPrepare 成功后冻结 generation/surfaces 的值副本，只有与当前 activation 匹配时报告；不参与 ready、可见或提交判断。

独审发现并修正同屏重导航继承旧文档时间的问题：绑定 surfaceID/navigationGeneration，后继 load/recovery/自发导航丢弃旧观测，缺项明确 partial；新 generation 的 hostReady 只消费本次事件，不沿用旧点。真实导航生产者的可控 WebView peer 门、传输/错身份/诊断无提交权门和原导航策略门通过。它们不证明真实 WebKit 回调、多屏或物理呈现。

## P1a 实施与必要纠偏

同次依赖签名供 execution、analysis、launch memo 与 awaited save 消费；内容摘要覆盖作者项目/属性源和依赖，顶层名字覆盖 sampleStructure 实际事实，跨根同名文件保持规范来源身份。旧 generatedAt/mtime memo 不再自授异步 launch 的内容认证。原 UI 同步入口保 memo/冷解析，其未经认证结果不回填新的持久证书，不将完整签名扫描搬上主线程。

独审驱动的修正包括：缓存 staging 编码/写盘放锁外，generation 核对与最终 rename/删除同锁；在途 ticket 持有 Slot，历史无 borrower 项回收。删除先使原 owner 的保存资格失效。最后 await 后重建当前 values/grants；缓存不保存授权，也不控制产品输出事务。

P1a 保留冷 summary 的独立文件读取，因此扫描 A 后解析 B 的错配必须被拒绝或不回填。临时文件/目录 identity/ctime 收据只检测可观测变化，不证明解析实际消费字节的摘要，也不证明未知文件系统的原子目录快照。P1b 仍须让解析与签名使用同份 captured bytes/namespace，收敛 single-flight/末个等待者取消并退役临时独立重开。本批不能称全链文件只读一次或 P1 整体完成。

声明入口变化须按原 resolver 的 regular-file、literal query/fragment、fallback 和 dependency-host 语义核对；不能把 `.html` 目录误当新有效入口而拒掉旧合法 fallback。旧版本租约保护具体来源路径，不能按同 itemID 的最新记录给旧 host 取新项目属性；原 property-source owner 改为返回 ID/具体目录/可选 project URL 的轻量来源，pin 分支只核目录与 project，不重建整库记录或从版本目录名推断作品 ID。目录有效但缺 project 的 inferred HTML host 仍保身份；无 pin 的旧兼容分支继续复用原完整发现与分类，其扫描成本未消除。

## P2a 与后续输入资格

ScenePkgReader 的 Data/FD 共用一个索引 codec。打开实例持有同一 FD，索引只读 header/table；entry 读取使用 pread、源状态检查、取消及 caller 提供的预期摘要。新接口预算是调用方策略，不是 PKGV 格式上限；原 URL/Data 与当前 extractor 明确走 compatibility，不收紧旧产品合法输入。

extractor 沿同 FD 取得完整 snapshot，保原全包/entry hash、缓存损坏和路径/大小写语义。目前仍整包读取、hash并多一次 table 复核；没有按需产品收益结论。verified 接口只有 CPU 门消费者，P2b 必须接唯一 ResourceView handle/receipt，若该迁移停止则删除未采用入口。

Reader 12项、既有 extractor 20项真实行为门通过：截断/overflow、预算边界与兼容、Data slice、同大小恢复mtime篡改、原路径替换、并发、取消及FD释放等。这些门不替代下述签名App与真实产品验证。

只读盘点后选用 `3750342273` 的隔离副本作较重成本资格：计入摘要17文件/59,237,327B，摘要 `1e8d5e06a6a784923f3b270e53ed848f67a1bb2a720cccd76245bdb8c6cae1f0`。包52,533,256B、table1,468B、27entries；其中MP3 45,315,800B、TEX 7,152,119B，还含字体、粒子和作者shader，不能只迁JSON/TEX即认领完整输入。

前驱一组 C0/C1/W0 真实设置全部通过，分别2165.425/1091.065/291.166ms；三个App正常退出、输入与生产偏好摘要不变。这仅资格与成本定位，不是五组正式统计。W0模型约87ms、资源约151ms；C0的编译/device准备也占等待，不能把全部耗时归整包解读。

该副本是 legacy，缺可信receipt时仍须完整准入；不能靠mtime或复制marker认领managed暖挂载收益。后续隔离managed输入必须经真实transaction prepare和service publishCanonical完整入库，再由receipt owner核原tree发布。P2b还须覆盖project先认证、同root shader pair/texture sidecar、ImageIO Data、媒体流式物化和CPU/GPU drain，详见现役专项。

## 有效签名候选 v2 与 Web 结算

首轮构建在独审发现整库记录重建问题后主动中断，exit75；未运行候选，不作产品构建失败或计时原点。修正后优化 Debug/WMO 构建331.076s成功，构建前后完整 Git 可见文件摘要均为`288f67597910bb7793c84ad203b395288deb4df96638a78b0db97a4a561b2dff`，无源码变化。v2 executable SHA-256 `180ee9d31245d4d99d620968aa675bc807ee879580bfd81ef8ed1c8d3d511ca6`，CDHash `048227695fc4c254a9bcba8894885b9a55189c14`，专用bundle/Team/版本与前驱一致；deep/strict验签通过。唯一编译诊断是未修改的InspectorBadgeView既存NSBox.borderType弃用警告。

实施代理最终执行runtime-cache、dependency-traversal、resource-grants、static-content-signals、launch-profile五模块6项门，31.496s通过，Swift6 strict-concurrency=complete harness编译通过；root复核10文件冻结hash一致。新增pin门用真实目录/项目parser验证固定A版本、稳定itemID、latest零查询、缺project与删目录；no-pin门只验证原builder委托顺序，不声称运行完整LibraryRecords扫描。最后adoption等待的A→B→A反例通过，payload与grants在最后await后统一重建；保存另核payload生成签名。root的端点/导航、wrapper、门路由和Release诊断隔离最近门也通过。

同一wrapper、固定轻Web输入900000001、同30FPS，五组AB/BA交替；各arm15个App，45个请求。C0/C1各5个独立App原点；W0是5个App内各6个相关重设，不能称30个独立App。

| selection→匹配commit | 前驱中位ms | v2中位ms | 前驱/候选最大相对中位噪声 |
|---|---:|---:|---:|
| C0 | 860.554 | 861.628 | 3.054% / 3.306% |
| C1 | 862.557 | 862.139 | 6.990% / 5.917% |
| W0 | 274.477 | 270.179 | 5.279% / 7.669% |

正式提速判定为**未通过**：无≥10%配对收益，C1/W0超原5%噪声门。W0 pooled中位降1.566%，但按App组配对降幅中位仅0.224%；不挑点、不补跑求通过。两arm各45请求均无geometry retry。v2资格9请求、五组45请求、作者样本9请求的preparation均匹配当前cohort且surface覆盖complete。

v2轻输入30个暖原点的观测区间中位：selection→launch enqueue2.658ms，完整surface创建106.017ms，load→首次ready90.344ms，snapshot41.136ms，剩余policy等待0.840ms；这是回调区间，不能机械相加当完整因果账。C0/C1 selection→hello含空daemon等待，不是service/cache独占时间。资格轮C0的1180.768ms仍完整保留，不混入另起五组统计。首批600.186ms暖点本批未重现，仍无旧点归因，原保护证据继续保留。

真实作者1103493745的一组前后C0/C1/W0中位为870.433→863.812、854.535→875.402、285.437→282.226ms，两arm18请求匹配commit并正常退出。这只是代表性启动/提交/退出回归；本批未重测实音、像素画面、书签移动或多屏，首批实音结果不能改标为v2重验。

## Scene 产品资格与成本复核

375与未参与修复的314各一组，共12个App、16个真实`setAsWallpaper`请求，均有drawable-presented与匹配parent finalize。W0确为同daemon/generation；全部正常退出、已观察所属子进程为空，输入和生产偏好双摘要不变。`daemonFinalizeAndDrainObserved=false`，不能把parent finalize写成已观察到daemon drain ACK，也不证明完整画面/音频。

| 输入/条件 | 前驱ms | v2 ms |
|---|---:|---:|
| 375 C0 / C1 / W0 | 2155.579 / 1088.095 / 306.056 | 1783.391 / 1116.133 / 286.176 |
| 314 C0 / C1 / W0 | 1439.459 / 971.016 / 123.802 | 1365.755 / 961.438 / 131.792 |

单组不作收益或无回退证明。314暖增7.990ms主要落在surfaces→presented（58.931→67.268），model/资源区间未增加，不能归PKG复核。375暖总时虽下降，model观测区间却83.671→91.227ms，因而补成本定位与唯一一轮五组真实入口对照；两个原单组继续保留为qualification，不混入后续统计。model/program/resource数值是父端相邻回调的观察间隔，不是独占CPU或PKG耗时；surfaces→presented混合父端surface阶段观察与子端真实drawable-presented时间，不是两个父端观察点。

真实extractor CPU定位使用冻结前驱/候选的实际Reader/Extractor、同一375副本、独立HOME/cache，五对AB/BA交替、每对每arm三次warm，rusage timeval换算ms，产物摘要在计时外。最初一次在HOME物理路径guard前失败，0次extractor；修正`/tmp`别名比较后才执行唯一有效轮。32次调用均成功，payload逐entry/index事实相同，源码和输入未变；全部15次/arm的CPU均值43.527→43.746ms（+0.220ms），墙钟43.644→43.956ms（+0.312ms）。未复现约7.56ms的extractor增量，未做消融，不能归因到pread/Set/复核/append中的某项。

该CPU工具原报告仍为`passed=false`：它额外要求两arm completion marker原始JSON字节SHA相同，结果各自稳定但跨arm不同；原文未保留、临时cache已清理，不能推断语义相同或将报告改成PASS。该结果只作成本定位，不取代既有20项缓存行为门；缺失的原始marker语义证明也不能靠payload摘要补造。

五组375真实入口共30个App、40个请求全部通过；前驱/候选各5个C0、5个C1、5个W0，W0只取同daemon第二次设置。保持原30FPS、固定输入、AB/BA、产品cache和噪声规则。

| selection→实际presented | 前驱中位ms | v2中位ms | 前驱/候选噪声 | 配对降幅中位 |
|---|---:|---:|---:|---:|
| C0 | 1882.221 | 1788.309 | 8.115% / 3.795% | 8.085% |
| C1 | 1106.510 | 1157.018 | 4.737% / 2.228% | −3.399% |
| W0 | 304.910 | 282.518 | 6.725% / 7.101% | 2.286% |

仍为**正式提速未通过**，不以总中位改善替代配对与噪声门。C1五对均变慢，总中位增加50.508ms（4.565%），配对增幅中位3.399%，未越沿用的相对非目标门`max(5%, 2×基线噪声)`；没有测全部CPU/GPU尾部、峰值内存或能耗，不能称性能卡整体通过。暖model观测中位80.704→81.606ms（+0.902ms），五对增量6.294/7.985/0.219/0.221/0.902ms，没有稳定重复首轮7.556ms，但不能说没有新增成本。新表不覆盖未参与修复314的完整统计、全部包或完整画面/音频。

## 未完成验证与产物

本机限期结果包为`.artifacts/scene-evidence/runs/wallpaper-startup-p1-p2a-20261024/`，保存原始报告/日志、构建及验签/冻结源码身份、派生统计与最近门收据，默认14天；`batch/report.json`的samples.label映射原路径，文件实际位于对应数字id目录，不依赖已清理tmp引用。CPU raw-marker资格差异单列最小保护包`wallpaper-startup-p2a-cpu-marker-unresolved-20261024/`，不自动到期，不能视为已证产品marker回退。首批600ms保护包继续保留。

运行wrapper已清各组HOME/staged App，CPU工具清独立cache；提取校验后清本批已停止结果/编译CLI/失败harness目录。任务根仅继续保留一份`DerivedData`、原P0与直接前驱P0b比较App、固定隔离输入和必要清理收据，服务后续同条件改造；私有生产偏好备份仍0600且不进入证据包。最终清理收据为`/private/tmp/mwx-startup-optimization-fbRhFY/p1-p2a-cleanup-receipt.json`。

所有实施改动只在独立worktree，未暂存、提交、推送或安装；主工作区保持干净，goal仍active。未认领专项完成、正式提速、完整画面/实音兼容、多屏、Release或长稳。P1b、P2b及P3其余/P4/P5/P6/P7仍未实施。
