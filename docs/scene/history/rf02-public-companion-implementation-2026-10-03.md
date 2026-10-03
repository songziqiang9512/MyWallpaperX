<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->
<!-- cutoffDate: 2026-10-03 -->

# RF02 B — 公开纹理 companion 的 typed 帧值

> **历史证据 — 非现役入口**。本记录固定本批实施与执行证据，不产生下一批任务权威。稳定合同见[架构](../architecture/runtime-architecture.md#authored-texture-companion)，能力边界见[Shader 覆盖表](../capabilities/render-graph-shader-coverage.md#op-shader-variables)，选序见[兼容路线](../roadmap/scene-compatibility-roadmap.md#batch-2-后继选序2026-10-02)。

基线为 `cba66f4da38bf8da367e7e5d6243fa146e9c6dc3`；产品与测试身份由下述冻结证据固定，Git 身份以包含本记录的职责提交为准。A 的采样纠正、atlas named 失败半径各自见[前序 A](rf02-authored-sampling-implementation-2026-10-03.md)与[atlas named](rf02-atlas-named-output-implementation-2026-10-03.md)。B 的数值、默认值与所采动画呈现依据[官方观察](rf02-companion-uniform-observations-2026-10-03.md)，不消费私有 shader 或内部实现表达。

## 问题、实现与独审修正

真实 typed publication→HostUniformSchema→Encoder→Program 的修前路径缺少公开 Rotation/Translation producer。保留的 `app-corrected-red` 同输入 signed App 红例在实际 generic 路径报告 `uniform/staticUniformBindingInvalid`，字段为 `g_Texture1Rotation`；该 companion 红例和 wrong-type/default 反例已独审，不能用测试构造 publication 冒充实际 TEX/catalog producer。

10 个 Swift owner 完成三项职责：

| 职责 | 实际 owner（相对 `MyWallpaperX/Core/SteamWorkshopScene/`） |
|---|---|
| 来源随资源帧原子发布 | `Resources/Textures/SceneTextureCandidate.swift`、`SceneMaterialAssetTextureCatalog.swift`、`SceneTextureProviderPublication.swift`；sprite 帧显式标记，普通候选默认 false，atom 比较包含来源 |
| 公开 host 与 reserved 名称失败边界 | `Compilation/Material/SceneResolvedMaterialHostUniformSchema.swift`、`SceneResolvedMaterialProgram.swift`、`SceneResolvedMaterialProgramFinalizer.swift`、`SceneResolvedMaterialProgram+Derivation.swift`、`Rendering/Bindings/SceneResolvedMaterialUniformEncoder.swift` |
| 精确资源身份 | `Compilation/Material/SceneResolvedMaterialProgramIdentity.swift`、`SceneResolvedMaterialProgramIdentity+ExactTexture.swift`；来源进入 exact，不改变 semantic/pipeline 选择 |

值直接来自当前 selected candidate 的既有帧变换；没有复制六个值、改 reader、放开非轴/多 image，或新增 clock/registry/compositor。独审发现错误类型或无 active sampler 的准确 companion 名称能在 host resolve 返回 nil 后由 authored/default 静态来源绕过。修正由 schema 统一识别 reserved 名称，Finalizer 在普通 fallback 前拒绝，Program source identity 再沿同一权威拒绝。该修正已独审 ACCEPT。

数组需区分拒绝层级：真实 `vec4[1]`/`vec2[1]` 源码在 bounded frontend 及实际 App generic preparation 的 frontend/normalization 阶段以 unsupported array shape 拒绝，未形成 Program consumer。现有 schema 数组反例保留；真实声明的 Program 静态来源正反对（构造 static binding）只覆盖 R/T wrong-type 与 inactive sampler；authored/default preparation 由 App 门覆盖，不把字段篡改或前端拒绝升级为数组 Program 验收。

## 本批执行事实

所有数字仅属于下列冻结输入、代码和产品。native/generic 的 119 是 companion GPU observations；A 的 11 项既有坐标 fixture 另行保留。自有 numeric probes 使用既有 preserved-channel attachment，实际 color effect/compositor 由 App 门验证。

| 门 | 已证结果与上限 |
|---|---|
| bounded `native-final-v4` | 3 tests OK，30.967 秒；119/119 companion command completion；原 A fixture、slot 0/1/7、vertex/fragment、值输出/一次显式采样、mapped 差分、non-sprite identity/padding 及 next generation。编译/执行输入 hash 前后相同 |
| actual generic compiler `generic-final-v2` | 3 tests OK；36 个真实 compiler artifacts，119/119 companion completion；sameInputs。工件集合含 A、数值 fixture 与真实声明的 Program 静态来源正反对（构造 static binding），未伪造 MSL/反射事实 |
| signed App cold | 12 profiles 首轮 11 pass；array 的唯一失败为旧测试将实际 frontend 拒绝误期望成 uniform 绑定阶段，原测量与健康 peer/named 输出仍保存。修正断言后不追改产品，不写成 cold 12/12 全通过 |
| signed App warm | 6 tests OK，93.276 秒；包括 array 正确的 frontend 局部降级、companion/default 拒绝及真实 sprite/named 后续帧。各输入 preregistration/project/pkg 与完整 measurements 均与 cold 相同。warm 前后 38 个 cache 文件全部 hash+mtime 不变，无新增 |
| 基线旧工件复用 | 新 App 使用 pre-fix 的 23 个真实 cache 文件，2 tests OK；原 23 个 hash+mtime 不变，另新增 1 个所需工件。证明 B 可复用合法旧编译解释，不能声称没有任何新编译 |
| 最近 focused owner 门 | 7/7 通过，合计 360.6 秒：catalog、visual failure、registry、graph publication、persistent cache、Program derivation、Finalizer；最终 14 个产品/测试 execution-freeze 文件身份仍一致 |
| 独立执行审查 | ACCEPT；两 backend 各 119 GPU observations。App cold 12、warm 6、旧缓存 2 共 42 PNG，独算 848 quadrants / 29,874,474 ROI 像素，固定 palette 100% 命中；不代表全窗口/全 corpus 或官方视觉 parity |

native 结果/identity SHA-256 分别为 `a0b1d05afa8b03580c5b3dfdb858f69bd31943eecbebeb866402808e84e81378` / `1cfb828f0ee40276bee18125532c5624a6e092468786acecefb9e2f2b296769a`；generic 分别为 `1953a9e971a2b5a699e1be91e6e8414e5d1a5770afaf5b43e70120d72c9d275b` / `308b26f4aa45988669a2d281e635b6f63b13fe104052468c9742b049c2cddfdc`。原执行根为 `/private/tmp/mwx-scene-next-build/`；二进制不是长期证据包内容。

官方补证的 450 张实验快照（90 supplement、360 animation）与原协议/控制身份已全部独审 ACCEPT。保留包为 `.artifacts/scene-evidence/runs/rf02-companion-observations-20261003`；包内另有共享基准图，不能把实验快照数误当整个目录 PNG 数。官方原图只支持量化盒与所采同屏一致性；产品选择盒内明确值，内部精确更新相位、所有 provider 默认值、不同尺寸来源与多 image 支持仍不外推。

<a id="knowledge-handoff"></a>

## 知识移交与收尾

A+B 的稳定职责已合并到架构，原[设计入口](../roadmap/batch2/authored-texture-coordinate-design.md)只作永久锚点导航，完整设计正文及来源保存在[归档](rf02-authored-texture-coordinate-design-2026-10-03.md)。本次退役对应临时设计 gate；未公开 8…12/MipMapInfo 仍为 unknown，若出现具体合法需求须另行设计。document-health 的预算、归档 hash 与角色迁移以本节为精确 adjustment 决策依据，不通过放宽无关基线过门。

产品执行证据保留于 `.artifacts/scene-evidence/runs/rf02-public-companion-implementation-20261003`：384 个保留文件的 SHA/size 已逐一核对；`manifest.json` SHA 为 `c7d1886c7a15240cd812aff085dfcae0063363a577e711dde9adfb87965aa2ce`，`product/report.json` SHA 为 `2d0e26b67708781247c61b4b40eba78a7c3c28772ad28c52432b663f031c7f09`。report 将原相对路径映射到保留文件，数字 entry ID 仅是运输标识，不是 Workshop 身份。执行冻结 `execution-freeze.json` SHA 为 `7f28b0ac24f70173a68c6ce8272c1de964e517955222646bc45fdbb4cb1bab6b`，覆盖 10 个产品文件和 4 个运行测试；签名 App 的 23 个 binary 与 10 个源码 hash 均复核相同。主程序 SHA 为 `1b221117fef62f19323deb8efbe7ed0be666ee6fe9adfec6514abd50c950af93`，Debug dylib 为 `32d90e1daae53c69bde823397c7e17696c9edc6f0c37b3230a815f9945007c91`；身份文件同包保留，等级仅为 Developer ID signed staged Debug，不是发布验收。

产品执行与文档职责独审均 ACCEPT，无未解决 P1/P2。Debug build、上表实际运行、Scene 结构/依赖/防御/代码健康、测试断言/产物/design gate、四组文档与治理回归通过；文档 audit 为 145/145、17/17 routed contracts，health 为 54 authorities、4 archives，6 项精确调整。文档迁移另修正历史权威索引遗漏和仍要求已退役 active-plan 的路由测试，未改产品验证输入。真实 Program 构造静态来源、实际 App default 准备路径、数组 frontend 拒绝三者分别记证，不外推官方精确值或全 profile parity。

官方包的 1111 个保留文件 SHA 已核对。官方原实验目录、被替代重试、两份 staged App、最终临时运行副本与运行 shader cache 已在提取并验 SHA 后清理，共约 590 MiB；必要证据按工具登记期限保留。连续开发只保留一份 `/private/tmp/mwx-scene-next-build/cache` 构建缓存供 RF04，另留少量当前任务收尾元数据；未知旧 `/private/tmp/mwx-rf02` 未动。已执行工具登记包的到期清理，本次无到期包；不触碰未登记、哈希漂移或运行中的材料。按用户授权随本职责批提交，未推送。

后继固定 RF04→D1：RF04 首先证合法 hidden/default mip consumer 的 source/read phase，不复制已有 F5 环境快照 owner；D1 随后补有可见 effect 正控制的成员/flag 差分。后续方向由兼容路线裁决，本历史记录不维持第二任务队列。
