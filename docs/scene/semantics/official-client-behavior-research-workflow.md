# 官方客户端行为研究与一致性验证工作流

> 状态：现役稳定合同
>
> 最近复核：2026-08-15
>
> 目的：当公开资料不足以决定会影响画面、时序或生命周期的行为时，用范围明确的官方客户端研究补足**可观察行为合同**，再由 MyWallpaperX 独立实现并以官方客户端黑盒结果验收。

当前已有资料、固定客户端身份和既往结论只从[资料来源与证据索引](source-index.md)进入；当前能力与运行结果仍只由[能力台账](coverage-ledger.md)和[运行证据索引](runtime-evidence-index.md)决定。本文规定研究流程，不证明任何功能已经支持。

本规则不是法律授权。只可研究用户合法取得的本地客户端和有权使用的内容，遵守适用条款，不绕过账号、许可、DRM、签名、加密或其他访问控制，也不得重新分发官方二进制、私有资产或反编译产物。对具体法律边界有疑问时停止并请求项目负责人判断。

## 1. 核心结论

需要增加官方客户端研究，但**不得把“每做一项功能都先反编译”设成前置仪式**。

- 官方公开合同优先；现有固定证据能够回答时直接复用。
- 能从合法黑盒实验直接观察的行为，优先测行为，不先猜内部算法。
- Ghidra 等静态工具只用于回答公开资料和黑盒仍无法决定的高层职责、字段归属、执行顺序、状态转换和生命周期边界。
- 反编译输出不能进入产品实现。实现者只能消费经过 clean-room 压缩的项目自有行为合同、正反 fixture 和官方结果对照协议。
- 算法、数据结构和 Metal 实现可以与官方不同；但对一个声称兼容的 bounded profile，最终作者可观察结果必须在**事先声明**的容差内与固定官方客户端一致。
- 静态结构一致、编译成功、非黑画面或 Mirage 输出都不能证明官方结果一致。

这条流程服务“快速出正确结果”：研究到足以消除当前纵向切片的关键歧义就停止，不追求恢复官方完整内部实现。

## 2. 何时启动，何时不得启动

只有以下条件**全部成立**才启动新的官方客户端研究：

1. 已在当前代码或隔离内容中记录第一个失败 identity 和用户可见差异；
2. 存在一个会改变公共实现选择的具体 unknown，例如 pass 顺序、default/override 优先级、事件相位、target 生命周期或 alpha/颜色合同；
3. 现役专项合同、既有固定客户端证据、官方公开文档/声明、合法 stock/corpus 和项目自有实验仍不能回答它；
4. 问题能写成一个有界问题，并能预先写出至少两种候选答案和区分它们的可观察结果；
5. 答案会直接闭合当前纵向结果，或避免建立明显错误的公共 owner/IR/lifecycle。

以下情况不得启动 Ghidra 扫描：

- 公开合同或资料库已有结论足够；
- 只是尚未把现有代码接到 product path，或缺项目自有测试、GPU/compositor 证据；
- 想知道官方 shader、粒子、随机、物理或数值算法的具体公式；
- 想为一个 sample/layer/path/hash 制造专用输出；
- 想做宽泛调用图、函数数量、常量搜索或“看看还能发现什么”；
- 问题属于公开第三方库自身，应直接研究其官方 API 或上游源码；
- 固定客户端身份、工具身份、研究范围或可观察验收无法建立。

若只缺官方运行环境，可以完成静态结构研究和项目自有实现，但必须把官方一致性状态记为 `blocked` 或 `not-run`，不得把静态结论升级为兼容完成。

## 3. 证据阶梯

对每个 unknown 按下列顺序取最小充分证据，前一层已足够时不进入后一层：

1. **当前项目事实**：代码 owner、当前首断点、已有 fixture、当前可复现运行证据；
2. **官方公开合同**：Designer 文档、公开类型声明、官方 changelog、官方文档源码和公开示例；
3. **合法结构化材料**：固定客户端随包 locale、声明、definition、stock 结构和项目有权使用的 corpus；
4. **官方客户端黑盒实验**：固定输入下改变一个变量，记录画面、时序、事件和生命周期差异；
5. **有界静态取证**：只为未解决的字段归属、producer-to-consumer 路径、顺序、状态或 owner 问题使用 strings/imports/RTTI/xref/选择性反编译；
6. **第三方固定 revision 对照**：只在官方证据仍不足或需要交叉检查完整链时检查职责、状态传播和顺序；
7. **项目独立实现与验收**：用自有合同实现，再回到固定官方客户端做同步黑盒对照。

第四和第五步可因运行环境可用性互换，但证据职责不变：黑盒回答“外部发生什么”，静态取证最多帮助回答“哪些高层职责和顺序可能造成它”。第三方实现永远不能替代官方黑盒结果。

## 4. 一次研究只回答一个问题

开始工具分析前，先写研究卡。问题必须类似：

- `condition` 是在 pass/FBO 纳入图之前还是之后求值？
- 同一 shader combo 同时有 material 显式值和 annotation default 时谁优先？
- `mediaPlayback` 事件在本帧 update 之前还是之后对脚本可见？
- optional target 失败时是否保留进入 effect 前的 current？

不得写成：

- “逆向官方 Scene 引擎”；
- “找出这个 effect 怎么实现”；
- “恢复官方 shader/粒子算法”；
- “让这个样本看起来一样”。

最后一个目标过宽；应拆成可验证的颜色、几何、合成顺序、时间、事件或生命周期合同。一次研究结束后仍有新的独立 unknown，另建研究卡，不扩张原范围。

## 5. AI 研究卡

启动本流程后，AI 在根据本次研究修改产品代码前必须填写以下字段；不适用项写 `not-applicable`，不能留空或用推测补齐：

```yaml
research_id:               # 稳定短 ID
owner_and_date:
user_visible_expected:
user_visible_actual:
reproduction:
current_first_breakpoint:  # sample/layer/effect/pass/slot/target 仅作 identity
bounded_question:
candidate_answers:
distinguishing_observable:

sources_already_read:
existing_evidence_reused:
remaining_unknown:
why_this_blocks_shared_design:

official_client_version_build:
official_binary_sha256:
content_or_fixture_sha256:
runtime_environment:       # OS/backend/quality/viewport/scale/color space
tool_name_version_path:
exact_command_or_ui_scope:
analysis_budget_and_stop_condition:

official_public_facts:
official_black_box_observations:
client_static_observations:
third_party_cross_check:
project_inferences:
still_unknown:

self_authored_behavior_contract:
allowed_inputs_and_order:
failure_and_fallback_contract:
independent_implementation_owner:
positive_and_negative_fixtures:

golden_capture_protocol:
comparison_metrics:
predeclared_tolerances:
parity_result:              # passed/failed/blocked/not-run
evidence_and_doc_updates:
```

研究卡中的 `fact`、`observation`、`inference` 和 `unknown` 必须分栏。客户端静态观察必须绑定版本/build/hash；第三方观察必须绑定 revision。没有固定 identity 的结论只能作为定位线索，不能进入稳定语义合同。

研究卡可以先放在本批 issue/工作记录中。只有能长期复用的行为合同和证据边界才进入现役语义文档；地址、伪代码、函数体和工具工程不得进入仓库。

## 6. 本机工具与有界静态取证

2026-08-15 的本机盘点可发现 Ghidra `12.1.2`、OpenJDK `21.0.12` 和资料库已登记哈希的 Wallpaper Engine 2.8.42 客户端文件；这只是当日可用性快照。每次研究仍必须重新发现并记录实际工具路径、版本、客户端版本/build 和 SHA-256，不能把个人安装路径或旧文档中的版本当成当前事实。

建议的静态研究顺序：

1. 先核对[既有客户端静态取证](client-runtime-static-forensics.md)是否已经回答该问题；
2. 对目标二进制重新计算 SHA-256，并核对固定客户端身份；
3. 用 `command -v`、包管理器记录或工具自身版本信息发现 Ghidra/Java；找不到时标 `blocked`，不擅自下载或更换客户端；
4. 在 `/private/tmp` 建立本批独立 Ghidra project 和输出目录，不复用含其他研究状态的工程；
5. 只启用回答研究卡所需的 import/export、strings、RTTI、xref、有限可达性和选择性 decompile；第三方库、无关模块和宽泛调用图不纳入；
6. 只记录高层字段、职责、状态、分支类别、先后关系、owner 和生命周期事实；
7. 将结果压缩为无实现表达的项目行为合同后，按精确归属清理临时 project、日志和反编译输出。

仓库可以保存：固定输入身份和哈希、工具/版本、可复现命令或 UI 范围、高层结构事实、证据限制、自有行为合同、自有 fixture 以及数值化对照报告。

仓库不得保存或转述：

- 客户端地址、offset、机器指令、字节或符号转储；
- 反编译伪代码、函数体、控制流的可还原抄录；
- 私有 shader、脚本、JSON/payload、纹理、模型、音视频或官方资产；
- 私有算法表达、公式、常量表、查找表、随机/物理积分细节；
- 能重建专有实现的连续字段布局、vtable slot 或调用链抄录；
- 原始 Ghidra project、分析数据库、PDB、日志或官方二进制。

本仓已有的字符串/结构化材料提取器只能辅助建立版本化证据清单，也不能把提取结果自动升级为运行语义。任何工具警告、反编译失败或 PDB 缺失都是分析限制，不是客户端缺陷。

## 7. 从研究到独立实现

研究者交给实现者的唯一接口是**项目自有行为合同**，至少包含：

- 输入字段、类型、默认/override 和合法组合；
- producer、consumer、作者顺序、frame/event 相位；
- state、target、resource、publication 和 teardown 生命周期；
- 可见输出、局部失败半径和 previous-current fallback；
- 明确正例、反例、unknown 和预算；
- 官方 black-box 对照方式和预声明容差。

实现者不得读取或照译反编译伪代码。实现必须落入现有 Swift/Metal 通用 Program、graph、VM host bridge、particle component op、resource/provider 或 compositor 职责；不得按研究用 sample/layer/path/hash 建产品 dispatch。

若官方只证明行为方向而未给出数值真值，可以先做项目自有 bounded approximation，但必须：

1. 在合同和能力表中明确标成项目近似；
2. 保持未知 profile fail closed 或局部 fail soft；
3. 不声称官方算法、像素或时序等价；
4. 保留后续官方 golden 能替换或校准它的单一 owner。

## 8. 官方结果一致性门

“最终结果一致”指：对**事先界定的 bounded profile**，同一作者输入在固定官方客户端和 MyWallpaperX 上产生相同的作者可观察语义，并在预先声明的容差内通过。它不是“内部算法相同”，也不是从一个截图主观判断“差不多”。

### 8.1 固定控制变量

对照前固定并记录：

- 官方客户端 version/build/binary hash 和 MyWallpaperX commit/App identity；
- project/scene/asset/fixture hash；
- viewport、DPI/scale、fit/crop、quality、FPS、color space 和背景；
- 属性值、Timeline 状态、time origin、pause/seek 和 capture frame；
- pointer 位置/按钮/事件序列；
- audio buffer、media state/artwork/metadata 和其他 provider 输入；
- 随机 seed；若官方不允许固定 seed，则记录多次运行和统计比较方案；
- warm-up 帧数、采样时间点、GPU completion 和截图发生的帧边界。

每次实验只改变一个变量。无法控制的变量必须写入 `still_unknown`，并限制结论范围。

### 8.2 预先声明比较方法

根据能力选择能直接反映用户结果的门，不得在看到失败后放宽指标：

| 行为类型 | 至少比较 | 典型容差形式 |
|---|---|---|
| 静态 shader/effect | 预定义 ROI 的 RGB/alpha、边缘、mask、透明区和合成背景 | 每通道误差、ROI MAE/分位数、边缘位置；必要时要求 exact |
| 几何/变换/文字 | bounds、anchor、baseline、遮罩轮廓和关键点 | 像素/亚像素距离、覆盖率、文本基线偏差 |
| 时间/Timeline | onset、duration、phase、pause/seek 后状态和多帧序列 | 帧数或毫秒误差、相位误差、关键帧值 |
| pointer/event/script | 事件顺序、次数、目标 identity、同帧/下一帧可见状态 | exact sequence/count；画面再用 ROI 门 |
| 粒子/随机/物理 | spawn/death 统计、轨迹包络、速度/颜色分布和稳定性 | 固定 seed exact 或多运行统计区间 |
| target/history/lifecycle | publication identity、previous/current、next-frame、reload/teardown | exact 状态顺序，加对应 ROI/序列 |

Direct3D 与 Metal 的浮点、采样和色彩后端差异意味着默认不要求整帧逐字节相同；但容差必须由作者可见需求、平台差异实验和反例敏感性事先确定，不能用宽松 SSIM 或任意非黑像素掩盖错误合成。能够合理 exact 的离散字段、事件顺序、target identity 和状态转换应要求 exact。

### 8.3 通过条件

一个可见兼容原子只有同时满足以下条件才可记为该 bounded profile 的官方结果一致：

1. 项目自有 synthetic 正例与反例通过；
2. 隔离真实或自有代表内容实际经过目标公共执行路径；
3. GPU/VM completion、精确 publication、terminal compositor 和 next-frame 合同按风险闭合；
4. 固定官方客户端对照按同输入、同时间、同事件协议运行；
5. 所有预声明 ROI/序列/状态/容差通过；
6. 新组合或反例证明实现没有退化为样本身份特判；
7. 能力表和运行证据只提升到本次实际证明的范围。

若官方客户端对照未运行，最高只能报告“项目自有实现/结构一致，官方结果未验证”；若对照失败，保持 `failed` 并记录第一个差异，不以算法不同、Metal 后端不同或主观可接受为由改写通过标准。

官方原始帧、客户端资产和反编译产物默认留在仓库外的受控本机证据目录。仓库只提交项目有权分发的自有 fixture、捕获协议、哈希、数值化报告和必要的差异可视化；若要版本化官方客户端输出，必须先单独确认许可与分发边界。

## 9. 停止条件与文档回写

出现以下任一条件即停止扩大研究：

- 已有证据能够唯一决定当前公共行为合同和验收方法；
- 继续分析只会进入私有数学、函数体、常量或第三方库内部；
- 研究范围从一个问题漂移成模块扫描；
- 客户端、内容、工具或运行环境身份无法固定；
- 需要绕过访问控制或保存禁止产物；
- 结论无法由项目自有 fixture 或官方黑盒实验区分；
- 当前阻塞其实已转移到 MyWallpaperX 接线、GPU、资源或 compositor。

完成后按事实分别回写：

- 可复用来源与版本边界写入[资料来源索引](source-index.md)或对应静态取证页；
- 目标行为写入唯一专项语义/实现合同；
- 当前支持范围写入能力台账或专项覆盖表；
- 实际运行和官方对照结果写入运行证据索引；
- 当前开发顺序只有真的改变时才更新现役路线。

不要把研究卡全文复制到多个文档，也不要因一次有界取证把固定版本观察改写成“官方引擎一直如此”。
