Agents 开发与问题修复流程规范

1. 问题来源

当检查样本后产生报错时，Agent 必须基于实际运行结果进行分析，不得仅凭表面错误信息进行猜测式修改。
样本源路径：`~/Movies/MyWallpaperX/创意工坊/`

真实创意工坊目录只作为只读样本来源。运行 benchmark、注入属性、清缓存或修改样本前，必须复制到隔离目录，并同时使用隔离的 Workshop root 和临时 HOME；不得直接修改、删除或清理真实样本。

Web / Scene 当前能力、验证结果和剩余缺口以 `docs/reviews/web-scene-current-state-roadmap-2026-07-19.md` 为状态入口；历史 review、handoff 和 regression 记录不能反向覆盖当前代码与最新运行证据。

继续 Scene 开发前，先查 `docs/scene/semantics/coverage-ledger.md` 的系统摘要，再按 `docs/scene/semantics/capability-dependency-map.md` 确认公共依赖，进入该行链接的 Effect、粒子、SceneScript、Graph/Shader、运行输入/属性或高级对象专项能力表核对代码、测试和运行证据，最后按 `docs/scene/scene-capability-development-plan-2026-07-22.md` 选择当前批次。专项能力表是逐项等级的事实来源；`docs/scene/semantics/official-page-map.md` 是 179 个官方页面的逐页归属门。不得把 `recognized`、`wired`、`executed-degraded`、固定 strict profile 或固定样本运行门写成完整兼容。

2. 修复前分析

在开始修改前，Agent 必须先完成以下工作：

1. 梳理每一个报错样本的运行逻辑；
2. 明确每个样本的预期行为、实际行为和报错原因；
3. 判断问题属于样本逻辑、框架实现、依赖配置、解析流程、缓存机制，还是环境问题；
4. 识别同一问题是否影响多个样本，避免重复修复或局部绕过。

3. 制定修复计划

Agent 必须先列出清晰的修复计划，再依次执行。

计划应包含：

1. 当前发现的问题列表；
2. 每个问题的根本原因假设；
3. 预计修改的位置和影响范围；
4. 需要验证的样本范围；
5. 每一步完成后的验收标准。

4. 修复原则

修复必须从根本原因入手，而不是进行小修小补或临时规避。

Agent 应遵守以下原则：

1. 优先修复通用逻辑，而不是只让单个样本通过；
2. 不得通过硬编码、跳过校验、隐藏错误等方式掩盖问题；
3. 修改必须保持向后兼容，避免破坏已有正常样本；
4. 对可能影响多个样本的公共逻辑，应评估连带影响；
5. 保持代码结构清晰，避免引入新的技术债。

5. 逐项修复与验证

Agent 必须按计划逐个问题修复。

每完成一个问题的修复后，必须立即验证：

1. 单独运行该问题对应的样本；
2. 运行可能受本次改动影响的相关样本；
3. 确认无新增错误、无回归问题；
4. 验证通过后再提交本次修改；
5. 提交完成后，才继续修复下一个问题。

不得一次性修改多个无关问题后再统一验证。

6. 验证范围控制

验证范围应基于影响面合理选择。

Agent 不应默认全量运行所有样本，因为这会浪费大量时间。应根据改动内容判断：

1. 如果只影响单一样本逻辑，只运行该样本；
2. 如果影响公共解析、构建、缓存、运行时逻辑，则运行相关样本集合；
3. 如果影响全局基础设施、核心执行链路或公共依赖，才考虑扩大验证范围；
4. 每次验证前都要说明为什么选择这些样本。

Scene 运行门分两层：`script/scene_wallpaper_sample_matrix.json` 是固定回归门，`script/scene_wallpaper_full_sample_matrix.json` 是当前真实 Scene 目录的完整快照门。日常局部改动按影响面跑定向样本；公共运行时、解析、缓存或资源链改动至少跑固定回归门；真实样本增加、完整矩阵合同变化或里程碑收口时，重建隔离副本并跑完整快照门。两层矩阵有重叠但不能互相替代，文档必须分别报告，不能把固定门写成“当前全部样本”。

7. 缓存与生效性检查

修改后必须确认代码变更已经真实生效，避免因为缓存、构建产物或文件解析问题导致误判。

Agent 应检查：

1. 是否存在旧缓存、旧构建产物或旧解析结果；
2. 修改文件是否被实际加载；
3. 样本是否读取了正确的配置文件、入口文件和资源文件；
4. 是否需要清理缓存、重启进程或重新生成中间文件；
5. 验证失败时，应先排除“修改未生效”的可能性。

8. 提交流程

每个问题修复完成并验证通过后，Agent 才能提交。

提交要求：

1. 每次提交只包含一个相对独立的问题修复；
2. 提交信息应说明修复的问题、根本原因和验证结果；
3. 不得把多个无关修复混在同一次提交中；
4. 若发现计划外问题，应先记录，再判断是否纳入当前修复范围。

9. 输出要求

Agent 在执行过程中应持续输出结构化信息：

1. 当前正在处理的问题；
2. 已确认的根本原因；
3. 本次修改内容；
4. 影响范围；
5. 已运行的验证样本；
6. 验证结果；
7. 是否已提交；
8. 下一步处理的问题。

10. 通用质量要求

Agent 应确保最终结果满足以下标准：

1. 所有已知报错均已修复；
2. 修复方案具备通用性和可维护性；
3. 相关样本验证通过；
4. 无新增回归问题；
5. 缓存、解析和构建链路已确认无误；
6. 每次提交都有明确边界和验证依据。

11. 代码健康与实现规模

Agent 修改 Swift 代码时必须同时控制文件体积和实现复杂度：

1. 新增或未列入历史基线的 Swift 文件不得超过 400 个物理行；不得通过压缩语句、删除合理空行或降低可读性规避限制；
2. `script/code_health_baseline.json` 中的历史超限文件只能保持或缩小，不得继续增长；触达这些文件时，新增代码前必须先判断能否按现有职责边界拆出独立声明或扩展；
3. 单次使用的逻辑保持就地实现；只有真实复用、独立职责或显著降低复杂度时才新增类型、协议、包装层或文件，不得预埋未来扩展点；
4. 拆分必须保持行为、命名和访问边界；不得为了跨文件访问而批量放宽 `private`，也不得按行数机械切割强耦合代码；
5. 修改 Swift 后、构建前和提交前都必须运行 `python3 script/check_code_health.py --check --base-ref HEAD`；文件缩短后先运行 `python3 script/check_code_health.py --ratchet-baseline` 锁定新的下限，再执行前述检查；
6. Agent 只能降低或删除历史基线，未经用户明确批准不得新增例外、提高单文件额度、移除源码根目录或调高 400 行阈值；
7. 新增 Tests、helper target 或其他 Swift 源码根目录时必须同步纳入扫描；远端历史约束使用 `python3 script/check_code_health.py --check --base-ref <base-ref>` 验证；门禁失败不得提交、推送或发布。

12. Scene 源码目录治理

`MyWallpaperX/Core/SteamWorkshopScene` 只作为 Scene 源码分类根目录，不再直接放置 Swift 文件。新增或拆分文件必须进入以下现有职责目录：

1. `Format`：Project、Document、PKG/TEX、JSON 和 interpretation；
2. `Runtime`：Host、frame context、runtime model、descriptor 和 diagnostics；
3. `Properties`：用户属性、binding program、dynamic snapshot 和 live update；
4. `Resources`：asset/resource index、texture loader、path resolver 和 video source；
5. `Rendering`：Metal 核心、compositor、layer、camera、geometry 和 utility；
6. `RenderGraph`：authored effect graph、dependency、render target、offscreen pool 和 ShaderContract；
7. `Effects`：具体 effect 的 pipeline、runtime plan 和 renderer；
8. `Text`：文字 descriptor、font、geometry、texture 和 dynamic text；
9. `Particles`：粒子 definition、parser、simulation、pipeline、texture 和 trail。

同一主类型的 extension 与主文件放在同一目录。不得新增 `Misc`、`Common`、`Helpers` 等兜底目录，也不得为空的未来能力预建占位目录。只有现有九类无法表达已经落地的一组独立职责时，才允许新增一级目录；通常应至少已有多个共同生命周期或依赖边界清晰的文件，而不是单个文件。可预见但尚未落地的 Timeline/Animation、SceneScript/Scripting、system/media/audio provider 和 Puppet/3D/Lighting 继续按开发计划推进，形成真实代码边界后再决定是否新增目录。新增目录须同步更新 Scene 语义手册和 `test_scene_semantics_coverage.py` 的布局门。移动 Scene 源码时必须同步测试源码路径和文档链接，保持 `project.pbxproj` 无无关改动，并运行 Scene 全量测试、代码健康检查和签名构建。
