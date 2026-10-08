<!-- document-role: active-plan -->
<!-- retirementCondition: 播放器来源进入现役合同并完成真实换曲、权限、来源切换及退出验收后归档；未覆盖播放器仍保留能力缺口。 -->

# Scene 真实播放器媒体输入

本设计补齐播放器到现有 Scene 媒体收件箱的生产入口，不改变作者脚本、文字、纹理及最终合成职责。所有常用播放器仍是目标；Apple Music、网易云、QQ音乐、汽水等分别验证metadata/专辑、封面、状态/进度和歌词。系统会话优先，平台公开接口补充；未提供的字段保持缺口，不能以歌名/封面通过代替歌词支持。歌词需先定位作者消费合同和可用来源，再进入同一通用媒体输入；不按播放器或样本选择作者字段、视觉行为；平台来源适配共用同一producer与合成链。多样本验收复用同一producer，单一播放器或339通过不等于平台/全样本完成。

## 决策

统一系统读取覆盖潜力最高。原生探针只能识别网易云来源，不能据 metadata 空排除统一入口。2026-10-05 经独立审核的参考中性合同提示宿主差异；项目自写同一签名辅助库、相同接口及2秒等待的 Native→系统Perl→Native 对照中，仅中间一次取得真实标题、歌手和播放状态。自有封面范围请求已取得可解码图片；实际Scene消费取得有界证据，范围见[实施记录](../../history/scene-system-media-input-implementation-2026-10-05.md)。其私有发布边界继续由[D6](../../../web/mediaremote-nowplaying-design.md)约束，仅允许明确实验配置，不进入默认来源；不改变系统安全设置、不伪造身份或添加私有权限。

先把统一系统入口推进到网易云真实歌曲与封面进入339场景，再验证来源切换及退出。已写的 Music 公开只读 Apple Events 保持显式来源补充；统一入口覆盖未验证前，不扩大逐播放器硬适配。只按播放器 API 身份选择读取适配器，不能按壁纸样本选择视觉行为。系统实际选中来源不明时，不以 Music 的旧曲目替代。

## 来源与职责

- 设置以单一开关表达曲目信息意图，缺省关闭。Apple Music 运行且已授权后，只有快照被 inbox 接受才接管系统来源；探测无曲目、失败或快照被拒时保留已有系统会话与发布。有效接管推进 epoch 并停止旧 transport，迟到回包不得覆盖新来源。系统观察库随 Developer ID Release 分发，须先签嵌套库再签 App（[渠道裁决 D6](../../../web/mediaremote-nowplaying-design.md)）；Mac App Store 不得包含该 backend。读取授权由用户操作发起，拒绝或没有运行目标时不启动播放器。
- 偏好只拥有选择意图。Scene 进程内一个媒体 producer 拥有需求集合、请求 epoch、串行后台读取及唯一发布权；多个显示器和切换候选不各自轮询。
- 已准备的媒体消费者产生需求；最后需求退出停止计时器并清空已发布会话。Debug 的受控输入默认不启动真实 producer，独立真实来源验收显式启用。
- Music公开适配器只读取当前运行的目标PID；系统实验来源核对系统选中来源与曲目identity。查询不发送播放、切歌、音量或库写入命令。权限检查、短事件超时及整体查询预算均在非帧队列执行；一时只有一个请求在途，普通帧只读现有快照。
- Music公开`track.album artist`（`pAlA`）进入既有`albumArtist`字段；空或平台明确不支持该可选属性时发布空，沿用作者自己的`artist`回退。权限、超时、畸形值及换曲仍按原事务失败处理，不伪造系统来源缺失的专辑歌手。
- 读取前后核对曲目 identity；跨曲目结果整次丢弃。来源变更、退出、禁用推进 epoch，旧回包不得覆盖新状态；暂停保留同来源的曲目并发布 paused。
- 歌曲信息、封面、播放状态和位置/时长作为一个会话提交给现有 `SceneMediaThumbnailInbox`；它继续唯一拥有各通道 generation。缺字段显式清除，不能保留前曲封面；原有独立通道 API 留给原作者事件与受控调试。
- 系统实验辅助库归 `Systems/Media`，在独立系统宿主运行，不编入主App执行路径。宿主通过有版本、有限长的JSON行输出来源和曲目identity、状态、metadata与封面；父端只做解码和限额校验，仍由现有producer统一发布。单一长期进程按低频采样，封面按独立artwork identity更新，缺identity时低频比较受限图片字节，只传输变化；来源退出、管道失败或最后需求消失时停止进程并清状态。辅助库构建/签名随Debug App产物登记，不能加载参考项目二进制。通过公共Perl XS入口在动态装载返回后启动，不能在装载构造器持锁时运行读取循环。

## 失败、成本与退出

无曲目、未授权、未运行、超时和协议不支持分别记录，不能把取不到数据写成系统没有播放。失效来源撤旧状态，壁纸其他部分照常播放。封面越界或缺失只影响封面；metadata 安全边界复用现有收件箱。只在有需求且选定来源时低频刷新，封面按曲目缓存；缺图允许后续补齐。没有已获用户权限时不持续请求或反复弹窗。系统管道12秒无完整记录即回收；需求仍在时以2至30秒封顶退避重试，每次重启推进epoch。未知系统媒体类型保持空值，不推定为音乐。

实验系统宿主只装载项目自写、身份固定的本地辅助库；输入端负责有界读取、类型校验及进程退出，不能每帧启动进程或重复传输完整封面。不引入私有 entitlement、网络封面搜索、另一个合成器或帧内 IPC。普通系统装载或签名检查失败时记录不可用，不关闭检查。任何来源未在真实签名 App 获得可靠数据时保持未验收，不以模拟通过替代。

## 实例纹理 fallback

作者 base-material instance 的 provider 与 fallback 共用既有 source selection。Solid 的非白 `textures[0]` 不能丢成 procedural-white：现 `BaseMaterialBinding` 保留一个可选 `SceneAssetTextureIdentity`，沿 `SceneMaterialAssetTextureCatalog` 的 typed demand、准备与 frame registry 发布；没有该事实的现有白 carrier 和已加载 image fallback 保持原合同。只接纳当前支持的 instance/provider slot0 形状与安全颜色 asset；未知 instance、冲突 slot、已知 data purpose 仍局部拒绝。Ready 封面沿原 provider identity/完整性校验替换该 slot；absent/pending/clear 或 provider 失败时只消费同一作者 fallback，校验其完整 publication、PMA purpose、颜色内容、UV 与 sampler，缺失或不安全时局部拒绝，不伪造白图。封面转场的current/previous mask沿同一Store发布：在原preservedChannels物理纹理上增加purpose为mask、content为data的typed视图，保留原provider identity/generation、UV与sampler；不能让PMA颜色上传供mask读源通道。ready/pending、换图、解码失败、clear与冻结frame沿原事务一起更新，颜色值单独变化继续复用上传，不增加解码或纹理分配。普通帧只查已准备的typed atom，不重新解析或加载，不增加路径表、provider、cache或compositor。验收以非白fallback→current→clear、current/previous mask同纹理及失败/陈旧publication反例，和原包受控转场实际像素为准；[已有执行证据](../../capabilities/runtime-evidence-current.md#e-2026-10-08-media-base-fallback)不代替真实播放器来源验收。

## 封面颜色输入

系统与Music适配器在各自后台读取队列上，对新取得的封面调用同一个无状态 `SceneMediaArtworkPalette`；不在主线程、渲染帧或每个显示器重复取色。适配器/producer复用既有同来源同曲目封面缓存，颜色与其字节绑定，和metadata、状态、timeline一起提交原Inbox。原显式颜色输入保持不变；没有图片或取色失败时只清本次颜色，不保留前曲颜色。

公开 [`MediaThumbnailEvent`](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/MediaThumbnailEvent.html) 只规定归一化RGB主/次/第三色、足够对比的文字色与黑白中对比更高者，未规定量化、排序或阈值。项目独立方案：ImageIO有界缩略至32px、转sRGB、忽略全透明并按alpha权重统计16级RGB色桶，按占比和稳定色键选前三；不足三色重复已有主色；全透明合法图片使用黑主色与白文字/对比色。文字优先使用满足4.5:1的次/第三色，否则取黑白中对比更高者；该阈值沿项目既有Web实现，对比按sRGB相对亮度计算。编码16MiB、维度8192及16M像素预算先验检查，取色不改变原纹理的alpha或颜色用途。

验收以自有纯色、多色占比、透明/半透明、坏图/预算、对比度及跨曲缓存反例，和真实339同封面的颜色事件→typed参数→GPU→画面对照为准。公开合同不支持宣称所选调色板逐值等于官方；精确官方排序仍是未验证范围，不猜私有算法。

## 验收

真实播放器的曲目、封面、暂停/恢复与退出必须进入同一实际场景并可见。自有输入验证缺封面、无曲目、迟到回包、来源切换、权限拒绝、目标 PID 退出及读取中换曲；检查无消费者时没有轮询，多屏只读一份。Debug build、独立审查、窄范围提交及原媒体消费者回归必须完成。系统授权与签名、运行证据和未覆盖来源分别记录。
