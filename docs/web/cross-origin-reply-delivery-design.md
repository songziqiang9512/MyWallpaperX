<!-- document-role: active-plan -->
<!-- retirementCondition: 所有宿主消息消费者使用同一 frame 定向投递并通过导航和跨源门，旧主 frame 中继撤权后归档。 -->

# D5 — Web 跨源 frame 定向回包与宿主推送

> 复核基线：2026-10-01，独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；已合入 `codex/engine-refactor-program`；实施时按其最新代码重新核对所列 owner，以下行号仍指向原设计基线。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

宿主请求回复只回发送它的有效文档 frame；属性、暂停、音量、频谱和目录变更向所有已注册且有权限的 frame 投递。跨源身份由 WebKit 提供，不访问别源 contentWindow 属性，不放宽网络/本地文件准入。横跨 Lifecycle、RuntimeBridge、DirectoryWatchers 与注入时机。

五判据：横切多个 owner 或主链节点=是；触碰唯一权威合同=是；用户可见且难逆的 API/数据/发布合同=否；触碰机器冻结结构家族=否；依赖官方或平台外部证据=是。

## 当前事实与证据

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift:317` 收 random-file 请求，`:327` 不指定 frame 回包；`:336` 网络请求没有传递 message.frameInfo。
- 同目录 `DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift:672` 的 resolveNetworkRequest 在 `:681` 默认主 frame 执行；`:319`、`:354`、`:398`、`:423` 的状态推送也如此。DirectoryWatchers 的 `:60`、`:76` 同类。
- 同目录 `DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift:60` 兼容脚本仅 main frame；播放门在 `:48` 已注入全部 frame。交接提及的 `wallpaperRelayHostPushToChildFrames` 在此基线没有命中，不能假设中继已存在。
- [Apple WKFrameInfo](https://developer.apple.com/documentation/webkit/wkframeinfo) 明确它是瞬时数据对象，不是跨 delegate 调用的唯一 frame ID；[frame-targeted evaluateJavaScript](https://developer.apple.com/documentation/webkit/wkwebview/evaluatejavascript(_:in:contentworld:)) 可指定 frame/world，失效 frame 返回 invalid-frame 错误。2026-10-01 复核。

## owner

现役 adapter 的每 webView/navigation 生命周期拥有 frame delivery endpoints；Lifecycle 捕获 `WKScriptMessage.frameInfo`，RuntimeBridge 执行唯一投递，DirectoryWatchers 只产生 typed payload。兼容脚本只消费本 frame 的状态，不充当跨源路由器。

## 方案设计与选型

选择 **(b) 宿主 frame 定向投递**。候选 (a) 请求侧判据让跨源请求回原生，能缩小挂起问题，但无法覆盖无请求的属性/暂停/目录推送，只作为迁移期间的未注册 frame 策略。

1. 把需要的兼容 receiver 在 document start 注入所有允许 frame；不把整个主 frame bootstrap 无条件复制，因为 ready、资源根和页面媒体 owner 有主 frame 语义。主页面 ready 仅由 `frameInfo.isMainFrame` 驱动。
2. 每个文档注入生成非持久 document nonce，hello 经 message handler 上送。宿主校验真实 webView、session/navigation generation、frameInfo.securityOrigin 和既有权限，然后向该 frame 回发宿主生成的 endpoint token。nonce/token 用于路由相关性，绝非提升资源权限的凭据。
3. 不用 URL、origin 或 WKFrameInfo 的对象相等性作为 frame 主键。保存 generation+endpointToken、最新 frameInfo、文档 nonce 和订阅；每个请求的 reply context 捕获其发送时 frameInfo 与 request ID，body 中自称 frame ID 不能替换它。hello 不得凭 body 中的旧 token 覆写已有 endpoint；续约由宿主向已有 endpoint 的 frame 发 challenge，receiver 确认本地 nonce/token 后才更新 lease。上限先定每 webView 128 个 endpoint、256 个在途请求，作为项目初始预算接受压力门后冻结。
4. 采用 `.page` world 调用页面兼容 receiver，使用结构化参数或既有安全 JSON quoting。接收端验证 nonce、generation、单调序号和请求 ID；旧文档迟到回复不结算新文档同名请求。
5. 主导航、web content process termination、surface teardown 撤销所有 endpoint 与未完成请求；子导航产生新 hello。无公开稳定子 frame ID 时不猜旧/新映射：旧记录在 invalid-frame、受限 lease 失效或容量回收时撤销；新 hello 重放当前快照。lease 初值 60 秒、存活文档每 20 秒续约，暂停状态续约由宿主调度，不依赖冻结的页面 RAF。
6. 请求回复不广播；状态推送逐 endpoint 投递。属性/暂停保持序号有序，频谱只保留最新一份并限制每 endpoint 一个在途调用，禁止慢 frame 形成无界积压。hello 完成先重放完整快照，随后收增量。
7. 对跨源 frame 仍用现役网络目的地/可读资源根策略；frame 定向只修回包，不授予任意文件、私网网络或主 frame 特权。

## fallback / route

注册前 fetch/XHR 走原生能力；宿主专属 random-file 返回明确不可用而非悬挂。无效 frame 的回包取消且不改发 main frame；单个 endpoint 失败不影响其他 frame。迁移选择每 frame 一个 route，定向路径启用后关闭它的旧中继，避免重复推送。原生 setAllMediaPlaybackSuspended 继续覆盖 media，JS 调度门覆盖所有注册 frame。

## 纠正门

- 真 WKWebView fixture：同源、两个不同源、嵌套 iframe、动态插入、about:blank/srcdoc、sandbox opaque origin 分别验证注册与权限。每 frame 使用相同 request ID，回复只能匹配发送文档。
- 请求在途时子导航/主导航、删除 frame、进程退出、重建 webView、跨屏；迟到回包不得到达替代文档；反例使用真实 completion 错误而非字符串断言。
- 检查每 frame 的属性/音量/目录/暂停/恢复/频谱事件次序和次数，恢复保留作者自暂停；主 frame ready 不因子 frame 重复触发。
- 洪泛注册/请求、慢 frame、nonce 重放和 origin 伪造不能扩大权限或内存；自动化门通过后记录 macOS/WebKit 版本和本地多源 fixture 执行身份。

## 退役条件

上述消费点同批迁移，旧中继消除且 Web 现役状态接管事实后归档。本文只批准投递合同，不证明远程任意网页已兼容。
