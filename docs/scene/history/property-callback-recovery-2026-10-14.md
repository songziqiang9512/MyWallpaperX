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
