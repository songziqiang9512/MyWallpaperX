<!-- document-role: historical-evidence -->
# Puppet 线性冲量与重复拖动：2026-10-28

> **历史证据 — 非现役入口**：当前接口归[脚本合同](../capabilities/scenescript-api-coverage.md#puppet-linear-impulse)，物理范围归[对象覆盖](../capabilities/advanced-object-coverage.md#op-puppet-bone-constraints)，余项归[队列](../roadmap/scene-open-breakpoint-queue.md)。

## 首批线性冲量

3749463715与2998757800在释放timer调用缺失的applyBonePhysicsImpulse后永久停用owner，后续拖动失效。现将显式name/index+有限Vec3线性冲量接入原matrix journal，保callback epoch/ordinal、整owner接纳/撤回；两参或第三参零角冲量可用，非零角冲量及省略bone未开放。C保有限Double，原Swift consumer边界拒不可表示的Float payload并撤整owner，健康peer继续，避免部分提交。

原PlaybackState/Motion独占物理状态；world kick与已有velocity一起进入原稳定spring/friction步，按当前canonical parent/attachment先父后子推进一次，再产挂点与网格。保local距离约束、query/render分域、setter丢前冲量留后冲量、frameIndex防重；退出旧全local后world顺序、重复矩阵数组准备和提交前dictionary复制。普通无physics/无attachment rig保原cached世界路径。没有第二solver、clock、队列或输出。

首批3187857248的gravity profile当时尚未支持（[本日后继](#translation-gravity-20261028)已补齐显式平移重力）。中间候选把新API当noop，允许作者继续运行，三轮最大bind位移从约8–13升至34–39、91–93，拒绝采用。最终在原prepared bone配置一次保存physics准入失败标记，C同owner固定256B随既有calloc/free；frame refresh传nil保留，普通帧不重映射/扫描。实际调用unsupported骨在journal前明确失败，普通未启用骨仍可noop，已支持骨继续消费。该检查针对实测累计形变，不阻止其他画面或加载，不读取诊断文案选择算法；318没有算修好。

| 原包 / 同三轮手势 | 实际结果与限定 |
|---|---|
| 3749463715 | 旧owner稳定持有窗写入11/0/0，第二/三轮单一旧几何；最终同gesture写入19/19/19，各轮均19个不同GPU几何，释手无异常。原图确认局部交互和完整构图仍可见。 |
| 2998757800 | 最终三轮写入17/17/15，持有时max bind位移均约40.948。每个持有窗一个几何hash是到固定点后稳态，不作为停滞；释手与再捕获正常，无VM失败。 |
| 3187857248 | 原版第一轮后missing-function禁用；最终第一轮后明确unsupported禁用。第二/三轮均0写入、位移保持约13.4（旧约13.8），未重现中间候选累计形变。重复交互与gravity仍待修。 |
| 独立3617056047 | 最终同一已签名App运行10秒，模型、圆环与文字可见，12 owners quiescent、exit0、surface1→0/GPU drained；不认Puppet物理parity。 |

三包均30秒、零频谱夹具及60FPS请求；表中是实际drag/release事件内缩0.3/0.2秒的GPU完成采样，不是呈现率或性能收益。先短probe取得真实骨NDC；318起点有小偏移以隔离作者零向量归一化风险，精确零位移未验。一次采集将stdout误写到App自带报告同名路径，未作通过证据，修正后重采。

五个现役行为模块通过，availability追加后只重验最近骨API九项，覆盖改名/name/index、ordinary-none、unsupported整callback撤回、nil刷新保留、坏count、非01非zero标记、世界方向/非等比parent、一次消费、typed Float晚拒绝及真实Metal输出。最终Debug按4398产品输入冻结、无漂移，严格深签名；独立审查未发现本片开放P1/P2。原owner getter/矩阵/生命周期门按影响面复用，未全矩阵重跑。

正式证据在主仓`.artifacts/scene-evidence/runs/puppet-impulse-20261028-{baseline374,final374,final299,baseline318,final318,rejected318,control}/`。318每包仅留必要一张未改原PNG，日志gzip保存且记录解压后SHA，单包≤32MiB/普通14天/总5GiB。官方重力观察器未取得联合可读/可见正控，V4未运行，结论STOP_UNKNOWN；未用其拟合gain、质量或friction相位。官方精确数值、gravity/角物理、完整样本/HDR/多屏及整体性能均不认领。

本批后按用户要求停止新修复并整合主仓。scalar-seed与vector-reflect的七个文件和既有7933c3921逐字节一致；CPU子树无独有修改，候选已撤回，依据沿[原记录](parallel-script-compatibility-2026-10-28.md#not-adopted)。必要研究仅归`scene-capability-followup-20261028-research`正式包；不把研究假设记成已修。

整合暂停收尾已清理本轮临时执行目录、App、样本副本、HOME与构建缓存；受应用固定保护的工作树不绕过保护删除。


<a id="translation-gravity-20261028"></a>
## 显式平移重力与318重复拖动后继

首错仍是ge=true使prepared translationPhysics=nil，释放impulse明确失败后停用owner；不能撤标记或noop。沿原RigReader一次准备world gravity，原Motion在同一闭式spring/friction步消费持续力，复用原PlaybackState cadence、parent/attachment、query/render与有序journal。没有第二solver/clock/registry。以常量输入响应避开g/k消减，含零刚度/摩擦；无重力不额外算响应函数，保local limit与setter/kick顺序。原数值百万上限退役，保有限非负可表示值；坏可选physics metadata只撤该骨配置，骨结构/weights仍硬拒，防新字段误伤健康骨。

官方2.8.0.42（binary SHA `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`）同网格双臂先资格setter及一次kick的实际形变：OFF横移、ON额外向下。随后静态spring板：m5/10、k150/300给world Y约−33.33/−66.67/−16.67；tip(s/tp)50→100、Rzπ/2及scale.5/.75不改world持续力，XZ约0，预定±.1通过。据此该显式profile采用1000×m×gd；不补缺省m/gd，不宣称官方动态积分或完整物理parity。首次字号太小只修字号；首次旋转误写90弧度却按π/2扣target，修为π/2后才接纳，该旧臂不作结果。

| 最终同三轮手势，零FFT / fresh HOME | 实际GPU完成输出与限定 |
|---|---|
| 3187857248，layer16 | 每轮持有窗均18次scriptWritten及18个不同几何；释放后4秒起max bind位移均约15（最高15.000001），无累计拉伸、无VM failure。三轮原图保持双脚/鞋/床单合成，恢复重复拖动。 |
| 3749463715，layer598 | 每轮19次写入/19个不同几何；释放后最大位移约.01–.20。layer562未捕获但原动画继续，不将其0写入判故障。 |
| 2998757800，layer23 | 17/15/16次写入，持有为固定点40.94812、释放回约.000062；单hash稳态不等于停滞。未用于重力推导的无重力样本保持再次捕获。 |

三包App exit0、surface1→0、GPU drained，实际原图经目视核对；这里只闭合本交互，不关闭完整样本或其他效果。最终App SHA `f7ce1055f20095e023266d121e380591dd8d757d35761bce4fa5ec24d13ed885`，debug dylib SHA `901799fae4e4ae7fe6398fec49697f7b339dee9653f4582984e2c0078437a56d`。一次保留的Debug build 83.82秒、4409输入无漂移；15个最近physics行为方法通过，含完整MDLS健康邻骨/坏JSON与边界反例。独审1项P2已修并复核关闭；未修改的UI/IPC三项actor警告仍在完整build日志，不称warning-free。

此前16点的临时build与修前/修后318原始目录在恢复时已被清空，18/0/0→18/18/18只保会话观察，不充作可复用raw基线。当前正式结果已用相同产品源码的新App重建重采三个原包；不为补文件重复官方研究。必要结果归`.artifacts/scene-evidence/runs/puppet-translation-gravity-20261028/{official,subject,control374,control299}/`，合计39.59MiB、逐文件SHA核对、单包≤32MiB、普通14天/总5GiB；不含私有PKG/MDL/纹理、App或HOME。可重建副本清理，一份增量cache留后续。缺省重力字段、旋转/角冲量/IK/rope、宽parent链、动态官方相位/HDR/多屏及性能均未认领；这些能力边界只归对象/API合同，不继续把已恢复的318重复拖动列待修。
