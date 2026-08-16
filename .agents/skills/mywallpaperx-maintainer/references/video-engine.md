# Video 开发方法

本参考保存本地/在线视频从产品库到每显示器 helper 输出中不容易从单个文件恢复的 owner、identity 和生命周期方法。当前文档角色索引没有独立 Video current-state/stable-contract 入口，因此这里的 owner 标签、事务形状和实现方式只是必须现场复核的发现假设与默认方法，不定义目标架构。目标由用户行为、`AGENTS.md`、长期技术边界和当前任务中明确成立的设计裁决；当前代码只证明现状。Scene 视频纹理与 Web media 不属于本执行链。

## 目录

1. [先重建当前链](#先重建当前链)
2. [职责重建与默认边界](#职责重建与默认边界)
3. [导入与派生资产](#导入与派生资产)
4. [Identity 与用户意图](#identity-与用户意图)
5. [IPC 与 helper 生命周期](#ipc-与-helper-生命周期)
6. [可见切换与系统状态](#可见切换与系统状态)
7. [失败半径与 correctness atom](#失败半径与-correctness-atom)
8. [验证与反漂移](#验证与反漂移)

## 先重建当前链

从用户动作向下追踪，不从本 Skill 的旧路径开始：

```text
AppKit command
  -> product library / selection / import owner
  -> playback intent and runtime-switch chain
  -> Video request plus per-display session owner
  -> helper IPC
  -> AVFoundation preparation and visible slot commit
  -> correlated ready/frame/teardown evidence
```

使用 `rg` 查 `setAsWallpaper`、`activeWallpaperRuntime`、`playbackIntent`、`displaySessions`、daemon command/event 和 helper ready/commit；核对两端 wire schema 和测试。长期语言、进程和 AppKit 边界只从 `docs/architecture/technology-stack-boundaries.md` 读取。

## 职责重建与默认边界

先沿当前调用链验证下列职责是否仍成立；它们用于寻找重复 owner 和 identity 漏洞，不能单独裁决新的迁移目标：

- 产品库 owner 管理规范视频记录、导入/移除、索引、持久化、选择、用户 intent 和派生资产 publication。
- 主进程播放 owner 管理 Video request、intent epoch、每显示器 helper session、IPC correlation、系统 pause evaluator 和恢复策略。
- helper 管理真实桌面窗口、AVAsset/item/player/layer、inactive/active slot 与可见提交；它不拥有产品库或全局用户选择。
- UI 展示投影并发命令，不保存第二套播放真值或绕过产品设置入口直达 helper。
- 跨 runtime 切换可能横跨 Manager、coordinator/notification、Engine、系统输出 API 和目标 host。每次从当前代码确认所有 runtime kind 与顺序；不要把 Video/Web session owner 外推成 Scene 或系统静态输出 owner。

只有真实复用、独立生命周期或缺失的 typed boundary 才允许新增协议/actor/store。便利转发不构成第二 coordinator 或扩大公开 API 的理由。

## 导入与派生资产

以下事务形状是导入链的默认审查模型；从当前 producer、commit 点和目标合同逐项确认，而不是把它当成固定类型图：

```text
selection/download completion
  -> background normalize/deduplicate/inspect
  -> import-generation check for the library transaction
  -> main-owner model/index commit
  -> background thumbnail/static-frame/metadata
  -> autoplay-token check at the playback commit
```

- 重 I/O、AVAsset 和图片处理不阻塞 AppKit 主线程；UI presentation 与 security-scoped access 留在明确边界。
- 清缓存、移除、新导入或取消必须使旧 generation 失效；旧 worker 不得重新发布已删除的 model/cache。
- 同资源的 in-flight 派生任务应合并；失败抑制只能有界，不能永久遮蔽恢复后的源文件。
- import generation 与 autoplay token 是不同 identity：前者阻止旧导入 worker 覆盖新的库事务；后者只决定完成后是否仍可自动播放。online/Workshop 下载与合法入库可以完成，但用户之后选择的 runtime/content 不能被旧 completion 抢回。
- bundled archive 只经校验 staging 和原子替换进入库；完成标记绑定真实 archive/version identity。
- 用户源视频保持只读。thumbnail、static frame、索引、staging 和 cache 才是可重建派生物。

## Identity 与用户意图

路径规范化用于索引、去重和资源定位，但路径不是完整异步 identity。跨线程/进程提交至少考虑：

- playback intent epoch；
- normalized content identity；
- runtime kind；
- display 与 helper session identity；
- request ID；
- import/cache generation；
- teardown/restart generation。

producer 创建工作时捕获 identity，consumer 提交前验证；不要在 completion 到达后读取 mutable current state 并给旧工作重新贴标签。避免分裂成互不关联的多个 intent gate；发现重复 epoch 时先确定唯一提交点和撤权关系。

模型或 wire enum 使用明确的协议值；本地化 label、路径展示和 enum `rawValue` 不得偶然成为 IPC 合同。文件可读不等于 codec/track/AVFoundation 可播放。

## IPC 与 helper 生命周期

wire schema 变化作为一个原子职责更新：schema/默认兼容、主进程编码、helper 解码/handler、helper event、主进程解析/stale guard，以及 malformed/unknown/old-request 反例。不要只改一端。

区分证据阶段：

| 阶段 | 仅证明 |
|---|---|
| command sent | pipe 写入成功 |
| accepted | 当前 helper 接受命令 |
| prepared | asset/item/player 达到所定义的准备条件 |
| visual commit | incoming slot 成为当前可见 owner |
| correlated ready | 当前 session/request 的 helper 提交完成 |
| frame evidence | 目标 display 出现预期内容/运动 |

事件改变主进程状态前验证 session/process、display membership、request、content/runtime、intent epoch 和 restart generation。旧 pipe reader、termination callback、player observer 或 delayed ready 不得作用于替代 session。

helper crash/restart 以 display 为失败半径并使用有界 backoff；其他 display 不应无故重启。新 process 必须获得新 session identity，成功的当前可见播放后才重置对应恢复状态。

## 可见切换与系统状态

先从当前 helper 重建切换策略。默认延续现有 owner-preserving 双 slot：保持 active 可见，inactive 准备 incoming，达到有界 readiness 后原子切换/crossfade，再发 correlated ready 并释放旧 item/player observers。若更强证据支持替代实现，它仍必须在准备失败时保留此前可见 current，不能先清空 active layer，并保持原子提交、correlated ready 和旧 observer 释放合同。

用户 pause、sleep/lock/display sleep、focused/fullscreen app、battery/idle 等进入共享系统状态 evaluator；UI、helper 和模块私有布尔值不能各自复制策略。resume 重新评估当前原因，不能无条件 play。Scene 可能消费共享 pause/audio 投影，但其 session/surface 仍由 Scene owner 管理。

## 失败半径与 correctness atom

一个 Video atom 应闭合：真实输入 -> 当前 intent -> 一个或多个 display request -> helper prepare -> visible commit -> stale/teardown counterexample。按风险选择：

- 单视频不可访问/解码：失败当前 request，保留 previous visible，交回产品 owner 决定恢复。
- 单 display helper 失败：只重建该 session。
- stale completion/event：丢弃并记录来源/current identity，不改变用户意图。
- thumbnail/static-frame 失败：只缺少该派生资产，不删除库记录或源文件。
- index/cache 损坏：重建派生状态，不修改源视频。
- malformed/unknown wire command：只拒绝该 command 并记录原因；只有 session negotiation、协议版本或关联 identity 已无法安全解释时才终止受影响 display session。
- 全局系统 interruption：由共享 evaluator 作用于适用 runtime。

反例至少覆盖一个新 intent 后旧 completion、session teardown 后 callback、display removal/replacement，以及准备失败保持 previous visible。导入变更还覆盖 duplicate path 与逆序 completion。

## 验证与反漂移

用 `rg --files script/tests` 与当前调用链选择最小 Video/import/daemon/runtime-switch tests；不要把本 Skill 中的旧测试名当现役清单。Swift 产品变化再按仓库当前 checkpoint build；可见声明需要隔离输入、真实 App/helper identity、逐 display request、visual commit 和 frame evidence。

完成前确认：没有第二播放 coordinator/pause evaluator；没有 UI/helper 取得产品真值；没有绕过 intent/session guard；没有把 Scene provider 或 Web media 合并进 Video helper；没有只用 path/fixed delay 表达 identity/readiness；没有改写或删除用户源文件；没有把 accepted/ready/build 提升为可见播放正确。
