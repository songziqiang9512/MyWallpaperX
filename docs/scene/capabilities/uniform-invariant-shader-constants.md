<!-- document-role: stable-contract -->

# Shader 的 uniform 派生只读常量

目标是执行作者只读、随本次 uniform 输入确定的派生值，保持原表达式和求值位置语义；不将它们冒充 GLSL 编译期常量。[GLSL §4.3.2–3](https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.4.60.html#constant-qualifier)要求 global const 使用 constant expression；[HLSL 变量限定符](https://learn.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl-variable-syntax)区分 shader 内只读与 uniform。本合同是本项目作者方言的有界适配，公开规范与真实输入不代表已取得固定官方客户端像素等价。

## 唯一职责与数据流

原 contract/预处理源保真 → generic source normalizer 的只读初始化事实 → 现 GLSL/SPIR-V/MSL 编译器 → 原 Program、uniform binding、graph 和 compositor。仅在准备期移除已证声明的编译期 const 限定符，保声明顺序、RHS、名称绑定及每 invocation 私有初始化；由现编译器生成入口局部存储。不得复制 RHS 到每处使用、Host 求值、增加 uniform/资源/context、getter 或第二初始化 owner。bounded emitter 仍保原拒绝，不能把 generic 的资格冒充两 backend 都支持。

callee 唯一性、遮蔽及按值形参类型由既有 `SceneAuthoredShaderFunctionSemantics` 共享；Prefix 保留 const formal 拒绝，generic 常量 consumer 独立要求 callee 其他引用位于函数体内，各自准入政策不在共享事实中合并。

## 准入与失败

- 仅唯一绑定、非数组的浮点 scalar/vector const；RHS 含至少一处 immutable uniform，只允许 literal、已证纯算式和无同名遮蔽的类型构造，先限直接 uniform 依赖，不递归扩展常量图。沿现 SyntaxUnit、binding/type 和 token-span 事实，不新建 lexer/parser。
- 所有 exact-binding 使用必须只读；重名/局部或形参遮蔽、component/整体写、out/inout/未知 consumer、数组维度/编译期用途、未知调用、采样、varying/attribute/builtin invocation 输入、依赖环或不完整证据均保留原 source 并交原拒绝/局部降级。静态 const、一般 mutable global、矩阵/整型/布尔和其他 storage 不由本片扩域。
- scalar/vector 广播仍由原转换 owner 负责，其类型准备使用既有 analyzeForTypeConversions；严格循环执行门继续归 bounded Frontend，不能因动态循环出现而跳过纯类型准备，也不能借类型事实开放执行。

## 验收与退出

同一输入经改名、括号/等价表达与相邻拒绝例；断言原声明/RHS/绑定保留、幂等、unknown 不改。两组不同 uniform 值须经过真实 generic 编译及 Metal readback，验证本次输入立即生效且不跨 invocation 保留；MSL 必须展示入口初始化一次。广播正例另保 bounded dynamicLoop 拒绝。再取真实 active Program、GPU完成、最终合成/下一帧、可归因画面和独立未参与修法样本；音频/pointer/phase/viewport 未对齐不判截图回归，不作性能或整样本结论。

若需一般 mutable global、新初始化 context，或再遇新的未界定首门，停止该纵切片并重排队列；不得为样本增加限定符白名单或放宽全部 global。当前支持范围归[Shader覆盖](render-graph-shader-coverage.md)，结果与未覆盖证据归[运行证据](runtime-evidence-current.md)，执行顺序归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。
