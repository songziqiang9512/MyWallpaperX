# 全仓校验与链路精简

<!-- document-role: active-plan -->

目标：按用户要求先审完 Scene、Web 两引擎，再扩到全仓，清退过度严格、重复、拖慢响应且无实际产品作用的校验、认证和附带结构。用户需要直接、轻量、按需执行的代码；历史合同、测试或“更严谨”的说法不能替代真实用途与成本证据。本轮从主仓 `codex/engine-refactor-program` 的 `8f71545d` 继续实施 P10–P22；用户于 2026-10-26 要求暂停 Goal、先收口合入该分支。长期审查现已暂停；另外两个会话由用户安排合并，收到整合完成通知后，先同步最新主分支 HEAD 再恢复余项。已知重大产品故障优先处理，局部小问题与未覆盖验证明确留在本页。

## 审查方法与完成条件

沿当前实际调用链逐段审查。对每项检查记录其生产者/消费者、执行阶段与频度、直接避免的产品错误、重复读取/计算/等待以及失败范围。无消费者的状态和缓存删除；可选派生缓存损坏或失效回原链重建；下载完整性留在下载/发布事务；普通本地播放不重新证明整个历史目录。保留实际防止解析越界、播错内容、非法访问、异步串台和错误释放的检查，在实际消费处执行，避免层层重验。

完成须同时满足：下表范围均有当前源码审查记录；有依据的发现均已处理或经实验明确撤回无效候选；对应行为回归与必要构建/代表运行完成；修正后独立复审没有发现尚未处理的新同类问题。只报已核实范围和实际前后数据，不能以构建或少数成功样本宣布全仓无问题。发现新问题就继续处理，覆盖表不以文件数或测试数代替。

## 顺序与覆盖

| 顺序 | 范围 | 当前状态 |
|---|---|---|
| 0 | 正式 Release 旧 Scene 误拒播；Scene 来源/读取/纹理身份；Web 重复扫描/缓存 | 历史摘要播放许可及旧迁移已退役；最近来源/缓存门与 P1 两份真实 Scene 已过。P21 优化 Debug 验过当时 P10–P20 的 5 份作者 Scene、2 份 Web 与 Video 跨链首呈现/提交；P22 当前普通 Debug 及最近原生门通过，未重跑完整 App；旧 P12 Release 不含 P13–P22，当前 Release 与完整视觉仍待验 |
| 1 | Scene：资源/解码/模型/字体/媒体/纹理准备及复用 | P3/P5 的 MDL、按引用目录、粒子单次准备、纹理 snapshot、Raw/BC 上传、视频私有文件及字体最近门已过；声音完成后真实 FD 边界已过；P19 材料查找减工已过，P20 部件数/路径政策已退役，CPU/实际材料/GPU及前后对照已过；P21 文字/粒子/Puppet 作者样本首呈现已过；初始同屏全部字体上传、字体内存及逐层视觉仍待验 |
| 2 | Scene：shader/Program/graph、特效、Metal encode、普通帧、输出与生命周期 | 准备/编译/VM/拓扑、粒子及模型减工的逐批最近门与必要对照已过，P20/P21 构建与 App 代表首呈现覆盖当时产品；P22 当前普通 Debug 通过，Puppet clipping 可见门、旧桥接夹具和完整代表视觉仍待验 |
| 3 | Web：项目/属性/资源权限、宿主/JS桥、媒体/特效/逐帧、进程/可见提交 | P1 有构建及两份产品入口；P3/P5 的目录/hosts/datastore、单 FD、取消、timer、CSS/媒体减工和 Release JS 剥离最近门已过；P6 卡片/方向导航及 P7 作者 memo 暖复用 CPU 门、P7-v6 合并构建已过；P21 完整合并 App 两份真实 Web 的产品提交已过；实际首屏画面、音频完整性仍待验 |
| 4 | 全仓：Video、公共播放/音频/系统策略、图库/下载、存储/索引、UI/工具链 | 父生命周期/单次读取/旧迁移等已有最近门；P16–P19 完成音频诊断/完整窗减工、Video 按需首建/重复发布退役、两路缩略图键复用与旧库发现短路，含实际音频值与 AV/JPEG 前后对照。P22 宿主行投影与 Video 同次工作/无用路径回显校验已精简，完整字段、AV/JPEG、最近原生门与当前 Debug 通过；SIL 原生负缓存及全仓余项随 Goal 暂停 |
| 5 | 集成：删除死 owner/API/测试、同步现役合同、必要前后对照与独立复审 | 持续进行 |

## 已证问题与裁决

| 发现 | 当前裁决 |
|---|---|
| 旧 Scene 播放等待全目录复制、摘要重算和 receipt 升级 | 退役该前置迁移 owner；捕获当前版本与 lease 后直接准备 |
| 无 receipt 每次启动核历史整目录摘要；附加截图/shader 缓存等也拒播 | 删除历史摘要播放许可；真实抽查两份的原 project/pkg/preview 摘要与入库值一致，后增无关文件造成误拒 |
| loose 纹理查缓存时全文读取/哈希，准备与主线程采用再次重验 | 当前文件 revision 作缓存身份；按需读取；已准备 GPU 资源按原请求/device采用 |
| Scene IPC 携带历史 contentDigest/receipt，仅供自身格式校验而无播放消费者 | 清退两个闲置 wire 字段；保当前 generation/storageIdentity 与父端 lease，旧 marker 的 receipt 只解码兼容，未知旧 wire 提示不影响实际来源 |
| 包为临时 receipt 整包及全部 entry 哈希；消费 entry 再哈希 | 同 FD 有界解析索引一次并按需读 range，保留实际修改/截断/范围检查 |
| Web execution payload 清单读取/计算/保存后不被返回值使用 | 删除无消费者缓存；当前属性与授权每次按需组装 |
| Web 暖命中先全文 hash/完整摘要、重复 HTML 再发现、全库预加载 | 用既有实际依赖 revision 失效 analysis 缓存，退役重复发现、预加载及其共享 flight |
| 可选依赖变化升级整次拒播，重复 lease/marker 检查 | 派生缓存失效后正常解析，保留实际作者版本的一份 lease |
| Scene 不变 effect subject、graph lookup/排序/ordinal/计划与 uniform 布局在普通帧重复核验 | 不变事实随原 capability/target plan 准备一次，帧只检查动态资源和真实 hazard |
| graph/node/mapping 诊断容量 512/1024 反向限制真实 effect 与提交 | 删除产品拒绝门；实际纹理/内存预算归原 owner，Debug 观测超容量只不记录 |
| Release 中纯日志媒体 listener/重复 observer；空 RAF/timeout；零 caller merge | 编译剥离或直接删除，无替代状态和缓存 |
| 每屏 DCL/didFinish 重做全部资源授权与目录扫描；用户属性更新又推不变 general 属性 | 请求/资源 revision 同步一次，ready/新 endpoint 重放现值；通用属性仅在自身值变化时推送 |
| 自动交互区域两份 signature 字段/精度不一致 | 统一使用实际 8 字段，未变不重扫/登记；子 frame 不做无用顶层扫描 |
| Web pipe 后台 decode 后，主线程再 decode 同份命令 | 原 mailbox 传同次 typed 值，按原始字节数限额，保留身份/版本/控制屏障 |

现役语义归 [Scene 启动合同](../scene/architecture/scene-launch-responsiveness-contract.md) 与 [Web 准备设计](../web/cold-descriptor-parse-offload-design.md)。旧专项的 D37/D40 验收是历史输入/版本证据，不覆盖这次正式试用发现的回归和后继代码。

## 已实施：不可变准备事实与实际动态检查分离

Scene 的 effect subject 守恒、静态 graph 查找/排序/command ordinal、无 history 图的编译操作和 layer target 聚合计划，归原 capability/admission/计划 memo 的不可变准备结果；普通帧消费这些事实，继续核对真实 publication、texture、reset/device/epoch 和读写 hazard，不另建缓存 owner，不为保存静态表而延长 texture/pin/history 寿命。uniform 在唯一、私有的 Program 工厂完成必要布局、来源、finite 与范围检查，encoder 不再重复遍历同一不可变 bytes。Release 编译剥离只服务统计的锁、Set 与 getter，真实 PSO 正负缓存继续使用。

资源侧优先删已证无用的路径子串拦截、同次 TEX header 重验及未选 shader 根的全文读取；选中资源、当前 include 和相对/根解释的真实歧义保持原语义。同次构图沿原 builder 复用已读取 source，不引入长期免失效缓存。字体、模型与每屏初始文字的重复准备继续审查，按原资源 owner 收敛；没有当前行为与成本证据时不以额外 wrapper/缓存掩盖问题。

对应反例：错误 effect/ordinal 在准备时仍拒绝；resize/reset/压力不复用旧物理分配；异步旧结果与 texture 读写冲突不能提交；NaN/越界 uniform 不能进 GPU；未选 shader 内容变化不使当前 Program 失效，选中 include 变化仍失效，真实 include 歧义不改 first-wins。

Puppet direct skinning 的 bind vertices 来自原 Reader 的不可变模型，普通帧不再逐顶点重验已接受的 position/normal/tangent/UV；当前骨骼/skin matrix、可逆性、输出范围与最终变形结果仍在使用处检查。localStorage quota 计算沿原 Session 单次累计 scope/总字节，不再摊平并反复遍历整份 envelope；已接受旧值的长度不重复检查，新 set 和首次读盘仍走原值边界，不增加额度缓存或第二份状态。

Scene 属性增量直接复用原值投影，不再逐 key 编码 JSON、解析回对象后再整包编码。QuickJS authored layer 配置沿原 Domain 记录已完成数量，只在全部槽配置后检查一次完整目录；原每槽数据/重复配置边界与最终重复 ID、parent 检查保留，不反复扫描所有槽来判断是否准备完毕。粒子音频的执行观测、诊断去重/帧快照和仅报表集合只编入 Debug；Release 直接计算原音频响应，不维护无消费者的观测状态。

## 后继候选与实施边界

P3/P5 的动态字体、hosts/datastore/目录、MDL、AssetCatalog、Web timer/单 FD/CSS/媒体减工已通过最近门，不能据此视为当前合并 App 已验收。初始同屏多层文字沿原 load 已有 raster 的 sourceFont 复用，不新增字体缓存；失败未产生 raster 时后层仍独立解析。跨屏首次准备和 TEX Reader 物理尾层尚未减少：同份解析值被 data/动画等完整消费者使用，不能直接跳过尾层；需先测成本，若有收益再在原数据流内按需物化，不另分 Reader 或长期 owner。

Web listener 优先复用已有方法 hook 与 lease challenge，不加 Proxy/全局 Object 拦截；目录抽样优先消费原 DirectorySnapshot，若携带原目录路径，只在它与当前授权目录相同后使用，不增加第二份长期缓存。MDL 若只准备一次，解析值限本次 launch CPU→GPU 交接，消费后释放，不能变成长驻 RuntimeModel。任何候选撤回须写清成本或行为原因，不因原方案列过就强行接入。

### MDL 一次读取与解析

当前为材质名调用 metadata reader，仍完整扫描所有顶点/索引，GPU 准备再读/扫一遍。改由 SourceFacts 对每个唯一模型读一次 snapshot、调用一次 `readParts`，从该结果直接取得材质 links；只有场景确有动画需求才从同份 bytes 解析 animation/attachments，原始 bytes 随单模型循环释放。`SceneMdlStaticModel.PreparedSource` 只持必要 CPU 解析值，经原 Builder 非逃逸 sink 交给 launch 局部，再由原 DeviceResourcesTask 一次消费并释放；inspection 默认不保留整组。GPU 不重新读取、校验或认证已经完成的 snapshot，材质与几何使用同份结果。无效模型仍局部缺失，不再次尝试另一读链；读取期间的 sourceChanged、无效句柄和取消沿原错误上抛。最近行为门核一次读取/解析、重复实例共享、有效材质/动画输出、坏模型局部化和取消，不新增全局模型缓存。

### 编译准备减工

同次不可变 source/key 的 SHA 已由原创建点取得，缓存读取不再对已与当前 key 相等的副本重新 hash，Preprocessor 不再反复 hash Builder 已捕获的 selected source。完整 artifact 的一次解码/ABI 与 payload 检查仍在原消费点；flight 返回已接受 Program，退出 flight 不再立即打开/认证同一文件。

App 内固定 compiler helpers 沿原 Bundle owner 只解析/严格核签名一次；默认主 bundle 的结果随进程存活，显式测试/工具 bundle 保原独立解析。运行时不再为每个 shader 先启动两个 `--version` 进程：打包工具负责版本身份，实际编译的退出码、超时、输出/ABI 说明该次能否执行。首次 Apple/Team/路径检查不放宽，不加第二个认证 owner 或探测调度器。binary archive 只需要确认候选是可用 regular file，不先创建丢弃的整份 Data 再让 Metal 读取；无产品消费者的统计仅 Debug/testing 保留。各 effect 的静态子图索引在原 admission 一次分组后使用，不反复扫描整图。最近编译/坏缓存/并发/失败反例及真实 shader 输出验证这些变化，未完成前不预报提速。

## 当前验证边界（2026-10-26）

以下 P0/P1/P3 是各固定版本的阶段证据，当前合并状态见文末。P0 最近 19 个模块已通过。P1 选定 CPU/JS、mailbox、资源/图计划/脚本/Release 隔离行为门已通过，优化 Debug 构建、严格签名及构建源快照零漂移已核实。代表 Metal 的 render-target table、offscreen pool、pass encoder、embedded data/image 与 prepared base-image 已通过；图执行/衔接等门的旧夹具补齐后只重跑失败项，不能先算完成。

两份真实用户 Scene 的只读副本（2913492057、3809618616）经现有产品入口完成首次 App、重开 App、同进程重播的实际呈现和父端提交，工具确认用户偏好指纹不变且进程退出。单次优化 Debug 的入口至呈现/提交分别为：291：2222/982/217 ms；380：1642/859/183 ms。同份 291 输入在旧基线未进入呈现；它不是可计算提速比例的成功基线。上述结果只覆盖单次、两份输入、当前版本；首次 App 使用临时 HOME，并未清 OS 缓存，也未完成逐像素或全部效果验证。

固定 P3 源快照的 38 个 CPU/JS 回归模块已全部通过，覆盖 P2 的 MDL、编译准备、粒子诊断、属性投影/QuickJS 配置，P3 的当前字体复用、拓扑准备、来源 wire 清退及 Web 目录/hosts/datastore 等。首轮 33 项通过，余项修正测试接线/旧断言后复验通过；编译请求的 Swift/Python key 一致，旧 color-boundary golden 更新同时保留旧协议反例。各次固定源摘要核对无产品漂移，不把夹具修正当成产品提速。Debug/Release 合并构建、GPU 与代表运行仍须完成。两引擎首轮全链静态查漏已汇总，开始扩散到 Video/共享策略及库/下载；后继改动仍待构建和实际运行，持续 Goal 保持进行中。

本机证据集中于 `/private/tmp/mwx-startup-optimization-fbRhFY/d41-playback-validation/`，索引、各门报告及源文件摘要保留；App 与构建缓存不进入仓库。不以该临时目录作为长期合同权威。

### P3 实现：只复用实际已经准备的值

- 纹理：BC 的 CPU premultipliedColor 路径在解码前选实际要上传的 mip 前缀，不再解码并拒绝未消费的尾层。所用层的块长、尺寸和 Metal 边界保留；straight/data 仍消费全部通道/层。TEX Reader 仍读取/解压全部物理 mip，不能声称这部分已经减少。
- 文字：原 RasterizedTexture 携带当前 sourceFont Resolution，DynamicTextStore 在内容/颜色/宽度变化时复用，同路径字号变化从原 CTFont 派生，路径变化重新解析；保的是排版前源字号，不是上次 raster scale 后的字体。完整 ResourceView 恢复 package→loose 作者字体优先级。每层仅保当前字体、不保历史列表；后继 P6 已复用同屏初始多层 sourceFont，实际上传门及 backing 内存仍待实测，跨屏首次解析尚独立。
- Web：准备结果的 host 集合沿现有 request/IPC 传递，删除 hello 后重新进入 descriptor 的 resolver；属性更新、重建和恢复携带同份请求值。普通 downloads 投影不再展开全库 UUID，确认删除才派生旧记录候选，WebKit 枚举 completion 现读实际 live/usage 保护集合再删除，覆盖迟到恢复与新 surface，保原宽限/重试规则。
- 来源：Scene wire 清退无消费者的 contentDigest/receipt，下载 marker 仍可解码旧字段；当前 source 的 generation/storageIdentity 与父端 lease 没有替换为另一套身份。

以上字体、Web 与来源 DTO 已通过对应 CPU 门；后继 P5 的 BC 实际 GPU 上传已过，字体 backing 内存和当前合并 App 仍待验证，这些不包含在 P1 App 的运行证据中。

两份真实 Web 的 P1 基线/候选单轮均完成 C0/C1/W0 产品提交，用户偏好未变且临时 runtime 已清理。同进程六次重播的单 App 中位数：Colorful Matrix 302→294 ms；Nothing OS Dashboard 698→362 ms。C0 的新进程条件没有清 OS/WebKit 缓存，先后顺序只有一轮，最终稳定提速须补多轮交替对照；工具的 performanceAccepted 为 false。图原生回归的源接线/旧断言漂移已再次修复，仍需实际复验，不能用真实壁纸成功替代。

### P4 设计：资源按实际消费者读取（最近行为门已过）

Web 单次请求的路径定位、实际文件打开、正文/Range/transform 和发送由现有响应流程直接衔接。准备普通 GET 正文时原 FileHandle 打开一次，以该 FD 的 regular/size/mtime 和真实 FD 路径在原 grants 判定中确定实际消费对象；Range 按同一次 size 解析一次，变换与流发送复用同一 handle，不再按 URL 打开第二份文件。HEAD/可直接 304 的验证器请求保元数据快路。原取消与授权 generation 在异步投递/发送边界保留，真实撤权仍拒绝；不添加认证 cache、token 或第二资源 owner。路径被 symlink 重定向不会推进授权 generation，因此不能用 generation 相同替代实际打开对象的边界。最近门必须覆盖暖路径/父目录 retarget、非 regular、Range/416/HEAD/304、变换长度、撤权/删除/截断与取消。

同一 IO 请求在排队期间已停止时，沿既有 cancellation 在开始准备前退出，不再 resolve/stat/open/read/transform。属性交付继续覆盖作者晚注册；沿同一个 timer 在实际 settled callback 结束才清理，pending 已清空则不再创建空的 RAF/fallback 链，不改交付间隔与作者初始化语义。

Scene AssetCatalog 的候选是按实际引用闭包读取，沿原 loader 的局部 queue/seen 工作；Root 索引仍完整保留作者文件名。种子必须覆盖静态/隐藏/潜在层引用、既有 SceneScript 动态 createLayer 模型、direct MDL 已解析 material links、stock/utility。闭包读到已选 material 后，其 pass 的 constant ShaderValue.scriptSource 也必须沿既有动态资源分析把模型加入同一队列；不能只看 Document.scriptBindings。MDL 使用既有单次 PreparedSource 交接，不重读；effect→material→shader/include 与模型/puppet 依赖沿原优先级/取消/局部失败规则闭合。粒子定义中的 material/children 是额外真实种子，必须沿原 definition/graph owner 前移同一次解析并交回原 prepareAssets 消费，不能为发现引用再解析一遍，也不能省掉根/子粒子材质。若当前已支持的动态表达式不能静态穷尽，须保它实际需要的候选或现有按需路径，不能因 literal 分析未命中就丢能力。动态路径的原候选顺序也要保留：直接模型名只有解析成功才压过 workshop namespace 候选；不能把完整文件名索引误当成功模型集合。不同 namespace 候选的局部缺失/坏 JSON 与同路径坏 package 不降 loose 是不同规则。关闭全量 authorHandles 读内容入口前，先确认全部动态消费者，再以未引用坏文件不阻播放、动态新建/隐藏待显、材质脚本与共享 literal 模板、根/子粒子、MDL多材质及直接坏模型/有效 namespace 的根优先级反例验证。不新增持久 catalog/cache owner。

### P4 普通模拟帧的固定事实（CPU 已过，clipping 可见门待验）

Puppet 的 physics bone indices 沿原 PlaybackState 初始化一次；当前 geometry 不含逐骨 alpha 时，clipping 直接消费原已知 coverage 恒一事实，含 alpha 的 geometry 保每帧实际扫描。CapVelocity 消费同 step 已算出的 normalizedLives，PositionAroundControlPoint 的固定 axis/circleBasis 沿原 plan 准备；live control-point 位置/角度与随机序列不冻结。没有新增跨帧几何/模拟缓存或第二 owner；最近门应证明无 physics/多骨、恒一/动态 coverage 与实际 alpha、age/lifetime 边界、axis/随机序列和退休/重建仍等价。未验证前不列入完成。

### 已实施：已完成视频文件的来源确认归请求入口

Scene 视频 Registry 的两个公开入口各确认一次本次当前 source identity，再用它查原 device/source 映射；private source 不在同步字典查找前后和私有文件构建后重复证明原作者文件。borrowCompletedWebM 只借已完成的私有 MP4，唯一生产 caller 已有当前 identity，不再接原 Handle 重验两遍。实际仍读取作者数据的 Root.readEntryChunks 保同 FD 稳定性和范围；已完成私有输出的 revision、domain/purpose、预算和 strong lease、取消、device/epoch/stop/rebuild 均由原 owner 保持。按当前调用静态计数，package live hit 来源检查 3→1、completed hit 5→1；实际前后行为和耗时须门验证。用户属性视频的异步 prime/adoption 有实际时间间隔，不套用该同步删重。

### 已实施：纹理 snapshot 完成后不重查作者文件

末轮查漏确认同次 TEX candidate 冷路径至少七次、暖路径仍五次 currentIdentity 查询；目录来源每次还重复路径解析与 lstat，视频声明也在纯内存检查前后重复查询。沿原 prepareTexSource/prepareDirectImageSource 在独立请求入口取得一次当前 revision，显式 expected key 只与该当前值比较，再查询原 cache；miss 沿现有 readSnapshot 保同 FD 读中稳定性、范围、路径和取消。随后尺寸、decode、upload、candidate、动画与已完整捕获 payload 的视频声明直接消费本次 PreparedSource，不因纯内存计算再次 stat，也不因读完后作者另写文件拒绝当前完整 snapshot。下一次独立调用重新取当前 revision，仍能发现同尺寸/mtime 的 ctime 变化和文件替换；prepared 的 input/key 不一致仍拒绝，不增加 validation stamp、permit、长期 cache 或第二 owner。URL/handle 非 prepared 入口直接进入原 prepare，清掉调用者先 sourceKey 再进入相同准备的重复。

最近行为门须区分读中修改仍失败与读完后可完成旧 snapshot、下一独立调用使用新 revision；冷暖 metadata 次数由测试副本计数，不增加产品观测。多 purpose 单次 decode、opaque/尺寸、video/sprite/volume/embedded/raw/BC 格式与真实 GPU 失败保原语义。真正还在读的媒体 FD/chunks/segment、owned-file lease 和 request/device/epoch 生命周期归原消费者，另沿实际调用查漏，不能用已完成纹理 snapshot 免除未来读取边界。

Web 小项只用本次 CSSOM 成功读取集合，避免同次重复 fetch 可读 stylesheet；不持久缓存无 hover，保晚插规则与不可读 CSS fallback。同次媒体列表用局部 Set 去重，作者事件仍每次通知。额外读取 playbackRate 再比较的候选撤回：作者注册对象可有抛错 getter 与正常 setter，原赋值有效，前置比较反而拒绝；保原赋值语义，不为省它新造绕行链。

同轮末查还有两处局部清退：字体的语法前置过滤不能拒绝 Root 原本接受的入根 dot/空路径段，选根与实际越界由原 literalEntry/FD 负责，非法绝对路径仍按原字体局部 fallback；Raw RGBA 静态 padding 裁剪先选最终会上传的 mip 前缀，再检所用 physical 布局和裁剪字节，未消费坏尾不再阻塞。原无裁剪/动画/data 全层消费者和实际所用坏 mip 仍拒绝。Release 纯日志 JS 即使没安装 listener，其正文仍有注入/解析成本，沿已有 DEBUG 拼接直接不编入；真实网络/媒体桥与作者通知保持。

### 全仓后继：Video 首播与共享音频

Video 首播没有实际淡入淡出，却等统一 crossfadeDuration 250 ms 才标记 transition complete，ready 又依赖此标记，期间每 50 ms 继续 WindowServer 查询。只将无动画首播分支在原 CATransaction 提交后立即交原 completeVideoTransition，真实可见/几何/Space/窗口归属确认仍走原 observer；已有画面间的实际动画及取消/身份保持。门须区分首播不等空动画、切换仍等真实转场，以及停止/被替换请求不迟到提交。

SystemAudioSpectrumService 的首次日志在 Release 仍每帧扫描 rectifiedMono.max()，静音可持续 30 Hz；hasLoggedCapturedData/captureGeneration 也仅诊断使用。整组观察和字段/reset 随原 DEBUG 编译边界剥离，保真实 captureResourceGeneration、token、PCM 分析及音频响应。用两配置编译与实际代码执行确认 Release 不再扫峰值，不能删除实际分析。

库/下载初审另定位卡片 cachedCanLaunch 的逐次 filesystem eligibility 和 project.json 同次双读取。继续追原字段/实际点击/热键导航/预览的消费者；便宜 UI 投影不应反复证明文件，实际候选和读取归原执行链，不能让外删文件在热键中反复卡住。未核清前不加另一缓存或新认证 owner。

库 project 预览准备沿原 SteamWorkshopProject 解码器只提取既有 preset 图像候选（按原优先级、只收字符串），删除第二次 project.json 读取和整份原始 JSON 投影。原 preferredPreviewRelativePath 统一完成作者/常规/preset/gif/旧 metadata 候选选择，目录 canonical path 同次只算一次；删除其后再次 stat 和绕过原入根判定的 project.preview 后门。无新增 cache/owner；非法可选 preset 值局部忽略，现有合法选择顺序保持，实际预览读取失败仍局部化。最近门用真实文件/实际解码和预览选择，计数同次读取一次并覆盖混合 preset、declared/gif/metadata 次序、缺失与根外路径。

### 全仓后继：事件、分片与重复桥接

Daemon 父生命周期沿原 process exit source 的 registration handler 在注册完成时再核一次父进程，覆盖安装竞态后删除永久 10 Hz getppid 轮询；保退出事件、stdin EOF 和硬退出期限。NDJSON buffer 只记原 storage 已扫描到的 offset，新 chunk 只扫新范围，消费/clear/reset 沿同 owner 更新，保长度限额和空行/分片/合包语义。Steam helper 回包用现有 decode(Data) 入口，删除 Data→String→Data 往返，原 JSON/字段/请求代际不变。状态栏初始化两次同步全采仅保一次；常驻采样与菜单新鲜度/网速基线另审，不盲删。CI 最终 validator 已深验同一未变 App，清掉紧邻前一份同参数 codesign verify；签名、Team/entitlements、公证和发布门不变，不执行发布。

### 全仓后继：卡片投影与实际目标分离

cachedCanLaunch 的 UI 路径仅按原记录已发布字段投影 ready、Video URL、Scene folder/project 和 Web entry/依赖状态，不调用会读文件的 isPlayableOrLaunchable、scenePackageURL 等 getter。删除不能提供独立事实的 Web eligibility signature/cache。上一张/下一张先按原顺序作便宜投影，再仅沿选定方向逐候选使用原实际可启动判定，失效则继续、最多一圈；实际启动保原异步 request/prepare/FD 读取边界，避免外删文件卡住热键，也不全库 stat。与并行 UI 会话按 hunk 集成，保其混合列表、票据和最近成功接线。

频谱配置在原启动 seed 与音量/速率一起一次落入引擎，首个 Video play 带完整当前字段；真实设置变化仍沿现有差分投影。删除每次 setAsWallpaper 后再次全量配置/清零/IPC，以及仅补首次播种的 0.6 秒 timer，不增加签名去重器或另一设置 owner。最近门须覆盖首播、谱开关、Web/Scene 先启动、新进程/多屏及导入重置偏好，避免以少推消息漏实际配置。

P6 补查：声音包 snapshot 同样在独立请求入口确认当前 identity；原 readChunks 完成后和借用已完成私有输出时不再查作者文件，真实读取稳定性与私有输出 revision/lease 保留。下载事务不因可选 preview 无效而拒绝有效入口，预览选择仍在原入根读取链局部处理；实际文件清单、复制和发布完整性保持。在线缩略图 attributes/read 与视频 fallback 的 NSImage open 已会处理缺失，删除紧邻的 exists；不改缓存过期、实际解码失败和 fallback 画面语义。

### P7：下载与旧目录迁移直接消费当前结果

旧 v1 公开目录迁移只负责复制当前作者目录，旧路径继续供现有播放使用；它不应在复制后用旧 contentDigest 拒绝已新增缓存或改过内容的当前目录。沿原私有 prepareSource 将历史 expectedDigest 从迁移 caller 退役，正常下载仍必传 receipt 摘要；本次 FD 复制的路径、稳定性、字节预算、取消和元数据当前指针不变，新 commit 直接记录该次复制已计算的摘要，不先 hash 整树再重算。用旧摘要+新增文件/修改有效入口成功迁移、普通下载同样变化仍拒、读中修改与旧目录保留反例验证。

在线图库下载沿原模型一次选择同一 variant 的 URL/size，直接 GET，删只供进度预估的串行 HEAD；真实响应长度优先、未知长度保原不显示百分比语义。URLSession 回调内及时 move 临时文件接管所有权，删中间整份视频 copy 和对新 UUID 的先删除。发布沿原 owner 在目标目录准备本次自有 staging，再原子替换最终文件；不能先删旧文件再搬新文件，失败清本次 staging，旧文件保持可用，跨卷只承担实际必需的搬移。实际 HTTP 失败在该响应消费点返回错误，不能保存 404 正文为 mp4；不加探测请求、摘要或预认证。用本机受控 HTTP 记录 GET/零 HEAD，覆盖长度、重定向、错误/断流、所有权与取消，以及已有旧文件时发布失败仍完整保留，不访问用户媒体。

SIL 失败签名只在负缓存非空时前置计算，真正解码失败仍生成当前签名；保缺文件反馈。mtime 保原精度，修复同秒同大小合法替换被旧失败条目持续拒绝。在线缩略图定期维护沿原 Shared trim 的同次枚举用实际过期 cutoff 先删除过期 regular 文件、再按剩余大小做原 LRU，不再随后二扫；默认未传 cutoff 的其他调用不变，原初始化清理保留。最近门覆盖空负缓存正常读取、坏图抑制/有效替换恢复、过期优先/新鲜保留、LRU预算、限频与删除失败，不加另一清理 owner。

### P5 最近验证结果

固定 P5 产品源的 18 个 CPU/JS 模块和 9 组原生/GPU/AV/Web 邻近回归已通过，所有运行前后固定源核对零漂移。首轮 CPU 10 项、原生 8 组通过；余项均为测试来源重路径、旧 DTO/解包目录假设、大小写计数或 throwing-autoclosure 编译接线，修正后只重跑失败项，没有改产品来迁就夹具。实际通过包含按引用闭包与未用资源零读取、粒子单次解析、同次纹理冷/暖一次身份查询、多用途 snapshot、包读取中修改/取消、字体入根路径、Raw/BC 真实上传、Web 单 FD/Range/HEAD/304、Scene 视频复用与 AV 出帧、Video 首播和两配置共享音频。P1 production GraphExecutor 的真实原子执行/预检门也已通过；其他旧图桥接夹具与 Puppet clipping 可见门仍须补齐。

P5 未做合并 App Debug/Release 构建、实际冷暖启动多轮对照、字体 backing 内存测量，不能用上述模块结果替代产品验收。本轮测试进程均已退出，构建/原生窗口已明确交还 UI 会话；测试只用任务目录和只读用户样本副本。P6 后继产品改动不在此固定源中。

### P6 最近验证结果

固定 P6 产品源的 16 个选定纯 CPU 单元已全部通过，运行前后源摘要零漂移。首轮 15 项通过；新增导航 symlink 夹具误把临时目录原始路径当作引擎保存的 canonical path，按实际 Engine.normalizedPath 修正夹具后该模块两方法通过，产品没有为此改动。已实测父退出安装竞态/硬期限、增量分片、Steam 代次/UTF-8、纯字段卡片与方向候选、真实 Combine 频谱差分、Web准备/Release隔离、可选预览、在线磁盘缓存和原生 helper 分类一次/签名策略 mock。声音包完成后修改/取消、下一独立请求与读中变更的真实 FD 边界另门已过，未启动 App/GPU 或播放扬声器 PCM。初始多层字体、Candidate 与 Puppet clipping/图桥接等原生门、合并 App 及测速仍待补；P7 不在该固定源中。

### P7 最近验证结果

固定产品源的 6 个选定 CPU 模块已全部通过：旧 v1 当前内容迁移/下载 receipt 反例、Shared 实文件过期与 LRU/限频/删除失败、在线调度/磁盘缓存、真实本地 HTTP 下载、Web 作者准备与缓存。HTTP 记录只有 GET、零 HEAD；同卷交接的真实 inode 保持，原子替换成功及最终失败保旧内容/inode、staging 清理、404/断流均过；取消在服务端仅发出 81920/4194304 字节时结束，不是收完后丢结果。跨卷仍承担实际搬移，不据此称任意设备零复制。

Web 属性更新、重置和 Combine 失败保留作者 memo，下一准备 0 作者字节读取/0 解析；override/bookmark/grants 仍重建，作者修改、坏缓存及删除发布 fence 反例保留。首轮下载临时路径与 Web 变量重名夹具修正后通过，产品未迁就夹具。零调用目录校验函数和普通图片重复 input/source 比较已删除；首次输入匹配、当前 revision、完整 snapshot 及实际读取失败门保留。四份只读样本的 9 个 TEX 未见超出颜色层数的物理尾层，只属元数据清点，不据此另造读取链。固定源均零漂移，独立复审无阻塞。

### P7 合并构建结果与剩余验收

固定 v6 的纹理 CPU 门、优化 Debug（-O/wholemodule、关闭 Debug dylib）和 Release 构建、严格签名及源码零漂移均通过。Release 为正式身份，Debug 为 Startup 测试身份，均由 H9QWU9XN8R 签名。Release SwiftDriver 未定义 DEBUG；选定四个 Scene/Web 调试 runner 在 Debug 有符号，Release 为零。未启动 App，构建耗时不算启动收益。

其余 14 个原生单元归 10 个编译组；其中五个 GraphExecutor 仅共享编译，仍各用新进程/缓存和原断言。驱动静态独审已过，尚未执行；局部清理失败误记成功已修正。字体成本/内存、SIL/其余 Metal、产品入口及交替冷暖对照未验。后继 P8/P9 不在本轮构建中，当前剩余范围见文末合入边界。

### P8：兼容命名空间的局部失败与单一读取链（旧链已退役，最近资源门与成本已验）

已证存量：兼容分支把同一索引解析三次，每次冷暖准备都捕获整包、计算全包及待解条目摘要，再逐字节比较所有缓存文件，Root 随后又枚举目录。生产 snapshot 在 extractor 锁前创建，进入旧链后取消未传递。未使用的别名条目也能触发整包回退，并把原本可直接挂载的大小写邻居降回宿主文件系统限制：在不区分大小写的缓存卷上，两个不同内容的 scene.json/Scene.json 加上被 extractor 忽略的 unused/a.bin、unused\a.bin 别名即可使包根失效。这是当前快慢链语义不一致，未证明由 v6 新引入。

裁决采用原单一 Root.package；索引只解析一次，不再退回物理解包。原 entries/directories 已能分别表达同名文件与子目录，不存在必须整包捕获的生产语义。安全条目只将反斜线换为分隔符，按 Unicode canonical 等价的 exact 目标确定性选择索引首条，首条 raw path/range 和包 revision 就是实际 identity；后续同目标条目不投影、不读取或认证。不同大小写邻居继续独立，literal 先 exact 再用原排序折叠命中。绝对、NUL、空段、dot/parent 等不能落入包根的存储名局部忽略，不影响其他条目。C:/foo 在此仅是 POSIX 相对逻辑名，旧 extractor 也接受，不套 Windows 路径禁令；公共相对名入口也删除该 Windows 语法拦截，目录 backing 的实际 canonical/已开 FD 入根边界不变。typed SceneVFSAssetPath 的全冒号禁令也无权限用途：实际 asset→TexturePathResolver→Root 读取从不进入 URL scheme 或 externalFile 分支，一并删除；userProperty/system/graph 的 typed 分流、控制字符与真实入根规则保留，以相邻 file: 名称只能读本 Root 同名文件反例验证。显式目录拼写 parent/、parent/. 保留目录意图，不能误读同名 parent 文件；中间目录必须存在，missing/../entry 不得消去缺失检查。

实施复审撤回最初的 lazy 别名逐字节比较方案：该检查只服务物理解包的目标覆盖，虚拟 Root 已无写输出，确定首条后没有身份混装、越界或播放消费者需要证明其他条目相等。直接删除 aliases 字典、额外 payload 读取、内容/长度认证和冲突拒绝；首条本身读错或格式坏仍按原资源局部失败，不试后续别名。选中读取保真实同 FD 变化、截断、解析范围及取消，sink 只有整次成功后才发布。Backing 同次 readFile 只选一次条目并构造其 identity，并在 prepare 前负责实际 consumer 字节预算；Reader 唯一产品 caller 只传本 opened.index 的不可变 Entry，删除没有外部 producer 的成员 Set/核验、重复预算参数和已无 producer 的错误 case。独立 currentIdentity 仍核当前 revision；不新增锁、缓存、stamp、permit 或 owner。

退休 SourceFacts 的 extractor fallback、整包 snapshot API、无生产/正式工具消费者的 extractor/facade、Reader 的 URL/Data 旧便利读取入口、只被转存而从未消费的 packageReport 及两个旧 report overload；产品只保同一打开包的 index/chunks，测试预期由 fixture 和独立切片建立。Host 在既有 launch 直接构造相同 App 私有媒体目录，声音/视频的 OwnedFile、预算和实际借用不变。旧解包缓存不再读取，因此其损坏/额外文件/宿主卷大小写不再影响播放，也不为修复它保另一检查平台；不清用户缓存。测试共享的 PKGV 生成器移入轻量 fixture，旧缓存实现测试退役，媒体断言迁移真实 Root/私有输出生命周期，不能保无人调用的产品链来服务测试。

验收覆盖忽略别名与大小写邻居组合、同字节/不同字节、不同长度及同 range/零长度别名的确定首条与后续零读取、Unicode/分隔符变体、file+directory/显式目录、安全入根与 C: 相对名、未用条目零读取、污染的旧缓存不参与、同 FD 读中修改/截断、并发独立读取与取消。比较原 v6 与新链的实际索引/字节读取、输出、局部失败及必要耗时；再做 Debug/Release 构建和代表 App 回归，不能以源码计数冒充启动收益。独立设计审查已确认单一首条来源、撤回别名认证及 report 无消费者，实施后独审与最近资源行为门已闭合；前后成本与剩余范围统一见下文“本批合入与暂停边界”。

P8 产品与测试迁移已冻结并完成静态独审；相对已构建 v6 的 11 个相关产品路径净减 519 行，两个旧 extractor/report 文件删除。CodeHealth 的 1388 份 Swift、Scene Defense、文档导航/健康及 diff 检查通过。测试改用真实 Root/FD、首条输出/后条零读取、目录与相对名边界、包不可用时完整 loose、音视频实际借用/回收；共享造包 helper 独立，旧解包测试退役。此为冻结时静态结果；后续实际资源门、SourceFacts 成本与本批构建结果见文末。静态路径计数不作为实测提速或零回归结论，媒体/App/GPU 与最新 Release 仍按延期项处理。

### P9：越界表项局部不挂载，文件入口跳过裸包目录（坏条目、loose 与字体最近门已验）

已证 Reader 末尾遍历全部 payload 范围，有效 scene.json 加一个未引用的越界 unused/bad.tex 就会丢整包 Root，无 loose 时误拒播放。裁决保留 Reader 的 magic/count/UTF-8/表长度等实际结构边界，将 payload 范围判定合入 Backing 已有逐 entry 名称投影循环；越界项在进入 entries、目录和首选集合之前直接略去，首选定义为首个路径与范围均可读的条目。省去 Reader 的第二遍扫描及已无生产者的 invalidEntry 错误，不新增晚期校验、异常、状态、认证或 fallback。Root 是原 readEntryChunks 唯一产品 caller，只从本打开包的安全投影选值，仍保 FD 读取稳定性、短读、取消及 prepare 前预算；不可读范围不生成 identity、进入缓存、reserve 或写私有输出。

原 literalEntry 只被 Scene JSON 和字体两个文件 Data 消费者使用。沿原唯一根顺序循环，凭真实 packageBacking 与现有 indexedResource 跳过裸目录，继续找可用 loose 文件；目录 backing 的文件 Handle 也可没有 indexedResource，不能误过滤。显式 /、/.、/.. 仍由已选末尾 / 保持目录意图，返回原 Handle 并报 unreadable，不误读同名或 lower 文件。文件与目录同名时，安全文件仍先选；已选文件内容坏仍按原局部失败，不重试后 alias/loose。这样避免局部去掉坏主条目后，残留同名目录又把原本可用的 loose 入口挡住。

独立设计审查确认无需新的 SourceFacts 选根 owner。有效大小写邻居仍按原 exact/fold 规则选包；部分坏包现在保留安全资源，可能与旧整包丢弃后的 loose 画面不同，应按新局部恢复规则明确断言，不能宣称坏包输出一律等价。验收覆盖未用坏项与有效主入口、坏主项和完整/不完整 loose、同名目录、大小写邻居、非法首 alias 后有效项、零字节 EOF 边界、不可读项零 payload/reserve、文件坏内容不改选，以及真实字体的目录/loose/stock与显式目录反例。正常只减少轻量 O(N) 遍历，不预称启动瓶颈；和 P8 合并到最新固定源统一做必要回归及前后成本，避免重复构建。四个产品文件与最近测试已完成并静态独审通过，后续已执行的合并资源门与成本结果如下；App 等延期范围仍不称已通过。

P8/P9 的 14 组选定 CPU 单元累计 65 个测试方法通过，无跳过。首轮 12 组过；余两组在仅修测试后全模块重跑通过：framebuffer 原夹具重复拼接同一类型，stock manifest 的实际差异逐项证明仅为系统 /var 与 /private/var 指向同一物理文件。后者只在测试比较物理目标时归一化，原逻辑名称、来源、顺序、类型、大小、查询及 missing 反例不变；未改产品迁就夹具。两固定源之间只有这两份测试及文档变化，产品字节相同，全部执行前后源零漂移。

SourceFacts 前后对照已在新输出重跑通过：两 arm 使用相同优化配置，5 轮交替 AB/BA、每次新进程，同一 owned HOME 内区分空产品缓存与同 HOME 再启动；未清 OS 缓存。计时不加载观察器，另用独立观察进程核真实 FD/pread，前后源零漂移。

| 输入 / 指标 | P7-v6 | 本批 P9 |
|---|---:|---:|
| 普通包，空产品缓存准备中位数 | 6.55 ms | 6.83 ms |
| 普通包，同 HOME 再启动准备中位数 | 6.13 ms | 5.90 ms |
| 兼容别名包，空产品缓存准备中位数 | 20.03 ms | 5.33 ms |
| 兼容别名包，同 HOME 再启动准备中位数 | 19.51 ms | 5.07 ms |
| 兼容别名包，未引用 payload 读取 | 29,360,138 字节 / 449 次 pread | 0 字节 / 0 次 |
| 有效场景 + 未引用越界表项、无 loose | 无场景 / descriptor | 场景与 descriptor 保留，实际 ID 7 |

普通包基本持平；兼容分支的额外工作被明确删除。功能反例单独记录，不进入耗时中位数；这些只覆盖 SourceFacts 准备，不是点击到真实可见首帧，更不是全样本提速。首轮观察失败由真实 /private/tmp 与 /tmp 路径别名造成，修正只在测试匹配 canonical URL；第二轮记录实际 FD=4 与原始/规范路径差异，baseline 字节/调用正控制通过。首轮失败收据保持失败，不覆盖成成功。

### 本批合入与暂停边界（2026-10-26）

本批 11 个相关产品路径相对 P7-v6 从 4438 减至 3915 行，净减 523 行；旧 extractor/report、整包 snapshot 和重复 alias 认证链已退役。当前没有已知需要阻止本地合入的重大产品故障；14 组选定 CPU/FD/CoreText 门已通过，最新固定 P9-v2 的优化 Debug checkpoint 已构建通过，严格签名检查成功、源码前后零漂移；耗时 451.678 秒只记构建成本，不当播放性能。该 App 未启动，标识沿现有 Startup 测试配置，当时正式 Release 尚未重建，后继整合基线与 P10 边界见下文。已完成的 P1/P3/P5/P6/P7 结果保留各自固定源边界，不称全部覆盖 P8/P9。

以下暂缓项不阻塞本批本地整合，也不等于已通过：

- 剩余原生正确性门：Puppet clipping、SIL、旧 RuntimeBridge/Program/GraphExecutor 夹具、初始多层字体及 typed FrameTextureRegistry；已有同输入通过结果继续复用，不为凑全门重跑。
- 新 Root 的 Sound/MaterialVideo 实际 AV 借用/回收、用户属性视频，以及最新合并 App 的 Scene/Web/Video 出画面、切换与停止。
- P10 完整 Release App、最新产品冷暖启动交替对照及字体成本/内存观察未补；主仓 8f715 的已安装 Release 属整合基线，不能覆盖 P10。本页 SourceFacts 数字不能替代产品验收。
- 主仓其他工作树合入后的冲突收敛与受影响回归、长期全范围末轮复查；轻微问题沿此页原责任登记，不另立阻塞平台。

该批合入时保留主仓原有 UI 设计与四处登记，不随本专项暂存，并已通知 UI 专项依用户指定顺序合入。后续整合由相应会话完成；旧 UI seed 后经用户确认为过时副本并退役，不再恢复。当前已按用户授权同步主仓并恢复 Goal，只重验受影响边界。本地整合与交接不代表发布或长期 Goal 完成。

### P10：同次来源查询与无消费者工作（最近回归与 Debug 已过）

Scene 目录 `currentIdentity` 在首次入根解析与 `lstat` 后，再次完整解析路径却不复核 inode/revision；删除末尾重复解析，以首次接受的 metadata 为本次查询结果。下一独立请求仍重新取当前 revision；缓存 miss 的实际读取继续由原 FD、expected identity、读中变化、范围、取消和预算负责。不新增许可、缓存或 owner，不将本项称为普通帧优化。最近门复用 snapshots、texture resource input、resource handles 的来源变化与读取反例。

Web 在原 owner 内清退三处无消费者工作：同一 canonical 目录的多个属性共用一份现有 watcher，逐属性快照和通知不变，最后一个属性移除才关闭；Release 不维护只供日志的 `reportedSkips` 和应用计数，真实作者 callback、逐属性容错和晚注册重放不变；自动交互区域只在主 frame 调度，子 frame 的真实媒体刷新与公共登记边界保留。不加第二套监听注册表或全局 hook。

普通材质 pass 不再遍历、投影并比较 Program 的三组不可变纹理槽，或重复构造 SlotBinding/核对同次 exact identity。原 private 装配/Derivation 已保证这些事实；原 canonical `g_TextureN` 名称规则移入既有 PreparedAssembly 绑定循环。保 ABI/sampler 失败优先级、graph publication 及替换输入的真实消费边界、设备/目标 alias 与命令生命周期；不新增校验规则、cache 或 wrapper。准备期错名/邻接有效名反例、finalizer、真实 Metal pass/replay 与 production graph 原子门已过。

Web 作者 RAF/timer 的 schedule 先取 `now()`，随后 arm 无条件覆盖；暂停中新建者也只在恢复 arm 后消费起始时间。原 entry 的初始 `started` 改为 0，真实计时仍由 arm 唯一赋值，省掉每次创建的无消费者时钟调用。用原调度脚本检查调用次数、暂停剩余时长与恢复/取消，再复用真实 WebKit 暂停门。

验收沿最近目录同步、音频/属性桥、Release 隔离、交互区域门，补真实目录监听共享/撤权/切换/别名改指向和主子 frame 调度反例。冻结源后做 Debug 构建与独立复审；对照实际调用、FD、事件和调度次数，耗时须另测，不能把减工数量当作整体首帧提速。已安装正式 App 正供用户试用，本批不擅自退出或替换。

当前 14 组选定单元共 63 个方法通过、无跳过：首轮 7 组通过，目录观察误将同一路径带/不带末尾斜杠的 URL 对象视作不同，真实 FD 被误计为零；仅修测试为 canonical.path 并标明等待阶段，不放宽超时或产品断言。固定 v2 复跑该门并补 6 组原生/JS门通过；首轮其余 7 组的产品及测试输入未变，复用原结果。两轮源前后均零漂移，原失败证据保留；没有修改产品迁就夹具。

实际减工对照：同目录双属性现在只有 1 个真实 FD/source，原逻辑按属性各开 1 个；目录 metadata 完整路径解析由 2 次变 1 次。相同新观察夹具执行原 8f715 JS 与候选：每次运行中作者调度的时钟调用 2→1；子 frame 的 20 次刷新触发由 20 个空 RAF→0。Release 实际 Swift 拼接已排除属性日志去重表、计数及统计对象，双配置作者回调/晚注册/逐项容错/颜色兼容均通过。材质 pass 的静态槽投影与身份镜像删除，真实 Metal 输出与失败反例通过；没有新增毫秒、帧率或整 App 启动提速结论。固定 v2 的优化 Debug 构建及严格签名检查通过，源码前后零漂移；430.700 秒只记构建成本。该候选未启动，已安装版本未替换；完整 Release App 和产品入口冷暖计时本批未重跑。

### 后继只读发现与覆盖边界

Web 主调用链已复查准备/缓存、IPC/切换、资源/网络、媒体/输入/暂停；下批小项为 RemoteStylesheets 的 Release 纯日志 3 秒 degraded timer，它不阻塞 3 秒，真实请求/重试/激活期限及 layer 恢复须保。Scene 已复查装配/graph/encode/输出、资源/格式/媒体、shader 内部及主要粒子/几何消费链：候选包括同次 fragment 重复解析与 normalize、词法长行拼接、同 MVP 成对指针重复求逆、skin 输出重复 finite 扫描、出生计划固定数学、粒子运行报告/文本脚本 hash/声音 KVO 的 Release 纯诊断，以及 MDL 重复扫描与冒号禁令。声音含 ./、重复分隔符及 .. 的路径当前还受 indexed 入口同类限制，不能只删上层 guard 就声称恢复；须另按原选源 owner 裁决。其中同次 fragment 解析、成对指针求逆及文本 hash/声音 KVO/样式日志已在 P11 处理，结果见下文；其余候选仍未实施，不混入 P10 运行结论。完整全仓复查与前述暂缓验收仍未完成。

P10 本机汇总为 `d41-playback-validation/p10/final-validation.json`；必要日志、首轮失败、FD 路径证明及原始片段保留。已退役两份完整旧源导出，首轮 owned overlay/manifest 与三个旧 JS 片段足以重建观察；连续迭代保留一份 DerivedData、最新候选和当前固定源，供后继集成对照。当前无本轮运行进程，正式 App 始终保留。源码、测试和文档均未暂存或提交；Goal 继续，不宣称全范围已无问题。

### P11：同次 shader / 指针计算复用与纯诊断剥离（回归、成本与 Debug 已过）

冷 analysis miss 已有严格 fragment SourceAnalysis，却又让六个分析器分别 lexer/syntax 同份源码。改用这些分析器现有的 Unit/tuple 入口，直接消费同次局部 fragment/main/outputUses；保持原默认语法、nil/失败、名称与控制流语义，不跨 variant 缓存，不把 normalized 与 raw source 混用。只省同次重复解析，不省实际 compiler 的源码预算或第二阶段 normalization。

当前/上一指针用同一帧 MVP 各求一次 Double 逆矩阵和残差；沿原几何 owner 同次求逆后独立投影两点，两个调用点各复用一次，不跨帧持有。一个指针无效不影响另一个，保奇异/非有限、近平远面 w、ray-plane 及既有逆矩阵精度。用原几何门正反例、成对/单点等价与实际求逆次数验证。

声音 timeControlStatus 观察和未知文本子集的全文 SHA 仅服务 Debug 报告，沿原 owner 将对应生成/字段/注册注销从 Release 剥离。Web remote stylesheet 的 degraded 状态、3 秒计时和 elapsed 只服务日志，也沿原 DEBUG 拼接剥离；保真实请求、重试、激活期限、layer 恢复与取消，不把它称作省去 3 秒播放等待。最近门须执行实际双配置代码及样式 JS 状态机，不能只查 transformer 输出。粒子运行报告整链、其他几何/模型扫描及格式路径语义保留后继裁决，本批不叠加。

验收选择实际 shader facts/缓存与相邻语义反例、几何对照、声音/文本行为和双配置诊断隔离、样式状态机。前后用同固定输入比较解析/求逆/纯日志调用次数；需要耗时结论才补隔离对照。所有代码冻结后独立复审并共用一次 Debug 构建；不退出或替换用户正在试用的正式 App，修改不暂存、不提交。

P11 的 11 组选定回归共 176 个方法已通过，无跳过。覆盖六类 shader fact 的 24 组语义变体/相邻反例、实际编译与 Metal 像素、几何数值与计数、真实声音播放、双配置文本回退/诊断隔离、样式 JS 状态机及真实 WK 兼容。复用首轮输入不变的八组，仅重跑修正夹具的三组；源码各轮前后零漂移。shader 的实际完整 analysis miss 在 25 个输入中都是严格解析 22→16，并非全部 shader 工作只解析一次。

首轮三个失败是测试存量：bounded GPU 夹具把顶点 uniform 留零，四个顶点重叠，P10v2 同样失败；按真实 layout 补单位四边形坐标后原 HDR/alpha/mask 像素断言通过。缓存门漏真实 ResourceView 源码组，补依赖而不加 stub。Puppet 静态门仍锁已退役的枚举/包装调用拼写和全文件字面计数，删除这些旧形状锁，保现有几何与拒错检查。根代理 v2 导出漏带缓存测试修正，原失败收据保留，v3 补齐后只重跑该门；未改产品迁就夹具。GPU 夹具按自然职责迁为一个独立 Swift fixture，原输出/拒错断言不变，本批相关文件均不超过 1000 行。

成本对照使用相同优化配置、输入与七轮 AB/BA 交替，计数与计时分离。shader 对照在候选依赖上编译 P10v2 原 computeAnalysis 方法（只改名）与当前方法；七个合法输入的耗时中位数均下降 11.6%–15.3%，351 字节输入为 2.54→2.25 ms，6531 字节为 36.96→32.19 ms。25 个计数输入的完整 analysis signature 相等；六类 fact 另有原字符串 API 的独立结果对照。不能把它写成两个完整 App 的对照。

指针数值探针用同一未插计数代码的 -O/WMO 二进制，对四组运行时 MVP/两点做 10 万次、七轮交替；双点片段 CPU 中位数 10.843→5.194 ms，需要 effect 的片段 14.986→6.154 ms，各轮校验和相等。只说明该 CPU 计算片段约省 52%/59%，不是每帧省这些毫秒或提高这些比例的 FPS。Release 纯诊断的剥离由实际双配置代码与 JS 状态机验证，不为它另造产品计数器；未做整 App 冷暖启动、RSS 或能耗的新结论。

最新固定 v3 的优化 Debug（-O/wholemodule）构建和严格签名检查通过，源码前后零漂移；415.499 秒只记构建成本。完整 Release App 未重建，但本批改动的文本/声音/样式链已实际分别编译两配置并验证剥离及行为。候选未启动，正式安装 App 始终保留，未重测用户入口的冷暖首帧。没有新增缓存、许可层、常驻观察平台或产品计数器；无调用者的旧 effect projection 矩阵入口已退出，单点 UV/Float inverse 的真实消费者保留。独立复审覆盖产品、夹具修正/提取与成本对照，未发现阻塞。

本机汇总 `d41-playback-validation/p11/final-validation.json`，保留必要原始失败、成本 JSON 与探针源码。三份停止使用的测试导出已压为可重建差异与 manifest，测速二进制/模块缓存及旧 P10 候选退役；连续迭代保留 P10 对照源、当前 P11 固定源、一份 DerivedData 与最新候选。所有源码/测试/文档保持未暂存、未提交。粒子运行诊断、模型/出生重复计算、其余格式路径与 shader 重复工作仍沿原候选队列推进，再扩至全仓；Goal 保持 active，不能据本批结算宣布全范围完成。

### P12：粒子纯运行诊断与无生产者载荷退役（必要回归及双配置 App 已过）

先处理 Simulator→Runtime→PlaybackState.loadReportLines 的纯报告链及 ChildRuntime 的普通帧日志工作：这些结果只被已是 Debug 的报告消费，Release 却仍生成诊断数组、去重、复制到帧快照、遍历映射与每秒 census。相比再扩一层 shader 缓存或混入模型格式改造，本批直接删除已有运行开销，职责和验证范围更清楚；模型/出生固定数学与其余 shader 工作按原队列继续，不撤销全仓目标。

沿既有 owner 将 SimulationDiagnostic 类型/生成与 audioDiagnostics、Simulator/FrameSnapshot 的诊断字段和赋还、Runtime/LayerImageEmitterCompiler 的消息构造和映射完整置于 DEBUG；不保 Release 空数组、空诊断函数或仍求值的日志参数。Runtime 直接消费原有 LayerImageEmitterCompilation，替代并排的 maps/initialDiagnostics 参数；maps 为真实产物，报告字段只存在 Debug。保持 Debug 原初始报告→graph 映射的顺序/去重。该变更不引入另一许可、缓存、状态机或产品计数器。

ChildRuntime 的 bufferFailurePaths 全配置退役：它始终由常量空数组生成、无真实分配失败 producer，父 Runtime 的遍历和日志计数一并删除。limitations 的多层诊断传递、字符串/集合/排序，以及 census 状态、每帧累加和到期遍历只在 DEBUG 存在，真实 spawn/follow 分配计数、容量 guard 与 continue 不变。优先沿原 Runtime 的 Debug 报告字段收敛，避免保 Release 空 inout/占位通道；不复制整段执行算法。

实施复查补齐上游：ChildGraphExpansion 的 performance 数组/inout 及 TemplateSupport 的成功 event-color marker 只有同一 Debug 报告消费，也同批编译剥离；Release 保真实 supported/unsupported 准入结果，成功分支不带空 marker 数组。Expansion 沿原构建结果收拢真实模板、unsupported 与 handled 输出，复用该结果的借用，不新增 collector；模板顺序和实际拒错不变。不能只删下游字段而留下无消费者生成工作。原 parent-control-point 准入成功值中的两个 O(1) 计数仍随真实 override 返回，不产生数组、字符串或扫描；本批保原直接接口，避免仅为两个整数再拆配置关联值和调用分支，不将此表述为所有报告元数据均消失。

不能按名称一律删除：Definition.diagnostics、graph/child expansion 的 unsupportedDetails/handlesAllChildren 仍决定实际可执行性。保有限值拒绝最小粒子、真实预热与 weighted work/periodic1024预算、发射 charge/reservedBytes 和所有非诊断存储预算、birth/death/transient、RNG/ID/余数/clock、worldspace 冻结/恢复与事件、step recorder 和 rope history。仅从 emissionStorageBytes 移除 Release 已不存在的诊断存储账目，不能下调实际数据/回滚预算来过门。Debug 诊断快照继续可回滚。

验收复用实际 Simulator/发射事务/音频双配置、Runtime/Child/rope 最近门。报告专属断言明确用 Debug，另用相同真实执行 HARNESS 的 Release 对照保留粒子输出、事件、容量/拒错、worldspace/child/teardown/回滚；仅排除诊断字段，不把所有测试改成 Debug 就宣称 Release 通过。对照临时证据核实际生成/存储和普通帧统计是否退出，若量耗时须计数与计时分开，不把片段收益写成整 App 启动或 FPS。冻结后共用一次 Debug/Release 构建，核完整 App 的配置整合与签名，并独立审查产品/测试及前后差异；正式 App 保留，所有改动不提交。

P12 最近行为结果：14 组选定模块报告 203 个方法，其中 193 通过，10 个可选真实作者门因缺隔离材料未执行，明确不记通过。11 组 CPU 共 136 方法通过；Runtime 的 49 个方法通过（含 16 模式 Debug/Release 实际输出、准入/容量/child/RNG/回滚/worldspace/rope/teardown），LayerImage 的 4 个实际 BC/映射/1024次种子采样与局部拒绝两配置门、MaterialCoverage 原 Debug 的 4 个门通过。真实作者其余模式不是本次 Release 对照；实际时间戳观测也不在此行为门覆盖范围。

固定源前后零漂移；CPU 首批与最终源的实际 Swift 输入/本模块哈希逐项一致，直接复用，后补 turbulence-mask 单门已过。首轮原生未进入行为断言即暴露旧测试闭包问题：禁用计时观测叶缺声明、同物理源码的 ../拼写重复、Descriptor 的真实 schema/identity/render-state 依赖未列。只修测试：复用既有叶且仍创建真实 encoder，按规范完整路径去重，补真实源码与空 DTO 类型；产品及真实 DescriptorBuilder→BC→EmitterCompiler→EmissionMap 路径不变。原失败及各轮 manifest 保留，仅重跑失败门；没有用产品兼容壳或削弱断言过门。

实际 Release 前后对照复用同一音频/粒子 HARNESS、同 -O/WMO，P11v3 与本批完整运行结果相等，只允许反射/存储元数据变化：Simulator/FrameSnapshot 的诊断字段均 true→false，FrameSnapshot stride 928→912 字节；该固定输入的一次原 emissionStorageBytes 预约 90016→84880 字节（少 5136），对应诊断存储与结构退出，真实状态/回滚预算保留。此为对象布局与事务预约账目，不是 RSS、冷暖启动或整帧耗时，不据此报新 FPS/能耗数字。

固定 v3 的完整优化 Debug 与正式身份 Release App 均构建通过，严格签名检查成功、源前后零漂移；430.564/364.355 秒只记构建成本。实际 Swift 命令中 Release 无 DEBUG；选定 Simulation/Runtime diagnostic 和 GPU 时间戳类型符号、child census/worldspace 日志串在 Debug 有、Release 为零，正常 Simulator 符号两者均存在。结合实际两配置字段/行为门证明本批剥离，不能扩写成整个仓库再无任何调试成本。两 App 未启动或安装，用户正在试用的正式 App 未替换；整 App 冷暖入口仍未重测。

本机汇总 `d41-playback-validation/p12/final-validation.json`。停止使用的 CPU/原生测试导出与旧 P10/P11 对照源已压成可重建差异及 manifest；探针二进制/模块缓存、旧候选与本批 Debug staged 副本退役，连续迭代保留当前 P12 固定源、最新 Release 候选及一份 DerivedData。193 通过与 10 未验分别记录，原始失败不覆盖。全部修改仍未暂存、未提交，Goal active。

后继只读复核已收窄：优先处理 lexical scanner 每字符重建累计字符串、VertexStream 对已验证静态/skin 输出重复逐顶点 finite，以及球形出生每次重算固定半径幂端点/维度。三者均沿已有 owner，不新增缓存或许可；当前 bounds、动态 skin 拒错、RNG/axis/sign/浮点次序须分别验证。归一化 Pair 的重复准备收益仅在 analysis/artifact 同时 miss 出现，且 route 与真实 compiler 预算不同，后置到直接热点之后；其余 MDL/路径和全仓范围继续原队列，不据本批宣布审查完成。

### P13：高频字符串、顶点与出生固定工作的直接复用（必要回归、成本与 Debug 已过）

本批选三个已有唯一 owner 的直接改点并行实施，共用一次集成构建。相比跨 analysis/compiler 的归一化 Pair 复用或重新设计模型上传接口，这三项数据来源和退役点更明确：scanner 只改更新方式；顶点只去已被 Reader/Skinning 证明的重复判断；出生只把固定数学移入原 Plan。不引入缓存、permit、额外校验层或占位 wrapper；若真实数据流不满足上述前提，先纠正方案，不能用放松真实坏帧边界过门。

Shader lexical scanner 的原 Segment 保持同 kind/顺序与字符内容；text 允许原位追加，分支只取 kind、不保 last 整值副本，不再每字符用旧累计 text 拼接重建 Segment。引号/转义、Unicode Character、行注释、跨行 block-comment 状态、code 空格投影、metadata/lineMap/预算和预处理语义原样。用原实现的本项目局部 oracle 比较精确 segments/code/raw/state 和相邻反例，复用 Contract/Preprocessor/MacroContinuation 最近门；隔离优化编译下量短/长 code/comment 片段前后成本，不预称完整 shader/启动提速。

StaticModelVertexStream 只在唯一 DirectModel 发布链消费当前顶点：Reader 已验证不可变 bind 全通道，Skinning 仅在当前 position/normal/tangent 有限时写入，UV 保留已验证 bind 值；任何后段 skin 失败由 DirectModel 完整回退 bind，不能发布半写 scratch。删除发布阶段重复的 12 通道有限值判断，仍在原一趟循环算当前精确 position bounds。保 count/空输入、当前动态 skin 拒错、设备/commandBuffer/slot generation/lease/取消及完成时序；不以作者 bounds 代替当前形变 bounds，不新增“已验证”证书。原绕过真实 producer 注入 NaN/Inf 的 stream 测试迁到真实 Skinning→DirectModel fallback，保全通道字节、late-invalid 完整回退、bounds、busy/cancel/late completion 与真实 Metal 门。

球形粒子半径仅把维度、两个距离 pow 端点及倒数指数移入既有 EmitterSpawnPlan，只有 sphere 准备该数学，不给 box/image 新增无消费 pow；原 raw 距离若无其他消费者则退役。出生仍按原方向分支抽样、调用 random.value 与最终 pow，乘法/abs/sign 次序和动态 CP/instance/event/world 输入不变。不折叠等端点、不跳过零 mask 抽样，不替换 sqrt/cbrt 或提前拒绝 Inf/NaN；RNG/ID/回滚和局部有限值拒绝留在原真实消费处。以原函数 oracle 比较 0/1/2/3D、阈值两侧、反序/等壳、±0/sign、极端输入及连续下一 RNG 状态/位模式，复用 Simulator/双配置发射事务最近门；仅在产品当前浮点环境下声明等价，不新增 fenv 许可。

四个产品路径各冻结并交叉独审；最近 CPU 与实际模型发布/GPU/生命周期门按影响执行。先修测试闭包，不给产品保测试专用旧链；有独立价值的失败反例迁到真实边界。计数/成本证据只在任务临时源中，计时不带计数；最终一次 Debug 构建和签名验收。本批不安装/启动候选，不改用户设置，修改保持未提交；未覆盖的真实 App 冷暖与作者样本继续明确列账，完整 Goal 不收窄。

P13 近门结果：11 个选定执行单元共 103 方法通过、无跳过；包含 Contract/Preprocessor/MacroContinuation、Simulator、双配置 PlaybackSimulator、真实 VM 发射事务、DirectPlayback/Skinning、Stream 的 7 个 CPU 生命周期门与 1 个真实 Metal 门、Reader 两个定点拒错门。新增球面 25 输入逐项比较连续 64 次非 NaN 精确位模式/同 NaN 类、每次及下一 RNG、0–3D 抽样次数；真实出生比较位置、允许的 ID 空洞、事件、极端半径仅拒新粒子与回滚。Reader 的 2 布局×12 通道×NaN/±Inf 共 72 输入在普通 Data 和非零起点 slice 都拒绝；三个真实 late-skin 溢出反例先证明已有首顶点写入，再核整份 bind 字节/bounds 回退和恢复。真实 Metal 从 Reader 自有 MDL 取顶点，经原 factory/Stream/Transaction 提交 GPU blit，核全字节读回、当前 bounds、已提交取消仍占槽、完成解租及同槽复用；不声明 draw 或作者画面。

首轮 MacroContinuation 旧 fixture 漏跟 throwing build，未进入行为；Simulator 一个旧源码形状断言仍绑定已退休字段。只给 fixture 加 try 传播真实错误、删非 optional 路径死兜底，并删除那条失效字段形状断言，不换成新字段锁。原失败不覆盖，修后只重跑两失败单元；两固定源仅上述两测试文件不同，全部产品字节及 Simulator 被其他门导入的顶层值一致。其余九个通过单元直接复用，各轮完整 manifest 前后零漂移，原 oracle/birth/失败反例保留。四个产品路径和三组测试分别交叉静态复审，无阻塞；静态复审与实际执行分开记。

相同优化编译下的片段对照（输入、输出检查在计时外，轮次交替）：scanner 的 64KiB code/comment 载荷约 27.380→2.446 / 27.588→2.166 ms；64 字符载荷约 4.580→2.395 / 4.678→2.391 μs，原 segments/code/raw/state 完全相等。模型 counted oracle 的 257 顶点重复 finite 次数 3084→0，全 12 通道位模式和 bounds 相等；独立无计数的 10 万顶点实际 updateBinding/copy/transaction-cancel CPU 片段约 0.268→0.207 ms（少 22.6%）。球面独立真实无插桩 sampler 的 20 万次 3D CPU 约 8.010→5.188 ms（少 35.2%），其余 0/1/2D 同组也有收益，连续样本位模式/RNG、计时校验和/下一 RNG 相等。sphere 的 Plan/Simulator 初始化在计时外，模型用 CPU Metal 协议叶；这些数字不等于完整出生、真实 GPU 发布、整帧 FPS、RSS 或 App 冷暖启动。

本机证据在 `d41-playback-validation/p13/behavior-validation.json`、`lexical-cost-v1/report.json`、`sphere-cost-v1/report.json`、`vertex-stream-cost-v1/` 与 `cost-window.json`。scanner 独立五源固定副本与最终源逐 SHA 相等；两其他成本沿完整固定源零漂移。没有把旧实现、计数或任务探针接回产品，球面旧 raw 半径字段与无人调用的 Stream Metal reserve 测试壳一并退役；新增长期 fixture 已登记最近测试路由。

完整优化 Debug 构建及严格签名成功，固定源前后零漂移；426.524 秒仅为构建成本。产品与测试的 14 路径仍与冻结清单一致，CodeHealth 1501 Swift 无超 1000 行文件，SceneDefense 棘轮保持。本批未安装、启动候选或修改设置；正式 App 原进程保留。完整 Release App 本次未重建，Release 算法成本与等价性由同 -O/WMO 无 DEBUG 片段证明；保留的 P12 Release 候选不包含 P13，不能冒充最新版本。作者画面、完整 App 冷暖入口及此前可选作者材料缺失仍未覆盖，不因本批 103 方法通过重授旧证据。

停止使用的首轮固定源和 P12 基线已按最终固定源保存可重建差异、原 manifest 及逐文件重建哈希；保留原失败日志、最终固定源、计数/计时输入和结果。任务探针二进制/模块、扫描器五源副本和冗余 Debug staged 副本退役，连续迭代只保留一份 DerivedData 和此前 P12 Release 候选，详见 `p13/artifact-retirement.json`。文档入口、正文预算和精确审阅身份同步当前事实。修改未暂存、未提交，Goal active。

后继优先做已确认的直接减工和误拒：模型上传直接消费既有不可变 ModelIR、合并 tight bounds 遍历，保 32 位输入可缩成 16 位的行为；MDL 的一概冒号禁令误拒合法相对材料名。Sound 的 ./、重复斜杠及入根 .. 同时被上层与通用查找挡住，须交原 Root 解析并保原索引别名、stock 与选根顺序；literalEntry 默认排 stock，不能一刀切替换或只删第一层。首次选择仅 invalidPath/symlinkEscape 局部拒本源；sourceChanged、invalidHandle 及取消即使发生在选择阶段也沿原事务上抛。shader Pair 临时复用只在 analysis/artifact 同时 miss 有收益，须保独立编译配置预算与 raw key，排在这些更直接的改点后。上述均仅完成只读裁决，未计为已实施；两引擎余项、随后全仓范围继续原完成条件。

### P14：模型上传与资源路径回归原 owner（回归、对照与 Debug 已过）

本批五个产品路径、三路并行：Pipeline/PreparedStaticModelResources 直接交已有 ModelIR；MDL Reader 去掉一概冒号禁令；Sound Program 与 ResourceView 合并真实路径选择。相比 shader Pair 横跨分析/编译 miss 的瞬时复用，本批先做每次模型上传的重复扫描和已证的合法作者输入误拒。最小结果是实际模型上传少扫索引/顶点、合法材料和声音路径可消费，原资源与 GPU 失败半径保持；不做另一解析器、许可、registry、缓存或永久兼容入口。

makeMesh 直接收同份 Reader 产出的不可变 ModelIR，退出重复的非空/三角形数量/索引范围准入；ABI 与实际 GPU 分配失败仍由 Pipeline 负责。当前所有顶点（包括未被索引引用的点）的 tight bounds 在原上传 owner 一趟求成，不用可能较宽的 authored bounds 替换。原 indexElementSize 为 2 已证明可窄打包，不再扫描是否有宽索引；原为 4 仍检查实际值并保留能缩成 16 位的行为。唯一产品 caller 改传原 part；所有旧接口的测试消费者迁到实际 ModelIR 输入，不能为测试保产品旧重载或另造“已验证”证书。真实 Reader→GPU 门核 65535/65536、32 位但小索引、大顶点数但小索引、未引用极值顶点、全通道字节与 tight bounds，保已有 draw/深度/阴影最近门。

MDL 路径首先删除单独的 contains(":") 判定，允许 POSIX 相对名如 materials/C:/paint.json；不新增 URI/磁盘前缀黑名单。完整 UTF-8/长度/结构解析和实际 VFS 入根仍归原 owner。两种格式及后续 material part、反斜杠等价和资源改名要走真实读取；保坏编码、绝对/越界、实际 symlink 逃逸等反例。其余路径语法是否重复由同一真实消费链继续裁决，不能把当前 Reader 限制重新定义为长期规范。

Sound 不再自己拆段拒 ./、重复斜杠与所有 ..，实际物理 .. 必须由原 Root 解释：missing/../file 不等于 file，指根外 symlink/../file 不能被字符串折叠偷换。沿已有 ResourceView 选择入口收拢索引引用与 literal 读取，保普通路径的 alias、大小写/exact、stock/assets 前缀及 package→loose→stock 顺序；原 literalEntry 默认作者文件语义保留，不全局放宽通用 strict normalizer。初次路径选择仅 invalidPath/symlinkEscape 只拒本条 Sound；sourceChanged、invalidHandle 及取消即使发生在选择阶段也继续上抛，已选 Handle 的读中硬错亦然，失败不换根，缺失/不可读仍保原 nil 播放槽位。方案以减少层级为准；若需要新增选择参数，只描述原入口的两种选择语义，不另包 Sound resolver 或错误 fallback 链。

验证先用真实 Reader/Root/OwnedFile 和 GPU buffer/draw 最近门，加入作者/资源改名、等价拼写及相邻不应命中反例；计数和优化耗时片段分开，任务探针不进产品。模型索引和 tight bounds 与原输出逐项对比，Sound 核成功 bytes/来源身份、选择失败局部与读中硬错/取消；不能只改 stub/path reason 便宣称恢复播放。三路冻结后交叉独审、固定源串行窗口、一次 Debug 构建与签名。本批不碰正式 App 或用户设置，不提交；完整作者视觉/整 App 冷暖的实际覆盖据执行结果单列，不提前宣称整仓完成。

实际减工对照使用同 -O/WMO、五个固定自有输入和六轮 AB/BA，只有 makeMesh 实现及其调用参数适配不同；共同 Format/材质/Metal 依赖沿 P13 基底，解析与 Pipeline 创建在计时外。32768 顶点、98298 索引的 16 位输入，实际分配、拷贝、tight bounds 与释放的每调用 wall 耗时中位数 0.4046→0.3360 ms（少约 17.0%）；其余四例少 10.4%–19.0%。计时不插产品计数，五例完整 CPU 可见 buffer 字节、索引类型、bounds 与消费值相等；实际 GPU blit 字节另由上传行为门验证。这不代表进程 CPU 时间、GPU 执行时间、用户输入分布、整 App 冷暖启动或 FPS。

声音路径实跑先暴露原 Root 的路径前缀混用：已有 Root 被 Foundation 标准化为 /tmp，缺失的 ./assets 候选仍保 /private/tmp，合法查询误报 symlinkEscape。仅让 literal 候选从同一已标准化 Root 追加原作者 path，不预先折叠 symlink/../；保原三项入根、Root 变化和实际 FD 检查。目录、虚拟包与真实 symlink 三模式的任务探针通过，最终冻结源的 17 项真实声音资源门也通过，包括默认 literal 的缺失 ./assets 返回 nil；不把此结果扩成全部引擎或作者画面。

P14 选定的 185 个方法全部通过、无跳过。覆盖两种 MDL 布局及后续 part 的合法冒号路径/真实材质消费，原 Root/Handle/包 revision，47 项声音 Program 与 17 项真实资源/私有 AV 资源门，模型 GPU 全字节/索引宽度/tight bounds，以及实际材质、发光、三类阴影、捕获/具名源、容量、深度、取消/完成租约。可选 App/作者材料门未纳入选择，不能把原生自有输入称为作者画面或完整产品入口验证。各轮原登记输入哈希无改写；已过且实际输入未变的结果复用，受影响的夹具重跑，失败历史完整保留，不能按尝试次数累加通过数。

原生门暴露的测试存量已按真实职责修通：补拆分后的 ResourceView/灯光源与 shader 头，不用新 stub 替代；坏模型不添加材质依赖的旧断言改为空闭包。自写模型顶点与作者 Y-up/world 转换不一致、派生夹具重复翻转、替换零命中和漏传可选 marker 字段均已纠正，保原颜色/alpha/深度/配额/共享源及生命周期断言。任务对照只把当前 makeMesh 的函数体换回 P13 完整旧体（两个局部别名适配新参数），相同原始 Harness/Metal/其他依赖下，120 组相机和 4 组快照全 JSON 相等，旧体也复现原失败；修正夹具后实际门通过。这是上传函数的回归归因，不是完整旧 App 的对照。只有实际消费 capture 计数的 Spot Named 方法显式用 DEBUG，未把整个门改成 Debug；无独立职责且重复拼声明的 Builder 支持 helper 已退出。

完整优化 Debug 构建及严格签名检查通过，424.008 秒仅记构建成本。构建冻结源与最终测试源之间只有测试/文档差异，全部产品、项目、helper 与构建脚本字节相同，因此复用这一次 App 构建；没有因后写结果文档重建。五个产品路径及最终测试适配独立复审无阻塞；CodeHealth 1504 个 Swift 文件达标，SceneDefense 棘轮保持。完整 Release App、作者视觉和整 App 冷暖首帧本批未重跑；P12 Release 候选仍是旧版本，不包含 P13/P14。正式安装 App 与用户设置始终保留。

本机结果归 `d41-playback-validation/p14/behavior-validation.json`、`model-upload-cost-v2/report.json`、`model-upload-native-control-v1/report.json` 与 `final-validation.json`。源码旧导出以逐文件哈希验证的差异可重建，原失败/输入/结果保留；停止使用的探针、模块缓存和重复 App 退役，连续迭代仅留当前固定源、一份 DerivedData 与此前 P12 Release 候选，详见 `artifact-retirement.json`。修改未暂存、未提交，Goal active。

后继仍按已证价值推进 shader normalization Pair 的同次复用、其他 MDL 路径语义与两引擎余项，再扩至全仓。声音格式能力筛选仍决定跳过首个不支持候选并选择后续 WAV，不能直接删除；扩展实际可播格式另需真实 decoder/选源语义证据。另登记存量 `test_scene_particle_simulator.py` 大文件：P14 未修改，早于此前单条旧断言删除即已超限，后续按自然 fixture 职责拆分，不作为本批新增或播放回归。全范围审查尚未结束，不据本批通过宣布再无问题。

### P15：同次 shader 归一化结果直接交给编译器（回归、对照与 Debug 已过）

Scene/Web 主链的已证余项继续落地，同时扩展 Video/公共播放链只读审查，不等待细枝末节无限收尾。本批先做 shader 在 analysis/artifact 同时 miss 时的同次重复归一化：既有 Coordination 已完整生成 Pair 却只取音频数组，实际 Compiler 随后再做一遍。相比再加持久缓存或把 route 失败变成许可，本批只让现有三个 owner 传递局部结果，不新增凭证、缓存、registry 或 schema；MDL 剩余路径与全仓候选先按真实消费者裁决，不混进尚未验证的能力承诺。

Coordination 的 computeAnalysis 沿原返回值携带 `(analysis, normalizedSources: Pair?)`，resolvedAnalysis 的持久命中只回原 analysis 与 nil Pair，miss 将本次 Pair 随原结果返回；分析表与 Resolution/Envelope 不存 Pair。ArtifactCache 只把该局部 Pair 交给既有 compile closure。Request key、raw authored source、color/ABI 验证仍消费原 BackendCanonicalizer compilerSources，不能把归一化 helper 当作作者输入。Pair 在该同步准备退出后释放；analysis 命中或 artifact 命中不因本改动新增归一化。

Compiler 仍先解析原 Bundle 配置；只有同次成功 Pair 才省第二次 normalize，且原两 stage raw 字节仍须符合实际配置的最大输入。route 默认 512KiB 与真实 compiler 配置不是同一上限：route 成功而 compiler 更小仍拒超限；route 超限/语法失败而无 Pair 时仍按实际 compiler 正常尝试，不将 route 失败升级为编译失败。归一化后输出沿原 compileStages 受实际输出上限控制，不以 raw 或 normalized 字节互相替代。Bundle 失败顺序、loop guard、反射/布局/链接及发布失败半径保持，不新增源身份重算或相同字符串认证。

验收沿真实 Normalizer、Coordination/ArtifactCache 与 Compiler 最近门，覆盖双 miss、analysis 命中、artifact 命中、暖 Resolution 命中、大小预算交叉、Bundle 失败优先、归一化输出扩张及真实 artifact/Metal 输出；输入改名和等价表达/相邻拒错保留。归一化次数和成本只用任务源计数/独立无计数片段，前后完整输出相等后才报告耗时，不能扩成全 App 冷暖提速。先独立复核三产品及测试，再固定源做一次 Debug 构建与必要原生回归；不触正式 App/设置，不提交。

同批补 MDL 的良性等价拼写误拒：只在原 readMaterialPath 的分隔符处理里去掉内部空段和独立点段，输出同一规范相对材料名，使现有 SourceFacts/Catalog/Descriptor/PreparedGeometry 直接匹配。保绝对路径、编码/长度、末尾目录意图及当前尚未接通的 parent 查询，不能把末尾 `/.` 变成同名文件。两种布局、后续 part、改名/反斜杠与包/目录沿真实材料/纹理消费验证，合法常规输入的 IR/GPU 结果不变。`..` 与材质内纹理路径的同类词法限制已确证，但要由原 Root 选择事实一路连至材料身份/种类与 GPU，另做纵切；本批不先删一层就宣布恢复，也不增加第二 canonicalizer。

扩展只读审查已实际追过 Video、SystemMedia 与 CoreAudio 的生产者/消费者。后继优先删 Release 无消费者的 rectifiedMono 整窗数组/归并（真实 FFT 只消费 signedChannels），再剥离 CoreAudio 设置 buffer 后仅供日志的 actualFrames 读回及 SystemMedia 的 report/lastStatus/字符串链。Video 另三项是普通视频进入旧内置素材迁移前的无谓路径解析/存在检查、频谱关闭时仍创建每屏 56 个子 CALayer，以及只供 Debug runner 的 launched/accepted IPC 与无读者请求镜像。这里只列为候选，尚未实施或计入收益；真实格式/采样率设置、授权、prepared/ready、播放代际/提交/退出 ACK 与频谱重启配置保留在原 owner。Artwork 已有 generation/需求缓存和增量传输，没有发现每次时间线重新 hash/解码，不能为凑减工破坏它们。

MDL 余项按实际作用登记：路径 4096 是有界扫描策略，parts 64 是加载/逐帧工作预算，均不是格式或 GPU 硬上限；控制字符还被下游 VFS 另拒。后继应沿真实 Root 选择身份/种类、Catalog 与 GPU 完成纵切，并审查每 part 重复材料查询；不能把旧常量叫安全必需，也不能只删 Reader 一层就宣布更多壁纸能播放。本批仍保这些策略，不新增另一套路径或资源 owner。

实际前后计数确认双 miss 的 normalize 2→1；分析已命中、仍需编译的分段 1→1，analysis miss/artifact hit 1→1，结构失败 2→2，实际 helper 编译的完整 artifact SHA 相同。计数探针分段直接调用 Compiler，不把它冒称完整 ArtifactCache.resolve 的四层缓存端到端计数；暖 Resolution 分支未变且位于 compile closure 之前，本批仅静态确认未新增归一化。成本用独立无计数 -O/WMO 二进制、八个运行时自有输入和六轮交替 AB/BA，所有 Pair/facts/raw key 与全字节消费值一致：173 字节 fragment 的每调用 wall 中位数 3.3784→1.9047 ms，60798 字节 fragment 571.2901→345.4238 ms；八例减少 39.5%–49.4%。范围为 analysis、必要 normalization 与共同 checksum，不含外部 helper、完整 shader 编译、Metal 或整 App 冷暖启动，不能据此报首帧提速。

59 个唯一选定方法全部通过、无跳过：28 项 MDL Reader/实际 Builder 材料 PNG 读取与原生资源/Metal，31 项 shader Pair/真实 helpers、独立预算、缓存修复、typed provider 与真实编译后坐标/伴随采样 GPU。模型 native 门沿原确定纹理 transport，不代替完整 TextureLoader 或作者画面；Reader 的 4 个、Builder 的 129 个和 native 的 114 个真实编译输入分别与合并源逐文件相等，因此复用三类门。首轮相邻 GPU 夹具漏带原共享门的 SCENE_GRAPH_TESTING，未取得已隔离计数，失败发生在 setup 编译阶段，未执行 GPU 方法；只补原测试条件，不恢复产品 Release 诊断，不删除 pipeline/像素断言。最终三方法复验通过，原失败日志保留。三产品/新门/探针及 MDL/补充测试条件两路独审无阻塞。

完整优化 Debug 构建及严格签名通过，433.151 秒只记录构建成本。全部产品、测试、项目、helper 与构建脚本沿最终冻结输入相同；只写结果文档和对应治理索引后不重建 App。CodeHealth 的 1505 个 Swift 文件及 SceneDefense 棘轮通过，本批 12 个产品/测试代码路径均不超 1000 行。未验范围仍是完整 Release App、本批真实作者视觉与整 App 冷暖首帧；旧 P12 Release 候选不含 P13–P15，不称最新测试 App。正式安装 App 与用户偏好保持原状。

本机汇总归 d41-playback-validation/p15/final-validation.json、behavior-validation.json、shader-normalization-cost-v1/report.json；两路独审分别绑定最终 shader 与 MDL/测试条件清单。停止使用的二进制、模块缓存、临时 HOME、复制工具包与本批中间源码导出已退役，源码仍由原 manifest 与逐文件哈希核准的差异重建；保留本批最终固定源、一份连续 DerivedData，前轮历史重建依赖的锚点保留，详见 artifact-retirement.json。未暂存、未提交，Goal active；下一批优先清掉音频/媒体 Release 无消费者的纯诊断开销，再继续 Video 与全仓审查，不据本批通过宣布全范围完成。

### P16：音频与媒体纯诊断工作归实际调试消费者（双配置回归、对照与 Debug 已过）

P15 已完成且保留未提交，本批选择共享音频/媒体的无消费者工作：相比还需实际路径/材料纵切的 MDL 余项，或有窗口/IPC生命周期影响的 Video 改造，先退役约 30Hz 重复的诊断数组，并清掉系统调用与媒体日志的 Release 空转，收益直接且职责可复验。Video 三项继续只读细化供后继，不能拿这些候选当已实施。

SystemAudioCapturedFrame 只携带真正分析消费的 signedChannels，rectifiedMono 字段与完整数组/逐窗归并在所有配置退出。首个有声 Debug 日志从本次相同声道按需求原整流均值峰值，不新增缓存、DTO、分析器或第二音频链；保持 Float 求和/除法顺序、阈值与原首次有声标记。这样不把已退出数据包成 Release 空数组，也不让 Debug 在已经记录后继续每窗工作。Factory 的真实 range、采样率、BufferFrameSize 设置和实际状态不变；仅 actualFrames 的纯日志读回进入原 Debug 分支。Service 的 scope、resource generation、连续环形 PCM、worker 快照、FFT/六组数组与静音屏障均沿原 owner。

SystemMedia 的 lastStatus、report 和全部调用/插值只在 Debug 存在；真实授权、PID/track/epoch、需求租约、系统 source 选择、清空、重试与 artwork 按需缓存维持，不删跨异步边界的当前身份判断。比保一个 Release 空 logger，更直接的是编译期撤掉调用点及其载荷。全仓其他检查仍须沿生产者/消费者裁决，本批不盲删真实权限、句柄或媒体格式边界。

验收沿真实 PCM/分析器、恢复/scope 与 SystemMedia/provider/Web/IPC 最近门，Debug 与 Release 运行同一组语义断言、完整有符号样本及公开频谱输出；已退役 mono 断言迁至实际 signed 输出，不能加空字段或伪造兼容值。CoreAudio 设置/读回仅在任务 I/O 边界统计，不能为门调用真实设备设置。Release 剥离应核真实编译输入/符号或输出，不能只检查日志字符串；保原 Debug 首次有声观察及源状态报告。任务片段单独对照完整输出与 -O/WMO 成本，不插产品计数、不声称整体能耗/RSS/启动提速；三路冻结后独审，一次必要 Debug 集成构建，若实际 Release 输入有变化补相称无 DEBUG 编译/门。正式 App、真实音乐/媒体与用户设置不动，不提交。

实际减工已由编译和执行分别确认：捕获帧两配置均只剩 signedChannels，旧 mono 字段/数组/整窗归并退出；Debug 首有声峰值保原运算顺序与阈值，已有日志后不继续计算。正常/Set失败的配置调用中，Release 纯日志 actualFrames Get 1→0，真实 range Get 和 Set 均维持 1；无效 rate/range 或 range 读取失败仍不设置。任务源只将原 Factory 的两属性 I/O 名称重定向，不调用真实设备配置。Media 的 raw SIL（-Onone、优化前）中，Release 不再有 lastStatus 存储、report 声明/调用及状态插值，Debug 正控制仍具备；不是仅用 NSLog 字符串缺失证明，也未用空 logger 隐藏载荷。

40 个唯一方法通过、无跳过。原媒体 Service 的 33 个方法在两配置均执行原语义断言，覆盖授权、来源/曲目 ABA、需求撤销、迟到回调、清空、重试、订阅租约与 artwork 转换；两臂 PASS 一致不表述为全部异步 snapshot 逐字相等。音频门实际比较双配置完整 signed 位模式、六组频谱及连续环形窗/独立快照，恢复门保 scope/配置/迟到资源拒绝。四产品及 owner 测试、任务探针和两个隔离门独审无阻塞。

片段成本使用完整旧/新 Buffer、同一未改 Analyzer 和同一 -O/WMO wrapper，不插计数、不读取旧 mono 强迫它保活，允许编译器自行消除无用工作。4 种 4096 帧双声道 PCM、6 轮交替 AB/BA 的每调用 wall 中位数：Float32 交错 20.967→17.481 微秒，Float32 平面 20.918→17.375 微秒，Int16 22.027→18.282 微秒，Int32 21.770→18.427 微秒，减少 15.4%–17.0%。完整 signed 字节与独立 Python oracle、六组频谱位模式、暖身/计时消费值逐臂相等才接受结果。计时是 decodedFrame 与共同 checksum，append、FFT、设备采集、App、RSS 和能耗均不在此片段内；移除一份 16KiB 逻辑数组不等于进程内存实降。

完整优化 Debug 构建和严格签名检查通过，407.549 秒只记录构建成本；全部产品、测试、项目与 helper/build 输入保持冻结，后写结果与治理索引不要求重建。CodeHealth 的 1506 个 Swift 文件通过，本批 8 个产品/测试代码文件均不超 1000 行。无 DEBUG 的真实音频/媒体门、原始 SIL 与恢复 Release 编译已覆盖本次剥离；完整 Release App、真实音乐/作者画面和整 App 冷暖首帧未重跑，不以片段结果替代。上批登记的六项中，本批完成三类共享诊断减工，Video 三项仍待实施；旧 P12 Release 不含 P13–P16，不能作为本批候选。

本机结果归 d41-playback-validation/p16/final-validation.json、behavior-validation.json 与 audio-buffer-cost-v1/report.json，两份独审绑定精确源码/探针清单；中间导出由 manifest/逐文件哈希差异重建，停止使用的二进制、模块缓存和临时 HOME 当轮退役。保留本批最终固定源、一份连续 DerivedData 和先前证据仍依赖的历史锚点，清单见 artifact-retirement.json。正式安装 App 与真实媒体/偏好原状保留，无暂存、提交或主仓库修改。Goal active，后继按已证 Video 最小职责继续，再扩散全仓余项；本批通过不代表全范围审查结束。

补充只读复查又确认音频后继候选：完整、连续、有限的 capture frame 到 Analyzer 后仍有第二次整窗 finite-map/复制/rolling，且没有独立产品 raw/partial 消费者；后继须收口原入口与真实测试输入，保 callback→worker 快照、时钟、格式重置、Double DC、padding 和 FFT 数值外溢。成品 64 带的多次重采样/Overlay 重复 finite/clamp，以及无 Scene 消费者时的 eager 16/32 投影也可沿原 Levels 按需派生，不新增缓存。入口支配的重复迟到判断和已完成幅度的 finite 小项排后处理。这些只是已证调用关系的候选，尚未实施或计入本批收益，详见本机 audit-audio-followup.json；全范围仍按实际消费者继续审查。

### P17：Video 首启按需准备与诊断 IPC 退出 Release（回归、减工对照与 Debug 已过）

P16 已完成双配置减工，本批先闭合已证的 Video 三项：普通库条目不应为旧内置素材迁移先查真实文件；默认关闭的频谱不应在每屏 helper 首建时生成 56 个子层；launched/accepted 事件与只供 Debug Runner 的父端镜像不应由 Release 编码、投递和存储。相比继续扩大音频 DSP 改造，这三项 owner/消费者已清楚且直接涉及库加载或 helper 启动，三路并行实施后交叉审查。音频完整窗/频带余项继续保留为后继，不据本批关闭全仓目标。

旧素材迁移仍由原 BundledVideoLibrary.migratedURL 唯一识别：先用原标准化 URL 核旧文件名与 .app/Contents/Resources 形状，只有真实旧候选才沿原 raw path resolvingSymlinks/存在检查，且仅缺失源才能触发原 lazy prepare/videoURL。Manager 移除前置 normalizedSourcePathExists，保全部记录元数据及原缺源扫描。普通路径、现存旧源/符号链接和相邻不匹配路径不能触发解包，不引入 classifier/cache/新迁移 owner；归档签名、staging、替换及失败语义不变。

频谱只延后首次 materialize：setup 仍挂原容器，空 bar 数组是未建事实，不新增 flag。首次启用前配置/resize 只维护当前值，实际启用沿原 rebuild/layout 并恢复已接纳 levels；首次后的重复启用、count 改动、关闭 0.18s 淡出、峰值与重启生命周期保原路径。不能每次关闭就销毁子层，也不能首次建层把 pending levels 清掉。原 play 的 configuration→enabled→levels 顺序、共享采集需求和实际渲染均保持。

Video helper 的 launched/accepted 发端与父端对应镜像/处理只在 Debug；DTO/线格式不改，Release 沿原 default 忽略意外诊断事件。latestPrepared/latestCommitted 等零读者字段退出全部配置；真实 execution.requests/nextRequestID、latestFinalized、prepared/ready/failed/cancelled/activity ACK、代际和物理退出不变。同一已触 owner 内的零读者 resizedSpectrumLevels 可直接退役；currentActivityID 若全仓确认无读者则连同赋值退出，命令 activityID 存在与 ACK 关联仍保留。不能给 Release 留空镜像或用启动观测当播放准入。

验收走真实 Bundled 准备/迁移与 Manager 元数据、原 helper AV 双槽和新增真实 CALayer 生命周期、父端 typed switch/取消/延迟退休/assembly，以及 Debug/Release 实际 helper 事件。先核 count/实际对象、已选数据与 payload，成本探针不进产品，不把少 56 个层或少事件直接叫整体首帧提速。已接近 1000 行的父端门若需演进，可将完整独立可执行 Harness 自然归 fixtures，以复用真实双配置门，保持原断言与输入字节；不造产品兼容字段。三路冻结并独审后固定源、共享锁串行运行，一次必要 Debug 集成构建，Release 用实际无 DEBUG 门证实剥离；不改正式 App、真实媒体或偏好，不提交。

实际前后工作量对照已完成：同一组 1006 条普通记录的 resolvingSymlinks 与 fileExists 调用各由 1006→0，迁移后的记录逐项不变；现存旧源和活符号链接各仍为 1 次，且两臂均不触发 lazy prepare。计数只在任务源副本观察原调用位置，不进入产品；这是 API 调用次数，不是系统调用数或耗时。缺失旧源、坏符号链接、相邻不匹配路径、等价路径、无压缩包与包稍后出现的真实准备，以及全部元数据和持久化次数另由真实 Bundled/Manager/Model 门执行。

完整真实 helper 的 -O/WMO 前后对照中，默认关闭频谱的 bar/peak/总子层为 28/28/56→0/0/0，两臂原容器均已挂载；新链不为未建立的层推进 presentation clock。当前有/无 DEBUG 的真实 helper 均通过首次启用、pending levels、实际 CALayer 高度/颜色/当前布局、暖对象复用、0.18 秒淡出、caps、静音清零及柱数/resize 行为。stdout 的 launched/accepted 在 Debug 各出现 1 次、无 DEBUG 均为 0；两配置实际命令失败仍带 request/cohort/generation，活动 ACK 保精确 activityID，并拒绝缺失 ID 与旧 request。父端使用真实 Session 声明与实际 NDJSON 分帧/事件消费，核无 DEBUG 无四项诊断存储，prepared/ready/取消/失败/ACK 及实际 execution 身份继续执行。

15 个唯一行为方法通过、无跳过，重跑和编译配置不重复计数。原 AV 双槽、生成短片实际解码/暂停首帧、准备失败保留已提交 item、跨淡出迟到清理、真实窗口可见确认/回滚、父端切换/停止及受控进程退出回调的退休屏障、索引有序保存、频谱 seed/差分及 play 载荷和 IPC 分帧均有最近门。原生短视频使用显式任务根传给夹具，避免 Foundation 忽略 TMPDIR；旧轮唯一 UUID 临时文件已由 defer 删除。真实用户媒体和偏好没有参与写入。

首轮两处旧夹具在 setup 编译时暴露漂移：停止反例仍用已被真实 Session 替换的便捷构造，频谱设置门还持有混合播放列表合并前的请求/恢复接线。只修改夹具：停止反例接真实 Session/受控 transport；频谱门复用真实 Sequence/Admission/request/dispatch/Manager prepare，provider/native IPC 保原记录叶。已退役的 restore 回调和其假计数删除，直接验证配置后真实 play 字段及实际两次配置只 seed 一次；本门不声称 Workspace 启动恢复集成。保留原失败日志，只重跑受影响或尚未执行的门；其余已过输入不变的结果沿冻结清单复用，未给产品增加兼容字段、wrapper 或旧入口。

完整优化 Debug 构建和严格签名检查通过，501.818 秒只记录构建成本，不代表播放启动耗时。构建使用固定 v4 源，后写结果文档和治理索引不改变任何产品、测试、项目或 helper/build 输入，不为结果文字重建 App。CodeHealth 的 1508 个 Swift 文件通过，本批 16 个产品/测试代码文件均不超过 1000 行。产品、真实层/AV 夹具、迁移/计数探针与修正后的 owner 夹具均有绑定精确源码的独立审查，无阻塞。完整 Release App、真实作者壁纸全量兼容、整 App 冷暖首帧、RSS 和能耗未重测，不能用少对象/事件或构建时间替代这些结果；旧 P12 Release 不含 P13–P17，不能作为本批候选。

本机汇总归 d41-playback-validation/p17/final-validation.json、behavior-validation.json 与 work-counts-v1/report.json，失败和复验日志均保留。停止使用的二进制、临时 HOME/模块缓存和中间源码导出当轮退役；导出仍由原 manifest 与逐文件哈希差异重建，最终固定源、必要历史锚点与一份连续 DerivedData 保留，详见 artifact-retirement.json。正式安装 App、用户偏好和主仓库未修改，无暂存或提交，Goal active。

后继按价值继续收口原 owner：共享音频完整窗仍有第二份 finite-map/copy/rolling，16/32 带投影可按实际 Scene 需求派生；Video CachePipeline 和 Steam 缩略图同一次请求仍重算已捕获的路径/缓存键，原局部值即可传到原 helper，不引入另一缓存。真实原始边界、当前文件身份、worker 快照、scope/时钟/FFT 数值出口及代际仍须保留。Video 首播重复赋值/窗口操作与零调用动画函数记低优先余项。上述均为只读已定位的候选，尚未实施或计收益；依据归本机 audit-next-audio-v1.json、audit-next-library-v1.json 与 review-helper-v1.json。两引擎和全仓还会继续沿消费者审查，本批结算不宣称目标全部完成。

### P18：完成帧直达频谱分析、按需频带与请求内缓存键复用（回归、对照与 Debug 已过）

P17 后先闭合三项已有实际消费者证据的重复工作：共享音频完整窗的第二次扫描/复制和无需求投影，以及 Video/Steam 缩略图同一请求重算路径/键。低频窗口赋值、零调用动画及 MDL 能力政策继续按价值排后；不因本批结束宣布全仓审查完成。本批改动 7 个产品文件，沿原 Analyzer/Levels、Manager 与 Steam pipeline 实施，没有新缓存证书、可信入口、wrapper 或生命周期 owner。

音频退役 raw/partial analyze 重载、第二份 PCM rolling history 及逐窗 finite-map/suffix/copy，真实部分回调语义回到唯一 CaptureBuffer/ring。Levels 仅持左右 64 带，Scene 实际读取时派生 16/32；Overlay 消费同份成品并退出重复 finite/clamp，先立体声均值再投影的数值顺序、灵敏度和风格不变。原始格式/字节边界、非有限输入处理、worker 快照、processingGate、scope/generation、capture clock、格式重置、Double DC、padding 和 FFT 数值出口保留在原消费点。长期职责归[共享音频设计](../architecture/system-audio-spectrum-design.md)。

完整实际 Buffer→Analyzer/Overlay/Web 的四类 PCM、三采样率共 12 组输入，signed bits、全部六组频谱及两路投影逐位相同。相同 -O/WMO、6 轮 AB/BA、每组 48 个计时窗：仅 Overlay/Web 时，12 组各自中位数的中位数为 32.313→16.431 微秒/窗；Scene 同读六数组时为 32.926→17.102 微秒/窗。各组配对比值中位数分别 0.499/0.519。计时含实际需求投影和相同 checksum，PCM 解码在计时外；这是本机分析片段成本，不能替代整 App 首帧、采集成本、RSS 或能耗。

Video 在原请求内复用一次 normalized path/key/output，resolved 的内存/磁盘分支复用同次 key；旧 URL-key/output 重叠 API 与实际 StaticFrame/Removal 调用一起迁移。独立请求仍重新解析。真实完整 generator、相同 H.264 短片/运行路径/-O/WMO 前后共 22 项行为及首张 JPEG 字节一致：三次冷请求的路径规范化 11→3、键计算 8→3；内存命中 2/1→1/1；磁盘命中 4/2→1/1；resolved 磁盘查询 2/2→1/1。上述是原函数/API 调用数，不是系统调用或启动毫秒数。别名合并、重定向后的新请求、丢失输出修复、失败、generation/清理迟到结果、原两许可并发和正常回调主线程一次完成均通过；clear 仍沿原语义撤回已经注册的回调，夹具等待旧队列排空后才重请，未新增竞态保证。

Steam 入口捕获的新鲜 metadata key 直接用于原 memory/inFlight/failure/disk/persist，同次 private helper 消费同一 outputURL，下一独立请求仍查当前文件。真实冷/新进程磁盘/源变更三组门的 16/5/8 项检查通过，包括生成期间 mtime 变化、后续 inode/size 变化、坏媒体、负缓存、原串行后台队列与一次主线程完成。相同 H.264 的冷请求序列中，键与 metadata API 各 11→6，前后生成 JPEG 字节相同；比较保留原 12 项功能断言，基线未满足的“每请求只查一次”是减工目标，未伪称旧行为检查全绿。源在请求中途变化不是新增的原子文件快照保证。

最近 9 个模块中选定的 61 个独立测试方法通过、无跳过；双配置分支和重试不重复计数。普通 Debug 集成构建与严格签名通过，91.448 秒只记录构建成本；优化片段另以 -O/WMO 对照，不把普通 Debug 当 Release 测速。构建后只有测试/证据及结果文档变化，App 产品、项目、helper 与构建输入未变。1510 个受管 Swift 的 CodeHealth 通过，本批 18 个产品/测试代码文件均不超过 1000 行。三路冻结实现与最终夹具/探针经交叉独审，无阻塞。

验证中修正两类测试接线/材料问题，均未放宽产品边界或图像断言：400 样本的噪声块应沿真实 ring 连续拼窗，前 10 块无帧、后 14 个完整窗继续原阈值；原 testsrc2 MPEG4 在本机 AVFoundation 生成整绿 JPEG，ffmpeg 解码同文件正常，改前/改后 JPEG SHA 和四项图像失败完全相同。H.264 彩色素材在相同真实 owner 下通过，最终 Video/Steam 测试及计数均统一该输入；Steam 补已知彩色素材的颜色结构和纯绿/纯灰反例，避免仅尺寸正确就算图像正确。MPEG4 兼容问题仍未修，也未确定具体解码器原因，不能把更换夹具写成产品修复。

本机证据归 d41-playback-validation/p18/final-validation.json、各固定源门、audio-analysis-cost-v1、video-request-counts-v1、steam-thumbnail-counts-v3 和 video-codec-diagnosis-v1。保留最终源、哈希可重建的中间输入、失败/最终日志及必要图像；已停止的二进制、模块缓存、临时 HOME 和媒体副本按 artifact-retirement.json 逐项退役。连续 DerivedData 仍只留任务原一份。正式安装 App、真实媒体/偏好及主仓库未改，无暂存/提交。完整 Release App、当前合并 App 真实作者壁纸、整 App 冷暖首帧/RSS/能耗未重测；旧 P12 Release 不含 P13–P18。

后继继续核实 MDL 准备期每 part 对全部 material passes 的重复规范化/查找，优先原 prepare 内局部 first-wins 索引。Reader 的 4096 路径/64 parts 是可能误拒合法输入的政策，不是后端寻址硬上限，须完整 Root→GPU 纵切，不只改数字；控制字符被两层拒绝，单删 Reader 无播放收益，暂缓。旧工坊目录建记录时，即使已有 project/metadata/pkg 仍 eager 预扫 HTML/视频，后继优先核原 guard 短路；同次新 Steam 预取重复读取 videoURL 可再复用局部值。StaticFrame/Removal 的路径/键余项、Video 首播窗口操作及低收益 Inspector 提示重复投影继续按实际消费者排序，细项归本机后继审查记录；没有把只读候选算作已实施。Goal active。

### P19：旧库发现按需短路、模型材料准备单次索引与 Video 首播重复工作退役（回归、减工对照与 Debug 已过）

P18 的实现、61 方法、值/图像/工作量对照、Debug 和独审已完成。本批优先原 owner 内可直接删除的真实工作：旧工坊候选目录已经有 project/metadata/pkg 时不再预扫 HTML/视频；MDL 准备按实际 geometry 需求增量建立局部 pass-zero first-wins 查找；Video helper 退役每次 play 重设 init-only window/gravity 及同次提交的重复状态/窗口发布，并清掉没有调用的旧动画家族。相比 MDL 64 parts/4096 路径能力政策和 StaticFrame 跨延迟语义，这些减工无需新能力策略或长期状态，优先闭合；不能把死代码删除计作运行收益。

LibraryRecords 只让现有 preflight 按原顺序短路，不删除整个候选存在边界；真正 preferred HTML/video、依赖、最终可用性、ghost suppression、当前来源/scan generation 均走原链。MDL 局部索引在原 prepare 内使用已有 SceneVFSAssetPath 和原数组的局部单调 cursor；首次实际 geometry 查询才向前扫描到所需项，沿途保每个路径第一个 passIndex==0，后续命中直接取值、不重扫前缀、不访问未需尾部。这样单个早命中仍只看原前缀，空/坏模型不建全表，避免用 eager 全表索引把小场景做慢；非法路径、后续 pass、重复别名和局部坏纹理维持原选择与失败范围，不预建纹理、不缓存动态资源、不另持 owner。Video 保初始化的实际黑底/不透明/层、display/frame 更新、fill-mode 几何动画、唯一提交点的 activation level/orderFront、取消回滚和可见证明；仅删被同栈或 init 支配且没有其他 writer 的操作，prepared-event 路径回声与 StaticFrame 余项不混入本批。

验收比较真实 installed-record builder 在 project/metadata/pkg、HTML/video-only、空/ghost、优先入口和依赖场景的输出与预扫调用；模型沿实际 prepare/native 小模型核 pass-zero first-wins、规范化别名、拒绝/缺失局部化、现有材质/颜色/alpha/depth 边界；Video 走实际 helper 的首次/动画切换、取消回旧槽、fill mode 和 display 几何。任务探针只在源副本观察实际调用并先比输出，不向产品加计数器。三路冻结后交叉复审，固定输入、共享锁串行最近门和一次必要 Debug 构建。本批原生/构建沿共享锁串行，与 UI 专项协调后仅执行不抢前台的隔离门，保留其用户验收 App；正式 App、真实媒体/偏好、主仓库和 Git 提交不动。


实际旧库 builder 两重载在同一物理目录树上比较 21 组记录，初始及删源后的全部 24 个存储字段均相同，22 项语义和 9 项减工检查通过。初始 project/metadata/pkg 的 exists API 次数为 24/24/24→24/11/8，HTML/Video resolver 44/42→26/23；删源后为 25/25/25→25/12/9、45/44→27/25。计数包含真正建记录所需的后续入口解析，未删除实际 preferred entry、依赖或可用性消费；这是函数/API 入口数，不是系统调用或启动耗时。

实际 MDL prepare 的 8 种输入中，材质/纹理像素/几何及请求次序相等，14 项选择语义通过。64 parts 且前有 1024 个未用 pass 时，候选访问 67616→1088、路径构造 67680→1152；逆序 64 parts 加尾部时为 2080→64、2144→128；16 层各 8 parts 为 131648→1032、131776→1160。单个早命中维持 1 次访问/2 次路径构造，单个晚命中维持 1025/1026，空、缺失和坏模型均 0→0。索引只在本次 prepare 存活，不称 RSS 实降或完整渲染提速，也不扩大当前 parts/path 能力政策。

Video 的相同完整 helper 夹具在两臂执行全部原生命周期断言和 9 项真实窗口/层/动画/解码与 resize 事实；新旧事实和原频谱事实相等。整段序列的四类固定 window/content 属性各 5→1，gravity 10→2，path/request 各 14→7，activation level 12→7，orderFront 14→9。以上是实际 setter/赋值入口数；零调用旧动画家族退出不计运行收益。原共同提交、动态 fill 几何、AV 可见准备和取消回滚仍由同一 owner 执行，没有新增可信入口、认证、缓存或 wrapper。

8 个选定单元、19 个唯一测试方法全部通过，无跳过；包括 MDL 原生材质/颜色/alpha/depth/shadow/配额/源快照、旧库/HTML/重载合并，以及 Video 的真实 WindowServer 可见性与回滚。失败均保留并明确修正：相邻 Shell 旧测试补提取当前真实 navigatePage/DirectoryReturnContext（未加产品兼容层）；根驱动一个类名改为实际现役类；新 Video 动画断言在 Debug 通过而 Release 失败，具体失败子项无旧分解记录，只证实原夹具未同步产品读取的 presentation frame。夹具显式提交并有界等待真实布局、保留原动画/request/level 断言后，两配置通过；不把测试同步写成产品 bug 修复。三路产品与最终夹具均交叉独审，无阻塞。

下一项优先完整 Root→GPU 关闭 MDL 64 parts/4096 路径的能力误拒；它们是策略而非格式/GPU 硬上限，须保持真实字节、索引、ABI、累计几何预算和实际分配边界。旧库依赖 host 重复完整记录投影、Video prepared-path/StaticFrame 同次工作、低收益 Inspector 投影与更广全仓审查继续按实际消费者核实，不能只因类型就删掉 video/HTML 字段：图库封面/主题回退和依赖宿主仍有真实使用。P18 登记的本机 MPEG4 AV 绿图未修；完整当前 Release App、作者壁纸、整 App 冷暖首帧/RSS/能耗未重测，不据局部计数宣称整 App 快多少。Goal active，改动不提交。


普通 Debug 集成构建及严格签名通过，84.371 秒仅记录构建成本；App 未安装/启动，保留连续任务原一份 DerivedData。1512 个受管 Swift 的 CodeHealth 已通过，随后仅改两项测试接线/同步及结果文档；本批 11 个产品/测试代码文件均不超 1000 行。构建冻结源与最终输入的 App 产品、项目、helper 和构建工具逐文件相等，因此不因文档/测试修正重复构建。最近门与独审收据归本机 d41-playback-validation/p19/behavior-validation.json、comparisons-v1、debug-build-v1/build.json 及 final-validation.json；停止使用的二进制、模块缓存、临时 HOME/样本和中间源码导出按 artifact-retirement.json 退役，保留最终源及哈希可重建的必要输入。无暂存/提交，主仓库与 UI 用户验收 App 保留。


<a id="p20-mdl-policy-retirement"></a>
### P20：退役 MDL 部件数与路径长度政策，保真实资源边界（CPU、材料/GPU、前后对照与 Debug 已过）

P19 已完成并保持未提交。本批优先移除会误拒可播放模型的 64 material segments 和 4096 path bytes 两项政策；相比仅省低频 Video 赋值或还需拆分完整行投影的依赖宿主，这一项直接补齐合法内容的读取/材料/GPU 链。不是提高常量：删除原 Reader 的两个私有上限、对应 count guard 与零生产者错误类型，NUL 搜索只由当前借用数据的实际剩余范围界定。原版本/profile/stride/index/UTF8/NUL/完整 trailer、累计 vertex/index bytes、实际 Root 选择/文件边界与 GPU 预算仍由原 owner 执行，不新增许可、缓存或第二解析链；read(data:) 的单模型接口及未支持的旧 profile multipart 不随此放开。超大完整输入的 CPU/对象/绘制成本仍需实证，不把 65 部件通过称为无限规模响应保证。

验收分开报告原合法输入无回退与新合法内容恢复，不能把改前拒绝算作提速。Reader 两布局覆盖超过 4096 的点段/分隔等价长拼写、Unicode/改名，以及现代完整 65 部件；原截断、无 NUL、无效 UTF8、后段坏索引/非有限、累计字节预算仍拒绝。实际 Builder/Root 验所有 65 材质依赖和真正超过 4096 的浅层 PKG 虚拟材质名（纹理保持短路径，避免物理文件名上限），保选中坏包不偷换 loose、根外符号链接等最近反例。原生门把现有完整 NATIVE_MAIN 自然迁到单个 Swift fixture，实际 Builder 主程序同样完整迁到其独立 fixture；两类程序因现有 DTO 载体不同，以同树当前 Root 的真实材料/PNG 与 canonical pass 字段显式交接，不另写 Builder 算法。统一测试画布高度和采样点，首 64 颜色保持并给第 65 个有界独立颜色，peer/overlap 独立字段；真实 prepare→主通道两帧读回每个部件并覆盖最后部件 cast/非 cast，保全部既有 alpha/depth/shadow/配额恢复/源快照断言。原确定纹理 transport 的边界必须如实注明，实际 Builder 的 PNG/材料读取另验，不冒称完整 TextureLoader 或整 App 作者画面。

三路分工：Reader/CPU、完整 parts 夹具/Builder/GPU、根集成及独审；修改前固定 P19 最终源，冻结后交叉审。源码相同的原短样本前后值/像素对照，新 65/长路径单列能力变化，随后必要 Debug 集成构建；无关全门不重跑。依赖宿主投影和 Video 队列后来源重读只读候选继续保留，不混入本批产品代码。正式 App/媒体/偏好、主仓库和其他会话的用户验收窗口保留；共享锁串行编译/原生，改动不提交。达到真实纵切和对应反例、独审/文档同步后结束本批，Goal 继续覆盖全仓余项。


Reader 已冻结并通过 19 个 CPU 方法、无跳过；同一 -O/WMO 真实 Reader 在 201 组字节输入及非零 Data slice 下比较，原合法 36 组的完整既有 JSON 投影相等、新合法 13 组恢复、坏输入 152 组仍拒绝。投影覆盖所有 part 的材质/索引/源索引宽度/位置，normal/tangent/UV/bounds 等只覆盖首 part；不称全 part 全通道逐值相等，原 readVertices/readBounds 方法未变，真实 native ROI 另验。15 个原被政策先挡住的坏输入现在报实际字节/索引/编码错误，具体差异保留；没有因旧错误分类要求恢复已退役 policy。普通 Debug 与严格签名已通过，82.710 秒仅为构建成本；当前 App 未运行，材料/GPU结果如下。


实际 Builder→Root→native 的同树交接与两帧 Metal 读回已过：65 部件、Unicode 改名和等价拼写均保全部 65 个材料依赖、mesh 与独立 ROI，画布高度 144 保最后一行真实可见；第 65 部件与其余 64 部件均通过 directional depth 的 cast/非 cast 反例，原三影型、alpha/depth、局部材质失败、配额前缀/恢复和源快照仍通过。长点段原拼写超过 4200 字节归同一短材料，浅层 PKG 的规范 Unicode 材料名本身 4115 字节实际读取并出图；选中坏包 JSON 不转 loose，坏第 65 段不发布该模型，健康 peer 仍绘制。实际 Builder/Root 读取材料 JSON 和 PNG 字节，native 再开同树当前 Root 核材料字节并消费显式 pass 字段；纹理/标量仍沿原确定 transport，不称完整 TextureLoader 或 App 内同一内存对象交接，更不称完整作者/官方画面。

共 52 个唯一选定方法通过、无跳过：Reader 19、实际 Builder/native 16、PackageBacking 16、Handle 1。原 P19 已执行 native 记录的 119 个源/依赖字节不变，只有 Reader 政策变化；旧 18 组 fixture 的协议输入及期望相等；testSources 作为来源元数据另行绑定，不纳入等值比较。核两端实际 input root、修后 source-identity 和完整已执行 Harness 与固定源后，13 个旧模式的全部 64 格、peer/overlap、两帧与原存储事实逐项相等，basis/attachment/first-wins 邻例也相等；没有为形式重编旧 GPU 臂。新增 65/长路径单列为从拒绝到成功的能力变化，不能算提速比值。Reader、Builder/Root、native/oracle 三路独审无阻塞；比较脚本补齐实际执行 sidecar/Harness 绑定后再执行，未改产品或放宽断言。

1514 个受管 Swift 的 CodeHealth 与 SceneDefense 通过，本批 5 个产品/测试代码文件均不超 1000 行；两完整测试主程序自然迁至 Swift fixture，没有产品新 owner/API、缓存或许可。App 产品/项目/helper/build 输入自一次 Debug 冻结后不变，之后只有测试/结果文档及其治理索引，不重复构建。已同步唯一模型准入合同及两份能力摘要，覆盖总表指向当前 P20 产品构建；原 RF16 历史 5/8 App、64 native 证据保持历史身份。材料/原生门与构建窗口已明确交还 UI 专项，其用户验收 App、正式偏好/媒体和主仓库未动。

本机结算归 d41-playback-validation/p20/final-validation.json、reader-semantics-v1、existing-native-comparison.json 及固定源门；保留必要结果/失败、最终源和逐文件 hash 可重建输入，停止使用的编译器输出、临时 HOME/模型/媒体及中间源导出按 artifact-retirement.json 退役，连续 DerivedData 仍仅原一份。P18 合成 MPEG4 的旧 AV 绿图仍未修，当前完整 Release、真实作者合并 App、整 App 冷暖首帧/RSS/能耗仍未重测。后继优先补当前 App 代表运行与基线，再处理依赖宿主的无消费者行投影、StaticFrame/Removal 同次重复工作及全仓余项；不因局部绿门宣布全范围完成。无暂存/提交，Goal active。


<a id="p21-app-startup-verification"></a>
### P21：当前 App 实际播放与冷暖对照（功能通过，未接受稳定提速）

本批不改产品代码，以同步主仓的 `8f71545d` 对比当前未提交 P10–P20；更早已合入的减工不计本次收益。两臂固定源码、同一 Debug `-O/WMO`、独立 Startup 身份与标准域 token/private suite/HOME、30 FPS；各 3 轮交替 C0/C1/W0。C0 仅新 HOME/测试偏好，未清 OS/WebKit 或样本旁已有 Web analysis，输入 hash 在启动前也会暖磁盘。计时从产品选择入口到 Scene 真正 presented/父端 finalize，Web 到实际 session commit，均不含主 App exec 前缀，也不冒称 Web 物理首屏。

首轮各 App 的中位数如下；Web W0 先取每 App 6 次暖选择中位，再比较 App，不把同进程样本冒充独立重复。配对差是每轮候选减基线的中位，负数才较快，不能以两臂中位数之差代替。

| 类型 / 条件 | 基线 App 中位 ms | 候选 App 中位 ms | 配对差中位 ms |
|---|---:|---:|---:|
| Scene C0 | 1573.0 | 1580.6 | +6.1 |
| Scene C1 | 777.3 | 897.8 | +118.9 |
| Scene W0 | 212.7 | 227.0 | +9.2 |
| Web C0 | 862.5 | 861.9 | -11.1 |
| Web C1 | 886.4 | 886.0 | +3.9 |
| Web W0 | 315.7 | 322.8 | +5.1 |

首轮 Scene C1 三对均慢，不能跳过。仅因此追加一次相同两 App/输入/口径的 3 轮确认：C1 三对差为 -29.828/-9.971/+21.952 ms，中位 -9.971 ms，原退化未复现；C0/W0 配对中位差为 -340.263/-0.351 ms。两轮完整保留、分开报告，不混六对追绿。当前结论是未证实稳定整段提速，也未证实稳定产品回退；不能把第一轮的较快基线或第二轮的较慢基线挑出来宣称成功。已观察主差异集中在 accepted 之前；同 PID 的 child AppKit begin/return 仅夹 NSApplication.shared，可作局部 inclusive wall-time 线索，不能证明 CPU 根因或归咎校验。

连同补充 3809618616、Dashboard 以及含 100 个 authored text 的 Pixels、Tropical 父子粒子、Ahri Puppet 单次产品入口和 Scene→内置 Video2→Scene，实际共 64 次主 App、121 次选择（Scene 57/Web 63/Video 1）。全部主时钟、首呈现/提交、跨链资源退休及最终自有进程退出通过；Video 屏障证明旧 Scene 资源槽退休，不要求当时杀掉可复用进程，最终 shutdown 后才核物理退出。输入/正式偏好指纹不变、两臂签名/源快照一致，主计时与驱动/实际报告独审无阻塞。文字/Puppet 样本到首帧不等于全部层/裁剪像素验收；Web 实际覆盖 standard/customScheme/workshopPersistent 与 highCompatibility/httpLoopback/scopedPersistent，不据此升级音频、完整视觉、长跑或 Release 结论。

发现两臂共有的小诊断缺口：同步 preparationReceived/processStart 早于测量对象绑定 ticket/epoch，prefix observer 丢弃这些事件，组合 child report 因此 invalid；主 presented/finalized 自有身份与时钟独立通过，不受影响。保留原失败字段，不补假前缀、不改产品加诊断层；局部 child 自报须独立核当前 PID/hello/六时间顺序后才使用。后继先根据真实成本处理仍有消费者证据的依赖宿主行投影、StaticFrame/Removal 同次工作、SIL 原生负缓存和全仓余项；初始字体/Puppet 可见门及当前 Release 仍未关闭，不因局部计数或本次功能通过宣布 Goal 完成。

本机入口为 d41-playback-validation/p21/results-summary.json、各原 report 与独审；计时已结束并归还窗口，原 UI 验收 App 按原 workshop/defaults 与确认的隔离 HOME 恢复。保留精确两臂 App 供未稳定的性能现象复查、最终源/manifest 及一份连续 DerivedData；成功临时 HOME/复制样本与可由 Git archive 重建的基线导出按 artifact-retirement.json 退役。只修改本专项结果和精确正文预算，不重建未变产品；无暂存/提交或主仓修改，Goal active。


<a id="p22-host-row-and-video-request-work"></a>
### P22：宿主仅准备实际依赖事实，Video 同请求直接复用（验证完成，Goal 暂停交接）

上一批完成当前产品入口验证，未证明稳定提速。本批选择已有真实消费者证据的重复工作：依赖边只用 host HTML/folder 却递归做完整 row 的 preview/date/整目录 size；Video 已捕获 path/key/output 后同一次同步调用又重算。相比新增长期 cache 或只按 Web 类型剪掉选源，直接在原 LibraryRecords 将现有选源/分类/准入与发布行投影分开，共用同一准备函数；实际 row 才做展示统计，递归边消费真实 admitted facts，不造部分假 record。保 managed→Web→Scene 顺序、项目/浏览分类、cycle 与真实内容准入；没有 HTML 但有 Video/pkg/Scene 的已接受 host 仍保 folder，真正 ghost 才无 host。库全字段及变更后的新一次读取结果必须前后相同。

Video 沿原 Manager 在本次同步操作传已取得的 normalized path/key/output；延时 1.5 秒或 worker 排队后仍新 resolve/exists，旧 A key 不能读 retarget 后 B 内容。独审确认 prepared 的 path 只是同一 VideoPreparation 原命令回显，不能补充文件事实；当前 cohort/session/request/display、candidate 与非取消已唯一关联后，连同该重复 path guard 直接退役，不换另一字符串认证。原 preparation 事件共用发端清掉无消费者 path 载荷；真正 AV ready/seek、VideoPreparation 的实际路径、独立 ended 路径和异步身份不变，不冒称文件没变。不新增资源凭证、缓存 owner 或认证层。若不能在原 owner 内自然表达，撤回对应候选，不用 wrapper 掩盖。

两路并行实现与交叉审查，根冻结改前/改后源码并串行运行最近库/Video 行为门、真实输入前后输出/调用次数对照和一次普通 Debug 构建。补共享/传递 host、无 HTML admitted/ghost、循环/选源/替换与已发布 row 全值；Video 覆盖内存/磁盘命中、迟到结果、清理/移除、排队 retarget 和实际生成回调。测试改动按自然 fixture 职责保持单文件不超 1000 行。达到当前行为/必要反例和独审后结算本批，不以计数当整 App 提速；实现与验证期间保留 UI App；现按用户授权收口提交并合入主仓。字体/Puppet/SIL 待验和全仓查漏继续留在原 Goal。


库侧同一 -O/WMO、同一输入树的两阶段各 42 组案例（包括 nil/ghost）前后完整 24 字段相同。初始实际 preview 入口 57→35 次、目录 statistics 51→35 次；文件变更后的新读取分别 57→34、46→34。项目/Video/HTML/metadata/package 选源与准入入口次数均相同，共享 host 展示工作 2→1、传递 host 3→1。它们是实际方法入口次数，不是 syscall、扫描字节或整 App 时间；真实作者内容仅保旧版本证据。

Video 双臂同 H264 字节/路径与 -O/WMO，18 项实际 AV/ImageIO/JPEG、别名 retarget、清理代际、迟到发布、sync 与派生删除断言均通过，可比输出和 JPEG 证明相同。两次同步 schedule 的 normalize 4→2（hash 2 不变）；sync miss 和 derived removal 的 normalize/hash 各 2→1。排队后继续当前 resolve，不把旧 A key 授给 B 内容；已开始的旧 worker 仍可能写派生 JPEG，但不可回写旧 model/callback，不新增拦截。prepared 无路径也按原 current session/cohort/request/candidate/generation 推进，错误/陈旧身份仍拒绝。

选定 13 个唯一回归方法全部通过、无跳过，覆盖旧库发现/HTML/交互/重载合并、静帧/缩略图/源删除收据、父端切换/显式停止/实际 Engine 组装、真实 helper ready/seek/取消和原生可见回滚。首轮端点 fixture 给 wire 的 let 字段赋值导致编译失败，只改事件构造参数，保错误 request、缺 generation、foreign session/display、取消与无关 path 反例；固定源 v2 仅此测试不同，产品不动，复用七已过单元和独立 intent 方法，失败/未跑五方法复验通过。首轮失败与重试分别保留。调度前另将门内拿同 flock 的 explicit-stop 与其余三方法分开，无嵌套持锁；不为测试调度改产品。

一次普通 Debug 构建与严格签名通过，99.017 秒仅为构建成本；全部产品、项目/helper 输入与最后受测源相同，测试构造修正和结果文档不要求产品重建。CodeHealth 的 1515 个 Swift 通过，当前本批 16 个代码文件均不超 1000 行，新增真实静帧 fixture 归原测试模块；两路最终源、执行选择与失败修正独审无阻塞。本批没有完整 Release/App 冷暖重测、NSWorkspace 实际桌面设置或作者完整像素/音频验收，不把减少重复调用升级为已证明整体提速。

恢复后的优先项：先沿原 CacheAssets owner 仅在派生路径实际改变时发布 row，补真实 Combine/sink→250ms 保存→SQLite 的前后观测，保持 currentWallpaper 独立同步；现有静帧受控叶和 ordered-save 的无 Published fixture 不能代替该证据。ImportProcessing 无消费者 orderedPaths/同栈 key、Shared ThumbnailCache 冷生成重复磁盘 key、SIL Inspector 重复 main.async 后排；SIL 重复导入 metadata 涉及删除/提交竞态，先明确原事务再裁决。P6 已有真实 ImageIO 负缓存/子秒替换门，缺执行证据，恢复后直接用原门，不再造测试。 另登记既有 `test_scene_particle_simulator.py` 结构债：当前 4541 行、基线 4566 行，后继按真实测试职责自然整理。字体/Puppet 可见门、当前 Release、全仓其他入口及 P21 不稳定计时结论仍保原边界，不因本次合并关闭。

交接：本机证据入口 `d41-playback-validation/p22/final-validation.json`，含改前/改后完整字段和 AV 原值、各次固定源、原失败、复验与独审。compiler/AV/native 窗口已归还，本批未操作 UI 试用 App；交接检查未发现旧 PID87290，已通知 UI 会话核对；正式媒体/偏好与其他工作树未修改。按用户本次授权提交本专项累积 P10–P22，并合入主仓 `codex/engine-refactor-program`，不推送。长期 Goal 保持 paused，不主动启动下一批；另外两会话由用户通知合并，等待其全部完成后再同步最新 HEAD 继续。
