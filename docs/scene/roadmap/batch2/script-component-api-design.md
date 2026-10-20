<!-- document-role: active-plan -->
<!-- retirementCondition: 公开 API 的限定表面、生命周期与预算通过双侧事务门并归入唯一脚本合同后归档，设计登记随实施关闭。 -->

# D4 — SceneScript component、object 与 particle API

> 原设计基线2026-10-01 `93b1b85a`；2026-10-04实例alpha后继以主分支`10e3f889`及官方自有黑盒为准。设计批准不等于实施或运行验收，历史行号开工重核。

## 目标合同与设计判据

脚本只能通过当前 scene generation 的 typed handles 操作作者对象、经验证的动态对象和粒子系统；脚本调用进入现役 VM→typed mutation→frame transaction，不直接操作 GPU。API 表面一旦公开成为作者兼容合同，且跨 VM、拓扑、粒子和资源 owner。

五判据：横切多个 owner 或主链节点=是；触碰唯一权威合同=是；用户可见且难逆的 API/数据/发布合同=是；触碰机器冻结结构家族=是；依赖官方或平台外部证据=是。

## 当前事实与证据

- component/object/particle综合项仍有缺口，不能由综合等级推断各基础设施缺失；现`SceneScriptLayerHandleBridge`已有upsert/destroy、mutation commit/discard与scope隔离，`SceneScriptOwnerLifecycleBridge`已有生命周期及mutation预算。
- 2026-10-01核对官方[IScene](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IScene.html)、[IEngine](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html)、[IThisPropertyObject](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IThisPropertyObject.html)、[IParticleSystem](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IParticleSystem.html)。公开入口未证明作者可调用`registerSceneScriptComponent`。

<a id="user-shortcut-macos-adapter"></a>

## User Shortcut 的 macOS adapter（2026-10-20，本机目标打开已验）

**目标与实际调用者。** 首片须让用户在原生属性面板为原357的Launcher配置本机文件、目录或HTTP(S) URL后，原作者按钮可见、可命中且真实点击能打开所选目标。[公开User Shortcut](https://docs.wallpaperengine.io/en/scene/userproperties/usershortcut.html)与[IEngine](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html)规定系统本地配置、cursorClick/up/down内调用、每click一次及重复throw；true表示shortcut successfully called，false表示无action，不要求目标App完成启动。本文限定macOS返回合同，不宣称Windows底层行为或全平台等价。 已只读核原357：16个`usershortcut`定义`_1…_16`默认空；Launcher214的`scriptProperties.shortcutName='_1'`，cursorClick先检查`thisLayer.visible && shared.appDockEnabled`再调用`openUserShortcut`。它不读取shortcut的`isbound/file`和图标投影；Dock209从原Bool `kg`和thisLayer.visible维护shared开关，210按原数量属性控制图标显隐/布局；214的`instance.usertextures`把`_1`声明为usershortcut。该结构用于验收，产品按类型、key和gesture执行，不按这些身份分派。现已支持的作者图标底图必须保持，不能因新增assignment把目标文件当图片解码、变成白块，或在可见/布局未接通时仅宣称opener成功。

**数据流与唯一职责。** 原Property definition/parser增加显式shortcut kind，原AppKit editor复用resource行、sheet request/window/row生命周期；SteamWorkshopService独占本机选择、bookmark、assignment持久化与revision。沿现coarse load/update IPC交付`recordID/requestID/configurationRevision/propertyKey`绑定的typed assignment/reference快照；Session复用现输入owner持有当前执行lease与gesture/frame预算，C/Swift窄桥只接受已注册property key，验证后同步调用`NSWorkspace.shared.open`并直接返回native Bool。无新broker、资源registry、时钟、进程或通用opener；App仍是用户意图/store唯一权威，daemon不写用户配置，普通帧不解析/刷新bookmark。 assignment是typed资源/动作能力，不塞进`SceneUserPropertyValue.string`的JSON、不把作者String当可执行URL。首片只开放registered key的配置与调用；`isbound/file` structured getter及其applyUserProperties事件投影明确pending，不把空String伪装为shortcut对象，后继复用现userProperties/event DTO。原357不依赖这些对象字段，限定实际打开证据归[本机后验](../../capabilities/runtime-evidence-current.md#user-shortcut-native-20261020)。首片保作者icon fallback，不能伪造系统icon或据未参与本片的字段阻塞原Launcher点击闭环。

文件/目录由用户chooser显式选择；URL由用户显式输入且只接受合法HTTP(S)。沿原record/key存储与bookmark资源生命周期扩展typed assignment，portable preset不导出本机授权；未知key、未配置、过期/不可读引用均不执行。Shell/console command、任意scheme、作者提供的路径参数、通用文件/网络API及无交互自动打开均不进入本片。 **选择与取舍。** 采用Session本地同步macOS adapter：native Bool只表示此次OS dispatch接受，不冒称目标已启动/文件已呈现。拒绝App侧异步排队返回true、始终返回false却仍打开，以及帧内pipe等待/嵌套RunLoop；它们不能保同步结果或会扩大阻塞。现[daemon合同](../../architecture/scene-runtime-daemon-contract.md)允许播放进程持有输入/AppKit runtime，此窄能力不迁移UI/store；相关coarse payload与执行边界由该合同登记。原typed对象变更仍走frame transaction，外部OS动作另按下述不可回滚合同，不借此绕过图层/资源事务。

**首次调用与预算。** 在现native pointer ingress为真实AppKit输入分配session内gesture identity，经surface合流、捕获、pending callback到C当前调用scope；timestamp只排序，不作授权。真实点击还须WindowServer实际接收窗口为当前壁纸surface或Finder桌面；复用现Web命中算法，提取Core共享纯判定函数并退役Web私有重复判断，Web原cache/输入owner保留。遮挡的普通App/设置窗口不给grant，普通pointer视觉传播保持。只在active、visible、outputActive且当前owner/request/configuration一致的物理cursorDown/up/click放行，init/update/timer/media、synthetic/debug输入和伪造callback kind均无grant。一次click跨down/up/click、所有owner/surface共享一次attempt，另共享当前frame的一次预算；由现input owner持有，不新增gesture服务。 显式macOS策略：合法String参数且进入授权cursor scope后的首次调用先消费两项预算，再查已注册key/当前assignment并尝试native dispatch；未绑定/unknown key/失效引用或native false均返回false且不退款。同gesture或已耗尽frame预算的重复调用throw，不能换owner/key/回调再试；非法类型或真正非cursor scope抛错且不调用OS；合法cursor没有native grant/adapter或已因配置/生命周期撤权时返回false，不把环境不可执行变成作者视觉owner永久禁用。只有真正的同gesture/同frame重复attempt仍throw。首次成功返回实际native true；失败调用的精确Windows计数细节未证，作为平台策略保留，不伪称官方失败分支parity。

**不可回滚与退出。** 消耗标记和dispatch结果留在现input owner、独立于VM/native mutation rollback。发出后即使作者随后throw、owner整包晚拒、GPU未提交/失败或presentation重试，也不退款、撤销或重放；外部目标无法随frame取消。调用前在同一串行点核active session及assignment revision，stop/切换/standby/候选未激活、reset/key删除或配置替换立即撤grant；排队事件保捕获时request/configuration revision，不改授新目标；已发出的OS动作不能追回，迟到事件、IPC重连/daemon重启不得重放动作。

chooser取消、隐藏/窗口换绑或旧请求完成保原选择；选取/替换仅在当前revision接受后发布新快照，晚到picker不能复活reset前授权。reset清本机assignment/bookmark并按原store/revision语义更新当前session；失效bookmark保用户已选意图供展示/reset，标记不可执行，沿原资源准备范围刷新或要求重新选择，不降级为裸路径或另一个目标。错误只影响该动作/失败owner，保健康脚本、原图标底图、选择和播放；不把失败打开扩大为整Scene重载。

**验收与停止。** 独立改名fixture须贯穿真实definition/editor-store投影→typed configuration/coarse IPC→原VM/cursor scope→typed key/revision校验→native adapter，用可计数native测试接缝分别注入true/false结果，验证不是伪queue成功；再由用户配置无害本机目录/文件及HTTP(S)，在原357真实桌面点击取得一次打开、对应native结果及原按钮/布局保持，关闭重开保选择、取消/reset生效。只用CLI改值、直接调用C或脚本shape门不能关闭该结果。

反例覆盖未绑定/unknown key、非String、非法scheme/命令、坏/失效bookmark、picker/reset/revision竞态、重叠owner/跨surface、down+up+click/同frame重复、非native/非cursor、stop/standby/旧generation、native false后重试、首次打开后throw/owner晚拒/GPU失败及daemon重连；均不得额外打开或串用其他target。健康独立脚本/图标fallback及普通typed事务保原结果。Swift实施须Debug build与隔离代表运行；设计落库阶段不执行打开；实施阶段沿用户已授权范围使用无害测试目标验收。

若原Launcher仍被shared/visible/typed资源门阻断，先修同链最早owner而非强显图标或绕过原脚本；若本地同步调用出现不可接受的主线程停顿，或gesture/configuration无法在dispatch前原子核定，撤回执行route并重评。未覆盖全部16项/全部target handler、系统icon/完整file shape、commands/schemes、Windows失败细节、App完成启动、性能长稳和完整官方parity；只把真正阻塞首片的未证字段单列pending，不反复泛化BLOCK整个API。

<a id="default-2d-camera-inputs"></a>
## Default 2D camera 输入

**现役范围（2026-10-16，有界已实施）。** 目标是让普通正交画布的作者默认相机 origin/zoom 经唯一 typed camera snapshot 到达现有投影。原无 Timeline 的 path 基值与 direct Slider zoom 漏接、origin Script 误作普通层位置，现与原 Combined Timeline 共享 `.camera(.origin/.zoom)`。混合来源按字段准入；运行和不同比例边界归[限定证据](../../history/default-2d-camera-inputs-2026-10-16.md)，不改作者画布或图层位置补偿。

限定 profile 为具有合法正交画布、唯一合法 default camera path 的场景。准备期统一确定来源层及可消费字段，静态基值、direct Slider zoom、现 VM origin Script 和已准入 Combined Timeline 共享 `.camera(.origin/.zoom)` definition、优先级、resolver 与 clock。输入路径保留原作者层 identity，VM 的 thisLayer/property scope 仍属于该源层；只有 origin 真正准入时输出 target 才改为 camera，保源 owner identity且退出该字段旧层 writer；未准入的 origin 完整保留原层 owner、definition、getter/setter和world路由，zoom可独立准入。相机当前值只由 settled snapshot 消费，renderer 不再读 path 或加第二 fallback。

direct user zoom 复用原 extractor、property Program、live 准入与事务；合法初值、连续改值、保存/reset 均更新同一相机 target。return 型 origin Script 沿既有 Vector owner 的 init/update、事件、失败撤回和退休，基值仅作原 resolver fallback。本片不开放 camera origin handle setter：其 mutation→schema/冲突尚属普通层合同，在原 preflight 拒绝相关 owner 整包，不能与 camera primary 形成双 writer；完整 setter 归后继统一别名准入，不能记作已支持。Combined Timeline 保原时钟与已准入 composition；未知动画、重复/非 default path、native 3D、冲突来源与非法有限域不顺带开放，拒绝只影响相关相机输入，健康内容保原路由。数值域复用已有 camera Timeline 验证，不在普通帧重找相机、解析、建图或编译。

验收从自有改名输入的真实 parser/extractor→property/Vector C owner→definition 合并/resolver→cameraTransform/投影走通：init 产生区别于 seed 的 origin，direct zoom 默认与两次热改保留该 current origin；静态 path、原 Combined Timeline、坏返回/非法 zoom、同名非 camera、重复 path/native/冲突来源为相邻反例。Swift 产品做一次有效 Debug build，304 原包实图对照并核实际相机输入，未参与修法样本真实回归；169 只按其独立证据裁决。正确接线不自动等于完整官方画面、跨比例、全部相机 API 或性能收益。失败保原局部回退，保暂停、取消、同 generation 与资源释放。

### 默认相机 Timeline 与控制柄（2026-10-19，有界已实施）

目标是让作者默认相机开场经原typed camera/投影播放。合法正交画布与唯一prepared default source内，独立Single按字段接origin-only、zoom-only或两条分轨，不要求同fps/length；完整origin/zoom组则按作者唯一root继承设置、name与原Playback状态，origin保持relative/additive、zoom保持absolute。Profile与compiler共用完整互逆关系及原raw三分量alias准入；坏peer、hard-error声明、外来incoming、残组或任一成员越界不得降成独立轨，组原子拒绝。独立字段只拒相关输入，保原static/direct Slider/return-origin Script；multiple/non-default/native、未知动画、竞争wrapper与复杂嵌套不扩。有效origin退出旧layer writer，source-layer identity/getter/definition仍唯一；renderer只读同一settled snapshot，不另读path、建图或维护当前值。

公共Timeline的wire front X为0…2、back X为−2…0，乘相邻frame半span；Y保持property-value offset。旧全span/±1解释退出，它制造355假多根和合法输入首拒。Parser保raw值，Evaluator仅改X解码，保原cubic/48轮有界二分；归一化控制点仍在0…1，无新求根策略、算法、cache或clock。disabled/缺省侧仍退anchor，双侧关闭严格线性；非有限、越界、坏结构及已消费Y溢出拒绝，wrap仍用同一末/首闭合段。正交origin三轴均为有限且绝对值≤原1e7的位置平移，near/far只验证clip span；静态、Script fallback、独立曲线与Combined共享原profile，不加Z0特例，保原CameraProjection及canvas-perspective fitted策略、zoom范围与control hull预算。合法曲线准备失败保原局部回退，不剥wrapper冒静态输入。

原SceneClock/PlaybackRuntime持播放位置，独立target各自clock映射、组成员共享root owner；Single末值保持，暂停/取消/事务和旧响应选项边界不变。prepared source的同帧parent-aware Bool显隐只撤origin/zoom到原identity分量，shake/parallax保原链；隐藏期时间继续，再显消费当前位置，不隐式play/pause/stop，官方重播策略仍未证。最近验收贯穿parser→descriptor/alias→Program→Playback/resolver→cameraFrame/getter，含两种root、改名/顺序、不同fps/length/startsPaused、typed控制、隐藏恢复、±Z/超far平移及坏peer/三分量/超幅/非有限反例。官方一板两次预登记fractional seek支持半span独立数学±0.25 authored单位，不认精确算法；原355实际由静止全景恢复近→全，独立358保持开场，均正常stop/GPU排空。具体身份/首失败归[当前证据](../../capabilities/runtime-evidence-current.md#default-camera-single-20261019)，只闭镜头缺失，不外推JS camera handles、同phase/viewport/pixel、完整视觉/交互或性能。

<a id="asset-path-string-values"></a>
## 资产路径值与字体入口（2026-10-18，有界已实施）

目标是让公开资产值可直接读写、比较并传入文字创建配置，不因项目私有对象包装中断作者回调。固定官方2.8.0.42的自有文字载体已观察到：`registerAsset`返回路径String，非空`font` getter也是String；合法stock路径直接赋值与注册返回值赋值均成功，同回调及下一回调读回保持。只限定所测路径值行为，不裁决资源预加载、路径规范化、空字体或字体像素一致性；具体身份与实测归运行证据。

唯一值入口为原AssetHost：保留module-only、参数与安全相对路径校验，注册结果直接返回原路径String。退出旧asset opaque class、finalizer、domain字段及借该class取得路径的分支，不增加registry或新资源授权。现有准备期资源需求、owner alias、typed mutation与资源consumer仍保各自职责；合法String不能证明文件存在或已准备。

字体getter、setter与`createLayer({font: ...})`使用同一String路径合同；后两者复用AssetHost的严格primitive String解码和真实UTF-8长度校验，不调用任意对象的coercion。短生命周期UTF-8视图必须在每条退出路径释放；setter先比较当前路径，相同即结束，不额外复制、stage或dirty；变化后才沿原authored baseline/mutation或dynamic journal复制并提交。构造器在释放配置值前取得持久副本。空getter保现undefined，省略构造font保原默认；不借此开放未知空值写入。

<a id="image-font-script-state"></a> 2026-10-20 图像层font决策（有界实施）：官方自有三路载体中，普通文字正控健康；caught/uncaught图像font路径赋值均不throw，前后文字更新继续，独立lookup读回同一String。只开放prepared authored image的有界JS状态：原catalog能力参数扩为互斥text/image标记并纳入launch身份；复用LayerRecord.font，image setter沿原primitive String/安全路径/1024 UTF-8字节准入与同值退出，直接存目标层，不发FONT mutation或资源需求；text仍走原typed事务。snapshot仅覆盖native文字font，图像值随原layer/domain释放，fresh handle与健康其他owner共读；不增加wrapper缓存、任意属性包或逐帧解析。最多4096层的C字符串上界不冒称QuickJS堆限额。

文字font、text和dynamic birth失败仍沿原callback及host frame整笔回滚。图像新值属于JS状态，和普通脚本状态一样不由native accept/discard恢复；拒用现整record dynamic journal，因多writer的Swift晚拒会回滚覆盖健康peer。官方未裁定throw、任意JS值、删除属性或其他kind，保留边界；非法类型/路径、过长、stale/destroyed与无能力target继续局部拒绝。native typed `.text(.font)`、descriptor、CoreText、last-ready source、graph及唯一合成不增加owner。验收要求改名/等价路径、跨lookup/owner、下一snapshot及snapshot回滚保值、A晚拒不覆盖B、target/domain退休无串值、无FONT mutation，加原text失败反例；同身份实际374修前/修后与独立作者样本运行才裁定收益，当前374字体热切换已有局部可见收益，默认横屏裁切/遮挡与整景不升完成；结果归[运行证据](../../capabilities/runtime-evidence-current.md#image-font-script-state-20261020)。
验收复用现QuickJS门的真实C执行：注册结果/String getter的类型与值、同回调读写及下一回调、getter转交创建、改名与等价表达式；非法相对路径、NUL、UTF-8上限、伪对象/coercion及整笔回滚为反例。真实stock时钟的getter传递由读源与该C行为门限定，不能冒称时钟App实图验收。一次Debug、同载体修前/修后实图及独立作者样本的执行结果归[运行证据](../../capabilities/runtime-evidence-current.md#asset-path-string-values-20261018)。已有层引用、topology和typed字体发布门只补受影响范围；声明、build或CPU通过均不代替画面，未测完整字体/parity或性能不得升级。

<a id="text-layer-pointsize-setter"></a>
## Text layer pointsize setter（2026-10-16，有界已实施）

目标是让文字层同一回调内的 `pointsize` 与 `text` 写入共同进入现有事务，使字号设置不再提前中止合法媒体文字回调。[公开 ITextLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ITextLayer.html)声明Number且未标readonly；真实中性投影只证明存在这些member写入，未读作者表达式，不推断其字号公式或完整视觉。

原C layer/value owner给thisLayer与lookup handle同一可写表面：复用mutation的point_size载荷，新增明确字段位；authored staging/baseline和dynamic rollback journal都保留raw值，同回调read-your-writes、跨回调current及partial merge按字段位处理。Swift桥投影至原`.text(.pointSize)` scalar与dynamic definition，再沿settled snapshot→原CoreText/source publication→既有graph/唯一compositor消费；不只改raw style，不新增VM、文字store、cache、clock或生命周期owner。

setter准入复用现scalar consumer的有限Double域，0/1025与有限极大值保raw，不能把create的1...1024 profile套到setter。动态descriptor与CoreText渲染值沿同一`SceneTextDescriptor`数值归一职责限制为1...1024后再转Float；原Store clamp迁入该owner复用，raw current与rendered style分域，不泄露Float.infinity。constructor原范围保持，以上是本项目既有安全消费规则，不宣称官方数值边界。

非Number/非有限、非text、stale/value-only、未授权或冲突目标沿原最小owner包拒绝；字号与文字、peer mutation、storage/事件共同preflight、commit/discard，不能只保先写字号或吞后写异常。已有Scalar/property/Timeline及其他typed producer仍走原优先级与固定点，不以新的样式字段覆盖已settled结果；退休撤原schema/资源，失败保previous-current，暂停不增timer或媒体派发路径。

C ABI按职责组织：HostTypes保存既有opaque handles、DTO、字段枚举与callback typedef，原SceneQuickJS.h保domain/owner函数声明并相对include；载荷与执行owner不变，不复制声明或仅为行数增加wrapper。最近真C→ABI→Swift验收覆盖thisLayer/lookup、同回调bundle、跨回调、partial/rollback、动态text clone、极端有限/非法类型、竞争producer及stale/退休；具体门与原包/独立输入结果只归[限定记录](../../history/text-layer-pointsize-setter-2026-10-16.md)，门与设计批准不代替实际输出。真实标题可见不外推artist文字、右黑块、全部媒体/字体parity或性能收益。

<a id="vector-mixed-dimension-arithmetic"></a>
## Vec3 与 Vec2 混合算术（2026-10-16，限定实现已接）

目标是让受支持的 Vec3 接收者对实际 Vec2 执行 `add/subtract/multiply/divide` 时，仅运算共同的 x/y，原样保留接收者 z。按[官方研究边界](../../development/official-client-behavior-research-workflow.md)固定官方 2.8.0.42（executable SHA256 `daac1ea7…bda07`）的 24 个自有黑盒 case 已确认该数值行为、改名直调一致、左值不变及返回另一对象；黑盒没有验证 prototype/instanceof，返回 Vec3 沿公开 API 签名与现 owner，不混作黑盒类型实证。

唯一实现 owner 是 `SceneQuickJSValueHost` 的共享 Vec3 四方法：仅在实际 Vec2 向量操作数分支保留 z，仍构造新 Vec3，其他运算表达式与调用链不变。不以 `rhs.z === undefined`、零值或 duck object 字段推断维度，不在 layer、property、media 或 typed publication 另补算术。原错误是读取 Vec2 不存在的 z 后产生 NaN；修复该 producer，不放宽 finite publication。

构造 `Vec3(Vec2)`/`Vec3(x,y)` 仍补零，单 Number 构造及算术仍广播至全部 xyz；显式 Vec3 的 z=0、undefined、NaN/Infinity 仍走原三维运算，显式零除法不改成缺维保留。非法 typed 返回、previous-current 回退、journal 与失败后恢复沿原边界。Vec4、mix、plain object、追加 z 的 Vec2、反向维度、非有限与正负零的官方规则未由本次黑盒裁决，不将本片结果外推为其官方一致性证据，也不为这些未证表面扩 API。

验收复用真实 QuickJS owner harness：四方法直接调用及变量改名/等价表达式、返回新对象且两操作数不变、scalar 与显式 Vec3、零扩展构造及非有限 typed 返回反例；不新建 vector owner 或测试算法。最近门、Debug、原包1128首错消失及独立实图的身份归[限定证据](../../history/vec3-mixed-dimension-arithmetic-2026-10-16.md)，原包保owner-executed，未直接观测位置向量或完整motion；不据此关闭 U13 光束、媒体或整样本差异。失败保留原局部降级，不增加 cache、identity 或逐帧准备。

<a id="named-user-pass-scalar"></a>
## Named-user pass scalar 输入（2026-10-16，有界已实施）

目标是让 effect pass 的有限 Number `script/user/value` 包装进入现有 Scalar owner；outer user 是当前属性输入，脚本返回值是唯一高优先级 uniform producer。真实 slider 包装已定位，原入口仅允许 named-user Vec3，故在 binding 解析即丢失 scalar owner。选择补接现有输入链，不加 VM、属性状态、frame writer 或特殊 shader profile。

Binding reader 只扩有限非 Bool Number 与规范化命名 user；Scalar projection 校验完整 owner/path/source、wrapper、user identity 及单分量类型。matching named input 的 resolved descriptor 可以与 raw authored fallback 不同，owner definition 仍保 raw seed；无 user 分支保原 seed 一致性。Material classifier 仅消费 exact target proof，将 user 留作输入，不能忽略脚本或登记并行输出。原 property compiler→preliminary snapshot→Scalar VM→settled snapshot→Program uniform/graph/唯一 compositor 全链复用，普通帧不增加解析或全图扫描。

首片只扩无 animation 的 `script/user/value` Number；scriptproperties 混合、数值 String、Bool、Vec2、其他 host 与 Timeline 控制不扩。缺失/错误/重复定义的属性仍由原 property compiler 诊断并提供原 authored/current fallback；没有 VM proof 保留 unproven attachment，失败返回、事务拒绝与退休沿原局部回退，不提前确认事件或发布部分结果。

验收用改名及等价表达式确认真实输入被脚本变换，覆盖非默认保存值启动、连续热改、错误类型/非有限返回、缺失或重复 owner、未知 wrapper/竞争 Timeline及健康旧 scalar/Vec3/property-only。最终隔离 App 须直接确认 target identity、typed 输入/输出与 encoded uniform、GPU/末合成/下一帧及实际旋转响应；未参与修法内容另作真实渲染。若没有实际 owner/consumer 或画面响应，保留未证边界，不扩大 wrapper 或颜色域；一个有效构建和最近门可复用。

<a id="camera-layer-fov-scalar"></a>
## Camera layer FOV scalar（2026-10-15）

合法 native-perspective default-camera layer 的 FOV 属性脚本复用原 scalar Program、QuickJS domain、typed snapshot和唯一 camera-frame。现役准入、数值、来源、失败/退休与未覆盖合同统一见[Property-bound 核心合同](../../capabilities/scenescript-api-coverage.md#2-property-bound-核心合同)；实现与验证身份、原生结果及未验边界只记[限定证据](../../history/camera-layer-fov-live-2026-10-15.md)。本段不另维护状态或测试清单，`ICamera` JS handle仍不因此开放。

取舍保留：Bindings只分类原object-scalar wrapper，不从raw JSON重算camera资格；prepared projection复用原camera owner的ortho/clip条件，实际layer world-frame/FOV override继续由同一consumer验证，不能以scene fallback完整性替代真实layer-camera资格。内部属性只更新原VM输入，不按样本/脚本文本猜消费，不扩direct FOV user、Timeline/animation或其他相机字段，不新造VM、camera、clock、last-value cache或投影公式。

真正topology退休只在原已提交lifecycle沿binding owner.layerID撤唯一Schema登记；失败禁用继续保previous-current，不能混作退休。累计墓碑在全部quiescent后不再新增bindings收集，cleanup重试仍可撤权；held snapshot、健康peer和原Scene代际屏障保持。该后继独立于其他历史D4批次，不将其重新设为串行前置。

## Legacy RegExp capture 后继（2026-10-13）

原native intrinsic的capture/realm/GC与失败边界已实施；唯一可观察合同见[API表](../../capabilities/scenescript-api-coverage.md#native-regexp-captures)，设计取舍、成本及真实时钟证据见[冻结记录](../../history/native-regexp-capture-2026-10-13.md)。不新增wrapper/正则算法或clock，未证完整提案与官方parity；普通编辑重建仍归属性卡。


## 共享 VM 容量与安装失败后继（2026-10-13，实施中）

原包隔离 App 在第 742 个 owner 的 layer handle 安装处实际耗尽共享 VM 的 16 MiB heap；记录为 memory-exceeded，分配量 16,777,168 / 16,777,216 bytes，计划上界为 935 个 owner。首个真实内存错误已沿现候选域 fatal 路径退出，旧逐 identity 重试耗尽 4096 的扩大失败已排除；该 16 MiB 版本原包开场仍未恢复。该证据说明容量不足，不定位症状的引入提交。32 MiB 前一候选的隔离原包已完成自动开场、后续运动与网格切换；本片最新安装失败边界仍须固定源码重建重验，不能沿用旧候选的运行结论。冻结身份及播放验收归[本轮中性历史记录](../../history/scenescript-host-heap-admission-2026-10-13.md)，不由此设计登记替代。

比较三个方向：共享 native handle 载荷可减少外部分配，但当前 QuickJS 每函数仍有独立函数对象与 closure record，不能单独消除 VM heap 缺口；按读取生成方法可减少 eager 函数，却将现 own data property 改成 accessor，属性描述符及 writable 行为的迁移证据不足；本片选择全局默认共享 JS heap 的有限 32 MiB 候选，保持现方法和 handle 语义，并以真实原包及自有高 owner 数验证。失败后不自动扩容，不按样本身份调度容量。

唯一预算 owner 仍是 SceneScriptScalarBudget：准备阶段将 JS heap/stack/interrupt/source 限额交给现 QuickJS domain，将独立 native transient 限额交给原 particle host boundary。默认 JS heap 为 32 MiB，默认 native transient 保持 16 MiB；存储两个独立字段。显式 initializer 的 native 参数可省略，省略时继承该调用者原 heap 限额，以保留现自有 custom budget 语义；生产 .default 显式指定 native 16 MiB。owner 构造工作 4096、单 owner/aggregate source、stack、interrupt 与现候选域重建规则均不变，不新增预算、identity、cache 或生命周期 owner。

handle 安装失败在清理前保留真实异常及 effect/layer/object 阶段、heap 分配快照，失败 owner 释放后分类；compile-only、engine-bind、namespace 与 handle 安装共用 native 异常分类，仅读取 Error 自有 data message，不执行可被此前 owner 改写的 formatter、accessor 或 Symbol.toPrimitive。这些 native 构造均不执行作者代码，四个 caller 均分离调用前旧异常与新 native 异常；成功恢复原旧异常，返回成功值同时留下新异常仍拒绝并清理已转交资源。失败 return 未留下新异常时只释放旧异常，不把旧 null/Error 当成新 OOM；compile 保留 compile-error 映射，其他未知失败为普通异常。真实新内存错误进入 memory-exceeded；compile 释放返回 module 且不进入作者 evaluation，bind 撤回原 active engine，namespace 释放返回对象，install 沿原 handles/audio/module/owner destroy 链退出。SDK compile-only 顶层尚未找到已证成功值伴新异常；对应自有注入只验证 caller 合同，不写成 SDK 实证。作者 module evaluation、rejected Promise 及 getter/setter 的原异常语义保留。成功构造与普通帧不扫描 heap。共享 heap OOM 仍立即拒绝该候选域，原 active Scene 的生命周期不由此更改；32 MiB 仍失败时先重新测失败 owner、分配和未执行接口，不连续提高上限。

相邻 layer/particle instance factory 的 native payload 分配失败在 producer 抛出现 OutOfMemory，closure/getter/setter/atom 逐步检查后转交。现 layer access payload 只在同步 closure 构造时持有临时 finalizer 标记；早期失败由 caller 释放一次，晚期失败由现 finalizer 释放一次，成功后清除临时指针，后续生命周期仍由原 closure 独占。当前 vendored API 返回 function 同时留下新 native 异常也按失败释放；调用前已有异常与新分配失败分离，不被成功构造覆盖，不新增异常系统或持久 owner。

验收分两层：自有真实 VM 证明 935 及更高 owner 数构造/更新，有限 heap 超限、低预算、作者 null/accessor、peer/stale/detached handle 与清理反例继续成立；Swift 最近门证明默认 native 16 MiB 和 custom/native override 相互独立。随后固定源码/App/未改作者字节的隔离原包验证开场退出、后续动画/显隐与交互，并用未参与修复的样本检查邻接行为。只有真实画面链成立才记本片完成；Debug build、owner 数、ready 或非黑不能替代播放验收。

## 初始图层配置后继（2026-10-12，实施中）

N06 真实脚本通过 `getInitialLayerConfig` 读取作者配置，再提取 image/size 或 text 字段交给既有 createLayer；本片优先恢复可由现役普通图片资源消费的原层脚本，不承诺完整 clone、Puppet 或 composition。官方 2.8.0.42 自有黑盒已证 String 名称、Number 顺序、ILayer 三入口返回原作者字段的独立对象，保留 script/value wrapper、string size 和未知作者字段，去除顶层 id；运行中的属性写入不改变初始配置；找不到名称或序号返回 null。同一 R2 实验已证嵌套数组/对象的副本隔离，动态 createLayer 的普通 Object 配置亦保留创建时深副本。不得推测 wrapper 展开。

数据沿现 `SceneObject.authoredValue → SceneRenderDescriptor.Layer → QuickJS layer catalog`；保留原始配置，不从当前帧逆构造。配置参与 load/configuration 阶段 catalog identity，初始化期间解析一次并保存 QuickJS 自有的对象序列化快照；getter 用 VM 原生对象反序列化返回独立对象，不重新解析作者 JSON、编译脚本或建立场景图。只复制调用者请求的配置，不做普通帧整图序列化。快照归现 domain/layer record，跟随其销毁释放，不新增状态库、renderer 或 lifecycle owner。缺少配置证据的合成 descriptor 不伪造作者配置。

本片仅开放 prepared 作者层配置读取；动态层 getter 明确报告 unavailable，旧 createLayer 不增加配置遍历或新的准入要求。官方已证动态 Object 的创建时深副本，但暂不实施：直接对任意动态参数调用 VM 序列化会读取数组 index getter（含稀疏数组原型上的 getter），为旧 create 引入额外脚本副作用；当前目标脚本不读取动态层初始配置，为此新增递归对象图准入收益不足。后继须先证明无新增 getter/Proxy 副作用及事务兼容，再复用当前接口开放，不能用当前值回填。

接口复用现层名称/顺序解析及带代次的 handle 校验。现值、事务和资源仍由原 owner 负责；读取初始配置不代表 createLayer 已能消费其中所有字段。对不支持的资源保持局部拒绝，不能把 Puppet 扁平化或对缺少 provider 返回假成功。验收覆盖三入口、嵌套副本隔离、实时值不污染初始值、缺层/旧句柄、配置 identity 变化、现 create/destroy/rollback；真实 App 则核对原 34 个失败 target 的实际分布、普通图片模板复用与实际脚本角度输出，不以方法存在或截图非黑计完成。

<a id="prepared-text-clone"></a>
## 已准备文字 wrapper 动态实例（2026-10-15，有界实施）

**目标与范围。** `createLayer({text: …})`应区分String、静态value、user绑定和script wrapper；有状态脚本的两个clone必须各自持有模块状态、init/update、输入修订和退休状态，不能把wrapper字符串化、只取fallback或共享原namespace。现真实缺口包含一个已准备时钟脚本与两个纯user wrapper；后者应走原property typed链，不为其创建空VM owner。初片仅复用本launch成功准备的作者文字模板，不接任意新源码、Puppet/composition、动态配置getter或新的资源发现。官方自有中性实验已证独立init/update及create返回后立即`.text`可见init结果；user/throw/destroy沿项目既有合同验收，不称官方parity。

**唯一准备与身份。** 原domain layer catalog持有作者wrapper及其String/property准备资格；script模板在原compile-only结果执行前保存可信进程内字节载体，原source owner仍消费同一次编译，clone经原VM读入为fresh模块，普通cadence不解析或编译源码。模板不是磁盘bytecode cache，跟launch/domain预算和退出释放；源层退休不销毁已被合法clone使用的模板。载体仅在当前可信domain内读入，不从不可信包或磁盘bytecode取得执行权。来源需完整value/user/script/scriptproperties及宿主准备语义匹配，不用名字、当前文字或源码hash猜模板，不给getInitial返回值加可观察token。不确定、修改后未准备或歧义配置在journal分配前局部拒绝。候选为原catalog内有界own-data匹配：先拒Proxy/accessor/不支持class，再用自有数据字段比较；须先证不触发getter、原型稀疏项或额外序列化副作用，不能直接递归JSON任意调用参数。

**同步激活。** 原create journal分配provisional层后，由原domain实例化prepared子owner，绑定新layer target及原codec解析的当前输入，在返回handle前执行现String init并写同一临时record。父callback续行须恢复原owner、有效callback epoch、engine/thisLayer/thisObject、frame输入、value-only权限、异常及job归属；身份分配保持单调，子工作计入父剩余interrupt/native/heap预算，不因nested入口重置。只开放这一受限激活边界，不能全局删除callback guards。现动态写入检查把creator等同active owner，需保留record creator及其连带退休权，另让该层已授权String property owner访问自己的target；不将creator改成子owner，也不放开跨owner句柄。

**事务与typed输出。** 子实例是creator bundle的provisional贡献。init期间的typed写入和命令必须进入同一可验证贡献，不能只返回文字而漏副作用；子init失败、父throw、预算失败或后置Swift/fixed-point拒绝时，原子拒绝依赖此次创建的creator bundle并撤回子owner、timer、roots、命令及文字；父catch不能把不完整创建重新接纳，清理期间的destroy副作用也不发布，健康peer继续。已接纳clone后续update失败沿原String previous-current/禁用与重试边界处理，不重新初始化source或peer。这里只保证项目原typed/host事务，不承诺回滚任意JS共享堆。接纳后原StringProgram持有script clone及其ledger；纯user/value复用原property codec与binding producer；script与outer user共存时，沿原objectText合同将user作为低优先级typed输入，String owner仍是唯一最终producer，不能并排登记两个输出。原DynamicLayerRuntime plan发布新增target定义/生产者及实际删除事件差量，frame schema按该revision刷新；原typed snapshot→TextTextureStore→publication/compositor继续唯一消费。作者fallback、init输出与当前值分开；无首帧整景重建或逐帧catalog扫描。

**ABI与持有转移。** 模板只登记原String/property准备成功的catalog层及完整wrapper；String构造从同一次compile-only保存可信字节。C原create/journal暂持fresh子VM handle及其creator依赖，采用原frame的user输入和模板当前已解析script-properties；接纳前的typed贡献归creator bundle，共同commit/discard。原StringProgram在已提交队列中接管handle与prepared元数据，C退出持有，随后仅存property-owner身份授权；不能在普通帧扫描全catalog找新owner。StringProgram在各族VM执行前刷新模板输入，按属性revision复用原codec结果。纯user/value只携带prepared binding身份和作者seed，原property producer输出投影到新target，不为它建立脚本owner。DynamicLayerRuntime负责接纳/删除binding与定义，StringProgram负责脚本状态；二者经原plan/schema revision进入typed snapshot，不新增服务、VM或输出链。

**退出与回调边界。** 单clone销毁、creator退休连带删除和launch退出，沿原retire/destroy/cleanup retry恰好撤一次贡献，陈旧异步raster不得复活；仅传destroyedAuthoredLayerIDs不足。初片覆盖init/update/applyUserProperties/destroy及现typed输入，不静默漏media/cursor/audio：按实际exports/注册资格明确拒绝尚未接线的模板，或在原coordinator按接纳revision更新，禁止第二dispatcher。现job drain/discard作用于整个runtime；在父已有pending job时直接嵌套会误消费/删除父队列。这是实施前资格门，不能仅save/restore active_owner掩盖。首片只核同步范围：所有可能执行JS的字段读取结束后，在journal/birth前要求parent无job residue（含pending queue、active rejection和overflow）及待决VM异常；不满足仅局部拒绝本次wrapper create，不能清父队列，旧String入口不加此限制。nested activation depth限1，子init再创建script wrapper不开放；子模块/init如排job，在执行这些job前拒绝并仅清当前子队列，避免每次drain重置64-job计数绕过父callback预算。未来若开放子job，必须共享最外callback剩余计数及原owner/frame命令/变更总预算。恢复后父新增jobs仍由原流程处理。父job/rejection、嵌套create及异常完整性须保持这些资格门，不扩大vendored job机制作为默认前置。

**实施与后继验收。** 本片限定范围已沿[冻结后验](../../history/prepared-text-clones-2026-10-15.md)完成真实C/Swift、隔离作者shadow选项、独立文字样本及退出验证。后继仍须保变量/资源改名与等价wrapper、双clone独立init/update/user、父throw/晚拒绝、坏返回与健康peer、单clone/creator退休/旧generation及原particle cadence作用域。值变化须到实际文字/画面，门通过、模块数和非黑不替代验收。任意新源码、未接事件、特殊clone与完整样本parity继续开放，不把本窄片等同N06完成。

动态String binding在原retire边界清理quiescent负ID owner及其定义、输入索引和派生缓存，避免反复创建/销毁积累至launch结束。原timer frame snapshot须强持捕获时的准确owner，restore/discard不再与可变bindings按位置zip；已退休owner不恢复，snapshot释放后owner自然退出。作者source模板保留到domain退出。原frame ledger与JSON cache按同一删除target清理，不新建退休队列；schema按已提交删除事件移除stateful target。验收包含持有旧snapshot时删除中间clone、健康peer恢复/丢弃及多轮创建退休后owner数量回落。

队列take只按已共同接纳的DynamicLayerRuntime plan中`layerID→template identity`移交：同帧新生又随creator删除、无live成员或身份不符的子handle直接释放，不注册String binding/stateful target。接管不等于新的拓扑接纳权。init中的topology operation沿原creator journal，接纳后的自身sort沿已有property owner授权重放；creator身份和删除权不转移。动态TEXT dirty ABI只区分显式setter与完整record镜像，其余动态字段不因此开放。`user:null`与省略user保持同一无绑定语义，完整wrapper比较仍保真。

动态文字沿原layer ABI限制为最多4096 UTF-8字节且无嵌入NUL，统一在typed mutation合同校验。同步init、已接管clone的输入/返回值及纯user投影均在最早target边界局部拒绝越界；普通作者String原65536返回合同不缩小。非法user输入保留唯一evaluation transaction的上一安全current，首次无值用作者seed；镜像继续做完整性校验，不吞错或跳过坏target来伪造成功。需验证4096/4097及NUL、坏clone后健康peer仍更新，不能因一个视觉值让共享VM停止。该限制是现动态layer ABI边界，不是官方文字上限。

产品原particle frame是整个cadence的共享native预算/事务作用域，开启它不能拒绝普通文字创建。同步子模块构造、init与失败销毁期间，在上述词法激活scope暂存并抑制原emission/boundary hooks，所有出口恢复原hooks/opaque；不重置active、work、limit或reserved。子init的particle播放/emit命令在原native入口、任何Swift preview/reserve或可捕获错误之前设sticky失败并拒绝creator，即使module阶段尚无provisional指针也按原nested激活身份拒绝；查询如被允许仍扣原共享work。父先前prefix/query候选不能被child end/discard边界清除。验收以原particle scope包围create并核前后父输入/预算、正常与失败出口、健康suffix；禁止为绕过此门关闭产品particle事务或新增第二模拟owner。

<a id="prepared-puppet-clone"></a>
## 已准备特殊实例（2026-10-15，默认Puppet几何有界已接）

**选题与资格。** 首片为已准备Puppet模型的默认几何实例，其次为空composition实例；文字显式style先需已证请求，不沿外观猜font或继承padding。实际原包31次create有25次普通命中、6次特殊模型缺失；六请求的own及完整已核原型链均没有animations/puppetAnimationLayers/effects，五Puppet源的mesh已成功准备。source声明不代表请求继承：不复制源动画、脚本或effects，不为本片新建子VM owner。[IScene](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IScene.html)公开配置创建，[IAnimationLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IAnimationLayer.html)公开播放控制；两页未裁决clone出生相位、配置省略或source销毁后的关系。只为实际影响首片的unknown做自有黑盒，不取私有算法。本片准入限静态atlas与原普通单pass builtin image材质、已准备model/mesh和无动画/effect请求；其他配置继续局部拒绝，动画/graph后继仍未裁决。

**职责与旧链退出。** 在原prepared-device/launch资源内形成可信Puppet模板：已验证mesh/rig/reference/attachments、按实际配置准备的pose/evaluator、静态atlas logical extent及创建资格。PreparedAsset不固化source selected clips；原作者配置与默认创建分别准备pose，无动画请求沿原empty-selection reference skinning或exact bind几何，保shear/小行列式及局部fallback。静态作者层和clone共用同一准备结果，退出重复MDL/轨道解析；不另建独立资源registry或clock。mesh/indices/UV/不可变轨道与采样资源可共享，PlaybackState、clip位置/显隐/blend、bone overrides、physics/scratch、vertex ring、clipping临时目标及publication/FIFO每实例独立。GeometryProduct绑定新实例state，不能复制捕获原state的闭包；atlas只作mesh采样，不能以quad或bind-pose冒充请求的动画。

**数据流与提交。** 原catalog模板资格→create journal携新layer identity/template identity与typed配置→原DynamicLayerRuntime候选/fixed-point→共同commit→原AnimationPlaybackRuntime及surface安装→同一typed LayerFrame/GeometryProduct/唯一compositor。出生/退休是已有plan的差量，普通帧不解析或扫描catalog。首次动画相位按取得的行为合同处理，不把原sceneTime初始化擅改成birth-zero。现负ID动画bridge和bone owner权限不能全局移除；实际需要的clone脚本/控制应沿原owner授权、回调与退休接通，未消费字段在出生前拒绝，不静默丢弃。本片遇到动画/effect字段沿原异常/事务规则局部拒绝，不忽略非空配置。未来请求effects时须给新identity实例化原graph/target/history，不能借模板成功伪装可用。

**失败与退出。** 模板缺失/配置漂移在journal分配前局部拒绝；父throw、预算或Swift晚拒绝、同帧生灭均不留下clip/surface登记。只在原共同接纳后安装实例；surface资源失败局部不可用，不回滚已执行JS或伪造geometry。单clone与creator连带退休撤原动画、surface及授权，in-flight资源按原completion释放；source退休不得提前销毁仍被合法实例使用的模板。空composition如后继实施，只复用原utility source/ordering/graph/pool出口，不复制source最终纹理，也不预设子成员复制。

**最近验收与停止。** 实施与未验边界见[默认实例记录](../../history/prepared-puppet-default-instances-2026-10-15.md)。本片用自有双实例验证真实mesh轮廓/默认reference或bind几何、独立state/变换、throw/晚拒绝无残留及退休一个后peer继续，另验真实候选与未参与修法样本；动画字段不复制source，用失败反例锁定。未来动画实例另须非静态mesh位移与独立播放事实。改名/等价配置和缺template、错误代次、用途冲突保邻反例。若真实请求依赖首片外脚本/graph或没有可消费的prepared结果，收口资格并重新排队，不以无可见收益的基础设施扩张计交付。性能只在重复准备确有可比收益时单独验收。

<a id="prepared-empty-composition"></a>
### 已准备空composition与限定透视消费者（2026-10-16）

[前轮省略原型](../../history/prepared-empty-composition-2026-10-15.md)因真实true请求无消费者而撤回；后继已锁真实Object的own Boolean true及authored286无成员背景采集，按[D1](composition-render-target-design.md)的flat capture/output分离重开。现实施沿原prepared resource模板/kind、同一catalog/journal/候选/topology接空composition，接受省略/false/true；普通size与初始配置可用边界保持。source的effects/成员/脚本/最终纹理不继承，无effect只参与顺序。未消费animations/effects、背景/config、parent/children/dependencies出生前拒绝，getter/Proxy异常和晚拒绝共同撤回，原排序/退休/creator归属不变。

本片限定正交canvas的普通childless背景采集；authored setter、factory与CameraFrame共用实际几何消费者，group、native-camera及未知profile不扩。[有界运行后验](../../history/composition-local-perspective-2026-10-16.md)区分已执行的真实controller/typed/GPU回绘与未证音频ROI；不能用句柄、旧蓝条消失或全景其他卡片倾转宣称图框音频恢复。动态图层初始配置仍unavailable，特殊配置和完整288交互保持开放。新成员/effect配置须给新identity准备原graph/history及明确变换消费次数，不把本片空模板扩成clone。

## 图层 perspective typed setter 后继（2026-10-12）

真实作者在图层 init 设置 `thisLayer.perspective`，随后只更新 angles/origin/scale；原桥接没有此 accessor，赋值成为无渲染消费者的 JS 自有属性。公开 [SceneScript 类型声明](https://docs.wallpaperengine.io/reference/lib.sceneScript.d.ts) 的 IEffectLayer（image/text 的共同表面）及 model 图层声明可读写 Boolean perspective，含义为透视而非平面绘制；公开 HTML ILayer 简表未完整列出派生属性。此次先闭合已准备图层及现动态 image/text handle 的 setter/getter，不扩 createLayer Object 配置、size、资源 profile 或文字克隆。

复用 layer catalog/mutation journal、Swift owner bundle 固定点、DynamicLayerRuntime 和 typed snapshot，增加现 layer Bool 字段；C 只保存已提交镜像、同 callback overlay 和既有 rollback baseline。当前相机帧持有同一不可变 typed snapshot 的值引用，唯一 `resolvesPerspective(for:)` 在现静态 override/default 之前消费该字段，Geometry、Program/MVP、lighting/fallback、cursor 和 Puppet attachment 共用它，不逐帧复制整图、解析作者配置或失效 shader/graph。动态层的完整值记录仅在 setter 后携带显式 override，未写值继续继承既有相机默认，不将省略改成 false；现 dynamic descriptor projection 继续消费该记录，不新增拓扑 owner。

准入范围按公开表面和现实际 camera/geometry 消费者确定；改变或首次显式设置 perspective 的 mutation 在 particle、sound、camera、utility 等无消费者层按原 owner bundle 拒绝。所有 catalog 层可读已有相机策略；已显式值的同值写沿现 setter 规则不生成 mutation，这类 getter/no-op 不计绘制支持。继承记录即使写当前默认同值 Bool 也生成显式 override，避免后续 camera 切换吞掉作者意图。value-only Boolean owner保留原权限边界；跨 owner/旧代/已删除 handle、throw、C 成功而 Swift 拒绝均走现拒绝/撤回。官方 2.8.0.42 自有同输入正交 image/text fixture 已证省略值为 false，Bool 同 callback/跨 lookup 即时读回，所测 1/0/string-false 非 Bool 写入忽略且不抛错，动态 false→true→false 的声明 ROI 与各静态参照一致。官方该 fixture 的 setter 后 throw 留下 true；本项目继续保留既有整个 owner bundle 原子撤回，这是项目事务约束，不能宣称这项官方 parity。native 默认、Puppet 黑盒和特殊组合仍未验证。CPU 门覆盖 VM→ABI→typed admission/commit/discard、同帧读回、健康 peer、镜像 rollback、动态层值及相机矩阵/命中一致性；Debug build 与隔离 App 运行另验真实原包和未见 fixture。该范围不证明原包全部特效、Puppet/composition克隆、完整官方parity或能耗验收。

## 动态图片创建几何配置后继（2026-10-12，实施中）

目标是让已准备普通图片的 createLayer Object 几何配置进入原 typed mutation、候选事务、descriptor 与真实绘制。固定官方 2.8.0.42 自有输入已证 String `"200 100"` 与 `new Vec2(200,100)` 的 size 同 callback 和第30帧均读回200×100，真实颜色边界同尺寸。最终普通图片矩阵（自有200×100纹理，模型仅 material/autosize 字段）已证：model.autosize=true 覆盖显式 String/Vec2，采用资源自然尺寸；false 或省略 autosize 消费显式尺寸，省略 size 的 getter/真实图均为1×1。追加公共黑盒已分别验证 Path String、仅 image 的 Object 和 registerAsset Handle 三个 overload 的省略默认均服从同一模型策略，即时与第30帧读数及真实边界一致；模型 width/height 声明仍未证，不按作者层尺寸推导默认。创建配置 angles 的 String/Vec3 均按 scene JSON radians 输入，公开 getter 为 degrees，仅在既有 VM 边界转换。constructor perspective=true 与同配置静态 true 已逐像素复核一致；此前多图目视误判已撤回，不形成产品债务。字符串 origin/scale 复用现 VM 通用向量读取器，不按脚本形状或资源名选择行为。

size 是只读创建几何：C 原 layer record/journal 保存已验证的创建尺寸，原 mutation ABI 携带其可用性和两个分量，Swift 原 LayerMutation 值保留该字段。DynamicLayerRuntime 仍独占身份、资源模板验证和候选提交；LayerTopologyProjection 采用创建尺寸，DynamicImageTextureProvider 用该层逻辑尺寸发布同一个 prepared texture/candidate，原 matrix、cursor 与 compositor 共用此出版物。不能只改 descriptor 而让 provider 再覆盖为纹理尺寸，也不能为尺寸重复加载、重采样或新增输出 owner。perspective 沿已存在的可继承 Bool 字段，省略保留当前继承状态，显式 false/true 进入原相机策略。普通字符串文字仍沿已有消费者；text value/user/script wrapper、Puppet、composition 和动态初始配置不随此片开放。

模型 autosize 与已准备自然尺寸在原设备资源 join 后一次投影进现 template 与 domain catalog，首次 init 前完成，绑定同 launch 身份、只读且随 domain 清理；不从当前作者层反构造、不在普通帧解析资产或维护第二份资源状态。自然尺寸由现 loader 准备结果提供：TEX 的 image extent，PNG/JPEG 的原始 CGImage extent，在上传尺寸归一化之前保存；即使 decoded cache 的 lease 被拒绝，准备资源仍保留该小型元数据，在 decoded cache 退出前捕获进原 prepared resource。资源缺失或不支持的创建在原 journal/handle 分配前返回 null，其他健康 create/setter 继续进入原事务；真实作者 getter/Proxy 抛错沿 JS_EXCEPTION 传播并撤回原 owner，不吞为局部 null。同 callback、提交后读回及 throw/Swift 拒绝/销毁仍服从原 C 与 Swift 共同接纳和撤回。静态图片 autosize 原缺口由下述同 owner 准备几何后继接入，不以动态创建替代静态层。

在模型已由现资源 owner 成功准备、canonical source 与普通图片 profile 接纳条件均成立时，限定尺寸表面包含 String、nominal Vec2、正有限 Number 标量及不含 script/user 的静态 value wrapper；这项字段消费不扩大 Program 的资源发现范围。现预准备分析的公共 owner 接线由下述 Program 资源需求后继负责；有限 literal 与已准备 authored image alias 之外的 helper/变量路径、registered handle 资源需求及嵌套配置发现仍未闭合；缺 prepared 资源返回 null，不能把字段解析成功当资源准备成功。普通 x/y Object 与 Array 沿官方默认尺寸邻域，不冒充 Vec2。constructor perspective 非 Bool 沿公开创建事实回落 false，不能套 setter 的强类型策略。官方合法 zero/negative 几何与物理资源正尺寸是不同合同；现 publication/capture/cursor 尚无完整有符号或退化几何消费者，本片不取 abs 伪造镜像，autoSize=false 时该 create 局部返回 null，明确为 unsupported 后继，不称非法参数。含 script/user 的尺寸包装同样不能仅消费 value 宣称完整支持。

创建前资源查找必须先采用现准备 Program 的作者资源身份映射。每个 owner 的 `dynamicImagePathsByAuthoredIdentity` 在构造阶段只读投影到其原 C owner，create 将已解析的作者路径转为 canonical model identity，再查询同 domain 的自然尺寸/autosize catalog；完整 upsert 继续携带该 canonical identity。既有 Swift Boolean admission 仍负责权限与共同提交，其解析接受相同 canonical 值，不建立竞争 namespace 规则。不能将 alias 放进全局表：不同 owner 可以用同一作者 literal 指向不同已准备模型。映射随原 owner 销毁；未知路径保持局部 null，getter 异常及 owner 失败仍沿原撤回。此接点以两 owner 同 literal/不同 canonical、直接 canonical 邻居、资源和变量改名、完整 upsert 与失败撤回作反例，避免提前资源检查收窄既有直接路径创建。

路径身份仍由现 Swift `String.lowercased()` 与 String 的 Unicode 规范等价比较定义；native 接口仅将该身份编码为 lowercase 后的 canonical-composed UTF-8 比较键，C 的 ASCII `strcasecmp` 或未规范编码的 `strcmp` 不能替代该身份规则。原 domain 在构造时安装无捕获状态的 native 规范化函数，配置 alias/catalog 和 create 查询使用同一函数，创建记录保留原 canonical model 拼写。接口必须在任何 owner/catalog 之前一次安装；未安装时不能配置新身份表，也不能静默切换到 C 的另一套 casefold。规范键按实际输出字节数分配，内部键不套原作者路径字节上限，公开路径仍沿原安全验证。函数只做现身份转换与独立字符串分配，不查资源、不调度、不持 owner/Swift 对象；C 消费后释放结果，domain 清理指针。普通 full upsert 不重新规范或查 catalog。不能调用作者可篡改的 String.prototype 方法，也不另建 Unicode/namespace resolver；真实 VM 覆盖非 ASCII 大小写资源改名、Unicode 规范等价拼写及污染 String.prototype 的邻居。

验收使用真实 VM→ABI→Swift mutation 和实际 descriptor/provider 消费；autoSize=false 正例尺寸刻意不同于纹理自然尺寸，并覆盖 String、Vec2、scalar、静态 value、变量和资源改名、等价表达式。相邻 Array/plain Object/script-user wrapper/非有限/越界、同资源不同作者尺寸、合法省略与显式值、健康 peer 和失败撤回分别断言。隔离 App 用同输入几何 fixture 看真实尺寸与倾斜；288 原包默认只作回归，开启已有 shadow 参数的隔离派生包仅作触发 fixture，不能把默认关闭画面或自然尺寸相同记作新增尺寸收益；heldout 由独立运行侧保留、只验真实结果。不计完整样本、parity 或性能验收。

## Program 公共图片资源需求准备后继（2026-10-12）

本片闭合相同直接图片请求只因 owner 返回类型不同而缺少 prepared 资源的断链。现 Boolean visibility 来源分析独占 DeviceResourcesTask 的动态 model 集合；Scalar、Vector、String 与 standalone Cursor 已有合法 VM mutation 消费者，却没有同等资源准备和作者 canonical 映射。文字 script/user wrapper 的独立动态绑定另有生命周期职责；本片不取 value 冒充完整支持。资源发现是准备期依赖，不改变任何 owner 的副作用权限。

选用原 SceneScriptValueOwner 共同构造入口，复用唯一 ReferenceAnalysis 与 domain 的现 layer catalog model identity；仅成功构造、通过原各族 projection/冲突与 route 过滤的 owner 将 canonical model 需求并入该 domain。每个 owner 的原 alias 配置同时保留其自己的作者路径映射，不设置全局 alias。Boolean effect/Puppet 等既有 value-only/禁止层命令边界不因发现资源而变为 effectful。失败候选 domain 整体退出，最终 construction report 与 media-route 固定点选出的 domain 才提供资源需求，不扫描所有 bindings 或预加载全目录。模块顶层 create 仍早于 owner/catalog 安装，不宣称支持。

原 DeviceResourcesTask 保留 metadata 阶段、静态 GPU 准备与 CPU Program 编译重叠；原 condition 接收最终 Program 需求一次，原 BaseImageResources 动态准备循环继续使用同 loader/device/generation。该等待只在 launch worker，不进入普通帧；空集合也明确完成。失败/取消唤醒等待者并沿原 task join 清理，不发布半准备 context；不另建资源任务、loader、namespace 或 registry。现 QuickJS candidate 的四族 plannedOwnerSources 目录共用原各族 projection/unique/exclusion，准备期依赖上界通过同 ReferenceAnalysis 提供给原 material color lowering；带脚本颜色的同模型请求得到原唯一颜色 owner，不重编整个 owner。原 Vector visibility 直接引用退出其作为唯一材质依赖、GPU 需求和 owner alias 的角色。上界只表示可准备候选，最终成功 domain 决定实际 GPU 需求。

ReferenceAnalysis 保留原有限 literal grammar（直接 String、平面 Object image 字段与现 workshop identity），由现 lexer 的 reference-token mode 排除注释/字符串伪请求，原请求 regex 退出；transition 子集 grammar 不变；该模式只服务所列 literal lane，不声明完整 JavaScript 词法或复杂 regexp/template 依赖分析。同 owner 的 helper/未知引用不再清空独立合法 literal。无法静态发现的参数、变量路径、registered handle、嵌套配置与模板表达式仍未闭合，缺 prepared 资源返回原局部 null。不得通过新 regex 分支或源码执行补这些语法。每个请求独立做原根内路径与可用 model 解析，未知请求不扩失败半径。

验收从原 Program→真实 VM→canonical mutation→原 prepared 动态资源消费者贯通四族；覆盖变量/资源改名与等价表达式、同 owner 合法 literal 加未知 helper、注释/字符串/text-only 假引用、不接纳/冲突 owner、两 owner 相同 raw literal 不同 canonical、原 Boolean 能力隔离。原 task 的 CPU 受控后端门覆盖 metadata 后等待与最终需求交接、空需求、取消和早失败；该门不运行 Metal，也不证明实际 load 次数。唯一动态 GPU 准备循环由源码职责审查及独立实际运行验证。独立运行侧用四族同材质图片和冻结变体检验真实四格像素，另保留未参与修改的真实输入。本片不证明完整 JS 依赖发现、动态文字 wrapper、官方全域兼容或性能验收。

## 静态普通图片的准备几何后继（2026-10-12）

模型策略仍由已解析 asset catalog 提供。原静态 descriptor 只采用作者 size/model width-height，忽略 autosize；原 GPU 上传尺寸不能替代资源自然尺寸。对现资源解析器已解析到普通静态图片的层，model.autosize=true 使用原 loader 的源图像自然尺寸；false 或省略保留显式作者 size，没有作者 size 且模型 width/height 两字段均缺席时采用已证 1×1。原 asset 解析 owner 保留字段存在性；在 false/省略的缺省1×1分支，单维或非法声明不冒充两字段缺席，保留其存量 fallback。true 仍使用有效 prepared 自然尺寸；官方宽高补测只覆盖合法正值 pair，未测单维/非法声明，不能把这两类产品行为称为官方 parity。原 initialConfiguration object 的 size 键必须真正缺席才能采用缺省；null/Array/不支持的 value 包装、显式 zero/negative 不冒充省略，仍保其存量解析值。追加官方自有静态矩阵已证模型 width=80、height=40 时：autosize=true 对显式120×60与省略均采用自然200×100；false/省略对显式保留120×60，省略继承声明80×40。故 true 的自然尺寸优先于模型声明，false/省略仍保持原模型声明 fallback；动态创建带 width/height 未测，不外推。named output、文字、Puppet、solid、video（复用现 TEX isVideoMp4，不以 isAnimated 代替）、sprite/animation 和其它专用资源保持原责任与尺寸域；不借动态 alias 资格收窄既有静态普通路径。

原 TextureLoader 的 preparation-only 自然尺寸入口复用 TEX 容器 metadata；PNG/JPEG 在同 ImageIO owner 读取 pixel-width/height 属性，不创建 CGImage、不上传纹理。读取前后校验同 SourceKey，读到的小型 metadata 写入原 PreparedBaseImageResources.Entry，在 decoded eviction 前保留。Entry 的 metadata 可先准备，outcome 缺席不计 GPU ready；deferred 请求继续原 pending/loading/ready/failed 生命周期，隐藏图片不会仅为几何而提前上传。原资源 task 在同一队列/condition 上先发布几何结果，再继续 GPU 准备；launch 等待 metadata 后继续 Program 编译与 GPU 准备重叠，最终仍由原资源 join 接纳。取消/失败沿原 task 退出，不能发布半准备 context，也不建立第二资源 registry 或几何生命周期。

同一 prepared size 结果一次覆盖 runtime/authored descriptor 的 sizeWH，保持 initialConfiguration 作者快照、size 原字段及其它属性不变。RuntimeInput 从准备后的 descriptor 构造现计划；所有 Script catalog、只读 getter、Cursor admission/local pixel、matrix、capture/effect/direct draw 消费相同几何值。普通帧不查文件、重读 header、重新解析模型、重建 Program 或维护额外图层状态。资源失败仍由原最小层资源消费者局部降级，metadata 成功不等于纹理或绘制成功。

验收沿原准备 owner、原真实 descriptor builder 和 VM catalog，覆盖自然尺寸不同于上传尺寸、同资源不同作者尺寸、显式/省略、资源与变量改名、等价表达式以及相邻专用资源/模型声明/显式零尺寸不误命中。deferred 必须证明 metadata 可用于几何而加载次数仍为零、outcome 缺席且状态 pending，随后原 worker ready/失败/取消保持原生命周期。真实 App 使用既有合法自有普通模型矩阵与独立 heldout，仅声明实测范围，不从大部分作者 size 恰等于自然尺寸推断新增画面收益或性能结论。

## 图层排序与共同候选同步

排序与其他属性更新互不覆盖，并保持原 domain 内真实调用顺序。真实 VM 反例已确认：同 callback 的 authored sort 与 alpha 合成一个属性 DTO 后，Swift 以 fields 为空识别 sort 而漏排序；先创建 X 排 C 前，再创建 Y 排 A 前时，早先 callback 复制的绝对 index 已陈旧；既有 dynamic X 只改 alpha 的完整 upsert 也不应贡献排序。不能只补 coalescing 标志或在 Swift 另建一次排序命令重放：init/events/update、Cursor 的多次合并和 owner 分组会改变 DTO 顺序，后置 owner 拒绝还会改变健康操作的上下文。

正常移动完成后返回 Boolean true，依据 [IScene 公开 Boolean 声明](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IScene.html)与已批准的固定官方普通新层移动黑盒结果，使作者可按成功返回继续写属性或排序。只改完成移动的成功出口；same-index/no-op 的返回、非法/越界和其它未测邻域保持原处理，不能扩成完整返回/失败语义 parity。真实 VM 须用严格 ===true 控制后续合法属性写入和第二次排序，并保留 TypeError 与 throw/撤回反例。

沿现 C topology journal 保持唯一排序执行权威，将其已有 baseline+有序操作重放提取为同一个可供 rebuild 与只读候选投影使用的实现。候选投影在 callback 全部完成后、共同提交之前，根据已接纳的 VM owner identity 过滤 pending 操作，保留 committed 操作与原全 domain 调用顺序；不修改 record、journal 或 VM heap，也不重跑作者 callback。没有 topology journal 时返回缺席，不在普通值帧构造完整顺序、解析或散列。安全错误沿原 owner/fixed-point 接纳失败，不能静默采用陈旧 DTO 的 index；固定点验证须包括只有 topology 参与身份而属性 mutation 已被合法裁剪的 effect 包。

原 C owner 仅导出 pending topology 的 owner identity，原 evaluation/owner-effect 包独立保留该参与身份；它不依赖会被 Boolean 返回合法裁剪的属性 DTO，也不受 coalescing/Cursor merging 影响，不是新的排序命令或 owner registry。原 domain 提供有界 typed raw order 查询，launch frame schema 将该纯投影交给现 DynamicLayerRuntime。原 runtime 仍独占属性/资源验证和 owner 候选：先验证 owner bundles，按接纳集合取得 C raw order，在原 finalizeTopology 内消费；普通动态完整 upsert 不再隐式排序。raw order 必须包含共同提交前的 authored tombstone 槽，随后沿原统一退休阶段移除 authored 层与其动态副本；不能提前删除再重放 index。外部命令拒绝和存储依赖 fixed-point 每次使用最终候选接纳集合重新投影，使被拒 owner 不影响健康 owner 排序。投影绑定同 launch/domain 生命周期，不跨 reload，也不持新对象树、namespace 或资源状态。

验收覆盖真实 VM→ABI→Swift candidate：sort 前/后写 alpha、两个 callback 创建顺序及不陈旧的相邻顺序、property-only dynamic upsert、变量/资源改名和等价调用、同 owner 多 callback/peer 交错、throw 与后置 typed/external rejection、dynamic destroy 和 authored 延迟退休。隔离普通图片 fixture 用有重叠的不同颜色层检验实际遮挡顺序，并由独立运行侧保留未参与修复的真实输入。测试 stub 仅供应外部 descriptor 元数据，不能替代排序、journal、mutation 验证或候选事务；构建与 VM 通过不计最终图像或全域兼容。

## owner

QuickJS domain owns JS object 与 callback roots；现役 Script bridge owns handle 验证与 mutation 编码；host frame transaction owns commit 时机；graph/resources owns 动态对象准备与释放。粒子作者播放意图纳入现役 `SceneScriptDynamicLayerRuntime` 的 typed layer state、candidate plan 和 immutable committed snapshot，C 只保存已提交镜像与 callback journal；不另建 session 意图库。各 surface 的现役粒子 runtime 仍独占实际 emitter schedule、存活、粒子 ID 与随机流，按 [D11](particle-playback-state-design.md) 消费有序转移。注册内部组件不能建立第二份对象树、simulation 或 clock。

## 方案设计与选型

选择**公开表面白名单 + 现役 handle bridge 扩展**。不把内部注册符号暴露成自创官方 API，不让脚本携带 native pointer，也不通过 JSON 整图序列化同步每帧状态。

| 作者表面 | 类型/返回 | 第一阶段行为及边界 |
|---|---|---|
| `engine.registerAsset(file)` | String → IAssetHandle | load/preparation 期解析允许根内资源；普通帧不得同步加载/编译 |
| `thisScene.createLayer(configuration)` | String/Object/IAssetHandle → ILayer | 先支持已准备的 asset handle 与可验证的 bounded object 配置；未准备配置显式局部失败，不返回假成功对象 |
| `thisScene.destroyLayer(target)` | String/Number/ILayer → Boolean | 复用延迟销毁、现役作者 identity 解析；不能复用已撤销 handle |
| `thisObject` | 按绑定归属为 layer/effect/property object | 保持现役 scope；不能把 component 属性写到 layer 同名属性，也不能为调用粒子四方法将 property/component object 偷换为 layer |
| `thisLayer` / 现役 scene layer lookup | ILayer；粒子层提供 IParticleSystem 能力 | 四方法挂现役 layer handle，再按 prepared particle profile 准入；实例参数脚本可经 thisLayer 操作所属粒子系统 |
| `IParticleSystem.play/pause/stop` | 无参 → void | 首片限已准备 root、无任何 authored child、恰一 supported 确定性 emitter schedule（periodic disabled 的有限 duration/burst 或默认连续排放，或 supported 且 duration/delay 各自 min=max 的周期窗口）；随机周期拒绝，转移语义引用 D11 |
| `IParticleSystem.isPlaying` | 无参 → Boolean | session 对当前代有效实例作只读 OR projection；同 callback 叠加有序 journal，缺实例返回 unavailable 调用失败，不能伪装 false |
| `IParticleSystem.emitParticles(count?)` | 可选 Number → void | 限定交付显式整数 0…1024，取现役更小预算；真实出生、调用期输入、同 callback query 与全 surface 准入见 D11。省略、非整数/非有限/非 Number、额外参数仍局部失败；实际验证范围见[执行记录](../../history/rf03-particle-playback-implementation-2026-10-02.md#rf03-explicit-emission) |
| `IParticleSystem.instance` | IParticleSystemInstance | [公开实例表](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IParticleSystemInstance.html) 的 alpha/size/count/speed/lifetime/rate/colorn 为 Number，controlpoint0…7 为 Vec3；各字段消费相位单独验证 |

普通 JS 自定义对象仍由 VM 管理，不因此变为可渲染对象。2026-10-02 再核[公开 globals](https://docs.wallpaperengine.io/en/scene/scenescript/reference.html)及[IThisPropertyObject](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IThisPropertyObject.html)：thisLayer指当前层，thisObject随属性归属动态变化；不能用人工把thisObject设为layer的C夹具代替真实实例参数脚本。component callbacks 首片只接现役 init/update/destroy 生命周期。`registerSceneScriptComponent` / `sceneScriptComponentAPI` 是内部装配命名候选；未找到公开签名的“注册任意组件回调”保持 unsupported，后继须补官方声明与独立合同后才扩大表面。

handle 包含 scene generation、owner kind、object identity 与生命周期 epoch；C 与 Swift 两侧校验。create 先返回本事务 provisional handle，只在该事务内可见；准备失败回滚并撤销 handle，不能有部分 publication。destroy 在安全帧边界撤销，保留 GPU 资源到 completion；destroy callback 最多一次。

安装发生在 descriptor/resources/handles 准备后、首次 init 前。update 不得递归触发另一轮更新；callback 产生的命令按作者事件顺序 staged。成功 JS 调用不等于已消费：先通过现役 callback/owner admission 的 Swift 验证，C staged mutation 与 Swift typed command 同时接纳或局部 discard；不能只撤 Swift 结果而留下 C 状态。共享 session 已消费的 VM 回调、对象命令和模拟状态服从 [D10](frame-admission-retry-design.md)，后续任一或全部 surface 的 drawable/encode/GPU 失败都不能重放回调或恢复旧命令；JS heap 本身不作为可回滚快照。

显式发射调用期输入和最终准入由[D11](particle-playback-state-design.md#显式数量发射后继切片2026-10-02)拥有；native hook只借当前cadence实际runtime。instanceoverride脚本返回值在callback后overlay，不倒灌先前出生，不因最终参数不同拒绝emit。

**实例alpha后继（2026-10-04）。** 自有官方2.8.0.42黑盒已证`thisLayer.instance.alpha=.25`使灰128的新粒子变32；4秒切换后长寿命旧粒子仍128，绑定返回值同相位。沿现layer handle暴露只读instance句柄，首片仅alpha Number getter/setter；getter取当前代镜像及本callback overlay，缺省1，setter须有限Number并复用现因子消费，不借generic layer alpha。其他instance字段不得假成功写入；普通非粒子、已销毁/旧代句柄局部拒绝。粒子类型与实例可用性独立于播放命令的单emitter/无child准入，不因此拒绝已有正常粒子参数路径。

复用layer mutation journal增加独立particleAlpha字段，原owner effect bundle、预算及fixed-point同时接纳/撤回；Swift启动预注册`.particle(id,.alpha)`定义，以typed snapshot为唯一提交权威，C仅镜像。无authored instanceoverride时沿原resolver使用中性默认，不新增参数库。新值作用后续出生，旧粒子不重乘；root/child沿现override继承。`alpha=A;emit;alpha=B;emit`由既有同步hook捕获各调用前缀，后置属性return不改早先出生。本cadence已准入setter进入现snapshot再自动模拟，跨callback仍读cadence已提交镜像；throw/owner拒绝撤回C/Swift及出生候选，GPU失败不重放。getter写入字段不等于整套instance API已开放。不选择普通可写JS对象（无消费/回滚）或整层GPU乘数（误改旧粒子）。验收真实VM→Swift→Simulator的identity、无authored默认、0/.25/1、非法类型/非有限、旧句柄、samecallback读回、两次setter/emit次序、throw/late-owner拒绝及健康peer；App同输入灰32、无TypeError及Metal/drain成立，旧粒子与绑定控制保留。完成后归现脚本合同；其他实例字段、官方return顺序与完整样本parity继续单独验证。
同callback查询读取已验证overlay；stop/pause/play的query按D11实际存活及排放工作推导，不能直接返回playing Bool。其他callback含同owner的timer/event/update均读本cadence已提交镜像；本callback drain的microtask归当前journal。共享模拟后renderer观察结果，不等GPU。candidate保留domain.callback_epoch/ordinal顺序、转移及revision，不按owner分组猜序或把stop→play压扁；owner拒绝须移除其命令并重算。每surface模拟前消费一次；committed只留intent/revision供rebuild，旧transitions不重放。

首次init/cursor/update前，完整同代surface必须完成粒子准备并发布真实query projection；prepareLaunch模块装载不算init。各scalar/string/vector/cursor共用该顺序，不能从缺失屏或空集合发布假查询。首launch保留现warm-up的prepared-live：init.pause只阻止后续出生，init.stop在首次模拟前清live/batch/history。rebuild须在构造前注入committed paused/stopped，禁止先warm-up再补开关。官方warm-up/init次序未知，不声称parity。
预算沿现役 VM time/memory/stack 与 aggregate mutation cap，不另开无限队列。首片项目上限为每 owner/frame 256 条 mutation、每 scene/frame 1024 条新增 API 命令、每 scene 128 个动态渲染对象、单次 emit 1024 个、每 scene 65536 个存活粒子；同 owner 的 cursor、timer、event、update 等 effect bundle 合并计入 owner/frame 上限，不能靠拆 callback 重置预算；每个实际有效上限取此值与现役对应预算的较小者，绝不借本设计提高旧上限。待销毁对象占用对象配额及既有 resident-byte budget，GPU 未释放不能返还配额。数字是保守项目配置，不是官方限制；实施时进入既有机器预算并以临界值/超一值测试冻结，调高必须附压力证据与显式基线变更。回调注册计入既有 VM roots/内存与命令配额，未建立可计量预算的 profile 不准入。

## 作者图层跨层删除后继（2026-10-07）

真实首断点是开场控制脚本删除另一个已准备作者图层时被自层限制拒绝，导致淡出中的暗幕和Logo永久残留。公开[IScene](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IScene.html)允许按name/index/ILayer删除并明确延迟生效。本片已沿现authored mutation journal允许有副作用权限的owner删除已准备、有效、无子层的作者图层；只改两个guard会遗留死层脚本，不能作为交付。Boolean controller跨层删除不改自己的返回值，自毁才归并false；有效删除请求返回true。纯value-only、陈旧句柄、子层级联与未准备对象不借此开放。

唯一DynamicLayerRuntime在候选plan中保留动态层的创建owner归属，接受作者层删除时一并移除该层脚本创建的动态渲染对象；同一plan撤回全部相关变化。共同模拟commit先finalize所有peer journals，再按新接受的tombstone退休目标层scalar/string/vector/cursor cohort，复用现生命周期teardown清timer/jobs/ended roots与C动态层，销毁回调至多一次。共享owner不得重复退休；从后续update、media、cursor调度剔除。teardown沿现清理合同，不把destroy回调里新发出的绘制命令另开嵌套提交；其跨对象副作用完整语义仍待独立生命周期后继。资源保持launch/residency/completion所有权，不因删除释放在途GPU资源。当前cadence使用原topology，下一cadence投影移除；不等待surface/GPU成功，也不重放已消费脚本。

Scalar/String通过现生命周期bridge内的value-owner协议共用一个退休入口；Vector复用同一清理循环，Cursor只负责自有owner及借用注册注销，不新增生命周期owner。没有待退休owner时不重建binding属性表。

不新建对象树、clock或销毁队列。拒绝owner的删除不触发退休；先写后删、销毁优先规范化的删后写、重复删除、未完整请求的child分支拒绝、被删provider/组合成员不回生均需反例。已实施证据见[删除与退休记录](../../history/authored-layer-retirement-2026-10-07.md)。核心门为真实parser→VM→typed plan→下一帧descriptor，目标timer/update停止、健康peer保持、动态副本同步移除、throw/Swift拒绝无提前退休，以及原样本4秒后暗幕和Logo退出真实合成。官方精确callback先后、多屏呈现及父层级联另验，不能把局部leaf实现称为完整IScene。

**完整显式分支删除后继（2026-10-16，有界已实施）。** Project Bool入口接通后，真实owner同时明确删除Logo父、子层，但旧leaf guard在父层先行拒绝整笔。只允许同一个owner bundle明确包含所有仍存活作者后代的删除请求；按原descriptor的声明及实际parent边核完整性，各请求仍独立校验identity、预算、字段、顺序及重复删除，任一失败撤回整owner。已提交child tombstone不再阻止清理空父层。复用原tombstone、下一帧topology、cohort退休与在途资源寿命；不隐式添加后代、不跨peer凑齐删除、不扩大单独parent删除或另建子树owner。正反门覆盖父先/子先、多级完整/缺一、漏报child、后代无效/throw、跨owner和同帧回滚；实际原包需同时证明Logo退休与口罩effect切换，否则保留后续断点。

<a id="puppet-query-render-pose"></a>
## Puppet 本地查询与物理姿态分域（2026-10-17，有界已实施）

**目标与范围。** 固定官方客户端的[同输入观察](../../history/repeated-puppet-drag-qualification-2026-10-16.md#official-pose-query-observation)已区分本地查询与物理世界姿态：平移物理骨的一次 origin setter 在同 callback 可读，下一 callback 的 origin/local matrix 回到动画基值，世界矩阵与网格仍回弹。实施前 physics 和 setter 共写持久 override，污染后续本地查询。本片只修正已准入平移物理骨的局部 translation 投影与寿命；rotation/scale/其余 matrix 分量及没有该物理配置的骨保留原 setter 行为，其更广寿命未证。冲量入口、方向空间/单位、角物理及其他 profile 仍是后继，不为通过本片猜测实现。

**唯一职责与旧链退出。** 原每实例 PlaybackState 继续独占 evaluator、物理位置/速度和 script overlay；物理推进只写 render pose，退出覆盖 query pose 的旧写入。明确 query-local 与 render-local/world 两种 typed 投影：本地 getter 的 translation 使用动画及当前 cadence 的脚本覆盖，其他 matrix 分量保留原投影；世界 getter、attachments、cursor 与 skinning 使用同一物理姿态。物理骨的局部 translation overlay 在新的 simulation cadence 退出，物理位置和速度续存；回弹目标仍由动画给出，不能改为 last setter。复用原 simulation frame identity 防止同 cadence 重绘/重试重复推进，不另建时钟、solver、资源或状态 owner；原 motion 算法仍是项目近似，不宣称官方数值一致。

**VM、失败与生命周期。** 沿现 pose publication 和 configure ABI 同时安装 query-local/render-local，parent/name 与 layer-to-world 保持唯一来源；C 只保存已发布镜像、同 callback overlay 和原 rollback baseline。新增 render-local 镜像及 baseline 仅为实际配置骨骼的 owner 按骨数分配、稳定布局复用并由原 owner destroy 释放；不能把固定最大骨数的新增数组摊到所有普通脚本 owner。local setter 更新该骨的两个镜像，world setter 通过物理 parent 求局部矩阵；重算 world 时保留未写骨的物理局部姿态，不能从纯 query-local 重建而抹掉其他骨的运动。完整候选验证后才发布；坏矩阵、父层不可逆、throw 和 Swift 晚拒绝沿原整 owner 撤回。GPU source-update FIFO、几何 publication/退休与多屏准入不扩域，不附带 pose/skinning cache 重构。

**验收与退出。** 真实 QuickJS 门覆盖不同 query/render 的父子与 layer transform、本地/世界 setter 同 callback 读回、未写物理邻骨、rename/等价表达式和失败撤回。原 PlaybackState/Metal 门覆盖一次 setter 后本地复位而世界/网格继续、同 cadence 不二次推进及下一 cadence 正常回弹；隔离 App 验证实际 setter 画面及未参与修法样本。该片不关闭 U40：实际释放链仍须有序 impulse/matrix journal、一次 simulation commit、原输入三轮持续拖动及释放后更新；不得将 getter 修正或原包 ready 记成重复交互恢复。

**既有矩阵命令顺序后继（2026-10-18）。** 同层不同属性 owner 可写同一骨；cursor 按输入事件执行后按 owner 打包，帧驱动直接展开会将 A₁→B₁→A₂ 重排为 A₁→A₂→B₁。保留唯一 owner bundle 接纳/撤回，在原 matrix journal 记录现 domain 的 callback epoch 与 callback 内 ordinal；所有 owner 完成固定点接纳后，仅在原提交边恢复顺序，再交原 PlaybackState。没有新 counter、物理状态或跨 domain 排序，不合并同骨写入；失败 owner 退出不重放健康 peer。真实 VM 证明交错写入、同 callback 多写及拒绝后的保序，原生姿态和独立 Puppet 作实际回归。本片不新增 impulse/reset 或改变 setter/getter/物理公式，不以命令顺序修复关闭 U40。

## Puppet 动画层后继（2026-10-07）

目标是让作者 `animationlayers[].visible` 及其 `IAnimationLayer` 控制进入真实骨骼、alpha、挂点和合成。它不同于属性 Timeline，不能借 `getAnimation()` 冒充。固定官方 2.8.0.42 自有黑盒确认：隐藏层冻结帧位置而 `isPlaying` 仍为 true；恢复后继续。`play(); setFrame(frameCount*.93)` 同 callback 保留小数位置且继续播放；getter 即时变化、公开骨骼姿态下一 update 才变化。暂停定位的 raw getter 保留负值和超尾值，姿态采样钳位到首尾；自然循环仍取余。现有自然播放 TRS 小数插值已由 controlled 轨道 0/.5/1 验证，不替换数学。研究原件暂存 `/private/tmp/mwx-puppet-seek-20261007/official`，不将单版本实验外推完整 API。

**第一片已实施：共享播放位置与隐藏恢复。** LaunchContext唯一播放owner与所有surface共用采样已接通，旧三处独立取帧退出；相同定义重建保留位置，暂停重建新恢复层补入当前冻结快照。稳定合同归[高级对象覆盖](../../capabilities/advanced-object-coverage.md)，验证与限制归[完成记录](../../history/puppet-animation-visibility-2026-10-07.md)。不再作为待开发项；下一片沿现owner扩展，不重新建立播放状态或clock。

**第二片已实施：作者脚本入口与有界控制事务。** 精确解析 animation-layer wrapper 和稳定身份，Boolean 返回值只写该动画层，绝不能写父图层 visibility。首次 init 前安装由已准备 MDLA 提供的 metadata 与真正 IAnimationLayer handle；先闭合本层控制，再另验跨层 lookup/create/destroy。命令沿现 owner effect bundle 的有序 journal、预算、Swift fixed-point 验证和共同 commit/discard 接纳，应用于同一 session 播放 owner；C 只保存 committed mirror 与当前 callback overlay。phase seek 和自然推进分开，所有消费者仍使用一个快照。不得为了 `'addEndedCallback' in thisObject` 分支提供空方法；ended 注册必须有真实有界 roots、实际结束事件、teardown、失败原子性和不重放的 cadence 消费。自然loop ended已证在帧推进后、普通update前且读到wrap位置；最终GPU相位、mirror及跨多圈等未定行为先用有界实验裁决，不能凭方法名称猜测。真实 authored init→VM→typed command→次帧 pose→GPU/compositor、throw/Swift拒绝/stale handle已验；证据与未验的多surface联动、官方GPU相位见[完成记录](../../history/puppet-animation-control-2026-10-07.md)。

本片实施边界：nested owner 同时绑定父图层 ID、动画层 authored index 与 ID；首次 profile 只准入 ID 存在且父层内唯一的 `visible` Boolean wrapper，复用既有动画层 typed visibility target，避免另造动态值通道。Script properties 继续复用通用 codec。脚本静态隐藏的 clip 也必须准备，返回值与控制命令均不能误落到父层 visibility。跨层 lookup/create/destroy 不在此片。

控制数据由共享播放 owner 发布只读 metadata/state 快照，C handle 只持身份、镜像及有序 callback overlay。play/pause/stop/setFrame 和 rate/blend/visible 的写入进入同一个 owner effect bundle；原始帧位置与渲染采样位置分开，显式越界 seek 只在采样端钳位。普通帧先推进播放并发布骨骼，再执行脚本；本片以已证的下一帧姿态作为验收下限，最终 GPU 相位不冒称官方一致。ended 注册必须在现有事务成功时保留、失败时撤销，使用实际自然结束事件并在 update 前执行；重复 cadence 不再次消费，未知 mirror/跨多圈行为需明确有界 profile，不能用假回调掩盖。控制命令上限取既有 owner/frame 与场景通道预算较小者；失败拒绝整个 owner bundle，重算其他 owner，不扩大到整个父层或 scene。

<a id="puppet-animation-layer-lookup"></a>
### 已准备 Puppet 动画层 lookup（2026-10-16，CPU及self-index GPU有界已验）

**目标与取舍。** 公开 [IImageLayer.getAnimationLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IImageLayer.html#getanimationlayer-name-stringnumber-ianimationlayer) 按 name 或 index 查现有动画层，[IAnimationLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IAnimationLayer.html) 的 play 恢复、stop 停止并复位；不能用属性 Timeline 或当前 nested owner 的别名代替所查 target。一次开放任意 layer handle 会扩大跨父层权限、target 生命周期和事件归属；当前实现限已有 prepared Puppet nested-owner 经 thisLayer 查询同 parent 的已准备动画层。String 名称与有限非负整数 authored index 均解析真实 target，不按样本、名字或当前动画 ID 分派。真实中性资格证明 receiver 是同 parent thisLayer；335最初在参数解析前被资源准备合同拒绝，后继读源和资源资格确认其按String名称查同parent目标，资源事件与实际播放进展归[事件链路](#puppet-animation-events)，不由lookup入口存在性推断。

**准备与身份。** 复用 ScenePuppetAnimationPlaybackRuntime 的定义、snapshots 与唯一 SceneClock；原 domain publication 入口持唯一 prepared committed 镜像，含 parent layer ID、authored animation index、可用 ID、名称及 clip metadata。无匹配、重名、越界/非整数 index 局部拒绝。仍在 publication 中的同 identity 临时坏数值、metadata 不符或重复 identity 只令该记录不可用，保留一份旧名称/metadata/incarnation，恢复原合法输入可恢复；真正缺席后重现分配新 incarnation，旧缓存不回生。稳定布局先全量验证 identity/metadata/有限域，再原位更新数值、复用 names/incarnation 与 prepared source 索引，健康路径零 C 分配；这是实现结构，不是性能收益证据。无动画创建、模型发现或动态 clone 动画准入。

**镜像迁移。** 原 thisObject 与新 lookup 共用 target resolver；owner 单 animation committed/overlay/name 副本已退出。getter 从 domain committed 记录重放本 owner 同 identity 的有界 command journal，其他 owner 的未提交命令不可见，不缓存另一套 target overlay或推进 C 时钟。原自层 Boolean 返回值仅保一项 owner-local typed 当前值及 journal 截点，维持自 target 的 visible 读回与原 setter 优先级，绝不写 sibling 或冒充播放位置；此投影同样可撤回。

**命令与提交。** 句柄绑定 domain、source owner identity/generation、resolved target identity 和 incarnation，每次 callback 重验 source 为已准备 nested-owner、parent 相同及 target 存活；同 owner 跨 callback/timer 可复用，跨 owner、旧代、同代删除/退休、callback 外均拒。Swift 沿显式 prepared source→同 parent target 验证再复用 Runtime.validate，未删除安全合同。play/pause/stop/setFrame/rate/blend 沿原数值域和有序 journal；同 owner 未提交的 initialize、事件、update 共享最多64条命令，仅通过 export cursor 导出当前 primitive 新范围，避免 Swift 重复收集，不另开通道或提高原 owner/frame/scene 预算。

**回滚与旧能力。** native accepted bundle 是唯一 commit；失败或 fixed-point 剔除由原 TimerSnapshot 恢复 count/export cursor、溢出状态、timer/ended roots 与自层 Bool 投影，其他 owner 和播放状态保持，已消费自然 ended 序号不倒退。共同 barrier 清 journal；C 在 finish 不改共享镜像，下一合法 cadence 仍由真实 Runtime 发布，未另加发布 producer。最后 configured Puppet owner 释放时清 catalog，名称只由 canonical 记录持有；生命周期不新增第二 registry。

**冲突边界。** thisObject 原 self visible setter、Boolean 返回值仲裁和 ended 注册/派发保持；lookup 回 self 走同一路径。sibling visible setter 与 addEndedCallback 显式拒绝，避免绕过该 target 的 typed visibility producer 或把结束事件注册到调用者；getter 和已准入播放命令按真实 target 工作。跨 parent、非 nested owner、任意 layer handle 后继另验，不借方法存在宣称完整 IImageLayer。

**有界验收。** 最近真实 C→ABI→Swift→共享 Runtime 的15项host门、22项邻门及签名Debug通过：name/index、改名/等价数字、self/sibling不同target读回、stop/play、缓存句柄、多primitive新范围、回滚、临时坏值恢复与真实缺席后的ABA拒绝均在CPU链验证，原self visible/ended边界保持。自有单parent输入仅使用已准备layer1221/index0/id6070、clip2471，lookup(0)的stop于frame0提交，timer play于frame29提交；stop生效后frame2–26的9个GPU骨hash相同，play后111条记录有79个不同hash，122条draw均GPUcompleted、4222顶点，退出正常、输入无漂移且GPU排空，root与独审查看after。此为`S4 bounded single-parent/self-index0`，不外推name或sibling GPU、完整原包、官方parity或性能。普通有界证据归 `.artifacts/scene-evidence/runs/puppet-animation-layer-lookup-20261016/`，保留14天。

**原包初始边界。** 最初335因MDLA0006现代尾部被整段零合同拒绝，lookup随prepared source退出，命令0；这份历史失败及原始身份保存在 `.artifacts/scene-evidence/runs/puppet-auxiliary-trailer-20261016/`。后继已定位其中事件记录，现状只由[事件链路与限定验收](#puppet-animation-events)拥有，不再把旧unknown当当前STOP；跨parent/任意layer handle、模型或动态动画创建和完整官方parity仍未闭。

<a id="puppet-animation-events"></a>
### Puppet 源帧事件与动画接续（2026-10-16，有界实施与原包接续已验）

**目标与取舍。** 修复合法现代MDLA事件记录被零填充合同拒绝、以及prepared动画无法经`animationEvent(event,value)`接续播放的共享链。335的同一资源两clip分别有1/0事件，事件名与nested Bool脚本输入精确匹配：初始化停止目标clip，收到另一clip的命名事件后播放；只读资格不算已恢复。公开[事件指南](https://docs.wallpaperengine.io/en/scene/timeline/animationevents.html)与[AnimationEvent](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AnimationEvent.html)提供源帧、name/frame及同层callback表面。选择复用原PlaybackRuntime和owner事务；只放松reader会漏掉真实事件消费，另建surface计时器或完整Timeline事件平台均不采用。

**资源与准入。** 现现代尾部拆为已验证的零六浮点字段、缺席后续scalar曲线及有界事件列表，不再整体按29零字节处理。保留每条事件的原时间字段及JSON的name/frame，按长度、数量、有限性、帧域和已知字段验证，错误仍拒该动画组并走原layer bind fallback。首片只接loop正向、内部非零源帧、正rate；0/end边界、mirror/single事件及未解释曲线继续显式拒绝，原无事件profile不收窄。JSON.frame作为本项目有界源帧调度合同；原时间字段保留，不据单一时间/帧对应宣称官方单位或精确时序。额外兼容性检查须写明项目策略，不复制参考实现或固定资产字节。

**唯一时钟与派发。** 原launch-owned `ScenePuppetAnimationPlaybackRuntime.advance`在既有可见/播放/rate的phase增量上产生immutable occurrence；暂停、隐藏、rate0和同cadence复用不新增事件，seek/stop命令本身不补发穿越事件。顺序按同parent内实际跨越位置、authored clip/event顺序稳定；首片只跨0或1个loop边界，区间内事件按预算枚举，更多圈或超预算报局部失败，不截断后声称成功。原FrameDriver一次发布给domain，各surface仅消费原pose，不发callback。

**最小消费者与事务。** 首片限已准备的Puppet nested Bool owner，接收同parent各clip的事件；不借假的layer身份或扩大跨parent权限。原owner在init完成后、update前调用`animationEvent(event,value)`，Bool返回更新原typed值，undefined保输入；命令与返回值进同一owner bundle，沿原Swift admission、fixed-point和共同commit。其余值族/非Puppet/Timeline事件不随片开放，但未接线的export不能撤掉既有init/update或文字clone。事件接入原owner有界pending队列，occurrence identity使同cadence重复publication不重入；消费游标与原TimerSnapshot/journal共同commit/rollback，下一cadence仍保留未提交payload。暂不可用而identity/incarnation仍合法的receiver保队，恢复后执行；真实退休才清旧事件。callback失败只影响该owner；健康peer继续，源播放不因单个receiver失败倒退。队列满不能静默丢事件。既有JS heap不回滚，不能把native撤回写成任意脚本堆事务。

**成本与退出。** 无事件cadence不扫描全owner派发、不序列化场景或重新读MDL；无事件owner不内联分配整份FIFO，首次真实事件才分配有界队列与payload，并计入原VM内存预算。资源解析只在准备期，事件与消费状态由原PlaybackRuntime/VM owner各持其职责，不建第二clock、资源registry或提交权。propertyRefresh不派发/消费事件。事件队列及callback引用随owner退休归零，reload不跨代重放。

**验收。** 自有两clip MDLA及真实C→ABI→Runtime门验证改名/等价JSON、event 1/0相邻资源、正确parent、未初始化、Bool/undefined/坏返回、同cadence与跨cadence拒绝重试、暂停/隐藏/seek/rate0、loop穿越、预算、throw/晚拒绝和退休；不复制作者脚本作测试算法。签名Debug后用原335证实际准备、init stop及事件后play命令、目标clip推进和GPU骨变形；未参与修法样本保播放与退出。没有事件后实际目标推进或出现新的更早准备缺口就停下重排，不把reader通过、base动画或非黑当事件恢复；官方同相位与性能收益另验。

**限定结果。** 原生产链reader门30 PASS/1既有资源skip，PlaybackRuntime原27项通过、最后两处修订仅补6事件门，真实QuickJS/Swift18项通过；最后event/name分配异常guard另经C闭包编译及静态独审，辅助standalone低heap行为资格失败不计PASS。签名Debug后原335的524/index1/id751于frame0提交stop、frame3因源事件提交play，目标clip510快照由42.445推进至262.283并loop回6.831；131条5805顶点骨输出均GPU completed且各hash不同。原包画面人物/纸片/雨/倒影已查看；独立379人物/花朵/图案保留，两run均exit0、输入无漂移、surface1→0与GPU排空。关闭旧资源准备STOP及该String-self事件接续，不外推任意sibling、完整样本/官方相位或性能；身份、证据与剩余范围归[事件运行记录](../../capabilities/runtime-evidence-current.md#e-2026-10-16-puppet-animation-events)。

## 属性 Timeline retained handle 后继（2026-10-08）

真实作者在 `init` 保存 `thisObject.getAnimation()`，随后在媒体事件调用 `stop/play`；原 callback epoch 限制使该合法同 owner 调用报 stale。公开 [IThisPropertyObject](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IThisPropertyObject.html) 返回当前属性的 [IAnimation](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IAnimation.html)，未规定 callback 临时寿命；此片不冒称已有官方缓存行为黑盒。沿现 property Timeline bridge 保持当前 target、play/pause/stop journal 与唯一 Timeline runtime，组件及图层的 accessor 和返回 handle 共用 domain、单调 owner identity 和 generation；每次调用从当前 active owner 解析并校验同身份、同代、未禁用和当前 Timeline 可用，不保存可能释放的 owner 指针。合法 init/event/timer/update 间复用成立，callback 外、跨 owner、销毁或同代重建均拒绝；JS throw 和 Swift 拒绝继续走既有 owner bundle 接纳/撤回，不因 handle 持久化重放命令或新增 clock。named lookup、rate 和其他 IAnimation 方法不在本片。真实 VM 及 ASan 门验证 init→media、事务拒绝、disabled、generation、销毁重建后保留的 handle、`thisObject` 和 detached accessor，以及健康 peer；实际原包运行另证。

含 `init` 的属性脚本仍可能变换值，不能仅因没有 `update` 改判为纯 Timeline 控制。已准入且带 Timeline 的 scalar 值管线在 idle 只投影当前 typed 输入和原有有限数据属性 overlay，保持 SceneScript 值发布而不重跑 VM。单次求值结果不可变地保留是否透传输入：本次实际 init、pending initialization、update 或有限 bound overlay 的主动值不标为透传，不按数值相等推断来源。现有 frame admission 在同一次已接纳 Timeline preview 上更新透传值，仍发布 SceneScript source；投影复用原 target scalar 校验，非法候选保留已验证当前值。固定点拒绝后沿原命令集合重算，不重放回调、再次读属性或新增 preview/clock。没有命令的普通帧保留原值，失败/disabled/退休和旧 snapshot 恢复继续遵守原 owner 生命周期；event-only Timeline 控制保持唯一 Timeline 值 producer，无 Timeline 的稳定 owner 保留原 idle 跳过。材质 finalizer 不放宽 source 校验，也不以 authored fallback 掩盖缺失输出。

<a id="general-bloom-strength-timeline"></a>
## General Bloom strength Timeline（2026-10-16，有界实施）

普通 LDR `general.bloomstrength` 的 absolute scalar animation 已接入原 Bloom 消费者；本片复用原 Timeline 及后处理，不新增 scene Script API、插值算法或 clock。

`SceneDocumentLoader` 从 sourceRoot 的原始 general 保留共享 `SceneTimelineAnimation`、作者 fallback（缺省1）、非 null Script 标记和诊断；effective general 仍生成启动当前配置。可选 general Timeline IR/diagnostics 位于 prepared descriptor 根层，不塞入 camera，也不把 saved/current user 值当作者 seed。compiler 以原始 seed 生成 `.scene(.bloomStrength)` binding，经现有 definition merge、PlaybackRuntime、SceneEvaluationTransaction/resolver 到 `SceneBloomConfiguration.resolving`；renderer 不读原 wrapper。

准入以实际 Bloom consumer 选择为准：只有 `camera.bloom.hdr == nil` 接纳本片 Timeline，HDR 保留 IR/diagnostic而无该 producer。`user+animation` 沿原 property/Timeline 优先级，重复目标按原规则；任何非 null Script 竞争源保真并局部拒绝该 Timeline，不执行脚本、不借 object 身份、不撤其他合法来源。scene Script producer（G9）现由[相邻后继](#general-bloom-strength-script)接入，Timeline与Script不争同一producer。

relative、group、错 lane、非法 wrap与非有限/坏结构沿原 parser/compiler 拒绝；消费端不可表示值沿现 fallback。原数值与 Bézier controls 保留，不按样本或关键帧极值添加非负/0…1 clamp。失败只退出该 producer，静态/property fallback、健康 layer及 HDR 消费原路保留。共享 playback/事务继续独占 pause/play/stop、preview/commit、取消与 snapshot 恢复；普通帧无新增解析、编译或 last-value cache。

生产链测试一次编译17项通过：原7 binding/15项保持，独立自有输入核 raw `.35`/catalog默认 `.6`/启动 override `.9`分域、frame40（40/30秒）输出1.36、loop、pause/stop/恢复、未提交候选保旧 publication、Timeline高于同 target user、改名/等价数字及局部拒绝。Debug构建30.708秒通过；测试不替代实际渲染。

受控静态白块只改变 strength Timeline：正值与zero hold图的571,536个本体像素无差，外部134,796个像素出现光晕，峰值50/255，主代理已查看。原3810943704候选22 image/43 effects实际 GPU completed、surface1→0、gpuDrained且无漂移，实图已查看；其原 Bézier保留，不称同相A/B、官方数值parity、全样本或性能收益。未参与修法的314完成12秒运行、exit0、无漂移、GPU completed与surface1→0/drained；独立代理实看壁炉/反光、时钟、频谱及音符光效，仅作回归，不推音频、Bloom因果或parity。

正式本机证据归 `.artifacts/scene-evidence/runs/general-bloom-strength-timeline-20261016/`；17项原测试收据在 `.artifacts/tmp/general-bloom-timeline-20261016/tests/attempt-01.json`。更广 general hosts、scene Script、HDR strength Timeline与未知值合同仍开放；需额外 clock/视觉算法时停止，不以局部门或ready外推。

<a id="general-bloom-strength-script"></a>
### General Bloom strength Scene Script（2026-10-16，有界实施）

**选择与最小结果。** 335事件接续已闭，307 speed的对象算术先作类型资格，不凭exception猜API。G9的213已证独立缺口：原IR保留普通LDR `general.bloomstrength` Number wrapper，首次Scalar projection错误地要求object身份，后续构造也强制layer；其init/update依赖既有audio16/average[0]/frametime，无新算法或媒体资源。先接一个返回值进入原typed Bloom消费者，优于重开未定Rope/world或无收益cache。公开事件和脚本参数合同沿原SceneScript；作者脚本只作输入与证据，不复制为测试实现。

**职责与身份。** 原ScalarProgram接纳唯一scene/general/bloomstrength目标：有限且Float可表示的作者Number、exact script/value包装、无user/Timeline/额外字段竞争、有效LDR消费者。原ValueOwner明确保scene身份且没有layer ID；layer/camera仍保真实source layer，不借layer0/负数/任意descriptor或camera冒充。构造不配置current-layer/effect/Timeline/Puppet权限，不做动态图片发现；原domain/module、audio registration、init/update、frame与generation/budget/teardown不另建owner、VM、时钟或缓存。层身份改为可缺席时，所有生命周期/注册及事件提取调用明确处理scene，不用强制解包或隐藏trap维持旧签名。

**事务与输出。** 原definition/Program publication经共同evaluation transaction/resolver到唯一BloomConfiguration；原通道优先级、作者seed与启动effective值分域保留。scene只准本次scalar返回，当前layer访问不得指向ID0；borrowed handle、任何material/layer/Timeline/media/texture/Puppet/particle命令或拓扑副作用都在现有完整owner bundle接纳处拒绝并撤回，不能只禁thisLayer而漏其他入口。静态peer与其他合法owner保留。坏返回、throw、陈旧代/取消沿原局部失败/回退；不新增长期last-value cache、不保证任意JS堆回滚，不静默吞已产生的非空effects。

**验收与退出。** 用自有改名/等价数字及audio/delta刺激，经实际VM→typed scene snapshot→Bloom resolver证明动态输出；同编译门纳入错误path/type/wrapper、HDR、竞争源、有限Double超Float、NaN/Infinity、borrowed effects/拓扑与健康layer/Timeline反例。原audio demand、pause/refresh、generation和teardown复用现门，改动只补受影响部分。签名Debug后自有可见白块在同App固定phase对比动态/零强度光晕，原213执行真实general callback并进入消费者，独立未参与样本正常渲染/退出；若需新API/算法、第二owner或假layer、或无法证明真实消费者，停止扩大并重排。此项不推断右黑块根因、HDR Script/full general host、官方同相位或性能收益。

**限定结果。** 一次focused门的53行为事实通过，覆盖真实Scalar/C/audio16→typed scene snapshot→生产Bloom resolver，三组自有改名/等价输入的1.2/1.25输出及相邻拒绝/恢复；首轮仅测试载体错误失败保留。最终签名Debug后，同App静态白块的零/正强度hold对照有571536本体像素零变化、152812外部像素出现光晕，峰值63/255。原213的scene callback已执行、首值0与非零AudioBuffers刷新均已证，作者后继非零结果未读回；不能据自有门称原包精确音频/Bloom ROI或右黑块恢复。独立314实图与正常退出保留；三run无输入漂移且surface1→0/GPU排空。具体身份、图与未覆盖归[限定运行证据](../../capabilities/runtime-evidence-current.md#e-2026-10-16-general-bloom-strength-script)，不计性能收益。

## fallback / route

unsupported API/配置是局部脚本调用失败，保留先前有效对象和画面；stale handle/跨 generation、越界、OOM/timeout/预算超限硬拒绝该不安全事务。禁止将失败返回伪装成有效 native handle。迁移沿现役 bridge `prefer-generic`→`generic-only`，旧 setter 同批撤权。

## 纠正门

- 公共签名、thisObject scope、返回类型与方法副作用分别用真实 QuickJS+Swift 门验证，不用 Python 模型或符号存在性代验。
- create→修改→destroy 同事务、throw 后回滚、C 成功/Swift 拒绝、超时、mutation 溢出、销毁回调再次销毁、旧 generation 回调均有反例。
- 粒子以非零 startTime 验证首 launch init.pause 保留 prepared-live 且不新增排放、init.stop 首图清旧 batch/历史；rebuild 的 committed pause/stop 不先 warm-up。有限非周期 schedule 自然结束后 play、固定周期 pause/continue、跨 owner 交错 callback 顺序及 owner 拒绝重算分别验证；实际未准备/陈旧 runtime 必须 unavailable。动态对象验证 prepare 次数、GPU completion、publication 与唯一 compositor；两帧不能重复提交同一 command。
- 公开未说明的默认/相位用固定官方黑盒区分；无环境时该 API profile 保持未开放，设计批准不作完整 API 兼容声明。

## 退役条件

表面与事务已由唯一脚本语义合同接管，所有开放 profile 验收、旧重复 bridge 撤权后归档。未证实 API 不可借归档自动转为支持。


## 命名属性 Timeline 入口后继（2026-10-10，已实施，有界验收）

U22实机副本点击命中后，`getLayer(...).getAnimation(name)` 缺方法，整个cursor owner事务失败，两个已编译alpha动画没有收到play。公开[ILayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ILayer.html)规定按名返回属性Timeline；[IAnimation](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IAnimation.html)的play/pause/stop语义与当前播放owner一致。选择保留动画options.name，由已经编译的Timeline Program在准备期发布不可变名称→typed target索引，QuickJS layer accessor与current-property accessor共用原animation handle/journal；Swift仅将稳定索引还原原target，沿现owner bundle、固定点、preview/commit执行，不增播放状态、clock或每帧解析。

首片覆盖layer/text自身属性动画；effect/material对象的命名范围、rate/seek等仍未实现，不扩大方法声明。缺名或同对象同名多target没有明确裁决时拒绝该lookup；不同layer同名必须隔离。句柄绑定domain、owner identity/generation与已准备target，合法同owner跨callback/timer复用；跨owner、退休/删除目标、越界索引、回调外及throw继续原拒绝/撤回。没有name的旧Timeline与无参数当前属性入口保持原样。动态创建层尚无Timeline编译来源，不能把静态索引套到clone身份。

验收：真实VM的异层同名隔离、retained/timer play-pause-stop、无名/歧义/过期/失败反例；同一Timeline runtime消费并生成alpha值。实际U22两次点击在同窗口驱动背景/水印alpha、视频持续播放；未验证官方完整逐帧交互与长时间性能不得关闭。新入口稳定后无需迁移owner，现役唯一Timeline runtime始终保留。

- 后继反例：独立cursor-only owner在点击内创建timer后不再求值；U22实际由借用的stateful Bool owner持有，timer到期后被typed cohort无条件拒绝animation。允许已有stateful Bool权限消费同一typed Timeline命令，纯只读Bool及material function边界不放宽。独立cursor timer缺口由自有VM门验证。该owner仍由CursorProgram唯一持有，仅在已有active timer时、cursor事件前调用既有typed evaluation并并入同owner effects；沿现有cadence消费与共同commit，不新增clock/调度器。构造继续拒绝init/update需求，借用owner仍由原Program推进，避免双跑。验收覆盖无新pointer事件时timer到期、snapshot helper恢复（不等于产品GPU丢帧重放）及借用owner不重复执行。

实施及反例统一归[历史记录](../../history/named-timeline-interaction-2026-10-10.md)，当前范围由API台账维护，不以局部交互代替完整样本验收。

<a id="scene-named-animation-lookup"></a>

2026-10-17 scene scope后继（已实施，有界验收）：固定v2.8声明的IScene.getAnimation(name)按名查询任意layer动画；322的合法点击先查询“切换滤镜”，现缺scene accessor且已有effectConstant编译结果被导出白名单过滤。最小片为显式String、存活catalog内exact唯一名称的scene lookup，加effectConstant的完整typed target导出。继续使用既有Program索引、retained handle、animation journal、owner effects及唯一Timeline runtime/SceneClock，不解析作者文档或增加播放状态。

同一不可变catalog加显式scene_only元数据：原layer/text为0，effectConstant为1，ABI只准0/1；scene查询看全部，原layer查询跳过scene_only，避免新nested同名把旧合法layer lookup变歧义。lookup handle单独标记scene scope，禁止复用UINT32_MAX（现代表current owner layer）；targetIndex仍指原bindings下标，不重排或从opaque index猜kind。catalog/target的domain、owner identity/generation、存活及退休校验不变；缺失、歧义、非法String/无参scene查询拒绝，原current-property无参入口保持。未证同名取首个、批播/Combined、动态clone新Timeline或新增控制字段不开放。

验收：原C/Swift门覆盖scene唯一与歧义、同parent同名layer/effect的旧layer隔离、仅effect名称scene可查而layer仍拒、改名/资源改名/等价表达式、坏scene_only/target索引、retained/cross-owner/stale/删除/16命令与throw整owner撤回；既有PlaybackRuntime实际消费play/pause/stop并使effect typed snapshot数值推进。一次最终Debug、自有同窗实际effect及原322点击控制与非零Timeline phase、独立原包/GPU排空和独审后才计入口恢复；2522 shader仍拒绝时只保其后继首断点，不把passthrough算作者滤镜。若需跨scope隐式猜名、重建图或第二时钟即停止重排。 实施沿本设计收敛；最近真实VM/typed门、自有特效像素与原322实际点击/非零phase归[限定运行证据](../../capabilities/runtime-evidence-current.md#scene-named-animation-scope-20261017)，不升级剩余目标或shader语义。

<a id="prepared-dynamic-image-material"></a>
## 已准备普通图片的动态复用（2026-10-12—16，默认材质有界实施）

10-12首片让作者通过初始配置取得image model路径后，createLayer继续消费既有dynamicImageResources、LaunchFrameSchema模板和DynamicImageTextureProvider。原资源owner在上传完成/失败回收后投影成功Entry的Loaded；model默认SourceKey须与Entry相同，保candidate/采样/texture身份，layer slot0 override不污染model默认源，显式资源优先。首片只准唯一model/material/pass、builtin image、单slot0、无常量/用户/provider、VERSION=2及translucent/disabled/disabled/nocull/alpha未指定。该plain专用资格现已由下述统一材质catalog接管，不作为第二入口；未知/custom/多pass不借纹理成功伪装普通quad。ColorModulationCompiler仍独占source Program语义lowering，不是资源引用资格，不重复调用它准备shader。

缺失、失败、延迟尚未准备的 Entry，以及 Puppet、composition、动画等特殊 provider 不借此开放。动态创建仍由原模板与拓扑事务检查，失败不返回假资源；资源随原 launch owner 保留，删除和 GPU completion 生命周期不新增权威。反例验证同 model 不同 layer override、没有原始成功 Entry、特殊来源和上传失败；正例验证共享实际引用且 load 次数不增加。初始配置的返回副本由 catalog/ABI/VM 合同负责，clone 的作者 size、perspective、text wrapper 和任意 model/material 语义不由该资源投影扩域；真实画面需另验，不把资源可用当成整样本通过。

**10-16后继目标与取舍。** 三条间接创建请求原已到达同一GPU就绪图片，却因默认材质含LIGHTING和metallic/roughness被plain资格拒绝；显式literal入口没有相同证明，纹理成功也不能证明材质执行。相比继续猜测旧TypeError或另造动态shader，本片复用现LightingProfileCompiler及lit consumer，最小结果是单pass、slot0普通builtin图片的静态默认材质进入每个新实例，保实例自身变换和原始资源身份。以上10-12纯plain范围是既有实现，不是后继已验收声明。

**唯一准备与消费。** 原BaseImageResources在launch按canonical model准备一次不可变默认材质fact；显式请求、初始配置间接请求及registerAsset共用builtin资格，不借源层的instance override、effects、脚本、property target或合成后纹理。仍由原LightingProfileCompiler产生profile，Resource只携带准备结果；GPU publication成功后与同一模板/catalog一起发布，再投影进唯一BaseMaterialProviderBindingProgram。现renderer集中查authored layerID，只有动态image才回落已准备model默认profile；lit pipeline预热含该表，光照仍消费同一frame snapshot与新实例自己的world/model矩阵。不增shader算法、provider、clock或普通帧解析。

**边界与旧路径。** 首片只新增builtin单slot0的静态LIGHTING及有限metallic/roughness；继续唯一pass与既有translucent/depth disabled/write disabled/nocull条件，未知combo/常量、动态wrapper/provider、optional normal/PBR map、reflection/emission和多pass均不因纹理成功准入。已有完整source Program及已获准的compositor lowering均在原join提供实际证明，不能冒充builtin profile或退回plain。固定官方客户端的自有透明parent目标把alpha转成灰度，省略/default/enabled两次预定ROI均无像素差；据此仅genericimage2+LIGHTING1接受default，不改通用render-state，不扩plain/genericimage4/default或enabled准入。官方直接证据限SDR、正交、ambient白、metallic/roughness=0；其余有限scalar沿既有alpha表达式不变是项目有界选择，不称全部官方像素等价。

**失败与退出。** canonical source不符、没有完整材质fact、上传失败或未完成时，原catalog不发布该资源，C与Swift都沿原局部拒绝；健康资源及当前画面继续。创建、晚拒绝、owner throw、destroy、旧generation与Session退出沿既有topology事务、GPU completion及launch资源退休，不缓存新layerID或给旧handle复活能力。移除原plain专用资格分支后由同一builtin材质准备入口接管；未证明的source Program范围不随本次迁移扩大。

**10-19透视neutral lowering设计。** 当前原包374330在非零PCM下频谱不可见，原source材质因透视不准入，统一catalog又正确拒绝只有纹理、没有完整材质事实的动态模板。选择扩现有neutral-tint证明，保留唯一catalog；不恢复旧纹理旁路，也不开放完整source Program的透视范围。只有既有quad attribute、无作者覆盖的host MVP、原UV、单straight-color采样及RGB/Alpha乘法已证，Bright/Power精确1、scroll0、无effects且每个显式消费者均有direct color consumer时，透视标记才不再拒绝lowering；最终位置继续由各自实例的既有world/MVP决定。非中性scalar的透视、任一未证兄弟/隐藏/named/依赖/特殊源、未知shader或状态仍局部拒绝。原binding在launch准备一次，经原typed material target和model表进入source uniforms；普通帧与资源/取消/退休owner不变。验收用变量/资源/等价表达式变体、透视与非透视同model、非中性/错误MVP/UV/兄弟反例及原包静音→PCM→静音实图，另取未参与修法样本；若频谱未真实恢复或引入相邻错误则撤回本扩域，不以Program命中关闭反馈。流星尺寸和同声源官方幅度另保开放，无性能收益声明。

**必要验收与停止。** 自有同model静态/动态lit消费者验证光照、材质常量及各自变换，变量/资源改名、等价构造、literal/间接/register入口与plain、完整source Program邻例；覆盖override污染、未知状态/常量、坏上传、失败撤回和退役。真实原包默认输入证明三条null消失及实际旋转，shadow模块默认Off不能误判缺影；开启Static/Perspective只在隔离声明输入变体中验实际边缘ROI，另取未参与修法样本实图。若现owner不能闭合材质执行或关键状态仍unknown，停在资格而不删guard；没有同条件测量不报性能收益。

## Sound 播放控制接入（2026-10-12）

目标是把作者对已准备 Sound 层的 play/pause/stop/isPlaying 接到唯一 SceneSoundPlaybackRegistry，首验 MP3 loop/single 与 startsilent。公开ISoundLayer描述启动、pause保留位置与stop重置计时，未明确重复play位置；本次黑盒对照补足single重复play和同回调查询，宿主暂停仍按产品生命周期合同验证。本次播放方法不扩volume脚本属性（后继见下节）；random/spatial不借此准入，OGG后继见[平台格式门](#sound-ogg-native)，失败仍只影响相应脚本owner或声音资源，不改变视觉算法。

复用现video command buffer/owner effects/frame validation/commit链，将其显式泛化为media playback command，携带videoTexture/soundLayer destination；保留一个64条预算与一次收集，不复制Sound回调/事件/遍历。旧Video名称迁移后退出，不保留alias或第二命令buffer。Video纹理handle沿原接口，Sound方法复用普通layer handle身份/过期检查；只对prepared registry有来源的层开放。查询读取当帧已发布状态，并在公开/黑盒合同要求时投影当前callback暂存命令；只读Bool仅可查询，不获得播放权限；异常、捕获后的预算超额和owner拒绝均随原事务丢弃，不在VM调用中操作AVPlayer。

帧前发布registry状态，现owner fixed-point admission分别交video/sound唯一registry无副作用验证，完整owner成功后才按命令顺序执行。play/pause/stop是可逆作者意图，宿主pause独立阻止实际播放，resume不得把脚本停止/暂停或startsilent对象改为播放；ready回调也服从同一意图。Sound registry stop仍是epoch销毁，不作为脚本stop复用。官方自有2秒MP3双层对照确认：single正在播放时再次play从头，pause后play续播；single播完后play可重建同player的item。loop重复play位置未证，保持原连续行为并登记边界。停止重置用现AVFoundation定位，不新增时钟或PCM播放器；已提交的authored layer销毁按ID从同registry撤observers/looper/queue，其他层继续；场景退役清整registry，迟到事件不能复活。首帧会在surface安装内同步执行，故registry必须在rebuildSurfaces之前建立并继承候选暂停/静音，失败由原session stop回收。

Vector applyUserProperties原已执行，但live state仅登记Scalar/String导致属性切换fallback重建；沿同一consumer map给Vector补真实callback owner/已声明key，失效owner仍由all−active拒绝，不新增属性解析器。

验收：真实VM方法→typed destination→owner提交/拒绝→AVQueuePlayer时钟与查询；startsilent、重复play、pause位置、stop归零重播、single自然结束、宿主暂停/恢复与停止后恢复、stale句柄/跨owner/throw/超额回滚，Video原方法回归。真实3761619125选曲脚本四MP3进入链，其他样本仅报告准入子集。Debug构建、独审及隔离运行，不把方法存在或player ready当成已播放；无法验证的模式继续记录首断点。

<a id="sound-random-playback"></a>
### Random Sound多源接续（2026-10-16，有界实施）

**目标与取舍。** 恢复已准备random Sound的正常播放和控制，让默认可达的音乐选择脚本能完成整个媒体事务。相比仍缺当前归因的旧视觉观察、尚无新增可避免成本信号的性能微调，这条真实首断点可直接解锁播放；具体选序仍只由现役队列维护。官方开发者[2021说明](https://steamcommunity.com/app/431960/discussions/2/3110266679775510809/)支持列表内选一源、完整结束后再选下一源，以及两声之间的min/max间隔；这是公开方向证据，不是当前客户端全部行为的实测。[ISoundLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ISoundLayer.html)保留play/pause/stop/isPlaying表面。本片不研究随机分布、洗牌或禁止重复，不把random映射为single。

**唯一准备与资源。** 原Sound Program的Binding用明确loop/single/random模式替换loops布尔；loop/single保持作者顺序首可用源策略。random保存经现路径/格式/ResourceView验证的候选URL及各自displayPath；只准入显式有限的0≤min≤max秒间隔，准备全列表只解析资源引用，不解码或创建全部AVPlayerItem。缺源保逐源诊断；全缺或非法间隔仅拒该Sound。显式空间化继续不支持；原volume、OGG平台能力、坏codec局部失败与资源生命周期合同保持。不得为通过控制查询返回假可用状态。

**唯一播放与时间。** Registry中原Source继续独占一个AVQueuePlayer；random每次只装一个item，完整结束后记录等待状态，再按共享SceneClock的sceneTime推进下一源，所有surface只推进一次。不使用被截断的simulation delta，不另设墙钟timer/player/provider。Source的剩余等待是状态而非第二时钟；Registry在surface/clock重置前建立，初始时间锚必须来自新epoch首个权威timing。AVFoundation继续拥有媒体播放位置；宿主暂停冻结间隔并阻止解码播放，作者pause/stop意图独立，不被host resume、ready或自然结束回执改写。

**控制状态。** random初次启动不等gap；wantsPlayback为真时play不重置item或等待。自然结束后抽一次间隔，等待时isPlaying仍表示运行计划；作者pause和host pause各自冻结剩余量。作者暂停gap后play立即选源，但保留原剩余间隔，原deadline到期按上节单item策略再选源；已有pending间隔时该临时item结束不再覆盖间隔。stop清等待并重置位置，随后play立即启动且按新结束重建gap；宿主resume只恢复已有意图，不主动选新曲。缺省/分布/不重复策略未证，不写额外shuffle规则；使用标准库随机选择及区间采样。只消费首个有限新SceneClock时间锚及后续非负sceneTime差，同时间/多surface不重复排程，不追赶历史漏播。解码失败终止本层计划并保健康peer，只有显式play可重试，不能自动无限重选。

**事务、失败与退出。** 复用原media journal、64条预算、无副作用validate与整owner提交；C host仍只对真实prepared来源开放，未知层不no-op。natural end/status回调核source epoch和item代次，晚到回执不得改写已替换item、退休层或已停Session。stop、层退休及Session退出取消等待、撤观察者并清原队列；坏源不无限重试，不引入后台扫描或第二资源fallback权威。loop/single旧行为及volume writer移交保持。

**行为资格与限制。** 固定官方2.8.0.42的自有两秒MP3以single前后quiet正控，再用一个random/min=max4及隔离gap控制观察默认render endpoint数字峰值。首次play附近即活动，后继约四秒低值窗且query持续true；running play不重排，stop→play新周期，pause→play保旧等待。唯一late反例支持等待到期可在恢复音源期间再触发，但峰值不能裁定官方替换/重叠；上述单player到期替换是本项目有界选择。不得以single行为填空，不宣称声学、精确onset/PCM、分布/不重复或完整parity。失败载体、低增益正控失败、最终结果及未验边界归[后验](../../history/sound-script-control-2026-10-12.md#sound-random-playback)。

**最小验收与停止。** 自有双短源实际自然完成并接续、同层不重叠、合法间隔与已资格控制合同、宿主暂停/恢复及退役后不续播；同一原包音乐选项3→1→0→3的命令与真实player消费、独立未参与修法样本实图。相邻门保loop/single、单源random、资源/变量改名、缺/坏源、非法间隔、stale回执和健康peer。无法在唯一现有链路内闭合或关键相位仍unknown时停该实施，不用构建、player ready、错误消失或日志数量代替播放收益；不预支性能或完整官方parity。

<a id="sound-ogg-native"></a>
### OGG平台原生准入（2026-10-16，平台限定准备、资源级已消费）

Sound Program继续唯一准备与作者首可用源选择，Registry/AVQueuePlayer继续唯一播放。`.ogg`仅在`AVURLAsset.isPlayableExtendedMIMEType("audio/ogg")`为true时进入原链；[Apple能力查询](https://developer.apple.com/documentation/avfoundation/avurlasset/isplayableextendedmimetype%28_%3A%29)针对给定container/codec声明报告可播放性，本片只据容器查询形成一次静态准备事实，不保证具体文件成功。当前最低系统可调用该API，不按系统版本猜支持。FLAC/MP3/WAV保持，不加codec、header解析、转码、player或资源owner，不泛开放M4A/WebM。

路径安全先于格式门；平台false沿原`audioFormatUnsupported/ogg`跳到下一作者源，平台true但资源缺失仍为`resourceUnavailable`。首个available resource命中即停止准备，不全列表验证，也不等同首个decodable文件。坏codec/异步decode失败仍沿现Registry事件、日志与局部边界；坏OGG已观察到failed及空队列，不以其rate仍非零或非finite时钟判为成功，未新增异步失败后换源。平台false实机、所有codec与听感未闭，不把平台query或available当文件播放保证。

[OGG资源级后验](../../history/sound-script-control-2026-10-12.md#sound-ogg-native)记录真实原样源及自有Vorbis经Program→Registry ready/时钟推进、同player pause/play、stop/retire与WAV健康对照；最近Program门及Debug构建已通过。完整原包仍在shader准备期未ready，没有该输入的原包音频/画面收益，不据启动超时否定格式。未取得整包恢复、最低系统实机parity或性能结论，不向Git加入原媒体；若真实Registry不能消费某输入，保持资源局部失败，不另建播放链。


<a id="sound-volume-script"></a>
## Sound volume标量脚本接续（2026-10-16，有界实施）

**目标与边界。** 普通Sound的`script/value`或`script/scriptproperties/value`音量经现Scalar VM→最终typed `.layer(.volume)` snapshot→唯一Sound Registry/AVQueuePlayer，改变实际增益而不重建播放器或场景。公开[ISoundLayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ISoundLayer.html)只定义volume为播放音量，[update](https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/update.html)定义当前属性值与返回更新值；越界/clamp及mixed优先级未获完整官方合同。现沿Sound有限`[0,1]`项目准入，越界走owner局部失败，不擅自夹取；精确named outer-user组合见[后继合同](#sound-volume-named-input)，Timeline、spatial/random与volume setter不扩，OGG仅按[平台格式门](#sound-ogg-native)准入。

**准备与种子。** IR `authoredValue`是raw fallback唯一事实；Sound定义和原Program的`authoredVolume`是property resolver后的启动种子，不能冒充raw。无outer-user首片以object/path/wrapper/typed输入形成结构候选，原Sound Program纯compile前移到QuickJS前，按真实资源/模式准入及同layer raw seed一致性迟判，通过既有`scalarExcludedTargets`统一planned/requested/constructed/fallback。缺binding、音源、种子不符拒绝该owner；不新增descriptor soundVolume或第二种子owner，不创建player提前消费脚本。Device资源最终需求仍只来自committed domain。

**消费与迁移选择。** 无outer-user binding由Registry消费snapshot实际标量；named binding是否退出旧property writer，由下节的最终owner构造决定，两集合互斥。二者最终调用原Source/baseVolume及master/mute乘积，不加override map、时钟或第二player。普通cadence完成原fixed-point admission后消费settled snapshot，排除当轮退休Sound IDs；遵循现CPU输入提交，不另加GPU成功barrier。重复相同volume/effective gain在原Source内避免无意义的AV属性写入，不新增缓存owner；连续音量的详细日志只在DEBUG诊断入口限量导出，配置只解析一次，普通帧不刷逐帧日志。失败沿既有lower-priority当前值，其他声音/画面继续。

**暂停及退出。** candidate Source仍在首帧前创建并继承宿主pause/mute；增益更新不改变作者play/pause/stop/startsilent、rate/queue/seek。旧direct volume暂停时继续即时生效；无outer-user脚本仍遵守冻结cadence，master/mute只作用于已消费baseVolume。仅下节的mixed owner在属性事件上做scoped刷新，不开放全部Sound暂停update。资源decode失败仅Sound局部，Sound epoch/owner退休和stop撤observer/queue，迟到事件不能复活。

**验收与停止。** 先真实Scalar VM反证及变量/资源/等价表达式变体，再沿同snapshot验证同一个真实AVQueuePlayer gain和下一cadence；覆盖无关属性不重置、暂停direct-volume编辑、master/mute、作者暂停/停止不复活、错误返回/缺音源/seed冲突、retire/取消及健康peer。现Sound Program/命令门复用，仅新失败重验。真实MP3 primary与独立内容分别核owner/提交值/播放器进展及画面，admitted/ready不当作可听或完整样本通过。公开/neutral schema候选3800728730:23及3662790108:2989只用于验证，不进入算法或准入。named后继不扩大其他mixed形态；OGG独立按平台格式门处理。若无实际增益链或出现生命周期回退，先撤该volume route，不扩参数/格式矩阵。

实施边界与真实增益、原包/独立内容、超时及未验入口统一见[Sound volume后验](../../history/sound-script-control-2026-10-12.md#sound-volume-script)；本节保留职责和退出选择，不复制运行状态。

<a id="sound-volume-named-input"></a>
### Named volume与声明输入（2026-10-16，有界已执行）

**目标与资格。** 让普通Sound的有限Number `script/scriptproperties/user/value`沿同一Scalar owner接收外层slider及内层条件输入，实际调增益和播放意图并避免编辑重建。3147346398的原始volume同时绑定0…1 slider与两个Combo条件Bool输入；一次现役App资格取得instruction=0、callback=0、rebuildRequired=true及真实改值拒绝。这不是无consumer的条件Combo；不能加value-only例外、忽略script或复用无关字体callback来宣称可热更。资格事实留`.artifacts/tmp/condition-combo-qualification-20261016/`，CLI拒绝不等于本轮已执行原生面板重建，尚无性能收益。

**准备与唯一writer。** 共享Sound专属合同只接精确`script/user/value`或`script/scriptproperties/user/value`、有限`[0,1]` Number、普通Sound volume路径及同源/同key身份，不放宽其他objectScalar。原条件解析、ScriptProperty codec、effective store与typed target继续唯一。IR保raw fallback；Sound Program保resolver后的启动值，named分支以唯一Slider、同key及resolved当前值迟证资源consumer，不要求当前值等于raw。只有最终构造成功的owner进入Program的`scriptVolumeTargets`，对应named target退出direct writer，增益只消费settled snapshot；未构造者保留旧direct输入。外层user仍是低优先级typed输入，不与VM争写player，也不提前建player消费脚本。

**暂停属性事务。** LiveConsumers在即时及deferred promotion的最终提交前，按changed keys选择实际受影响的mixed-volume owners，仅通过Scalar `targetFilter`求值。`SceneEvaluationTransaction.prepareScoped`以完整committed snapshot为base；publishing owner必须有schema，附带输入只刷新base已有lane，缺失声明输入保原codec fallback，不造definition。未触及Timeline/脚本值及transform metadata保持；完整surface cohort、同generation、catalog token与schema不符则拒绝刷新。SceneClock保持暂停sceneTime和delta0，frameIndex沿用base，publication仍由原property revision/evaluation generation管理，不新增clock或snapshot缓存。

**显式mode与VM镜像。** primitive init/update及property callback共用显式`propertyRefresh`，不运行due timers、观察或消费media事件，也不派发video/Puppet ended；Promise jobs仍按原callback完成/失败机制drain。其他owner不额外求值，暂停renderFrame继续复用画面。原layer runtime publication owner的partial入口只更新Sound观察，复用C committed字段并保current origin、world/scale及peer media/text/particle状态；失败沿原snapshot discard恢复，不能重发缺省字段覆盖peer。

**副作用与失败。** 暂停包络接纳Scalar结果及通过原Sound验证的命令；含material function、Timeline/layer mutation、texture/Puppet/particle操作或非Sound media命令的整owner拒绝，不静默丢副作用。原journal、localStorage依赖闭包与fixed-point统一决定admitted effects，再经共用commit提交Sound命令和typed snapshot。被拒owner丢弃未提交命令、恢复其事件账本，增益可消费原resolver接纳的下层fallback；整笔刷新取消则保持原LiveState、增益与意图，不以临时slider直写补偿。这里只保证typed/host事务，不承诺任意JS堆回滚。

**验收与停止。** [有界后验](../../history/sound-script-control-2026-10-12.md#sound-mixed-volume)记录真实原包播放/暂停热改、派生脚本实际增益、原生保存/重开/reset单session及独立渲染；VM/player门覆盖改名、fallback、timer/media不额外推进与partial peer/rollback。未测性能；deferred visibility与Sound同key的实际组合、故障后整笔Session取消、多surface及听感/parity仍待验。若需全场景update、第二writer/输入缓存或扩大暂停包络，先另补合同及区分门。

<a id="color-input-numeric-slot"></a>
### Color输入与数值slot（2026-10-16，有界已实施）

**目标与资格。** 3337494481的147/effect3 alpha在进入JS前因Number fallback绑定Color持续拒绝。固定官方2.8.0.42自有正控证明：Color送入数值`addSlider` slot仍为三分量String，callback可返回有限scalar；不应按fallback类型提前拒绝或强转Number/Vec3。它不证明原作者media/fade画面已修，详细资格只归本机`333-next-qualification-20261016/official-property-slot/`。

**唯一链路。** 原ScriptProperty input在程序构造边按唯一property definition一次保存输入kind，Scalar/String/Vector及其借用cursor/media/lifecycle共用该值；普通帧不重新找定义。只对declared Color与有限Number fallback新增经原RGB parser验证的String转交。VM实际builder slot继续独占String/Vec解释，不扫描作者源码或按参数名分派。原property compiler使用已有Color/vector3输入指令；此输入checkpoint的seed来自作者Color定义的合法default，原script fallback仍为Number，二者属于不同输入域，不能广播Number伪造颜色或改变fallback。

**失败与验收。** 缺失/重复定义、非法/非有限RGB、其他String类型和不健康owner保原拒绝与整键rollback；不新增通知/store/renderer。最近真实VM门覆盖改名/等价表达式、cold/hot/重复编辑、原Number fallback及相邻非法/非Color输入；原333实际Scalar回调与画面、独立健康样本及退出另验。若需要通用coercion、额外输入owner或改JS slot类型则停止本片，另取区分证据。此修复不认领CPU/GPU收益。

[有界后验](../../history/property-callback-recovery-2026-10-14.md#color-numeric-slot-input)记录原333首错退出、自有Scalar同窗编辑与独立画面；当时残留的末次合法编辑拒绝由[回调退场后继](#retired-property-callback-consumers)接续，特殊composition和完整交互不随此关闭。

<a id="retired-property-callback-consumers"></a>
### 永久删除后的属性回调消费者（2026-10-16，有界已实施）

333同时间无非法输入对照仍拒绝末次合法编辑；精确guard证实，启动时冻结的全键callback集合仍包含已永久删除的347.visibility。选择修正事件消费者投影，不复活owner、不削失败准入，也不改VM事件或属性存储。Session从唯一DynamicLayerRuntime的已提交tombstone，使用现有target→layer映射，只投影本次keys已永久删除的callback receivers；LiveUpdateState仅从事件集合减去它们。显式typed instructions的消费者、值验证及原子提交仍全部保留，避免把活跃text clone复用的原输入当成已死数据源。暂时隐藏、disabled、待retry或资源未ready且无tombstone者继续阻挡；无存活consumer的键保原边界。新dynamic callback注册、widget owner退场和全无消费者的面板值不随片开放。

普通/合并编辑、deferred完成及userTexture异步再次准入都重新读已提交事实；拒绝或未提交的destroy不能改变参与者，不新增退休registry、全场景刷新或帧内工作。永久删除后清理失败仍由原生命周期重试，不重新登记事件订阅。复用现有callback派发与owner teardown，值revision只随实际成功变化递增。门验证改名/类型、同值no-op、未退休失败peer、显式绑定/共享输入及全事件owner退休；原包同时间对照与原非法→合法序列、自有离场/调值画面及独立原包归[后验](../../history/property-callback-recovery-2026-10-14.md#retired-property-callback-consumers)。异步再次准入已审调用，实际deferred/resource删除竞态、完整原生面板/存储、多surface/HDR及性能未验；若需忽略活跃失败owner或传播到共享typed输入，则停止扩大并另立合同。

<a id="project-utility-visibility"></a>
### Project utility 的 Boolean owner（2026-10-16，有界已实施）

**目标与首断点。** 已资格的真实点击能进入原cursor owner，但共享状态的消费者挂在project层visible上，被候选contentKind和utility限制提前丢弃，未创建VM owner。选择补齐此普通Bool入口，优于猜事件API或绕过作者脚本。仅接无parent/children、无dependency及authoredDependency的project capture；其既有source route、Program和graph仍须独立通过准备。同束删除仍按上文完整显式分支合同，不跨peer借未提交tombstone。不为脚本副作用单建调度器，也不按源码形状决定准入。

**唯一链路与失败。** 原Bool Program持有init/update/属性事件及typed owner effects；返回值进入现layer.visibility，effect setter沿现bundle共同提交/撤回。现动态visibility admission保留固定root准备需求，utility planner保留初始隐藏的capture能力；当帧snapshot和原active execution demand决定是否实际编码，不逐帧重建计划。无effect仍是无像素的合法值owner，资源或Program不可用不伪造捕获。composition保持现支持范围；parent/child、依赖project和错误kind继续拒绝，project effect的初始隐藏激活不随片扩展。2026-10-17 fullscreen后继批准：真实322的38.visible有合法公开update/applyUserProperties，但候选kind及utility门提前丢弃；现有准备、动态visibility admission和utility消费者已支持独立root fullscreen。只将exact fullscreen kind、无parent、声明及实际children均空、两类依赖均空的Bool脚本接入同一Program/typed snapshot，不改VM、帧驱动、图或compositor；缺失utility及kind不匹配仍拒绝。验证真实Bool init/update/属性事件、错误返回与owner事务、合法改名/等价表达式、相邻image/composition/project及独立样本；真实38若在更晚host/API失败则保留该新断点，不以owner数量替代播放结果。

**验收与停止。** 自有VM输入验证Bool返回与跨effect副作用、改名/等价表达式、原子失败及邻近不准入形态；隔离App以相同窗口证明脚本持续更新和实际effect像素切换，另验project自身false→true→false及未参与修法内容。原包口罩变化须同时有owner、typed effect/graph执行和实际ROI，点击命中或非黑不足。不能承接动态capture或出现更早owner缺失时停下重排；多surface/HDR、完整样本及性能另验。

<a id="script-module-top-level-initialization"></a>
#### 模块顶层初始化后继（2026-10-18，有界已实施）

成功求值的 stateful Bool 模块即使没有可调用回调，也可通过顶层初始化贡献共享状态。官方 marker、真实 candidate 门与原 U35 的限定画面已验证；构造 attempt 内曾执行模块仍不等于最终 domain 已接纳，本片不改变 Catalog 或 UI 属性通知。只撤除现有合法 stateful Bool 的额外无 hook 拒绝，不另造 Scalar、String 或非 Bool Vector 分支，不扩大其已有行为；非函数导出沿现共享 export Bridge 视为无可调用回调，不新增 ABI 判定。

共享 `ValueOwnerConstruction/Exports` 识别无回调模块，真实 owner、namespace 与顶层贡献由最终成功的 domain 保活；不合成 `init`、伪造返回值、复制旧 heap 或新增调度。纯初始化模块沿 `requiresFrameEvaluation` 闲置，不抢占 authored/property/Timeline 值；原 timer/work 能力仍按现 owner 调度与预算。value-only Bool、destroy-only 和独立 Cursor 的原资格保持，不能借 module-only 身份取得新权限或放开空事件入口。退休、销毁与 Session 退出沿原 owner/domain 生命周期。

模块 throw、预算或其他构造失败仍排除失败 target，并重建干净候选 domain；不把失败 attempt 的共享 heap 合并到最终域。最近门验证实际 candidate 重建、兄弟读取、改名与等价初始化、闲置无多余帧调用、失败模块清堆及健康 peer；value-only 与 destroy-only 反例保留。原 U35 默认输入的 ready/after 均不再出现底部复制矩形，三个 origin 首输出保持作者屏外基值；独立 U25 的时钟、圆环、问候与主体保持。只据此确认初始化贡献及这项画面收益，不外推精确音频/动画相位、字体像素、整样本兼容或性能；其他模块生命周期不能由此自动准入。

<a id="layer-alpha-raw-setter"></a>
### Layer alpha 的 raw setter 与显示边界（2026-10-17）

**目标与资格。** fullscreen owner接通后，322的4907渐变先写有限负alpha再归零，现宿主范围拒绝使callback永久停用、中央组不能继续淡入。独立普通2D官方四卡证明0/1正控及1.01/−.01均不抛错，同callback与下一callback保持raw数值；黑底白源分别得到白/黑端点。此证据只说明属性/显示分域，不定位官方内部clamp相位，不推广非有限值、HDR、color或particle instance。

**唯一链路。** 沿现ILayer.alpha setter→C staged/baseline journal→Swift typed preflight/commit/snapshot→下一cadence C镜像保留有限Double；撤下这些环节的[0,1]属性范围门和镜像clamp，不新增raw状态表或更新owner。authored与已准入dynamic handle复用同setter/事务；既有constructor配置、资源准入、color、particle instance及权限范围不扩。显示仍由现SceneDynamicLayerValues.alpha归一后转Float；已证唯一显式providerAlpha调用点也传此归一结果，既有graph-source fallback未随片扩展，普通帧不重建或重新准备。

**失败与退出。** 非有限输入、坏ABI、失效identity及现owner effects冲突继续局部拒绝/撤回，不放宽跨owner提交或JS heap回滚承诺。raw Double不可直接窄化成GPU Float；若发现现消费者绕过既有显示归一，先在该唯一消费者接回现owner，不能按值/样本另建clamp链。

**验收。** 真实VM的dt0→正dt负值/上界暂态后修正、同/下一callback raw读回、commit/discard与健康peer，含改名/等价表达式、finite极值、NaN/Infinity及真实异常；复用现显示归一门证明GPU输入有限。一次最终Debug，原322的38/4907实际控制及中央/两侧人物、同条件独立样本实图和GPU排空、独审通过后才关闭该首错。保留接线中间失败，不因候选数或App正常退出认整样本通过。

<a id="shared-timer-cancellation"></a>
## 共享 timer 取消能力（2026-10-18，有界已实施）

**目标与证据。** `setTimeout/setInterval` 返回的取消函数可以经同一 Scene 的 `shared` 传给另一合法 stateful owner，再裸调用以停止创建者的工作；timer 仍由创建者持有和推进。旧实现把函数身份限定为当前 callback owner，真实媒体面板的 hover 会因此抛错并禁用脚本。固定官方 2.8.0.42 的单 timeout 对照已区分正常跨 owner 调用；另一组独立健康 observer 又确认取消成功后调用方立即显式 throw，原 timer 仍不触发。该证据不定义官方 typed badreturn、退休、所有 timer 组合或内部事务策略；输入、原图与失败记录归运行证据。

**职责与数据流。** 沿原 `TimerHost` 的创建、owner timer 数组、唯一 SceneClock 和 callback 调度修正返回能力，不新增 timer registry、owner 索引或 clock。每个使用 timer 的 owner 懒建一个弱 lifetime anchor；每次 registration 的取消闭包持有 anchor、原单调 timer identity 与 `externally_cancelled` 状态。active record 和现有 timer snapshot 各持同一取消 JSValue，保证其 native token 存活。anchor/token 使用 VM 计费分配；owner 退休先将 anchor 的 owner 置空，再释放 callback 和 owner 引用，逃逸函数不保活或解引用已释放的 owner。旧两整数、仅从当前 owner 查找的取消路径退出。

**调用及失败合同。** 取消是对创建者调度工作的即时能力调用，与调用方的 typed 值提交分开：合法调用成功后，调用方后续 throw、非法返回或 typed bundle 拒绝不撤回该次取消。显式 throw 有上述官方有界证据；typed 拒绝是本项目一致的调度政策，不冒充官方观察。调用方必须处于同 domain 的有效 callback，且不是 value-only 或嵌套 value-only guard；创建者必须存活、未禁用或退休。过期 timer identity 在存活 owner 下幂等无操作；非法上下文、受限调用方及退休能力继续安全拒绝，未取得官方陈旧调用合同。

跨 owner 调用通过检查后，即使当前数组中该 identity 已 inactive，也将该 registration 标为 externally cancelled。创建者后续 init/Puppet/显式 snapshot 恢复跳过此标记及已失效 anchor，不能复活 peer 已取消的工作；snapshot 不复制或回退该标记。同 owner 取消沿原 snapshot 恢复合同，原单调 issuance counter 始终不回退，重试、slot 复用及 ABA 反例保持。teardown 在 destroy 前清 timer；仍存活的本 owner 清理回调调用旧取消函数须保持幂等无操作，凭 anchor 中不可变 owner identity 校验，不查新 slot 或解引用退休 owner，peer 不取得该权限。创建失败只撤销新 timer；CClosure 的 early OOM、late finalizer 和残留异常必须统一释放新 token，不影响已有工作。普通帧仍只遍历原有 timer 数组。

**取舍与退出。** 不用全 domain owner 表查找，也不新增逐帧快照。caller cancellation journal 会改变到期前即时取消的时序，并为不存在的 caller-fate 回滚合同增加重放职责，故此片不采用；后继若取得相反目标证据，再修同一 owner。若原样本交互未获恢复，保留实际新首断点，不能以取消函数或执行计数通过记整景完成。

**验收。** 复用真实 QuickJS 门验证裸/成员调用、改名和等价表达式、同 owner identity/restore、value-only、退休/ABA、创建者 snapshot 及 already-inactive 反例、调用方失败后健康 peer；补 OOM/GC/销毁顺序的内存安全门。固定源码 Debug build 后，以相同原包、受控媒体和 hover 序列比较故障与恢复，并跑一个未参与修法的真实样本。只认实际触达及可见/交互结果，不认领性能、完整 timer/API 或整样本 parity。

<a id="combined-timeline-playback-owner"></a>
## Combined Timeline 的唯一播放状态（2026-10-17，有界已实施）

目标是让同层合法组合属性在同一作者时间、控制与typed事务中播放。实施前U17原包20s已证脸/龙Puppet推进；头发origin↔angles关系保留却命中普通组的静态拒绝条件，未导出其逐帧typed值，不把视觉差异先归单因。[官方Combined合同](https://docs.wallpaperengine.io/en/scene/timeline/combined.html)要求新property复用已有animation的设置；旧camera只复制设置、Runtime逐target持State，不能作为通用组合控制实现。现扩展原Program/PlaybackRuntime，替换逐成员状态；不新建clock、动画注册表或输出链。

准备职责：同一作者层内平坦、双向引用的relative origin/angles/scale组，复用完整root target、唯一播放State与成员顺序；准备期把root的fps/length/mode/start-paused/wrap归一到各lane，再守typed target、base、component、finite及wrap门，不缩放keyframe帧或改变relative基值。**混合alpha后继（2026-10-19，实施前决策）**在相同ordinary组中纳入absolute scalar alpha，root可为alpha或原变换；alpha沿原absolute求值与终端归一，变换仍加作者基值，不建新clock/evaluator或复制播放分支。先以官方已成像2D载体、非单位base及独立source/alpha/position正控区分M非wrap、W wrap与仅换root的R；输入/运动/alpha不可区分即STOP_UNKNOWN，不扫参数。通过后只改原compiler两处组准入，按值类型验证有限作者基值；relative alpha、absolute transform、未知host、坏/跨层/嵌套引用、重复target及响应域外仍拒整个相关组，健康peer继续。验收须实际parser→descriptor→compiler→Program→Playback/resolver，覆盖改名/等价输入、root交换、成员pause/stop及上述反例；同源Debug补自有相位与原包242实际消费，再用未参与修法样本。242仅是已证准备缺口，不作为脸/龙/小人/刀轨迹根因；无可归因像素收益则仅记输入准入，原视觉项不关闭。

**基础Single曲线后继（2026-10-18，实施前决策）。** U09的58 angles→scale带非空smoothing=.9/stiffness=87，旧整组拒绝使原包人物一直横倒；同HEAD测试副本只移除这两个选项后，健康背景保持，人物从零XY尺寸恢复并转正。固定官方2.8.0.42原输入的后两张实图也为完整、转正人物；这证明已知曲线不应整组冻结，未证明两选项只是编辑元数据或没有过渡响应。选择复用唯一Evaluator/PlaybackRuntime执行基础关键帧近似，不引入未知spring算法或第二clock。范围仅限上述合法同层relative变换组、root mode=single；有效响应值须在已见编辑选项域内（smoothing 0…0.9，stiffness 1…200，分别可省略）。其他模式或域外/非有限值保持组级未准入，不按样本选择。

Program保留作者响应值及原owner关系，在准备期为实际接纳的组发布一次`responseOptionsUnmodeled`降级诊断；曲线、相对基值、root时长/暂停/名称、命令顺序与typed事务全部沿现链执行。该诊断表示平滑、迟滞或过冲未实现，不等于完整原动画精度；child被root替换的选项不另建状态。验收须保原输入完成基础姿态变化、零尺寸阶段局部退化后恢复及健康背景，覆盖改名/换成员顺序、合法选项变体、nil旧路径、暂停/重启、非法拓扑与非有限反例，并以未参与修法的真实Timeline样本检查回退。官方无同engine-phase marker的截图只支持基本姿态，不裁精确entry时相、lag或数值平滑。后继获得响应合同后在同一owner替换近似并撤销该诊断，不保留并行播放算法；若原输入基础姿态不获恢复则撤回本候选。

原binding/Program保存不可变的完整播放owner关系，旧独立输入默认自身owner；准备期形成target→owner状态索引和owner→有序成员，普通帧只消费已准备索引。原PlaybackRuntime每组只有一个State，所有成员在同一elapsedFrames求各自值；命令按原journal顺序作用owner，preview投影该组全部成员，原validate/apply和typed事务共同接纳或撤回。未知target/throw/溢预算/提交前取消保持原owner包失败；Runtime的next-frame observation快照/恢复API保留并覆盖组成员；当前host没有该API调用者，本片不宣称无surface提交时host已恢复观察，也不以该诊断日志证明呈现。preview不消费、拒绝命令不apply，已接受播放状态不因后续GPU失败新增回滚协议。

命令顺序修正（2026-10-18）：同域不同脚本可交错控制同一已准入播放状态，按脚本分包不能改写实际callback先后。C命令记录复用现domain callback epoch与callback内ordinal，typed mutation原样传递；preview及最终apply均先筛选已准入owner，再由同一Bridge恢复此顺序。手工构造的命令默认顺序元数据为零，保留传入顺序；不新增计时器、全局序号或播放owner，不改变throw、overflow、discard及固定点拒绝半径。最近门复现stop→play→pause被分包为stop→pause→play导致下一时刻继续播放；修法须同时证明同callback命令、失败peer及后续健康callback保持，跨pass身份另行资格，不能借此放行。

名称仅由root发布一次，不复制到child制造歧义，不改变既有targetIndex/handle身份与代次规则；合法成员target的控制归同owner，不新增API或猜同名优先级。已支持的default-camera origin/zoom迁移到同一owner状态表示与归一化职责，保原相机选择、range、near/far、relative与降级门；camera既有非空smoothing/stiffness只保真、Evaluator未解释的边界不在本片新增拒绝或认领行为支持。child被root替换的设置不另作有效输入准入，不保留第二套camera播放owner。普通单target输出/时序保持，旧普通组blanket拒绝只对经过完整准备证明的组退出。

验收复用现parser→descriptor→compiler和Runtime/resolver、named QuickJS门：root/child不同设置仍服从root，改名/成员顺序变体、共享play/pause/stop/single重播、同帧全部成员preview、坏peer拒绝/Runtime观察API及原camera/独立Timeline，手动restore测试不冒host提交恢复；缺/坏引用、循环、重复、非准入host/relative和有限域为相邻反例。一次最终Debug后，自有相位可区分组合实图、原U17的15–18s画面与实际typed/geometry消费、一个未参与修法的真实Timeline样本及安全退出；不把原包几何健康或profile命中当组合画面收益，不声称官方同phase轨迹、整样本或性能完成。若需要嵌套/跨host合成、第二时钟或新视觉算法，停在新首断点重排。

实施结果与限制归[能力合同](../../capabilities/runtime-input-property-coverage.md#op-timeline-combined)和[运行后验](../../capabilities/runtime-evidence-current.md#combined-timeline-playback-20261017)。旧逐成员播放State已退出；本片不扩嵌套/跨host及未准入target，不新增host观察回滚协议。
