<!-- document-role: stable-contract -->

# 二维数据纹理的标量遮罩消费

目标：作者直接读取数据纹理红通道作为标量遮罩时，沿现有 Program 使用真实数据资源，不因编辑器 sampler 模式与 stock 资源用途名称不同而拒绝。

**设计决定（2026-10-12，实施前）。** 既有直接红通道的 noise 用途协调继续保持；对 `opacityMask` sampler，只在 prepared `channelUse=redOnly`、没有冲突 source-purpose fact、候选注册用途为二维 data 时，允许消费该候选原注册用途。normal、noise、preserved、flow、phase、depth 等均保持原上传和 publication，用途不改标为 mask，不新增纹理、typed view 或转换算法。颜色资源与三维 LUT 不在此范围。规则按模式、通道与类型合取，不按样本、资源名称或 hash 选择。

**职责与数据流。** `Sampler.purpose(for:)` 沿已有候选/默认资源仲裁扩展 scalar-data 条件；`TextureSlotPurpose` 保持 ordinal/provenance，原 demand、loader、variant、finalizer、encoder 消费同一注册用途。将既有 variant 私有 data 分类移到 `SceneTextureLoadPurpose`，供两处复用并删除旧分类，避免第二份列表。source-purpose 冲突分支保持原拒绝；候选与 shader default 分别按实际用途检查，normal candidate 的缺席不把 noise default 改为 normal，也不合并二者 identity。

**取舍。** 保留注册资源用途及原物理存储，可复用数据上传与缺席默认资源；把资源强制重标 mask 会改变 cache identity、噪声替代和失败边界，故不采用。只扩现有 scalar 读取链，不重写 Gradient/Mask/Blur。prepared sampler 分析字段不变，运行时用途由现代码重新协调，不盲目失效仍有效的 shader/demand cache。

**失败与退出。** whole-vector、RG/alpha-only、其他声明模式、冲突 source fact、颜色与 volume 资源继续原限制；request、代际、尺寸、采样、物理格式和 Program ABI 仍拒绝最小不安全单元。普通缺资源沿原候选/default及局部回退，不替换素材、不隐藏失败。若后继 compiler/资源仍拒绝，先追该 owner，不扩大本规则掩盖。

**验收。** 自有输入先复现 normal/red mask 拒绝，再验证 schema→真实候选→Program→Metal 输出与两帧。包括变量/资源改名、等价红通道表达式、candidate/default 的 ready/absent、noise 旧规则保持及相邻反例；未知表示、错误用途/identity/generation仍拒绝。检查实际样本目标节点和画面，并用未参与修法的另一真实样本验证实际渲染。只有路由命中、非黑或构建不算完成。

当前能力归[Graph覆盖](render-graph-shader-coverage.md)，实际执行边界归[运行证据](runtime-evidence-current.md)，样本余项归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。本页仅拥有稳定语义与决策；本批过程和未恢复节点另存历史证据。达到上述验收后退役临时 design gate，后续由原 sampler/typed-resource 合同维护。
