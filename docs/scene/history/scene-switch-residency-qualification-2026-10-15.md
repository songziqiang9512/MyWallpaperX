<!-- document-role: historical-evidence -->

# 轻重切换驻留资格与类别诊断（2026-10-15）

> **历史证据 — 非现役入口**。执行与未完成验收归[性能卡](../roadmap/performance-convergence-card.md)。本批确认同一轻场景返回后的进程 footprint 上移，并缩小分配类别；没有实施内存优化，没有认领泄漏、具体持有 owner 或长期有界。

## 无 attach 的七窗轨迹

同一 Debug App 可执行文件 SHA `3ec09e8eeaeba6ac49462c56bc1f5e992968a01cf7fd3e4d249ecbfe9dba2b13`，同一 daemon PID 51668/startMachTicks 10596921238131，目标60FPS、默认属性、输出静音、无外部音频发布。隔离样本 L=3766415113、H=3042492564，顺序 L0→H1→L1→H2→L2→H3→L3。原媒体只读；每步匹配 request 首帧、candidate/activated surface 及两次推进的 frameStats 后，固定30秒稳定、30秒观察，1Hz外部进程采样。没有同时构建、测试、截图或 profiler。60FPS是目标，不代表重场景完成帧达到60FPS。

| 同一轻场景 | footprint 中位 B | footprint 最小—最大 B | resident 中位 B |
|---|---:|---:|---:|
| L0 首次参考 | 186393536 | 186352576—186598336 | 74235904 |
| L1 | 260965648 | 260883728—263275792 | 93274112 |
| L2 | 286352656 | 286295312—296387856 | 120659968 |
| L3 | 334300552 | 327992712—334316936 | 71434240 |

返回窗 L1→L2 增25387008 B（9.728%），L2→L3 增47947896 B（16.744%），三窗范围不重叠。所有轻窗 GPU allocated 每点均94289920 B、RT pool均0；H1/H2/H3 footprint中位771769712/848709000/835061296 B，并非单调。GPU回到平台不能证明全部CPU保有释放，resident下降也不能抵消footprint上移。七窗有效、所有观察窗 busy/dropped/fallback 增量0；重场景各71/71 VM quiescent，正常退出0且最终 gpuDrained=true。逐旧session成功drain、pin与聚合预算终值未导出，不能据最终退出认领全部退场。

证据根 `.artifacts/tmp/scene-switch-residency-qualification-20261015/`，`summary.json`、`run/result.json`、原始CSV/JSONL、边界与输入冻结保留。CPU Mach ticks按125/3换算；Python receivedMonotonicNs只做同接收钟域连接，原C时间戳不混用。CPU约轻155–177ms/s、重1019–1023ms/s只是本Debug配置观察，接收跨度并非精确采集跨度，无候选对照，不计每完成帧、Release或能耗收益。该轨迹只有缓存起始清单，不推断磁盘增长。

## 单独的侵入式类别诊断

另起同一App，PID53333/startMachTicks10621690380668，L0→H1→L1→H2→L2；每步30秒稳定、5秒有效性观察，在各轻窗结束后各一次 `vmmap -summary`，三次均exit0。后续窗口经历前次attach，不与七窗合并，也不用于CPU/GPU性能比较。下表保留工具原有M/K显示单位，region与zone覆盖不同，禁止相加。

| L1→L2 | 前 | 后 | 限定解释 |
|---|---:|---:|---|
| IOAccelerator graphics virtual/resident | 32.0M/24.3M | 32.0M/24.4M | 基本持平 |
| IOSurface virtual/resident | 69.0M/68.9M | 69.0M/68.9M | 持平 |
| owned unmapped graphics virtual/resident | 55.9M/55.4M | 55.9M/55.4M | 持平 |
| DefaultMallocZone BYTES ALLOCATED | 26.8M | 27.1M | 分配字节基本持平，非应用live payload总量 |
| 同zone resident / DIRTY+SWAP FRAG SIZE | 80.3M/65.4M | 146.2M/73.5M | 驻留/碎片值上移，非新增payload总量 |
| DefaultPurgeableMallocZone allocation count / BYTES ALLOCATED | 12/27.4M | 24/60.7M | 最明确的分配类别增量 |
| 同purgeable zone resident/swapped | 0K/64K | 13.5M/17.0M | allocated并非全量常驻 |

Malloc Large (empty) dirty 24.5M→45.6M、Small (empty) 10.1M→10.6M；SWAPPED不自动代表compressed，vmmap TOTAL resident不与proc RSS对账。L2六条GPU allocated前三条70221824 B、后三条94289920 B，pool0；快照前已回94289920，不能把七窗的“全程同值”套用本次。

私有generic磁盘缓存起终1743文件/13932301 logical B，按相对路径、SHA及大小比较added/removed/changed全0；它不能排除进程内或其他缓存保有。源码只读检查未见显式NSPurgeableData/NSDiscardableContent/Metal purgeable接口，不能凭zone名归因ImageIO、shader或解码缓存。下一项须定位新增12个purgeable allocation的调用方与消费者退出后的持有者，再选择修法；不凭类别清空缓存或提高预算。

证据根 `.artifacts/tmp/scene-switch-residency-categories-20261015/`，完整vmmap、输入身份、缓存起终清单与收据保留。五窗正常结束、最终gpuDrained=true，输入无漂移。两条轨迹及类别解释已独审；原始采样不重跑。所有daemon/sampler/probe已退出，两份运行副本各清理178945454 logical B；保留当前App、唯一DerivedData及必要原始证据。没有30分钟/20次切换、最低设备、多屏、HDR或正式Release结论。

后继先用公开purgeable API的2MiB自有carrier做工具资格：heap明确枚举zone/地址/大小，唯一lite malloc_history live查询只有空Call graph、没有caller帧。没有启动真正Scene五load，不推断Scene所有purgeable栈都不可用；普通malloc双对照未执行，保源码待有必要时重选。carrier正常释放/退出且精确PID消失，binary/dSYM清理50440 logical B。原输出及资格边界归`.artifacts/tmp/scene-switch-residency-owner-qualification-20261015/`，持有owner仍开放，不凭zone清cache或上调预算。
