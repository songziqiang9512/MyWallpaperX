<!-- document-role: active-plan -->
<!-- retirementCondition: 唯一媒体仲裁落地并完成相应分发渠道验收，私有实验被公开能力替换或明确撤销后归档。 -->

# D6 — Web 系统 now-playing 数据源与单一媒体状态

> 复核基线：2026-10-01，独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；已合入 `codex/engine-refactor-program`；实施时按其最新代码重新核对所列 owner，以下行号仍指向原设计基线。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

媒体元数据与频谱采集是不同通路。系统存在有效 now-playing session 时优先系统；确实无 session 时回退页面媒体；页面作者收到一个自洽状态快照。跨系统 producer、Web bridge、页面状态且依赖私有平台接口，必须先定产品与发布边界。

五判据：横切多个 owner 或主链节点=是；触碰唯一权威合同=是；用户可见且难逆的 API/数据/发布合同=是；触碰机器冻结结构家族=否；依赖官方或平台外部证据=是。

## 当前事实与证据

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+MediaState.swift:195` 从页面 media node 派发完整媒体状态；`:124`、`:138`、`:154`、`:169`、`:183` 分别写 `__myWallpaperMediaState` 字段。
- 同目录 `DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift:421` 是频谱推送，不是系统曲目 provider。不能从已有频谱推断系统 now-playing 可用。
- 交接的官方音频静态结构只作为“频谱与媒体两路”的研究线索，不证明 macOS MediaRemote 能力或 entitlement。
- [Apple App Review 2.5.1](https://developer.apple.com/cn/app-store/review/guidelines/) 要求公共 API（2026-10-01 复核）；`MediaRemote.framework` / `MRMediaRemoteGetNowPlayingInfo` 没有本批核实的公共 SDK 合同。Developer ID 签名成功也不证明接口稳定或发布可接受。

## owner

系统会话 producer 放在现有宿主媒体输入边界，不能由每个 WKWebView 独立观察系统。RuntimeBridge 的单一 arbiter owns selected source、session epoch 与 event sequence；页面 `__myWallpaperMediaState` 只有一个 reducer writer。页面媒体观察器改为 candidate producer，不与系统回包竞写。

## 方案设计与选型

选择**先交付可测试的仲裁，私有 backend 仅限明确的实验配置**。保持纯页面媒体不能满足系统来源目标；静默把私有框架加入默认发行包会把未经验证的平台依赖固化。公开 MPNowPlayingInfoCenter 的自应用发布用途不能冒充任意应用的系统读取。

| producer 结果 | 仲裁动作 |
|---|---|
| 有效系统 session（包括 paused） | 选择系统；paused 不等于无 session |
| 明确 no-session | 同事务撤销旧 artwork/metadata，选页面 candidate |
| 系统 provider 不可用/权限拒绝/超时 | 发布 unavailable；按项目降级策略切页面并标记来源，不伪称系统无曲目 |
| 相同 epoch 的字段更新 | 组装一致 snapshot，顺序派发 status/properties/thumbnail/timeline/playback |
| 旧 session artwork 或迟到 callback | 丢弃，不混入新曲目 |

snapshot 至少含 source、provider generation、session identity、sequence、playback state、可选 title/artist/album、duration/position 及 artwork identity。缺字段明确置空，禁止沿用前曲。系统异步入口统一序列化；页面 candidate 只由主 frame 汇总，子 frame 消费通过 [D5](cross-origin-reply-delivery-design.md) 的定向投递。

系统 backend 使用运行时 capability 探测，缺符号、调用失败或 OS 变化可整路关闭，不能影响 Web 播放。观察注册按宿主需求引用计数，最后消费者退出即注销；artwork 有尺寸/字节预算和取消身份，远程 artwork 不绕过既有网络约束。timeline 在同一 monotonic clock 内外推，paused 停止推进，不能建立第二套播放时钟。

产品裁决：本设计批准仲裁及实验接口边界；**默认产品保持公开/页面 route**，Mac App Store 构建不得包含私有 backend。Developer ID 实验启用必须先完成目标 OS、sandbox/entitlement、hardened runtime 与签名/notarization 实测并由发布负责人明确接受该渠道风险；本批不猜 entitlement、不要求解除安全策略、不批准自动发布。若无法建立可靠权限与生命周期，删除私有候选，保留不可用结果。

## fallback / route

provider 故障仅降级媒体元数据到页面，不改变系统音频采集或壁纸暂停策略。切换来源原子清空不再适用字段，先撤旧 epoch 后发布新快照；错误不能让两个 writer 同时生效。迁移 route 从仅观察 candidate 到 arbiter 唯一发布，旧 JS direct writers 随后全部收敛到 reducer。

## 纠正门

- 可控 producer：系统播放→系统暂停→无 session→页面播放→系统恢复；精确验证 source、字段清空、事件序号，系统暂停不能意外回退页面。
- artwork 迟到、权限拒绝、OS capability 缺失、provider timeout、导航/退出；任何旧 epoch 写入必须拒绝，页面仍可播放。
- 真实系统会话至少用两个应用交替、退出与锁屏；记录 OS/构建/接口可用性。模拟 producer 通过不证明 MediaRemote 可部署。
- 分发门分别验证 App Store 不含私有依赖、实验构建签名/权限行为；未完成者保持 backend disabled，design approved 不覆盖发布决策。

## 退役条件

数据源仲裁稳定合同接管，渠道边界实证明确且私有候选有替换或退出结论后归档；不得把“实验可用”写成系统媒体全面支持。
