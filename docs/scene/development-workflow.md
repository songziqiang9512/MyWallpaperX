<!-- document-role: stable-contract -->

# Scene 日常开发工作流与消融准则

> 目标：用一条准备一次、逐帧执行、唯一合成输出的 Scene 主链，最快得到正确画面，并让性能问题在共享断点上收敛。
>
> 本文是日常开发的操作入口。它不记录批次、样本、指标或历史过程；当前事实分别由[能力台账](semantics/coverage-ledger.md)和[运行证据索引](semantics/runtime-evidence-index.md)拥有。

## 1. 先记住四条红线

1. **一条产品主链**：`authored data → prepared Program/graph/resources → typed frame update → Metal encode → unique compositor/output`。任何只产生诊断、报告、hash、route 统计或重复 owner 的机制都不能成为普通播放的前置步骤。
2. **准备一次，执行多次**：解析、降级、shader/reflection、ABI/target 检查、图准备和 pipeline preparation 只在 load、generation 或明确 invalidation 时做。普通帧只更新 typed value/publication，并执行已准备对象。
3. **共享 owner 优先**：身份、作者顺序、frame state、property/provider、resource/target/publication、Program/graph 生命周期和最终 output 各只有一个产品权威。样本、layer、path、hash、截图不能选择视觉算法。
4. **失败就地收敛**：安全/生命周期/GPU 合同破坏硬拒绝对应执行单元；shader、optional provider、脚本 API、粒子组件等视觉失败只停用最小 effect/pass/component，保留 previous-current 和安全输出。

用户可见收益的优先级固定为：正确画面与布局 → 首帧和稳定帧时间 → 新能力 → 诊断便利。

## 2. 每次改动只走这一圈

### A. 找首断点

先执行 `git status --short --branch --untracked-files=all`，划定本批拥有的文件。然后只读四个入口：

1. [路线](scene-compatibility-roadmap.md)：当前 V 轨和完成门；
2. [能力台账](semantics/coverage-ledger.md)：能力、owner、route 和待办；
3. [运行证据](semantics/runtime-evidence-index.md)：最近实际运行和证据上限；
4. 受影响类型的当前调用链：producer → first wrong identity/state → committing consumer。

把问题写成一行决策卡，足够即可：

```text
结果：要恢复的真实作者输入/用户画面
首断点：第一个错误 identity、state、resource 或 output
owner：当前负责类型；generic/fallback route
最小门：一个正例 + 一个反例 + 必要的 next-frame/completion 证据
```

如果找不到共享首断点，不增加 wrapper、registry、profile 或完整诊断；先补能区分候选解释的最小 observable。

### B. 做一个纵向结果

只实现能闭合一个可见或可执行结果的最小职责。允许跨目录改动，但所有文件都必须服务同一条播放链。优先扩展现有 owner；新类型必须直接执行多个合法 authored 输入、消除重复 owner，或拥有独立且必要的生命周期。

每个迁移 owner 必须处于一个显式状态：

- `observe-only`：只收集证据，不持有产品输出；
- `prefer-generic`：通用路径优先，旧 owner 只按 typed reason fallback；
- `generic-only`：通用路径拥有产品执行权，旧实现最多作为离线 oracle；
- `disable-generic`：只用于回滚，并留下退出条件。

不允许静默双执行。通用路径扩大拒绝半径或出现明显回退时，撤回 route、保留反例和诊断，再缩小切片。

### C. 立即做最小验证

验证只覆盖本批真实失败半径：

| 阶段 | 命令/结果 | 什么时候用 |
| --- | --- | --- |
| `inner` | `python3.12 script/verify_scene_change.py --phase inner --base HEAD --path <owned-path> --run` | 每轮编码；最近 executable unit，不构建、不启动 App |
| `checkpoint` | 同上改为 `--phase checkpoint` | 可提交前；定向测试、代码健康，Swift 改动再 Debug build |
| `integration` | `--phase integration` + 一个契约化代表内容 | 触及 GPU、VM、资源、生命周期或可见输出 |
| `milestone` | 明确选择 fixed/full、压力、长稳或发布门 | 只有风险确实跨越这些边界时 |

`--module` 是精确选择；只有显式 `--keyword` 才扩展匹配模块。普通改动不跑 full matrix，不把非黑、route 计数、compile success 或一个样本的 PASS 写成兼容完成。

可见结论至少要有实际执行身份、GPU/VM completion、publication、terminal compositor、next-frame，以及与声明相称的截图 ROI 或事件证据。只有在这些都成立时才可写 `slice-visible`；owner 撤权还需要 fallback 指标、回滚演练和旧引用清零；官方 parity/release 是更高一层的独立结论。

### D. 只同步一个权威面

- 行为/架构改变 → `runtime-architecture.md`；
- 阶段顺序或完成门改变 → `scene-compatibility-roadmap.md`；
- 能力、owner、route 或当前缺口改变 → `coverage-ledger.md` 或对应专项表；
- 新运行结果、失败首断点或证据身份改变 → `runtime-evidence-index.md`；
- 仅过程、命令和边界改变 → 本文或 `AGENTS.md`。

同一事实只写一次。路线不抄样本和数字，台账不抄完整报告，运行索引不承担当日任务队列。

## 3. 消融：每次减少一个常驻成本

消融不是另一个测试平台，而是审查现有主链是否仍背着不必要的工作。一次只移除一种成本，并用同一代表内容比较：首帧时间、稳态 CPU/GPU 帧时间、输出是否改变、失败半径是否扩大。

优先顺序：

1. 关闭普通帧的完整 observation、hash、route 聚合和 corpus instrumentation；
2. 移除重复解析、整图扫描、重复 catalog/descriptor preparation；
3. 将 launch-stable topology/index、Program、resource 和 pipeline 改为缓存，保留 dynamic value、generation、provider readiness、target/publication/completion 的逐帧检查；
4. 移除没有产品 owner 的 wrapper、registry、placeholder type 和第二 output/present 入口；
5. 最后才考虑更大范围的 matrix、长稳和发布门。

Scene CPU 性能消融采用同一隔离输入的四路对照：baseline、只关闭粒子推进、只关闭 resolved-material preflight、两者都关闭。当前 benchmark 没有这两个开关；实现时使用一次性 DEBUG evidence knob 或按语义等价的无粒子/无 effect fixture，默认播放路径不得保留开关。每路记录 app executable hash、sample/package hash、matrix hash、knob、duration、CPU/pre-encode/GPU p95、FPS、submitted/completed/failed、drawable/next-frame 和 ROI；同一输入至少重复三次取 median/p95。诊断窗口与普通播放性能分开报告。

一次消融只有在以下条件同时成立时才算完成：

- 正例输出和 next-frame 行为保持在既定容差内；
- 反例仍在最小安全单元 fail closed 或 fail soft；
- 主链不再依赖被移除机制；
- 至少有一个未见组合或独立 fixture 证明没有退化为样本特判；
- 同一输入的三次重复中 GPU completion、next-frame 和预登记 ROI 保持不变或在既定容差内；
- 证据写入正确的权威文档，而不是新增日志型文档。

若消融无决定性证据或没有减少工作量，立即换下一个共享断点，不在文字、矩阵或报告格式上循环。

## 4. 文档和目录的减法规则

- `AGENTS.md` 只放会改变实现、验证、提交或工作区安全的长期约束；不要把当前阶段、指标和样本写进去。
- 本文是 Scene 日常操作唯一入口；路线只决定“先做什么”，架构只决定“最终怎样”，台账和运行索引分别决定“现在能什么”和“实际发生了什么”。
- 专项表保留可复用的语义合同、正反门和当前 route；批次叙事、截图流水账和旧命令进入 `docs/history/` 或 Git，不进入日常入口。
- 官方取证、Mirage 对照和 corpus 清单是按需加载的研究资料，不是每个功能的前置仪式。
- `.codex`、`docs/scene/evidence/` 和隔离 runtime 是证据缓存，不是源码或知识库；报告生成后只保留可复核摘要，删除候选必须先列精确清单并单独确认。

## 5. 当前 V4 的选择原则

V4 不是新建输入平台，而是把 user property、Timeline、pointer、audio、media、text 和 provider 接到同一 frame commit、identity、generation、resource/publication 和 compositor 主链。每次只选一个“producer → consumer → next-frame/event”的纵向结果；不能用另一族 input 的通过替代 V4 完成，也不能为了补 coverage 先重写全 corpus。

如果性能仍妨碍视觉验证，优先修复运行证据索引记录的逐帧 CPU/pre-encode 首断点、重复 topology/descriptor 工作和普通帧诊断成本；这仍属于当前主链的性能纠偏，不是跳到新的 V 阶段。
