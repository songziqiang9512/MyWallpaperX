# D9：旧 managed 来源完整准入后的临时挂包

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

> 截止：2026-10-24。本文保存本批改动与限定验证。现役顺序归[启动专项](../../development/wallpaper-startup-optimization-plan.md)，长期边界归[启动合同](../architecture/scene-launch-responsiveness-contract.md)与[源码职责图](../architecture/runtime-as-built-map.md)。后续实施均未提交。

## 改动与取舍

D8 的旧 managed 无 ref 路由已完整核原 commit 的作者树，但之后仍将所选包转成整份 Data，再由 extractor 做包/entry hash、展开写入及暖缓存逐文件比较。D9 在原 SourceFacts 和 ResourceView 内消除合格来源的这段重复，没有改 service、迁移任务、IPC、父来源 lease、播放/属性 Request 或其实际 join 边界。

旧来源仍逐请求完整核原 tree。只有该次已认证的 loose Root 可以从自有 selected handle，在原 path/FD fence 内取得 approved FileFact、duplicate 一个 Reader，并流式导出整包/table/entry 事实；整包 SHA 必须等于原 FileFact，再用同一个 Reader 构造原 package backing。没有临时自签持久 ref，没有放宽原静态 receipt factory，也不授跨请求暖信任。此路径仍是完整 tree 后第二次整包 stream，不能称单次读取或旧库持久升级。

暂态资格沿原 Reader 表/entry 数量、8GiB 累计 entry hash 工作与 selected PackageFact 的 4MiB 编码限制；这不是完整 manifest 可发布或 RSS 上界。PackageFact 有界 JSON 计费核放回原值层，publisher 共用它，仍保完整 manifest 最终编码/磁盘预算。仅明确的格式、namespace 或预算不合格回原 authenticated snapshot/extractor。摘要/来源变化、非法 handle 与原取消继续拒绝；回调即便抛 Reader 的政策错误，也不会被错分为可降级资格。有 ref 路由保持原强校验。未选中的坏 pkg 不阻断健康的所选包。

持久升级仍需要原 publisher 的可恢复 CAS 或新 generation，不能 metadata-only 附 ref。全 v3 后台 copy 会增加启动争用，活跃 lease 又拒绝目录替换，nil ref 还包含政策不合格来源；因此本批先采用能服务仍在播放旧版本的临时挂包。永久迁移继续列 P2 余项。

## 固定身份与最近门

实际 before 为保留的 D8 App，exe `677026821eec6ed98acd9c23bf311fa9b8f996e6affd14edf3059ef43fa42658`；对应文本快照清单 `3ab25656fbb37e168d3033f856d1b854c472020faf01ab906fdab36ce78cfc9e`，与原构建产品的唯一差异仍是已记录的非执行 inventory 注释。候选 exe `c4f3bfc238c58c9bce5c9a4ecb9aa078c68b715e66b790d30f7ac3c52e796182`。双方同配置 Debug.Startup、2.11.0(283)、Developer ID 签名；候选 Debug 构建 461.797 秒通过，5926 个输入前后不变，清单摘要 `08a79a301d859de947a48dbc44831d7c37850b5427d97dcf48dc9f32f2426c9e`，深度严格签名通过。

| 范围 | 本批结果 | 原始记录 |
|---|---|---|
| 原库 receipt 与事务 | 14+30 方法通过，19 个实际输入前后 SHA 一致 | `d9-library-cpu-v1.json`、`d9-library-budget-final.json` |
| Root 暂态挂包 | 当前 15 方法/110 事实通过；实际 before 原 10 方法/78 事实另跑通过 | `d9-root-final-source.json` |
| 原 publisher→认证→SourceFacts→ModelBuilder | 当前 3 方法通过，实际 before/current/producer 均重新编译运行 | `d9-package-source-final-qualification.json` |
| 代码行数、依赖、Scene 防线、设计 | 通过；不等于全能力/全语言行数或性能验收 | `d9-check_*-v1.log` |

当前共 62 方法，不把 before 或事实数量相加冒充测试数量。纵切保原 ref 17 事实、旧 alias 兼容/不可变快照/flock 7 事实、暂态 route/硬错/取消 16 事实及改名 4 route 事实。完整 Facts 与 Model 投影在原入口、改名入口、等价目录和实际 D8 before 间一致，包含真实 enabled/amount 属性解释。合法 no-ref 在 before 明确走 extractor/cache，候选明确使用 package identity 且无展开缓存；等值 slash/backslash alias 仍走旧兼容。原 ref、同大小篡改、捕获后换源、预算和 callback 反例保留，出版文件不改。

纵切首次编译因新探针误用不存在的 View API 失败，0 方法执行；只修探针到真实 literalEntry 及项目实际 entryPath，原失败保留。旧 publisher helper 首次因 task 暂存名不满足原 staging 规则被拒绝，尚未 prepare/publish；只修 task 命名，原产品源码未改。两者不算产品失败，也不隐藏原记录。

## 真实旧库对照

代表内容 `3750342273` 的只读作者输入有 18 文件、59,243,475 字节。使用保留的实际 D7 原事务/出版源码与原 metadata DTO，分别发布两份 canonical schema3 库；原 copy/hash、metadata 解码、marker 完整 commit 与出版后的现有原 Tree 核验证均通过。无 ref 是 D7 publisher 原本没有该能力，并非删除 sidecar 或伪造旧 marker。作者 tree 均为 `54128d5ebeb06c9f9a58158105d61a58e5402d7f6adda8a91904ff6e714e49bb`，generation 分别为 `a8306048-bf9e-419a-bed1-3b37b63baf0d`、`cb5e17b8-770c-4e94-b554-cca3d367c325`。这不是 Steam 网络下载或账户授权验证。

沿原 benchmark 做预定五组 AB/BA，不另加 pilot 或补跑至绿。30 次 App、40 次设置均完成原产品首呈现/父端 finalize，双方每条 admittedSource 都与各自完整 source.json 严格匹配，ref 仍为空；输入/出版两 guard、源码 App、签名、正式偏好不变，正常退出且子进程清零。C0 是新 HOME，不代表 OS 页缓存冷；没有 CPU/RSS/IO syscall 或 native workspace 采样。

| 条件 | D8 首帧中位 ms（范围） | D9 首帧中位 ms（范围） | 基线噪声 |
|---|---|---|---|
| C0 新 HOME/新 App | 2200.321（2087.972–2624.731） | 2001.297（1946.023–2283.154） | 19.29% |
| C1 同 HOME/新 App | 1339.254（1262.791–1996.088） | 1292.957（1263.096–1537.629） | 49.04% |
| W0 同 daemon 重设 | 497.762（441.083–534.262） | 403.301（350.402–437.047） | 11.39% |

**三条件均超过原 5% 噪声门，不认正式提速或无性能回退。** 不删慢点、不放宽门；中位数差不能全归于解包。五份 before HOME 各留下 28 文件/52,536,198 字节展开缓存，候选五份为零；这是存留产物观察，不是实测写入量。原点、资格与计费方法归 `d9-old-managed-heavy-comparison-five/report.json`、`d9-old-managed-heavy-five-analysis.json`。

## 正常 UI 与实际画面

正常隔离 UI 的已下载→详情→设置，以及同卡菜单再设，分别产生两个不同 request 的 accepted→launched，使用同一 daemon；App 真实 Cmd-Q、exit0/子进程清零，签名和正式偏好保持。该作品只有未支持的 scheme color，属性窗口实际显示无可调受支持属性的提示，仅证明入口可达；不能称取得可编辑模型或 live 属性像素验证。CPU 纵切的 enabled/amount 投影另有资格，二者不混用。

严格 UI wrapper 报 `publishedInputUnchanged=false`，原失败原样保留。只读补充检查定位 24 处 JSON 变化恰为 fetchedAt 与 item 展示详情：与原详情补全→persistDownloadMetadata 保 commit 的路径吻合。完整 commit、marker/source 字节及 18 个作者文件逐 SHA 未变，无新增作者文件，ref 仍为空。该结论不把 strict wrapper 改成通过，也不修改原导入收据或重跑掩盖。事实归 `d9-ui-supplemental-assessment.json`。

最后分别用实际 D8/D9 原 daemon 协议共读未变的同一 baseline nil-ref 来源，双方都发送完整 source/schema1：prepared→commit→实际 presented→finalize→两次 capture→shutdown。before rendered 3→33，候选 23→53；双方原始 exited 都是 code0/gpuDrained=true，进程退出0，完整来源字节保持。四张原图均见山体、雾雪和中央日期/时钟，动画/镜头相位不同，不认像素或精确相邻帧等价。这是独立执行端，不能替代同一父端产品 lease、AV drain 或资源峰值证据。见 `d9-gpu-assessment.json`。

## 保留边界

P2 仍开放：旧库持久升级/完整 tree 准入成本、政策不合格来源兼容、跨 provider 私有文件共享、D7 未分类 seek、峰值与完整回归；D4 残余、Web C1 归因及 P3–P7 整体验收也未关闭。本批不认全 Scene、Release、多屏、最低设备或官方像素一致。

最终源快照、原日志、四张图与失败材料按产物规则提取到 `.artifacts/scene-evidence/runs/wallpaper-startup-scene-d9-20261024-checkpoint/`。清理本批已停用 App/HOME/modules/库副本及重试环境，只保一份任务 DerivedData、连续对照需要的实际前驱和唯一未解 seek 材料。最终数量/校验以该包及清理收据为准。Git 全部未暂存、未提交、未推送；goal 继续。
