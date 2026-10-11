<!-- document-role: active-plan -->
# 多段材质链的输入尺寸与终端显示

目标：修正普通 solid 特效把屏幕尺寸当作源纹理尺寸造成的重复采样，同时保留末尾效果停用时前一有效材质的屏幕细节。沿用唯一 graph、Program、pool、submission 与 MainPass，不增加样本分支或第二输出链。

## 行为与范围

官方 2.8.0.42 自有实验（2026-10-11）确认：120×60 solid 经 identity 后，下一段 g_Texture0Resolution.xy/zw 仍为 120×60，不随世界缩放及窗口尺寸改变；10×10 solid 生成64周期条纹，末段 identity 停用时为屏幕密度，启用时经历小尺寸中间采样。固定输入、二进制和像素测量保存在 `.artifacts/tmp/effect-texture-extent-20261011/`，失败探针不作为合同。真实纹理替换的尺寸比例问题是该能力的消费者，不是准入键。

首批限定可见、非 provider 的简单 color 链、普通 source-over、target-pixel 顶点、无 FBO/history/function/compose/几何网格；保留现高级混合职责。2026-10-12 补充：普通正交文字的单 stage 链复用同一证明与 terminal receipt，保留文字源尺寸、padding、pivot 和动态纹理 generation；作者顶点越过原矩形时直接进入既有 MainPass，不先采已裁的 graph-final。文字高级混合、透视及跨图输出暂不扩域。先验证无外部依赖，再依据同一资源生命周期合同接入已准入的外部只读输入。未验证的跨图 provider 与复杂图保持原路径。

## 外部只读输入扩域（2026-10-12）

已证首错是consumer工作纹理使用placement放大尺寸，named provider和Resolution编码已传递真实资源尺寸；不修改作者shader、采样器或uniform数值。扩展同一prepared资格，使原依赖owner已准入的精确externalPrimary在可见、非provider、简单color链及target-pixel顶点证明成立时使用同一源尺寸/terminal链；保留`!requiresGraphOutputProvider`：本片不要求provider graph output；binding仍由原owner准入，不能直接删除全部dependency守卫。外部text、透视solid、高级混合、aggregate、同层/secondary、几何placement特殊合同与复杂图不据此扩大。

原FrameInputs依赖证据、PreparedLedger与GPU submission共同保留provider/slot/epoch/object/content及实际texture；terminal replay只消费已经验证并编码的同帧资源，冻结Program输入不再解析/捕获。最终消费仍通过唯一ticket、MainPass和completion pin，不能为named输入新增尺寸表、资源缓存或输出入口。真实写后读冲突继续原输入副本机制；普通缺图沿原局部passthrough；陈旧/被覆盖资源拒绝当前不安全单元，不能回放旧帧。

验收补充：尺寸不同的named provider与consumer、scale/viewport改变、末段active/inactive/失败、多段覆盖保留、错误provider/slot/epoch/object/content、同buffer/重复消费、取消与完成前pin。官方named实验须先通过内容正控；历史失败探针不作数值合同。原始376截图必须实际减少矩形重复，保留头部deformer独立缺口及其他样本回归，不以效果节点执行成功代替画面收益。

## 职责与数据流

1. Capability 用已有 prepared graph/material/variant 事实证明所有可能成为终端的材质；纯停用或局部失败阶段可透传，不独立发明材质。
2. FramePreflight 使用真实静态源 mapped extent；无静态源的程序化 solid 使用作者尺寸。Resolution uniform 始终来自真实资源 descriptor，不伪造 Candidate 或修改 shader 数学。
3. GraphExecutor 仍准备和执行完整小尺寸 graph。最后成功 active material 的冻结 Program 通过现 PassEncoder 派生 terminal pass；后续透传不抹掉它。
4. 若后续阶段会覆盖该 pass 所读的 pair 输入，现 pool 按层及纹理槽保留同 descriptor 的临时副本，现 resource encoder 在该阶段完成后、覆盖前追加一次精确 copy。PassEncoder 仅将相同 descriptor 的物理绑定换为副本，采样器、uniform、Program 和 epoch 不变。无覆盖不用副本，无成功材质不用 replay。不得每段复制或新增 registry publication。
5. 副本 pin 由 PreparedGraph 随原 submission ledger 保持至 GPU completion；未编码失败立即释放，编码后取消沿现 ledger terminalizer。无独立生命周期 owner。最终仍由同一 MainPass 在原层顺序消费一次 terminal receipt。

## 取舍、失败与退出

仅缩小所有 RT 会破坏停用尾段的细线；伪造 resolution 会破坏物理资源合同；只回放最后声明阶段会丢失最后有效阶段。这三种捷径不采用。副本只在真实写后读冲突时出现，代价是一张源尺寸纹理和一次拷贝。副本分配或准备失败不得回放被覆盖输入，可局部使用真实 graph 输出（细节降级），不得丢帧或读取陈旧句柄。未知图不扩大准入；新设计没有新的 renderer、clock、资源注册表或提交器。通过后删除单 stage 限制，未证明复杂图继续保留现受限路线。

## 验收

真实 GPU 正反例：末段 active / inactive / 局部失败，细线密度、精确输入颜色、一次必要 copy、无冲突零 copy、同 buffer / stale / one-shot 守恒与完成前 pin。文字补充正负倾斜越界像素、identity 与 alpha、动态日期/时间末字边缘，停用回原 graph 路线。Debug build；原生同一官方自有尺寸及条纹输入对照；原始真实样本短跑与截图。外部依赖、全样本、桌面产品入口、长期性能不得由这些门代替。实现结果与剩余边界归现有队列；完成过程归档，稳定职责归运行架构。
