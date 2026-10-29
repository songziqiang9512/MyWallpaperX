# macOS 视频屏保接入设计

<!-- document-role: active-plan -->

本文件是本专项唯一现役设计。**2026-10-29用户明确收敛为仅支持Video，撤销本批所有Scene/Web屏保改造。** 此裁决替换此前三引擎屏保目标；不得根据旧goal文字、旧方案或测试产物重新接回Scene/Web。主App原有Scene/Web桌面播放保持原样。

## 1. 目标与系统边界

- 面向macOS 26以上，以公开ScreenSaverView组件播放本地视频，自动安装组件、部署已选视频并保存配置；系统负责屏保窗口、闲置启动、密码和退出。
- 主App完全退出时仍能独立播放；不需要启动或升级旧的/Applications App来维持屏保，不以活动socket作为播放许可。
- 不做独立密码页替换、私有WallpaperExtensionKit、后台录制、转码、预编译、全局保活或大小核绑定。静态后备只来自所选视频，不开放图片/Scene/Web为屏保来源。
- 真实锁定与手动ScreenSaverEngine、系统全屏预览、系统小预览分别取证；isPreview不是认证状态。开始时间和密码要求保留用户设置。用户已要求删除App内预览，不再提供额外播放器入口。

## 2. 收敛理由与退役范围

本机收敛前实测磁盘占用：已安装Debug测试组件126.7 MiB，原三引擎Release组件96.5 MiB（可执行约29.4、资源60.5、编译助手6.6）；该Release App约308.5 MiB，/Applications旧App约213.3 MiB。此为本地包体，不是压缩DMG增幅。用户据此选择Video-only。

撤销本批Scene/Web外部surface接缝、runtime bundle抽取、Web命名空间迁移、屏保专用媒体/权限分支和对应测试适配，恢复它们相对本工作树HEAD的原实现；删除没有剩余消费者的新类型与新fixture。保留视频共享静帧执行、配置/发布/安装、App入口和暂停交接。组件不得再编入Scene/Web、QuickJS、Metal着色器、stock/font库或shader编译工具。App自身仍正常携带这些原有能力。

退役前192个所属源码文件已保存到ignored的.artifacts/lock-screen-screensaver/retired-realtime-saver-sources.tar.gz（约1 MiB，含原HEAD和逐文件hash），供查明已放弃方案；不进入发布、不作为现役代码。旧三引擎灰屏根因未确认，不能写成已解决。除非用户重新授权，不再重复此方向实验。

## 3. 职责和最小数据流

1. ScreenSaverCoordinator从现有资料库解析可用视频；Steam版本租约和文件安全scope只在复制事务持有，不改来源下载/播放逻辑。
2. ScreenSaverIntegration沿一个utility串行队列复制实际视频到私有不可变Media/UUID，调用原VideoStillFrame从该副本生成poster.jpg；二者就绪后原子发布current.json。取消/清除/导入/重置/退出沿原代次撤销，不新增owner。
3. ScreenSaverConfiguration只含schema/publication、视频generation、标题、opaque来源关联、视频/静帧相对路径、布局和电池策略。保留kind=video作为格式判别，拒绝把旧Web/Scene入口当视频；不再依赖它们的属性或资源类型。
4. 系统MyWallpaperXScreenSaverView直接在系统提供的子视图用AVQueuePlayer/AVPlayerLooper播放，AVFoundation持有唯一视频时钟。App不编入该视图，不创建额外预览播放器、桌面窗口、渲染服务或每帧IPC。
5. ScreenSaverActivityClient/Monitor仅让配套新版App把屏保活动合入原PlaybackPolicyController的OR暂停原因；没有App时连接失败只结束活动连接，绝不停止视频。关闭最后一个活动view只撤本原因，不覆盖用户暂停。

资源租约保留到解码器停止；发布维护只回收自有、非当前/上一份、无租约的generation。未知目录和组件保留。视频源移动/删除不影响已部署副本；删除入口提示副本可在设置清除。显式清除/卸载撤销在途操作并清持久意图，不因下一桌面提交复活。

旧schema=1的视频内容可沿同一解码读取；旧Scene/Web或损坏配置不播放、不做跨引擎迁移。用户保存一个有效视频时可原子替换不支持的旧配置，候选失败仍保留原磁盘值；不强迫先执行一次清除。纯布局/电池更新仅对实际可读的视频配置生效，不复制源文件。

## 4. 用户操作和UI

- 配置面板复用Steam登录面板的原生玻璃底座和胶囊按钮，500×640原生sheet（原520×700），固定单行标题与图标沿Y轴居中，不保留装饰副标题；左下角“清除内容”“卸载组件”胶囊按钮不带省略号、右下角“保存屏保”/取消；内容从上至下分为选择视频、播放选项、系统启用指引，一屏展示，不再嵌滚动区。三段内容用原生Stack等间距分配可用高度，段内保留正常行距，不把内容挤到顶部、底部留下大块空白。设置入口位于“显示设置”的“多屏支持”上一行。配置面板本身不启动播放器。提示区分尚未部署、已保存和系统选择未知，不用“已保存”冒充系统已经启用。
- 共享WallpaperPanelSurface直接继承NSGlassEffectView，由原生cornerRadius独占外轮廓（默认20、详情22）；退役外层NSView的CA裁剪/描边、内层玻璃及额外底色，不再用两套圆角叠加。唯一bodyView绑定真实contentView，所有共享面板消费者向bodyView添加内容。保持regular玻璃及用户认可的深色tint黑0.10/body黑0.18，浅色controlBackground 0.15/body白0.82；降低透明度/增加对比度用body实色且保留交互。详情/属性外层只保原阴影，材质不改宿主窗口透明度、不监听主窗色彩、不生成缩略图。用户已停止追求进一步透色，不扩大为模态呈现方式改造。
- 配置顶部一行依次为144×90静态缩略图、标题及当前/未保存状态、右对齐“选择视频”按钮，三者沿Y轴中心对齐；文字列伸缩，按钮保持原生尺寸。删除选择区、选项区的内部矩形底板，仅保留外层原生玻璃、内容分隔线及正常控件背景，标签和右侧控件沿同一边界对齐。选图直接使用原ArtworkProvider的共享liveLoader/资源身份；仅在来源缺失且sourceIdentity匹配时读已部署poster，复用原静态图缓存，不常规重复读第二张图。换源/关闭取消消费，迟到回包不能串图。关闭按钮与详情复用同一32×18控件；首开由窗口自身接管首响应，不强制给选择按钮画蓝焦点，也不全局关闭Tab焦点提示。普通重复展示只聚焦最上层子面板；明确新reference先撤旧子面板再消费，不吞选择命令。
- 用户确认App预览多余后，同批删除按钮、预览窗口/播放器和遮挡状态、Coordinator独占的预览解析/后备入口以及组件App预览数据分支。组件视图不再编入主App；正常保存仍沿原单一解析/版本租约/scope复制事务，系统屏保播放与系统静态小预览保持原样。缩略图身份/迟到回包测试保留，只退役两项无消费者的App预览断言。
- 视频选择直接扩展原WallpaperPlaylistPickerController为两种目的：原列表添加保持多选及原事务，屏保单选只返回当前视频、不写列表关系；复用同一网格、缓存、搜索/缩放和原生模态域。屏保仅呈现全部/我的视频/我的下载中的本地可用Video，取消不改草稿，选择不自动播放或发布。选择器和卡片“用作屏保”只接纳本地可播放Video；在线视频未下载时沿原下载反馈，Scene/Web/图片不提供屏保入口。
- 固定视频，或“跟随最近播放的视频”。手动选择视频同时切为固定模式，确保保存的就是面板所选内容。跟随只消费原成功且记录最近使用的Video提交；桌面切成Scene/Web/图片时保留最近已保存视频，不报错、不复制、不把不支持来源写进目标。
- 布局为完整显示/填充屏幕。始终静音、1倍速；使用电池默认只显示本视频静帧，可显式启用普通电池动态；系统低电量模式仍静态。
- 系统小预览仅静帧；实际系统surface不套用App窗口遮挡判断。
- 首次保存自动部署自有组件并打开系统墙纸设置，系统选择只保留公开机制支持的操作；不改写系统Index、不kill系统宿主。后续换视频不重复打开设置。
- 系统启用区按本机macOS26实际界面精简为三步：保存屏保→屏幕保护程序…/自定义/其他/全部显示/MyWallpaperX→设置启动屏幕保护程序…时间并完成；“打开屏保设置”“锁屏设置”并排等宽。页面保留屏保早于熄屏的短提示，锁屏按钮tooltip说明密码项的完整名称；组件清除/卸载固定左下角。系统开始时间、密码与组件选择只由用户设置，UI核对不改变它们。
- 当前/Applications旧App（2.12.0/284）没有内嵌屏保。测试组件独立安装于用户Library/Screen Savers；安装态、发布内容和系统是否已选中分别呈现，不假定版本号相同就能力相同。

## 5. 生命周期、功耗和失败

AVFoundation自身解码显示；animateOneFrame不推进视频、不读配置。继承isAnimating保持系统生命周期，静态/AV使用稀疏基类timer；stop、视图脱离、睡眠时取消准备、停player、撤looper和child view，迟到结果按代次丢弃。睡眠/电源恢复只对仍有效的view重建；preventsDisplaySleepDuringVideoPlayback=false，不修改熄屏时间。

视频准备期间显示该版本静帧；不可读/无有效时长的候选局部失败，不循环重启。无静帧无法完成发布，保留旧配置。App退出不结束系统屏保；解锁只重算原桌面政策，不重复设壁纸或写最近使用。

用户此前暂停锁屏验证；另一会话已明确归还构建/窗口/CPU/GPU，可做普通构建和窗口验证，系统锁屏仍等待恢复许可。不用旧三引擎低CPU、一次运动或构建成功证明Video持续播放/功耗。

## 6. 打包与验证

组件target只编译ScreenSaverSources的Video视图、配置和可选活动client；没有QuickJS桥接头及Scene/Web源码组。资源阶段仅复制LICENSE/NOTICE和静态thumbnail.png、thumbnail@2x.png，无额外资源构建脚本。两张缩略图采用本机Apple Random.saver相同的90×58/180×116规格，将本项目AppIcon居中呈现；系统“其他”列表直接消费静态资源，无运行时绘图或播放器。App图标变化后运行`xcrun swift script/generate_screen_saver_thumbnails.swift`重生成，生成器从AppIcon目录的Contents.json选择1024px源图，勿手改生成PNG。主App不重复打入这两张图。CI保留组件版本与App一致、arm64/macOS26、inside-out签名、公证随App、符号包和实际包体检查，删除组件shader助手签名与大资源要求；主App原助手签名不动。

复用DerivedData时须在本轮构建前精确清除自有旧.saver产物及其App内副本，防止已退役资源残留；不清主仓/并行缓存。验证实际Release包中无Scene/Web资源和助手，并实测组件大小，不以源码行数估算收益。

已安装组件不能仅按version/build跳过更新：本机两端同为2.12.0/284但UUID与二进制不同，已证旧组件会被错误保留。仅在安装事务比较现有CodeDirectory unique identity，相同才复用；不执行签名有效性验证、不全文哈希或扫资源，不进入打开面板/播放路径。身份不可读或未签名时正常重新复制，不变为新权限门。夹具使用真实隔离MachO/BNDL签名，待验证同构建不重复拷贝、同版本代码身份变化替换、升级与foreign保留。

按阶段执行：①撤销Scene/Web并收敛数据/target/UI；②最近发布/取消/租约/导入/暂停/安装门和独立审查；③Debug、Release及实际资源/签名闭包；④资源允许后用真实视频验证普通预览和系统自动闲置启动，App完全退出是基线，配套测试App运行只是对照。至少覆盖循环超过视频时长、停止/重新启动、遮挡恢复、低电量/睡眠、主App退出、更新/清除。每阶段问题直接在原owner修复，不用新后台层掩盖失败。

## 7. 当前证据与未完成项

- 当前验收仅为Video-only；旧三引擎灰屏根因不当作已解决。用户暂停真实锁定验证的要求保留，普通窗口、系统小预览与真实锁定分别记录。
- 最新整App Debug构建23.92秒通过，随后组件元数据增量3.65秒通过；App预览已删除，单行标题/图标、三列居中选择区、固定胶囊页脚、一屏分区间距和最终文案已由实际窗口确认。设置入口现位于“多屏支持”上方。此后仅静态资源路由和文档有调整，最终整合构建仍需核实。
- 最新近门26个Python测试在28.63秒通过：实际封面身份/复用/取消11项、活动socket14项、发布/取消/租约/同版本安装33项；Release合同16和CI路由7个测试通过。新增生成器的路由遗漏经独审修正到既有system-screen-saver组，路由器68个测试通过。
- 既有共享UI回归已通过：详情/属性标题24组与状态4组；Picker40、Steam登录22、API输入5、列表编辑器54、系统模态32项。初始汇总中3处fixture失败分别修正为标准Resources路径、真实bodyView查找、宿主居中与失败诊断；保留原断言及失败日志，不将原失败汇总冒称全绿。删除App预览后仅退役2项无消费者断言。
- Debug测试包整包复制并重签，不能只替换启动shim。已验证实际代码dylib及签名；此前旧dylib造成的像素结论作废。测试App必须用显式HOME/CFFIXED_USER_HOME启动，退出后只用进程清单确认；CUA再次getApp/AX会自动重启App，不能用于确认退出。
- 同版本安装实际替换已验证到用户Library/Screen Savers，签名strict通过；安装前后current.json字节未变。最新组件UUID 4123B5C2-D6E5-335C-82DF-CFFE45B5A336。媒体内容的后续用户选择不由测试回滚；系统选择、密码和闲置时间保持用户控制。
- 系统“其他”列表已实际显示本App图标。只有PNG入包不等于目录更新：本机27.2的WallpaperLegacyExtension把SHA256(path+"-"+name)作为磁盘PNG键，旧缓存存在便不重写，不包含mtime/版本。独立静态复核arm64e与x86_64均读取bundle.imageForResource("thumbnail")；ScreenSaverThumbnail元数据试验无效，已退役该字段及无消费者的验证要求。
- 图标验证只将已确认属于本模块的一个默认蓝图缓存移到本轮ignored产物并保留receipt，再由系统正常重建；其他目录项未动。Settings/目录扩展的临时重开用于本次实验，产品不加入杀进程、扫缓存或改系统Index的链路。旧PNG、前后hash、安装receipt在.artifacts/lock-screen-screensaver/runtime保留，避免后续重复试验尺寸/mtime/多层背景。
- 主App退出后，先前真实已安装组件在一次性普通窗口运行53秒，AV时间正常，约19秒视频观察到两次循环；stop释放、同view重启继续、ready且无失败。此为系统动态角色的普通宿主，不是认证锁屏或功耗基线，不外推低电量/睡眠/长期锁定。删除App预览后的最终组件仍需结合最终Release做最近运行复核。
- 单独组件上一轮Release320 KiB仅为旧测量；新增两张PNG后最终包体待实测。整App Release WMO及实际资源/签名/dSYM/Debug诊断排除尚未完成；本树缓存中的App内嵌旧.saver含退役资源，构建前须精确移除该旧输出，不能清理主App Scene资源。
- 三位子代理完成UI、发布/安装/状态及CI/target的独立复核。仅发现不可用本地视频误报“先下载”和新生成器未路由两项，均在原链路修正。更早Debug有3条未改动Scene并发警告；最近增量无新源码警告不代表全仓零警告。
- 用户已授权最终通过后提交并合入主仓codex/engine-refactor-program，保留中途其他会话的新提交和未提交内容，不推送、不替换/Applications。整合验证、最终Release与实际系统锁定边界分别报告。保留本树一份构建缓存、最新测试App/隔离home及有界证据，已停止的临时宿主/编译工具在交接前清理。

公开接口：[ScreenSaverView](https://developer.apple.com/documentation/screensaver/screensaverview)、[AVPlayerLooper](https://developer.apple.com/documentation/avfoundation/avplayerlooper)、[允许显示器休眠](https://developer.apple.com/documentation/avfoundation/avplayer/preventsdisplaysleepduringvideoplayback)、[原生玻璃](https://developer.apple.com/documentation/appkit/nsglasseffectview)。这些接口不构成动态密码页替换授权。

玻璃容器用法依据：[Apple WWDC25 AppKit 新设计](https://developer.apple.com/videos/play/wwdc2025/310/)（contentView，避免同级背景叠放）。
