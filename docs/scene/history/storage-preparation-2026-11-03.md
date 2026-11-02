# Scene localStorage 准备边界后验

> **历史证据 — 非现役入口**

<!-- document-role: historical-evidence -->

> 2026-11-03 固定批次。目标归[重构设计](../roadmap/engine-refactor-program.md#localstorage的准备输入与帧事务)，当前状态归[运行证据](../capabilities/runtime-evidence-current.md)，未闭事项归唯一队列。

<a id="storage-before-frame"></a>
## 同一 Session 准备，帧纯内存事务

Session 初始化只保存 URL；QuickJS Candidate 成功 construction report 确认真实 scalar/vector/string/cursor 任一实例后，在原 configureStorage 前调用同一 storage Session.prepare。idle、event-only、pass、Sound/media 和借用 cursor 仍按真实实例裁决，零 owner 保轻量，不按源码形状或 update 出口猜使用。作者 top-level 仍受原 callback 合同限制；init/事件进入前已有准备结果。

唯一文件读取/解码入口留 prepare，read/apply/beginFrameTransaction 只取已准备 envelope。原 activation 与前任最新内存 envelope 合并、原后台 PersistenceCoordinator 写出/重试及事务接纳/撤销保持；不新增 worker、状态镜像、每帧磁盘版本认证或懒延至第一次 get 的读取。

2 产品文件增23/删4，净增19；3测试文件增118/删6。产品增长是明确准备入口和真实实例调用，未增加持久字段、wire 或流程 owner。

## 身份与验证

| 项目 | 固定结果与范围 |
|---|---|
| 产品 patch SHA-256 | `8fc35686c1bce3de5c35e55b2156b622fca81ba4ac3febbda9edb149e2e59a9f`，按 cache 提交前冻结 source 基线，产品路径不与 cache 重叠 |
| 当前签名 App | `a993632220c3b7628fe21ff0b0872e9771411a87e11df4406d91d1f6cdc81a47`，同时含可选 cache 批；arm64 Debug `-O`、Team `H9QWU9XN8R`、严格验签，6产品文件构建身份不变 |
| 真实 Candidate/事务 | storage 19例通过；同一 Session 准备后修改磁盘，再让真实 init/get 读原准备值并写下一值，证明不是换空实例或帧再次读取。覆盖零 owner、idle/event/media、两实例隔离、坏/未来载荷局部失败 |
| 前任/候选与退出 | 原真实 late peer 写入、activation merge、候选未晋升、discard、配额、replay及固定点恢复/稳定拒绝反例保持 |
| 相邻 VM | String lifecycle 4例与 shared identity 12例分别通过；同一 domain/shared heap及原失败/禁用行为保持 |
| 实际 App | 两份不变原包及可选cache四native例在联合App通过、正常退出/排空；这不是专项持久数据的端到端用户验收，不认领首帧耗时或能耗收益 |
| 本机 provenance | `.artifacts/scene-architecture-continuation-20261102/` 的cache/storage冻结源码、构建、identity、初始失败与最后storage门；详细原样保留 |

## 首失败与纠正

- 新隔离 session 的 peer 变量与原 VM peer 同作用域重名，仅改名，后续类型错误随之消失；产品无关。
- 原恢复门假定不同 owner 写同一 alpha 会冲突，但现役按顺序覆盖。改用真实 deferred authored destroy→后写已退层的失败，继续原恢复 `[1,3]/[2]`、稳定拒绝 `[3]/[1,2]`、seed诊断和健康peer断言；不恢复已退仲裁或放宽期望。

本批关闭帧首读职责，不证明系统 I/O、全语料或整体性能/架构已收口。当前相机、活动消费者退休、M3剩余及产品daemon继续按现役设计。
