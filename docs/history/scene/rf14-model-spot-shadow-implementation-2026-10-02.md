<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF14：真实模型聚光阴影（2026-10-02）

> **历史证据 — 非现役入口**。 本片已获独立产品终审 **ACCEPT RF14 coherent v1**。设计前置提交 `8a4db9b7`，同职责投影数据抽取补充 `0adc0ec4`。本机证据根 `/private/tmp/mwx-rf14/`。

## 实际结果与职责

现总四灯准入内全部显式 cast-on spot，可对主链已经准备的真实静态及 source-only named 模型三角形成遮挡。原第一 cast-on directional 优先，其后 spot 按作者顺序；最多四张图，不新增灯、图资源或 compositor 权威。每张图只调制对应灯的 direct，保其它灯、ambient、emission、alpha 和原显示输出。point 全向及其它 directional 仍属后继。

spot 的严格投影开关沿原 SceneShadowCastIntent；typed light snapshot 携带当前身份、意图与锥域参数。原 mandatory 与 RF13 作者序准备只执行一次，原模型主颜色仍一次消费。现 pool 用有界候选槽复用，失败不压缩槽号；成功资源立即 pin 到同提交 completion，某灯失败保其 direct 和其它成功灯。原单图 record/ABI 完整替换为统一 typed 记录与固定四槽 ABI，投影数据从原 Pipeline 移至同职责文件，没有兼容 wrapper 或新 atlas manager。

## 旧反例与独立方法

原 RF13 不可变 App 的四组自有合法 MDL 输入中，cast-on/off/no-caster 两接收 ROI 均62，light-off为9；灯光实际贡献53，而 cast switch 整图完全相同。目标至少变暗20的预注册门为红。独立灯射线与三角确定遮挡和健康位置，主相机射线不经过 caster。旧协议 SHA `3ecb04a512c3b6e854631939b780bf4f30d055c19e8f9b3bdd370a7674b9d8e9`；目录 `baseline-omag2q3t`。

参考资料只提供作者行为、输入和生命周期依据。有限锥投影、几何面深度及接收滤波由本项目独立实现，未复制参考代码或私有公式。最初公开 API 微证直接采用光栅插值轴深度，三个非对齐输入超过原2e-6门；同输入改用实际三角面与 fragment 采样灯射线交点后通过。原红与对齐坐标正控保留，未放宽阈值或增大 bias。实际产品另外使用真实 PSO/backcull、14个输入验证，最大误差约9.62e-8；含非退化双负w、窄宽锥96extent及反面全clear。

严格布尔旧探针证明数字1/0会被原spot宽松桥接为Bool；修复复用已有严格判据。探针字符串转义编译失败、depth壳首轮统一反转winding错误和half输入.5001量化为.5，均属测试基础设施/输入问题，保留现场，不计作三个新产品缺陷。half阈值门改用原存储可精确表示的相邻值；产品coverage阈值未改。

## 冻结身份与运行范围

十产品清单 `implementation/checkpoint-v1-products.json` SHA `33ea91f58bb2318cecaad4a7f8e224f6d5a9dd22e385dcd4c975c02522db9ec8`，diff SHA `9e3f1d0d83cec2bb145a96e7612a1e867e9e654eba7b4b1a59e3082fc436d6c2`。完整 Debug 构建通过，前后十产品身份相同；本机签名 App `source-v1.app` 的五文件身份见 `build-v1/identity.json`，dylib SHA `478eda74b7b45f4acc924f6d10e6c6227a1367158e5d1f345121d5180efa206b`。deep strict 与两个 helper Team requirement 通过，不是公证或发布验收。

`app-v1-e10jqd5y` 原四输入逐字节重用：新 cast-on shadow9/healthy62/caster绿118，off为62/62，no-caster62/62，light-off9/9。ready/after整图相同，后三组与旧App各自整图相同。五App文件、输入和运行源身份一致；frame1/2、shadow写入/接收/completion及安全drain成立。独立审查重算PNG接受这段有限证据，协议SHA `70b14d1f2643efd1ab055496c534f5cd13f851caf0ff5ffbd9e58547904e7560`。独立体积光路径的 spot-light failed 诊断不代表模型直射失败，direct正控与阴影变化区分两条消费路径。

`mixed-app-v1-e8ybx5sa` 另5次App执行：四spot与directional+三spot分别on/off，四个独立遮挡ROI只减少对应颜色通道，健康区与其它通道exact；前者选中通道分别减少23、56、42.33、14，后者第一方向光减少66，其余相同。四个当前light身份都有完成事件，off不生成map。动态spot位置80→100→80时两接收ROI由9/65换为65/9再恢复，健康区始终48；两张中间快照证实换位，ready/after整图exact。五App文件、执行源和输入预冻结，协议SHA `c5ee74735a29bb34759d6f322c05aa8e1c0f3704a784179dea673e84e08e86e2`。合计9次新App输入执行，不称单次全量套件。

多灯数值测试初稿错误地把每个颜色输出视为单次half舍入；实际既有shader包含lighting转换、surface乘法与alpha乘法。独审确认后按原预注册每项两half ULP工程容差及表达式系数传播修订，并保留等效模式逐值相同门。原红保留，未改shader、几何门或单灯容差，也不将工程容差称严格全域误差定理。

新spot十个唯一方法已分组通过：原九个方法覆盖17个深度向量、33个radiance输入、12个多灯输入、8个frame owner输入、3个named组合，另有9项parser取值与实际snapshot。旧邻接36个唯一方法：directional7、FrameOwner3、snapshot7、named11、staticmodel6、spot plan1、spot rendering1；按分组执行，不累计复验次数或把编译失败当方法通过。另一个方法专门验证部分写入后未发布图的生命周期。

最终测试索引 `test-final-v1.json` SHA `a0ff0b1357fac00cac20c1a8b016fbde70e4dee44b6c27c99c8a2f32ce784b8b`，root与独审均核154个显式artifact身份匹配。新模块最终SHA `31c4ea558783faf526468de76062892babf1050a644e220bf77eee2fec3e9315`；实际新一旧六共7测试文件变更，未改的spot rendering另有通过证据。46个唯一方法按索引逐一追到实际通过行。索引初版只有spot plan方法后缀重复，已更正metadata且保留原字节，未改结果或计数。

原frame owner的8输入使用真实pool/native quota，mandatory模型/粒子租约只准备与消费一次；配额仅容0/1/2图时保健康原颜色，directional优先和真实tiny-angle中间失败后的候选槽空洞得到验证。在飞A持4图，reset后B将相机target64改128再取消，A完成后C重新准备4图、真实模型draw及completion成功。图仍固定1024且灯ID未换；这是pool逻辑驻留与提交寿命，不是阴影图resize或Metal对象已析构的证明。terminal closure计数不替代完整Bloom/display容量，邻接原snapshot/named门另验原消费相位。

partial门1方法44.619s：实际CPU RuntimeModelBuilder从作者alpha1e100产出有限Double，按现material转换为不可表示Float，随后在已证明的prepared边界输入实际frame owner。第一caster写出65536个有限非clear深度像素，第二被原guard拒绝，零图发布且pin为1；SharedEvent阻塞中reset保4194304逻辑字节，completion后归零。GPU资源builder未实编，此输入不是端到端加载证明；仍持纹理强引用时，不把逻辑计费归零称物理析构。

named聚光门3输入使用真实ordered/capture/publication与模型GPU consumer，同provider供caster及两个cast=false receiver；这是有准备壳的native证据，不冒称新增named-spot完整App。最终广义协议标签的实际执行边界固定在 `coverage-final-v1.md` SHA `1761a05cd8bca619fbdb647c0138003c28374685118fed996ba19de48377d81f`。实际Pipeline的透视/模型scale与translation已验；本片未新验完整App perspective、作者parent遍历、pending换灯ID、跨queue、多屏或所有feature组合。

code-health通过：1056 Swift、0 locked legacy、8 locked review warnings、240 warnings；scene-defense通过：0 locked dead、18 canonical、3 swallow，保留历史acknowledgement提示；design-gate通过。文档角色13方法通过。未增加结构/防御预算；新投影数据文件仅登记原Rendering.Metal职责。

## 未验范围与后继

不以自有输入宣称官方像素parity、完整原包spot可见收益、性能、所有model格式、普通image/Puppet/particle阴影或全部light atlas。片元写depth可能限制early depth优化，四张1024²图是有界项目质量选择，尚无性能改善结论。

下一主片推进point完整全向域与接缝，通过原typed灯/几何/pool/提交及唯一输出链实现，不用单面图冒充全向。参考方法缺失由独立算法和实验补足；确需外部语义的部分先定行为规格，不把未知扩大为整项跳过。


## 终审与移交

独立报告 `product-final-review-v1.md` SHA `12f2c0d23b6f1cc36a2e983a3e1f9e11ec8b26f210eeac139865a269769b3e17` 接受上述10产品、7变更测试与最终索引，无未关闭产品finding；其重算17depth最大误差约9.62e-8，33radiance均匹配对应A/Full控制，多灯最大误差仅为原工程传播界约0.273，等效权重模式逐值相同。稳定职责移交[架构](../../scene/design/runtime-architecture.md)，[本批设计](rf14-model-spot-shadow-design-2026-10-02.md)归档并删除窄gate；[RF15工作卡](../../scene/design/reference-evidence-implementation-cards.md#rf15-model-point-shadow)承接下一设计与实施。按职责窄提交，不包含并行layout排序或census索引改动；未推送。GPU/App执行结束，原失败现场和精确证据根保留本机。
