<!-- document-role: active-plan -->

# Scene 壁纸属性面板工作卡

本卡与[性能卡](performance-convergence-card.md)改善打开、滚动和编辑响应，追合法定义显示及热更新；复用原typed链，减少整场景重建。

**排查顺序。**

1. 用真实属性较多的壁纸复现打开/滚动/编辑卡顿，区分主线程解析、控件/布局重复创建、同步I/O、事件风暴与播放链争用；保样本、App与操作身份。
2. 追作者property定义→导入/归一化→面板模型→可见条件/本地化→控件→保存/事件→engine update，逐项记录在哪个责任首次丢失；未知类型须有明确状态，不能静默吞掉。
3. 按现有consumer能力分类更新影响：普通scalar/color/Bool/文字，资源替换，combo/拓扑或几何变化。只更新必要value/resource/variant/graph，保持跨surface事务及clock；需要结构重建的真实情况保留。
4. 核所有当前已出现类型的默认值、范围、选项、条件显隐、路径/媒体选择和作者标签；区别中文资源缺失、翻译映射、合法定义被过滤与实际功能缺口。

**首轮最小交付。** 定位并修复一个可复现的主线程热点或可避免的整场景重建，再核同类属性和独立壁纸。优先复用现property store、prepared model、typed frame/resource update及已有control，不增加另一套属性解析、缓存、通知或renderer。

**当前进度与下一轮。** 专项约25%（阶段估计）：条件投影和typed候选复用已闭局部重复成本，[图层引用/退休callable](../history/layer-reference-responsibility-convergence-2026-10-13.md)已修且304时钟恢复，未代表整面板收敛。云层编辑仍重建约8.634s；颜色callback首异常阻断cohort，先中性定位实际失败阶段，保全键校验，不删consumer。[原生捕获状态](../history/native-regexp-capture-2026-10-13.md)已恢复293双时钟与Clock1热切，格式等callback-only定义的面板准入仍待查。相同值保edit revision、pending取消及最新意图；setter/通知、detail observer、同步资源检查仍待量；callback-only、未知类型、本地化/媒体入口按真实consumer追缺口。

**验收。** 同条件记录打开/滚动/编辑响应与engine重建/资源更新事实，验证实际画面立即/下一帧变化、连续多次编辑、关闭重开及保存恢复。资源替换还须检查取消、缺失/坏资源与旧画面保留；条件显示、重置、依赖属性、脚本回调及多个surface保持一致。不能只断言未重建：值和事件必须真实到达consumer。

热更新与缺口按通用property语义修复，变量/属性键/资源改名和相邻不应命中反例加入验证；不按样本ID或固定作者键选择行为。测量面板响应时保播放与诊断条件一致，不以隐藏控件、丢定义、关闭特效或合并应独立的事件换顺滑。

**职责与退出。** AppKit控件/布局、导入模型、property store与Scene engine各修最早失败owner；跨职责重要策略先修对应设计。每批独审、提交并汇报画面/交互收益、受益类型、当前专项进度与下一项。已完成记录归history，未执行定义/type问题留本卡或原队列，不复制两套状态；用户结束专项或已证类型与交互矩阵闭合后退役。
