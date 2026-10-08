<!-- document-role: historical-evidence -->

# 共享 Shader 类型兼容与 U21/U23 后验

> **历史证据 — 非现役入口**。截止2026-10-09；当前合同归[运行架构](../architecture/runtime-architecture.md)，待办归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

## 范围与当前结果

基线 `e5928b54274756d8e0207de1f81997c4406babb5`。用户在 `cccea6c` 报告的 U21 `3806337293` 灰层/过曝/环形音频缺失和 U23 `3796588443` 混合/音频缺失，分别以原包隔离运行。样本仅作回归输入，产品没有样本、路径或 shader 名称分派。

本片修复共享编译类型兼容，**尚未恢复这两个被拒绝的真实效果**：U21 仍卡在音频数组双下标；U23 已越过函数返回 `const` 和作者 `fract` 冲突，当前首拒绝为 fragment `gl_Position`。不得把 CPU/GPU 小输入通过、graph 的 fallback succeeded 或原来已执行的音频条计为本片新增画面收益。

## 唯一职责与边界

- SyntaxAnalyzer 提供同一词法/声明/函数事实；generic 类型转换可独立取事实，不要求浮点循环通过 bounded 执行门。bounded `analyze` 仍证明循环预算，动态浮点循环仍拒绝。
- 现 BuiltInVectorConversion 接纳已证明返回 scalar 的内建表达式作为 `mix` 权重；VectorConversion 对返回 `vec3` 函数内已证明的 `vec4` 值、构造和唯一函数调用取前三分量，整个表达式只求值一次。未知、数组、重载和遮蔽保持不转换。
- 原 scalar intrinsic 重命名职责扩展到精确 scalar `fract`，保留作者函数体及调用；只删除函数返回位置的 `const`，保留 global/local/parameter const。既有 `mod` 边界不扩大，不以系统 fract 替换作者算法。
- 缓存按真实消费边界退旧：bounded ProgramCacheKey v16、generic analysis v15、request v26，Python request 镜像同步。准备输入/shared canonicalizer 未变，不提高其 schema。无新纹理、renderer、frame owner 或 compositor。

## 验证与运行身份

实现收据 `.artifacts/u21-typed-numeric-20261009/result.json` 保存13个代码/测试文件的 hash、行数和命令；实现 diff SHA256 `de33f46db1632186261eb6f51150ac1e21fe10fe3c5a1a4f3331f699871bda8d`。33项定向 CPU 检查通过，包含真实 glslang stage-link、bounded MSL 离线编译、缓存及请求边界。

签名 Debug build 成功且源码未漂移：App SHA256 `cea110ec0d10284b583570516ee553f121ff032211823c8f5210944edfaa604c`，Debug dylib SHA256 `4bac3b52d2e69ef49fe4e054624dc819052dd12dbbf8e3205b251cdaa9deaa80`。`/private/tmp/mwx-blend-common-20261009/build-final.json` 保存全部产品源身份。

复用现有 scalar/vector 测试的 GPU harness，自有5个输入经产品 normalizer → glslang → SPIR-V → MSL，逐项渲染两帧：`mix` 两端选择、vec4变量和函数调用返回vec3、与内建刻意不同的作者fract，全部逐通道符合预期（误差门1e-6）。收据 `type-gpu/receipt.json`。这是有界数值合同，不是完整效果或官方画面验收。

真实运行证据均在上述任务根下，使用新空 generic cache、受控频谱、原包只读副本；两个 App 均正常停止，surfacesAfter=0、gpuDrained=true：

| 样本 | 当前实际链路与余项 |
|---|---|
| U21 | `gray/typed-final`：2676/2686首effect仍各0 material/1 rejected，spin/opacity处理solid回退；灰层、过曝和环缺失未关闭。原包 SHA256 `c3726c0ac70beff0482d98335c8641553afb5cf24e60b48f07c459a20e582ae0` |
| U23 | `blend/typed-final`：131/650音频各4阶段实际执行，紫色条可见；241首effect仍0 material/1 rejected，当前准确错误为fragment位置未声明。LOVE色阶/灰色矩形仍存在。原包 SHA256 `68120c5eca62c217d98fdcbd9071112d163fa8cc40aeb3dfe204a38865712072` |

两组音频条在本片前基线已执行，不能重复计为本片收益。包索引显示 Simple_Audio_Bars 同族在5样本存在，只证明声明影响面，不证明5样本均激活或本片获益。

## 未决合同与后继

[公开变量合同](https://docs.wallpaperengine.io/en/scene/shader/variables.html)把64带音频定义为float数组；不能凭作者双下标就改成另一套host ABI。自有官方2.8.0.42实验已证明普通局部scalar数组单下标执行、局部双下标拒绝，尚不能裁定保留音频uniform的特殊语义。第一轮fragment位置表达式可见，但除数过小使XY饱和，坐标空间仍未知。

后续同输入实验在窗口有效extent前失败，未产生语义证据；必须修复公共窗口ready采集流程后再测，不能猜测flatten或直接替换gl_FragCoord。保留 `/private/tmp/mwx-blend-common-20261009/official` 中的中性输入/身份/失败与清理收据；没有消费私有实现。窗口流程已修为fresh HWND/真实extent最多60秒，并在失败时保留preflight。随后公开进程清单证实客户端已退出，重新启动所得PID10664路径/版本/hash均核同；同输入open返回0，但119次检查始终无HWND，结束时该进程已退出。没有像素证据，不推断shader崩溃或数组/坐标行为。下一实验先以过去成功的简单输入区分客户端启动与新fixture失败，不能继续原样超时重试。VM恢复暂停，未杀其他进程；精确guest目录70文件已删除，本地同hash输入保留，收据`official/refined/startup-guest-cleanup-receipt.json`。

下一门：取得保留音频数组与片元位置的可区分官方合同，再扩原编译/输入owner，确认目标节点 material=1/rejected=0并检查最终画面；灰层/过曝、背景混合及真实声源分别验收。类型片已独立只读审查，无可操作正确性或重复owner问题；审查13文件diff与实现身份一致。产品提交`c9040e6aa6bb13ea52160a292782fbfaed2c152a`；提交后逐文件核对13个已审文件及10个构建产品文件均匹配，严格staged preflight通过。原样本开放状态不因提交改变；本轮已停止的样本副本、HOME、generic cache与临时GPU二进制/模块清理148,886,657字节，明细`cleanup.json`；保留上述有界身份、截图、日志、输入及失败复现。连续构建仅留`/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d`；未知归属`.mimosa`218字节保留，residue门因此非PASS，结构/依赖/设计/代码与测试断言门通过，文档49项通过。
