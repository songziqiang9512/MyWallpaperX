<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。合同见[效果执行边界](../capabilities/effect-execution-coverage.md)，余项见[断点队列](../roadmap/scene-open-breakpoint-queue.md#qf--2026-10-07-用户点名四样本公共主链修复)。

# 普通颜色误判为独立信号的修复（2026-10-07）

起点84fdc1ec。聚光灯3791967416的三层barcode编译成功，却因`independentAlphaSignalPreserving`要求信号输入、实际输入是premultiplied color，在launch envelope被拒。第四个拒绝属于audio_caps_render：default boundary将data slot0当作颜色，独立留待后继。

修复现有IndependentAlphaAnalyzer的宽松fallback：终值只准载体的纯标量缩放，复用IndependentSignalCarrierAnalyzer与ScalarContract；括号、标量乘除、左乘和重复贡献有正例。计算型载体须从零累加未改写的直接采样，每个整向量写和源读取均检查；生成RGBA、顶层广播加减、整向量swizzle及索引写不能借裸变量终值取得信号合同。专用producer/carrier/accumulator在此fallback前继续持有自己的证明。旧fallback对未证明写法的宽松认领不作为兼容承诺。

独立审查依次发现并修正括号/标量回退、局部变量混色遗漏、运算优先级、未知whole写及whole swizzle绕过。variant/generic analysis与bounded Program缓存同时失效；artifact key原有expected transfer/slots自然变化。没有新增形态分析器、route、graph、clock或compositor。颜色反例先红后绿；同批发现GraphExecutor测试仍上传旧16-byte顶点，Swift/MSL镜像同步coverage1和24-byte stride，保留原照明像素断言。

## 验证边界

验证日志、冻结diff、App身份、原样回放与隔离视觉探针保留在`/private/tmp/mwx-color-envelope-20261007`。真实原包只读。三条barcode从visual-failure-passthrough恢复为真实material node、GPU completion与compositor consumption；音频柱、动画层脚本seek、最终亮度和全样本官方parity没有因此完成。原样截图受视口裁切、动画和遮挡影响，不能单凭节点执行宣称完整视觉对齐。

最终冻结App的CDHash为`80fcc919bcbe53cc12072aa74bc5b6d8d0eef0cd`，executable SHA256为`1c7a92a998af4ad56569ab7f12cad81281c7194e149b61667f3bb9d9c512ebe2`。原包30秒回放exit0、无超时；265/271/275均有materialNodes1、rejectedNodes0、GPU completed与compositor consumed，且下一帧继续执行。整体benchmark仍FAIL：audio_caps拒绝造成CPU invocation/passthrough失败，hover证据不足。不能将本批三处恢复推算为完整样本正确率。

隔离探针保留三层原始条码、将正交视口改为1440×1440并关闭相机淡入/视差，12秒benchmark PASS；两张series截图确认三列亮色条纹实际显示并随时间移动。它是裁切/遮挡之外的显示证明，不是原样本或官方parity。用户的`截屏2026-10-07 08.28.05.png`为官方实机参考；当前原样回放仍明显偏暗，未作同视口同相位像素验收。

独立审查最终ACCEPT，绑定`review-final.diff` SHA256 `72f2ffea547cd00a00434d97bc08d879136cc98ceab7410825e3ce8274e263f0`。相关12模块回归通过；最后whole-swizzle/index反例补齐后37项颜色合同测试通过，Debug重新构建通过，上述实机与探针均使用该最终App。最初GraphExecutor照明门失败归因于测试顶点ABI，已独立提交`7411a8bf`，修后原GPU像素断言通过。结构、依赖、防御面、文档与设计门通过；这些结果不证明全样本兼容性或性能提升。

本轮进程已退出，staged App、样本副本与重复运行目录已删除，精确清单见`cleanup.json`；必要日志、报告、代表图和源码身份留在上述临时证据目录（约18MiB，大日志/报告gzip压缩）。正式证据缓存已满，promotion拒绝新增、prune无可清项，未删除未知或受保护旧证据。继续共用`/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d`这一份构建缓存。


## 图内数据输入后继修复

起点c85e6a34。audio_caps_render的slot0引用已准入RGBA状态缓存，slot1引用previous颜色。launch已有producer content map并保持不可变，entry→compile漏传该事实；default boundary直接使用所有graph input槽，错误对数据采样执行颜色转换，随后被正确的typed颜色门拒绝。

沿既有entry/compile/artifact链传content事实：只从当前active且ready的最高优先graph候选、精确identity和已证非颜色content派生graphDataTextureSlots，implicit捕获不排除；default边界扣除这些槽。低优先data候选、未知fact、signal与其他color不因本修复放行。拓扑集合、source分析器、运行时颜色拒绝门和输出owner不变；generic resolution Input/hash、persistent digest/v7完整携带新事实，artifact key复用已有边界槽身份。源分析缓存语义未变，不扩大失效范围。

冻结diff SHA256 `adf9a4e0d88456cb14f6646207c432078b44d07af28ce702c8cf3a8d66e4ec68` 独审ACCEPT。Debug构建通过；34模块中33通过，另1个typed-input测试夹具漏传新增字段，补齐后4项独立重跑通过。persistent-cache新增数据/颜色键隔离、边界[0,1]→[1]与数据采样不转换/颜色转换一次断言通过；旧单独cache日志的预期列表失败被focused成功重跑覆盖。结构、依赖、防御面及设计门通过。

原包注入音频回放30秒，App CDHash `9ab29b7a74e89346806f65fc0afc2215c45a864f`：exit0、无超时；层57三道material均encoded-output、GPU completed、compositor consumed，下一帧持续消费；visual failure passthrough归零。整体benchmark仍因hover证据不足FAIL。原始编译MSL导出位于lowering之前，不能拿其helper缺失判定最终Program；颜色转换次数由执行后的lowering探针断言。


隔离视觉探针只保留原音频层，视口1440×1440、origin720/720、size1000×400，关闭相机淡入和视差，使原本受裁切的柱体完整可见；shader和参数不改。有声时16柱按输入高度显示、峰值标记可见，静音时收回基线；两种输入均无GPU失败或passthrough。有声benchmark PASS，静音只因hover无画面变化而FAIL，符合该探针没有交互的范围。它不证明真实系统音源、官方峰值运动parity或完整场景亮度；原包画面左下方也可见恢复的音频柱。

本后继证据在`/private/tmp/mwx-audio-boundary-20261007`，包含原包与两种探针的摘要、代表图、测试和源码身份；构建缓存复用前述唯一目录。下一项是动画层脚本入口与统一seek相位，联验眼部组装，再固定输入核对亮度。

本轮进程已退出，staged App、样本副本、失败视口重试目录与重复截图已清理（精确清单见cleanup.json）；保留约10MiB必要证据，大日志/报告gzip压缩。正式缓存已满且无到期可清包，promotion拒绝后有界保留临时证据，未删除旧保护材料。
