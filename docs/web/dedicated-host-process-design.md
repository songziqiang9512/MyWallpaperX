<!-- document-role: active-plan -->
<!-- retirementCondition: 独立 Web 播放与三引擎交接验收完成，稳定合同接管后归档。 -->

# Web 独立桌面宿主与切换交接

状态：2026-10-18 已接入唯一独立播放入口，Debug 签名构建与协议/生命周期门通过；物理 Space、长稳与全作品兼容另验。

## 目标与依据

最小 WKWebView 对照在桌面和普通窗口层级均复现同进程主窗口最小化/恢复的约 0.5–0.7 秒 RAF 间隔；只有桌面 WebView 的独立 accessory 进程在另一进程窗口动画期间未复现该量级停顿，真实 Space 切换仍有约 120ms 间隔。该证据支持隔离主 App 窗口事件，不支持承诺全部系统/作者内容零掉帧。

本批把唯一生产 WKWebView、桌面 NSWindow、页面 bridge 与输入生命周期迁移到专用进程。保留作者页面、属性、资源规则、系统歌曲信息、音频频谱、暂停与多屏行为。Video/Scene 复用既有独立播放进程；三者统一遵守控制面与播放面边界，不为统一名称重写已成立的渲染器，不引入第二套 Web runtime interpretation。

## 所有权与协议

`主 App 请求/设置/共享音频与媒体服务 → WebDaemonHostAdapter → 有界 NDJSON → WebDaemonRuntime → 既有 DedicatedWebWallpaperHostPlaceholderAdapter → 每屏 WKWebView`。

- Web 产品进程与空宿主采用 `.prohibited` 激活策略，与 Video 后台入口一致，不能取得前台焦点；桌面 surface 在 AppKit 启动后按 IPC 创建、以非 key 窗口显示。只有显式 DEBUG evidence 窗口允许 `.accessory`，便于独立画面取证。
- 主 App 不再创建生产 WebView。沿用同一可执行文件的独立 `--mwx-web-daemon` 入口，在产品装配前进入禁止激活的后台 AppKit run loop；普通 XPC service 不持有桌面窗口。
- 请求 DTO 只传不可变 URL、属性、可信 typed resource grants、profile、语言、显示配置与白名单；`PlaybackResourceLifetime` 留在父进程，直到对应子进程退出。命令/事件带协议版本与 request UUID，准备/提交另带 surface preparation generation，旧进程或旧请求不得发布状态。
- 属性、暂停、音量、速率、显示配置走有序控制；频谱只保留最新值并以控制为屏障。stdin、stdout 均限制积压与单帧大小，EOF/协议失败结束该子进程，不能继续显示失控旧内容。

属性消息携带独立的 property/resource revision 和完整授权替换快照。已提交 request 在崩溃恢复等待、恢复候选和显示重建期间也必须同步最新属性与撤权；不能只更新 active，也不能把另一用户选择的候选当作已提交 request。已退出 transport 只更新原恢复输入，不写 dead pipe；重启、reload 与多屏继续消费同一请求事实。授权粒度和消费边界归[运行模型合同](web-project-json-runtime-model.md#24-playback-context)。
- 系统歌曲信息仍由主 App 的唯一 SystemMediaService 采集。子进程只聚合页面 demand、接收可还原完整状态的 Web 投影并投递各 frame；不传 Scene 原始封面，缩图仅在身份变化时传递，缺少同身份基线时有界请求完整重放。频谱也不在子进程新建采集器。
- 父 adapter 投影每个存活子进程的持久 store 使用与记录 identity；回收不能误删尚在运行或准备的 store。diagnostics 回传到原 store；网络授权沿用原声明白名单，不扩大根目录。

## 三引擎共同隔离合同

- 主 App 只拥有用户意图、设置、共享采集、异步控制与状态投影。Video、Web、Scene 子进程各自拥有窗口、播放时钟、渲染、输入及本地暂停状态；持续播放不需要主 App 心跳或逐帧许可。
- 唯一共享音频采集在后台通过带身份的线程安全投递端直接写入有界 transport，不经过 AppKit 主队列。控制面只更新投递目标与需求；Scene 保留 capture scope 与 daemon generation 校验，旧端点在停止/替换时撤权。系统歌曲信息按事件传完整快照，不能阻塞子进程播放。
- 页面音频需求由现有frame endpoint登记持有：注册必须绑定surface、文档nonce与endpoint token；主导航撤销该surface全部端点；早于hello/ACK的注册在确认后重报。屏幕及主App只聚合仍存活端点的需求，不保留独立screen Set真值。goodbye、导航换代、租约失效、拆屏与teardown沿同一退役路径撤销；其他端点仍需求时不得停共享采集，Scene/Video聚合不变。持续频谱只向声明需求的端点投递，旧evaluate completion/ACK不得恢复需求或flush撤销端点。页面恢复须以当前有效身份重新声明，不能靠旧租约复活。
- 验收须覆盖唯一音频iframe移除后原生采集停止、双消费者只退一个仍播放、晚注册/重复ACK/导航/租约/重建与全退役；沿真实IPC+系统音频验证，不能只以JS事件计数或进程退出当需求回收证明。
- 三者沿用同一个 DaemonProcessTransport 的有序控制、最新值合并、EOF 与退出合同。引擎专属协议/首帧判据保留，避免通用包装抹掉实际就绪语义。
- 暂停或撤销频谱需求时，投递端先向旧合法 Video/Web 端点发送一次有序静音屏障，再拒绝迟到采集；不能只清父端快照而让子端保留旧柱高。Video 子端 CommandReader 仍逐条投递主队列；父死亡/EOF 已有共同后台硬截止期，入站合并仍为待收敛边界。
- 跨引擎准备期间保留旧输出。Web 在 snapshot 后补齐媒体 completion 和 WindowServer 确认，Video 在 AVPlayerLayer 就绪后补齐逐屏窗口确认，Scene 保留实际 first-frame-presented。唯一产品交接由 [播放生命周期与切换事务](../architecture/playback-lifecycle-transaction-design.md) 约束，主 App 确认旧输出退休后才 finalize 新输出。系统 Space/WindowServer/WebKit 本身调度仍可能带来短停顿，进程隔离不声称消除系统级暂停。

## 启动身份与 Dock

Web/Scene 复用主可执行文件，应用包默认以 `LSUIElement=YES` 的后台身份注册；这发生在 Swift 入口之前，避免启动后再隐藏普通 App 图标的闪现。主 App 的 `MainWindowCoordinator` 继续独占角色切换：打开主窗口升为 `.regular` 并显示唯一 Dock 入口，关闭主窗口回到 `.accessory`。Web 产品入口保留 `.prohibited`，Scene 保留现有后台窗口策略，子进程不执行主窗口装配。Debug/Release 构建声明一致。

采用已有主窗口角色权威，避免为启动图标另建 helper target 或改变 IPC/进程复用策略。验收检查构建产物的实际 Info.plist、子进程从启动通知开始的策略，以及普通主窗口的 Dock、最小化、关闭/重开和焦点行为；命令行 helper 或单次调用 `setActivationPolicy` 的通过不能替代应用包启动身份验证。

## 候选与交接

- 至多一个活跃 Web 子进程与一个候选。新请求取消旧候选，保留旧活跃画面；失败或超时仅结束候选。显式停止/跨引擎停止撤销两者和所有订阅。
- 点击后的异步作品准备与同 UUID 的空宿主启动并行；预备宿主尚不读取作品、不创建窗口或订阅采集。完成后将同一 transport 原子交给候选 Session，未完成的 hello/协议帧继续由新 Session 消费。新选择、准备失败、显式停止或 15s 未采用会结束请求预备进程；异步完成另以主 App 唯一产品意图 epoch 的只读快照拒绝迟到发布。预备与候选共用一个名额。
- 候选窗口先位于活动壁纸之下，不在 HTML 导航完成时覆盖旧画面。导航 ready 后对当前每屏 WebView 执行一次原生 snapshot preparation；成功只说明可生成当前渲染内容，不冒充物理显示呈现时间。
- 父 adapter 只报告准备/可见事实；WallpaperManager 事务授权激活，候选暂升 desktop + 2，旧输出确认撤下后 finalize 恢复常规层级。候选准备期间静音且不接管桌面输入，交接时应用当前音量并启用输入，避免两份作者音频重叠。显示拓扑改变会撤销旧准备代际，不能用旧 snapshot 的确认提交新 surface 集。
- 跨引擎退休由唯一产品事务下达，运行时通知仅投影提交事实；Video/Scene 的原生准备和资源链仍归执行端。审查所有方向的现有 ready/retire 时机，只有实际通过的方向可声明视觉连续；不以 `didFinish`、process alive 或 `.launched` 名称替代首帧证据。
- 接受新意图时立即撤销旧导入的自动播放票据与过期候选，不能依赖延后的可见交接通知。撤销准备同时恢复实际 active 的请求投影；坏 Video、准备失败及验证早退不留下虚假的 kind/path 或继续启动的候选进程。
- Scene 沿用现有 Host 唯一输出 owner，跨进程首帧事务补齐 prepared → commit → first-frame → finalize。最终确认前保留旧 Scene standby；新意图撤销时可以回滚已准备或尚未 finalize 的候选。commit 后另设 5s 实际呈现截止期，daemon 收到同请求 presented 即撤计时，仍等父 finalize 退休旧输出；无 presented 则回滚并报失败，父主线程阻塞不造成已呈现候选误超时。版本租约保留到对应准备/GPU 使用结束确认或进程真实退出，不在父端撤销身份时提前释放。此扩展只管启动交接，稳态渲染不等待父进程逐帧许可。
- Video 保留既有双 AVPlayer slot，以 prepared → commit → ready → finalize 约束显示与旧 slot 释放；取消只撤未确认请求，保留已提交 slot。多屏须全部目标准备、确认后才退休旧显示集；延迟淡入和清理绑定请求代际，不能清掉后续新 slot。
- 失败时事务撤销候选并恢复已提交端点活动权；Video helper 缺失时以同产品票据的新执行代际恢复。已提交 Video 的 ended 按播放 UUID 暂存，新意图准备期间不抢播；回滚到相同播放代际才消费一次，重新提交同路径或停止即撤销旧终态。自动切换 timer 只为已提交且当前意图仍为 Video、没有新候选的播放启用。
- WebContent 自身崩溃沿原页面恢复机制；宿主进程退出通过当前 request 的有界重试恢复。新选择、停止和退出使旧重试失效。准备失败保留旧安全画面，父 App 退出先关闭共同进程登记的准入、推进产品意图与异步解析代际，再正常关闭 stdin 并有界回收所有精确进程，等待实际退出，不能在等待 Scene 回收期间重新创建 Web。

## 启动优化：有界空宿主与最小首帧探测

目标是在保留隔离、作者样式和旧输出回滚的前提下，缩短用户点击到 Web 提交的等待。参考 Mirage 的专用播放入口、候选交接与极小区域快照；其源码不证明本项目的耗时占比。当前每次创建宿主，WebKit/作品初始化和快照在关键路径；Scene 冷准备另有独立内容成本。

本片选择已有 adapter 内一个有界空宿主，避免新增进程池 owner 或修改共享 Xcode target：

- Web 成功提交后延迟 2s 预备下一空宿主；启动延后 3s 时仅在本地有可播放 Web 记录且无候选时尝试一次。空宿主至多一个，30s 未采用即退出，超时不自行补充；不读取作品、不建 WebView/窗口、不运行作者脚本、不采集音频。内存压力、显式停止、跨引擎意图与 App 退出撤销预备及延迟任务。
- 空宿主 UUID 在创建时确定；App 装配把该 UUID 作为下一用户请求的 requestID 返回，随后请求保留原意图 epoch 和全部 guard。没有把旧作品请求改名、复用旧页面或重贴迟到事件。采用时转换为请求预备，重新给予原 15s 截止期；hello 前后均可采用。无空宿主或预备失败仍走现有冷启动。
- 原 `hasPendingRequest` 只计用户请求，不把无内容预热投影为加载态。进程清单仍包含空宿主；资源 store 使用只从真实 Session 汇总。准备、候选、空闲共用一个名额，活动输出另一个名额，retiring 保留至真实退出。
- 每屏首帧检查改用中心 1×1 区域，并要求 afterScreenUpdates；保留 surface/准备代际校验与全部目标完成门，不删首帧确认来换取计时。
- App 延后预热只为实际 Scene 意图保留 Scene daemon，不因当前 Web 或泛化的旧工坊身份额外启动 Scene。Scene 内容准备及渲染线程不在本片迁移；精简 executable 与线程迁移需各自成本证据和设计，不能与本片混做归因。

验收先在同一 Debug 身份、相同隔离作品与 HOME 条件记录正常产品入口到提交，区分有无提前存在的进程，包含首次冷启动；再执行采用、过期、停止、跨引擎、失败留旧及真实音乐连续性。只在有效样本显示收益时保留；无收益则撤回该优化而保留隔离和正确性修复。首帧探测完成仍不冒充物理 presented。常态不启用性能 runner 或持续探针。

## 验收与退出

协议 roundtrip/畸形与超大输入、同 ID 新 request、迟到事件、控制与频谱屏障、EOF、快速切换、失败保留、停止后媒体/音频撤销、资源保留至退出须有行为反例。Swift Debug 构建后用隔离真实 Web 样本验证属性、暂停、频谱、真实音乐歌曲信息与窗口/Space 操作，并检查三个引擎切换的实际画面和进程。

唯一生产入口切换后，原 host 类仅由 Web 子进程和明确测试 harness 构造；不保留用户可切换的双生产宿主。若独立宿主并未改善主窗口动画停顿，回退整个生产路由并保留诊断证据，不继续叠加无依据的 WebKit 私有设置。

运行门：`script/playback_process_isolation_benchmark.py --app <Debug可执行文件> --runtime-home <全新目录> --output-dir <全新目录> --scene-root <只读样本副本>`。native runner 对主 App 主线程阻塞 1.25s；检查真实音乐、Web RAF/本地 run loop、失败保留、进程恢复、六方向交接、Web 同类型替换和实际退出。冷 Scene 准备可等待至 60s，整体门默认上限 240s，包含实际 31s 采用存活及 30s 空宿主退出检查；不能据此宣称即时启动。内存压力导致未创建预备进程时，缺前提记为 notCovered、总门 INCOMPLETE，不能作为全项 PASS；实际已创建者仍检查 PID 真实退出。实际物理 Space/窗口操作用 `--mwx-debug-web-continuity-log <jsonl>` 单独记录；`--mwx-debug-web-disable-policy-pauses` 仅供排除暂停策略，既有策略与产品默认值不改。此测量记录含暂停转换及页面频谱到达/变化计数，RAF 探针不等于作者画面逐帧验证。空目录须在 URL 构造前拒绝，不能隐式扫描进程当前目录；空属性不建立轮询，实际选择的目录与缺失后恢复仍保持原语义。`test_web_directory_sync` 以非空 cwd、属性/文件改名、清空与合法路径为反例。
