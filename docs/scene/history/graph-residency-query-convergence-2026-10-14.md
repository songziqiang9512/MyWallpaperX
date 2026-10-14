<!-- document-role: historical-evidence -->

# Graph resident 查询与整体 CPU 收敛（2026-10-14）

> **历史证据 — 非现役入口**。顺序与未验成本归[性能卡](../roadmap/performance-convergence-card.md)，唯一 resident/预算与查询边界归[资源合同](../architecture/scene-resource-admission.md#锁内-graph-resident-查询)，未修画面归[队列](../roadmap/scene-open-breakpoint-queue.md)。本批接收优化诊断配置、单 surface 代表负载的整体 CPU 收益，不关闭性能或属性专项。

## 通用语义与选择

前驱采样中 resource bundle prepare 含子调用占主线程279/2066个样本，reserveGraphLocked 为198；这是重叠的 inclusive 证据，不能相加或当耗时。比较 VM 重复准备、graph resident 查询与 GPU 提前编码后，选择原缓存锁内反复全表筛选：前两已有可追踪 owner，查询片更容易保持既有语义；提前编码会覆盖同尺寸 graph 共享 working pair 中尚未消费的结果，实施前已撤回，未引入另一套 GPU 调度或复制。

设计先写入资源合同，再实施五个产品文件。一次操作在原缓存锁内构造只存 key 的不可变索引：graph/foreign preparation 按 allocation plan key，history 按 resident history key，generation 区分唯一与歧义。未改变 resident 时复用；实际 demotion 后重建，并显式加入刚从 current 转成的 history。索引定位后仍复验 live entry；提交循环可变的 next 继续读取实际字典。capacity 只把数组物化改为惰性序列，原准入算法、pin、预算、分配与取消 owner 不变。

没有跨帧缓存、第二资源账本、整图哈希或按样本分派。临时视图到锁内操作结束退出；它可能暂时保留原 Entry，但不跨操作保留纹理或代替 GPU completion。shared/owned、foreign preparation、重复 generation、history/COW、reset、部分选择与陈旧 reservation 原边界保留。

## 两次实现试验与实际 App

第一版把 Entry 复制到索引，三对 CPU 时间率降幅9.1462% / 9.6789% / 11.9927%，中位数9.6789%，**未达到10%门槛**，没有四舍五入接收。第二版只存 key，复用未变视图及唯一 generation 查询；原门槛不变，只允许这一次后继实现试验。首对须先过10%，然后旧 App 漂移检查，再完成后两轮；没有第三次微调。

Apple M4/macOS27.0.1，3024×1964、单 surface、60FPS，原304输入239属性，静音fixture；96秒运行、30秒预热后有效64.45–64.53秒，每轮66次资源采样。关闭 execution observations，正式计时不并行构建、测试或 profiler；样本/HOME隔离，文件缓存已暖。配置为 Release 加 Swift DEBUG/-O、C -Os、WMO，非正常 Release。旧 App SHA `b85c6205…`，最终 `61797f31…`；Debug与优化构建冻结4253项源码/资源输入且 drift=[]，该数不是编译单元数。

| 指标 | 旧版 B1 / B2 / B3 | 最终 C1 / C2 / C3 |
|---|---|---|
| 整进程 CPU ms/有效秒 | 853.166 / 864.187 / 879.330 | 764.271 / 768.647 / 772.942 |
| 整进程 CPU ms/完成帧 | 14.468 / 14.595 / 14.660 | 12.741 / 12.814 / 12.886 |
| frame CPU p50 ms | 9.041 / 8.995 / 9.056 | 7.720 / 7.729 / 7.782 |
| frame CPU p95 ms | 9.693 / 10.150 / 10.115 | 7.961 / 8.200 / 8.064 |
| GPU p50 ms | 9.466 / 7.943 / 9.643 | 7.573 / 8.720 / 10.523 |
| GPU p95 ms | 10.511 / 13.041 / 12.375 | 8.232 / 13.056 / 11.167 |
| sampled footprint peak MiB | 800.002 / 819.580 / 920.767 | 920.314 / 917.455 / 918.798 |

固定配对整体 CPU 降幅10.419354% / 11.055474% / 12.098684%，中位数 **11.055474%**；基线最大相对中位偏差1.752274%，旧 App B4时间率851.104ms/s，相对原中位数漂移1.513861%，通过的是原登记CPU门；B4对候选中位仅降9.68828%，作为敏感性观察保留，不更换主配对或声称所有比较均≥10%。同60FPS配置，实测completed为58.971–59.984FPS，不能称实际呈现或完成节奏完全相同。frame admission p50 三轮约6.82–6.89→5.59–5.61ms；它是局部归因，不能与嵌套阶段相加。

每帧36 main pass、109 offscreen、76 resolved、33 source capture、2 copy、1 framebuffer capture，复制26,902,272B和pool峰值136,262,688B保持一致。没有靠减内容或质量降低 CPU。GPU 波动明显，不认领 GPU 收益。footprint候选中位数比原基线约高12.1%，落在基线噪声导出的24.69%非目标容差内；B3和旧 App B4也达到约921/937MiB，不能宣称内存相同、已降或无长期增长。

非目标项检查中位与各配对原数，不删除异常：B1 completed3801却仅presented2706，actual present max19.300秒、drawable wait max1.006秒；累计CPU读取66/66有效，无失效证据，但缺逐秒CPU trace，无法定位缺口或排除干扰。B4超预算呈现比例1.16369%，未过1%门；它只用于CPU漂移，不能写全轮呈现通过。B2 present p99为25ms；候选各轮present max25ms、超过1.5倍间隔比例0.491% / 0.103% / 0.052%，≤1%。主CPU/GPU/present p95均在16.67ms预算内，原偶发最大值越界仍保留；不把中位数通过写成全时无卡顿。启动只有每轮ready观察，不是五次冷/暖启动或尾部分布验收。

## 正确性与运行边界

真实 pool/准备/提交门39项通过，新增22个行为事实覆盖四种 shared/owned×1/3 graph、16个无关 resident、foreign preparation、部分 finalize、warm复用/cancel、reset和重复 generation。新 fixture 也在未修改的旧产品源码上通过。首次fixture漏同command-buffer ordering context导致旧/新版均拒绝，修正输入而未放宽产品准入；原24个 recovery事实完全一致。另过现役 coordinator 生命周期、结构/代码/设计/防线/依赖最近门，未运行选择器列出的全部28模块。

实际原304性能运行始终保留原粒子加载失败；禁用 execution observations 的性能报告不承担材质执行完整验收。独立Bunk原27项矩阵失败完全一致，graph执行/contract、GPU完成/合成/下一帧图层集合、粒子与scalar绑定及每帧census相同；原runtime UUID、执行次数和时间驱动vector值不同，不称全报告相同。实际两张后期图的房间、窗外树木、家具、光影及动态时钟保留。单graph独立输入1553008362旧/新版严格矩阵均通过，短窗frame CPU p50为2.150/2.237ms，整体CPU时间率403.059/377.627ms/s；没有长预热，不认领此样本性能。原304后期人物、星空、时钟和建筑保留，原视觉缺口未记完成。

普通产品入口首试及旧版同条件反例均在request之前被隔离HOME策略拒绝：repo位于真实账号HOME内，故其子目录不能作此探针HOME。未放宽保护；改用HOME外 `/private/tmp/mwx-graph-product-entry-q0a_i72_`。客户端生命周期按已观测23–27秒ready留45秒窗口，非提高性能timeout或改验收值。实际经SteamWorkshopService→client→daemon达到launched、唯一request/首present各1、651帧，系统音频scope1有采集发布；停止后VM71/71 quiescent、粒子退出、进程消失。该工具只证明S3采集/发布与入口生命周期，没有普通UI、完整音频consumer或产品画面验收；内部Host实际画面另列。

## 后继与证据

原1128属性回调非有限 origin、544/source 错误及其他视觉断点继续开放。GPU高级混合 attachment读取须先证普通quad与primitive顺序，再做实际App筛选；不重启已撤回的共享pair提前编码。长期轻重切换、cache有界/资源回落、最低设备、多屏、正式Release、能耗/温度及完整首帧验收仍归性能卡。

本批还查明优化诊断整模块构建约304–323秒、Debug约27–31秒；实际argv含WMO且无incremental。日志无逐命令计时，不能把全部五分钟归给单一任务。下一独立批研究固定优化增量诊断供筛选，保同配置身份与正式WMO验收，不增加每批两套完整比较。

本机证据位于 `.artifacts/tmp/graph-residency-query-20261014/proof/`：原报告、预登记、两版差量/构建身份、原失败、配对分析及独审随批限量保留。运行缓存/副本在完成后按精确归属清理；连续构建缓存与最终签名诊断 App 单独注明保留，不把产物移动称为释放。
