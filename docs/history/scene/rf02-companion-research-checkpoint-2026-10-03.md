<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->
<!-- cutoffDate: 2026-10-03 -->
<!-- uniqueValue: RF02真实Swift修前反例、固定官方客户端身份及自有fixture准入检查点；不记录产品完成。 -->

# RF02 修前反例与官方自有输入准入检查点

> **历史证据 — 非现役入口**。截止2026-10-03，实验产品基线为`c4bb5704`。本机证据根 `/private/tmp/mwx-rf02/`，下表工件路径相对该根。本文独有价值是保存已执行修前反例和黑盒入口进展；现役判断仍见[RF02卡](../../scene/design/reference-evidence-implementation-cards.md#rf02-companion)、[兼容路线](../../scene/scene-compatibility-roadmap.md)、[能力台账](../../scene/semantics/coverage-ledger.md)与[运行证据](../../scene/semantics/runtime-evidence-current.md)。本文“下一实验”仅属于截止日。

真实Swift执行四个自有输入：baseline与dead-companions准入；active Rotation/Translation保留精确float4/float2顶点字段，却在现役HostUniformSchema找不到producer，真实finalizer及VariantCache launch均返回`uniform/staticUniformBindingInvalid`。独立只读审查接受这一有界CPU反例。执行未创建Metal设备；图输入只是launch metadata，不代表纹理publication。隔离编译器缺license bundle后走shared bounded frontend，不能宣称compiler artifact成功。

| 冻结证据 | 结果 | 最高可支持结论 |
| --- | --- | --- |
| `counterexample/report.md`、`counterexample-review.md` | 四项真实Swift断言通过，230编译输入哈希未变 | 修前host binding缺口；无GPU/像素证据 |
| `host/identity-32-v2.log`、`host/process-v4.log` | 32位官方客户端2.8.0.42；完整SHA与进程路径留档 | 本轮客户端身份；不是通用版本合同 |
| 主代理CUA观察 | 自编PNG显示；关闭旧popout后，新32位窗口显示`neutral-admission`自有单帧TEX完整16×8色格 | 自有资源可见准入；未做文件像素测量 |
| `host/grid-install-v1.log`、`host/own-errors-v1.log`、`host/grid-syntax-v1.log`及CUA观察 | v1.3红屏/X3086；仅将uniform/varying移到列首的变体`21EA1D3A…496D739`显示完整32×16黑白格 | 语法差分的可见预检；尚未数值解码 |

失败尝试保留：临时Swift driver曾误用`details`，改为`boundedDetails`后通过；v1.3的自有shader在strict ps_5_0报sampler2D X3086，日志仅过滤自有路径，列首变体尚不足单独证明因果。v1.3独审指出旧low-tier控制可漏检1/2048量化；v1.3.1已改为±奇数q控制并冻结新身份，官方执行待完成。

下一可执行实验是运行v1.3.1，保留原截图与shader/resource/window身份，按完整网格、固定中心ROI和全部已知控制准入，解码Rotation四分量与Translation两分量的完整区间；随后用已冻结literal point、同容器palette及literal/active程序比较自动变换次数。重载和精度不满足就保持unknown，不能放宽容差。数值布局、单位、自动阶段与同帧publication定案并经独审后，才沿既有反射→typed uniform→sampler进入产品实施及GPU/compositor/next-frame验收。

本轮不证明数字语义、官方parity或产品修复完成。未读取Reference Project、stock/private shader或私有表达；本检查点仅同步研究记录和工作卡；没有产品改动或App构建，不推送。foreign `script/scene_source_layout.json`保留，三份受保护文档未触碰。

CPU证据冻结：`counterexample/freeze.json` SHA `822cc3f1d8444335c4a04cfa353962381bc4605b0e060754218da1da2ba32a14`；独审报告 SHA `4e1eca20b7e221163121547cc5ce314ae461da31532b2aae3c1c4b32e0257c33`。v1.3.1自编slot1 shader SHA `9426d94e9fdb27086077bfbada2314363c419cd37a38b2fe8b3980dc4d0e2e81`，本机和guest两份effect片段身份一致；尚不代表数值校准。

v1.3.1有限finite/single-frame/slot1测量设计获独审ACCEPT，报告SHA `6c059016aef1bc4488a44d9fcd80860ebef70c4eaaa667002e4293e5a4fdf523`；批准的是实验设计，仍要求最终程序自己的原图、完整ROI和八控制实过。guest文件已安装并发启动命令；检查点尚未观察到新窗口身份，不能把旧语法变体画面替代新版本。
