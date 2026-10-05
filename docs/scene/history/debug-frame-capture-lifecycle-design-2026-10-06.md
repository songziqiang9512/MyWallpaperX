<!-- document-role: historical-evidence -->
<!-- retirementCondition: 诊断请求有界、单次终结、独立 readback 导出及 surface/session/隔离退出 drain 通过行为门，稳定诊断合同接管后归档本文并删除对应设计登记。 -->

> **历史证据 — 非现役入口**。现役职责见[运行架构](../architecture/runtime-architecture.md)，后继顺序见[暂停交接](../roadmap/scene-maintainer-handoff-2026-10-06.md)。

# Scene 调试截图导出生命周期（已完成设计）

2026-10-02，设计边界 approved；属于 [P 路线](../roadmap/scene-compatibility-roadmap.md) 的 [RF05](../roadmap/batch2/reference-evidence-implementation-cards.md) 派生片，排在 RF01 后、RF02/RF03 前。批准不表示实施、GPU、性能或发布验收。本文只使用我方代码及已定位诊断现场，不依赖第三方实现、私有 shader 或新的作者语义。

> 本有界设计已完成；冻结验收见[实施记录](rf05-debug-capture-lifecycle-implementation-2026-10-02.md)，稳定约束由[运行架构](../architecture/runtime-architecture.md#debug-capture-lifecycle)接管。本文后续的实施语气保留历史背景，不是现役待办；RF05整卡仍有其他余项。

## 1. 已证偏差、产生者与准入判定

`MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneDebugFrameCapture.swift:55` 的 Metal completed handler 同步进入 persist；`:88` 做16F逐通道转换，`:116` 编码PNG，`:127` 写盘。它延长诊断回调占用，已影响短 HDR 证据窗口；不能把全部资源峰值归因于此，也不能把短窗口统计失败升级为 GPU 故障或性能结论。

真实请求产生者是 `MyWallpaperX/App/Debug/DebugScenePlaybackRunner.swift:411` 的 ready/after、`:480` 的 periodic，以及 pointer/resize/switch/relaunch 等有限诊断事件。`DebugScenePlaybackRunner+Arguments.swift:42` 允许 periodic 最低80ms、`:14` 允许运行至3600秒；持续请求和没有 drawable 的序列能使现有 pendingRequests 无界增长。这里的额度门有具体产生者，不是为未知输入补防御。

当前请求经 Host:130 → Session:301 → MetalView+Debug:5 到 Capture:22。renderer 在 `SceneMetalRenderer.swift:937` 编码readback，然后仍可能 seal拒绝；PreparedFrame.cancel也可放弃提交。Capture已经removeFirst，不能把未提交CB的析构回调当必达终结。Runner:393 stop后只延迟0.2秒退出，AppDelegate:176对隔离Scene直接terminateNow。Host.stop先retire会话，Session.stopAndDrainGPU:15保存queues后调用stop；SurfaceTeardown:31清空surfaces。事后从Runner收集capture会漏掉已释放或正在退役的surface。

设计前置五判据：①**是**，跨诊断、提交、surface/session teardown和隔离退出；②**是**，触碰独立readback资源的completion/释放及现役drain完成边界，但不改变播放clock/publication；③**否**，文件是可重建诊断证据，不改变用户数据或持久化格式；④**是**，触达现役Frame/Session冻结职责，不能增长平行协调器、registry或基线；⑤**是**，仅核对公开Metal完成等待合同，不依赖Wallpaper Engine私有语义或框架。D10只批准模拟/呈现合同，resident-resource设计只批准分配账，均未裁决请求终结和CPU导出drain，故新增 `scene-debug-frame-capture-lifecycle` 登记，不借旧approved扩权。

## 2. Owner 与最小实施边界

| Owner | 输入与输出 | 本片边界 |
|---|---|---|
| DebugScenePlaybackRunner | 具名诊断事件 → 截图请求；关闭意图 → finish | 关闭既有生产者，不新建任务registry、timer或退出owner |
| SceneDebugFrameCapture | 请求 → 独立MTLBuffer → PNG或明确失败 | 唯一诊断请求/导出状态；仅DEBUG；进程共用串行utility导出lane，capture各自拥有可等待outstanding |
| SceneMetalRenderer.PreparedFrame | 最终drawable结果 → readback blit | 仅在既有submit闭包、present/commit前调用；准备cancel不消费 |
| SceneResourceBudget/Allocation | 原生heap size → 现有buffer租约 | 继续makeSceneBuffer；实际MTLBuffer只有一份总账租约 |
| Session.stopAndDrainGPU / retireSurface | 冻结queues和captures → GPU terminal → DEBUG导出terminal | 现役会话/退役集合保留引用，不增加capture registry |
| AppDelegate | 隔离Scene终止申请 → terminateLater → Runner.finish → reply | 使用既有terminationReplyPending；非隔离产品、daemon-client和Web原出口不变 |

生产代码owned paths是现役Capture、SceneMetalRenderer、MetalView+Debug、Session的DEBUG请求入口/Shutdown、Host的DEBUG请求入口、DebugRunner/HostOwnership/SceneSwitch/SurfaceStopRelaunch/PauseResume/Performance和AppDelegate的隔离Scene分支；SurfaceTeardown沿现有retireSurface入口，不另改owner。Performance:163的非法FPS延迟直接terminate也是实际产生者，归同一Runner退出方法。测试沿现有capture、surface submission/teardown、debug runner与benchmark模块扩展。无需修改shader、时钟、VM、provider准入或其他卡。

## 2.1 Runner 证据调度可测试边界（2026-10-03）

当前 benchmark 测试以源码字串查找同步 launch，无法验证现役异步入口。批准在同一 `DebugScenePlaybackRunner` 中把 evidence launch、普通/periodic capture 和初始 pointer-vs-regular 分发移到 `DebugScenePlaybackRunner+EvidenceSchedule.swift`；主入口保持原调用位置与后续安排。保留 launch 前 pointer 预置、await 前后 closing、异常传播及现有 DispatchQueue 调度，不改变 interval、资源提交、clock、capture owner 或取消语义；不新增注入协议、第二 scheduler 或产品状态。

行为 harness 编译实际 EvidenceSchedule、PointerDrag 与 Arguments 扩展，使用 harness-only runner/host 和事件 sink，在 host 暂停时证明无提前 capture，覆盖启动失败、await 期间 closing、正常/drag/hover/click/periodic 和参数无效值。主动提前 capture 或交换 pointer 事件应被 oracle 拒绝。只声明诊断边界的调度行为；真实 GPU/completion 仍由原 capture/资源门验证。harness 的调用方替身负责 await 后再调度，提前 capture 反例验证 oracle 能拒绝坏顺序，但未执行真实 `launchScene` 主函数；实际主入口顺序由独立静态审查核对，Debug build 只验证接线与类型。提取本身不代表完整入口、GPU 或视觉验收。

## 3. 有界请求与预算政策

这是**项目诊断策略**，不是官方作者合同。首片固定每个capture最多两个待编码required请求和一个待编码periodic请求：两个required槽对应已存在ready/after的独立证据义务；一个periodic槽只保留最新周期请求，防止80ms产生者将无drawable窗口变成积压列表。pointer/resize/switch等事件也属于required，并共享这两个槽；满时立即明确拒绝新请求，不把调用方挂起、不新增隐藏溢出列表。后续调整必须有实际请求负载和相同反例依据。

请求类型由Runner产生者显式传递，periodic只有schedulePeriodicSnapshots使用；不凭reason前缀猜优先级。新periodic替换已接收的pending periodic时，旧请求以 `superseded` 失败终结；ready/after及其他required不被periodic挤出。未接收请求返回明确rejected结果及reason/stage；已接收请求拥有局部诊断request ID，恰好一次产生persisted(path)或failed(stage)。不把surface-found布尔或enqueue成功当PNG成功，不重复由Runner和Capture报同一失败。

进程待导出buffer最多两个，**GPU尚未回调、CPU排队和CPU正在导出都占此额度**。两槽允许一个CPU任务运行时下一次真实readback完成并交付，验证completion独立性；不为吞吐增长更多并行PNG。现有Capture内部共用一条串行utility lane及count/byte backpressure；它只记工作额度，不保存capture集合或注册资源identity，不是新allocator/registry。字节上限取 `SceneResourceBudget.shared.maximumBytes / 4`：现役resident设计已将可重建decode缓存局部限制为总额四分之一，本片选择同量级局部上限，保证诊断不能凭两张超大图独占总额；这是明确项目选择，不声称OS内存保证。各capture仍竞争唯一全局resident总账，active/candidate/retiring叠加不会取得独立工作槽或总额度；各自outstanding归原capture，用于现役Session持有引用并等待。

实际buffer通过现役 `makeSceneBuffer` 分配，按 `heapBufferSizeAndAlign(...).size` 比较诊断byte上限；不能再对同一GPU对象reserve第二份租约。诊断counter只记录未terminal的工作额度，MTLResource上的既有lease持续记真实resident，最后引用释放才归还。CPU lane只有一个运行任务；现有16F转换可控scratch最多为一份words和一份Data，即2×有效像素byteCount，BGRA8最多一份Data。进入复制分配前，以checked乘法计算实际可控scratch并用同一SceneResourceBudget的现有decoded额度预留；沿现有reserve/release加锁合同，失败终结为cpu-scratch-budget，task所有出口释放。这是不同物理CPU副本的记账，不重复收费GPU buffer，不增加allocator；它与decode缓存竞争总账内现有四分之一decoded子上限，不再取得独立CPU总额。实现可在GPU完成、该buffer仅归CPU任务后原地16F→u16，并让no-copy provider保留buffer至PNG写完，以减少或消除显式全帧副本；按实际副本成本计入decoded子额，所有权和16位像素合同不变。这是同一边界内的实施选择。autoreleasepool及时释放临时对象；CGImage/PNG encoder/driver内部瞬态仍属resident设计明确未计入的库内存，只承诺单任务和有限像素输入，不把可控scratch或局部额度称RSS/OS OOM保证。

在分配前冻结width、height、pixelFormat和rowBytes，沿现役BGRA8/RGBA16F准入。width×bytesPerPixel及rowBytes×height使用有效的overflow检查；任何溢出、unsupported format、byte上限或原生分配失败均终结该请求，不能产生截断buffer或越界copy。已接收required遇到暂满的两buffer槽只保留在上述有界pending槽，留给后继实际提交；finish/teardown即明确失败尚未编码者，因此不能无限保留。额度拒绝只影响诊断，不影响该帧提交和健康输出。

## 4. 提交、handoff 与单次终结

将encodeFrameReadback从prepare末尾移入现役PreparedFrame.submit闭包，在present/commit之前执行；位置仍在最终compositor、Bloom及SDR映射之后。prepare/封口失败和PreparedFrame.cancel不消费请求、不分配buffer，不借测试故障或 sibling surface失败吞掉ready/after。

成功建立readback时，**在注册completed handler和commit之前登记outstanding并占用工作额度**。该登记覆盖GPU已完成但capture回调尚未完成handoff的间隙。blit/setup失败在同一责任内终结并释放；completion失败同样终结，不进入PNG。[Apple waitUntilCompleted](https://developer.apple.com/documentation/metal/mtlcommandbuffer/waituntilcompleted()) 等待的是该CB的GPU工作及其所有completion handlers；不能据另一barrier CB的wait，推断前一capture handler派生的异步CPU工作已完成，不能用导出queue.sync空block替代outstanding drain。

成功completed handler只把独立shared MTLBuffer及冻结的值元数据交给导出lane。闭包不得将drawable、source texture、SceneMetalView或completed commandBuffer带入CPU任务；无需在CPU阶段读取source dimensions/pixelFormat。lane完成16F转换、16位PNG编码与atomic写盘后才发布persisted；任何PNG/write错误发布failed。所有终结路径恰好一次释放工作额度、减outstanding，缓冲最终引用沿原lease释放。原输出路径和PNG精度保持既有合同，不使用 `@_optimize`、私有shader或改变tone-map来遮掩诊断成本。

capture close先拒绝新请求，再对所有pending请求发布teardown失败；已提交readback继续用自己的buffer完成导出。**closed且outstanding为零是唯一导出drain完成条件**，多次close/drain可注册等待者但不得重复终结、重复写文件或重复释放。阻塞CPU导出不持有状态锁；completed handler只短暂更新状态，不能等待PNG队列或主线程。

## 5. 沿真实停止链关闭与等待

1. Runner唯一finish从running转closing；关闭requestSnapshot入口和后续派生调度。具名重建产生者还包括 `DebugScenePlaybackRunner.swift:31` 的延迟首次Task、`:220`的异步launch回包、`DebugScenePlaybackRunner+SceneSwitch.swift:71–75` 的延迟Task.launch、`DebugScenePlaybackRunner+SurfaceStopRelaunch.swift:38–41` 的延迟relaunch。在真正launch入口和await/回包后均核对同一closing状态；不得关闭后再创建session、setPlaybackPaused或安排snapshot。Host既有cancelPendingLaunch处理已开始的launch，不新建任务框架。
2. Runner调用唯一Host.stopAndDrainGPU。Host.stop先retire是现役事实；Session必须在当前snapshot queues位置，同时freeze/retain active和retiring surfaces的capture引用，**先封capture请求，再调用stop清surfaces**。不能等Host.stop返回才从activeSession收集。
3. existing GPU barriers按现役队列等待terminal，保留原GPU结果。DEBUG分支随后等待冻结captures的outstanding终结，才finishDrain和释放retiringSession。barrier创建失败仍记GPU失败并等待已有capture终结；无queues也必须处理捕获集合，不能因空数组直接把所有诊断当完成。Bool仍表示GPU结果，PNG失败用独立诊断terminal/drain结果表达，不使诊断参与产品GPU准入。
4. retireSurface在GPU barrier terminal后也等待该surface capture导出drain，再从现役retiringSurfaces移除。否则GPU先完成会释放唯一可等待capture，稍后whole-App finish会漏它。barrier创建失败不能提前移除；保留现役surface由后续Session drain接管，明确GPU失败。
5. 隔离Scene的scheduled stop、正常终止及重复Runner finish归现役Runner终态。AppDelegate仅拆开Scene/Web合并的DEBUG分支：已有finishResult（包括GPU失败终态）直接terminateNow；尚未terminal时复用terminationReplyPending返回terminateLater，实际drain后只reply一次。terminateLater可能在主GCD block内进入AppKit modal run loop，DEBUG Session的必要完成交付及最终reply须能在该mode前进，不能再排到被嵌套等待的同一GCD队列。Release保留原派送；daemon实际也使用NSApplication.run。Runner已closing后抑制自有迟到终止产生者。Web保持原terminateNow，非隔离产品仍prepareProductTermination→daemon shutdown→reply，daemon-client原入口不变。applicationWillTerminate只执行已完成finish的幂等收尾。真实AppKit探针确认modal等待内再次直接NSApp.terminate可能跳过delegate强制退出；本片不扩NSApplication subclass或全App退出owner，此外部强退不保证graceful drain，不能把重复Runner finish测试写成拦截框架强退。

首片不引入“超时后仍继续写最终文件”的假成功分支。正常关闭异步等待实际终结，不阻塞主线程。benchmark现有 `script/scene_wallpaper_benchmark.py:7454–7462` 的duration+60外部超时/TERM/KILL仍判该运行失败；TERM/KILL不保证走AppDelegate，不能称graceful drain或补造terminal成功。若以后要内部deadline提前返回，须先设计取消后的最终文件发布门，不能只加常量超时。本片不扩展信号处理或全App退出政策。

## 6. 行为门与冻结

| 门 | 可执行输入与反例 | 必须观察的结果 |
|---|---|---|
| completion独立 | 并发barrier/semaphore阻塞真实CPU导出；提交本帧及后继真实Metal CB | 两个completed事件先完成，PNG仍未完成；释放barrier后导出与drain完成，无sleep猜时序 |
| 独立snapshot | readback完成后覆写/释放原texture及surface，再释放导出barrier | PNG保持原帧像素、尺寸和16F精度；任务不依赖drawable寿命 |
| 请求有界 | 无drawable/导出阻塞时持续periodic，并夹ready/after及第三个required | pending不超过2 required+1 periodic；替换、拒绝、关闭各有具名terminal；accepted各恰好一次结果 |
| buffer/byte有界 | 注入小额度、阻塞worker，连续真实readback及不同尺寸/格式 | GPU/queued/running合计≤2，超byte与全局预算明确拒绝；不产生无限buffer；释放及失败后真实lease回落 |
| 提交cancel | seal拒绝、PreparedFrame.cancel后下一帧成功 | 取消不consume请求、不分配readback；同reason后继成功或teardown明确失败 |
| completion/drain竞态 | 控制GPU barrier回调先于capture completed handler enqueue | drain不得提前完成；outstanding覆盖间隙；PNG/write错误仍释放并完成失败terminal |
| 退役/退出 | retireSurface→稍后全Host stop，重复stop；barrier创建失败；延迟switch/relaunch在closing前后释放 | 原capture保留至export terminal，无漏集合、迟到session/请求、重复reply；GPU失败与PNG失败分开 |
| App出口 | 隔离Scene关闭及空Host、正在launch、正在导出；Web/非隔离出口回归 | 真实NSApplication.run验证已terminal直接now、pending先生产者关闭→GPU→export→唯一reply；重复Runner finish不重复终结；外部第二次直接terminate的框架强退单列未保证，Web与产品原owner守恒 |

现有 `script/tests/test_scene_debug_frame_capture.py:167–168` 只编译Capture与Harness，产品Capture已调用makeSceneBuffer，需将真实SceneResourceBudget源纳入测试编译依赖。保留ready/after尺寸、顺序、16位梯度与alpha检查；file检查改为等待导出drain，不能以waitUntilCompleted代替PNG完成。测试断言事件/输出/真实预算和寿命，不断言源码文字或内部符号形状；可注入调度队列、额度和导出barrier用于确定性反例，不添加无调用方测试入口。

inner运行相称capture/提交/退出行为模块；checkpoint Debug build及code-health、scene-defense、design-gate与现役结构门。GPU门使用隔离自有输入、真实Metal completion/publication/terminal compositor/next-frame；同身份短HDR capture-on/off App观察仅作辅助，不能代替上述反例，也不宣称性能完成。owner diff及证据identity冻结后独立只读终审，再进入实施/合批。本文落盘没有运行产品门。

## 7. 退役

只保留此有界诊断迁移；不新增第二allocator、capture registry、compositor、clock或全App退出流程。请求和导出行为、准备cancel、retiring surface、Session及隔离退出门闭合，稳定诊断合同接管后归档本文，删除登记并收缩旧同步persist/固定0.2秒退出路径。未通过条件保留明确失败现场，不把设计approved或App非黑计为完成。
