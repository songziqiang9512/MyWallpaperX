<!-- document-role: historical-evidence -->

# 属性换图操作反馈（2026-10-14）

> **历史证据 — 非现役入口**。通用语义归[属性能力合同](../capabilities/runtime-input-property-coverage.md#user-texture-operation-feedback)，后续交互验收归[属性卡](../roadmap/properties-panel-card.md)，本地与发布签名边界归[签名合同](../../release/release-signing.md#steamservice-build-and-signing-boundary)。本批只闭合操作反馈与有界换图语义，不关闭属性或性能专项。

## 通用语义与实现

换图失败原先被 service 压成 Bool 并写入全局下载错误，可能在浏览器呈现“下载失败”，发起属性面板却没有原因。设计先落入现役能力合同，再沿原 pending/revision 将既有 `ScenePlaybackTextureUpdateOutcome` 交回发起 editor：applied 刷新已接受值，failed 显示局部反馈，superseded 安静结束；unavailable 仍先走原 reload fallback。未增加结果类型、资源 store、通知或 renderer。

真实失败不提交新书签/override；同 key 替代、stop 与 launch cancelled 结为 superseded，意外断连仍为 failed。原 Client 在批量结清 completion 的同步阶段封闭纹理准入，嵌套保存/恢复原状态；双 key reset 回调递归提交下一 key 时立即 superseded，不向退役会话新增 pending/IPC。普通逐 key 完成不封闭健康会话。此边界针对已出现的纹理回调 producer，不声称解决任意回调直接发起 loadScene 的通用重入。

原 revision 继续拥有提交权。reset 保逐 key 成功提交，汇总时首个真实 failed 优先于 superseded，不伪装全 reset 回滚或全场景呈现 ack。UI 只拥有反馈寿命：同 key 重试清本 key 错误，异 key 的有效失败保留；新操作、隐藏/关闭或迁窗后旧结果不覆盖当前反馈。picker 取消不提交，已提交事务不因关面板而取消。

## 已执行验证

最近 service/control-plane/native-list 首轮28 tests 中26通过，两个原生 probe 因拼接得到 `}import Combine` 而编译失败；只修 fixture 换行后原生2项通过。随后补异 key 错误保留、旧 reset 迟到结果与真实迁窗反例，原生2项再次通过（8.354秒），其余26项有效结果复用。真实 client harness 覆盖 stop/launch/termination 期间递归 apply/reload、nested drain、fallback 与部分 reset；不把 leaf spy 当真实 daemon/GPU 验收。

Debug 构建最终通过（36.258秒），4294项源码/资源/构建脚本输入 drift=[]。前两次失败为签名 timestamp 服务不可用，不是 Swift 编译失败。签名脚本另批提交 `664ecb76`：Debug 与显式诊断配置禁用在线 timestamp，普通 Release/直接真实身份签名仍默认 required；runtime、JIT 与 strict verify 保留。真实 shell、仅 codesign argv leaf 替换的11项门通过，不等于证书、notarization 或发布验收。

候选 Debug App 主 executable SHA `08a6dc31…`、实际 debug dylib `2c6f0edc…`；完整代码与签名身份见本批 `proof/candidate-app-identity.json`。本批没有性能测量，不认领 CPU/GPU、启动、内存或能耗收益。

code-health、scene-defense、design-gate 一次通过：1192个Swift文件均≤1000行，防线仍为0 dead entry/18 canonical helpers/3 swallow patterns，未放宽阈值。最终产品源码 drift=0，收据为 `static-gates.json` 与 `final-source-identities.json`；有效结果复用，不为文档收口重复产品门。

## 正常 App 窗口与退出

根线程在隔离 Workshop/HOME 与专用 defaults 域操作真实290输入：红图选择已接受；选择坏 PNG 后在属性面板显示明确 inline 错误，仍保红图已接受值。坏图前后专用域中该 key 的 bookmark 与 override 两项字节数/SHA 完全一致，未导出书签 payload。蓝图重试后 label 为 `blue.png`、inline 错误消失；逐行恢复默认显示作者默认资源，随后取消 picker 保默认且无错误。关闭重开仍为原20条列表、默认值且无陈旧提示；最终被检查的属性持久键为0。

普通入口未使用 daemon-client 或截图 flag。App87271/daemon87287 的同一 `0335DBFF…` session 全程只有1次 session-first-frame 与1次 launched，操作没有新增 Scene 启动。正常退出后两个精确 PID 均消失；VM182/182 quiescent、failures/timers/jobs/mutations/dynamicLayers 均0，粒子 surface-stop、声音停止。回执为 `normal-ui-receipt.json`、`normal-ui-final-preferences.json` 与 `normal-ui-runtime-excerpt.log`。

这些事实证明真实窗口反馈、失败不写持久值及该入口退出。面板截图只在 CUA 内查看，未返回本地文件；正常入口只证明首个 GPU-completed present，没有捕获桌面像素。全 reset 部分失败未作真实 UI 验收，不据控制门或窗口 label 认领。

## 独立293功能与像素边界

原293输入沿现役 CLI 使用同一 Debug App、隔离 HOME/suite。首次冷 cache 在31.15秒仍有 preparingPrograms/编译进展、尚无 first-present；外层为保留后续操作窗口主动停止，没有执行换图步骤。这是未完成取证，保留 `cli-293-failed/report.json`，不是45秒 runner timeout、已证挂死或产品换图失败。

核实已有28项持久 shader-program cache 后，只进行一次同45秒设置的部分暖 cache 功能运行。日志完整得到 red applied→broken failed(`texture-update-resource-unavailable`)→missing failed(unreadable/unsupported)→blue applied→reset applied。仅观察到同一 presented request `30E1918B…` 与daemon91693；最终 JSON 缺失，因此没有逐步 PID 字段，也不称全报告身份完全证明。

现有 Metal 截图 owner 生成五张3024×1964图。在ROI `(64,64)..(512,256)` 的86016像素，initial/reset逐字节同为RGBA(0,0,0,255)，red/afterBad逐字节同为(230,40,30,255)，blue为(30,80,230,255)。实际图检查显示黑→红、坏图保红、蓝→reset回作者黑底，中央音乐卡与粒子仍合成；原右侧时钟裁切保留。这里只证该属性背景ROI，不称动态整图相同、官方parity或此CLI书签字节已证；持久值另由正常UI证据承担。

暖运行由48.052秒外层guard终止：runner的45秒计时从load-dispatched开始，最后日志在其后46.993秒，缺最终JSON/未优雅收口，原因未定。**仅五步功能与画面有界通过，不是完整CLI PASS**，也不将 replay/ack时长当性能。该次精确App/daemon均已退出；正常UI的独立优雅退出事实保留。原报告、ROI和截图见 `cli-293-warm/`，冷暖条件不合并作启动或性能结论。

<a id="native-full-reset"></a>

## 原生面板全 reset（2026-10-15）

复用冻结 C App `29891b05…`、原 shared shader cache 与正式 snapshot 的单2938612768隔离副本，无产品改动。作者 `newproperty7` 是默认空字符串的 scenetexture，`newproperty2="8"`（Local files）揭示并消费它。原生选择一次自有红 PNG 后，资源书签为672B、override含条件键与资源路径；点击面板顶栏“恢复默认”后，属性持久项为空、条件键回作者默认“1”。再次选择 Local files，资源行显示作者默认纹理，持久态仅有条件键、无资源 override/bookmark，实际背景恢复黑底；最终再全 reset，持久项仍为空。未以条件行隐藏代替资源恢复证据。

根线程独立查看 default/red/reveal-reset 三张真实 Scene 窗口原图，确认黑→红→黑。相同86016像素背景ROI为RGBA(0,0,0,255)→(211,61,46,255)→(0,0,0,255)；这是OS窗口捕获，不与前述Metal取色混作颜色parity或动态整图相同。全程 request `5DF5A290…`、session `99171919…`、App25995/daemon26015，仅一次 launched/first-frame/activated。Stop后列表与详情均回“设为壁纸”，78/78 VM quiescent、failures/timers/jobs/mutations/dynamicLayers全0，粒子surface-stop、音频停止；CmdQ退出0，精确两PID消失，退出后没有CUA观察或自动重开。

本轮snapshot verify退出0，`source_changes=[]`、`isolated_changes=[]`，没有字体轮的copied marker差异。证据在 `.artifacts/tmp/property-full-reset-native-20261015/native/`：`native-acceptance.json`、reset前后短持久态、`background-roi.json`与日志；书签仅留大小/SHA，不导出payload。三张Scene原图与三张必要panel图共4,162,367B（约4.16MB）。精确PID与lsof无句柄后，已清隔离副本/HOME/tmp共195,860,737逻辑B，保冻结App、原DD及共享cache；不称物理释放或运行RAM下降。

本片仅证一个既有PNG资源的成功全 reset，取消/坏图沿用原门，不重验矩阵。全 reset部分失败、更多资源/格式及最终GPU pin/drain未验；原opacity-mask失败和右侧时钟裁切不由本片关闭，无性能收益。

## 边界与证据

PNG/JPEG 既有 consumer、fallback 与成功提交点未扩张；effect mask、particle、video、多 user slot、更多格式、多 surface 和完整系统键盘访问仍按原缺口记录。1128回调非有限 origin、544作者颜色及其他既有画面/严格矩阵失败未由本片关闭；性能选序仍归[性能卡](../roadmap/performance-convergence-card.md)。

必要原始日志、失败、正常UI与独立像素证据约16MiB限量保留于 `.artifacts/tmp/property-texture-feedback-20261014/proof/`；正式runs晋升总预算已满，不重复晋升或提高预算。exact lsof无句柄后已删本批 `DebugDerivedData`（1,239,691,369逻辑B）与 `/private/tmp/mwx-property-texture-feedback-20261014-yee_0nr3`（743,800,073逻辑B，含staged App/clone/HOME/cache），非APFS物理释放量。六个选定原文件与clone哈希一致，无真实用户媒体写入；专用defaults delete返回1，未声称域删除成功，隔离HOME文件已随运行根删除。详见 `derived-data-cleanup.json`、`runtime-cleanup.json`；最终文档导航与健康结果另存本proof，不冒充产品验证。
