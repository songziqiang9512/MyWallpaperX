<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# D3 材质贴图与静态自发光实施记录（2026-10-02）

> **历史证据 — 非现役入口**。本批目标与项目保守分支由[D3设计F3](../../scene/design/2d-lighting-material-design.md#f3-slot2材质贴图与静态自发光独立设计审查已批准)拥有，后继由[RF10卡](../../scene/design/reference-evidence-implementation-cards.md#rf10-pbr-direct)决定。本文记录MR贴图与静态自发光窄片的实际实施、独立验收及边界，不据此称完整D3完成。

## 起点与职责

基线`3f13619ca88290df92921292981709b283192d8c`，现有builtin标量/default及普通instance底图已闭合。本片消费[经独立审查的中性输入](d3-pbr-map-input-neutral-contract-2026-10-02.md)，采用自有数值策略，未接收原始静态表达、私有公式或payload。官方map动态parity未运行。

首断点是准备期profile无slot2声明/需求，lit payload及fragment无对应消费；既有catalog、`.mask`用途、rawFlags、逐帧candidate、独立sampler/fullUV和publication已存在。因此接现owner，不新建资源表、loader或compositor。产品修改九个既有文件，精确批准范围在本机`/private/tmp/mwx-rf10-pbr/map-design-release.json`。

设计完整审定SHA`85bda66e7b187797fd54caf9dae2d45ba41f9d14283ab9a3e89bfa3c3c60ab64`、F3节SHA`b72fabeab29805fdfb4c7af08e79304eab08d28cb2d4b85d1dbc36554a438fd5`；仅批准标题/状态释放后的全文SHA`545aa39540dd5c42490a3f87b2d27d03bcf48e8d619b1bd106abc929f0f10e3e`。设计审查已明确slot2 typed provider优先保守拒绝与现有parser的typed信息上限，产品不能另在帧内解析raw或改normal/provider规则。

## 实际修复前反例

证据根`/private/tmp/mwx-rf10-pbr/map-implementation/`。`baseline/prerun.json`在正式运行前冻结输入预期与两测试模块，旧F2 App主程序SHA`45eb659138491670dd9847f54a0cc79a8ceb063f02350921f922ff0427c290be`、debug dylib SHA`8f3ffdd4ad34caf763f12aceebaa814312fedbbddef5b9ba060cad53a7b9258e`；这些二进制属于已验F2基线。初次fixture缩进错误尚未启动App，留在`runner-syntax-error.log`；修正后才冻结正式运行，不能把语法错误当作产品反例。

正式`baseline/app.log`为3方法FAIL（44.361s），每例完成实际窗口输出，健康邻层3721采样点保留：

| 单一变化 | 预先数值期待（±2） | 修复前实际ROI |
|---|---|---|
| 启用Metallic component，R=1替代scalar=0 | RGB各82.944 | RGB各27 |
| 启用Roughness component，G=128/255替代scalar=1 | RGB各81.655574 | RGB各5 |
| 黑ambient、无灯，启用emissive | RGB 64/128/32 | RGB 0/0/0 |

这些是项目独立合同的实际无响应反例，不是官方黑盒对照，也不重用此前scalar缺响应当map证据。最终绿必须同样区分错误通道、乘scalar代替替换、合法zero退回默认和普通灯增亮。

## 数值与资源验收

产品及CPU/GPU门已通过；冻结App的10方法、15场景亦通过（`app-v2.log`，303.349s）。真实材料单变量消融亦完成，完整原场景的新旧共同失败已另记；最终整批独立终审须绑定精确清单。独立reviewer已在不读新实现/实施oracle的前提下冻结16组数值，`map-independent-oracle/manifest.json` SHA`a00ba2b4ee7ca8912f9fa3dc327f9245bb3addc545b0f9658d589efa3453953b`；此时只有预期向量，尚不证明实际GPU通过。

首轮旧标量GPU为31数值case通过（1方法，11.089s），profile相邻4方法通过（15.602s），Debug build完成。新增18数值向量首轮通过，但同次`gpu-v2.log`整体仍FAIL：其`realBudgetDenial`把decode-cache上限误当GPU allocation配额。独立复核确认现cache拒绝只禁止缓存，合法加载仍应继续；真正资源分配由SceneResourceBudget/SceneResourceAllocation先预留配额。故修正测试为两条实际owner门，不修改产品cache合同，也不把该次整体FAIL涂成绿。F3预算段同批澄清，全文SHA`e5536771995d6ca37a55a71bea44ba42616b32c67b47a18d99009ab603654563`，九个产品职责未扩张；实际配额注入不等于物理OOM。

纠正预算门后`gpu-v4.log`为1方法PASS（10.194s），含18数值向量及资源合同：cache拒绝但合法加载、shared GPU配额占满后fresh真实mask加载失败、精确释放恢复原基线、scalar/无emission降级及同源重试。日志nativeBC4/6/7是TEX格式码，实际格式为BC3/2/1，并非新增Metal BC4/6/7支持。期间`gpu-v3`是fixture的Swift optional overload编译失败，同样保留，不归因于产品。数值候选先独立冻结，清单`numeric-freeze-v1/manifest.json` SHA`7a6671be414f36e28efb1b7ea2473e567dc2166f2fd61fd97566518b99139d7c`绑定测试、三消费者及输入/实际输出；独立Decimal交叉已确认18/18个half目标与实施Double oracle一致、实际RGB均在1个half ULP内、alpha全精确（最大Double差7.254e-11），交叉清单SHA`f87e64cf36dd66c5adaf44fa46f6b21631cffd3d67a99c33a470ebcfc0498fc0`。原独立16组只预冻结未GPU执行，不与实际18加总。后续`inner-v6`两方法通过（31.312s），覆盖27项真实解析与22项实际GPU数值；补充合法brightness0和BC3/2/1的R/G消费，并将容差收紧至1个half ULP、不设固定误差下限。UV用非零X/Y原点及不等正轴尺度，独立复核确认采样82/255；不扩展既有准入之外的旋转/skew。独立Decimal再算22项half预期全相同，实际RGB均≤1 ULP、alpha全精确，最大Double差2.7492e-10；增量交叉清单SHA`2290bcb87fbcf52d88c31681914233ab10e2e2aec2cb96925705172f1ee2d371`。原16预期仍不计实际GPU数，不与22项累加。

独立静态预审另找到实际需求遗漏：只启用emission且其值无效时，profile仍发布mapAsset，Launch会加载一个不会被消费的资源。新增真实parser/profile第27项先复现：`profile-demand-red.log` 1 FAIL（19.926s），请求仍为materials/map.tex、allowed8、emission无值，预期应不形成需求。修复限定原profile：先确定可消费分量再生成asset需求，保留作者声明/诊断；合法brightness0与仍可用的MR不能被误删。修复后27项解析用例通过；非法emission-only为allowed0/required8/disabled，MR合法仍加载，合法brightness0保留。新产品冻结`source-v2/manifest.json` SHA`5e5cbe0924e224e6d875f16650bc2588f3386d54f4d5e30f2bf165bec45057da`；独立复核九个镜像及1069个依赖均与冻结一致，无新增阻塞finding。

## 冻结App与门禁

`app-prerun-v2.json` SHA`0e6a9816e03c56c623127e93c3bb31c342a2a60ebc7281ed1fc3b3c7dfe45fca`在正式运行前绑定七个测试文件与二进制，runner从`test-freeze-v2`快照导入。App主程序SHA`59d16ac941a9bd2b1e1fa0eee6ececb5124db6d4a8d74c06a9e38c41217424e9`，debug dylib SHA`585853d05f21202dc236b8220f01517a4f8b9607079539820cc8fa194084ebc3`。独审补出shader binary身份遗漏，另存运行中观测的`default.metallib` SHA`179deadfc387b3d310e1f50d43c69db0e3138a1ea41344847649143623d930b0`；未倒填原prerun，`app-v2-result.json`运行后核验两二进制/七测试与prerun一致、metallib与运行中记录一致；正式App单次执行完成，没有以重试拼接绿结果。

15个App场景覆盖三项原反例、非恒等effect、动画后续帧、instance覆盖、LIGHTING0保持原路、MR与normal共存、无效emission不关MR、缺图/坏图的normal及scalar保全、brightness0、总/分量关闭及headerless显式1不制造presence。每例验证ready/after窗口ROI、健康邻层3721采样点及GPU完成/排空，实际方法数为10，不把场景数或内部断言数当测试方法数。原三反例修复后metal83、rough82、自发光64/128/32；effect分别42及32/64/16，instance覆盖32/64/128，动画从0进入64/128/32；两effect路径实际记录graph publication、compositorConsumed、GPU completion及后续帧。四个关闭/冲突场景为0，缺/坏map保留normal后的ROI为69.55，MR加无效emission为96。

非App累计41个不同方法通过：其中5个在v1实施身份执行（旧scalar数值1、profile邻接4）；36个在v2执行，不能把历史v1门写成最终v2重跑。`verification-nonapp.json`列出去重方法及各次log。最终inner两方法通过（29.587s），含同URL color与mask用途隔离；格式/脚本解析邻接30方法通过（23.900s）。normal/lit邻接两方法通过（19.132s），GPU资源encoder及真实graph executor三方法通过（86.348s）。v2 Debug构建与严格签名通过；code-health为0错误/238现有warning，scene-defense保持0 dead entries/18 helpers/3 swallow patterns；设计门通过。文档checkpoint25方法通过（1.688s），最终文档25方法及退役后的设计门也通过。这些门不代表官方像素parity或性能验收。独立审查已对v2产品、自有App和真实材料贡献门给出ACCEPT；临时`scene-2d-pbr-direct-response`登记按退役条件删除，稳定职责移交runtime-architecture，D3整体登记保持。整批提交只承接随后精确冻结清单的独立终审，不包含并行`script/scene_source_layout.json`。

## 真实材料与证据上限

只读作者JSON重核3662790108的scene entry SHA`faea17adcce6b09b40c1a722c08b53bc4f3588c3189873986c754517a9500cc5`及两sun材料，符合中性archive身份；完整场景847对象。sun-4和sun-1均有origin/scale脚本，前者另有godrays效果。因此原材料/资产的独立呈现只能证明其消费者，不能冒称完整原场景恢复；完整场景须记录实际是否执行与首断点。Universe材料brightness wrapper仍需原属性owner接通，本片不把其raw fallback当已解析值。两个reflection-only材料不改作者开关来凑本批收益。

完整原包v2隔离运行后来完成准备并进入surface，最终首断点为`Rendering/Targets/SceneOffscreenTextureFramePreflight.swift:233–240`的`frame-target-byte-budget-exceeded`：required805390384/budget794569728/residents29，后续required801766144/residents26；没有完成帧或PNG，候选超时自行安全retire，进程exit0且gpuDrained。不是外部150s kill；早期取得的decode准备栈只是中间观察，不能当最终根因。旧F2的同条件完整包对照已完成：project/pkg SHA相同，同为0完成帧/0PNG、首帧timeout与安全drain；首次及后续required/budget/residents完全相同，仅重复拒绝次数67与65不同，比较记录为`sun-whole-comparison.json`。因此本次完整包失败在旧身份也存在，不能归为F3新增回归；同样不能宣称原场景已恢复。后继由[RF11卡](../../scene/design/reference-evidence-implementation-cards.md#rf11-frame-target-budget)优先修正通用目标预算/需求首断点，再继续材料属性能力。

两原材料独立presentation的旧F2输出均为黑，新v2实际输出进入有色ROI，但首轮数值门仍FAIL：runner把预期写成255×emissivecolor，未经证明就假设map A和底图覆盖均为1。保留该错误预期与失败结果；独立审查批准改用单变量贡献门，未修改原FAIL。`sun-ablation-prerun.json` SHA`bb8e30cd105d1147e756c8e6331641e1418f3bebb127d95b76df01d1192a5cce`先冻结关闭预期RGB0±2；仅将material passes[0].combos.EMISSIVE_MAP由缺省变为0，结构化差异确认无其它字段变化，model/纹理/scene/project哈希保持。两off运行的ready/after ROI均精确0、健康邻层3721、GPU完成及drain；原on ROI分别145.7125/155.4625/181.46和236.945/192.9675/180.47。`sun-ablation-comparison.json`同时保留on原FAIL及off真实PASS。该有界对照证明原材料在独立presentation中有自发光贡献，不是原绝对像素门通过，更不是847对象原场景恢复。

正式源码和测试共九个产品、七个测试文件。证据及失败现场保留在本机上述临时目录；不将App、DerivedData、采样包或截图入库。三份受保护Scene权威未改，下一批为RF11，目标是消除通用首帧预算阻断；材料属性、reflection与shadow继续保留后继，长期Goal不据本片完成。
