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


<a id="general-bloom-strength-timeline-20261016"></a>
## General Bloom strength Timeline的有界实施记录

生产链测试一次编译17项通过：原7 binding/15项保持，独立自有输入核 raw `.35`/catalog默认 `.6`/启动 override `.9`分域、frame40（40/30秒）输出1.36、loop、pause/stop/恢复、未提交候选保旧 publication、Timeline高于同 target user、改名/等价数字及局部拒绝。Debug构建30.708秒通过；测试不替代实际渲染。

受控静态白块只改变 strength Timeline：正值与zero hold图的571,536个本体像素无差，外部134,796个像素出现光晕，峰值50/255，主代理已查看。原3810943704候选22 image/43 effects实际 GPU completed、surface1→0、gpuDrained且无漂移，实图已查看；其原 Bézier保留，不称同相A/B、官方数值parity、全样本或性能收益。未参与修法的314完成12秒运行、exit0、无漂移、GPU completed与surface1→0/drained；独立代理实看壁炉/反光、时钟、频谱及音符光效，仅作回归，不推音频、Bloom因果或parity。

正式本机证据归 `.artifacts/scene-evidence/runs/general-bloom-strength-timeline-20261016/`；17项原测试收据在 `.artifacts/tmp/general-bloom-timeline-20261016/tests/attempt-01.json`。更广 general hosts、scene Script、HDR strength Timeline与未知值合同仍开放；需额外 clock/视觉算法时停止，不以局部门或ready外推。


<a id="normalized-color-timeline-20261031"></a>
## 粒子实例颜色Timeline的出生接入

原338的323/124 starfield、369/391 light_shafts_0各有absolute三lane colorn，旧Parser只枚举七标量，prepared particleTimelines为空而无diagnostic。沿原IR新增normalizedColor/hostLabel colorn、原扫描表接host、原Compiler映射Vec3/seed，三产品净+3行；没有新增owner/state/clock、求值或颜色算法，也不逐帧解析。实际launch重新Loader读scene、重编Program，没有旧已解析IR磁盘复用，不加缓存版本或目录认证。原writer仅调后续出生，旧人口/Color优先级/General bit8保持；不扩raw255 Timeline、live recolor或295颜色公式。

最近真实Parser→Descriptor→Compiler→SceneClock/TimelineRuntime→EvaluationTransaction/resolver→InstanceOverride→Simulator：旧887三产品隔离RED，42事实中12预期失败；候选42/42、18.002秒，无输入漂移。覆盖ID/资源改名、等价fps/lane、红→蓝→loop红、旧人口保持、bit8白/raw255优先、九类局部反例和健康alpha。未把业务逻辑抄入fixture；原重复粒子Source清单改复用既有Simulator门，两个测试文件净+130，985/385行。原338四wrapper经同一harness有四Vec3 absolute loop binding及非seed运行值；此处未构建其真实粒子资源，不作实际出生证明。

自有同输入普通App/GPU末端readback、约4秒两改名case：旧版red17700/blue0/green80656像素；候选red3540/blue10620/green80656，并有过渡紫色，旧红仍在、新蓝实际出现。root及独审均实看原PNG并核计数。旧版为优化DEBUG113eca18…，候选为普通Debug dd3f1613…/dylib b856dcb9…，不作同profile性能/精确phase比较或普遍像素等价。Source/IR的RED和实际新颜色共同证明本片能力，非profile命中。

首次构建65为本机Metal Toolchain缺失，未改产品绕过；官方命令补齐27B47后metal exit0。最终Debug155.016秒、优化DEBUG489.530秒均签名0/无源码漂移，后者在取消尝试前已自然完成，没有进程被杀；实际原包使用新优化exe `5affce66…4dfcd3`，不误用旧App。编译器组件保留为开发依赖；本批无性能收益测量。

原338/295/299各8秒、默认属性与同PCM fixture均PASS/exit0/drained，实际画面已看。338四目标在ready/after均0、committed集合不含它们，completed实例仅见其他20/110/295/320；不以非空音频、变化的Timeline值或别的粒子认领该光线恢复。295金光、299人物/雨/背景仍在，只有候选有界邻例，不认官方同状态parity。338整体样式及295白光继续唯一队列，不改音频阈值、gain或延窗碰出生。

正式包`.artifacts/scene-evidence/runs/particle-color-timeline-20261031/metadata/samples/0/runtime_evidence.zip`为1,532,309B、96项，SHA`8f6b672371183ce5dfe3009a8929009207d48414a1b2f7ddce89065485c8ac3c`；含受控原PNG、真实样本粗图及原SHA、日志/输入/源码/App身份、RED/环境失败/修后与独审，普通14天/32MiB单包/5GiB总量。不存私有包/App；验存后清已停临时目录，原共享增量缓存保留。
