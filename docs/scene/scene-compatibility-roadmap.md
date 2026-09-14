<!-- document-role: active-plan -->

# Scene 兼容执行路线

> 当前主线：**全样本验收收口**。以真实作者 corpus 中每一个样本的正确显示、正确播放与作者参数进入播放链路为唯一完成门；进度只由[样本验收台账](semantics/scene-sample-acceptance-ledger.md)的人工裁决计数表达。
>
> 唯一目标：`authored input → prepare once → typed frame commit → GPU execute → unique compositor`，并在稳定帧时间内持续得到正确画面。每个改动必须让验收台账中至少一个样本的首断点消失或视觉裁决前进，或闭合一个被多个样本共享的公共首断点。

对象如何加载、进入合成和释放，统一遵守[播放器设计 §8](design/runtime-architecture.md#8-scene-播放生命周期与落代码合同)。本路线不复述已完成的实现过程。
>
> 本文只拥有阶段顺序和完成门。能力、owner、route、样本和运行结果分别由[能力台账](semantics/coverage-ledger.md)、专项表、[运行证据索引](semantics/runtime-evidence-current.md)、[样本调试台账](semantics/scene-sample-debug-ledger.md)和[样本验收台账](semantics/scene-sample-acceptance-ledger.md)拥有。日常操作见[开发工作流](development/development-workflow.md)。

## 1. 不变的目标架构

产品只有一条 Scene 主链：

```text
authored data → loss-preserving IR → prepared Program/graph/resources
              → typed frame update → Metal encode → unique compositor/output
```

Swift/AppKit 持有 identity、作者顺序、frame state、资源/target/publication 生命周期和 Metal 调度；shader compiler、ECMAScript VM、particle interpreter 和 media/text provider 可以独立演进，但必须生产或消费共享运行对象。不得按 sample、layer、path、hash 或截图选择视觉算法，不得引入第二套 property/provider/clock/graph/compositor。

普通帧不得重新解析、编译、建图、序列化/哈希整图或构造完整诊断。安全完整性检查（generation、epoch、target、publication、completion）保持逐帧；其余准备工作只在 load、generation 或明确 invalidation 边界执行。

## 2. 验收标准

验收对象是真实样本根下的全部 Scene 样本，不是矩阵成员或 fixture 子集。一个样本只有同时满足下面三条，才能在验收覆盖层写成 `pass`：

1. **正确显示**：在普通 App 的异步 `requestLaunch` 路径（不是仅 debug probe）下，首帧与稳定帧的构图、方向、图层可见性、文字、颜色与作者预览一致；没有缺块、倒置、错位、黑线、闪烁或异常背景。
2. **正确播放**：动画、粒子、Timeline、脚本驱动、音频/媒体/鼠标响应按作者意图持续变化；帧时间稳定到动画可辨认，性能阈值在 P5 建立基线后写入，之前不凭主观预写。
3. **作者参数进入播放链路**：`project.json` 声明的每个用户参数（bool、slider、color、combo、text、textinput、scenetexture、usershortcut、group 及其 `condition`）都能在属性面板出现，修改后经唯一 typed property snapshot 到达其 consumer 并产生与 Wallpaper Engine 一致的可见/可听变化。确实无法在 macOS 实现的参数或 target 族必须显式记为 `unsupported-by-contract` 或平台策略，不得静默忽略。

裁决方式只有人工对照真实播放，必要时用官方预览或[官方客户端行为研究工作流](semantics/official-client-behavior-research-workflow.md)边界内的同输入对照。benchmark PASS、非黑像素、structural-chain-complete、compile success、route 数和单次隔离 probe 都不能写成 `pass`。裁决只写入验收覆盖层，由台账生成器汇总；本文不复制任何计数。

## 3. 阶段

工程重构与性能消融按[重构执行档案](engine-refactor-program.md)执行。下表 P5 是性能／长稳的最终验收阶段，不是开始测量或优化的前置阶段；P1–P4 的改动同样保留正确性与帧成本约束。

阶段按“共享首断点集群”而不是按能力轨排序。集群定义与逐样本归属只在验收台账维护；每个阶段的完成门都由台账计数直接判定。

| 阶段 | 目标 | 完成门 | 当前状态 |
| --- | --- | --- | --- |
| P0 | 验收基线：全部样本有隔离运行归档、首断点集群与人工裁决槽位；tracked matrix 从历史固定成员扩到全 corpus 的 identity-only 门 | 台账无 `not-run`；full matrix tier 覆盖样本根全部成员且不带历史视觉期待 | 台账已覆盖全部样本；matrix 扩容未做 |
| P1 | 公共首断点清零：按 `effect-chain` → `particle-load` → `texture-load` → `scenescript` 顺序，让每个集群的样本回到 `visual-review` | 各集群样本数为 0；每个修复有公共正例、局部失败反例和 next-frame 证据，不含样本专用分支 | **现在**（`effect-chain` 优先） |
| P2 | 用户反馈样本逐项闭合：台账中 `fail` 的样本按报告顺序修到 `pass`，只允许公共 owner 修复 | `fail` 为 0 | 与 P1 并行，逐样本推进 |
| P3 | 作者参数全链路：属性面板 → typed snapshot → consumer → 可见变化；未支持 target 族逐族闭合或显式 unsupported | 所有声明用户参数的样本参数验收通过；[输入覆盖表](semantics/runtime-input-property-coverage.md) 中不再有仅结构级（`L0/L1`）的 authored target 族，除非标为平台策略 | 部分 target 族已有 live consumer；具体剩余 target 以输入覆盖表为准；当前 Bloom 链与参数验收仍开放 |
| P4 | 视觉复核收口：把 `unreviewed` 逐个裁决为 `pass`，新发现的首断点回到 P1/P2 | `unreviewed` 为 0；`pass` 等于全部样本减去 `platform-unsupported` | 未开始批量复核 |
| P5 | 播放稳定性与发布：帧时间基线（首帧、CPU、GPU、next-frame）、长稳（睡眠、显示器变化、切换）、签名发布 | 全部 `pass` 样本在基线机器上稳定播放；发布门通过 | 未开始；性能数字只作为观察记录 |

P1 从[当前断点队列](scene-open-breakpoint-queue-2026-09-09.md)选择可复现的最早公共失败。已完成 family 不再重复排队；一个 family 的修复以公共 primitive 表达，并验证未见组合。

## 4. 完成与回滚

每个 atom 都要有：目标合同、当前首断点、一个正例、一个反例、previous-current fallback、最小 completion/publication/next-frame 证据，以及它在验收台账中改变的样本状态。完成状态分开写：

- `slice-visible`：实际内容进入共享链并有相称的画面/事件证据；
- `owner-migration`：route state、fallback reason、回滚演练和旧产品引用清零；
- `parity-release`：固定官方对照、性能/长稳、签名和发布依赖全部满足。

compile success、recognized/wired、route 数、matrix PASS、非黑像素和单样本通过都不能越级成为上述结论。

进入 `generic-only` 前必须有新组合/未见 fixture 和局部失败反例；通用路径扩大拒绝半径或明显降低画面时，回到 `prefer-generic`/`disable-generic`，保留诊断和 fixture，修复共享首断点后再尝试迁移。

一个批次结束时：样本可见结果变化写入[样本调试台账](semantics/scene-sample-debug-ledger.md)，人工裁决变化写入验收覆盖层并重新生成验收台账，能力等级变化写入能力台账/专项表；本文只在阶段状态或完成门改变时更新。

## 5. 本轮结构性决策

以下决策服务于“尽快让全部样本正确”，与[兼容运行时架构](design/runtime-architecture.md)的安全边界一致：

1. **effect 准入从逐形状静态证明转向默认合同加视觉验收。** 当前多数 effect 首断点来自 prepared source 的颜色/形状证明不成立，而不是编译或 ABI 失败。路径/range/ABI/target hazard/生命周期失败继续硬拒绝；单纯“颜色合同未证明”的普通 effect 改为按官方 blend/alpha 合同的默认策略执行，并以样本视觉裁决而不是 analyzer 证明作为通过门。每新增一个 source-shape analyzer 前，必须先说明为什么默认合同不能覆盖该 family。
2. **性能与正确性共同约束。** 工程重构按 E0 建立基线后即可推进，不等待 P5。兼容修复不得以错误缩放或改变作者行为换取帧率；P5 负责统一性能、长稳与发布验收。
3. **能力轨保留为词汇，不再决定顺序。** V0–V5（ordinary shader/material、graph、VM、particle、typed input/provider、Puppet/3D/lighting/发布）继续作为能力台账、依赖图和技术栈边界使用的轨名；具体能力在 P1–P3 按集群与样本需求被拉入，不再等待某条轨“收口”。V4 仍是横切轨：每个 input family 各自闭合 producer → typed channel → consumer → next-frame/event，不得以另一个 input family 的通过替代 V4 完成。
4. **Fast Scene Suite 在 P0 内要么批准要么退役。** 仍为 `selection-required` 的成员不再被任何文档当作可运行的低成本门引用。
5. **同一实验只比较同一输入。** 验收与复现统一使用普通 App 异步启动路径、隔离样本副本与显式 property snapshot；debug probe 只用于定位首断点，不用于裁决。

## 6. 何时退休本文

当验收台账中所有样本均为 `pass` 或显式 `platform-unsupported`，P5 的基线、长稳与发布门全部通过，且各能力族的终态已由稳定架构合同、能力台账和专项表接管时，将本文转为历史证据。历史正文中的命令和“下一步”只属于截止日期，不再作为现役指令。
