# 主界面 Q01–Q09 与 P01–P05 前轮实现与验证记录 · 2026-10-26

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**
> 保存本轮八项调整之前的候选实现、验证和边界，不代表用户最终验收；当前标准见[唯一方案](../../development/main-window-playlists-redesign.md#inspector-playback-appearance-round)。

<!-- preserved-body:start -->
<a id="user-ui-revision-nine"></a>
## 16. 当前九项用户实测修正（Q01–Q09）

本节覆盖与§15冲突的视觉/模态/计数目标。当前为已授权实施，逐卡记录实现与验证；按本节末条件提交/合并，按真实事件及帧验证，Root串行构建/原生门，保留并行后端hunk。图片只作现象与比例参考，不含额外指令。

| 工作卡 / 用户项 | 最小结果与职责 | 验证及状态 |
|---|---|---|
| Q01 / 1及补充2 | 全部本地页面卡片可拖到侧栏自建列表快速添加；拖动唯一用途为copy关系，不做媒体卡内部排序，目录/侧栏列表排序另保留 | 用户最新裁决替换原成员拖排目标；Grid/Composition/Store无消费者成员重排链及专属整理入口已退出，保native source、单卡选择、跨类型/filter/readonly/reset/取消；continuous/topology及Store/Controller/Query/Commands近门通过，Sidebar原生71项通过（q1/menu-sidebar-10），整App物理拖到侧栏快加待用户试用 |
| Q02 / 1、2 | 所有媒体卡拖图不采出空黑glass bar；取消/失败回原位不清图、不detach/reload导致闪烁。共用最小拖图/原生归位规则 | 已发现原outlet拖图超出卡框，现共用原缩略图裁切，四来源真实卡片原生回归均通过（q1/local-cards-core-2/3）；只采原已显示缩略图；侧栏添加一次关系、取消零写；不造焦点补丁 |
| Q03 / 3 | 目录进入列表的右侧首位独立返回按钮可真实点击返回，保目录查询/UUID锚点 | 已修真实按钮target/action冲突，NSButton/overflow原生门通过（q1/back-fixed-1），Q09-ui-check-1及Q11整App实际按钮点击均已返回目录；不仅直接factory；侧栏/删除/reset撤旧上下文 |
| Q04 / 4 | Editor显著紧凑，去固定大底部空白；约340–360宽、内容驱动高度、封面约96–112、描述约56–64，错误仍完整可见 | 已实现360宽/112图/内容高度，Editor原生49项通过（q1/panels-3/0），Q11整App已实看紧凑布局；真实fitting/长中文/emoji/错误/保存中/最小屏幕，控件不裁，取消不写 |
| Q05 / 5 | 所有播放列表目录原生让位连续动画，取消/成功结算稳定；减少动态效果遵系统 | 3–6列真实forward/cancel中间呈现帧、原185交互/锚点/事务与ReduceMotion均通过；willDisplay漏末卡需求已改viewport原生layout属性，独审及同一严格initial demand门通过（q1/final-native-12/0）；无全库scan或新timer |
| Q06 / 6 | Editor/Picker/SteamLogin共享清透玻璃，去不透明window/root及重复灰层；主窗禁鼠标/滚动/键盘，禁灰色遮罩。仅模态焦点/输入域及原生AX语义，不暂停现播放 | owned child+单一输入域已实现，Editor49/Picker/Steam13/菜单27及原生模态门通过；Steam主窗不可拖。Esc真关闭后不复用死panel，原文本/held域断言全保；Header/Chrome UI桥已复用原输入域，Shared声明/退出原生AX modal；保留按钮/真实事件队列的严格效果回归已通过（q1/chrome-native-queue-17），不按程序内performClick推演给每个业务闭包增加guard；物理wheel与整App材质待验；公开原生呈现优先，原sheet若系统强制dim则用受控原生modal/child方案，不能私有KVC/global event tap/轮询抢焦点；嵌套面板/host关闭/reset/迟到回执覆盖 |
| Q07 / 7 | Sidebar按Music截图统一22 pt槽/封面、实际30 pt行高，SF和字体沿真实挂载的native source list比例；所有列表用3×3符号 | 已退出无效手配20/global font，独立挂载native基线的符号/字体语义及实际rowRect30原生71项通过（q1/menu-sidebar-10）；保长名/中性选中/AX，Q11整App已实看比例，用户最终审美验收保留 |
| Q08 / 8 | 头部随机/播放/添加同一实际高度、胶囊背景；只有播放带文字 | 三按钮原生flexiblePush/28pt，去冗余等高约束；legacy127项及指定frame的非空bezel主体边缘通过。原生玻璃alpha约.078，按峰值平台测；旧push同指定frame也画同高，oracle不冒充整Button实看；Q11整App已实看三按钮同高，自建计数标题后小字 |
| Q09 / 9及补充1、3、4 | 在线浏览不显示下拉计数；目录封面下名称左/数量小字右同一排；自建列表Header标题后小字计数、不下拉。其他本地资料库/最近/喜爱计数仍仅原生下拉显示 | 在线pull专属桥接/空Grid及孤儿测试已退；目录同行计数、playlist清前页pull、local count readiness/partial及原GridScroll11项均通过；不做备用展示，物理下拉待用户实测，原safe inset/锚点/分页/模态/AX不变 |

执行先修Q01/Q02/Q03，再合Q04–Q08及共享Q09，交叉审查后运行最近门和必要增量Debug并实看；每卡完成即更新此表。三面板无灰模态若需改变原beginSheet合同，先在本节补唯一呈现/退出/嵌套设计，测试不得将旧sheetParent正例直接删掉而无等价原生阻断反例。Q09不建立第二计数/分页/选择owner，背景模态中不得接受pull输入；回弹不得持久化负scroll anchor。全部修正交付用户后停，不自动开始新的引擎或性能专项。

Q06实施设计：原Shared呈现职责统一一次owned child panel及本地输入monitor，公开parent/child关系唯一判域，不建全局registry；只初次makeKey。退出先撤嵌套sheet/QR子窗、child及monitor，再原owner一次收尾；主host鼠标/scroll/key/hover新事件拦截，合法panel descendants可输入，held动作继续执行时核同一permitsInput；host关闭/reset清理不套新输入guard。三者玻璃只保regular及边框，取消整片填色，a11y回退保系统底色；详情不连带改。Editor改360宽/112图/60描述，去spacer与520硬下限，错误按需完整可滚，不裁正文。

Q09实施设计：共享ScrollView以现clip bounds及scroll phase计算顶部真实overscroll，只在空隙画非命中label；不改document尺寸/insets/bounds/anchor，不添回弹timer。仅本地资料库/最近/喜爱/目录总数使用pull；目录每卡原Query成员数右对齐显示，自建playlistHeader同一行标题后小字展示其现完整成员数，二者不用下拉替代。在线浏览完全退出pull计数及专属wrapper/空Grid需求，原服务器分页/空提示/CTA照旧，不为计数扩Core owner。资料库依完整来源readiness，partial只称已加载；关系页以Query完整canonical成员数，不强等source；未知不冒充全库0。用户明确不做备用显示；CUA phase0不代表实际鼠标/触控板，不能据其gap0加覆盖首卡浮层。Q06补充：Steam登录Panel保持原焦点和关闭生命周期，isMovable及isMovableByWindowBackground均false，不新增全局输入拦截。

<a id="user-ui-feedback-round"></a>
## 17. 深浅外观与操作反馈（P01–P05）

| 工作卡 | 用户操作后的标准结果 / 唯一职责 | 当前状态与最近验证 |
|---|---|---|
| P01 外观 | 浅/深切换后玻璃bar标题、按钮、placeholder/边框及相邻自绘语义色立即可读；CGColor在实际view的effectiveAppearance解析，图片上固定深底白字保持配对，不强制dark或重建资源 | 实现及近门通过；真实CATextLayer与字形像素覆盖冷启动/深浅往返、自定义文字色和原缓存；placeholder/三类Footer及四来源生命周期通过，整App实看另记 |
| P02 播放反馈 | 任一本地/已下载卡点击→现Sequence/transaction准入即沙漏→真实提交后停止；失败恢复、Stop清状态、旧回包不改新目标；旧正在显示卡仍可准确停止，pending同卡不重复启动，在线未下载仍下载 | 实现及近门通过；真实dispatch前同步发布、16类型组合/失败/Stop/旧回包及Scene删除ACK前撤沙漏；Adapter、真实Video/SIL/Pixabay/Steam卡及18项生命周期方法通过，桌面输出不据fixture冒称 |
| P03 系统确认 | 删除等二次确认由NSAlert原生玻璃/布局负责；保checkbox默认off、取消零写、原响应/嵌套/host关闭/一次completion，退出整套自绘owner；Editor/Picker不替换 | 实现；原生按钮/窗口、完整信息/checkbox/Help、Esc和Return安全响应、嵌套输入/宿主关闭/无host模态的实际门通过（native-alert-final-15）；非首取消用原keyEquivalent，首安全或单按钮仅alert生命期的裸Esc桥保原Return，不改布局/抢焦点 |
| P04 多选收尾 | 添加到既有/新列表、移除、收藏等全成功后只结束原操作的多选；取消/全失败保持，partial删除保失败项及提示；切页/重选/reset后旧完成不清新意图，复用原selection receipt和Store结果 | 实现及近门通过；真实Commands/Presentation/PlaylistActions与SQLite事务、写失败/部分删除/重选切页reset/UndoRedo；Editor草稿与文件transport保受控边界 |
| P05 链路交审 | 每项按点击→准入→异步→持久/播放结算→可见反馈→再次操作检查；覆盖别名/切页/取消/失败/partial/Undo/重试，修实际可达错反馈，保状态栏新接线与原功能 | 独立子代理交审已修可达反馈遗漏；重复颜色writer、Pixabay进度覆盖小时钟/Stop及源Apply绕CoreStop均已收口；状态栏Panel/Icon与来源播放/工作区/导入近门通过，原断言保留 |

实现边界：Core仍只有现播放Sequence/事务真值，UI新增仅只读pending投影与准入/结算通知，不设UI倒计时/重复播放状态机。Shared确认只委托公开NSAlert，原业务命令不迁到窗口；选择完成收口仍由Presentation原票据判归属。验收包含light/dark原生像素/切换、准入前后同票据与失败反例、确认取消/checkbox、全成功/partial/迟到完成；本轮近门/失败证据和构建收据保留于ignored `.artifacts/ui-feedback-20261026/`；Debug增量构建175秒、签名通过且4375产品输入稳定，沿用唯一缓存 `/private/tmp/mwx-main-window-ui-debug-4hopmbb7/DerivedData`，已启动隔离W21试用配置，用户正在操作，未重启或接管。真实AX已见原生删除确认及默认off源文件选项；深浅外观以原生字形门验证，未切系统外观。Scene依赖门仅报主仓既有stale admission edge（源/脚本/基线均与8f71545d8一致），非本轮新增；不冒称全仓所有门通过。全部未暂存/提交，原分支保留8f71545d8。
<!-- preserved-body:end -->
