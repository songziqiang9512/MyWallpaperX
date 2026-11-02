# 当前拓扑与活动组件生命周期后验

> **历史证据 — 非现役入口**

<!-- document-role: historical-evidence -->

> 固定 2026-11-02/03 批次。目标归[重构设计](../roadmap/engine-refactor-program.md)，当前状态归[运行证据](../capabilities/runtime-evidence-current.md)，未闭职责归[唯一队列](../roadmap/scene-open-breakpoint-queue.md#51-顶层设计已裁决的代码职责重构)。

<a id="sprite-timeline-retirement"></a>
## Sprite 与 Timeline 活动状态退休

Session 在原 Surface 执行阶段一次采样共享 Sprite 时间，前置 VM snapshot 与 commit 接纳 texture commands 的 nextFrame 顺序不变。提交销毁后，TextureAnimation/Timeline 原 runtime 消费本次新增销毁成员，整理活动 bindings、indices、owner 映射和 pending observations；保作者 Program/named catalog 的稳定索引、幸存播放 anchor、hidden 和跨 owner 控制。不在后续出生/排序时重放累计死集。

View 在 Surface 下一次采用 committed topology 时退休 Sprite 实例与输出；暂停重绘继续持有原冻结帧资源及 UV。原装配入口在构造前排除 committed 删除成员，共享 source/健康 peer 保留；MPS completion 持有在途 playback 和 destination reservation 至 GPU 完成，未提交仍走原 cancel/rollback。QuickJS TextureAnimation getter 和保留的方法句柄在原入口拒绝同 owner 已 staged destroy 的使用，保 destroy 前命令，不层层新增 runtime guard。

12 个产品文件增 205、删 24 行，净增 181，含已有 DEBUG runner 的真实重建探针及按需 snapshot；7 个测试文件增 508、删 38。无新产品文件、clock、cache、registry、状态镜像或退休 manager。运行时新增代码服务活动状态退出；DEBUG 观察不进入非观察普通帧，不以数量变化声明性能收益。

### 身份

| 身份 | 固定值 |
|---|---|
| 直接前置材质批 | `c61ad5701`，本批实现和冻结快照源自其 M1 前置，产品路径不重叠 |
| 本批产品 patch SHA-256 | `c7bf494f4efeffcdb993da7da71b91575963b29ae04b620cbcaa993f1c227d10` |
| 联合签名 App | `5e41db87ff8fb4a26bfdb4e52570fe9675caf2b82ee4c1dbf0c8c6140a96e5dd`；同时含 M2，arm64 Debug `-O`，Team `H9QWU9XN8R`，严格验签 |
| 本机 provenance | `.artifacts/scene-architecture-continuation-20261102/` 的 `topology-*`、版本化 source freeze、原失败及 `material-frame-topology-*` 构建身份；载荷可用性按产物保留规则 |

### 验证

| 责任 | 真实结果与范围 |
|---|---|
| 动画 runtime | texture-animation、Timeline、named Timeline、真实 QuickJS 与 layer identity 门分别通过。覆盖同源/异源、先命令再销毁、旧句柄 stale、discard、hidden、跨 owner、Combined 共享 state、camera origin/zoom 双 lane 及幸存 owner 精确 clock |
| MPS 与事务 | BC uploader 使用产品 SourceUpdateTransaction 的 arm/didSubmit/cancel，保实际 Metal 输出与取消恢复；不是用自写事务替身声明原生命周期 |
| 帧/提交 | source-update transaction 与 Surface submission 最近门通过，原 GPU submit/commit 语义保留 |
| 暂停冻结帧 | 实际双 Surface App：存活 owner 在 frame0 销毁可见 Sprite，所有 Surface 先准备该帧再 commit；暂停后两次 resize 重绘仍命中原 magenta ROI，cyan UV 反例不命中。单次 VM cadence、frame0 可见/hidden 和实际退休均有断言，最终 gpuDrained=true |
| 同 Session 重建 | 实际 Host.applyDisplayConfiguration 以原 display ID、仅自有窗口几何变化进入 Session rebuild。前后 request/session 不变；两屏 window IDs 全更换；Sprite ID 各只剩 `[6]`；暂停前后 sceneTime 精确相同、driver inactive，恢复后 driver active 且时间推进，cyan peer ROI 保留而 magenta victim 不复活，最终 GPU 排空 |
| 相邻画面 | 联合 App 的半透明 named/三候选局部失败及两份不变原包在 M2 记录各自通过；这些身份不拆成虚构的独立批次 App |

原生夹具验证 Sprite/MPS 与普通合成输出，不以 source-material 的原 reachability 告警声称该 shader 组合已经通过 resolved 材质。两 Surface 为显式 DEBUG 载体，不能外推物理多屏或系统显示配置变化。

### 首失败及资格纠正

- QuickJS 首门证明同 owner staged destroy 后旧 TextureAnimation 方法仍可访问，现沿已有 journal 拒绝；同样保 discard 后恢复及 destroy 前命令。
- Timeline 旧载体缺合法 orthogonal canvas，camera target 未构造；补真实作者输入，不改产品去接受无来源 target。另两个旧相机硬编码值不符合其实际 30fps/180帧 owner clock，改用独立真实 playback 的 stop/seek frame150/paused 与 survivor 测试，比较完整 origin/zoom，不复制曲线算法或放宽误差。Swift 复合表达式的 typecheck 超时仅拆为明确 Bool，原值不变。
- 冻结 Sprite 原用 Boolean owner 自毁，现有语义当帧强制 visibility=false，因此没有待保留画面；改存活 owner 销毁目标并核当帧真实可见，原 magenta/UV 门槛不变。常量 color 改为入口接受的向量字符串；原失败日志和输入均保留。

相机 current topology 的候选/顺序及 preVM 消费、其余组件和普通产品 daemon 完整链继续按现役设计，不由本批关闭。未认领全语料、长期运行、性能/能耗、官方 parity 或正式 Release。
