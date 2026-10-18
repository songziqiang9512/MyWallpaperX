<!-- document-role: historical-evidence -->
# 共享表面 roughness 零端点

> **历史证据 — 非现役入口**。截止2026-10-19。当前有限像素策略归[F3共享零端点](../roadmap/batch2/2d-lighting-material-design.md#surface-zero-roughness)，数学职责归[运行架构](../architecture/runtime-architecture.md)，343夜侧/光色、间歇闪烁与collision余项归[队列](../roadmap/scene-open-breakpoint-queue.md)。本批不关闭整样本。

官方2.8.0.42原生Parallels窗口的合法generic4白色metallic1平面，只改roughness .5→0：两侧预登记非奇点ROI由RGB255降为0，黑plane footprint与蓝clear正控保持。该native双臂支持有界的离中心有限宽direct高光零端点；旧CLI全黑捕获及传输失败照保，只撤回“全黑即渲染失败”的推断。未证明精确NoH=1、delta/亚像素、HDR/IBL或其它正粗糙度；不把本次3D资格当成前批2D emission三色STOP_UNKNOWN的补证。

唯一产品修改在`SceneSurfaceResponse.metalh`：effective typed roughness==0时有限像素direct specular为零；原NoL/NoV下Schlick Fresnel及`(1-metallic)*(1-F)*NoL`漫反射保持，只有GGX/visibility镜面计算置于正粗糙度分支。2D scalar/合法map零、generic4模型共用原owner，无新flag/ABI/caller分流；正值floor与算序、ambient/emission/reflection、coverage/灯/阴影及最终输出不变。该有限采样策略由项目明确选择，不宣称复制官方奇点算法。

最近真实GPU consumer在修前形成2D scalar、sampled map、3D generic4三类行为红：scalar零值约185.875对独立diffuse .888，map约611对.642，模型金属轴向约509.25对零。map首轮先遇Swift UInt8数组类型夹具编译失败，无行为断言；只补类型再跑该门，实际行为仍红，保全部失败。修后7方法/3次编译PASS、冻结输入与五份测试无漂移；scalar/map各31向量，模型五个既有方法含八个零端点向量。原HDR压力改正roughness .1仍到65504，最小正map1/255仍有强高光；保Fresnel/diffuse、禁用组件、无profile/unlit、resource改名与legacy/emission/alpha反例，未放宽容差。

固定基线`511676f73f541934effefee16373115fc6cc41ec`叠加唯一header `2d714ee6a25b0dc69314471295154db8427722db7a16431b4ef57d254abaa4b6`的一次普通Debug，4312输入/外部闭包无漂移，4311 mtime保留、14.720s、严格签名0。App executable `6fed7a9c40cb1672eb0f1cb70be9e3eed84a106183bb17d37498dbce8a376b18`，debug dylib `05da73b36ab72910d93380ed567d8e73ef25d1891a4a321fe141af427c485e59`。构建用时与输入复用不是性能收益证据。

原343同输入arm、3024×1964原生背板只跑一次，exit0/FAIL[]、输入/App无漂移；根与独立审查实看原白色圆热点消失，地表、云层、蓝边、银河与星空仍可见。事前热点ROI近白像素1964→0，rightEarth平均约37/42/50几乎不变，仅为SDR描述、不拟合阈值或光色golden。两图时钟与作者phase不同、VM Date/私有累计状态未冻结；夜侧仍比目录官方参考偏亮，光色差异、间歇闪烁和旧collision继续开放，不能由单张after裁定高频闪烁关闭。

未参与修法的3617056047完整原包，layer70 SodaCan正roughness .65，同候选App原生短窗exit0/FAIL[]、无漂移；根与独立审查看到罐体印花、灰顶/底及中央虚线环、上下文字。只有candidate after，不声称与旧App外观不变、精确位置/色光或官方同phase，未验完整交互/动画及所有模型兼容。

必要身份与失败暂保本机`.artifacts/tmp/roughness-zero-endpoint-20261019/`的`tests/{red-summary,final-receipt}.json`、`build-reviewed/receipt.json`、`visual-result.json`、`independent-visual-review.json`；官方native与旧捕获失败在`.artifacts/tmp/343-model-lighting-20261019/roughness-zero-qualification/native-endpoint-result.json`及所指原始收据。正式14天包`.artifacts/scene-evidence/runs/surface-zero-roughness-20261019/`已保earth-after、heldout-361和official native .5/0，22957113B、单包低于32MiB；基线只引用既有`lit-image-emission-after-20261019/after/`，不重复复制。official输出0/1明确为本机synthetic身份、workshopID为空，不计入样本或验收分母；实际PNG/日志以正式包为准。

清理先核13份正式payload文件SHA，两例结果无损gzip保留，确认stop1→0/GPU排空后精确删除两例results/runtime、retained重复、两个旧staged App runtime_root和旧Cloud-off副本共8目录、1140056229B（1087.24MiB）。当前候选App、唯一共享source/DD与343 original/official probe供后继研究保留；范围见同根`promotion-receipt.json`、`cleanup-receipt.json`，不认CPU/GPU、内存、启动、能耗或完整官方parity。

<a id="residual-low-energy-20261019"></a>
## 后续：低能环境候选否定与真实状态资格停止

只含环境光的合格generic4载体，sky .3/albedo .5，仅切HDR：固定官方2.8.0.42与Native的SDR/HDR四臂plane均RGB19、对应clear差≤3U8；Native日志确认HDR实际enabled且headroom>1。该低能候选被否定，停止此方向，不改gamma/skylight gain；不外推强direct/HDR截断、Bloom/LUT或完整343夜侧原因。复用旧同App原图/Cloud隐藏对而未新增运行，右地球ROI约37/42/50→23/26/36，去Cloud后基底仍受光；隐藏同时改变颜色/coverage/depth，不能据此裁定Chroma BRDF。

真实默认状态仅一次官方preview，crash且无有效scene/property正控，按STOP_UNKNOWN收口。24文件hash虽匹配既有Native arm，但该arm以loose alias入口配仅在PKG内的资源，官方原project entry/alias挂载与VFS未先资格，不能认等价原包装载；有效保存属性也未读回。不把此失败说成原343官方必崩、属性原因或任何光色结论，保transport/Unicode与readiness首失败。VM保开，crash dialog及owned窗关闭尚未确认，guest stage留存；未执行产品变更或后续试验。

普通14天包`.artifacts/scene-evidence/runs/model-lighting-residual-20261019/`保两Native/两official及两crash原图、日志/runtime与最终研究/VFS/transport收据，3581142B；旧Cloud对引用原正式包。临时身份/停止边界见`.artifacts/tmp/343-lighting-residual-20261019/`的`final-result.json`、`real-default-state/final-result.json`、`transport-review/review.json`及`promotion-receipt.json`。两个Native App确认GPU排空、lsof为空后，正式逐选文件SHA匹配，两例结果无损gzip；仅删5个已停目录、21070707B，见同根`cleanup-receipt.json`。current App/DD、原343 arm、tiny输入/收据与状态未知的guest stage保留。343仍fail，夜侧/光色、间歇闪烁与collision保持开放。
