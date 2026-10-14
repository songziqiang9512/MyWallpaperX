<!-- document-role: historical-evidence -->

# Scene 原生属性列表与面板 CPU 收敛

> **历史证据 — 非现役入口**。截止2026-10-14。现役职责归[属性合同](../capabilities/runtime-input-property-coverage.md#op-user-overview)，下一批归[属性卡](../roadmap/properties-panel-card.md)、[性能卡](../roadmap/performance-convergence-card.md)与[队列](../roadmap/scene-open-breakpoint-queue.md)。本批不关闭长期Goal、整专项或整样本。

## 实施前设计


2026-10-13，实施前决定。本批目标是保留全部已投影定义与原编辑语义，退出SwiftUI lazy集合的滚动/布局职责，减少重复控件创建与无关更新。范围是Scene属性窗口；不重做Web编辑器、parser、property store、资源事务或engine更新，也不将本批当作本地化/未知类型/整专项验收。

**取舍。** SwiftUI局部修正仍依赖已复现的lazy AX故障owner；普通VStack已在同条件操作周期产生额外CPU工作。原NSTableView试验的完整AX查询反复实例化屏外控件/默认key loop，三轮CPU回退；公开row successor无效、复用Web Bool checkbox虽下降约15%仍回退约2倍，均未验收。2026-10-14实施前重排：自造AX代理会重复输入/可访问职责；保留NSTableView继续细化已收益不足；选仓库现用NSCollectionView单列可视项复用，系统管理可访问项和可视控件。保持全部投影定义、原面板玻璃/窗口身份与位置；不全量创建控件或缓存每个属性的NSView。系统原生控件负责键盘/鼠标/无障碍输入，现条件程序和标题归一化负责投影，避免新增条件语法或值存储。

**主链与唯一owner。** 已有prepared context → Scene editor NSView的不可变行描述/完整有效值投影 → NSCollectionView可见项 → 原service update/reset/texture事务 → 原store与typed frame/resource consumer。ScenePropertyWindowController直接挂载此NSView，删除本边界的hosting owner；共用PropertyPanel的presentation/关闭/焦点所有权不变，由原glass card显式选择填满属性窗口可用高度，其余inspector角色保持原布局。原Web滑块的mouse tracking控件提升为Workshop UI共享控件，原Web提交/去抖逻辑保留。

**更新。** 定义按context原序/索引保持行identity，标题、说明、尺寸及依赖在准备时投影。现WebDisplayConditionProgram决定显隐/Combo选项，所有有效值包括隐藏定义仍保留；改变依赖时只插删对应行并刷新受影响可见控件，普通值变化保原控件/第一响应者。service通知先比完整override快照，无关通知不重建UI；外部reset/资源结果读回现store，不保第二个真值。空选项、当前不可选值和现标签过滤语义保持。

原PropertyPanel的Tab/Shift-Tab仅委派当前挂载editor：按现行身份和作者行序滚动并聚焦下一控件，尊重系统full keyboard access；其他内容和窗口chrome走原responder chain。屏外目标按需实例化，不为key loop预建所有控件；关闭/替换移除委派。

相邻Web Combo的同标题不同值已复现被系统便利方法合并；只修原菜单构造，按typed option identity选择/提交，其他Web模型、控件提交与布局仍留原owner。

**事件与退出。** slider连续值、Bool、文本/颜色、Combo提交保持原public入口，不丢独立事件或改成仅结束时提交。编辑会话绑定原定义索引、editor与cell binding generation；同一行值更新保留控件、caret/marked text及mouse tracking。隐藏/复用前取消未提交输入并失效会话，已发出的值保留；reset先取消UI会话再调用原revision事务，迟到end-edit/tracking/色板动作不能写入新行或覆盖reset。复用单元解除旧colorWell的活动关系；选择图片使用原资源入口，异步sheet/结果以原窗口与editor身份拒绝已退出界面的迟到操作。已提交的资源事务仍由原service的revision/cancel/previous-current合同完成；接受回执必须更新资源就绪/文件名，即使override路径相等。关闭/替换释放订阅和行。旧SwiftUI Scene editor在该批一次撤权，不保双路产品flag；若功能或成本回退，修当前owner或撤回整批，不保隐藏fallback。

**验收。** 原生owner可执行测试涵盖各已支持kind、长标签/说明、重复标题而不同值Combo、条件显隐/选项、隐藏值、键/资源改名、相邻无关条件、连续编辑与通知、reset/迟到资源、关闭/替换与控件复用。真实293详细设置on的打开/正常滚动/AX端点/格式编辑、重开/reset，加未参与修法样本实际画面；三轮相同配置与操作对照记录App CPU、打开/滚动阶段与控件保留，不以AX可达或build代画面。首次/暖准备、媒体占位、engine GPU/温度与长期切换另验，不从UI成本推断。

**2026-10-14 后验取舍。** 完整AX查询周期CPU两次回退约2.4倍；采样定位到屏外行临时实例化后的默认key loop/布局，其中系统控件进入重复视觉准备。公开row successor试验仍命中原热点，撤销该试法，不靠自造AX代理或截断定义降低工作量。Web同款原生Bool checkbox试验也未达成本验收，现选择上文NSCollectionView唯一虚拟列表owner，退役table试验。文本编辑Tab/Backtab经原delegate调用唯一focus遍历，补真实命令及实机端点。

## 接受的实现

最终唯一列表owner是NSCollectionView，不保table试验或产品fallback flag。系统创建的item根视图保留，按kind复用一个实际子控件；没有每个定义的NSView缓存或自定义AX过滤。完整有效值和定义身份保在prepared context投影，只有可视控件参与布局。依赖插删按原定义索引更新、保原第一响应者与caret；屏外colorWell在didEndDisplaying及复用时退役。Tab目标按作者序按需实现，使用nearestHorizontalEdge滚动至上下边缘，缺失目标返回原窗口owner，不跳过合法字段。

原PropertyPanel与glass card继续拥有窗口/关闭/布局，显式填满属性可用高度，标题/副标题保持紧凑；其他inspector未选此模式。原Web滑块提升为共享tracking控件。Scene和相邻Web Combo改为显式菜单项，避免同标题不同typed值被系统便利接口合并；Web原option identity与提交逻辑保留。

## 同条件成本

普通App产品窗口，签名Debug -O；只读293副本、详细设置on、暖准备、无壁纸播放。三轮串行同操作：正常打开→完整AX读取→原生滚动三页并读取→回滚三页并读取→关闭并读取主窗口。App全进程rusage_info_v4 CPU使用Mach timebase 125/3换算，25ms取样，保每轮边界前后有效raw值；基线边界与修后边界均绑定实际操作。不同原生布局行高/AX树不等同，不比较相同像素ROI或全量枚举同数控件；完整定义仍可经系统滚动到达。

| 轮次 | 原SwiftUI基线 CPU ms | 最终Collection CPU ms |
|---|---:|---:|
| 1 | 1179.138917 | 436.915000 |
| 2 | 1221.710958 | 440.061417 |
| 3 | 1234.375208 | 415.679708 |
| 中位数 | 1221.710958 | 436.915000 |

未舍入ratio为0.3576255063，降低64.237449%；这是上述完整操作周期App CPU工作量，包含系统AX查询，不是打开/输入至呈现延迟、engine播放CPU、GPU、物理内存峰值、温度或能耗。工具操作耗时另保，不能当面板响应。修后每轮边界采样偏移0.894–28.663ms；raw区间完整可复算。

原NSTableView同操作中位数2974.882ms约2.4倍，撤销；额外分段轮再次回退。30秒主线程sample定位到AX屏外行实例化→默认key loop→控件布局；公开row successor试法未退出原热点。同Web checkbox的table候选降至2528.004ms但仍约2.07倍，也未验收。分段短窗口可能重叠采样，只作定位，不拿局部数抵销总回退。坐标滚动未实际移动的试跑、旧长空闲周期及失败构建均排除。最终采用既有Collection职责，无额外AX代理或截断定义。

## 行为与真实画面

可执行探针编译实际Scene/Web编辑器、原条件parser/归一化、窗口及glass card；store/dialog异步叶为spy。涵盖重复标签不同值、fractional连续slider、IME提交、条件改名/等价表达式与相邻不命中、200项非eager与真实reuse、屏外混合kind颜色退役、隐藏/reset/关闭后迟到事件、图片选择nonce一次消费及已提交service事务完成。焦点之后插删前面的行四次，原field editor/caret/值保留，后续输入仍提交原definition。原生named pasteboard拖放协议证一次颜色提交，不冒充真实OS鼠标拖拽。

普通键盘实机Clock1→Clock2的Tab和反向Shift-Tab已验。另在自己的NSApplication子类模拟公开full-access getter，actual窗口/列表探针证Bool→slider→text→color与首尾交还原window loop；AppKit原生chrome的canBecomeKeyView仍读取真实系统偏好，该探针不证明系统完整访问的chrome环。未修改用户系统偏好，此范围明确未验。

最终App SHA256 `031c011217fde5462564de5d115a3b3c636bf0b86b60a77679f70526a76579a7`，App/daemon PID61601/61606。正常App→client→daemon播放293，window27738：Clock1 `HH:mm`热改`HH:mm:ss`显示01:24:02，关闭重开保存，reset恢复无秒格式；同窗口、同一次startup。原生滚动条1到末项`[Old] Audio visualization`，0回首项，未复现旧SwiftUI端点崩溃；原自定义AXScrollToBottom已退出，不声称同名动作仍存在。

未参与修法的2134765860正常切换到window27761，房间/灯光/时钟仍有输出；Night Lights On关闭呈深蓝房间、灯光熄灭，再开恢复，未增加第三次startup。右侧灰色媒体占位仍开放，此轮无媒体条件下未见206/457异常，不能据此记修媒体来源/黑块。293替换与213退出分别41/31个VM owner全quiescent，failures/timers/jobs/mutations/dynamicLayers为0；退出码0且App/daemon/helper均消失。这是两次有界生命周期事实，未证长时间轻重切换缓存增长或资源峰值回落。

## 证据与收尾边界

本机证据位于`.artifacts/tmp/native-property-list-20261013/proof/`。raw、冻结、日志与reset图已封装为约2.43MiB的native-panel-proof归档，before/edited与独立房间on/off四图另存；首次计划登记的归档加四图及report总payload为21.842436MiB，但既有登记缓存1023.970MiB、无已到期包，promote因1GiB总限额拒绝；完整登记尚未完成，不冒称永久包已发布。未到期/保护或未知归属证据保留，本批唯一raw/画面暂留任务目录，容量可用时再沿原工具登记：同条件raw/边界、最终build/App/input identity、实际窗口及截图、原生探针与独审冻结清单。被拒绝试法只保必要成本和定位收据，不保多份staged App/重试缓存。继续迭代仅留当前App、只读测试副本与既有`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`缓存；最终清理清单另保。未知归属与其他批独有崩溃证据不清理。

独审先拒绝Table成本回退，再核Collection根视图、滚动轴、目标缺失、颜色退出与焦点身份。最终独审以同一source/diff/App/测量/运行身份为准。构建/探针不替代上述产品画面或成本；完整callback/cohort、颜色首ReferenceError、约8.634s云层重建、本地化、视频媒体入口、未知类型、HDR/SDR及多surface仍沿原队列，不记完成。


## 未知类型只读投影

2026-10-14后继修复定义在panel projection被静默过滤的问题：catalog仍拥有类型/标题，context仅把unsupported定义加入原条件闭包，Collection复用全宽只读行与标题净化；缺类型标明状态，纯图片/空标题回退“未命名属性”。不推断空类型是text，不新增控件/store/renderer。unknown-only也能打开；依赖控制器仍走原存储和更新，未知行不派发值或资源事件。reset按prepared中可编辑控件决定，不按engine consumer数量，避免控制器自隐藏后无恢复入口。

真实3147346398正常隔离产品面板显示四条缺类型定义，HDR作者说明可读、纯图片标题不暴露长键；滚动到底与关闭重开正常。独立2134765860原控件仍可操作，Night Lights On经面板1→0→1；同次播放首帧GPU完成，退出31个VM owner全quiescent。此正常UI App为`1d9d125282436dbcb5da3dcee5e4625151ca542df37aeb23b01f805fd9851ed6`，先于reset判定修正；只读呈现代码相同，条件自隐藏/reset另由真实native owner探针验证。该UI运行未截桌面像素，不把首帧日志当画面证据。

最近门覆盖改名类型/键、等价条件与相邻不命中、混合/纯未知、长/空/纯markup标题、键盘跳过与无未知写入。独审发现unknown条件引入controller而actionable为空时reset会消失，修后两组条件自隐藏→保存→重开空列表→reset恢复反例通过。只重验受影响owner；未重跑完整兼容矩阵。输入、原始失败/修订和分阶段收据位于`.artifacts/tmp/unsupported-property-panel-20261014/proof/`。这是定义可见性收益，无新增CPU/GPU/内存/能耗收益；本地化、媒体入口、运行类型缺口与其他旧视觉问题继续开放。

最终诊断App `86b320dfbd08f7c6620d62d25f706fb9c8b18f9090b34151698f4b3502a9d123`在独立Bunk短运行中保房间、灯光、时钟/日期真实输出；严格矩阵27项原FAIL与前驱完全一致，右侧媒体占位未修。该8s功能窗口不计稳态性能，正常面板交互与CLI画面分别记录。
