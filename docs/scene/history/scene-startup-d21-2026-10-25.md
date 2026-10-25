# Scene 启动 D21：外部启动采样资格停止

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-25；后继归[启动专项](../../development/wallpaper-startup-optimization-plan.md)。本批未修改产品或测试、未重建App；外部采样失败，没有新的提速、启动栈或原因结论。

## 一次采集与失败

D20将主要父观察等待缩至start返回→hello。D21复用实际D20 App `7304834e…4ef9`、CDHash `f15987d3…6ed2`、UUID `403D03AB-A41D-32EF-B1E3-BCBFD65F3534`，原编译source-map `aafc5637…f635`/5950输入；本轮开始live5951仅多D20后续文档，产品/原helper均未变。Debug get-task-allow为true；同实际binary的read-only debug-map有1153个原对象记录且均存在，没有为此生成dSYM或构建。31,009,787B原debug-map输出经完整往返SHA验证压成3,214,463B保留。

本机man/help与App Launch `--show-recording-options`通过，后者未录制；不把配置可读当实际采样可用。沿原四helper和core.main/计时/隔离/清理，只包原第2次C1：notifyutil在PTY准确输出K0证明注册，xctrace的真实tracing-started通知K及watcher exit0后才调用原C1，无sleep就绪。ready合计15s、5s全进程record、C1返回后的record+TOC收尾合计30s，均在执行前冻结。driver `bccab1b0…83ff`、recorder `241a7d96…af01`、protocol `8b4930a8…079`；独审通过后唯一一次执行，按原流程实际完成C0/C1共2App/2请求，未额外增加App/request或取值owner。

与另一独立工作树仅协调同机实测短窗；对方root+三agent回执静态，读实际字段后执行。readiness约2.461s成功，C0与C1原App完成。xctrace打印5s到期、Recording completed/Saving，另警告请求1ms与配置10ms采样期不同；它未在原30s收尾界限退出，原finally仅针对本次notify/xctrace句柄终止，record PID88974最终-9。整次窗口42.779s，结束即明确释放对方，未执行W0或重采。45个1s/边界快照无观测foreign/error，不证明整host/亚秒空闲。

C0有完整原run结果，正常退出/owned children0并通过。C1原run_selection确已返回passed=true：冻结控制流在recorder.finish前require该值，实际traceback由finish超时；另有native完整source/ticket/request/execution、presented及parent finalize。parent88982/daemon88986，entry→acceptedObserved633.811ms、presented1026.607ms、finalize1027.658ms，仅为带扰动原点。C1完整返回dict没有在wrapper异常前写入外层runs；failure.runs仅C0、无最终report.json。故只报这两个有限事实，不称整组3App/4请求或完整C1返回记录验收，也不与D19/D20作A/B。

## 停止依据与清理边界

原失败trace仅 `Trace1.run/RunIssues.storedata` 40,960B，无打开句柄，未保留采样流。对独立副本一次只读TOC导出exit10：`Document Missing Template Error`，无TOC。没有对原trace修复、续录、放宽超时或换直启child；原recorderMechanicalPassed=false不改。现成模板全进程target及通知已实证可启动，可靠收尾/数据可用仍失败，无法从空栈推断dyld/AppKit/Metal/IPC耗时。后继按原P0转最小DEBUG子入口值点；物理hello与完整P2/P3/P7、旧seek/Web边界继续开放。

原run_arm_conditions因wrapper抛出且无startup_cleanup而保守保留suite/runtime/staged App，不表示检测到App还活。Root在确认精确自有App/child/recorder退出后，按原helper清独立suite及仅Startup标准域，并以本次token归属防误删后继。首次额外核验过严要求defaults export必须报域不存在；实为已清后的空plist/exit0，随后按原core相同的空值语义核实，无第二次删除或生产域恢复。生产偏好指纹在原执行与单独cleanup前后均不变。原failure报告的retained标记保原样，实际后清理另有收据，不改写原点。

必要raw输出、native/失败、通知/协议/工具身份、40KiB失败原件及副本导出错误、完整压缩debug-map和独审归本机 `.artifacts/scene-evidence/runs/wallpaper-startup-scene-d21-20261025-checkpoint/`。产品来源与源重建引用已核的D20保护包，不重复保存全App/媒体/构建源；归档核验后只清本轮已停止且无句柄的runtime/staged App、执行/副本/采集环境，保一份任务DerivedData及既有必要实际App/同代输入。未暂存、未提交、未推送，goal活动。
