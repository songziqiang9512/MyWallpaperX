<!-- document-role: active-plan -->
<!-- retirementCondition: Scene/Web 共用唯一媒体采集与授权 owner，真实播放器和生命周期验收通过，稳定合同接管后归档。 -->

# D6 — Scene / Web 共享歌曲信息接入设计

> 2026-10-17 按现役代码复核。本页的共享采集、Scene IPC 与 Web 五监听接线已实施；实际运行与未覆盖范围见 Web 现役状态。修订原 D6，不增加平行计划；`approved` 仅表示职责与实施边界已明确。

## 目标与改造前断点

### 2026-10-20：M2按消费者生成Web封面

本次实施顺序归[Apple silicon统一路线](../development/apple-silicon-optimization-plan.md#m2p1按-web-消费需求生成歌曲封面)，本节只拥有实现合同。原SystemMediaService继续是唯一媒体源／授权／epoch与封面producer；Subscription增加缺省false的needsWebArtwork，并规范化为needsMedia且Web需求。仅Web的两处订阅传该能力，Scene订阅缺省与IPC原语义不变，不新增采集进程或缓存。

分别比较聚合媒体需求和Web派生需求：媒体0↔1沿原reloadSource；仅Web需求0↔1递增Web需求revision、清空或重建Web派生状态，禁止调用reloadSource、推进媒体epoch、stop/start源或清空Scene快照。派生准入与发布同时核对(media epoch, artwork generation, Web需求revision)及仍有Web需求；最后Web退出撤销旧任务，重订阅不能接收旧任务结果。无Web时不把generation记为已准备；首个Web晚到使用当前原图仅生成一次。坏图只缺Web派生，不影响Scene原图、调色板、标题或来源。

验收在真实Service/provider行为门计转换次数与source start/stop：Scene-only零Web转换、晚订阅／ABA／清空、转换在飞退出与重订阅、同代替换订阅、授权拒绝／恢复；Web需求变化不能重启源。再通过实际Scene/Web消费与Release无开发诊断检查。优化只声称省无消费者转换／通知；没有测功耗不声称能耗比例。若需要第二owner或改变原始媒体语义则停止，不保双路径fallback。

开启“壁纸歌曲信息”后，支持媒体监听接口的 Web 壁纸与 Scene 一样收到用户当前播放器的标题、歌手、封面、播放状态及可选进度。作者原有布局与样式不变。歌曲信息与 PCM/频谱是两条独立通路；不分析音频猜歌、不扫描用户音乐库、不修改作者文件、不新增授权按钮。

改造前 Scene 的 `SceneSystemMediaProvider` 汇合系统会话和 Music Apple Events 补充，提交 `SceneMediaThumbnailInbox`。它由 `SceneDesktopWallpaperSession` 按 prepared 需求 acquire/release，实际运行在 Scene daemon，singleton 仅在该进程唯一。Web 的 `DedicatedWebWallpaperHostPlaceholderAdapter` 与 WKWebView 在主 App；五个媒体监听入口已经存在，但 `+MediaState.swift` 从页面 `<audio>/<video>`、页面 `navigator.mediaSession` 与页面标题生成数据，尚未收到系统歌曲。`SceneMediaSourcePreference` 的产品开关也未投影到 Web，Web 的 enabled 仍缺省 true。频谱接通不能证明歌曲信息已接通。

## 选择与数据流

采用**复用现有采集实现，迁移到主 App 的单一共享服务，再向两个引擎分发**。拒绝在每个 WebView 另建观察器，也不直接在 Web 引用进程局部的 `SceneSystemMediaProvider.shared`：后者会让 App 与 daemon 各启动一份 helper、Music 轮询及授权。让 Web 依赖 Scene daemon 则把独立 Web 播放绑在另一个引擎的存活上。

```text
设置开关 + Scene/Web 活跃媒体需求
                 ↓
主 App：共享系统媒体服务（source 选择、授权、epoch、曲目身份、后台采集、封面缓存）
                 ↓ 统一不可变 snapshot
        ┌────────┴─────────┐
WebDaemonHostAdapter     SceneDaemonClient
        ↓                  ↓ 现有 transport，新增 typed media 命令
D5 frame 定向推送      SceneMediaThumbnailInbox
        ↓                  ↓
唯一 JS media reducer   原作者事件 / 纹理 / Metal 合成链
```

共享采集与 snapshot 类型归 `Core/Playback`，沿当前音频共享服务的主 App 装配边界接入；平台 source 与取色实现按职责迁出 `Systems/Media`，Scene Inbox、VM 事件和纹理仍归 Scene。服务不持有 WKWebView 或 Scene renderer。主 App 的权限交互保留现有设置入口；读取、解码、PNG 转换和取色在 utility 队列串行执行，一次至多一个 Music 请求，多屏复用一份结果。共享 snapshot 含 enabled、provider 状态、source/session identity、epoch/sequence、曲目 generation、可选属性/状态/进度、artwork identity/字节和颜色；通道变更标记避免每次进度更新重传封面。

原 Scene IPC 只有 `publishAudioSpectrum` 等命令，没有媒体元数据通道。实施须新增媒体需求事件与 typed snapshot/clear 命令，按 transport generation、request/session 需求身份接纳，冷启动/重启后重放最新快照；不拿频谱包夹带歌曲信息。Scene 保留现有受限原图字节与质量，不套用 Web 缩图。最大 16MiB 封面通过有 artwork generation 的有界分片（单片至多 256KiB）传输，一个在途曲目、一个最新待发快照，控制消息优先；完整校验后才提交 Inbox，换曲/clear/退出立即撤销旧分片及缓存。ACK 故障先 clear，daemon 12 秒本地租约防永久残留、主 App 4 秒续租；最多一次自动重建，耗尽后仍可关开恢复。同一曲目跨 Scene 需求仅复用身份完全一致的已完成原图。不提高现有 8MiB 控制队列预算，也不把整幅 base64 原图塞入控制队列。只在 artwork identity 改变或首次重放时发送图片，metadata 增量保留图片身份。接收方先验证来源/曲目/sequence，封面失败只清封面，不能阻塞控制消息。主 App 与 daemon 来自同一 App 包；不支持该新命令的旧 transport 如实报告元数据不可用，不启动第二采集 owner。

## 作者接口与投递

沿用[官方 Web Media Integration](https://docs.wallpaperengine.io/en/web/audio/media.html)的五类注册接口；这些接口需要壁纸作者主动消费，普通页面不会自动长出歌曲 UI。

| 监听入口 | 适配内容 |
| --- | --- |
| `wallpaperRegisterMediaStatusListener` | enabled 为设置开关的布尔值，与有没有歌曲分开 |
| `wallpaperRegisterMediaPropertiesListener` | title、artist、subTitle、albumTitle、albumArtist、genres、contentType；不支持的可选字段为空 |
| `wallpaperRegisterMediaThumbnailListener` | 可直接作为 img.src 的 PNG data URL（`data:image/png;base64,…`），加五个 CSS 颜色字符串；不暴露本地路径 |
| `wallpaperRegisterMediaPlaybackListener` | 显式映射 STOPPED/PLAYING/PAUSED，维持现有作者常量兼容，不靠真假值判断数字枚举 |
| `wallpaperRegisterMediaTimelineListener` | 已确认的 position/duration 秒数；来源不支持时保持缺失，不假造进度 |

官方正文称封面为 base64 PNG，示例直接赋给 img.src，因此采用完整 PNG data URL；不能误传裸 base64、file URL 或 JPEG。共享服务在后台另按 artwork identity 缓存 Web PNG（最长边至多 512px、编码至多 1MiB），不重复转码或降低 Scene 原图质量；颜色复用现有 `SceneMediaArtworkPalette`，Web 只转换 CSS 表示，不再重复用 canvas 抓系统封面。调色板具体数值不声称与官方一致。

Web 独立播放进程按 request UUID 接收主 App 的完整快照，不在子进程另建采集；宿主通过既有 D5 endpoint/token、定向 evaluateJavaScript 和 push sequence 投递，主 frame、同源及跨源子 frame 都按各自有效文档消费。监听注册上报独立 media 需求，不能借用频谱需求；只有 status 监听时仅订阅开关，无需启动歌曲采集；legacy `updateMedia*` 兼容回调也通过同一 reducer 分发。初始化、晚注册、导航后的 hello snapshot 都包含开关和最新媒体状态；endpoint 注销、导航、WebContent 退出与 teardown 同步撤需求。每 endpoint 只保留一个在途投递和最新待发 snapshot，合并时保留最新完整状态，不能丢掉清空或封面变更。最后一个 Scene/Web 需求退出即停止共享观察和轮询，开关关闭时仅保留轻量设置状态同步。

先一次替换 JS 中的完整会话，再差分派发各事件，保证回调读取其他字段时属于同一曲目。迟到图片、旧导航投递与 A→B→A 曲目回包按 epoch/曲目 generation 拒收。壁纸暂停不等于播放器暂停：页面冻结期间合并更新，恢复先重放最新 snapshot，不制造曲目时间。timeline 复用来源的更新节奏，不为每根柱、每个 frame 或每块屏幕另建计时器。

## 来源、授权与失败

沿用 [Scene 来源合同](../scene/roadmap/batch2/system-media-input-design.md)：有效系统 session（包括 paused）唯一决定选中来源；Music 公开只读接口仅补同一曲目允许的字段。只有观察资源 missingResource 才允许完整 Music fallback；noSession、临时未知、超时和权限拒绝分别处理，不用 Music 的旧曲填空。迁移不扩展既有 Developer ID / Mac App Store backend 渠道范围，发布与签名仍按[发布流程](../release/release-signing.md)；共享服务换到主 App 后必须重新核验真实授权归属。

本修订撤销旧 D6 的“无系统会话回退页面媒体”建议。官方歌曲监听通道以系统歌曲为准，没歌曲就清空，不能显示壁纸自己的背景音。页面 media 观察继续服务音量、播放门和节点诊断，与官方系统媒体状态分离；原 `__myWallpaperMediaState` 的页面 direct writers 必须退出，禁止后台页面事件覆盖系统 snapshot。关闭开关发布 enabled=false 并清空曲目/封面/进度、STOPPED；开启但无 session 发布 enabled=true 和同样空内容。封面缺失只影响封面，系统服务失败不影响壁纸、频谱或其他列表。

保持持久化 key `sceneMediaInfoEnabled` 及旧值迁移兼容，内部可更名为共享偏好。首次按需申请 Music 自动化授权；拒绝后不因刷新/多屏/换曲重复弹窗。用户重开开关复查，已允许则恢复，仍拒绝时保留当前系统设置引导。不开启 Music、不调用 MusicKit、不增加逐壁纸授权。主 App 一处负责提示，daemon 和 WebContent 不各自触发。

## 实施顺序、退出与验收

1. 先提取共享 snapshot、source/provider 与需求生命周期，并把 Scene 改为 IPC consumer；在同一迁移点撤掉 daemon 内 producer acquire/release。受控 Debug 的媒体注入继续留在原 Inbox，不暗启真实采集。Scene 真实歌曲、封面及无需求停止回归后再接 Web。
2. 新增 Web 宿主媒体需求/推送，补 hello replay 和唯一 JS reducer，撤页面对官方歌曲状态的直接写入；随后把设置说明改为 Scene/Web 均适用。开关默认值和已有授权交互保持。
3. 验收：Music 真实播放、换曲、暂停/恢复、退出；拒绝→系统允许→重开；缺封面/坏图/越界图、无 session/临时未知、迟到 ABA；断言字段清空、授权无重复、最后需求退出无轮询。曲目与封面缺口逐项记录，不以频谱跳动代替。
4. Web 用自有五监听探针及未参与实现的作者样本，覆盖 custom scheme / loopback、晚注册、多屏、同源/跨源 iframe、导航与 WebContent 重启；实际可见核对标题/封面/颜色/进度和开关清空。Scene 经真实 client→daemon→作者事件/封面合成回归，检查两端同时需求仍只有一个采集 helper。

普通帧只消费已发布快照；Debug build、协议/身份反例和真实 UI/渲染分别验收。失败时整体回退本次媒体入口迁移，不保留两套并行生产者；用户关闭功能即可停止采集，其他壁纸功能继续。该链已进入唯一主 App producer 路由，daemon 内旧 producer 已撤销；不宣称所有播放器或官方像素等价。
