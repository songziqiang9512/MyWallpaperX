<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

# Web 同次准备

> 截止：2026-10-24。当前Web职责见[项目模型](../../web/web-project-json-runtime-model.md)和[现役状态](../../web/current-state.md)。

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

## 未完成验证与产物

本机限期结果包为`.artifacts/scene-evidence/runs/wallpaper-startup-p1-p2a-20261024/`，保存原始报告/日志、构建及验签/冻结源码身份、派生统计与最近门收据，默认14天；`batch/report.json`的samples.label映射原路径，文件实际位于对应数字id目录，不依赖已清理tmp引用。CPU raw-marker资格差异单列最小保护包`wallpaper-startup-p2a-cpu-marker-unresolved-20261024/`，不自动到期，不能视为已证产品marker回退。首批600ms保护包继续保留。

运行wrapper已清各组HOME/staged App，CPU工具清独立cache；提取校验后清本批已停止结果/编译CLI/失败harness目录。任务根仅继续保留一份`DerivedData`、原P0与直接前驱P0b比较App、固定隔离输入和必要清理收据，服务后续同条件改造；私有生产偏好备份仍0600且不进入证据包。最终清理收据为`/private/tmp/mwx-startup-optimization-fbRhFY/p1-p2a-cleanup-receipt.json`。

所有实施改动只在独立worktree，未暂存、提交、推送或安装；主工作区保持干净，goal仍active。未认领专项完成、正式提速、完整画面/实音兼容、多屏、Release或长稳。P1b、P2b及P3其余/P4/P5/P6/P7仍未实施。
