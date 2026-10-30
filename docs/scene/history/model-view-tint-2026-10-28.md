<!-- document-role: historical-evidence -->
# 静态模型视角双色：2026-10-28

> **历史证据 — 非现役入口**：当前问题由[断点队列](../roadmap/scene-open-breakpoint-queue.md)拥有，本文仅记录本批验证边界。

基线 `a6e86559a`，独立工作树 `MWX/scene-capability-followup`。本批只修无 Tint Mask 的视角权重及 tint 的提前 Half；不扩展 Chroma 表面 profile。

## 已复现的公共语义

合法 stock chroma4 的输入行为区分 mask 与无 mask；无 mask 为 signed facing 的线性双色，指数只属于 mask 分支。343 的 Cloud114 确为 chroma4、mask0，现准备结果走 legacy 模型 consumer；Earth112 另有 generic4 profile。修前把两者都截至0…1后指数化，改 exponent 会错误改变无 mask 输出；大 tint 端点在有效乘积前转 Half 会误饱和。

在原 `SceneStaticModel.metal` 复用既有 `materialFlags.w` 分流权重、统一 Float tint 乘法。coverage、PMA、零覆盖 discard、深度和资源/取消链不变；产品净减7行，无新 owner/持久状态。保留 masked 现行为；未声称补齐 mask 纹理混合或整个 Chroma。

## 验证与身份

- 原产品运行扩展后的现役 `test_scene_static_model_emission` 为 RED（20项失败），候选6个行为门全部通过；复用生产 ModelPipeline/MSL，不另造 renderer。
- 独立手算 RGB/A：facing .5、front .75/back .5、基色 .25/coverage .5，无 mask 输出 `.078125/.5`，exp2/4相同；mask分别 `.0703125/.5`、`.064453125/.5`。负 facing -.5 为 `.046875/.5`；法线等比例/载体标签变体、PMA输入、layer fade及等色反例通过。原 emission/fog/表面灯光/HDR边界继续通过。
- Debug 基线与候选构建均成功，6217输入各自冻结且构建期间无漂移；候选增量14.69秒。两份 App 分别真 Team `H9QWU9XN8R` 签名并严格验证，benchmark 前后身份一致。
- 原包343与未参与修法的361各做修前/修后9秒，固定pointer、静音输入，全部exit0、loaded1.0、surface1→0、GPU排空。候选361保罐体、白圈与文字；只证 renderer 相邻健康，不是第二个 Chroma 受益样本。
- 默认343两轮 `colour="2"`，Cloud动态back色相同；Earth/Cloud会按update累计旋转，现报告未绑定snapshot frame，故不能把全部像素差异归给tint。完整官方图还存在viewport/时刻差异，不认整景对齐。
- 仅补两次固定姿态控制：复用同两份已签App和合法启动属性`earthrotation=0`，6秒/固定pointer/静音；各约19.7/19.9秒（含准备与停止），exit0、身份未变、surface1→0/GPU排空。Cloud前三帧world一致。预定全地球ROI的8位可视RGB平均绝对差`.575/.271/.126`，右夜区`.151/.091/.031`；天空对照`0/0/.000026`。这确认局部小幅tint响应，不代表完整夜侧或官方贴合；原始PNG保留，8位统计不冒充线性HDR。
- 独立只读审查未发现本diff新P1/P2。遗留 legacy `litColor` 仍有 Half 转换，不能称任意有限HDR安全；masked纹理混合与完整表面参数不由本批扩展。

## 保留与剩余

必要身份、输入冻结、红绿/治理日志、实际报告及固定姿态修前/修后原图归主仓`.artifacts/scene-evidence/runs/model-view-tint-20261028-baseline/`与`model-view-tint-20261028-candidate/`。同阶段合成一包，均小于32MiB；报告保留原裁决并明确未归档的默认343重复截图。普通结果14天、总预算5GiB。两个已停止的staged App、HOME、样本副本与冗余结果当轮清理；连续后继只留一份构建缓存。

当时未闭的宽暗区由[10-30后继](#hemisphere-basis-20261030)定点复验；完整光色、MR/specular/pigment、间歇全屏闪烁与collision仍归现役队列。未做CPU/GPU/启动收益比较。

<a id="chroma-response-20261029"></a>
## 2026-10-29 Chroma独立响应资格

当前Cloud114声明chroma4、metallic=.1/roughness0、彩色specular tint和pigmentation.2，现consumer仍缺独立响应；不把它并入generic4或调整Earth总gain。新自有explicit albedo板、neutral tint/specular、pigment0、固定白directional/非零clear、SDR无Bloom，在同1000×650与实际sRGB ICC下得到真正PNG：r=.5正向、r=1正向、r=.5固定Y倾斜三臂中央RGB中位数分别107/66/45，两次静态捕获逐臂SHA相同，clear均32/32/64。Root另实看三原图确认灰板/倾斜；C近侧超出client，不认完整四角几何对齐。

六图magic/解码均PNG，guest/host hash和ICC一致；没有把旧JPEG转壳或作为精确golden。只确认独立roughness与联合normal/view/light响应可用于最小设计，不能凭三点唯一求BRDF、拟gain或将generic4改名。未跑当前macOS同新载体；Cloud的r0/彩色specular/pigment、HDR/coverage及343完整夜侧均未资格，不关闭原用户反馈。

协议、输入、固定官方身份、6张原始PNG、实际ICC、像素数据及helper失败/退出收据已归本机`.artifacts/scene-evidence/runs/chroma-response-qualification-20261029/metadata/`，普通14天/单包32MiB。首次PNG helper只读变量名错误在取像前失败，仅修变量名，未改场景/ROI；Windows自有预览/精确guest输入及本轮缓存已退出，主客户端与VM保持运行。下一步先沿原static material/shared surface职责设计，不新增渲染或资源owner，不据资格报告直接宣称产品修复。

### 453快照中的真实直接模型范围

同日定点盘点区分raw字段与真实引用：308个model叶值含52个null；256个string MDL引用分属12样本、105个sample/model路径身份，既非256独立网格也非37个加载consumer。仅查首部/材料关联得693个实例化pass，stock Chroma只有343 Cloud114，明确pigment=.2、roughness0、cyan specular与dynamic tintback；stock缺省pigment=.5，不能把缺省当0。基线中的neutral pigment0候选真实consumer为0，因此后续须面向该完整材料，不以只覆盖实验板的窄片代交付。原compact field/schema统计本来保留null/string，数字不改；此盘点不覆盖新增38或全部非二进制/Puppet材料。关联来源与未知项保在本机限期研究归档。

<a id="hemisphere-basis-20261030"></a>
## 2026-10-30：模型半球光随 canvas 轴转换

原343在固定合法rotation0、相同1512×982视口与属性下，关Cloud后宽夜区跨端残差仍保留89.3%；Earth发光10→0及backlight .5→0亦未消退。仅Sky .3→0使残差19.735→.457U8，支持沿半球光查首错，不把Cloud缺参数当主因。各臂为隔离副本，原媒体只读；原JPEG同ICC转共同sRGB显示域，固定ROI、8px侵蚀及32px网格，不是线性HDR或精确parity。两次有效on来自独立启动；误取普通主窗帧被排除，截图未绑定GPU帧。

Oct18模型矩阵改为`F·authoredWorld`后，normal也反射Y；旧半球光仍按未转换的系数消费。原`SceneLightSnapshot.make`对有效canvas高度仅交换已解析的两RGB，恢复作者±Y语义；native域、raw authored ambient、求和消费者、法线/direct/BRDF/发光均沿原链。产品净增7行，无新字段、API、owner、ABI或片元计算。[唯一合同](../capabilities/advanced-object-coverage.md#model-hemisphere-basis)。

同一最近GPU门修前四个canvas原名/改名×±Y端点FAIL，修后PASS；literal不等双色oracle经过真实make/world/resources/draw/MSL与completion。native、raw ambient、sum、direct方向和原12个basis case保持。红绿夹具字节一致，唯一产品源变化为snapshot；未重跑全模块。Debug36.202秒成功，无Swift warning，仅AppIntents无依赖提示；原菜单并行改动已由`af44ce421`提交，构建前后该源SHA未变，不据此授UI或性能收益。

候选exe `96003428…686c0b7`、实际Debug dylib `d583b2d6…3fe82`，Team H9QWU9XN8R签名严格校验通过。原343恢复Cloud on、Sky .3、emission10、backlight .5，Earth/Cloud前三帧实际encoded/GPU完成，world与基线一致；同窗口两张CUA JPEG相隔46.734秒。预定night网格残差22.105→.488U8（下降97.79%），54个明显偏亮块降为0，原图宽暗区恢复；sky控制低于3U8。全Earth仍约7.816U8残差及亮侧/云层余差，不能全部归Cloud；完整Chroma、r0/specular/pigment、coverage、闪烁与collision不销账。

未参与修法的原361短窗strict PASS，真实罐体、圆环和文字保留；该样本ambient=sky=.3提供等色相邻反例，不授新光色收益或官方parity。两次产品运行均exit0、surface1→0/GPU排空；独立静态与原图审查GO，无性能收益结论。必要因果/修后原JPEG、原日志、输入身份、红绿、构建及独审归本机`.artifacts/scene-evidence/runs/model-hemisphere-basis-20261030/`，普通14天/单包32MiB/总5GiB；临时媒体/运行HOME退出后清理，连续迭代只保原单份构建缓存。
