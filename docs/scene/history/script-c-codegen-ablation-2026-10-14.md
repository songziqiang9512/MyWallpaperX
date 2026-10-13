<!-- document-role: historical-evidence -->

# SceneScript C代码生成消融（2026-10-14）

> **历史证据 — 非现役入口**。当前执行归[性能卡](../roadmap/performance-convergence-card.md)，方法归[工作流](../development/development-workflow.md)。本轮撤回C优化候选，不关闭CPU、温度、GPU、HDR或其他视觉问题。

修正测量语义：Debug只设置Swift `-O`时，C/QuickJS仍为`-O0`。031 App的三轮GPU p95为42.922/42.775/42.972ms，进程CPU为68040.044/67320.098/67836.945ms；这些仍是该诊断配置的有效记录，不能用其热点或与新配置的差值宣称正式Release收益。正式Release的实际C response为`-Os`，Swift为`-O`。

独立5秒sample在单独进程采集，不并入性能对照。主线程2007 samples中，逐分支汇总的engine bind为330、layer handle构造200、scriptProperties解析/赋值122、snapshot publication84；包含关系不能相加换算整进程收益。owner宿主安装只在创建时执行，没有重复整套安装。查名本身占比小；fresh对象、own descriptor、绑定getter及每callback属性重置有可观察语义，未改成共享句柄或跳过赋值。后续应在优化配置重新定位，而非依据旧`-O0`比例重构。

## 同条件消融与退出

先三轮`-Os`，后在App target Release临时设置`-O3`、三轮候选，最后用原冻结`-Os` App返回基线。两臂为Release配置、Swift `DEBUG`与`-O`，保诊断入口；不是无`DEBUG`的正式Release验收。实际仅24个C对象重编译，Swift沿用原对象；20个自有SceneQuickJS host和4个QuickJSNG来源不变，无C++，未加入fast-math/LTO、改ABI或复制算法。App target的候选设置已撤回，Debug仍保`0`、Release保原`-Os`。

同3662790108隔离副本、默认属性、3024×1964单surface、60fps请求、固定静音、execution observations关闭；每次新HOME/engine cache，OS文件cache暖，warmup30s，测量约62.5s。准入计划仍为935个脚本target；layer517/effect0/pass0的`[P1] Data`仍报读取undefined的`p1_longNode` TypeError并局部fallback，成因待查，未吞掉或记作已修。

| 运行 | 进程CPU（ms） | CPU/完成帧（ms） | CPU/elapsed（核） | 完成FPS | GPU p95（ms） | ready（ms） |
|---|---:|---:|---:|---:|---:|---:|
| Os 1 | 70131.378 | 54.705 | 1.121743 | 20.505 | 61.466 | 23595.681 |
| Os 2 | 69895.225 | 54.182 | 1.118127 | 20.636 | 50.705 | 23990.676 |
| Os 3 | 69678.220 | 55.698 | 1.114210 | 20.005 | 62.447 | 23457.330 |
| O3 1 | 69950.191 | 51.700 | 1.118917 | 21.643 | 51.580 | 23057.131 |
| O3 2 | 69872.641 | 52.774 | 1.117676 | 21.179 | 51.808 | 23719.503 |
| O3 3 | 69726.146 | 55.470 | 1.117084 | 20.138 | 62.708 | 23784.151 |

每帧3次texture copy、52,810,688字节，2次framebuffer capture、5,297,600字节；53个offscreen pass、27个resolved-material pass和23个graph source capture一致。有限计数窗口下main/depth约37.5/6.5，均值差不足0.001；其余列出的每帧计数一致。

O3中位每帧CPU较低，但第三轮接近原基线，CPU速率未下降，GPU跨轮波动也较大。返回Os每帧CPU为53.671ms、CPU速率1.116793核；差异未稳定复现。O3 ready中位23719.503ms，Os为23595.681ms；不记启动、内存、GPU、能耗或降温达成。候选Mach-O增加365,760字节、`__text`增加349,560字节，不为不确定收益保留配置扩张。[Clang说明](https://clang.llvm.org/docs/CommandGuide/clang.html#code-generation-options)亦区分速度优化与代码体积取舍。

## 验证与边界

真实现役VM门在记录的`-O3` clang argv上执行：OOM/构造清理、强制GC、fresh reference/own descriptor/detached accessor、跨owner及退役权限、timer/job、snapshot rollback、初始配置深拷贝、数值/Unicode/正则均保持。7模块9测试通过，43条实际clang命令及输出SHA保留；不是把硬编码`-O0`的原门冒称O3。产品候选已撤回，因此未进行正式O3 Release普通入口/heldout交付，也不宣称完整兼容。此前属性面板成果与现役视觉队列保留。

证据暂存`.artifacts/tmp/hdr-export-convergence-20261014/proof`，核心为`c-codegen-comparison.json`、各report、编译参数、App/source身份、native日志和独审；Os App SHA为`40dc7426a73e5b8ba9881910fb5f4d898586295d688c129c03379ab3229dd2b8`，O3为`532bc0e30e20fb43b0b86ba852df54a61a0a9216c2e414d821ff1ca9af33be2d`。必要证据保留；本轮停止使用的候选App、HOME、shader导出与重试副本按精确清单清理，一份现役构建cache与Os冻结基线供下一批复用，正式runs晋升仍受现有容量限制。

下一项按收益重排为HDR终端复制：early independent scratch即使准入成功也可能挤掉原本能工作的group/source/capture/Bloom，原终端可等读者退出后借group scratch；graph preflight不覆盖全部强制资源，故reserve失败才fallback不足以保旧画面，该方案未实施；公开Metal attachment输入与现逐像素映射有静态可行性，仍须先设计、GPU像素/失败、可比实际成本与正常产品入口验证。CPU属性解析模板、snapshot staging容量复用及长期轻重切换继续开放，不围绕编译级别惯性细化。
