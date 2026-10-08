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
