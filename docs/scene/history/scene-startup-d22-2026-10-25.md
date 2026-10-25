# Scene 启动 D22：子入口六点与调用窗定位

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-25；顺序与后继归[启动专项](../../development/wallpaper-startup-optimization-plan.md)。本批完成观测与一次原入口诊断，不认领提速、AppKit内部原因或整体无回归。

## 改动与验证

设计先落原P0/registry。原Client仅在DEBUG prefix observer存在时附显式子flag；App在Scene role及flag判定后取entryObserved，原NSApplication.shared前后与Runtime构造前后各取一次。前五点局部值一次交原Runtime并清局部引用，原configure在hello编码前冻结最后snapshot，原hello携8整数。没有移动初始化或更改原版本/role/握手/replay/lease/提交/退出；没有额外请求、事件或时钟owner。原callback/reducer独立核数值/schema/PID/当前ticket/epoch/request/generation，自身顺序与父startBegan/hello边界；不要求child入口晚于父startReturned。暖无新hello报告notApplicable/null；坏诊断不改产品hello或原首帧/父五段passed。

7个Swift文件DEBUG-off投影与改前逐字节相同，属于静态等价而非Release构建。两最近门原23+23条事实保留，现44/35项事实实际执行全true；共7个unittest方法、12条原生命令（6编译/6执行）均0、无skip，5952输入未变。原source/lease/同ticket/transport回归保留；Client carrier编入真实SwitchEndpoint及严格decoder抽取，不等同完整consumeOutput或App执行。原Scene daemon自动路由补入实际startup reducer/取消门，7变更Swift均有映射；没有新增测试框架或产品owner。

实际Debug `-O`/WMO/arm64、ENABLE_DEBUG_DYLIB=NO、零override，从5952文件冻结副本构建，前后源码不变；410.868s仅构建时长。App为Startup独立测试身份、2.11.0(283)、Team H9QWU9XN8R；exe `691802cd…90af`、CDHash `ded6008e…695b`、source-map `e18e7b0e…84ce`，strict签名0。shader语义`182dc218…dcc`、toolchain `a3a31085…5e`及267540B stock manifest `46984e52…94a6`保持；没有运行旧binary或生成dSYM/重试外部profiler。实际LSUIElement=true，不支持仅切该flag的猜测。

## 原入口一次诊断

另一独立工作树与root/代理明确释放、全静默后执行原四helper/core.main。iterations1、30FPS、90s外限/45s每行，原3App/4请求，原计时/汇总/默认域/清理未改；driver `d4bfc280…9493`、protocol `c3da86ea…7776`。真实输入沿原D15托管publication，generation `1cd11e13-001f-4c4b-a376-6dac1d4534d6`，作者/库原件均只读。窗口UTC21:56:57.915–21:57:08.329，exit0后立即释放，无第二次采集。

| 条件 | 接受观察 ms | 实际presented ms | startBegan→child入口 ms | NSApplication.shared调用 ms | Runtime构造 ms | snapshot→父hello ms |
|---|---:|---:|---:|---:|---:|---:|
| C0 | 667.672 | 1917.824 | 8.759 | 520.610 | 67.862 | 0.297 |
| C1 | 656.202 | 1009.308 | 10.426 | 554.723 | 70.737 | 0.301 |
| W0首请求 | 658.646 | 982.153 | 8.177 | 561.470 | 68.358 | 0.296 |
| W0同daemon暖请求 | 1.713 | 209.281 | null | null | null | null |

三fresh parent/child各自资格通过，暖parent原两点通过且child合法notApplicable、events/reportedPID/8interval全null；W0 PID99768/gen1不变但request/execution各自不同。C0/C1 child PID99690/99752，完整ticket/request/execution/6raw值保原native。四行全部沿原source准入、actual-presented及parent finalize；3App正常退出/owned children0，测试标准域/suite/HOME/staged App按原owner清理，生产偏好本轮前后语义与磁盘摘要均相等。15个1s/边界进程快照无观察到foreign/error，不证明整host或亚秒空闲。

## 结论与保留

改前D20仅把C1 start返回→父hello缩为631.921ms组合窗；改后可在本次原请求内分出上述调用窗。不同binary/签名/观测与系统缓存条件使两批不能组成A/B；C0仅私有HOME为空，不是OS/GPU全冷。本组没有调整启动工作或重跑五对，不能称新增性能收益或解释D19 C1正差。入口点含最初参数检查，start调用可与child执行重叠，不能叫独占dyld；AppKit窗可能含调度和框架服务等待，Runtime包含Host/defaults/预算设备，不能分别冒称CPU或Metal独占；最后点在编码前，非enqueue/write完成。

三fresh日志有sandbox_extension_issue_file_to_process/Operation not permitted；精确D20三对应原日志已出现相同警告，不是D22首次出现，不能称日志零错误或据此归因。三native的daemonFinalizeAndDrainObserved仍为false：原report生成时未观察到typed退出ACK，正常App/child退出不是GPU/AV drain正证。旧seek、Web尾延迟/实音连续性及完整P2/P3/P7不因本批关闭。

后继只读核查定位到原Client跨类型退休常见分支会stop/exit，而warmSession已有同transport复用；候选仅针对同App切回Scene，不改善首次C0/C1，也尚未测净收益。现retireOutput ACK只核窗口撤回，release另路且Host忽略drain false，尚不授权idle复用。须沿原Host/Client精确代次和原queue/Session成功终态闭合，保rollback/显式退出与有界TTL；AV最终borrower/RSS不能随Session冒称归零。没有实施该候选，完整后继裁决仍归专项。

必要raw/native/日志、最近门、冻结源的HEAD blob与所有nonHEAD字节、final owned覆盖及独审归本机`.artifacts/scene-evidence/runs/wallpaper-startup-scene-d22-20261025-checkpoint/`。归档校验后清本轮已停源/执行副本和重复收集，连续迭代仅保任务DerivedData与既有必要实际对照App/同代输入；不保全App/媒体/HOME重复。未暂存、未提交、未推送；goal仍活动。
