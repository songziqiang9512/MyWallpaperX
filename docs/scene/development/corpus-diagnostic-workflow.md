<!-- document-role: stable-contract -->

# Scene 全样本声明诊断与报告合同

目标是让完整、缺文件或畸形目录都能留下准确的声明诊断，并由同一次观察产生可复验的总览与明细。它不运行引擎，不裁决官方画面一致性；执行顺序仍归[断点队列](../roadmap/scene-open-breakpoint-queue.md)，统计归[声明总览](../capabilities/scene-corpus-capability-inventory.md)与[样本明细](../capabilities/scene-corpus-sample-inventory.md)。

## 输入、职责与迁移

真实Scene目录只读。单个目录的project解析失败仍保留sample identity、失败原因和实际材料事实，不能为消除报告异常把失败改成成功，或把未知材料一律补false。

```text
CLI / build_census 唯一遍历与守恒
  -> samples 单目录 authored 观察 -> 现有 resources/effects/particles/profiles -> io
  -> contracts family/repair 声明及引用校验
  -> reporting 同一结果的 snapshot / 总览 / 明细纯投影
  -> CLI 校验输出路径、预生成全部payload、沿现atomic_write写出
```

`scene_capability_census.py` 保留实际corpus orchestrator、缓存query与CLI；迁出的完整职责分别由 `scene_capability_census_samples.py`、`scene_capability_census_contracts.py`、`scene_capability_census_reporting.py` 唯一拥有。原定义退出主文件；既有可导入函数/常量用显式import保持同一函数对象，不复制算法或增加转发wrapper。下游不反向import CLI，不引入第二扫描、缓存或运行结论owner。生成器身份manifest覆盖所有实际职责源。

这次迁移服务两个已证故障：失败row缺材料字段导致报告KeyError，旧单页writer与现役双页文档不符。样本观察、合同、报告按完整职责迁出，使本批触碰的自有源码各≤1000行；不为缩行数切任意代码块。未触碰的profiles既有超限不借此宣称关闭。

## 一次观察、三项输出

- snapshot保留机器可查声明、失败与身份；不装入作者脚本/shader正文。
- 总览只保分母、声明/能力汇总、证据边界及明细导航；不重新塞入整张样本表。
- 明细拥有逐样本行，包含失败目录与材料事实；总览/明细互链。旧N样本矩阵成员只写是/否，不称“新增”、从未运行或当前运行裁决。

原 `generate / verify / query`、缓存优先及显式live语义保留。新增可选 `--sample-markdown`；未提供时从 `--markdown` 所在目录派生 `scene-corpus-sample-inventory.md`，自定义总览输出不能悄悄写入仓库默认明细。旧Namespace调用缺新属性也用同一规则。具体参数以 `--help` 为准。

## 失败、写入与退出

1. 构建前校验snapshot、总览、明细的resolved路径均不在只读输入根，且三者不互相覆盖；符号链接按实际目标判断。
2. 每次generate/verify只构建一次census。结构合同失败沿原返回值退出；单样本解析失败保留失败row，不能阻断其余报告。
3. 首次写入前，在内存生成全部三份payload；投影失败不得留下“新snapshot＋旧文档”。随后复用现单文件atomic_write。它不承诺三文件IO事务；IO失败明确报错，由verify逐项识别漂移，不另造持久化协调器。
4. verify分别检查三项输出，区分snapshot、总览与明细drift；query缺缓存的早退与显式live边界不变。

运行归一器和粒子/脚本/资源的视觉准入独立维护。工具正常或声明计数守恒不证明样本能正确播放。

<a id="evidence-capture-timing"></a>
## 运行截图时刻

`after-snapshot-delay`以ready后开始安排截图的单调时钟为起点，约束after请求的最早时刻。鼠标hover、click、trajectory及普通单轮drag还须发出hover截图请求、移出并经过原0.2秒等待；取两者较晚者。鼠标动作不为等after而延长，独立命名的多轮drag保持原计划。普通ready/after、周期截图和spring-after继续各自现有时序。

launch失败/取消或closing后不请求新截图。该时间只约束DEBUG请求，实际捕获/保存仍由原frame-capture owner确认；日志时刻、音频和鼠标状态共同决定图像是否可比较。旧鼠标路径提前after的历史图保留实际日志时刻，不按请求参数追认成延后截图，也不因此自动改样本裁决。


<a id="diagnostic-output-acceptance"></a>
## 验收与停止条件

最近小fixture包含正常包、仅shaders/无project、带截屏与说明但project无效的目录；验证发现数=成功+失败、失败诊断不丢、材料事实准确，三项输出可生成与verify。分别篡改每项输出均须报告drift；自定义路径、输入根、符号链接、输出互撞及投影失败前不写入均有反例。

原声明确定性、payload-free、family/repair引用、缓存query与API门保持；测试按完整观察组和输出/合同组迁移，共用原真实fixture builder，不能重复发现同一TestCase或复制扫描算法。所有本批触碰源码/测试/helper实测≤1000行。

小门通过后，从原目录只读完整生成到隔离目录并verify，对照原有效manifest/计数及现双页；已解释的生成器身份与材料字段变化单列。未知计数或语义漂移先停并定位，不靠重生成抹掉。最后才同步现役双页及队列中的这两个子项。此工具批无需App构建或设备运行。
