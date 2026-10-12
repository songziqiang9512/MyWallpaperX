<!-- document-role: historical-evidence -->
# 二维数据纹理标量遮罩消费修复（2026-10-12）

> **历史证据 — 非现役入口**。稳定语义归[标量遮罩合同](../capabilities/scalar-mask-data-purpose.md)，实际执行边界归[运行证据](../capabilities/runtime-evidence-current.md)，其他视觉余项归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

## 通用语义与范围

基线 `57e28c8a2c1f7024fbcbbe23c8381192fc1343c5`。作者直接将二维数据纹理红通道用作 opacityMask 时，sampler 声明与资源注册用途不同不应单独导致拒绝。沿原 `Sampler.purpose(for:)` 扩展 prepared redOnly 条件，保留原 normal/noise/data 用途、资源身份、上传与 publication；不改标 mask，不新增纹理、转换算法、profile、publisher 或 compositor。原 source-purpose 冲突先拒绝；旧 noise/redOnly 协调保持。

原 variant 私有 data 分类迁到 `SceneTextureLoadPurpose` 供两处使用，删除旧列表。LUT 仍属于 data，新二维消费另排除 volume；颜色、whole-vector、其他模式/通道、lower-chain 冲突、physical/ABI/identity/generation 门保持。candidate 与 default 分别验证，仅明确 absent 沿原默认选择；pending、unavailable、损坏输出不借默认掩盖。既有 sampler analysis 字段与缓存 schema 不变，不无依据失效仍有效的 cache。

## 验收与实际画面

自有原链基线复现 normal candidate direct/fact nil 与两帧 purpose 拒绝；同像素声明 mask 对照可执行。修后沿真实 Program/PassEncoder/Metal 验 normal 与 mask 用途各保持、两帧像素一致；变量/资源名与等价红通道表达式变体，以及默认 noise、候选 absent、错误 source/mode/channel、颜色、volume、lower 冲突和资源状态反例。资源改名后的未注册素材按自身声明 mask 判断，不伪造 normal 注册事实。独审发现首版未动态验证lower冲突与pending/unavailable，已补：material lower-noise + instance higher-normal保ordinal，launch成功但两帧Finalizer精确purpose拒绝、无GPU；pending/unavailable各有ready noise default，均在launch精确binding拒绝，无帧/GPU。未以“静态未改”替代这两类实际反例。

独审补齐反例后，新GPU模块5门通过（67.425秒，原8组合×两帧保持）；相邻3模块14门通过，原executor六门全部通过（436.453秒），原fixture与271结果键未改。281个executor输入相对上批仅本次3产品文件变化，运行中记录与运行后身份一致；它不是全64映射模块或完整语料验收。

隔离 Debug App 实际运行2960821850，277/effect4/node4 从拒绝恢复为 genericCompilerArtifact，首/后帧均 GPU completed。effect4 本身不是末合成节点；其输出由 effect5 消费，effect5 GPU completed 且进入唯一 compositor。每帧 materialNodes 23→24、rejectedNodes 8→7，effect encoded-output 23→24、failed 2→1。图级 completed 25 与终端 consumers 8 保持，不能把一节点恢复说成全图新增25个效果。截图中唱片区域有修后输出，时间和动画相位不同，不宣称逐像素或官方完整一致。

实际原包candidate ready、normal publication/content、request generation、prepared ordinal/provenance没有独立回执，继续unknown；不能从Program成功反推出全部资源事实。自有矩阵对此检查typed publication和代际。

独立2134765860未参与修法，首/后帧37材质、37图级GPU完成、14终端消费，15跳过全部作者visibility-disabled，无visual failure；实际房间、灯光、时钟保持，ready/exit0/GPU排空。目标样本也ready/exit0/排空。真实原包运行只证明内部 Host→Program/GPU/输出；普通桌面入口、多屏、音源、全部属性、官方同相位与性能不在本批验收。296剩余7个拒绝为215/effect0的4个Blur视觉拒绝及3个作者visibility-disabled；仅4个Blur视觉拒绝作为待修，作者关闭不计缺陷；本批后按用户调序转性能与属性面板，不以本修复关闭N05或整样本。

## 交付与后续

本机证据根 `.artifacts/tmp/n05-mask-admission-20261012/` 保存产品/App/helpers身份、自有红绿、原包中性回执与必要截图。真实媒体仅只读验证后复制运行。最终测试、独审、Git与产物记录由收据绑定，不把路由选择或构建成功当画面正确率。

用户本批要求的[性能收敛卡](../roadmap/performance-convergence-card.md)与[属性面板卡](../roadmap/properties-panel-card.md)已接入现役队列；先内存/启动，后GPU复制、HDR历史、首帧、长稳；属性面板先复现主线程热点与热更新断链，再补定义/type缺口。未实施项保持工作卡，不混入已完成的遮罩批。
