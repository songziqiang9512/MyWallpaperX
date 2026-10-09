<!-- document-role: historical-evidence -->

# for 更新子句的整数转换边界（2026-10-10）

当前待办由[断点队列 U24](../roadmap/scene-open-breakpoint-queue.md)维护。本记录是完成批次的证据，不是新增路线。

## 当前问题与修复

起点 `cd77d100799424a80b37dfec8958353c73df9c4c`。真实 `3420215721` 默认设置、隔离HOME、音频fixture复核：并非历史报告所说的全景静止；圆环、脚本与底部频谱持续更新，但四个示波器occurrence的generic编译被拒，随后bounded frontend也拒绝动态varying数组索引，效果局部previous-current。

机器只比较语法类别与hash，未向实现上下文输出作者/生成shader表达式：原始和三份prepared source没有构造器内statement block，normalized fragment首次出现该错误。首错是现有 `SceneGenericShaderSourceNormalizer.rewriteFloatToIntAssignments` 的RHS扫描忽略深度零的`)`，把for更新后的循环体吞进整数构造器。自造合法整数循环也能复现，循环体中的浮点数会错误触发更新表达式转换。

在同一转换器内先检查外部表达式边界，再维护括号/下标深度；语句块中止，最终只接受`;`或`)`结束。原有类型证明、逗号/多声明拒绝、显式转换避免重复、比较数值提升及失败范围不变。没有新增parser、示波器算法、runtime分支或输出owner。Swift/Python共享request身份升为v29，避免旧缓存复用。

## 验证与真实画面收益

- 新增for反例在旧产品上5组失败；修复后的完整scalar/vector canonicalization门13项通过，最终含6组for用例，并运行既有比较/循环次数GPU像素门。独立构造输入覆盖整数/浮点更新、plain/compound、嵌套括号、数组、无brace及显式转换。
- 编译工具与缓存合同28项通过；Scene依赖、defense与设计门通过。全仓code-health仍因未修改的Web `DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift` 1008行失败；HEAD原件同为1008行。本批Scene文件低于1000行，未调整基线掩盖该问题。
- 签名Debug构建成功。所有761个Scene产品源的身份与工作区一致；构建隔离checkout的Web基线较旧，不能当作全HEAD/release构建。dylib SHA `b05280e5ee363840c00214bc0d1edb4f580e2c3e2ec244d6a6a7289ea6fe1edf`。
- 原样本重跑：4个示波器occurrence（257/369/719/744的effect0）由failed/visual-failure-passthrough变为resolved-material/encoded-output；默认可见719/744消费非零双声道16-bin音频，GPU完成，后续Perspective/Motion Blur输出由唯一compositor消费，紫蓝声波实际显示并变化。257/369作者默认隐藏，不能算作默认可见收益。
- 本次观测的effect occurrence编码由20/24变为24/24；这是观测链覆盖，不是作者全部56个声明、全部组合或完整正确率。基线graph也会成功发布fallback，所以不以graph succeeded单独证明修复。
- 既有整数复合转换健康样本`3809618616`重跑，照片与底部频谱正常可见，5/5观测effect编码、0编译拒绝/效果失败。两次最终App均exit0、surface归零且GPU drain；无长期性能结论。

## 尚未闭合与排除项

U24封面层491仍因`execution-stage-conservation`在准备期拒绝。中央环较暗，但没有原样本官方对照，不能认定仍有色彩错误。本批不扩展媒体输入或调整HDR/Bloom。

曾怀疑作者layer alpha大于1被截断导致暗环，官方2.8.0.42有效solidlayer控制不支持该改法：SDR/Bloom关闭，alpha=.5有变化，alpha=1与7在普通源、identity、alpha×.25效果后三行内区均逐像素相同。初始两次错误源入口的实验无效，不能引用。此结论只适用于该控制，不推断HDR、半透明纹理或真实U24效果链，产品alpha逻辑未修改。

## 证据与交接

本机批次根 `.artifacts/tmp/static-scene-20261010`，含输入/build身份、红绿日志、`runtime-comparison.json`与中性`audit/syntax-machine`。必要证据包为本批根 `runtime-evidence.zip`（8,158,442字节，SHA `51b7f00b048b6848a9a8551a57b0eced5ee681f1894081502c6c8120f4536a6b`）；正式promotion因全库1GiB预算满被拒，未提高预算或删除其他任务材料。最终截图/日志/收据有界保留；本批样本副本、隔离HOME及374个生成shader已清理，共约1.22GB逻辑字节。连续开发只复用 `.build-cache/solid-source-domains-recovery-20261009` 一份构建缓存。

独立审查覆盖精确owned diff及证据界限。后继优先处理用户新报U16/U24正常桌面在歌曲进入后整体停帧（隔离fixture不覆盖真实system media）；然后复核U34音频环和U22视频持续掉帧；U24残余留在现役队列，不把本批完成写成整样本完成。
