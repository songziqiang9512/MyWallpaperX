# 全仓校验与链路精简

<!-- document-role: active-plan -->

目标：按用户要求先审完 Scene、Web 两引擎，再扩到全仓，清退过度严格、重复、拖慢响应且无实际产品作用的校验、认证和附带结构。用户需要直接、轻量、按需执行的代码；历史合同、测试或“更严谨”的说法不能替代真实用途与成本证据。用户于 2026-10-26 要求本批完成后本地合入 `codex/engine-refactor-program`，随后暂停 Goal；待主仓其他工作树整合并由用户指示后再同步继续。不把修完所有小问题或跑完整个长期专项作为本批合入前提；已知重大产品故障优先处理，局部小问题与未覆盖验证明确留在本页。

## 审查方法与完成条件

沿当前实际调用链逐段审查。对每项检查记录其生产者/消费者、执行阶段与频度、直接避免的产品错误、重复读取/计算/等待以及失败范围。无消费者的状态和缓存删除；可选派生缓存损坏或失效回原链重建；下载完整性留在下载/发布事务；普通本地播放不重新证明整个历史目录。保留实际防止解析越界、播错内容、非法访问、异步串台和错误释放的检查，在实际消费处执行，避免层层重验。

完成须同时满足：下表范围均有当前源码审查记录；有依据的发现均已处理或经实验明确撤回无效候选；对应行为回归与必要构建/代表运行完成；修正后独立复审没有发现尚未处理的新同类问题。只报已核实范围和实际前后数据，不能以构建或少数成功样本宣布全仓无问题。发现新问题就继续处理，覆盖表不以文件数或测试数代替。

## 顺序与覆盖

| 顺序 | 范围 | 当前状态 |
|---|---|---|
| 0 | 正式 Release 旧 Scene 误拒播；Scene 来源/读取/纹理身份；Web 重复扫描/缓存 | 代码已清退，19 个来源/读取/缓存/生命周期邻接模块通过；两份真实 Scene 的 P1 产品入口呈现/提交及 P7-v6 合并 Debug/Release 构建通过；P8/P9 后继不在该构建中，正式 Release 实际播放与全部视觉仍待验 |
| 1 | Scene：资源/解码/模型/字体/媒体/纹理准备及复用 | P3/P5 的 MDL、按引用目录、粒子单次准备、纹理 snapshot、Raw/BC 上传、视频私有文件及字体最近门已过；声音完成后真实 FD 边界已过；初始同屏字体实际上传门、字体内存及合并 App 代表运行待验 |
| 2 | Scene：shader/Program/graph、特效、Metal encode、普通帧、输出与生命周期 | 静态准备、编译/VM/拓扑减工通过最近 CPU 门，P5 原生 production GraphExecutor 已过；P7-v6 合并 Debug/Release 构建已过；P8/P9 后继、Puppet clipping 可见门与剩余旧桥接夹具待验 |
| 3 | Web：项目/属性/资源权限、宿主/JS桥、媒体/特效/逐帧、进程/可见提交 | P1 有构建及两份产品入口；P3/P5 的目录/hosts/datastore、单 FD、取消、timer、CSS/媒体减工和 Release JS 剥离最近门已过；P6 卡片/方向导航及 P7 作者 memo 暖复用 CPU 门、P7-v6 合并构建已过；当前完整合并 App 实际播放待验 |
| 4 | 全仓：Video、公共播放/音频/系统策略、图库/下载、存储/索引、UI/工具链 | Video 首播、音频诊断剥离、project 单次读取及 P6 父生命周期/分片/桥接/卡片导航/频谱/可选预览最近 CPU 门已过；P7 已冻结，旧迁移/在线下载/维护扫描与 Web 暖缓存最近 CPU 门已过，SIL 原生负缓存门和合并验收待补 |
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

## 下一批：不可变准备事实与实际动态检查分离

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

### 下一批：已完成视频文件的来源确认归请求入口

Scene 视频 Registry 的两个公开入口各确认一次本次当前 source identity，再用它查原 device/source 映射；private source 不在同步字典查找前后和私有文件构建后重复证明原作者文件。borrowCompletedWebM 只借已完成的私有 MP4，唯一生产 caller 已有当前 identity，不再接原 Handle 重验两遍。实际仍读取作者数据的 Root.readEntryChunks 保同 FD 稳定性和范围；已完成私有输出的 revision、domain/purpose、预算和 strong lease、取消、device/epoch/stop/rebuild 均由原 owner 保持。按当前调用静态计数，package live hit 来源检查 3→1、completed hit 5→1；实际前后行为和耗时须门验证。用户属性视频的异步 prime/adoption 有实际时间间隔，不套用该同步删重。

### 下一批：纹理 snapshot 完成后不重查作者文件

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

Web 的实际属性更新、重置和 Combine 失败入口不再丢作者 memo，下一准备 0 作者字节读取/0 解析；当前 override/bookmark/grants 仍重建，作者修改/坏缓存/删除发布 fence 反例保留。首轮下载夹具错误要求 macOS 系统临时 API 跟随 TMPDIR，已改按真实 owned 目标 staging 验证；最终发布先删旧文件的存量缺陷也已修正。Web 夹具局部变量重名仅改测试，产品无回退。各轮固定源零漂移，独立复审无阻塞；SIL 实际窗口门、字体/其余 Metal 门仍待执行，末轮结构门还发现并删除零调用的旧目录校验函数 isOrdinaryDirectoryFile；该门现已通过。后继复审又删除普通图片同一入口内重复的 prepared input/source 比较；首次输入匹配和 expected revision 比较保留，固定 v6 的最近纹理来源门已再次通过，包含当前 revision、完整 snapshot 与实际读取失败反例。四份已有只读 Scene 测试副本共 9 个 TEX 的物理表均无超出颜色层数的尾层；该元数据清点不能代替运行成本或全样本结论，当前无依据为它另造读取链。首轮合并 Debug 曾为包含目录死函数清退主动中断；后续固定 v6 的 Debug/Release 已完成，具体边界见下段，原生与启动对照仍待运行窗口。

### P7 合并构建结果与剩余验收

固定 v6 的纹理来源 CPU 门通过，未创建 GPU 或解码图像，运行前后源摘要零漂移；随后优化 Debug（与 P1 同为 -O/wholemodule，关闭 Debug dylib）及 Release 均构建成功，严格签名检查通过、源快照前后零漂移。Release 使用正式 com.songziqiang.MyWallpaperX 身份，Debug 使用既有 Startup 测试身份；两者均为 H9QWU9XN8R 签名。实际 Release SwiftDriver 未定义 DEBUG，选定四个 Scene/Web 调试 runner 的符号在 Debug 存在、Release 均为零，与既有 Release 隔离门一致。本轮未启动 App，不把构建用时当成壁纸启动收益。文档后续状态同步不要求重建未变的产品源码。

已通过的同源纹理门从后续清单移除；剩余 14 个选定单元使用 10 个编译组，其中五个 GraphExecutor 原方法仅合并一次编译，仍各用新进程/独立缓存并执行原断言，静态独审通过但尚未运行。字体读取/耗时/内存、SIL/其余 Metal 门及真实 Scene/Web/Video 产品入口和交替冷暖对照仍待完成。测试驱动已独审，局部清理失败误记成功已修正；它不增加产品校验。末查已确认命名空间兼容分支仍有重复工作及失败半径问题，见 P8；不能以普通播放快路不走它代替审查。编译窗口已明确交回并行会话，持续 Goal 尚未完成，修改保持未提交。

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

本批 11 个相关产品路径相对 P7-v6 从 4438 减至 3915 行，净减 523 行；旧 extractor/report、整包 snapshot 和重复 alias 认证链已退役。当前没有已知需要阻止本地合入的重大产品故障；14 组选定 CPU/FD/CoreText 门已通过，最新固定 P9-v2 的优化 Debug checkpoint 已构建通过，严格签名检查成功、源码前后零漂移；耗时 451.678 秒只记构建成本，不当播放性能。该 App 未启动，标识沿现有 Startup 测试配置，最新正式 Release 仍未重建。已完成的 P1/P3/P5/P6/P7 结果保留各自固定源边界，不称全部覆盖 P8/P9。

以下暂缓项不阻塞本批本地整合，也不等于已通过：

- 剩余原生正确性门：Puppet clipping、SIL、旧 RuntimeBridge/Program/GraphExecutor 夹具、初始多层字体及 typed FrameTextureRegistry；已有同输入通过结果继续复用，不为凑全门重跑。
- 新 Root 的 Sound/MaterialVideo 实际 AV 借用/回收、用户属性视频，以及最新合并 App 的 Scene/Web/Video 出画面、切换与停止。
- P8/P9 最新 Release 尚未重建；最新产品完整冷暖启动交替对照及字体成本/内存观察。本页 SourceFacts 数字不能替代上述验收。
- 主仓其他工作树合入后的冲突收敛与受影响回归、长期全范围末轮复查；轻微问题沿此页原责任登记，不另立阻塞平台。

合入保留主仓原有 UI 设计与四处登记，不覆盖、不随本专项暂存；共同 AGENTS 条款已逐字相同。合入后通知 UI 专项依用户指定顺序开始其合入流程；本 Goal 暂停，不继续新批次。下一次先等待用户完成主仓整合并明确恢复，再同步主仓、核对实际合入内容，只重验受影响边界。此处是本地整合与交接，不代表发布或长期 Goal 完成。
