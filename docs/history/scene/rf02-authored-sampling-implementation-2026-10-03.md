<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->
<!-- cutoffDate: 2026-10-03 -->
<!-- uniqueValue: RF02 A 作者采样坐标修正的冻结产品、native RED/GREEN、真实App有限ROI及未闭合边界；最终审批仅限本批冻结。 -->

# RF02 A：作者采样坐标修正（2026-10-03）

> **历史证据 — 非现役入口**。设计基线 `3360a787688f16e58a2c255fb4dbf11720f906bf`；最终批次独立审批 **ACCEPT（仅RF02 A）**。证据根 `/private/tmp/mwx-rf02/`，下列工件路径相对该根。本文集中保存本批执行结果与失败现场；现役卡只链接本文，当前方向仍由[RF02卡](../../scene/design/reference-evidence-implementation-cards.md#rf02-companion)与[兼容路线](../../scene/scene-compatibility-roadmap.md)裁决，稳定职责见[架构](../../scene/design/runtime-architecture.md)。

## 实际改动与边界

旧产品在每次二维采样外再套 candidate affine 变换，即使作者已给出固定或显式映射后的坐标也会再映射。本批 A 让 bounded emitter 与真实 generic compiler 保留作者坐标，保留已支持的 sampler、显式 LOD、坐标类型转换、结果通道与颜色边界。synthetic texture-transform uniform ABI、host 编码/校验、same-slot compensation analyzer/facts 及其 Program/variant/finalizer/诊断消费者一并退休，不以识别某种作者表达式决定是否补偿。

原 baseimage compositor frame 映射与 effect terminal identity 职责不改；Candidate/Loader/reader 的非轴准入、资源尺寸和动画相位不扩张。真实 Resolution-only dependency、一般 type/stage/slot/range/hash/target hazard 与 publication/generation 门保留。B 的公开 Rotation/Translation producer、companion 尺寸与相位仍 **blocked**，不能从 A 的像素正确或 uniform 名称推断 B 已实现。

产品冻结 `implementation-a/product-review-v1/freeze.json` 共26路径：23个存在文件、3个删除；SHA `0719e884789034da3391229014dfb02ea8e5584ba51645b7261efa982a9463c9`。精确 diff SHA `71df6c289b0158cec1668d3cffed20917424576411522a768473e62aa8e5362e`。静态独审 `implementation-a/product-review-v1/review.md` SHA `8faff13086e3c05e10e31a472719aed6e251dfce0b5985696a3942f5f0e23041` 无新增 finding，但明确只覆盖产品冻结，**尚非完整批次批准**。

删除3个产品源与 compensation-only 测试，更新 canonical source sets/选择器；冻结产品 diff 增42行、删1152行。shape-analyzer 库存58→57，与其余65项合计123→122；duplicate-body ratchet 127→123。保留 foreign inventory 改动，不新增 matcher、registry、compositor 或普通帧分析入口。

缓存随实际读写 owner 失效：bounded frontend key9→10、shared frontend schema39→40、VariantAnalysis9→10、GenericShaderAnalysis3→4、request key v14→v15、artifact schema7→8、默认 Programs目录v10→v11；Python镜像同批同步。Preparation目录schema1及导出Envelope schema5不变：前者的key/有效性检查绑定frontend40，后者不是artifact/key的失效版本。override根仍用v15 key且decoder要求schema8，不能只靠默认目录换名。

## 修前 RED 与修后 native GREEN

修前 `native-sampling-counterexample-v2/` 在 `07d45f4a` 上真实执行 bounded frontend→uniform encoder→Program→PassEncoder→Apple M4。自编384×192 atlas、活动slot1、固定float32点，identity/axis/identity三次均完成；实际A `(30,86,144,255)`→B `(44,44,88,255)`→A，而作者原样坐标目标应始终A。axis目标为 **RED**；运行exit0不能改写目标失败。publication由harness构造，未执行generic、真实asset/provider或App terminal。

v2 report SHA `ff9ba219c347a2d599db8354af920e9f07135870f159c5948d537f2eaa46170d`；独立delta审查与冻结binary重放 **ACCEPT该有界反例**，review SHA `ee57539a25bed84a861a7ab2485308eaeb437170bb7359af0f5339c1859354b0`。169输入与11冻结项重放前后未变，result SHA `310bcd4d72267712f90b8cae2a10735d317845183a655a0b57948f6ca60e9105`。v1最初 SUPPORT 缺产品已有 `.sceneEnvironment` 的编译失败，以及v2仅把无效slot0尺寸字典改slot1/订正报告措辞的历史均保留。

修后 `implementation-a-gpu-run-3/` 两模块均通过，不是skip。11个自编fixture×3 generation×2 backend，共 **66次真实GPU completed/无error读回**，每次检查完整2×2 RGBA。bounded使用实际frontend/Program；generic调用真实Swift `SceneGenericShaderCompiler.compile`，由产品签名resolver/probe运行glslang/SPIRV-Cross，发布11个artifact，经Swift decoder/`makeProgram`→`assembleCompiled`→PassEncoder上GPU；旧手写MSL generic替代路径退休。签名只作用于临时bundle helper副本，repo helper不改。

| 主输入（slot1、384×192、nearest/clamp） | generation1 identity | generation2 axis metadata | generation3 identity，新texture R+7 |
| --- | --- | --- | --- |
| literal/raw | `(30,86,144,255)` | `(30,86,144,255)` | `(37,86,144,255)` |
| 作者显式F一次 | `(44,44,88,255)` | `(44,44,88,255)` | `(51,44,88,255)` |
| 同shader混用raw与F | `(30,44,88,255)` | `(30,44,88,255)` | `(37,44,88,255)` |
| 显式LOD1 | `(77,123,201,255)` | `(77,123,201,255)` | `(84,123,201,255)` |

另覆盖原样varying、vertex/helper显式坐标、两种显式LOD API的level0/1、slot0/7。第三帧替换真实texture并更新resource/content generation，exact identity变化，新颜色实到GPU；pipeline attempt稳定仅是正确性观察，不是性能证明。bounded122、generic183实际编译输入前后相同。GPU freeze SHA `95418efb9d3f7390267d4633ad59ca7b14a3cfe41a028c432a3120b69156e55e`；bounded/generic result SHA分别 `08ad876b6b7fedffea5a66119f03346b9f7336acce7372e86083402efe2721c3`、`adaa920e90819b66a6a85b58a1eb744f9a5fcecd1e4d7d8b873d892e17ed4956`。源、binary、命令、signed bundle、artifact和日志均留档，可重放。

两次失败不能隐去：`implementation-a-gpu-run-1/bounded/` 的helper返回采样颜色在frontend编译后未获现役Program准入；改为helper返回vec2、main采样。`run-2/bounded/` 的直接vec4 LOD输出亦未获准入；最终采用等价opaque `vec4(sample.rgb,1.0)`，所有自产mip alpha原本255，RGB/坐标/LOD预期不变。这两项没有旧HEAD动态复现，不能称已证旧缺陷。shared SUPPORT补 `.sceneEnvironment`，pass fixture旧synthetic identity编码分支也删除；旧mandatory synthetic ABI/源码包装断言由实际像素门替代。

## 完整 App 的有限链路证据

隔离Debug App `implementation-a/source-v1.app` 执行自编pkg，覆盖axis atlas与padding baseimage、显式颜色置换effect及named slot1 consumer。v1把consumer依赖设为axis atlas effect层12，实际拒绝 `layer-31-dependency-input-invalid-image-provider-invalid`；没有completed事件，measurements为空。现场 `app-integration-v1/test_axis_padding_effect_and_named_consumer/` 保留。这个修后App现场不是旧HEAD动态反例，也没有修复atlas named准入或其失败半径。

v2仅将consumer引用/依赖12→22，使用真实padding effect provider；shader、canvas、panel/ROI、颜色预期、容差和时域限制不改，preregistration除input hashes外逐字段相同。实际base加载→source capture映射一次→作者effect→layer22 graph-output publication→layer31 named绑定/采样→terminal输出，完成后续帧并drain。两capture为ready/after，各检查 **20个事前内缩象限ROI**，correct fraction均1.0（门为≥.99、每channel容差3），并检查每panel四个外部点；不等于整幅像素或整条边通过。

截图由terminal encode后的同command buffer completed才导出，但ready/after未严格绑定相邻frame索引，输入为静态单帧；这不能证明动画相位或B companion publication。host先capture的局部texture也不能代替native直接采样非identity candidate。summary SHA `4d0a69dc90d33393cefccbc1e1fba2e78b71c5cf564a552c5a08ee98281203ee`；test source SHA `53db014b6c67a404efb8d8be621b7711698f7019acf4785c57a17b15ffbddfc6`、事前protocol SHA `d1fa795be988b6efafb9e1dac3f02be6140cf1836e9f5f33bc78e2929feda1be`。App executable/debug dylib/metallib与两helpers的5项运行后hash均匹配summary。

## 构建、回归与保留日志

`implementation-a/build-v1/build.log` 为Debug **BUILD SUCCEEDED**，receipt exit0/productsUnchanged=true；26路径source-before/after完全一致，App签名验证valid/satisfies designated requirement。receipt SHA `31c27e5a8faccce0eab03831b12201607d6eef080c553f7e5d095fb6a46728ef`。构建与静态门不能替代采样或App证据。

下表记录主目录截至写入时的实际日志，不累加聚焦重跑的唯一方法数，不称全库绿色：

| `implementation-a/` 日志 | 结果与后继 |
| --- | --- |
| `generic-artifact-tests-v1.log` / `v2.log` / `v3.log` | setup ERROR→1 FAIL→82方法OK；前两现场保留 |
| `offline-layout-tests-v1.log` / `v2.log` | 4 FAIL→迁移/退休旧ABI预期后28方法OK；离线Python不是产品generic GPU证据 |
| `finalizer-cache-tests-v1.log` / `v2.log` / `cache-tests-v3.log` | 初次finalizer setup ERROR及3个cache subtest FAIL；v2 finalizer33方法通过但cache仍3 FAIL；cache v3的1方法OK |
| `source-sets-v1.log` / `v2.log` | 旧集合/数量2 FAIL→退休清单同步后11方法OK |
| `pass-encoder-tests-v1.log` / `v2.log` | 1 FAIL→shared SUPPORT与旧synthetic编码分支同步后1方法OK |
| `frontend-derivation-tests-v1.log` | 83方法，1 FAIL/1 skip（隔离3141421197 shader fixture不可用）；derivation失败随后闭合，skip仍未验证，不能覆盖为全部通过 |
| `derivation-compositing-tests-v2.log` / `derivation-signal-final.log` | v2的3方法中derivation因退役HostUniform分支残留1 FAIL，另两个compositing通过；清掉该分支、旧48byte内部ABI期待并补SUPPORT后，最终真实derivation与signal GPU两方法OK（82.907s） |
| `signal-gpu-tests-v1.log` | 1方法FAIL现场保留；后继真实fixture使用者由`derivation-signal-final.log`实际通过，不以其他compositing模块代替 |
| `code-health-v1.log` | PASS，1053 Swift文件、239 warnings；不是零警告 |
| `scene-defense-v1.log` / `v2.log` | v1要求把duplicate groups127→123收缩锁入baseline而FAIL；下降后v2 holds，未上调防御预算 |
| `governance-final.log` / `document-role-final-v2.log` / `document-links-final-v2.log` | 原20方法4 FAIL：退役源造成5条旧链接失效、历史索引authority集合不一致、两项inventory门。链接与索引已修，13项角色门及单项全库链接门重跑通过；以同一扫描器隔离重算HEAD与当前：derived均66/预算65、dependency均6/预算5，命中path/line逐项一致、delta=0（`ratchet-head-probe/result.json`）。这是基线已存在的库存超额，本批未提高预算；全结构门仍未通过，需独立纠偏 |
| `design-gate-v2.log` | 所选变更设计门通过，B仍blocked；自动生成的51模块计划未全量执行，采用本表及实际GPU/App的风险定向门 |

额外缓存门以受控fixture把上一版schema7放在新v15 key同目录，要求真实读取拒绝，再对schema8接受；它不是历史旧版本产出的真工件。首次误用系统Python3.9因annotation不兼容失败，改用Homebrew Python3.14后 `cache-previous-artifact-v2.log` 的该方法通过（60.106s）；这是独立执行的补门，不借用前述82方法的结果。

## 审批与下一批

**最终独立审批：ACCEPT，限 RF02 A 冻结批次。** `implementation-a/full-review-v3/owned.diff` SHA `b59c5c2da033b656c244b75f9faf6da5417c1822e1b94412fd8d8ec77844623f` 覆盖60路径；独立报告 `implementation-a/full-review-v3/review.md` SHA `0b667bb604b39bd1e3103e581e9ea44b8d9f9c829d01464e1a7e1c8f6b589a0f` 核对产品、工具、测试、实际GPU/App、缓存、文档与预算收缩。738份归档文件逐项匹配基线Git blob，HEAD/current扫描输入与两项库存命中独立复核增量为零；两库存门仍FAIL。审批允许随后仅机械删除A登记并记录本裁决，B登记保持blocked，含B的设计文档继续有效。不得把本次接受外推atlas named、公开companion或全结构门完成。

下一批先处理axis atlas named输出的真实准入与失败半径，辨明普通视觉未准入与unsafe identity错误的owner，补健康peer/previous-current/重载的相称证据，再推进B companion尺寸、相位及公开R/T的可区分取证。当前不放宽非轴profile，不据名称猜分母/单位，不以padding v2代替atlas named问题关闭。

本批不证明官方parity、全profile/任意shader支持、动画相位或性能完成。历史报告写入未操作VM/UI/真实样本、未读取私有shader或参考项目原始实现；按单一RF02 A职责提交，不推送；并行库存排序不入提交。三份受保护权威未改，后续由其owner引用本记录。
