# 本地资源先呈现与缩略图回访

<!-- document-role: active-plan -->

<a id="overview"></a>
复核日期：2026-11-03。负责人：repository-maintainer。入口：[主界面专项](main-window-playlists-redesign.md#73-页面命令和快照)。

2026-11-02用户目标：打开App先显示上次本地内容，目录检查在后台更新；本地视频、图片和自建列表快速双向滚动时，已取得缩略图优先复用。该卡同时覆盖列表内已入库Steam/Pixabay/在线图片的本地记录，在线浏览预算和播放引擎保持。状态：R62实现、最近行为门和签名Debug已完成，保留文末三项原生验证限制；真实用户库人工体验待验。R61普通精简候选后移。

<a id="adaptive-grid-size"></a>
## R112：按实际卡片像素保留单一清晰缩略图（已实现/未提交，体验目标未验收）

后续全模块目标已由[统一交付设计](thumbnail-delivery-design.md#overview)接管：按来源复用、兼容清晰结果共享、必要构图按需缓存，替代本节互斥单Entry作为最终目标。本页保留R112实现与原证据；本地与在线共享需求/准备接入及剩余跨模块范围见该统一设计，不代表全模块已统一。

本批Git边界：用户已允许继续实施与验证，但明确要求最终暂不提交，待其检查具体结果后确认；旧循环提交授权不适用于本批。方案须同时报告优点、成本及反例，不把用户建议当无需评估的技术结论。

2026-11-03用户明确否决双层缩略图与低清→高清渐进替换，要求按屏幕、分辨率和行列/卡片大小控制像素占用，同预算保留更多可用图。R111候选未合入、未提交、未构建完整Debug，隔离Source的产品/测试候选已逐文件恢复到R110提交；下述诊断仍有效，候选改善不作为已交付能力。

**R112修改前的断点。** 原SIL固定512最长边，180count常先于192MiB触发淘汰；Video派生图固定400×400上限，大Retina方卡的短边可能不足。网格是正方形aspect-fill，150pt@2x需300×300可见像素，不能把ImageIO最长边设为300后仍保证清晰。当时memory、inflight及磁盘均仅按path，SIL Inspector还共用该键写800；只给source loader加size会被旧盘图/内存命中绕过。首次make可能尚无正确cell frame，reloadData还可能早于layout更新，目标须取当前Grid布局意图并转换backing像素。

**实测结论。** 相同1024张自有图片、800×600/5列、2x、52pt工具栏及18次六页下/上真实窗口输入，两臂clip路线逐项一致。150pt需300px，当前归320：单Entry实际733184→409600字节（约−44%），LRU180→491张；配置192MiB不变，但原count先淘汰只用约126MiB，新版可用满约192MiB，因此总驻留内存可能增加，不等于RSS降低。精确输入期间405次willDisplay即时无图405→289，反向回访190→91；磁盘decode开始1738→652、源ImageIO重抽均0、无trace截断。235个manual-visible项未达原360覆盖门，仍为false；对象回调不是屏幕/FPS证据，真实混合库和触控板未验。尺寸节省有效但未消除空卡，不认领照片级。

**最近验证。** 缓存69/Decoder41/lease63事实通过；真实AV20事实、原生成/clear/卡片交付及邻接Inspector、Pixabay、SIL需求/离屏重授予、GridViewport/Adapter、调度门通过。首次SIL不受控持卡反例曾失败，产品未据此修改；保原10断言改用原controller+idle factory固定未复用前提并新增grant前身份/旧像素检查后通过，不能称原失败因果已证。旋转夹具改官方输入display_rotation才取得真实90°track，未据坏夹具修产品。最终Debug29.731秒/5923输入稳定、strict/deep签名过；首次全编译的本批8条async隔离警告已通过原queue续流修正并重编消除，另有未改Scene及CS0665/CS8603警告，最终增量仅AppIntents无依赖metadata skip。review App保留隔离位置，未安装/启动真实用户库。

**改动规模。** 产品18个既有文件净增220行，测试24文件净增560行：尺寸必须贯穿Grid/原Adapter/三处UI消费者、原provider/缓存/视频生成，增加目标标签与类型化回执但不新建owner、尺寸索引或缓存层；当前最大产品文件998行。测试复用原实现与真实ImageIO/AV/窗口，装配清单随真实依赖更新，不复制业务计算。

**后续裁决。** 缩尺寸与保更多图不能单独保证无空卡；优先查剩余非驻留图的提前解码/交付和旧Video master首次质量升级。Video400→320需要新增AV，合成单任务约6–24ms，仅说明额外工作存在。复用既有lane的质量预取只研究未实施：Core remove丢handlers，盲加continuation可缺终态；不加第二协调器或96个AV。64px分档减少连续resize的重解码，但300→320多约14%像素；更细分档与频繁resize成本待实测再选，不宣称任何布局均省。

**已选数据流与职责。** 原Grid从当前clip宽/列数的Metrics得点尺寸，经collection.convertToBacking取backing像素，向上归64px档（上限4096），同一整数随CellState和viewport传原Adapter/provider；显示准入使用CellState?（nil撤销），离屏保留卡重授予时只有目标变化才用已绑定来源重配，不再查全源表；原生挂载、resize、列数和backing变化重发原有有界需求，无轮询/全库遍历。ImageIO重用orientation/aspect-fill计算，后台绘制独立连续的中心方形位图，避免仅cropping仍持整张底图。小原图允许其真实上限，不把上采样叫新增细节。

**原缓存内的单图语义。** ThumbnailCache.load/cachedImage增加可选pixelSide，默认nil保原uncropped消费；DecodedThumbnailMemoryCache每源唯一Entry记录已完成的square目标（原生小源允许其真实上限），仅同构图且目标像素足够时命中，已有更大清晰方图可直接复用，避免为缩小强制重解码/可观察替换；新冷项用当前尺寸，旧大项到LRU退出前暂留较高占用。这比另建exact/min两套读API简单；不保尺寸集合或preview tier。在途image key为(source,pixelSide)，同尺寸单飞、不同尺寸不错误合并；完成仅替换同源Entry。默认Inspector/状态栏/Artwork消费者继续原未裁图语义，不给其增加缓存或迁出既有owner；与网格可能互换唯一Entry并额外后台解码，这是换取无variants状态的明确成本。remove/clear覆盖同源全部target请求/唯一Entry；内存压力仍原释放语义，不加新代次、latest-target表或时钟。

**磁盘与源质量。** 每源仍一份uncropped JPEG，暖盘按目标下采样并绘制方图；不足覆盖则走原source一次，生成时持久化原未裁图、只将目标方图入内存/最终交付。SIL源master至少保原512最长边，Video至少保原400（原生不足例外），防止小网格写小盘图后默认详情消费者变糊；仅内存按当前卡片裁小。暖盘缩小不把较大盘图改写成小盘图，不增加尺寸文件族；并发不同尺寸都先盘miss时，原单generation队列后完成的小图仍可能替换较大盘图，后继大需求可额外回源，但不得误满足。接受此有限重算成本，不加latest-target目录或每次generation重复盘读。Video沿原canonical派生生成owner按需取得足够短边，保默认400路径的现有使用；旧小派生图与在途400结果不能被大目标当最终清晰结果。必要的大小比较只放原读取/生成边界，不在普通暖内存路径stat。缓存不是源许可，真实小源/失败不得自递归生成。

**公开依据与取舍。** Apple公开PHCachingImageManager要求预热与请求的targetSize/contentMode/options一致，已准备项立即返回；它支持按需求后台预备，不能证明Photos内部会整库解码常驻。本批沿此原则统一尺寸与需求，在原cache内保单图；拒绝全库常驻和可观察低清→高清双层交付。参考：[Apple预热接口](https://developer.apple.com/documentation/photos/phcachingimagemanager/startcachingimages%28for%3Atargetsize%3Acontentmode%3Aoptions%3A%29)。

**预算/取舍。** SIL192MiB/Video128MiB总已解码字节保持，将两者count提高到4096有界元数据上限，让实际bytesPerRow×height主导。150pt@2x归320px方图紧致RGBA约400KiB，192MiB理论约491张（不含行对齐、色深、对象、在途或卡片持有，非RSS/实测）；大卡可能更贵，不能承诺任何布局都减少占用。选择直接生成当前清晰方图，替代未裁缩图仍缓存将被裁掉像素；拒绝全局改尺寸清全库、永久尺寸索引与多阶段低清回调。现有图在重布局/正确请求完成前按原View生命周期持有，不清空或闪loading；新最终图必须满足其目标或真实源上限。Scene不改。

**验证。** 用当前指标尺寸×1x/2x、列数/窗口/换屏、方/竖/全景/方向信息，以及先小后大/先大后小、旧盘暖、迟到结果、清理/单键失效检查像素充足、缓存成本和单次正确交付。复用已确认合法窗口输入；真实视频/图片/自建混合及帧节奏继续验，不以对象有图替代Photos级体验。设计已在实施前落库；各片段须通过真实门后才合入。

<a id="progressive-return"></a>
## R111：真实回滚诊断与已撤回候选

原正常App生命周期、合法窗口输入、原Grid/Adapter/SIL/cache/native52pt工具栏，1024张自有盘暖图片/180count192MiB：25单页下再25单页上实际445项可见，预取领先可见插入最小18.54ms，已创建可见卡均同步有图；淘汰均count而非bytes/压力。9次六页下再9次六页上复现190项先赋图→真实淘汰→反向可见无图→同绑定重新赋图，最长30.499ms；18真实窗口输入、405次willDisplay均身份/可见相交成立，无源重抽/截断。此路线仅235 manual-visible项，未达探针360覆盖门，具体因果可成立但不称完整超驻留门通过。AX读取另导致Time Profiler152个make栈中150来自AX，不能归作自然滚动成本。

私有双层96px候选曾在相同18次位移观察到405次可见对象无图→0、后继清晰交付405次，但用户明确要求不可观察渐进，方案整体撤回，不合入其双层预览产品/测试或宣称已交付；原SIL selection精简候选亦未合。屏幕像素、物理触控板/FPS、真实混合和完整照片级均未由本实验证明。后续只按[R112](#adaptive-grid-size)推进，不重做R55/R62/R109已结事项，Scene不改。

<a id="generated-delivery"></a>
## R110：可见视频请求直接等待派生图生成

2026-11-03完成原可见请求的生成→解码→卡片交付；**真实用户库与完整照片级滚动仍未验收**。真实A/B视频、原批导入/generator/Provider/cache/card方法复现：A首次请求在原AV挂起时返回最终nil；A随后ready/JPEG可解码、B仍挂起、原batch尚未进静帧时，旧卡经原repair仍无图，新卡读取同A有正确红像素。ready事件无统一网格消费者，repair见JPEG存在也不再生成；旧请求已结束。早期repair另外安排的静帧可能间接重配，不称必定永久黑卡。

**数据流与最小替换。** 原可见请求→原ensurePreviewAssets的源存在/冷却/inflight策略及可选completion→原generateThumbnail→同cache解码→原卡片token/requestID批准。已有JPEG保原resolver/validation/暖缓存；prefetch miss仍直接nil。仅cold visible miss在原decodeQueue确认源存在、撤销自身canonical派生key的旧memory/disk再handoff，批准输出path直接进入load，不二次stat/normalize或递归请求。缺源仍本卡文案，不因新ensure入口增加全局missing提示。最终nil后的Card ensure调用退出，避免clear/失败后从UI自行重生；已有独立可见修复与静帧策略保留。

产品32增13删净+19行，无新owner/state/cache/observer/timer/model写入、Core→UI或shared-cache API更改。额外成本限冷visible miss的一次源检查、canonical键和精确缓存失效；同时miss可能重复失效，不添第二单飞表。取消抑制后续交付，不物理中止共享AV；cache.remove沿原语义仅撤回填权，不取消全部旧在途消费者。clear释放本请求后不递归重生，不代表以后独立2秒repair永不生成。可见ensure可新增一次原static调度，不能把原batch静帧尚未进入写成新版无静帧工作。

**最近门。** 同最终Swift夹具44控制/16行为事实：旧44控制全真，仅A直接交付2项与memory/disk新蓝像素4项红；候选全真。真实红→蓝MOV重生后，首次交付和后继cache命中均为新蓝，模型未写；prefetch/missing无ensure与AV、missing无全局report，冷却0AV、取消无迟到、clear一次nil且旧生成不落新JPEG/不从Card再启动保持。原validation21、nil路径21控制及3像素/同turn观察均通过；repair16在补真实normalizer装配后单独通过。6308输入与实际编译输入稳定。测试净+369行：复用原生成/路径/缓存owner，新261行真实场景与原Python装配/方法，不复制业务算法；三个旧控制Manager只适配completion/pathExists。

首次联合门因repair fixture缺normalizedPath编译失败，原样保留；只在该方法装配提取真实normalizer后补跑。最终Python仅此处较已绿版变化，其余helpers/生成门和另6原方法字节保，已绿3方法按实际编译输入复用；不冒称最终脚本重跑全模块。生成切片有原nonisolated Manager装配的6条actor诊断，不等于产品新警告。签名Debug26.657秒/5868输入稳定，strict/deep通过，仅原CS0665/CS8603；测试后来加入，最终3产品字节与App相同。未重跑已知完整hover原生限制；静帧/model/metadata/report为记录叶，不证明完整Catalog/DB/window或Leaks/TSan。

**滚动调查与下一步。** 原R108/R109直接clip位移没有经过scrollWheel。新增固定8ms/238包尝试虽解码phase/momentum，实际event.window=0、clip无位移，全部排除滚动性能证据；第二版正常5126pt文档/600pt clip仍不能形成窗口输入。实际Scroll/Clip/Collection三个类兼容值均true，只满足[Apple的必要条件](https://developer.apple.com/documentation/appkit/nsview/iscompatiblewithresponsivescrolling)，不证明响应式滚动全链已运行。后续直接NSWindow.sendEvent方案因[官方明确禁止直接调用](https://developer.apple.com/documentation/appkit/nswindow/sendevent%28_%3A%29)撤回，未执行，不堆模拟层或私有字段。

下一优先换成隔离窗口的合法原生输入/代表App采样，拆make来源查找/原生创建/绑定配置，不先删参与动画准入的needs检查或沿用旧source map。SIL selection的异步重复几何是后续候选，须量测和即时/布局/复用反例后裁决。真实视频/图片/自建混合、超驻留、硬件滚动/窗口像素/FPS/能耗及拖拽仍待，R55/R62/R109已结修复不重做，Scene不触。

<a id="toolbar-underlay"></a>
## R109：工具栏透过区域也持续取得图片

2026-11-03完成三处图片需求矩形替换；**工具栏断点已复现并验证，真实用户库和完整照片级目标仍待验收**。用户R107 Debug在所有列表反馈回滑迟刷。旧R108字节的真实Grid/Adapter/SIL/native fullSize+unified toolbar夹具，未手设inset，系统自动top=52pt；target32在sample23已创建、仅落toolbar band，需求false/image nil，120ms停留后sample37仍无图；sample50进入safe区，sample55才需求true/有图。不将此断点称为所有卡顿的唯一原因。

**根因与裁决。** 原gridViewportRect为anchor/pointer扣除contentInsets，gridVisibleRect继承此交互区；willDisplay、publishViewport与目录cover demand错误共用它，排除透明toolbar下仍绘制的卡。Apple的[自动inset合同](https://developer.apple.com/documentation/appkit/nsscrollview/automaticallyadjustscontentinsets)及SDK NSScrollView.h说明contentView仍铺在toolbar之下；原生观察确认collection.visibleRect覆盖完整clip。只将Grid两处缩略图需求和目录cover demand改为collection.visibleRect；gridVisibleRect/gridViewportRect继续供AX激活、hover/menu/pointer、anchor/restore与pull count。产品3增3删净0，无新helper/state/clock/cache；30ms、资源身份、撤销、窗口可见租约和原预算保持。透过区增加有限图片/动画及原provider可见检查工作，不只JPEG解码；不改源可用性反馈、播放许可或Scene。

**原生前后证据。** 两臂31份编译Swift仅Grid两处目标表达式不同，观察body和运行夹具逐字相同。同144次视口采样/3380次卡对象观察，旧sample37仍无图，新在safe区外已需求/有图；已创建但无图对象观察160→0，立即尚未实例化25次两臂相同，不能称所有空卡清零。盘派生解码均59、源重抽增量均0。各76帧own-window SCK，hold附近同一PNG可见新版玻璃下卡片色块；occlusionVisible两臂false，属于自身窗口合成内容证据，不是物理前台scanout/FPS。生成器首新臂在编译前因匹配旧表达式失败，仅匹配锚点修正后续跑，保留原runner/失败记录；没有改轨迹或观察算法。

**回归与边界。** 最终Grid夹具36项：旧仅新增两项图片需求红，候选全真，原30项和AX安全区/隐藏撤销保持。目录聚焦模式31项：旧仅新增cover需求红，候选全真，原toolbar/锚点/键盘组原样抽取并被完整模式与聚焦模式复用，cleanup生命周期保留。产品净0，测试净+115行（Grid +67、目录+40、Python +8），不复制产品算法。输入/实际编译输入均稳定。早期Grid装配私有成员编译失败及复用旧窗口造成的无效几何负例保留，不计行为红。

抽取前完整目录夹具两次40秒超时，未到工具栏段；最终抽取后只运行聚焦门，未重跑完整门。重试1秒主线程采样626/626在CoreDrag等待mouseUp。没有删原拖拽测试、补伪mouseUp或改产品焦点；完整目录交互仍未通过，单独聚焦门不能替代它。签名Debug 28.545秒/5868构建输入稳定，strict/deep通过，无新增Swift警告，仅原CS0665/CS8603。最终测试抽取在构建后完成，三行产品字节与已构建App相同。

**下一验收。** 交付冻结Debug后核真实所有列表工具栏回滑、触控板连续滚动与拖拽。最小host非完整Main split，160张图片非混合/超驻留用户库；照片级目标、帧率/能耗和R106残余仍未证明。视频生成交付见[R110](#generated-delivery)，之后优先量测cell同步刷新成本，不沿用过期viewport map，不追加刷新链；R62/R55已结问题不重做。

<a id="viewport-lookup"></a>
## R108：一次视口内批量读取来源

2026-11-03完成原Adapter内批量来源准备；**完整照片级目标未验收，后续工具栏断点见[R109](#toolbar-underlay)**。旧updateViewport对每个目标分别调用数组first，在发首provider前就做完全部搜索；10k尾116项有1,153,330次UTF8 predicate调用。原Adapter字节未变，沿用R107旧量测，不重跑旧计时。

**数据流与取舍。** 现有wanted前移复用→本次resolveSources→四类来源共用局部collect，惰性读取所需数组，命中全部请求即停→原provider/lease链。复用WallpaperReference的provider+原始UTF8身份；命中从pending移除保来源重复first，只保存本批所需结果，missing沿原缺省，不预填再覆写。Pixabay以Int行的String匹配保canonical身份，online仍原record(for:)字典API。无持久索引、订阅、模型发布或新owner；下一viewport重新读取当前数组。原单条cell查询、排序/重复请求、资源revision、可见优先、取消和decoded预算保持。

产品27增10删净+17行，新增23行私有批处理/4次真实复用，替换原逐reference resolver closure。集合/哈希仍有固定成本；有该provider但全为非法Pixabay引用时，新版会一次扫表，旧版可在解析处零读取，不称每种输入都更快。未选各来源常驻索引/全库临时index及跨turn旧map，避免同步状态、O(N)副本与过期换卡；改语言/组件不能替代这段重复工作。

**最近门与成本。** 同最终Adapter夹具92项，旧仅3个新增读取预算红，其余89项含原76全部真；候选92全真，6307输入/2实际子过程稳定。四provider多目标、opaque/Unicode、Pixabay数值反例、重复first、missing、跨次替换/撤销和无请求零读取保持；测试97增2删净+95行，仅记录实际收到的path/URL/title及小矩阵，不复制查找算法。micro计数68/未插桩29检查通过，19/51业务case剔除工作/计时字段后逐项严格相等。原逐ref predicate调用与新scan rowVisits分列，不能作同单位减法；新head116行即停、tail/missing10000行、small160行。

未插桩-O、各5轮中位毫秒（只计进入首provider前，受控来源数组/真实模型，非整App FPS）：

| 来源/输入 | 旧 | 新 |
|---|---:|---:|
| Video 10k头116 | 0.627 | 0.426 |
| Video 10k尾116 / missing116 | 64.929 / 56.456 | 3.922 / 3.399 |
| SIL 10k头116 | 0.530 | 0.403 |
| SIL 10k尾116 / missing116 | 49.484 / 43.080 | 3.914 / 3.505 |
| Video / SIL 160尾116 | 0.917 / 0.784 | 0.417 / 0.426 |

私有计数夹具首次沿用旧matches断言、Root中间又误用累计getter，均保误红；最后按本次真实getter差值观测，产品/永久门未改，不把两类操作混为一种。

**原生证据。** 同一无-O真实Grid/Adapter/SIL/cache/卡片与own-window SCK，10k来源元数据+过滤后160项真实独色文件；不是10k全网格或真实用户库。两臂连续阶段均90次viewport/540次make、100次派生解码、1364次provider-start、源重抽0。首真实SIL请求66次中位107.928→7.156ms（最大149.753→9.802）；viewport总10.446→0.698秒，make总1.050→1.057秒未改善。相同输入轨迹实际用时13.930→4.188秒，捕获713/238帧仅因时长不同，不能算FPS。连续阶段两臂20点均未采背景；旧首帧一次缺图位于continuous之前，新未采到，不称连续黑卡已修。点采样/有限PNG不覆盖全像素、物理scanout、触控板、混合列表、超驻留、选择动画或能耗。外层native allowance在首跑前两臂同调60→180秒，轨迹/编译/断言不改；实际均完整终止，输入稳定。

签名Debug 27.838秒/5868输入稳定，strict/deep通过，无新增Swift警告，仅原CS0665/CS8603。

**后续定位。** 下面用户反馈已由[R109](#toolbar-underlay)的真实fullSizeContentView+native toolbar验证共享需求裁剪，保交互/锚点safe area。cell本次make成本未动，needs/update在连续段未调用，不外推选择/动画；必要时另测同步刷新批次，禁止沿用旧viewport map。新生成Ready刷新窗口与混合/超驻留仍待，R62/R55已结问题不重做；Scene不改。

**新增用户实测（2026-11-03，R107 Debug）。** 所有列表仍有肉眼可见的滚动不顺畅；回滑时半透明工具栏下的卡片似乎要越过安全区才突刷。未测FPS，不将其写成已定位的掉帧原因。本批大源表probe没有真实主窗口toolbar，不覆盖这条反馈。后续R109已复现并修正共用需求裁剪，见[当前裁决](#toolbar-underlay)；真实用户库体感和全部卡顿仍待验收。

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
