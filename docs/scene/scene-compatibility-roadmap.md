<!-- document-role: active-plan -->

# Scene 兼容执行路线

> 当前主线：**V4 typed input/provider 收口**。
>
> 唯一目标：`authored input → prepare once → typed frame commit → GPU execute → unique compositor`，并在稳定帧时间内持续得到正确画面。每个改动必须减少首断点，或闭合一个可见/可执行合同。
>
> 本文只拥有阶段顺序和完成门。能力、owner、route、样本和运行结果分别由[能力台账](semantics/coverage-ledger.md)、专项表和[运行证据索引](semantics/runtime-evidence-current.md)拥有。日常操作见[开发工作流](development-workflow.md)。

## 1. 不变的目标架构

产品只有一条 Scene 主链：

```text
authored data → loss-preserving IR → prepared Program/graph/resources
              → typed frame update → Metal encode → unique compositor/output
```

Swift/AppKit 持有 identity、作者顺序、frame state、资源/target/publication 生命周期和 Metal 调度；shader compiler、ECMAScript VM、particle interpreter 和 media/text provider 可以独立演进，但必须生产或消费共享运行对象。不得按 sample、layer、path、hash 或截图选择视觉算法，不得引入第二套 property/provider/clock/graph/compositor。

普通帧不得重新解析、编译、建图、序列化/哈希整图或构造完整诊断。安全完整性检查（generation、epoch、target、publication、completion）保持逐帧；其余准备工作只在 load、generation 或明确 invalidation 边界执行。

## 2. 阶段

| 阶段 | 目标 | 完成门 | 当前状态 |
| --- | --- | --- | --- |
| V0 | 普通 material/shader 与首个可见共享链 | 至少一个真实作者输入进入 Program → GraphExecutor → compositor，正反门闭合 | 已闭合；细节见专项表 |
| V1 | Render Graph、FBO、history、effect owner 迁移 | multi-pass、dependency、publication、rollback 和一个真实 generic owner-migration 闭合 | 已闭合 bounded 范围；细节见专项表 |
| V2 | 真实 ECMAScript VM 与 typed host bridge | property/lifecycle script、exception/timeout/reload/stale 反例和 owner 迁移闭合 | 已闭合 bounded 范围 |
| V3 | 粒子 component interpreter | emitter/initializer/operator/renderer/child/control-point 组合与实例生命周期闭合 | 已闭合 bounded 范围 |
| **V4** | **typed input/provider 横切收口** | 每个纳入范围的 producer → typed channel → consumer → next-frame/event，含 generation/cancel/teardown；consumer 不保留私有值/provider/clock | **现在** |
| V5 | Puppet、3D、lighting、离线与发布 | 每个独立领域分别做 visible slice、预算/生命周期、性能/签名/发布门 | 未开始整体推进；按项立项 |

阶段不是完整产品覆盖率。任一阶段回归时，只撤回受影响的 route 并重新通过对应完成门；不要恢复历史专用 owner。

## 3. V4 选择顺序

V4 处理 user property、Timeline、pointer、audio、media、text、video 和 provider。每次只选一个真实纵向结果，优先级按当前运行证据的共享首断点排序：

1. 先解决[运行证据索引](semantics/runtime-evidence-current.md)记录的共享 CPU/pre-encode 首断点；
2. 再闭合一个 typed producer 到真实 consumer 的可见结果；
3. 再补 next-frame/event、cancel/generation/teardown 反例；
4. 最后才更新能力表和运行索引，或扩展到下一个 input family。

不得以另一个 input family 的通过替代 V4 完成，不得先重写全 corpus、full matrix 或完整诊断平台。

## 4. 完成与回滚

每个 atom 都要有：目标合同、当前首断点、一个正例、一个反例、previous-current fallback、最小 completion/publication/next-frame 证据。完成状态分开写：

- `slice-visible`：实际内容进入共享链并有相称的画面/事件证据；
- `owner-migration`：route state、fallback reason、回滚演练和旧产品引用清零；
- `parity-release`：固定官方对照、性能/长稳、签名和发布依赖全部满足。

compile success、recognized/wired、route 数、matrix PASS、非黑像素和单样本通过都不能越级成为上述结论。

进入 `generic-only` 前必须有新组合/未见 fixture 和局部失败反例；通用路径扩大拒绝半径或明显降低画面时，回到 `prefer-generic`/`disable-generic`，保留诊断和 fixture，修复共享首断点后再尝试迁移。

## 5. 何时退休本文

当 V4 所纳入的 producer/provider 都已在能力台账中标为 `supported`、`unsupported-by-contract` 或有明确平台策略，且 V5 各领域均由独立现役合同接管顺序与完成门时，将本文转为历史证据。历史正文中的命令和“下一步”只属于截止日期，不再作为现役指令。
