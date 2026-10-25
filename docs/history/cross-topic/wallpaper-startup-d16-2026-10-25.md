# 壁纸启动 D16：统一测量 App 的运行包名

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**
>
> 截止：2026-10-25。当前步骤归[启动专项](../../development/wallpaper-startup-optimization-plan.md)。本批修正跨 Scene/Web 的测量输入，未改 Swift 产品；名称对照受并发编译干扰，不认性能或系统因果，D15准入前差异仍未关闭。

## 断点与取舍

[D15](../../scene/history/scene-startup-d15-2026-10-25.md)的原App从 `d15-baseline.app` 启动，候选从 `MyWallpaperX.app` 启动。原 `stage_signed_app` 沿用来源包名，因此实际运行外层名也不同。备份名进入测量输入是可消除的混杂；不能只核主exe、bundle ID和签名就认为两臂运行路径等价。旧单测把两来源都硬编码成同一运行名，未暴露此问题。

只读身份审查确认两App的Info.plist、entitlements、Team、指定要求、hardened flags、SDK/minOS、依赖/rpath和检查到的xattr相同，无quarantine。2563个普通文件和6个符号链接中，差异为主exe、15个SteamService Mach-O和CodeResources；后15个各slice仅签名blob不同，代码、UUID、布局及CDHash相同，不能称helper代码漂移。原主exe为 `01c4a7296936607efea48db3c72cb4e4ebda88baa037277c3285f89013d0256d`，候选仍为 `bb1d21997be3bc2d76baa97d83db6da56f539adad4a7503612a5334c71699256`。

历史原点也不支持把约0.5s前缀直接归给D15产品改动：核D10/D11/D14/D15保护包的72份native与72份App日志，D15前66个新App首请求的entry→accepted观测窗为477.503–756.369ms；D14同一原exe三项为609.555/528.647/537.803ms。同daemon暖点仍另列，保留旧长尾。不同stage路径、generation、HOME和采样条件使这些记录不能组成新的同条件对照，也不抹去D15原AB差异。

源码追踪表明accepted之前包含启动、异步hello写管道、父端读取/RunLoop投递、角色与配置回放、子端stdin/主队列及再次事件交付。hello入队早于输入桥和read loop安装；首display日志也不是child main入口。此窗没有Scene模型/包读取/Metal/noise创建，组合延迟不能当成某个owner的独占成本。先纠正包名输入，尚不为假设的OS、LaunchServices或TCC原因修改产品。

## 名称控制原始结果与污染

固定同一候选App和D15原publisher发布的同一library/generation，预先冻结驱动、协议、2569项相对文件字节/模式及链接目标。仅在任务副本上依次改外层名：A1 `MyWallpaperX.app` → B `d15-baseline.app` → A2 `MyWallpaperX.app`；不改源App、Info.plist或签名。沿原唯一benchmark核，各组C0/C1/W0共3App、4请求，30 FPS、90s、无sampler、一次执行。相对树检查不涵盖全部目录元数据/xattr，新stage父路径/inode和执行顺序也仍变化。

**执行失误与证据边界：** 启动前检查发现其他会话Swift frontend PID 28556/28566并返回1；主Agent编排未按退出码阻断，仍派发执行。发现后检查时驱动已结束，没有实际中断，也没有重启或重采。原收据v1中的中断意图和更正后的v2一并保留。没有全运行窗的清洁进程证明，这组数据标作污染诊断，不能作为正式性能或名称因果资格。

| entry→accepted观测（ms） | A1 | B | A2 |
|---|---:|---:|---:|
| C0新App | 623.991 | 468.814 | 610.429 |
| C1新App | 652.858 | 72.962 | 644.186 |
| W0组首请求 | 649.306 | 72.687 | 600.631 |
| W0同daemon暖请求 | 1.687 | 2.697 | 1.163 |

九个App、十二个请求的完整admittedSource、出版guard、作者/库树、生产偏好、原helper、签名及正常退出/清理资格均通过；候选主exe和CDHash `69e47b45eda722d02ef1c54b50ccc917b8c0c450`不变。原报告 `passed=true` 只表示这些功能资格，`performanceAccepted=false`；独审明确 `contaminated=true`、`cleanPerformanceQualification=false`。表格保留名称关联的原观察，不据此推定系统缓存、安全检查或产品提速。

## 最小工具修正与前后验证

先在专项P0修订输入合同，再沿原复制/验签owner增加可选keyword-only `runtime_bundle_name`。默认None保留来源包名；仅 `wallpaper_startup_benchmark.main` 显式传 `MyWallpaperX.app`，适用于单臂及所有配对臂。另三个Scene/Web/process-isolation调用者仍用原两位置参数；不新增CLI、计时器、调度、统计口径或staging owner。

显式名称须为单一有效 `.app` 文件名；绝对路径、父级/子目录、反斜线、NUL、空stem及非字符串在复制/目录创建前拒绝。仍保来源路径作provenance、相对exe位置、原ditto、strict签名/身份检查及原清理。四个原计时/调度函数 `run_selection`、`run_arm_conditions`、`summarize`、`summarize_paired`逐字节不变。

| 检查 | 修正前 | 修正后与范围 |
|---|---|---|
| 两来源包名不同的原main反例 | 实际断言 `baseline-source.app != MyWallpaperX.app`，失败保留 | 原配对/单臂fixture消费真实传参，均断言统一名称 |
| 两最近Python模块 | 原9+19方法保留 | 增2个文件系统/非法leaf反例；30方法全通过，0失败/错误/跳过；四源前后哈希稳定 |
| 真实已签名原/候选App staging | 旧两臂沿用不同来源名 | 两份都落到 `MyWallpaperX.app`；各2569项文件/链接、相对exe、主SHA、原CDHash、前后strict签名及源不变核等；随后原owner清理 |

后两份真实staging只复制/核验，没有启动App或调用编译器；30方法是Python测试，不是30次App运行。新工具下的完整C0/C1/W0尚未取得清洁运行资格，本批没有Debug构建要求或新的产品性能结论。独立终审通过默认兼容、失败反例、原函数不变及上述证据边界。

最终helper SHA256 `fae8c55d6f90fd99f5f2fcdbd88a7e485239b75037e308d211068073ea018986`；startup SHA256 `400c1175d2fc763e3a11c85f412f385e397ab74016103258c7eba3e4e1a81025`。旧helper、驱动、协议、失败检查及native日志保持原字节；不改旧协议SHA绕过输入冻结，不追认旧D15/D16为清洁性能结果。

## 后继和保留

优先在统一运行包名、相同实际来源和无争用条件下前瞻验证准入；失败检查必须阻断派发。若差异仍在，再有界区分Process.run返回、物理hello交付与主队列接收。之后回原variant owner量cache读取/纯分析/当前eligibility，不把组合窗归给Voronoi或提前落完整内容缓存。D15局部输出及成本证据保留，D4资源残余、D7 seek失败、Web C1旧长尾和完整P2/P3/P7门不因本批工具通过而消失。

必要源、协议、红绿日志、污染对照原日志和独审提取到 `.artifacts/scene-evidence/runs/wallpaper-startup-d16-20261025-checkpoint/`。保护原因为未解前缀差异及污染对照须防止后人误认因果；实际载荷以manifest和sourceAliases为准，不放App/媒体/DerivedData。核验归档且无打开句柄后清本批结束的副本和运行目录，精确收据为任务顶层 `d16-cleanup-receipt.json`；连续任务仍保单一DerivedData、原App与D15同generation发布输入。未暂存、提交、推送或安装，goal继续活动。
