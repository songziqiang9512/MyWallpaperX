# D10：旧 v3 按需持久 receipt 升级

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**
>
> 截止：2026-10-24。现役顺序归[启动专项](../../development/wallpaper-startup-optimization-plan.md)，长期语义归[启动合同](../architecture/scene-launch-responsiveness-contract.md)，实际接线归[源码职责图](../architecture/runtime-as-built-map.md)。本文只结算 D10，不改 D9 历史；后续实施均未提交。

## 改动与职责

D9 已让旧 managed 在完整认证原作者树后临时挂包，但逐请求认证和整包 stream 仍在。同 generation 加 sidecar 会污染已捕获 nil-ref 请求的作者树；外置 receipt 又扩大定位、协议与回收职责。D10 沿原 Transaction copy/hash 到新 generation、生成完整 receipt，再由原 publisher 出版；不移动 active、不停旧壁纸、不作整库后台复制。busy 旧版本仍可走 D9，不保证所有旧库立即获得持久信任。

播放的原共享准备 Task 与属性 Request 先 await 同一 service 预准入。同 library/root/item、physical identity 和完整 commit 的在途升级共享一个 producer，各 waiter 独立撤权。临时原 lease 仅由 MainActor 持有，覆盖实际 worker join；join 后清自身引用，无 await 地重核完整 commit/marker、删除更新与其他借用，仅原 publishDownloadedVersion 取得一次 reservation 并 CAS。迟到借用或 CAS 改变保旧版本，候选清理由原事务裁决，durable journal 的恢复输入不能删除。详情补全保最新 item 字段。

同一 copy 核只排除旧 ownership marker，完整作者 facts/digest、同 FD Reader receipt、Root/marker 尾 fence 及原容量/预算保留。require-ref 路径只接受完整 receipt 候选；静态格式/namespace/编码/路径拒绝须在完整旧树认证后返回，只绑定完整 commit/policy 跳过重复升级，不授权 bytes。空间、busy、候选冲突与 I/O 暂态不记永久拒绝；原新下载的可选 nil-ref 兼容不变。

目标只读、incoming 不可创建或拒绝记录写入失败曾不必要地阻断仍可信可读的旧源。最终仅对原 message-only 事务/文件失败验证兼容读：须原 journal 明确无 pending、同 capture/physical identity/完整 pointer 仍当前且持原 lease；完整认证实际 join 后再核。硬摘要/来源错误、未知 journal、取消继续失败关闭；回滚和恢复仍只归原 publisher。普通选择、删除和末 waiter 取消保真实 join。同 ticket 重备另核原 preparation ID，旧 Task 的成功、失败、取消均不能撤新准备。

App 退出曾加入 Task join-barrier；真实 AppKit terminateLater 探针的 joined/pending 分支失败，deadline 分支才在拒绝退出后等到 worker，证明该调度会误拒正常退出，候选已撤回。最终只同步撤权/取消，保原播放进程 registry 的退出权威；不称 App 内 copy 已 join。真实 App 进程死亡才是其内 worker/FD 终态。未 ready 且无 journal 的 incoming/候选只沿原 24 小时 GC 和空间记账；只有 durable journal 的输入由原 publisher 恢复，不承诺立即删除或自动续传。原失败保存在 `d10-root-quit-cpu-v1/report.json`。

## CPU 正反例与固定构建

最终 CPU 94 方法按实际分组为 61+20+3+1+1+8：库侧原 Transaction 30、receipt 14、Publication 13、新升级 4 共 61；service 最终 20；source admission 3；lifetime 1；属性 preparation 1；原相邻前端/下载链最终 8。service 最终 20 已包含原 13，不重复相加；相邻 8 是首批成功 5 与受影响 3 项重跑组合，不能写成同一批全重跑。实际编译输入 SHA 与复用边界由各收据保留，不以事实数量冒充方法数量。

库/长期 service 门明确使用 synthetic legacy protocol fixture：真实 prepare/copy/hash 后在私有测试目录去 ref/sidecar，再由原 publisher 正式出版；不冒称实际 D7 旧 producer。覆盖完整树、改名/等价目录、硬 digest/marker/Root 错误、静态政策、暂态重试、共享 waiter、copy 中取消、迟到 lease、完整 commit CAS、删除和原 durable intent/恢复。目标 I/O 修正前同最终夹具 5 方法全失败，修后完整 service 20 方法通过；真实 chmod/创建拒绝与 incoming ENOTDIR 已执行，未注入 ENOSPC/EIO。更早 fatal 夹具原记录保留。

same-ticket 最小实际前端反例原 1 方法有 3 项失败，修后 source-admission 3 与 lifetime 1 方法通过；原属性准备 45 checks 保留。原相邻 8 方法首轮有 2 failure/1 error，受影响 3 项重跑通过，原记录不删。属性模型叶为受控 carrier，不据此认完整渲染。入口为 `d10-library-cpu-v1/report.json`、`d10-destination-io-final-source.json`、`d10-service-tests-final.json`、`d10-same-ticket-regression/{before,current-runs}.json`、`d10-service-property-v2.json` 及 `d10-root-cpu-v{2,3}/report.json`。

最终同 flags Debug.Startup 构建 `d10-build-v2` 用时 336.779 秒通过，产品 2.11.0(283)，Developer ID 深度严格签名通过。构建输入前后同为 `932e24916ec2f03b4eae187546bee7ea1ce78e24a4e93773b82c624920f8a85e`；最终 exe `3b96b37992ddc8b3c3a4524fccf2efddb4dcb4b3a41b22d78e1d14bf150614c5`，实际 D9 before 为 `c4f3bfc238c58c9bce5c9a4ecb9aa078c68b715e66b790d30f7ac3c52e796182`。早期 build-v1 的成功记录保留，不冒充后继修正后的最终构建。运行后原 5504 项产品/script/build 输入仍逐 SHA 等于 build-v2，见 `d10-post-runtime-product-source-qualification.json`；后继仅文档/治理变更不重定义该构建身份。

## 实际旧库、M0 与五组比较

代表作者输入 `3750342273` 有 18 文件/59,243,475 字节；两个独立 arm 由保留的实际 D7 Transaction/Metadata/Publication helper 正式出版，真实 nil-ref metadata/marker，没有手写 ready 标记或删除新 sidecar 造旧。旧 prepare copy/hash 与现共核出版后 tree 认证分别记录。原 tree 均为 `54128d5ebeb06c9f9a58158105d61a58e5402d7f6adda8a91904ff6e714e49bb`，baseline generation `ddf303ed-c0d6-4146-ac78-ac5394b3660e`，candidate 原 generation `54b3b52d-51b6-4d5c-b5f3-06f971a01933`。原输入只读；旧库建立在计时外，不是 D10 升级。

M0 只执行一次候选真实产品 C0/C1/W0 组，共 3 App/4 请求。第一 C0 从 setAsWallpaper entry 开始，升级 copy/写入/等待包含在内：实际 presented 2126.081ms、父端 finalize 2130.166ms；accepted 的父端观察为 756.369ms，它包含多个前置工作，不能独占归因为 copy。后继 C1 970.130ms、W0 281.120ms 仅作单点诊断，不合并入正式五组。

M0 后才运行只读原 manifest/tree 认证：新 generation 为 `d233fbe4-9ec2-4af7-9136-7e141ae80fce`，完整 receipt 7615B，SHA `fd0854357af4bf8bc554a4ad582c9bd353ab59f59b119dafe00ffafc35681560`。完整新 commit/metadata/marker/ref、全部 18 原 facts 与新旧实际作者 bytes 均核等。原 publisher 将旧 canonical 改写为 retired v2 marker，完整 marker/作者树也核等；不能错误要求旧 canonical marker 字节不变。

随后仅一次预定五组 AB/BA、30 App/40 请求，全程固定 30 FPS。原 core 计时、每条 admittedSource 精确核等、输入/出版 guard、正式偏好、签名及正常退出均通过，无子进程残留。baseline 全程仍 nil-ref，candidate 全程匹配上述实际新 ref，不在组间重迁移。M0 与正式合计 33 App/44 请求；所有原点保留，没有追加直到绿或删慢点。

| 条件 | D9 中位 ms（范围） | D10 中位 ms（范围） | 观察差异 | 基线最大偏差/中位 |
|---|---|---|---|---|
| C0 新 HOME/新 App | 1672.729（1638.336–1892.000） | 1564.990（1524.901–1636.984） | -107.739ms / -6.441% | 13.109% |
| C1 同 HOME/新 App | 1105.147（1062.117–1202.526） | 1016.893（991.734–1042.650） | -88.254ms / -7.986% | 8.811% |
| W0 同 daemon 重设 | 313.621（286.195–317.151） | 250.504（219.815–265.712） | -63.117ms / -20.125% | 8.745% |

**三个条件均超过原 5% 噪声门，formalPerformanceAccepted=false；只认本批执行资格与观察差异，不认正式提速、无回退或完整性能卡通过。** C0 新 HOME 不等于 OS 冷缓存；无 IO syscall/CPU/RSS/AV drain 测量，也没有五对“首次迁移”统计。原点与算法归 `d10-old-managed-heavy-five/report.json`、`d10-old-managed-heavy-five-analysis.json`，M0 与出版认证另见 `d10-first-upgrade/report.json`、`authentication.json`。

两个 arm 的五份 HOME 展开缓存均为 0；D9 本来已临时挂包，不能再将无展开归为 D10 新收益。磁盘观察中 baseline canonical 19 文件/59,243,867B；candidate 新 canonical 20 文件/59,251,864B，另保 retired 19 文件/59,243,852B。它记录 receipt 和新 generation 的空间代价，不是实测写入量、物理分配或 RSS。见 `d10-artifact-assessment.json`。

## 实际画面与退出边界

独立原 daemon endpoint 补充一次 baseline/candidate 两帧 capture，root 逐一查看四张原 JPEG：双方均有山体背景、中央日期/时钟和粒子场，后张粒子位置变化，无明显缺背景、缺文字、黑帧或大布局差异。两端原 typed exited 均 gpuDrained=true/code0，进程退出 0，保护输入和签名保持。结果见 `d10-old-managed-daemon-gpu-qualification/report.json`（SHA `428d6a0c2ff591472d9e50ca72cac800e81ec7f23be80ecacbd58c33e2c68095`）及 `d10-gpu-visual-assessment.json`。

该补图只证明一个代表 Scene 的独立执行端进度与限定画面，不是同一 App 父端 lease 请求，也不证明精确相邻帧、逐像素等价、官方一致、App worker join 或 AV decoder drain。产品真实来源资格另由上述 44 请求承担，不能互相替代。

## 剩余与产物状态

active/busy 旧版本继续 D9；静态不合格及可证明旧源可读的写入暂态保原完整认证，不保证立即升级全部旧库。P2 全局验收、跨 provider 私有文件共享、既有 seek/峰值、长期多屏/Release 仍开放。D4 残余资源代价、Web C1 与字体呈现不确定性保各自原结算，本批不关闭它们。

必要源码、原点、日志、限定失败与四张原JPEG提取为 `.artifacts/scene-evidence/runs/wallpaper-startup-scene-d10-20261024-checkpoint/`；包内报告保原始来源、版本、SHA与去重载荷映射。逐字节核验提取后，重查精确目录无在途writer/打开句柄，已删除本批29个临时App、HOME、库、源码和测试目录，共3,047,630,751逻辑常规文件字节；不等同实测物理释放。清理只涉及D10自有目录，未触真实媒体/偏好、正式版或跨批唯一未解seek证据。单份连续构建缓存仍保留 `/private/tmp/mwx-startup-optimization-fbRhFY/DerivedData`，供后续专项使用。最终结构门与清理收据保包内；并行工作树保留，未暂存、未提交、未推送，持续goal尚未结项。
