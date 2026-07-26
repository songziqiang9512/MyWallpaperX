# MyWallpaperX Web 与 Scene 当前状况评估及演进路线

> 评估日期：2026-07-19，Web 状态更新至 2026-07-22，Scene 状态更新至 2026-07-25
> 评估对象：当前仓库中的 Steam Workshop Web 与 Wallpaper Engine Scene 实现  
> 文档性质：当前事实、差距评估和后续验收路线。历史计划与历史回归记录只作为证据，不反向覆盖当前代码。Scene 的能力等级、门数据与批次索引不在本文重复维护，见第 5 节列出的四个权威入口。

## 1. 执行摘要

### Web

Web 已经具备可持续回归的正式运行主链。文件属性类型推断与跨重启恢复、强 DOM/视觉/交互证据、纹理 WebGL 的 loopback 路由、旧式颜色数组兼容、空 `file:///` 占位符处理、境外远程样式降级恢复、真实 64+64 双声道频谱及 Wallpaper Engine 兼容幅度响应、固定样本矩阵、签名 Debug App 身份门、切换/停止释放门禁、重叠系统中断恢复门、CoreAudio 配置失效重建和 Space 通知路由均已落地。

当前固定矩阵包含 10 个真实 Workshop 样本，覆盖 file/directory、dependency、媒体、Canvas、WebGL/WebGL2、Live2D、WASM、iframe、持久化存储、音频、指针输入和动态画面。最新隔离运行结果为 **10 个 A，平均 98.2，证据覆盖 94.3%，矩阵门禁通过**。每个 App 进程使用唯一 Debug UserDefaults suite，日志必须确认 suite，结束后必须删除；因此结果不再继承用户在产品 UI 中保存的样本属性。另外 5 个作者公开源码样本的独立门覆盖属性密集、Worker、音频频谱、约 33 MB 生成脚本和复杂 WebGL 动画；其中 `1396475780` 的大型脚本还验证了 Service Worker 静态识别，当前最终结果为 **5 个 A，平均 98.8，证据覆盖 97.9%**；3 个 Steam CDN 代表样本覆盖响应式 Canvas、手工三视口 WebGL 和 CoinGecko 实时数据，当前最终结果为 **3 个 A，平均 98.0，证据覆盖 94.8%**。

当前本机 34 个 Web 样本已固化为完整基线。2026-07-20 构建的长批次为 **34 个 A，平均 98.2，证据覆盖 93.3%，完整门通过**；同一构建的作者源码和 Steam CDN 批次分别为 5A 与 3A。这组结果继续作为历史基线，但不再代表当前最终 HEAD。

2026-07-22 首轮 34 项完整门的 28A/6B 失败已完成归因和修正：4 个无 `applyUserProperties` listener 的样本移除错误 `properties` 标签；无需属性桥的样本不再被记为 weak coverage；当前 listener 与当前 payload 的 DOM 应用签名可作为正向属性证据；完整门最低观察窗提升为 18 秒；Debug evidence 窗口会进入当前 Space 并成为 key，避免 WebKit 因 `isOnScreen=0` 停止 `requestAnimationFrame`。这些修正没有放宽评分阈值、隐藏错误或修改样本源码。

当前最终签名 Debug App 的同构建结果为：**34/34 可运行、32A/2B、平均 97.7、证据覆盖 95.9%，完整门通过**；作者源码门为 **5A / 98.8 / 97.9%**，Steam CDN 门为 **3A / 98.0 / 94.8%**，三组 App 身份均为 Team ID `H9QWU9XN8R`、CDHash `f3eb94e6f511403263775b7ee8e04f3fdc0ceb30`、可执行文件 SHA-256 `5278316bbc5ca6d5b22c8b014380ebdb857c1635a107a04f2b38a52bd40bd7db`。`3700131876`、`3700928191` 仍保留样本脚本属性错误和 B 等级，只因矩阵明确允许该既有短板而不阻断批次；其余非空 shortfall 均与各样本允许例外一致。

Web 目前没有已确认的宿主 P0 阻断，当前 HEAD 的 34+5+3 已知样本功能兼容主链和系统音频到 JS 主链可以视为闭环，但仍不能称为发布级“最终完全闭环”。确定性锁屏、重叠休眠、采集配置失效恢复、Space 通知中心路由/观察者释放和当前非沙盒发行链的 file/directory 服务持久化已关闭；真实 OS 电源周期、物理 Space/显示器与音频设备变化、runtime 互切、性能和长期运行预算、真实文件选择器 UI 与签名沙盒授权回归，以及 CI/发布流程接入仍未完成。按本文八项能力门重算，当前工程成熟度仍约为 **90/100**。

### Scene

Scene 已建立独立模块、PKGV 读取、受控缓存、typed interpretation、纹理解码、Metal 渲染和桌面宿主。当前链路为 interpretation v29；实现基线 `b86db59` 的 renderer 消费十一类严格注册 effect backend，生成 20 个精确登记的项目自有 built-in 粒子纹理，并执行非音频 Turbulent Velocity Random。Puppet 已有 bind-pose mesh、静态 MDAT attachment，以及只接受 MDLV0023/MDLS0004/MDLA0006、单个静态可见 loop clip、non-additive、blend/rate=1 的 source-FPS 离散 CPU LBS 子集；粒子的 strict child 已执行至层级 2：depth-one static/default-static/eventspawn/natural-eventdeath/eventfollow 加 depth-two 仅 event 触发的 nested child（按 parent asset path 去重展开、(parent system, 粒子) owner），Sprite Trail 和 1,024/system 预算，`2131872317` 延迟 App 门可见烟花。Static/default-static 允许有限 origin translation，但仍要求零 angles、单位 scale、无 CP、probability=1、非音频且资源/renderer 可执行，并在 authored local origin 创建一次，目标定义自身含 event children 时不再被 nested 阻断（`2974757317` 43 列 matrix 数字雨为真实正例）；Event child emitter 在 Sphere/Box、合法有限参数、非音频、已知 flag 和 Sprite/Sprite Trail 边界内执行 instantaneous、continuous rate、两者混合及有限/无限 duration；Event Follow 以父 ID 逐帧更新 origin，并在父死亡时强制回收。每个 root child runtime 每深度最多 64 个系统、跨两层 128 系统/131,072 粒子容量，超限明确诊断；depth-three 与 nested static 声明 fail closed。BC1/2/3 颜色纹理在预算内走 CPU premultiply，超预算或多 image 载荷走 GPU premultiply；`3768903841` 的跨 image sprite 当前只裁 authored 首帧作静态 fallback，完整 5-image/140-frame 动画未实现。Turbulent velocity 的 audio profile 和其他未声明 profile 保持 fail closed；自建 gradient noise 不是 WE 数值或像素等价实现。动态 effect profile 按完整 definition/material/shader/resource fingerprint 准入，并在同一 ordered scheduler 保持作者顺序；X-Ray 另有明确受限的前缀执行边界。默认 96 MiB pool 只保证 6 个全尺寸 BGRA texture unit，超预算链在规划阶段整链拒绝。generic material pass、authored shader preprocessing/translation、真实 history consumer、generic compose/scene-background、condition/function、SceneScript/time/media、Puppet 插值/mixing/动画 attachment follow/constraints，以及 static angles/scale、event transform、collision/delete child、event CP/value inheritance、depth-two static 与 stop/switch teardown 压力门仍未实现。

当前运行证据仍分完整快照与固定回归两层：`b86db59` 以真实目录重建 45 样本隔离副本并把完整矩阵合同刷新到 interpretation v29 后，`.codex/scene-nested-child-full45-20260727/report.json` 为 **44/45**，唯一失败是 `3743305891` 的 masked Opacity layer 23（`20dc036` 遮罩消费批次既有缺陷、feat 前构建复现一致、独立核查中）；`3770500543` 因缺少 `scene.pkg` 排除。`.codex/scene-nested-child-fixed13-20260727/report.json` 固定门 **PASS 13/13**。完整门 particle `110/131`、strict stage 122、chain 15、failed 1；固定门 particle `66/76`、82 stage、10 chain、failed 0；历史 static-origin 定向门 `.codex/scene-static-origin-targeted-20260725/report.json` 按当时口径保留 1/1、`17/19`，`3088601835` 当前为 `19/19`，Snow root layers `513/534` 可见且未过曝，`snowstormfog` child 在两层生成实例且未洗白。完整 Scene suite 为 **86 模块：字体替代断言 5 项既有失败独立处理中，其余全部通过**，代码健康为 **456 Swift files、44 locked legacy files、400-line limit**。当前三门签名 App 为 `2.0.8 (268)`、Team `H9QWU9XN8R`、CDHash `8661db034136a4030592f6e2f3190b08de4c448a`、可执行文件 SHA-256 `1ddea5e09f45e45828b5e1003debb56e92fcb82cfef4f0428e7cde45ac70d004`；运行前后签名通过、sample root residue 0。样本自带 preview 是当前第一视觉依据（证据基线 `3194ac5`）；WaifuX SceneBake MP4 只作辅助动态参考，二者均不能解释为 WE 视觉一致。

## 2. 评估口径与证据边界

本评估采用以下证据：

1. 当前 Web/Scene 源码与模块调用路径。
2. [Web 壁纸运行能力评测标准](../web/web-wallpaper-benchmark-standard.md)。
3. [Web 外部代表样本基线](../web/regression/WEB_EXTERNAL_SAMPLE_BASELINE_2026-07-20.md) 与 [Steam 代表样本基线](../web/regression/WEB_STEAM_REPRESENTATIVE_BASELINE_2026-07-20.md)。
4. [Scene 能力台账](../scene/semantics/coverage-ledger.md)、[能力依赖图](../scene/semantics/capability-dependency-map.md) 与 [运行证据索引](../scene/semantics/runtime-evidence-index.md)。
5. 2026-07-20 对当前 Debug App 的 10 项固定矩阵、5 项作者源码外部矩阵、3 项 Steam CDN 代表矩阵、34 项全量扫描和三段生命周期隔离运行结果。
6. [Web 外部代表样本基线](../web/regression/WEB_EXTERNAL_SAMPLE_BASELINE_2026-07-20.md) 中的来源、revision、能力覆盖和证据边界。
7. [Web Steam 代表样本基线](../web/regression/WEB_STEAM_REPRESENTATIVE_BASELINE_2026-07-20.md) 中的 Steam CDN 快照、响应式/多视口/联网能力和证据边界。
8. 提交 `3a5ef15` 的远程字体硬失败恢复、慢响应、iframe、HTTP HEAD/Range 和 34 项完整门报告。
9. 提交 `3b69614` 的纯信号测试、受控 `afplay` 双声道频率测试、音频需求生命周期、10 项固定门和 34 项完整门报告。
10. 2026-07-21 的 Web 音频幅度回归测试：`884307090` 圆环/直线两种属性模式分别为 96 / A，`1509243786` 确定性频谱和真实 `afplay` 两次均为 100 / A；报告保存在 `.codex/web-audio-calibration-20260721/`。
11. 2026-07-21 的系统中断恢复门：`1509243786` 在系统睡眠与显示器休眠重叠、部分唤醒、最终唤醒、锁屏/解锁后均按需停止和恢复采集；最终通过报告保存在 `.codex/web-system-state-final-20260721/results-pass2/`，首次失败口径报告也保留在同目录的 `results/` 供复核。
12. 2026-07-21 的 CoreAudio 配置失效恢复门：突发三次失效合并为一次重建，单次失效触发第二次重建，三代监听与真实 PCM 均恢复且最终资源归零；最终报告保存在 `.codex/web-audio-restart-final-20260721/results-pass/`。首次立即重建触发 CoreAudio `!obj` 的失败报告保存在同目录的 `results/`，用于证明 1 秒 teardown settle window 的根因，而不是删除失败证据。
13. 2026-07-21 的 file/directory 持久化门：生产更新、A/B/A 切换、外部 file/directory 实际改名、跨进程 bookmark 恢复、reset 和再次重启均通过；最终独立偏好域报告保存在 `.codex/web-property-persistence-final-20260721/results-suite-pass/`。
14. 2026-07-21 的 Debug 偏好隔离门：`HOME/CFFIXED_USER_HOME` 不能隔离进程外 `cfprefsd`，现改为每次 App 启动显式传唯一 Debug suite 并由 scorer 校验、结束后删除；最新 10 项矩阵为 10A / 98.2 / 94.3%，报告保存在 `.codex/web-defaults-isolation-final-20260721/matrix-regression/`，10/10 suite 均已删除且标准偏好摘要未变化。
15. 2026-07-21 的 Space/屏幕 observer 门：`NSWorkspace.activeSpaceDidChangeNotification` 改由 `NSWorkspace.shared.notificationCenter` 注册并从原 center 释放；default center 反向 0 次、两次 workspace 通知各 1 次、3 次屏幕参数通知合并为 1 次协调、stop 后回调为 0，最终报告保存在 `.codex/web-space-lifecycle-final-20260721/results-pass2/`。首轮 19 秒窗口在 `completed` 前约 0.4 秒结束的失败报告保存在 `results-pass/`，用于证明门禁时长修正，不删除失败证据。
16. 2026-07-21 的截图证据身份门：benchmark 先严格验证并隔离复制签名 Debug App，运行后复核 bundle ID、Team ID、CDHash、版本和可执行文件 SHA-256；`3700131876` 在隔离 Workshop root/HOME 下取得 ready 与 after-interaction 的 WebView、Canvas、当前进程窗口三源快照，窗口截图肉眼确认非空。单样本结果为 92 / A、coverage 90.3%，既有 `properties.error` 仍按短板保留；报告保存在 `.codex/web-wallpaper-benchmark-capture-final-20260721/`。
17. 2026-07-22 的当前 HEAD 34 项完整门：34/34 可运行，28A/6B，平均 96.3，coverage 94.7%，矩阵门失败；报告保存在 `.codex/web-full-final-20260722/`。
18. 2026-07-22 的 9 项属性证据定向复跑：完全复现 4 个属性 B、3 个 coverage-only 失败和 2 个既有允许例外，排除长批次偶发；报告保存在 `.codex/web-full-targeted-retry-20260722/`。
19. 2026-07-22 的当前最终 34 项完整门：32A/2B，平均 97.7，coverage 95.9%，矩阵门通过；报告保存在 `.codex/web-full-final-pass-20260722/`。
20. 2026-07-22 的当前最终作者源码门：5A，平均 98.8，coverage 97.9%，矩阵门通过；报告保存在 `.codex/web-external-final-pass2-20260722/`。
21. 2026-07-22 的当前最终 Steam CDN 门：3A，平均 98.0，coverage 94.8%，矩阵门通过；报告保存在 `.codex/web-steam-final-pass-20260722/`。
22. Scene 逐批实施与验收记录（2026-07-22 起的首批自动门到最新合成正确性批次）不再在本文逐条复制：批次索引见 [Scene 播放能力开发计划第 8 节](../scene/scene-capability-development-plan-2026-07-22.md)，逐项运行报告、矩阵 SHA 与签名身份见 [运行证据索引](../scene/semantics/runtime-evidence-index.md)，实现细节以对应提交为准。

前序专项报告保存在 `.codex/web-closure-final-20260720/`；作者源码、Steam CDN、34 项历史基线、系统中断门、音频配置失效门、文件持久化门、偏好隔离矩阵和 Space/屏幕门报告分别保存在 `.codex/web-external-final-20260720/results/`、`.codex/web-steam-final-20260720/results/`、`.codex/web-full-final-20260720/results/`、`.codex/web-system-state-final-20260721/results-pass2/`、`.codex/web-audio-restart-final-20260721/results-pass/`、`.codex/web-property-persistence-final-20260721/results-suite-pass/`、`.codex/web-defaults-isolation-final-20260721/matrix-regression/` 和 `.codex/web-space-lifecycle-final-20260721/results-pass2/`；作者源码和 Steam 样本副本分别保存在 `.codex/web-external-representative-samples-20260722/` 与 `.codex/web-steam-representative-samples-20260720/`。这些目录被 Git 忽略，只作为本地复核证据保留到分支合并，不替代仓库内的矩阵定义和生产测试。

本次 Web 固定矩阵结果：

| Workshop ID | 代表能力 | 得分/等级 | Evidence coverage | 结果说明 |
| --- | --- | ---: | ---: | --- |
| `923576681` | file、媒体、音频、Canvas | 100 / A | 95.5% | 隔离文件属性 fixture 生效，DOM、交互和两张 Web 快照齐全 |
| `1509243786` | 属性密集、file/directory、媒体 | 100 / A | 95.5% | 空文件根占位符不再产生 `__absolute__` 拒绝 |
| `2675660496` | dependency、颜色、音频 | 100 / A | 95.5% | dependency shell、资源、主动音频监听、交互和画面通过 |
| `2997985023` | Live2D、WebGL、媒体 | 93 / A | 100% | 延迟首帧后画面和交互通过；样本包缺少其声明的音频文件，本轮另有一次样本 AudioContext suspend 错误 |
| `3700131876` | 纹理 WebGL、loopback、属性恢复、动态画面 | 92 / A | 94.8% | 雨滴持续生成；两帧平均差 0.0070、显著变化 8.30%；样本自身仍有 1 个属性脚本错误 |
| `3726135866` | WASM、WebGL、存储、file | 100 / A | 95.5% | 通过 |
| `3740867386` | 存储、媒体、音频 | 100 / A | 95.5% | 主动音频监听、128-bin 分发和频谱变化通过 |
| `3752541815` | WASM、iframe、directory、存储 | 98 / A | 90.3% | 通过 |
| `3757331413` | WebGL、file、颜色、指针 | 98 / A | 90.3% | 通过 |
| `3762337744` | WebGL、Canvas、指针 | 98 / A | 90.3% | 通过 |

新增外部代表矩阵结果：

| Workshop ID | 代表能力 | 得分/等级 | Evidence coverage | 结果说明 |
| --- | --- | ---: | ---: | --- |
| `1748506393` | WebGL2、35 项属性、音频、指针 | 100 / A | 95.5% | 主动音频和持续流体动画通过 |
| `1396475780` | 174 项属性、WASM、Worker、音频 | 100 / A | 95.5% | production 构建、粒子画面和动画通过 |
| `2014502586` | WebGL 后处理、Worker、音频 | 100 / A | 95.5% | Canvas/窗口合成画面和运动证据通过 |
| `2119347960` | Canvas、约 33 MB 脚本、FPS | 96 / A | 90.3% | Service Worker 补扫去重并限制为单文件 1 MiB 后，进程口径 `host.ready` 为 6.5 秒；交互和动画通过 |
| `2553306714` | 74 项属性、WebGL、指针 | 98 / A | 94.8% | 属性、指针和持续动画通过 |

新增 Steam CDN 代表矩阵结果：

| Workshop ID | 代表能力 | 得分/等级 | Evidence coverage | 结果说明 |
| --- | --- | ---: | ---: | --- |
| `3733483918` | Canvas、属性、DPR、响应式布局 | 98 / A | 90.3% | 三源画面、交互和持续动画通过；不把标题中的 Multimonitor 当作真实多屏证据 |
| `3765959388` | WebGL、70 多项属性、三视口/三相机、FPS | 98 / A | 90.3% | loopback origin、复杂画面、交互和动画通过；仍需真实多屏验证 |
| `3764966764` | Canvas、外部 fetch、实时数据 | 98 / A | 90.3% | CoinGecko 数据在当前网络/代理下成功显示；未验证断网/恢复 |

当前 34 样本全量扫描的例外项：

| 类别 | 样本 | 当前结论 |
| --- | --- | --- |
| 样本脚本属性错误 | `3700131876`、`3700928191` | 颜色数组整包兼容重试后，各自在 `motionintervalmin` 的错误访问处按原回调顺序停止；不再越过错误修改雨滴默认参数。两者均为 92 / A，动态门通过 |
| 样本缺媒体 | `2731942107`、`2997985023`、`884307090` | 包内声明的音频文件不存在；归为 `sample_resource` / `media_audio`，不是宿主映射失败 |
| 样本缺图片或可选资源 | `3759146455` | 请求文件不在样本包内；当前归因规则按 `reason=missing` 归为 `sample_resource` |
| 稀疏暗色 WebGL | `3765286189` | OLED 黑底星空按声明的 `sparse-dark-output` 能力、非黑采样、方差和峰值亮度确认有效，A；普通纯黑、纯白和单点噪声反例仍失败 |
| 境外远程字体 | `1509243786`、`3696478440`、`3740867386`、`3763370103` | Google Fonts 不再阻塞 DOM/宿主就绪；无代理或网络失败时先使用后备字体并按 2/4/8/16/30 秒限界重试，网络恢复后激活。最新 34 项长批次全部为 A |

本次没有得到以下证据：

- 34 个本机样本、5 个外部作者源码样本和 3 个 Steam CDN 代表样本只代表 2026-07-20 当前快照，不代表所有公开 Workshop Web 壁纸，也不是未来新增样本的自动成功率。
- 34 项完整基线已有固定清单、能力标签、允许例外和失败退出条件，但尚未接入 CI 或发布 checklist；新增本机样本也不会自动进入清单。
- 外部 5 项来自作者公开源码的固定 revision，不是 Steam CDN 原始归档；第三方构建产物没有提交到仓库，因此它们是可选独立门，不是默认门的隐式依赖。
- Debug 音频 fixture 只用于确定性桥接门。受控 `afplay` 已证明系统采集到 JS 的主频、幅度和左右声道相关性，但本机当时仍有其他后台声音，未形成“系统绝对静音”实机证据，也未自动判定最终画面的逐帧音频相关性。
- 配置失效门通过生产调试入口触发与 CoreAudio 属性监听回调相同的重建路径，证明 debounce、teardown、重建和资源回收，不证明 AirPods、HDMI 等物理设备变化的系统通知一定到达；当前机器只有一个可用输出端点，无法完成该实机矩阵。
- 当前 Debug、Release 和已安装 App 均未启用 App Sandbox。文件门证明普通 bookmark 与当前非沙盒读取链，不等同于签名沙盒构建中的 security extension 授权；真实 NSOpenPanel 点击路径和重新启用 Sandbox 后仍需单独回归。
- 用户真实 Scene 目录当前有 46 个数字目录，其中 45 个具备可运行 package 并进入完整快照门；`3770500543` 缺少 `scene.pkg`，按源结构明确排除。运行和属性注入均只使用 `.codex` 隔离副本，source manifest 复核真实目录与隔离源均为零修改；本机没有 Windows Wallpaper Engine 同配置逐帧录屏，因此仍不能给出逐像素兼容结论。
- Space 自动门使用真实 Web 宿主和生产 observer，但通过进程内投递确定通知中心路由；它不冒充 Mission Control 实际切换后的肉眼可见性，也不证明显示器热插拔或分辨率变化。
- 没有 30 分钟以上交互运行、2 小时 soak、真实休眠唤醒、屏幕热插拔、内存压力或发布包回归。
- 因而本文能说明当前已知样本的结果，但不能给出整个 Workshop Web 或 Scene 的总体成功率。

## 3. Web 当前实现状况

### 3.1 已形成的能力

#### 运行时与宿主

- Web 使用独立于 Video/Scene 的宿主接口和状态模型。
- 当前实际策略是每屏独立 `WKWebView` 的 `dedicatedHostPlaceholder`；daemon 已降级为诊断 harness。
- 宿主支持屏幕增删、运行状态广播和一次 WebContent 进程终止恢复。
- Space 变化监听使用 `NSWorkspace.shared.notificationCenter`；屏幕参数突发变化按 200 毫秒合并，observer token 始终从其注册 center 释放。
- 代码入口：[WebWallpaperHostTypes.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift)、[WallpaperEngine+WebWallpaper.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift)。

虽然类型名仍带 `Placeholder`，其实现已经承担正式播放职责。后续应在验收完成后重命名，避免代码语义继续误导维护者，但重命名不是当前 P0。

#### 资源加载与隔离

- `mwx-local://` scheme 支持 MIME、Range、受控可读根和符号链接越界检查。
- localhost profile 只绑定 `127.0.0.1`，用于 Service Worker、module、WASM 等对 origin 更敏感的样本。
- 支持按 Workshop/profile 选择 persistent、scoped 或 ephemeral data store。
- Google Fonts 等境外远程样式遵循系统网络/代理配置，但不再是页面就绪前提；主文档、iframe、动态 link 和嵌套 CSS import 均支持失败降级与网络恢复重试。
- loopback 的二进制 GET/HEAD/Range 保持 HTTP 语义；被转换的 HTML/CSS 明确不声明 Range，避免响应头与正文不一致。
- 代码入口：[WebWallpaperLocalSchemeHandler.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler.swift)、[WebWallpaperLoopbackServer.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLoopbackServer.swift)。

这部分架构方向正确，不应退回到扩大整个 Workshop 根目录读取权限的通用 `file://` 方案。

#### Wallpaper Engine API 兼容

- 支持 `applyUserProperties`、`applyGeneralProperties`、`setPaused`、`setPlaybackState`。
- 支持 listener 延迟注册后的状态重放，避免页面在 document-start 之后才赋值而丢失首轮属性。
- 已包含目录变更、媒体状态、媒体属性、缩略图、timeline、playback 和音频频谱接口。
- Web 音频使用保留符号的 PCM 分声道执行 4096 点 FFT，按 32 Hz 到 20 kHz 的 64 个对数频带输出 `left[0...63] + right[0...63]`；只有真实单声道输入才复制为左右两组。
- 兼容层按 foundation、resource rewriting、media、pointer、DOM lifecycle 和 host bridge 拆分。
- 代码入口：[DedicatedWebWallpaperHostCompatibilityScript+BootstrapFoundation.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+BootstrapFoundation.swift)、[DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift)。

#### 属性、输入和产品接入

- Web 属性定义、默认值、preset、用户覆盖、显示条件和本地化已经形成完整链路。
- 属性面板覆盖 slider、color、toggle、text、combo、file、directory、label、group 等主要类型。
- 外部 file/directory 用户覆盖不会读取或写入 execution payload cache；每次播放重新解析 bookmark 并恢复授权，静态 descriptor cache 仍可复用。非沙盒构建在 security-scoped bookmark 不可创建时保存普通 bookmark，文件或目录改名后仍可跟随。
- 输入层支持 pointer、wheel、点击、拖动和临时捕获，不依赖壁纸窗口直接抢占桌面事件。
- 代码入口：[SteamWorkshopService+WebPropertyParsing.swift](../../MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPropertyParsing.swift)、[DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding.swift)。

#### 诊断和评测

- Runtime 事件按 record、display、type 和 severity 记录。
- `script/web_wallpaper_benchmark.py` 可以启动真实 App、聚合日志、评分、生成 coverage，并与 baseline 比较；每次正式运行拒绝非空输出目录，只接受本次日志声明且位于当前样本目录内的截图路径。
- benchmark 会严格验证签名 App、复制到独立 runtime bundle，并在运行前后核对 bundle/Team/CDHash/版本/可执行文件 SHA-256；报告记录这组身份，不再把被原地改写或来源不明的 App 当作本轮证据。
- 已定义启动、导航、资源、属性、媒体、交互、视觉和性能八个评分维度。
- 代码入口：[WebRuntimeDiagnosticsStore.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/WebRuntimeDiagnosticsStore.swift)、[web_wallpaper_benchmark.py](../../script/web_wallpaper_benchmark.py)。

### 3.2 已关闭的问题与当前剩余风险

#### 已关闭：文件属性类型与资源路径闭环

- 属性解析会按定义和实际资源推断 file/directory 类型，类型不匹配的旧持久化值会被清理。
- benchmark 在隔离 Workshop 根之外创建文件属性 fixture，并使用唯一 Debug UserDefaults suite；仅设置 `HOME/CFFIXED_USER_HOME` 不再视为 bookmark/偏好隔离。
- `923576681` 已取得属性注入、DOM、资源、交互和非空快照证据。
- 空 `file:///` 不再被重写成无意义的 `mwx-local://wallpaper/__absolute__/` 请求。
- 持久化 gate 对 `1509243786` 的 file、directory 和目录模式调用生产更新，连续运行 A/B/A；首进程退出后把两类 fixture 改名，第二进程以旧 raw value 通过 bookmark 恢复到新 resolved/payload，随后 reset，第三进程确认 bookmark 不复活、值为空且模式回到 1。存在外部覆盖时不生成 execution cache，清除后普通 cache 恢复。

```bash
python3 script/web_property_persistence_gate.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --runtime-workshop-root <isolated-workshop-root> \
  --runtime-home <empty-temporary-home>
```

仍需保留一项产品 UI/签名回归：真实 NSOpenPanel 的点击选择，以及未来若重新启用 App Sandbox 后的 security-scoped 授权恢复，目前不是自动门禁。服务层的“选择值、立即生效、切换回来、重启恢复、清除授权”已经自动化，不再是已确认宿主缺陷。

#### 已关闭：视觉与交互强证据

benchmark 现在要求像素统计、DOM 状态和 pointer/click/drag/wheel 注入。视觉证据可来自 `WKWebView.takeSnapshot`、页面 Canvas 和 ScreenCaptureKit 当前进程窗口；窗口采集对限界瞬态错误重试，并结构化记录阶段、错误域、错误码、attempt、window ID 和是否终止。动画只比较同一来源的非空前后帧，避免 WebGL drawing buffer 清空时把黑帧误判成运动。普通画面按覆盖、方差和色彩判断；声明 `sparse-dark-output` 的 OLED 星空还要求非黑采样、方差和峰值亮度。纯黑、纯白、单点噪声和应动未动均形成关键短板；固定矩阵禁止 `interaction`、`visual_output` 和 `animation` 短板。系统整屏截图只作为人工复核附件，黑屏或采集失败时不写入报告，不能替代上述样本内强证据。

#### 已关闭：真实双声道频谱与 Web 监听需求

- 原实现先对 PCM 取绝对值，再把桌面 28 柱插值为 64 柱并复制左右声道；这会把 750 Hz 全波整流成约 1500 Hz，并制造重复的固定形状。现在同一采样拆成两条用途明确的路径：rectified mono 继续维持桌面覆盖层旧视觉，signed stereo 专供 Web FFT。
- Web 分析器使用固定 4096 点 FFT、Hann 窗、去直流和固定 dBFS 标尺，输出严格 128 个有限 `0...1` 值。生产测试覆盖静音、750 Hz 不倍频、125/500/2000/8000 Hz 递增频带、左 250 Hz/右 4 kHz、幅度单调、单声道复制、Float32/Int16/Int32、交错/非交错和非有限值。
- `3b69614` 首次引入真实双声道 FFT 时遗漏了旧宿主边界的兼容响应，导致常见输入从约 `0.10...0.18` 放大到约 `0.68...0.98`；`884307090` 等样本还会把输入乘以 `range * 100`，因此出现音频条过长、动作幅度过大的视觉回归。当前在 JS 分发前恢复 `pow(level, 1.35) * 0.18`，保留真实频率和左右声道，仅校准输出量级。生产测试直接编译该宿主扩展，锁定 128-bin、最大幅度、单调性和双声道独立性。
- `wallpaperRegisterAudioListener` 第一次有效注册会独立请求采集，不再依赖“桌面系统频谱”开关；导航、WebContent 终止、屏幕移除、Web 切换、Video 切换和 stop 都会释放需求，多屏按首个请求/最后释放聚合。
- 受控 `afplay` 实机证据中，左 250 Hz 稳定落在第 20 频带，中央 1 kHz 落在第 34 频带且 0.02 到 0.80 幅度明显上升，右 4 kHz 落在第 47/48 频带；样本 `1748506393` 为 100 / A。音频到无音频再到音频的生命周期序列证明采集按需启动、停止、重启和最终释放。
- 2026-07-21 回归中，`884307090` 的圆环和直线样式由样本属性 `visual_audio_model=1/2` 决定，不是宿主改变绘制类型；两种模式在确定性频谱下均为 96 / A，画布幅度受控。`1509243786` 的确定性频谱为 100 / A；关闭夹具后循环播放系统音效，日志从静音帧进入 `audio.spectrum.changed meanDelta=0.0224`，真实采集结果仍为 100 / A。
- Debug benchmark 仍只在显式参数下注入确定性 64+64 fixture，用来发现“注册但未分发”和“持续发送同一数组”；它不冒充真实系统采集证据。

确定性系统状态恢复已关闭：消费者需求与实际采集资源已经分离；暂停、系统睡眠、显示器休眠或锁屏会释放 CoreAudio tap，最后一个中断原因结束后再由统一播放策略恢复；失败保留需求并限界退避。采集还会监听 tap format 与 aggregate device alive，250 毫秒内的突发配置失效合并为一次重建；监听先移除再销毁 CoreAudio 对象，teardown 后等待 1 秒再创建新 tap，避免已由首轮失败门确认的 CoreAudio `!obj` 竞态。系统状态门和配置失效门都要求每一代恢复后出现非静音 PCM 数据，不能只以 CoreAudio 对象创建成功代替数据恢复。剩余边界是实际 OS 睡眠/唤醒、真正的系统静音、物理输出设备切换与蓝牙重连的真实通知投递，以及把 JS 频带与最终画面响应做自动时间对齐。

#### 已关闭：代表样本矩阵与单样本门禁

固定矩阵由 [web_wallpaper_sample_matrix.json](../../script/web_wallpaper_sample_matrix.json) 定义。每个样本有能力标签、最低等级和最低 coverage，批次还限制平均分、平均 coverage 和关键短板。矩阵自带 18 秒最低观察窗，避免大体积或冷启动样本在首帧与属性回放完成前被过早终止。

当前 34 样本已固化为 [web_wallpaper_full_baseline.json](../../script/web_wallpaper_full_baseline.json)，外部 5 样本由 [web_wallpaper_external_sample_matrix.json](../../script/web_wallpaper_external_sample_matrix.json) 定义，Steam CDN 3 样本由 [web_wallpaper_steam_representative_sample_matrix.json](../../script/web_wallpaper_steam_representative_sample_matrix.json) 定义。固定矩阵仍是公共 runtime 改动的快速门，完整基线用于高影响改动和发布候选，外部门用于扩展能力验证。大型脚本 Service Worker 静态识别已修复并由缓存版本 14 验证；补扫采用 64 KiB 分块匹配、单文件 1 MiB 上限，验证报告会复用描述符摘要，避免大批生成脚本重复拖慢冷启动。但 `1396475780` 在 Wallpaper Engine 分支实际注册数为 0；因此 Shadow DOM、Service Worker 真实注册、真实多屏 scale factor、外部网络失败/恢复等能力仍没有形成独立行为门。

#### 部分关闭：切换、停止和资源释放

生命周期模式会连续启动多个真实样本再 stop，并验证：

- 每个样本到达 `host.ready`。
- 每次 teardown 后 surface、loopback、directory watcher、鼠标 monitor 和 pointer timer 都为 0。
- 每个旧 `WKWebView` 通过弱引用确认已释放。
- 每个启动过的 loopback server 都有对应停止事件。
- 最终 phase 为 idle，lifecycle observer 为 0。

锁屏/解锁和重叠系统/显示器休眠的生产 handler、采集停止/恢复、部分唤醒抑制和最终释放已有自动门，但它通过直接调用生产 handler 注入事件，不冒充真实 OS 睡眠周期。Space/屏幕 observer 门已验证正确 notification center、重装不重复、屏幕 burst 合并和 stop 后零回调；它使用进程内通知，不冒充真实 Mission Control 或显示器热插拔。尚未覆盖真实 OS 休眠/唤醒、物理 Space/显示器增删与分辨率变化、Web/Video/Scene 快速互切、物理音频设备变化、系统代理启停、一般网络断开恢复和连续 WebContent 崩溃，因此生命周期仍只能算部分关闭。

#### P1：性能和长期稳定性预算尚未建立

需要记录首个 `host.ready`、可视首帧、稳定 CPU/GPU、App 与 WebContent 内存、音频采集负载、暂停功耗和缓存增长。常规大体积静态分析限制为每个文件最多 128 KiB 的首尾窗口；Service Worker 诊断补扫限制为单文件 1 MiB 并使用分块搜索。约 33 MB 生成脚本样本的最终进程口径 `host.ready` 为 6.5 秒，已通过 18 秒外部门，但仍有性能提醒；单次优化和释放证据也没有证明 30 分钟交互运行和 2 小时 soak 不持续增长。

验收标准：建立单屏和双屏基线；暂停后 CPU/GPU 明显下降；30 分钟和 2 小时曲线无单调增长；运行中 WebContent 恢复次数受控；超预算报告必须包含样本、profile 和进程级数据。

#### 部分关闭：全样本门禁已建立，尚未接入发布流程

2026-07-20 已对当前 34 个本机样本建立固定清单、能力标签、已知样本例外和失败退出条件，并增加 5 个作者源码样本和 3 个 Steam CDN 代表样本的独立门。固定矩阵用于每次公共 runtime 改动；涉及 parser、origin、资源、属性、缓存签名、音频或评分规则的改动，以及发布候选版本，再运行完整门。2026-07-22 当前 HEAD 已在同一签名 Debug App 上完成 34+5+3 刷新，三组矩阵门均通过；首轮 28A/6B 暴露的 scorer、能力标签和无 listener 页面属性证据合同不一致也已修正。下一步是把完整门接入发布 checklist；仍不能用平均分或失败项单独重跑通过替代批次关键短板判断。

#### P2：正式宿主契约和发布流程尚未收口

`dedicatedHostPlaceholder` 已是事实主力，但命名、接口稳定性和 daemon diagnostics harness 的边界仍未正式收口。固定矩阵和生命周期门禁尚未接入 CI/发布 checklist。

验收标准：正式命名当前宿主；明确 daemon harness 的保留理由；发布前固定运行兼容矩阵、生命周期、UI 文件授权回归和性能预算；失败报告保留样本 ID、profile、日志和截图。

## 4. Web 距离最终完全闭环还有多少

### 4.1 工程成熟度估值

| 能力门 | 权重 | 当前得分 | 说明 |
| --- | ---: | ---: | --- |
| 启动、分类与资源主链 | 20 | 20 | 34+5+3 已知样本可运行；双 origin、资源隔离、HTTP 语义、纹理 WebGL 和远程字体失败恢复已验证 |
| 属性与持久化 | 15 | 14 | file/directory 服务持久化、颜色和错误隔离已闭环；真实选择器和签名沙盒授权仍是发布回归 |
| 媒体与音频 | 10 | 9 | signed stereo 64+64、真实声音相关性、按需生命周期、确定性中断和配置失效恢复已验证；物理设备切换、系统静音和真实 OS 睡眠未完成 |
| 输入与交互 | 10 | 9 | 原生指针转发和自动 pointer/click/drag/wheel 证据已进入门禁 |
| 多屏与生命周期 | 15 | 14 | 切换/stop/释放、音频需求启停、重叠睡眠/锁屏状态机、Space 路由和屏幕 burst 合并通过；真实 OS/显示器事件与 runtime 互切未闭环 |
| 稳定性与性能 | 10 | 6 | 有恢复和释放证据；无正式 CPU/GPU/内存/功耗与 soak 预算 |
| 诊断与自动化验证 | 15 | 15 | 三源视觉、DOM、交互、主动音频、三级矩阵、归因自测和生命周期报告已具备 |
| 发布支持与故障降级 | 5 | 3 | 已有完整基线和失败退出规则；尚未接入 CI/发布 checklist，也没有正式降级标准 |
| **合计** | **100** | **90** | **已知样本、真实音频主链、确定性中断和配置失效恢复已闭环，真实设备/OS、长期性能和发布流程仍未闭环** |

### 4.2 剩余工作量的正确理解

剩余不是“再补 10% 兼容代码”，而是完成以下 3 个工作包：

1. **系统生命周期与异常恢复**：确定性睡眠/锁屏、CoreAudio 配置失效重建和 Space/屏幕通知路由已完成；继续覆盖真实 OS 电源周期、物理 Space/屏幕热插拔、runtime 互切、一般网络/系统代理变化、物理音频设备变化和连续崩溃；不得以静默重试掩盖首轮失败。
2. **性能与长期运行门禁**：首帧、CPU/GPU、内存、功耗、缓存增长、30 分钟交互与 2 小时 soak。
3. **产品与发布闭环**：维护 34+5+3 样本、revision 和允许例外；完成真实 NSOpenPanel 与签名沙盒授权回归；收口 placeholder/harness 边界，把矩阵、生命周期、性能和 UI 回归纳入发布验收。

工作包 1、2 完成前，不能称为系统稳定性闭环；工作包 3 完成前，文件授权产品链、样本扩展机制和发布流程仍不是持续兼容承诺。

### 4.3 推荐完成顺序

```text
已完成：文件属性与跨重启/reset -> Debug 偏好隔离 -> 签名身份与三源视觉/动态证据 -> 远程字体失败恢复 -> signed stereo 真实音频 -> 固定/作者源码/Steam CDN/34 项历史门 -> 按需采集与 stop 释放 -> 重叠睡眠/锁屏确定性恢复门 -> CoreAudio 配置失效重建门 -> Space/屏幕 observer 自动门
下一步：最终 HEAD 34+5+3 刷新 -> Web/Video runtime 互切矩阵 -> 真实 OS/物理设备变化
  -> 性能、泄漏和功耗预算
  -> 基线维护、文件授权回归、正式宿主与发布门禁
```

每个工作包应独立修改、独立验证、独立提交。不要同时改 origin、属性重写和缓存签名后再通过一个高平均分判断结果。

### 4.4 当前可复现门禁

这些命令要求 `--app` 指向签名有效的 `.app` 内可执行文件。benchmark 会在新鲜输出目录中复制并复核运行 App；显式 `--output-dir` 已有内容时直接拒绝，避免旧截图或旧报告混入本轮证据。

固定矩阵：

```bash
python3 script/web_wallpaper_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --workshop-root <isolated-workshop-root>/Web \
  --runtime-workshop-root <isolated-workshop-root> \
  --runtime-home <temporary-home> \
  --matrix script/web_wallpaper_sample_matrix.json \
  --screenshot
```

生命周期：

```bash
python3 script/web_wallpaper_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --workshop-root <isolated-workshop-root>/Web \
  --runtime-workshop-root <isolated-workshop-root> \
  --runtime-home <temporary-home> \
  --lifecycle-sequence 3700131876,3726135866,2675660496
```

系统中断与真实采集恢复：

```bash
python3 script/web_system_state_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --runtime-workshop-root <isolated-workshop-root> \
  --runtime-home <temporary-home> \
  --id 1509243786
```

Space 路由、屏幕 burst 与 observer 释放：

```bash
python3 script/web_space_lifecycle_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --runtime-workshop-root <isolated-workshop-root> \
  --runtime-home <temporary-home> \
  --id 1509243786
```

当前 34 样本完整门：

```bash
python3 script/web_wallpaper_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --workshop-root <isolated-workshop-root>/Web \
  --runtime-workshop-root <isolated-workshop-root> \
  --runtime-home <temporary-home> \
  --matrix script/web_wallpaper_full_baseline.json \
  --duration 12 \
  --screenshot
```

外部 5 样本能力门：

```bash
python3 script/web_wallpaper_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --workshop-root <external-sample-root>/Web \
  --runtime-workshop-root <external-sample-root> \
  --runtime-home <temporary-home> \
  --matrix script/web_wallpaper_external_sample_matrix.json \
  --duration 18 \
  --screenshot
```

Steam CDN 3 样本能力门：

```bash
python3 script/web_wallpaper_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --workshop-root <steam-sample-root>/Web \
  --runtime-workshop-root <steam-sample-root> \
  --runtime-home <temporary-home> \
  --matrix script/web_wallpaper_steam_representative_sample_matrix.json \
  --duration 20 \
  --screenshot
```

`<isolated-workshop-root>`、`<external-sample-root>` 和 `<steam-sample-root>` 必须是只用于测试的副本，包含 `Web/<id>` 和依赖目录；不得把真实 `~/Movies/MyWallpaperX/创意工坊` 直接作为 runtime root。外部样本的来源、revision 和准备方式见 [Web 外部代表样本基线](../web/regression/WEB_EXTERNAL_SAMPLE_BASELINE_2026-07-20.md)，Steam CDN 快照见 [Web Steam 代表样本基线](../web/regression/WEB_STEAM_REPRESENTATIVE_BASELINE_2026-07-20.md)。

Scene 当前 13 样本语义门：

```bash
python3 script/scene_wallpaper_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --sample-root <isolated-scene-sample-root> \
  --matrix script/scene_wallpaper_sample_matrix.json \
  --output-dir <fresh-output-directory> \
  --duration 3.0
```

`<isolated-scene-sample-root>` 必须包含测试副本 `Scene/<id>`；不得直接传入真实 `~/Movies/MyWallpaperX/创意工坊/Scene`。当前完整快照门为 `.codex/scene-nested-child-full45-20260727/report.json`，当前源码固定回归门为 `.codex/scene-nested-child-fixed13-20260727/report.json`，历史 static-origin 定向门为 `.codex/scene-static-origin-targeted-20260725/report.json`；Snow/Smoke texture、static child、Flare、continuous-child、Event Follow、Turbulent Velocity、Light Shafts 0、Fire、BC、Puppet animation/attachment、`particle/halo_4`、X-Ray 和视觉校准报告只保留为对应阶段证据，不能反向覆盖当前结论。

## 5. Scene 当前实现状况

Scene 的逐系统能力等级、代码/测试/运行证据与剩余缺口不再在本文复制维护，统一以四个入口为准：

- 系统级摘要与逐项等级：[Scene 能力台账](../scene/semantics/coverage-ledger.md)，逐系统专项表由其链接；
- 当前两层运行门、签名身份与证据包：[运行证据索引](../scene/semantics/runtime-evidence-index.md)；
- 实施顺序、批次决策与历史批次索引：[Scene 播放能力开发计划](../scene/scene-capability-development-plan-2026-07-22.md)；
- 逐样本视觉基线与用户实机观察目标：[21 样本评估](../scene/scene-sample-assessment-2026-07-22.md)。

当前差距的定性结论（详情见上述入口）：

- **执行子集是受限白名单，不是通用引擎**：十一类 strict effect backend、puppet bind-pose、20 个程序化 built-in 粒子纹理和受限 provider/dependency 链都按完整 fingerprint 准入、fail closed；generic material/shader executor、真实 history consumer、generic compose、condition/function 未实现。
- **每新增一个 strict backend 仍重复 texture/state/target 调度基础**：下一步应提取共享 material pass executor、stock shader registry 和 shader preprocessing IR，而不是继续复制每个 effect 的调度代码。
- **动态系统仍不完整**：Timeline 无 IR、SceneScript 无运行时、音频/媒体桥未接；Puppet 已有严格单 clip MDLA/full-TRS/CPU LBS，但没有插值、mixing、动态 attachment follow、constraint/IK/physics。粒子只有 strict static/default-static/eventspawn/natural-eventdeath/eventfollow 与持续/混合 child emitter 子集，non-identity transform、collision/delete/nested child、动态文字 producer 和大量 effect 时间语义仍决定许多样本的核心动态差距。
- **正确性与健壮性遗留**：PKG reader 逐 entry 重复解析整包、`entryCount` 缺上限、每屏重复解码上传纹理、无按屏刷新率/目标 FPS/后台节流；这些不阻塞当前门但在性能预算阶段必须关闭。
- **产品闭环缺口**：无按屏 pause/resume、FPS/音量/画质策略；用户属性的 Texture Variants、media、transform、particle/audio target 未闭环。

## 6. Scene 演进方向

### 阶段 0：产品边界与执行门（已确定方向，进行中）

当前仍选择"可审计的兼容 Runtime"方向。Effect-definition IR、authored graph planner、ShaderContract v1、十一类 strict backend、ordered strict chain、resource identity/property fallback、file-backed `sceneTexture`、Frame Context、B0 live program、direct dynamic text、同帧 copy/swap、受限 unique history、Precise Blur interleave/legacy compose、exact Shake/Foliage Sway/Water Ripple/Water Waves/Water Flow/X-Ray、Puppet 严格单 clip LBS、strict depth-one static/default-static/eventspawn/natural-eventdeath/eventfollow child、持续/混合/duration child emitter、root child aggregate budget、有限 static origin translation、22-key built-in registry、非音频 turbulent velocity，以及 `3769688830`/`3768903841` 暴露的公共合成缺口已完成。隔离 45 样本 census 已记录 static/default-static 119 条，其中 14 条 identity declaration 与 `snowstormfog` 有限 origin declaration 已执行，其余 104 条 non-identity static 先受 nested profile 阻断；collision/delete 0、inherit-value 0、非空 child CP mapping 0。两条 event child scale probe 分别被 world-space root 与 world-space Rope Trail root 阻断，没有新增执行层；当前批次优先级以 [开发计划的当前批次优先级](../scene/scene-capability-development-plan-2026-07-22.md) 为准：下一代码批处理 nested ownership、递归深度与跨层总预算。route-only、内部 blocker 数和跨样本视觉分数都不能单独决定优先级。

### 阶段 1：正确性、安全和性能基础

1. B0 property 主链已建立 typed DynamicValue/target registry、v22 binding program、per-surface snapshot、原子 live state，以及 layer alpha、solid-only color、direct dynamic text、strict Local Contrast/Opacity consumer。新增 live target 必须同时注册 compiler target、真实 consumer、fallback 与 identity 门；visibility 仍不得仅靠现有路径取消整场重建。
2. B2 ordered strict effect-chain、target allocation、pass ordering、同帧 copy/swap、受限 unique FBO history seed/clear、Precise Blur interleave、exact legacy compose、最终合成原子性、十一类 strict backend 与当前 Water/Blur/X-Ray 真实 chain 已完成；generic compose 和真实 history consumer 未完成。`2998757800` 的右下亮边在 `fog1` 完全透明时仍存在，当前证据不支持继续调暗 fog；Flare 的 non-audio turbulent velocity、strict eventfollow owner、持续/混合/duration child emitter、root aggregate budget 与三张缺失 built-in 纹理已执行，layer 260 可见且无持续过曝；strict static/default-static child 也已在两个定向样本恢复可见第二层叶片。
3. B1 已用 dynamic text 验证 per-layer generation、stale cancellation 和 last-ready fallback；下一步补通用 metadata/status/cancel，再接 Texture Variants、video/system/media、通用 material 与 effectful/nested/child source。
4. 在同一 target/frame 合同上横向接通 Timeline core、SceneScript core、cursor/audio/media snapshot，并补高频 particle atlas/multi-texture、world/child/control point/rope/audio/collision 最小闭环；每类都要有作者关闭反例和失败降级。
5. 最后用固定矩阵与 Windows golden 集中校准字体、视差、粒子和效果精度；在视觉主链之外继续补 PKG header/entry/解包边界、索引与纹理复用、按屏刷新率/FPS 和性能预算。

验收标准：无样本 ID/名称特例；effect/pass 顺序、live 输入和 dependency GPU 成败可审计；未声明能力保持关闭；逐步扩充的代表 Scene 矩阵在 image/solid/text/particle、位置、方向、alpha、层级和释放上无回归。损坏包仍须受控失败，同一 pkg 不应重复全量解析。

### 阶段 2：补齐 Scene Lite 产品链

1. 扩展现有 Scene 用户属性 target，补 sceneTexture、media、transform、particle/audio 参数和无重建热更新；保留独立编辑窗口。
2. 在 live value 主链上补齐动态 text/container 和可靠的视频纹理生命周期。
3. 接入按屏 pause/resume、睡眠/锁屏、Space、遮挡、电池和屏幕热插拔。
4. 增加 FPS、音量、画质/降级策略与 per-display 状态。
5. 建立 Scene 样本 fixture、截图 baseline、诊断报告和性能预算。

完成该阶段后可以稳定交付“Scene Lite”，但仍不能声明通用 shader、SceneScript、完整粒子兼容或 Wallpaper Engine parity。

### 阶段 3：兼容 Runtime 能力

如果产品目标是接近 Wallpaper Engine Scene，需要按依赖顺序建设：

1. 材质模型、shader translation/execution、render state 和真实多 pass。
2. 扩展 text、sprite、video、composite 与 particle renderer；当前静态 text、2D sprite、built-in drop/trail 和 bounded dependency 只作为已落地起点。
3. SceneScript 沙箱、事件、时间、输入和属性桥接。
4. 音频响应、puppet、内置 assets 和版本化兼容策略。
5. 每一类能力都必须用固定样本和图像差异验证，不能只凭“成功启动”验收。

这一阶段是独立渲染引擎项目，不应与普通 App 功能迭代混在同一里程碑。

## 7. 建议的近期里程碑

### M1：Web 用户可见阻断清零（已完成）

- 已关闭文件类型推断、纹理 WebGL 路由、旧式颜色数组和空文件根占位符问题。
- `923576681` 已具备隔离文件属性、DOM、资源、交互和截图证据。
- `3700131876` 和 `3700928191` 的雨滴回归已从属性回调顺序根因修复；两样本双帧动态证据通过。
- 当前没有已确认的宿主 P0 Web 问题。

### M2：Web 强证据回归门（已完成）

- 已固定 10 个代表样本并加入能力标签、最低等级、最低 coverage 和批次禁用短板。
- benchmark 已增加 WebView/Canvas/当前进程窗口视觉像素、同源运动、DOM、主动音频和自动 pointer/click/drag/wheel 断言。
- 当前独立偏好域固定门结果：平均 98.2、coverage 94.3%、10A；当前最终完整门为平均 97.7、coverage 95.9%、32A/2B；作者源码门为 98.8 / 97.9% / 5A；Steam CDN 门为 98.0 / 94.8% / 3A。四层门均通过。
- 音频生产链已按 Wallpaper Engine 契约输出 signed stereo 64+64 布局，并在分发边界应用兼容幅度响应；受控系统音源验证频率、幅度和声道，Debug fixture 只用于确定性桥接和样本视觉回归证据。
- coverage 未设为 95% 的原因是部分样本没有媒体节点或特定能力事件，不能用伪造事件抬高覆盖率；单样本关键门禁优先于平均 coverage。

### M3：Web 生命周期与性能闭环（进行中）

- 已完成 Web-to-Web 切换、loopback 启停、WKWebView 释放、Web 音频需求启停、重叠睡眠/锁屏恢复、CoreAudio 配置失效重建、Space/屏幕 observer 和最终 stop 零状态门禁。
- 2026-07-22 已刷新当前 HEAD 的 34+5+3，三组矩阵门均通过。随后完成真实 OS/设备状态、Web/Video/Scene 互切、30 分钟交互运行和 2 小时 soak。
- 建立单屏/双屏 CPU、GPU、内存、功耗和缓存预算。
- 验收：无持续资源增长、无窗口/端口/音频残留、暂停后负载下降、恢复序列可诊断。

### M4：Web 发布闭环（进行中）

- 已建立当前 34 样本完整基线、5 样本作者源码能力门和 3 样本 Steam CDN 代表门；后续维护样本、源码 revision/CDN 更新时间与例外复审。
- 已完成可控双声道真实音频到 JS bin 的频率、幅度、声道、确定性睡眠/锁屏和配置失效重建回归；后续补物理设备切换的真实通知、真正系统静音、实际 OS 睡眠及最终画面时间对齐。
- 已完成当前非沙盒发行链的 file/directory 更新、A/B/A、跨重启移动恢复、reset 和偏好隔离门；后续固定执行 NSOpenPanel 与签名沙盒授权 UI 回归。
- 将固定矩阵、生命周期和性能报告接入发布 checklist/CI。
- 正式收口 `dedicatedHostPlaceholder` 和 daemon diagnostics harness 的边界。

### M5：Scene 基础质量收口

- 已建立 13 个真实 Scene 样本、签名身份、Metal 非黑双帧、语义字段、动态像素、dependency GPU 完成和 surface 释放门，样本覆盖层级/有效可见性、MP4 payload、作者与 built-in sprite 粒子、静态文字、脚本密集图层、音频声明和更多 effect。
- 十一类 strict backend、ordered strict chain、Bloom、程序化 solid、静态与 direct-property 动态 text、camera cover/显式 parallax、受限水波/合成、pointer-driven X-Ray、built-in 粒子纹理/sprite trail、utility/named target、静态 image blend、file-backed `sceneTexture`、Frame Context、B0 live 主链、受限 unique history、Precise Blur interleave/legacy compose、exact stock Shake/Foliage Sway/Water Ripple/Water Waves/Water Flow，以及 Puppet bind-pose/静态 attachment 已落地；v24 保存 attachment name/bind frame。非阻断 preview 和 SceneBake MP4 方向性门已建立。下一批以 [覆盖台账](../scene/semantics/coverage-ledger.md) 和 [Scene 播放能力开发计划](../scene/scene-capability-development-plan-2026-07-22.md) 的新增样本与公共能力顺序为准。
- Scene 属性当前通过独立窗口编辑受支持 target；实际可执行的 texture key 支持 PNG/JPEG 选择和恢复作者默认，不再把未实现 target 伪装成可调控件。
- 继续移除效果硬编码，修复 PKG 边界与重复解析，并建立 CPU/GPU/显存预算；样本只作验收，不新增 ID 适配。

## 8. 最终判断

Web 的运行主链已从“基本可用”推进到“有固定、作者源码、Steam CDN、完整四层兼容门、远程网络降级门、真实音频证据、文件跨重启恢复门、确定性系统中断恢复门、配置失效重建门、Space/屏幕 observer 门和释放门”。2026-07-22 当前 HEAD 的 34+5+3 与独立偏好域 10 项门均全绿；Google Fonts 在国内无直连或代理失效时不再阻塞启动，Web 音频也已从重复的桌面假波形改为按需 signed stereo FFT，并补回旧样本依赖的兼容幅度响应。当前可声明“当前构建 34+5+3 的已知样本功能兼容闭环、当前非沙盒发行链的 Web 文件服务持久化闭环、Web 音频宿主主链及确定性睡眠/锁屏、配置失效和 Space observer 恢复闭环”；仍不能声明“发布级最终完全闭环”或“以后所有样本都会成功”。后续应集中完成 runtime 互切、物理设备与真实 OS 状态、长期资源预算、真实 UI/签名沙盒授权回归和发布流程接入。当前专用 WKWebView 宿主、受控资源协议、按需 loopback 和结构化诊断路线应继续保留，不应改回宽权限 `file://` 或引入重复宿主。

Scene 的基础架构成立，运行能力仍是明确子集，并已有签名 App、45 个真实目录隔离样本快照加 13 个固定回归样本、Metal 双帧/语义/dependency/strict graph/释放门，以及 preview/SceneBake 同样本方向性证据；`3770500543` 因缺少 package 未进入运行矩阵。v25 已闭合 direct text 动态 provider、Puppet bind-pose/静态 MDAT/严格单 clip LBS、strict depth-one static/default-static/eventspawn/natural-eventdeath/eventfollow child、持续/混合/duration child emitter、root child aggregate budget、有限 static origin translation、22-key built-in registry，以及非音频 turbulent velocity；B2 已有同帧 copy/swap、受限 unique history、Precise Blur interleave/legacy compose 和十一类 strict backend。`3769688830` 的静态挂点已恢复，`3750813609`/`3766387484` 的 static child 第二层叶片已恢复，`3088601835` 的 Snow root layers 与 `snowstormfog` child 已恢复，BC 白 matte 与折射粒子白块假阳性已消除，受限樱花/光束/火焰/双光束/Flare/Snow/Smoke 粒子已进入 runtime；`3768903841` 仍只有 authored 首帧 fallback。十一类 strict backend、当前完整门 15 条 chain、固定门 2 条 chain、direct text、22 个 built-in 粒子纹理、自建 turbulent noise 与严格 child 子集仍不等价于 authored shader execution、真实 history consumer、SceneScript/media、完整 Puppet、完整 child/event 或 WE 数值/像素等价。当前可以声明受限能力可用和同样本视觉变化可审查，不能声明达到或接近 WE parity。下一代码批处理 nested ownership、递归深度与跨层总预算；event scale 等各自 root 能执行后再恢复。
