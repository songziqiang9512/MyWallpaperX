# 仓库改良完成记录 · 2026-10-03

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

同页历史分节：[任务路由频率取样依据](#task-route-frequency)。

本记录关闭原提案18项及M1–M8的仓库治理实施范围。长期操作由[仓库开发工作流](../../development/repository-workflow.md)接管，源码职责与剩余边界查[仓库地图](../../architecture/repository-map.md)，已完成治理设计见[同页归档](#structural-governance)，[旧入口](../../development/structural-governance-design.md)只保留历史身份。以下命令、状态与“下一步”仅描述归档时点，不产生现役任务权威。

历史验收（2026-10-03，非当前HEAD复验）：基线 `6105ffe5648330ee758a9ebb1e54d2f2edcd4309`，122个选择模块首轮119通过，3个修复模块合并38项通过（19.027秒），另13个后续门通过，冷Debug构建63.636秒。隔离App只重签 `spirv-cross`、`glslang` 两个compiler helper为Team `H9QWU9XN8R`，产品可执行文件、Debug dylib和metallib保持不变；原六个fixture于99.149秒6/6通过，各场景published=2、signatureInvalid=0、gpuDrained=true，覆盖atlas/padding/named、更新帧、raw-miss局部失败、resize、双consumer及退出。原App已清理；以下SHA256内联保留执行身份，不以临时目录存在作为结论依据。这是有界运行证据，不是整App Developer ID签名、全corpus、官方parity或发布验收。

| 历史工件 | SHA256 |
|---|---|
| `Contents/MacOS/MyWallpaperX` | `4eceed7901cf20186a2ad822cda506362614a6721aca84665e01221ec743aa11` |
| `Contents/MacOS/MyWallpaperX.debug.dylib` | `68cf241fba2d9684ff965afc78d1fa133467832ad0d0f724796c0d96de02a7bb` |
| `Contents/Resources/default.metallib` | `2f53d0a8ab2e46a8ca6d383cc6d3409398bf42aa94ac252e5e77c95ad5970e18` |
| `Contents/Helpers/spirv-cross` | `507b3117a4b6e64802a10471cd73470d5d6b763db88b3e5ee52bbdec79f63791` |
| `Contents/Helpers/glslang` | `ebcc85c5561a19fb5ec8ade220d5decb213e94c097f5f2342c17099d55ce2bc8` |
| 六场景测试源码 | `8c59df92dc1b2414abefcee81b10ee456b5823cbbe50aa22187d736081923fdf` |

下方完整保留关闭前路线正文，唯一转换是相对链接随归档路径调整。正文中的未来式关闭条件和provenance待审表述属于当时路线；其人工分层复核结果已记在同一正文末段，不代表另有未闭批次。旧入口全部锚点永久转接。


<a id="governance-closeout-corrections"></a>

## 本轮治理收口更正

原18项完成指基础治理工具和列明示范，不代表所有细项或存量债务清零。P1-1要求的超长单行仍未彻底收口，能力台账仍有单行承载多段叙事；本批优先纠正审查发现的治理缺陷，未借此改写能力事实。400行拆分、逐文件测试配额及每批全仓receipt已由当前工作流撤销；50条依赖todo、源码形状断言和能力缺口仍由各原权威管理。日期派生队列改用稳定路径；冻结运行归档只迁移四处队列链接路径，保留原锚点和全部其他字节。此处是该机械迁移的决策依据。冻结payload的SHA256由 `312f5b315e0969a2209b10f0773eef48bebc4e21173c01d61951757001afb9f1` 变为 `a4df7a139deaf75c8bfcbaa52977334e886bec07b9c3109715017084de94b76e`，四处路径反向替换后字节一致。

三个 `test_scene_{pulse,standard_blur,xray}_dedicated_family_retirement.py` 已删除：原测试主要扫描旧文件/符号不存在和具体源码字符串，不执行退役后的独立pipeline。目录归属/新增文件由 `test_scene_semantics_coverage` 的布局门执行，原legacy执行链由 `scene_source_layout.json` 的 `retired-effect-chain-authority`、`stage-renderer-product-call`、`legacy-recovery-kinds` 等零预算规则与 `source_authority` 执行。保留的行为门分别是Pulse共用alpha/artifact正反例（`test_scene_generic_shader_program_artifact`）、Blur真实compiler/Metal与失败override（`test_scene_standard_blur_previous_composite`）、X-Ray provider准入及typed用户纹理（`test_scene_dependency_render_plan`、`test_scene_user_property_textures`）。这些门各守对应职责；旧测试的每个具体名字和源码拼写禁令没有逐条等价替代，不把删除称为新增行为覆盖或官方parity。

结构分类/完整发现与依赖试点的工具、基线、故障注入门及编排已完成，两个窄设计登记退役；依赖稳定合同、50条todo、分类元数据与历史比较继续保留。`structural-governance-design.md` 的navigation壳保留旧 `classification_migration.design_doc` 身份；这不表示checker或一次性历史迁移记录已退出。

本次审查纠正的验证（2026-10-03）：文档健康与验证编排119项、缓存/hook/证据清理40项、角色/索引/设计门33项、全仓Markdown链接1项，共193项通过；索引143/143文档、17/17稳定合同，正文门55份权威/3份归档通过。另以修正前基线核对7项精确调整，暂存diff逐字未变。独立静态复审覆盖四个工具修复；本批没有App构建或产品运行验收，不扩大此前产品证据结论。

最终固化验证（2026-10-03，比较基准 `6105ffe5648330ee758a9ebb1e54d2f2edcd4309`）：选中130个测试模块，首轮129通过；截图生命周期测试暴露drain通知与闭包ARC释放先后不同的竞态假设，以真实GPU/导出屏障证明该窗口后，仅修测试并独立通过（1.797秒），未改产品合同。汇总中16个条件测试跳过，不作全corpus或发布结论。另11个结构/文档/依赖/产物/设计门与隔离冷Debug构建通过，构建目录自动清理。固定fixture修复了分类迁移测试在首次提交后依赖HEAD的错误假设，6项相关检查通过；Scene工作流已统一设计前置。AGENTS新增有限维度的方向比较、最小结果和停止/转向条件，禁止指标膨胀或擅自替换用户目标。产品源码在最终验证期间未变化，第三方33个C/h与比较基准一致。

<!-- preserved-body:start -->
# 仓库改良执行路线

<!-- document-role: active-plan -->

本路线承接[原始改良提案](repo-improvement-program-2026-10-02.md)。原提案的18项问题和M1–M8是验收范围，本路线负责合并依赖、实施顺序和等价方案；不以旧统计、另写文档或标记“不采纳”代替落实。用户于2026-10-03授权全仓结构改良，本次按“权威与发现 → 确定性门禁 → 职责拆分 → 验证与维护”执行。稳定操作由[仓库开发工作流](../../development/repository-workflow.md)接管，源码职责查[仓库地图](../../architecture/repository-map.md)，结构裁决查[治理设计](../../development/structural-governance-design.md)。

## 原案逐项落实

| 条目 | 实际实现与等价裁决 | 验收入口 |
|---|---|---|
| P0-1 导航真话 | Scene现况快照前置；分层角色、真实节名与旧锚点一致 | document-links、document-health |
| P0-2 任务入口 | 既有角色索引唯一承载taskRoutes、合同覆盖、术语和gate IDs；查询一步返回，不另造重复路由JSON | document_registry --audit/--query；[频率取样](repository-improvement-completion-2026-10-03.md#task-route-frequency) |
| P0-3 发现域 | 全仓非忽略docs Markdown包含未跟踪文件；角色必须完整登记 | test_document_role_index |
| P0-4 owned选择 | 精确路径选择、重命名双侧、排除清单；默认全变化不变 | test_verify_scene_change |
| P0-5 快照出库 | 63.6MB census原字节迁到忽略evidence缓存，并从index移除；缺缓存不隐式生成；5MB门带精确上限/owner/原因/退役例外，当前无例外 | check_repository_artifacts、test_scene_capability_census |
| P1-1 长文生命周期 | 两份长台账原文迁历史，旧入口保留永久转接；当前正文预算、首读快照、合同复核日期与证据依据机器检查 | document_health、原Markdown链接门 |
| P1-2 inner轻门 | 结构与链接独立选门，正式source_authority复用扫描；不重复执行混合模块 | scene-structure、document-links |
| P1-3 门注册 | 实际发出的门有风险、触发、成本、串行和退役元数据，输出注册全覆盖；零命中设计门保留拒绝未来违规职责 | test_verify_scene_change、check_design_gate |
| P1-4 测试质量 | AST v1逐身份冻结，只减不增；表达式字面量普查公开检测边界。runner/提交取消/快照回滚有真实Swift行为和故障变异门 | check_test_assertions；--census-expressions；相关Swift harness |
| P1-5 巨文件拆分 | Renderer入口917→219行，4个帧职责扩展；Variant编译入口993→259行，7个准备/分析/产物/终结扩展；不新增状态owner或包装类型 | [已批准设计](../../scene/roadmap/batch2/frame-admission-retry-design.md)、submission事件门、ProgramFinalizer冷/热门、Debug build |
| P1-6 子树路由 | Scene AGENTS仅8行指针，不复制长期规则；规则桩和一跳合同受查询门约束 | document_registry |
| P1-7 构建缓存 | 显式opt-in隔离keyed DerivedData；默认冷构建；锁竞争exit 2。相同产品树两次冷构建及cache冷/热对照已执行 | test_checkpoint_build；本路线M6 |
| P2-1 会话残留 | 产品树7处.mimosa共61文件按精确清单可逆移至忽略隔离区，逐文件SHA相同；另27处__pycache__/DS_Store共586文件同样隔离保留；无删除、无解释研究正文；新增只读再生检测 | repository_residue --check；隔离区manifest |
| P2-2 Debug归类 | 22个Debug文件原字节移入App/Debug，同步所有活跃消费者；Xcode同步组与DEBUG边界检查，完整Debug构建 | app-debug-layout；路径迁移SHA；build-verify |
| P2-3 平铺合同 | Format/Diagnostics全层级枚举与唯一归属，取消depth-2逃逸 | source_authority、scene-structure |
| P2-4 提交前快检 | 可选、可卸载、默认提示；只看当前worktree暂存blob/owned/JSON/gate登记；保护他方hooks。Area trailer解析可供release notes分组 | commit_preflight、test_commit_preflight |
| P2-5 清偿节拍 | repository_health从已有权威派生优先级/家族/难度；receipt记录每批下降及每项未降原因，并对独立base执行append-only校验 | repository_debt --check --base-ref |
| P2-6 依赖方向 | 单边Rendering→Compilation内部试点；prepared公开值合同精确登记，混合算法namespace列todo，产品与harness分别盘点；新增边拒绝 | [依赖合同](../../scene/architecture/scene-dependency-boundaries.md)、check_scene_dependencies |

## M1–M8复评

| 度量 | 可重复检查与证据边界 |
|---|---|
| M1 定位距离 | `document_registry --query scene`、`--query 发布`、`--query sampler`；query输出合同、源码、当前事实和gate IDs；三层Scene入口直达sampler；首读快照≤150行。频率来自最近100条提交标题，不伪称自然语言任务命中率。 |
| M2 注册完备 | 编排器测试枚举实际发出gate ID与method gates，对登记作100%对账；元数据空缺、新未登记ID为红。 |
| M3 文档覆盖 | 全docs发现集和role index集合相等；稳定合同必须被任务路由覆盖。forensics仅登记身份，不读取表达。 |
| M4 inner结构门 | 专用方法门，不再把混合结构模块整个放入inner；单独计时输出是最终批次验证证据。 |
| M5 体积止血 | `git ls-files -- script/scene_capability_census_snapshot.json`为空；当前5MB门通过且exceptions为空；旧Git历史blob不改写。 |
| M6 构建成本 | 同一产品树：默认冷构建69.502s、65.173s；隔离缓存首次56.975s、第二次6.692s，均成功。缓存热相对缓存冷下降88.3%；仅此机器/源码/工具链对照，不代表运行性能。日志及身份在本机批次证据。 |
| M7 清偿节拍 | v1精确身份新增即红；表达式census包含合法行为断言，待provenance审查，禁止直接算作债务。每批receipt要求未降项原因100%，实际新增或变大拒绝，既有冻结工具仍为权威。 |
| M8 导航真话 | 原全仓Markdown链接门、727个旧锚点转接、归档完整载荷hash及节名门共同校验；行内代码路径仍不冒充可点击链接。 |

## 等价裁决与持续维护

原方案OQ1选择产品路径design gate；OQ2按职责拆分，不推断作者动机；OQ3缺缓存明确处理、不引入LFS或重写历史；OQ4采用纯指针桩；OQ5引用与Xcode构建共同验收；OQ6在现有role index维护路由与术语；OQ7复核日期绑定Git维护证据或hash导航审计，并明示非运行复验；OQ8零命中不能退役设计门；OQ9平铺清单保持完整发现且在职责目录化时整体替换；OQ10 Compilation规模进入派生队列，已拆两个热点，不宣称全仓技术债清零；OQ11仓库共享hook显式安装，按执行worktree读index；OQ12全量角色登记无静默豁免；OQ13 v1执法与表达式普查分离，扩检测口径必须独立设计并重审基线，不能把合法输出断言判成源码测试。本批表达式普查2411候选/176文件，人工分层溯源21条：10条产品源码形状、6条治理静态、5条执行或生成输出；非随机样本不外推总体。defense对全部13个可达基线版本复核后移除3条无使用acknowledgement，保留10条确有历史消费者的记录。

本路线在18项对应验证以及M1–M8复评完成后关闭；持续合同、各产品路线和真实剩余债务各归原权威。此次不是全产品功能、官方parity、账号、发布或长期性能验收。实际Swift事件、Metal探针、Debug构建各有自己的证明范围；迁移原证据不产生新的运行结论。工作区供审查，未获授权不提交、不推送。
<!-- preserved-body:end -->

<a id="task-route-frequency"></a>

## 任务路由频率取样依据

下文完整保留该阶段的历史裁决、证据身份和未验证边界；其中状态与后继顺序仅适用于原记录日期。

<a id="task-route-frequency--任务路由频率依据2026-10-03"></a>
### 任务路由频率依据（2026-10-03）

> **历史证据 — 非现役入口**

> 当前任务入口由[文档导航](../../README.md)和[角色索引](../../document-role-index.json)拥有。此处是固定代码历史的取样，不声称用户自然语言请求的真实频率。

<a id="task-route-frequency--可复核取样"></a>
#### 可复核取样

固定 revision：`6105ffe5648330ee758a9ebb1e54d2f2edcd4309`；最近 100 条提交。复核命令：

```sh
git log -100 --format="%H%x09%s" 6105ffe5648330ee758a9ebb1e54d2f2edcd4309
```

只用 conventional commit 标题括号内 scope 分组，没有标题 scope 的提交计入 `unclassified`，不补猜。完整记录输出 SHA-256：`06eacef45e3aafcaa40da6302ed03e98a1051e010fb08e73eb3af6ad0f87a968`。

| 标题 scope | 提交数 |
|---|---:|
| app-shell | 1 |
| audio | 1 |
| comparison | 1 |
| compiler | 1 |
| history | 1 |
| layout | 1 |
| review | 1 |
| scene | 55 |
| scene-particle | 1 |
| scene-particles | 2 |
| scene-resources | 1 |
| scene-shader | 2 |
| scene-textures | 2 |
| sil | 4 |
| steam | 1 |
| steam-core | 1 |
| steam-library | 3 |
| steam-net | 1 |
| steam-ui | 5 |
| unclassified | 10 |
| video-inspector | 2 |
| video-library | 2 |
| web | 1 |

<a id="task-route-frequency--路由取舍与证据边界"></a>
#### 路由取舍与证据边界

取样支持把 Scene 视觉/执行问题作为首屏入口；发布与设计前置是低频但高后果的必备入口，不能由频率淘汰。App、Video、Web、Steam 与跨引擎控制保留覆盖入口。提交 scope 是工程活动代理：一次任务可能产生多提交，未提交任务不在样本中，不能换算用户任务百分比；改变路由前可用新的固定窗口另存后继记录。


<a id="structural-governance"></a>

## 结构治理原始设计（已完成实施）

以下原设计的状态、现状和未来式属于批准时点；当前退出结论见本页收口更正。

# 结构治理的分类与完整发现

<!-- original-document-role: active-plan -->

状态：approved（2026-10-03）。本设计属于[仓库改良路线](../../development/repository-improvement.md)，只改变可执行治理，不改变产品算法。用户已授权全面调整仓库规则；本轮以当前代码反例裁决量度，禁止靠产品改名、删除 guard 或虚增预算过门。分类稳定并并入工作流、初次口径迁移检查退出后归档。

## 已证问题与目标

现行五后缀正则把 `SceneDebugFrameCapture.Admission` 的纯结果枚举计作作者形状分析器；现行 singular 规则把同一局部 first-element 别名的每次消费都计作独立职责。前者表达 DEBUG 请求 accepted/rejected，后者新增的是现役 compositor 的读取。计数准确反映正则命中，却没有准确表达原合同要冻结的结构家族与 owner。Format/Diagnostics 直接文件还被 depth-2 分支跳过，清单无法阻止新增文件。

五问：①否，无产品多 owner 改变；②是，变更治理唯一分类与冻结语义；③否，无用户数据和产品持久格式改变；④是，涉及已冻结结构家族；⑤否，只用当前我方代码。登记 `repository-structural-governance`，批准范围仅以下分类和发现纠偏；没有批准放松产品结构预算。

## 裁决与实现边界

- 保留原 broad discovery pattern，不能让新增名字或新增引用消失。按登记元数据分类每个命中，未分类项拒绝。
- 被动值声明可记录精确文件、限定声明身份、编译条件和纯枚举 payload。纯值分类必须拒绝新增函数/可变状态/其他行为；登记 owner、产生者、理由与退役条件。它不是运行语义证明，不豁免同文件的新 analyzer。
- 局部别名量度为被审核的局部声明身份，记录函数、initializer 和允许的只读消费形态。每个原 identifier 命中仍接受检查；新文件、新声明、函数外使用、未知消费和状态写入拒绝。原“mentions”与新“declarations”不可比较为代码偿还，口径转换必须显式记录，随后冻结定义与分类元数据。
- 分类机制由通用元数据驱动，不在检查器按业务规则 ID 写专用例外。当前两个产生者是初次迁移依据；后续新增分类须受与 pattern/范围变更同等的显式审核，不能靠编辑基线洗白。
- Format/Diagnostics 的直属 Swift 文件必须精确登记；所有层级走完整布局验证。新增、漏登记、移错目录和意外深层文件都有明确失败，而非自动扩清单。

## 验证与退出

正证：现有值声明和只读 alias consumer 保持接受；所有现行结构规则通过。反例：同文件新 analyzer、值枚举加行为、新 alias/写入/函数外使用、未声明直属/深层文件必须失败。检查器自身测试使用自有 fixture；同时核验原 regex 匹配全集仍被检查，原排序改动完整保留。没有产品修改，不据此声称画面、性能或 renderer owner 已迁移。

机器分类与已提交合同迁移由 `script/source_authority.py` 承载，semantics 测试保留真实全域扫描与故障注入案例；执行器不藏在测试用例文件中。它是有界静态治理工具，不是 Swift 编译器或语义证明。
