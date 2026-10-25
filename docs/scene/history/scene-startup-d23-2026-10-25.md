# Scene 启动 D23：跨类型重入、强退役与空闲互斥

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-25；实施顺序和后继归[启动专项](../../development/wallpaper-startup-optimization-plan.md)。本批已完成采用链及限定运行；最终五对功能通过、原噪声门未过，不认整体性能验收完成。

## 实际改动

D22 将新子进程等待缩到 NSApplication.shared 调用窗；本批沿原 Manager/Client/Host 复用刚完成退役的 Scene 进程，加速同 App 的 Scene→Web/Video→Scene。首次启动仍需新进程，不据此宣称 C0/C1 受益。没有新增池、播放 owner、Root 授权或模型缓存，也没有搬动 AppKit 初始化。

原 endpoint.retire 接收可选已提交后继 ticket。Scene 仅在精确 active/no-pending、后继 Web/Video、原 hello 能力有效时申请强退役；普通 Stop、失败和取消继续退出。原 retireOutput 的 requireRequestRetirement=true 暂停原 inbox drain，等待原 preparation queue、已接纳 user-texture/initial-video Tasks、Session CPU/GPU 成功终态、窗口撤回及空 Host owner，再以同 operation/request/generation 的 requestRetired=true 回执。unknown、缺字段、错误类型、失败和超时不能授空闲；原精确物理退出结清旧控制与租约。

子端任务在调度前加入原 drain，取消不冒充 join；普通退役失败也停止精确子进程。频谱迟到回调复核完整 scope，成功强 ACK 前按原 FIFO 发布 none，父端空闲/强退役拒绝旧 positive demand。原 Client 单一30秒 token 绑定 transport/generation，所有 load/replay/legacy 入口沿原 latest 队列等待；新 Scene 重新认证来源、取得新 lease/request/execution，取消旧 timer 后采用同 PID。旧 ACK/TTL 不得停止新请求；空闲崩溃不重放，App quit 仍等 registry 实际退出。此资格不承诺最后 AV borrower、全部 FD 或 RSS 归零。

D23a 的切出正差促成 D23b：原 Scene HostWindow 首次展示前设置 animationBehavior=.none，保作者动画、几何、层级、窗口撤回确认及所有 GPU/租约/超时门。静态 SDK 及 Web 现存设置仅支持这个候选，不把壁钟直接解释为独占动画成本。

D23c 修复审查发现的持续额外空闲进程：原 Manager 通知携 runtime，忽略被同步重入替代的旧 epoch；非 Web 新意图取消已有 Web optional idle，非 Scene 仅停止 Scene idle/强退役保留，保仍承担回滚的 active Scene。原 handoff 实际调用时即时核当前 replacement epoch 或更新的 Scene 意图，失效则传 nil，仍执行旧 retire/done/barrier。App 把 Scene idle/strong/原 retiring map 的只读事实接入原 Web 实际空预备准入，覆盖启动3秒与提交2秒两入口；真实 Web 请求不受可选门阻断。没有新调度器、产品 epoch 副本或全局 PID 配额；“两槽”指 Web adapter 角色，物理 retiring 和多屏另按原 registry 计。

## 冻结源、最近门与真实 App

设计/合同/登记先于 A、B、C 各次产品变更。A 最近21个 CPU 方法、2个实际 Metal/AppKit 退出方法通过；最初 Session stub 少 MainActor 及 Grid carrier 缺现有字段造成的原编译失败均保留，补夹具后通过。最终 C 从完整私有冻结源执行14个最近方法、32条原生编译/执行命令，全部0、无 skip、输入未变；覆盖原取消/回滚、同类型、lease、严格字段、scope、旧 ACK/TTL、同步重入、真实 Web 准备及两处 optional 准入。C 的 task protocol 准备曾误把字符串当列表，未导入测试或启动原生命令；错误记录及实际修正保留，不算产品失败或原生通过。

两端独立审查及源/资源寿命审查未发现新增静态阻断。最终1391个 Swift 文件通过1000行门，Scene defense 保0 locked dead/18 canonical helpers/3 swallow；编译/门数不代表全作品兼容或性能。

| 实际构建 | 文件数 | source-map SHA 前缀 | 可执行文件 SHA 前缀 | 说明 |
|---|---:|---|---|---|
| D22产品＋共同 DEBUG 入口 | 5955 | 4b66e02e | 99f43b1b | D22产品字节重建；仅共同测量覆层 |
| D23a | 5956 | 720e4344 | bc092da6 | 初始强退役/保留 |
| D23b | 5956 | c7d5ead2 | 54d7f2f1 | 仅 Scene 窗口系统动画修正 |
| D23c | 5956 | 40842754 | 93df7539 | 在 B 上补原意图/optional 准入互斥 |

四者均实际 Debug -O/WMO/arm64、ENABLE_DEBUG_DYLIB=NO，Startup 独立身份2.11.0(283)、Team H9QWU9XN8R，严格签名0且构建输入未变。shader semantics 182dc218…dcc、toolchain a3a31085…5e、267540B stock manifest 46984e52…94a6 相同；不是 Release 构建或安装发布。共同 Startup.swift SHA bfe55914…01cc 逐字相同，默认 single/sequence 与原计时、来源、首帧和父 finalize 没有更改。

## 同条件前后对照

共同入口执行真实 Service Scene375→Manager bundled Video2→Service 同 Scene；每 App 新 HOME/suite/测试标准域、30FPS、两次新 request/execution/epoch，保完整当前认证与 lease。固定托管 generation 1cd11e13-001f-4c4b-a376-6dac1d4534d6；系统缓存未 purge。基线核原子进程实际退出后新 PID，候选核同 PID/gen 与唯一匹配强 ACK；两次原 drawable presented、Video 全目标可见/finalize、旧 barrier、正常退出及当前正式偏好分别核对。

A 功能一对后，仅执行一次预定5对 AB/BA；10 App/30选择、原6组 max(abs(x−median))/median≤5% 全通过。Scene 重入中位977.737→229.915ms，但 Video交接479.058→628.574ms、配对差中位+145.263ms；总窗1459.741→867.391ms。已有 wire 的资源释放→强 ACK 仍155.166–180.292ms，不能由总收益隐藏切出正差。

B 只做一对诊断：Scene1004.078→238.301ms，Video542.140→486.109ms，总窗1555.498→731.311ms，资源事件→强 ACK28.073ms。真实 App/原点保留；一对不授性能结论，未重复 B 五对。

C 在最终冻结构建上只执行一次预定5对，不补跑、不剔点：

| 指标 | 基线中位 ms | C中位 ms | C−基线配对差中位 ms |
|---|---:|---:|---:|
| 第二次 Scene 实际 presented | 967.854 | 245.096 | −698.071 |
| Video选择→Video finalize/旧 barrier | 459.648 | 498.361 | +38.713 |
| Video选择→第二 Scene父 finalize | 1456.350 | 744.859 | −679.042 |

五对 Scene 重入差均负（−763.068、−698.071、−694.575、−751.411、−658.032ms）。但原6组噪声仅基线 Scene presented 组通过，其余5组失败；C Scene 最慢309.822ms、Video与总窗亦有波动。结论是本次有界产品资格通过、重入等待一致缩短，**最终稳定性能门未过，Video正差仍待结算**。不能将 A 的噪声通过转授 C，不能称整体无回退或全条件提速。C报告 SHA8987e071…204f；10 App正常退出、精确 owned child0、runtimeRetained=false，原输入/当前正式偏好和源/分阶段 App 签名未变，原进程静默采样未见外部冲突；不是整host/亚秒全空闲证明。

## 正常界面的 TTL、普通退出与闲置观察

另以当前 C 的17个真实生产源＋现有 task importer/当前 DTO 声明投影，实际编译并发布一次 UI 专用受管库，未手改元数据。generation a9cb4809-8141-4230-8234-ece0e023b2ea，18个实际输入文件/59243475B，含此前测试副本已有派生叶；这是独立 UI 来源，不能冒充基准同一 generation。实际 publisher 的 metadata、完整 commit/marker/ref 与原认证核均通过；不证明真实下载 IPC 凭据。原固定库和输入保持不变。

两次普通 App 都只用未消费的 startup-report 参数通过既有隔离门，没有 daemon-client/root/product-entry/mode 或自动 runner。测试标准域30FPS、未暂停、关闭自动切换/系统壁纸同步及焦点等自动暂停，私有 HOME/suite 分离；实际 CUA 通过“已下载→设为壁纸”播放 Scene，再“我的视频→Video2→Return”。退出使用普通 Cmd-Q，没有先调用 Client.shutdown。

- TTL：Scene PID29866/父29727及 lstart 精确捕获，Video已播放后原 Scene 自然消失，而父和 Video helper 继续存活；最后普通退出，父0/children0且未触发 fallback。首次 wrapper 因 `/tmp` 与 `/private/tmp` 字面前缀不同误拒观测，原 passed=false/唯一错误完整保留；只修 argv executable 的 canonical path 对等后，独立将 v2 原 nested lifecycle 函数应用同一原始 samples/markers，补充资格通过，没有重跑 App。
- 闲置：Video标签后的13个存活样本跨13.443s，累计 CPU增加0.01s、RSS177632–177680KiB；首次缺失在标签后14.485s。标签晚于实际交接，不作精确30秒归因；这是外部有限观察，不是能耗、AV/FD释放或零 RSS 证明。
- 普通 Quit：独立第二 App在旧 Scene仍存活且未到 TTL时 Cmd-Q，原 wrapper v2通过，父0/精确 children0、无超时/清理介入；只关闭窗口不算退出。两次均核测试 suite/标准域清理、实际源/源及 staged签名/原 shared输入和正式偏好不变；UI metadata本次也未发生 enrichment。

日志仍有先前已出现的 sandbox_extension_issue_file_to_process 警告，不称零错误日志。普通 UI没有安装 wire observer，不能由进程保活冒称强 ACK；typed资格由共同入口及最近门另证。

## 剩余与保留

主链已接入：可信 ref直挂包、旧无ref合资格临时挂包、明确不合格/非托管仍合法 extractor；来源变更、digest/ref错误不能回退。没有发现第二套产品播放/准备 owner并行。旧 extractor仍承担合法兼容，不能全删；工具 URL分支归P7继续核退役，不以旧名字判断死代码。

后继限P7三组：累计冷暖性能及Video正差结算；30分钟稳态/20次轻重切换与resize、压力/睡眠/显示变化等未完回归；旧失败与旧链归属、文档/证据/产物收口。D19 C1正差及旧 Scene video seek红点仍保留，D23没有改变seek产品源，Video2属于另一个引擎；没有新因果事实时不重复跑到绿。已按证据 STOP 的新缓存/Metal共享/WebView复用/origin方向不成为新前置。

本批归档路径固定为本机 `.artifacts/scene-evidence/runs/wallpaper-startup-scene-d23-20261025-checkpoint/`，保存原失败/最终 raw、四臂 HEAD＋nonHEAD完整源重建、工具、review及最终 owned文档；不含 App、媒体、HOME或DerivedData。连续迭代仅保一个任务DerivedData及后继确需的对照App/输入，精确清理记录归任务回执。所有实施/本批文档均未暂存、未提交、未推送；初始文档提交ae0ac798c不变，goal仍活动。
