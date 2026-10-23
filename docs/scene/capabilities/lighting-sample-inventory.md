# Scene 光线与光照样本清单

<!-- document-role: current-state -->

> 复核：2026-10-23；输入基线 `2710b64b1`。
>
> 本页只拥有当前样本的静态分类、去重集合与统计边界；实现能力归[能力台账](coverage-ledger.md)，运行事实归[运行证据](runtime-evidence-current.md)，执行顺序归[现役断点队列](../roadmap/scene-open-breakpoint-queue.md)。

现有 **373** 个样本目录，**372** 个 Scene entry 可解析，**1** 个失败：`3763323436` 缺 `project.json`，保留在总分母并标 `UNKNOWN`。目录身份及全部可解析样本的 project/Scene entry SHA256 与既有 census 缓存一致。

## 分类与去重

统计读取真实 Scene 声明及其引用的 effect/material 元数据；原生灯由 `light` 字段分类，光束 effect 由 `replacementkey` 与引用 shader identity 分类，普通图像 receiver 由 material/instance 合并后的 `LIGHTING=1` 和 builtin identity 分类。不以任意文件名含 `light` 判断，也不把包内未关联材料算作 receiver。实例包含作者隐藏项与动态项。

| 主分类 | 独立样本 | 声明实例 |
|---|---:|---:|
| God Rays | 37 | 67 |
| Light Shafts | 26 | 42 |
| 两种光束 effect 去重 | 59 | 109 |
| 原生灯对象 | 17 | 51 |
| builtin image 受光声明 | 7 | 31 |
| 所读粒子材料的显式 `LIGHTING=1` | 0 | 0 |

God Rays 与 Light Shafts 交叉 **4** 个：`3448877775`、`3566880847`、`3807668787`、`3820312181`；光束与原生灯交叉 **5** 个：`3287715210`、`3437487219`、`3470948192`、`3662790108`、`3768903841`。7 个 image receiver 样本均在灯集合中。因此严格主并集为 **59 + 17 − 5 = 71**，不是各行相加。

| 原生灯 `light` 子类 | 独立样本 | 对象 |
|---|---:|---:|
| `point` | 5 | 10 |
| `lpoint` | 6 | 20 |
| `ldirectional` | 5 | 11 |
| `lspot` | 3 | 9 |
| `ltube` | 1 | 1 |
| 对象总计（样本跨子类重叠） | 17 | 51 |

109 个光束 effect 的静态 `visible / dynamic / hidden` 为 **54 / 29 / 26**；51 个灯对象为 **20 / 13 / 18**。这些状态沿作者回退值与父层传播；动态输入之后可能改变，不能据此声称运行时可见。

| 辅助发光分类 | 独立样本 | 声明实例/全局配置 |
|---|---:|---:|
| 全局 Bloom authored 开关为 `true` | 51 | 51 |
| 独立 Bloom effect | 10 | 16 |
| Edge Glow effect | 1 | 2 |
| `emissivebrightness/emissivecolor` 字段 | 3 | 10 |

主集合再并入这些辅助类后为 **108** 个，其中**仅辅助类 37** 个；辅助各行也不能相加。51 个全局 Bloom `true` 配置中有 4 个 authored strength 为零；emissive 字段存在不证明 map 分量、资源及输出有效。

环境光单列：**370** 个样本具有非零 `ambient/skylight` authored 回退值，3 个有动态输入；与已证 image receiver 的交集为7个。模板全局环境色本身不证明实际受光，不纳入71主集合。若额外把任意非零环境色也算入广义集合，结果为371；仅按 ambient 字段存在则为372，均属不同口径。

## builtin image receiver 分型

上述7个样本的31个受光声明按关联材质的 builtin shader identity 细分如下；`genericimage4` 的 stock 声明含 `LightingV1`，`genericimage2` 使用旧灯接口。这里记录作者输入类别，不以接口名推断实际灯贡献或运行支持。

| 材质 identity | 独立样本 | receiver 声明 | 静态默认开 / 关 |
|---|---:|---:|---:|
| `genericimage2` | 4 | 25 | 6 / 19 |
| `genericimage4` | 3 | 6 | 4 / 2 |
| 合计 | 7 | 31 | 10 / 21 |

“静态默认开/关”只合并字面 `visible`、直接 Bool 用户默认值、字面 combo 相等条件与祖先可见性。它不代表资源就绪、alpha 覆盖、实际投影、遮挡或脚本/Timeline 后的可见像素；31项也不表示同时存在31个可见 receiver。

| 样本 | 材质 identity 与关联层 | 静态默认状态与归因边界 |
|---|---|---|
| `2784267518` | `genericimage2`，Mountain `24` | 雪山开关默认关闭，24静态关；独立 Eye Pulse 层不归此 receiver。 |
| `2815826216` | `genericimage2`，人物 `20` | 20静态开；同包两个 `point`，其中44的强度含脚本，不能将总亮度当固定灯响应。 |
| `2890473419` | `genericimage2`，`124 / 13 / 82` 共用人物材质 | 三层静态开；动态位置、effect 与重叠需另作实际像素归因。 |
| `3708363772` | `genericimage2`，四份反光材质关联20层 | 默认布局与样式选中 `234 / 172`；其余18层经自身或祖先开关静态关。 |
| `3351179520` | `genericimage4`，背景 `98` | 主题 `zt=1` 选中祖先657与98，静态开；同包声明 `lpoint`，材质同时启用 Reflection，不能将背景变化单归直射。 |
| `3437487219` | `genericimage4`，Universe `146 / 135 / 143` | 默认 `milkyway=3` 仅135静态开，146/143关；同包声明 `ldirectional / lspot`，材质另有 emission 与 slot2 mask。Earth/Cloud 的模型受光不属于这三层。 |
| `3662790108` | `genericimage4`，sun-4 `1121`、sun-1 `1336` | 两层无可见性开关，静态开；同包声明 `lpoint`，但动态微小 scale/origin、depth、emission/mask及1121的God Rays使实际投影贡献仍需核实。 |

本细分来自正式包 `builtin-image-light-families-20261023` 内的只读 `builtin-lit-image-tier-matrix.json`，未增删样本或声明，仍保持373/372总分母、71主集合、108含辅助类并集及109外观相关下界。运行修复与边界另见[有界后验](../history/builtin-image-light-families-2026-10-23.md#builtin-image-light-families-20261023)，不能由本静态分型推断实际贡献。

## 完整去重样本 ID

严格主集合 **71** 个，按 ID 升序：

```text
1926190458 1937925563 2784267518 2815826216 2890473419 2949019513
2951452910 2999907577 3028090166 3088601835 3113287126 3248220186
3287715210 3291326967 3292370168 3299228616 3321237804 3337494481
3351179520 3389974179 3396722575 3437487219 3443450456 3446316682
3448877775 3470948192 3471294034 3477054430 3509243656 3549827466
3562021804 3566880847 3581882134 3585542943 3587571382 3589454154
3603711180 3605722997 3616476797 3617056047 3627973226 3662245960
3662790108 3694697894 3695791724 3708363772 3719111841 3723344874
3737432178 3742497499 3747492842 3749463715 3754630802 3761159935
3764725758 3766387484 3768724269 3768903841 3769761761 3770462923
3779026256 3780391264 3781757083 3787382101 3796588443 3797217144
3800356808 3807013762 3807668787 3809541486 3820312181
```

仅辅助类 **37** 个，与上列无交叉；两列合并为108：

```text
1695673397 1994794519 2134765860 2524111047 2684431262 2797913147
2866086594 2902406982 2913492057 2927205881 2960821850 3146507587
3147346398 3219398263 3221354414 3238423642 3323988600 3420215721
3454689854 3472940912 3554161528 3577990983 3585875739 3663810817
3666041758 3750813609 3767343314 3767460992 3768020435 3780119725
3782740481 3788897599 3795384177 3802005866 3806337293 3807151772
3810943704
```

## 未知与执行边界

另有实际复核的**粒子光卡外观**：1315486372顶部52以128×512纹理Sprite形成光线，3769761761含SpriteTrail/static-child光束。131不在上述71/108声明集合内，376已在集合中；把这项已确认外观也纳入时，广义相关样本的**已确认下界为109**，不是穷尽总数。任意自定义/粒子发光用途仍不能由文件名或`LIGHTING=0`排除，后续沿[实际贡献与几何资格](../history/light-particle-qualification-2026-10-23.md#light-particle-qualification-20261023)补证，不据此升级运行支持。

- **MDL receiver UNKNOWN**：12 个样本的256个 `.mdl` 对象尚未通过完整 material-path reader 关联到材料，不能用同包 `LIGHTING` 字段推断受光。12个样本均已在71主集合内，此项待补分类不会新增这些样本身份。
- **Fluid effect UNKNOWN**：`2987771245`、`2999907577`、`3137495261`、`3723344874`、`3749463715` 共11个 `fluidsimulation` effect 不可由普通JSON解码；须沿现有条件/模板解析器补证。其中前述 `2987771245`、`3137495261` 未在71主集合中，不能当作已排除光照。
- **自定义语义 UNKNOWN**：任意 custom shader 的照明/发光含义、prepared variant/host来源、binary model 默认受光、材质map有效性及 live property/Timeline/script结果未在本次闭合；粒子零计数仅指所读关联材料中未见显式 `LIGHTING=1`，不是通用粒子光照缺失结论。
- 样式术语仅沿官方[God Rays（radial/directional）](https://docs.wallpaperengine.io/en/scene/effects/effect/godrays.html)及[Light Shafts（Linear/Radial/Corner、Color/Gradient）](https://docs.wallpaperengine.io/en/scene/effects/effect/lightshafts.html)分类；这些链接不证明本项目已执行同输入官方实验。
- `3321237804` 的光线四点域现况、首帧视频问题及后继验收只由现役队列与运行证据维护。本清单不另立排期，也不把静态声明、family命中或非黑结果换成准备期准入、GPU/桌面可见支持或官方 parity。

## 可复算证据

正式元数据证据包：[lighting-inventory-20261023 manifest](../../../.artifacts/scene-evidence/runs/lighting-inventory-20261023/manifest.json)、[metadata ZIP](../../../.artifacts/scene-evidence/runs/lighting-inventory-20261023/supporting/samples/0/runtime_evidence.zip)。ZIP仅含 `census.json`、`receipt.md`、`metadata_census_scan.py`、`review-census.json`、输入身份摘要与内容清单；完整逐类ID、交叉、定位和所读JSON SHA256保存在census。独审接受这一有界静态清单，包完整性校验通过；transport路径中的 `runtime_evidence` 不表示运行已执行，report明确 `passed=null`。默认保留14天，不含媒体、原包或probe输出，也不是第二份统计权威。

| 文件 | SHA256 |
|---|---|
| `census.json` | `eea6f26ac1f918852f2305ac9cecf6bd121691c6a095cafe440340ec430e6756` |
| `receipt.md` | `95a5ce700beac819ff62ab8a73f929e4b20c982552cb36489a0651863586563c` |
| `review-census.json` | `6f0add28926524fa2f68aa1c7b646843e4e110f9b5ecb6e941f74c42a4d4b467` |
| 正式包 `manifest.json` | `399e5d6b503f51d76fb7d827cef36459a9731b8509facf4d31b3abbeecfd75b1` |

receiver 分型的只读补充矩阵 SHA256 为 `3b6c08e31fcadca5697c5c76719cecc346b28be7911f134c4d13bfc507ff38bc`；它不在上述原始 census ZIP 内，仅补充同7个样本的材质类别与静态默认状态。

仅用只读 `PkgArchive` mmap 与引用JSON补充缓存缺失字段，保留15,051个JSON资源文档的哈希（读取约35MB），未解出媒体/纹理或读取shader正文。包读取前后size/mtime稳定，未整包重算哈希；不把缓存package SHA冒充本轮验证。上述静态统计未构建、运行App/VM或产生构建缓存。
