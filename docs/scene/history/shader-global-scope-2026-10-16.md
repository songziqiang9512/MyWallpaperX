<!-- document-role: historical-evidence -->
# Shader 全局引用与局部作用域修复

> **历史证据 — 非现役入口**。截止：2026-10-16。当前能力归[Render Graph 与 Shader 覆盖表](../capabilities/render-graph-shader-coverage.md#op-shader-syntax)，未验作者输入与后继选序归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。本批关闭共享引用分析及其两个 generic 消费方的具体作用域错误，不代表完整 shader 语法、真实作者命中或性能专项完成。

<a id="shader-global-scope"></a>
## 通用语义与前置反证

同名局部变量的 initializer 仍读取外层 binding；当前 declarator 在 initializer 之后生效，逗号分隔的后项可以读取前项。参数只遮蔽所属函数，block、for header、if/else 等语句作用域退出后恢复外层可见性。成员访问、struct field 声明和注释不是同名全局值读取；数组维度中的真实值读取仍须保留。它们是共享 token 语义，不按变量名、资源名或样本选择实现。

改产品前冻结 140 个 Swift 输入。自有 fragment 在全局 varying 的同名局部 initializer 中读取外层值，旧 `GlobalReferenceAnalyzer` 却返回 0 个全局引用；generic 归一化仍报告成功，真实 glslang 链接因已删接口的标识符未声明而失败。基线源集 SHA `99012cd913f7b5af3cf5662de5e65053652d6126d2e85eac3cbe6e743d8e8de0`。冻结基线另外确认 320 层 block/if 原本能得到精确全局 token 及 bounded lowering，不能把它们回退为 unknown 后以保留接口冒充成功。

## 原 owner 内修正与旧路径退出

`SceneAuthoredShaderGlobalReferenceAnalyzer` 继续消费既有 `SceneAuthoredShaderSyntaxUnit`，按 declarator 顺序扫描 initializer，再激活局部名字；函数参数、block、for、if/else、do 与 switch 的作用域由显式 continuation stack 退出，不新增递归深度阈值。函数内外 struct 的 field 名和成员访问排除，成员数组维度继续读取；既有 `[loop] for` 提示后的真实全局 token 仍精确解析。未知语法只保留 potential，不把可能的 local 改成全局字段；`exactReferenceIndices` 在证明不完整时返回 nil。

bounded emitter 继续取原 analyzer 的 token 做 context-field lowering。generic normalizer 在既有接口去重后，用原 body 与同一 SyntaxUnit/analyzer 事实判断 fragment varying 是否真正已死；旧 `hasLocalDeclaration` 的“存在同名 local/参数便删除 global”正则退出。真实 global stage ABI 错型仍拒绝，相同 fragment varying 重复声明不再使作用域事实失效。该修复不扩大跨 stage uniform 冲突删除、varying prefix 或其他类型转换的准入范围。

首轮 after 暴露另一个既有消费方：`SceneGenericShaderMutableFragmentVaryingNormalizer` 把 local initializer/赋值当成 global mutation，合成多余 copy，再整词替换，造成重定义或读取已裁剪接口。该 owner 现共用原 SyntaxUnit/analyzer 的完整 exact token 事实，仅把实际 mutation、所有全局引用均限于 main 的 non-array varying 局部化；只改写这些 token。旧 mutation 正则、名字级整词替换与独立 brace/comment 扫描退出；未知证明不授权合成 copy，真正不合法的只读 stage-input 写入仍由后端拒绝。

Frontend analysis cache `19 → 20`、Swift/Python generic request identity `v32 → v33` 退出旧结果。普通帧仍选择 prepared Program，不增加逐帧解析、编译、graph 或 compositor owner。

## 自有证据与跨冻结输入边界

长期回归为 `script/tests/test_scene_shader_global_scope.py`，复用已有 fragment-position 的真实 compiler、glslang/spirv-cross 和 Metal 提交/readback。23 个唯一 case 中，15 个像素 case 是 14 个普通正例与 1 个真实 global mutation；每例双 backend、各两帧、三处 ROI。变量/资源改名、等价表达式与邻接不应命中反例均进入实际输入，不以产品源码字符串形状代替结果。

| 冻结输入 | 实际执行与保留结论 |
|---|---|
| 首轮 after，140 源 SHA `32d520f5c3248b90f5d7a91915cebe3d490b29f0708c4e780bb42b361370582d` | analyzer 精确事实通过；保留 6 个普通正例的双 backend 像素、真实 ABI 错型双拒绝及 struct 数组维度 token 事实。7 个 generic 链接失败交原 mutable owner 修复，未算通过。 |
| 最终产品，140 源 SHA `93915e5ddc5627e663f6b5d9a10b6eb966fd6e3ad1dbb3d0a666844612b6762a` | 定向补跑 8 个原失败普通例、3 个 metadata 控制、`[loop]` 与真实 mutation 两控制；因 walker 又有修改，另补 320 层 block/if 两个纯 CPU 事实。产品反例、精确 lowering/link 与 mutation 像素通过。 |
| 同一最终 binary 的 uniform fixture 补测 | 两份 uniform 改名例先因测试 buffer 布局/裸 spirv-cross 输出的 Metal buffer 索引错误而失败；只修 fixture，复用已编 Swift binary，再补两例双 backend 像素通过，不重编 Swift 或重复其他矩阵。 |

真实 mutation 先对 global varying 加 `vec2(0.125)` 再读取；bounded/generic 两帧三处 ROI 均为原插值加 0.125，最大检查值为 0.96875/0.953125，证明 copy 后读取新值。它防止以禁用 mutable lowering 让 local 同名例通过。独审指出的 `[loop]` token 丢失与顶层 `fixedValue.signal` 成员误判，分别由精确 token/lowering/link 和 dead-interface 真实链接控制关闭；静态审查本身不充当执行证据。

23 例是按 case 合并上述证据，**不是最终产品下整套重新运行**；6 个旧像素例未重复。320 层例只证明原 token 与 bounded lowering 能力，不声称外部 Metal 编译器的括号预算。varying 用于 struct 数组维度的输入只证明引用事实，不声称它是合法常量 GLSL 数组尺寸或可执行 Program。全部冻结输入在对应运行结束时哈希稳定。

最终测试 SHA `6d681a70a243cb0350d70bd1b10b92d1888a3273ce5ae0bb31448a53818188b7`，harness SHA `6a8f4dbcd8f983e463dfa232da38cff9d43baf464c60a435af686ce61766c5dd`。本批没有读取真实作者 JS/GLSL、隔离标准 blur 测试或私有实现；没有官方同输入对照，也没有 CPU/GPU/能耗或启动性能测量。

## App 与独立真实输入

最终 Debug build 成功，用时 24.705s，4278 个输入哈希无漂移；Developer ID `H9QWU9XN8R` 的 deep/strict 签名验证通过。App executable SHA `86e21ecffeb4432fcccf23d99c88b018a13637e50f0501293f2d6018f3e1d56e`，debug dylib SHA `7fef1a1bbfb878b95004adffa135982b22b86f4fa23ee6abda443c5b0de198c1`。相邻旧门的 semantic artifact retirement、dead mismatch 与 main-only mutable 三方法为 3/3，通过用时 37.234s；这些门不替代全部旧 suite。

未参与修法的原始 `3743305891` 以隔离副本在 direct Debug host 运行：ready 6.657s、总运行 15.782s、exit 0、inputDrift=[]、surfaces `1 → 0`、gpuDrained=true。主代理实际查看 `scene-after-window.png`，人物/头盔、星空、日期/时间及频谱可见；保留原字节截图 SHA `c00df62958f54c57a970599bc4e21078bfb626c846a0f947f94349bf3d48e997`。它是独立真实画面回归，未证明作者输入命中本次 scope 修复，不标 S4、VM 完整健康、原生面板/daemon 或整样本兼容；ready 不与前批计时比较或解释为启动收益。

## 收据与保留

本机证据根 `.artifacts/tmp/shader-global-scope-20261016/tests/`，`summary.json` 逐 case 记录采用的冻结身份、像素与声明边界。必要 baseline/after/retry/uniform 收据、失败 glslang 输出与自有 GLSL 保留；三份 140 源及 harness 经逐文件哈希核验后压缩为 `frozen-inputs.tar.gz`（1,150,057 B，SHA `8eea28c49a86a81d1568f09cdab3688ba10b9cf2f32318b1604699fe6987fda8`）。已删除停止使用的 harness 二进制、展开源码和模块缓存，测试证据共约 2.8 MiB。现役提取工具只接受 Workshop 样本报告，不伪造 sample identity 晋升此自有测试；到期登记清理检查无移除项。

整批根目录另保原截图、中性 JSON 与 gzip 日志；根 `cleanup.json` 只记已清文件的逻辑字节，唯一连续 DerivedData 仍留原路径，不将其写成物理磁盘释放量。
