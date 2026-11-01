# macOS 视频屏保接入设计

<!-- document-role: active-plan -->

本文件是本专项唯一现役设计。2026-10-29收敛为仅支持Video；2026-11-01用户批准在此基础上接入系统动态锁屏，使主动锁屏和自动锁屏均无需等待闲置屏保计时。Scene/Web屏保继续退役，主App三引擎桌面播放保持原样。新增私有墙纸协议边界、阶段与验收以第8节为准；旧普通宿主证据不能冒充新锁屏验收。

## 1. 目标与系统边界

- 面向macOS 26以上，以App内嵌的单一Video原生墙纸扩展承接即时锁屏和闲置屏保；保存只部署视频和配置，系统负责surface、闲置启动、密码和退出。旧公开ScreenSaverView组件的验收仅保留为第7节历史。
- 主App完全退出时仍能独立播放；不需要启动或升级旧的/Applications App来维持屏保，不以活动socket作为播放许可。
- 不替换密码页或认证，不做后台录制、转码、预编译、全局保活或大小核绑定。仅第8节Video系统墙纸扩展可使用已声明的私有宿主协议；静态后备来自既有封面/桌面底图，不开放图片/Scene/Web为屏保来源。
- 真实锁定与手动ScreenSaverEngine、系统全屏预览、系统小预览分别取证；isPreview不是认证状态。开始时间和密码要求保留用户设置。用户已要求删除App内预览，不再提供额外播放器入口。

## 2. 收敛理由与退役范围

本机收敛前实测磁盘占用：已安装Debug测试组件126.7 MiB，原三引擎Release组件96.5 MiB（可执行约29.4、资源60.5、编译助手6.6）；该Release App约308.5 MiB，/Applications旧App约213.3 MiB。此为本地包体，不是压缩DMG增幅。用户据此选择Video-only。

撤销本批Scene/Web外部surface接缝、runtime bundle抽取、Web命名空间迁移、屏保专用媒体/权限分支和对应测试适配；最终整合后Core内Scene/Web源码与主仓994493dd4一致，保留其他会话的最新修改。删除没有剩余消费者的新类型与新fixture。保留视频共享静帧执行、配置/发布/安装、App入口和暂停交接。组件不得再编入Scene/Web、QuickJS、Metal着色器、stock/font库或shader编译工具。App自身仍正常携带这些原有能力。

退役前192个所属源码文件已保存到ignored的.artifacts/lock-screen-screensaver/retired-realtime-saver-sources.tar.gz（约1 MiB，含原HEAD和逐文件hash），供查明已放弃方案；不进入发布、不作为现役代码。旧三引擎灰屏根因未确认，不能写成已解决。除非用户重新授权，不再重复此方向实验。

## 3. 职责和最小数据流

1. ScreenSaverCoordinator从现有资料库解析可用视频；Steam版本租约和文件安全scope只在复制事务持有，不改来源下载/播放逻辑。
2. ScreenSaverIntegration沿一个utility串行队列复制实际视频到私有不可变Media/UUID，调用原VideoStillFrame从该副本生成poster.jpg；二者就绪后原子发布current.json。取消/清除/导入/重置/退出沿原代次撤销，不新增owner。
3. ScreenSaverConfiguration只含schema/publication、视频generation、标题、opaque来源关联、视频/静帧相对路径、布局和电池策略。保留kind=video作为格式判别，拒绝把旧Web/Scene入口当视频；不再依赖它们的属性或资源类型。
4. 系统原生扩展向macOS提供远程CAContext，内部用AVQueuePlayer/AVPlayerLooper和AVPlayerLayer播放，AVFoundation持有唯一视频时钟。App不编入Native源码，不创建额外预览播放器、桌面窗口、渲染服务或每帧IPC。
5. ScreenSaverActivityClient/Monitor仅让配套新版App把系统播放活动合入原PlaybackPolicyController的OR暂停原因；没有App时连接失败只结束活动连接，绝不停止视频。关闭最后一个活动surface只撤本原因，不覆盖用户暂停。

资源租约保留到解码器停止；发布维护只回收自有、非当前/上一份、无租约的generation。未知目录和组件保留。视频源移动/删除不影响已部署副本；删除入口提示副本可在设置清除。显式清除撤销在途操作并清持久意图，不因下一桌面提交复活；移除已安装旧组件不取消发布或清视频。

旧schema=1的视频内容可沿同一解码读取；旧Scene/Web或损坏配置不播放、不做跨引擎迁移。用户保存一个有效视频时可原子替换不支持的旧配置，候选失败仍保留原磁盘值；不强迫先执行一次清除。纯布局/电池更新仅对实际可读的视频配置生效，不复制源文件。

## 4. 用户操作和UI

- 配置面板复用Steam登录面板的原生玻璃底座和胶囊按钮，500×640原生sheet（原520×700），固定单行标题与图标沿Y轴居中，不保留装饰副标题；左下角“清除内容”及仅旧组件存在时显示的“移除旧组件”胶囊按钮不带省略号、右下角“保存屏保”/取消；内容从上至下分为选择视频、播放选项、系统启用指引，一屏展示，不再嵌滚动区。三段内容用原生Stack等间距分配可用高度，段内保留正常行距。设置入口位于“显示设置”的“多屏支持”上一行。配置面板本身不启动播放器。提示区分尚未部署、已保存和系统选择未知，不用“已保存”冒充系统已经启用。
- 共享WallpaperPanelSurface直接继承NSGlassEffectView，由原生cornerRadius独占外轮廓（默认20、详情22）；退役外层NSView的CA裁剪/描边、内层玻璃及额外底色，不再用两套圆角叠加。唯一bodyView绑定真实contentView，所有共享面板消费者向bodyView添加内容。保持regular玻璃及用户认可的深色tint黑0.10/body黑0.18，浅色controlBackground 0.15/body白0.82；降低透明度/增加对比度用body实色且保留交互。详情/属性外层只保原阴影，材质不改宿主窗口透明度、不监听主窗色彩、不生成缩略图。用户已停止追求进一步透色，不扩大为模态呈现方式改造。
- 配置顶部一行依次为144×90静态缩略图、标题及当前/未保存状态、右对齐“选择视频”按钮，三者沿Y轴中心对齐；文字列伸缩，按钮保持原生尺寸。删除选择区、选项区的内部矩形底板，仅保留外层原生玻璃、内容分隔线及正常控件背景，标签和右侧控件沿同一边界对齐。选图直接使用原ArtworkProvider的共享liveLoader/资源身份；仅在来源缺失且sourceIdentity匹配时读已部署poster，复用原静态图缓存，不常规重复读第二张图。换源/关闭取消消费，迟到回包不能串图。关闭按钮与详情复用同一32×18控件；首开由窗口自身接管首响应，不强制给选择按钮画蓝焦点，也不全局关闭Tab焦点提示。普通重复展示只聚焦最上层子面板；明确新reference先撤旧子面板再消费，不吞选择命令。
- 用户确认App预览多余后，同批删除按钮、预览窗口/播放器和遮挡状态、Coordinator独占的预览解析/后备入口以及组件App预览数据分支。组件视图不再编入主App；正常保存仍沿原单一解析/版本租约/scope复制事务，系统屏保播放与系统静态小预览保持原样。缩略图身份/迟到回包测试保留，只退役两项无消费者的App预览断言。
- 视频选择直接扩展原WallpaperPlaylistPickerController为两种目的：原列表添加保持多选及原事务，屏保单选只返回当前视频、不写列表关系；复用同一网格、缓存、搜索/缩放和原生模态域。屏保仅呈现全部/我的视频/我的下载中的本地可用Video，取消不改草稿，选择不自动播放或发布。选择器和卡片“用作屏保”只接纳本地可播放Video；在线视频未下载时沿原下载反馈，Scene/Web/图片不提供屏保入口。
- 固定视频，或“跟随最近播放的视频”。手动选择视频同时切为固定模式，确保保存的就是面板所选内容。跟随只消费原成功且记录最近使用的Video提交；桌面切成Scene/Web/图片时保留最近已保存视频，不报错、不复制、不把不支持来源写进目标。
- 布局为完整显示/填充屏幕。始终静音、1倍速；使用电池默认只显示本视频静帧，可显式启用普通电池动态；系统低电量模式仍静态。
- 系统小预览仅静帧；实际系统surface不套用App窗口遮挡判断。
- 原生组件随App提供，由系统登记；保存不复制或重签组件，不改写系统Index、不kill系统宿主。首次使用需要用户在系统设置选择，后续只更新同一视频发布。
- 系统启用区分开说明：保存视频→墙纸页MyWallpaperX分组选择视频启用即时锁屏；屏幕保护程序…/自定义/MyWallpaperX分组选择视频并设置时间、完成。按钮“墙纸与屏保设置”“锁屏设置”并排等宽，密码/开始时间均由用户控制。用户若在系统设置换成其他墙纸，扩展不自动抢回；App原有“同步改变系统壁纸”也会替换系统provider，启用原生动态锁屏时需关闭该选项，再选回MyWallpaperX。

## 5. 生命周期、功耗和失败

AVFoundation自身解码显示，无自建逐帧timer；系统请求失效、连接退出、熄屏或睡眠时释放player/looper及租约，保留静帧。睡眠/电源恢复只对仍有效的surface重建；preventsDisplaySleepDuringVideoPlayback=false，不修改熄屏时间。解码失败在当前激活期保持静帧，不进行忙重试。

视频准备期间显示该版本静帧；不可读/无有效时长的候选局部失败，不循环重启。无静帧无法完成发布，保留旧配置。App退出不结束系统屏保；解锁只重算原桌面政策，不重复设壁纸或写最近使用。

测试与并行会话串行协调屏幕/GPU/AV，不用旧三引擎低CPU、一次运动或构建成功证明Video持续播放/功耗。

## 6. 打包与验证

唯一组件target为MyWallpaperXSystemWallpaper，产物嵌入App的Contents/Extensions；只编译ScreenSaverSources/Native、配置和可选活动client，不含Scene/Web、QuickJS或shader助手。系统目录显示已部署poster，空配置不提供视频条目；旧静态图标、生成器和PNG校验已退役，组件Resources仅携带LICENSE/NOTICE，实际视频封面来自已发布媒体。CI检查版本与App一致、arm64/macOS26、inside-out签名、App Sandbox和同一App Group、dSYM与实际包体；主App原助手签名不动。

复用DerivedData时须在本轮构建前精确清除自有旧.saver产物及其App内副本，防止已退役资源残留；不清主仓/并行缓存。验证实际Release包中无Scene/Web资源和助手，并实测组件大小，不以源码行数估算收益。

旧.saver安装/签名比较链已退役，不为新扩展另建安装器。只在用户确认后按已知旧bundle ID移除旧组件，保留同一媒体发布；未知组件不删除。扩展升级由App的正常更新/签名及系统登记承接。

按阶段执行：①撤销Scene/Web并收敛数据/target/UI；②最近发布/取消/租约/导入/暂停/安装门和独立审查；③Debug、Release及实际资源/签名闭包；④资源允许后用真实视频验证普通预览和系统自动闲置启动，App完全退出是基线，配套测试App运行只是对照。至少覆盖循环超过视频时长、停止/重新启动、遮挡恢复、低电量/睡眠、主App退出、更新/清除。每阶段问题直接在原owner修复，不用新后台层掩盖失败。

## 7. 旧Video-only .saver整合证据（截至2026-10-29）

本节记录迁移前的已完成交付，不作为第8节原生扩展的当前验收或下一步顺序。

- 当前验收仅为Video-only；旧三引擎灰屏根因不当作已解决。用户暂停真实锁定验证的要求保留，普通窗口、系统小预览与真实锁定分别记录。
- 整合主仓994493dd4后的代码19c7fff15完成整App Debug（66.95秒）、Release（421.91秒）构建，输入hash未漂移。App预览已删除，单行标题/图标、三列居中选择区、固定胶囊页脚、一屏分区间距和最终文案已由实际窗口确认。设置入口的实际顺序为卡片单击操作→锁屏与屏保→多屏支持。后续收尾仅改文档，不改变已验证产品字节。
- 最新近门26个Python测试在28.63秒通过：实际封面身份/复用/取消11项、活动socket14项、发布/取消/租约/同版本安装33项；Release合同16和CI路由7个测试通过。新增生成器的路由遗漏经独审修正到既有system-screen-saver组，路由器68个测试通过。
- 既有共享UI回归已通过：详情/属性标题24组与状态4组；Picker40、Steam登录22、API输入5、列表编辑器54、系统模态32项。初始3处fixture失败修正为标准Resources路径、真实bodyView查找、宿主居中与失败诊断；保留原断言及失败日志。整合后系统模态32、页脚/原生Cmd+A路由34、命令事务35项和设置导入3个Python测试通过；7测试首轮唯一失败是Picker仍提取已退役selectAllMenuAction，删除过时提取后Picker40项单独重跑通过，不恢复旧产品路由。删除App预览仅退役2项无消费者断言。
- Debug测试包整包复制并重签，不能只替换启动shim。已验证实际代码dylib及签名；此前旧dylib造成的像素结论作废。测试App必须用显式HOME/CFFIXED_USER_HOME启动，退出后只用进程清单确认；CUA再次getApp/AX会自动重启App，不能用于确认退出。
- 实际签名Release组件已通过原安装owner替换到用户Library/Screen Savers，strict签名通过；安装前后current.json字节未变。最终组件UUID B8E57B83-6576-3C3B-ADE6-087DB561BD4D，Resources仅LICENSE/NOTICE与两份thumbnail。保留用户最后保存的Video3，不回滚后续手动选择；系统选择、密码和闲置时间保持用户控制。
- 系统“其他”列表已实际显示本App图标。只有PNG入包不等于目录更新：本机27.2的WallpaperLegacyExtension把SHA256(path+"-"+name)作为磁盘PNG键，旧缓存存在便不重写，不包含mtime/版本。独立静态复核arm64e与x86_64均读取bundle.imageForResource("thumbnail")；ScreenSaverThumbnail元数据试验无效，已退役该字段及无消费者的验证要求。
- 图标验证只将已确认属于本模块的一个默认蓝图缓存移到本轮ignored产物并保留receipt，再由系统正常重建；其他目录项未动。Settings/目录扩展的临时重开用于本次实验，产品不加入杀进程、扫缓存或改系统Index的链路。旧PNG、前后hash、安装receipt在.artifacts/lock-screen-screensaver/runtime保留，避免后续重复试验尺寸/mtime/多层背景。
- 主App退出后，最终已安装Release组件在一次性普通窗口运行53秒，AV时间正常，约19秒视频观察到两次循环；stop释放、同view重启继续、ready且无失败，配置未变。此为系统动态角色的普通宿主，不是认证锁屏或功耗基线，不外推低电量/睡眠/长期锁定。
- 最终Release组件349700字节（341.5 KiB），整App215069303字节（205.11 MiB，不含符号链接）；实际发布合同门通过。组件无Helpers、Scene/Web资源和已知Debug诊断符号/字串。精确移除自有App内的退役.saver旧输出后重建，未清主App Scene资源。
- 原CI完整Sign app步骤在最终Release克隆上以本机ad-hoc身份执行，inside-out及strict deep验证通过；实际权限合同通过，Main App/Daemon/组件三个dSYM UUID均与产物一致。此证据不包含Developer ID、时间戳、公证或发布。
- 三位子代理完成UI、发布/安装/状态及CI/target独立复核，发现的不可用本地视频误报、生成器未路由与整合Picker测试过时提取均在原链路修正。双配置仍有未改动Scene文件的3条并发隔离警告，本批无新增源码警告；不声称全仓零警告。
- 产品与测试已按用户授权提交，整合保留主仓994493dd4全部提交，Core内Scene/Web相对该提交无差异；最终文档收尾后快进至codex/engine-refactor-program，不推送、不替换/Applications。整合验证、最终Release与实际锁屏边界分别报告。本树保留一份构建缓存、签名Release克隆及有界证据；已停止的Debug测试App、一次性宿主和编译工具在交接前清理。

公开接口：[ScreenSaverView](https://developer.apple.com/documentation/screensaver/screensaverview)、[AVPlayerLooper](https://developer.apple.com/documentation/avfoundation/avplayerlooper)、[允许显示器休眠](https://developer.apple.com/documentation/avfoundation/avplayer/preventsdisplaysleepduringvideoplayback)、[原生玻璃](https://developer.apple.com/documentation/appkit/nsglasseffectview)。这些接口不构成动态密码页替换授权。

玻璃容器用法依据：[Apple WWDC25 AppKit 新设计](https://developer.apple.com/videos/play/wwdc2025/310/)（contentView，避免同级背景叠放）。

## 8. Video 原生屏保宿主与锁屏边界（2026-11-01）

### 当前交付与已知限制

当前只打包 MyWallpaperXSystemWallpaper.appex，旧 .saver 的播放器源码、target、scheme、静态图标及生成器退役。用户确认主 App 退出后系统自动屏保可播放；主动锁屏先显示原桌面静态图，等待约一分钟后视频开始，**主动锁屏立即播放仍未实现**。不能用构建、普通宿主或旧原型的正证宣称这一目标已完成。

系统目录仅提供 screenSaver 视频条目，desktop 发布空目录，以撤去早期候选暴露的墙纸条目。屏保不捕获、复制、覆盖或恢复原桌面底图，不要求用户设置系统墙纸。首次保存后从“屏幕保护程序…”→自定义→MyWallpaperX 分组选择视频，并由用户设置开始时间；之前在墙纸页选过早期条目的用户，需要在系统界面一次性改回原墙纸。保存只更新发布内容和屏保意图，不向桌面播放器发切换命令。

### 唯一职责与数据流

- ScreenSaverCoordinator 解析资料库来源和用户意图；ScreenSaverIntegration 是唯一发布 owner。仍用 schema=1 的视频、poster、布局和电池设置，不在锁定时复制、转码或哈希资料库。Video/Web/Scene 桌面引擎和系统认证、密码、闲置及熄屏设置各保留原职责。
- ScreenSaverSources/Native 仅处理必要的私有 WallpaperExtensionKit/NSXPC 协议及远程图层；AVQueuePlayer、AVPlayerLooper、AVPlayerLayer 持有视频解码和时间线，没有逐帧图片传输、主 App 保活、计时轮询或额外播放 broker。macOS 管理扩展进程与远程 surface；私有边界不可用时保留已发布内容并返回正常错误，不新增另一播放 fallback。
- 创建、更新在入口读取 typed geometry/presentation/activity，按 connection/request 保存有效请求；每屏只共享一个正式 surface/player，预览独立且只显示 poster。单连接退出不能停止其他活动请求；update 原地保留已返回 context ID 并更新尺寸，跨显示器需要重新 acquire，不能在不返回新 ID 的 update 中偷偷换 surface。
- 先订阅通知，刷新时读取会话锁定状态，结合有效宿主请求决定动画。App 和活动 socket 不是播放许可；socket 只供配套 App 暂停桌面，App 退出后组件仍可独立读发布内容。普通电池按用户开关，低电量/预览显示静帧，熄屏/睡眠停止，失败释放解码器和媒体租约。
- 系统目录在连接建立时同步一次，仅 publicationID 变化或清除时更新并失效旧快照；重复 reload 不重复通知。清除停止跟随并清发布内容，旧异步结果不能复活已清配置。Resources 只含 LICENSE/NOTICE，系统中的视频名称和封面取自当前发布。

### 单数据根与旧组件退出

App Group 使用 H9QWU9XN8R.MWX，唯一实际数据根为组内 ScreenSaver；旧逻辑路径仍为用户 Application Support/MyWallpaperX/ScreenSaver。仅显式保存时准备迁移：原目录与指向新根的链接通过 Darwin RENAME_SWAP 原子交换，旧逻辑路径变为别名，媒体/lease/socket inode 保留，不复制视频或多存 current.json。交换失败保留原目录，中断的自指链接可重试；既有跟随视频提交不提前迁移或检查组件可用性。短组名使规范化 socket 路径含 NUL 为86字节，低于 sun_path 的104字节边界。

已安装旧 .saver 不自动删除或重装；配置面板在发现旧组件时显示移除入口，只按已知旧 bundle ID 删除，保留视频和新扩展，未知同名目录保留。新版随 App 更新，不另建安装器或签名比较链。旧宿主沙箱能否经新根别名继续读媒体仍未完整真机验收；新版选择和旧组件移除应由用户确认，不能用保存完成冒充系统已选中。卸载整个 App 前需在系统设置换成其他屏保，不能承诺删除 provider 后仍可播放。

### 验证、研究取舍与余项

早期原型在本机 macOS27.2、主 App 退出且同时选择 desktop/screenSaver 时，用户确认主动锁屏和自动屏保持续运动；这不能证明当前仅屏保目录可以即时主动播放。私有请求已观察到 destination、isPreview、presentationMode、activityState；mode=active 的完整真宿主语义仍需证据，合成输入门不能冒充系统调用。用户反馈屏控在占用时主动锁屏无即时视频，但尚未证明屏控是原因。

最近行为门覆盖实际系统 codec、匿名 NSXPC 首推/变更/清除/断开、真实 H264 的无主 App 活动请求、挂起恢复、多请求退出、预览 context/layer 保持、失败静帧/租约，以及发布、取消、旧组件移除和原子迁移。Debug/Release 已构建，清理后的组件 Resources 均仅 LICENSE/NOTICE；Release/CI合同及独立静态审查通过。Developer ID/hardened 本地签名无正式时间戳、未公证，不构成正式发布验收。证据身份与有界日志位于本树忽略的 .artifacts/lock-screen-native，保留一份 .build-cache/checkpoint-native 供迭代。

未完成：保持原系统墙纸且主动锁屏立即动画、延迟密码冷启动、连续锁定/睡醒、多屏、HEVC/大视频、低电量/电池及长期功耗稳定性；macOS26仅为构建目标，没有该版本真机结论。当前改造没有证明性能、能耗优于旧 .saver，也不能把等待闲置计时后播放当新版独有能力。

已否决在本批继续的路线：不改系统墙纸 Index、不重启系统服务、不把主 App 锁屏通知当完整播放入口、不复制原静态图来模拟保留原 provider，也不退回旧组件后声称即时目标已修复。若继续即时动态锁屏，须先证明“不接管桌面、主 App 退出、主动/自动均正确”再扩展迁移；若收敛回旧 .saver，须由用户明确选择，不能在讨论时擅自撤回。第7节仅保存迁移前的历史交付，不作为新宿主验收。
