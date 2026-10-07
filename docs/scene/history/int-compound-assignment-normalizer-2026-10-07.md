<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。工作卡与验收门见[断点队列 QF 段](../roadmap/scene-open-breakpoint-queue.md#qv-visual-repairs)。

# int 复合赋值 normalizer：`bar *= step(...)` 拒编译修复（2026-10-07）

起点 `2d225f5f`（批A 后工作树）。承接用户点名样本 3809618616（全屏渐变色）：`Simple_Audio_Bars` 作者 shader 在 `int bar` 上 `bar *= step(...)`——GLSL 任何版本都拒绝 float→int 赋值（author.frag:273/274 `'assign': cannot convert from 'global highp float' to 'temp highp int'`），官方 D3D 管线隐式截断接受。两个全屏 composelayer（层 19/29）的 bars 效果被 stage-link 整体拒编译→`gradient_color`（Hue Speed 0.3）独自在透明捕获上全屏执行=整屏旋转渐变。

## 修复（1 产品文件 + 合同同步）

`SceneGenericShaderSourceNormalizer+Rewrites.swift` 的 `rewriteFloatToIntAssignments`（既有 plain `=` 截断改写器）扩展复合赋值：`*=`、`+=`、`-=`、`/=` 在 LHS 为 int/uint 声明、RHS 含 float atom、非纯整、非显式转换、无顶层逗号/嵌套赋值/链式复合时，整句重建为 `lhs = int(lhs op (rhs))`——与官方隐式截断逐语义一致。守卫与 plain 分支共享（`declaredScalarVectorTypes` 类型表、`explicitConversion` 防双包、`rhsTopLevelCorrupts` fail-closed）。普通 `=` 分支逐字节不变。登记的 fail-closed 残余：`%=`（GLSL `%` 整数域，无机械截断形式）、vertex 阶段（调用点仅 fragment）、qualified member LHS `foo.bar`（裸名类型表会丢限定符，guard `tokens[index-2].text != "."` 拒绝）。

## 验证（2026-10-07，隔离根 /private/tmp/mwx-sample4）

- 3809618616 端到端：修复前 4 条 stage-link 拒绝（两实例×两 profile）+ 全屏渐变；修复后零拒绝、benchmark **PASS failures=[]**、150 根频谱柱+渐变可见（审查修复后的二进制复跑确认）。底图照片层（model 引用 genericimage4）不可见为批B 前既有（修复前 frame 0 即纯渐变），归批D。
- 门禁：`verify_scene_change.py --phase inner` 推导 22 模块——首跑 20 OK + 2 红；1 红为本批 P0（既有测试断言复合赋值 fail-closed，与新合同相反，已按新合同重写该测试：compound 期望 `bar = int(bar * (step(...)))`、新增 `*=`/uint/纯 int/float LHS/显式转换五类反例）；另 1 红=`test_scene_shader_preparation_census` 为 **HEAD 预存红**（9ad62c7e 增加 `SceneBuiltinShaderIdentity` 引用未更新 census 源清单；干净 HEAD worktree 复现同签名），本批顺带偿清（census `CURRENT_SOURCE_PATHS` 补基名条目）。复跑 2/2 OK，合计 22/22。
- 结构门：scene-dependencies PASS、scene-defense ratchet holds、repository-residue PASS、code-health PASS、design-gate pass。

## 独立审查

首轮 REJECT 抓出：P0 既有测试断言未同步（实测转红兑现）、P1-1 函数注释反向描述、P1-2 qualified LHS 限定符丢失（`foo.bar *= f` 会改写为丢 `foo.` 的错误程序）、P2-1 链式复合赋值嵌套 span、P2-2 `%=` 残余、P2-3 热路径数组分配。全部处置后提交复核（结论见提交信息）。

## 边界

- 修复只覆盖 fragment 阶段作者 shader 的四则复合赋值族；`%=`、vertex、qualified LHS 三类残余已登记（同函数注释）。
- 官方行为依据=该 shader 在官方客户端正常编译（D3D 隐式截断）；未做新官方黑盒实验。
- 3809618616 的底图层照片缺失不在本批范围（批D model→material 路由）。
