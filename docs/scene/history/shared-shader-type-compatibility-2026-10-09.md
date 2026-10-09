<!-- document-role: historical-evidence -->

# 共享 Shader 类型兼容与 U21/U23 后验

> **历史证据 — 非现役入口**。截止2026-10-09；当前合同归[运行架构](../architecture/runtime-architecture.md)，待办归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

## 类型兼容片的范围与结果

基线 `e5928b54274756d8e0207de1f81997c4406babb5`。用户在 `cccea6c` 报告的 U21 `3806337293` 灰层/过曝/环形音频缺失和 U23 `3796588443` 混合/音频缺失，分别以原包隔离运行。样本仅作回归输入，产品没有样本、路径或 shader 名称分派。

本片修复共享编译类型兼容，**尚未恢复这两个被拒绝的真实效果**：U21 仍卡在音频数组双下标；U23 已越过函数返回 `const` 和作者 `fract` 冲突，当前首拒绝为 fragment `gl_Position`。不得把 CPU/GPU 小输入通过、graph 的 fallback succeeded 或原来已执行的音频条计为本片新增画面收益。

## 唯一职责与边界

- SyntaxAnalyzer 提供同一词法/声明/函数事实；generic 类型转换可独立取事实，不要求浮点循环通过 bounded 执行门。bounded `analyze` 仍证明循环预算，动态浮点循环仍拒绝。
- 现 BuiltInVectorConversion 接纳已证明返回 scalar 的内建表达式作为 `mix` 权重；VectorConversion 对返回 `vec3` 函数内已证明的 `vec4` 值、构造和唯一函数调用取前三分量，整个表达式只求值一次。未知、数组、重载和遮蔽保持不转换。
- 原 scalar intrinsic 重命名职责扩展到精确 scalar `fract`，保留作者函数体及调用；只删除函数返回位置的 `const`，保留 global/local/parameter const。既有 `mod` 边界不扩大，不以系统 fract 替换作者算法。
- 缓存按真实消费边界退旧：bounded ProgramCacheKey v16、generic analysis v15、request v26，Python request 镜像同步。准备输入/shared canonicalizer 未变，不提高其 schema。无新纹理、renderer、frame owner 或 compositor。

## 验证与运行身份

实现收据 `.artifacts/u21-typed-numeric-20261009/result.json` 保存13个代码/测试文件的 hash、行数和命令；实现 diff SHA256 `de33f46db1632186261eb6f51150ac1e21fe10fe3c5a1a4f3331f699871bda8d`。33项定向 CPU 检查通过，包含真实 glslang stage-link、bounded MSL 离线编译、缓存及请求边界。

签名 Debug build 成功且源码未漂移：App SHA256 `cea110ec0d10284b583570516ee553f121ff032211823c8f5210944edfaa604c`，Debug dylib SHA256 `4bac3b52d2e69ef49fe4e054624dc819052dd12dbbf8e3205b251cdaa9deaa80`。`/private/tmp/mwx-blend-common-20261009/build-final.json` 保存全部产品源身份。

复用现有 scalar/vector 测试的 GPU harness，自有5个输入经产品 normalizer → glslang → SPIR-V → MSL，逐项渲染两帧：`mix` 两端选择、vec4变量和函数调用返回vec3、与内建刻意不同的作者fract，全部逐通道符合预期（误差门1e-6）。收据 `type-gpu/receipt.json`。这是有界数值合同，不是完整效果或官方画面验收。

真实运行证据均在上述任务根下，使用新空 generic cache、受控频谱、原包只读副本；两个 App 均正常停止，surfacesAfter=0、gpuDrained=true：

| 样本 | 当前实际链路与余项 |
|---|---|
| U21 | `gray/typed-final`：2676/2686首effect仍各0 material/1 rejected，spin/opacity处理solid回退；灰层、过曝和环缺失未关闭。原包 SHA256 `c3726c0ac70beff0482d98335c8641553afb5cf24e60b48f07c459a20e582ae0` |
| U23 | `blend/typed-final`：131/650音频各4阶段实际执行，紫色条可见；241首effect仍0 material/1 rejected，当前准确错误为fragment位置未声明。LOVE色阶/灰色矩形仍存在。原包 SHA256 `68120c5eca62c217d98fdcbd9071112d163fa8cc40aeb3dfe204a38865712072` |

两组音频条在本片前基线已执行，不能重复计为本片收益。包索引显示 Simple_Audio_Bars 同族在5样本存在，只证明声明影响面，不证明5样本均激活或本片获益。

## 未决合同与后继

[公开变量合同](https://docs.wallpaperengine.io/en/scene/shader/variables.html)把64带音频定义为float数组；不能凭作者双下标就改成另一套host ABI。自有官方2.8.0.42实验已证明普通局部scalar数组单下标执行、局部双下标拒绝，尚不能裁定保留音频uniform的特殊语义。第一轮fragment位置表达式可见，但除数过小使XY饱和，坐标空间仍未知。

后续同输入实验在窗口有效extent前失败，未产生语义证据；必须修复公共窗口ready采集流程后再测，不能猜测flatten或直接替换gl_FragCoord。保留 `/private/tmp/mwx-blend-common-20261009/official` 中的中性输入/身份/失败与清理收据；没有消费私有实现。窗口流程已修为fresh HWND/真实extent最多60秒，并在失败时保留preflight。随后公开进程清单证实客户端已退出，重新启动所得PID10664路径/版本/hash均核同；同输入open返回0，但119次检查始终无HWND，结束时该进程已退出。没有像素证据，不推断shader崩溃或数组/坐标行为。下一实验先以过去成功的简单输入区分客户端启动与新fixture失败，不能继续原样超时重试。VM恢复暂停，未杀其他进程；精确guest目录70文件已删除，本地同hash输入保留，收据`official/refined/startup-guest-cleanup-receipt.json`。

下一门：取得保留音频数组与片元位置的可区分官方合同，再扩原编译/输入owner，确认目标节点 material=1/rejected=0并检查最终画面；灰层/过曝、背景混合及真实声源分别验收。类型片已独立只读审查，无可操作正确性或重复owner问题；审查13文件diff与实现身份一致。产品提交`c9040e6aa6bb13ea52160a292782fbfaed2c152a`；提交后逐文件核对13个已审文件及10个构建产品文件均匹配，严格staged preflight通过。原样本开放状态不因提交改变；本轮已停止的样本副本、HOME、generic cache与临时GPU二进制/模块清理148,886,657字节，明细`cleanup.json`；保留上述有界身份、截图、日志、输入及失败复现。连续构建仅留`/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d`；未知归属`.mimosa`218字节保留，residue门因此非PASS，结构/依赖/设计/代码与测试断言门通过，文档49项通过。


## 片元位置后继

基线`0330eca4`。官方2.8.0.42的成功自有controls保持全部vertex、资源和元数据不变，仅改一个fragment读取gl_Position.xy；1280×720固定窗口的三处ROI符合左上原点像素模型，最大误差0.25 U8（预定门2），两帧差0。仅移动面板x800→480后，红通道下降63.75–63.875，旧位置恢复背景，排除240×240局部坐标解释。只验证XY读取，不定义Z/W或fragment写语义。没有读取私有实现。

采集修正了PowerShell空字符串不等于native NULL及DPI虚拟化；旧复合probe全黑，公开Error确认客户端崩溃，因此旧图无坐标证据。后继音频单下标阳性控制也出现Error/黑控制图，双下标两输入未打开，音频映射仍未知。下一次先隔离audio flag和shader声明，不原样重试或猜flatten。官方自有进程、音频child、窗口及guest/shared输入已清理，原本running VM和未知新renderer保留；精确收据位于`/private/tmp/mwx-blend-contract-20261009`的`neutral-summary.json`及cleanup文件。

产品只在既有bounded emitter按stage选position输入/输出，generic fragment归一化为gl_FragCoord；无新runtime owner、坐标uniform、texture或copy。bounded ProgramCacheKey v17、generic analysis v16、request v27及Python镜像同步退旧；prepared source/VariantAnalysis未变。9文件代码/测试freeze的tracked diff SHA256为`01233525a4b54a9e07088ad3d96ee956a9241b7e1f49d738b5f51c2253d588f7`，新测试hash见`freeze.json`。独立只读审查无可行动问题。

签名Debug build成功且2806源码身份不变：App SHA256 `edee8b25a36ebb50ed831d6748db8a0d258b566bdd2a0edaa68c706824ef8510`，Debug dylib SHA256 `3e5c92ea3f8089c1324f1a59a99e5bb7851d0333744a4499feddb5318f942f1d`。8项cache/request、4项结构门通过；真实原shader经当前Swift normalizer、generic stage-link/Cross/离线Metal通过。片元位置3项门通过，实际两个backend的vertex/fragment在14组合、两帧28次Metal提交中完成84像素核验，含helper、平移viewport、不同target尺寸和vertex缩小反例。`fragment-position-gpu.json`的139源码hash匹配build；未把未知fragment写语义固定为长期测试。

U23原包隔离运行`blend/position-final`：241首effect从0 material/1 rejected变为1/0，首帧与下一帧GPU完成；后继effect消费该effectOutput并进入最终compositor。首帧effect graph记录59材质节点、0拒绝；base仍有material-pass-count降级，不能外推所有输入无降级；两组音频各4阶段仍执行，不重复计为新增收益。截图中紫色光效恢复参与背景和LOVE合成；LOVE色阶及矩形背景仍未完成官方同输入验收，不能把59/59执行当完整正确率。App正常停止surfacesAfter=0、gpuDrained=true，原包hash不变；`native-position-result.json`保存逐节点链及运行身份。U21数组/环形音频/灰层/过曝仍开放。

本片原样本副本、HOME与generic cache在已停止PID确认后精确清理27,273,187字节；保留官方中性输入、必要截图、App/代码身份、失败和GPU/运行收据。连续构建仍只留既有`/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d`。未知归属`.mimosa`218字节仍保留，residue门非PASS；不冒充工作区残留已清零。

产品提交`bd9fc353439e46b5ffa7c84aa93de543b65f6cb4`；提交后9个代码/测试文件逐一核对与独立审查freeze相同，5个产品文件与实际构建相同。严格staged preflight通过；35项文档检查通过，文档导航/预算只降同步。下一原子先归因U23的base降级、LOVE色阶与背景矩形；U21音频合同另用缩小输入实验，不新增样本分派。

## 原包混合后验

基线`21e97130`。官方2.8.0.42以同hash原包运行，1280×720两帧均有灰紫色矩形和蓝/洋红/白LOVE图案；其存在属于作者设计，不能再作为待消除缺陷。LOVE为text，作者colorBlendMode17；背景人物alpha .3、colorBlendMode23。剩余明确观察是本机背景网点比官方强；两端尚非同一时间、音频和内部工作尺寸，不据此直接修改混合公式。官方原样本证据、输入身份与精确清理收据在`/private/tmp/mwx-u23-official-20261009`。

`material-pass-count`等日志来自可选的base材质颜色绑定筛选，不证明图层丢失：三solid与composelayer无普通image材质是现有utility入口预期；两人物图层有effects且base为hostBuiltin，不属于neutral authored-source tint候选，回退附加材质tint为白，作者layer tint仍参与原source链。LOVE从未进入该image筛选。不得为消除这些日志另造base渲染链或放宽候选。

网点11项作者常量经现有schema→Finalizer→static uniform编码核对一致，包括Scale250（不按UI range0…50裁剪）、Alpha .3、三个鼠标/贴图影响参数0；`dot-cpu/result.json`位于前片任务根，非App buffer捕获。solid241的colorBlendMode28沿原compositor传入最终混合，未被mode0专用terminal replay绕过。实际stock读取确认noise256×256、white32×32全白；本机slot0工作纹理2048×1152，作者公式仅用xy/y，其比例与2560×1440一致，尺寸差异不能直接解释为网格数量改变。

原包静音缩窗至1210×786后网点仍明显，见`/private/tmp/mwx-u23-blend-20261009/blend/small-silent`。官方自有窗口以公开API校正到相同client extent后，两帧仍无同样强网点，收据在官方任务根`matched-extent/official-matched-corrected-{0,1}.*`。对该自有location提交13项作者bool/color默认值，公开CLI无readback，故不把返回成功等同属性读取验证。两端时间、音频与内部pass extent仍未对齐，下一门是官方参数读数及pass执行哨兵；此处未新增产品修复或宣称完整画面验收。本机已停止的样本副本/HOME/cache精确清理27,273,187字节，保留截图、日志、请求和身份收据，原包hash不变。


## solid源尺寸后继

基线 `16a4d52a`。首错在已有静态源入口：solid 无条件使用共享1×1白占位、没有 Candidate，作者明确的静态 slot0 未进入原 resolver/loader。现接回 prepared base image→Candidate→Store；没有可解析静态源继续原程序化 fallback。不是新增纹理算法，也没有把32写入产品。正交可见、非provider的简单 color 链按实际源 extent 运行；mode0仅单stage复用现 terminal Program/MainPass，straight PSO恰好关联一次；高级混合仍从 graph-final 进入唯一 compositor。独立审查指出多stage普通混合尾段停用、前段失败尚未守住输入/回执，因此本批撤回该扩展，保留旧高分辨率路径，余项进入断点队列。

官方2.8.0.42自有输入用公开shader导数和颜色哨兵区分采样/栅格，未读取私有实现：mode0两阶段中，前段单位UV栅格32×32，末段覆盖1397×786（1210×786 client裁切16:9 quad），末段slot0 metadata为32×4；mode28前末段仅证≤512，不能宣称精确32。控制色误差≤0.5 U8，两帧稳定。原始身份和清理收据曾在 `/private/tmp/mwx-solid-raster-metadata-20261009/official` 与 `mwx-solid-raster-mode28-20261009/official`，续接后目录已不可访问；下述数值来自本会话已完成的工具观察，不再将旧路径冒称现存证据。曾尝试整链取占位1×1，虽消除网点却破坏光束：普通光柱相对官方最大误差223/255，已完整撤销。只改resolution uniform也未消除网点；一次测试FBO副本因instance pass数量不匹配未准入，不作视觉证据。

首轮签名Debug App SHA256 `3171f09ebdb15f5a994359f2fa69653046cfd9f5617fc2e9a08e8cd658d75316`，dylib `c198e6c99b629761be66b39cd43cf55dc1c7786f698fd4b24ad37ddac61057fc`；2806产品源码与构建一致。U23原始entry字节副本和固定光效副本均实际播放；241两stage现在input32×32、rejected0、GPU completed，末段compositorConsumed=true。固定输入1210×786画面强网点消失、紫色光束保留；背景ROI相邻亮度差XY由10.966/11.020降至0.721/0.678，官方两帧约0.84–0.88/0.73–0.81。ROI只证明异常高频改善，其他动画未锁相，不是全图parity百分比。普通单光柱同输入有效内区与官方最大误差1/255、p95=0，未出现占位尺寸候选的回退。

终端graph/pass真实GPU门通过，包含straight半alpha只关联一次、预热后不再编译；coordinator覆盖straight/opaque、data拒绝、同buffer、epoch、one-shot和append失败；显式solid静态源与无源fallback、原runtime bridge近邻门通过。修正了standalone capability stub与Python receipt消费key，保留初轮失败日志，不把其计作产品成功。独立只读审查所报三项产品问题以收窄profile及正确回执处理关闭，无新增renderer、registry或输出owner。构建与少数运行不代表其他混合模式、完整交互、真实声源或长稳验收。

本批续接时原临时目录及测试句柄失效，不能宣称旧截图仍可读或旧测试最终通过；已观察的数值单独标记为会话恢复记录。重新构建、原始包直接播放及近邻门的现存收据/最终图保留在 `.artifacts/tmp/solid-source-domains-recovery-20261009`。promotion被既有总缓存预算拒绝，prune-expired无可删项；未提高额度或清理未知材料，不冒称已入正式证据缓存。当前可见专项为“强网点及普通光效不回退”已闭，整样本外部音源/交互尚未闭。下一优先 U21 音频数组双下标→环形频谱/灰层实际输出；不能将 U23 的源尺寸修复直接套给 U21 或修改作者参数。


续接补验：签名Debug App `18981d97623140fded6d52e5d3470529e67a93608054da47ef9bd2a98a1c22ae` / dylib `7db720f9f237c716be754c7d4d8032a051eab71a86a3ed8783860b99fd7bc4cc`，4239个产品/项目文件构建前后hash一致。直接复制原始scene.pkg与project.json（不重打包、不改shader），受控PCM下上下两组频谱可见，131/650各4stage均GPU完成且末段被compositor消费；241两个stage为32×32，背景强网点消失、光束保留。首帧44个effect执行记录合计59材质/0拒绝，exit0、surfacesAfter0、gpuDrainedtrue，原文件hash不变。40项近邻CPU/GPU测试及49项文档测试全部通过；结构/依赖/防御/代码/设计门通过，仅既有未知归属`.mimosa`218字节使residue门非PASS。未重跑旧官方截图实验，旧对照数值保留明确证据上限。

本批已停止的原包副本/HOME/cache精确清理27273187字节，明细`cleanup.json`；唯一构建缓存留 `.build-cache/solid-source-domains-recovery-20261009` 供下一批增量验证。


<a id="u21音频索引后继"></a>

## U21 音频索引后继

基线 `a75020bb`。原包实际首错为 float 复合数组下标（generic stage-link: scalar integer expression required）。两环首effect拒绝后白solid继续通过spin/opacity和mode31，故灰色斜矩形、亮度增量与环缺失首先归同一编译断点；不据此改混合公式。

官方2.8.0.42黑盒合同：六个保留float音频数组（16/32/64、Left/Right），float helper参数由有界循环或动态UV传入[0,N)内整数/小数时，`audio[bin / 4][bin % 4]` 与 `audio[int(bin)]` 同帧相等（shader阈值1e−6）；半段错位负对照同帧均不相等。六组正条全部绿色、反条全部红色，排除静音全零假阳性。直接main动态双下标及普通const float数组双下标被官方X3121拒绝，不能推广成任意二维数组或另一套host打包ABI。追加动态helper和去掉floor的小数helper正反对照均通过，因而删除拟议的caller-loop证明，无须新增循环准入职责。未裁定负数、越界、副作用或任意row/component表达式。公开资料/作者输入/自有probe/官方黑盒之外未消费实现表达。

最小实施边界：在已有authored index归一化owner降低这一已证索引形式，保留N个float的现host输入；未证或绑定不唯一的表达式不改。同一实际compiler随后暴露vec3 helper返回vec4局部值，原声明扫描被另一函数同名col阻断；现仅在原VectorConversion按所属函数获取声明事实，保留同函数遮蔽/内层scope拒绝。必要输入、同帧正反输出、客户端身份与合同保留于 `.artifacts/tmp/u21-audio-contract-20261009/neutral-contract.json`、`six-live.png`、`six-live-pixels.json`。早期简化fixture使官方崩溃、音频未加载及直接RGB比较受显示颜色转换影响的尝试均不作语义成功证据。实现与原包运行结果见下。


最终签名Debug App `64f8abf219f7873117613f5f2e618d415e8915317518ad28a31d338906c295b7` / dylib `b42ffd42ec46d318c605ed8fc47795b341368da5c49c67512f725ed39d53cead`，4239个产品/项目文件构建前后hash一致。原始pkg/project字节副本、受控PCM、7秒隔离Host运行：两环2676/2686各3stage在首帧/次帧/resize后均material=1、rejected=0、GPU completed，末段compositorConsumed=true；首帧21个effect材质/0拒绝。截图中灰斜矩形消失，肩胸部额外增亮解除并恢复衣物细节，环形频谱可见。原包hash不变，exit0、surfacesAfter0、gpuDrainedtrue；最终身份/逐节点结果/截图在同根`accepted-u21`。

本片不改FFT/gain、host音频数组、作者参数或混合公式，不新增runtime/输出owner。独审发现逗号声明shadow、括号lvalue写及highp inout/out参数顺序绕过guard，分别复用原declarator facts与原varying只读scanner修正；旧scanner原位副本删除，varying默认语义不变；原mutable参数事实改为识别完整参数范围的out/inout。最终13路径静态独审ACCEPT，身份`review-freeze.json`。32项normalizer、4项varying、2项loop近邻和7项cache/request门通过。六数组合同是通用兼容；242个scene.pkg文本扫描只确认U21命中该具体形式，另一个非同名包未计，不冒称其他样本运行受益。

本样本人工报告的三项现象已在受控PCM原包关闭（3/3），不是完整正确率。官方与本机音频/时间/窗口比例未锁相，不宣称全图逐像素一致；外部播放器、完整属性交互、长稳与正常App→daemon入口另验。下一批按现队列优先核剩余颜色/窗光与光束共享首错，不重做已闭SDR shoulder或重型启动；本批必要证据保留于上述任务根，正式证据缓存预算限制不变。官方自有窗口和guest输入已清理、VM恢复暂停；测试副本去重清理见`cleanup-first.json`，连续迭代只留既有构建缓存。

六数组GPU数值门沿最终Swift normalizer→bundled glslang→SPIRV-Cross→Metal，分别输入不同频段数值，两帧读回最大误差7.5e−8；保留既有N-float布局，证据`gpu/receipt.json`。该门为反射buffer自有输入，App真实输入另由上面的原包受控PCM验收。首轮自有vertex缺少标准attribute输入且声明行不规范，被normalizer拒绝；修正fixture后通过，未为测试修改产品。
