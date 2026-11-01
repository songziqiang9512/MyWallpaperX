<!-- document-role: stable-contract -->

# Sampler 来源、公开纹理参数与优先级

Owner：`SceneResolvedMaterialShaderSchema`；支持范围见[能力台账](coverage-ledger.md)。

<a id="authored-texture-companion"></a>
## 作者采样与公开纹理 companion

**采样与唯一来源。** 作者二维采样操作保留传入的坐标、sampler 与显式 LOD；两个 compiler lowering 不得逐次注入 candidate 的 atlas/padding 变换，也不靠坐标形状分析抵消二次映射。无作者 shader 的基础图像由原 compositor 映射一次，完整 effect 输出按单位映射合成。公开纹理元数据由实际选中的本帧 `SceneTextureCandidate` 产生；来源身份、UV/resource metadata 与几何放置分别保留原 owner。

**当前公开 shape。** `g_Texture0…7Rotation: float4`、`g_Texture0…7Translation: float2` 及既有 `g_Texture0…7Resolution: float4` 由唯一 HostUniformSchema 裁决。Rotation/Translation 只接受准确名称、准确类型、非数组及当前 active sampler，vertex/fragment 读取同槽 typed host 值。准确的 Rotation/Translation 名称即使带作者 default、静态值或动态来源，也不在 schema 失败后改成普通 uniform；准备绑定与 Program source identity 共用这一命名权威，失败限于受影响的 pass/effect。Resolution 的空槽策略另见[下节](#missing-texture-resolution)。

**帧值与身份。** TEX sprite 选帧与原 `uvTransform` 一起发布 `isSpriteSheet=true`，单帧 sprite 也保留此来源事实。Rotation 取 `(xAxis.x, xAxis.y, yAxis.x, yAxis.y)`，Translation 取 `origin`，不再归一化或复制另一份变换；Resolution 取同一 candidate 的 physical W/H、mapped W/H。当前静态资源及已完成映射的 graph/provider 输出为 non-sprite，公开 Rotation/Translation 编码为零；这是有界非 sprite 观察下的项目消费策略，未证明所有官方 provider 都恒为零。

sprite 来源事实参与 publication atom 比较和 Program exact texture identity，不选择 shader variant，也不进入 pipeline semantic identity。encoder 每帧读取当前 candidate，复用原选帧、contentGeneration、commit/discard、registry、GPU completion 与 compositor，不增时钟、反射或摘要。reader 的合法资源范围不由本合同扩大。当前 slot 8…12、MipMapInfo 及其他未准入 family 保持 unknown；这是现有 schema 覆盖，后续合法 family 应沿同一 owner 扩展，不构成永久禁止支持的架构白名单。迁移工件及研究限度归[RF02 实施历史](../history/rf02-public-companion-implementation-2026-10-03.md)与[原设计归档](../history/rf02-authored-texture-coordinate-design-2026-10-03.md)。

<a id="missing-texture-resolution"></a>
## 空槽 Resolution 的有界消费策略

真实资源使用原 Resolution dependency/host 路径；self-composite 沿其已准备来源合同，不能借另一纹理的尺寸。当前缺失 Resolution 中性化只用于无默认纹理、template/frame 均是真实空槽，且完整 shader 已证明精确成对 UV 归一化的情形，保留作者运算顺序，prepared typed 值为名义 `[2,2,2,2]`。下游可经 helper、循环或多处消费，不能把此值推广到任意绝对尺寸用途。该数值是现有等价消费策略，不是所有缺图 shader 的公开默认，也不是未来合法尺寸语义的永久准入门。

Template 的非空槽身份（包括 pending）在准备期贯穿 schema、两种 frontend 与缓存，不能因当帧未 ready 被误当空槽。默认纹理由原 contract parser 判定；声明含混或解析覆盖不足时保留资源需求。bounded frontend 尚未准入的 uniform 数组仍是当前 frontend 能力缺口，不据此认定 Program 数组 consumer 已支持，也不把它提升为全局架构禁令。等价表达、改名、非空/pending、默认声明及绝对尺寸反例归[有界行为记录](../history/missing-resolution-normalization-2026-10-12.md)。

<a id="effect-texture-reduction"></a>
## Effect 纹理缩减参数

项目目前没有全局纹理质量缩减；非数组 scalar float `g_TextureReductionScale` 仅在 effect-context 由唯一 HostUniform enum → 共享 schema → encoder 提供中性值 **1**。source/base 同名值保留原 authored/static/dynamic 来源。局部上传或 target cap、physical/mapped padding、作者 FBO scale 都不能代作该值；不新增 frame 字段、尺寸推断或第二 owner。错误类型、数组及作者来源冲突沿原局部失败边界处理；未来引入真实全局质量策略时，须由该 owner 替换常量并重验，不叠加第二路径。

固定官方 2.8.0.42 自有 ordinary solid/text、图层/窗口缩放及 FBO scale 1/2/4 的有效输出均与 1 相容；全局质量档、HDR、透视未测，不据此宣称全域公式。验收核 host scope/身份/冲突反例、顶点 GPU 输出与 target 缩放独立，以及真实 effect 和最终可见贡献；历史证据归[实施记录](../history/effect-texture-reduction-2026-10-11.md)。

<a id="effect-working-geometry"></a>
## Effect 的工作采样几何

effect texture projection 对应该层最终实际提交给 graph 的卡片：fullscreen 使用 canonical output geometry，普通 image、Puppet、composition 使用其 live emitted world geometry。采样源的 logical extent、UV/resource metadata 与 output placement 分责，不能用 source texture 尺寸代替 world/放置矩阵；尺寸 planning 消费已准备 source product 的 extent contract，不能由各 effect 在帧内覆盖。

无 imported image `size` 的透明 direct-draw unit quad 先形成 prepared output-geometry 合同。当前已证 source-less carrier 保留半个作者画布的基底及作者 layer/world scale；只有所有 launch variant 的精确 combo 与 prepared shader 都证明同一静态 active-content 边界，才携带归一化局部 inset 校正内容锚点，且不改变 carrier extent。动态、歧义、非有限、variant 不同或未证明形态沿已有居中 carrier，不按 effect 名猜 placement。该 proof 范围是现有几何能力，未来输出形态沿原 geometry owner 扩展。

作者四点、方向等参数原样进入 Program；geometry compiler 只消费已证明的输出覆盖事实。frame preflight 按 prepared geometry source 求值一次，同一 output MVP 交给 target sizing、effect projection 与最终 compositor，后续阶段不重算第二套放置。新增参数沿 typed source/现有 producer 接入，不在 frame preflight 增加 effect/sample 特判。

## Sampler 缺省输入与显式声明

`implicitFramebufferSlots` 只补齐未声明 material 角色的 slot 0。显式 material 必须经现有 alias、authored candidate 或完整 effect-input/color-carrier 证明的 dormant 路径裁决；未知 material 不因 slot 0 自动成为 framebuffer，label 不提供来源身份。有证明的 hidden 任意 key 保留 dormant provenance；未知角色局部失败。已证作者中文 `material=上一个` 与 `ui_editor_properties_framebuffer` 共用隐藏、regular、slot 0 `g_Texture0` 的既有 alias 规则，绑定当前 layer source 或前一个 active effect；只写 label 不成立，显式资源和实际生效的 default 仍先裁决，缺图 identity 仍拒绝。不按样本分派，不另建绑定 owner。

<a id="declared-framebuffer-binding"></a>
## 显式声明 FBO 的准备期覆盖

末候选为 explicitBinding 且指向 graph framebuffer 时，原 TextureSelection 的 immutable override 连 absent 也不回落 lower；launch/demand 同样先选 graph。原 TemplateCompiler 因先解析旧字符串而整拒有效pass，是准备职责与实际消费分歧。沿原 textureSlots 将此类执行候选一次投影到 terminal，raw diagnostic 保留每项原值、provenance 与 ordinal；terminal 仍经原 textureReference 的 context/universe/node-binding 证明，不复制校验，不解析实例后缀或扩大 RT Vocabulary。

仅此 framebuffer 身份覆盖不可达值；previous 的 layerSource/effectOutput、普通资产、可选 provider 及 source material 路径原样。原 selected kind 自然进入模板/分析身份，无新字段、owner、缓存或普通帧工作。源数据与诊断保真；删去无消费者的低候选准备，不在 renderer 中补伪纹理或历史。

验收沿真实Resolver/Template验证改名与等价输入、完整diagnostic及foreign/undeclared/错槽/无context拒绝，已有unavailable override门保持最小失败边界；Debug后原包须到实际Program/GPU/末合成/次帧和可见贡献，独立同类样本保history/后缀/停止。若进入新首拒或贡献无法归因，只记录当前边界，不称整层恢复；不为清日志增加fallback或扩motionblur算法。

<a id="captured-main-self-override"></a>
Captured-main 的当前源角色复用 schema 已证明的精确 slot/input ingress fact；`.sameLayerCompositeDefault` 同时覆盖 shader 自身的同层 default 与作者显式同层 composite 候选链。候选链已生效时，闲置 asset default 不再否定该证明；mode、身份、活跃唯一源、binding/target、完整ready闭包及全链同层约束仍归原 owner，foreign/mixed 不成为当前源。GraphExecutor 先成功捕获并发布精确 ready ingress，再沿同一 implicit identity finalize；不为通用 TextureSelection 合成 absent 状态增加第二关卡，其真实 fallback 规则保持。验收含有/无override、改名/等价表达、idle default与真实default、foreign/mixed、未ready、内部FB及原样本实际Program→GPU→输出，不以旧日志或sourceSlot单值代像素。

Direct static model：仅在 authored texture 与 user 请求皆空时，schema 提供普通颜色 sampler 默认资产，descriptor 保存 `staticModelDefaultAlbedoAssetPath`；VFS/loader 加载 straight albedo，沿原 draw、深度、阴影和 compositor 消费。comparison sampler 不参加数值 uniform 证明；这不授权其采样或 shadow 路由。默认事实独立于 uniform `.unavailable`；`.rejected` 仍拒绝部件。帧内不解析或分配默认输入，保留 authored slots/readiness combo。

该模型默认通道的显式坏路径、加载失败和 named provider 未就绪不回落默认。无 default、条件同名/条件 include、宏改写/别名/生成声明、数组、冲突、非颜色用途和 internal target 不扩大准入。只在已证明默认资产范围退出 nil 即跳过；不采用所有空输入补白或 shader 名特判。元数据核 graph 身份、完整声明、combo 名和宏；固定模型不执行 custom shader，不因无关 variant 准备失败丢弃无条件默认。其 declaration reflection 保留原名，不能替代宏检查。

验收：自有默认白/彩色、null/省略、显式/user 优先及上述拒绝反例，经 reader→prepare→frame→Metal 验像素和释放，再做 Debug build 与隔离真实模型。官方自有 generic4 plane 黑盒仅证明固定条件下 null/省略仍绘制且等价白输入、坏资源不同；不推出内部机制、MDL/normal/reflection 或全样本 parity。shader fixture 改源码同步摘要，缓存隔离且冷/热结果一致；测试与运行范围不能互相替代。
