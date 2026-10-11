<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。稳定合同归[运行架构](../architecture/runtime-architecture.md#effect-texture-reduction)，剩余任务归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。
# Effect 纹理缩减参数（2026-10-11）

## 决策与实现

基线主树a9a2bd35、隔离树6828c77d同树。2877855240虽已恢复启动，六个MODE1 Skew仍因缺少g_TextureReductionScale走visual-failure-passthrough，时间/日期直立、紫色线条端部方正。此批只在既有HostUniform enum/schema/encoder补effect-context非数组float参数，当前无全局纹理质量档，提供已验证中性profile值1；错误类型/数组/声明冲突和Program来源校验不放宽，source/base同名作者值不抢占。原requiresEffectDrawModulationHost更名requiresEffectHost并同步两个调用；没有新增帧字段、尺寸算法、effect路径识别或输出owner。设计先落架构和登记，再改五个产品文件。

固定官方2.8.0.42（exe SHA daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07）自有输入：6个ordinary solid/text三档layer scale及6个clip-space FBO scale配置1/2/4的scalar ROI均R32/G128，uniform÷8解码1.00392±0.06275；六个独立sample-only控制R64。真实slot0 alpha随glyph/采样变化。此前两个viewport的ordinary结果复用。active MVP-FBO对照与上游控制重合而被排除，不能解码为2；旧probe失效机制未完整解释。全局quality原值未读到、未更改，HDR/透视/图片媒体等未测；不据此推全域公式或把local cap、padding比例当缩减值。neutral-contract SHA477649b67c9564330f39a77f55f084196eec6d63d8cebb4ba849fbc0541f6f4a经独立设计审查和root中性交接接受，未读私有实现或生成缓存bytes。

## 实际画面与边界

原包SHA3a3b1ff68529e885d4a9455cdc0b3b9b8aad55914a36615058a5231a7e1f2933不变；同隔离HOME/内部Host/静音PCM方式，新Debug App ready21.517秒、播放12秒、exit0/gpuDrained=true。层84/132/577/756/88/97的六段Skew在frame0和frame1均真实Program、gpuCompletion=completed、compositorConsumed=true；之前相同六段均为失败透传。实际after截图确认时间/日期倾斜、四段紫色装饰端部斜切；人物、背景和原健康effect继续显示。该缺口6/6进入链，不等于整样本正确率；窗口比例/动画相位不同，不做全图数值parity或性能结论，桌面产品入口/长稳/全交互未验。

App主程序SHA6847268a0ee64e70ab60ed1e6ae5c95539c5b2c487f014674685839200a419ac，dylib b369a88cfd3628411aa42abb52227155814bf5df307a0a23baa2c97850a17e1b；产品diff SHAfb21deedf7f3bc0b900c92a8025744e7246945c312581a7d88c0c6c8a9576ac6。五产品静态独审无P1/P2；完整最终收据随本机冻结保存。

## 验证与留存

新增CPU两门修前FAIL，修后11项CPU均通过，覆盖host/source静态动态隔离、alias共存、类型/数组、声明冲突、Program身份与terminal保值。原alpha/color两GPU门通过。新增离屏GPU载体曾漏sourceGraph，并误把原fixture的pass=true负例（shadow PASS）当作普通采样尾段；另一个单FBO试验不满足effectOutput合同，均在准备期拒绝，未冒充GPU通过。最终恢复原合法两节点graph及默认普通采样template，补完整sourceGraph，复用裸Swift carrier的disable-generic策略；它验证bounded Program/Metal的vertex参数与实际target extent，不代替原App的generic终端验收，不扩产品路由或降低像素预期。最终3项GPU全部通过：FBO实际8×8/4×4/2×2各三帧vertex读取1，参与位置及varying，真实FBO publication按uniform÷8读回BGRA[51,191,32,255]、completed且无fallback/重编译；原alpha/color终端读回保持。独立终审发现原R255读回不能区别1/2/4的饱和盲点，改÷8编码后v5三门83.027秒通过；旧v4不作数值合同。合计14个不同参数门由11 CPU+3 GPU分阶段覆盖，不能称单次完整套件全绿。49项最终文档门通过。Debug构建、代码/依赖/防御/设计门通过。结构/文档组合60门中59通过；未改的source-set门要求frontend测试源码直接含scene_swift_source，既有consumer实际间接导入canonicalizer SWIFT_SOURCES而失败。三相关文件均与基线字节一致，保留为既有结构门债务，不宣称全门通过；主树canonicalizer并行改动保持。

本机根`.artifacts/tmp/skew-uniform-20261011/`保留官方中性合同、自有输入、有限截图、native-comparison、App与源码身份和门日志；上一批before引用skew-reduction-20261011/after。官方三个自有窗口及guest临时输入已清理，VM/receiver保持原状态；本轮原生运行已退出，隔离输入/HOME及重复生成shader/ready图已清理。唯一连续构建缓存仍为`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`。后继优先N06 Sound脚本共性缺口：376旧运行报particle playback unavailable，作者实调sound，376631/378175也有同调用；此为现代码/旧日志+只读作者输入定位，未声称三样本本轮全部复现。沿唯一sound registry处理播放意图，保留OGG/random及独立BAD_RETURN；N03缺失slot1尺寸作为次选，不填假尺寸。
