<!-- document-role: active-plan -->
<!-- retirementCondition: composition作者采集范围、顺序、实际source及目标生命周期获得明确行为合同并通过实施门，稳定架构接管且无依据分派撤权或由已证profile接管后归档。 -->

# D1 — composition 采集范围、source 与目标生命周期

> 状态：`blocked-pending-design`（2026-10-02 重新裁决）。旧版已批准的“composition仅采parent后代并在独立target输出”方案撤回；它没有区分普通父子变换关系与实际采集范围。本文件重新限定需要定案的合同，不允许继续扩写该隔离组假设。开发顺序只由[兼容路线](../scene-compatibility-roadmap.md)维护。

## 目标合同与判据

恢复作者 composition 的实际输入、效果与画面合成结果：采集哪些层、在什么作者位置采集、copybackground/passthrough如何影响它，必须由公开合同与可区分官方黑盒确定；parent本身不得自动成为采集成员声明。输入沿既有 prepared graph、typed frame source、target lease 与唯一 compositor 执行。纹理寿命和源身份必须与实际source一致，不能用另一张纹理准备graph、到encode时只换外层request。

五判据中①跨 compilation/rendering/resources、②graph/target/compositor唯一权威、④冻结结构家族、⑤依赖官方作者语义均命中。③用户数据/持久化格式不涉及。设计通过前只做公开/黑盒研究、自有反例与现代码只读定位，不实施新的视觉语义。

## 当前事实与证据

- **官方公开事实**：[RGB Hardware Support — Extra Notes on Composition Layers](https://docs.wallpaperengine.io/en/scene/rgb/introduction.html#extra-notes-on-composition-layers) 描述composition像场景相机，向RGB镜像它下面的所有层。这证明至少存在按下方场景内容采集的语义；其RGB上下文不能独自决定所有copybackground/passthrough组合、对象数组方向或普通视觉输出。
- **自有producer事实**：`MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayer.swift`仅识别utility类型、copybackground及config.passthrough；`Format/SceneDocument.swift:219`保留parent；`Runtime/Frame/SceneRenderDescriptor.swift:113–118`反建child IDs。没有已识别的独立render-group字段，不能把关系字段升级为成员语义。
- **当前第一处推断**：`Rendering/Composition/SceneUtilityLayerSourceRoute.swift:36`以children非空切换路线；`:199–223`求parent闭包，`:265–273`将其当isolated成员并取末后代触发。root有无child因此改变source范围和执行位置。这是需用行为反例核实的产品风险，不是已证明的官方合同。
- **旧路径的自洽性风险**：`SceneResolvedMaterialFramePreflight.swift:658–670,828–837`仍将mainTarget交给graph preparation，而`SceneUtilityLayerRenderer`随后传group target；preparation实际固定的capture输入不会因draw request改变。`SceneUtilityLayerRuntimePlan.swift`的membership又依root可见效果/准入，且空组只close encoder、目标extent仍可能被pool缩小。只有作者确有隔离profile时才修这些group路径；若该profile无依据，应撤销错误路径，不能先把它完善成另一套错误合同。
- 原交接中3226487183的“21/24/32/35”是作者数组位置，非layer ID；2522主组后代在该样本恰好连续，35位置为无效果composition。真实样本只能作回归，不能替代自写交错输入或决定算法。上述行号对应`92258a2d`附近，后续按冻结代码重核。

## owner、候选与裁决顺序

作者格式/descriptor拥有类型、parent和顺序；现役 planner拥有采集时点与读写边；既有target pool/lease和submission coordinator拥有预算、generation、pin及completion；graph executor消费精确准备的source；唯一compositor输出。不得增加独立renderer、resource registry或按sample分派。

先判**采集范围**：建立官方编辑器生成的自写composition，区分下方非child是否进入source、child移到上方是否仍进入source；固定实际作者字段、GUI层序与颜色ROI，再分别变一个因素。随后才判copybackground/passthrough、无effect与identity effect、alpha/transform、采集位置及clip。旧“父slot/末后代slot/flat”实验以parent隔离为前提，只能在成员语义确证后使用。

候选及可证伪结果：

1. **按场景下方采集**：改变一个非child下层颜色会改变composition source，parent变更在不改层序/世界变换时不改变采集内容。沿现capture owner改正顺序/范围并删除无依据subtree分派。
2. **显式隔离组**：必须找到真实作者字段组合/公开设置，并用外部层不进入、组成员实际进入的正反例证明；仅此profile才准入私有target scope。不得仅凭现parent字段推定隔离；若官方GUI/黑盒证实composition类型与parent共同界定成员，记录该组合产生者与反例，不强求另有新mode字段。
3. **模式相关**：若copybackground/passthrough或其他明确作者字段区分两者，在现typed prepared source中表达其合同，不能凭child数量、effect数量或样本身份分派。

这三者目前未定案，不以现状、旧设计或第三方结构选其一。公开说明已足以撤回无条件“非成员不进入组源”的旧断言，但尚不足以直接上线相反的全部组合。

## fallback / route 与资源约束

当前研究不变更产品输出。定案后的普通视觉不支持局部保留安全current；identity、cycle、hazard、预算、epoch/generation漂移拒绝最小unsafe unit。不能用更大范围的主帧采样掩盖缺失source identity，也不能把未知语义升级为永久special-case fallback。

若需要capture/隔离target，其extent、颜色域、透明clear、resize及in-flight预算由既有owner统一裁决；不能静默缩放后当exact viewport，不得将encode成功当完成。失败时保留已经存在的安全父输出不等于新增“上一帧组图像”history；没有明确作者history就不增加组历史缓存。具体extent/clip与alpha施加位置随行为profile批准，旧父viewport建议不自动成为所有composition的规范。

## 纠正门

研究卡先固定官方客户端version/hash、OS/backend、viewport/scale/颜色状态、自有输入hash、候选ROI及容差。公开与固定黑盒只交中性行为结果；不读取或转写私有算法/资产/反编译。

实施前将已定案profile、真实产生者及备选拒绝理由写回本设计，再翻approved。自有反例必须走真实parser→plan/source→Metal→publication/compositor→next-frame；覆盖parent单变量、非成员颜色、子层自身effect、root无effect/alpha、嵌套或模式切换及相称的clear/resize/completion失败。相同用户结果不因无关child关系改变。实际顺序与source不能只以route字串或非黑判定。每个新增guard都能指名实际产生者，现役错误分派和零消费者入口随修复删除；不扩大普通帧parse/compile/建图。

## 退役条件

行为profile经设计批准，真实正反例、资源生命周期与输出门通过独立终审，稳定架构接管后归档。无依据的旧isolated/subtree路径须明确撤权或由新的已证作者profile接管。单样本启动、target存在或公开RGB一句说明均不足以宣布D1实现完成。
