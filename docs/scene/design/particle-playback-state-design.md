<!-- document-role: active-plan -->
<!-- retirementCondition: 对象排放控制与宿主暂停的组合合同通过事务和可见门，未知 reset profile 有明确归宿后归档。 -->

# D11 — 粒子对象播放门与 reset 边界

> 复核基线：2026-10-01，独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；已合入 `codex/engine-refactor-program`；实施时按其最新代码重新核对所列 owner，以下行号仍指向原设计基线。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

每个粒子系统拥有独立的作者播放意图，宿主暂停不会改写该意图。公开 `pause()` 停止新粒子排放，已存在粒子仍模拟；宿主 pause 才冻结 scene 时间。对象 stop 清空存活粒子。跨脚本命令、模拟事务、子粒子与绘制，触及唯一 clock 和 lifecycle。

五判据：横切多个 owner 或主链节点=是；触碰唯一权威合同=是；用户可见且难逆的 API/数据/发布合同=是；触碰机器冻结结构家族=否；依赖官方或平台外部证据=是。

## 当前事实与证据

- `MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePlaybackState.swift:4` 已有该类，`:64` 接共享 delta，`:91`/`:99`/`:111` 是 prepare/commit/discard；`:149` 起限定实时追帧债务。不能新增同名或平行 PlaybackState。
- [官方 IParticleSystem](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IParticleSystem.html)（2026-10-01）：play 恢复排放或结束后重启，pause 停排放，stop 清空，isPlaying 同时考虑排放或模拟，emitParticles 可绕过对象 stopped/paused。这优先于交接“对象 pause 冻结模拟”的可能理解。
- `reset_sequence` / stay-paused 是交接研究方向，本基线未提供可确认公开签名；不把第三方内部控制选项新增为官方 JS API。

## owner

[D4](script-component-api-design.md) 的桥接产生 typed command；现役 SceneParticlePlaybackState 保存 frame transaction；SceneParticleRuntime/Simulator 每对象状态是 emission/存活/sequence 唯一权威。Host sceneClock 仍提供 delta，render batch 不拥有第二份播放开关。

## 方案设计与选型

选择**对象 emission state 与 host execution gate 正交**；拒绝简单 Bool 同时控制 visibility、排放、模拟和用户暂停。

| 对象状态/命令 | 新排放 | 已有粒子 | 状态查询/转移 |
|---|---|---|---|
| playing | 按作者 emitter 规则 | 正常模拟 | 自然结束且存活耗尽后 isPlaying=false |
| pause | 停止自动排放 | 继续模拟到死亡 | 有存活时 isPlaying=true |
| stop | 停止 | 本次成功事务清空 | isPlaying=false；play 可重新启动 |
| play | 恢复/自然结束后重启 | 已存活者不因恢复重复初始化 | 不自动清空已有系统 |
| emitParticles(n) | 显式 burst 即使对象 pause/stop 也允许 | 新生进入同一模拟与预算 | 不隐式改写自动排放意图 |
| host pause | 不推进任何时间驱动排放 | 冻结 | 保留对象意图；恢复后对象仍保持原 pause/stop |

首次实施只开放显式合法整数 n，省略参数默认另由 D4 公开声明门固定。宿主暂停时外部命令可 staged，但不绕过 frame gate 执行模拟；恢复或现役允许的控制事务提交后生效。多命令按作者事件顺序处理，不能错误 coalesce 掉 stop→play 或 emit→stop。

reset 作为内部独立 transition：成功提交时归零该系统 elapsed/emitter cursor/sequence 状态，清空其存活粒子与未派发事件；显式携带 reset 后的 emission intent，防止 stay-paused 被 reset 自动变成 play。是否重置随机流、warm-up、子系统及官方回调次序必须以公开/黑盒合同固定，未解决前 reset profile 不准入；不得凭名称把 seed 设零。普通公开 play/pause 不隐含 reset_sequence。

对象 command、emitter accumulator、particle storage、child event 队列和 draw batch 进入同一 frame snapshot。父 stop/reset 的子系统影响先限定“该对象拥有的派生 child”，独立 scene 粒子层不受影响；子系统具体 stop/死亡事件传播仍需公开/黑盒区分，未证明的组合局部禁用。

## fallback / route

unsupported reset/child profile 仅拒绝该 command 并保留原对象状态；无效 handle/generation、粒子预算或 OOM 硬拒绝该不安全事务。GPU/提交失败沿现役 rollback 恢复 simulation 与 pending command；恢复不能重放已提交 burst。不以隐藏 draw batch 冒充停止模拟。

## 纠正门

- 两对象 A pause、B play，观察 A 无新排放但已有粒子继续，B 正常；再 host pause/resume，A 仍停排放。stop 后清空、play 后恢复、paused 时 burst 精确计数。
- 控制命令序列 stop→play、emit→stop、重复 pause、自然耗尽、生命周期边缘死亡与 child event 分别验证，不能仅断言 enum。
- 注入 busy/discard、GPU failure、reload 后迟到 command；state/event/random snapshot 必须完整回滚且 next-frame 无重复 burst。
- reset/stay-paused 只有在默认、随机、warm-up 与 children 行为可区分的官方实验完成后开放；项目自有 reset 不能报告官方 parity。真实 GPU/compositor 多帧观察与对象 count 同时记录。

## 退役条件

既有 runtime 成为唯一对象控制 owner，公开语义纳入脚本合同、正反例及可见门通过后归档；reset unknown 须明确继续禁用或补合同，不能被一起默认为支持。
