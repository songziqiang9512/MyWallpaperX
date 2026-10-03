<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# D3 PBR贴图输入中性合同增量（2026-10-02）

> **历史证据 — 非现役入口**。这是[原PBR输入合同](d3-pbr-input-neutral-contract-2026-10-02.md)之后的v6/v7增量，仅归档经独立隔离审查的输入事实。实现裁决由[D3设计](../roadmap/batch2/2d-lighting-material-design.md)拥有，后继由[RF10卡](../roadmap/batch2/reference-evidence-implementation-cards.md#rf10-pbr-direct)拥有。本文不批准产品、不提供官方算法或像素golden。

## 身份与隔离

研究者永久research-only；root、实现者与审查者未接收原始静态表达。v6只读固定2个stage的8个输入选择窗口，未读include或BRDF；v7只核固定第三方公共采样helper的一行输入绑定。没有操作VM、构建产品或新增corpus；原始代码、函数体、公式、payload及观察JSON不进入本文。

固定官方客户端2.8.42，wallpaper32.exe SHA `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`。以下stage路径相对合法本机客户端的assets/shaders；路径/行号只定位证据，不引用源码。

| 输入身份 | 文件SHA-256 |
|---|---|
| genericimage2.frag | `1e252e2271cae57fcfdecf3bd79d1685bb726e1e8afe09ba863dca2e1b12d68e` |
| genericimage4.frag | `6b5344953054ae853ff8a7942f716dd9eb67f61cc1526bd8b6bc67df92c76e1f` |

本机审查包位于 `/private/tmp/mwx-rf10-pbr/`。v6中性包SHA `09ba8a3a61e8d0277c9681e9c2b8e0ba266c8565a68e2356f7372af984592de4`，完成卡经两处旧拟议字段纠正后SHA `c8d39d5decca061f41743f3cc9e634c65e0d093a9257c743ce3c21ca682aec3c`；v7中性包SHA `1192938f70c4320cb229583f7a8ea1a15355eb299871e90d1669b41ce197608e`，完成卡SHA `5df921414741c4a335c4eff2e641962dadf1365e3d945de8ecc6c40452674eef`。各自独立neutral审查ACCEPT；审查对象是中性输出及证据上限，不是重新读取原始实现。

## 三种不同的输入事实

**official-client-static-observation。** v6确认固定stage中slot2采样结果的逻辑分量。不是原始文件字节排序，也未研究数值shading。

| 作者component | 逻辑sample分量 | generic2 / generic4位置 | 输入作用类别 |
|---|---|---|---|
| Metallic / METALLIC_MAP | R | 84 / 104 | 替代对应metallic标量输入 |
| Roughness / ROUGHNESS_MAP | G | 88 / 108 | 替代对应roughness标量输入 |
| Reflection / REFLECTION_MAP | B | 128 / 158 | 对reflectivity输入作权重，未恢复数值处理 |
| Emissive / EMISSIVE_MAP | A | 152 / 189 | map、作者color和brightness共同参与；精确模式unknown |

**third-party-reference-pattern。** v7核对Mirage固定revision `da4fa7b3ee33e9e94c59307f47098aa521f21aa6` 的 `SceneRenderer/Sources/SceneRenderer/Wallpaper/Compiler/MaterialShaderCompiler.cpp:273`，文件SHA `278301ca9fc4c81fbab3f85ab733b9c40d88641ecbbb4834ef2b79d390440f89`：该公共采样绑定保持返回资源采样结果的分量，没有本地重排或额外decode。只证明该第三方backend局部绑定，不能证明官方native backend、所有格式的前置解码或色彩转换。

**既有presence链。** v3已核header compo1..4经component-enabled index0..3对应Metallic/Roughness/Reflection/Emissive声明，精确owner/hash在原合同。这决定分量是否存在，与上表采样哪个分量以及资源是否可用分别处理。非空slot2不能推出四分量全开；map值为0也不能推出分量缺省。三个LIGHTING=1的已知作者TEX只有Emissive presence，不能因slot2存在而把未声明的MR分量当成有效贴图输入覆盖标量/default。

## 推论、未决项与实现边界

上述输入链足以支持项目为已知格式定义独立采样与材质算法，须用自身解码、逐通道fixture验证。不得说已证明所有物理格式、私有公式或官方视觉parity。环境反射需要独立资源合同，场景前缀背景不能自动充当环境贴图。

固定第三方schema中同键instance combo优先于material，非空instance同槽覆盖、空槽继承；但下列编译优先级仍未证明：effective显式component combo与header自动presence的最终优先级、整体PBRMASKS=0与非空slot2的冲突、headerless普通PNG上显式combo能否单独启用。无header不能自行全启用。完整LIGHTING/REFLECTION gate及emissive精确数值模式仍unknown。

设计可为这些精确冲突定义保守的项目策略并记录局部fallback；明确的有header、无冲突静态输入应继续落地，不因未知分支冻结全部能力。自有emissive算法无需恢复官方公式，但须区分作者颜色/强度、灯光依赖、覆盖与HDR行为；不得将独立方法写成官方合同。

官方单通道GUI黑盒本轮not-run，未取得官方map黄金图。后续真实样本只能据实际执行身份、资源与逐帧输出声明项目收益，不能由本静态合同声称兼容完成。
