<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。剩余任务见[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# Puppet 未引用尾顶点修复（2026-10-07）

从 `f4d90174` 的用户官方截图对照继续，3791967416 身体层962实际被mesh reader拒绝，并非单纯偏暗。只读作者包提取的MDLV0023在offset71含8771个80-byte顶点、47451索引，最大索引8767，8505个顶点被引用。末尾3顶点未使用，旧等式因此误拒；整个MDLS前搜索范围只有一个索引合法候选。

修复保留既有末槽索引候选的全局首匹配顺序；全扫描无旧候选时，仅接纳唯一(offset,stride)候选。歧义不以浮点数值猜解，保留65536顶点上限及所有顶点的有限/范围验证，decode失败不重试其他块。无样本/路径/资产分派，无新增解析owner。现役二进制边界见[格式参考](../capabilities/scene-format-and-render-graph.md)。

验证：

- 自有11顶点fixture由旧reader失败转成功；原索引和未引用尾顶点完整保留。29项mesh门通过（1项原有真实attachment fixture缺失skip），覆盖同块/跨块歧义、旧候选优先、越界、数量上限、unused NaN、旧候选NaN不改选；原80/84/48与历史版本用例保持。
- 真实Swift reader读取身体模型：stride80、8771 vertices、15817 triangles；Debug build成功。单改产品源可选中mesh门；结构、设计、防御、依赖、产物、测试断言与门禁工具检查通过。独立只读审查接受代码与反例，未冒充独立App复跑。
- Developer ID staged Debug App CDHash `3922f3b21852a413bd402c70d8e0a730c9437069`。隔离direct Host的12秒与30秒运行均exit0、无超时、GPU drain；身体、手臂纹身和黑色服饰实际恢复，30秒运行的series-0001（就绪后约21秒）已核图。
- 整体benchmark仍FAIL：barcode色彩局部降级，30秒运行还有hover阈值。body动画因blend=1.3超出已有播放profile退回bind pose，小眼睛auxiliary track亦拒绝。人物完整动画、最终颜色、正常产品入口和官方parity未完成；loaded=1不能作完整正确率。
- 最初staged App遗漏同团队compiler helper签名，导致shader拒绝，该次runtime排除视觉验收；补签Helpers并重签外层后以上两次运行helperSignatureInvalid=0。产品代码无签名相关改动。

证据位于 `/private/tmp/mwx-spotlight-mesh-20261007`，源包SHA `c2ac2d365c87ba0253c439381709d686db24a7218c1005529df63b8b9bc61199`；清理副本与App后保留报告、日志、source identity、代表图，沿用一份checkpoint缓存。用户原件未改。

颜色只读追踪未发现opaque层23重复预乘，样本HDR关闭，不能归因终端tone-map。官方截图视口约1.83而回放约1.54，鼠标/时刻也未对齐；先锁输入，再对隔离副本Noise78/37消融和逐stage RGBA核验。现有fragment.metal dump在color lowering之前，不能当最终GPU程序。hover调试流程的after图早于请求22秒，实际稳定观察使用带时间日志的series图；后继不得按文件名推断时间。
