<!-- document-role: historical-evidence -->

# 属性回调异常后的局部恢复（2026-10-14）

> **历史证据 — 非现役入口**。当前顺序与剩余问题归[属性卡](../roadmap/properties-panel-card.md)、[性能卡](../roadmap/performance-convergence-card.md)和[队列](../roadmap/scene-open-breakpoint-queue.md)；本批不关闭长期 Goal。

## 接受的实现

目标及失败边界见[属性回调恢复设计](../capabilities/runtime-input-property-coverage.md#property-callback-recovery)。普通作者 `applyUserProperties` 异常不再把所有后续合法属性编辑都强制导向整景重建；下一次真实属性 revision 可恢复同一 owner/module/realm。预算、内存、命令超额、宿主恢复、init/update/媒体/异步任务、timer、Puppet 待处理回调、teardown 和旧 generation 不放宽。失败 native journal 丢弃，JS/module/shared 仍为原非事务堆语义。

原 live state 持有效值/revision，C owner 持失败分类与熔断，原 frame ledger 持消费 ack；ValueOwner 只保失败输入及未确认恢复变化键。先准备输入与 payload，再清熔断；按当前值投递待消费键及恢复键。原 native commit 清恢复输入/键，cohort 拒绝保留并按原 ack 补发，同 revision 普通帧不重试失败调用。未引入第二时钟、属性 store、VM 或输出 owner。

修正同一失败分类入口的旧缺口：layer 与 Puppet animation 命令缓冲区超额在 discard 清标志前归为 mutation-overflow，不能被当成普通可恢复异常。

## 证据与边界

- 原复现：真实 `3042492564` 的 `cloud` 是 typed layer visibility consumer，不在 rebuild keys。首帧颜色脚本自由变量 `event` 抛 ReferenceError 后，完整 callback/cohort 准入让其他合法键也返回 accepted=false；原 client 因此 relaunch。作者自由变量错误不由本补丁修改或注入全局补偿。
- 冻结 VM 回归：34 项行为事实通过，覆盖原 owner 恢复、再次异常、改回最后 ack、缺/错输入不消耗恢复、cohort 拒绝补发、多键恢复被拒后反向编辑、同 revision 去重、Scalar/String、初始失败、旧 generation、timer、teardown、无效事件 JSON 与真实 257 层命令超额；原跨 owner 事件事务回归通过。
- 普通产品入口经隔离 Workshop → 面板/store → client → daemon 完成三次 false/true/false 编辑；恢复默认、关闭重开及跨 App 重启的保存值已核，产品停止按钮实际退出播放，最后一轮 VM teardown 71/71 quiescent，timers/jobs/mutations/dynamicLayers 均为 0，音频/粒子退出。基线三次均出现 125 条 launch-preparation，候选三次均为 0；这只证明重准备事实，不是输入到呈现延迟。
- 同 App 的独立 Host 实图补齐 consumer：`cloud` accepted=true，surface 1→1、窗口 29740 不变；ready/after 原图显示右下云层由可见到消失，主体、时钟和星空继续。原 544 的 ReferenceError 仍局部失败；339 multiply 的 1→0 是 single Timeline 已播放相位保留，旧 relaunch 才会重置为初始 1，不以不同相位数值认定画面回归。
- 未参与修法的 `2134765860`（Bunk）以同输入/配置在两 App 运行，房间、时钟及光影原图未见新增差异；媒体 hash 与 scalar binding census 一致。原严格矩阵的 27 项旧 expected 不匹配列表两版完全相同，原样本仍有 particle loading incomplete；所有原始报告仍为 FAIL，没有改阈值或重写期待为 PASS。

## 同条件操作成本

Apple M4、相同 OS/3024×1964 单屏、相同隔离样本与默认属性、实际普通产品音频环境、默认播放 cadence，优化诊断配置 Release + Swift DEBUG/-O + C -Os。基线 `82270924`，候选 `c19cc00b`；Debug/优化诊断构建的 4271 输入无漂移。正式操作窗口没有构建、测试或 profiler。顺序 B1/C1/C2/B2/B3/C3，配对方向 false/true/false；测量每次 click 前至其后 20s 的 App+Scene daemon 累计 CPU，含播放及基线重建，不含外部编译服务/其他系统进程。普通 UI 使用实际系统音频，未冻结相同 PCM 或做音频输入消融；后续 Host 才显式使用 silence fixture。

| 配对轮 | 基线 CPU 秒 | 候选 CPU 秒 | 配对下降 |
|---|---:|---:|---:|
| 1：关闭 | 38.8318 | 11.8301 | 69.54% |
| 2：开启 | 39.9957 | 12.1307 | 69.67% |
| 3：关闭 | 37.6517 | 11.8641 | 68.49% |

每进程每窗 694–699 个有效 rusage 样本，Mach ticks 按 timebase 转换，边界最大约 13.7ms，表按实际窗口归一到 20s。中位 CPU 38.8318→11.8641 秒，配对降幅中位 69.535%；基线/候选最大相对波动 3.039%/2.247%，达到预登记 ≥10% 且超过两倍基线噪声的操作成本数字门；音频波形未锁定，保留这一环境边界，不计音频锁定的稳态性能验收。daemon 窗内 footprint 峰值基线约 2.01–2.12GB、候选 0.92–0.99GB，仅为该操作窗观察，不当作长期内存/缓存验收。

这是避免整景重准备的真实交互成本收益；未量输入到呈现延迟、稳态 CPU/GPU、温度或功耗，不计引擎整体效率或启动专项完成。优化诊断配置不等于正式 Release。多 surface、含 timer/Puppet pending 的恢复、资源/拓扑重建仍走原边界；长期轻重切换、完整媒体事件/设备矩阵及既有视觉问题留现役卡/队列。

## 验证与材料

34 事实真实 VM、跨 owner 事件事务及最近 health/defense/design 门通过；纯 live state 与预算门沿相同职责复用，修正仅窄重跑受影响 VM/事务，未重复 full matrix/全测试。独立审查发现并闭合准备前清熔断、cohort 拒绝丢事件、多键反向编辑与 overflow 误分类反例，未降低原 oracle。

本轮 `.artifacts/tmp/property-callback-recovery-20261014/proof/` 保 App/输入身份、构建/原始 CPU、正反例及原 FAIL 报告和必要原图。早期已被修正的构建不计验收；本轮不用的 staged App、HOME/Workshop、临时样本及重试环境退出后清理；保一份冻结优化 App 作为后继 CPU/GPU 基线，及一份已声明的连续 DerivedData，避免相同输入重建。正式 runs 根约 1023.97MiB，prune-expired 无可清包；不提高预算、不删除未知证据，必要材料限量保在任务 proof。

## 后继：无属性回调的 Vector owner 休眠

更窄的后继修正让 Vector 与原 Scalar/String 一致：只有实际导出 `applyUserProperties` 的 owner 才准备属性差量事件。没有该回调的 event-only/init-only owner 不再因属性修订进入空更新；真实媒体事件、value hook、timer 和待发布值仍由原 owner 决定调度，并从原 snapshot 读取当前属性，不增加缓存、时钟或事件 owner。

扩展同一个真实 VM harness，旧源码在 40 项中复现三个休眠失败；修后 40 项全真，覆盖普通/改名导出、首次与新 revision 休眠、媒体事件读新值及消费去重、init-only 与 update-only 相邻反例，并继续覆盖前述恢复/拒绝边界。Debug 与优化诊断各构建一次，4253 个产品输入无漂移。本后继不认领稳定的整进程 CPU/GPU 或能耗收益；短筛选和实际输出材料归 `.artifacts/tmp/steady-cost-attribution-20261014/proof/`。

短筛选沿冻结的机器/输入、239 属性、静音 fixture、3024×1964/60FPS、优化等级与无 execution observations 配置；原基线 `c19cc00b`、候选 `b85c6205`，每次 48s，30s 预热后有效计时 16.5s。首基线因零呈现回执被原 parser 拒绝并保留；顺序为无效 B/C/补 B。有效 B/C 的进程 CPU 时间率为 845.452/842.006 ms/s，仅低 0.408%；CPU p50 9.006/9.057ms、GPU p50 12.488/12.643ms，GPU/target pool 采样峰值均相同（548257792/136262688 bytes），主/离屏/source capture 工作量不减。此短窗不足稳态且只有一对，远未达到预登记 ≥10% 筛选门；不追加三加三正式性能测量，不计 CPU/GPU 收益或回归裁决。

原 304 实图仍有人物、星空和时钟，原粒子不完整 FAIL 保留；独立 Bunk 复用同输入/工具配置的 `c19cc00b` 基线，只补候选真实渲染，房间、光影和运行时钟未见新增差异，媒体 hash 与相关 scalar/vector/资源 census 相同，原 27 项矩阵失败完全相同。后继候选 Stop 为 71/71 quiescent、timers/jobs/mutations/dynamicLayers=0、surface 1→0 且 GPU 排空。本后继未重跑普通 UI 入口或重新证明其编辑收益，前批 UI 证据仅覆盖其原配置；Host 实图不扩称新 UI 验收。

同轮 CPU 栈的主要成本仍在 graph/material/resource 准备。GPU census 为每帧 36 主 pass、109 离屏 pass、33 source capture，仅说明工作量，不是逐 pass GPU 时长。提前编码后继 graph 的方案在实施前撤回：现有全帧工作对按尺寸共享，后继会覆盖未合成前驱的输出；无新增 ledger 阶段、独占纹理或复制。原 1128 实际有属性回调，其 Vec3/Vec2 混合运算的非有限 origin 仍开放；[公开 Vec3 文档](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/Vec3.html)列出 Vec2 参数，但缺失分量的具体行为尚未受控核实，不能凭此补值或关闭断点。


<a id="prepared-property-json"></a>

## 后继：未确认属性事件复用完整 JSON

真实304的1128 owner持续返回非有限origin，尚未成功record，原全量属性JSON因此逐帧重新编码。本批只复用FrameDriver按revision准备的同一快照字节，覆盖Scalar/String/Vector首次与未确认投递；不提前ack、不省略回调、不缓存作者可变事件对象。ack后的delta、失败恢复键和cohort回滚保留原owner；Scalar/String直接调用省略prepared参数时保留原codec语义，不把默认`"{}"`误当完整输入。1128非有限返回本身仍开放。

真实parser的249定义/239有效值生成6656B payload；同一`-O`生产类型二进制五对交替，每臂每轮3000次未ack调用。原路径CPU中位1152.816ms（0.384272ms/次），复用路径0.034ms/轮，仅快路径转交与长度/首尾消费；计时外完整UTF8相等及7项ack/delta/rollback/empty/color/nonfinite边界通过。绝对值极小的局部比值不外推为App收益，也不含VM事件对象解析。

复用前批签名App `470440b8…` 作B，只构建C `ee885541…`；4294产品输入仅5个属性路径变化，构建前后无漂移。诊断配置仍为Swift -O/singlefile、C -Os，非正式Release/WMO；增量构建30.020s，Debug检查68.083s通过。原304、3024×1964/60FPS、静音、无execution observations，各96s/30s预热、约64.5s有效窗，独占计时。B/C CPU时间率854.246/817.232ms/s，单对降4.332855%，未达10%继续门，停止扩测；每完成帧14.245/13.624ms，完成59.970/59.984FPS。GPU p95 12.430/12.044ms，但p50由8.828升至11.502ms（+30.29%），明显非目标异常未归因，不能认领GPU无回退或整体非目标验收；单对不足区分代码影响与时段/频率/调度漂移。footprint峰值826443432/819267168B，pool峰值均136262688B；每帧36主/109离屏/33 source capture/2 copy与26902272复制字节不变。呈现超1.5倍间隔0.02587%/0.05172%，最大均25ms。单对不构成稳定CPU、GPU、内存或能耗验收。

最近真实QuickJS门66事实与String生命周期4测试通过；覆盖改名/等价、连续badReturn、成功后拒绝重放、ack去重、显式prepared与省略默认入口、delta及清空。新增String夹具首轮5项失败来自descriptor/binding源码身份不一致，修正夹具后只重跑受影响门，未改产品准入或放宽oracle。原304两边正常退出，人物、建筑、星空与运行时钟保留，原粒子FAIL不变；独立Bunk复用相同B身份/内容/工具配置，只补C实图，房间、树木、家具、光影与时钟保留，原27项FAIL完全一致。C的Bunk退出31/31 owner quiescent、timer/job/mutation/dynamicLayer均0；未重验普通面板入口、HDR/history、最低设备、多屏或长期切换。

本批证据归`.artifacts/tmp/property-json-reuse-20261014/proof/`及三个运行报告/必要截图；不用的编译中间产物、转储和临时运行环境按归属清理，保当前候选App及原连续DD供续接。下一步先核GPU工具能否给出普通image/source的实际执行归因，再决定最小实验；CPU备用为已在栈中命中的VM尺寸Vec2重复准备，不能跳过作者保留旧对象、resize与多surface语义。执行顺序仍归现役卡，不新增计划或状态入口。


<a id="ordinary-value-resend"></a>

## 后继：普通同值重发不触发结构重建

原生slider量化后可连续发送相同值，LiveState原先在同值判断前拒绝结构键或不可用consumer，client收到false后走requestLaunch。本批在唯一有效值owner提前接受已知普通键的严格typed同值重发：整请求均有当前值/替换值，且由instruction、script consumer或rebuild集合识别；不改值、revision、payload或回调ack。未知键、删除、缺值、错类型及混有真实变化的请求保原验证，prepared texture键即便同路径也保加载/重试事务。未缓存UI猜测值，未增加热更新能力。

冻结原实现配新回归复现1项失败；修后17测试通过，两组改名覆盖scalar/Bool/text/color、不可用consumer、结构键和上述相邻反例。Debug与优化诊断各构建一次，4294输入无漂移。实际304 Host以g_zoom=.73/cloud=true启动，顺序重发.73、改.74、关闭cloud：基线86b320df为false/false/true，候选bae53b53为true/false/true；g_zoom确属rebuild集合，cloud到482.visibility。候选单session/同一窗口，ready/after原图中右下云层消失，人物、星空和时钟继续；退出71/71 quiescent，surface 1→0、GPU排空。Host不调用client的拒绝后重启，故不把本次Host基线false记成实际重建次数；client出口沿未修改代码核对。

独立Bunk复用86b320df报告，仅补候选真实运行；媒体与matrix hash相同，原27项FAIL列表相同，房间、家具、树木及运行时钟保留。两次实际时刻17:24/18:40不同，窗外日夜与灯光明显不同，未锁wall clock，因此不宣称逐像素或光照等价。此次未重验普通面板完整交互、待处理launch取消窗口、多surface或HDR；未量编辑延迟、CPU/GPU、内存、温度/功耗收益，不沿用前批69.5%的数字。

证据归`.artifacts/tmp/property-repeat-noop-20261014/proof/`及`bunk-candidate/report.json`，复用前批App/回归入口与当前连续DD，不重跑全矩阵。保一份候选App供续批；原始报告、必要画面及输入身份保留，弃用临时样本/编译环境与重复转储按归属清理。后继复核确认该边界会被同值优化扩大：先有结构K的候选准备，再提交J的同值/热更新，旧Host取消候选后只在旧active上接受J，丢失K的最新意图。现Host对同record、非空变更且启动进行中取消后返回false，交原client用完整最新activeIntent重放；不再局部提交到旧active。无pending、不同record、空变更和终态不改委派。真实Host/Client方法加受控准备/session/transport叶子门在旧版复现，修后13测试/37事实通过：三类编辑都取消代次1、替换为3，迟到旧progress/completion不发布，最终完整K/J激活。此门无完整App/daemon/GPU，实际快速连续UI竞态未重验。

Host修正后与Encoder后继共用91fe54e3优化诊断及Debug构建（输入身份/日志归Encoder proof），普通304播放正常停止，实际pending竞态仍以上述受控owner门为界。独审另发现历史Client时序：尚未消费launched时编辑已合入activeIntent，迟到launched可能以冻结pendingIntent覆盖；该分支未被本Host修复覆盖，留属性卡后继，不把所有IPC时序标成完成。
