<!-- document-role: active-plan -->
<!-- retirementCondition: composition作者采集范围、顺序、实际source及目标生命周期获得明确行为合同并通过实施门，稳定架构接管且无依据分派撤权或由已证profile接管后归档。 -->

# D1 — composition 采集范围、source 与目标生命周期

> 状态：采集成员/模式仍为`blocked-pending-design`；现有source的准入、绑定一致性与资源生命周期窄片已实施并通过实际输出门，稳定资源合同由[架构§3.3](../../architecture/runtime-architecture.md#33-保留事务安全不扩大视觉失败半径)接管，冻结结果见[执行记录](../../history/d1-composition-source-implementation-2026-10-02.md)。旧版“composition仅采parent后代”的语义批准仍撤回，不扩写该假设。开发顺序只由[兼容路线](../scene-compatibility-roadmap.md)维护。

## 目标合同与判据

恢复作者 composition 的实际输入、效果与画面合成结果：采集哪些层、在什么作者位置采集、copybackground/passthrough如何影响它，先由公开合同、既有官方研究的中性交接和固定reference的行为证据定案；只有资料仍不能区分的关键分支才补有界黑盒。parent本身不得自动成为采集成员声明。输入沿既有 prepared graph、typed frame source、target lease 与唯一 compositor 执行。纹理寿命和源身份必须与实际source一致，不能用另一张纹理准备graph、到encode时只换外层request。

五判据中①跨 compilation/rendering/resources、②graph/target/compositor唯一权威、④冻结结构家族、⑤依赖官方作者语义均命中。③用户数据/持久化格式不涉及。新的成员/模式语义批准前只做研究与反例；明确的项目source/资源不变量可按下列窄片独立实施。

## 当前事实与证据

- **官方公开事实**：[RGB Hardware Support — Extra Notes on Composition Layers](https://docs.wallpaperengine.io/en/scene/rgb/introduction.html#extra-notes-on-composition-layers) 描述composition像场景相机，向RGB镜像它下面的所有层。这证明至少存在按下方场景内容采集的语义；其RGB上下文不能独自决定所有copybackground/passthrough组合、对象数组方向或普通视觉输出。
- **自有producer事实**：`MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayer.swift`仅识别utility类型、copybackground及config.passthrough；`Format/SceneDocument.swift:219`保留parent；`Runtime/Frame/SceneRenderDescriptor.swift:113–118`反建child IDs。没有已识别的独立render-group字段，不能把关系字段升级为成员语义。
- **当前第一处推断**：`Rendering/Composition/SceneUtilityLayerSourceRoute.swift:36`以children非空切换路线；`:199–223`求parent闭包，`:265–273`将其当isolated成员并取末后代触发。root有无child因此改变source范围和执行位置。这是需用行为反例核实的产品风险，不是已证明的官方合同。
- **修前资源首断点（基线119bbe28，已取得真实pool反例）**：`Rendering/Targets/SceneOffscreenTexturePool.swift:133–165`产生`.compositionGroup` key与`.composition` allocation；`SceneOffscreenTextureAllocationCache+SharedPair.swift:21–29`未承认该配对，commit会拒绝首次分配。`SceneUtilityLayerRuntimePlan.swift:370–388`因而局部退化。该处已有exact viewport尺寸检查；旧“未检查pool缩小”风险描述撤回。
- **修前错源断点（基线119bbe28，越过准入后已取得App反例）**：`Rendering/Frame/SceneResolvedMaterialFramePreflight.swift:658–670,828–837`把mainTarget交preparation；`Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator.swift:450`和`SceneResolvedMaterialGraphExecutor.swift:232–240`将其放入source capture操作；`SceneGraphResourcePassEncoder.swift:74–79,204–209`保存并实际绑定该纹理。`Rendering/Composition/SceneUtilityLayerRenderer.swift:43–85`后来更换外层request.texture，claimed执行仍消费已准备操作，并不覆盖它。`Rendering/Frame/SceneMetalRenderer.swift:213–241,271–285`先准入、后创建组runtime，使实际source到达过晚。中间App先修key和exact extent后，实际GPU/terminal两帧均得到主源蓝色而非应有组红色，证明此错源会到达像素；阶段身份保存在[本批执行记录](../../history/d1-composition-source-implementation-2026-10-02.md)，不与最终验收混用。
- 原交接中3226487183的“21/24/32/35”是作者数组位置，非layer ID；2522主组后代在该样本恰好连续，35位置为无效果composition。真实样本只能作回归，不能替代自写交错输入或决定算法。上述行号对应`92258a2d`附近，后续按冻结代码重核。

2026-10-02 [首轮实验记录](../../history/d1-composition-membership-attempt-2026-10-02.md)已证实我方真实parser/source route会因parent单变量改变成员和trigger，世界矩阵相同；官方自有composition已建立，但未得到效果启闭正控制，不能定采集语义。后续先提炼现有reference §6及官方研究的中性输入/输出、层序、group camera/target和生命周期合同；能建立自有正反例的职责采用我方算法落地，不以缺少像素golden阻塞。只有采集成员或flag等仍冲突的关键分支，再以可见effect正控制与加载身份做parent/order黑盒。设计状态不因成功启动窗口而改变。

## 已实施窄片：现有source准入与准备/编码一致性

**目标与依据。** 以[经审查的中性交接](../../history/d1-composition-neutral-contract-2026-10-02.md)提取职责，独立实现本项目资源合同：现有planner已选择的source应能按既有pool规则分配；准备、实际写入与graph采样必须是同一纹理及有效generation/extent。此合同不需要恢复参考算法，也不以官方像素golden为前提；修好现有路径不证明其成员选择符合官方。

**方案与owner。** 修正既有allocation cache对实际group key/allocation配对的遗漏；在source-capture preparation之前由既有pool为当前frame取得实际group target，并把它交给现役frame source准备与组写入consumer。选择应从当前已准备的utility route产生，不能新增第二成员计算、registry或graph。准备只冻结本帧资源绑定，不新增普通帧解析/编译/建图。组runtime仍拥有透明初始化、写入结束与合成次序，pool/coordinator仍拥有容量、generation和completion；复用不得把上帧内容当history。目标分配前先判断exact extent，避免缓存被静默缩小后才拒绝。沿现allocation cache submission pin在预留后立即保留source，防后续graph准备把它逐出预算；pin交既有submit/cancel/completion链，失败/取消释放，GPU完成后释放，resize时旧pin仍计费。预留只分配纹理，首次实际写入才透明clear；同帧续写load，空源在首次采样前也须初始化。具体携带方式以真实调用链最小改动决定，不引入空protocol或wrapper。

**备选与选型。** 拒绝仅在draw request换texture：已准备source操作不会读取它。拒绝临时覆写prepared graph的隐藏绑定：会形成第二身份权威。选择把真实source提前到现有binding preparation，并让写入消费同一对象；若producer实际提供不同generation/extent则拒最小unsafe unit，不悄悄重新采样mainTarget。拒绝先重写全部成员规则或等待所有官方模式定案：这些都不是修复该资源不变量的必要条件。

**fallback/route。** 保持现有成员/触发route，`SceneUtilityLayerSourceRoute`不在本片写权限。预算不足、尺寸不匹配、source不可用时保留安全父输出并局部跳过对应组，不让成员泄漏到错误目标；安全输出指本帧既有输出，不新增组history。旧generation、实际读写hazard、非法range和预算破坏按既有owner拒最小unsafe unit。每个新增guard必须绑定本次观察到的真实producer。

**纠正门。** 先以真实pool证明冷启动合法key被拒的反例；修正后同key可复用、不同root不别名，超预算/错extent仍拒绝。再以自有两色source和非identity effect证明实际prepared source采样，而非request字段保存；effects顺序、透明背景、非方形extent、下一帧移走内容无残影、resize/旧generation及实际completion进入相称门。完整App沿parser/现route→实际target写入→effect GPU→唯一terminal→next-frame给出颜色ROI和身份；已有语义不明分支明确标注项目现路线，不宣称官方parity。嵌套与带effect成员须覆盖prepared执行序与实际trigger一致：当前coordinator要求前驱已消费，不得把尚未执行的root排在其需要先渲染的成员前；沿现preparation-order owner消费已有trigger关系，不另建scheduler或重新裁决作者成员。 组内无子层的composition同样从所属组读取并写回该组，由同一pass owner完成采样前clear与encoder结束；与外组同trigger时必须先完成内层，再交外组效果，不能泄漏到全局主帧。直接合成无graph-provider publication时不虚构发布事件。CPU/结构测试不能代替可见输出；独立终审逐个核新增guard和失败半径。

**边界与退役。** 不改变parent、copybackground/passthrough或作者顺序语义；不新增默认隔离profile。本片资源不变量已移交稳定架构，窄设计登记随同职责提交退役；成员/flag开放问题继续由下节拥有。若成员后续裁决撤销旧组路由，沿同一source owner删除失去consumer的代码，不保留兼容旧错误路径。

## owner、候选与裁决顺序

作者格式/descriptor拥有类型、parent和顺序；现役 planner拥有采集时点与读写边；既有target pool/lease和submission coordinator拥有预算、generation、pin及completion；graph executor消费精确准备的source；唯一compositor输出。不得增加独立renderer、resource registry或按sample分派。

先判**采集范围**：按既有证据提取真实产生者、字段、source与顺序，区分官方已知、第三方行为和我方独立策略；不要把“缺方法/未实现”当作跳过理由。若资料仍无法区分下方非child是否进入source、child移到上方是否仍进入source，再用官方编辑器生成的自写composition补单变量实验，固定作者字段、GUI层序与颜色ROI。随后才判copybackground/passthrough、无effect与identity effect、alpha/transform、采集位置及clip。旧“父slot/末后代slot/flat”实验以parent隔离为前提，只能在成员语义确证后使用。

候选及可证伪结果：

1. **按场景下方采集**：改变一个非child下层颜色会改变composition source，parent变更在不改层序/世界变换时不改变采集内容。沿现capture owner改正顺序/范围并删除无依据subtree分派。
2. **显式隔离组**：必须找到真实作者字段组合/公开设置，并用外部层不进入、组成员实际进入的正反例证明；仅此profile才准入私有target scope。不得仅凭现parent字段推定隔离；若官方GUI/黑盒证实composition类型与parent共同界定成员，记录该组合产生者与反例，不强求另有新mode字段。
3. **模式相关**：若copybackground/passthrough或其他明确作者字段区分两者，在现typed prepared source中表达其合同，不能凭child数量、effect数量或样本身份分派。

这三者目前未定案，不以现状、旧设计或第三方结构选其一。公开说明已足以撤回无条件“非成员不进入组源”的旧断言，但尚不足以直接上线相反的全部组合。

## fallback / route 与资源约束

除上述资源窄片外，成员研究不变更产品输出。普通视觉不支持局部保留安全current；identity、cycle、hazard、预算、epoch/generation漂移拒绝最小unsafe unit。不能用更大范围的主帧采样掩盖缺失source identity，也不能把未知语义升级为永久special-case fallback。

若需要capture/隔离target，其extent、颜色域、透明clear、resize及in-flight预算由既有owner统一裁决；不能静默缩放后当exact viewport，不得将encode成功当完成。失败时保留已经存在的安全父输出不等于新增“上一帧组图像”history；没有明确作者history就不增加组历史缓存。具体extent/clip与alpha施加位置随行为profile批准，旧父viewport建议不自动成为所有composition的规范。

## 纠正门

研究卡先固定官方客户端version/hash、OS/backend、viewport/scale/颜色状态、自有输入hash、候选ROI及容差。公开与固定黑盒只交中性行为结果；不读取或转写私有算法/资产/反编译。

成员/模式实施前须将已定案profile、真实产生者及备选拒绝理由写回本设计，再批准对应登记；上述资源窄片已独立批准。自有反例必须走真实parser→plan/source→Metal→publication/compositor→next-frame；覆盖parent单变量、非成员颜色、子层自身effect、root无effect/alpha、嵌套或模式切换及相称的clear/resize/completion失败。相同用户结果不因无关child关系改变。实际顺序与source不能只以route字串或非黑判定。每个新增guard都能指名实际产生者，现役错误分派和零消费者入口随修复删除；不扩大普通帧parse/compile/建图。

## 退役条件

行为profile经设计批准，真实正反例、资源生命周期与输出门通过独立终审，稳定架构接管后归档。无依据的旧isolated/subtree路径须明确撤权或由新的已证作者profile接管。单样本启动、target存在或公开RGB一句说明均不足以宣布D1实现完成。
