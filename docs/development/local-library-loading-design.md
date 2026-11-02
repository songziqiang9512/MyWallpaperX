# 本地资源先呈现与缩略图回访

<!-- document-role: active-plan -->

<a id="overview"></a>
复核日期：2026-11-03。负责人：repository-maintainer。入口：[主界面专项](main-window-playlists-redesign.md#73-页面命令和快照)。

2026-11-02用户目标：打开App先显示上次本地内容，目录检查在后台更新；本地视频、图片和自建列表快速双向滚动时，已取得缩略图优先复用。该卡同时覆盖列表内已入库Steam/Pixabay/在线图片的本地记录，在线浏览预算和播放引擎保持。状态：R62实现、最近行为门和签名Debug已完成，保留文末三项原生验证限制；真实用户库人工体验待验。R61普通精简候选后移。

<a id="video-warm"></a>
## R107：无持久封面路径的视频复用已有像素

2026-11-03完成局部暖读取修复，完整照片级目标仍未验收。真实Provider/cache及原卡片configure已复现：thumbnailPath为nil，真实resolver已将派生JPEG暖入原cache，挂起原串行验证队列后旧卡片当次仍无图，显式路径对照立即有图。新导入生成只通知、不回填该字段，不仅历史数据受影响；本地视频和自建混合列表共用该owner。

**裁决与成本。** 原cachedThumbnail保显式路径优先；nil时以记录path纯计算原cacheKey/thumbnailOutputURL，读取同一cache。无normalize/stat、模型回填、新状态或缓存；规范路径立即复用已解码图，历史alias/relative不保证同步命中，继续原异步resolver。原验证、删除最终清图、取消/串台与播放许可保留。产品3增1删净+2行；nil记录每次暖peek增加一次原SHA键计算，避免模型发布/持久化和另建路径索引。Apple的[预热合同](https://developer.apple.com/documentation/photos/phcachingimagemanager/startcachingimages%28for%3Atargetsize%3Acontentmode%3Aoptions%3A%29)明确已准备图可立即交付；当前首断点是现有暖键未接通，未见需要换语言/组件或研究系统二进制的证据。

**验证。** 同一最终真实路径/Provider/cache/card切片夹具，旧版21控制全真，仅nil当次暖图断言红；候选21控制及同步断言全过。显式不同JPEG优先、alias/relative最终恢复、模型不写、clear及保留内存时删除派生文件后的最终清图均保。实际normalize/pathExists入口计数在暖configure前后均为3/2，仅证明这两入口未增加调用，不称全局零物理IO。原validation21、repair16事实全过，6307输入和6实际子过程稳定；原完整hover装配仅编译通过，未重跑其已知原生超时，不称交互验收。测试净+215行：真实owner装配复用、131行反例夹具及原3装配依赖补齐，原断言保持，没有复制SHA算法。

签名Debug 25.805秒、5868构建输入稳定，strict/deep通过；无新增Swift警告，仅原CS0665/CS8603。用户媒体只读，不改Scene引擎、共享接口、数据库或卡片交互。

**调查与下一步。** 同轮SIL像素/交付时线探针173帧未采到背景点、源解码0；插桩改变时序，未重现不等于R106残余已修复。另在真实完整Adapter/真实Video和SIL模型、受控来源数组中，10k尾部116项在首provider前比较1,153,330次；独立未插桩-O五轮中位Video64.929ms/SIL49.484ms，缺失56.456/43.080ms；不是整App FPS。下一批优先在原viewport内批量解析，保原始UTF8身份、重复首项、当前快照与撤销，不加持久索引。之后验证新生成Ready事件缺少网格消费者的可达等待窗口；尚未运行该反例，不混入本批。真实视频解码/窗口连续帧、混合大库/触控板和整App能耗仍待验，R62三项原生限制保持。

<a id="continuous-scroll"></a>
## R106：按最近位移准备前方缩略图

2026-11-03：完成原Grid/Adapter预取owner内的有界改善，**完整照片级连续目标仍未验收**。R62启动先呈现保持，不重做；本批不改Scene引擎、源数据库、缓存发布顺序、UI或鼠标/键盘业务。

**根因与选择。** 真实Grid/Adapter/SIL的160张不同色PNG，在盘暖、decoded LRU已清条件下取到合成黑卡。旧时线86–89仅在约135ms进入可见后才请求，派生图约138ms就绪、主回调约150ms；原viewport约83→132ms已跨过前方20项覆盖。没有再次进入原源解码，不把它误判为反复抽原图或语言问题。Apple的[PhotoKit预热合同](https://developer.apple.com/documentation/photos/phcachingimagemanager/startcachingimages%28for%3Atargetsize%3Acontentmode%3Aoptions%3A%29?language=objc)要求匹配显示参数并复用ready图；PHAsset不替代本应用文件模型。[AppKit预取](https://developer.apple.com/documentation/appkit/nscollectionviewprefetching)在本输入的只观测臂贴近实例化才通知，没有前瞻收益，故保原owner。必要时可换组件/架构/语言；当前公开资料与实测足以定位，无需Photos二进制研究。

**最终数据流。** 原clip滚动位置→复用lastViewportOffsetY计算最近跨行项数→本地邻居取原两屏下限与3倍最近跨行项数的较大者、仍cap96→纯indices算法按已知方向2:1距离权重排队→原onViewport/Adapter/cache。约2份最近位移留在前方，余1份在身后；方向未知对称，首尾不足由另一侧补齐。位移读真实clip矩形，实际可见项仍用collection交集，避免空交集无穷坐标转Int。没有新clock、字段、owner或并行预取链；退出原每步临时候选数组。独立Pixabay/Steam caller和统一Grid远程页保默认对称/原24上限，30ms、可见优先、取消、原资源身份与decoded预算保持。

**成本与退出。** 高速时邻居可从通常40增加至96，会增加有界提前工作与淘汰压力，不声称无成本。一次同轨迹时线两臂均100次派生解码、0次源重抽；文件检查115→100、provider调用1295→1339，属于该轨迹计数，不是CPU/FPS/能耗结论。缺失/损坏仍沿原反馈和重建，用户媒体只读，不改播放许可。纯隐藏暖图补参、全局提前image回调、main.async替代30ms、直接替换SDK及单独2:1原预算方案均未采纳；raw/动画需在静态成功回调前可复用，不能为早交图拆坏原发布关系。

**真实验证及上限。** 共用20点SCK own-window帧记录，7/10/16ms逐行往返及快折返，旧版两轮186/165帧中6/1帧卡内采样落背景；自适应189/184帧中0/1帧。只重分原预算的候选0/5不稳定，未采用。decoded-warm两臂各182帧均0背景点；每臂504次对象采样/10080项，源解码增量0。点采样与有限PNG不覆盖所有像素、边角、物理scanout或FPS。残余自适应frame17底沿150/152/153/154：显示前约8ms的willDisplay仍无图，显示后2ms才采到图；尚无证据证明已绑定但未draw，不能报空卡全消失。

最近门：真实Grid几何/方向/窗口租约/空库→单项→完整恢复30事实、真实缓存/磁盘/HTTP返回52事实全过。旧ReturnReuse叶遗漏真实Web enum的Codable仅在测试装配补齐，首编译失败原样保留；产品Model/flags未改。6306输入与实际编译输入稳定，最终签名Debug24.764秒/5867输入稳定、strict/deep过，无Swift新警告，仅原CS0665/CS8603。R62旧hover/key-sheet/拖拽采样限制不重跑、不冒充通过。

**下一验收。** 优先补残余晚交付时点及真实本地视频、图片/自建混合列表、超驻留与压力后的连续帧；再核Steam预热/显示尺寸不一致、无封面视频fallback排队。真实大图库/触控板、点击双击/播放/拖拽和整App能耗待人工/代表运行。保持原身份/clear撤权与单一缓存owner；若改成分级像素或prepared-view需求，先证明缺口并定义旧链退出。原[主界面设计](main-window-playlists-redesign.md#73-页面命令和快照)继续拥有页面交互。

**修复前已证断点。** Workspace在来源Catalog尚空时投影持久关系，Query将缺行当成unavailable；Video/SIL原索引读到后，Catalog仍等待全批fileExists/isReadable才首发。SIL启动还在主线程逐项清理缺失文件。Video缩略图暖命中先排串行路径检查再回主线程，现门只检查最终有图，未证明复用当帧；SIL已同步暖命中，其黑卡原因需区分容量/压力、复用、真实冷解码。当前预取中段通常仅前后各一行，不把这一几何事实冒认为卡顿时长。

**数据流与职责。** 原source持久模型 → 原source内存记录 → 无文件I/O的首份Catalog/PageSnapshot → 原卡片；原source后台扫描/校验 → 按原revision/generation提交差异 → 原查询增删/排序/更新。关系仍只归UserCollectionsStore，来源仍各自拥有索引/文件和命令，Catalog不新增持久副本，Grid不伪造媒体模型。后台结果不得覆盖启动后已提交的导入、删除或重新定位。

- Video复用现有在途SQLite初载、失败完整fallback与startup journal合并；首份内容只等待索引读取，不再等待媒体stat/metadata。不把当前索引塞入旧迁移冻结结果，不重复读取SQLite，不新增全局ready状态。
- SIL直接使用已读JSON行，缺失文件对账移到原服务后台；只在当前记录仍匹配时提交，保现用户操作/关系和源文件。未完成检查不等于文件丢失。
- 本地持久关系的缺行只有在相关来源完成初载后才可成为缺失卡；已有内容保持，初始交付沿现loadedProviders/索引回调，不以固定延迟掩盖。后台确认不可用时沿原能力/提示更新，不向播放路径授予缓存许可。
- Steam当前没有完整安装记录快照：由原installed-library owner持久/恢复成功的本地records作为可重建展示基线，限定当前library root；不存登录、临时任务或另建Catalog缓存。原single-flight scan/generation继续对账，扫描失败保留旧基线并显式失败，不能把读取失败当成功空库。warm展示不提前宣告完整扫描成功或触发自动恢复；其他已有本地索引继续复用原owner。

**缩略图方案。** 复用原ThumbnailCache、严格LRU与磁盘派生图，不另建全库位图副本、轮询或第二缓存owner。

- 卡片先取同一资源已解码图显示，异步请求仍只有原一次最终回调；Video路径存在性/修复留在原后台，不让暖像素等待排队。资源换绑/显式clear/取消迟到仍撤销原请求，复用不能显示上一资源。派生文件删除的最终验证语义保留；不能以暖图绕过真实播放检查。
- 同一图片仅元数据改变时保持已显示像素；只按真实资源身份改变清图，不以旧image覆盖新资源。
- 先用生产缓存与真实Grid/Adapter的双向滚动证明驻留命中、LRU/压力淘汰和磁盘返回的区别。若主要缺口是前方覆盖，只在原viewport demand里扩大有界预取，保可见优先和取消；若主要是容量，再以实际字节/回访窗口裁决预算，不盲扩内存、不降低画质，不提前承诺整个图库常驻。

**验收与退出。** 优先扩现有Catalog/索引、SIL原生demand、Video prefetch和CellAdapter门。冻结后台file probe时首份内容应已有真实卡片，后台释放后正确处理新增、删除、移位与过期结果，保SQLite/journal失败恢复及重置。预热→滚出原生池复用→反向返回，检查当次可见已有正确像素，而非只pump最终非nil；超出驻留或显式clear后检查磁盘补图、源重抽次数及迟到串台。使用原30ms viewport调度，不以测试立即fire代替快速滚动。Swift修改后签名Debug和隔离代表App运行，保点击/播放/自建列表/排序/选择锚点；未跑完整人工路径不得报已验收。替换的首发等待/重复派生校验或缓存链同批退出，不追加兼容owner。当前没有真实用户库现场计数或FPS/能耗结论。


**R62实施裁决（2026-11-02）。** Video/SIL使用已有模型当次发布，再异步检查；元数据字段仍可首发，后台回执按原revision批准，未验证事实不进入checked复用基线。Query仅在UI投影省略“来源未就绪且尚无行”的成员，已有行立即显示；默认解析、播放队列和关系存储保持完整，避免待载成员永久丢失。SIL缺失对账在utility检查、main按原load generation及原始ID/path提交，不删除用户媒体。

Steam在原cacheDirectory保存可重建的ready本地records，恢复时标记展示来源、保loaded=false；纯字段首投影不跑Web/Scene校验。ready暖行仅inspect，真实删除、依赖和属性动作在原source就绪后恢复；单项启动重放仍走原定向元数据读取，替换该条暖记录后供后续消费者复用。扫描失败保旧基线；成功空扫才清空。可选快照后台暂存、原generation批准后原子替换，写失败只报告，不撤销已发布内容；删除/发布仍沿原事务和代次撤权。

视频卡片在configure当次读取已有thumbnailPath的已解码图，随后仍走原一次后台验证/最终回调，派生文件删除仍能清图；历史thumbnailPath缺省时保原异步路径。同一图片ID/path的标题、分类等元数据更新保留当前像素，换资源/复用仍清图。

SIL生产LRU保持180张，字节上限64→192 MiB，按实际访问填充、压力回收保持；最大驻留预算增加128 MiB。本地邻居预算保两行下限、按两倍可见项数扩展且至多96，中段通常前后各一屏，remote browse保原两行/24；增加有界解码工作，Steam本地记录的远程预览fallback也可能增加有界请求，不能声称所有网络工作完全相同。不提前预载整库、不降低缩略图画质，不保证无限图库全驻留。

详情原显示状态增加完成标记这一实际输入，避免同一ready记录扫描完成后属性按钮被去重缓存一直禁用；真实通知反例先红、两行修复后通过，不新建刷新链。

**当前验证边界。** 真实Catalog/索引、UI混合查询与完整播放队列、Video暖配置及派生删除、Grid local/remote预取边界已通过最近门。SIL真实生产缓存160张图片、0→40→80→120→0原生视口调度中，回访20张保持同一已解码图、当次无placeholder、源ImageIO增量0；受控取消/冷载/淘汰62项和原生重排17项通过。这只证明该有界输入与回访窗口，未测真实大图库、连续触控板FPS或能耗。

已知未通过的原生门保留：Video完整hover门在旧/候选均于新增暖段之前超时；Picker报告App未激活、sheet未成为key；SIL拖拽首native-turn未被采样，其mounted/图像/alpha事实正常。没有修改产品焦点/拖拽或放宽断言，不将这些门计作通过。实际用户库启动、双向快速滑动、点击/双击/播放、自建列表与增删重排仍待测试App人工确认。

Steam暖Catalog 111项通过，包括7项新增无冷入口、账号/任务能力和fresh不复用未检事实；实际元数据单项重放6项通过：未全扫时原定向读取/解码各1次，后继3次解析复用该行，原位顺序及tombstone/坏metadata拒绝保持；仅临时字节视频，不冒称AV播放或完整Restoration owner运行，不把recording stub当文件读取证明。原播放恢复和typed dispatch两方法、发布/删除/状态栏七方法通过，包含启动未扫拒绝删除、原缓存失效、原取消/迟到结果和opaque ID；详情单方法先只“完成后恢复属性”红，补原输入后全绿。最终签名Debug29.017秒，5866构建输入稳定且strict/deep通过，增量构建无警告；首构建仅原AppIntents、CS8603和CS0665提示。本轮不改Scene引擎。
