# 粒子材质执行：变体需求与同层深度（2026-11-01）

> **历史证据 — 非现役入口**。保存实施前设计（基线`118c741b6`）及有界验收。现职责和未覆盖范围归[粒子覆盖](../capabilities/particle-component-coverage.md#particle-material-depth-variants)。

## 目标与范围

让已支持的单screen Sprite折射材质消费作者只读depth test，完整支持同层普通writer child/sibling；完整当前层没有writer时省掉与clear1恒通过的比较和全屏depth分配，保同一相机与clip。补实际缺失消费者，不靠材质/样本/路径特判。原356:398仅是验证输入：read-only、additive、no-cull、90°perspective、无child，仍须实际出生和ROI证明。

重要设计判据命中跨准备/Runtime/Metal/资源及普通帧成本。现普通粒子depth是按layer独立的clear1/lessEqual域；模型另用reverse-Z，不能互借。Depth write的REFRACT、其他billboard/cull/alpha、Scene共享depth、shader算法和模拟不随本片扩展。

## 当前断点与选择

Planner及state compiler拒绝REFRACT depth；pipeline无相应attachment PSO，refraction encoder不携depth。普通writer child经现准入可先于REFRACT root进入同layerBatches，故单batch write=false不能省test。完整层无writer时，正常Metal clip后的深度在[0,1]，lessEqual全1恒成立；只省比较，不能改投影、near/far或behind-eye裁剪。

选择在原pipeline用一个有限变体表替换八个散PSO字段，并沿现root/child准备链按可达模板归并需求。直接再加两个字段/开关会继续扩展重复创建与选择；只准无child/read-only则新增排斥门并留下现mixed缺口，均不选。变体表是原PSO存储的替换，不新增factory、cache、renderer、depth owner或运行计划。

## 唯一数据流与职责

1. AssetGraph入口一次取得typed material state，交原RefractionPlanner与state compiler；不重复解析同一pass。保现texture/constants/purpose失败，planner只扩read-only。State compiler复用screen Sprite形状，但depth资格与`usesSceneCamera`分开，REFRACT不能因放宽combos而改旧camera/basis。
2. 变体key只含shader家族、blend和是否携depth attachment；test/write仍用原depthStates，不叠加PSO维度。MetalPipeline准备一次、表随后不可变，普通帧仅取已有PSO，不lazy编译。
3. ChildRuntime→Runtime→PlaybackState沿原coverage需求归并职责，替换旧coverage布尔。只看已准入root/child模板，包含dormant/event child，不用首帧非空batch猜需求。按层潜在writer补attachment变体，并保非writer无attachment变体；最终并集交pipeline。旧散字段和失效布尔同批删除，不增加长期需求owner或逐帧建集合。
4. 当前层`layerBatches`有任意writer才租depth；原draw及StaticModels三处预留/可用性判断一致改用writer需求，不只改最后draw。无writer不分配、不等待可选depth容量；有writer时全部ordinary/coverage/REFRACT都选匹配attachment的PSO并消费自身test/write。
5. Refraction捕获背景后沿原MainPassEncoder恢复同一lease，首次成功draw clear1，其后load；普通与折射成功draw共用一次clear状态更新。跨snapshot不得重clear，不新建depth/history；取消、完成与释放仍由原pool/command buffer负责。
6. 可选coverage变体失败继续局部缺席，不使健康ordinary退出。其他失败沿现material/batch最小范围处理，不新增帧事务、重试或层层认证。表缺已请求变体是准备/调用错误，不在普通帧临时生成或伪造替代shader。

Standalone pipeline构造可保明确的默认变体需求，原App必须传实际准备需求；旧coverage开关退出。测试调用按其真实用途请求变体，不为减少改行数保第二条旧创建链。

## 实施前验收与停止条件

复用现assets/camera/refraction行为门；相机夹具仍有余量，不继续向近1000行refraction夹具或巨型rendering脚本堆代码。先冻结输入/oracle，再执行一次必要的修前/修后，不重复绿门。

- A：非零背景、同MVP/顺序的全只读REFRACT，test on/off逐像素相等；反转顺序各自成对，coverage正控非空，实际depth租用为零。
- B：同层普通近writer→远REFRACT reader，on遮挡/off可见；跨背景snapshot保持旧depth，另验writer在后的作者顺序、ordinary/coverage混合及已支持read/write独立组合。错误重clear必须被正控识别。
- C：原90°perspective，合法near/far、跨边界和behind-eye；test on/off同clip，合法正控非空；保普通ortho、资源/变量改名及等价几何变体。
- D：已准入但延迟出生的child writer/reader在首次无粒子时已有所需PSO；后续不编译。ordinary-only、全只读及mixed分别只准备可达变体；无关壁纸不增加新PSO或depth分配，coverage局部失败保持。
- 普通Debug、原356实际398非空折射/可归属ROI与原531保持，再用未参与修法的真实折射样本验证。加载/PSO数量不代视觉、官方parity或CPU/GPU收益；性能结论须同条件对照。

仅当read-only能力、mixed遮挡、无writer零分配、clip和按需准备同时闭合，才提交产品并把稳定职责移交能力合同；原散字段/coverage开关退出。若需改相机、读模型depth、添加第二owner或猜画面补偿，停止该扩展并重排。首失败、真实输入及未覆盖边界归历史，队列仅移除已证首门。

<a id="bounded-result"></a>
## 有界结果

本批替换原十个产品文件的散 PSO/coverage 布尔，产品 +148/−157，净减9行；没有新增 renderer、pool、clock、普通帧编译或长期 owner。实际职责归粒子合同，以下为固定观察。

- assets 实现门2方法通过，含116个材质变体；真实 Metal camera 门12方法及 coverage 邻例6方法通过。只读 on/off 的14组几何对逐像素一致且零 depth lease；mixed writer→reader 在两种混合下各有144个差异像素，背景 snapshot 后遮挡保持；near/far、跨 clip、behind-eye 与反序保持。实际 Runtime 的 dormant child 出生前已准备1/1/7个所需变体，出生并上传后编译表不变；mixed 才租16,384字节的64² depth。该字节数是离屏夹具结果，不是全 App 内存收益。
- 先保留 v1 类型推导超时、v2 非法 PNG 折射载体、v3 遗漏真实 instance upload 的失败，再只修夹具得到 v4。四轮产品及断言未变；旧八方法基线被冻结但未单独运行，候选实际包含这八方法。未强制 Metal 后端编译失败；coverage 邻例只证未准备变体局部失败与 ordinary 保持。
- 一次签名 Debug 构建53.768秒，4415输入无漂移；App `25a09e14…ed3cf`、dylib `68c75322…b31d`。十产品独立审查无阻断。旧 App 是上一批有效构建，仅用于能力反例，非同 HEAD 整 App 性能基线。
- 自有非黑背景、原398定义与原delay的三臂对照：旧版 depth-off 有213个完成批次/7251实例，旧版 depth-on 缺席；候选 depth-on 有227个完成批次/7727实例。预登记 ROI 在 ready→after 的≥5差异像素依次为62,305、0、62,145，证明该材质实际贡献；不证明光学位移、同phase或官方像素一致。
- 未修改原包356实际运行18秒：398有135个完成批次/5485实例，531有135个完成批次/6741实例，均0失败；人物、蝴蝶与金色波纹保持。552/141仍不可用，不关闭整样本。独立241原包短窗人物、粉色环、星点保持，粒子不可用项为空。两原包和三臂 App 均退出0、surface 1→0、GPU排空；全局报告 FAIL 原样保留，原因见下节。

普通14天必要包：`.artifacts/scene-evidence/runs/particle-material-depth-20261101/metadata/samples/0/runtime_evidence.zip`。包保源码身份、事前设计/ROI、所有首失败、实际日志/读回、已用原图、独审与停止证据；App、可重建缓存及未用于结论的重复截图不归档。唯一连续构建缓存保留 `.build-cache/scene-gravity-20261028`。

<a id="presentation-observation"></a>
### 呈现观察边界

三臂及两原包均有 Metal 读回/编码完成证据，但 presented 计数与 interval 均为0；surface最大值1，不支持“多条呈现流”或已确认 producer 回归的归因。日志尚不能区分系统回调缺席、时间无效或代次过滤。验收 consumer 对非 log-only 运行无条件要求 performance qualification，故报告保留 FAIL。能力结论仅据本次实际执行与读回，不授屏幕呈现时序、稳定帧率或 CPU/GPU/整体内存收益。此观测债已记队列，未降低阈值或重跑追绿。

REFRACT depth write、其他 billboard/cull 组合、共享模型 reverse-Z、552/141 normal 槽位、HDR、官方同phase与性能均未扩展。mandatory 非 coverage PSO 的创建失败仍使原 pipeline init 失败；optional coverage 缺席仍局部处理，没有把全部创建失败改成局部成功。
