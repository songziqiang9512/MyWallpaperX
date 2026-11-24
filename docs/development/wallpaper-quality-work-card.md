<!-- document-role: active-plan -->
<!-- retirementCondition: 完成各引擎画质纵向链、实际退役与验收，稳定规则交现有合同后撤除工作卡。 -->

# 三引擎壁纸质量改造工作卡

<a id="execution"></a>
## 当前批与接手步骤

从主工作树 `codex/engine-refactor-program` 的 `b2b80f892` 建 `Fluxo/wallpaper-quality-settings`。评估方案给技术取舍与失败判据，本卡维护唯一执行顺序与当前批。开工核对分支、实际 diff 和上批证据，从原设置行为追到真实运行消费者。 [算法与技术设计](wallpaper-quality-settings-plan.md#decision) · [源码地图](../architecture/repository-map.md#wallpaper-quality) · [验证工作流](repository-workflow.md#设计判定与记录)

**当前推进 Q2 阴影**。泛光四档已接通，两个超高档在 M4 XDR 验了 SDR／EDR 输出、旧值迁移和暂停重导出。禁用与启用验证了光晕像素差、作者 HDR 场景降档后累积保留、独立作者作品可达真实呈现。显示 HDR 的实际混合显示拓扑及官方普通缺省仍待取证。接下来闭合阴影开关及一档降预算，再处理体积和反射。 [Scene 技术裁决](wallpaper-quality-settings-plan.md#scene-post-processing)

Q0 已取得 M4 上基线源码的独立 Metal 泛光和映射结果。Q1 从 App 偏好写入入口把帧率与 Web 模式投影到实际端点，Scene 保原缓存档，Video 保原片。已验签名隔离 Debug 的 30／60 真实呈现、实际 WKWebView 投递、候选端点、导入复位和独立复核。复杂作品的 60 FPS 与长稳功耗仍按 [实测门槛](wallpaper-quality-settings-plan.md#quality-release-gates)验证。每批冻结源码后跑最近门和独立审查，只提交本批文档、源码与测试。

1. 以原设置窗、Scene 30／60 IPC、Web 投递和 Video 原片作为基线，用现有 Debug 构建及最近行为门。涉及真实输出的批次再用隔离 App、HOME、素材和输出目录，对照首帧、改档、暂停、恢复与换屏。
2. 先落 typed 偏好、旧键读取、v8 字段导入和显式复位，再接原 AppKit 控件和实际消费者。现有缓存行为持续到 Q3 实测解耦，兼容性断言覆盖没有新字段的文件和未完成的恢复票据。
3. 一次改一个可验证的质量字段。查当前容量、帧边界和准备代，先闭合禁用／原画，再验证新增档。发布档位以真实收益、相邻作品和回退经验证为准。
4. 代码接通后同步该事实的稳定合同、源码地图、配置入口和最近验证。批次状态与下一步只更新本卡，样本结论写原能力或运行证据入口。收尾注明真实通过项、欠缺硬件和合理退出项。

## 分批完成条件

| 批次 | 顺序与交付门 |
|---|---|
| Q0 基线 | 固定当前原版行为，取得各效应正例与邻例、逐屏 30／60、Web callback、Video 实际片源数据。冻结画面取样、成本与噪声门。 |
| Q1 设置 | 原生设置区、迁移、导入和复位到 Scene 实际上限、Web 每屏建议及 Video 原片适用说明。验证候选、晚注册、错代和恢复。 |
| Q2 Scene 可选效果 | 先处理场景泛光和 HDR 后处理路径，再依次验证反射、阴影、体积的禁用／基线。后续档由实测推进。 |
| Q3 Scene 规格 | 解耦帧率和缓存，贯通基准入口与逐屏口径，先验 10–60，再验 61–120。接入纹理质量和可选 MSAA，按已验证项组成预设。 |
| QV Video | 接入当前素材规格说明，评估来源规格与同源离线 A/B。真实素材和播放成本成立时推进节能版，保原播放器、音画与原片退出。 |
| Q4 整体 | 正常入口与多屏／生命周期、导入、相邻不适用例、真机质效、官版适用范围。交接稳定合同、退出临时状态和验证入口，结算全部批次。 |

## 官方对照和 HDR 决策

逐项记录实际官版 build、窗口模式、作者输入、用户档、显示与可见结果。先查官方文档和已有证据，再用合法已安装的固定客户端做单项 A/B。需要静态材料时只跟踪能区分行为的具体设置到消费者，以独立运行验证。Windows VM 说明行为，Mac 真机说明像素格式、呈现和功耗。 [官方研究工作流](../scene/development/official-client-behavior-research-workflow.md) · [固定版本证据与待验矩阵](wallpaper-quality-settings-plan.md#official-quality-evidence)

官版「启用／超高」控制作者普通泛光与 HDR 过亮，编辑器预览自有规则。2.8.0.42 确认物理 HDR 由「超高（显示 HDR）」选择，无支持时界面回落为普通超高。MyWallpaperX 把旧开关迁入该后处理档，显式旧开映射到显示 HDR，显式旧关和未保存选择映射到普通超高。后一种保作者 HDR 画面，物理显示 HDR 改为主动选择。保留显式请求，按屏能力和当前 headroom 映射，非适用屏沿普通超高输出。配对验收真实 HDR、HDR 主屏加 SDR 屏、关闭／重开、`clear=false`、旧导入恢复和缺省复位。接管后退出旧开关、通知、跨进程同步和它的无消费者测试。 [官方 Bloom](https://docs.wallpaperengine.io/en/scene/effects/bloom.html) · [官方显示 HDR 公告](https://steamcommunity.com/games/431960/announcements/detail/3133943554973045545) · [Scene 渲染合同](../scene/architecture/runtime-architecture.md#effective-quality-policy)

Q2 先在原准备入口引入有效后处理投影。普通档和禁用档沿作者基础素材及原 source 顺序，普通档只处理普通泛光。超高与超高显示 HDR 共用同一作者工作域、粒子／文字／材质亮度和终端 Bloom 准备；显示档才申请 EDR。禁止只修改终端开关而遗漏作者过亮的直接、捕获和具名输入。冷热变更沿实际用途区分，只有工作域或资源变化才经原候选重准备。先用单输入实证颜色与效果，再开放其余的可选效果和档位。

首片先落实两种超高档。新增值加入现有画质记录，旧 bool 只读迁移，便携载荷优先新字段，缺省新字段才采合法的旧 bool。App 仅在请求变更发一次 Scene 命令，启动与恢复采用原 Scene wire。原 Host 保最新意图，候选、恢复会话及换屏交给原 Surface。切档只更新每屏 EDR 申请和必要的冻结帧，复用既有颜色映射、GPU 资源和时钟。受控夹具要求验证旧／新导入、正常／暂停切换、SDR 反例和取消候选。 [Scene 质量策略](../scene/architecture/runtime-architecture.md#effective-quality-policy)

### 禁用与普通泛光的实施片

1. `loadScene` 采纳请求时由原 Host 固定准备档。穿过已有 Model／SourceFacts 准备入口，将有效 HDR 投影给对象解释和渲染 descriptor。保留作者原始 General、属性和脚本输入。超高与显示 HDR 沿同一已准备工作域热更，跨工作域显示下次应用生效，由原候选和可见接管承载。
2. 禁用跳过全景 Bloom 的 PSO、资源和编码。启用走普通分离模糊。两档的专用 HDR 增益沿实际消费者撤出，核对粒子实例、文字、静态模型、直接与捕获图像、图层亮度绑定和具名输出。作者其他局部效果保持各自合同。仅有 HDR 参数的作品按可区分的官方普通默认对照结算，旧解析后默认值无法证明原作者显式写入。
3. 同一夹具检查 HDR 过亮源、仅普通亮源、作者禁用／零贡献、动态普通参数和局部效果邻例。分别量原工作域颜色、泛光轮廓、实际 pass／池计费、独立作品及原累积 history。先验 App 确实选择新路径，再测何时可开放控件。

作者 HDR 且 `clear=false` 的场景降到 SDR 时，沿现有 `sceneColor` 提交保留跨 drawable 的 raw 累积。用实际 SDR 规格预约，省去 HDR 映射所需的临时显示附件。复制 raw 后在 drawable 上做普通泛光，暂停重导出可复用最近合格 raw。以至少三帧颜色累积和暂停重导出验收到同一 raw 收据，普通作者 SDR 继续走原路径。 [Scene 原输出合同](../scene/architecture/runtime-architecture.md#effective-quality-policy)

### Video 在线可选规格的实施片

Pixabay 原始记录已有多档 URL。浏览、键盘、浏览右键和远程详情共用一个原生选档入口。单个实际文件直接下载，多文件默认选最高已可用档，取消不建任务。相同 URL 的重复档用一个可选文件。复用原 attempt、staging 和发布，选中档的 URL、尺寸和预期字节来自同一条候选。下载继续是下载意图，完成后仍由用户单独选择播放。

历史回执只保存可选档位代码，重试按作品 ID 重新解析并取原档，缺档提示重新选择。旧回执、普通下载和库缺件恢复保原最高可用逻辑。AV 播放链直接读取发布的文件。本片验真实 HTTP 传输与 MP4 内容、取消、重复请求、缺档、重试及输出循环。真实原片规格和标称 FPS 归原详情链下一片，离线派生相对实际功耗的筛查独立进行。 [Video 技术评估](wallpaper-quality-settings-plan.md#video)

QV1 已验原生详情选择、重复 URL、单个有效规格、取消、原档重试及真实 HTTP 发布，所选 MP4 在现有 Video daemon 原生窗口里连续播放两个循环。更宽的产品交接和能耗仍由后续片取证。 [源码地图](../architecture/repository-map.md#wallpaper-quality)
