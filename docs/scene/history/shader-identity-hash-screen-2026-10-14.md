<!-- document-role: historical-evidence -->

# Shader identity 重复哈希筛选（2026-10-14）

> **历史证据 — 非现役入口**。执行顺序归[性能卡](../roadmap/performance-convergence-card.md)，静态准备职责归[实际架构](../architecture/runtime-as-built-map.md)。本批仅证局部查找成本下降，未通过整体效率验收，不关闭性能专项。

## 通用语义与取舍

两段真实304 CPU采样同时命中PSO Dictionary查找与预热消费Set插入中的完整MSL字符串哈希。采样使用前驱优化诊断App `61797f31…`，有一次1.57秒间隔扰动，只作归因，不作基线；inclusive栈不能相加为CPU百分比。相比只在预热entry增加首次消费状态，在原不可变 `ShaderSemanticIdentity` 构造时保存标准Swift Hasher结果能覆盖两条路径，不新增owner/reset链。

所有原字段仍参与完整结构判等；缓存只用于当前进程的Hashable查询，不作持久键或视觉算法选择。原PreparedAssembly持有身份，已准入variant逐帧复用；raw derive仍可能新建assembly。没有缓存完整帧Program、跨command buffer PreparedPass或绕过当帧资源验证。代价是每个身份多一个Int及一次前移的哈希计算。

## 可比短实验

真实生产类型、113份Swift输入，仅替换identity单文件；两臂 `-O -whole-module-optimization`，五对交替AB/BA，micro独用固定hash seed，正常回归保默认随机seed。每形状32键、12万次Dictionary查询，原源2813B及自有64KiB注释扩展68354B，分别量共享键与独立相等字符串键。

| 源长度 | 2000次构造中位 B→C | 共享键查询中位 B→C | 独立相等键查询中位 B→C |
|---|---|---|---|
| 2813 B | 0.226→3.313 ms | 192.221→6.124 ms | 202.316→15.489 ms |
| 68354 B | 0.195→68.726 ms | 4139.104→85.184 ms | 4315.225→238.044 ms |

配对查询降幅中位为96.814%/92.323%、97.947%/94.490%；初始化上升不隐藏。它只证重复身份查找，不是App、GPU或能耗收益。

## 实际App筛选与边界

当前HEAD `88e7f77a` 新建同配置B/C：Release加DEBUG、Swift -O/singlefile、C -Os，非普通Release/WMO；App SHA `e1de8c7f…` / `470440b8…`。4294输入只有identity不同，构建及staging前后无漂移；增量构建26.513/20.036秒，Debug检查56.706秒通过并自动清理其DD。

原304、3024×1964、60FPS、静音、关闭execution observations；各96秒运行、30秒预热，独占计时，无profiler/构建/测试。B/C CPU时间率881.393/837.994 ms/s，单对下降 **4.9239076202%**，未达预登记10%继续门，停止完整多轮campaign；不能称稳定整体收益。CPU/完成帧14.733/13.970ms，frame CPU p50为9.413/8.789ms；实际completed 59.825/59.985FPS。每帧36 main、109 offscreen、76 resolved、33 source capture、2 copy与26,902,272复制字节相同。

GPU p95为11.356/10.660ms；sampled footprint峰值826,820,216/964,658,880B，候选上移约16.7%，单对未归因，不能认领内存无回退或整体非目标验收通过。pool峰值相同136,262,688B。呈现超1.5倍间隔比例0.441%/0.181%；仍保基线183.333ms最大间隔。未量功耗/温度，未做三对WMO、五次启动、最低设备、多屏及长期切换。

## 正确性与后继

最近derivation门通过，两臂优化harness各140项事实全真：独立构造、16种字段变化、变量/资源改名、等价表达式、Unicode规范等价，以及强制容器碰撞后仍按结构比较。该碰撞测试不假称制造了私有Int碰撞。原资源、layout、attachment/sample等失效反例保留。

原304两边正常退出，人物、建筑、星空与时钟保留，原粒子加载失败及1128非有限origin仍开放。独立1553008362两边原严格矩阵通过；短窗不认领性能。独立Bunk两边正常退出且原27项矩阵失败完全一致；实际房间、树木、家具与光影保留，时钟继续更新。普通产品UI、HDR/history专项和交互未在本批重验。

当时提出的失败重试全量属性JSON候选已另行完成局部筛选，现状归[属性JSON复用记录](property-callback-recovery-2026-10-14.md#prepared-property-json)，不再作为本历史文档的待执行项。

本机归因证据在 `.artifacts/tmp/steady-cpu-attribution-20261014/proof/`；本批输入、逐轮原数、构建/回归/实际App与审查证据在 `.artifacts/tmp/shader-semantic-hash-20261014/proof/`，运行产物按精确归属清理。保留原连续迭代DD、注明的暖cache及一份候选诊断App供下批复用；未修视觉与长期性能边界不因本记录关闭。

<a id="current-cpu-startup-screen"></a>

## 后继整体CPU与启动资格筛选（停止小候选，无产品收益）

优化诊断App `592e8457…` 原304在观察ready后30.241s取6s暖栈，sample exit0。主线程2423个observations包含系统/等待，不能作为活跃CPU时间分母。五处非嵌套`reserveGraphLocked`根合计148（初始32、allocator32、admit原视图21/重基视图36、finalize27）；拟删同锁第二轮只覆盖36/2423约1.49%主栈，不能称CPU比例或收益上界。停止该删除候选，不加计数或原型，不把资源安全检查当可消除成本。

最大的非嵌套主渲染分支为图准备/提交894、资源准入/preflight345、按层编码330；ARC、enum与memmove分散在值复制/析构中。Entry生命周期有61个具名ARC/memmove叶落在已撤回的working-view区域；PreparedLedger析构还能经pin release进入Entry，两类父链不能相加。诊断freeze41，另线程Metal提交trap906不是906份活跃CPU工作。未找到单一可安全减少整体10%的职责；不因此复活material payload、identity或缓存微调。profiler扰动下报告不作性能对照或验收。精确样本、报告SHA及聚合方法见 `.artifacts/tmp/allocation-transaction-screen-20261014/proof/global-stack-triage.json`，原栈在同目录`current-stack/sample.txt`。

toolchain资格短实验复用真实bundle/process owner，`-O`单binary对保留App执行8次顺序、再4次并发资格检查，12次均成功，输入前后无漂移。顺序单调用中位11.562ms（首调用28.569ms），并发单调用11.742–11.941ms；暖调用约11–12ms，不能把资格成本当全部shader编译成本。没有候选、App对照或shader编译收益，停止资格cache方向。原数与边界在 `.artifacts/tmp/toolchain-qualification-screen-20261014/proof/raw.json`、`receipt.json`，清理见`cleanup.json`。下一项仅按[现有启动合同](../architecture/scene-launch-responsiveness-contract.md#ready-request-preparation)准备真实catalog调度切片，尚未实施/验收；性能专项保持开放。
