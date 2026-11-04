# 验证、macOS 调试与 Git 交接方法

本参考吸收通用 macOS Skill 对本项目有用的 shell-first build/debug、AppKit/window、测试分诊、日志、签名、打包和公证方法。只在任务实际涉及这些表面时加载；加载后仍不使用 `build-macos-apps`。

## 目录

1. [先定义证据问题](#先定义证据问题)
2. [发现当前工具入口](#发现当前工具入口)
3. [首次隔离运行](#首次隔离运行)
4. [失败分诊](#失败分诊)
5. [AppKit 与窗口](#appkit-与窗口)
6. [日志与 typed diagnostics](#日志与-typed-diagnostics)
7. [签名、nested code 与发布](#签名nested-code-与发布)
8. [Runtime 隔离与声明等级](#runtime-隔离与声明等级)
9. [最终 gate 与证据闭环](#最终-gate-与证据闭环)
10. [Tracked 与 untracked 交接](#tracked-与-untracked-交接)

## 先定义证据问题

每个命令只为回答一个可证伪问题：新代码是否被目标/harness 加载；target membership/链接是否成立；运行的是哪个 App/helper；request/session/surface 是否仍是当前意图；结果到了 accepted、prepared、published、composited 还是 visible；局部失败是否保留 previous current；签名/entitlement/Gatekeeper 是否是实际阻塞。

先跑能区分当前候选解释的最小门。只有风险或新结果要求时扩大到 build、runtime、matrix、签名或发布；无信息地重复 full suite 不增加证据。

## 发现当前工具入口

从当前仓库发现 Xcode project/workspace、scheme、`script/` 入口、测试和 machine manifest。实现与验证从 `docs/development/repository-workflow.md` 进入，Scene 方法再查 `docs/scene/development/development-workflow.md`；运行 `script/verify_scene_change.py` 前读取当前 `--help` 和预览，确认实际模块、门与未映射项。`AGENTS.md` 管安全与权限，专题 current-state/README 管事实路由；不要把本参考中的命令示例当永久 interface，也不要创建第二 run script 或 ad hoc 环境配置。

典型选择方法：

- 纯结构/单元：运行直接命中的 Python/Swift harness，确认实际 selection。
- Swift 产品变更：在共享 build/runtime 空闲时串行执行当前 checkpoint build。
- build + run/debug/logs：先读当前 `script/build_and_run.sh` 行为，确认 kill 范围、scheme、DerivedData、App 路径和 mode；只读任务不能运行。
- Scene/Web runtime：使用各自 current gate/benchmark 和隔离 output，不能用普通 App 存活替代 host/GPU/visible evidence。
- release：读取 `docs/release/release-signing.md` 和当前 CI/export workflow。

任何工具会终止同名 App、重用共享 DerivedData、写真实目录或启动长期进程时，先核对授权和并行状态。

## 首次隔离运行

只在任务需要运行证据时进入本节。先按用户行为确定要经过的入口，再准备 App、输入和输出；避免先跑容易启动的 runner，随后把结果外推到另一条链。

1. **选入口与最近门。** 从仓库工作流的验证预览和相应 benchmark 的 `--help` 取得参数，沿当前 runner 调用核对覆盖范围。Scene 的内部 Program/GPU 反例可用直接 Host 入口；IPC、崩溃恢复须经过 client → daemon；普通选择、参数和跨引擎切换须经过实际 App 分发 → client → daemon。入口职责与接线查 `docs/scene/architecture/runtime-architecture.md`，Web 查 `docs/web/current-state.md`，Video 查仓库地图的 App/helper 两端。直接 Host 或直接 client 的成功只覆盖其经过的链。
2. **准备本轮候选。** 核对 gate 的构建条件、App 参数形状与签名要求。默认 checkpoint 是禁签名且退出清理的纯构建门；需要运行 App 时，在独立 DerivedData 按当前项目 Debug/签名配置生成并保留本轮候选，从真实构建输出取得可执行文件路径。Scene/Web benchmark 的 App staging 与验签沿现有 `script/web_benchmark_capture.py` 调用复用；不另造安装器，也不以旧已安装 App 代替新候选。DEBUG runner 要确认实际编入；性能优化级别查 Scene 工作流。
3. **准备输入并闭合结果。** 只复制当前正反例所需内容；Scene 副本/manifest 的创建与核验查 `script/scene_sample_snapshot.py --help`，Scene 运行查 `script/scene_wallpaper_benchmark.py --help`，Web 查 `script/web_wallpaper_benchmark.py --help`。按各工具实际要求设置隔离样本、HOME、Workshop 与全新输出，核对真实启动命令和本轮报告中的 App/input/request 身份、结果及失败反例；再按产物规则保留必要证据、清理已结束的环境。某入口不支持目标场景时，记录该边界并沿真实产品链验证，不虚构通用 flag 或将较低证据阶段升级。

## 失败分诊

| 类别 | 先核对 | 不要误报为 |
|---|---|---|
| source/health/layout | 规则、路径、source set、file length、manifest | runtime regression |
| compiler | 第一个真实 syntax/type/Metal diagnostic | 后续 cascade |
| linker/target membership | symbol、duplicate、architecture、Xcode/standalone list | 功能逻辑失败 |
| toolchain/settings | SDK、deployment、module、dependency、Python/Xcode identity | 产品代码回归 |
| signing/entitlement | 实际 bundle、nested code、Team ID、runtime、sandbox | 普通 compile failure |
| launch/process | executable path/hash、bundle、helper、process tree | surface ready |
| environment/fixture | sample、permission、display、WebKit/GPU、runtime root | 产品 assertion |
| assertion/regression | 确认测试真实执行与 target contract | flake 或环境问题 |
| async/flake | request/generation/session 和 deterministic stale case | 可忽略偶发失败 |
| visual/fidelity | producer-to-compositor identity、ROI/事件 | route/build success |
| crash/GPU fault | symbolized stack、command buffer、现场 identity | 普通视觉差异 |

架构调整后，standalone source list、stub 和源码形状断言也可能过时。先看首个错误和实际编译输入；归因不清时用冻结的迁移前源码复现同一失败，分清存量测试债务、预期语义变化与新回归。不能为恢复过时断言而把重复 owner、无用校验或已退役路径放回产品，也不能只因产品文件未改就认定失败早已存在。修测试时优先断言真实输入、输出与失败反例。

修复后先复现原失败，再跑相邻反例和相称 checkpoint。测试若锁定已知错误现状，应按目标合同修测试和实现；目标本身被证伪则先走合同/Skill 纠偏。报告测试债务与未覆盖范围，不把有失败的选择集称为通过。

## AppKit 与窗口

项目 UI 是 AppKit-first。优先现有 `NSWindowController`、coordinator、responder chain、toolbar/sidebar/inspector、panel/menu、pasteboard 和 drag/drop owner；既有 SwiftUI 只是受控残留，不为新功能创建新 SwiftUI 产品面或扩大 `NSHostingView` bridge。

原生Swift夹具沿产品isolation flags编译；`autoreleasepool`闭包内声明的局部UI函数显式标`@MainActor`，不靠降编译模式消除隔离错误。资源寿命观测按完整动作/回调划分局部pool，几何和弱引用读取也及时drain，只让值或weak观察跨阶段；测试自身强持旧view或整流程共一个pool会污染存活计数，须先排除这些观察效应，再判断产品owner，不放宽真实释放断言。

ScreenCaptureKit的自身进程窗口查询可能返回零frame；按已确认的自身NSWindow设置输出尺寸，并核实际buffer/PNG宽高，帧计数或complete状态不能代替有效画面。高负载探针须观察实际排队、解码与预算淘汰，条目数量不能证明压力成立。需要前台交互结论时，在测量起点及动作期间核active/key；后台启动造成失焦的运行只作诊断，有帧和位移不代替前台资格。

AX树遍历可通过`NSCollectionView.accessibilityItemAtIndexPath`触发真实cell构造；采集工具的截图也可能先读AX。将观察放在动作区间之外并按栈单列，不能把观察造成的Main忙段归为业务瓶颈。AX按钮动作可能先scrollToVisible，须与坐标鼠标事件区分。`CALayer.presentation()`近似当前事务起点的呈现；同一事务内隔一段时间重读不等于实时屏幕采样，跨事务的显式flush也须计为探针扰动，不能由此声称像素/FPS。

滚动呈现探针把预热、等待输入与实际测量分段；有界逐帧预算应围绕真实动作计数，初始校准帧单列，不能在等待前台或输入服务时耗尽。进程、AX或截图可访问不证明动作到达；核实际输入/位移及测量段采样，未到达或截断时保留失败入口，不能据此认领流畅度，也不能改产品来迎合探针。 `performClick`的模拟按压开销与真实action handler分段，纯动作派发可用原控件`sendAction`并单列协议，不混为物理输入或与旧协议时耗作A/B。

合成`postEvent`/`sendEvent`不会移动系统指针。若同一门还读取`mouseLocationOutsideOfEventStream`，事件位置与指针输入须一致，复用现有受控窗口即可；否则一次正常布局回调就可能取消模拟hover。保留放大/命中断言，修正不一致的夹具输入，不把它报成产品回退。受控指针仍不能证明真实指针跨越新sibling控件的跟踪。原生控件的mouseDown也可能异步返回，合成按压不能强制要求嵌套eventTracking循环；让真实事件泵递送mouseUp，再分别核控件入口与业务动作。Timer未运行或up根本未发，不能归因为产品吞击。

[visibleItems](https://developer.apple.com/documentation/appkit/nscollectionview/visibleitems%28%29)含AppKit管理的离屏成员，需另记实际几何相交、绑定及图片属性，不能直接称屏幕可见或泄漏。[hitTest](https://developer.apple.com/documentation/appkit/nsview/hittest%28_%3A%29)的点属于接收者superview坐标；观察前核具体API坐标合同。Main预期layout、实际cell/文字和presentation属性均不等于已绘像素；屏幕身份须有同一截图内可核对的标题/rect等锚点，缺失或截断直说，不靠强制layout/display或扩大采样把缺证变通过；额外绘制锚点须说明其对失效/合成的扰动。

窗口变化检查 role、identity、display、restoration、teardown、accessibility、drag region、visible-frame placement、Spaces/collection behavior、focus/input 和 borderless wallpaper level。主窗口、panel、Video helper window、Web surface、Scene output 各由当前唯一 owner 管理；不要把通用 SwiftUI scene/window modifier 套进当前 AppKit 生命周期。

UI 只投影产品状态并发命令，不能成为第二 runtime 真值。多显示器行为使用目标 display 的当前 geometry，不假设固定分辨率或单屏。

## 日志与 typed diagnostics

优先模块已有 typed diagnostic/store；需要统一日志时使用真实 bundle subsystem 和稳定 owner category。事件包含 privacy-safe 的 request/display/session/surface/generation/route identity，区分 accepted/prepared/published/visible、stale rejection、fallback、crash/recovery 和 teardown。

不记录 token、bookmark data、用户文件内容、完整私人路径、原始 Workshop payload/shader；不以 `print` 或每 mutation 大 payload 代替产品 telemetry。运行一次目标路径并按 process/subsystem/category 过滤，确认事件数量有界且来自正确 build/identity。日志出现只证明事件代码执行，不证明画面。

## 签名、nested code 与发布

先区分 local debug 与 distribution。notarization 不是普通 Debug 前置，ad hoc 签名也不能证明 Developer ID 或发布身份。

对实际 artifact 检查主 app/executable、wallpaper helper/daemon、framework、compiler/VM worker 或其他 nested code，以及 entitlements、hardened runtime、Team ID、CDHash、architectures、DMG/export、notary result 和 Gatekeeper。使用当前系统工具读取 artifact，不从 Xcode settings 推断最终包已正确签名。

正式运行证据绑定 staged app 的绝对路径、bundle ID、Team ID、CDHash、executable hash 和 helper identity。没有 exported/notarized artifact 时明确结论只到 build/static/signed-staged 的实际等级。签名问题按 identity、entitlement、runtime、sandbox、nested-code、bundle structure 和 notarization phase 分类。

## Runtime 隔离与声明等级

导出源码运行测试时，为导出目录提供独立 `.git`，不要让测试进程继承指向真实工作树的 `GIT_DIR`、`GIT_WORK_TREE` 或 `GIT_INDEX_FILE`。测试夹具会初始化仓库、切换分支和创建提交；refs、index、config必须独立，只读对象缓存可以共享。

普通GUI副本先核Foundation实际目录和standard偏好域真实读值，不能把空HOME或独立bundleID当作禁恢复/禁登录；路径别名按实际身份比较。只给本次唯一测试域配值并精确清理，不写生产域；固定Keychain/IPC名及AppGroup/getpwuid派生目录另沿实际触达链核对，不能称全文件隔离；未记录原inode的用户运行点不按名称清理。前台测试先准备输入协议；xctrace用真实started通知准入，不把PID或目录存在当ready，再按动作时间戳核TOC覆盖，结束后的动作不作性能对照。单一Darwin通知注册的FD由notify_cancel关闭，不再重复close；用既有busy路径保护固定运行点时须标记通道未验收并核前后节点。

调试器attach后，不用父方Popen的退出状态代替目标退出：先核已绑定身份的实际PID消失，再释放原生会话和运行点租约。断点须在目标模块加载后记录resolved locations；pending ID不算观察就绪。调试器退出、目标仍活时，先关闭精确测试目标并保留无效运行，不能认作产品失败或有效点击证据。

真实 Scene/Workshop root 与用户视频只读。sample copy、runtime home、property injection、cache、manifest、screenshots、reports 和 evidence 使用每次全新隔离位置；记录 App/helper 的绝对路径、hash、PID 和 display/request/surface identity。检查旧 `/Applications` App 没有抢占 helper、URL handler 或 writer。

同一时刻只运行一个会竞争 App、helper、GPU、benchmark、matrix 或共享 DerivedData 的任务。先核门是否已由`run_native_app`持会话锁；父进程不得持同一flock再等子进程取锁，按真实tempfile目录/inode选唯一锁owner。结束后确认进程退出或明确保留。高体量输出另加载 artifact governance。

声明按实际最高阶段：static/recognized、compiled/linked、process alive、accepted/host ready、prepared、published/composited、visible bounded case、matrix profile、signed staged、official bounded comparison、release。较低阶段不能冒充较高阶段；所有 PASS 绑定 frozen source diff 或 commit、精确 build identity、输入、环境和 gate version。产品源码、gate/build input 或 App identity 变化后，旧 runtime 证据不再证明当前候选。

## 最终 gate 与证据闭环

把最后一个 build、runtime 或 gate 也当作新的 process/artifact writer。它结束后再核对相关 App/helper/benchmark/build/test 进程、output 保留状态、适用的 sample-root residue 与工作区 status；较早的收尾检查不能覆盖后来的命令。只终止精确归属于当前任务的进程，否则记录明确保留理由。

将刚完成的 gate 结果写入其 role-specific 证据文档后，避免制造自引用重跑循环：若只变更 prose、link 或 evidence field，且产品源码、gate manifest、test selection、build input 与 App identity 均未变，只重跑受影响的 document/link/governance/semantic validator；若上述任一输入变化，则重跑相称的 product build/runtime。

## Tracked 与 untracked 交接

先展开 owned manifest：

```bash
git status --short --branch --untracked-files=all -- <owned-paths>
git ls-files -- <owned-paths>
```

分开审查：

- tracked unstaged：`git diff --check -- <owned-paths>` 与 scoped `git diff`；
- staged：`git diff --cached --check -- <owned-paths>`、`git diff --cached --name-status` 和 scoped cached diff；
- untracked：逐文件完整读取并运行适用 validator/formatter。需要 patch/whitespace 视图时可用 `git diff --no-index --check /dev/null <file>`，但“文件有差异”本身会产生非零状态，必须与真实 whitespace diagnostic 区分。

空 `git diff` 不能证明 untracked 内容 clean。全工作区 status 用于发现并行 lane；全工作区 `diff --check` 的其他 owner 错误只能作警告，不能归责当前 owned batch。

提交前逐路径暂存，禁止 `git add -A`。核对 cached manifest 只含本批完整职责，提交后再检查 `git show --stat --oneline HEAD`、`git status` 和目标路径状态。除非用户要求，不推送。最终报告只列适用项：实际结果、验证、未运行门、runtime/signing/artifact identity、剩余边界和 Git 状态。
