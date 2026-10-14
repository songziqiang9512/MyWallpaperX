<!-- document-role: historical-evidence -->

# 原生播放 CPU 与分配归因（2026-10-15）

> **历史证据 — 非现役入口**。选序和验收归[性能卡](../roadmap/performance-convergence-card.md)，属性热更新归[属性卡](../roadmap/properties-panel-card.md)。本记录只决定值得短筛的职责，不认领性能收益。

## 普通入口与 CPU 边界

冻结优化诊断 App `56ecb327…`，Release/-O/singlefile、DEBUG 开启；4297 个构建输入前后无漂移。原304经实际库选择→client→daemon运行，原默认属性，单显示器；音频捕获实际启动，外部声音未冻结。真实媒体只读，HOME/Workshop副本隔离。本配置不代表正式Release或WMO。

先取约20.25秒未附profiler的rusage窗，再另取6秒双PID sample。父进程CPU时间率6.438ms/s、daemon448.636ms/s；父进程占这两个PID之和1.415%，不是整个系统比例或所有IPC成本上界。sample中主线程图准备539、资源准入193、按层编码184、粒子更新172个非嵌套observations；等待、ARC、copy等叶分散，不能相加换算CPU比例。607条1128失败日志约30条/秒，但失败日志不是完成帧，不能据此删回调、采样或日志。

分配工具停止后的另一个约20.25秒窗，父/daemon/媒体观察helper分别6.267、491.035、0.164ms/s；这是附加过profiler的后续状态，不能与前窗作性能对照。没有普通入口completed-frame导出，未证明attempt浪费或每帧CPU。系统音频、WindowServer和驱动不在这三个PID之和中。两个会话均正常退出。

## 实际分配资格

第二会话附一次系统Allocations，实际记录9.199558秒，计量窗不与构建、测试或其他profiler并行。Statistics累计Heap为5,252,374项/3.28GiB；累计分配不等于峰值驻留、泄漏、CPU或能耗。初记的全Heap期末值小于其子类，选择范围/表头未能确认，独审后撤销该驻留口径，不用于结论。Instruments Call Trees使用MB/KB显示，与Statistics的MiB/GiB标签分别保留，不自行换算。

All Allocations + Separate by Category + Invert + Hide System Libraries区分出：

| 调用范围与存储类型 | GUI显示累计量 | 具体责任 |
|---|---|---|
| beginTextureFrame / LookupStatus字典 | 136.37MB / 2862项 | `ensureUnique→beginTextureFrame`；同类型在该子链的唯一构造点是snapshot从空reduce增长，snapshot已inline；其中包含最终必需storage |
| beginTextureFrame / PersistentEntry字典 | 64.59MB / 318项 | 提交/回滚baseline共享下的keepCapacity清空；不能删baseline省分配 |
| graph overlay全部分配 | 120.52MB / 64511项 | 临时Dictionary初始化39.90MB/24152、replacement39.90MB/24152、增长40.71MB/16207；不是64511次快照调用 |
| root rebuild / GPUInstance数组 | 627.37MB / 2231项 | keepCapacity清空328.97MB/1908，后续map/增长298.41MB/323；另有Int索引7.45MB/318 |
| child builder全部分配 | 3.73MB / 318项 | `removeAll→rebuildAll`，没有证明rope临时数组是该样本主因 |

snapshot单次预留容量和避免graph临时updates字典是后继备选，不同时并入粒子试验，也不由累计字节推断整体收益。publications会随initialize/material/copy/swap改变，不能跨node缓存整个overlay。根实例的最终数组被旧SimulationFrame/重试合法持有；不能仅改inout或提前清掉旧帧来声称复用。

## 粒子单次物化短筛：两版撤回

原排序算法保留，只把Float深度/index排序移到GPUInstance物化之前，再生成一份最终payload。rope、child、上传和旧帧不迁移；与先前直接排序完整实例/有序跳过不是同一实现。

V1本地helper捕获inout root，所有32个released-output局部形状都变慢。V2改为捕获不可变配置，非排序分支恢复原clear/reserve/append；同一基线二进制复用，仅编译V2。两臂-O WMO、103冻结输入，逐次advance的完整160-byte实例序列与phase checksum均为32/32一致，输入无漂移；局部不等于App。

| V2形状 | 基线→候选 | 局部变化 |
|---|---|---|
| 255 additive/equal | 3.083→4.792µs | +55.4% |
| 4096 additive/ordered | 31.541→60.729µs | +92.5% |
| 16384 additive/interleaved | 133.854→245.521µs | +83.4% |
| 16384 translucent/reverse | 1.013→1.177ms | +16.2% |
| 16384 translucent/interleaved | 1.145→1.556ms | +35.9% |

仅256/4096乱序透明形状下降约10.5–17.5%，相邻分支明显回退，停止该方向。未做App对照或完整多轮，V1 App虽构建成功但未启动；不为已撤候选追加Debug/独立样本/生命周期campaign。Runtime已精确恢复原SHA `b48c83309824dd7a57d6f62b55c768287e3b21b761ac567f6fa8afd5b44750cc`，无产品flag或第二路径。

新增held-old/Float收敛/nonfinite/spritetrail门未完成：复用旧固定桶生成器处理count1，第二phase桶越界导致基线harness SIGTRAP，不能记产品失败或门通过。按先筛收益的原则未为已退候选修完并重编全门。最初非WMO候选编译也曾精确中止，最终局部两臂一致WMO；不混用中断二进制。

两次独立静态审查均未见语义阻断，但不能替代上述未执行门或收益。完整原数、源码patch、App/编译身份、冻结harness、退出与撤回receipt在 `.artifacts/tmp/particle-instance-materialization-20261015/proof/`。没有CPU、GPU、驻留内存或能耗收益；不再依据同一分配资格尝试排序/container池/depth cache微调。

## 保留与未覆盖

原数、双PID样本、rusage、GUI归因与身份在 `.artifacts/tmp/native-cpu-attribution-20261015/`。普通会话退出后清理HOME、临时目录、样本副本和发现marker共170,706,968B；保留冻结App供同配置短筛、一份连续DerivedData及已有shader disk cache。分配trace退出后经CRC验证归档为151,783,226B，删除636,722,505B展开内容；归档仍超过单包promotion限额且全局证据cache已满，暂保任务目录，不扩预算。粒子未用App与module cache另清256,682,077B，原数/源码保留；GPU前轮trace仍被既有Xcode句柄持有，不删除或终止用户Xcode。

未测温度/功率、普通入口逐帧成本、最低设备、多屏或长期稳定性，不认领GPU、启动或内存驻留改善。

<a id="nonfinite-origin"></a>

1128混合Vec3/Vec2运算产生非有限z的最早位置已定位，但公开资料不能确定缺失z的算术规则；官方黑盒准备就绪后遇Windows PIN登录，未输入凭据、未执行官方case，VM已正常停止。该问题继续由[断点队列](../roadmap/scene-open-breakpoint-queue.md)保存。


<a id="graph-intermediate-screen"></a>

## 后继：graph 临时映射表短筛撤回

实际分配资格支持单独筛去overlay的临时updates Dictionary：原Snapshot内部改用Collection，五类caller传惰性映射或标准CollectionOfOne，只构造最终扁平replacements；保完整批次校验、base/COW、同selection新物理atom与增量digest。固定dependencyFrame仍须随各节点当前publication重做overlay，未跨节点cache。容量仍为原max(M,K)，未混入M+K预留或其他算法。空replacements原路径已把updates作为最终表，其存储本来不可全省。

复用现有真实owner -O fixture的9形状/每形状1200次；12产品+fixture+2驱动共15输入，两臂仅Publication产品不同，各编译与运行前后无漂移，原atom/digest/branch/weak-retirement门两臂均18/18真。共同fixture只导出既有计时读到的contentGeneration=91，不跨进程比较随机Hasher checksum。最终两binary按B1/C1/C2/B2/B3/C3运行，未重编/扩大形状；先前预审前候选只编译未计时，不混入最终数字。

| 非空形状 N/M/K/新key | 三配对C/B中位 | 基线偏差噪声 | B/C ns/op各自中位 |
|---|---:|---:|---:|
| 2048/256/8/否 | 0.9575667254 | 10.91495% | 30775.833/30837.500 |
| 2048/256/8/是 | 0.9347141056 | 7.72029% | 29090.000/27190.833 |
| 256/128/128/否 | 0.9479731229 | 4.28057% | 263496.667/254124.167 |
| 256/128/128/是 | 0.9218354326 | 3.58262% | 227394.167/209620.000 |

配对比值中位不是两个ns/op中位之比。非空改善中位仅4.2–7.8%，均未同时达到10%和超过两倍相应噪声；fresh形状涨跌交错，三项中位上移约2.5–3.1%，不据此判稳定回退。停止并撤回，不进入App或为撤回候选追加完整环境入口门、Debug、独立样本和长稳；没有新的实际分配计数、内存驻留或整进程CPU/GPU收益。避免中间表在结构上合理，不代表值得产品化；后继不继续泛型/容器微调。

独审复算27个配对比值及上述统计边界后接受停止。产品与fixture均恢复1d8c35f8对应SHA，无实验分支。原数、命令、两臂输入、原oracle及候选/撤回身份归`.artifacts/tmp/graph-overlay-intermediate-screen-20261015/`。未改变既有App，保必要源码/patch/日志，停止使用的binary与重复module cache按归属清理；唯一连续DerivedData不动。下一项以原snapshot增长热点另行筛选，不把本轮记成优化完成。

<a id="pin-retirement-baseline"></a>

## pin 退休仅基线短否证

原allocation cache的releasePin按UUID扫描resident，可能在同一completion批次重复；不沿旧key缓存，因为释放会改history/retired身份。只在原pool/cache/pin owner单列释放阶段，不实现逆索引或批量退休。预注册G32/R128 release中位<0.1ms即停；超过也须真实App分母，不能自动GO。

唯一一次-O WMO编译34真实产品源，三轮G1/G32×R0/R128：release CPU中位分别0.001250/0.009125/0.114605/0.310667ms；整周期0.024791/0.345355/0.919042/2.054959ms。G32/R128三轮0.310396/0.310667/0.315188ms、最大偏差1.46%；G1/R128偏差66.21%，保随机Dictionary位置影响，不称全形状稳定。线程CPU用CLOCK_THREAD_CPUTIME_ID纳秒，不用wall差相减。

该0.310667ms包含必要状态更新/查找/存储，非扫描独占成本；没有当前App调用分母/整体收益资格，结论NOT-QUALIFIED，不进入产品或App campaign。21个改键/history/外部pin/重复release相邻事实全true，输入无漂移，无GPU encoder/commit、App或产品修改。`.artifacts/tmp/pin-retirement-cost-screen-20261015/`保协议/冻结源/harness/原数与summary；module cache45,283,842B及已不用binary1,422,232B已清，所有进程结束。

<a id="mdl-validation-screen"></a>

## MDL双阶段校验成本短筛：资格不足

SourceFacts按路径读metadata提前发现材质，PreparedStaticModelResources稍后解码并上传几何；同次prepare重复路径已有geometryByPath复用。两入口都完整验证顶点/索引/分段/trailer，只有后者保留完整几何。metadata不构造几何、单次字节借用、临时分量复用及分块SHA已实施，本轮不重做，也未增加跨阶段packet/cache。

真实reader两文件一次`swiftc -O`，复用自有略超64MiB输入与8段混合索引邻项，五个独立进程各先暖链再测metadata→decode，两次独立Data(.mappedIfSafe)读取。材料顺序/count和首尾12分量/索引在计时后核对，五进程exit0、十项warm/预期proof一致、输入无漂移。计时止于reader返回，不含完整geometry释放/上传，不称CPU或App时间。

大输入chain五轮86.271917/60.693125/100.236333/51.264750/57.235125ms，中位60.693125ms，逐轮metadata scan/含两次read的chain比例中位44.574609%，chain噪声65.152697%；小邻项chain中位0.103625ms、噪声1084.238359%。预登记noise>5%先拒绝，故两者均STOP_NOISE_UNQUALIFIED，不因占比>10%放行、不剔除慢点、不重试或扩参数，未进产品。没有实际App启动分母、CPU/RAM/GPU收益或安全门新通过结论；未来仅在实际启动归因重新支持时重选此职责。

独审复核原数与计算后接受停止；`.artifacts/tmp/mdl-validation-screen-20261015/`保最小源码/命令/身份与五份原数、日志、结果。已停止的大fixture/module cache和审查后的binary共清105,088,339逻辑B；没有App/正式测试或产品修改，原NaN/索引/trailer/Data-slice/工作预算合同保留。
