<!-- document-role: historical-evidence -->
# U40 连续 Puppet 拖动：fresh 资格与候选 API 缺口

> **历史证据 — 非现役入口**。截止：2026-10-16。记录仍在进行的资格与候选依赖定位，没有交互修复、官方冲量语义或完整样本通过结论。

当前状态与后继归[断点队列](../roadmap/scene-open-breakpoint-queue.md)，属性专项归[工作卡](../roadmap/properties-panel-card.md)，执行边界归[兼容路线](../roadmap/scene-compatibility-roadmap.md)。

## 问题与资格范围

3749463715 的用户报告为胸部拖动只首次有效，第二次及后续失效。
本轮先证明首轮选骨、持续按住、实际骨写与GPU几何响应，再用同一输入重复三轮。
不从短gesture、事件日志或单张人物图推断骨骼功能；不按样本或骨号增加可见算法。
只消费中性metadata、typed结果与Root实际图像观察，不读取作者表达或私有实现。

既有DEBUG pointer schedule新增可登记的press/held/between时间，保持原触发入口。
单次selected骨origin投影仅用于选择起点，输出layer-render NDC、finite/inViewport等数值事实。
它投影已发布pose且零pointer parallax，不能替代实际hit与骨写资格，也不改变产品交互语义。
新增工具与测试是取证能力，不是U40修复。

## 有效受控三轮

同一Session、同NDC起点`(-0.260381,-0.347046)`到终点`(-0.180381,-0.347046)`。
计划press=1s、held=2s、between=6s，每轮同方向/幅度/持有窗口；不比较随机手势。
最终Debug build exit0，23.565s，工具/测试输入drift=[]。
受控运行PID43970，exit0、40.101302s、ready、timedOut=false、reaped=true、inputDrift=[]，停止GPU drained。
Root实际查看三张held图，再结合typed GPU回执判定，不以截图文件存在代替观看。

| 窗口 | layer598实际结果 | 邻居与边界 |
|---|---|---|
| 第1轮按住 | 21条GPU completed均scriptWritten；21个geometry hash，revision1→160 | cursorDown/Up都到达；首轮持续骨响应已资格 |
| 第1轮释放之后 | visibility owner报code=exception，TypeError:not a function | 保异常事实，不能以空操作隐藏缺口 |
| 第2轮 | 首次事件报code=disabled，无598 cursor callback/骨写；21条记录只有1个geometry hash、revision285固定 | 562仍收到down/up，不能据此认定全局pointer失效 |
| 第3轮 | 无598 cursor callback/骨写；22条记录只有1个geometry hash、revision285固定 | 562继续收到down/up；未证明其全部物理行为 |

该结果fresh复现“首轮有效、释放后后续失效”，并把异常/disable与骨几何停止对应起来。
这是受控override入口证据，不等于原生OS拖放或固定官方行为已一致。

## 未取得资格的 native 尝试

native-attempt-1 的Library窗口改变了交互上下文。
native-attempt-2 的短down/up被同帧合并，没有首轮scriptWritten骨响应。
两次都不计native功能成功，也不用于决定capture或physics算法；不为凑重复轮数追加无资格运行。

## 候选依赖与待定合同

最终中性AST报告确认两层各有独立4331B wrapper，回调形态均含update/down/up/init；各一处`applyBonePhysicsImpulse`调用为两参`[Number,Vec3]`，现役host注册缺该API，其他投影公共依赖有定义。
这是与异常时序相符的候选API依赖缺口，与队列既有impulse/angular未知项相接；尚未动态调用归因，不能写成已确证该call导致异常。
只有真实API按已证合同实施后同输入恢复，才能进一步直接验证因果；本文不引用作者片段或未净化runtime载荷。
省略angular对显式0的官方Q1资格进行中，尚无经审结果；default、direction空间及实际冲量响应仍unknown。
禁止no-op、猜default或削减异常fuse把后续callback恢复包装为物理修复。

最小后继是有区分力的省略/显式参数正反对照；取得合同后才决定现役host与motion消费的最小改动。
如果仍不能证明非零冲量/姿态结果，保unknown并停止该实现分支；不得只用有效handle、零错误或位置跳变验收。
修复后的原样三轮持续响应、释放后继续更新、健康邻居与原生入口仍需重新验收。
本轮不关闭N06、N08、其他Puppet profile、整样本视觉、物理多屏或性能专项。

## 证据与保留

忽略根`.artifacts/tmp/u40-drag-qualification-20261016/`保资格计划、构建身份与中性投影。
`controlled-repeated-drag/neutral-projection.json` SHA为`45565f4d095520a4a409ae343c8dee661d679748f6162a675771c05ca1520a1b`。
`neutral-failures.json`位于同一controlled目录；骨origin资格见`bone-origin-qualification/neutral-bone-origins.json`。
最终中性API projection SHA为`15cbbe780ef729c015d809336063229afdd5f40695fe6e8037f9b7d1c75f0dd5`，receipt SHA为`16cc240a8a6a13c98f763142751150f7dbb7ccb758e6205c7f6f8a03e26486a8`。
`cleanup.json`保留controlled三张held及一张released PNG，共30,791,766B；native/pose无资格及重复PNG已删，必要日志gzip、中性投影与执行receipt保留。
本次清10个file/65,399,845B；前轮native-cleanup另记344项/948,068,524B，分列为磁盘产物清理，不计内存或性能收益。owned App=[]且GPU drained；原374 project/pkg重核sourceDrift=[]。
同根`sample/3749463715`只读副本及`home`保留供后继opaque seed/修后同环境复验；唯一DerivedData仍为`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`。
全局promotion预算拒绝条件未变、未重试，未知证据未删；官方VM按用户要求保持运行，Q1资格尚无经审结果，不将环境保留或未完成研究算修复。
真实用户媒体只读；U41既有提交`b132add7`不作为U40修复；提交、推送与发布状态由root另行汇报。
