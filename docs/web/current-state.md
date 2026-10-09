# MyWallpaperX Web 现役状态

> 状态：Web 当前状态唯一入口
>
> 源码复核：2026-08-11；共享暂停链路复核：2026-09-28；宿主缺陷与导航合同：2026-09-30；收尾修复（loopback 会话因子 / frame 硬门 / 暂停回合 / store 回收归文档）：2026-09-30；Web 引擎缺口批（mwx-local 百分号合同 / fetchall 去抖 / XHR open 清理 / loopback 上限 / @import 限定符）：2026-10-09
>
> 证据边界：2026-09-28 共享暂停批已完成 Debug 构建、实际 WKWebView 暂停测试与隔离 Scene 子进程验证；没有重跑 Web 样本矩阵。2026-09-30 宿主缺陷批按 229a6b25 / c5719a0d 的记录完成免签名 Debug checkpoint 构建（退出码 0）与 F01/F29/F40 的 node vm 拼接 15 段注入脚本实跑，但没有在同一身份跑运行门（无 App 运行、无样本门）。导航/兼容脚本收敛批与收尾修复批（同一工作树，未提交）批内实际执行：`py_compile`、`swiftc -parse`、门禁选择器干跑（inner/checkpoint），以及**真实 WKWebView harness 实跑**——`test_web_compat_parity`（F01/F19/F29/F40/frames 全过）、`test_web_playback_pause`（暂停/恢复、帧边界与 AudioContext 暂停回合）、`test_web_navigation_policy`、`test_web_response_transformer`、`test_web_static_content_signals`、`test_web_display_conditions`。未执行 App 构建、`swiftc` 类型检查（只有语法解析）、`checkpoint` 构建与任何样本门。

本页回答 Web 当前生产路径由谁拥有、哪些结论只有源码证据、哪些发布项仍未闭合。长期语言、进程与性能边界统一由[技术栈与架构路线边界](../architecture/technology-stack-boundaries.md)规定；测试证据口径由[Web 壁纸运行能力评测标准](web-wallpaper-benchmark-standard.md)规定。

## 1. 当前生产所有权

| 系统 | 当前所有者 | 当前边界 |
|---|---|---|
| 项目解释 | `SteamWorkshopService` 的 Web Core | 原始 `project.json` 是声明源；构建 descriptor、runtime model、playback context 与诊断，不覆盖作者文件 |
| 播放协调 | `WallpaperEngine` | 保存当前 Web request/content/property 状态，执行共享暂停结果，处理属性、音频需求、显示器与 runtime 切换 |
| 暂停策略 | `PlaybackPolicyController` → `PlaybackCommandMultiplexer` | 四个节能开关与锁屏/休眠统一控制 Video/Web/Scene；手动暂停独立保留，Web 不再额外按低电量模式暂停。归属与验证边界见 [E2b](../scene/roadmap/engine-refactor-program.md) |
| 生产宿主 | `DedicatedWebWallpaperHostPlaceholderAdapter` | 当前唯一生产 Web 宿主（`WallpaperEngine.dedicatedWebHostAdapter`，`WallpaperEngine.swift:73`）；负责每显示器 WKWebView surface、生命周期、输入、属性、音频和本地资源桥接 |
| daemon Web 路径 | 无 | 旧宿主策略切换与 `.daemonDiagnosticsHarness` 已随 aee7c08a 删除；daemon 不再持有 Web 宿主，扩展第二套宿主仍需先有可复现证据 |
| 本地资源 | `WebWallpaperLocalSchemeHandler` 等 | 受控读取项目根、MIME/响应转换和兼容资源映射；不能扩大为任意文件访问。loopback 档另受「入口前缀 + `SameSite=Strict` 会话 cookie」双重凭据约束 |
| 持久化 WebKit store 回收 | `WebWallpaperDataStoreReclaimer`（装配层注入在用事实） | 只按「曾见过 + 新投影缺席 + 模块删除意图」判删除（`confirmedDeletedRecordIDs`，`WebWallpaperHostTypes.swift:471`）；宽限期末按实时在用事实复核，未回收必有 `MWX WEB DATASTORE REMOVAL` 日志；派生标识为 SHA256（`+Surface.swift:370`）。用户可见后果：highCompatibility 用户既有 scoped store（旧模 256 派生的 localStorage）不会被新算法再次命中，等于重置，旧 store 由孤儿退役清理；未接入显示器期间创建的 scoped store 也按孤儿回收，该屏重连后 store 重建 |
| 评测工具 | `script/web_wallpaper_benchmark.py` 及矩阵 | 采集 App 身份、日志、DOM/窗口/动画证据；没有 fixture 时不能伪造 PASS |

当前生产 Web 播放链为：

```text
project.json / Workshop directory
  -> ResolvedWebProjectDescriptor
  -> ResolvedWebRuntimeModel
  -> ResolvedWebPlaybackContext
  -> WallpaperEngine
  -> DedicatedWebWallpaperHostPlaceholderAdapter
  -> per-display WKWebView surface
```

`Placeholder` 是尚未完成命名收口的历史名称，不表示该类型没有产品执行权。重命名必须作为独立机械批次完成源码、测试、日志 schema 和文档同步；不得同时改变宿主行为。

## 2. 稳定实现合同

- 原始 `project.json`、目录和资源布局保持只读；本地 descriptor/cache 是派生执行数据，不反向改写样本。
- loopback（`httpLoopback`）档的受控资源访问是双重凭据：入口 URL 携带 `/mwx-<token>/` 前缀，入口 HTML 响应另下发 `SameSite=Strict` 会话 cookie（`WebWallpaperLoopbackServer.accessCookieHeader`）。页面 origin 下以 `/` 开头的 Web 根绝对路径（`<img src="/x">`、`fetch('/x')`、`new URL('/x', origin)`）按 cookie 放行，其余无前缀请求仍是 403；跨站页面无法携带该 cookie，未持有 token 的本机进程同样拿不到。合同落点 `WebWallpaperLoopbackServer.authorizedRequestPath(_:cookieHeader:)`。
- 兼容脚本的 frame 门（顶层 frame 才发屏幕级信号）是行为边界的第一层；宿主对任何 frame 都能直投的 `window.webkit.messageHandlers.*` 消息按 `WKScriptMessage.frameInfo` 二次判定：`wallpaperHostInteractiveRegions` 与 `wallpaperHostRandomFile` 只接受主 frame，`wallpaperHostLog` 的 `dom.ready` 副作用只认主 frame（日志按来源 frame 标记），网络桥接的在飞配额按 frame 分桶，子 frame 不得耗尽顶层配额。
- 暂停快照按宿主暂停「回合」记录，不按每次应用的观测状态重写：同一暂停被重复应用（种子期、`dom.ready`、DCL/`load` 兜底重放、`applyPausedState`）时，宿主自己的 `suspend()` 不得被记成作者挂起；`AudioContext` 与媒体节点在恢复时只重放未被作者暂停者。DCL 与 `load` 是同一属性重放的互斥兜底（先到者取走一次性标志并撤销另一侧），不是两次重放。
- Web 与视频、Scene 的产品状态分离，但共享高层播放切换、显示器、系统中断和音频采集合同。显式暂停由 WebKit 原生媒体门与所有 frame 的页面调度门执行，冻结 RAF、定时器、CSS/Web Animations；恢复保留作者自行暂停的动画。调度门不接管 Web Worker 等独立执行域，不承诺冻结任意后台计算。
- 每个播放 request 使用显式 identity；旧 navigation、旧 surface、旧 property replay 和旧异步回调不得修改新 request。
- Web 项目通过受控本地 scheme 和明确的资源根加载，不以任意 `file://` 权限换取兼容。mwx-local 请求路径的百分号合同：三条生产路径（入口构造、randomFile/`__absolute__` 逐段编码、页面 `encodeURIComponent`）都恰好编码一次，resolve 侧取 `percentEncodedPath` 按段解码恰好一次（`WebWallpaperLocalSchemeHandler.decodedRequestPath`，`+Resolve.swift`）——既不做第二次整体解码（字面 `%XX` 文件名会解析到错误路径且缓存键碰撞），也不用 `URL.path`（它把段内 `%2F` 解码成路径分隔符）。
- Wallpaper Engine property、audio、media、pause、input 等桥接按声明和需求启用；存在 handler 或路由不等于用户可见行为已经通过。
- macOS 桌面输入不宣称与 Windows Wallpaper Engine 等价。单宿主的 click-through、hit test 和短时接管必须以“不吞桌面输入、不产生长期 focus/Space 副作用”为上限。
- 不新增第二套生产 Web 宿主。只有现有宿主无法满足且有可复现证据时，才允许提出替代方案；替代必须同批撤销旧 owner。

## 3. 当前证据状态

| 结论 | 当前证据 | 可表述范围 |
|---|---|---|
| 四层 project/runtime 模型存在 | 当前 Swift 类型和调用链 | 可称“源码已实现”，不能据此称所有项目可运行 |
| 生产 Web 宿主唯一 | `WallpaperEngine.dedicatedWebHostAdapter` 的唯一装配（`WallpaperEngine.swift:73`）与 `WebWallpaperHostAdapter` 协议 | 可称“当前代码只有一个生产 Web 宿主”，不能据此称多显示器或发布环境无回归 |
| 本地资源、属性、输入、音频与生命周期实现存在 | 当前 Core/Host 源码 | 只能证明对应路径存在，用户可见兼容仍以运行门为准 |
| 2026-07 固定、完整和外部样本结果 | [统一历史索引](../history/README.md)中的 dated roadmap 与 baseline | 只作为历史比较基线，不代表当前 HEAD PASS |
| 共享暂停执行（2026-09-28 身份） | `test_playback_policy`、`test_playback_policy_delivery`，以及 `test_web_playback_pause` 中真实 WKWebView + 生产兼容脚本 + 原生媒体门 | 该身份上已验证设置持久化与组合、暂停/恢复、iframe、媒体不能自行重启、作者暂停保留；该身份之后兼容脚本与宿主文件已被 aee7c08a、229a6b25 等批改动，重新表述当前 HEAD 必须先重跑 `test_web_playback_pause`（本批未运行）。物理电源/锁屏/多显示器与任意远程网页仍未验收 |
| 2026-09-30 Web 宿主缺陷批（F01/F02/F04/F19/F20/F29/F37/F40） | 229a6b25 提交记录（含免签名 Debug checkpoint 构建退出码 0、F01/F29/F40 的 node vm 实跑）与 c5719a0d（F02 DEBUG-only 运行时探针，checkpoint 构建 exit 0）；F 编号源 [2026-09-30 UI 代码审查](../history/cross-topic/ui-code-review-2026-09-30.md)，该文声明修复结果以工作树与提交历史为准 | 可称“八项缺陷已按批落地并附探针”；该批没有在同一身份跑运行门，修复效果不能称已验证 |
| 2026-09-30 导航/兼容脚本收敛批 + 收尾修复（本批，工作树未提交） | 收尾修复批实跑 `test_web_compat_parity.py`（F01/F19/F29/F40/frames 五场景，真实 WKWebView）、`test_web_playback_pause.py`（含新增的 AudioContext 暂停回合断言）、`test_web_navigation_policy.py`、`test_web_response_transformer.py`、`test_web_static_content_signals.py`、`test_web_display_conditions.py`；`scene_validation_gates.json` 的 `web-host-lifecycle` 现覆盖 Support 目录（scheme handler / loopback server 与 connection）、Modules web 运行时缓存与校验路径 | 可称“资源服务、暂停/恢复、frame 边界与属性路径已有可复跑断言，并进入宿主文件的 focused 选择”；**未运行** App 构建、`swiftc` 类型检查与任何样本门。资源服务批（scheme handler / loopback keep-alive / 流式交付）没有专属测试模块，只由 focused 组的既有 Web 模块间接覆盖；本批以 checkpoint 档起步 |
| 2026-10-09 Web 引擎缺口批（本批，工作树未提交） | 实跑：`test_web_response_transformer`（新增 mwx-local resolve 百分号合同断言——swiftc 编译生产 Support 源，修复前 HEAD 逻辑反证 FAIL "literal %20 filename must resolve to itself"；新增 Google Fonts @import 裸 `screen` 限定符改写与复合媒体保留断言）、`test_web_playback_pause` 与 `test_web_compat_parity`（真实 WKWebView 装配全量兼容脚本，XHR open() 清理改动入链）、`test_web_navigation_policy`（补 D5 `frameEndpointRegistry` 桩，清偿 ff267b62 落地时的预存红）、`test_playback_policy_delivery`、`test_web_display_conditions`、`test_web_static_content_signals`；loopback cluster（Server+Connection+SchemeHandler+Transformers）`swiftc -typecheck` 通过；XHR open() 清理语义经 node vm 原型访问器探针验证；隔离 DerivedData Debug 构建（退出码 0，`** BUILD SUCCEEDED **`） | 可称五项缺口（mwx-local 双重解码 / fetchall 事件无合并 / XHR 实例访问器残留 / loopback 无上限缓冲与滴流续窗 / 裸 screen @import 漏改写）已按批落地并有可复跑断言；实机多显示器与真实网络不可达场景未验收 |
| 2026-10-09 Web 运行时缓存主线程重构批（B27，工作树未提交） | 实跑：`web_property_persistence_gate`（隔离 workshop 副本 + 空 HOME + 本批隔离 DerivedData 构建，**PASS**——三阶段×三次 App 启动、A→B→A 三次 web 启动、运行时缓存冷写/热校验全链路；顺带修复该 gate 的预存断裂：整库扫描自 875a104a 起异步单飞而 debug runner 仍 reload→同步 guard，`samples-required` 恒失败，本批为 runner 补 `awaitInstalledRecord` 有界等待）、`test_web_playback_pause` / `test_web_compat_parity`（真实 WKWebView）、`test_web_response_transformer` / `test_web_navigation_policy` / `test_web_display_conditions` / `test_web_static_content_signals` / `test_playback_policy` / `test_playback_policy_delivery` / `test_debug_scene_product_entry_policy` 全绿；隔离 DerivedData Debug 构建 `** BUILD SUCCEEDED **`（含 IsolatedConformances 零残留：清单值类型显式 nonisolated） | 可称：点击播放热路径不再做任何文件 IO（读盘/签名扫描/比对全在 detached 段）；冷路径扫描+编码+双清单写盘下沉后台；preload 逐记录让出主线程；未覆盖：冷路径的 descriptor 解析（读 actor 状态）与 `loadCachedWebProjectDescriptor` 分析缓存校验仍在主线程（属性面板打开路径，后续批） |
| 2026-10-09 Web 点击代际批（批三，已提交 34b386ec） | 实跑：`web_property_persistence_gate` PASS（同批二口径，隔离 workshop 副本+空 HOME+本批构建，三阶段三 App 启动全过——单启动路径无回归）、`test_web_playback_pause` / `test_web_compat_parity`（真实 WKWebView）、`test_response_transformer` 等七个焦点模块全绿、隔离 DerivedData Debug 构建 SUCCESS。代际逻辑本身（双击/同名重击/跨类型点击/早退超跃/preload 抢占七场景）由独立子代理审查按 MainActor 串行化对抗推演闭合，未做双击实机序列 | 可称：web 异步启动的完成序倒置已由每点击代际关闭（旧请求的迟到通知与失败出口整体退役且不触碰共享状态）；preload 任务句柄竞态同步关闭（被抢占任务只清自己的句柄）。未覆盖：真实 UI 双击连点序列 |
| 2026-10-09 Web descriptor 记忆缓存批（批四，工作树未提交） | 实跑：`web_property_persistence_gate` PASS（隔离 workshop 副本+空 HOME+本批构建）、`test_web_playback_pause` / `test_web_compat_parity`（真实 WKWebView）、`test_web_response_transformer` / `test_web_navigation_policy` / `test_web_display_conditions` / `test_web_static_content_signals` / `test_playback_policy_delivery` / `test_web_property_persistence_gate`（评分器）全绿；隔离 DerivedData Debug 构建 SUCCESS | 可称：`resolvedWebProjectDescriptor` 的四个同步调用面（属性面板 rebuild / 详情页 / 诊断 / 宿主桥解析闭包）在 mtime 态未变时零 IO 返回（`webProjectDescriptorCache`，与 `webValidationReportCache`/`webRuntimeModelCache` 同一 mtime 键纪律，失效钩子同步）；本会话后台保存段写入的分析清单在会话内校验免再扫（会话新鲜快速路径，跨会话清单仍逐次全量签名比对）。设计取舍：descriptor 保持同步 API——四个调用面是同步 UI 表面（列表行渲染/宿主同步闭包），全异步化不成比例；首个未命中的冷解析/跨会话校验仍在主线程（有界，一次每 mtime 态）。未覆盖：主线程冷解析的下沉（需 actor 输入快照重构，独立设计批）、真实 UI 双击连点序列 |
| 当前 HEAD 发布级 Web 闭环 | 本批未运行 | **未验证**，不得写成已完成 |

新的“当前 PASS”、样本数量、得分、coverage、Team ID、CDHash 或报告路径只能在同一源码/构建身份完成正式门后写回本页；被替代的历史数字收入统一 history，不复制到 README 或长期技术规范。

### 兼容脚本与宿主语义取证记录（2026-09-30）

本批按 `docs.wallpaperengine.io` 公开文档核对兼容脚本与宿主导航语义；只做了兼容脚本 JS 的语法自检、`xcrun swiftc -typecheck` 与源码核对，没有重跑隔离样本或运行门，因此下列结论只能称“按官方文档/保守行为落地”，不能称已验证。

- **媒体集成 payload**：Media Integration 页给出官方字段集——`MediaProperties` 为 `title` / `artist` / `subTitle` / `albumTitle` / `albumArtist` / `genres` / `contentType`，`MediaThumbnail` 的 `thumbnail` 是 base64 PNG 并带 `primaryColor` / `secondaryColor` / `tertiaryColor` / `textColor` / `highContrastColor`，`MediaStatus.enabled` 表示“用户是否启用媒体集成选项”。据此补齐 payload 字段（无源字段空串、缩略图五色用离线 canvas 取色、`enabled` 改由宿主设置驱动，宿主当前无该开关故缺省 `true`）；`thumbnail` 仍是页面 URL，未做官方 base64 PNG 化。
- **user 属性应用时机**：User Properties 页只说属性事件在壁纸加载时触发一次（"fires once when the wallpaper is loaded"），并要求把 `wallpaperPropertyListener` 初始化在事件之外；Audio Visualization 页要求不要用 `window.onload` 承载 WE 专用代码（"it's unreliable and can lead to Wallpaper Engine missing certain events"）。文档没有给出 DOMContentLoaded 与 `load` 的精确边界（取证未定案），按 DOMContentLoaded（`readyState === 'interactive'`）放行落地，`load` 只作为同一重放的互斥兜底：先到者取走一次性标志并撤销另一侧监听，两者不会各重放一次（重复重放会重复应用暂停状态，把宿主自身的挂起染成作者挂起）。
- **子 frame 注入面（含已知缺口）**：官方 Web 文档没有子 frame / iframe 注入语义的表述（取证未定案），按全 frame 注入落地——与宿主既有的暂停门、远程样式表脚本同一注入面；同时按屏幕级语义收口：`dom.ready` 只由顶层 frame 发出，交互区域登记（含 `dom-auto` 与页面显式调用）只接受顶层 frame，避免子 frame 以自身视口归一化的坐标污染宿主屏幕级命中测试。该收口是双层门：注入 JS 的顶层判定是第一层，宿主侧对 `WKScriptMessage.frameInfo.isMainFrame` 的二次判定是第二层（任何 frame 都能绕过包装函数直投 handler）；`wallpaperHostRandomFile` 与网络桥接配额同样按 frame 归属，见 §2。主 frame 收到宿主推送后向同源直接子 frame 中继：属性、一般属性、目录文件与目录访问错误、频谱、音量、倍速、暂停、被动指针状态与合成指针链（指针坐标按子 frame 视口换算）。跨源子 frame 拿到的是完整注入体本身、但收不到任何中继推送——即当前口径是「全量注入 + 同源推送」，不是 detail 里的保守选项「跨源只注入最小 API 子集」。
- **子 frame 的「需要宿主回包」请求：同源走中继、跨源回落原生**：宿主 → 页面的回包只经 `webView.evaluateJavaScript` 送达主 frame（网络回包 `DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift` 的 `resolveNetworkRequest`、随机文件回包 `+Lifecycle.swift` 的 `wallpaperHostRandomFile` 分支、目录通知 `+DirectoryWatchers.swift` 的两条推送）。主 frame 解析后把网络/随机文件回包转发给同源直接子 frame（子 frame 按自己的 requestID 认领，`+HostBridge.swift` 的 `__myWallpaperResolveNetworkRequest` / `__myWallpaperResolveRandomFile` 包装器），因此**同源子 frame** 的跨域 XHR/fetch 代理与随机文件请求能正常完成；代理请求 ID 带 per-frame 随机段（`+InteractionAndRuntimeLogging.swift` 的 `networkRequestNonce`），主 frame 与子 frame 不会互认彼此的回包。**与顶层不同源的 frame 判定为「回包不可达」**（判据 `wallpaperHostReplyReachable`，`+BootstrapFoundation.swift`，用 `window.top.document` 可访问性覆盖嵌套档；观测探针 `window.__mwxHostReplyReachable`）：这类 frame 的跨域 XHR/fetch 与随机文件请求按原生产行为处理，不进入只会等桥超时的代理路径，回落时留 `host-reply.unsupported` 诊断（`+InteractionAndRuntimeLogging.swift` 的 fetch/XHR 分支与 `+BootstrapResourceRewriting.swift` 的随机文件分支）。改动前子 frame 的这类请求一律走原生，本批注入面翻转后由上述两条修复闭合；更彻底的收敛路线（宿主按发送 frame 定向回包）仍是后续批次缺口。
- **作者暂停的媒体**：Property Listener 页对暂停只有“`setPaused` 不是必需，Wallpaper Engine 会完全冻结渲染进程”的表述，没有“恢复后是否重放被作者暂停的媒体”（取证未定案）；按保守行为落地——宿主暂停前为每个媒体节点与 `AudioContext` 写恢复快照，恢复时只重放未被作者暂停者。
- **主框架导航与外链**：抓取公开 web 章节 7 页（overview、first/gettingstarted、customization/properties、audio/media、performance、api/index、debug/debug）没有主框架导航、链接外跳或 iframe 限制的任何记载，官方语义无法定案，因此按保守分支保持取消：主框架决策收敛为唯一纯函数 `navigationDecision`（`+NavigationDelegate.swift:50`，决策枚举 `:41`）——子框架/首载/reload/同文档放行；`linkActivated` 且 http(s) 且非环回主机转交系统浏览器；环回主机（127.0.0.0/8、localhost、::1）按内部资源取消且绝不拉起浏览器（修掉 httpLoopback 档内部链接命中旧 handoff 而误开浏览器）。诊断 reason 也据此不再把未转交的自定义 scheme 点击谎报为 link_handoff；页面与探针可直接查询 `window.__mwxNavigationState` / `__mwxNavigationBlocked`（`WebWallpaperHostTypes.swift:389` 起，`+Surface.swift:52` 以 forMainFrameOnly 注入），无需依赖宿主诊断存储。

## 4. 未闭合边界

下列项在没有新证据前保持未闭合：

- 当前 HEAD 的签名 Debug/Release Web 固定门、完整门和外部样本门；
- 视频/Web/Scene 连续互切、进程崩溃与 stale request 恢复；
- 真实锁屏、睡眠、Space、显示器热插拔和音频设备变化；
- 文件选择器、security-scoped bookmark、sandbox、hardened runtime 与发布包权限；
- 首帧、切换 hitch、CPU/GPU frame time、WebContent 内存、能耗和多显示器长期预算；
- 网络离线/恢复、Service Worker/WASM/大型项目和第三方远程依赖的明确产品策略；
- `DedicatedWebWallpaperHostPlaceholderAdapter` 的命名收口；
- “所有 Workshop Web 壁纸”“Windows 行为/像素等价”之类无界兼容声明。

## 5. 开发与验收顺序

1. 从当前可复现问题建立 request、host、resource、property/input/audio 或环境根因，不从历史样本得分猜任务。
2. 修共享合同，禁止 sample ID、路径、站点或资产名特判。
3. 先跑受影响的项目自有测试和定向隔离样本；跨宿主生命周期风险再选择固定门。
4. 完整矩阵、外部样本与发布验证只在 milestone/release 或较小证据无法排除跨样本风险时运行。
5. 性能批次按长期[性能与效率合同](../architecture/technology-stack-boundaries.md#8-性能与效率合同)记录首帧、frame time、hitch、内存、能耗和恢复，不能只报告平均分或页面非黑。
6. 验证完成后同步本页的证据状态；批次过程、截图和报告细节进入 regression 或 Git，不继续扩张本页。唯一例外是 §3 末尾的取证结论小节：它只记录官方文档定案/未定案与对应的保守分支，按「同类结论替换更新、不新增小节」维护，不复制报告、截图或证据缓存。

## 6. 历史入口

- [统一历史索引](../history/README.md)：2026-04 兼容/输入方案、2026-07 Web/Scene 状态快照，以及两组代表样本基线。历史材料不决定当前开发顺序。
