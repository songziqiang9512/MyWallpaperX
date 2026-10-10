> **历史证据 — 非现役入口**。当前任务从[断点队列](../roadmap/scene-open-breakpoint-queue.md)继续。

# 命名 Timeline 与鼠标脚本定时器（2026-10-10）

固定基线 `3c365d4d`。当前待办只由[断点队列](../roadmap/scene-open-breakpoint-queue.md)维护；能力范围见[API台账](../capabilities/scenescript-api-coverage.md)，设计见[组件API设计](../roadmap/batch2/script-component-api-design.md)。本记录不是全样本或发布验收。

## 首断点与实现

U22（3805547608）右上角点击命中104/118后，作者分别调用其他层93/58的 `getAnimation("789"/"7899").play()`，1.5秒定时器再pause。基线只有当前property的无参数入口，实际报TypeError。两条都是已编译的start-paused alpha Timeline，复用原播放状态即可，不需要媒体切换器或新动画算法。

保留 `options.name`，launch从已编译Program投影 `(target,name)`；同domain配置只读索引。layer/text所属的命名属性动画由同一QuickJS handle/journal产生typed目标，经过原owner bundle、固定点准入、Timeline preview和共同commit。current无参数入口保留；同层重名、缺名、已删除、动态clone和错误owner/generation拒绝。索引不会按样本、资源路径或截图选择。目标删除沿原下一cadence生效合同，不根据候选删除提前拒绝整owner。

首轮实际点击已提交play，但1.5秒后pause被 `Boolean value owner produced out-of-cohort mutations` 拒绝：该样本用借用的stateful Bool owner，timer已到期，失败发生在Swift权限检查。现在已有stateful副作用权限允许typed Timeline命令；纯只读Bool与material function边界保持。测试还发现作者捕获第17条动画命令异常时，reader会返回前16条；现沿原overflow标记拒绝整批。

另一个自有VM反例证明，独立cursor-only owner可在事件中创建timer，却没有后续tick。CursorProgram仅为自己持有且有active timer的owner，在事件前调用已有evaluation，将副作用并入原bundle；不发布虚构值、不新增clock，借用owner继续由原value Program推进。构造仍拒需要init/update的独立owner。raw pointer overflow只抑制不完整输入，不冻结独立timer。snapshot测试仅证明显式helper restore，不证明普通FrameDriver会因GPU丢帧重放VM；现役cadence消费合同不变。

公开行为依据：[ILayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ILayer.html)、[IThisPropertyObject](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IThisPropertyObject.html)、[IAnimation](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IAnimation.html)。只读取公开API与作者数据，未消费参考项目私有实现。本批不覆盖effect/material命名范围、metadata/rate/seek、动态clone的Timeline生成及完整官方时序。

## 验证边界

- 真实C/QuickJS及ASan：同名异层、retained getter/handle、timer、current兼容、缺名/歧义、generation/销毁、clone、纯只读Bool和捕获溢出。
- Swift typed桥：init/update/cursor目标一致、失败evaluation不发布、healthy peer、捕获溢出，以及stateful Bool的click→timer pause。Timeline compiler/runtime原门保留。
- 独立cursor门：无pointer输入仍到期、timer→click顺序、raw overflow、显式snapshot restore、失败owner与健康peer、借用owner不双跑、闲置无VM工作、init/update准入不放宽。
- 最终Debug build成功；U22受控14秒点击后，两条alpha命令同帧提交，1.508秒后pause保持在93≈0.99997、58≈0.49999，12秒截图仍为切换后背景。原App普通指针输入的100秒窗口记录三次有效切换：到45帧保持、再到90帧回零、再次到45帧保持；同一window/surface，没有重建。该窗口其他输入来源未完全隔离，不把所有点击归因于自动化。最终GPU完成5491帧、失败0，平均57.96FPS（含截图/UI影响），不宣称性能提高或长期无衰减。
- Timeline IR 12项、compiler/runtime/timer及Swift桥44项、新stateful Bool/overflow桥1项、C/ASan3项、独立cursor timer1项及原cursor事务/捕获19项通过；结构4项、依赖/defense/代码健康/设计门通过。产品diff独立只读终审SHA256为 `a4d2bbe6599f6a590d39510cb6d03fe93867ef7e5f72a3ff095cf8626494cee3`。构建和这些门不代表全部Scene兼容；正常App→daemon长期视频衰减未闭。

## 同批旧报告复核

U24（3420215721）原包349/409的circular_text均明确 `visible:false`，没有作者脚本激活。slot1准备日志不能证明当前画面缺文字；中央环亮度仍缺官方同状态定标。未提交计数不是“GPU错误数”，也不以busy0排除in-flight延后。

U34（3782740481）基线受控32L/R非零输入下，305/453/466三个oscilloscope进入graph、GPU完成及唯一合成器，实际三环可见；不需新增stock shader。直接Host16秒不替代真实音源、静音及官方同声源幅度验收。

U22基线双4K视频层65秒持续有新帧，末段约60FPS，GPU P95约9.7ms。该窗口未复现逐渐卡顿；不能据此关闭用户所报所有带视频样本长稳问题。

有界证据统一保留 `.artifacts/tmp/scene-named-timeline-20261010`；隔离样本、HOME和未采用截图在收尾提取证据后清理。连续构建只复用 `.build-cache/solid-source-domains-recovery-20261009`，不推送。
