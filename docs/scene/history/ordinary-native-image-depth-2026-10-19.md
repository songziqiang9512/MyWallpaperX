<!-- document-role: historical-evidence -->
# 普通原生平面的显式材质深度

> **历史证据 — 非现役入口**。2026-10-19有界修复。职责归[D1](../roadmap/batch2/composition-render-target-design.md#普通原生图层的材质深度状态2026-10-19)，未解画面归[队列](../roadmap/scene-open-breakpoint-queue.md)。本片不关闭333盒体问题。

## 通用修正

旧普通image忽略作者显式depthtest/depthwrite/cull，最终无深度回绘；单个不透明前模型、后画蓝条的enabled/disabled两arm均穿透，排除多模型隔离归因。现沿唯一loaded model/material编译有限状态，准备层、动态模板与dormant资源继承同一值。仅native perspective、builtin普通quad、translucent和alpha unspecified；text、省略状态、自定义Program、geometry product及terminal replay不据此扩张。

纯typed状态与谓词进入Runtime/Frame，作者字符串解析留唯一Compilation扩展；Rendering无解析调用，4条旧混合namespace依赖退出。solid材料由原AssetCatalog正常收集，已证stock中性procedural源与provider白源/custom fallback保持，未知shader不能冒充中性。

原StaticModelFrame独占共享depth、首次clear、mandatory优先、busy/取消；新consumer在graph admission前资格，资源不足局部排除，busy整帧延后。唯一compositor最终draw使用reverse depth及独立读/写/剔除政策，source/effect空间和颜色不变。绑定失效由同一frame owner直接drop，不依赖可选graph runtime；此错误传播增量经静态反例审查，未在完整App注入故障。

## 验证与实际边界

最近CPU：状态编译4、loader/schema3、provider1通过，含改名/等价字段、未知/多pass/作者覆盖反例、动态模板与未实例化需求；DTO分离后重验前两门7项。有限Metal门2方法覆盖11组普通像素及2组旧source，读写四组合、normal/nocull、alpha0写入、overlay状态恢复、错pass/状态/缺capability均过。帧资源门4项保mandatory/late named/首次clear/取消/busy，source与普通consumer共用单lease。

同一自有包及3024×1964协议：旧App两arm重叠RGB均(32,96,224)；候选R1 enabled恢复前景(232,95,20)、disabled仍蓝，外侧蓝及紫overlay正控通过。最终R2仅重验enabled及健康控，disabled复用未受代码迁移/错误分支影响的R1结果；所有App输入/身份稳定、GPU完成、停止排空。H仍穿透，只作text默认未知观察。

真实333用R1同前批PCM、pointer(.5,.2)和关闭提示属性：前面/音频条保留，反向日期文字仍穿透；effect CPU、229局部fallback、Rope三FAIL保留。实际普通image正例隐藏或关闭depth，748是effect图消费，不能拿它冒充普通直绘受益。

独立358原包在旧App/最终R2均呈现土星、星环、时钟与底部控件，exit0/runner FAIL[]、输入/App稳定、正常排空。请求sceneTime30和wallDate，但作者Date/媒体音量仍随实时时钟变化，不能做整图锁相差分；sun431状态已准备，具体像素归属/遮挡收益仍未证。两真实样本均保持unreviewed，无性能收益声明。

官方default-depth自有R1未通过蓝image/紫overlay与glyph world位置正控，STOP_UNKNOWN；R2只冻结未运行，不裁定text/省略默认。未继续平台重试；VM/主客户端保留，唯一自有R1预览未正常关闭的精确标题/窗口身份留本机结论。

## 身份与去留

最终固定a06b09767加51项overlay、显式退休旧类型文件，Debug69.227s/4314输入无漂移、签名验证0；freeze `1ba6b20f71bc8b9bce72fdb9e4ec390cb8a0371e5f614fed67b449256f9b3b66`，exe `ceae8349e703d2f440ee39ca967c05d48186cdc9017a824bb10d9183d4b816c4`、dylib `cb044abf0bf3ccc46c9c59e99150f40fee9ee567d94b72810dcf710eabb6d97a`。首审P2与历史fixture装配失败均保留；修后分职责独审、门禁与必要画面归本批证据，不混入并行Xcode项目改动。

必要证据归`.artifacts/scene-evidence/runs/ordinary-native-image-depth-20261019/`，普通14天；仅保一份续接App/构建缓存。停止向未知text/replay默认扩策略，下一门区分模型实例隔离与跨面文字遮挡，不以本片公共语义恢复替代真实333修复。
