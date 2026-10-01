<!-- document-role: active-plan -->
<!-- retirementCondition: 对象排放控制与宿主暂停的组合合同通过事务和可见门，未知 reset profile 有明确归宿后归档。 -->

# D11 — 粒子对象播放门与 reset 边界

> 复核基线：2026-10-02（按 D10 现役模拟单次消费合同收敛）；原设计基线为独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；已合入 `codex/engine-refactor-program`；实施时按其最新代码重新核对所列 owner，本轮更新的 PlaybackState 证据行号指向主分支当前代码，其余旧指针须在实施前重核。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

每个粒子系统拥有独立的作者播放意图，宿主暂停不会改写该意图。公开 `pause()` 停止新粒子排放，已存在粒子仍模拟；宿主 pause 才冻结 scene 时间。对象 stop 清空存活粒子。跨脚本命令、模拟事务、子粒子与绘制，触及唯一 clock 和 lifecycle。

五判据：横切多个 owner 或主链节点=是；触碰唯一权威合同=是；用户可见且难逆的 API/数据/发布合同=是；触碰机器冻结结构家族=否；依赖官方或平台外部证据=是。

## 当前事实与证据

- `MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePlaybackState.swift:59` 的 `advance` 已直接消费共享 delta，`:68` 推进现役 runtime，`:120` 限定实时追帧债务；旧 prepare/commit/discard 口径已被 [D10](frame-admission-retry-design.md) 撤权，不能恢复或新增平行 PlaybackState。
- [官方 IParticleSystem](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IParticleSystem.html)（2026-10-02 再核对）：play 恢复排放或结束后重启，pause 停排放，stop 清空，isPlaying 同时考虑排放或模拟，emitParticles 可绕过对象 stopped/paused。这优先于交接“对象 pause 冻结模拟”的可能理解。
- `reset_sequence` / stay-paused 是交接研究方向，本基线未提供可确认公开签名；不把第三方内部控制选项新增为官方 JS API。

## owner

[D4](script-component-api-design.md) 的桥接产生 owner-scoped typed command。作者 intent 与 transition revision 归现役 `SceneScriptDynamicLayerRuntime` 的 typed layer state，沿现役 candidate plan 准入并发布 immutable committed snapshot；C handle 仅作镜像和 callback journal，不新增 session 意图库。各 surface 的 SceneParticlePlaybackState/Runtime/Simulator 独占实际 emitter schedule、存活、ID、随机流及已消费 revision；session shared evaluation 决定本 cadence 输入消费，各实例消费同一已准入有序 transitions 一次。Host sceneClock 仍提供 delta，render batch 不拥有第二份播放开关；session 查询只是现役实例的只读 projection，不成为共享 simulation。

## 方案设计与选型

选择**对象 emission state 与 host execution gate 正交**；拒绝简单 Bool 同时控制 visibility、排放、模拟和用户暂停。

| 对象状态/命令 | 新排放 | 已有粒子 | 状态查询/转移 |
|---|---|---|---|
| playing | 按作者 emitter 规则 | 正常模拟 | 自然结束且存活耗尽后 isPlaying=false |
| pause | 停止自动排放 | 继续模拟到死亡 | 有存活时 isPlaying=true |
| stop | 停止 | 本次成功事务清空 | isPlaying=false；play 可重新启动 |
| play | 恢复/自然结束后重启 | 已存活者不因恢复重复初始化 | 不自动清空已有系统 |
| emitParticles(n)，后继未开放 | 公开行为允许绕过对象 pause/stop | 须实际 birth preflight 后进入同一模拟与预算 | 本首片明确 unsupported，不隐式改写自动排放意图 |
| host pause | 不推进任何时间驱动排放 | 冻结 | 保留对象意图；恢复后对象仍保持原 pause/stop |

首片只开放 play/pause/stop/isPlaying，限定已准备 root、无任何 authored child、恰一 supported 确定性 emitter schedule（periodic disabled 的有限 duration/burst，或 supported 且 duration/delay 各自 min=max 的周期窗口）；无 child 必须检查作者定义，不能以 childRuntime 为 nil 冒充通过。多 emitter、随机周期、children/reset 和全部 emitParticles 调用保持 unsupported。显式 burst 的后继须沿已有 emitter identity、makeParticle/initializer、birth RNG、ID、events 与容量做真实 birth preflight；`SceneParticleSimulator.swift:676` 可拒收 lifetime≤0 或非法出生，不能用 n>0 替代实际出生，也不能成功提交少于承诺的数量；省略 count 默认继续未知。预算沿 D4 既定上限与现役更小容量，不另造阈值。

同 callback 基于已提交 query snapshot 按作者顺序折叠本 owner journal：stop 后立即查询 false；pause 保留 liveAny，因此有存量仍为 true；play 恢复尚未完成的发射 schedule，仅对已自然完成或 stopped 的实例重新 arm，不能把方法调用直接等同于有发射活动。是否 arm 后仍有发射工作由现役 emitter plan/state 判定，零工作系统不得假报 true。owner admission 的 candidate plan 保留有序 transitions，stop→play 必须先清空再恢复，不压扁为最终 intent。typed command 携现役 domain.callback_epoch 与 callback 内 ordinal，恢复实际 callback 调用顺序，不按 owner 分组后 flatMap 猜序，也不新增 clock；owner rejection 先移除该 owner 的命令，再重算 candidate intent、transitions 与 revision。宿主暂停不绕过现役 frame gate 执行新模拟，不新增外部控制回调入口或第二 clock。

查询在首次任何作者 callback 前从已准备实例发布，并在每 cadence 的共享 VM evaluation 前刷新。对当前 generation/完整有效 surface 集合，以 `liveAny || emissionActiveAny` 作 OR；emissionActive 来自作者 playing intent 与各实例尚有发射工作的现役 schedule，不能由本帧恰好有没有 births 推断。projection 还须从同一 emitter plan/state 提供“暂停中仍有待续发射”及“重新 arm 后有工作”的只读事实，供 staged play 推导；仅传两个 OR Bool 不足以判定 play，不在 C 复制 schedule 数学。此 OR 是项目跨屏合同，不是已实测官方多屏语义；指针源可能令各屏在 `SceneParticleSimulator.swift:568` 的 emitter frame 准入处产生不同进度。准备与准入均验证该完整同代集合；隐藏、静态 alpha=0、资源失败导致缺 runtime，或 stale generation，使该对象 projection unavailable，调用明确失败，不跳过缺失屏、不从首屏取值，也不以空集合返回 false。C 仅叠加本次 callback 的转移；同 owner 的其他 callback 和其他 owner 均读本 cadence 已提交镜像，不能把多个到期 timer 或 ended handler 合并成一个 callback。

首 launch 保留现役 warm-up 的真实 prepared-live，init 查询观察这些存量；init.pause 只阻止 owner admission 后的自动排放，已有粒子继续模拟，init.stop 在首个 updateSimulation 前清空 live、旧 batch 与历史。官方 warm-up/init 次序仍未知，此为项目初始化边界，不宣称 parity。

自然完成后的 play 在现役 emitter schedule owner 内重新 arm，重新开始 initial delay、elapsed、remainder 和 instantaneous 发射游标；保留 simulationTime、现存粒子的年龄/状态、nextParticleID 与 birth RNG，不重跑 warm-up。暂停未完成的 schedule 后 play 仅继续，不重置 delay。重新执行 initial delay 和保留 birth RNG 是本项目保守策略，公开文档只确定“完成后重启”，不宣称官方 delay/随机序列 parity；周期 RNG 未定的随机周期 profile 不准入。stop 清除 live、当前帧 transient render samples、未派发事件及其 trail/cache，并在同一现役 schedule 重置上述局部发射游标但保持排放关闭，不推进 RNG/ID/time、不重跑 warm-up。这样 stop→pause→play 仍从停止后的 schedule 开始，不能因最终 intent 变为 paused 而恢复停止前游标；C staged 查询须与此顺序一致，不另加持久 latch。旧 draw batch 或 birth/death 事件不得在下一帧复现。

reset 作为内部独立 transition：成功提交时归零该系统 elapsed/emitter cursor/sequence 状态，清空其存活粒子与未派发事件；显式携带 reset 后的 emission intent，防止 stay-paused 被 reset 自动变成 play。是否重置随机流、warm-up、子系统及官方回调次序必须以公开/黑盒合同固定，未解决前 reset profile 不准入；不得凭名称把 seed 设零。普通公开 play/pause 不隐含 reset_sequence。

对象 command 先进入现役 callback owner admission；通过后，在每屏 updateSimulation 前按同一有序计划消费并记录 revision，再推进 emitter accumulator/particle storage 并派生 draw batch。C journal、Swift candidate plan 与其他同 owner effects 同时接纳或拒绝；拒绝不更改 committed intent 或任何实例，不承诺回滚 JS heap。消费后共享提交发布最终 intent/revision，丢弃当 cadence transitions；后续 GPU 失败不再拥有它们。每屏上传/提交是模拟之后的独立阶段，不保存供 GPU 失败重放的第二份命令或模拟快照。

surface rebuild 从同一 committed typed intent 初始化新实例，并把当前 revision 设为消费基线；不重放旧 command、stop→play 序列或未来 burst。rebuild 已知的 committed paused/stopped 意图必须在新 simulator 构造前注入、warm-up/首次 advance 前生效，不能先默认发射再补开关；stopped 新实例为空，paused 新实例不得自动生成粒子。rebuild 期间不执行依赖不完整实例集合的作者查询，完成后重新发布实际 projection。此片保证作者意图保留，不将现役 surface 重建的粒子重建行为宣称为 simulationTime/live/RNG 连续迁移；playing 的重建实例可能重新开始作者 schedule，须以独立重建反例记录这一项目边界。场景 reload 则撤销旧 generation/handle，不继承旧命令。

## fallback / route

unsupported reset/child profile 仅拒绝该 command 并保留原对象状态；无效 handle/generation、粒子预算或 OOM 硬拒绝该不安全事务。尚未通过 callback/owner admission 的命令局部拒绝并保持该对象原状态；通过共享模拟消费后，即使全部 surface 无 drawable、encode/提交拒绝或异步 GPU 失败，也不回退 simulation、VM 事件或 pending command。每屏只取消未提交资源或保留其 GPU previous-current；恢复上传最新模拟状态，不能重放已消费 burst。不以隐藏 draw batch 冒充停止模拟。

## 纠正门

- 两对象 A pause、B play，观察 A 无新排放但已有粒子继续，B 正常；再 host pause/resume，A 仍停排放。真实 QuickJS 以非零 startTime 验证 init.pause 保留 prepared-live 且准入后无新增排放，init.stop 首图清旧 batch/历史；stop/pause/isPlaying、stop→query、pause→query、stop→play 和重复 pause 均经 Swift owner admission 到实际模拟。
- periodic disabled 的有限 duration/burst 自然完成但仍有存量时 play 重新 arm，存量年龄/ID 不变；delay 重新开始、birth RNG 连续、固定 min=max 周期未完成暂停后继续、stop→pause→play 不恢复旧游标、零工作系统查询分别验证。emit/default count、随机周期、多 emitter、任意 authored child、reset 均有明确 unsupported 反例。
- 两屏 pointer 内/外令发射进度不同，查询证明 OR 且不依赖遍历顺序；隐藏/alpha0/资源失败缺 runtime 或 stale generation 不能 false。rebuild 前 pause/stop、重建期间查询不可用、重建后 intent/revision 生效且无旧转移重放；playing 重建的现役模拟重建边界单独记录，不冒充状态迁移。
- 分开验证两种失败：跨 owner 交错 callback 按既有 epoch/ordinal 保序，callback/owner admission 拒绝先移除该 owner 命令并重算，不得留下 C overlay、部分对象命令或任一屏状态；模拟成功后的 busy、drawable 缺失、所有屏 encode 拒绝和 GPU failure 不回退 state/event/random 或重复 burst。reload 后迟到 command 按 generation 拒绝，恢复帧只呈现最新状态。
- reset/stay-paused 只有在默认、随机、warm-up 与 children 行为可区分的官方实验完成后开放；项目自有 reset 不能报告官方 parity。真实 GPU/compositor 多帧观察与对象 count 同时记录。

## 退役条件

现役 typed layer state 独占作者意图、各 surface runtime 独占实际模拟，公开四方法语义纳入脚本合同、正反例及可见门通过后归档；emit/reset/children unknown 须明确继续禁用或补合同，不能被一起默认为支持。
