# Scene / Web 壁纸冷暖启动改进专项

<!-- document-role: active-plan -->

> 设计日期：2026-10-23。状态：方案已定义，产品实施与性能验收尚未开始。
>
> 用户指定本专项，允许替换不合适的旧链路；本次仅落设计，不授权 Git 提交、推送或发布。
>
> 本文唯一维护本专项的步骤、裁决与停止条件。Scene 稳定边界归[启动合同](../scene/architecture/scene-launch-responsiveness-contract.md)，Web 执行生命周期归[宿主设计](../web/dedicated-host-process-design.md)，跨引擎产品提交归[切换事务](../architecture/playback-lifecycle-transaction-design.md)。自主兼容队列不作为用户指定启动工作的前置，其他专项不因本文自动重排。

<a id="decision"></a>
## 1. 目标、范围与选择

在相同内容、属性、画质、授权与首帧门下，减少从“设置壁纸”到实际可见的等待，以及启动期间的 UI 阻塞、文件读写、重复解析/编译和内存峰值。覆盖首次使用、保留磁盘缓存的新进程、同类型重设/切换与跨引擎返回；不能只优化内部 Host 返回或某个阶段日志。

本专项选择两条主链：Scene 在现有 ResourceView 内迁到已校验 PKG 索引和按需字节读取；Web 在现有项目解释与宿主 owner 内消除重复准备，再以有界退休 worker 复用研究 WebKit 初始化成本。允许重构 DTO、IPC、资源消费者与租约释放边界，但保持 Swift/AppKit、Metal/WKWebView 和唯一产品事务。

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
| [ScenePkgCacheExtractor](../../MyWallpaperX/Core/SteamWorkshopScene/Format/ScenePkgCacheExtractor.swift)、[SourceFacts](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRuntimeSourceFacts.swift) | 每次准备读整包、包/entry hash；命中仍枚举并逐文件读缓存比较 | P2 |
| [SceneResourceView](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceView.swift) | package/loose/stock 每次重建目录索引；Host 还要求 `packageReport.outputURL` | P2、P3 |
| [SceneDesktopWallpaperHost+Launch](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift) | 每次 ModelBuilder；基础作者事实与属性投影尚未形成可复用的独立输入 | P3 |
| [PassEncoder](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift) | authored library/PSO cache 属于实例；多屏可能重复 `makeLibrary(source:)` | P4 |
| [WebRuntimeCache](../../MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebRuntimeCache.swift)、[准备入口](../../MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopWebResolvedRuntimeModels.swift) | execution 命中仍扫描；跨 App analysis 校验可能再次扫描；保存再取得签名 | P1 |
| [WebDaemonRuntime](../../MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonRuntime.swift)、[父 adapter](../../MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter.swift) | 生产 IPC 一次 launch；空 daemon 只完成 AppKit/IPC，未创建 WebView | P5 |
| [LoopbackServer](../../MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLoopbackServer.swift)、[scheme IO](../../MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler+IO.swift) | 高兼容档 port/token 改变；HTML/CSS 非 304 响应重读/转换 | P6 |

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

每步均执行：重核 owned diff/并行改动 → 最近行为门 → Swift 改动签名 Debug build → 对应隔离产品入口 → 冻结差异和证据独审 → 更新本表结果与稳定合同 → 精确清理。文档本次不执行产品门。阶段中“通过”必须附输入/build/工具身份及未覆盖范围。

| 步骤 | 依赖 | 本次设计状态 | 产品/性能状态 |
|---|---|---|---|
| P0 有效基线与观测校正 | 无 | 已定义 | 未执行 |
| P1 Web 一次依赖准备 | P0 | 已定义 | 未实施 |
| P2 Scene package 资源输入重构 | P0 | 已定义 | 未实施 |
| P3 Scene 内容与索引复用 | P2 | 已定义 | 未实施 |
| P4 同 launch Metal 成功产物共享 | P0；与 P2/P3 不重叠时可独立 | 已定义 | 未实施 |
| P5 Web worker/兼容 WebView 退休复用 | P0、P1，初始化成本有依据 | 已定义，先 standard 档 | 未实施 |
| P6 Web 响应复用与 loopback 边界 | P0、P1；与 P5 协议协同 | 已定义有界范围 | 未实施；跨重启稳定 HTTP origin 不认领 |
| P7 整体验收与旧链退役 | 实际采用的阶段 | 已定义 | 未执行 |

### P0：先使冷暖与首帧测量有效

1. 冻结主 App/daemon/helpers、源码与工具链身份，准备只读媒体的隔离副本和独立 HOME/cache。记录普通产品配置与优化 Debug 观测配置，禁止混作同一分布。
2. 沿现有 Scene daemon-client 与 Web startup runner 补同请求 selection、accepted、内容准备、CPU Program、device/WebView、prepared、present/visible、commit/finalize 时间。selection 从实际设置入口开始，包含通知 daemon 前的租约/属性准备；观测只读且 DEBUG 显式启用，不新增产品计时 owner。
3. 记录包/entry/目录/依赖实际读取次数与字节、Metal 创建次数、worker PID/instance、Web store/origin、CPU 峰值与停止后驻留。嵌套/并行阶段按同一时钟和区间解释，不把各段机械相加。
4. 先取得有效基线，再按主链选题；若主要等待已转移，重排本专项阶段，不按静态可疑点强做缓存。

现有 `scene_wallpaper_benchmark.py` 默认 direct Host，`startup_ready_ms` 是 runner ready，不能称产品首呈现；`--keep-runtime` 仅保留本轮目录，下轮新 HOME 不算暖。沿 `DebugSceneDaemonClientRunner` 现有 first-present 通知扩展产品观测。Web 的 `--mwx-debug-web-startup-report` 终点是匹配产品 commit，轮询有约 20ms 误差；`forcedCold` 只撤预备进程，不清磁盘 cache，也不保证 WebKit 真冷。

**退出门：** 各测量条件能由实际 HOME/cache identity、PID/instance 和真实事件证明；缺可见事件的 run 标无效，不补造数值。停止重复归因，进入首个可证且可区分的改动。

### P1：Web descriptor/execution 共用依赖快照

1. 在现 `SteamWorkshopService` 准备核中形成同次 immutable input：库版本、entry/root、属性来源、locale、overrides 与资源授权 revision；actor 只装配产品状态。作者依赖 key 与 execution 投影 key 分开，单纯 overrides/grants 变化不重做作者依赖发现，采用仍绑定当前修订。
2. 合并 execution 与 analysis 的廉价失配检查；均可能命中时执行一次依赖发现/签名，用同一结果判定两份清单。解析与保存复用该快照，不再各自 BFS 全文读取。
3. 内存 memo、磁盘 envelope 和冷解析共用原 descriptor 构造核；先收敛重复职责，再删失去消费者的重复校验入口。共享 single-flight 按完整作者输入合并；一个等待者取消不撤其他有效请求，最后等待者撤销后停止领取/回填并 join。扫描保文件数、单项/总字节和检查 deadline 预算；deadline 不保证能抢占单次阻塞读取。
4. 采用前核版本/资源 revision，重建当前 grants；源变动或截断走保守原重算/风险档位，不用成功缓存掩盖未知。
5. 首批保留 `await saveWebRuntimeCache`，保存消费同次签名；await 不阻止 actor 重入，同 key 旧保存不得覆盖后继版本，删除不得被迟到回填复活，沿原 owner 轻量核提交 generation。各清单分别原子发布，双文件不是整体事务；两者错配/缺失各自拒绝命中。旧“编码/写盘后移”屏选已否决，不能用后移 0.9–4.5ms 的历史局部数值声称 App 收益或强行新增队列。

**反例：** 跨启动仅一份清单命中、include/JS/CSS 依赖新增/删除、同大小修改、扫描中变动/截断、overrides/语言变更、书签撤权、A/B 交错与旧保存。缓存不存 grants；冷暖产出的 descriptor、payload 和档位须一致。

**退出/重开：** 同输入不再重复发现依赖且输出相同即闭合职责；耗时另验。只有新产品计时证明保存仍占关键路径，才在此处修订后移设计；需原 owner 的版本 CAS、取消与退出 flush，不恢复独立保存队列旧方案。

### P2：Scene 一次安全挂载，按需读取，退出全量解包

1. 将 PkgReader 的产品入口改为已打开 FD 的 header/table 读取；检查索引大小/计数、完整路径、range、别名冲突与来源 receipt，避免为读索引加载全部 payload。坏索引不进入资源视图。
2. 在原 ResourceView 中接 package mount；向 Scene/project、AssetCatalog、模型、shader/include、TEX、脚本消费者交付同 generation handle。所有引用仍由原 resolver 排优先级，不改视觉算法。
3. 逐类迁移读取核，先跑 PKG 与等价 loose 的正反结果；字符串/模型引用、大小写冲突、可选缺资源的现行为保留，完整性失败与普通视觉缺失分开。
4. 接入媒体 URL-only 流式物化桥；先预算后分配，校验、取消、single-flight、部分写入与 provider pin 一并闭合。字体保字节入口；实际媒体首帧与字体输出不能由“已有 URL”替代。
5. 修改 SourceFacts 和 Host 输入，移除 `packageReport.outputURL` 必需条件；挂载合法 namespace 才是资格。迁移期仅允许开发/测试显式选择新旧 route 作对照，产品每请求只选一次来源，失败不静默回旧路径绕过安全检查。
6. 同输入验证后删除 extractor 的产品调用、旧完成 marker 的信任路径和双重目录扫描；工具专用解包可保留明确入口。旧 cache 按原预算/租约安全回收，不全盘删用户或未知归属目录。

**反例：** 截断索引/溢出 range/路径逃逸/规范化冲突、索引与 receipt 不符、实际 entry 同大小篡改、未用坏 entry 后续首次消费、读取中替换/截断、取消/并发物化、来源删除/更新被 pin、媒体/字体重新打开及失败后旧 active。

**退出门：** 所有产品消费者不依赖全量展开，所需 entry 结果/失败合同与来源身份闭合；暖挂载不读未消费 payload，首次不写无消费条目；实际首帧及峰值预算通过。若迁移失败，撤回本阶段完整产品 route，保留证据并修订，不长期维持两套 VFS。

### P3：复用基础内容和固定索引

1. package 索引直接由挂载表产生；stock manifest 在构建期生成或按 bundle 内容身份进程内一次构建，两者均由原 ResourceView 消费。loose mutable 根独立失效，不以 App 版本替代内容身份。
2. 分离 ModelBuilder 内不可变作者事实与属性/会话投影。PreparedContent 仅缓存自持 bytes/IR 和依赖摘要，初始容量一份、总字节预算显式登记；单份超预算直接不缓存，不能把“一份”当物理内存上限。
3. 命中前仍取得本请求的合法版本 lease/receipt，不能复活已删除/更新的 generation；loose 来源重新核实际解析依赖摘要。缓存不豁免 entry 完整性，不能直接存含 URL/ResourceView/属性投影的整个 RuntimeModel/SourceFacts。LaunchPlan 按当前属性/locale 生成，VM/clock/provider/history 新建。
4. 首批只在真实请求中填充；下载后预解析不默认开启。若后续证明确有命中收益，预热沿同 key single-flight 提升优先级，压力、新意图与退出取消，不能重复 build。

**退出门：** 相同内容不同属性不复用旧投影；修改依赖、内存压力、取消后迟到回填、更新/删除与第二次播放均正确。量完整首帧、命中率、RSS/峰值和稳态争用；无收益或预算回退则撤缓存，保留 P2 合法资源输入。

### P4：同 launch/device 共享成功 Metal library/PSO

1. 把 authored 成功 library/PSO 存储和 single-flight 上移到现 `ScenePreparedDeviceResources` 所属同 launch/device repository，encoder 消费成功对象。复用现有 binary archive，不新增第二磁盘 owner。
2. key 包含完整 MSL/函数/常量/编译选项、render state、格式/sample/write mask 与 device generation；不能跨不同 attachment 或 ABI 错用对象。
3. 每屏 encoder ownerToken/resetGeneration、graph target/history、binding 和 publication 保持独立。失败按原本次局部结果返回，不跨请求保存为成功；一屏取消不撤另一屏在飞创建。
4. 最后一个 borrower 退出、在途创建/等待者完成且相关 GPU work drain 后释放 repository；准备期取消也计入，不只数 Session。首批不做跨 launch 保温。分别测单屏与同/异尺寸双屏，避免拿额外驻留换局部 compileMs。

**退出门：** 实际同 key 创建次数减少、不同 key 不误命中，第二屏/失败/取消/重建/停止后输出与 lifetime 正确；没有全启动收益时只记录局部机制，不计整体提速。

### P5：Web 退休 worker 复用，保持双候选事务

1. 先用 P0 分清 daemon/AppKit、WebKit/WebView、页面资源与作者初始化；成本不在初始化则停止此阶段。主方案保留原 adapter 至多 active + candidate/warm 两个槽，不建第二进程池。
2. 拆开 transport 的 daemon instance 身份与每次 execution request/session generation。worker 的原请求不可改名；协议显式版本升级，旧版本拒绝新命令，不提供双生产协议 fallback。
3. 先实现 daemon-only 复用，再启用匹配配置的 WebView 复用。旧 active 由原事务在新候选可见后退休；退休先关输出/输入/音频并撤 grants/endpoints/watchers、取消导航/资源/网络任务，再 drain，不能先等持续任务自然清空。去掉旧 handler/user scripts 后，由专用 reset 状态只允许本机控制的空文档导航，确认旧文档失效；未证明后台 Worker/Service Worker 退场的配置不保留 WebView，必要时退出 worker。
4. child 回传 instance/request/sessionGeneration/reset nonce 全匹配的 ACK，父端在预期 retiring 状态才释放该 request 的 library lease；重复/迟到 ACK 无效，实际退出也能结清。ACK 前旧 scheme/Range/网络/目录任务与重开文件回调均已撤销/排空；每段有截止期，缺失/错误、超时、压力或父退出终止精确 worker。可再次 bind 还须原事务允许 endpoint 退休且无未决回滚/采用预约，不能仅凭资源 ACK 提前改名。
5. P5a daemon-only 必须先完成全部 surface/WebView/server/request 资源销毁与 drain ACK，再空闲。P5b 在其通过且 WebView 成本有依据后，以 HostCompatibilityKey 匹配 store/profile、资源 authority/root、origin、bridge/config schema、screen 布局；完全匹配才保留 standard WebView，否则沿 P5a。blank finish 不证明 BFCache/历史对象清空，必须防旧文档恢复和旧 generation 写入；公开 API 无法满足则退 P5a，不引入私有清理 API。空闲态无作者执行/授权/采集，persistent store 内容不全清。
6. 新请求只采用已 reset 的空闲 worker，注入当前身份/grants 后按原导航、snapshot、媒体 completion、可见确认进入事务。active 不原地改页；reset 中新意图遇到两槽已满，终止该 reset worker 并等精确退出后冷起候选，期间保 active 和原 newer-wins，不借此开第三槽。
7. 退休 warm 与原延后预备共用名额，reset/blank/drain 资源计总峰值；保留空闲超时与压力/停止退出策略，不以定时补进程。HTTP loopback 首批只用 P5a，不保留 view/server；退出在原总截止期内撤销扫描/reset/预备，shutdown 不重新补进程。

**反例：** A→B→A/同记录重设、不同 store/profile/屏幕、reset 期间新请求、迟到脚本/网络/媒体回包、同 store 两个 worker、取消/恢复、主进程死亡/阻塞、worker 崩溃、旧租约释放后更新/删除、cookie/localStorage 应保留而页面对象应清空。

**退出门：** 真实 ACK 后旧 request 无任务/授权/输入/采集，旧 lease 可回收；非兼容 key 全量重建；五次以上交替启动及最终长期切换门通过。P5b 无收益/清理不成立退 P5a；P5a 失败退单次 daemon + 空宿主预备，删除相应产品分支，不延 timeout 或减少 reset 验证。

### P6：Web 本地响应复用与 HTTP origin 边界

1. 在 scheme/loopback 原读取核内复用 HTML/CSS 转换结果，key 含内容 generation/resource digest、transformer schema 与影响输出的 profile/origin/token 投影。含 token 时缓存中间表示后按请求投影，不能注入旧 URL/grant。单项/总 bytes 及双 worker 总驻留设限，超大项不缓存，不持 grant/FD/来源 lease；为 digest 仍读全文时只认少转换，不能声称同时少 IO。
2. 保留每次资源授权与规范路径检查、ETag/Last-Modified/304、HEAD/Range/取消及背压；`no-cache` 是重验证，不等于 `no-store`。普通媒体已有分块，不重新做整文件缓存。
3. loopback 保留现有两种准入：带本 lease token 前缀的路径，或无前缀但携本 lease cookie 的请求；不是每个请求都要求 token AND cookie。先覆盖同 store 的 active/candidate 并存：cookie 不按 port 隔离，见 [RFC 6265](https://www.rfc-editor.org/rfc/rfc6265#section-8.5)。cookie 名/删除按自身 lease 区分，不能覆盖后继凭据；这只解决冲突，不证明跨端口请求来自哪份文档，根/grants/token 的原安全边界不得放宽。
4. 首批不强行固定端口、不为稳定 URL 跨 author 合并 origin、不把同 origin 下多个活跃 grant 取并集。保持现有随机 token 路径与逐 session 授权；高兼容档跨重启的 storage/HTTP 缓存身份尚未解决。
5. 只有 P0 的真实缓存/存储反例确认 origin 变动为目标成本，才另修订本节确定单一 origin 授权 owner、双候选路由和端口冲突退出；在此之前不启用高兼容 WebView 复用，也不新增 broker/第三进程作为整个专项前置。

**退出门：** 同内容转换次数减少且当前 token/授权正确，源修改/依赖变化即时失效；跨 worker cookie 不干扰、撤权有效、媒体与框架加载相同。origin 稳定与 HTTP/Code Cache 实际命中另报未知，不能由 store UUID 稳定推断。

### P7：整体验收、退役与收尾

1. 在原始基线、直接前驱和最终版本之间按第 5 节比较，避免多批局部收益掩盖累计回退；保留有效反例和未采用方案的 STOP 原因。
2. 删除已经替代的产品 extractor/重复扫描/实例缓存与旧一次性资源释放假设；未采用阶段撤原型、测试桩和 flag。仍有工具消费者的代码保留明确工具归属，不能只改名称冒充退出。
3. 当前能力/运行事实分别同步 Scene 能力与证据、Web current-state；稳定资源输入、身份和生命周期回到原合同。本文只保阶段结算与剩余条件，不复制运行台账。
4. 结束时按精确路径清理隔离 HOME/App/DerivedData/cache、样本副本和重试输出；有限最终证据沿[产物规则](../../.agents/skills/mywallpaperx-maintainer/references/artifact-governance.md)保留。未知归属与唯一失败证据先保留。

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

正式统计沿[性能卡](../scene/roadmap/performance-convergence-card.md)：启动每条件至少五个基线和五个候选，交替顺序；固定配置、输入、温度状态及缓存策略。记录中位、范围与原始 run，不用五次宣称尾部分位数。先冻结噪声与非目标预算，超噪声先排干扰，不能删慢点或放宽门。

用户可见主指标：Scene selection→实际 presented→产品 finalize，accepted 为中间分段；Web selection→匹配 commit 并单列 snapshot/窗口可见，不称物理呈现。辅助指标包括主线程最大 stall、读取/写入字节、各缓存真命中、首次完整内容、峰值/稳态内存及停止后资源；准备期间旧 active 连续性同样验收。普通优化产品与诊断配置分别报告；Release 不新增详细观测。

Swift 产品改动需签名 Debug build；GPU/VM/资源/宿主改动需隔离真实输出和下一帧、暂停/恢复、失败/取消及 drain。最终执行至少 30 分钟稳态、20 次轻重切换/resize，并覆盖停止/退出、压力、睡眠/唤醒和显示器变化。缺最低设备、多屏或 Release 时明确未验，不扩大声明。

### 5.3 最近工具与测试

- 先用 `python3.12 -B script/verify_scene_change.py --phase inner --path <owned-path>` 预览真实模块，再按实际输入选 `run_scene_tests.py --module <name>`；不得把未映射或源码形状门当行为验证。
- Scene 最近候选：`test_scene_pkg_cache_extractor.py`、`test_scene_resource_view.py`、`test_scene_asset_catalog_resource_view.py`、`test_scene_persistent_cache_behavior.py`、`test_scene_pipeline_repository.py`；P2 必须补真实 range/物化行为输入，不能只让旧测试消失。
- Web 最近候选：`test_web_runtime_cache.py`、`test_web_launch_profile.py`、`test_web_response_transformer.py`、`test_web_property_persistence_gate.py`、`test_playback_process_isolation.py`；其中属性 gate 测试主要检查 parser/评分，真实运行另走 `script/web_property_persistence_gate.py`。IPC/reset、双 cookie 与授权反例补在原 owner 最近门，不能以进程存在证明 WebView 已热。
- `playback_process_isolation_benchmark.py` 用于真实进程/交接反例，不是启动 A/B；`scene_wallpaper_performance.py` 是日志解释工具，`web_wallpaper_benchmark.py` 是运行能力/画面证据入口，均不独立证明首帧提速。

## 6. 取舍、未定边界与停止

本设计批准原 owner 内的资源输入、依赖准备、同 launch 共享与 standard worker 退休复用边界；不预批准跨 launch GPU 常驻、全库预解析、高兼容稳定 HTTP broker、绕过授权或新视觉算法。P5/P6 的入口成本/实际协议门未满足时，停留在已闭合的前驱机制，不把未实施写成完成。

连续两次有区分力短实验仍无收益或非目标越门，停止该方向，查明成本是否转移后重排；正确性/安全失败立即修正或撤回。可靠小幅局部减工可按现性能卡保留，整体比例和能耗未知如实报告，不能以强行达到预写百分比扩大范围。

专项结束条件：实际采用阶段通过产品冷暖与失败/退出门，替代 owner 退役，剩余项有明确停止/未验结算；或用户结束专项。完成后将执行结果归历史，长期边界留原合同，索引退役本 active-plan。设计门的 `approved` 只表示边界可实施，不代表产品实施、性能、官方一致性或发布通过。
