<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**；证据提取与清理结算见末节

# Scene 启动 D4：目录纹理 Input、同 FD 身份与跨相位短值

> 截止 2026-10-24。实施顺序归[启动专项](../../development/wallpaper-startup-optimization-plan.md)，稳定边界归[启动合同](../architecture/scene-launch-responsiveness-contract.md)。本批实施目录 TEX/直接图片的来源、身份和准备链；首轮模型 W0 超预算原点保留，最终各中位在原非目标预算内，但高噪声且整体性能卡未通过，不认领无回退、正式提速、按需包 IO 或 P2b 完成。本文保留 D3 的历史时点，不将 D4 状态倒写为 D3 已完成。

## 实际改动与退出边界

本批沿原 owner 修改 24 个产品文件、32 个测试/fixture 和两个既有门映射；专项设计另行同步，不计入这三类。清单由 `d4-owned-paths.json` 记录，实际改前源码由 `d4-source-before.json` 及 `d4-before-source/` 绑定，未用 HEAD 冒充仍含前期未提交工作的 D3-final 前驱。

| 原职责 | D4 接入与保留边界 |
|---|---|
| ResourceView / Loader / Candidate | `FileInput` 显式区分所选 Root handle 与独立外部文件；目录 `readSnapshot` 交付自持 Data 和同一打开 FD 的 FileIdentity。Loader 继续拥有 TEX/ImageIO 解释、尺寸/opacity、解码、中间缓存、GPU candidate 与失败重试，PreparedTexSource 和嵌入视频声明携所选 Input 与身份。退出作者纹理由 URL 重新猜 Root、独立重开后沿用旧 key 的路径。 |
| BaseImage / Material / StaticModel / Video declaration | 沿现有 prepare、预算与事务使用 Input；同次 Data/CGImage 可供 metadata、多 purpose 及上传准备。URL-only 媒体仍由其实际消费者处理，不为包伪造 file URL，也未借本批激活 package backing。 |
| Particle / Stock / Sprite | 粒子纹理来源改携 Input，D3 定义图的同 launch 身份保留；primary-all invariant → global localized → 原 literal/custom stock → builtin 的次序不变。普通纹理仍 candidate/template-first、每项遍历 roots。stock Root 用既有空 index，不新增目录枚举。sprite `-json` 仅原粒子动画消费者读取选中纹理的同 Root raw sibling，不扩张普通动画。 |
| Host / Session / MetalView / UserProperty | 硬错沿原 throwing prepare 或现有 texture/emitter/provider 事务拒绝最小不安全单元，保留旧完整输出；不能把 sourceChanged、invalidHandle、越界或原取消当作 missing 后改选低根、builtin 或 inline URL。外部用户文件保原 security scope、冻结资源和 revision/cancellation 事务，不纳入作者 Root。 |

FileIdentity 是目录文件的当前 revision 身份，不是内容摘要或可信安装 receipt。当前 metadata 查询与同 FD payload 读取各保其职责；Input 的 Hashable/Equatable 表示选中来源引用，不认证内容、不作跨 launch 持久身份。Root/index 不存请求取消、错误或资源租约状态，原 Loader 仍是唯一解码/cache owner。

DirectImage 保留 metadata 先行与后台 GPU 准备重叠：header 解释同次 Data，不提前解码整图。跨 metadata → GPU 留存完整 encoded bytes，须取得原 decode budget 的 source lease；GPU 领取时先从排队集合移除短值，当前操作结束释放，不将预算拒绝的 CGImage 留到整批末尾。预算拒绝时只保小 metadata，GPU 按 expected identity 重捕获，deferred 队列只保 Input 与身份。因此不能声称所有条件、所有页面或整个纹理链只读一次。

## 真实前驱资格与审查纠偏

同一真实 shader/Root harness 替换为实际 D3-final Root 后，共 58 项恰有两项失败：`defaultIndexedSiblingReadsRawNameInSameRoot` 与 `indexedRawSymlinkReplacementCannotEscapeRoot`。D4 对应 58 项全部为 true，其他 56 项保原结果；这证明所列 sibling/选中路径安全反例及邻近行为，不推广为全部文件系统证明。

首次“raw leaf 四项应失败”的假设经实际 before 执行被否定：默认 resolvedResource、author handle 与 Root 默认 handle 原本就能读真实 POSIX 反斜杠叶，早期 raw 组只 sibling 失败。原始首次负资格与纠偏保留，不把这些本来成功的读取宣传成 D4 新修复。最终增加的第二个目标失败是选中 indexed raw 路径被 symlink 替换后的入根安全反例，不能与先前四项假设混为一谈。

选中的原始路径、同 Root sibling、literal symlink/`..` 的真实 kernel 目标、外部 URL 和取消沿最近门验证；不先折叠 raw 路径再重选，不因 lookup 大小写规则迁移改变 primary invariant/global localized 语义。初轮 selector 对照用同一真实旧核，7 个原有结果相等，新增 stock Root 转向产生 typed 失败。D3 定义图与模型解析未另起 owner。

模型/粒子 GPU 前驱结果来自已归档 actual D3-final，而非本轮伪造 before 重跑；225 条 source bindings 与 D4-before 相符。首轮 D4 模型 9 项、粒子 47 项及最近 48 项（含两个 CPU 事务）均通过、无 skip。明确字段仅归一 113 处受控模型输入路径与 5 处进程生命周期 UUID；数值、像素、预算、回滚和单次运行内身份关系未改写，归一后无差异。原 raw 差异、规则及关系检查均保留，不宣称 raw JSON 全同、任意画面等价或长稳完成。API 编译适配保原断言；compile-only 只计编译，不充作 GPU 执行通过。

以上首轮结果不替代 Root `881b…` 之后的最终 GPU 核验；最终结果与 source `79cd…` 在下方单列，不能把先前 `2cdf…` 源摘要、旧 GPU 或诊断原点冒充最终候选。

## 构建身份与失败资格

v1 构建退出 65，37.660s，源码前后未变；MetalView 两个 `FileInput` → `URL` 调用点漏接类型，编译日志保留。修接实际 API 后才进入 v2，不删除原日志或将编译失败计入有效运行。

| 构建 | 结果与身份 |
|---|---|
| v2，首轮正式运行候选 | Debug/WMO 签名构建 340.529s，通过 deep/strict 验签；构建前后源码摘要均 `2cdf3fb855f0242784a66a5fc78e9d7edeebda32f7abc2a56fdecccf1e38a113`；executable `483f9b3786bd98c5dcb6f815bb8a9ef78d9680e923fd4475e995a4c541e07583`。 |
| v3，路径成本收敛后的最终构建 | Debug/WMO 签名构建 337.398s，通过 deep/strict 验签；构建前后源码摘要均 `79cd331f1d72da2889654b5216d8620eb42980d46ef79cec88201857b5a0fe02`；executable `49394ef80fb6e7d58dadf98fb55e2115280e1a74bb0ba6e1fa08fea4e07baafe`。 |
| 直接 D3-final 前驱 | executable `4f3998bb180ebbe05f5b9228bda75f0f8af5a609ebf686275ecf19699b7a107f`；保留实际 signed App，不以源码 HEAD 另构近似前驱。 |

专用 bundle 为 `com.songziqiang.MyWallpaperX.Debug.Startup`，2.11.0(283)，Team H9QWU9XN8R；它们是隔离 Debug 测量构建，不是 Release/安装验收。`d4-build-v1.json/.log`、`d4-build-v2.json/.log`、`d4-build-v3.json/.log` 分别绑定各次结果，不混用源码与二进制身份。

## v2 正式五组：行为通过，模型 W0 超预算

固定三个输入、每 arm/条件五个原点，交替 AB/BA，共 90 个 App、120 个请求。沿原 setAsWallpaper 产品入口，30 FPS，C0 是新隔离 HOME/cache 的新 App，C1 是同内容/同 HOME/cache 的新 App，W0 是同 App 两请求中的第二次，保持同 daemon PID/generation；不清系统页缓存，不把 C0 称为操作系统绝对冷启动。匹配实际 presented 与 parent finalize、正常 App/拥有的子进程退出、输入/App/生产偏好身份检查均通过；这些不是 typed drain ACK。

| v2 首轮正式五组中位数，ms | C0 前驱 → 483 候选 | C1 前驱 → 483 候选 | W0 前驱 → 483 候选 |
|---|---:|---:|---:|
| 3750342273 重输入 | 1584.139 → 1578.317 | 1018.318 → 1044.501 | 250.027 → 263.869 |
| 3141421197 独立输入 | 1259.694 → 1232.463 | 882.235 → 876.049 | 115.555 → 115.535 |
| 自有五段 MDL PKG | 868.565 → 893.293 | 834.707 → 852.539 | 90.996 → 104.182 |

**v2 性能卡未通过。** 模型 W0 中位增加 14.4907%，超过既定非目标预算 10.0686%；前驱噪声 5.0343%，候选噪声 17.3494%。噪声按 `max(abs(point - median))/median` 计算，原点未删；其他中位数在本次非目标预算内，也没有达到正式目标收益门，不能用它们抵消模型回退。完整范围、配对值与所有原点由 `d4-runtime-analysis.json` 和各原始 `report.json` 保留。

既有同源事件把持续增量定位在 resource-progress → surface-progress：W0 7.742 → 19.794ms，增加 12.052ms，五对候选均较慢；C0 为 11.698 → 23.164ms，C1 为 9.957 → 22.466ms。原 daemon 累计 device-join/first-surface-join/prepare-end 也反映约 7–8 → 19–20ms。它们是重叠 worker/IPC/调度边界，不是独占 CPU/GPU 计时；嵌套值不能求和，也不能单凭此把全部增量归因给某个读取函数。

另两个 W0 原点总计 122.257/120.785ms，launched（父端观察）→实际 presented 间另有 21.346/19.883ms 等待；其余三个候选该间隔为 1.112–4.247ms。这两个额外呈现等待与五点均有的资源阶段增量分开记录，不能删慢点、混称一次 GPU 执行变慢或先归因为刷新调度。完整 request/log/source 关联见 `d4-regression-stage-analysis.json`。

## Root 同调用减工与单组诊断

静态核对确认，pre-cost Root `c9acf5c5021c7e5b987f5f8fe4a4668231817ece4516e953ef9a572ca978fac2` 的成功 currentIdentity 路径在一次调用内显式调用 `resolvingSymlinksInPath` 9 次。收敛后 Root 为 `881b4a9011affbe461885720ecd310cd2668b22c0041ece3d19c655b381a44f4`：每次 validatePath 仅解析实际 Root 一次，空子目录边界复用该结果；直接 lstat 已验证 canonical candidate，随后仍完整重验 Root/candidate，并要求前后 canonical candidate 一致。成功 metadata 路径变为 4 次显式解析 API、仍 1 次 lstat。这是 Foundation API 调用位置计数，不是内核 syscall、readlink、磁盘 IO 或页缓存 miss 数。

没有跨操作缓存文件系统事实；before/after 验证、raw open、`O_NONBLOCK`、payload 前实际 FD 入根、regular fstat、expected identity、取消、最终 fstat/fstatat 及路径检查仍保留。snapshot 未用先前 canonical URL 替代实际打开 FD 身份；metadata 不是原子目录快照或任意文件系统 ABA/内容证明。独审无新增阻断，最近四个真实 CPU 模块通过，均绑定 `881b…`。

同一 `-O` Root/Index/FileInput CPU harness、同一 PNG，保留三个原点：500 次 metadata 中位 40.579 → 26.433ms；50 次 snapshot 5.507 → 4.251ms。外部文件参照为 3.902 → 4.274ms，没有以 Root 策略替换它。这只支持调用内局部减工机制，不证明 App 收益或说明原 12ms 全由此造成。

随后 483 → 493 的单组 AB 诊断保留原输入/30 FPS/隔离退出，模型 W0 resource 18.650 → 14.977ms、entry→presented 100.831 → 94.644ms。该组是定位后的诊断，不与原五组混池、不算正式增益，也不据此宣布原回退闭合。原正式失败继续保留，按实施前裁决只进入一次新候选固定复核，不复测旧候选直到变绿。

## 最终候选验证与固定正式复核

最终模型 9 项、粒子 47 项、其余最近 48 项（包含两个 controlled CPU 事务）全部通过、0 skip。执行前后 source 聚合均为 `79cd331f1d72da2889654b5216d8620eb42980d46ef79cec88201857b5a0fe02`，Root 为 `881b4a90…`，App 为 `49394ef8…`，上表列完整摘要。225 条 archived-before source bindings 仍匹配 D3-final / D4实际before；仅归一已声明的 113 处模型路径与 5 处 UUID，数值、像素、预算、回滚结果无差异。最终批日志、原始 JSON 与归一规则保留，不能据此扩大到任意内容或长稳。

沿预先记录的三输入、五组、交替 AB/BA 固定协议，最终 90 App/120 请求全部资格通过，实际 presented 与 parent finalize 匹配，正常退出，拥有的子进程退出，输入、App 与生产偏好身份检查通过。连同首轮正式 90/120 和独立诊断 6/8，本批合计 **186 App/248 请求**；计时统计仍各批分开，不混池。正常退出与 presented/finalize 不是 typed drain ACK。

| v3 最终五组中位数，ms | C0 D3-final 前驱 → 493 候选 | C1 D3-final 前驱 → 493 候选 | W0 D3-final 前驱 → 493 候选 |
|---|---:|---:|---:|
| 3750342273 重输入 | 1590.762 → 1580.172 | 1018.291 → 1047.822 | 247.289 → 253.002 |
| 3141421197 独立输入 | 1275.785 → 1259.256 | 900.768 → 890.030 | 115.491 → 115.517 |
| 自有五段 MDL PKG | 851.970 → 866.741 | 838.050 → 849.833 | 90.157 → 94.890 |

最终原事件继续显示残余资源代价：模型 W0 resource-progress → surface-progress 为 7.687 → 14.116ms，增加 6.429ms，五对均为正增。它仍是父端观察到的重叠阶段窗口，不是独占 CPU/GPU 成本。v2 候选该中位 19.794ms、v3 候选 14.116ms，跨批描述差为 −5.678ms，不能当配对 gain；前文 18.650 → 14.977ms 才是独立单组诊断。目录迁移与同调用路径减工已经接线，残余资源代价和正式性能卡仍开放。

九个条件的中位变化均落在原规则计算的非目标预算内，**不是证明无回退或全部回退已修**。模型 W0 为 90.157 → 94.890ms，增加 5.2497%；前驱/候选噪声分别 36.4220%/20.2603%，前驱范围 87.754–122.994ms、候选 93.497–114.115ms，原点均保留。首轮模型 W0 超预算结论不会被重写，两个正式批的前驱噪声也不同，不能把跨批候选中位差直接解释为改动收益。

本次只有独立输入 C1 和模型 C1 的两 arm 噪声都低于 5%；其他七个条件至少一 arm 超出。重输入 C0/C1/W0 前驱噪声分别 9.178%/8.552%/8.227%，W0 候选 13.899%；独立输入 C0 候选 30.051%，W0 候选 7.190%；模型 C0 前驱 6.951%，模型 W0 两 arm 如上。完整原点、范围、配对差与各项预算布尔值见 `d4-v3-runtime-analysis.json` 及各原始 `report.json`，未删点、未放宽门或重复五组直到变绿。

**最终 `wholePerformanceCardPassed=false`，无正式收益。** 各条件目标计时门均未通过，局部 CPU 减工只证明该机制；不以行为通过或落入高噪声预算抵消收益门。停止目录 stat 微调，不代表关闭 regression，也不再为使计时变绿继续缩减校验；后续沿原计划处理字体、独立 AV、可信 receipt/package 等实际未迁移字节族，P2b/P3 的真实 package/内容复用须重新验证，package 激活仍以全部硬前置为准。

## 结构门与剩余边界

结构门运行 15 项、3 项失败。隔离重建 753 份 source 集合，仅将 24 个 D4 产品替换为其实际 D3-before 后，原 scanner 的 before/current 结果一致：6 个目录 layout 违例、shape-derived-analyzer-fleet 67 对 baseline 66，以及同一组 authority/completion 报告。D4 新增 pattern delta 为空；相关 scanner/baseline 也匹配 actual-before。raw 正则计数含一个被原 classifier 排除的 passive DEBUG 声明，正式分类值为 67，不能用 raw 68 混报。未放宽 baseline 或更改断言消掉这些先存失败。

其余 app-debug-layout、assertions、repository-artifacts、dependencies、residue、code-health、defense、design 最近静态门通过；相邻产品 CPU/GPU 与 compile-only 分别按实际日志结算，不将“选中了模块”当作执行结果。结构存量仍是已知边界，不把 build 成功当作全部仓库规则通过。

字体、独立 AV/音频 URL-only 字节消费、可信 library source DTO/receipt/IPC 与 package backing 尚未闭合；extractor 仍完整读包和校验缓存，本批不是 P2b 完成。未验证长稳、峰值 RSS、CPU/GPU 尾部、能耗/温控、多屏、完整画面/音频、Release 或 typed drain ACK。正常退出与 presented/finalize 不替代上述验证，Root 目录 metadata 也不授权对 modified 包重算收养。

## 证据、清理与 Git 状态

证据已提取至工作树忽略目录 `.artifacts/scene-evidence/runs/`，`batch/report.json` 的 label → 样本 ID 和 manifest 拥有原文件的映射：

| 包 | payload 数（含 report） | 逻辑字节 | manifest SHA-256 | 保留 |
|---|---:|---:|---|---|
| `wallpaper-startup-scene-d4-20261024` | 986 | 19,297,888 | `d85385958d1d59386b43479e61c870047aa0c8f2baed2a80f4b21a48c9bf5786` | 默认 14 天 |
| `wallpaper-startup-scene-d4-regression-20261024` | 220 | 5,976,454 | `388a4617cf3737033d2675e1eb59394e25583238717e2b8696adacff200094f2` | 未解决回退受保护 |

两包全部 payload 在清理前已与原文件逐项校验大小和 SHA，清理前再次校验包内字节及不可变 manifest。首轮超预算与最终资源窗口残余均保留，protected 包不随普通到期清理。后续合同一句旧 URL 描述的修正、文档登记 v2、独立语义终审、精确清理和最终门另存 `wallpaper-startup-scene-d4-20261024-closeout`，不改写先提取的两包。主要标签包括 `d4-owned-code-final.json`、actual-before source、Root 假设与修正、GPU 前驱绑定/归一对照、三次 build、两轮 formal 原点及各自分析、Root 成本探针、单组诊断和最终验证收据；后续登记替代关系保留旧收据，不能将旧版本误认最终源码。

`d4-cleanup-receipt.json` 记录已结束产物的精确文件清单、哈希匹配及句柄/进程检查：删除 1,947 个文件、413 个空目录，文件逻辑长度合计 166,654,669B。包含可复建的受控模型样本、native 模块缓存及已验证归档的重复日志/源码快照；不是声称实际磁盘释放同样字节。清理时相关 App/helper、native harness 和编译进程均已结束，待删文件无打开句柄，无未归档项被猜删。

连续迭代只留任务目录 `/private/tmp/mwx-startup-optimization-fbRhFY/DerivedData` 一份构建缓存及最终签名 App493；`d4-predecessor-app` 保留实际前驱 App4f，`d4-candidate-v2-app` 保留首轮失败 App483，供未关闭回退复现。隔离 `inputs` 和 `d2-synthetic-inputs` 留给后继迁移；私有偏好备份和先前受保护失败材料保留，不收进公开证据。小体积文档修正前快照与预览在 closeout 提取前保留。未触及真实用户媒体和官方参考原件，未重置用户设置或安装测试 App。

本批新增历史证据登记，更新当前合同/接线和同路径正文预算；正文硬上限及原产物预算未放宽，稳定合同 review hash 绑定实际正文。目录迁移的限定行为验证完成，正式性能卡仍失败、资源回退仍开放。代码、测试及文档均保持未暂存、未提交、未推送；主 checkout 保持干净，专项工作仅在隔离 worktree。持续 goal 继续，后继优先真实 package/内容复用依赖，不因本批归档宣称全部改造完成。
