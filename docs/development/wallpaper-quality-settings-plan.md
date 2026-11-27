<!-- document-role: active-plan -->
<!-- retirementCondition: 各质量项完成验收或明确退役，稳定语义归对应引擎合同，专项顺序与设计登记一并退役。 -->

# 三引擎壁纸质量设置执行评估

评估以 2026-11-25 主仓库 `codex/engine-refactor-program` 的源码为依据，三引擎初版基线为 `5946c3683`，Scene 六项算法选型复核至 `b2b80f892`。产品目标是 macOS 26+、Apple Silicon（M1 及更新硬件）。本文引用仓库已有运行结果，候选参数和发布条件在实施时按冻结输入验收。

[官方选项](#reference-and-current) · [偏好与预设](#product-and-state) · [Scene 算法](#scene-aa) · [Web](#web) · [Video](#video) · [实施顺序](#delivery) · [实测条件](#validation)

[现役工作卡](wallpaper-quality-work-card.md#execution)维护批次顺序及接手状态。Q2 首片由后处理的「超高（显示 HDR）」接管原独立 HDR 的物理输出。普通「超高」保作者发光，使用 SDR 输出范围。 [Wallpaper Engine 2.0.97 公告](https://steamcommunity.com/games/431960/announcements/detail/3133943554973045545)

<a id="decision"></a>
## 实施裁决

1. 在 AppKit 设置的「节能与暂停」附近新增「壁纸质量」区域。首批整合现有 Scene 30／60 FPS 与 HDR 显示入口，让 Web 可选采用该帧率建议，Video 明示按当前素材播放。用户原有偏好升级后保持同等行为。
2. Scene 以官方完整档位作为评估范围，沿现有帧节奏、Program、资源和 Metal 渲染入口分批交付。先验证全景 Bloom、实时反射、模型阴影和体积光的开关，再验证各质量档。动画帧率扩展到 10–120 FPS 的计划分两段，MSAA 保持默认 1×，2×／4×／8× 逐档验证。
3. Web 通过官方兼容桥交付 FPS 建议，作品自行控制绘制和媒体。Video 的节能入口选用真实较低规格文件，先评估来源已有档，再用离线 A/B 决定是否上线可选派生。预设只能组合已经有效、已验收的控件。
4. 首批完成条件为升级、导入恢复和复位正确，Scene 实际控制提交节奏，Web 在真实宿主中正确收发建议值，Video 的适用范围一目了然，三引擎候选、暂停、恢复和输出交接通过代表验证。后续每项都以独立可见结果和成本取证决定发布。

<a id="reference-and-current"></a>
## 官方选项与本项目范围

低／中／高／超高预设，10–120 FPS，MSAA 无／2×／4×／8×，后处理禁用／启用／超高，纹理自动／高质量／高性能，阴影与体积禁用至超高，反射开／关，来自用户提供的官版界面。渲染输出像素、纹理规格和 FPS 各有自己的消费者。项目实际请求、当前效果、回退与选项开放条件以[逐档执行合同](../architecture/wallpaper-quality-execution-contract.md#quality-option-semantics)为准。

官方资料明确了普通／HDR Bloom、三种投影灯、点／聚光体积、Web FPS 建议和视频素材质量。四套预设的实际属性值见下方客户端核验，渲染差别与生效时机仍由固定版本的单项 A/B 验收。 [性能 FAQ](https://help.wallpaperengine.io/en/performance/gpu.html) · [Web FPS Limiter](https://docs.wallpaperengine.io/en/web/performance/fps.html) · [Bloom](https://docs.wallpaperengine.io/en/scene/effects/bloom.html) · [高级光照](https://docs.wallpaperengine.io/en/scene/models/lighting.html) · [反射](https://docs.wallpaperengine.io/en/scene/lighting/introduction.html) · [纹理分辨率开发者答复](https://steamcommunity.com/app/431960/discussions/2/3035978213219373047/) · [mip 开发者答复及后续修复](https://steamcommunity.com/app/431960/discussions/1/4418677198500806035/)

重用本仓库的 Apple Silicon／macOS 26 路线，分别由 AppKit、Metal、WKWebView、AVFoundation 承担现役职责。主 App 管用户意图，运行端保各自时钟、资源与唯一输出。运行中的质量改变沿既有执行代次投递，画面接管沿原产品事务。 [技术栈合同](../architecture/technology-stack-boundaries.md) · [三引擎切换事务](../architecture/playback-lifecycle-transaction-design.md) · [Scene 默认质量与采样域](../scene/architecture/runtime-architecture.md#effective-quality-policy) · [Web 现役状态](../web/current-state.md)

<a id="product-and-state"></a>
## 控件、偏好与生效

### 入口与作用范围

- 复用 `SettingsWindowController`、`AppKitSettingsView` 和 `AppSettingsPanelDependency`。质量区域由动画帧率、Scene 质量、Web 建议和 Video 素材组成。Scene 后处理统一管理显示 HDR。作品的作者属性仍可从原属性面板操作。 [布局现址](../../MyWallpaperX/Shared/Settings/AppKitSettingsView+Layout.swift) · [设置动作注入](../../MyWallpaperX/Shared/Settings/AppSettingsPanelDependency.swift)
- 全局「动画帧率」现已支持 10–120 的 1 FPS 滑杆、键盘步进和直接输入。副标题说明 Scene 使用此调度上限，受当前屏幕组合限制时并列显示意愿与生效值。Web 可选「随显示器（最高 60）」或「跟随动画帧率」，缺省随显示器；跟随后，帧率、预设或 Web 模式变更将重算作品建议。Video 显示已知的片源分辨率与素材帧率，派生达到交付门后再显示素材选择。静态图、封面、系统屏保与锁屏遵循各自既有路径。
- 使用 AppKit 原生 segmented control、popup、switch，连续 FPS 用带数值反馈和键盘步进的 slider。Tab、VoiceOver 读出控件名和当前值，说明和失败状态用文字表达；窄窗、浅／深色及已支持语言的长文案实查。拖动时可预览数字，触发资源准备或 IPC 只在一次完成编辑时合并提交。 [本地化与布局标准](localization-contract.md#layout)
- 「恢复默认画质」沿一次差分更新复位帧率、Web 模式和已交付的画质字段。显示 HDR 随后处理档恢复为普通超高。直接调档需要冷准备时会自动重新应用当前 Scene。导入后仍有差分、或自动应用失败时，设置提供原手动动作。帧率受限时可看到确认的生效值，其他质量控件显示所选档及适用说明。未完善的档位留在开发验证面。Web 无作者回执时显示「作品支持时应用」。 [重新应用与验收](wallpaper-quality-work-card.md#quality-reapply-current-scene)

### 数据与生命周期

| 层 | 单一权威与接入规则 |
|---|---|
| 持久化与入口 | 由 `PlaybackQualityPreference` 唯一持久化用户请求，控制器、预设、复位和导入都由此投影。`PlaybackCommandMultiplexer` 一次保存、按实际字段差分下发。Scene 后处理的准备归并由 `ScenePostProcessingMode` 判定一次，冷档比较和同域热切共用。 |
| 首开与升级 | 新记录未建立时取 `mwx.playback.performanceProfile` 的合法 30／60 与原缓存映射，缺失或无效时用 60。已有新记录中新增字段按兼容默认初始化。旧键供一次迁移或旧版读取，日常只写新值。动画帧率与 decoded cache 上限已解耦，旧 30 档仅保留兼容额度位。 [画质偏好与旧键投影](../../MyWallpaperX/Core/PlaybackControl/PlaybackPerformanceProfile.swift) |
| 便携 v8 导入／导出 | 按明确声明的字段更新。新 FPS 合法时优先，只有缺省新 FPS 才读取合法 legacy 30／60。新字段存在但枚举未知或数值越界时保本机相应字段，类型或结构错误沿原写入前错误。旧档只含 30 时只改 FPS，保本机 Web 模式和其它档。导出向旧字段仅投影能表示的 30／60，直接退回旧二进制仍读取升级前旧键。 [v8 载荷](../../MyWallpaperX/Models/PersonalSettingsPayload.swift) |
| 导入时的活动播放 | 只有画质与视频库视图排序差分的 v8 计划允许维持原播放。Scene 帧率和同准备域显示 HDR 可热更，冷向量变更供下次准备，Web 原页消费有效建议，Video 继续原片及已捕获的播放顺序。视频库排序按原视图状态持久化，新播放选择才采纳其顺序。带来源、关系或其它设置变化的计划沿原停播屏障。登录项有实际偏好差分时才由原系统入口同步。 [画质导入](wallpaper-quality-work-card.md#quality-only-import-playback) · [视频库排序](wallpaper-quality-work-card.md#quality-import-video-sort) |
| 中断恢复与复位 | 旧 v3 恢复票据在 preferences 阶段前将实际声明的字段投影到相同 typed 比较，沿原 before／target 处理间隔编辑。已结算的 preferences 继续承认其收据，存储按启动迁移。画质复位和完整重置显式写默认向量，保原 reset epoch。旧恢复票据里相同的隐含 HDR 布尔值作为未编辑处理。验写前／写后中断、用户后续更改及旧键 30 同时存在的反例。 [导入恢复](../../MyWallpaperX/App/PersonalSettingsImportCoordinator.swift) · [完整重置](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Persistence.swift) |
| App 到执行端 | 通过现有动作和命令层下发各端实际消费的 typed 字段。Scene 沿单一父端和 daemon wire。Web 定向到现有 Web 入口，处理 Video／Web handler 别名和广播去重，更新 Web 会话与以后 launch 的 seed；Video 没有需要消费的 FPS 消息。wire 以现有版本和请求信封承载，启动状态含完整有效子集，变更发一次差分或小快照。 [App 装配](../../MyWallpaperX/App/MyWallpaperXApplication.swift) · [命令层](../../MyWallpaperX/Core/PlaybackControl/PlaybackCommandMultiplexer.swift) · [Scene IPC](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonProtocol.swift) |
| 执行端有效值 | 由当前内容、设备／显示能力、实际 consumer 与原帧／资源合同决定。字段只进入其消费点；静态资格于准备期确定，动态作者值仍由 typed snapshot 提供。请求、候选准备收据、实际消费和物理呈现是不同事实。状态、生效和失败交给[执行合同](../architecture/wallpaper-quality-execution-contract.md#quality-feedback)，采用进度见[工作卡](wallpaper-quality-work-card.md#execution)。 |
| 失败与回退 | 热更新只在当前会话和合法边界采用；已准备的下次应用项按最新偏好重新解析。需要更新资源／pipeline 的候选沿现有 request、generation、surface、提交和 pin，候选失败保旧画面，取消或更晚的意图淘汰旧结果。关闭/恢复档位沿原单一事务，无新 watchdog、每帧 IPC 或偏好认证。 |

Scene FPS 在下一排帧边界采纳，Web 在当前文档回调，能原位采用的可选 Metal 功能在提交前的帧边采纳。直接调档在已保存冷向量变化时进入原同源执行事务。新 Scene 会重新建立作者 VM 和动画时钟。有冷档差分时「重新应用」仍能显示待应用并用于显式重试。Scene 暂停时只用原路径必要的冻结帧更新，已提交的 Web 页面暂停时保存最新设置并在恢复回调交付。暂停、切换、轮换、系统休眠与恢复原先各有权威。 [待应用验收](wallpaper-quality-work-card.md#scene-cold-quality-receipt)

<a id="scene-cold-auto-adoption"></a>
### Scene 冷档自动采纳

固定官版的静态路径显示，普通桌面三项差分进入自动刷新分支，按已选配置恢复。这里保留现有候选接管能力作为执行入口，复用同源快照和原暂停意图，新会话沿重载规则重建作者 VM 和时钟。先核同一 daemon 提升候选时，旧窗变透明至新 drawable 实呈的差距。候选在透明时已有 GPU 产出，单凭顺序不能判桌面露底。用两次原作者的原生设置和独立窗口证据，记录旧／新窗口 PID、sample time 和实呈收据。验证真实捕获的片段覆盖交接，不以枚举窗口代替像素。有可复现露底再调整同一 Host 的冻结窗展示边界；透明画面须在新结果实呈时退出重叠。当前一个首呈回执属于整个请求，逐屏连续需要独立取证。 [Apple 显示采样 API](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)

M4 单内屏用同一签名产品的真实作品 3477054430 与 3746066933，沿原生重载及恢复各做两次接管。以提升日志前后 200 ms 为窗，主屏过滤合成的完整样本为 45／20 与 43／42，三处取样均无见证底色。退出 Scene 后两组均在全部取样区域读到洋红正控。三组最大完整样本间隔为 16.67 ms，347 的第二组跨提升留有 83.33 ms 间隔。374 两次匹配到旧／新窗口号，347 的外部窗列表无有效观测，身份沿原签名运行事件。结果支持当前继续原接管，不增加 Host 窗层或逐屏状态。它只覆盖三个采样区和实际取到的帧，物理逐刷新、真实桌面底图、短闪及外接屏仍待相应证据。 [窗口与采样收据](wallpaper-quality-work-card.md#quality-reapply-current-scene)

直接 AppKit 的单项、预设和画质复位在提交时比较 `.preparationQuality`，冷向量变化时更新在途普通选片的准备，或沿原 `.settingsReload` 重载已提交 Scene。FPS、Web 建议和同域显示 HDR 仍原位更新。导入、启动与恢复保各自执行合同。复用已提交引用、库快照与原取消／提交，不加普通帧工作、第二套 IPC 或候选 owner。若 B 实际在途而用户退回已确认的 A，沿原切换事务按票据静默撤 B。后续 C 只在当前选择还属于本次编辑时投同一候选；导入与 B 重叠时不得触发新的导入重载。显式「重新应用」也登记同一张冷准备票据。若 B 当时由显式按钮发起，之后的直接编辑 C 同样只让 C 接管。纯导入仍不发候选，所选冷档保持待应用。用原票据区分质量重载和其它来源，单一临时意图在最新直接编辑、退出、实际失败或换片时结算。失败保原输出和反馈，无新用户动作不自重试。排队而尚未送入 daemon 的撤销也由原 Scene 终态清除 Workshop 的加载标记。

同一原生控件验一项冷档、整档、重复选择、自动 B→C、显式重试 B→C、B→A、在途换片／停止和候选失败。显式用真实便携导入保 A，再点击原按钮，在首个准备回执让 C 介入。检查原窗口续存到实际新画面、采用当前偏好、可继续暂停和恢复、无需再次按旧按钮。纯画质导入保同执行、窗口和作者时钟。自动采用成功后隐藏原重试行。纯导入或失败保留一次显式重试。真实候选已到实呈后再发现旧意愿时，拒绝产品提交并由原事务恢复；更早的撤销才可核实原候选从未呈现。 [两作者与导入验收](wallpaper-quality-work-card.md#quality-reapply-current-scene) · [官版可比边界](#official-live-quality-refresh)

<a id="scene-cold-ordinary-preparation"></a>
#### 普通选片在准备期间的直接调档

从库选择 Scene 已向 daemon 发送准备请求时，原请求已冻结冷画质。此时直接改档会保存新值，普通选片占用的切换事务会挡住现有的同源重载。先在原生控件动作和第一个候选准备回执之间复现实呈旧档。如果成立，在该选片仍处于准备、尚未登记候选端点时，由编辑动作通知原选片准备入口。沿现有 Scene launch 保留产品票据、来源版本、资源租约、库顺序和截止时刻，用新 wire request 重准备同一素材。旧 request 沿原撤销回路退场。普通加载提示继续归同一选片，迟到事件沿原 request 和 transport 归属过滤。尚未送出的请求会读取新偏好。已经登记端点的切换继续由原事务结算。已提交 Scene 的同源调档沿当前入口。无需新增状态、候选 owner 或普通帧检查。

沿签名隔离产品从真实 Video 选择 Scene，在首个准备回执处操作 AppKit 的一个有实际画面差异的冷档。基线需证现役的旧向量实呈、最终接管且提示待应用。候选需同一产品票据和库顺序、两份不同 wire request，旧结果没有呈现或过期接管，旧 Video 在准备时仍有对应可见窗口，最终 Scene 用新档实际实呈、画面符合作者控制，待应用提示消失。以相邻的 FPS 热改和便携冷字段导入核不重准备。再跑独立 Workshop 作者，同源重载和普通轮换既有门提供相邻回归。若基线未出现旧档接管，或需在普通帧判断保存偏好，则结束该实现候选。 [选片状态机](../../MyWallpaperX/Core/PlaybackControl/PlaybackSwitchTransaction.swift) · [原 Scene 候选端点](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonClient%2BSwitchEndpoint.swift)

签名基线的自有白块 Scene 和 Workshop 3477054430 都在准备回执处保存禁用，但唯一实呈和完成接管的请求仍准备启用档，设置显示待应用。候选的两组请求共用一次选片票据，库快照和 Workshop 加载标记保留，两次准备时原 Video 仍有可见窗口。旧请求无实呈，只有采用禁用档的新请求实呈并完成，待应用提示随即消失。自有白块的左右固定区域在 1512×982 的同执行 Surface JPEG 中平均由 21.11／24.56 降为 0／0。白块中心与远黑为 255／0，独立暗色参考 RGB 34／50／75 均一致。Workshop 原作者的有界接管已确认，动画相位和显示器逐刷新未以该取样结算。

同一签名候选用独立 3746066933 在准备回执处直接改帧率，只准备一次，并由原请求以 25 生效。3477054430 通过真实便携入口在准备回执前写入高性能纹理，原请求保高质量纹理，仅一次准备和实呈，设置保待应用。收据归 `.artifacts/wallpaper-quality-scene-selection-edit`。 [签名产品门](../../script/web/playback_quality_coexistence.py)

### 四档预设对照

[逐档执行合同](../architecture/wallpaper-quality-execution-contract.md#quality-option-semantics)定义实际预设向量与自定。兼容默认保持原 60 FPS、1×、普通超高、高质量纹理、自适应阴影、高体积和实时反射，升级仍保已有的 30／60 FPS。Web 初始给显示器建议，Video 按所选原片。对照来源见[官版向量](#official-quality-evidence)。

<a id="scene"></a>
## Scene 逐项技术裁决

### 帧率上限

- **首批方案**保留 30／60 的可见语义，共享同一 daemon host 配置，包含候选、重建和恢复。复用 `SceneDesktopWallpaperSession+FrameDriver` 的单次 Timer、GPU admission／忙帧重试与 `SceneClock` host time；切档更新调度上限和既有对应 decoded cache 额度，仍用真实经过的场景时间。单独核对 Timeline、VM callback、粒子、媒体、作者日期、暂停首帧和恢复时间。多 Surface 仍由同一 session clock 供时。 [现有帧驱动](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift) · [Scene 时钟](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneFrameContext.swift)
- <a id="scene-particle-rate-transition"></a>**10–60 FPS**先解耦帧率与解码缓存，再从设置入口规范化整数值。按单调目标期限跳过错过的周期，忙帧沿原 admission，热切重定下一期限。验 10／11／24／25／30／59／60 和越界值。10 FPS 核粒子、动画事件、媒体、触控响应和基于帧计数的脚本。热切期间，Scene 粒子上限沿当前周期及上个真实仿真刻之后已换出的在途有效周期取最长，再加一步。单次随原 SceneClock 样本消费，后续恢复当前档；多次换档也只留一个最长周期。验证 10→60、往返、GPU defer、掉呈现和暂停恢复。作者原始时钟及按帧发射意图沿原合同。25 FPS 在固定 60 Hz 屏上按稳态上限和呈现间隔分布验证，忙后保持无连续补帧，明确区分提交与物理呈现。 [官版每秒发射与单帧上限](https://docs.wallpaperengine.io/en/scene/particles/component/emitter.html) · [粒子热切实测](../scene/capabilities/runtime-evidence-current.md#particle-fps-retune)
- **61–120 FPS**在高刷屏和真实输入的 GPU、作用线程及耗电结果通过后开放，验 61／90／119／120、退出高刷与热插。现有 Session 由单一时钟驱动多 Surface，先以单高刷屏或同刷新率组合取证。混合刷新率先沿已验证共同上限运行；只有省掉低刷屏额外提交的价值成立，才在既有驱动中按 Surface 准备有效调度，继续共用 SceneClock。用户选择可随屏幕限制临时降效，屏幕更换重新取有效值。
- **技术比较**优先现有 Timer。若实测发现跨刷新率抖动、额外唤醒或提交错位，再在同一驱动职责内比较 `CADisplayLink`／`CAMetalDisplayLink`。系统帧率范围是调度提示，验收以尝试／提交／GPU 完成／presented 及长窗节奏为准。 [Apple 帧节奏建议](https://developer.apple.com/documentation/metal/improving-your-games-graphics-performance-and-settings) · [CAMetalDisplayLink 帧率提示](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/preferredframeraterange)

<a id="scene-script-interval-phase"></a>
#### SceneScript 重复定时器的到期帧

`update()` 次数随实际计算帧调整，按累计 `engine.frametime` 或 `engine.runtime` 驱动的动画沿作者时间。MyWallpaperX 的重复定时器在首个合格帧派发，到期时从派发帧重新开始下一周期。零延迟和跨多周期都每个有效 tick 至多一次，同时间、暂停、取消、事务和单次回调沿原 owner。对低帧率作者作品，这会量化基于重复定时器的节奏。先按固定版本实际行为验证，再决定是否改变此口径。 [官方 SceneScript 更新](https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/update.html) · [官方重复回调 API](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html#setinterval-callback-function-delay-number-function)

固定版官版与本机在 25 FPS 的可见计数一致，保现役到期帧策略。QuickJS 原生门继续覆盖不同间隔、同 owner 模拟换档、重复时间、零延迟与超长一步。粒子、Timeline、内嵌媒体和官版普通桌面的热改仍各自验收。 [两端画面与独立作者证据](../scene/capabilities/runtime-evidence-current.md#script-interval-frame-cadence)

<a id="scene-fixed-refresh-proof"></a>
#### 固定刷新屏的实际呈现分布

原 Debug 产品基准已采集每屏 `CAMetalDrawable.presentedTime` 并按稳定 Surface 汇总 P50／P95／P99。相同百分位可能来自不同的 2／3 周期比，不能据此判断 25 FPS 是否在固定 60 Hz 上按预期量化。窗口结束时在原遥测快照读取同一批有效间隔，按测量窗稳定的 CoreGraphics 模式率换算周期。保 1–24 周期的计数，偏离最近整数超过 0.20 周期或超范围的记在 0；未知模式省略分布。索引是周期数，每屏独立。原数组、计时器、时钟和普通帧开销保持，Release 无此诊断。不以模式名或这些计数单独裁决面板固定性。

先确认另一工作树无在途真机性能采集。只在原显示的点尺寸、背板像素和几何相同的情况下，在隔离进程暂用 CoreGraphics 会自动回退的模式配置。用独立外部读回核 60／59.94 Hz 当前模式及实际显示时序，结束恢复原模式。同一签名 App 在固定 60 Hz 上跑自有移动态和独立真实作者的 25 FPS 实际窗口；窗内调度约 25，约 60% 间隔跨 2 个周期、40% 跨 3 个周期。首轮实测预期至少 95% 在两桶内，2 周期占比为 55%–65%，实际呈现 ≥24.5 FPS 且 GPU 零失败；偏离要保留实际分布及 A/A，检查提交和显示依赖。另以两个模式下的 120 请求验实效应分别为 60 和实际小数模式值。有实际过载时以轻夹具判模式限幅，复杂作品的呈现另记。混合屏和面板光度独立验收。 [CoreGraphics 临时模式](https://developer.apple.com/documentation/coregraphics/cgconfigureoption/forapponly)

M4 内屏 1512×982 点、3024×1964 背板，同一团队签名 Debug 在原库选择路径接管。外部 CoreGraphics 和 AppKit 确认模式 55／56 的最短、最长刷新间隔一致。独立 display link 的中位周期为 16.66662／16.68329 ms。按相同几何临时切档，场景完成后独立进程读回原模式 54（120 Hz）。六窗的每屏桶计数均等于实呈帧数减一，GPU 失败、计时器和准入失期均为零，原请求正常排空。

| 固定模式与请求 | 实际呈现 | 实际间隔 |
|---|---:|---|
| 60 Hz，自有动态场，25 FPS，两次约 61 秒 | 24.984／24.984 FPS | 每窗 912 段 2 周期、610 段 3 周期、1 段 1 周期。P50／P95／P99 约 33.33／50.00／50.00 ms |
| 60 Hz，独立 Workshop 3455121165，25 FPS，60 秒 | 24.966 FPS | 898 段 2 周期、599 段 3 周期，无其它区间 |
| 60 Hz／59.94 Hz，自有动态场，120 FPS，各约 12 秒 | 59.833／59.665 FPS | 生效 60／59.939987，717／715 段全为 1 周期 |
| 59.94 Hz，自有动态场，25 FPS，13 秒 | 24.923 FPS | 195 段 2 周期、128 段 3 周期，无其它区间 |

保持现役 Timer。三个长窗均满足预定的 25 FPS 门，单个 1 周期间隔的发生位置和原因未定。真实作者副本沿原包及着色器运行，首次把缺索引的下载标记散拷进测试库被正常拒绝，正式取证只在隔离副本内移出该标记，作者 project 与 pkg 摘要保持。基准验证本机单内屏及系统实际 drawable 呈现，不含同一个运行会话的物理切屏、混合屏、面板光学、真实启动分段或整机功耗。收据归 `.artifacts/wallpaper-quality-scene-fixed-refresh`。 [Apple 实际呈现时刻](https://developer.apple.com/documentation/metal/mtldrawable/presentedtime)

<a id="scene-live-refresh-proof"></a>
#### 原播放会话跟随物理刷新率变化

固定模式的稳态窗遇显示或有效 FPS 变化时主动结束。热切另外沿原产品的库选择、已完成交接与现有 Debug 帧捕获取证。父进程只保存 120 FPS 请求，从既有 cadence 回执等待 120→60→实际 59.94→120。独立进程临时更改同屏、同几何和背板的模式，在每次切换后核 CoreGraphics 与实际显示时序。Scene 父端仍由 AppKit 屏幕通知走原拓扑 IPC，不注入模拟拓扑、不重选壁纸。

每档前后两次捕获核 parent ticket、execution、Scene request、generation、daemon PID、session 和 WindowServer 窗 ID 不变，帧驱动仍活动。作者时钟随主机单调时钟前进，验每段及相邻两档，无重置、冻结或补时跃升；稳态每 0.4–2 秒的时间差与主机差容差 0.12 秒，跨档允许 0.25 秒。独立外部固定窗两帧应有内容变化，并核显示与窗口归属。固定 120 请求下照实回显有效小数，假通知、重复选片或仅看冷启动不计通过。自有移动场先过主门，再用同签名独立作者作品。结束需原模式回读、原机偏好与精确子进程退出。诊断仅用于这一验证，若产品通过则退出追加的临时观测入口。物理多屏仍独立验收。 [CoreGraphics 临时模式](https://developer.apple.com/documentation/coregraphics/cgconfigureoption/forapponly)

M4 同内屏 3024×1964 在同一签名诊断 Debug 的原库入口分别播放自有移动场和独立 Workshop 3455121165。两次都保持自身的 ticket、execution、request、transport generation、daemon、session 和 WindowServer 窗。每次只保一个已接管的请求，保存 120，实际回显为 120→60→59.939987→120。独立 CoreGraphics 模式 54→55→56→54 与回执相符，两个固定档的独立显示时钟间隔为约 16.667／16.683 ms。同屏尺寸与背板保持，结束均以独立进程读回原 120 模式。

每档在同一 WindowServer 窗取两张实际画面。缩到 320×208、任一 RGB 通道差超过 3 的像素比例，自有场为 2.75%–2.79%，独立作者为 1.28%–1.48%。两作品的八段档内及六段跨档取样中，作者时钟增量与单调主机时间增量最大偏差小于 0.012 ms。前后两帧均为活动帧驱动，实际画面仍在变化。样本在隔离副本取证，作者 project 和 pkg 摘要与固定刷新门相同。独立作者图层 115 的 named target 绑定在首档前先报失败、随后成功。画面样本用于取证持续出画和时钟，单层效果正确性另验。正常退出、子进程结清和生产偏好摘要复核通过。阶段采样未量切换瞬间的系统黑场、逐帧间隔或跨物理屏事件。退出临时诊断改动，现役保持原通知、拓扑和 Timer 实现。收据归 `.artifacts/wallpaper-quality-scene-live-refresh`。

<a id="scene-aa"></a>
### 抗锯齿

**选型为默认 1×，合格的 3D 主几何域优先试 Metal 原生 MSAA ×2。** 做过迟 resolve 的样本 358 在 3024×1964 下，GPU 帧时 P50 由 15.180 增至 18.463 ms，池峰约 743 至 855 MiB。环边阶梯减轻，碎石暗点仍在。独立样本 347 的 GPU P50 由 12.178 增至 13.316 ms，画面收益不足以抵消成本。两组短窗导致通用默认 2× 撤回，已有 4× 局部覆盖参考。重启 2× 必须利用能降低旧成本的实际几何域，再证整景动态收益。 [已有 GPU／像素对照与停止线](../scene/capabilities/model-runtime-evidence.md#model-raster-coverage)

| 算法 | 对本项目的取舍 |
|---|---|
| **Metal MSAA** | 在光栅化时处理几何覆盖、遮挡与混合，保原生输出尺寸。Apple GPU 在合格连续段可用片上 `memoryless` 附件并 resolve 到单采样原输出。跨 pass 须保留样本时，额外色深存储和读写是主要成本。 [Apple MSAA 示例](https://developer.apple.com/documentation/metal/improving-edge-rendering-quality-with-multisample-antialiasing-msaa) · [附件 load／store 合同](https://developer.apple.com/documentation/metal/setting-load-and-store-actions/) |
| FXAA／SMAA 1× | FXAA 在单采样终图单遍滤波，SMAA 1× 用边缘检测、权重搜索和混合改善斜线。适合作只能取得终图时的独立候选，须同时比较文字／线稿锐度、HDR 和全屏读写。已合成的颜色不足以重建原逐样本遮挡。 [FXAA 白皮书](https://developer.download.nvidia.com/assets/gamedev/files/sdk/11/FXAA_WhitePaper.pdf) · [SMAA 论文](https://www.iryoku.com/smaa/downloads/SMAA-Enhanced-Subpixel-Morphological-Antialiasing.pdf) |
| TAA／MetalFX Temporal | 可针对运动亚像素闪烁。接线需可信的运动向量、深度、抖动、历史重置和透明效果的有效输入。当前 Scene 缺可覆盖作者材质、骨骼、粒子和具名图的共同运动输入。仅在真实输入能闭合的 3D 场景重开。 [Apple MetalFX 时域接线](https://developer.apple.com/videos/play/wwdc2022/10103/) · [透明效果与拖影](https://developer.apple.com/videos/play/wwdc2025/211/?time=406) |
| 超采样／纹理过滤 | 两轴 2× 超采样会产生 4 倍渲染像素，适合离线边缘参考。缩小纹理产生的摩尔纹由其 mip 与过滤处理，保作者的 nearest／图集合同。 [Apple mip 采样](https://developer.apple.com/documentation/metal/improving-texture-sampling-quality-and-performance-with-mipmaps) |

**设备级别**。Apple 当前能力表中，M1／M2／M3–M4 对应 Apple7／8／9，原生 render pass 的 MSAA 上限为 4×。8× 列在 Apple10（含 M5）和 Apple11。Apple7 已列出 `rgba16Float` 过滤、混合及 MSAA／resolve，`depth32Float` 的过滤资格单独看设备。档位仍由实际 device sample count、格式／PSO 和预算决定。当前请求为无、2× 和 4×。8× 要在实际支持的设备和格式取得正向画面及预算证据。跨设备导入保有已交付的意图。 [Apple GPU 映射、采样上限与像素格式表](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)

**实现和生效**由原 `SceneMainPassEncoder` 准备实际颜色和相机深度的共同采样域。设备、附件格式、PSO 和当前资源预算在准备期接纳 2×／4×／8×。共用附件的模型、文字、图像与粒子使用匹配的 pipeline（含 alpha-to-coverage 和深度状态）。连续段用 `.multisampleResolve`，中间读色后续画须保逐样本色深和原顺序。非线性 attachment-read、无法匹配 PSO 或紧预算时该域采用原 1×，界面保请求并显示有效值。独立阴影、VolumeOccluder、compute、真实具名离屏仍按自身附件合同。 <a id="scene-aa-depth-independent-tail"></a>**带独立末段的原生 MSAA。** 保存的 2× 与成功呈现的 1× 已可同时出现，旧整帧否决使任何材质计划都无法共享内存中的主域 MSAA。先支持从清屏开始、包含真实模型的连续根域。若剩余的活跃程式是顺序确定、直接读已解析单采样主色且不触及主相机深度的末尾全屏效果，在它真实 utility 触发点 resolve 一次，原 1× encoder 继续加载同一主色，不启第二渲染 owner、不把解析图重灌为 MSAA。已结束的主几何采样数交回原成功呈现读口，活跃 PSO 继续取当前 encoder 样本数。后续颜色测试、具名写者、活动深度读写及历史留原资格。验收先在 BGRA8／RGBA16Float 比对深度相交的斜边与末段独立探针，再用 3477054430 仅关闭共享深度的月亮、保作者像素化，证明几何 1×→2×／4× 的图像差、原效果真实读取同一已解析纹理和原 Bloom。完整缺省的月亮深度及 3617056047 原音条中段读色走回退；另外挑一份独立作者核泛化，检查实际呈现、超出原预算及失败回退。 这一步只验证切换原语。面向日常改档的目标是让已准备的绘制依其实际色深读写决定采样域。独立离屏作业与其它功能的存在本身不决定主域降档。无需跨切点保有逐样本附件时用片上根域；后续真的消费先前深度或样本时比较保留逐样本色深的私有附件，以及单独发布给单采样素材的可读 resolve。以实际材质 Program 的读写和编码边界确定图，不再增加作品、效果名或整帧特征组合名单。几何、先行音条和默认共用深度的真实作者须进入常规场景验收。原型经 M4 签名 3477054430 验证，保像素化时几何实绘前缀 2×／4×，一次 resolve 后作者像素化实际读取同一主色，1× 沿同附件继续。排除两次原 1× 的作者动态矩形后，两次 4× 都稳定改变 17,656 个终图像素至少两码。原默认月亮和独立 3617056047 原音条请求 4× 各仍 1×。另用 Metal 的跨段试验在 SDR／HDR 先保真实逐样本色深，再让已解析颜色成为实际材质输入，最后恢复遮挡。无可见独立扰动的分段和连续逐字节相同；故意清深度反例改变 1,515／1,550 像素。实测 3024×1964 下私有色深物理分配，SDR 2×／4× 为 94／186 MiB，HDR 为 140／277 MiB。一次拆段下 GPU 中位增加约 0.56–1.35 ms。按真实读写选择片上段与跨段私有存储，避免所有帧常驻私有色深。签名和成本收据归 `.artifacts/wallpaper-quality-aa-effective-20261127`。 <a id="scene-aa-color-prefix"></a>**从单采样颜色前缀开始的原生段。** 按最终层序的真实模型、具名准备切点及 utility 实际触发次序选择主颜色切换点。交界前的 Program 用原 1× 捕获和回写，交界后连续的模型和可匹配 Quad 共用原生色深，原相机深度已经被使用、后段仍需读主附件或换编码器的交界沿原 1×。使用现有 composition 池持有一张与主目标完全同规格的颜色副本，在首个真实模型前由原主编码器结束 1×、复制当前完成色、以禁用混合和深度写入的全屏逐像素 read 初始化 memoryless 色图，同时清反向深度为 0；最终一次 resolve 到原目标。副本必须独立于 resolve 目的地；仅在原生段开启前准备失败才沿原主目标 load 续画，已编码副本保至同一命令缓冲结算。已开始原生绘制的提交失败沿旧 GPU 终态。可从清屏开始时继续原直通路径，采样读数取真实开启的主域。产品顺序先接默认保留音条的 3617056047 的通用先读色后模型，再接不依赖主深度的 1× 尾段。<a id="scene-aa-paired-depth-terminal"></a>**材质图与带深度的最终图层。** 对实际图输入仅来自已准备作者贴图的局部材质图，复用当前 PreparedGraph、票据、完整依赖与输出格式。按原事务顺序提前编码，要求同一命令缓冲中先驱已消费、后继仍处容量已提交状态，且图操作与回放不读主附件。图就绪只发布输出，原层序从同一票据消费一次，1× 回退也复用已完成图。原层序时由原终端消费图输出，使用匹配样本数的 source-over 与作者原有深度读写，保现有 .greaterEqual 及透明像素不写深度。尾段所有实际消费者都与相机深度和逐样本值独立时，在首次尾段读色的位置 resolve 一次，继续读同一根色。默认 3477054430 的月亮 44 从独立 512² 作者纹理进入图，色图生成可与根相机深度分开，其材料声明深度测试和写入，现役 translucent 准备保测试并按作者相容规则归为只读。终端须与模型共享逐样本深度，原生段维持实际准备后的读写状态。随后 83 的像素化读非局部根颜色且终端无相机深度。验收先用独立近远叠层及透明洞的深度负例，再保 44 和 83 同时开启，核实际图源、深度写入和不同样本数的窗口。保留局部图原有分辨率与终端重采样，终端按作者声明读写深度。存在不能提前且确实需要关闭主 encoder 的操作，后续绘制还消费前段逐样本颜色或深度时，才按实际读取评估原池私有色深保留、按需 resolve 及回放费用。原生小图用独立奇尺寸、负值/超白 HDR、透明 alpha、深度反例和 2×／4× 斜边证明，签名验收再要求真实音条捕获、模型与后续文字同一提交和终图，补分配失败及独立作者，按原 60 FPS 实呈预算与资源池驻留判发布。 [Apple Metal resolve](https://developer.apple.com/documentation/metal/mtlstoreaction/multisampleresolve) · [画质执行卡的 M4 对照](wallpaper-quality-work-card.md#scene-aa-four)。高采样数独立验证每档收益，低档不可用时按 1× 回退。 [采样域合同](../scene/architecture/runtime-architecture.md#raster-sample-domain) · [粒子 PSO](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleMetalPipeline.swift) · [设备采样数查询](https://developer.apple.com/documentation/metal/mtldevice/supportstexturesamplecount%28_%3A%29)

**实测验收**固定原生像素、相机、场景相位和 LOD，用独立高采样参考量斜边 alpha 覆盖误差和连续帧边缘跳变。近远半像素遮挡换序、前缀读取后续画、透明模型和粒子、`clear=false`、具名历史、SDR／HDR 与小预算回退必须能区分错解。纯二维有效图元边作独立正例，满屏贴图内部边、文字贴图和不完整根域作负控。分别量 resolve 次数、帧时 P95、submit／present、私有附件及在途峰值。候选须在合格作者正例和独立动态作品有可重复的改善，并在承诺设备／帧率守住[质效门](#quality-release-gates)，否则保 1×。

<a id="scene-aa-ordinary-quad"></a>**纯二维根域。** 退出冷准备必须有模型才能准备普通 Quad PSO 的限制。模型域仍以原实际模型准备确定采样。无模型域从原普通 PSO 决定能否共用同一套片上附件，复用原清屏段和最终一次 resolve。根段只接已准备且无深度依赖的普通 source-over 命令，按现有 utility 实际执行判定避开需要中途离屏的路线。二维加独立尾部的试验能在实际 utility 捕获前 resolve，但已验作者的配对终图相同，短窗 GPU 成本增加，暂退出根域候选。图片或纯色至少有一个当前有源且实际投影到目标像素的几何边。用原图元变换和已有 viewport 裁剪确认，满屏铺图、纯纹理内部边、不可见或整齐对齐像素格的边沿原 1×。选中图元的这次变换交原绘制复用；不添加第二份几何目录、位图滤波、逐帧资源遍历或后备复制。若设备/管线/配对失败沿现役局部 1× 与实际档回显。清屏之外、作者读回、程序效果、粒子或分组走现有约束。实测冻结原作品实际时钟、屏幕与背景相位，拿原生 1×／2×／4× 与解析覆盖参考比较斜边误差和亚像素相位，核同帧附件、纯色／透明混合、唯一 resolve 和匹配终图。独立作者重复，另测满屏贴图、图内 alpha 和无合格图元的资源成本。只扩展已能用实际覆盖证明画面收益的普通根域，持续呈现与更广硬件覆盖沿现役工作卡验收。

<a id="scene-post-processing"></a>
### 后处理与 HDR

**选型为现有低尺寸可分离 Bloom 和保留当前 HDR 工作域的浮点金字塔。** 场景后处理首先负责全景泛光及显示 HDR。作者启用 HDR Bloom 后，官方最终播放中的用户档需用「超高」，并可让作者另配普通 Bloom 供「启用」档使用。属性面板只控制作品公开的相应作者参数。自定义局部 effect 沿其图执行。Windows 编辑器预览与 macOS 每屏 HDR 显示各有自身状态。 [官方 Bloom 合同](https://docs.wallpaperengine.io/en/scene/effects/bloom.html)

| 算法 | 对本项目的取舍 |
|---|---|
| **现有 MSL 分离模糊与 HDR 金字塔** | 普通路线在宽高 1/4 提取，1/8 做纵向、返回 1/4 做横向，按源物理像素计步距，最后用 RGB 加法写回。HDR 用 `rgba16Float` 保超白值，首级按面积聚合先逐像素取软阈值的贡献，再做 tent 降采样与加权重建。HDR raw／history 及作者混合沿当前 display-referred 工作域，EDR 终端才解码到线性输出。combine 无需新全尺寸结果。 [Bloom 实现](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneBloomPostProcess.swift) · [终端颜色转换](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneDisplayMappingPostProcess.metal) · [阈值与奇数边合同](../scene/capabilities/render-graph-shader-coverage.md#hdr-bloom-extraction) |
| 全尺寸 Gaussian／MPS | 可在离线或同尺寸探针中做参考。sigma、边界权重、色彩、alpha 和源步距决定实际光晕，高分辨率中间读写仍有成本。保持现有分离路径，只有相同光晕和作者结果的候选在 Apple GPU 实测有明确收益时才替换局部滤波。 [MPS Gaussian API](https://developer.apple.com/documentation/metalperformanceshaders/mpsimagegaussianblur/init%28device%3Asigma%3A%29) |
| Dual Kawase／减少金字塔级数 | 更少采样或在小纹理处理宽晕是候选。核形、跨级权重和亚像素能量会改变光晕。优先保作者级数，缩档须守阈值、强度和局部对照。已有有界官方宽块结果支持沿当前核，薄线的官方精确能量和通用性能仍待取证。 [Dual Filtering 方法](https://community.arm.com/cfs-file/__key/communityserver-blogs-components-weblogfiles/00-00-00-20-66/siggraph2015_2D00_mmg_2D00_marius_2D00_notes.pdf) · [项目 HDR 证据](../scene/capabilities/runtime-evidence-current.md#hdr-bloom-extraction) |

**档位和生效**「禁用」沿原终端让预约和编码使用同一有效配置，跳过全景泛光，保原颜色、alpha、局部效果与 raw history。作者 General 开关仍供作者逻辑。普通与禁用档须在原准备入口确定有效 HDR 工作域和亮度，终端再分别走普通泛光或跳过。当前 HDR 初始化选择 HDR PSO，普通档使用原普通准备入口。「超高」采用作者 HDR 金字塔，普通作品仍可用基础路径。作者禁用、零贡献或可选分配失败沿原局部结果。两个超高档共用作者工作域，只有「超高（显示 HDR）」向可用屏申请 EDR。 [作者场景和粒子](../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneDocument.swift) · [合成与终端](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+ClearColor.swift) · [Apple EDR 映射](https://developer.apple.com/documentation/metal/performing-your-own-tone-mapping)

只在有支持显示器时开放显示 HDR 的新选择。无支持屏时，设置将已保存的显示 HDR 请求标记为暂不可用，实际窗口沿 SDR 输出。用户仍能明确选择普通超高，原屏幕通知会在能力恢复后更新菜单。 [设置回显验收](wallpaper-quality-work-card.md#scene-hdr-saved-selection)

普通参数缺省在 General 已补为 1／0.65／白色。先用固定官版对照仅配置 HDR、显式普通参数等于默认、以及有动态普通绑定的场景。「启用」如适用普通缺省就直接用现有值。如果仅显式配置时才生效，在现有 General 解码保留消费所需的最少声明或绑定信息，沿当前 descriptor 投影。该语义通过黑盒与原 App 夹具后再开放「启用／禁用」。 [General 解码](../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneDocument+General.swift) · [摄像机配置](../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRenderDescriptor.swift)

禁用／启用改变工作域或 Bloom 资格，在下次应用的原候选准备时采用。禁用的候选没有 Bloom owner，其旧工作集随已呈现候选接管、旧会话排空和原 Surface 退役释放。两个超高档只热更显示 EDR，复用同一 Bloom 链。作者强度短暂为零时跳过当帧，保同一 owner 的有界暖复用。真实新旧会话交接的配额重新取得仍需同进程取证。

<a id="scene-post-processing-feedback"></a>**实际回执。** 原终端在同一提交中确认 SDR／浮点工作域、最终输出是否实际含普通或 HDR Bloom、显示侧采用 SDR／扩展范围及其限制。禁用、作者关或零强度、有效输入但不支持的 HDR 级数、准备或编码未完成独立回显。Bloom 使用原编码结果，图像是否确有高光或光晕用配对画面验证。持久 raw 只留原生产证明，暂停复用 raw 时按新提交的显示副本和实际映射确认；映射失败而实际回拷 raw 时不报告副本的 Bloom。丢帧保最近成功回执。沿既有逐屏完成和变更去重，不增加资源、检测 pass 或状态来源。设置按现行活跃请求、Surface 及实际显示意图标注旧结果。验收用普通作者、真实 HDR 作者、暂停热切及 SDR 反例，另以原 Metal 夹具核作者禁用／零强度、附件路径和原色回退。

**实测验收**用单亮像素、多相位细线、偶／奇数边界、宽亮斑、彩色过亮和零强度输入。在原工作域比较 `开 − 关`。需报告线性输出时对开、关各施同一终端变换再取差，记录两组实际 headroom。量近／中／远光晕剖面、RGB 贡献积分、alpha 和基础颜色，验仅普通／仅 HDR／两者皆有及动态开关。再跑含体积加光、反射和 `clear=false` 的作品，确认 Bloom 读取完成主色、累积历史保持 raw，验证预算失败后恢复和完成后可再取得配额。记录各级 pass、实际尺寸和读写、首次切档时间、暖／在途峰值、P95、呈现与 SDR／EDR 换屏。

<a id="scene-texture-quality"></a>
### 纹理分辨率

**选型为保作者 mip 与可用的原生 BC，合格静态色图选择真实较小 mip／解码尺寸。** 沿原 Loader、source revision、`TextureKey`、raw／BC uploader 和 frame publication 结算。Apple Silicon 用统一内存，RGBA8 的 4096² 基级单张逻辑 64 MiB，从作者 2048² mip 开始可跳过这部分基级数据。BC、对齐、cache 及同时在途改变物理读写和峰值，须另量。现有采样器按作者 filter 决定 mip 插值，线性且符合各向异性条件时已有最高 16 的设置。 [Loader](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader.swift) · [采样器](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift) · [设备 BC 能力](https://developer.apple.com/documentation/metal/mtldevice/supportsBCTextureCompression)

| 算法 | 对本项目的取舍 |
|---|---|
| **作者 mip 尾和原生 BC** | 合格 TEX 上移物理 base，上传保留的原 mip，源文件原样。先以一档试验，保颜色角色、滤波／地址语义、逻辑尺寸和有效取样密度。Apple7／8 也须按 macOS 上的实际 `supportsBCTextureCompression` 和用途选择，失败沿已支持解码路径。若当前容器仍物化全部 LZ4／mip payload，初版只计已证的 GPU 上传／驻留收益。解码成本确为瓶颈时，在原 parser 的 payload 材料化点跳过已完成边界检查的未选级。 [TEX 读取](../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneTexContainer.swift) · [压缩上传](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneCompressedTextureUploader.swift) · [Metal 格式表](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf) |
| **ImageIO 目标尺寸解码** | 静态普通 RGB(A) 图片沿原入口试长边 2048，保 ICC、颜色空间、预乘 alpha 和逻辑像素。非默认方向 JPEG 沿原 EXIF thumbnail transform，与缩小在一次输出完成，其他格式保原方向规则。每种纳入格式实测 CPU 峰值，含特殊 alpha／色彩解码而语义未证相同的图片继续走原路径。 [现有 ImageIO 与上传](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift) · [Apple ImageIO 指南](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/ImageIOGuide/imageio_source/ikpg_source.html) |
| LOD bias、GPU 重采样、重压缩／streaming | 现有 mip 过滤处理取样闪烁。只改 bias 仍保完整分配。GPU 上传后再缩小须计双方同时驻留和带宽，适合已有原尺寸消费者的情形。ASTC 重新编码和 sparse 需额外硬件门、映射及缓存维护，由独立瓶颈决定。 [Metal 纹理优化](https://developer.apple.com/documentation/metal/optimizing-texture-data) |

**档位和生效**「高质量」等同现役选择、尺寸上限和设备预算。「高性能」对用途已知且可缩放的静态色图减少实际规格。「自动」由准备期的最大投影 footprint 取满足目标屏与所有消费者的最小已验证表示。缺稳定投影上界或依赖精确像素时沿原规格。已证明的静态普通图随实际 drawable 扩大越界后，在原基础资源 worker 复用冷准备的 `.minimumExtent`。每轴沿同源最大作者用量取需求，加载最小足够的原生 mip；只有该需求越过所有尾级或原 Loader 回退时才请求基级。每次成功以已上传候选的物理尺寸为准。精确像素寻址、固定 LOD、`g_TextureResolution`／mip 信息参与精确作者计算、未知通道、数据／法线、atlas／动画、mask/cutout、LUT、体积、动态／Video 保原语义。实际表示不同且共享缓存会相遇时才加 GPU key 的 base mip／extent，CPU 原字节可共享，旧代待现有租约和 GPU pin 回收。档位在下次应用时采用，已选择自动的会话可以在原 Surface 内升级资源。 [候选元数据](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader+Candidate.swift) · [资源准入](../scene/architecture/scene-resource-admission.md) · [原通道物理复用](wallpaper-quality-work-card.md#scene-raw-texture-reuse)

无 padding 的归一 UV 色图以选中输出供应实际尺寸和映射尺寸，保 UV 比例为 1。原逻辑尺寸沿现有作者布局。`candidateOutputGeometry` 与 ImageIO 按已授权输出核物理尺寸和方向，精确／带 padding 角色保原校验。 [候选 UV 几何](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader+Candidate.swift) · [ImageIO 尺寸及方向](../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift) <a id="scene-texture-deferred-quality"></a>初始隐藏而由作者属性显示的普通根图沿已有延迟 worker 加载。它与同源初始可见图共用同一纹理选档计划，保精确用法、作者原布局、TEX 资格和同源最小尺寸的约束。冷准备仅传已选方案，不新增隐藏图像解码、上传或磁盘读取。延迟显示按现有 loader 消费选档，Auto 扩展仍由现有投影和资源 owner 接管。用现有准备夹具证首次可见才上传且实际尺寸与初始可见对照一致，以同源精确用途、变尺寸和晚失败作反例，验收复用现有原生门和签名 desktop。在原包 2877855240 的初始隐藏层 282 由作者原 Combo 显现后，484×316 的原生绘制目标上 Auto 实际绑定 960×219，高质量 1920×439，二者均完成原 deferred 提交和显现。独立自有 Combo 夹具用不改字节的作者 TEX，高性能绑定 1920×1091，高质量 3840×2182。真实 3264246690 的初始隐藏层已显现，高性能仍绑定 5120×1440，另一个可删除层的可见性 VM 实际执行，旧资源准备因全域模型别名保护覆盖该源。改由冷准备按消费者分配：明确请求的动态模型独立准备全规格，已上传且实际可为相同模型默认纹理建别名的图层才保留全规格。脚本模型请求与能变更图层的 VM 都可在运行时求值 createLayer 路径，完整的 eager 别名继续可用。延迟图层不参加冷目录，首次显现采用高性能选档。Auto 仍沿原投影资格，未知的脚本跨层几何写入尚无投影需求来源，保留该限制直到按实际变换驱动。M4 签名原包 3264246690 的另一层脚本仍运行，层 28 高性能实际绑定 1280×360、高质量 5120×1440，两档均真实显现。计算路径真实克隆、同源可见加延迟及 Auto 继续沿原回归。独立场景、资源尺寸与截图对照归[纹理执行卡](wallpaper-quality-work-card.md#scene-texture-rollout)。 完成帧与资源回归归 `.artifacts/wallpaper-quality-deferred-texture-20261127`。
<a id="scene-raw-candidate-layout"></a>
静态原通道纹理的第二个消费者仍需作者布局。已核的 3453730450 同一 22,105,819 B TEX 在基础图清理解码缓存后再次读取，依原 parser 展开五级 22,347,776 B。比较延后完整解码缓存清退、对 TEX 开短读分支、复用已验布局。延后清退会延长大数据与 GPU 的双驻留，短读需新入口及同等坏块判定。选用现有 GPU 项附带首个正常静态 Candidate 已结算的 mapped 尺寸、原采样位与格式。实际纹理提供 physical 尺寸。只在该源 revision 的同一原通道对象和已认可的静态布局同时存在时复用。原各用途 Content、几何和发布沿同一 Candidate 构造，不能复用别的用途的 Candidate。条件图集、sprite、压缩和需要原 payload 的消费者仍走现有准备。普通静态命中读一次当前来源，miss 沿该次已取 identity 进入原 parse。没有第二缓存、也不改变缓存清理和对象驱逐时点。

同 revision 第二消费者须消除一次完整读取和 LZ4，保五级纹理和实际终图。核 padded R8／RG8、改名与新 revision、坏尺寸、动画／BC 和颜色／法线。量准备时间及实际解析字节。若增加驻留或重复布局，保现役。 [现有 GPU 复用](wallpaper-quality-work-card.md#scene-raw-texture-reuse)

<a id="scene-tex-lz4-input"></a>
LZ4 同步消费 TEX 快照中已验证的输入区间，省压缩数据复制，保持实际输出长度和坏块失败。普通未压缩 mip 自持 Data。已用 3453730450 和独立 3477054430 的 RG8 对照 CPU、实际字节和坏块边界。物理读盘、完整启动与能耗分别量。 <a id="scene-texture-snapshot-slices"></a>**库内快照借用试验已退出。** 原 parser 允许静态 TEXB3 嵌入 PNG／JPEG 借用已验证区间，整份快照只计一次，外部映射、条件、动画和独立解压沿原表示。精确解析租约仍在时共享快照。拒收或另一 Loader 所持同一文件键时，只分离实际消费的延迟编码载荷，紧凑 RGBA8 由解码像素自己供给。原生产品 Loader 以真实尾链确认局部峰值下降和完整像素一致，签名 App 两种取样路径均复现同一场景启动峰值上升。本版不进入产品。新方案须先解释并消除整场准备高水位，再争取局部节省。 [实绘与全链结算](wallpaper-quality-work-card.md#scene-embedded-mip-snapshot-result)

<a id="scene-one-level-texture-trial"></a>
**高性能只跳一级的试验** 保持现有高性能的普通静态根图资格和 2048 启动门，仅将既有目标基级最多限制为 L1。复用原完整链、加载失败回退和物理缓存，同一个作者的非颜色、具名、动态和精确坐标消费者仍独立。对照 1695673397/12 的 L2 1000×1067 与 L1 2000×2134、3355255518/54 的 L2 1632×1105 与 L1 3264×2210。两例都是本机已接纳的 TEXB3，不替 Windows TEXB4 的运行验收。[官版 L0 静态证据](#official-texture-resolution)

同一内屏、全物理尺寸及固定钟相，以高质量图为参考。169 预选画面归一区域 (0.34,0.24)–(0.48,0.43) 的脸与细发，335 预选 (0.68,0.11)–(0.84,0.29) 的眼与头饰。每个真实作者的候选 RGB 平均误差相对参考须较现役降低至少 10% 且至少 0.25 个 8 位码值，并超过现役 A/A 波动。作者该区域在 A/A 时若仍有未冻结运动，先定位可冻结输入。另核独立邻例 3383210272/184 维持原一级，带 padding、法线、单 mip、坏低级沿现役。记录实际绑定、画布与主色尺寸、Texture allocatedSize 和准备局部预算；可见提升成立才做关闭捕获后的原 P95。整帧 P95 超过同机 A/A 波动且恶化超过 5%、作者精确输出受损、或增加分配引发局部退化时保现役。只在可见收益过门后考虑公开行为变化。签名 3024×1964 固定输入的 A/A 和 B/B 均逐字节相同。169 的区域误差 6.4344→1.7607，独立 335 从 0.001679→0，后者未过 0.25 的绝对门，尽管候选全图与高质量参照同字节。邻例 338 实绑 1955×1100。额外的作者 L1 会扩大真实规格，独审核到现有 L1 分配失败会转试更大的 L0，旧 L2 仍可能可用。按画面门撤回一行试验，保现役，未进入时延与预算实测。收据归 `.artifacts/wallpaper-quality-scene-one-mip-trial`。

<a id="scene-effect-color-mip"></a>**带局部特效的基础色纹理。** 高性能在既有冷准备以已可执行的独立局部颜色捕获选级。全部可达 Program 变体须证明实际图槽读取同一颜色捕获。固定归一坐标捕获的基础源可换小作者级，捕获尺寸仍按原映射及当屏尺寸确定。Program 维持原采样顺序、规格与包括 LOD 的图内语义，独立精确纹理和未证用途保原。多段先验真实前后输入。第一段读取归一色捕获，后续段读取上一段发布的同规格颜色，已知安全的运行旁路继续沿原图。各段原工作目标、滤波、辅助输入及顺序保持。多 pass 的首批范围为原已准备的局部材质图。按原节点顺序核对每个临时读取已有本帧写入，采用已准备的候选槽、变体和原图 identity 验证可证采样的色源传到最后输出。普通全附件覆盖的局部生产者和固定颜色捕获可参与，不扩大 terminal replay、临时目标尺寸、格式或采样规则。依赖、具名输出、历史、混合输入、清除函数、额外合成切换和主色读回保原。Auto 继续用原局部捕获格与屏幕投影取较大需求，临时纹理仍取作者图的现有规格。原包 3842146674/20 与 3678939765/23 为正例，3561969313/16 为保原反例，按同屏同相位验实际各 pass、切档、终图和 MTLTexture 分配。实际收益不过门即撤候选。高性能以同一档旧版为对照，至少两部独立作者比终图与实际分配。同相位同档重复先稳定。Auto 在原准备入口逐轴合并最大屏投影和固定局部捕获需求。首批仅静态正交、无角度、标准局部捕获，复用渲染的 128 量化与工作目标裁限。能进入原优选捕获的映射尺寸、多用途、可变尺寸和未确认用途保原。沿原同源冷选、延迟加载和热升，升档后缩窗复用在手纹理。3583632808/31 验原尺寸冷启与小窗热升，3462639638/16 验另一作者低级实绘同灯光相位，3600590272/17 验小级高度不足时保原。按同档重复核对原实绑、原捕获、终图与资源退役。取 3561969313/34、1695673397/71 与别名反例 3226487183/57 的签名完成帧核实际采样、原效果目标与终端，再测分配。画面先比较同档重复，只有超出同档波动且与局部捕获对应才归因。实际进入终图后记回执。 **实测验收**用真实 4K 静态 TEX、普通图片分别量源读取、解析／LZ4、ImageIO 解码、Metal 上传及 `allocatedSize`／池计费／进程峰，按冷、暖、切档与新旧 Surface 共存取样。用条纹斜移和实际 1×／2× 显示验证摩尔纹、锐度、UV 与颜色。检查候选物理 mip 尺寸、边界采样和作者布局尺寸，加入定向不对称 JPEG、ICC、透明边、奇数长宽、颜色和数据共享消费者、资源改名、等价表达及带 padding 的 atlas/cutout、动态媒体、绝对取样、无 mip 反例。验 Auto 的尺寸决策、换屏／放大、源 revision 与坏缓存重建。实际减少内存／解码成本且可见精度在预登记范围内时，才公开对应档。

<a id="scene-single-png-color"></a> **单级 PNG 色源试验已退出。** 在可缩静态普通色或已证局部颜色链中，若 TEXB3 只含一张无填充 PNG，复用原解码和原 DeviceRGB 高质量栅格化，直接上传长边至多 2048 的单级纹理。先用原解码可证无 alpha 的输入验同一颜色语义。选择原生大小、原作者 mip 或缩小的基级仍由原候选与 GPU key 决定。缩小如不能执行，回原完整表示并说明。实际基级仍为 L0，回执区分重新采样的基级与作者 mip。保作者原布局、逻辑 UV、滤波、局部捕获和依赖语义。若两部独立原作在终图、Metal 分配与准备时长的对照通过，再接 Auto。Auto 只在相同缩小规格覆盖逐轴投影与固定局部捕获时采用，越阈按原热升从同源换回原级。单级始终单级，无新缓存、纹理读回、上传后再缩小或逐帧处理。看实际 RGB 与变化区域，另加透明、精确数据、填充、ICC 和已具作者尾链负例。以两部原作、稳定相位、终图 MAE ≤ 1 码和实际 GPU 分配减少为最低门。阶段时间超过重复对照噪声且稳定恶化时撤选该路径。本轮未过门，保现行基级归一化和作者尾链。 [原作对照](wallpaper-quality-work-card.md#scene-single-png-result)
<a id="scene-auto-fitted-drawable"></a> **Auto 冷准备与原尺寸取景。** 全窗上界适合「填充屏幕」，在「保持原尺寸」下可能跨入更大的作者级。候选比较安装后向下换级与冷准备复用取景计算。采用后者，省一次上传、资源换入与首帧驻留。Host 只为 Auto 快照所选目标窗像素范围与取景请求，后台解出作者相机后逐屏用 Metal View 同一正交内接算法并向上取整，最后按轴取最大值。缺有效画幅和默认填充沿全窗。既有选级继续合并纹理的固定局部捕获格。已安装 Surface 用真实 drawable 经原失效事件触发热升，准备中发生的更大实际需求也走这条路径。缩小复用当前级，失败沿在手图，完成帧仍是回执权威。没有新缓存、重载或逐帧计算。验 3678939765/23 与 3842146674/20 的独立多 pass 局部链，另以 1695673397/12 验普通根图实绑与切档。固定同窗与作者输入，用旧版 Auto Fit 对照实绑、终图和单纹理 Metal 分配。两部均须降一级和降低分配，终图平均 RGB 绝对误差不大于 1 码，作者局部格与各 pass 保持。依次 Fit→Fill→Fit，确认原会话升回原级、原窗重新呈现及热升后保留在手级。补异向多屏及缺画幅反例。有画面退化或无实际分配收益就撤候选。
<a id="scene-shadow-quality"></a>
### 阴影

**选型为现有灯空间深度图＋接收平面校正的 PCF，首批用是否生成阴影和真实深度图预算分档。** 定向图根据实际可见接收区做固定世界网格拟合，定向比较当前 16 tap（分组 gather），点／聚光保原 4 tap。点光为六面 3×2 atlas，聚光和定向各一图。深度图跨 pass 供接收者读取，用原 `depth32Float` 池。单图 1024² 的逻辑载荷约 4 MiB，4096² 约 64 MiB，单个点光 1024 六面约 24 MiB。历史固定 1024→4096 短对照 GPU P50 20.354→23.417 ms，池峰约多 120 MiB（两个在途图）。因此档位先控制真实图尺寸，采样成本单独量。 [现役编码](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+StaticModels.swift) · [接收面滤波](../scene/capabilities/advanced-object-coverage.md#model-directional-shadow-filter) · [图尺寸对照](../scene/capabilities/model-runtime-evidence.md#model-directional-shadow-density)

| 算法 | 对本项目的取舍 |
|---|---|
| **现有 shadow map 与 PCF** | 保合法屏外 caster、同帧 pose／UV、镂空材质、真实接收面、灯序和偏移。GPU 用原 gather 与逐 tap 深度参考。调 map 密度直接影响覆盖、内存和带宽，PCF 的世界尺度随 texel 变化，需要同时验证阴影边宽。 |
| 硬件单参考 PCF／PCSS | 固定比较参考的硬件 PCF 不能表达现有逐 tap 的接收面深度。PCSS 能按遮挡者距离改变半影，增加遮挡搜索与采样，需要真实作者光源尺度及遮挡材质合同。有独立软阴影需求时再比较。 [PCSS 原文](https://download.nvidia.com/developer/presentations/2005/SIGGRAPH/PCSS.pdf) |
| VSM／CSM／光追 | 方差图可预滤但需要统计纹理和压制漏光。级联可改善宽距离跨度，却增加图、边界和共享预算。实时光追引入加速结构与动态几何更新，也扩大硬件资格。当前需求由实际接收区的单图与预算解决，另有实证问题再立项。 [VSM 方法与漏光](https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows/chapter-8-summed-area-variance-shadow-maps) · [Metal 光追加速结构](https://developer.apple.com/documentation/metal/ray-tracing-with-acceleration-structures) |

| 档位 | 定向图候选上限 | 点光／聚光每面候选上限 |
|---|---:|---:|
| 禁用 | 跳过 map、caster encode 与 receiver 阴影采样 | 同左 |
| 低 | 512 | 512，验证点光六面与聚光边缘后采用 |
| 中 | 1024 | 1024 |
| 高 | 2048 | 1024 |
| 超高 | 4096，沿原接收区选择 | 1024，沿现行路径 |

**实现和生效**定向低档以实际 512 接通拟合边距、稳定网格、atlas 视口和采样。更高档、逐灯和整组回退保守按原 1024 拟合。禁用停产三类影图，保直接光、相机深度、体积遮挡和作者 `castsShadow` 资格。

点光候选将高／超高每面升至 1280／1536，单灯 37.5／54 MiB。尺寸由实际影图生产者按候选的冷准备档选择。点光成图后用实际 atlas 宽度除以三得到每面尺寸，低于本档计划时只给该灯记录降档。采用候选后，点光 1024 只代表中档或实际降档，原 1024 灯种上限只留给聚光。定向仍用实际接收范围解释等效。AppKit 不从档名推断规格。扩档组须同时有渲染池逻辑余量和设备实际分配额度。一次无驱逐预约包括规划、提交与分配失败路径，三个位置共用同一条件。超出任一额度即按原规则预约定向、聚光和基础点光，原组仍失败则沿原有逐灯基础回退。原本较晚申请的材料纹理、反射环境与前向图输入优先于点光扩档。原相机深度仍在合成准备早期取得，光空间影图在实际来源及前向 Provider 准备之后、首个模型消费之前一次生成。同一帧先拟合普通模型的实际 caster 与投影，再确认终端和 framebuffer 快照容量。反射、源材质和有实际 caster 的影图计划共用这次容量结果。有 caster 而光投影均不成立时仍保护原终端和快照。随后完成供货及前向图并消费原计划。具名模型仍由原晚准备 owner 在供货后拟合和编码。需要前缀 MSAA 或体积遮挡的组合须先证明所需冷目标与扩档能一次预约。整组失败时沿基础影图和原晚目标顺序继续。3024×1964 合成测试的 120 MiB 档须观测点光回落 1024，保持 4×、另写 D32 与中档光晕。宽松池高档须同时实用 1280 和全部其它效果。75 MiB 记录各实际结果。指数零用解析积分，非零指数邻例核原超高六点和参考画面。以完成帧的影图绑定、D32 读写身份和匹配终图裁决，再进入长窗。逻辑余量不足时扩档无需申请纹理。验收包含物理额度充足而逻辑池满的相邻反例，确认暖纹理身份、计费和原接收保持。六面交角选择沿原 X／Y／Z 次序。选择前保同尺度整数 texel 中心，避免各轴归一化把真等值方向舍入成异值。实际采样仍用当前面真实 texel 与径向深度。 [候选画面与状态](wallpaper-quality-work-card.md#scene-point-shadow-density-trial) · [作者点光资格](../../MyWallpaperX/Core/SteamWorkshopScene/Format/ScenePointLightDefinition.swift)

**实测验收**固定 world 网格和四个亚 texel 相位，量影边位移、亮度波动、接触间隙、孔洞和自阴影。核动态骨骼、组裁剪、具名／合法屏外 caster、点光接缝、聚光锥、多灯紧预算、镂空和独立实体遮挡。比较真实图尺寸、caster draws、深度 pass、receiver 成本、计费和连续帧 P95。禁用时三类阴影工作归零，直接光与普通遮挡保持。 [实际投影与覆盖合同](../scene/capabilities/advanced-object-coverage.md#model-directional-shadow-density) · [影边成本](../scene/capabilities/model-runtime-evidence.md#model-directional-shadow-filter) · [官版阴影图与滤波](#official-shadow-atlas)

<a id="scene-shadow-feedback"></a>
#### 阴影的实际结果

分开记录已保存的档位和实际完成帧。准备侧只给模型资源本来就知道的禁用、缺少资源等事实。投影侧在原预约时保留各灯的计划规格和失败原因。只有模型管线为同一提交匹配投影灯、实际绑定影图并编码受光材质，才记为消费。以现有每帧最多四灯的范围按灯种收敛，点光用每面尺寸，定向和聚光用单图尺寸。停止使用仅遍历已生成影图的接收证明，复用真实绑定结果。无同帧影图消费时根据已知的禁用、无适用灯或接收、生成失败分别回显。定向拟合从原有可见区与灯空间重合判定直接报告无投影，保留数值不合法与后续影图生成失败的区别。以同一灯的实际规格和原预约原因说明降档。仅有尺寸下降无法识别预算原因。已有有效接收且由投影范围或灯种上限得出同样规格时报告等效。

沿现有准备帧、提交完成、各屏合并和活动请求事件传递，沿用抗锯齿已经验证的淘汰、去重与失败处理。只保留首次和发生变化的有界结果，AppKit 读取同一活动请求进行本地化。持久主色封存同帧采样和阴影事实。重呈该主色时沿用其对应回执，暂缓呈现但已在 GPU 完成的主色只有在实际申请呈现且再次完成后才更新界面。冷启动、切换屏幕或提交失败时的未知沿原事务表达。验收走原控件，核定向明显档差、点光与聚光实际规格、已生成而未绑定、合法场景无投影、禁用仍受直接光及紧预算回退。加一例同屏复用旧主色以及一个发生迟到完成的切换反例，异档同值时须在界面解释原因。

<a id="scene-shadow-steady-author"></a>
在物理桌面上按 A/A/B/B/A 对照。3589454154 用定向低／高，3455121165 用点光与聚光低／中，均固定 30 FPS、同一构建、原包和 1 GiB 解码额度。点光扩档另以未改 3455121165 和兼容默认 60 FPS、超高阴影对照现役。在独立短窗核真实灯图与聚光不变，正式长窗关捕获和阶段重诊断。桌面接管后预热 30 秒，采至少 60 秒，核完整呈现端点、离群、GPU 失败和排空。分列调度重对齐、drawable 缺失、计时器和准入失期。失期率为两种失期之和除以（有效 FPS × 秒数）。两项均以候选最差值减基线最好值。呈现 P99 差最多一个实测最短刷新周期，失期率差最多 1 个百分点。GPU 与帧时间差须超 A/A 波动才归因。接管、实际图接收或独占 GPU 任一缺失，剔除该窗。 [桌面选片基准](../../script/web/wallpaper_startup_benchmark.py)

画面另行固定作者时钟，以禁用图定位阴影，逐档重复并量边缘位置及相邻相位。无可定位差异的作品只提供实际影图接收和呈现证据。能耗另走物理测量门。18 个固定相位的签名收据和首个 30 FPS 有效桌面窗见[工作卡](wallpaper-quality-work-card.md#scene-shadow-steady-prior)。独立复核与裁片归 `.artifacts/wallpaper-quality-shadow-frozen-repeats`。

<a id="scene-volume-quality"></a>
### 体积照明

**选型为点光保当前球内有限视线的分段 Gauss–Legendre 求积，聚光保自己的有序光锥绘制。** 点光需要清屏透视根域、作者无阴影的合格点光、至少一个合格的根域实体写入者。用独立遮挡深度截取视线，进出球界之后在最近点分段，高档每段用四点，超高用六点，指数零直接用线段长度。聚光当前是按作者 TRS 及材质参数绘制的锥形覆盖，沿根层、父层和组 source 位置合成。两者已有真实链证据，通用照明、多重散射及更广聚光遮挡须各自验收。 [点光合同](../scene/capabilities/advanced-object-coverage.md#point-light-volume) · [点光 MSL](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/ScenePointVolume.metal) · [实际遮挡生产](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+StaticModels.swift) · [聚光锥合同](../scene/capabilities/advanced-object-coverage.md#spot-light-frame) · [代表实播证据](../scene/capabilities/runtime-evidence-current.md#point-light-volume) · [官方点光／聚光作者控制](https://docs.wallpaperengine.io/en/scene/models/lighting.html)

逐屏回显复用完成帧的质量回执。点光取得独立深度并编码积分时登记实际管线。若所有参与点光指数为零，登记解析积分。取得合格积分计划而深度或编码失败时登记点光不可用。聚光只在作者光锥实际编码时登记，可与点光并存。两者均无回执的完成帧显示未绘制体积光，成功的禁用帧单独回显。超高请求实际执行四点时说明降档。原持久颜色携带原回执，活动屏、首次完成、旧请求和失败沿既有质量事件，无每帧额外投递。验收检查禁用／四点／六点、解析和纯聚光并档、两者并存、失败与冷切旧帧，最后走原设置控件与签名窗口。

| 算法 | 对本项目的取舍 |
|---|---|
| **原尺寸四点／六点积分与有序光锥** | 点光在同一实际遮挡深度上积分，按真实光球投影的保守并集收紧片元覆盖，输出直加原主颜色。全屏仍走本档同一积分。六点适用于真实高指数峰值，沿同一 PSO 槽冷准备。两点未复现收益，实验已退役。聚光开关沿真实 producer，保作者锥形覆盖和顺序。 [实测](wallpaper-quality-work-card.md#scene-volume-point-coverage) |
| 半宽高积分＋深度引导重建 | 已退出。色积分像素数约 1/4，但同一 Apple GPU 的粗格和重建合计与现役成本重合。真实深度不足以恢复稀疏亮光，试验丢失窄峰。额外私有颜色跨 pass 存储，不能用 memoryless 消除。 [实测](wallpaper-quality-work-card.md#scene-volume-half-trial) · [联合上采样](https://johanneskopf.de/publications/jbu/) · [Metal 存储](https://developer.apple.com/documentation/metal/mtlstoragemode/memoryless) |
| 逐像素 ray march／froxel／时域重投影 | 支撑更广的阴影体积和介质，增加采样、3D 网格或历史，且会碰到作者分组／顺序和动态透明深度。待有完整的光空间可见性和介质需求再独立评估。 [视锥体素照明实践](https://advances.realtimerendering.com/s2018/Siggraph%202018%20HDRP%20talk_with%20notes.pdf) |

| 档位 | 点光已交付基线与其余候选 |
|---|---|
| 禁用 | 停可选遮挡收集、独立深度重放及终端加光，保表面光与主相机深度 |
| 低 | 同尺寸两点与半宽高重建未达真实成本或画面门。等待可区分的低耗算法 |
| 中 | 保持现行基线。只有与低档在画面及完整成本上存在一致分级时开放 |
| 高 | 对应已交付「启用」所用的原尺寸四点兼容基线，积分区域按实际场景收紧 |
| 超高 | 原尺寸六点。保指数零解析分支，PSO 不可用沿原四点 |

对 448 条归一化裁切弦做独立 CPU 积分，三点在指数 1、2 的相对误差 P95 为 0.10%、0.32%，指数 10 升至 8.39%，现役四点分别为 0.03%、0.09%、2.61%。模拟实体裁切的指数 10 则为 9.75% 对 1.73%。两点已有低指数成本阴性，三点在已知广覆盖高指数作者现缺足够精度，原尺寸等距也会产生依赖相位的亮峰偏差。先保高与超高，低／中要取到新的可区分算法和真实作者，暂不将这些数值结果当发布档。完整对称弦可能共用一半积分，已知广覆盖作者为眼内，应有真实可达的广覆盖外部灯再评估，且不以此制造质量档。 片元四 lane 的共享求积在本机 Metal SDK 可编。代表射线会在同深度的相邻像素间共享各自不同的球相交、端点和遮挡；完整 quad 也可能只有一个像素命中窄亮峰。边界与 helper 要求活跃成员，逐灯复验支撑和分段又引入热路径工作。当前保逐像素积分；空间缩放按可复验的光晕、细峰与成本单独判断。 [Metal quad 规范](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf#page=226)

**实现和生效**体积档随原 Scene 冷准备。禁用退出独立体积点光和聚光锥的原 producer。高档保旧 `enabled`，超高只从同一光积分 PSO 槽改求积阶数。作者半径、密度、指数和亮度继续由原参数控制，父程式输入、顺序、可见性、直接光和具名供货留原权威。 [顺序编码与遮挡重放](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+OrderedLayerEncoding.swift) <a id="scene-volume-depth-footprint"></a>现役的专用遮挡筛除普通主深度中的 legacy 模型和终端程式写入，两份原作者均触发差异，主 D32 不直接复用。沿用已经证明覆盖完整的积分 scissor，先筛专用 D32 缩小附件。渲染沿原投影、剔除和逆深度状态，用负整数 viewport 原点把物理像素平移到局部附件。积分仍按全屏视线，只在读 D32 时减去同一原点。附件采用已有有界池和固定尺寸档，原点不参与池键。当前完整屏继续原路径。验收需覆盖斜边和近面裁剪、显隐和跨尺寸、写入不测深度、HDR／SDR 原深度及画面、紧容量恢复和宽灯未新增成本。窄灯须实际减少至少一半 D32 驻留；阶段测不到帧时改进时只记录容量收益。原生 M4 的含真实遮挡六组在同一读区保持覆盖及终图逐值一致，倾斜／近面 D32 最多差 2 ULP；3024×1964 测试夹具实际分配从 24,641,536 降至 540,672 B。待签名作者、尺寸切换及同一 D32 多 pin 的正常驻留。原生读回归 `.artifacts/wallpaper-quality-cropped-volume-depth-20261127`。该优化服务当前精度，低／中档另验真实分级。 [Metal viewport](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/setviewport(_:))

**实测验收**用离线高精度积分或指数零的解析长度验证能量与光锥轮廓，再用场内球内／外、擦边射线、近远裁剪、亮窄峰、透明轨、薄实体、名义有灯但零贡献及 group／named spot 夹具核原 App。配对作者启用／关闭 `castsShadow`，分别切用户阴影档，核前者不会生出无阴影光束。移除唯一合格根域实体作无体积负控。单列前景两侧的漏光与轮廓偏差，核异尺寸换屏、开关无错误残影、Fog 与直接灯邻例。量遮挡深度重放、积分、重建各自成本和总 P95、带宽、临时池与整机能耗。额外纹理读写吞掉节省时放弃半尺寸，较高积分阶数未超过参考噪声时让「高」保持上限。

<a id="scene-volume-reparameterized-quadrature"></a>
#### 向光心偏置的二点／三点求积

先在数值门试每个半弦的 `t=a+(b-a)u^q`，其中绝对坐标从近灯心端到远端。取固定 q 为 1.5 或 2，按变量替换把 Jacobian 并入原 Gauss 节点权重，编译后无需逐像素算 q 次幂。与已退出的线性二／三点不同，候选把有限节点移到密度较高的一侧。精确相交、近远截取、遮挡边界、零指数和 alpha 仍由原路径负责。若通过，仅考虑保全尺寸、同遮挡和同 PSO 槽的成本试验。

以独立高阶积分对照分层归一化弦。覆盖中心、近中心、擦边、眼内、前后截取及不对称双半弦，指数为 0、分数及整值至 32。绝对贡献至少 0.001 的每组中，相对误差 P95 不高于 3% 或现役四点同组误差再加 0.5 个百分点，取较大值。中心高指数、前景截断与窄峰的固定探针允许绝对误差至四点再加 0.003。64／128 仅作压力对照。超界即退出。

自适应积分筛查 37,995 条弦，其中 20,913 条达到贡献门槛（含压力组），2,086 条中心轴结果通过解析交叉核验。二点 q=1.5／2 分别失守 49／54 个分层，三点分别失守 33／34 个。已有作者采用的指数 10 上，两种三点的完整弦 P95 为 11.50%／18.05%，四点为 4.93%，此组限 5.43%。实体截断组为 11.24%／16.32%，四点为 4.18%，此组限 4.68%。独立计算以完整中心半弦精确值 1/11 及近轴截弦复核三点失守。q=1.5 的未归一 Jacobian 权重和也偏离 1，导致指数趋零时的偏差。四种候选均退出，不进入 GPU 或成品试验。保原尺寸四点与六点。矩阵和复算归 `.artifacts/wallpaper-quality-volume-tiers/reparameterized-quadrature`。

<a id="scene-volume-density-table"></a>
#### 原尺寸累积密度查表

保留现役逐像素光球相交、D32 遮挡裁切、覆盖区及合成。只在隔离候选里将分段求积换为两次累积密度采样。以固定作者指数冷生成 `64×64 R16Float` 小表，列为距光心的轴向位置相对半弦的比例，行为 `1−sqrt(1−b)`，其中 `b` 为归一冲击参数。由两个裁切端点取带符号的累积值相减，累计和辐射仍用 Float。指数零沿解析长度；此片先核整屏指数 10 正例与原有窄灯，超出资格的指数继续按现役积分。另验射线同侧短段、大辐射和近切线，避免低精度表互减吞掉真实光。

以同一 D32、RGBA16Float 和 3024×1964 按 A/A/B/B/A 量阶段中位。两次候选均须较最快基线省至少 15%，独立窄光最多多 0.02 ms。原生须保 alpha 和遮挡，另核近切线、短段和独立细灯。宽域收益成立后再验作者和真实提交。

M4 眼内指数 10 的五臂为 0.513／0.480／0.345／0.346／0.481 ms，候选降约 28%，宽完整弦约降 24%，窄灯约 0.103 ms。92 组 alpha、实际 D32 一致。但同侧短弦的遮挡中心从 0.14612 抬至 0.30664（SDR 37→78），超过 7,500 个有效红分量。限域至清深度并严格跨心，只让此域查表，保护了 393,388 个模型覆盖读回像素，宽域节省 23.5% 以上，近／远裁线跨心仍有 0.00342 至 0.01685 的 HDR 净跳变，SDR 可跳 6 码。两候选退出。M4、复制及独立复算归 `.artifacts/wallpaper-quality-volume-tiers/density-table-trial`。

<a id="scene-volume-segment-mean"></a>**原尺寸点光的网格积分。** R16Float 三维直接平均表曾避免端点消减，窄光超门且每指数需要约 3.19 MB，已退出。直接 SDR 用冻结版本的团队签名诊断验证 32／64 px。沿原 D32 之后的主目标加载，不增加产品质量字段。只接受实际单采样 BGRA8 输出、合格宽域和保守同行投影；其他目标或几何按原路径。分开取固定作者阶段的实际终端、主目标相同输入的读回和无截图短窗成本。真实独立窄灯须保持原裁剪与输出。同帧签名画面已过单灯门。下一轮要在同一正常 Scene 会话交错原四点／候选帧，用各帧实际生效步长分组，采同一 command buffer 的提交与 GPU 时间。先按镜像六帧窗分组，原路径/32/64/64/32/原路径，以组内邻近的原路径及全原路径安慰剂分辨波动。整个 GPU command buffer 完成后批量导出，计时窗口不采截图或阶段计数。尺寸用实际射线跨度和画面误差预算确定准入，避免为同一物理跨度再按步长套一层尺寸门。同会话镜像次序未复现稳定整帧收益，64 px 相对 32 px 的差距小于原路径配对波动。这条双档候选退出接线。保留物理射线准入与出图证明，后续有新的实帧降成本机制再开档。只插值一盏宽光无遮挡的 GL4，其余灯的保守矩形由同一 encoder 的原三角形按原序相加，非清 D32 续算原公式。用投影的近面四角、远面支撑与四侧平面偏距收敛几何，分别限制平滑曲率和半弦切换的导数跳变，再乘最大 RGB 辐射。区间参数可离线定界，普通帧只消费原打包的相机与灯。有限差分供筛查，实数界、Float 计算、混合和终端映射分别验收。各档未达几何、辐射或分辨率条件时，走已合格的小步长或原 GL4。<br>**保留原全屏三角形的 HDR 候选。** 源误差微小仍可能跨半浮点舍入或被实际 EDR 传递放大。带附件读的几何网格在亮处回原公式仍可出现微差，线性标量缓冲保正确但阶段收益不足。后续只验证小型 R16Float 网格。原体积已合格且 D32 完成后、沿同一 command buffer 在原主 encoder 重开前，按合格步长生成一盏灯的清深度积分。原全屏三角形按原尺寸 D32 和同行面积回原 GL4，低于约 1 的背景和预测叠加色才能尝试网格。亮处保持固定功能加法和原射线。使用原池的随帧物理尺寸键，储位在终端与 D32 之后，失败退出原路径，禁止加全图亮度扫描或改深度尺寸。优先验证直接 SDR 双步长和受控 HDR 的真实帧过渡，分别补原报告的 15% 阶段门、整帧代价、作者 Bloom／持续 raw 邻例、签名终端和独立宽光。全亮反例的增加成本未解决前维持 HDR 原公开档。 [Apple 单 pass 颜色附件读取](https://developer.apple.com/documentation/Metal/rendering-a-scene-with-deferred-lighting-in-swift) · [原生准入与映射证据](../scene/capabilities/runtime-evidence-current.md#point-volume-grid-terminal-replay)
<a id="scene-volume-full-half"></a>
#### 完整半弦的降成本筛查

当分段后的端点恰为光心和球面时，现役四点半弦积分只取决于偏距与作者指数。先用捕获的真实 D32、相机和灯复算，到球面的单个完整半弦也计入，保留所有模型深度和近远截取。分别试匹配边界权重的 Gauss–Jacobi 与拟合现役完整半弦，比较独立积分精度、相对现役 GL4 的交界差与相邻像素组可省节点。拟合只替代完整段，所有部分弦仍沿原节点。对比一张 1024×1 的 R32Float 表，它直接存现役整半弦值并线性插值，避免旧二维端点相减。过滤能力按设备实测；先固定指数 10 判定是否值得冷准备更一般的纹理。 [加权求积公式](https://dlmf.nist.gov/3.5.E26) · [Metal 浮点过滤能力](https://developer.apple.com/documentation/metal/mtldevice/supports32bitfloatfiltering)

先在当前作者指数 10 和独立指数 1 实际捕获检验受益范围。合资格的完整段在浮点筛查须保近轴、近切线与 HDR 高辐射，端点从内侧接近完整弦时，与现役 GL4 的原始线性差不得超过 0.0001。该值只用于筛选。GPU 同尺寸复核原生 SDR／HDR 交界、深度和 alpha，再以原 A/A/B/B/A 量阶段至少 15% 的收益。无达标候选时沿原档；单样本或新路径只能取证，不能开放低／中两档。

实际宽灯 3453730450／39 的两帧各约有 594 万条命中。完整后半弦覆盖 5,348,046／5,345,658 条，分别占全部求积段 46.64%／46.63%。独立 3455121165／85 的 89,752 条射线均读到非零深度，实体在球后，两半都能保留。两种二节点 Gauss–Jacobi 在宽灯实际偏距的 RGB 交界差分别达 0.0104／0.0482，超过原始线性门。七次拟合改对现役四点的完整半弦值，在宽灯的最大差为 0.0000143。直接表的全偏距双半弦误差不超过 0.00000845，同样保部分弦的原求积。

M4 的每种隔离候选各与原版配对 70 组直接目标。35 组 BGRA8 逐字节相同，9 组实际写入的 D32 及全部 alpha 一致。指数 10 的 RGBA16Float 最大分量差为拟合 0.0001221／直接表 0.0000610。直接表在合成完整宽弦的阶段中位从 0.3176 ms 降至 0.2563 ms，约 19%。重放真实两帧的 D32、灯和相机时，拟合两臂均未达 15% 门。直接表两帧各有三臂原版约 0.476–0.478 ms，两臂约 0.461–0.462 ms，收益约 3%。复算量与现役 GL4 的交界极限差，原生读回只量静态完整、裁切和眼内目标。阶段重放不足以证明动态越过球面的连续性、独立精确积分、桌面呈现、显示 EDR 或功耗。两种 Gauss–Jacobi 在数值门退出，七次拟合和一维表在实际输入的阶段计时门退出。只在取得宽域真实完整弦的新样本、或更便宜的整个裁切半弦算法时重开这条路线。隔离收据归 `.artifacts/wallpaper-quality-volume-full-half`。

<a id="scene-volume-dark-tail-screen"></a>
#### 点光暗尾的真实射线筛查

原四点每一段的权重为正，和为 2。对归一弦 `[a,b]`、离中心轴平方偏距 `p²` 和正指数 `e`，令 `t₀=clamp(0,a,b)`，则任一颜色分量在叠加前的积分上界是 `abs(radiance)·(b−a)·max(0,1−sqrt(p²+t₀²))^e`。一条射线可分别估整个弦和现役在光心分开的两段。指数零保解析长度。以后若采用省略，须在上界趋近阈值时连续淡出，并以实际 RGB 辐射对多灯误差求和。上界约束叠加前原始值，Bloom、终端显示映射、半精度舍入及后续帧反射仍须用真实画面检查。

先仅对已完成的真实 Debug 终端捕获，在同一命令缓冲读取点光实际绑定的单样本 D32、打包相机、灯、scissor 和求积阶。只给指定请求编码一次 readback，不进入计时或正式渲染改造。保存清深度与真实模型深度，按现役片元坐标、半弦分段和 4／8 求积点数估潜在可跳过工作，同时统计完整 2×2 相邻组。先取已验宽光 3453730450/39 的两个自然相位和独立窄灯 3455121165/85，分别以 0.000025／0.0001 的原始预算及 0.001 的压力比较核占比。每个预算留一半作连续过渡，至半预算以下才计完全跳过。两种紧预算均不足 15% 的乐观相邻组工作比例就退出当前方案。原始预算只是筛查条件。超过后仍需独立宽光正例、终图误差不超过 1 SDR 码或 0.003 线性 EDR、深度和 alpha 保持，并在不回读的 A/A/B/B/A 中证至少 15% 阶段收益。没有终图与成本的双证，不发布低或中档。 [现役点光积分](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/ScenePointVolume.metal) · [Metal 纹理到缓冲复制](https://developer.apple.com/documentation/metal/mtlblitcommandencoder/copy%28from%3Asourceslice%3Asourcelevel%3Asourceorigin%3Asourcesize%3Ato%3Adestinationoffset%3Adestinationbytesperrow%3Adestinationbytesperimage%3Aoptions%3A%29)

同一团队签名 Debug 在 M4 的 3024×1964 实际编码高档。3453730450 灯 39 的两帧均为全屏、指数 10、打包 RGB 辐射 4.72627。在 5,939,136 条实际交弦中，396,714／397,853 条有模型深度，原四点共约 4,586.7 万／4,586.1 万个求积点。独立 3455121165 灯 85 用作者太阳体积属性、指数 1、scissor 342×342，89,752 条实际交弦都读到实体深度。每个 D32、光和相机、编解码请求与同一完成命令缓冲及实际点光绑定的纹理身份相符。

| 原始预算 | 宽光两帧 2×2 相干可省的求积比例 | 免费知道每段原四点贡献时的逐像素上限 | 窄灯 2×2 相干可省 |
|---:|---:|---:|---:|
| 0.000025 | 0.000227%／0.000270% | 0.021157%／0.019119% | 0.017827% |
| 0.0001 | 0.001701%／0.001640% | 0.078349%／0.076998% | 0.017827% |
| 0.001 | 0.178308%／0.177729% | 0.815554%／0.816811% | 0.080221% |

上表相干列取分段上界模拟 2×2 像素组，两帧宽光按整弦直接判停均为零。上限列把阈值全部交给省略，忽略判定本身的成本与执行不一致，仍低于 15% 的门。三帧实际主色为 SDR。另用原显示映射计算一个半精度 EDR 边界反例。相差约 2.38×10⁻⁷ 的两个 Float32 原始值跨过 1.5／1.5009765625 的舍入中点。在足量 EDR 余量下，两路半精度线性输出相差 0.00390625，已超过 0.003。Bloom 与后续反射还需要自己的误差验证。因此原始阈值不能代替终端门。 [显示映射源码](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneDisplayMappingPostProcess.metal)

整弦与半弦暗尾省略退出。扩展只读库存覆盖 984 个可读根场景，现有无阴影点光体积声明仍只有 3453730450、3455121165；前者另两盏初始隐藏。3287715210 和 3294151411 的已知点光体积在作者声明投影且为正交，现役不接纳。原 D32 与复算归 `.artifacts/wallpaper-quality-volume-dark-tail`。 <a id="scene-volume-exit-table"></a>**实际交段到达球面出口时的直接积分表。** 以离轴偏距和带符号的入射位置 `s=start/halfChord` 索引，存原四点（含跨心分段）的区间平均密度。查一次乘实际区间长度。半弦贴边时贡献自然归零，恒密度和球内被截断仍算原路径。由实际未截终点越过球面后的距离在 0 至 0.01 倍半径平滑过渡，确保遮挡切线无档差跳变。先用上述三份完成帧绑定的 D32、原相机和灯，对照 129²／257² 的 R16Float／R32Float。限制已达贡献 0.001 的误差 P95 ≤3%，原始峰值偏差 ≤0.003。以同一 2×2 像素组能完全退原计算的求积次数统计，宽域至少 15%。遮挡移动、切线和极端辐射留独立实绘。M4 三份真实 D32 的宽域相干覆盖 94.95%／94.93%，真实窄灯的模型深度在球外，原截断资格保留。129² R32 原始最大误差约宽域 0.000224、窄域 0.000349。真实作者 BGRA8 原主色与 D32 原生重放，最大差 1 码，alpha 相同。以相同 `.load/.store` 跑 A/A/B/B/A，四点三窗 0.6521／0.6528／0.6511 ms，候选 0.5864／0.5835 ms，重复节省 9.9%／10.4%；读深度的近空片元为 0.3399 ms。收益低于预定 15%，退出这一版本。未实测切线混合、HDR、窄光 GPU 和整帧。证据归 `.artifacts/wallpaper-quality-volume-exit-table-20261126`。 <a id="scene-volume-clear-depth-table"></a>**清深度直查。** 单灯、近裁面在球内且远面已出球时，只有原 D32 为零的像素按光心的轴向入射与离轴偏距查原四点到出口的积分。相机相对计算省出口求交、区间归一与长度乘法。模型深度走原积分。平方偏距取样在合法近轴反例差 0.00460，改按偏距取样，同一 257² R32 表的近轴加密最大差为 0.000210，真实宽灯为 0.0000264。签名宽灯的同帧 D32、原主色和原 `.load/.store` 重放，四点三窗 0.6465／0.6433／0.6443 ms，候选 0.4314／0.4347 ms，两窗均省 32% 以上。4,261 个清深度像素至多差 1 码，模型像素和 alpha 逐值一致。独立窄灯用真实 D32 和合成底色，输出一致，仍绑定候选 PSO 的两窗较最快原版慢 0.02084／0.02283 ms，超 0.02 ms 门。真正窄灯派发须继续用原版 PSO。宽灯实际 D32 配合成 HDR 底色的原 RGBA16Float 最大差 0.001953，原显示映射后为 0.005859，10,439 像素超 0.003，HDR 路线退出。大世界坐标导致原 Float 近面先舍入，M4 独立夹具中心 SDR 从 109 变 5。任一产品化候选须保近面数值语义并验证辐射范围。冻结 `4740f4080` 的同一团队签名 App、真实 3024×1964 单采样 SDR。宽窄各 288 帧完成并实际呈现，宽灯 96 帧确实选表，独立窄灯 96 次候选请求均保原 PSO 和 342×342 裁剪。宽灯两种镜像交错的整帧 GPU 中位节省为 −0.099／+0.005 ms，同会话安慰剂为 +0.275 ms，未达成本门，候选退出。独立 review 核对实际 D32、资源轮转、终图 F121 及呈现回执。隔离运行用独立 Debug suite；生产偏好摘要同窗变化且同期另有已安装 App 及测试进程，写入者未能确认。性能结果限本次签名证据窗，不外推独占稳态。证据归 `.artifacts/wallpaper-quality-volume-clear-depth-20261127`。

<a id="scene-volume-higher-order"></a>
#### 全尺寸六点精度筛查

六点候选只替换球内每一段的 Gauss–Legendre 节点与权重。沿现有点光 PSO 冷建时选定阶数，保视线与遮挡、实际覆盖裁剪、原加法叠加和目标 alpha。指数零仍用解析路径，聚光不改。始终共用原全尺寸反向深度与终端，无粗格纹理或新增编码段。当前选择达到本机验收，官版各质量档的具体算法仍须另取证。

原生 `rgba16Float` 用完整中心弦 e16／e32 精确贡献 0.117647／0.060606，把六点误差分别限制在 0.0004／0.0032，同时核四点误差确实≥0.0055／0.0225。e10 用偏距 0.05 倍半径且远平面截到后半弦 65% 的中心射线，独立数值参考为 0.146492，六点误差≤0.0008、四点≥0.0035。复用实际深度写入、SDR、完全遮挡、透明、多光和基础小指数等原路径。RGBA 读回中受光之外及 alpha 保原。

先用已证作者 3453730450 灯 39 做 A/A、六点两轮和回归原四点的同签名对照，静止相机、作者属性、时间与分辨率，按事先固定的灯内和盘外区域量差分。灯内至少 1% 的像素差达到两个显示码值，且明显高于同区原四点 A/A 才计真实变化。若独立低指数 3455121165 画面保持且高指数素材确实产生精度收益，再以 30 秒预热和至少 60 秒稳态核原播放预算、完整 GPU P95、实际呈现与零失败。若实际作者画面对比未达门，或昂贵路径出现持续预算回退，保留四点并撤实验。 [实施路线](wallpaper-quality-work-card.md#scene-volume-gl6-trial)

<a id="scene-reflection-quality"></a>
### 反射

**选型为沿原实时屏幕颜色近似反射，按真实消费者启用最近合格完成帧的完整颜色与 mip。** 模型路径对屏幕颜色按法线偏移、视角权重、边缘淡出与粗糙度 LOD 取样。图像和合格 Program 的环境输入沿各自已准备着色。独立水滴和同作品官版开／关对照已证局部贡献，尖端与相位的精确一致和整景性能仍需对应实测。统一内存上的全图复制和 mip 阶段应分开测。熟化的可选反射从上一完成快照直接生成 mip；未完成的双缓冲成员受同一提交 pin 保护。必需持续颜色保原单级和环境派生。以 UHD 的 `rgba16Float` 为例，单基级约 63.3 MiB 逻辑载荷，完整 mip 链约 84.4 MiB，分辨率、池计费及设备实际分配分别记录。 [原模型采样](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneStaticModel.metal) · [模型反射证据](../scene/capabilities/model-runtime-evidence.md#model-screen-reflection)

| 算法 | 对本项目的取舍 |
|---|---|
| **原合格完成帧颜色＋mip** | 复用原 `ReflectionFrame`、pool、blit 和完成状态。经尺寸、像素格式及提交收据接纳的最近成功帧可跨过失败或无呈现帧。只有实际被采样才准备环境副本及 mips，采样与 publication 留同一执行代。Metal blit 要求实际格式可渲染、可过滤，mip 核随 GPU 家族可变。 [现有历史与 blit](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+ClearColor.swift) · [Metal mip 生成](https://developer.apple.com/documentation/metal/mtlblitcommandencoder/generatemipmaps%28for%3A%29) |
| 平面反射／环境 cubemap | 镜面重绘需第二视角、遮挡／剪裁和更多带宽，只适合确认的平面。探针或预过滤 cubemap 可给作者已声明的环境，动态更新和屏外内容需要别的输入，不能拿静态图替实时系统的一般颜色贡献。 |
| 深度 ray march SSR／Metal 光追 | SSR 要完整几何深度并处理屏外、遮挡与透明缺失。光追另需加速结构、动网格同步和硬件资格。当前由作者材质与完成的颜色供货满足首批开关，仅在真实可观测的反射缺口下独立研究。 [屏幕空间射线方法](https://jcgt.org/published/0003/04/04/) · [Metal 光追](https://developer.apple.com/documentation/metal/ray-tracing-with-acceleration-structures) |

**开关和生效** 关闭继续撤普通图像和模型的可选环境采样。作者供货策略只覆盖 `_rt_MipMappedFrameBuffer` 对应的 `.sceneEnvironment`，统一作用于已选的显式和 Shader 缺省槽，保材质与原 Program。关档有实际需求时，由现有环境生产与发布链供应匹配主域尺寸、完整 mip 的不透明黑，按 Surface／尺寸复用其初始化。完成色身份始终由原提交 receipt 授权，黑值走同一 typed 供货入口并保明确来源。无实际消费者时不占用黑值资源，普通关档帧不再申请可选实景快照或编码复制／mip。正档沿原完成帧。保作者持久 raw、`_rt_FullFrameBuffer`、具名目标、作者贴图、独立 Reflection 效果与折射。冷接管和资源不足沿原候选／局部回退边界。 [消费者准入](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneResolvedMaterialFramePreflight+Admission.swift) · [官版判别](#official-reflection-targets) · [现役运行合同](../scene/architecture/runtime-architecture.md#scene-reflection-quality-policy)

关档纹理采用原离屏池的 `r8Unorm` 私有只读附件，完整尺寸和 mip 描述照常保留，Metal swizzle 指定 (0,0,0,1)。无需 CPU 上传、GPU clear 或生成 mip；正档仍使用原色彩格式与真源。M4 Metal API Validation 探针验证奇数 13×7 的非零底层数据，以及 3024×1964／5120×2880 私有纹理的每级实际 read／sample 均为不透明黑。纹理尺寸与级数真实可查询，资源计价仍按原池。该探针只验证设备语义，产品实际绑定与冷热切换另行测量。 [Metal swizzle](https://developer.apple.com/documentation/metal/mtltexturedescriptor/swizzle) · [常量通道](https://developer.apple.com/documentation/metal/mtltextureswizzle) · [GPU 家族支持](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)

可选 `.snapshot` 因关档停产时，由原提交 owner 撤销旧快照的再用与完成采纳资格，原 GPU pin 保到 terminal。重开时先用基础材质，待本次启用后成功完成的快照才恢复。作者声明 HDR 且 `clear=false` 的普通／禁用 SDR 和超高工作域，必需 `.persistence` 沿原收据更新，开档可使用同请求最近合格 raw，包括关档期间完成的 raw，已累计的作者颜色继续保留。两者沿原 receipt 判定，整图 invalidate 会清掉持久／named history，热切应避免。现有提交边界若无法仅处理停产的可选快照，选择「下次应用」或原 Surface 重准备。 [raw 准入条件](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+ClearColor.swift) · [快照资格与完成](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator+SceneColor.swift) · [现有失效边界](../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator+Lifecycle.swift)

**实测验收**以同一素材控制反射率、粗糙度、视角和屏幕边缘，核方向、粗糙度模糊、边界淡出、基础材质和 alpha。令 A 开档红、B 关档绿、C 重开蓝，令关档前的可选 A 晚完成，核停产 `.snapshot` 路径的 C 首帧使用基础材质且后续只采合格新代，加入非 HDR `clear=false` 防止误入持久路径。配对的作者 HDR `clear=false` 场景在同一 Surface 和历史代内验证 C 可采最近合格的 B 持久 raw，必需主色与已有 named publication 依代延续。现役冷切验接管后按新 Surface 成功收据重建历史及拒绝旧快照。混合 Program＋模型验证 B 时保 Program 输出，目标 L0／高 LOD 只供不透明黑，无伪造完成收据，普通材质反射贡献为零。同一黑目标验证奇偶尺寸、分档重载、连续提交与预算不足／恢复，跨 HDR 累积验证原 raw 与 C 复用。补真实显隐、大小与多屏换代、暂停开关、首帧或快照失败、GPU 取消和无环境消费者。数快照、base copy、mip 编码、逻辑与驻留字节、P95／呈现和耗电。混合作品报告部分生效，纯可选作品关档去掉新增环境工作。

<a id="scene-quality-interactions"></a>
### Scene 根采样与资源预约的收敛方案

同一 Surface／请求经一份帧计划决定原生区间和实际资源回退。根采样收敛设计基于现有最终层序与图输入，确定一个原生区间及清屏／颜色前缀进入、帧尾／utility 前 resolve、提前就绪的局部输出。先从原 Program、源需求和层序取得不占容量的计划事实，再兑现选定的根深度和原图目标预约。普通终端与模型共用相机深度，阴影预算先保障此容量，再预约独立影图。原生 pass 的深度测试及写入用片上 D32，纹理读取按自己的真实存储要求。现有清屏、前缀和实验尾段的分开判定随迁移退出。有效采样取具有呈现请求且 GPU 成功完成的根 pass，显示实呈沿原 drawable 回调。原生附件失败沿原 1× 预约顺序；耗尽私有 1× 深度池时，验证只依赖已有原生附件的帧仍能提交，失效反例核原 1× 与同一图票据。新执行实际呈现并获接管确认前保旧输出，源或缓存代际需重准备时走原候选、取消和交接。记录实际代际、显示 ID、逻辑与物理 extent、色深格式、有效档及退回理由。事件只在应用或状态变化时发。针对资源压力验证必需颜色、相机深度和 named/history 能先获容量，低档只撤对应可选工作。

先交付无前置根色读回或具名供货的清屏根域。以最终层序和实际已准备的普通图像／文字／纯色终端状态，检测同域 source-over、深度测试及写入匹配的 PSO；持有合格根色深 pair 才采用原生段，且不预约第二份私有相机深度。关档、规格/PSO 不匹配或含真实独立根消费者时，保原排序及原 1× 预约。前缀方案与早期清屏共用同一根采样计划和真实采样回执。以透明洞、部分 alpha 和深度相交的实际图像验证，补无原生 pair 和 1× 池在途占满的反例。含独立材质图时，清屏计划使用原 capability 的本图输入与最终层序。只有可在当前事务最前生成、不读主附件且终端可直接消费的图输出提前。按现有 utility 的实际触发点结束原生段，允许随后的 1× 根色读取；后续仍消费相机深度时维持原 1×。原生附件或 PSO 资格失败在图池预约前保持原必需 D32 顺序。接纳原生附件后，真实图 bundle 的在途／拒绝仍沿原图事务处理；可局部回退的源按原合格单图出画。原生段开始后的意外中断沿失败终态，避免把不完整的多重采样报成已完成。

<a id="scene-aa-point-volume-tail"></a>
**点光体积末段。** 点光遮挡收集记录已绘制的模型几何、投影和深度状态，独立重放到 1× D32。只有实际点光积分和遮挡存在时，才在原重放入口结束多样本根段，解析到原主色，再以现有 1× 管线加光。撤根计划对收集开关的整帧否决。保原阴影／反射顺序、输出色域、容量归属与局部失败。已有 utility 解析可直接复用。无积分时正常结束原根段。独立深度或 scratch 不可用时跳过体积尾段，已解析主色交原终端。根段或终端自身失效依原规则处理。以具备真实遮挡的作者输入核同一帧根 2×／4×、一次 resolve、独立 D32、四／六点与实际画面。固定相位对照无抗锯齿、关体积及无体积邻例。真实场景另有相机深度或全局环境消费者时继续按原顺序判定，若无实际覆盖改善则退出本片。

<a id="scene-aa-model-reflection"></a>
**模型实时环境与根采样。** 反射所需的上一成功场景色及 mip 在根编码前沿原环境事务供货。模型为已准备的反射混合类型生成请求样本数的 PSO，沿原同域深度、色域、透明混合和槽位读取该环境。两种根入口共用已有模型资格检查。支持反射的 1× PSO 缺少请求样本数版本且实际可绘部件需要时保整个原根域，避免让反射模型落画或悄悄改基础材质。环境首帧缺失或当帧不可用，使用同样本数的原基础 PSO。清屏原生根直接用片上深度，颜色前缀仍保原反射的私有 1× 深度预约，覆盖前缀种色未打开原生段的回退。该预约成功后原生段可能不消费它，私有池忙时仍可延后，本片保原必需深度优先顺序。退役模型反射需求本身造成的整根否决。保普通图像与作者 Program 的环境、具名资源及已打开单采深度前缀的独立契约。真实画面须同时见前一完成帧供货、原生根及实际反射绑定；对照关闭、没有历史及独立真作品，保反射和几何各自的像素结果。

各项与作者 Program 的实际参与范围和最小组合门见[执行合同](../architecture/wallpaper-quality-execution-contract.md#quality-combination-checks)。

<a id="web"></a>
## Web 实施与兼容

**首批实行每屏 FPS 建议。** 现 `applyGeneralProperties` 用 scalar `fps`，按目标屏取 `max(1, min(60, screen.maximumFramesPerSecond))`。缺省保持该行为，用户选跟随后发送规范化的用户值；扩展到 10–120 后仍用同一个数值字段。屏幕与浏览器实际节律约束呈现，Scene 在对应屏幕组合下的有效上限与作者 Web 建议各自由自身消费者处理。沿正式 launch state、当前 adapter/session 与现有 callback 送到已登记主／子 frame，Web 作品的 canvas、WebGL 或作者 JS 可依 elapsed time 控制实际 draw，原官方 API 不提供作品接受证明。 [官方 Web FPS 合同](https://docs.wallpaperengine.io/en/web/performance/fps.html) · [属性监听合同](https://docs.wallpaperengine.io/en/web/api/propertylistener.html) · [当前桥](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift)

1. **投递顺序**从现有 `WallpaperEngine.WebWallpaperRuntimeState`、`WebDaemonLaunch.state` 和 typed command 到 daemon seed 与普通控制 FIFO。候选的启动静音拷贝保有 FPS 投影。更新当前／候选／standby、恢复会话、延迟 launch 及 topology rebuild 的最新值；空预热采用时取实际 launch 值。Web daemon 已退出但退避仍持有已提交会话时，暂停、音量及倍速与 FPS 建议沿原命令更新这份输入。由宿主按是否有可写端点决定是否发送，替换进程的 hello 只取最新输入。同 request 和 navigation generation 接纳，ready 沿原合格条件结算。 [Web 启动状态](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift) · [daemon 输入](../../MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonRuntime.swift) · [会话与恢复](../../MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter.swift) · [延迟切换](../../MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter+SwitchExecution.swift)
2. **初始、热更和重载**文档起始注入为 seed，已有 view 内新 frame、晚注册、reload 与跨源 hello 使用现有快照／回放。实时 hello、DOMContentLoaded 与监听器回放共用同一份文档内属性包。同一监听对象和方法收到这份包的调用最多发一次，作者有副作用后抛错也不重做。仅投递时生成作者可修改的兼容值；后注册或替换方法收到原生当前值。缺 hello 沿原时限使用 seed，随后第一次实时包与 seed 内容相同则复用原包身份。正常热更沿新包投递，不算整包签名。 宿主实际发起主文档 load／reload 前按目标屏用当前输入重新注册原 document-start 脚本。WebContent 自身退出恢复沿原窗口与 WKWebView，种子采用已生效建议及当前暂停，暂停中另存的请求仍到恢复时应用。因此迟到或缺失 hello 仍有正确首值，等值到达沿原去重。只在实际导航准备脚本，实时控制和普通帧不重复注册。 [WebKit 脚本注册](https://developer.apple.com/documentation/webkit/wkusercontentcontroller)同 FPS 下音量、暂停和显示变化仍各自到达。校验 reuse 同一 WKWebView 时旧评估在新文档收到最新值后迟到；若现有文档内 sequence 不足以区分跨文档投递，复用原 endpoint/document nonce。当前 view 内热更；暂停、原生媒体挂起、访问授权、输入、Web 音频／频谱、回调其余字段与浏览器存储继续原宿主合同。 [文档注入](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift) · [按 frame 投递](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+FrameReply.swift)
3. **其它画质**分辨率、MSAA、纹理、后处理、阴影、体积、反射可通过已声明的作者属性和应用内原属性面板操作。活动 WKWebView 公开接口无宿主统一的 FPS／独立 backing render scale；`pageZoom` 的 CSS 缩放、私有 WebKit 开关、全局 rAF／timer 包装或截图播放会改变布局、命中、JS 时序、iframe、CSS/WAAPI 或媒体行为。依旧用真实 WKWebView、原 pause policy 和作者值，热门作品不单列特例。只有官方或作者定义可复用质量合同且实测后才扩大通用字段。 [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) · [pageZoom](https://developer.apple.com/documentation/webkit/wkwebview/pagezoom) · [作者属性](https://docs.wallpaperengine.io/en/web/customization/properties.html)
4. **验收**自有听从设置的 canvas/WebGL 测实际 draw 和可见更新，用忽略建议的 CSS/WAAPI、HTML 视频、Worker 与静态页做反例。检验 60→30→随屏幕，扩展后加 25；主文档与同／跨源 frame 核实一次首次投递。受控延迟解析使实际 hello 或恢复在 DOM 就绪前到达，检查原 view 重载、旧回包、无 hello 的等值与异值、替换回调和作者修改属性副本。另验延迟 ready、崩溃恢复及屏幕热插。终止实际活动 daemon，在替换启动前改档、暂停、音量和倍速。核原请求、新 PID、新页面首个作者回调与恢复前后的可见绘制，另验运行中的替换采用随屏默认，避免把旧显式值或恢复后的热更误算为首值。暂停中连续改值后只恢复使用最新建议，观察同步绘制、解冻、音量与媒体状态。区分作者回调次数、实际绘制、物理呈现与 CPU/GPU/WindowServer 开销；忽略建议的内容作为工作量持平对照。 [Web benchmark 标准](../web/web-wallpaper-benchmark-standard.md)

<a id="video"></a>
## Video 实施与兼容

**默认原片。** 桌面 helper 使用本地 URL、`AVPlayerItem → AVQueuePlayer/AVPlayerLooper → AVPlayerLayer`，App 和 helper 在现有 DaemonKit 换行 JSON 协议中各司其职，系统屏保为独立执行端。原片尺寸和规格按需复用异步详情入口，素材帧率从 track 补读；VFR 仅显示已知的标称值并标明口径。本地 item 已移除仅适用 HLS 的 `preferredMaximumResolution`，仍直接播放原文件。缩 layer、限呈现频率或改变 rate 无法替代压缩素材降规格。 [播放实现](../../WallpaperDaemonSources/Daemon/Playback/WallpaperDaemon+Video.swift) · [媒体详情](../../MyWallpaperX/Modules/VideoLibrary/Core/WallpaperLibrarySupport.swift) · [Apple HLS 限制](https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredmaximumresolution) · [官方 Video 性能](https://help.wallpaperengine.io/en/performance/gpu.html)

| 候选 | 选择与边界 |
|---|---|
| 在线源已有规格 | 优先评估 Pixabay 新下载，服务已有 large／medium／small／tiny 的实际 URL、尺寸和体积。下载弹层用实际可用规格，沿现有 attempt 将选中 URL、预期字节和元数据成套提交，取消/重复任务、重试、磁盘替换和原子发布沿原 owner。浏览卡及详情用默认可选档的尺寸与近似字节。默认维持现有最高可用，缺候选明确重选或继续原流程。已有下载、Steam/本地单文件不自动换源或重下；继续只下载、不抢播。 [Pixabay 规格](../../MyWallpaperX/Modules/Pixabay/Core/PixabayModels.swift) · [下载 owner](../../MyWallpaperX/Modules/Pixabay/Core/PixabayService.swift) |
| 显式派生节能版 | 用同一个 SDR 输入先做原片、仅降像素、仅降 FPS、同时降两者的离线 A/B，全部走原播放器。通过后才提供单个可取消、可清理的可选节能版。尺寸预设优先 `AVAssetExportSession`（用实际输出证明），精确 PTS／尺寸／codec／色彩才用 `AVAssetReader/Writer`，编码沿平台支持。首候选为最多 1920×1080 横向或 1080×1920 竖向的等比例包围盒，按源 PTS 向至多 30 fps 选帧，低帧源保原频率，保持画面完整与比例。保 transform、色彩标记、音轨、时间原点、时长及首尾循环，验证偏差后再选择固定 FPS 或保时基。先覆盖普通 SDR 单视频、零或一条可保留的音轨；HDR10、HLG、Dolby Vision、alpha、复杂 VFR、多音轨留原片并各自取得资格再开放。 [Apple 导出预设](https://developer.apple.com/documentation/avfoundation/export-presets) · [原生 HDR 播放与逐帧处理](https://developer.apple.com/videos/play/wwdc2022/110565/) |
| 解码或呈现重写 | `AVVideoComposition` 可留在 AVPlayerLayer 呈现，`AVPlayerItemVideoOutput` 的自呈现路线另需管理窗口内逐帧交付。两者增加解后处理，较少输出帧无法证明较少压缩帧解码。VideoToolbox 的 reduced-resolution decode 是可选底层能力，需要自行承担解码时序、音频同步、HDR、原生轮换和输出。现阶段采用真实素材文件，保既有 AV 时钟和桌面输出。流媒体将来如有自适应档沿对应 HLS 能力独立处理。 [VideoToolbox 降分辨率解码](https://developer.apple.com/documentation/videotoolbox/kvtdecompressionpropertykey_reducedresolutiondecode) |

派生落地后，质量区提供「原片／优先使用已生成的节能版」，便携偏好只携带这一意愿；作品详情负责显式生成、查看与清理对应文件。现有 Video 执行层在下一次播放时解析实际 URL。产品选择、关系、收藏、恢复、历史、预览与结束事件仍以原始 `WallpaperReference` 为身份。当前 `ended` 结合 request 与 path，派生接线须将执行路径归回源身份后按原合同推进轮换。用来源轻量 revision、转换参数及版本给实际派生键，后台合并同键、单并发、有限字节，暂存后检查真实素材元数据再原子发布。缓存损坏、不可用／磁盘满和转换取消沿原片并显示实际档。删除、路径替换、clear cache 撤销在途发布；在用租约等真实旧 slot 清除或 helper 退出，复用取消回执，复用 helper 缺 slot 释放回执时只补该执行身份的回执。产品退役与发出 finalize 可早于 slot 清除。以后确有即时切档需求时，沿现有同源候选和每屏 cohort、同源 `CMTime`、静音准备及可见确认换档，保旧画面到接管和最新暂停／音量／速度／播放方式。 [执行交接](../../MyWallpaperX/Core/Playback/WallpaperEngine+SwitchExecution.swift) · [helper slot 释放](../../WallpaperDaemonSources/Daemon/Playback/WallpaperDaemon+VideoPreparation.swift) · [结束事件](../../MyWallpaperX/Core/Playback/WallpaperEngine+DaemonEvents.swift) · [系统锁屏独立入口](lock-screen-screensaver-design.md)

收益按实际选中的压缩文件和媒体时基验证。4K60→1080p30 理论源像素/秒约少八分之七，编码器、bitrate、媒体引擎及窗口合成决定实际能耗；测 App、每屏 helper、WindowServer 与整机，核 24／29.97／60、横竖和长 GOP、旋转/色彩、音画同步、loop/ended、跨屏和睡眠。1× 的素材帧率口径须明确，2× 播放速度属于时间控制。Scene 图中的视频、Web 媒体和系统屏保独立验证。

<a id="video-candidate-poster"></a>
#### 同一窗口的候选海报

同一显示器先以「完整显示」持有实际方形视频，再准备带有不同宽高比海报的作品。旧视频在可见提交前拥有包含留黑区的完整原画面。候选静帧属于无当前视频的准备分支。沿 Video helper 已有的当前视频身份分派，不复制候选状态，同窗切换也省掉同步打开和解码海报。空窗海报在原就绪或撤销点清空，随后提交复用已隐藏的层。先用现有原生切换门核旧图层保持、候选失败和撤销。实窗对照在原媒体仍在场时读取画面边栏和中心，用冷启动读到的海报证明候选输入有效。空窗海报与已解码画面用同一填充几何，分别取已解码图像和视频的呈现尺寸。完整显示先等比收进窗口，仅当拟合高度不超过屏幕可见区与窗口的交集高度时按交集竖直居中。首帧海报按原图层在冷打开、热改填充和现有屏幕尺寸更新中重新布局，热改沿已解码图片，不重复打开文件。原生门用满高源和短横幅分别复现上下裁剪及热改偏移，核相同画幅的实际视频、反向调档、原暖切与撤单。 [窗口切换合同](../architecture/playback-lifecycle-transaction-design.md#二可交接确认) · [原生切换门](../../script/tests/ui/test_video_preparation_cancellation.py)

原 M4 WindowServer 窗口在候选尚未就绪时，两侧黑边实测变成 RGB 234／51／35，中央旧视频保持 RGB 130／130／130，共 2,081,840 个窗内像素变化。修复后的 Debug 和 Release 原生 helper 在准备前、准备中和损坏候选失败后，整窗 3024×1964 捕获像素一致。独立 Workshop 3821981384 的 3840×2160 H.264 原片带上下留黑，同样在两个构建的同窗前后逐像素一致。空窗口正常读到红色首帧，原生门核就绪和取消都清空海报图像。Debug 构建通过。本轮用原生 helper 窗口做画面和边界验收，未计音频或物理显示时序。收据归 `.artifacts/wallpaper-quality-video-warm-poster`。 同一 M4 实窗的冷海报前后验证中，方形控制与独立竖片 2974010050 原海报底部均有 47 px 空带。改后竖片的海报和解码画面均高 1964 px、宽 1104 px，边界一致。原生门同测准备期间宽海报的热改及反向调档、屏幕尺寸更新、对象复用、撤单和暖切留黑。全 App Debug 构建及带／无 DEBUG 两组原生门通过。画面和收据归 `.artifacts/wallpaper-quality-video-cold-poster`。

<a id="video-crossfade-luminance"></a>
#### 同窗 Video 淡入的画面亮度

Video helper 复用同窗的两个播放器。原过渡在黑色底上同时淡出旧层、淡入新层。按照图层透明度的合成规则，两份同像素原片中间也可能变暗。先用同一原生 helper 和两份路径不同的相同 H.264，从实际窗口取 A→B→A，核中途和两端颜色。若复现，把原两个播放器的显示层按提交顺序叠放，新层从透明渐显，旧层保完整亮度直至新层覆盖。使用播放器层自身的黑底为作者 alpha 提供现有黑色基底。原构图、位移、缩放与动画时间沿原消费。动画结束时在同一事务隐藏旧层；旧媒体、音频权、取消回滚与实际可见确认继续走原切换票据。沿同一堆叠保海报在下方和频谱在上方，撤出反向透明度动画。

同画幅恒色基线须有两段可辨变暗。以窗口固定中心与内侧区，过渡前后相差至多 2 个 sRGB 码值，旧版至少连续两帧低 6 码。修正后含起止段各至少三次实际采样，任何采到的相邻帧低幅最多 2 码。异色素材应出现连续混合。再验完整显示的不同画幅和留黑、途中取消后恢复旧层、不同槽顺序、首播静帧与可用的 HDR 或 alpha 邻例。用独立真实原片复核实际接管及画面，活动录屏与硬件模式沿现有隔离条件。若同画像素没有可测损失，结束产品变更。 [可见交接合同](../architecture/playback-lifecycle-transaction-design.md#二可交接确认) · [原生窗口采集](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)

M4 内屏同一 WindowServer 窗口以 60 FPS 上限实际采集。旧版两次同像素 H.264 在中段从 RGB 157 降到 118／119，修正后两个方向分别采到 13 和 15 个过渡帧，四个取样区都保持 157。异色从 RGB 157／157／157 逐步过渡到 216／91／142，途中撤销恢复旧片。完整显示缩幅后两侧保持黑色，扩幅时中心从原中段最低 118 恢复为全程 157。提交约 198 ms 后热改回填充屏幕，保最终填充，中心恒为 157，跨过旧层隐藏与 finalize 后四区仍为 157。HEVC alpha 稳定后的完全透明区为黑，不透明区端点与旧版一致，回灰全区为 157。独立 Workshop 3821981384 的原 4K60 H.264 以相同首帧换向两次，各 13 个过渡采样帧中的四区像素稳定，完成确认仍来自原 AVPlayerLayer。连续 RGBAHalf 采样的 PQ＋AAC 片保持左侧 0.590，旧版最低约 0.313。同窗另取 16 位 HDR 端点，两个版本的最亮探针在首播与接管后均为 6.552。连续采集把最亮区限到约 1，过渡中的超白仍待实测。窗口采样核合成输出，物理 120 Hz 的逐刷新、真实声轨输出和热改途中撤销未测。原生首帧、可见性、几何淡入和票据回归及 Debug 构建通过。收据归 `.artifacts/wallpaper-quality-video-crossfade`。<br><a id="video-crossfade-aspect"></a>**混合画幅的过渡几何。** 原先两轴 transform 会把影片内容本身拉到过渡矩形。以各槽自己的宽高比和 bounds／position 动画承接移动。新片起点等比收在旧片内，旧片终点等比收在新片内，首尾画面保持原适配与留黑。动态切换播放器的原生填充策略虽让圆标过门，实窗热改仍出现瞬时换裁切，退出。沿原生播放层的等比填充，切换中热改从各槽呈现几何改目标，保正在淡入的 opacity 和原票据。旧片目标继续收进新片，按现有淡入剩余时间到位。读取者仍以现役 AVPlayerLayer 的可见性确认接管。原生窗口双向圆标检出 14／14 个过渡帧，各有 7／8 帧同时看见两标。原宽高比极值 .364／2.85，现役 .984–1.019。单片热改时 604→222 px 分阶段移动；全屏淡入后约 81 ms 热改的中间负控在旧层隐藏时从 604→336 px，修正后已逐步收至 222 px，跨该时刻持续 222。反向热改中心恒 157，边缘最大偏差 .57 个 sRGB 码。相同影片双向和扩幅的中心恒 157，取消回到上一请求，HEVC alpha 完全透明区呈黑。独立 Workshop 3821981384 与 2974010050 分别为 3840×2160／1214×2160 H.264 60 FPS，照常实际播放，同一窗口双向各采到 28 个过渡帧并正常交接。结果来自团队签名原生 helper 的 WindowServer 采样。物理逐刷新、HDR 超白淡入和真实音轨没有在本批实测。收据归 `.artifacts/wallpaper-quality-video-fit-transition`。 [Apple 视频布局](https://developer.apple.com/documentation/avfoundation/avplayerlayer/videogravity)

<a id="video-import-display-size"></a>
#### 本地导入的轨道显示尺寸

本地 Video 的导入索引目前对宽高向量直接应用轨道矩阵，斜向矩阵会在一个轴上抵消两项，卡片与右侧详情显示的规格不同。导入复用 Shared 已有的轨道显示包围盒及整数格式，先沿一次视频轨道查询，只读尺寸和矩阵。保原时长、文件大小、索引阶段和缩略图准备。导入不额外读 codec 或标称 FPS，不增加缓存、全库迁移或播放路径。没有视频尺寸时仍留空。 [Apple 仿射包围盒](https://developer.apple.com/documentation/coregraphics/cgrectapplyaffinetransform%28_%3A_%3A%29) · [原片轨道事实](../../MyWallpaperX/Shared/WallpaperVideoTrackDetails.swift)

以原导入读取与真实 AVFoundation 详情互验。64×32、正负 45° 轨道应同为 68×68，90° 应为 32×64，未旋转保持 64×32。另验无视频轨与真实 Workshop 原片。保文件大小与时长，同样的原片 URL 继续由播放器使用。由此读取器写入的导入索引使用正确规格。已有完整索引行沿原刷新规则。若仅能修详情或需要新读取链，不接入卡片。

真实轨道对照中，+45° MOV 的导入规格由 22 × 67 更正为 68 × 68，与详情一致。−45° 同为 68 × 68，90° 为 32 × 64，正常横向为 64 × 32，纯音轨的宽高仍为空。独立 Workshop 3834029472 的原片两侧均为 1920 × 1080，同一文件大小、时长和原生提取帧保持一致。斜向素材的 68 × 68 是显示轨道的几何包围盒，原生静帧入口对该素材返回 64 × 32。通过真实导入读取与详情行为门、Debug 构建。读回在原生轨道与索引层，未另测卡片合成或播放器输出。薄收据归 `.artifacts/wallpaper-quality-video-import-size`。 [Apple 原生静帧的方向支持](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/appliespreferredtracktransform)

<a id="pixabay-same-path-source-revision"></a>
#### Pixabay 下载原片换版

原下载内容发布与缩略图沿同一轻量文件身份。等长原子替换可以保留路径和修改时间，旧键因此复用旧规格和旧像素。用一次文件对象观察替换原每文件 URL 元数据读取，键包含标准化路径、设备、inode、字节数和纳秒修改时间。创建／修改时间与目录状态来自同一次观察。仅在跟随链接失败时读取链接自身属性，链接仍以不可用条目发布，其它下载可正常刷新。AV 读前后和缩略图现有阶段继续比较该版本，权限恢复仍按当前可用性触发，旧缓存沿原额度自然回收。以两段实际 MP4 做等长等时的原子替换，刷新后核方向、尺寸、标称 FPS、实画和暖缓存复用。 [现有源发布](../../MyWallpaperX/Modules/Pixabay/Core/PixabayDownloadedContent.swift) · [原生媒体门](../../script/tests/ui/test_pixabay_downloaded_thumbnail_identity.py)

原生实片以相同路径、相同字节数和相同修改时间原子替换，旧版保留 720×1280／2 FPS 与 180×320 竖版缩略图。修复后发布 3840×2160／4 FPS，实际缩略图变为 180×101。无视频轨的原反例保持空值，断链初次保不可用条目，目标出现后重新发布实际轨道。另用从真实 Workshop 3821981384 和 3815201149 读取的原样副本组成两段等长测试输入，经同一目录发布得到 3840×2160 与 1920×1080，各生成一次真实 160×90 图像。换版后的重复请求命中暖缓存，图像内容与旧版不同。证据归 `.artifacts/wallpaper-quality-pixabay-source-revision`。

<a id="video-derivative-audio-timing"></a>
### 派生片保留原音轨与时基的筛查

用两部公开的独立 SDR 有声 4K 素材，空间与时间同时降档组采用 60 FPS，空间组采用不超过 30 FPS 的作品。原始片对照从合法的本地输入或公开清晰源整块重封装，核没有丢包、音视频相对起点和有效末端。候选沿原离线方法，保原颜色和宽高比，只降已超限轴。60 FPS 取每两个显示样本中的第一个，低速及分数帧率维持原有时间；不把音轨用于缩帧、重新编码或回填。

在同一来源、有效片段与同一时间原点冻结下列门槛。输出需要一条视频及一条原 AAC，AAC 的格式参数、每包摘要与相对 PTS／DTS、持续时长及有效 PCM 同源一致。视频须由实际解码验恰当数量、严格递增 PTS 和正确分数步长，首尾边界与原片差均不超过 1 毫秒。沿原同帧参照缩小源，空间和时间候选的逐帧亮度 SSIM 最低 0.97，最后到第一帧的跳变变化不超过 1 个 8 位等效码值。音画相对边界不能增加延迟。漏音、截尾、单独改快慢及拿更长的图去补末端均为失败。沿现有 AVFoundation 原生循环门至少验证候选两次续播，记录计到的媒体时间；该门没有录制声卡输出。

首次筛查只试兼容的实际压缩文件及时间基，先检查不带音、只比名义 FPS 或时长的反例会被拒绝。结果通过后再决定与真实作者长稳 A/B 的同源编码、实际音画输出及一次性转码能量。未达到独立电力门时保留原片。 [公开有声样片](https://learn.microsoft.com/en-us/playready/advanced/testcontent/playready-3x-test-content)

原生候选沿 `AVAssetReader/Writer` 分轨，以原压缩视频样本的有效 PTS 辨认解码预滚与重复首帧。选中帧保共同时间原点、间距及视频末端，在原生缩放后显式提交时间和最后一帧的持续长度。原 AAC 缓冲经 pass-through，保已有裁切与编码延迟附件。先验证已冻结的两部公共样片，再用一部未参与前次筛查的 Workshop 原作作实片邻例。任一时基或音频门失败时先查原生封装的实写结果，必要时试 `VTCompressionSession` 显式时长或 MOV。保留原播放与能耗发布门。 [Apple Writer 样本透传](https://developer.apple.com/documentation/avfoundation/avassetwriterinput/outputsettings) · [Apple 编码时间接口](https://developer.apple.com/documentation/videotoolbox/vtcompressionsession)

只取两部公开片源的开头完整音视频分片，共四个约 1.75–6.03 秒的片段。Big Buck Bunny 的源 sample entry 为 `hev1`，本机 AVFoundation 拒绝解码。实验对照改为 `hvc1` 后解码，视频和音频的压缩样本与时间不变。两侧首个原生解码缓冲报告 BT.709 附件。派生文件沿两部源片各自的 10 位与 8 位。原视频首个压缩样本在 1/30、1/12 秒。强制 CFR 在时间零补出 1／2 帧，改变音画起点，退出。按原片的显示 PTS 选帧，并按相邻画面时刻及原片末端写样本时长。60 FPS 的短片由 120 到 60 帧，24 FPS 短片保 40 帧。Bunny 的长片有变间隔，保 179 个选中时间点及两段 50 毫秒停留。沿用带 B 帧的封装虽然保住影片结束时刻，末尾视频样本仍短 1/60 秒。以无 B 帧编码及显式样本时长验证修正。

四个片段的原 AAC 每包数据、PTS／DTS、样本时长与有效 PCM 均一致。AVFoundation 分组缓冲的个数不同，但实际解码的 PCM 样本、散列及合并后的时间覆盖相同。保留有效音轨数据却推迟 50 毫秒的对照和删轨对照均被拒绝。视频首尾和 MP4 样本时长另用压缩轨验证。AVAssetReader 证实时间零的额外输出缓冲、之后的实际 PTS 和总媒体时长。原生解码的单视频缓冲未附有效样本时长。四组最低亮度 SSIM 为 0.983847，接缝平均亮度差最多多 0.026881 个 8 位等效码值。两部短片各自的原片和候选在现有 Video daemon 门中窗口已就绪并完成两次媒体时钟回绕。

本轮没有测扬声器或物理呈现接缝。保真编码的 Tears of Steel 片段文件大小增约 17%，还需真实转码与播放功耗估算，59.94 等其它源时基另验。生产继续原片；不发布固定帧率或只改文件尺寸的推定档。实测和命令归 `.artifacts/wallpaper-quality-video-audio-timing`。

M4 原生候选使用 `VTPixelTransferSession`、硬件编码请求及 AAC 缓冲透传。跳过无样本的编辑标记，用压缩样本有效 PTS 对齐解码帧，各轨按实际样本末端结算。直接取原始 PTS 使 Workshop 3836065720 首帧从 0 错移至 1/60 秒，全局裁切使原生解码少 838 个 PCM 样本，两个做法均退出。两部公开样片四段和该 Workshop 共五段的所选帧 PTS 与视频包时长符合源时间轴，AAC 包及原生 PCM 与源一致。长 VFR 选中 180 帧，末帧保 1/60 秒。公开未标色片被写入原 AV 解码采用的 BT.709，五段有效色彩附件一致。最低亮度 SSIM 0.977249，按同一位深的原始亮度算接缝，最大差 0.247 码。两部公开短片和 Workshop 的原片与派生各完成两次原生循环，Workshop item 时长相差 0.333 毫秒，签名 helper 的两臂实际出画并退出。丢音和延后 50 毫秒反例均被拒绝。收据归 `.artifacts/wallpaper-quality-video-native-derivative-20261127`；长稳整机功耗、实际出声及转换净能量待测。 [Apple 样本有效呈现时间](https://developer.apple.com/documentation/coremedia/cmsamplebuffer/outputpresentationtimestamp)

<a id="alternatives"></a>
<a id="video-inspector-source-recovery"></a>
### 本地 Video 原片恢复后的规格

详情沿库发布和重新挂载检查当前源。目录的可用性差分从原详情协调器直达原视图，避免「停止播放」等动作仍相同时漏接恢复，也复用后台已查的可用性。若同一路径先被观察为不可用，再恢复可读，原详情视图撤销旧轨道读取并启动一次现有 AVFoundation 读取。同步模板保持可操作，终值在原位替换。路径变化、取消与重新挂载仍沿原任务。视频播放和缩略图各由原消费者更新；详情不轮询、不更改库模型或文件。

验收用同一已挂载详情先展示真实原片规格，再在原路径观察缺失，随后恢复画幅和标称帧率均不同的第二片。核缺失提示、新字段、同一视图、重复发布不重读，以及旧读取晚到不覆盖。另以初开即缺失和相邻正常 remount 为对照。同一路径始终可读的替换沿原后台可见或明确刷新检查，用同一次 stat 的设备与 inode、字节和纳秒 mtime 形成原有资源 revision。目录预发布及已检查的普通模型发布保留同路径版本。协调器见两个已确认版本变化时，将同一详情视图的轨道读取作废，沿原取消和载入得到新规格。首个版本只建立比较基线，未进入原可见检查的卡片可在显式刷新时采纳。保原可读权限、检查范围及活动播放票据；相邻资源变化供已有轮换状态重新评估。屏保保存时仍从当前本地原片重新部署，目录探测的版本只用于比较观察结果。复用原播放器，不增加定时器、缓存或哈希。一次 AVFoundation 视频轨道查询成功后，详情终值只投影当前轨道，当前源确认无视频轨时显示未知分辨率与编码并省略标称帧率。查询失败仍允许显示历史入库分辨率。验同尺寸同 mtime 但换 inode、有效纯音轨换入与视频恢复、旧 AV 后到、详情暂时离开窗口、重复发布与真实作者原片。

同一原生详情先由真 H.264 读出 320×180、24 FPS，原路径失去源后换入 192×108、60 FPS。旧版清提示但保旧规格，修订后原视图和原正文显示新规格。初开缺失和首次读取期间恢复都能更新，重复发布和完成后重新挂载均复用结果；两次被撤销的读取迟到时，只有当前任务可补值。真实协调器同页停播动作状态相等，原视图只收到一次不可用和一次恢复事实。原生窗口内的详情宿主、真实轨道和 Debug 构建通过；协调器综合门仍有初版同样的八个非本片失败。收据归 `.artifacts/wallpaper-quality-video-source-recovery`。在同一详情视图再以有效纯音轨 MOV 原子换入 192×108／60 FPS 的路径。旧版仍显示入库分辨率，候选的分辨率显示未知、移除帧率行且保留可读状态。再换入独立 Workshop 3834029472 原片，同页恢复 1920×1080、H.264 和 24 FPS。缺失及 PNG 的原历史提示由真实 AVFoundation 读取失败反例保住。收据归 `.artifacts/wallpaper-quality-video-no-track`。

<a id="video-hdr-output-proof"></a>
### Video 原片的 HDR 输出验收

Scene 的作者工作域和桌面显示权限独立于 Video。Windows 2.8 的 Scene DX11 是 Video 可选框架。本项目先验现有本地文件的 AVPlayerLayer 原生结果，没有画面问题时无需另加模式、转码或帧输出。设备 `eligibleForHDRPlayback`、原轨色彩标记、WindowServer 实际扩展亮度与真实发光度分别登记。 [官方 2.8 变更](https://steamcommunity.com/ogg/431960/announcements/detail/705520776093106486) · [Apple 原生 HDR 播放](https://developer.apple.com/videos/play/wwdc2022/110565/)

在 M4 XDR 以同一签名 Video helper、相同可见桌面窗口口径分别播放 SDR、已知范围的 10 位 PQ／HLG 测试片及有可信色彩标记的独立外部 HDR 素材。输入按原格式、原轨和内容摘要核对；若外部来自公开分片，只作有界无重编码封装。复用现有 play→prepared→commit→ready→finalize 和暂停恢复。读 ScreenCaptureKit HDR 窗口的线性亮度、超过 SDR 的像素和宿主 PID。正例须见稳定高于 SDR 白点的区域，SDR 须保在基准范围；至少跨一次真实动态更新。先在异档同屏重复排除捕获变动，再看有无可复现的呈现问题。显示实测授权只限本机这一屏、该格式和可见捕获路径。 [Apple 样片](https://developer.apple.com/streaming/examples/advanced-stream-dv-atmos.html)

M4 内屏用同一团队签名的现役 Video helper 走真实可见接管。在同一 PID／窗口依次播放 SDR、10 位 PQ、10 位 HLG、Apple 公开的 1920×1080 Main10 PQ 片，再切回 SDR。ScreenCaptureKit 16 位图在扩展线性 Rec.2020 算亮度 Y。PQ 灰阶为 0.591／1.500／6.552，HLG 为 0.110／0.848／9.852，前后两次 SDR 为 0.047／0.264／0.805，都没有 Y>1.02 的像素。公开素材的 406 个视频包重封装前后内容摘要逐个一致，封装保留 HDR10+ 动态元数据；1× 播放有实窗运动，首捕 Y 峰 3.492、3406 像素超白。用 .25× 拉开同素材的亮段复测，首捕 Y 峰 3.694、近中性超白像素 52351，后续采样也有较暗画面。屏幕当前扩展余量 1.2，窗口的扩展内容值不用于推算物理发光。当前证据支持沿原 AVFoundation 路径播放；屏保、混接屏、Dolby Vision 及 Windows 物理输出仍未实测。收据归 `.artifacts/wallpaper-quality-video-hdr`。

## 超出截图的选项与决策

| 方向 | 采用条件与成本 |
|---|---|
| 固定渲染比例 | Scene 保原生默认。先定位可缩放颜色阶段，再按固定比例与双线性作净收益和视觉对照。获得采用资格才裁决是否显式开放低档。 [固定比例与 MetalFX](#scene-spatial-scaling) |
| 自动省电与热状态 | 首轮优先使用现有前台／全屏／电池／空闲暂停。将来需要「电池降低 FPS」时采用原 policy 现有事件向 cadence 投影并显示有效值；固定、可逆、用户显式选择。自动降纹理、重载资源或多档瞬时跳变的切换成本大，先量到长稳真实收益，再限定迟滞、频率与条件。 |
| 每屏或每作品覆盖 | 现有多屏拓扑、设备能力与属性维持。全局值先验收；只有实测存在混合刷新率／EDR 或用户明确长期需要不同策略，才在原显示/作品 owner 加一个可解释覆盖层。设备测值只产生有效值，便携设置不写物理 display ID。 |
| 粒子、脚本、色彩、缩放 | 作者粒子数量、固定步进、script/timeline、阴影材质和各类后处理拥有各自语义，禁止随预设笼统删减。AV、WK、Scene 各自已有 fit 与色彩路径；显示比例与解码规格分开。库网格、预览帧、桌面静帧与系统锁屏控制另有既存入口。 |
| 平台与依赖 | 优先 AppKit/Swift、Metal、ImageIO、WKWebView、AVFoundation。引入 FFmpeg、另一个浏览器内核、私有 API、第二 renderer 或永驻转码 helper，都会增大发行、原生架构、签名、维护和退出成本。仅当确有竞争方案无解且独立设计验证后才重开。 |

<a id="scene-spatial-scaling"></a>
#### Scene 固定比例与 MetalFX 的采用条件

先处理作者栅格正确性和同规格下的重复工作，再对现役优化构建做 1× A/A 与阶段归因。3749463715 少五次离屏材质，GPU P95 18.298→18.244 ms，实呈仍约 39.8 FPS，作无收益对照。3673609113 保持作者历史规格，阶段重叠不能相加。宽幅 3448845950 已恢复作者局部栅格并减少停用段复制。缺失普通副纹理已沿原冷准备和静态发布恢复活动采样，并复核官版同属性格距与独立作者终图。后续再用现役分支归因实际像素瓶颈。 [副纹理合同](../scene/capabilities/render-graph-shader-coverage.md#missing-ordinary-material-texture) [复测与无收益对照](../scene/capabilities/runtime-evidence-current.md#terminal-main-ablation) · [局部栅格](../scene/capabilities/render-graph-shader-coverage.md#childless-composition-local-effect-raster) · [停用阶段](../scene/capabilities/render-graph-shader-coverage.md#inactive-terminal-source-capture)

普通 Blur 的作者 `fbos.scale=4`、God Rays 的 `scale=2`，分别使用四分之一、二分之一轴长；Blur Precise 使用原尺度。各保作者栅格、`Scale` 调参、mask、核脚印、透明覆盖和后继输入。只对已归因的独占软色中间结果另试可等价的采样路径。God Rays 以 2868108515 和独立 2165492759 的光束、遮罩及定相为资格，保精确同帧输入。Motion Blur、Workshop Bokeh、Shine、Light Shafts 各归其原语义。 [Blur](https://docs.wallpaperengine.io/en/scene/effects/effect/blur.html) · [Blur Precise](https://docs.wallpaperengine.io/en/scene/effects/effect/blurprecise.html) · [God Rays](https://docs.wallpaperengine.io/en/scene/effects/effect/godrays.html) · [局部栅格实证](../scene/capabilities/runtime-evidence-current.md#author-chain-godrays-local-grid)

对已量有资格的颜色通道，0.85× 为首个画面候选，0.75× 为更强的带宽探针，名义减像素约 28%／44%。仅缩放内部通道，保原生 drawable、遮挡、作者历史、具名或精确纹理、界面文字、指针和终端映射。最便宜的单次 Metal 双线性作为基线，Lanczos 可作高质量空间参考。Spatial 在有资格的同样尺寸与正确色域、alpha、传递函数下才竞争。M4 原生探针为 2560×1440 → 3024×1700 创建 BGRA8 感知和 RGBA16Float HDR 两个 scaler，只读 usage。两者输入需 shaderRead，输出需 shaderRead+renderTarget。对现役 framebuffer-only 的 Surface，需可读的输出再走原终端。按 Surface／规格准备，计入 scaler、额外纹理、最终呈现的全部成本。Temporal 须先有可靠运动、深度、抖动、遮挡历史及 reset 合同。Web 沿作者 FPS 建议，Video 沿原 AVPlayerLayer；不引入跨引擎统一缩放。探针归 `.artifacts/wallpaper-quality-spatial-scaler-probe`。 [MetalFX 接线](https://developer.apple.com/videos/play/wwdc2022/10103/) · [Spatial 规格](https://developer.apple.com/documentation/metalfx/mtlfxspatialscalerbase) · [Drawable 限制](https://developer.apple.com/documentation/metal/mtltexture/isframebufferonly) · [Lanczos](https://developer.apple.com/documentation/metalperformanceshaders/mpsimagelanczosscale)

先验真实相同相位的细边、纹理、遮挡、透明度和下一帧，精确域按原图要求，避免清晰纹理或光束随时间闪动。同一机的固定相位原生／缩比例／还原与独立作品全通后，再比较实际 presented、GPU 中位／P95、驻留、换屏和固定时间窗功耗。按既定 A/A 波动、收益与回退门判断。原生分辨率和现有四档保留当前语义，纹理「高性能」仍只选择作者 mip。仅在有净收益、有明确画质代价并符合总体门时评估低档独立选项；其余档保原生。 [性能与画面门槛](#quality-release-gates)

<a id="delivery"></a>
## 评估工作包、工程成本与停止线

各批都可由现有实体任务分工，设置与导入/包协议等共享文件由一个整合者写入。Scene 多项可分开实验；真机性能、VM 和 GPU 取证顺序运行。以下为相对成本，包含行为门和代表运行，机型、素材和官方资格尚影响排期。

| 批次 | 交付与先决条件 | 成本与退出 |
|---|---|---|
| Q0 基线与夹具 | 固定当前 build 和至少一个默认 Scene、一个 HDR/阴影/体积/反射的正例及邻例，Web 作者建议页、Video A/B 源；保存现有 30/60、HDR、三引擎切换与功耗基线 | 中。依真实能力画面建立样本资格，核清观测成本。无法区分画面或机器噪声时先修测量；布局准备可并行 |
| Q1 设置与帧率 | 原面板、导入/复位、Scene 30/60 实际帧节奏、Web 可选跟随、Video 原片适用，回收重复设置入口 | 中。Debug 与正式 App 路由代表场景通过，原缺省及现有偏好无退化，运行中即时设置适用；切换、旧 v8 及暂停实证后可独立结束 |
| Q2 Scene 轻量项 | 依次验证 Bloom、反射、阴影、体积的禁用与现行质量，补普通 Bloom 路径和定向上限 1024。按实际光源、像素和成本扩阴影及体积档 | 中至高。一个控件牵涉的画面与开销分别取证。graph 或资源要求重准备时在下次应用生效，候选失败局部退回 |
| Q3 Scene 规格与预设 | 纹理验证高质量、高性能和自动。帧率先解耦缓存，并扩现有基准 CLI、Debug telemetry 与报告的 FPS 输入，再验证 10–60 及 61–120。MSAA 依 2×／4×／8× 逐档取证，用已验收字段组成预设 | 高。高刷、MSAA 和纹理各有独立收益与停止线。无实际独立差异的预设或档位继续在验证阶段 |
| QV Video | Q1 给现状，已有在线规格与 A/B 可并行；真实功耗、画质、回本时间通过才实现派生。需要即时换档则另做生命周期验证 | 中到高。缓存增长、HDR/loop 回归或实际总能耗不优时原片正式路径收口；下载规格独立判断 |
| Q4 整体验收 | 三引擎与静态图、显示与系统 policy、可访问性、导入、并发切换、恢复、长稳。对声称兼容的选项补官方有界对照 | 中到高。只有实测通过的选项进入发布说明；能力/证据回写原 owner，移除旧设置、废弃 wire/测试和专项顺序 |

<a id="validation"></a>
## 验证与度量

### 最近行为门与运行入口

| 边界 | 现有门或入口与应补断言 |
|---|---|
| 设置、兼容、跨引擎 | 扩 `test_settings_cache_actions` 所用原设置动作入口或等价真实验证、`test_personal_settings_import`、`test_playback_command_multiplexer`、`test_playback_switch_transaction`、`test_playback_switch_endpoints`。核一次变更一次 owner 写入与准确路由、旧数据和复位、候选取消、同时改作者参数、A→B→C、切出再恢复及迟到失败 |
| Scene 帧率与 IPC | `test_scene_daemon_protocol`、`test_scene_frame_context`、`test_scene_paused_frame_recovery`、`test_scene_surface_submission`、`test_scene_daemon_switch_cancellation`。经真实设置 → App client → daemon → timer/GPU/presented 检查 10／25／60／120 及两段边界、设备回退、时间轴和无连续补帧；高刷项在合格设备与混合刷新率反例中验收 |
| Scene 渲染项 | Bloom 扩 `test_scene_bloom_post_process`；纹理用 `test_scene_texture_candidate`、`test_scene_bc_texture_uploader`、`test_scene_raw_texture_uploader`、`test_scene_frame_texture_registry`；阴影用 `test_scene_directional_shadow_frame_owner`；体积用 `test_scene_point_volume`、`test_scene_spot_light_plan`、`test_scene_spot_light_rendering` 及聚光源真实 App 门；反射用 `test_scene_reflection_history_integration`、`test_scene_reflection_history_named_depth`；MSAA 复用 `test_scene_graph_resource_pass_encoder`、`test_scene_static_model_depth_pending`、`test_scene_particle_main_depth`。扩最近真实消费者与正反像素，不复写业务算法 |
| Web | `test_web_system_media`、`test_web_compat_parity`、`test_web_playback_pause`，另走正式进程与导航 `web_runtime_switch_benchmark.py` 和 `web_wallpaper_benchmark.py`；包含首个/最终回调、WebContent 重建、忽略建议和作者实际降绘制 |
| Video | `test_video_inspector_metadata`、`test_video_preparation_cancellation`、`test_playback_visibility`、`test_wallpaper_library_playback`、`test_pixabay_download_transfer`、`test_pixabay_downloaded_content`；沿现有进程隔离基准或正式库入口验证真实格式／PTS、端点收据、尾首音画时间、下一次切换、坏缓存回原片和真实释放。窗口 ready 与实际播放截图／时间采样分别记录。 [进程隔离基准](../../script/web/playback_process_isolation_benchmark.py) |

用 `python3.12 -B script/run_scene_tests.py --module <module>` 选最近门，产品 Swift 变更再跑现有 Debug 构建。先用 `verify_scene_change.py` 预览按 owned path 的门，GPU/生命周期用独立 staged App、HOME、只读素材的隔离副本和新输出目录验证。通过 direct-host 可快速定位，产品声明经正常 App 入口。末次运行后关精确归属的进程，清本批衍生产物，证据只保必要日志与画面。 [仓库验证工作流](repository-workflow.md#并行与验证) · [Scene benchmark](../../script/scene/scene_wallpaper_benchmark.py) · [Scene 性能](../../script/scene/scene_wallpaper_performance.py) · [Web benchmark](../../script/web/web_wallpaper_benchmark.py) · [产物保留规则](../../.agents/skills/mywallpaperx-maintainer/references/artifact-governance.md)

现有 Scene 基准 `--performance-fps` 和转发参数、direct-host／daemon-client 启动、Swift `reset(targetFPS:)` 与报告解析都只接收 30／60，呈现的尾部分位数为多流合计。Q3 先扩展这条同一入口读写合法 FPS，保 30／60 证据兼容。用已有呈现流标识关联实际 Surface／显示 ID，调度与实呈各按实际承诺节奏度量，逐屏输出计数、间隔、漏期和尾部。设备或屏幕代变后开启新测量窗。复用 Debug 观测，发布路径无需每帧收集画质报表。 [基准 CLI](../../script/scene/scene_wallpaper_benchmark.py) · [转发参数](../../script/scene/scene_wallpaper_property_updates.py) · [direct-host](../../MyWallpaperX/App/Debug/DebugScenePlaybackRunner+Performance.swift) · [daemon-client](../../MyWallpaperX/App/Debug/DebugSceneDaemonClientRunner+Startup.swift) · [Telemetry](../../MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneFramePerformanceTelemetry.swift) · [结果解析与稳态资格](../../script/scene/scene_wallpaper_performance.py)

<a id="quality-release-gates"></a>
### 性能与画面门槛

| 发布判定 | 实测条件 |
|---|---|
| **输入与样本** | 每项至少一个能区分错误的自有夹具、一个实际受影响作品、一个未参与调参的独立作品和同域无该能力的负控。先写可观察预期、固定相位／seed、ROI、颜色空间、误差范围和失败判定，保改名、等价表达与相邻反例。源版本、显示拓扑和背板像素、合成比例、属性／音源、系统及热状态固定。优先同优化构建只改一项设置。算法变更需要不同构建时冻结各自构建身份，保相同优化、签名类型与测试参数。 |
| **原样与局部隔离** | 默认保冻结旧版的几何、覆盖、色彩、作者时钟与历史。对可要求精确的 identity、裁剪、alpha／深度、发布与回退用明确断言。光晕、粗糙度、降纹理及积分误差按各项预定的像素／时序容差。逐项验收列明效果损失和允许范围，组合验收验证同帧选择、必需容量、可见接管和相邻效果。 |
| **质效双门** | 降档需让目标阶段 GPU／CPU 时间、可见掉帧、真实驻留或整机能耗至少一项超过同机 A/A 波动，且守画面容差。提升档（如 MSAA、HDR 或更密阴影）可使用更多预算，但须比低档有可重复的独立画面收益且守承诺的帧节奏和资源容量。改档验收包含正常产品请求、实际消费级别与终图或实测资源，不以保存字段和重准备回执结算。至少两份不同作者的原默认播放保有相关能力，记录未改作者功能时的生效范围与退档原因，简化素材只作归因。没有作者投影光、泛光或反射输入时，界面按原会话说明实际无该作用对象。建议 Q0 初筛线为等质改造目标指标中位改善 ≥10%，原默认和邻例的 P95 帧时／可见首帧恶化 >5% 时复核。阈值在读取候选前按输入、机型和实际噪声确认。 |
| **帧节奏与负载** | 记录调度请求、提交、GPU completed 和实际 presented。以有效目标帧率 (F) 计算每帧 (1000/F) ms，30／60／120 FPS 约为 33.3／16.7／8.3 ms。逐屏登记固定刷新量化或可变刷新的实测机会。固定 60 Hz 上的 25 FPS 理想情况下每五段跨 12 个刷新周期，约有三段 33.3 ms、两段 50 ms，排列随相位变。正常量化列入参考。Q0 建议漏期率比同节奏基线至多多 1 个百分点，呈现间隔 P99 至多多一个该屏实测刷新周期，检测噪声较大时在试候选前据 A/A 定线。另对照 CPU／GPU 各自 P95、等待及提交到呈现延迟。预算内仍须逐屏实呈通过。 |
| **冷暖与长稳** | 同机 AB／BA 交替，冷起、暖稳、快速切换和长稳分别取样。45–90 秒可作短探针。Scene 发布级稳态沿已有 AS1 门槛，ready 后预热至少 30 秒，再取至少 60 秒有效窗，建议至少 5 对有效配对。整机功耗声明另用平衡热态的 20–30 分钟，保持同刷新率、实际呈现量和屏数。调档有意减载的节能结果标明对应画质／FPS，等质提速按同画质对照。报告中位、P95／P99、离群和所有失败。 |
| **设备与回退** | 至少验证最低代际 Apple Silicon 与较新代际，记录 OS build、GPU family、实际 sample count／格式、内存和 EDR headroom。覆盖单屏 Retina／普通外屏、混合刷新率及 SDR／EDR、热插、睡醒、供电切换、快速档位往返、暂停中改档、故障回退与退出。同一 PID 分别量 active／candidate／retiring 的高水位与归还，区分临时 display、warm cache 和真正漏掉的租约。缺相应硬件的项保留验收缺口。 |

每个候选在 Q0 登记可执行的通过判据及取样位置。作者语义与生命周期先用确定断言，错相位、错源、漏画、非法覆盖、必需分配失败或应关 pass 仍执行时直接退回。画质变化用相同色域的配对值，改进档须比低档超过重复取样噪声，节能档须低于预登记的最大误差。首轮在固定高对比夹具上可用 1 原生像素作额外边缘漂移的初筛上限，透明细线、灯影有效宽度及柔光范围须按各自参考调整。在看候选截图前冻结容差，并记录失效的作品和设备范围。SDR 和 EDR 先核同一 raw，显示侧用各自正确的输出映射，HDR 验收要保原浮点／高动态范围证据。

定位时用已有 benchmark、Metal System Trace、Metal Resource Events、必要的 GPU pass／内存带宽采样和 Time Profiler。采集帧与 profiler 使负载变化时独立取证，连同空闲桌面／正常播放对照。正式时间与能耗窗口关可选采集。纹理描述逻辑字节、Metal 已分配、资源池计费和进程 footprint 各自记账，统一内存下避免把其中几项相加。Web 加作者实际 draw 与 WebContent／WindowServer，Video 加真实 codec／PTS、音画与一次性转码时间和能耗。派生节能版的回本时间基于有效播放每小时节省。 [仓库性能工作卡](../scene/roadmap/performance-convergence-card.md#measure) · [Apple 性能观测](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app) · [GPU 带宽](https://developer.apple.com/documentation/xcode/measuring-the-gpus-use-of-memory-bandwidth)

<a id="official-quality-evidence"></a>
### 官方对照证据与待验

2026-11-25 读取运行中的 Windows 客户端 2.8.0.42 设置资源，核对四档写入向量、刷新率上限输入和第四档条件。无显示 HDR 支持时界面省略第四档，并把该 UI 状态回落到普通超高。VM 是单路径 120 Hz、8 位 RGB，高级颜色不可用。当前核验覆盖已发客户端设置投影及显示资格，物理 HDR 仍需实际 HDR 设备与保留高动态的取证。 [官方显示 HDR 公告](https://steamcommunity.com/games/431960/announcements/detail/3133943554973045545) · [同版 Main renderer 响应证据](../scene/capabilities/model-runtime-evidence.md#model-hdr-emissive-gain)

| 官方 2.8.0.42 预设 | FPS | MSAA | 后处理 | 纹理 | 阴影 | 体积 | 反射 |
|---|---:|---|---|---|---|---|---|
| 低 | 10 | 无 | 禁用 | 高质量 | 低 | 低 | 关 |
| 中 | 15 | 无 | 启用 | 高质量 | 中 | 中 | 开 |
| 高 | 25 | ×2 | 启用 | 高质量 | 高 | 高 | 开 |
| 超高 | 30 | ×2 | 超高 | 高质量 | 超高 | 超高 | 开 |

<a id="official-live-quality-refresh"></a>
#### 已运行桌面的冷档刷新路径

固定 2.8.0.42 的 `wallpaperui.exe` 把 `applyGeneral` 送为消息 `0xc9`，本机同版 Win32 接收端从 `0x4250b8` 进入 `0x416a50`。比较函数 `0x439b70` 读取 MSAA、纹理分辨率、后处理的新旧值，三项差分共进 `0x43a0b2`。原路径在 `0x416c3c` 调 `0x451630` 清理正在使用的壁纸对象，再由 `0x416c41` 调带 `ApplyRefreshWallpaperConfig` 标记的 `0x416890`，后续读取 `selectedwallpapers`。这条普通桌面的原生自动刷新由编辑时的投递触发，具体时序、首帧、作者时钟和预览窗口继承仍待运行验证。SHA、消息表和三处分支随本机薄收据 `.artifacts/wallpaper-quality-official-cold-refresh` 保留。共享 VM 未操作。

<a id="official-web-fps-window"></a>
#### 具名 Web 预览的建议值与绘制

用固定 2.8.0.42 的公开窗口 CLI 装载一个本轮自有 Web 探针。只读当前普通桌面配置中的 fps，保 receiver、全局设置和原壁纸；不尝试用作品 `applyProperties` 模拟全局 `applyGeneralProperties`。查首次回调数、类型与建议值，并用同一个 `requestAnimationFrame` 循环分别记采纳建议和忽略建议的 Canvas 绘制。取至少两个大于两秒的前景观测窗，记录实际时间、绘制、rAF 和像素标志。当前建议低于 rAF 时，采纳侧应收敛到建议值浮动 ±1 帧每秒，忽略侧接近 rAF；两者饱和时只结算实际建议和可见绘制。只用具名打开、查询、关闭；窗口或运输不能隔离即保留未验证。末尾复核确认原接收进程、桌面输出和画质意图。热改全局值、桌面继承与物理呈现另行核对。 [官方 Web 建议](https://docs.wallpaperengine.io/en/web/performance/fps.html) · [具名窗口命令](https://help.wallpaperengine.io/en/functionality/cli.html)

先核固定客户端身份和现有 25 FPS 保存值。用完全相同的自有 `index.html` 在本机非持久 WKWebView 跑生产的 Web 兼容桥及帧属性入口，25 由夹具绑定的 adapter 提供。首个 rAF 前收到一次数值 25。在 840×440 CSS 视口，两段 3.016／3.000 秒各有 181／180 次 rAF 与 76／75 次按建议绘制，段内最长回调间隔为 19 ms。两窗结束后读取一次 Canvas 的橙色和蓝色标记，1680×880 的 WebKit 快照完整显示两条路径及同一组读数。回调、作者画布和 WebKit 输出均已取证，物理呈现仍单独测量。本机薄收据归 `.artifacts/wallpaper-quality-official-web-fps`。

固定 2.8.0.42 的 Win32 同次运行以公开命令装载摘要相同的 `index.html`，前景具名窗实绘完整码板和橙、蓝标记。数值 25 在文档完成、第四次 rAF 后到达一次，两段 3.009／3.000 秒各有 356 次 rAF 和 75 次按建议绘制，约 118.31／118.67 与 24.93／25.00 次每秒。保存值与两端的启动回调一致，浏览器调度和作者绘制各自独立。CLI 可用但具名 `getWallpaper` 未返回路径，Parallels CLI 在弹窗播放时截图全黑。本次官版读数来自无遮挡的原生控制台图像转录，未取得可逐像素重放的官版 PNG。关闭具名窗后原 receiver、配置文件摘要、选中壁纸摘要和被覆盖的桌面区域像素一致，客体副本已清理。全局热改、普通桌面继承和物理呈现继续独立验。Windows 实测收据归 `.artifacts/wallpaper-quality-official-web-fps-live`。

<a id="official-scene-preview-bloom-clock"></a>
#### 具名 Scene 预览的帧时钟与普通 Bloom

以固定 2.8.0.42 同一 receiver 和保存档打开自有 Scene。两臂使用同一 960×540 作者画布及 CLI 尺寸请求，保全局配置，在两个具名臂中只改作者普通 Bloom。静态白块、远离光晕的独立色块及清除背景作画面控制。预登记观察白块边缘外同轨 4–12 个像素范围内的可见光晕，关闭臂背景应为黑。开启臂若光晕未区分，先核真实作者资源和当前窗口，再停于鉴别失败。同时绑定一个 SceneScript 文本探针，以墙钟时长、`engine.runtime` 差值和实际 `update()` 调用数作证。预热至少 1.5 秒，连续两个至少 3 秒的同文档窗口，两臂应有可见字样和递增时钟。25 FPS 的可比作者节奏门先取 24–26 次更新每秒，若实际超过则记录预览路径差异。脚本节律、可截图画面和物理呈现分别计。只清本轮的两个具名窗和临时输入。 [官方 SceneScript 更新](https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/update.html) · [官方泛光](https://docs.wallpaperengine.io/en/scene/effects/bloom.html)

固定 2.8.0.42 的 Win32 同一接收进程以公开 CLI 开启两份自有 960×540 Scene。两份输入的有效场景声明只差普通 Bloom，作者 HDR 均为关。保存值为 25 FPS、普通后处理；未写全局档。关闭臂两段各 75 次更新，墙钟为 3008／3011 ms，约 24.93／24.91 次每秒。开启臂各 75 次，墙钟为 3013／3014 ms，约 24.89／24.88 次每秒。四段分别显示与墙钟等长的 `engine.runtime` 差值和累计 `engine.frametime`（毫秒舍入）。开启臂原生控制台中，白块轮廓外出现可辨光晕，蓝块中心仍可辨且周围有蓝光，远处背景保持黑。两次查看间作者时钟显示从 `CLOCK 8` 到 `CLOCK 13`，绿块位置随之改变。关闭臂同一白块轮廓外未见光晕。单次保存值只可证明此具名预览的实际作者节律与 25 一致。观察来自原生控制台图像转录，未取得可逐像素重放的预览图，也未量测光晕宽度、亮度或逐帧呈现。全局热改、普通桌面继承、后处理禁用／超高、HDR 和物理呈现须另测。原接收进程、配置和原壁纸摘要一致，预览覆盖区与原安全启动窗的两个固定矩形恢复到相同像素。具名窗关闭，客体两套输入和生成的 shader 缓存已清理。本机薄收据归 `.artifacts/wallpaper-quality-official-scene-preview`。 [具名预览命令](https://help.wallpaperengine.io/en/functionality/cli.html)

<a id="official-texture-resolution"></a>
#### 官版纹理基级与合成范围

固定 Win32 2.8.0.42 的界面将高质量／高性能／自动写为 `generalSettings.resolution` 的 `full/half/auto`。`0x4de3eb–0x4de453` 映射至位域 0／0x20／0x10，`0x4de850` 写到 Scene。内层 `0x52c4e0` 得出全／半，Auto 会比较字段面积与 1,969,920，另一个标志路径比较两组面积与 3.9 倍。适用的真实 TEX 调用将 `0x533da7` 写入的因子 1／2 变成 `0x515986–0x5159cd` 的 0x4／0x6。TEXB4 reader 在 `0x5138cf–0x5139f8` 根据新增 0x2 位、mip 索引为 0、该图超过一级作决定，按存储长度越过 L0 并绕过其解码。单 mip 输入仍载入 L0。该处不看尺寸或用途。跳过后如有 TEXS，`0x514ca0–0x514d01` 将三对 sprite 坐标乘 0.5。随包雨滴色图与折射法线均为 256²、七级、16 帧，收到同一 0x6 的通用调用时都符合这段条件。上游预缓存顺序、真实调用及 GPU 建图结果待分用途运行核对。

帧端 `0x52d6d8` 独立计算分支。部分内容在 `0x52e13f` 经同一虚调用的两轴尺寸乘 2，之后 `0x52e36c` 恢复。随包组合材质引用 `_rt_FullFrameBuffer`。已追踪的 `WM_SIZE→0x52cfc0→0x52d30f` 创建使用传入的客户区尺寸，`0x52d012/15` 保存工厂后续消费的宽高。当前只确认两条静态消费，整场主色半尺寸或所有用途统一降档仍待实际 D3D 目标与画面核对。保留本机现役逐源策略。下一试验在已准入的过 4096 真实色图 1695673397/12 和独立 3355255518/54 对照只跳一级与现役长边上限，后者的一级规格已有 Auto 真画面。记录原布局、相邻精确用途、细节和实际 Metal 容量，核可见收益及帧时与驻留开销，再决定是否调整。Windows 固定相位对照同时登记无纹理几何斜边、TEX 物理基级、主色与组合尺寸，用来区分素材降级和主域缩放。薄收据归 `.artifacts/wallpaper-quality-official-texture-resolution`。 [WM_SIZE 客户区尺寸](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-size) · [本机现役策略](#scene-texture-quality)

<a id="official-shadow-atlas"></a>
### 官版阴影图与比较滤波

Win32 2.8.0.42 从 `0x4d9280` 读取 `shadows`，禁用／低／中／高／超高对应 0–4，缺省或不识别值为中。值经应用 `+0x190`、打包配置 `+4` 和渲染字段 `+0x178` 到 `0x548105–0x54817c` 写入 `LIGHTS_SHADOW_MAPPING_QUALITY`。档位尺寸助手 `0x5e16d0` 返回低／中／高／超高 256／256／512／1024。定向路径在 `0x53a60c` 取值，`0x53b0ce` 分派三次级联插入，`0x53cb29–0x53cb39` 将边长填入每一级的宽高。点光在同一个 atlas 内用 2×3 视口组，`0x53c899–0x53c8bc` 分别将该边长除以 2 和 3。整个 atlas 由随后打包决定。本项目使用单张自适应定向图、3×2 点光 atlas 的六个方形面和单张聚光方图，档位尺寸须按各自接收区比较。

随包 `common_pbr_2.h` 第 74–115 行对低档发一次深度比较采样，对其它启用档发九次等权比较。D3D11 atlas 从 `0x53b48d` 传标志，经纹理工厂到 `0x476c50`，在 `0x476d10–0x476d9f` 建比较线性 `0x95`、零边界、`GREATER` sampler。硬件对邻近 texel 的比较结果作滤波。此证据给出固定版本随包代码与原生路径，运行时变体选择、实际可见画面、热切换和 Windows 驱动表现待单项运行核对。本机在低档 512 上用原接收面逐 tap 语义比较。一次 gather 未通过细影与亮孔相位门，现役低档继续采用三 texel 滤波。 [滤波枚举](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/ne-d3d11-d3d11_filter) · [比较采样](https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl-to-samplecmp) · [本机计划](wallpaper-quality-work-card.md#scene-shadow-low-filter)

<a id="official-volume-shader"></a>
#### 官版体积照明的静态边界

本机参考安装的 32 位执行体 SHA256 为 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`，与前述 2.8.0.42 运行收据一致。设置项从 `generalSettings.volumetrics` 写到原 `general.user.volumetrics`，值为 disabled、low、medium、high、ultra。随包 `volumetricsfront.frag` 的等距线段采样提供两套变体。阴影或投影纹理组在缺省、2、3、4 的步数分别为 12、24、32、64，其他组为 2、3、5、8。阴影分支另用屏幕相位偏移。样本依据世界空间衰减等权累计，步数不能直接换算为本项目的分段四点／六点积分。

普通几何从正表面开始，全屏顶点变体把起点放到近面。前片元从后界深度及限制深度截断射线路径。随包横纵滤波分别读两张光缓冲，三点权重 1/4、1/2、1/4，合成从主光缓冲加到原画。

同一文件的 REA／Ghidra 与 x86 短窗验证到 32 位 D3D11 冷准备。解析 `0x4d9280` 得到禁用、低、中、高、超高的 0／1／2／3／4，其中中档使用默认 2。配置适配 `0x4dcd30` 写应用对象 +0x191，`0x4dae83` 搬到打包初始化参数第 5 字节，`0x52a7c5–0x52a7d3` 最终送渲染上下文 +0x179，前材质 `0x5e2bf8` 用该值编入 `QUALITY`。设备初始化请求 11.1、11.0、10.1 和 10.0；已追踪的成功分支只在前三种置能力位，能力位清除时会将档位置 0。在允许分支，低至超高的非阴影／非投影纹理变体为 2／3／5／8 步，阴影或投影纹理变体为 12／24／32／64 步。 [原版灯光控制](https://docs.wallpaperengine.io/en/scene/models/lighting.html) · [D3D feature level](https://learn.microsoft.com/en-us/windows/desktop/api/D3DCommon/ne-d3dcommon-d3d_feature_level)

首次准备为非零档时，低／中把主光、限深和第二光缓冲的每轴除以 8，并准备横纵滤波。高／超高把主光和限深的每轴除以 4。后界除数均为 1。工厂 `0x54b240` 经实际 vtable 到 `0x477740→0x4a9830`，将初始渲染 client 宽高逐轴整除、下限 2，再把结果填入 `CreateTexture2D` 描述。以 1920×1080 渲染窗口为算例，主光与限深在低／中为 240×135、高／超高为 480×270。限深目标另外传 0x17／0x19，含义未取证。证据限定此 Win32 冷路径。窗口 DPI 与实尺、实际选中的灯型变体、目标创建成功、热切换和最终画面仍需要单变量运行取证。薄收据归 `.artifacts/wallpaper-quality-official-volume`。 [D3D11 纹理描述](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/ns-d3d11-d3d11_texture2d_desc)

<a id="official-reflection-targets"></a>
#### 官版反射开关下的三个取样来源

固定 Windows Win32 2.8.0.42。随包界面投影为单数 `generalSettings.reflection`。同版原生 `0x4de3c7–0x4de3f5` 解析 `reflection`，`0x4de91a` 写渲染状态 `+0xfc` 的 0x80 位。`_rt_Reflection` 和 `_rt_MipMappedFrameBuffer` 是两个附件，建立条件分别读取同一作者准备状态的 bit 0 和 bit 11。前者由 `0x52e92a–0x52e97d` 管理，在 `0x52dc80–0x52dc8f` 另读全局档选择反射视角绘制或清除分支。后者在 `0x52e97d–0x52ea89` 管理，关闭档传零 RGB、alpha 1 给清除路径，已有附件在 `0x4de874–0x4de906` 同样处理。帧端 `0x52e10a–0x52e128` 和 `0x52e237–0x52e255` 另要求开档。已核 D3D11 后端虚表 `0x7d644c` 的 +0x04 在适用源上调用全资源复制或 MSAA resolve，+0x10 调用 mip 生成。 初始清除或关档刷新成黑时，也可调用同一 mip 生成入口传播清除值。材质实际选中的 texture slot 入口 `0x50f610` 把标准目标表的位合并到材质 `+0x170`。`0x595fc9–0x595fe5` 以其中 bit 3（MipMapped）写入该材质路径的 `REFLECTION` 编译组合。全局设置另在 Scene 端控制附件生产。该观察限此固定二进制的已追踪 D3D11 渲染路径。 [D3D11 复制](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11devicecontext-copyresource) · [MSAA resolve](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11devicecontext-resolvesubresource) · [mip 生成](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11devicecontext-generatemips)

随包 `generic2` 默认反射读 `_rt_Reflection`，`generic3/4` 及 `genericimage2/3/4` 默认反射读 `_rt_MipMappedFrameBuffer`。后面三种图像 shader 的部分组合还单独读 `_rt_FullFrameBuffer` 作合成，保留该身份以区分两条消费。作者的独立 Reflection 特效沿标准 pass 的颜色输入和 mask 按轴取像素，随包默认无上述两种反射附件绑定。独立场内显式绑定仍按实际资源核对。此前 3470948192 在原官版的开／关／开改变模型轮廓，参数相位和尖端的像素还未配对。 [官版 2D 材质](https://docs.wallpaperengine.io/en/scene/lighting/introduction.html) · [作者 Reflection 效果](https://docs.wallpaperengine.io/en/scene/effects/effect/reflection.html) · [已有作者对照](../scene/capabilities/model-runtime-evidence.md#model-screen-reflection)

官版 2.8.0.42 同一第三版具名色板完成原设置面板开／关／开。窗口重开后，显式历史目标随关档呈不透明黑并随开档复原，普通反射也随之退出和恢复。同帧前缀与自带贴图保持。热改观察有独立时间窗，适配沿本机现有冷接管。该证据确定 `_rt_MipMappedFrameBuffer` 的供货边界。精确尺寸、物理 mip 层数、上一帧年龄、`_rt_Reflection` 的作者显式访问和桌面热切仍各有独立资格。 本机 985 个可读作者包、1,868 个松散文本无 `_rt_Reflection` 或 stock debug 材质显式引用，实际绑定对象的五个 generic2 材质均未启用反射。双包与显式探针已封装回读，归 `.artifacts/wallpaper-quality-reflection-view-probe-20261126`。先验证其独立视角与历史 mip 均非黑且可区分，再做官版开／关／开。 [开关与像素实测](../scene/capabilities/runtime-evidence-current.md#official-reflection-toggle) · [公开 CLI](https://help.wallpaperengine.io/en/functionality/cli.html)

改造前的签名 M4 画面对照中，普通反射接收区由 RGB 179／128／128 变为基准灰，显式槽 3 与 Shader 缺省槽 2 在关档仍从上一完成帧采晚层红。现役在这两个槽供独立不透明黑。随包 Reflection 无遮罩、普通混合的红蓝上下镜像在两档均实际画成蓝／红，旁置原图在两档均为红／蓝。独立的透视图以 `_rt_FullFrameBuffer` 在 layer 20 槽 0 读取同帧前缀，后继 Program 和遮挡继续接原主域。两档五处固定探针均命中原色预期，归属同一构图收据的实际捕获均完成。 [完成帧与作者效果验收](../../script/tests/scene/test_scene_authored_environment_integration.py) · [同帧前缀验收](../../script/tests/scene/test_scene_native_world_composition.py)

独立作者 3465215190 在两档均由原 layer 123 槽 0 取图层颜色，同一 Reflection Program 实际出画、进合成并排空。作者 3228084178 在两档的四张捕获均记录 layer 192 的 Reflection 实绑前序效果颜色和包内 `mask` 槽 1，末端消费和 GPU 已完成。两部作品未锁定动画相位，受控无罩画面负责判断像素上的档位差。颜色板按实际作者包提供同样的效果定义、材质和 Shader。只带定义的起始夹具复现随包材料路径缺失，解析器按材质的原虚拟路径查找。2026-11-26 本机库直下的 984 个 `scene.pkg` 中，实际引用这一定义的 13 个均有根路径资源，暂不调整通用资源查找。

<a id="official-global-ab-isolation"></a>
独占 Windows 执行环境可使用同版已购客户端目录和本地壁纸走官版正常性能面板。先核二进制摘要、选档可正常保存并重启、同一素材在桌面与具名窗均真实出图。桌面及具名窗的冷继承和同接收进程热改分别做 A/B/A。源客体关机时已用 Parallels 完整克隆取得独立虚拟磁盘和 UUID，源配置摘要一致。副本待做会话、离线客户端和采集资格验证。物理 HDR 另要求 Windows HDR 模式、实际出现显示 HDR 档及保留高动态的 FP16 采集，以参考白、灰和超白作对照。独占接收或有效采集无法成立时，继续采用已取得的单档和静态证据。 [官版离线运行 FAQ](https://www.wallpaperengine.io/en) · [Parallels 完整克隆条件](https://kb.parallels.com/en/123907) · [Windows HDR 采集](https://learn.microsoft.com/en-us/windows/win32/direct3darticles/high-dynamic-range)

锁定合法安装的 Windows 版 Wallpaper Engine build、位数／版本、系统／GPU／显示、全量设置和自有输入，先记录四预设逐字段向量，再测单项改变、选择另一作品、重启、按屏及运行中的生效时机。帧率记录 10／25／60／120 及输入步进、上限与显示节律，MSAA 在设备允许时用几何斜边、遮挡和纯 2D 反例逐档对照。后处理用作者普通／HDR 开关组合和实测三档相互验证，纹理以含 mip／无 mip／图集、阴影以三类灯、体积以点光／聚光、反射以实时接收与静态对照验证各档。另让相同 Web／Video 输入读取或播放，核影响面。每次只改一项，固定可见 ROI、捕获身份、色域、DPI、动画相位与 pause；预览如未采用桌面质量配置，验证其会话或改用有界桌面窗口。VM 采行为，Mac 功耗真机另测。

如固定版本的公开/可见实验无法区分「候选设置确实被该 consumer 读到」等问题，先用现有 locale/changelog 结构提取，再按官方研究工作流选择 REA 对单一设置写入→读取关系作有界静态研究。保留版本、证据位置和可观测预测，随后用单变量运行反证；解析结果只作线索，最终行为仍取实际画面与事件。此轮补固定版本随包资源及 REA 静态定位。共享 VM 保留原设置和会话，后续实际开关实验在独立副本进行。目标档的行为和 macOS 整机功耗仍各自取证。 [官方研究与保留规则](../scene/development/official-client-behavior-research-workflow.md) · [结构提取工具](../../script/evidence/extract_wallpaper_engine_client_evidence.py)

<a id="retirement"></a>
## 退役与完成判定

Q1 落地时统一设置入口、迁移和导入路径，后续用初始默认、相邻无影响例与独立作者移除被替换的 prototype、空档、旧入口和临时双写。Scene 的长期策略、Web 的作者桥语义、Video 的素材执行规则分别交原合同；Scene 能力缺口和运行报告依旧交开放队列和证据索引。官方未知、被停止的昂贵候选和缺覆盖的硬件保留明确收据。专项的退出条件是每个拟交付选项都能从原设置到真实消费与用户可理解结果，余项有证据或清楚退出；发布、提交和推送依当时授权。
