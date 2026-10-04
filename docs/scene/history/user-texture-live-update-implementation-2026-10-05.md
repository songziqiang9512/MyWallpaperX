<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# 文件纹理原位更新实施（2026-10-05）

> **历史证据 — 非现役入口**。当前权威：[运行架构](../architecture/runtime-architecture.md)、[能力台账](../capabilities/coverage-ledger.md)、[运行证据](../capabilities/runtime-evidence-current.md)。

2026-10-05，基线022aa313。用户已实测背景和播放器封面可选择，但每次选图重建整个Scene。目标是已有场景换PNG/JPEG时只准备相关纹理，保持脚本、时钟、graph和输出；失败继续显示旧图。此设计是RF05后继，不把单样本、构建或已准备variant当作验收。

## 实施前决策与职责

当前Service的sceneTexture分支在180ms后requestSceneRender，MetalView启动时固定userPropertyTextureLoad。资源层已有同源多purpose加载、typed candidate/publication和prepared readiness variant；URL与尺寸不属于VariantKey。故不用重编整场景，也不按样本分派。

采用Session拥有的窄文件纹理事务及不可变资源快照，复用现loader、decode budget、upload queue和registry。每View独立异步加载会重复解码并形成分屏revision，放弃此方案。Session不成为第二纹理解码器或compositor；View移除独立可变资源权威，只消费Session发布的快照。首次启动也走同一快照所有权，后建surface不重新载入旧URL。

| 环节 | 唯一职责 |
|---|---|
| 属性服务/UI | 保留最新选择意图；成功回执后提交bookmark、override和控件状态。清除选图携带作者默认值。失败不覆盖已提交选择。未播放时用后台同decoder验证后保存；删去当前主线程预解码，避免live路径双重decode。 |
| command/IPC/client | 每次窄typed纹理事务只含一个key、recordID、revision、selected(reference)/reset及对应属性值；reference沿原bookmark跨进程。校验键集、类型、revision和transport generation。只有成功更新已接受重放intent；坏图失败不走scalar拒绝即重载。停止/切场景/daemon退出必须结束等待回执。 |
| Host/Session | 校验active record/session；启动期无可更新session或已有需重建的同record候选时明确unavailable，由原launch路径接管最新意图。正常运行准备所改key的全部实际purpose，按key最新revision、session/launch/device身份拒绝迟到结果。 |
| 后台资源准备 | 使用受控串行worker及现loader，一次解码、准备同key所有用途；security scope覆盖读取/上传完成。不是简单Task包装主线程调用；按产品MainActor配置验证实际worker。安全失败取消该请求并留旧快照。 |
| 帧入口/registry | 全部用途ready后，在任一surface encode前一次采用新不可变快照和相应effective values；递增content generation并保留真实source revision、extent、UV及sampling。旧GPU帧继续持有旧资源。 |

不得为新事务公开pending/unavailable去覆盖旧ready。新图失败、资源预算不足、已取消、过时回调都不改变健康运行资源。首次替换尚无旧图时保持原absent/fallback。reset为全部该key typed identities显式absent，并删除bare userProperty纹理，复用作者asset/低优named fallback。不同key独立排队，完成时合并当时最新快照；单请求限制一个key，全部重置由属性服务逐key发送，非纹理值仍走原scalar链。同key A→B→reset只允许最新意图提交。缺文件和坏PNG不得自动重启Scene。

App重放仅保存已接受资源。daemon重启中断未完成选择并通知调用方，原accepted reference重放；迟到成功/失败不可覆盖新transport或新record。明确unavailable与decode/upload failure不同，同record正在启动时先等待该次首次呈现，再提交纹理事务。真实graph/ABI变更才回退现launch：候选携带仅本次有效的requiredUserTextureKeys接纳约束，指定key所有用途ready（reset为absent）后才允许候选取代旧Scene；匹配首次呈现后确认并清除重放中的约束。失败保持旧Scene。普通PNG/JPEG的URL、内容或尺寸变化不构成重建理由。

不承诺多屏GPU同时呈现。现FrameDriver逐surface提交/commit；各surface encode前读取相同revision，失败surface按既有规则discard并在后帧使用最新快照，不能回滚另一屏已提交的GPU。暂停时也应完成资源准备/意图确认并在恢复或安全静帧刷新时使用新快照，不为了等待回执私自推进SceneClock。

## 原验收与退出约束

- CPU/Metal门：合法PNG/JPEG、不同尺寸、同文件新revision、多purpose完整发布；坏图/缺文件/任一purpose失败保旧；reset显式absent；A→B→reset、乱序完成、取消、device/session退出、未完成请求的回执与资源释放。
- 实际产品命令经过IPC/Host/Session/registry/compositor；真实293的7/25/26/48四属性覆盖基础背景及effect override。25/26同时有base和effect消费者，不能仅修base。自有输入另外证明通用键、尺寸和fallback。
- 对比选图前后session、VM generation、clock与shader/graph准备计数不重启；记录操作到真实新画面的耗时，不用测试数或非黑作性能证明。多surface CPU同revision和实际单屏GPU分开报告；daemon重启重放、暂停、快速连续选择分别验证。
- 保护022aa313坏图保旧语义，删除被新异步事务取代的同步预检/全量重载职责；普通scalar/脚本属性更新不退化。
- 独立只读终审核对固定diff、App及实际证据。完成后把资源事务职责移入runtime architecture、修正as-built-map的全surface GPU栅栏旧表述，记录范围并退役本窄登记。未知组合保留明确缺口，不绕过安全检查或把Scope缩成仅base。

## 实施结果与证据上限

普通 PNG/JPEG 选择现经真实 Service → typed IPC → Session 串行资源准备 → 同一 snapshot/registry → 原 compositor 原位更新；删除主线程重复预解码及正常换图全 Scene 重载。失败保留旧资源/设置，reset 显式 absent 并释放旧 publication。启动期等匹配首帧；真正不支持 live 的混合绑定保留 existing candidate 路由并验证 required keys。solid 文件原先在 draw 前被拒绝、露出灰色 clearcolor；现进入唯一 candidate 校验并复用 ready-provider 动态颜色规则，静态占位黑色不再遮住选图，reset 恢复作者颜色。

独立审查的两项 P2 已通过真实 Service/Client 反例修正：旧全 reset 不覆盖等待期间的新 scalar 编辑；fallback 候选首帧/死亡不抹掉窗口内已接纳的其它 key。候选 App Debug dylib SHA256 `a8dc34cabbecb2285f846ca1daadac7952a4eb7df4c593836ff42f97f4c39783`，1088 个产品输入冻结且构建前后 drift=[]，完整 Debug build 与 deep/strict 签名检查通过。资源/registry 原生门、Session 事务、控制面、solid 真实 draw/uniform CPU 反例及相邻回归通过；Scene 结构门仍有 HEAD 既存的 analyzer inventory 两项失败（66/65 与 PreparationAdmission 分类），未扩大基线。

验收只到本次隔离输入。物理多屏、真实音频/平台媒体事件、暂停中可见刷新、fallback 重建的实际 GPU 故障和官方同状态像素仍未验；相关乱序/暂停/重放仅 CPU 行为门。单次 ImageIO 读取不可抢占。整体样本完整正确率尚不能估计，执行数量另按相应输入给出；普通帧热替换不会重建 VM/graph 不代表所有组合都已覆盖。稳定职责已移交运行架构/Daemon合同，本窄设计登记退役。

实际产品输入为隔离293包（原 scene.pkg SHA `1f3a74c0241bb8f57c0abdbcded05562e329ebfc6ff47bf762e8b71f4e0326fc`）及自有512²红PNG、640×360蓝PNG、360×640绿JPEG。最终 `product-final` / `product-48-final` 两次运行分别覆盖7/25/26与48，四键均确认实际像素，25/26沿base及effect消费者合成。普通背景红→蓝→坏图保蓝→reset黑，cover红→蓝→缺图保蓝→reset默认，唱片绿图，流动背景红→蓝→坏图保蓝→reset默认均成立。各运行只有一个daemon PID和一次firstPresent，13项操作没有重建Scene；合法换图回执64–275ms，操作至Metal截图落盘156–360ms（含捕获开销，只限本机Debug与这些输入）。原件逐文件SHA核验未变。

两运行实际shader stage并集39/73，终端被compositor消费的effect owner为23/37；这是此操作覆盖下限，未触发的分支不记失败，也不是整体正确率。85个顶层对象中51image/29text/5particle；当前未逐对象声明全正确。下一批处理该样本媒体封面及音频/点击触发后的实际首断点，不以静音或未触发pass-through冒充响应。本机证据包 `.artifacts/scene-evidence/runs/user-texture-live-20261005/final/samples/1/runtime_evidence.zip`，SHA256 `cd42e343fda94614902bcf44510903e9e17b42fcaf3ad8ffe605f04407269f32`，限14日保留且不含原包。产品/测试独立审查冻结manifest为 `535dfbf6e5f56ef89e60f6a8a8be2487248deb95246d9b640e33660d27c81c99`，其后仅文档归档与状态同步。
