# 冷暖启动专项结算

> **历史证据 — 非现役入口**

> 截止：2026-10-25。本文保存已结算专项、未采用设计及全部原失败/STOP；不产生新的任务或产品能力。
> 当前职责：[Scene启动合同](../../scene/architecture/scene-launch-responsiveness-contract.md)、[Web模型](../../web/web-project-json-runtime-model.md)、[Web宿主](../../web/dedicated-host-process-design.md)、[切换事务](../../architecture/playback-lifecycle-transaction-design.md)、[当前运行证据](../../scene/capabilities/runtime-evidence-current.md)。原URL仅作[永久导航](../../development/wallpaper-startup-optimization-plan.md)。

> 后续更正：正式 Release 试用已发现新增历史摘要校验误拒旧壁纸及重复准备成本。当前纠正范围与状态见[全仓精简执行记录](../../development/validation-simplification-plan.md)；本页的 D37/D40 结算只证明当时输入与构建，不能再作为后继代码已完成或保留过度认证的依据。

## 最终结算

- 专项实施及本机限定验收已完成；产品固定为D37签名Debug App（exe `f075dca44ba637e5a23a28f9e95b2c160279f4e100fe93c81a59f31a6553ef68`），D40无产品改动或新构建。4352产品/工程输入与实际构建map相等；测试后332个原有未提交文件字节/模式不变，HEAD仍`ae0ac798c`、暂存为空。
- 已采用：Web同次作者/依赖输入供解析、analysis/execution校验与保存共用，最终重建当前授权；Scene可信来源receipt、单挂载索引及按需验证读取，必要URL消费者沿原资源owner有界物化；stock构建期清单；Sound/完成WebM文件的弱成功复用及Registry命中免读；Scene已提交跨类型交接后的最多30秒有界进程重入，以及与可选Web空预热的原入口互斥。WebView退休复用、跨launch常驻缓存等未采用。
- 已证局部减工分别保留原范围：45.3MB音频第二次准备读/写各45315800→0B、第二次音频Program准备耗时26.920→0.153ms；stock叶构建154.214→83.563ms且2264项投影同；WebM原生准备183.358→18.826ms、该机制磁盘预约减半。后两批已补产品接入/回归，不能把这些叶时间冒充整App提速或内存修复。
- 最终D7→D37近上限输入五组配对、30App/40请求的RAM三条件通过原噪声/相对/4GiB门，C0/C1/W0配对变化分别−1.3949%/−1.7497%/−3.6570%。整体启动时序仍未通过原噪声门，不提供稳定累计提速百分比；旧Video交接完成约+38.713ms与观察到的首画/完成边界分别保留。
- D40同一普通UI App真实出版light314与自有WebM TEX900000008，30FPS；21组唯一请求/会话/票据对应GPU首帧完成、原Service与Manager提交，20次轻/视频交替，20条相邻旧会话retiring链成立。无标签pause与旧会话handoff时序相符，不能据此判新视频暂停。原sandbox扩展警告保留。
- 最终视频稳态1816.634893292秒、1498次资源观察，主App95737与Scene96163身份全窗唯一无缺席；有界端点原生画面变化，首/中/末自有caffeinate断言及保守电源窗口无睡眠记录。原采样RSS范围70976–138032KiB、首138032/末73216KiB、Scene CPU累计92.3秒，只是该次运行观察，不是泄漏、FPS、能耗或完整峰值资格。
- 真人OS恢复仅覆盖本次Scene视频：实际锁/解锁伴随原暂停/恢复及后续输出；kernel睡眠21:28:38.509142→唤醒21:29:07.098955，电源日志另见Software Sleep与FullWake；缩放使Scene逻辑1512×982→1352×878→1512×982、backing3024×1964→2704×1756→3024×1964，变化及恢复后均有动态输出。
- 压力仅人工OS warning通知，不是物理RAM压满：第一次观察从warning2开始、只见恢复1，缺进入起点，原记录保留未授完整资格；在确实先记录normal1后，真人补一次5秒命令，独立raw完整1→2（约4.913秒）→1，恢复后同Scene两次原生输出有变化。不推每个owner收到了通知或全部cache清空。
- 普通Cmd-Q自然结束parent0/所有owned child退出，无超时或退出前强清；原11项守卫全部通过，包括测试suite清理、生产偏好、作者/commit/receipt、签名、来源/工具与并发环境。9个已知运行/出版/编译PID均物理gone，全部观察器与外层终态0，公共flock实际可取释；运行窗口已明确交回UI会话，未恢复其崩溃候选。
- 合理STOP不是欠开发：P4/P5及无成本依据的常驻/额外缓存继续停止；375完整五对RAM/时间因极短命helper不能取得有效值而STOP未覆盖，D39功能/退出/采样间隔通过不改变该失败。旧D28 seek红点及之后有限成功各保原时点，原因未追认。最低设备M1/8GiB、多屏、Release、Web真实OS恢复和完整作者/官方一致性未验；不据本次Scene输出扩授。
- 已替代toolURL/Process解包分支及空协议已退役。合法legacy builtin extractor、旧managed完整认证/升级与Registry miss仍是必要兼容/失败路径，不是第二套启动权威；不为清零删它们。新链沿原选择→来源准入→准备→候选/GPU首帧→呈现/产品提交→退休，失败/取消及最后资源借用仍归原owner。
- 后续只按稳定合同维护，不从本归档重开STOP或把approved设计当已实现。详细原点归D31–D39历史；本批证据入口为`wallpaper-startup-scene-d40-20261025-checkpoint`与独立原图包，提取/保护状态以最终manifest和收据为准；全部代码与本轮文档保持未提交、未推送，等待用户审核。

## 原设计与阶段记录

以下“当前/下一步/approved/命令”仅属于冻结时点，不表示已实现、通过或继续实施授权。原设计、失败与STOP完整保留；只改相对链接及角色标记。

<!-- preserved-body:start -->
# Scene / Web 壁纸冷暖启动改进专项

<!-- archived-original-role: active-plan -->

> 设计日期：2026-10-23；2026-10-24开始实施。状态：当前产品仍D37，完成文件复用与命中免读已采用；D38同D7/D37近上限30App/40请求正式RAM三门通过。D39退出重核已验证，375七App/九请求功能/退出/采样间隔全过，但一短命helper首次查询即gone，原coverage失败保留；按事前停止该统计方向，不再重采。最终仍需当前D37视频路径20切换/30分钟及用户延期的OS恢复；D24长跑属旧版本，不能直接转授。
>
> 用户已授权阶段实施和必要重构；初始文档提交为 `ae0ac798c`。后续批次保留未提交改动待审核，不推送或发布；持续 goal 在实际采用阶段验收并结算前保持进行中。
>
> 本文唯一维护本专项的步骤、裁决与停止条件。Scene 稳定边界归[启动合同](../../scene/architecture/scene-launch-responsiveness-contract.md)，Web 执行生命周期归[宿主设计](../../web/dedicated-host-process-design.md)，跨引擎产品提交归[切换事务](../../architecture/playback-lifecycle-transaction-design.md)。自主兼容队列不作为用户指定启动工作的前置，其他专项不因本文自动重排。

<a id="decision"></a>
## 1. 目标、范围与选择

在相同内容、属性、画质、授权与首帧门下，减少从“设置壁纸”到实际可见的等待，以及启动期间的 UI 阻塞、文件读写、重复解析/编译和内存峰值。覆盖首次使用、保留磁盘缓存的新进程、同类型重设/切换与跨引擎返回；不能只优化内部 Host 返回或某个阶段日志。

**产品收益裁决（用户2026-10-25明确）：** 启动等待、重复读取/解析/转换、内存、磁盘、CPU/GPU、能耗及稳定性，任一方面有明确收益，都可考虑接入产品；不要求同时解决当前正在排查的问题。分别核实际收益和其他方面的代价，保正确性、授权与生命周期；不能因某项指标未改善而否定另一项收益，也不能用另一项收益掩盖已知回归。原生机制结果先补必要产品集成与代表验证，不将其直接冒充完整App结论。

本专项沿原owner完成两条采用链：Scene可信package索引/按需读取和必要有界物化；Web同次作者依赖捕获/解释复用。后续内容、Metal与宿主复用按成本进入；P4/P5等无成本依据的STOP边界不作为欠开发。D34完成转换文件的原生准备/磁盘收益已沿D36接入当前未提交产品候选，D37继续消除命中前的重复读取；长期强驻留cache仍停止。保持Swift/AppKit、Metal/WKWebView与唯一产品事务，不以未采用复用协议冒充现状。

| 备选 | 收益与风险 | 裁决 |
|---|---|---|
| 继续优化全量解包缓存，再另建增量解包 | 可少做部分暖校验，但仍有首次全量写盘与重复 namespace；容易形成三套资源来源 | 不作为终态，不单独建设另一套可信解包 cache |
| 现 ResourceView 承接 package index、read 与必要物化 | 直接减少不被消费的读写；需迁移 URL 消费者、完整性发现时点和 lifetime | Scene 主方案；先 CPU 行为，再同输入产品运行，最后删除旧产品调用 |
| 全换 Web 引擎或单一 daemon 承载全部候选 | 可能降低初始化成本，但扩大崩溃半径、改变隔离与协议，当前缺成本依据 | 不选；保留 active 与 candidate 的隔离，改造现有 worker 的退休/复用 |

不以全模型常驻、无界进程池、默认后台扫全库、跳过校验、降低画质/内容、延长 timeout 或提前 ready 获得收益。Windows DXBC/私有缓存键与算法不移植到产品。

最小可交付结果是：真实产品入口的有效基线、Web 同次依赖快照复用、Scene 单挂载按需读取的完整纵向链。后续内容/Metal/宿主复用各自按证据进入；每阶段可以独立保留或撤回，不把全部候选捆绑成一次大重写。

## 2. 研究依据与当前首断点

2026-10-23 对本地合法客户端作只读有界取证：Wallpaper Engine 2.8.42，Ghidra 12.1.2 / Java 21.0.12。Scene `wallpaper64.exe` SHA-256 为 `40e2ce021e9352324fadb3b8f72b8ba2a7ee95b71cc571d5b9f84be75cd993b0`；Web `bin/webwallpaper64.exe` 为 `51173dab085628159b1af7d9b745c15768497d738c7bab7b72d667a35b4f6d9d`。两者研究前后相同。临时工程与反编译输出已清理，不进入仓库。

**固定版本静态观察：** Scene 所查播放路径建立包内索引，按条目定位读取；shader 有编译字节码/配套元数据命中路径，未命中再编译。Web 使用本地文件 URL、项目根检查、`cacheId` 分区的 CEF profile；存活 browser 有重导航路径。不能据此推断 PKG mmap、全部切换的进程复用、缓存实际命中率或性能。

**公开依据：** [官方 CLI](https://help.wallpaperengine.io/en/functionality/cli.html)接受 Scene PKG 入口；[Web 创作指南](https://docs.wallpaperengine.io/en/web/first/gettingstarted.html)要求尽量随项目提供本地依赖；同版 CEF 的[缓存设置](https://raw.githubusercontent.com/chromiumembedded/cef/3a0fcf1/include/internal/cef_types.h)与[CreateBrowser](https://raw.githubusercontent.com/chromiumembedded/cef/3a0fcf1/include/cef_browser.h)解释全局 profile/context。参考只决定研究方向，按本项目合同独立实现。

**未运行：** 官方黑盒冷暖测速、初始 mip 策略、真实浏览器 HTTP/Code Cache 命中与官方进程保温条件。没有官方时序/画面一致性或提速百分比结论。

下表是本设计冻结时的源码事实，实施前重核，不是性能占比：

| 现有 owner | 首断点 | 对应步骤 |
|---|---|---|
| `MyWallpaperX/Core/SteamWorkshopScene/Format/ScenePkgCacheExtractor.swift`（历史旧文件）、[SourceFacts](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRuntimeSourceFacts.swift) | 每次准备读整包、包/entry hash；命中仍枚举并逐文件读缓存比较 | P2 |
| [SceneResourceView](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceView.swift) | package/loose/stock 每次重建目录索引；Host 还要求 `packageReport.outputURL` | P2、P3 |
| [SceneDesktopWallpaperHost+Launch](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift) | 每次 ModelBuilder；基础作者事实与属性投影尚未形成可复用的独立输入 | P3 |
| [PassEncoder](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift) | authored library/PSO cache 属于实例；多屏可能重复 `makeLibrary(source:)` | P4 |
| [WebRuntimeCache](../../../MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebRuntimeCache.swift)、[准备入口](../../../MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopWebResolvedRuntimeModels.swift) | execution 命中仍扫描；跨 App analysis 校验可能再次扫描；保存再取得签名 | P1 |
| [WebDaemonRuntime](../../../MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonRuntime.swift)、[父 adapter](../../../MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter.swift) | 生产 IPC 一次 launch；空 daemon 只完成 AppKit/IPC，未创建 WebView | P5 |
| [LoopbackServer](../../../MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLoopbackServer.swift)、[scheme IO](../../../MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler+IO.swift) | 高兼容档 port/token 改变；HTML/CSS 非 304 响应重读/转换 | P6 |

已存在的 CPU Program/preparation 持久缓存、single-flight、PSO archive、隐藏资源延后、媒体 Range 分块、持久化 WKWebsiteDataStore 和有界空宿主必须复用。调用 `MTLCreateSystemDefaultDevice()` 不证明驱动重初始化；不能据此新建 device owner。

## 3. 目标职责、身份与资源合同

```text
产品意图/epoch（WallpaperManager）
  ├─ Scene: 版本租约 → 一次挂载/安全索引 → 按需验证字节 → 不可变作者事实
  │          → 属性/Program LaunchPlan → 同 launch/device 资源 → 每屏 Session → 原呈现/提交
  └─ Web:   版本与属性输入 → 同次依赖快照 → descriptor/context + 当前 grants
             → 原 adapter 选择兼容空闲 worker → 新执行代次 → 每屏候选 → 原可见/提交
```

### 3.1 一份内容身份，两种证明

内容身份包含已有 library storage identity/generation/content digest 与索引/解析 schema；launch 再加入属性、locale、compiler/render contract；device 产物再加入 OS/compiler/device/attachment。recordID、路径、mtime 或 App 版本均不能单独代表内容。

版本租约只阻止 App 发布替换/回收，不能认证文件字节。来源 generation 的准入 receipt 必须另绑定包摘要、规范索引摘要和 entry 预期摘要；由主 App 既有 library 版本元数据 owner 发布，再经现请求 IPC 传身份/receipt 给 daemon，不信来源目录的自报 sidecar。现 library `contentDigest` 是路径/长度/file digest 组成的树摘要，不能与 package SHA 混用。旧安装缺 receipt 时，须完整流式核对原 commit 的树摘要后才能为 managed 来源签 receipt；不匹配拒绝受影响单元，不能对修改后的当前包重算后静默收养。可变 legacy 来源完整准入形成新 generation，派生 marker 不自授信任。

receipt 的 package/entry 摘要来自参与该树核验的同次字节流或已认证私有 immutable snapshot；不能先 hash 包，再按 URL 重读 entry 为新内容签名。流式读计划可按 offset 排序并同时更新覆盖区间的 entry hash，但保索引原序及原先合法的重叠 range，不为简化实现收紧格式。首次准入只承诺有界与认证闭合，不承诺少读。

首次准入验证完整路径、别名/大小写冲突、索引及全部 range；缺可信 manifest 时完整流式 hash 建立 receipt，可沿入库或首次播放完成，该轮不承诺省整包读取。暖挂载重读小索引；字节消费者核对实际 entry 摘要后取得同次自持数据，大媒体则边验证边写受控物化文件，完成前不发布。FD 前后状态变化使本次读取失效；metadata 只发现变化，不替代摘要。不能“校验一次路径，再按路径另读未验证内容”。

**发现时点变更：** 未被读取 payload 的损坏可以延后至首次使用 entry 才发现；索引/range/路径错误仍在挂载时拒绝。实际消费 entry 的同大小篡改不得漏检；依赖完整性失败不发布 Program/纹理/媒体。这个有界按需语义须迁移旧 extractor 测试，不能以减少测试覆盖实现速度。

### 3.2 来源与物化只有一个入口

现有 ResourceView 继续唯一决定 package→loose→stock 查找优先级，内部把物理路径资源改成带来源/generation/purpose 的只读 handle。拟新增的 mount/handle/receipt 是该 owner 的组成部分，不再建并行 registry 或第二 resolver。

字节消费者统一读取 handle；字体沿现 Data→CGDataProvider→CGFont 直接消费验证字节，不因迁移新增 URL/落盘。必须 URL 的媒体走同 owner 的显式桥：先按 range 长度预约聚合内存/磁盘预算，再以有界块从同一 FD 边 hash 边写唯一 staging，摘要成功后原子完成并把 owned-file lease 直接交 provider；不能先验 handle 再按作者 URL snapshot 一次。按 generation+entry digest/purpose 去重，最后 waiter 取消后停止领取、join 并退还预留；桥不扩成整包展开。发布后的 App 自有文件不原地改写，使用前仍核实际文件/完成身份；损坏重建或局部失败，marker 路径命中无效。

mount/物化 pin 属于实际 request/provider；CPU 在途读取与 GPU drain 未结束不得释放来源租约。自持 bytes/IR 缓存不持有来源 FD/URL；若以后保留 lazy handle，必须扩展原租约协议并证明不阻塞版本更新/删除，不能偷偷常驻。

### 3.3 缓存分工

PreparedContent 只保存不可变作者数据、依赖身份和解析结果；属性投影、VM/clock、localStorage session、RNG、媒体播放器、binding、graph target/history 与 publication 不进入它。LaunchPlan 按当前属性建立；device 成功对象先限同 launch 多屏共享。跨 launch/device 保温另取收益与驻留证据。

Web 同次依赖快照服务当前 descriptor、execution 校验和保存；有效资源 grants 继续由原 bookmark/binding owner 在采用时重建。文件在扫描期间改变、扫描截断或身份未知不能伪造完整命中；仅同一已验证输入可共享结果，不能把扫描时间预算当原子快照或永久新鲜度。

## 4. 分批实施步骤

每步均执行：重核 owned diff/并行改动 → 最近行为门 → Swift 改动签名 Debug build → 对应隔离产品入口 → 冻结差异和证据独审 → 更新本表结果与稳定合同 → 精确清理。阶段中“通过”必须附输入/build/工具身份及未覆盖范围；测量资格、结构改动与实际提速分别结算。

| 步骤 | 依赖 | 本次设计状态 | 产品/性能状态 |
|---|---|---|---|
| P0 有效基线与观测校正 | 无 | 已定义 | 原隔离/计时与分段保留；D24累计功能合格、5/6噪声失败。D25确认Video交接完成差不等于首画差，STOP继续追因，不授正式性能 |
| P0b Web 原生窗口配置 | P0 几何归因 | 已定义 | 原生过冲消除、五组交替及作者音频通过；保留 prepared 前未归因长尾，不认领性能卡整体通过 |
| P1 Web 一次依赖准备 | P0 | 已定义 | P1b 捕获/纯解析/取消租约已接线，行为/签名/代表启动及当前实音通过；v3五组无正式提速，v2约179ms回退仍保未归因证据 |
| P2 Scene package 资源输入重构 | P0 | 来源链及D36完成文件复用已接；D37复用命中减重读已证 | D38当前近上限RAM三门通过，时间仅观察；D39已修退出采样间隔，375单个极短命helper不可查询，完整统计按先验STOP未覆盖。D35已撤，旧seek保留 |
| P3 Scene 内容与索引复用 | P3a 固定 stock 仅需 P0；其余需 P2 | 按成本进入 | P3a/D15局部减工、D18默认stock构建清单已接；D17内存tier、D19额外排序均成本不足停止，D19音频复用限定验证保留；整体性能未验收 |
| P4 同 launch Metal 成功产物共享 | P0；与 P2/P3 不重叠时可独立 | 条件设计；成本不足即停 | D13停止产品实施：双encoder确有重复创建，但单key第二次已命中原archive、窗口很小，未证实际多key/多屏热点 |
| P5 Web worker/兼容 WebView 退休复用 | P0、P1，初始化成本有依据 | 已定义；入口成本不成立即停止 | D12停止实施：现暖预备已覆盖spawn/AppKit/IPC，未证daemon-only的关键路径净收益；不落闲置协议/drain基础，P5b公开清场边界仍不足 |
| P6 Web 响应复用与 loopback 边界 | P0、P1；复用依赖热点证据 | 已定义有界范围 | D12同store双端口先红后绿，精确本cookie清理；转换cache及稳定origin STOP，不认提速 |
| P7 整体验收与旧链退役 | 实际采用的阶段 | 最终证据未齐 | D24稳态与D25 GUI/Web有限功能已补，D36新版375功能通过；D38近上限RAM已过、D39对375统计STOP未覆盖；当前D37视频长跑及真实OS恢复待补，原噪声/seek、最低设备边界保留 |

### P0：先使冷暖与首帧测量有效

1. 冻结主 App/daemon/helpers、源码与工具链身份，准备只读媒体的隔离副本和独立 HOME/cache。记录普通产品配置与优化 Debug 观测配置，禁止混作同一分布。
2. 沿现有 Scene daemon-client 与 Web startup runner 补同请求 selection、accepted、内容准备、CPU Program、device/WebView、prepared、present/visible、commit/finalize 时间。selection 从实际设置入口开始，包含通知 daemon 前的租约/属性准备；观测只读且 DEBUG 显式启用，不新增产品计时 owner。
3. 记录包/entry/目录/依赖实际读取次数与字节、Metal 创建次数、worker PID/instance、Web store/origin、CPU 峰值与停止后驻留。嵌套/并行阶段按同一时钟和区间解释，不把各段机械相加。
4. 先取得有效基线，再按主链选题；若主要等待已转移，重排本专项阶段，不按静态可疑点强做缓存。

`scene_wallpaper_benchmark.py` 默认 direct Host，ready 不能称产品首呈现，keep-runtime 下轮新 HOME 也不算暖。P0 沿原 daemon runner 每轮走 `setAsWallpaper`，绑定 ticket/request/execution 和真实 presented payload；prepared/finalize 观测仅 DEBUG。Web startup 显式保留产品 coordinator 并抑制重放/登录恢复/全库预热；schema 2 取原 `session.committedAt`，轮询仅作资格匹配及另列延迟，不承诺 20ms 上界。

**隔离资格修正（2026-10-24）：** 实测 `CFFIXED_USER_HOME` 未隔离 `UserDefaults.standard`；首轮生产 bundle ID 的运行作废，不作前后比较。用户已授权恢复默认播放偏好，保留30 FPS/未暂停。P0 仅接受签名及 Info.plist 均为 `com.songziqiang.MyWallpaperX.Debug.Startup` 的 App；native 在产品装配前核标准域随机哨兵与实际 HOME/Library/cache。[统一脚本](../../../script/wallpaper_startup_benchmark.py)每组 C0 经 defaults API 清空并验证测试标准域，C1 保留，结束清理；生产标准域前后核语义/磁盘摘要，不输出私有值。Scene 两级 shader cache 仅 DEBUG 额外允许精确测试身份，仍走原隔离 HOME 缓存路径。新身份权限单独资格确认，不借生产 TCC 状态。

固定 staged App、样本绝对路径、配置与各组 HOME；两臂统一运行包名`MyWallpaperX.app`，备份名不进入运行输入。仅启动benchmark显式传名，由原stage owner复制/验签，其余调用默认不变。C0/C1/W0分列，Web首项不计W0，Scene W0同daemon PID/generation。作者音频保持，系统缓存未知，未接计数不填零；保原点，不暖机删点或放宽门。D16名称控制有并发编译干扰，不授清洁性能因果。

**退出门：** 各测量条件能由实际 HOME/cache identity、PID/instance 和真实事件证明；缺可见事件的 run 标无效，不补造数值。停止重复归因，进入首个可证且可区分的改动。

**D11配对摘要纠正（已落地，计时与验收门不变）：** 同App/同已发布来源的一次A/A已显示，独立汇总中位数之差不等于同iteration配对差异中位数。沿原benchmark唯一计时和取值核新增显式配对摘要：两臂每iteration/条件须唯一、成功、有限且符合真实runner形状：Scene W0一暖值，Web七次选择的后六暖值先按App取中位，再各作一配对点并保原值/数量；缺失、重复、失败或不匹配拒部分比较。零基线保毫秒差，百分比不可定义则显式缺失，不能丢点。保原分布/原点，不自动授性能验收；原5%噪声、配对降幅及非目标门均不放宽，不改历史D10结论。D12补真实Web形状，不改计时或重跑历史。

2026-10-24 的[首批记录](wallpaper-startup-p0-2026-10-24.md)保留隔离故障、有效输入与全部慢点。Web schema3 将一类等待定位为窗口几何确认，外部轨迹及 P0b 已验证原生展示动画的影响；不因源码有重复扫描就优先重做 P1。P3a 已证 W0 重复索引工作减少，正式交替批基线噪声略超原门，只保留有界机制，不认领全面性能验收；P2/P3 内容缓存仍按原安全依赖推进。

**P0b 窗口配置短修裁决：** 仅本任务 App 的外部只读几何轨迹确认连续缩放与过冲，快轮也可能在短暂正确的矩形处通过。先在现 Web `makeSurface` 首次显示前设置 `animationBehavior = .none`，关闭 AppKit 普通窗口展示动画；不改作者 CSS/JS 动画、窗口层级/Space/几何判据、媒体 ACK、旧输出屏障或重试间隔。以同输入短轨迹验证过冲是否消失，再做原 C0/C1/W0 交替对比及健康输入回归；无效则撤回该单一配置，不能改宽几何阈值。此修正只依赖已取得的 P0 成本依据，不等待 P1/P5 大重构。

**P0b 结算与下一断点：** 候选短轨迹的全部在屏观测保持目标矩形，交替批当前 activation 的几何 retry 由全部出现降为零，当前媒体 ACK 与旧输出屏障仍成立；真实作者音频持续到达页面。保留这项原生窗口配置及观测到的中位数改善。候选 W0 有一次 prepared 前长尾，预启动 daemon 已采用且之后几何/媒体确认正常；现证据不能判断它是新回归还是既有离散，更不能归给 IO/WebKit。原点、日志和噪声门完整保留，整体性能卡不通过。下一轮先在原 Web prepare owner 分解此段，并补代表性重输入的 Scene 成本，再按实际成本选择 P1/P2/P5；不重复证明已闭合的窗口问题，也不盲目把同配置套给 Scene。Scene 短查未见同类连续缩放，采样不覆盖精确 presented 瞬间。

**准备分段裁决：** 沿原 DEBUG observation 追加父端 launch enqueue、子端接受、各 surface 完整创建/load 发起/首次 ready 来源、当前 cohort 的 snapshot 与 policy 等待时间；在原 didPrepare 成功边界冻结 generation/surfaces，再随已匹配 activation 传回。整段 surface 创建不等同 WKWebView 构造，ready 可能来自 didFinish 或注入消息，policy 接受可能复用已有 ACK；这些时间均不证明作者异步资源全部完成。先分离父端准备/传输/导航与 snapshot，不扩成全资源 trace，不增加 ready/提交权威。

**D20/P0 预接受分段（已实施；诊断通过，不授性能）：** 沿原 Client 显式 DEBUG observer 记录 `preparationReceived`、`processStartBegan/Returned`、`helloObserved`、`loadEnqueueAttempted` 五个父端 systemUptime 边界。foreign ticket/epoch事件直接忽略，load原request及generation/PID与prepared身份核等；本行必需事件缺失、同票重复、错代或倒序只使独立分段资格失败，不改原首帧passed。准备收到覆盖准入、属性及 Shell 转交总和；start 调用含原 registry/Process.run/reader安装，hello 含管道及 parent main 等待，send前仅尝试。无 observer 不取时钟，结束撤销；暖选择缺失不补零，不新增计时/退出 owner 或更改 IPC/超时。

设计先落库，6最近方法/12原生命令、Debug与一次原C0/C1/W0的3App/4请求通过；C1 648.817ms预接受中631.921ms落在start返回→父观察hello，准备总和10.592ms；同daemon暖预接受2.711ms。现可将后继缩至子启动/握手组合窗，但不能解释D19配对正差或认领提速。D21已执行一次现成App Launch全进程短记录：真实ready通知成功，但5s录制后的收尾超过原30s界限，停止自有句柄，trace副本导出报缺template、没有启动栈，方法STOP。后继转原DEBUG子入口的最小同boot单调值点，先分main前、AppKit、Runtime/Host与hello排队；设计须沿原hello/transport身份和当前观测owner，不新建产品时钟/退出权威或改初始化顺序。D14旧sample无栈与本次失败保留；不盲加cache、重跑五对或把工作移过accepted制造收益。完整原点与边界见[D20](../../scene/history/scene-startup-d20-2026-10-25.md)。

**D21资格边界：** 原C0完整结果通过；C1原passed分支与native呈现/finalize成立，但完整返回对象未在采集器异常前纳入外层runs。W0未执行、整组失败，不能报3App/4请求通过，也不能把工具超时当壁纸回归。仅独立测试suite/标准域按原owner清空并核生产偏好不变；最终App/source未变，无新构建或提速结论。原点见[D21](../../scene/history/scene-startup-d21-2026-10-25.md)。

**D22/P0子入口分段（设计先落库，已限定验证）：** 外部采样STOP后，只在原Client已安装DEBUG prefix observer时给原daemonArguments附显式flag；child必须同时为Scene daemon且带该flag才取值。App原main在这两个参数判定后局部记录`entryObserved`，在原watchdog之后/`NSApplication.shared`之前、之后各记`appKitBegin/Returned`，在原`SceneDaemonRuntime()`前后记`runtimeBegin/Returned`。前五点的局部值在构造后一次交原Runtime的DEBUG可选属性，App不再写；原stored-property/Host/预算设备初始化顺序不变。configure在原hello编码前加`helloSnapshotCaptured`并冻结，随同一hello附一个8整数子字典（schemaVersion=1、child自报pid及6时点），不新增请求/事件、时钟或退出owner。原IPC版本、role/sourceSchema、握手期限、replay与选择流程不变，Release预处理后保持原代码。

子字典在原合法入站hello内限8键，仅接整型数值，沿既有unsignedInteger拒绝bool/负值/越界，DEBUG另排浮点/字符串；缺坏值只投为观测缺失或无效，不改变产品hello准入。沿同一个prefix观察值带给原reducer，独立`childStartupObservation`核schema/精确键、child自报pid与真实transport及最终prepared PID、既有ticket/epoch/request/generation身份、自身时序及最后点不晚于父hello。fresh若有父startBegan则只核其不晚于child第一点，绝不要求child第一点晚于startReturned；已在预热中的hello可早于本行entry。暖选择无新hello合法notApplicable/null，不回填旧值。原首帧passed与D20父五段资格不被新诊断更改。

六点只分调用/调度合窗：startBegan→child第一观察还含fork/装载、调度、Swift入口及参数检查，不能命名独占before-main/dyld；runtime构造含原Host/defaults/预算设备查询，不能独归Metal；最后snapshot→父hello仍含编码、queue/write及父交付，不能伪称enqueue或物理write完成。验收为最近reducer/原Client正反例、Release双投影、冻结源Debug及一次原3App/4请求（不加profiler或重跑五对）；实际点须单列构建/缓存扰动，不据一次诊断声称提速或解释D19正差。未取得可减重复工作则停止此成本方向，不能后移初始化、改超时或加缓存制造收益。

D22完成7最近方法/12命令及一次3App4请求，三次NSApplication.shared调用窗520.610/554.723/561.470ms；同daemon暖无hello，原child字段按NA保null。这是带系统/调度等待的壁钟，不是AppKit内部CPU或旧正差原因。后继强退役/有界重入已由D23接管；首次C0/C1不据复用认收益，AV borrower/RSS不随Session承诺归零。原点见[D22](../../scene/history/scene-startup-d22-2026-10-25.md)，最终证据缺口归P7，不再从旧待实施措辞另起owner。

`daemonFinalizeAndDrainObserved=false` 是runner关闭前固定写值，不是负ACK。原lease仍持到真实进程退出；当前产品采集未纳typed `exited.gpuDrained`，保此未覆盖门，不从App exit0/child0推断GPU或AV drain。关闭此门须沿原shutdown分别核ACK与真实退出，不能置true或另建退出权威。

### P1：Web descriptor/execution 共用依赖快照

1. 在现 `SteamWorkshopService` 准备核中形成同次 immutable input：库版本、entry/root、属性来源、locale、overrides 与资源授权 revision；actor 只装配产品状态。作者依赖 key 与 execution 投影 key 分开，单纯 overrides/grants 变化不重做作者依赖发现，采用仍绑定当前修订。
2. 合并 execution 与 analysis 的廉价失配检查；均可能命中时执行一次依赖发现/签名，用同一结果判定两份清单。解析与保存复用该快照，不再各自 BFS 全文读取。
3. 先 P1a 让校验/保存复用同次事实，再 P1b 合并冷解析读取；内存 memo、磁盘 envelope 和冷解析共用原 descriptor 核。原签名仅 path/mtime/size，同会话 generatedAt 免扫和 memo 不能充当内容验证；要拒绝同大小同 mtime 修改，须记录已读 bytes 摘要并升级清单。single-flight 按完整作者输入合并；末个等待者撤销后停止领取/回填并 join。保文件数、单项/总字节和 deadline 预算，不声称可抢占阻塞读取。
4. 采用前核版本/资源 revision，重建当前 grants；源变动或截断走保守原重算/风险档位，不用成功缓存掩盖未知。
5. 首批保留 `await saveWebRuntimeCache`，保存消费同次签名；await 不阻止 actor 重入，同 key 旧保存不得覆盖后继版本，删除不得被迟到回填复活，沿原 owner 轻量核提交 generation。各清单分别原子发布，双文件不是整体事务；两者错配/缺失各自拒绝命中。旧“编码/写盘后移”屏选已否决，不能用后移 0.9–4.5ms 的历史局部数值声称 App 收益或强行新增队列。

**反例：** 跨启动仅一份清单命中、include/JS/CSS 依赖新增/删除、同大小修改、扫描中变动/截断、overrides/语言变更、书签撤权、A/B 交错与旧保存。缓存不存 grants；冷暖产出的 descriptor、payload 和档位须一致。

这里的来源是本请求已批准并持有租约的具体 folder/dependency generation；库发布新版本不强迫仍合法的旧版本请求改读 latest。快照自洽检查不能被表述为已核 canonical 最新版本，租约也不认证外部改写后的字节。当前授权仍在最后 await 后沿原 owner 重建；派生缓存发布失败不改变产品输出事务。

**P1a 实施修正：** 作者输入不仅是 entry 依赖，还包括 record/property-source 项目字节及 `sampleStructure` 实际消费的顶层目录名；跨根同名文件保规范来源身份。P1a 的单轮签名不等于全链文件只读一次，属性判定和冷 summary 仍有独立读取；其间观测到来源变动必须拒绝当前候选或至少拒绝回填，不能把解析 B 标成摘要 A。临时 FD/目录收据只用于变化检测，不持久化，不替代 P1b 对实际解析字节的绑定，也不能宣称未知文件系统的原子快照/所有外部改写已证明。派生发布先在锁外写唯一 staging，锁内只核 generation 并最终 rename；删除共享该边界，在途 ticket 结束后 slot 退出，不让主线程等待整份缓存写盘或积累历史 record 槽。

属性定义只需来源 ID、具体目录和可选 project URL，由原 property-source owner 返回轻量值；已 pin 的依赖版本不得重建整份库记录或改用 latest。目录存在而缺 project 的 inferred HTML host 仍保来源身份并返回空定义；目录消失则拒绝来源。无 pin 的旧兼容分支继续复用原 latest→Web→Scene 发现及分类，不以简化 HTML 检查近似递归依赖；其旧扫描成本仍在，不能称所有主线程路径均已免扫描。

**P1b 实施裁决（实施前记录）：** 在原 service 内捕获具体 own/property-source 角色、规范路径、同次项目字节、原入口 resolver 实际选择及候选类型事实、依赖状态/sourceKind、顶层目录名与完整有序 `languageKeys`。原 JSONDecoder 声明入口与 JSONSerialization 属性解释消费同一份 Data，转换为 Sendable typed facts；不跨 actor 传裸字典，不以缺项为由重开作者 URL。实际 localization/definitions/display resolver 显式消费捕获的完整语言序列；memo、analysis/runtime 清单和 flight 绑定同一完整作者身份，不能只补 flight key 而磁盘清单仍漏依赖态或入口类型。清单升级拒绝旧版本，不只按首选宿主语言合并。

真实 `setAsWallpaper→canLaunchDownloadRecord→webLaunchEntryIsValid` 前门只核 record 已选入口的存在/普通文件类型与依赖可用，原准入 memo 使用 entry-only key，不选 property source 或同步 JSON 解码。声明入口和 fallback 合法性只在后台 capture 沿原 resolver 解释，失败仍返回本次准备反馈；不能让前门另一套 preferred-only 检查抢先否决原 resolver 的合法 fallback。同步 UI miss 同 turn 复用已选轻量 source，不能为签名与解析各发现一次。减工探针若未覆盖此前门，报告仍明确该范围。

缓存认证与冷 summary 是两个逻辑遍历、一个读取叶核：现签名最多120文件、单项4MiB/总16MiB/200ms，summary 没有文件数上限，已有205文件反例。认证期只保有界精简事实供 summary 复用，后续 summary 流式归约并释放 bytes；保原128KiB前后片段、≤1MiB service-worker 全文补扫，全文签名发现的中段引用不能扩张 summary 的原连边。超认证预算仅失去 cache/flight 资格，不能截断冷解析或让200文件之后的风险消失。读取内部继续核 FD/来源稳定与取消，退出 capture→parse→adoption/save 之间的重复打开检查；捕获 A 后磁盘变 B，解释仍消费 A，不声称 WK 页面资源或文件系统获得原子快照。

memo、analysis envelope 与冷核只提供同一种纯作者 parse product；不共享含当前 binding/preconditions/grants 的整份 descriptor。捕获的 preset/pathlike facts 经原 assembler 传到 preconditions、payload、bindings 和最后 grants；最后 await 后仍逐调用方取得当前 overrides、书签/安全域及路径存在性。同步 UI 走同一解析/读取核但不做启动认证或给未经认证结果授持久内容身份。

在原 service memo 职责内按完整实际消费事实摘要、own/source 角色路径、entry/root、完整语言序列及 parser/schema 合并在途纯解析；不完整身份不合并，完成后不另留一份免扫描缓存。每个等待者有独立 waiter identity、publication ticket 和当前投影；一个取消不影响其他等待者，最后一个退出关闭 admission、取消并 join producer，旧 flight 只能按自身 identity 清理。每个异步调用方（包括 preload）在同一无 await 的 actor admission 段选定实际来源、拒绝 record/source/dependency 正在删除，再沿原 library registry 对实际 managed roots 并集取得 lease：包括 own/source、entry/root、项目来源及有序授权 namespace，覆盖独立 capture worker 的 await/join 与后续 flight join；不能仅用 record 的 dependencyHost 字段近似无 pin 来源，或遗漏 own props 配 host entry 的组合。

产品外层 record lease 保早段准入；成功准备把实际 roots 的同一 token 随通知转交原 renderer，按原 ACK/退出释放，不让新 lease 在准备返回后消失、消费端却只持旧 record 双字段的 lease。失败/取消与无 renderer 的 preload 则在自身读取/join 后释放；纯 product、cache 和 flight 不持 token。采用/保存继续核已捕获来源的删除状态；legacy 无 managed identity 时不伪称已获租约保护，保原兼容失败边界，不另建 legacy lease registry。

产品 `setAsWallpaper` 在原 intent owner 保存准备 Task/generation，新选择立即 cancel 旧准备；本地 Video、静态图片与 stop 不经过该入口，故原 Manager 的 `beginPlaybackIntent` 在推进唯一产品 epoch 后，通过 App 注入回调撤销 service 的准备，不能只等最终 `isCurrent` 拒绝结果。Web 先取得原进程预备意图，再捕获 service generation，避免被自身 epoch 推进判旧；入口早退仍先撤上次准备。旧 Task 直至读取/flight join 后才释放自身 library lifetime，preload 以自身 lease 保留独立有效 waiter。同步取消入口不阻塞主 actor 等待，阻塞文件读取仍不能立即抢占；回调不建立第二产品提交或跨引擎协调器。 安装点保原 Manager 初始化时序：在既有 mute migration 之后、coordinator/configureRuntimeSwitching 的恢复播放之前设置；不能为接一条回调把 Manager 提前到 Service/桥接装配前。

原 preload 的 live-resource 跳过策略不在 lease 外解析作者定义：沿原 overrides/bookmark owner 只查已存书签存在或绝对路径 override，已知状态即保守跳过，否则进入统一 admission/capture。路径形态 text 可能因此少一次可选预热，真正选择仍按实际定义准备；不扩大 live 作品的后台扫描/授权或另增 author-only preload、缓存发布策略。项目/依赖读取先非阻塞打开并确认普通文件，特殊 FIFO 不应让取消后的 join 永久等待；普通阻塞磁盘读取的不可抢占边界不变。

验收必须编译真实捕获/解析/装配核，覆盖 A→B/ABA 后仍消费 A、own/host 同名角色、pin/no-project/声明入口与 fallback、次选语言变化、205 文件及前后片段/中段连边反例、认证预算不影响冷播、override ABA/当前 grants、单/末等待者取消与旧 flight 不清新 flight；原 CAS 保存/删除门保留。缓存核替身门不能代替这些真实解析和产品取消入口行为。

[第二批实测](wallpaper-startup-p1-p2a-2026-10-24.md)未证明 P1a 整体提速。P1b 以收敛解释输入和退出临时重复检查为边界，不围绕轻输入签名继续做低收益微调；宿主创建、页面 ready、snapshot 的实际等待由 P5 原职责处理，不能跳过可见和提交检查换速度。冷条件 selection→hello 可包含与 service 准备重叠的空 daemon 等待，不能把 selection→launch enqueue 全归解析/缓存。

[第三批结果](wallpaper-startup-p1b-d1-2026-10-24.md)：三文件冷服务核读取API操作10→3/返回800→190B，不代表物理IO或完整启动比例。v3轻Web五组C0/C1/W0中位899.851→874.380、871.188→901.436、270.620→274.718ms；C1增3.472%，各条件噪声门未全过，整体卡不通过。v2原C1增约179ms与后续基线自身漂移均保留，装配顺序纠偏未证因果，不称已修复。停止围绕轻输入重复微调，后继按已证职责推进。

**退出/重开：** 同输入不再重复发现依赖且输出相同即闭合职责；耗时另验。只有新产品计时证明保存仍占关键路径，才在此处修订后移设计；需原 owner 的版本 CAS、取消与退出 flush，不恢复独立保存队列旧方案。

### P2：Scene 一次安全挂载，按需读取，退出全量解包

**P2a 基础切片：** 先在既有 Reader 内统一 Data/FD 的一个索引 codec，FD owner 提供有界 table 与同一打开来源的读取/验证。现 extractor 复用同 FD 的兼容 snapshot，继续全包/entry 摘要及原缓存损坏反例；此时仍整包读写，不认领按需 IO 或 P2 完成。新按需接口的 table/entry 分配预算显式传入，不能未经依据把新阈值套给旧产品而收紧合法输入。验证读在本切片只有 CPU 反例消费者，须随 P2b 接入 ResourceView handle/可信 receipt；若该迁移停止，则撤除未采用接口，不能长期留下第二资源入口。

**P2b 接线顺序：** 目录 backing 的消费迁移可先独立推进，保留旧产品准入与 extractor：D1 在原 ResourceView 增 Root 自持的 read/sibling handle，先迁 shader raw stage/source graph，保持同根选对、大小写/歧义、隐藏路径精确探测及原读取预算。取消/来源变化/完整性失败沿 graph→Catalog→SourceFacts 传递，不能被 `try?` 降成 missing 或转读低优先级根；原 extractor facade 对已观测 `Reader.sourceChanged`/取消也须穿透，不能变成 failed report 后读取旧展开目录。普通缺失/无效可选作者内容仍按原局部结果。D2 再迁结构、模型/material/puppet/effect 等字节核。此顺序只解除消费者对 URL 的假设，不提前认证 legacy 来源或启用包读取。

**D2 结构边界（原实施裁决继续有效）：** Catalog沿ResourceView唯一选择核，以同份Data解释完整作者namespace中的model/material/puppet/effect；SourceFacts的MDL metadata保完整格式验证。model→puppet、effect→material保原全局引用优先级，不能强制改成同Root sibling或缩为静态场景引用。选中源失败不重选低根；typed sourceChanged/invalidHandle与取消穿透，普通坏内容局部，不新增格式上限。实际before与限定结果归[D2记录](../../scene/history/scene-startup-d2-2026-10-24.md)。

**消费迁移与剩余边界：** TEX的source identity、cache/candidate与视频声明及同Root sprite sidecar/直接ImageIO已按D4接线；目录字体按D5沿原owner接Handle/Data，不扩作者来源范围。Sound已按D6沿同Root流式写原私有文件并随实际AV asset持有；D7已实施其余四支视频的私有写域与退役交接；D8接聚合磁盘预算及可信package认证桥，实际managed入口已有资格，但不由此关闭seek门、旧无ref完整准入与有限兼容成本或完整P2验收。inline脚本由Document同份Data解释，当前仅builtin模块导入、无作者.js读取叶；LocalStorage属可写状态，不纳入作者包。轻量记录分类/工具的Project URL适配不为迁移强建整图索引。

**D3 播放/粒子/完整模型边界（实施前裁决已落地）：** SourceFacts先捕获并复用唯一loose Root，再以自持Data解析Project/Document；保derived包优先级、package→loose字面first-existing、隐藏入口和选中坏内容不fallback。粒子定义退出独立目录枚举，在原Host throwing prepare中沿ResourceView构图，硬错/取消在候选发布前返回，LaunchContext携带图供surface构建自身runtime/GPU状态；普通坏定义仍局部。完整MDL/puppet同份Data供原mesh/rig/animation/attachment核，保完整验证、GPU预算/回滚，不新增owner或格式上限。目录probe/open保raw路径及真实中间目录语义，payload读取前校验FD实际入根；不能先折叠dot再读。D3源码、审查纠偏、CPU/GPU及固定五组产品结果归[D3记录](../../scene/history/scene-startup-d3-2026-10-24.md)，读取边界完成不等于性能卡或P2b完成。

**D3 路径选择约束：** 粒子原primary lookup的invariant `lowercased()`不能替换为Root默认`localizedLowercase`。同一captured index生成保首到次序的invariant投影；定义handle精确读取选中原始路径，含POSIX反斜杠文件名，不能再当Windows分隔符改写后重选。共用原literal open/FD入根核，不恢复文件系统枚举，不改变其他消费者/global/stock规则；跨locale、相邻反例及冲突次序必须对照实际before。D4起定义图携带已选纹理Input与Root引用，仍只是同launch准备结果，不能标作跨launch纯产物缓存。

**D4 目录纹理边界（已实施，限定行为通过、正式性能卡未过）：** 同批闭合TEX/直接图片的显式来源、读取身份、cache/candidate、自然尺寸/opacity及嵌入视频声明；不是只把`Data(contentsOf:)`换成包装。目录Input沿Root原FD读核返回自持bytes与同FD FileIdentity；currentIdentity取得相同revision字段的当前stat身份，metadata不替代内容摘要或可信receipt。cache命中只核当前身份，不重复读payload，来源变动不能把旧key贴到新bytes。纹理输入明确区分已选Root handle和独立外部URL，不从任意URL猜Root，不为包伪造file URL；目录期candidate仍可用真实文件identity，package generation/digest分支在激活时同步闭合，不预留无消费者原型。Loader继续唯一解析/解码/缓存/GPU owner，prepared source携带输入与身份，同份Data/CGImage供尺寸、alpha、多purpose和视频payload；保持现有预算、purpose/device隔离、负缓存和GPU发布/失败重试。Root校验与原取消沿throwing输入API传播；已有prepare/worker/Host边界上抛，surface/particle/deferred则由原失败/资源事务拒绝最小不安全texture/provider，保旧完整输出，禁止以nil触发另一根或内联URL重开。必要的typed失败只作原结果运输，不新增全局错误状态owner。

D4实际对照若出现资源准备回退，先按原阶段事件和同输入CPU探针定位，保留失败原点。Root的同次路径校验只解析actual Root一次，空子目录边界复用它；metadata直接stat该次已校验canonical candidate，再完整重验Root与candidate，保前后路径身份一致。它是调用内复用，不缓存跨操作的文件系统事实，不撤来源/FD/取消检查；证明该局部减工后才进入新候选构建和一次固定对照，不重复旧候选直到变绿。

D4的DirectImage短值保留原metadata先行/后台GPU重叠：header只解释同次Data而不提前decode；同一纹理操作/多purpose复用请求短值的Data/CGImage。跨metadata→GPU相位留存完整encoded bytes必须获原decode budget的source lease，GPU循环领取时先从排队集合移除该短值，不能把拒绝预算的decoded CGImage留到整批末尾；deferred队列只存input+identity。预算拒绝跨相位留存时只保小metadata，GPU阶段以原expected identity重新捕获，明确不认该条件全链只读一次；优先保内存/退出边界，不以无预算字典追求读次数。

普通纹理继续candidate/template先、每项遍历全roots；粒子继续primary全candidate invariant→全roots localized→原字面stock→builtin，不能统一成root-first。选中的indexed路径及同Root sidecar保raw路径，sprite的`-json`仅在原particle动画消费者应用，不扩大默认语义。外部用户属性继续原security scope/冻结资源/取消与revision事务，不纳入作者Root；合法外部URL适配仍属原Loader，不能变成任意作者资源后门。验证须覆盖真实前驱/当前输入结果、source change/根转向/alias/取消、不fallback、缓存命中/evict/低预算/多purpose、sprite比例、视频声明及原provider/旧active门，再做冻结签名构建与隔离代表输出和同条件冷暖对照。D4时点字体/独立AV媒体与可信receipt仍后续，字体目录接线现归后文D5；D4目录迁移通过也不激活package或认领启动收益。

D4实际D3-final前驱/当前身份、限定回归、首轮W0超预算及五对资源增量归[D4记录](../../scene/history/scene-startup-d4-2026-10-24.md)。目录迁移和调用内减工不等于性能验收；停止stat微调后仍保留残余资源代价，后继P2b/P3须再验。


**D5 目录字体切片（已实施，限定验证通过；不认启动收益）：** 原FontResolver保系统别名、缺文件时known stock与坏字体Helvetica的区分，以当前ResourceView中原package Root替代cacheDirectory重开；exact/literal选取保旧路径规范和大小写语义，不借全roots搜索扩大loose/custom-stock。已选作者字体沿Handle同次自持Data→CGDataProvider→CGFont，普通选中内容缺失/不可读/坏字体仍为invalidBundledFont，不转stock；来源变化、无效handle、路径逃逸与原取消穿透。初始加载由原TextLoader按层拒绝不安全文本；动态worker失败走原generation finish(false)，保旧完整raster，不能try?降成默认字体。默认、alias与App内stock无需作者Root，不新建字体cache/资源type/全局失败owner。

D5修复动态文字删除/重建的generation ABA：原State用有界单调发行序号，unregister/reset不复用，耗尽拒新保ready；Store保单在途/追最新、失败不publication，CPU退出随后由D6接回原链。实际D4-final对照、改名/坏选中源不转根、CoreText/raster正反例、构建及两输入产品结果归[D5记录](../../scene/history/scene-startup-d5-2026-10-24.md)。高噪声与字体呈现不确定性保留，不外推无回退、启动收益或可信package。

**D6 声音物化与在途 CPU 退出（已实施，限定行为与产品资格通过；无性能验收）：** 独立 Sound 是剩余作者 AV URL 消费者；沿原 Host 串行 prepareLaunch、Program、Registry 迁移，不新增播放器、队列或全局缓存。ResourceView.Root 已将 readSnapshot 的同 FD、入根/路径与 FileStamp 前后核合为唯一64KiB chunk读取核；snapshot仍保一次预留与自持Data，Sound的Handle流式sink不整份载入内存、不按diagnosticPath重开。原SceneVideoOwnedFile增加作者Handle入口和正确音频suffix，排他创建0600私有文件，完整读取/校验/close后才交付，取消/源变化/写失败清唯一partial。已有外部video的1GiB/30s政策不扩成作者音频上限：Sound原来没有bytes/duration上限，本批仅把单次分配限为64KiB并约束到初始文件长度，仍未建立磁盘聚合预算；package暖资格及receipt物化预算在后继激活前单独裁决，不能据本片宣称全部资源预算闭合。

Program保candidate-first/roots与原格式名单，首选中即固定：loop/single不因选中后copy不可读而试另一authored path，random保持原选中槽位、顺序/分布和Binding/脚本target准入。选中的普通missing/unreadable以typed unavailable保留槽位，由原Registry局部失败；不伪造URL、不删除Binding、不改为低优先根。sourceChanged/invalidHandle/逃逸及原取消穿透原Host候选失败，保旧active。原compile局部共享同源完整file lease即可去重，不建长期cache；Host传显式App可写输出目录，不让package backing伪造作者file URL。Registry loop模板、single/random换曲均由原Source的同一item工厂建立AVURLAsset(private URL)，file lease随实际asset保留（含looper借用），避免Program/Source先退后文件过早unlink；AV工作只读该私有快照，父来源lease不等待native codec终止，也不把GPU/资源ACK说成AV drain。

字体沿原Store锁同时关闭准入、reset原State和串行queue尾fence；schedule入队须与关闭同锁线性化，阻止next/解锁间隙在fence之后入队，主线程不wait。Session所有surface拆除（含重建）先关闭对应Store，原retiringSurface group等该queue、GPU及已有export都terminal后才退出，makeCommandBuffer失败也等字体CPU。整体Host停止继续原stop与Session聚合，并合并原launchPreparationQueue尾fence；没有Session也不能提前完成，DEBUG沿已有common/modal RunLoop投递，Bool保原GPU语义。共享baseImages的deferred作者读取已在原deferredQueue接入同锁关闭/入队与尾fence；全clearContext在清launchContext前把该owner的queue尾纳原retiringSurfaceDrain，保先stop后drain（如拓扑重建失败）也不丢在途工作；不另留一个pending资源owner。单surface重建不关闭共享owner。先关准入并等字体/共享deferred CPU终态，再提交全停surface GPU barrier，避免后台准备在barrier之后又提交工作。这些只是加强原release时点，不建第二资源/退休owner。失败候选继续复用原whenRequestResourcesReleased fence；此处只结算已迁字体、deferred和Sound所在launch队列，不能代替后继package激活的完整来源lease资格。

**D6物化存储纠偏：** Sound曾写入展开根，extra-file校验会触发重建并越过活跃AV file lease删除它；普通failed/missing包也能进入合法loose，故outputURL父目录不能代表App缓存。最终Host显式传原extractor.cacheRootURL，不推断写域或忽略extra。实际Reader/Extractor→Root→Program→AV门验证成功/failed/missing三种来源不写作者根、强制重建不删借用，最后asset释放清理；中间parent推断候选及全部失败归[D6记录](../../scene/history/scene-startup-d6-2026-10-24.md)。Sound范围已闭合，其他视频随后归D7，不能倒改证据范围。

D6以实际D5-final为before，原Sound/字体/deferred最近门与真实Root→私有文件→原Registry、CPU退出反例已限定验证；134方法含新跑58及按实际依赖资格复用76，并非同批全跑。最终签名与固定两输入60App/80请求有资格，六条件噪声门均未过，无性能验收。原构建/无效输入、存储缺陷版本及慢点完整归[D6记录](../../scene/history/scene-startup-d6-2026-10-24.md)；D4残余、字体呈现不确定性、Web C1与整体卡仍开放。

**D7 视频私有输出与 AV 借用（实施中，尚未验收）：** 余下四支视频写入（初始外部用户属性、live 属性更新、material TEX、普通 layer TEX/重建）仍把作者展开目录当作原 SceneVideoOwnedFile 的输出根，会污染 extractor 精确文件集合，并在重建时绕过仍活跃的 file lease 删除路径。沿唯一 Host prepare 捕获原 extractor 的 App cacheRootURL 为不可变 `privateMediaCacheDirectory`，显式传过 LaunchContext 到四支既有消费者；作者 `cacheDirectory`/ResourceView 读取身份保持原合同。MetalView 的该参数只用于输出与日志，改为明确私有输出含义，不另造缓存 owner、不让 extractor 忽略 extra、不从作者路径推断写域。

Video Source active期始终强持ownedFile，唯一退item处是终态stop，deinit必调stop；Sound在active期会换曲/looper退item，不能套同一交接时点。原SceneVideoOwnedFile只统一 `retainForLifetime(of:)` 关联操作：Sound保D6创建实际asset时pin；Video保整个active构造/prepare/seek原路径，在首个有效stop中、任何cancel/replace/nil前，把仍强持的确切file交给当前item.asset，再释放Source引用。初始化失败在创建item前退出；WebM未安装便stop时仍由worker/result任务持file且原ID拒迟到安装，已安装则走同stop交接。重复stop由首次交接覆盖，不新增播放器、registry、clock或AV drain。

初版 `makeAsset()` 统一构造候选及恢复URL构造但在install读取asset的候选，原样seek对照出现before通过而候选不同fixed-retry case失败，均作阻断保留；恢复构造未证明因果。旧/新×0/80ms接收延迟×两个discard场景的固定8case诊断全通过，只证实anchor先catch-up，未复现no-target，不能据静态猜测重写seek/seed算法。现裁决缩到上述退役交接：Video除stop交接外与实际D6源码逐字等同，验证该事实并重跑真实AV借用、seek/WebM及原像素门；尚未认已定位失败根因或整体无回退。

最终退役版真实material门3方法通过（27项存储/借用与两改名GPU变体各35项事实），WebM和其余视频命令5方法通过，Source仍存活时最后asset/file释放、私有池为空；原seek父门仍有discard-after失败，不能称整模块通过。另固定4case失败后单次观察已在实际D6前驱的discard-before捕到pending seek/未接纳完成、rate0/playerTime6/无cache，fresh prepare同样无新帧；两版其余3case通过。该证据确立旧版也会失败，但未解释候选此前discard-after，正式seek稳定性/性能资格继续开放，不因窄媒体门放行。

冻结最终Debug构建349.731s通过，全部构建来源前后一致，专用Startup身份/Developer ID深严格签名通过。单列一轮真实入口pilot共6App/8请求全部正常呈现、退出且生产偏好不变；观察到相同1882B MP4真实payload，before位于hex展开根内，候选位于原App缓存根的私有池，作者输入前后不变。该pilot带只读路径观察，时长不用于正式统计；未执行预定五组，未认提速或整体回归通过。最终限定9模块去重114方法为113通过/1失败，原seek父门失败保持阻断；不把构建、文件放置或局部媒体门替代它。

验收仍用冻结D6-final源码/App：真实Root/Extractor→Registry/Source的自建MP4/TEX及外部视频，核普通重建复用、强制展开重建不删旧AV借用、Source仍存活时最后asset借用释放删除文件、failed/missing package合法loose不写作者根、源变化拒绝及像素保持。强制重建后旧声明必须拒绝。文件即时删除断言移到真正AV借用/临时引用释放后，stop即时拒帧和原超时/像素断言保持；不以销毁Source掩盖其自持item。补共享关联影响的Sound最近门、冻结Debug构建及输入资格通过后的同条件冷暖比较。此片不实现聚合预算、可信receipt或package激活，不据窄门认整体性能通过。

原 library owner 仍须捕获与具体 lease 同源的 launch-source DTO/receipt，经原 Scene 请求及 load IPC 传入；这是 package backing 激活的硬前置。结构、shader、纹理/模型/字体及媒体都完成迁移后，统一切换 package backing 并退出 extractor。handle 的 read/sibling/materialize 仍由同 Root 执行，不为未迁移消费者伪造 URL 或自动物化整包；bundled stock 的共享 Root 不持请求取消/错误/lease 状态。旧属性 owner 的 `preparedProperties` 裁剪边界保留，其在途来源工作补同一 admission/lease。D1–D6的限定验收只结算目录读取、Sound私有快照与已迁CPU退出，不记为按需包IO、所有媒体退出或P2b完成。

1. 将 PkgReader 的产品入口改为已打开 FD 的 header/table 读取；检查索引大小/计数、完整路径、range、别名冲突与来源 receipt，避免为读索引加载全部 payload。坏索引不进入资源视图。
2. 在原 ResourceView 中接 package mount；向 Scene/project、Catalog、模型、shader/include、TEX、脚本交同 generation handle。外层 project.json 先按 receipt 的 loose-file digest 取得自持 bytes，再解释 derivedPackage→scene.pkg 的既有选包规则，不能先按 URL 解析后才认证。索引/receipt 错误沿 typed 失败退出受影响来源，SourceFacts/旧 extractor 的 try? 或 report 不能把它吞成 missing 后回落 loose/stock。读源与 App 自有可写产物目录分开，不把作者根改作 cache。Texture source identity 增 package generation+entry digest 分支，不伪造文件 URL。shader vertex/fragment 保原同 source-root 规则；所有引用仍由原 resolver 排优先级。
3. 逐类迁移读取核，先跑 PKG 与等价 loose 的正反结果；字符串/模型引用、大小写冲突、可选缺资源的现行为保留，完整性失败与普通视觉缺失分开。sprite 的 `.tex-json` 尺寸 sidecar 必须沿原 texture 的同 root sibling handle 读取，保粒子动画宽高比；直接图片的尺寸/opacity 改用同次验证 Data/CGImage，不为 ImageIO 字节消费者落盘。
4. 接入媒体 URL-only 流式物化桥；先预算后分配，校验、取消、single-flight、部分写入与 provider pin 一并闭合。字体保字节入口；实际媒体首帧与字体输出不能由“已有 URL”替代。新物化 worker/waiter 进入原请求的 CPU 退出与 GPU drain，join 完成才沿 `launchResourcesReleased` 释放父端 lease，不能只等 GPU 或提前清 launchContext。
5. 修改 SourceFacts 和 Host 输入，移除 `packageReport.outputURL` 必需条件；挂载合法 namespace 才是资格。迁移期仅允许开发/测试显式选择新旧 route 作对照，产品每请求只选一次来源，失败不静默回旧路径绕过安全检查。
6. 同输入验证后删除包括属性准备在内的 extractor 产品调用、旧 marker 信任和重复扫描；工具专用解包可保留。Catalog 当前全量准备作者模型等，不能未经证明缩成静态场景引用而丢动态创建能力；只按实际 consumer 证明少读。receipt 表受原 metadata/IPC 预算限制，可用父端批准的 manifest 引用+摘要，引用路径本身不授信。旧 cache 沿原预算/租约回收。

**反例：** 截断索引/溢出 range/路径逃逸/规范化冲突、索引与 receipt 不符、实际 entry 同大小篡改、未用坏 entry 后续首次消费、读取中替换/截断、取消/并发物化、来源删除/更新被 pin、媒体/字体重新打开及失败后旧 active。

**运行输入资格：** P0/P2a 的普通复制记录属于 legacy；缺可信 receipt 时仍按本轮来源完整准入，不能靠 mtime/size 或复制 marker 省掉整包认证。它们可验证兼容与退化边界，不能单独支撑 managed 暖挂载收益。后续在隔离库沿现 library import/commit owner 入库并由 receipt owner 核验发布，或对真实 managed 原 commit 完整核验；两者均保原始媒体只读。

**receipt 前置核查：** 现下载与 v1 迁移虽收敛到同一 copy/hash 核，v2→canonical 重命名及旧 canonical/legacy 不经过它，不能统一标记已认证。原 commit 只新增有界 receipt 引用/摘要/大小，完整表仍由原 library generation owner 发布与回收，不内联撑破既有 marker/metadata/journal/IPC 预算。保 copy 核的 loose-file 摘要；包导出沿原 Reader 单 codec，从同一 pinned FD 取得 table，并把整包流摘要与 copy 已认证值核等，才能把各 entry 摘要归给该包，不能第二次打开 B 后标成 A。暖请求核期望 header/table 与实际消费 entry，不读未消费 payload。


**D8 receipt与package纵向切换（实施中，尚未通过完整产品验收）：** 本批最小结果为原入库事务产生可信receipt，经同一实际版本lease和原请求/IPC，接入原Root，再被播放及属性SourceFacts实际消费；仅发布sidecar、增加DTO或工具原型不算闭合。新下载/v1 copy核保留已认证的完整逐文件SHA表，tree编码/排序与旧核共用。原library事务与Scene admission共用Core/SteamWorkshopStorage中的同一底层descriptor/inventory/hash机制及值DTO；不新增发布/租约owner，不让Core反向调用Modules或复制树摘要算法。原copy创建FD当前为O_WRONLY，包认证需显式取得本事务自有可读写FD，再由原Reader复制FD并用pread；不得重开URL冒充同源。导出以同一顺序字节流更新整包及覆盖range的entry hash，核copy已认证包SHA和同次raw header/table；索引保原raw entry/range，不以lookup归一键替代认证身份。

完整manifest放原generation内排他创建的App-owned sidecar，随原目录事务移动、回滚与GC；author表排除本事务新增的marker/sidecar，不能覆盖作者同名文件。Commit新增可选的小引用（schema、受控相对路径、bytes、SHA、stable storage identity及原tree digest），layout版本不变，canonical/retired/job恢复/metadata enrichment须保真。原publisher在使版本ready及恢复时核实际sidecar，原完整Commit/marker和metadata CAS不放宽。sidecar首批编码预算4MiB、累计entry hash工作8GiB，均复用既有量级；原library 8GiB/200k项/8MiB路径、Reader table16MiB/100k项及marker16KiB、metadata4MiB、journal12MiB、IPC8MiB/256条不扩容。overlap工作先计费；sidecar也计原磁盘/retained预算。仅签发前的暖资格超预算或受控名冲突可不签receipt并明确走完整准入，不能把已知原摘要不符重标为ineligible。

**旧来源纠偏：** 现extractor仅hash当前包/比对派生缓存，未核原Commit的tree digest，不能称旧managed完整认证。旧managed无receipt仍携原expected tree逐请求完整核验；D9沿已认证loose Root的selected handle，在同一path/FD fence内以approved FileFact核整包/table/entry事实，合资格即临时挂包，仅明确格式、namespace或预算资格不合格才走原authenticated snapshot/extractor。随后消费的project、包及loose作者字节仍绑定该次原树预期；不得降成unmanaged、当前字节自签或每次悄悄收养新内容。无原commit的unmanaged另保原兼容边界且不授暖信任。已有v3不做metadata-only附ref；D10仅在原预准入内按需copy至新generation并由原publisher/CAS出版，未升级来源继续显式完整核验；active/busy与不合格来源不因该接线取得暖信任。present ref的schema/路径/长度/manifest/tree/table/消费entry不符均拒绝当前来源，不能catch后转extractor/loose/stock。引用只运输父端批准的事实，不新增路径授权。

**D9 旧managed完整准入后临时挂包（已接线，本批限定验证已结算）：** 原tree认证已持有原Commit预期，仍把所选包转整Data、解包、再核展开cache是可避免的重复。先不扩v3整库后台copy，也不把原swap journal改成原地增ref协议：按需新generation出版会触活lease拒替换，首次另有copy/hash成本，nil ref还含已按预算不合格来源，不能每次请求反复copy。D9当批未做持久迁移；当前限定按需升级见D10，active/busy与不合格来源仍保D9，不以本片关闭P2余项。

本片保原父端source/lease、播放及属性worker/join；无ref旧managed仍逐请求先完整核原tree，随后只由已认证loose Root实例从其自有handle取得approved FileFact。在同一原path/FD fence内打开一个Reader，沿原exportReceipt核整包SHA、table和各entry；只有整包摘要匹配原FileFact，才用同Reader建立原PackageBacking。新增明确的临时完整认证入口，现有持久receipt工厂仍要求非nil ref，不能伪造ref或接受caller自签fact。仍是full-tree后第二次整包stream，不宣称单遍或永久暖信任；本片减掉全包Data/entry整体Data集合、展开写入与暖展开cache复核，当前active旧版本也无需swap或先停壁纸。

暂态facts沿原Reader table/count、8GiB累计entry工作和4MiB事实编码预算，后者只限selected PackageFact，不等于完整manifest可发布或native RSS上限。编码计费核在原SceneSourceManifest值层共用，原publisher继续保完整manifest最终编码/空间预算。仅明确的格式/namespace或预算资格不合格回原authenticated snapshot/extractor；来源变化、digest不符、无效来源及原取消必须上抛，present ref路径完全不降级。未选中的坏pkg不得阻断合法所选pkg。验证原合法/改名/等价目录投影、nil-ref与有ref边界、同大小篡改、捕获后换源、取消、预算/不支持格式合法兼容、unused坏包、warm无展开和真实播放/属性；以实际D8 App及源快照为before，冻结前后，不把小门或本片通过当持久迁移/完整P2完成。

**D10 旧v3按需持久升级（已接线，本批限定验证已结算；正式性能门未通过）：** D9每次仍完整认证作者tree并stream所选pkg。原目录同generation添加sidecar会让已捕获nil-ref的在途请求、属性worker或replay将其计为新增作者文件，触原摘要拒绝；仅加marker/metadata journal不能解决这一读侧过渡。外置receipt store又须扩可信定位、IPC能力、恢复/回收/容量协议，当前收益依据不足。本批选原新generation copy/receipt/publication，不要求活动旧版本立即得到持久信任，也不为迁移stop或移动active。

长期播放/属性lease准入前，原service按具体library/root/item与完整旧commit检查v3、Scene、nil-ref、当前metadata/marker核等、无删除/更新和既有稳定政策拒绝记录；先检查原protected/referenced identities，busy直接沿D9，不做无效复制。对同key的在途升级共用一次原copy-capacity工作及独立waiter，临时source lease只由MainActor持有并覆盖实际worker join，不跨actor伪Sendable。最后waiter取消须cancel并join，不能只清Task/token。App退出仅同步关闭升级准入并取消，继续原播放进程退出边界；不新增Task join-barrier或二阶段quit。真实AppKit证实terminateLater期间普通MainActor Task不及时推进，新增barrier会误拒已完成工作。复制仅写原incoming/非ready候选，原同步publisher与退出不交错；App进程真实退出才是其内worker/FD终态，不能称已join。无journal的孤儿incoming/非ready候选保不就绪并计原空间预算，由原24小时GC回收；有durable journal才由原publisher恢复，普通选择、删除与末waiter取消的真实join要求不变。清派生缓存不改变账号、下载或持久库事务语义。前端仍由原产品intent/property Request决定是否继续，不新增播放或publication权威。

原Transaction增加受控v3源入口：同一已打开源FD核完整旧marker、排除该marker的作者inventory/原digest并复制到新generation，所有实际作者文件仍须完整认证，marker/源Root在结束fence再核。保原可用空间/retained/copy预约、receipt 4MiB/entry工作与取消预算；不把v3伪装成v1或伪造下载凭证。只有有可信完整receipt的新candidate可进入出版；静态格式/namespace/编码/路径预算不合格与动态空间/占用不足须typed区分。静态拒绝可由原metadata owner保存绑定完整旧commit+policy版本的非授权结果，后续仅跳过重复升级，绝不跳过D9认证；busy、取消、IO/空间暂态不能永久记为不合格。message-only事务/文件错误（例如只读目标）不能剥夺旧来源原D9读能力：准备及静态refusal记录阶段仍持复制lease，沿原Authentication对同capture完整认证并保lease至实际worker join；出版已返回错误时，仅原journal probe明确无pending、同actor核完整oldCommit/marker及原physical identity仍在、并由原registry重新取得旧读lease，才可复用这次认证回退。await后再次核无pending和同capture；任何未知/待恢复journal、已变pointer、不可借用、取消、硬digest/source/Reader错均拒绝，不取代原publisher的回滚/恢复。不按错误字符串分派，不把这些facts当暖授权；合法旧来源才暂缓可选升级并继续D9。

copy实际join后清所有自身临时lease引用，再在同一service actor无await段重读当前root/完整commit/marker、删除/更新状态及其他引用；仅沿原publishDownloadedVersion的一次reservation和原canonical journal出版，不能外层重复beginReclamation。出现新借用或CAS变化即保旧版本、不等待借用消失；本次prepared candidate由原owner有界清理，不累积待发布副本。元数据详情补全保最新item字段；持久ref仍与新generation同目录随原回滚/退役/GC，不扩ref/schema/定位授权，不全库后台copy。成功后回原source admission取得新source+lease；属性Request和原共享产品准备Task在await期间保取消/身份；同ticket的属性重建还须以现有准备ID拒绝旧Task的成功、失败与取消结果，不能仅核相同epoch后撤新请求。纹理引用回调仍是原同步non-escaping调用，不造迟到异步语义。旧active直到原首帧提交才退出。

本批原库/service/前端最近CPU共94方法有资格，实际D9前驱与最终同flags Debug构建、真实D7旧publisher两库、一次M0和固定五组原产品请求均完成来源/出版/正常退出核验；M0包含首次copy/写入/等待，后继组固定实际新generation/ref。独立daemon两帧与typed GPU退出补充限定画面。五组C0/C1/W0均超原5%噪声门，只记录观察差异，不认正式提速；M0/原红/全部原点、完整认证及空间代价归[D10限定记录](../../scene/history/scene-startup-d10-2026-10-24.md)。active/busy仍保D9，媒体共享、原seek、峰值及完整P2门不随本片关闭。

**后继切片裁决：** 暂停receipt微调。[D11限定记录](../../scene/history/scene-startup-d11-2026-10-24.md)保一次A/A、原seek六门及完整配对摘要，不放宽门或重标D10。D12仅执行一次冻结源副本的原seek6因果child，原2秒/12秒及像素/texture期待不变，本次通过、未读失败observer，按预定STOP不重采、不改产品seed/clock/缓存；D7组合及D11首次target失败未归因；D17已取得ordinary候选的discard/同timing重试门通过，按STOP不改Source、不称seek修复。P5a入口审查确认现暖预备已覆盖spawn/AppKit/IPC，未证fresh Host/view能省关键路径，停止大drain/协议重构；P5b保持停止，不以暖复用冲销Web C1债。继续只选可证明减工或阻止候选能力回退的P2/P4/P6切片。

同一service actor准入段捕获具体root/完整commit/ref并取得原lease，再做任何异步属性资源准备；Shell通知桥、queued/recovery/replay与Scene load IPC逐层保真。原v2 child会忽略未知load字段，故保现协议版本的legacy兼容，同时hello显式报sourceSchemaVersion=1；父端按本transport generation记录/清理能力，任何managed请求缺该能力即沿原失败/回滚退出，不能发给旧child而失去认证。Client的保留lifetime匹配除root/recordID还须核该source generation，不能A token配B receipt。属性窗口每次后台准备也走同一准入，由原MainActor Request在await/join既有queue工作期间持opaque lease，worker只收纯DTO与取消信号，不伪标lease为Sendable。取消须传到读取核并等真实终态，不能清Request handle就释放、也不能取消WorkItem后丢失completion；成功仅保原preparedProperties纯裁剪结果及值witness，不留Root/FD/lease。managed memo须核generation/ref及实际解释输入，不能以roots.map(\.url)伪造package目录；不能独立验证时先不复用该memo。外层project先认证再由manifest namespace决定既有derived→scene.pkg选择，不能再按裸URL的fileExists选另一包。

原Root内增加package backing，目录/external继续真实FileIdentity；package用generation/package/table/entry digest的typed ContentIdentity，readSnapshot/readChunks/cache/candidate沿同一身份。完整namespace、隐式目录与literal dot/raw路径、localized/invariant排序和firstWins仍由原Root投影；package literal沿该namespace逐段exact优先、miss才取同Root的localized firstWins真实entry，隐式目录同规则，缺中间目录的dot遍历仍拒绝；纯目录保原文件系统literal语义。不把旧extractor白名单当完整namespace，不造作者文件URL。stock generic4按选中Handle provenance判断，raw shader按typed Root分组且保同根stage；分组相等与排序分开。纯目录route保原真实路径排序；managed route按原查找域package→loose→stock，再按typed source identity稳定排序，避免已退役展开路径决定新route。normalized重复identity须保目录原反例并新增managed同根stage/真实消费者对照；若发生能力回退仍作阻断，不能仅改expected放行。package candidate同步接入真实provider publication、generation/lifecycle及直接绘制叶；不得顺手把它纳入只允许外部授权文件的userProperty分支。Sound诊断不把handle路径转文件URL，Catalog不保假primaryRootURL兜底。

交叉审查补充两条真实消费约束：authenticated directory的currentIdentity在Loader缓存命中前须沿原chunk核流式核expected SHA，不能仅凭当前metadata复用externalFile或其他Root填入的缓存；不保额外Data或第二缓存。该路径增加loose/旧managed重复核验成本，性能对照须如实包含，后续减少读取必须同时保住认证分区。目录ordinary index继续原FileManager的skipsHiddenFiles/skipsPackageDescendants投影，不把完整manifest表直接追加进去；捕获后核承诺文件的存在、类型、长度和入根，消除可见项消失后落到低优先级根的窗口。此硬错仅针对已选承诺项消失、存在但未被批准的文件及摘要/身份不符；原本未承诺且不存在的shader等候选仍返回missing，不能把所有ENOENT/ENOTDIR都提升为sourceChanged而拒绝健康项目。package保完整raw entry表供literal读取，ordinary index只投影PKG能表达的可见命名空间：dot隐藏及公开UTType目录package边界；PKG没有文件系统隐藏flags，不声称等价复制这些额外属性。真实目录与package可见集、隐藏literal/ordinary/invariant及被缓存B污染的RootA均须有反例。

D8媒体预算裁决：聚合磁盘账本归原SceneVideoOwnedFile，覆盖本Scene进程所有并发私有Sound、外部视频、TEX MP4及WebM输出，初始8GiB沿原library允许量级，不借GPU/decoded账本冒充磁盘预算。已知长度的copy/MP4在读取或写入前预约精确输出长度，所有partial与已发布文件均计费；预约随实际file/worker/最后AV借用释放，失败清partial，不能按Source.stop或GPU drain提前退还。原外部视频1GiB/30s及WebM输入/packet/30s政策保持；Sound不新增单项格式/时长限制，但受明确的总磁盘准入约束，超额只沿原不可用source slot降级，不能转读作者URL或低优先级Root。

WebM原核是VP9 passthrough remux，输入长度不能充当AVAssetWriter输出硬上界。采用公开AVAssetWriter(contentType:)及segment delegate，在原writer内保sourceFormatHint、纳秒时间与单video track，分段借用bytes由原OwnedFile受控FD sink逐段先预约、后写入；framework不再直写URL，超过聚合额度即沿原准备失败退出并清partial。需用真实VP9验证fragment拼接后的AV解码、timing与seek，SDK存在API不等于该组合已验收；失败则本次writer切换不得激活。源Data继续原不可变捕获及现有codec预算，不另复制；AV内部workspace、segment回调bytes与全进程footprint须区分；D26仅补原夹具有限观察，不宣称磁盘账本覆盖native内存或最大输入峰值。worker若仅持自持Data/OwnedFile，预算随实际worker退出保活；只有仍读作者Root/FD的工作才需要延长原author lease并join，不机械延长到所有AV借用。

同layer/device跨surface的原Registry及同次Sound compile已有共享，不新增重复owner；跨次成功文件复用按下述P2b限定实施，不据此认single-flight或完整P2性能验收。先验证原事务发布/崩溃恢复/lease拒替换、PKG与等价目录的实际解释/纹理/字体/媒体结果、篡改与取消不fallback，再签名构建和真实managed产品播放/属性入口；合资格managed route不得调用extractor或创建作者展开根。隔离产品运行与计时还须读取原父端commit完成后的activeIntent.source观测（DEBUG报告admittedSource），与本轮具体storage/generation/tree及receipt摘要核等；不能仅因样本目录放有sidecar就认已走managed。观测缺失、null或不匹配的候选不进入managed统计。旧managed/unmanaged兼容成本与D7 seek失败各自保留，未解失败不通过重采、放宽timeout或改宽断言消除。

**P2b 已准入 package 音频成功文件复用设计（2026-10-25，先设计后实施）：** 当前单Host串行准备下一candidate时，旧active仍由Session/Program/实际AVAsset保活至promotion退休；同一generation的Sound编译会再次流读并写入私有文件，真实输入已选MP3为45,315,800字节。首片只消除此阶段已成功物化的重复entry读写，不推定其占组合模型窗的耗时，不扩到跨停播/跨进程常驻、目录、WebM转换或全Program缓存。

唯一成功表放原`SceneVideoOwnedFile.snapshot(from: Handle)`工厂，只为`packageBacking`以当前请求合法Handle取得完整`.package` identity；key含该identity全部字段、实际私有目录canonical路径及dev/ino、suffix与原DiskBudget实例。目录沿原单次stream，不为查表增加认证全读。表仅弱持已完成文件及完成writer同FD捕获的revision，不保Root/Handle/grant/lease/AVAsset；锁只管metadata与取得强局部借用，IO及取消在锁外。并发miss各自走原copy，不新增flight、等待或取消共享；dead项在查表时清除。

命中仍核当前来源身份及私有output完整revision（no-follow/nonblocking regular FD、路径/FD一致、dev/ino/size/mtime/ctime等），再检查当前取消。output缺失或改动只使复用miss并由当前合法Handle重建；作者sourceChanged/invalidHandle/取消必须原样拒绝，不能借旧文件兜底。miss保原readChunks核SHA、预算、分段写/finish/close与取消终态，prepare的实际identity须等key，只有成功完成和末取消检查后才登记。一个物理文件共用原Reservation一次计费；原最后Program/实际AV borrower释放才unlink/返账，弱表不延长寿命。

验收沿真实Reader/Root→两次独立Sound Program/Registry证明同代活跃借用可命中、一次entry读取/写入及一次预算、玩家独立；真实AV borrower单独保活与最终释放、source更改/取消、generation/entry/写域/suffix/budget隔离、私有output删除/改写/替换及首次失败不得缓存均有反例。先最近行为门与真实45.3MB条目叶成本比较，无有意义收益或寿命/身份失败即撤本快路；通过后做签名Debug构建、同managed输入实际切换/暂停/退出及同条件首帧对照。未闭合或噪声超门不授P7，不按测试数量认无回归。

**P2b限定现状：** [D19](../../scene/history/scene-startup-d19-2026-10-25.md)已接原OwnedFile弱成功表，真实同代45.3MB第二次Program准备0重复entry读写、单份预算并保最后AV借用；并发miss仍各走原copy，不是single-flight。32最近方法、最终Debug与30App40请求合格；6/6噪声失败及C1+36.978ms原点保留，不授正式性能。D20–D22已限定启动等待，D25无新可减重复工作，停止追因；不扩目录/跨停播/跨进程/其他转换，完整峰值与最终P7仍分列。

D8/D9的真实入口、独立GPU、原点和失败各归[D8](../../scene/history/scene-startup-d8-2026-10-24.md)、[D9限定记录](../../scene/history/scene-startup-d9-2026-10-24.md)。合格route无展开payload；D9完整tree与第二次包stream仍在，普通UI详情补全失败，不能认可编辑属性UI。两批三条件噪声均超门，不认提速、IO/RSS改善或完整P2完成。

**退出门：** 合格package产品消费者不依赖全量展开，entry结果/失败与来源身份闭合；暖挂载不读未消费payload，首次不写无消费条目，实际首帧满足原门。可控源Data、decoded/GPU和私有磁盘沿各自原额度、失败退款及最后借用终态验收，不能充当进程RAM预算。正式内存比较按[性能卡](../../scene/roadmap/performance-convergence-card.md)固定完整产品process set/窗口与同条件基线，保原非目标`max(5%, 2×本项噪声)`及事前设备/内容绝对预算；隔离native leaf是风险/归因证据，不是另一套正式全P2比例门。D27–D29仍显示明显新增leaf峰值，**媒体内存风险未解决、未授峰值预算资格**，不能用范围澄清或绝对政策未定掩盖它。先定最低设备、允许并发和系统余量，再冻结metric/窗口、最大合法输入覆盖并评价证据；不能拿实测MiB倒定阈值，不新增全RSS账本/watchdog/缓存。D31原10.4MB长GOP整App对照30App/40请求资格合格，三条件RAM噪声失败；D32近上限另30App/40请求资格全过，C0/C1门过、W0五对低噪声+11.0394466775%超原5%门，375仍0App，不授完整RAM/P2或以绝对4GiB通过代相对验收。合法builtin兼容fallback保留；若路由迁移失败，撤回该route并修订，不长期维持两套VFS。

**D30事前整产品RAM验证设计（D31噪声/D32相对回退STOP）：** 产品仍覆盖M1，按推荐8GiB作最低RAM设计假设；本机M4/16GiB只授本机证据。所测内容/窗口的进程集合预算冻结为`min(物理RAM/4, 4GiB)`（8GiB→2GiB，本机→4GiB），理由是为OS/前台留下至少75%的设计余量；这不是系统实际剩余保证，也不改变原内容能力、GPU/decoded额度或新增产品驱逐/准入。GPU账本不再加到footprint上。按下述实际采样评价，合法内容超预算即该场景不验收，不倒改额度。

- 复用已校验D7 pre-package App `725b8e…766`与当前D28 `bb658…2099`，不为取数重建；D7是全展开直接前驱，不冒充已不存在的原P0 binary。P0累计历史原门保持。两臂从相同作者输入真实独立出版v3库，完整commit/marker/ref及source保持；旧App不访问候选保留库。当前逐row严格核admittedSource；旧无此观测，用原产品入口/根/item/ticket/first-presented/finalize与旧cache包摘要/产物核资格，不伪造旧IPC字段。
- 输入分别结算375原52.5MB包/45.3MB音频、原10.4MB单GOP WebM TEX及另行冻结并被原parser接受的接近256MiB真实编码WebM；最大输入不靠padding、不改GOP/能力限制。W0包含真实active/candidate/retiring交接。未生成的最大输入、未知并发或最低设备不由小输入外推。
- 原30FPS、C0/C1/W0、HOME/cache/真实产品入口和90秒外界不变。按原五组AB/BA顺序，首个预登记A/B兼做来源/行为/测量资格，不另跑pilot；资格失败即停，不用补组掩盖。原相对/噪声门与绝对预算同时保留，不能混合不同输入冲销回退。
- 原kernel V4方法扩成任务目录的显式PID适配；先实际C ABI核sizeof/offset及身份，再接原runner旁路观察。预定20ms采样，记录实际gap、round起止与逐PID查询span；只在同round、全部已知目标可读且身份一致时合计current footprint，称采样进程集合峰值。各PID lifetime high-water单列，禁止相加作实际总峰。root+实际owned daemon/worker/helper持续跟踪到物理退出，并与原发现/报告PID核等；漏瞬态、launchd重挂/共享XPC归属不明或采样缺口不能授完整集合资格。未知/ESRCH不是零，安全退款/原偏好和最终退出仍走原门。没有原逐视频帧等证据时，first-presented不自动升级为持续视频解码资格。

**D31结果：** [整产品RAM首轮](../../scene/history/scene-startup-d31-2026-10-25.md)沿原五组交替AB，30App/40请求来源、原生首呈现/提交、30FPS、采样质量和实际退出全部合格；所有采样峰值低于事前4GiB，但C0/C1/W0各有一臂噪声超5%，正式内存门三项均失败。D31按当时协议停止，不补组、不调门；当时375及被原parser接受的251.86MiB输入仅真实出版、0App，D32独立补覆盖结果见下。产品保持D28，既有leaf风险/原seek红点不抹，不能认内存已改善或P2/P7完成。后继先解决能否获得有效整产品证据，停止同型重采；不新增缓存/适配层。

**D32补覆盖与后继：** 两份独立一次near-cap→375原五组，仅完整资格及相对/绝对门均过而纯噪声失败才可继续另一case，不重跑D31。实际near-cap 30App/40请求全部qualified，C0/C1 RAM过；W0五对均增、配对中位+11.0394466775%，双臂噪声0.2945771185%/1.0254949787%，超原5%门；绝对4GiB通过不抵消，全局STOP、375零App。峰在第二surface→present、daemon主导，无idle plateau，成因未知。旧新纹理均为Root heap，本例无材质目录命中；首次remux在普通可见视频成功首呈现前已终态，运行worker重叠假设STOP。COW归零复制/非同步flush不能直接采用。完成转换文件复用仅作下段任务机制验证，未进入产品，不授App修复。当轮产品仍D28，不重开借用/池微调、不先加cache或强等，P6强驻留/长期转换缓存STOP保留。原数/协议归[D31–D39历史](../../scene/history/scene-startup-d31-2026-10-25.md)。

**D33–D34机制结算（当轮未入产品，D36已接）：** D33两编译通过、A两actualFrame后新增raw-target 1µs oracle失败STOP，B零执行；旧记录无actual requested/scale，不能由D34追认其具体原因，原字节永久保留。D34另行事前冻结公开CMTime量化独立oracle，保原输入/像素/generation/decoded容差/全部期限与双窗，一次A/B各33 checks全true：12个seek上下文真实duration=33660/600、有效requested误差0，独立player及最后实际AVborrow释放/unlink/budget0通过。ready183.358→18.826ms、磁盘预约减半仅证单对原生机制减工；功能窗current峰887407984→886605144B仅少802840B/0.0904702%，31/25完整round，按事前规则STOP作为RAM修复的产品采用，不补跑/cache变体。D32稳定+11%仍阻断、375未跑，无新产品/Debug build，不授完整App修复或性能/P2/P7。该STOP只否定“作为RAM修复”，不否定原生准备和磁盘收益；后继补当前来源准入、完整内容身份、独立播放器/取消、原预算与最后AV借用释放的产品接入，再量真实启动。整产品内存持有/分配另行纠正，原P6长期强驻留cache STOP保留。原数归同一[D31–D39历史](../../scene/history/scene-startup-d31-2026-10-25.md)。

**D35结算：共享TEX候选撤回。** 有界Root独立heap捕获的COW视频slice及完整backing逻辑计费按先验实施；20方法/7选择器全部通过、2333依赖稳定，5966文件冻结Debug/strict签名通过。原near-cap五组30App/40请求全部qualified，但W0 RAM配对中位+15.43798%（双臂noise2.57370%/2.06544%，原允许5.14740%）仍失败，375零App；同期启动配对中位C0/C1/W0均未显示净收益，未授正式时序结论。不与D32跨批差额作因果归因。按先验停止并将三产品/三测试准确还原本片actual-before，保所有D28与并行D36改动；原测试、构建、失败原点及撤回记录保留，不补跑/改门。撤回依据是没有已证产品净收益，不是“只看RAM”；D34完成文件的启动/磁盘收益沿D36独立继续。当轮DerivedData中的D35 App仅为撤回候选证据，不对应撤回后的live源码；后续构建已替换该缓存内App，不能由缓存路径推断版本。原数归[D31–D39历史](../../scene/history/scene-startup-d31-2026-10-25.md)。

**D36结算：完成转换文件保留产品候选。** 沿原OwnedFile弱成功表区分snapshot与WebM完成转换，完整PackageIdentity/实际私有域/suffix/原DiskBudget共同定键；只实际package Handle参与，loose/external仍原准备。Registry声明及真实Handle前后核保持，命中用原preparedFile；成功登记仅携已经捕获不可变payload的纯identity，worker不留Root/Handle/lease。v1强捕Handle经审查发现合同冲突，在编译前更正；失败/取消/partial不入表，并发miss独立，原Source/worker/实际AVAsset最后借用才unlink退款。原样sound、MP4与选中来源错误不降级。

原3方法保留、新1方法26事实与原Sound/OwnedFile最近门共8方法/3组全过、71输入稳定；实际两GPU红帧、独立Player、同文件/单预约、停A后B继续、实际asset最后借用释放/预算归零成立。5966文件冻结Debug/strict签名通过，D28→D36产品字节恰三provider不同，flags/toolchain一致。真实已出版pair原五组/30FPS/20ms观察/90s及来源/偏好/退出门不改：near-cap30App/40请求全qualified，RAM三条件门全过，W0配对中位-12.587175%；等待配对中位-134.855ms/-30.643919%，五对全快，但基线时序噪声超5%，只保观察，不授正式性能。375原第一D28 baseline正常呈现/退出且来源合格，但完整round gap116.816125ms超原100ms而STOP；原矩阵false不翻绿。随后事前冻结独立协议，只覆盖此前未执行的新candidate，原core跑C0/C1/W0共3App/4请求功能全过；不含RAM观察，不补统计、不冲销旧失败。独审支持保留本片候选，P2整体D7 RAM最终资格仍待。实际数及所有原点归[D31–D39历史](../../scene/history/scene-startup-d31-2026-10-25.md)。

**D37实施边界（事前冻结，已按此完成本片）：** 本片只重排既有Registry的Input入口，不改变首次冷路径或长期保留声明：仅已选`.tex` package Input在当前Root/完整SourceKey及取消前后核验后，先查同owner/device的原live Source，再借D36原弱成功表的完成WebM文件；命中仍由原Source、epoch、rebuild reachability和独立AVPlayer构造/发布。未命中、loose/external和非TEX继续原Loader声明与现有失败处理；完整身份/当前来源硬错不得回退或吞错，文件变动仅撤自身弱命中并回原准备。删除命中路径的重复声明读取，不新增缓存、flight、预算、Root/lease保活、clock或输出owner。验收先在真实Reader/Root、decode预算拒绝或显式evict条件下记录原entry payload实际读取字节：live命中与完成文件命中须零新增读取，最后借用释放后miss恢复原读取；原生像素、独立player、stale/取消/同字节不同身份、非视频/坏内容及释放反例保持。实际before同一夹具记录原重读，不以源码形状或仅函数返回证明收益；随后最邻近回归、冻结Debug构建与必要隔离产品确认。未能证明减工或身份语义不成立则准确撤回本片，不扩缓存和实验变体。

**D37结算：复用命中退出重复声明读取。** 原Registry的Input入口只对已选package TEX核当前完整身份后，进入同一个同步lazy声明核心；同owner/device活Source或D36弱完成文件命中不再调用Loader，真实miss才捕获声明。取消/来源前后核、epoch/rebuild及唯一发布保持，完成文件构造失败仍原callback+nil，不二次转换；无长期Data、Root/lease、flight、缓存或时钟owner。三测试文件只新增真实pread观察与独立方法，旧4方法AST/旧D36夹具主体不改。实际D36产品4352文件与原build-map等值后冻结作before；新候选5966固定输入签名Debug通过。新IO两臂各13事实、current原26/27事实共4方法全过，132输入稳定：同一2101B条目live/completed/cancel从2101降0，cold/gen/最后borrow释放后miss仍2101；nontex/非视频/坏内容/硬来源和独立player保持。不能据小夹具字节数推算全App时间。

原D7→D37五组近上限30App/40请求全qualified，C0/C1 RAM过、W0配对中位-2.873835%且五对均低；candidate噪声5.179615%使原RAM门false，所有绝对峰低于4GiB。等待W0中位672.928→225.975ms、配对-461.705ms/-67.139513%，三条件六臂时序噪声全超5%，仅保观察；不与D36跨批差额归因本片。按事前纯RAM噪声续下一未测375，原D7首App来源/呈现/退出及samplingQuality都过，但报告的短命spirv-cross PID76401无成功内存查询，coverage partial而STOP；不是第二个gap失败，新candidate当时零App。另冻结协议只补此前未运行的新candidate3App/4请求功能全过，无RAM统计、不翻原false。80已知PID真实gone、锁归还，独审支持保留实际减工；P2正式整体RAM/375仍未齐。完整原点归[D31–D39历史](../../scene/history/scene-startup-d31-2026-10-25.md)。

**D38观测修正边界（事前冻结，已按此执行）：** D37原raw证明core note到首次kernel query额外19.445625ms，其中等下轮19.281583ms，observer的libproc从未列到该PID；不能据ps自称helper在note时仍存活。仅修任务采样器为原唯一线程的新PID事件唤醒：保20ms固定定时目标，事件可提前补一个新的完整round，不回填旧parent值、不把单PID首读拼成同期总峰；新round按实际begin/end、完整集合、身份、discovery及原100ms门独立资格化。发现后集合变化仍partial，已gone/exited、身份未知后PID复用、容量或stop/join错误仍失败，旧D31–D37原件及false不改。core只登记/通知，所有kernel查询和状态仍唯一线程；通知去重、clear与pending交换同锁，已接纳事件与stop/join线性，stop也唤醒。保原20ms周期deadline不因补轮漂移，新增raw trigger标明periodic/discovery；不新增产品观测、依赖、时钟/renderer或App构建。原RAM算子、5%双噪声/相对/绝对门与产品首帧/退出/来源均不改；新方法另冻协议，两臂统一使用，不与旧固定周期数字拼接或追认旧失败。先以受控Python子进程与脚本化错误/identity/cap/通知竞态反例验证即时完整轮次、定时不被事件推进、gone不补0及单写者，实际运行等另一会话交还窗口。测试和独审通过后再用同D7与D37实际App一次近上限→375预定矩阵；测量仍失效则保失败，审方法边界，不反复跑同型候选。

**D38结算：大输入RAM合格，375保留采样失败。** 只改任务目录observer，不改产品/Debug App；同一单采样线程保持20ms固定目标，新PID通知触发额外独立完整round。旧pending、identity、partial、求和/峰值与5%双噪声/相对/4GiB/100ms门保持。实际Python进程正反例与受控错误/复用/容量/stop竞态共旧2、新5方法通过；200ms受控周期的事件延迟201.273→0.050ms只证观测机制，非App提速。静态及实际raw独审通过。新一次协议两臂统一方法，仍实际D7与D37，当前4352产品/工程输入与原D37 build-map等值，未重建。

near-cap五组30App/40请求全部qualified，冷空缓存/新进程磁盘暖/同进程暖RAM配对中位分别-1.394904%/-1.749699%/-3.656962%，双臂噪声均低于原5%、相对及4GiB门均过；只授本机M4/16GiB当前采样指标/窗口。W0时间中位503.386→186.962ms、配对-62.859118%仅观察，六臂时间噪声仍全部超5%。375共4App/5请求：旧baseline C0/C1/W0合格，新candidate C0来源/首呈现/退出及全部报告PID成功查询通过，但四个辅助进程相继gone，四个原round正确partial；其间完整round126→131相隔100.484ms，超原100ms而STOP。总矩阵false保留，不补0、不拼旧读数、不将功能正常当统计通过；candidate C1/W0在本协议未执行，原D37独立功能证据保留。88已知PID物理gone，窗口已归还UI会话。实际原点及口径归[D31–D39历史](../../scene/history/scene-startup-d31-2026-10-25.md)。

**D39退出重核边界（事前冻结，已按此执行）：** D38原375四个连续gone使round126→131的完整间隔100.484ms；无缺PID或慢query证据。本片只在原唯一observer线程实际移除gone成员后，立即补一个全新的完整cohort round，raw标记postGone；保原partial/null、固定20ms周期目标，不能拼旧parent值或将本次失败翻绿。仅真实gone触发，exited/unavailable/身份变化不得借此删除成员或补0；stop须排空已接纳pending及本次重核，原时长/tick/PID容量和所有错误门不改。连续gone可连续重核，最终无成员仍partial，不忙等未知/不可读成员。先以受控序列证明连续gone后的独立新查询、原partial保留、周期不漂移、身份复用/unknown/stop反例；D38原方法作为同夹具before，200ms受控节拍只证观测机制。测试/静审通过后冻结新一次协议，实际D7/D37产品不变，两臂同用新方法，仅跑尚未合格375原五组AB/BA、C0/C1/W0、30FPS及原来源/首呈现/退出/相对双噪声/4GiB/100ms门。D38已合格near-cap不再运行，不混合旧协议点。首个资格/非纯噪声失败按原门STOP；仍不能有效取数则结算未覆盖，不为追绿增加新候选。实施、测试与本协议原始身份/终态分开记录。

**D39结算：退出重核生效，统计方向停止。** 仅任务observer增加postGone完整重核，同一固定网格/原partial/null与全部门不改；同夹具D38 before2/current5方法实际通过，200ms受控周期真实gone→剩余完整轮200.590→0.386ms仅证机制。实际375一次7App/9请求，所有来源/首呈现/正常退出与samplingQuality通过，完整间隔最大42.075ms；前6row全部qualified，第7candidate第二组C0的reportedPID88867无成功查询，coverage partial触发原STOP。它仅一次core note，0.135167ms后首次kernel query即ESRCH/gone，身份null，所有libproc childlist从未见；不能证明note时仍活着，也不能补0或回填内存。41个实际postGone轮含28个完整轮、7个空集合partial，原gone轮均null；独审复算通过。41个已知PID物理gone，窗口已归还UI。无五对375 RAM/时间结论，D38近上限通过与旧false分别保留。

**P2后继最小步骤：** 产品资源重构及有证收益保留；375完整五对统计按D39先验STOP并明确未覆盖，不把它写成已知产品回退或通过。没有证据支持继续采样器变体、为统计另造产品候选或同binary功能补跑。最大输入的当前RAM已按D38有效验收；首次预算拒绝的跨阶段重读保原payload寿命，不扩cache。余下工作转最终D37视频长期借用/释放与真实OS/P7验收，旧seek、时序噪声、最低设备/多屏/Release边界保留。

### P3：复用基础内容和固定索引

**P3边界与后继门：** [D15](../../scene/history/scene-startup-d15-2026-10-25.md)保noise局部减工，原输入无需求，不认整App收益。[D17](../../scene/history/scene-startup-d17-2026-10-25.md)真实variant暖load约4ms，停止新内存tier，完整内容cache暂缓。[D18](../../scene/history/scene-startup-d18-2026-10-25.md)stock首建叶确认成本后实施清单，完整投影一致，五对资格通过但5/6噪声超门；保暖慢点，不授P7。[D19](../../scene/history/scene-startup-d19-2026-10-25.md)一次任务ABA中原A自身下降20.57ms，候选仅比A2少1.00ms，停止排序产品改造；不以最坏复杂度认收益或重采挑点。音频重复物化已由D19按P2b限定实施。不按原计划惯性添cache，组合模型窗不归因单叶。

**P3a 独立切片裁决：** 同 daemon W0 模型段约156 ms，源码确认每次枚举并排序完整 bundled stock；尚无该枚举独占耗时结论。先由原 ResourceView 共享本 App 内默认 stock 的一份成功完整 Root/index/lookup，保持完整 namespace、优先级和动态创建资格。bundle 以本进程实际资源来源为边界，不以 App 版本或可变目录 mtime 充当内容摘要；custom stock、package、loose 不进入此共享。失败或不完整结果回原重建，不能常驻为成功；不缓存模型、属性、VM、grant 或版本 lease。此切片只依赖 P0，验收为真实资源结果相同、重复构建减少、同输入 C1/W0 比较及原失败门；无收益或正确性回退则撤回共享，不拖 P2 一起实施。

1. package 索引直接由挂载表产生；stock manifest 在构建期生成或按 bundle 内容身份进程内一次构建，两者均由原 ResourceView 消费。loose mutable 根独立失效，不以 App 版本替代内容身份。
2. 分离 ModelBuilder 内不可变作者事实与属性/会话投影。PreparedContent 仅缓存自持 bytes/IR 和依赖摘要，初始容量一份、总字节预算显式登记；单份超预算直接不缓存，不能把“一份”当物理内存上限。
3. 命中前仍取得本请求的合法版本 lease/receipt，不能复活已删除/更新的 generation；loose 来源重新核实际解析依赖摘要。缓存不豁免 entry 完整性，不能直接存含 URL/ResourceView/属性投影的整个 RuntimeModel/SourceFacts。LaunchPlan 按当前属性/locale 生成，VM/clock/provider/history 新建。
4. 首批只在真实请求中填充；下载后预解析不默认开启。若后续证明确有命中收益，预热沿同 key single-flight 提升优先级，压力、新意图与退出取消，不能重复 build。

**退出门：** 相同内容不同属性不复用旧投影；修改依赖、内存压力、取消后迟到回填、更新/删除与第二次播放均正确。量完整首帧、命中率、RSS/峰值和稳态争用；无收益或预算回退则撤缓存，保留 P2 合法资源输入。

**P3b 构建期 stock 索引设计（2026-10-25，已按先设计后实施；验收边界归D18）：** D18 原六源叶门在实际最终 App 的 2264 项资源上得到默认首次154.214ms、命中0.017ms；直接原索引128.777ms、Root建表3.438ms，完整资源/字节/查找投影相等。这是预哈希后的一次同步叶级观察，不是OS冷或App收益。选择消除默认不可变 bundle 的运行时枚举；拒绝序列化完整Root或构建机locale的查找表，也不新增全模型缓存。

生产沿原 `copy-scene-stock-assets.sh` 在rsync删去编辑器材料后调用薄Swift生成器；生成器与原 `SceneResourceIndex.swift` 一起编译，由原 `buildWithCompleteness` 读取实际目标assets，只有完整结果才能原子写入bundle顶层 `SceneStockIndex.json`（assets外）。清单只含schema及raw path/Int64 size行，行JSON原始Data和SHA256封装；不存绝对URL、构建机kind、locale、lookup或作者授权。包内新增清单不改任何运行资源/许可证字节；生成失败使本次构建失败，不留旧清单。

消费只由原 `BundledStockRoot.value` 在原默认路径canonical位于 `Bundle.main` 内时选择；清单自身canonical也须位于同stock bundle且不经重定向。原IndexBuilder负责解码和投影，解码输入上限4MiB（当前约数百KiB，构建器同限）；核schema、payload摘要、非负长度、唯一且无绝对/空/dot/traversal/反斜线/NUL路径，再沿原kind和当前locale排序，交原Root建立原双firstWins表。不同路径在当前排序出现 `.orderedSame` 时退出快路、沿原枚举，以保原filesystem tie顺序。自SHA只核清单自洽，不在运行时发现一份合法但陈旧的清单；正确性由同次打包后的完整生成、失败去旧清单及真实投影门闭合。清单不认证作者文件，信任边界仍是本运行App不可变签名bundle，不用App版本/mtime代表内容。

缺失、损坏、版本/预算/路径/摘要/排序歧义或bundle边界不合格均只撤清单快路，沿原完整枚举和成功完整Root共享；不保负缓存。显式/custom stock、loose、package及外部重定向默认根仍走原路径，locale改变仍由原槽重建。清单不含payload、不新增资源/缓存owner；本次启动后仍只保原Root，临时decode Data退出即释。

验收先以原生成/消费链证明完整打包字节不变及隐藏/package可见集、locale排序/大小写/firstWins、缺坏/超限/路径和外部/可变根反例，再做Swift Debug构建、实际stock完整投影和同输入规范化App对照；warm不回退、原来源/提交/退出不变。旧枚举保作缺坏清单的明确fallback，不并行双建；实际stock不能用快路或原条件无有意义收益时撤本切片，而非降低验收。完整P2/P3/P7仍按各自原门结算。

### P4：同 launch/device 共享成功 Metal library/PSO

1. **D13 STOP：** 同device/同key两个同时存活、owner独立的真实encoder确各创建library/PSO，peer串行命中原archive的whole warmup仅约0.35ms；首创建不因共享消失，未证多key/真实多屏热点，不落复用层。保原fixture ABI失败与一次隔离修正资格，详见[D13](../../scene/history/scene-startup-d13-2026-10-24.md)。重开先证实际重复频率/关键窗口，再采用以下条件设计，不据实例或计数自动实施。
2. 若成立，由现 `ScenePreparedDeviceResources` 持同launch/device的authored编译复用对象；在原两准备Task启动前建立轻量对象，首屏与后续runtime注入同实例，保纹理准备并行。固定内建pipeline职责不迁；不强迫独立Graph测试编译内建管线。复用原binary archive，实际创建者独占原tier/fallback，不增磁盘owner。
3. 共享成功表只弱持有实际library/PSO；encoder原正缓存强借用，原局部负缓存保留。按key single-flight仅在途及已加入等待者暂持结果，完成后移出表；失败只回本次同flight调用者，后续独立encoder可重试。一屏取消不撤他屏创建。准备边界清死弱项，不在普通帧全表扫描；不得用共享强表延长退休屏驻留。
4. key绑定实际device、完整选中MSL（含attachment变体）、函数/ABI/常量/编译选项及原完整MetalCompileStateKey；hash仅加速。每屏ownerToken/resetGeneration、target/history、binding/publication独立；等待时若释放encoder锁，须保存进入时generation，不能把旧prepare标成reset后新代。
5. 沿原worker实际join/GPU completion保encoder借用至终态；无新drain owner、不跨launch保温。分别测单屏与同/异尺寸双屏，注明并发负载，不将探针耗时认整机提速。

**退出门：** 并发同key创建合一、异key隔离，第二屏/失败重试/reset/取消/停止后输出与lifetime正确；最后强借用释放后允许重建。未证全启动收益只认局部机制。

### P5：Web 退休 worker 复用，保持双候选事务

1. **D12入口STOP：** 现W0在selection前已有hello，原空daemon预备已覆盖spawn/AppKit/IPC；fresh Host/view初始化未证可省成本。stop及弱引用诊断不证明目录/网络/JS/FD终态，复用还须迁移现version2请求和频谱身份。保单次daemon及空预备，不落闲置drain/协议基础；重开须先证同进程第二个fresh Host/view相对新预备daemon的净收益及可行清场，再实施以下条件设计。P5b公开清场不足仍停止。原adapter保持两槽，无第二池。
2. 拆开 transport 的 daemon instance 身份与每次 execution request/session generation。worker 的原请求不可改名；协议升版拒旧版，无双生产fallback。
3. 首片daemon-only只接原事务已允许退休的committed成功Session；失败/取消候选、重建和恢复仍精确退出。新候选可见后原事务退休旧active：先关输出/输入/音频、撤grants/endpoints/watchers、取消导航/资源/网络，再drain，不能等持续任务自然清空。后台Worker/Service Worker退场未证则退出，不保WebView。
4. child 回传 instance/request/sessionGeneration/reset nonce 全匹配的 ACK，父端在预期 retiring 状态才释放该 request 的 library lease；重复/迟到 ACK 无效，实际退出也能结清。ACK 前旧 scheme/Range/网络/目录任务与重开文件回调均已撤销/排空；每段有截止期，缺失/错误、超时、压力或父退出终止精确 worker。可再次 bind 还须原事务允许 endpoint 退休且无未决回滚/采用预约，不能仅凭资源 ACK 提前改名。
5. P5a全部surface/WebView/server/request销毁及drain ACK后才空闲。P5b还须证WebView成本，HostCompatibilityKey全匹配store/profile、authority/root、origin、bridge/config schema及screen；去旧handler/scripts并受控blank，但blank finish不证明BFCache/历史清空。公开API不能防旧文档恢复/旧generation写入即退P5a，无私有清理API。空闲无作者执行/授权/采集，不全清persistent store。
6. 新请求只采用已 reset 的空闲 worker，注入当前身份/grants 后按原导航、snapshot、媒体 completion、可见确认进入事务。active 不原地改页；reset 中新意图遇到两槽已满，终止该 reset worker 并等精确退出后冷起候选，期间保 active 和原 newer-wins，不借此开第三槽。
7. 退休warm与原预备共用槽及总峰值，保原空闲超时/压力/停止策略，不定时补进程。HTTP仅P5a；退出原总截止期内撤扫描/reset/预备，shutdown不补进程。

**反例：** A→B→A/同记录重设、不同 store/profile/屏幕、reset 期间新请求、迟到脚本/网络/媒体回包、同 store 两个 worker、取消/恢复、主进程死亡/阻塞、worker 崩溃、旧租约释放后更新/删除、cookie/localStorage 应保留而页面对象应清空。

**退出门：** 真实 ACK 后旧 request 无任务/授权/输入/采集，旧 lease 可回收；非兼容 key 全量重建；五次以上交替启动及最终长期切换门通过。P5b 无收益/清理不成立退 P5a；P5a 失败退单次 daemon + 空宿主预备，删除相应产品分支，不延 timeout 或减少 reset 验证。

### P6：Web 本地响应复用与 HTTP origin 边界

1. **D12首片：** 同host/Path=/固定名`mwx-access`会在同store双端口HTML间覆盖。改名绑定原不可变lease token，名字/值均核本server，保token路径或本cookie的OR准入；原surface teardown按创建时WK store精确删本name/domain/path，不清整个store、不取后继surface，不将异步删除冒充drain。保原token熵/SameSite/path/端口/root/grant/stop重启，不认跨端口文档隔离。真实共享WK store两端口先红后绿，核双向无前缀读取、停A后B及迟到响应；无cookie/错误token/旧固定名/陌生前缀和原Range/304/HEAD/撤权仍拒非法。只认连续性。转换cache无热点依据STOP；重开后沿原读取核按Data digest/kind/schema及实际输出投影有界复用，含token存中间表示再投影。不持grant/FD/lease，单项/总bytes受限；仍读全文取digest只认少转换，不认少IO。
2. 保留每次资源授权与规范路径检查、ETag/Last-Modified/304、HEAD/Range/取消及背压；`no-cache` 是重验证，不等于 `no-store`。普通媒体已有分块，不重新做整文件缓存。
3. loopback 保留现有两种准入：带本 lease token 前缀的路径，或无前缀但携本 lease cookie 的请求；不是每个请求都要求 token AND cookie。先覆盖同 store 的 active/candidate 并存：cookie 不按 port 隔离，见 [RFC 6265](https://www.rfc-editor.org/rfc/rfc6265#section-8.5)。cookie 名/删除按自身 lease 区分，不能覆盖后继凭据；这只解决冲突，不证明跨端口请求来自哪份文档，根/grants/token 的原安全边界不得放宽。
4. 首批不强行固定端口、不为稳定 URL 跨 author 合并 origin、不把同 origin 下多个活跃 grant 取并集。保持现有随机 token 路径与逐 session 授权；高兼容档跨重启的 storage/HTTP 缓存身份尚未解决。
5. 只有 P0 的真实缓存/存储反例确认 origin 变动为目标成本，才另修订本节确定单一 origin 授权 owner、双候选路由和端口冲突退出；在此之前不启用高兼容 WebView 复用，也不新增 broker/第三进程作为整个专项前置。

**退出门：** 同内容转换次数减少且当前 token/授权正确，源修改/依赖变化即时失效；跨 worker cookie 不干扰、撤权有效、媒体与框架加载相同。origin 稳定与 HTTP/Code Cache 实际命中另报未知，不能由 store UUID 稳定推断。

### D23：Scene 跨类型重入的有界原进程复用（实施前设计）

**目标、依据与停止条件：** 仅加速同 App 中 Scene→已提交 Web/Video→Scene 的短时重入。D22 三个新进程的 NSApplication.shared 调用壁钟约521–561ms，现 active/no-pending 退役直接 stop/exit，故选择复用已存在且成功退役的空 transport；不调整 AppKit 初始化顺序、不另建 helper 或预热池。进一步研究框架内部缺少 owner 证据；主动预热会增加无关后台工作，均暂不采用。首次 C0/C1 不受益，本批未取得实际净收益之前不授性能结论。若强退役无法闭合、空闲能耗/资源不可接受或真实重入无净收益，撤回保留策略，不继续扩池。

**唯一职责与数据流：** Manager 仍独占产品意图/提交。原 PlaybackSwitchEndpoint.retire 增加可选的已提交后继 ticket 参数；普通 retire 传 nil，handoff 传原新 ticket，Video/Web/静态实现忽略该参数。只有 Scene 的精确 active/no-pending execution、后继为已提交 Web/Video 才申请保留；Scene→Scene、取消、失败、普通 Stop/丢失沿原路。Client 不反查 Manager，不修改 reducer、首帧或回滚权威。用户 Stop 本来已显式调用 Client.stop，继续要求物理退出。

**原协议的强退役资格：** 原 hello 增 requestRetirementSchemaVersion=1；原 retireOutput 可选 requireRequestRetirement Bool，缺省 false，原 requestID/operationID 不变。普通分支保持窗撤回时序；只有强分支在原 inbox 暂停 drain，先捕获已知精确请求、原窗口及 Session，再走原 Host 请求范围的 preparation queue fence、Session CPU/任务与 GPU terminal，不做异步全局 stop。完成在主线程发原 switchControlResult：accepted 仍表示原窗口撤回，新增 requestRetired=true 还要求精确已知请求成功终态且 Host 无 active/candidate/promotion/rollback/retiring/准备 owner，然后恢复同一 inbox drain；未知 UUID、空字典、缺字段和失败不能自证成功。父端原2秒控制截止期和物理退出升级不延长；child 强退役等待期间 shutdown 可在原队列等待，独立父死亡/硬截止期仍保留。不存在第二 load 队列或完成记录表。

**资源与音频闭合：** 原 requestResourcesReleasedHandler/whenRequestResourcesReleased 传真实 Bool；仅成功发原 launchResourcesReleased(resourcesRetired:true)，失败 Session 保留在原 retiringSessions 到精确进程退出，不能提前退 source lease；普通旧 Scene 退役若 GPU/任务终态失败，沿原 Runtime.shutdown 精确退出该子进程并由原 Client 恢复已提交意图，不能仅记日志无限保留。所有已接纳 userTexturePreparationQueue→main→prime Task 及 initial user video prime，在调度前进入原 retiringSurfaceDrain，实际终态唯一 leave，取消不冒充 join；原 Session shutdown 先 join 再 GPU barrier，stop 后不得新接纳。原异步频谱 demand 回调发布前复核完整当前 captureDemand（含 scopeEpoch），成功强退役 ACK 之前沿原 FIFO 发布当前 none；父端退役/空闲状态拒绝旧 positive demand。私有 WebM remux 的自有 Data/file 及最后 AVAsset borrower 可按原预算继续存活，不能再读作者 Root或晚发布；不承诺 AV/native allocator、全部文件/FD或 RSS 归零，不强清其预算。

**父端身份、排队与寿命：** 扩展原 SwitchControl.requiresRequestRetired，沿其 operation/request/transport/generation 表成为唯一在飞屏障，强持旧 lease 到强成功或物理退出；旧 release 事件不能提前结清强控制的借用。hello 能力缺失/坏字段/错误身份/false/timeout 走原精确退出，不能先完成 barrier。所有 load/replay/legacy requestLaunch 入口在强退役期间沿原 latest queued preparation/pending intent 等待；只保最新有效票据及租约，取消精确匹配，旧回调不得清新意图。强成功先清旧 execution/媒体和 coherent 状态，才调用可能重入 Manager 的完成，再复核原身份发后继。

只在原 Client 保存一个精确 idle identity（transport+generation）及一个30秒 DispatchWorkItem，从成功退役计时；不新增第二个 Scene 进程、Root、descriptor、Program 或来源缓存，不因 warmSession/其他类型选择续期。新 Scene 在当前 registry 准入仍开放时同步移除 token/取消 timer，重新走 Service 来源认证/lease并创建新 request/execution，只复用原已握手进程。stop/shutdown/spawn/exit 失效 token；旧 ACK/TTL 不能操作新请求/进程。到期只对仍同 token/transport/generation 且无 Scene owner 的实例执行原 stop，空闲崩溃不重放；退出 registry 仍登记原进程，App quit 等待真实退出。原“两槽”是 Web adapter 的活动/准备角色约束，不能推导成跨引擎、多屏最多两个物理 PID；Scene 保留与 Web 可选预热的互斥按下述 D23c 裁决实施。

**实施与验收顺序：** 先保存本设计/合同/登记，再实现 Host/Session 强终态、Client/Manager 有界复用和共同 DEBUG 测试入口。最近真实 Swift 门验证被阻塞 CPU/prime、GPU nil/error、unknown UUID、完整身份/能力/字段反例、旧 ACK/TTL、快速 C→D/取消、legacy/replay、同步重入、Stop/quit/registry close、原 Scene→Scene 失败回滚及音频迟到。固定源签名 Debug 构建后，以相同共同 DEBUG harness 重建 D22 产品基线与候选：真实 Service Scene375→Manager bundled Video2→Service 同 Scene，两次原 drawable presented/来源/票据/执行身份及实际旧 barrier，基线新 PID 与候选同 PID/gen、fresh request/lease分别记录。原 C0/C1/W0 测量与默认单次/sequence 行为保持；无 profiler、不跳来源认证、不直接 Client/Host 假装产品入口。普通 App quit 另走 AppDelegate/registry，不能用测试 finish 的预先 shutdown 冒充。TTL/Stop/失败、资源/音频及代表回归按风险补测；对照必须等另一独立工作树释放共享 CPU/GPU，源码无需互相阻塞。真实前后差、噪声、空闲成本与剩余未验边界结算后再决定采用；所有代码文档保持未提交。

<a id="d23-window-withdrawal"></a>
**窗口撤回修正（先设计、后实施）：** D23a 五对的原噪声门通过，但Video交接正差不能被总窗收益掩盖；原wire仅将余窗缩到父端资源事件→强ACK合窗，缺child fence/首次CG结果，不能全归窗口确认。D23b只修原Scene桌面HostWindow的系统展示/关闭动画策略：在同一窗口首次显示前设animationBehavior=.none，保原几何、层级、作者动画、all-display/WindowServer撤回确认、GPU/任务/版本租约和全部deadline，不提前ACK或新增barrier。SDK及现Web设置只支持最小候选，不把壁钟直接归因为动画；Video无同名设置证据。

保持共同harness重建D22产品基线；B只做一对诊断，最终五对留给容量修正后的C，未重复B五对。四实际App/源图与A/B的原通过/正差不改写，最终C不能继承A噪声资格；原点、方法及实际数值唯一归[D23历史](../../scene/history/scene-startup-d23-2026-10-25.md)。

<a id="d23-idle-admission"></a>
**D23c 空闲准入修正（先设计后实施）：** 独立审查发现原 beginPlaybackIntent 通知只推进 Web 解析代际，Scene idle 没有 pendingIntent，原取消准备首 guard 会直接返回；Web 提交后2秒和 App 启动3秒都可能再建空预备。因此 D23a 会出现 Scene idle + Web active + Web idle 的持续额外进程，不能认资源约束已闭合。没有全局两 PID 合同，不为修正文案新建共享调度器或严格等退出平台；沿现有 owner 撤多余可选工作。

原 Manager 意图通知携本次可选 runtime；runSwitchEffects 可能同步重入，只有捕获 epoch 仍为当前 epoch 才发布，旧通知不得驱逐新 Scene。原 App 装配在非 Web 意图取消已有 Web idle/延迟任务，保实际 active/candidate；把 runtime 交原 Scene Client，Scene 意图保留排队/采用，其他意图仅在 idle 或强退役已清 active 的状态调用原精确 stop。强控制及旧 lease 继续等真实退出，迟到 ACK 不得重建 idle；仍承担失败回滚的 active Scene 不受此通知停止。原 stop→retiringTransports→真实退出继续唯一，不把撤 token 称物理退出，允许既有退出模型内有界的 retiring 瞬态重叠。

commit 的产品投影也可在旧 handoff effect 之前同步产生更新意图，此时 Client 尚无 idle/强控制，单靠通知不够。原 Manager 在实际调用旧 endpoint.retire 时才授可选后继：本次 replacement 仍属当前 epoch，或当前请求为可采用原进程的新 Scene，才传其原 ticket；已被更新非 Scene/Stop 取代时传 nil，仍沿原旧输出退休及 barrier 完成。只抑制失效保留资格，不丢弃 handoff、不在 Client 复制产品 epoch 或反查 Manager。

原 Scene Client 只投影 idle、强控制或原 retiring map 是否存在，不持第二份槽账本；App 将此只读事实接到原 Web adapter 的可选空预备准入 closure，prepareIdleProcess 在实际创建前求值，统一覆盖两处定时入口。强退役、idle 及退出未确认期间不额外预热 Web；真实 Web 请求的 prepareProcess、候选、恢复及冷启动回退不受此可选门阻断。没有空闲释放后的新重试/补池计时器，原后继事件可再尝试。沿原内存压力和退出准入保持取消。

最近真实 Swift 反例须覆盖：启动时已有 Web idle 的跨类型撤销、2秒/3秒任务实际执行时重查、真实 Web 请求不被门阻断、强退役中非 Scene 意图及迟到 ACK、Scene 新意图可排队/采用、active Scene 失败回滚不被停止、同步重入旧 epoch 不投递、Stop/registry close 和最后真实退出后恢复准入。当前C已完成14个最近方法/32命令、冻结Debug及一次预定五对；五对产品资格通过，5/6噪声失败与Video正差仍在。普通UI自然TTL/保留时Cmd-Q和有限idle CPU/RSS另证，原TTL观察路径别名失败及同raw校正都保留。全P7、C0/C1累计收益及旧seek不由此关闭，详同一历史。 D25复核：Video实际visible/Manager commit先于旧Scene退休，Engine finalized/readiness在旧屏障后；ACK到runner发现仅2.262–10.190ms，原同栈无额外等待。+38.713ms继续作为交接完成成本保留，不称首画回退；没有安全可删环节，STOP额外诊断与微优化。

### P7：整体验收、退役与收尾

1. 在原始基线、直接前驱和最终版本之间按第 5 节比较，避免多批局部收益掩盖累计回退；保留有效反例和未采用方案的 STOP 原因。
2. 删除已不可达或被采用route实际替代的职责；D24已退toolURL/Process/空协议。合法legacy builtin extractor与明确工具消费者保原归属，不为“清零”删兼容回退；未采用原型/flag按实际退出。
3. 当前能力/运行事实分别同步 Scene 能力与证据、Web current-state；稳定资源输入、身份和生命周期回到原合同。本文只保阶段结算与剩余条件，不复制运行台账。
4. 结束时按精确路径清理隔离 HOME/App/DerivedData/cache、样本副本和重试输出；有限最终证据沿[产物规则](../../../.agents/skills/mywallpaperx-maintainer/references/artifact-governance.md)保留。未知归属与唯一失败证据先保留。

**此前证据（D24–D28）：** [D24](../../scene/history/scene-startup-d24-2026-10-25.md)保20切换/30min与累计原点；[D25](../../scene/history/scene-startup-d25-2026-10-25.md)保普通GUI六方向、两作者属性及分请求政策暂停/实音，不升级为全作者或同请求全程资格。[D26](../../scene/history/scene-startup-d26-2026-10-25.md)仅补小WebM夹具与单次App绝对观察。[D27](../../scene/history/scene-startup-d27-2026-10-25.md)同binary/fresh进程的合法长GOP共同解码/时序/seek通过，但reader前当前进程高水位明显高于旧URLwriter，P2物化内存风险重新打开。单对不授正式统计、独占workspace、整体App或256MiB上界，也不能忽略该信号。 [D28](../../scene/history/scene-startup-d28-2026-10-25.md)包级释放池未降低同输入峰值，停止该假设，不进入产品；后继区分归下段。

**当前责任点与停止（D39）：** 产品保持D37，D35已撤、D36完成文件与D37命中免读保留已证收益；D38近上限RAM通过，D39对375完整统计按先验STOP，不再观测变体。D24旧30分钟/20切换不能替代D36/37新增视频文件长期借用；actual map与当前仅8个产品/工程路径不同，Host/Session/Manager/IPC字节相同的旧限定行为可沿用，整体媒体寿命仍须最终版本补验。下一仅当前视频长跑、用户延期OS/显示/压力及最终结算；原时序噪声、约39ms交接完成成本及旧seek/最低设备/多屏/Release边界保留。


**D40最终版本验收边界（事前）：** 产品不再变化，固定实际D37签名App及4352产品/工程输入等值原build-map；仅任务副本适配原D24普通UI wrapper/marker，将硬D24 build/5957计数改为实际D37收据与源集合，显式轻/视频输入角色，保原30FPS、真实Service/Manager提交与GPU首帧、20次轻重切换、至少1800秒awake视频稳态、60分钟外界、quiet/source/偏好守卫及普通Cmd-Q自然退出。新私库沿现有managed importer真实出版原light314与已保留自有10MB WebM TEX900000008；不改D31配对库、不新生成媒体、不借real用户目录写入或改作者内容。不用旧wrapper硬身份或仅marker替代实际提交，不增加App观测/输出owner或重建。新完成文件的长期借用/切换后释放须由本次实际路径与原资源/生命周期日志核验，原D36/37精确AV最后借用反例仍保独立范围。

一次20轻↔视频后视频连续awake30分钟，必要端点截图/进程身份/资源采样及自然退出沿原工具；只能证明离散有界稳定性，不声称全FPS、无泄漏或性能对照。真实锁屏/解锁、睡眠约20–30秒/唤醒、显示缩放一档后恢复放在稳态完成之后，只有实际系统事件/Scene bounds变化及后续输出才能验收；压力需实际系统通知和恢复，既有权限失败不算已执行。若用户仍延期或权限不可用，保持该项未验，不伪造事件。先静态适配/独审，待UI会话明确交还约45–60分钟才出版/运行；测试App就绪后逐步提示用户操作。来源、身份、输出、退出或并发守卫失败即STOP并保原点，不重复挑绿。

## 5. 验证协议与声明范围

### 5.1 必须区分的条件

| 条件 | 产品 cache | 进程与执行 | 用途 |
|---|---|---|---|
| C0 首次使用 | 隔离且为空 | 新主 App/对应 daemon，无本轮空宿主 | 完整首次成本；不声称 OS 页缓存真冷 |
| C1 跨进程暖 | 明确保留同一 HOME/cache/内容 | 新进程，记录 WebKit 实际 PID | 跨进程持久产物收益 |
| W0 同进程暖 | 保留同一份 cache | Scene 同 daemon；Web 记录 worker 采用/新建 | 同内容重设及 A→B→A |
| X0 跨引擎返回 | 保留 cache | Scene/Web/Video 六方向，记录真实退出/复用 | 生命周期、回滚及实际产品等待 |

各条件单列单屏/双屏、轻/重、静态/脚本/视频纹理、standard/highCompatibility。每阶段用一个能触达目标的输入和一个未参与修复的健康输入短筛；最终覆盖上述代表集，不要求每次局部改动全量矩阵。资源/变量改名与等价依赖/属性变体应得到同结果，不能按样本/path/hash分派算法。

### 5.2 性能与正确性门

正式统计沿[性能卡](../../scene/roadmap/performance-convergence-card.md)：启动每条件至少五个基线和五个候选，交替顺序；固定配置、输入、温度状态及缓存策略。记录中位、范围与原始 run，不用五次宣称尾部分位数。先冻结噪声与非目标预算，超噪声先排干扰，不能删慢点或放宽门。

用户可见主指标：Scene selection→实际 presented→产品 finalize，accepted 为中间分段；Web selection→匹配 commit 并单列 snapshot/窗口可见，不称物理呈现。辅助指标包括主线程最大 stall、读取/写入字节、各缓存真命中、首次完整内容、峰值/稳态内存及停止后资源；准备期间旧 active 连续性同样验收。普通优化产品与诊断配置分别报告；Release 不新增详细观测。

Swift 产品改动需签名 Debug build；GPU/VM/资源/宿主改动需隔离真实输出和下一帧、暂停/恢复、失败/取消及 drain。最终执行至少 30 分钟稳态、20 次轻重切换/resize，并覆盖停止/退出、压力、睡眠/唤醒和显示器变化。缺最低设备、多屏或 Release 时明确未验，不扩大声明。

### 5.3 最近工具与测试

- 先用 `python3.12 -B script/verify_scene_change.py --phase inner --path <owned-path>` 预览真实模块，再按实际输入选 `run_scene_tests.py --module <name>`；不得把未映射或源码形状门当行为验证。
- Scene 最近候选：`test_scene_pkg_reader.py`、`test_scene_pkg_cache_extractor.py`、`test_scene_resource_view.py`、`test_scene_asset_catalog_resource_view.py`、`test_scene_persistent_cache_behavior.py`、`test_scene_pipeline_repository.py`；P2 必须补真实 range/物化行为输入，不能只让旧测试消失。
- Web 最近候选：`test_web_runtime_cache.py`、`test_web_launch_profile.py`、`test_web_response_transformer.py`、`test_web_property_persistence_gate.py`、`test_playback_process_isolation.py`；其中属性 gate 测试主要检查 parser/评分，真实运行另走 `script/web_property_persistence_gate.py`。IPC/reset、双 cookie 与授权反例补在原 owner 最近门，不能以进程存在证明 WebView 已热。
- `playback_process_isolation_benchmark.py` 用于真实进程/交接反例，不是启动 A/B；`scene_wallpaper_performance.py` 是日志解释工具，`web_wallpaper_benchmark.py` 是运行能力/画面证据入口，均不独立证明首帧提速。

## 6. 取舍、未定边界与停止

本设计批准原 owner 内的资源输入、依赖准备、同 launch 共享与 standard worker 退休复用边界；不预批准跨 launch GPU 常驻、全库预解析、高兼容稳定 HTTP broker、绕过授权或新视觉算法。P5/P6 的入口成本/实际协议门未满足时，停留在已闭合的前驱机制，不把未实施写成完成。

连续两次有区分力短实验仍无收益或非目标越门，停止该方向，查明成本是否转移后重排；正确性/安全失败立即修正或撤回。可靠小幅局部减工可按现性能卡保留，整体比例和能耗未知如实报告，不能以强行达到预写百分比扩大范围。

专项结束条件：实际采用阶段通过产品冷暖与失败/退出门，替代 owner 退役，剩余项有明确停止/未验结算；或用户结束专项。完成后将执行结果归历史，长期边界留原合同，索引退役本 active-plan。设计门的 `approved` 只表示边界可实施，不代表产品实施、性能、官方一致性或发布通过。
<!-- preserved-body:end -->
