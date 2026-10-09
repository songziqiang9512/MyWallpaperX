<!-- document-role: active-plan -->
<!-- retirementCondition: 播放器来源进入现役合同并完成真实换曲、权限、来源切换及退出验收后归档；未覆盖播放器仍保留能力缺口。 -->

# Scene 真实播放器媒体输入

补齐播放器→现有Scene收件箱入口，保持作者脚本、文字、纹理及唯一合成链。Apple Music、网易云、QQ音乐、汽水等分别验证metadata、封面、状态/进度；系统会话优先，公开接口补充。歌词须先确认作者消费合同和来源，缺字段保持缺口。多样本复用同一producer，不按样本选视觉行为；单一播放器通过不代表全平台完成。

## 决策

统一系统入口覆盖潜力最高。2026-10-05的自有Native→系统Perl→Native实验取得真实metadata与封面，宿主差异及有限Scene证据见[实施记录](../../history/scene-system-media-input-implementation-2026-10-05.md)。仅消费经独立审核的参考中性合同；渠道边界遵循[D6](../../../web/mediaremote-nowplaying-design.md)，不改系统安全设置、身份或私有权限。

系统入口后续验证真实换曲、来源切换及退出；Music只读Apple Events作为补充。先验证统一入口覆盖，不扩大逐播放器硬适配；来源不明时不以Music旧曲替代。

## 来源与职责

- 设置以单一开关表达曲目信息意图，默认关闭。需求期间持续观察系统；snapshot/noSession决定会话，拒绝Music旧曲接管。仅missingResource允许完整Music fallback；pending、helperUnavailable及transport故障不猜选Music。系统选中com.apple.Music时，公开适配器只补albumArtist及其已知music媒体类型：非空title及artist/album与系统值逐项精确相同才接纳；系统仍唯一提供歌曲、状态/进度及封面。两个API的opaque曲目ID不可直接比较，字段匹配不冒充身份等价，不据此换封面。来源/曲目改变推进选择generation并拒收旧补充回包（含A→B→A）；transport epoch继续只管观察器寿命，每次系统发布重算补充，避免字段交替清空。公开读取失败只撤补充，不清有效系统会话；暂停继续显示系统选中的同来源曲目。系统观察库随 Developer ID Release 分发，须先签嵌套库再签 App（[渠道裁决 D6](../../../web/mediaremote-nowplaying-design.md)）；Mac App Store 不得包含该 backend。授权只由用户发起，不启动播放器。
- 偏好只拥有选择意图。Scene 进程内一个媒体 producer 拥有需求集合、请求 epoch、串行后台读取及唯一发布权；多个显示器和切换候选不各自轮询。
- 已准备的媒体消费者产生需求；最后需求退出停止计时器并清空已发布会话。Debug 的受控输入默认不启动真实 producer，独立真实来源验收显式启用。
- Music公开适配器只读取当前运行的目标PID；系统实验来源核对系统选中来源与曲目identity。查询不发送播放、切歌、音量或库写入命令。权限检查、短事件超时及整体查询预算均在非帧队列执行；一时只有一个请求在途，普通帧只读现有快照。
- Music公开`track.album artist`（`pAlA`）进入既有`albumArtist`字段；空或平台明确不支持该可选属性时发布空，沿用作者自己的`artist`回退。权限、超时、畸形值及换曲仍按原事务失败处理，不伪造系统来源缺失的专辑歌手。
- 读取前后核对曲目 identity；跨曲目结果整次丢弃。需求退出、禁用及transport重启推进epoch；Music回包额外核对目标PID、请求时系统选择的曲目key及选择generation，旧回包不得覆盖新状态；暂停保留同来源的曲目并发布 paused。
- 歌曲信息、封面、播放状态和位置/时长作为一个会话提交给现有 `SceneMediaThumbnailInbox`；它继续唯一拥有各通道 generation。缺字段显式清除，不能保留前曲封面；独立通道API留给作者事件与调试。
- 系统实验辅助库归 `Systems/Media`，在独立系统宿主运行，不编入主App执行路径。宿主通过有版本、有限长的JSON行输出来源和曲目identity、状态、metadata与封面；父端只做解码和限额校验，仍由现有producer统一发布。单一长期进程按低频采样，封面按独立artwork identity更新，缺identity时低频比较受限图片字节，只传输变化；来源退出、管道失败或最后需求消失时停止进程并清状态。辅助库构建/签名随Debug App产物登记，不能加载参考项目二进制。通过公共Perl XS入口在动态装载返回后启动，不能在装载构造器持锁时运行读取循环。

## 失败、成本与退出

无曲目、未授权、未运行、超时和协议不支持分别记录，不能把取不到数据写成系统没有播放。失效来源撤旧状态，壁纸其他部分照常播放。封面越界或缺失只影响封面；metadata 安全边界复用现有收件箱。只在有需求时观察系统，公开补充仅在系统选中Music或观察库缺失时低频读取，封面按各输入自己的曲目缓存；缺图允许后续补齐。没有已获用户权限时不持续请求或反复弹窗。系统管道12秒无完整记录即回收；需求仍在时以2至30秒封顶退避重试，每次重启推进epoch。未知系统媒体类型保持空值，不推定为音乐。

实验系统宿主只装载项目自写、身份固定的本地辅助库；输入端负责有界读取、类型校验及进程退出，不能每帧启动进程或重复传输完整封面。不引入私有 entitlement、网络封面搜索、另一个合成器或帧内 IPC。普通系统装载或签名检查失败时记录不可用，不关闭检查。任何来源未在真实签名 App 获得可靠数据时保持未验收，不以模拟通过替代。

## 实例纹理 fallback

作者 base-material instance 的 provider 与 fallback 共用既有 source selection。Solid 的非白 `textures[0]` 不能丢成 procedural-white：现 `BaseMaterialBinding` 保留一个可选 `SceneAssetTextureIdentity`，沿 `SceneMaterialAssetTextureCatalog` 的 typed demand、准备与 frame registry 发布；没有该事实的现有白 carrier 和已加载 image fallback 保持原合同。只接纳已支持的instance/provider slot0与安全颜色asset；未知 instance、冲突 slot、已知 data purpose 仍局部拒绝。Ready 封面沿原 provider identity/完整性校验替换该 slot；absent/pending/clear 或 provider 失败时只消费同一作者 fallback，校验其完整 publication、PMA purpose、颜色内容、UV 与 sampler，缺失或不安全时局部拒绝，不伪造白图。封面转场的current/previous mask沿同一Store发布：在原preservedChannels物理纹理上增加purpose为mask、content为data的typed视图，保留原provider identity/generation、UV与sampler；不能让PMA颜色上传供mask读源通道。ready/pending、换图、解码失败、clear与冻结frame沿原事务一起更新，颜色值单独变化继续复用上传，不增加解码或纹理分配。普通帧只查已准备的typed atom，不重新解析或加载，不增加路径表、provider、cache或compositor。验收以非白fallback→current→clear、current/previous mask同纹理及失败/陈旧publication反例，和原包受控转场实际像素为准；[已有执行证据](../../capabilities/runtime-evidence-current.md#e-2026-10-08-media-base-fallback)不代替真实播放器来源验收。

## 封面颜色输入

系统与Music适配器在各自后台读取队列上，对新取得的封面调用同一个无状态 `SceneMediaArtworkPalette`；不在主线程/帧/每屏重复取色。适配器/producer复用既有同来源同曲目封面缓存，颜色与其字节绑定，和metadata、状态、timeline一起提交原Inbox。原显式颜色输入保持不变；没有图片或取色失败时只清本次颜色，不保留前曲颜色。

公开 [`MediaThumbnailEvent`](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/MediaThumbnailEvent.html) 只规定归一化RGB主/次/第三色、足够对比的文字色与黑白中对比更高者，未规定量化、排序或阈值。项目独立方案：ImageIO有界缩略至32px、转sRGB、忽略全透明并按alpha权重统计16级RGB色桶，按占比和稳定色键选前三；不足三色重复已有主色；全透明合法图片使用黑主色与白文字/对比色。文字优先使用满足4.5:1的次/第三色，否则取黑白中对比更高者；该阈值沿项目既有Web实现，对比按sRGB相对亮度计算。编码16MiB、维度8192及16M像素预算先验检查，取色不改变原纹理的alpha或颜色用途。

验收以自有纯色、多色占比、透明/半透明、坏图/预算、对比度及跨曲缓存反例，和真实339同封面的颜色事件→typed参数→GPU→画面对照为准。公开合同不支持宣称所选调色板逐值等于官方；精确官方排序仍是未验证范围，不猜私有算法。

## 验收

真实播放器的曲目、封面、暂停/恢复与退出必须进入同一实际场景并可见。仲裁须测Music三种状态不抢占、系统空/临时不可用、同来源暂停、两个API不同步、ABA迟到及禁用；系统缺封面的跨API身份桥接仍待证。自有输入验证缺封面、无曲目、迟到回包、来源切换、权限拒绝、目标 PID 退出及读取中换曲；检查无消费者时没有轮询，多屏只读一份。Debug build、独立审查、窄范围提交及原媒体消费者回归必须完成。系统授权与签名、运行证据和未覆盖来源分别记录。
