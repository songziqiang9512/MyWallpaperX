# Scene 引擎重构顶层设计

<!-- document-role: stable-contract -->

本设计规定优化方向、职责和退出条件，不维护批次顺序或完成状态。全局优先级归[兼容路线](scene-compatibility-roadmap.md)：画面合成/正常播放、性能、属性热更新、其他；当前开放项归[断点队列](scene-open-breakpoint-queue.md)。[性能卡](performance-convergence-card.md)与[属性卡](properties-panel-card.md)只维护各自专项选序和验收；已完成的SteamKit迁移退役，获取服务按[稳定合同](../../architecture/steam-workshop-acquisition-contract.md)维护。旧 E/AS 编号只用于历史追溯，不是串行前置门。

## 目标与取舍

真实 Scene 正确加载、播放、交互和合成；正确性优先，其次覆盖收益、简单性与性能。在相同作者内容、画质和资源安全条件下，减少整体 CPU/GPU 工作、内存与启动成本，改善属性响应。帧时限达标不能证明能耗合理；局部阶段下降也不能替代整进程或用户交互收益。

以现有 Swift/AppKit、Metal、系统媒体能力和通用编译/VM 底座演进。重构围绕已证成本或能力缺口展开，允许替换不合理的旧结构；整体换语言、新框架、第二 renderer 或更多缓存均不预设为目标。新增或替代机制须说明旧职责何时撤权。

## 职责与数据流

```text
authored data → prepared Program/graph/resources → typed frame update
              → Metal encode → unique compositor/output
```

具体阶段、对象生命周期与编码落点由[运行架构](../architecture/runtime-architecture.md#8-scene-播放生命周期与落代码合同)维护，实际接线查[代码地图](../architecture/runtime-as-built-map.md)。本设计不复制另一份对象表。

- App 保存选择与属性意图；既有播放控制边界统一切换 epoch 和有效暂停状态；adapter 保存执行事实，UI 消费投影。Video/Web 保留各自系统媒体与窗口生命周期。
- Scene client 传递可重放意图、请求/修订及显示配置；VM、frame、纹理和 GPU 由现役 daemon/session 持有，不跨 IPC 重建第二份。
- identity、clock、graph、资源生命周期与最终输出各有唯一权威。Shared 提供可复用值、视图与注入接口，具体服务由 App 装配。
- 切换目标为 request→prepare candidate→可呈现确认→commit active→retire previous；失败/取消保留旧安全画面。多 surface、部分 GPU 提交和迟到结果遵循原事务，不能伪造整体回滚。

## 优化边界

下表是可选择的职责面，不规定执行先后；每批比较实际热点、覆盖收益、风险与可验证性，只选一个完整结果。

| 职责 | 优先减少的工作 | 必须保持 |
|---|---|---|
| CPU/VM/帧准备 | 重复解析、投影、序列化、字典/数组复制、分配、锁与桥接 | 静态事实在生成/失效边界准备；当帧 live identity、fresh JS 引用、getter/setter、副作用与事件仍有效；不跨 command buffer 缓存完整帧 Program |
| 资源/启动 | 压缩纹理展开、重复解码/上传/编译、逐资源等待及无消费者预热 | purpose、mip、颜色、lease、completion 和取消发布；以首帧依赖缩小提前准备，失败局部回退 |
| GPU 合成 | 多余 copy/capture、store/load、pass 切换及实际最贵 shader 工作 | 作者顺序、背景读取、HDR/SDR、history/copy/swap、最后 store 和唯一 compositor；不全局降精度或减少内容 |
| 内存/退场 | 重复驻留、无界 cache、多 surface/候选叠加峰值 | 聚合既有 owner 预算；in-flight/history/provider 在安全点释放；allocator 驻留与泄漏分别判断 |
| 调度/能耗 | 无效 attempt、重复唤醒及无消费者采样/解码 | 唯一时钟与提交权；completion 不递归 render；不能因 GPU 忙跳过原本应消费的作者事件/VM；静态按需须证明动态依赖与 invalidation 完整 |
| 属性编辑 | 主线程重复准备、控件重建、通知风暴和可避免整景重建 | 复用现解析、控件、store 与 typed value/resource/variant/graph 更新；真实拓扑变化仍重建，跨 surface 与 clock 保持一致 |
| 工程反馈 | 重复 harness 编译、失效源码形状断言、重复文档和证据整理 | 保留独立行为与安全反例；同一事实一个权威，验证按影响面升级 |

<a id="apple-silicon"></a>

Apple Silicon 的平台、语言和依赖政策由[技术栈合同](../../architecture/technology-stack-boundaries.md)维护。原生 BC、附件寿命、shader 精度、GPU 几何、显示节奏及系统媒体转换均按上表热点条件选择；新 Metal API、memoryless/aliasing、DisplayLink、PSO archive 或 GPU simulation 不作为必做迁移。采用前须核实基线设备能力、总成本及安全退出，不新增第二执行链。

## 设计、失败与验收

重要能力或 owner/identity/lifecycle 变化先修订所属专题设计，再实施；普通局部修复直接推进。设计说明完整数据流、替代方案、失败半径、取消/退出和最近正反例，沿[仓库工作流](../../development/repository-workflow.md#设计判定与记录)登记，不为每个 helper 新建任务书。

资源越界、stale handle 和错误代次拒绝最小不安全单元；普通视觉失败局部降级，保留合法 previous/current 与不受影响内容。不按样本、路径、哈希或源码形状选择视觉算法，不复制参考实现；研究边界遵循[clean-room 工作流](../development/official-client-behavior-research-workflow.md)。

验证复用[工作流的风险分级](../../development/repository-workflow.md#并行与验证)。先用最近门和短实验筛选，短实验不作性能验收；目标收益成立后执行工作卡规定的同条件多轮比较、变体/相邻反例、独立真实样本和一次最终独审。正确性或生命周期退化立即纠偏；连续两次有区分力实验仍无收益，停止该方向并重新选题。

同源码/工具/配置/输入身份的构建与有效证据复用；修订只重验受影响部分。共享合同、高风险生命周期或发布结论才扩大门，不能省掉实际变化需要的验收。测量期间避免构建/测试/profiler争用，诊断与普通播放分开；性能阈值与噪声规则在比较前冻结，失败后不放宽。

关闭一个切片须有用户结果、旧职责退出、可比较成本与未覆盖边界。构建、测试、提交或代码数量不计性能收益；局部计时、整体 CPU、GPU、内存、启动与能耗分别报告。最低设备、多屏、长稳、恢复和正式发行验收按声明范围执行，不作为每个局部修改的重复前置门。

## 历史与追溯

早期候选查[调查线索](../architecture/refactor-baseline.md)，使用前须核对当前调用与成本。

<a id="5-可直接交接的执行卡"></a> [归档记录](../history/engine-refactor-program-through-2026-10-14.md#5-可直接交接的执行卡) <!-- archive-redirect -->

[截至 2026-10-14 的 E/AS 档案](../history/engine-refactor-program-through-2026-10-14.md)保留原实验、失败和未闭合事项；[更早工程记录](../history/engine-refactor-program-before-2026-09-15.md)保留 completion 唤醒失败、validation memo 撤回等约束。它们只供对应职责按需追溯，不能用历史数字判断当前瓶颈。当前能力归[能力台账](../capabilities/coverage-ledger.md)，实际结果归[证据索引](../capabilities/runtime-evidence-current.md)及其历史链接。
