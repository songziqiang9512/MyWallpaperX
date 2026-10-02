<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# D1 composition 采集范围的首轮实验（2026-10-02）

> **历史证据 — 非现役入口**。当前权威：[D1 设计](../../scene/design/composition-render-target-design.md)、[实施路线](../../scene/scene-compatibility-roadmap.md)、[资料来源索引](../../scene/semantics/source-index.md)。本轮没有得出官方采集范围结论，也没有修改 D1 产品代码。

## 我方真实 CPU 反例

基线 `03ba383c` 附近，用101份实际 Swift 产品源码编译 parser/model builder→descriptor→source route→world transform探针，外部无关 graph/VM/MDL 叶节点使用既有测试 stub；没有创建GPU设备或执行capture。仅给A20/B40添加parent10，固定顺序 `[R10,A20,X30,B40]`、composition类型、两个utility flag=false、effects为空；真实世界矩阵和其余输入均相同。

无parent时实际结果为trigger10、isolated=false、members空；加parent后为trigger40、isolated=true、members=[20,40]，非child X30被排除。exit0，含编译56.614496s。它证明当前source选择和触发位置由parent改变，不能证明哪一种符合官方，也不能把无effect的计划结果当作实际capture成功。

本机记录 `/private/tmp/mwx-d1-next/parent-probe/` 保存源码/输入hash、swiftc完整命令、输出与世界矩阵。二进制SHA256：`cb438504e6f87200812ba9f0e630dd61bfc6a5cb821a82fb31c17866c1742318`。以该冻结输入/源码为身份，不把后续产品修改冒称已由本探针验证。

## 官方黑盒实际做到哪里

核实运行环境为 Wallpaper Engine UI 2.8.42（PE 2.8.0.42），Windows11 ARM64 10.0.26200（OS补丁revision未核），Parallels WDDM 20.18.2633.57507。官方wallpaper32.exe SHA256为 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`，wallpaperui.exe为 `dab38bfc017dd5fd4947a09706d23f27833870d1bbb87485677a3e67d1d55791`。只使用GUI/公开CLI和自写输入，不读取私有shader/模型实现。

GUI成功保存自有800×600 Scene，创建真实“可调整组合层”。最后保存输入version5、对象顺序B17/C19/R24，parent均省略；C引用`models/util/composelayer.json`，origin400,300,0，size512,512，Tint effect25的作者参数为alpha1、color0 1 0、visible=true。最终own scene SHA256为 `a42d161e4ed503d283601f53970902301a8fc3040aa2a27b6bf043ebe9bcea8b`。这里只保存作者字段/引用，不打开被引用的官方资源。

实验记录报告GUI的copybackground复选框默认勾选，而作者scene省略该字段；没有执行off/on保存对照，不能据此决定缺省值。我方parser缺省false是独立代码事实，应在后续用字段变化和实际输出共同核实。

预登记V0=[B,C,R]、V1=[B,R,C]、V2同V1但Tint关闭，目标是在已确认加载相同自有输入和viewport后，用效果启闭的颜色差异建立正控制，再改parent/order。实际V0/V1窗口曾启动并截图，未取得有效Tint启闭正控制，最后GUI拖拽也未改变保存层序。故不能用红色截图判“非child不采集”、认定缺省copybackground、选择隔离target，或宣称官方场景不支持该能力。颜色管理、内容注册与backend控制也不足以关闭数值parity。

## 收口与下一可执行动作

本机证据根 `/private/tmp/mwx-d1-blackbox/`，包括研究卡、实际身份、自有输入/作者字段、截图及未成功的尝试。`final-manifest.json` SHA256为 `5122b3ee1b159478a8acfe1834dc304d22e0135cfaaf407e9173774345261968`。研究代理两次模型容量错误中断后，主线程只读保存own最终scene，正常ACPI关机并确认本任务启动的VM为stopped；没有强停或删除现场。GUI操作恢复依赖双击，prl屏幕捕获曾返回全黑，随后使用已有授权的宿主捕获；这类工具/可观察性限制不等于官方行为结论。

本轮后的用户指示强调积极提取参考项目中性行为并自行实现算法。后继先复核已研究的reference层序、group camera/target与生命周期证据，能定合同者直接转自有反例/实现，不把官方像素golden设为全部开发的前置。仅对仍不能定案的成员/flag分支，先在一个已可见自有image建立公开颜色效果启闭正控制，再在composition确认同一信号、加载身份与viewport注册，之后做parent/order和copybackground单变量。无正控制时不要重复同一红图实验或扩大组合解释。D1继续保持blocked-pending-design，旧parent隔离假设不恢复；选择独立可推进的显式粒子发射作为后继，不宣称该能力已经实现；其次序由现役路线维护。
