# Scene 启动 D20：父端预接受分段

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-25；后继归[启动专项](../../development/wallpaper-startup-optimization-plan.md)。本批只补被动DEBUG观测，诊断/回归通过；没有启动实现提速或两臂因果结论，P2/P3/P7与旧失败仍开放。

## 改前与改后

D19保留的十份C1原native/app.log离线复核：entry→父观察accepted配对差中位+35.027ms，其后到presented配对差中位+1.413ms。旧日志无admission/spawn/hello/load单调时间，不能细分或跨进程拼墙钟；本输入已有ref，不走旧nil-ref升级。不能将两个配对中位相加为总差，亦未把另一批同b502结果混入配对。

专项P0设计与窄登记在实施前保存。沿原Client新增五处父端systemUptime值事件：实际prepareSwitch收到准备、transport.start前/返回、原合法hello消费、原load send之前。准备点使用incoming ticket，涵盖准入/属性/Shell等总和；transport.start调用含原registry/Process.run/reader安装，hello含接收/parent-main排队，enqueue只为尝试。独立reducer按ticket/epoch→load request/generation/PID→prepared身份核等，忽略foreign ticket/epoch，拒同票重复、错代、倒序及必需事件缺失；暖选择的spawn/hello缺失保null且可通过。无observer不取时钟，原runner完毕撤销。IPC、调度、来源lease、候选/输出、超时和原首帧资格未改变；五个Swift关闭DEBUG后的源码投影逐字与改前相同。

原纯值门9检查完整保留，新增14个prefix正反例；原真实SwitchEndpoint/Client取消门20检查保留，新增incoming ticket、原wire身份与撤observer三例。一次6测试方法、12原生编译/执行命令、0skip通过，全5950冻结输入无漂移。原metadata/marker/lease、同ticket取消、source/wire/hello以及真实transport退出/管道边界守各自范围；没有重跑未改的全Scene或旧seek门。

## 实际构建与一次诊断

5950输入冻结、无task覆盖；原Debug -O/wholemodule、Startup专用身份/Team构建404.655459s成功、strict签名0，snapshot/live哈希均不变。实际exe `7304834ecf38c65ffad031dcae8a018bd59572d80aef962c5184438957434ef9`，CDHash `f15987d3346ec0838a74969f4ac0526b8ace6ed2`；source map `aafc563798120e801c480bc3c58ef3ce19ef3dcf68329790c8511a56e4abf635`。stock清单267540B/SHA `46984e52…94a6`、shader semantics `182dc218…79dcc`及toolchain `a3a31085…305e`与D19相同。改前D19实际7e537 App另保留，不以重建产物替代。

驱动 `1b444ecc…57cc9`/protocol `cf797345…b8fa`绑定实际成功构建，原四helper及核心main/计时/隔离/清理函数不改，单臂iterations1、30FPS/outer90s/native row45s。仍同一真实managed发布generation `1cd11e13-001f-4c4b-a376-6dac1d4534d6`、原全source及三publication guard。prepare为0App/0compiler/0publisher，Root审实际协议后才执行。独立工作树只在同机实测短窗协调，源码和缓存归属分开；读到对方root与三agent实际ready字段后，唯一一次execute约10.139s，完成即释放。

| 选择 | entry→acceptedObserved（ms） | start返回→helloObserved（ms） | entry→presented（ms） |
|---|---:|---:|---:|
| C0 | 658.612 | 592.640 | 1996.859 |
| C1 | 648.817 | 631.921 | 1038.081 |
| W0首项（建立active） | 639.449 | 624.392 | 990.828 |
| W0暖项 | 2.711 | 缺失，未补值 | 222.173 |

C1内另有准备10.592ms、准备收到→start前0.171ms、start调用0.410ms、hello→load尝试0.295ms、load尝试→accepted观察5.428ms。上述相邻边界在同一row可核算整个父观察窗，不是独占CPU成本或child发生时刻；不跨row相加中位数。前三个新daemon事件集均五项，暖项仅准备与load两项，且与本App第一项同PID/generation。原3App/4请求呈现/finalize和独立prefix资格、完整实际source、签名/defaults/HOME隔离、正常退出/owned children0及清理均通过；当前生产偏好整轮不变。15个1s/边界快照无foreign或错误，不证明亚秒或整host无负载。

这次将主要等待缩小到start返回→父观察hello，不能证明D19那+35.027ms的原因，也不与D19中位数作A/B。静态冻结源确认hello前有AppKit、原Host两次profile读取、原ResourceBudget→MTLCreateSystemDefaultDevice预算探测，尚未独占计时。后继先分exec/动态加载、AppKit/Host和事件调度；不凭调用存在就改预算或把工作移过accepted来制造收益。D14已有sample无栈失败，后继先核方法资格与停止条件。

## 关闭边界与保留

三份 `daemonFinalizeAndDrainObserved=false` 保原样：报告在shutdown前固定写此值。原Client把transport和lease移retiring，物理进程终态才结清；子端有原Host/Session CPU+GPU排空回调和typed exited，但父端当前未采ACK，2s grace/强制退出也可完成终态。App0/child0不能证明positive GPU ACK或通用AV drain，本批不改生命周期、不关闭该门。

必要原点、12命令raw字节、原源码/窄差异、实际构建与5950源重建、协议/ready/finished和独审归本机 `.artifacts/scene-evidence/runs/wallpaper-startup-scene-d20-20261025-checkpoint/`。归档核验后清本轮已终态的构建source、执行环境和采集副本，保一份任务DerivedData及明确需要的旧实际App/同代输入；精确去留见cleanup收据。后续文档变化不冒充已编进App。未暂存、未提交或推送，goal仍活动。
