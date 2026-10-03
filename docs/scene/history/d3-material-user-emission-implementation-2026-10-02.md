<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# D3 F4：2D material 自发光亮度用户属性（2026-10-02）

> **历史证据 — 非现役入口**。设计由[D3 F4](../roadmap/batch2/2d-lighting-material-design.md#f4-material-user-emission)拥有，开发顺序由[RF10卡](../roadmap/batch2/reference-evidence-implementation-cards.md#rf10-pbr-direct)拥有。本片产品/App已获独立终审ACCEPT；冻结范围与未验证边界如下，不代表完整D3或官方parity。

## 基线、owner与隔离

基线`769d8a5e11daa8da4c38c33a92bb6418f1c97b55`。RF11计费纠正已独立提交；本批接通catalog材料的合法emissivebrightness用户属性，沿原material绑定编译器、property Program/snapshot、原live事务和唯一lit consumer。Metal ABI与F3数值策略不变；实例实时输入、其它材质字段与完整Scene一致性不由本片自动获准。

root、实施者及审查者均未接收原始私有静态表达。只消费现有经审查中性合同、自有代码和合法作者字段；无Reference Project原始算法复制。三份受保护Scene权威与并行layout排序保留。

## 设计与已知作者输入

合法3437487219的materials/Universe.json SHA`4fc65fa8a29edccefbe94fb0fed2ea0fc45c87e2607d5b91e2fbb34d804d2cd3`声明emissivebrightness user=constellations、作者fallback=2.3；project slider默认1、范围0…1，三层146/135/143共用material且无instance覆盖。只读trace发现material catalog未解析wrapper，原compiler/live准入仅接staticModel，2D profile因未解析wrapper关闭emission并漏map需求。此trace本身不是App证明。

独立设计ACCEPT绑定`design-v1/manifest.json` SHA`f2913f2dfd01ab053fb19ff61e333399e7136434f8e5b4243636b153160fc1ae`；批准状态与稳定anchor释放后`design-release.json` SHA`ae8951e59d8301193dc8094062dbd1fc7a05955a61e3925b9c15cf4818ba0828`。窄登记`scene-2d-material-property`批准后才授权产品写入。重要裁决为：显式instance键包括0/null/非法值均抑制底material绑定；启动缺effective fallback与live非法更新拒绝分开；结构需求依已编译能力而非当前亮度。原Program仍唯一决定fallback和revision。

## 实际修前反例

证据根`/private/tmp/mwx-2d-material-property/`。CPU `red/prerun-manifest.json` SHA`da33182fd09325be2389d76775ccc8d4f0394987c78e9cc0838f5fed59c0ca58`冻结101个实际源码、harness、输入和预声明期望。实际SceneRuntimeModelBuilder串起project/catalog/document/descriptor/Program与profile；链外leaf stub范围保存在harness。预期三个层级target和default1；结果instructionCount=0，三层均无snapshot值、无emission、无map需求，`cpu-comparison.json`明确pass=false。不是Python模拟或源码形状断言。

旧App使用RF11冻结`/private/tmp/mwx-rf11-target-budget/source-v1.app`。`red/app-prerun-manifest.json` SHA`1048a5534b29fc587acb5fe84fc0a3538067ca1cfa2a20973f73c8297fe17c67`绑定三个工件、runner/support、输入与数值oracle。三层自有不透明黑底、无灯、合法emission map/color，另有绿色健康邻层。

| 实际场景 | 三个接收层ROI结果 | 结论 |
|---|---|---|
| wrapper + 默认1 | 全为0；预期RGB64/128/32 | FAIL，启动属性未消费 |
| wrapper + 启动0、live改1 | 更新accepted=false、after全0 | FAIL，实时消费未接入 |
| 同材质仅将brightness改literal1 | 三层均RGB64/128/32 | PASS，静态渲染正控制 |

三次均正常完成、exit0、gpuDrained，绿色邻层像素计数3721。root目检wrapper与literal终端PNG确认前者仅邻层可见、后者三层均显示；原始日志与PNG保留。default/literal未发live命令，摘要liveAccepted=false不算拒绝证据；只有zero-to-one日志中实际命令accepted=false用于该判定。此自有presentation不是原Universe完整包恢复证明。

## 原Universe完整包基线

`red/universe-baseline/prerun.json`在运行前绑定RF11 App、runner及原输入：project SHA`00cae8424848aa3a04e0b3ccd7ccb7c334537fe2fb090ed296cec809abad3bd4`，pkg SHA`518358c55cdf0b281a0234a72600cfe9d3af708c369a40a9f102e5a76cd86935`。隔离原包未修改作者内容，21层、8 image、3 effects，ready耗时17045.803ms，已有GPU完成帧、终端PNG、exit0和drain。root目检看到地球、银河、星点及钟表；不能将此基线写成原包启动失败或全黑。

日志另有三条emission invalid-or-unresolved并关闭的观测，但仅此不足以量化整图缺失范围。后继须证明该属性的具体贡献或保持有界材料presentation上限；runner中心/greenPeer字段不是此完整场景的断言。一次Debug准备耗时不是性能基线，未作性能结论。

## 同key兄弟与验证入口

限定扫描原包20个JSON/JS文件，constellations显式出现于project声明、scene三个alpha wrapper及material brightness wrapper；没有脚本文本的显式key命中，不排除计算式脚本访问。旧runtime evidence实际登记三条layer alpha instruction，key不在rebuildRequired列表，146/143隐藏、135可见。故原包0/1全图变化已有alpha贡献，不能冒称自发光修复；本片需六target原子门，并用固定alpha材料presentation归因emission。

真实同会话0→1→0需要多步输入，现debug runner只ready后发一次dictionary。本批为原DEBUG runner两文件另落顺序输入补充设计、独立审批与窄门，增量独立ACCEPT绑定`design-cycle-v1/manifest.json` SHA`f45bf7b38497aeca9e5e21cb1b2624416b12b818ebb93caab385093854d6ebd2`，仅批准状态释放后的`design-cycle-release.json` SHA`77fbda1c52cdb09d678a9ad9f97361434026259a23ef9f1ccf1933d00ca6a21f`；两App文件此前未写。输入仍调用原host属性事务，复用原periodic capture，不引入产品时钟。

## 实施中纠偏

初始增量遗漏了已批准的静态合法color前提：brightness binding先生成，非法color使profile不再发布consumer，从而让同key原alpha也被all-consumer门拒绝。root追踪、实施者复核成立，暂停最终冻结；按原F4合同让compiler/profile共享静态分量选择，只为真实可构成emission的输入产生新目标。缺坏map或作者关闭组件仍由既有可选输出规则处理，不等同非法color；不取消原属性事务的原子拒绝。新增六target正常与非法color只保原alpha三target的行为对照，最终验收另记。

独立静态终审另发现Puppet image的新brightness target会被准入，但真实geometry在lit producer读取snapshot之前已被拒绝。已在新绑定编译入口限制到实际可消费receiver，保留原alpha/静态/3D；用实际model.puppet descriptor反例验证不再发布虚假consumer。captured-main utility及transparent quad不属于该image准入，不增加无producer guard。Puppet受光仍是后继能力。

DEBUG序列最初把index插入旧live日志，破坏benchmark连续字段；改为完整保留原行，另发sequence-step事件，避免尾部keys捕获也被污染。中间build失败和source-v1中止App现场保留，不计最终通过；最终身份与结果见后续验收。

## 修后实际App与身份

产品候选`source-v3/manifest.json` SHA`c0d485f127e6dbb81bf78f80c29d0c93e182f28eacf29b14b75efec2b9f33d32`，相对v2仅参数排版与缩进，不扩文件行数基线；`build-v5.log`成功。签名App为`source-v3.app`，主可执行SHA`fe1be012cd4fddebf98b615fa53f74dfb1922f566b3e9f1928e0c423f04a8c60`，debug dylib SHA`6170b995908975d7e845ff1596bfad39a55f4617044a660b54e618fb9c92b6f9`，metallib SHA`179deadfc387b3d310e1f50d43c69db0e3138a1ea41344847649143623d930b0`。冻结测试`test-freeze-v2-manifest.json` SHA`5d140d98fb95cb44435740b01e8f14e7a9bb127db725586565e1dfb45cbf86eb`；命令与运行前oracle在`app-v3-command.json`和各case的`prerun.json`。

`app-v3.log`八项实际App门89.791秒全通过。普通层三ROI在同会话0→1→0得到黑→RGB64/128/32→黑；非identity半亮效果为黑→RGB32/64/16→黑。静态instance两层保持0与0.5，仅继承层变化；非法live类型被拒绝、旧亮帧保持，下一合法0恢复。非法静态color只保原alpha更新，不毒化同key。非法/缺payload序列没有执行前缀，也不退回single；原single参数仍正常。各case仅一个candidate和session、更新前后window相同，健康邻层保持，已完成帧及drain成立。root目检普通层亮帧，独立全证据复核已通过。

utility疑虑属于一次静态审查误判：虽包内可自带utility material，descriptor先生成composition/project/fullscreen类型，已有image准入将其排除。实际disk-builder三个带模型/material/effect反例也无新增binding，详见`utility-probe.log`；撤回finding，没有新增防御分支。

## 后续验收边界

`verification-summary.json`按完整方法名去重，50项定向测试通过（33实际Swift CPU、2 Python CLI、15存量形状检查，后者不是产品行为证明）；31项中间门与11项最终门不相加冒充唯一方法数。含原3D、startup instance、身份/事务、非法color/Puppet边界、profile/map与实际Swift参数解析。相邻routing模块仍有一项HEAD既有源码形状测试ERROR（`test_unready_deferred_selection_preserves_previous_current`查找已不存在方法），精确HEAD源码隔离复现见`head-routing.log`，因此不声称整模块全绿。本批增加参数触发的另一精确调用形状断言已退役，并由实际行为门承接，不能把它误报成旧失败。CPU capture shell替换GPU分配与light packing且手填activeConsumerTargets，不能独自证明Host激活或GPU编码。

最终`code-health-final.log`、`defense-final.log`、`design-gate-final.log`通过；防御面保持0死入口/18典范helper/3吞错模式，未扩基线。旧benchmark parser实际解析v3的12条live事件且keys完全为constellations，见`legacy-parser-v3.json`。source/tests/App事后身份与冻结一致，产品和测试职责清单为`owned-final.json` SHA`7617662e3d4d23d6e93141bbc8083f9fe660bfc534e2903c6d0206468bb0626b`。

`universe-whole-v3`用同一原project/pkg、保留作者脚本执行0→1→0；实际runtime evidence中constellations由原三个alpha扩为三个alpha+三个materialConstant，隐藏146/143未毒化事务。两次更新accepted=true，单candidate/session、window稳定、完成帧和drain通过。root读取了六条实际instruction并目检原包亮帧；完整包图像受alpha、脚本和动画共同影响，不将其差分归因于emission或宣布官方parity。

`universe-presentation-v3`另外保留原material及其资产，固定alpha、隔离无灯黑环境，沿同一属性输入0→1→0。亮帧在预声明card区域最高249，225644个像素达到预声明亮度阈值；前后off图完全相同，健康邻层3721采样点稳定。root目检看到该原材料的银河自发光；此presentation证明材料贡献，不冒称原21层布局或最终官方数值。两个运行均绑定v3 App且事后工件不变，精确输入与oracle见各`prerun.json`，结果见`result.json`。

文档角色13项通过。补跑角色与selector共77项时有9处失败断言；以HEAD的selector、registry、测试及build脚本四份精确源码隔离复现相同9处（`head-selector/identity.json`、`result-v2.log`），分别为既有design-gate预期遗漏和cursor组漂移，本批只扩原pbr组映射。此处不声称selector全绿，也未为通过旧断言放宽门禁。未新增直接stale recordID注入、暂停恢复运行门；原Session identity与事务未改，仅沿现合同复核。未重跑未改Metal的全normal/graph数值套件，无官方parity、性能或完整D3完成主张。

## 独立验收与移交

`product-v3-review.md` SHA`8c5ad825dc3383f8aeb575ae896af25732a48640a765bf05c9ba6f05e8e6e024`明确ACCEPT；复核12现存产品及删除、1017 Swift依赖、455测试快照文件、三个App工件，并独立重算八case的56张PNG、44个PKG条目及两个Universe门的12张PNG。真实Host六目标以实际Program、原全consumer原子检查与同会话accepted事件闭合，未借CPU shell替代。完整包两次截图因superseded/teardown未发布，不影响事务、实际完成帧与安全drain；不作全图像素因果声明。

稳定职责移交[架构§3.4](../architecture/runtime-architecture.md#34-通用执行不等于单体-renderer)，本批两个窄登记退役；设计批准/释放的历史身份保留于本记录。DEBUG序列由原runner及实际消费者测试维护，无新产品开关。最终整批清单及审查保留于证据根`final-batch/`，提交仅包含本职责；layout只提交编译器更名，不搭入并行排序。下一批按现役RF10路线明确环境reflection输入来源、生命周期与可观察门后独立实现，继续阴影及其它材料接收者，不能因缺少数值方法直接跳过。
