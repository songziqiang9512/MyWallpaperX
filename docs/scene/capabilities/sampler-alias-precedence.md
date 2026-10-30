<!-- document-role: stable-contract -->

# Sampler 缺省输入与显式声明的优先级

Owner：`SceneResolvedMaterialShaderSchema`；支持范围见[能力台账](coverage-ledger.md)。

`implicitFramebufferSlots` 只补齐未声明 material 角色的 slot 0。显式 material 必须经现有 alias、authored candidate 或完整 effect-input/color-carrier 证明的 dormant 路径裁决；未知 material 不因 slot 0 自动成为 framebuffer，label 不提供来源身份。有证明的 hidden 任意 key 保留 dormant provenance；未知角色局部失败。已证作者中文 `material=上一个` 与 `ui_editor_properties_framebuffer` 共用隐藏、regular、slot 0 `g_Texture0` 的既有 alias 规则，绑定当前 layer source 或前一个 active effect；只写 label 不成立，显式资源和实际生效的 default 仍先裁决，缺图 identity 仍拒绝。不按样本分派，不另建绑定 owner。

<a id="captured-main-self-override"></a>
Captured-main 的当前源角色复用 schema 已证明的精确 slot/input ingress fact；`.sameLayerCompositeDefault` 同时覆盖 shader 自身的同层 default 与作者显式同层 composite 候选链。候选链已生效时，闲置 asset default 不再否定该证明；mode、身份、活跃唯一源、binding/target、完整ready闭包及全链同层约束仍归原 owner，foreign/mixed 不成为当前源。GraphExecutor 先成功捕获并发布精确 ready ingress，再沿同一 implicit identity finalize；不为通用 TextureSelection 合成 absent 状态增加第二关卡，其真实 fallback 规则保持。验收含有/无override、改名/等价表达、idle default与真实default、foreign/mixed、未ready、内部FB及原样本实际Program→GPU→输出，不以旧日志或sourceSlot单值代像素。

Direct static model：仅在 authored texture 与 user 请求皆空时，schema 提供普通颜色 sampler 默认资产，descriptor 保存 `staticModelDefaultAlbedoAssetPath`；VFS/loader 加载 straight albedo，沿原 draw、深度、阴影和 compositor 消费。comparison sampler 不参加数值 uniform 证明；这不授权其采样或 shadow 路由。默认事实独立于 uniform `.unavailable`；`.rejected` 仍拒绝部件。帧内不解析或分配默认输入，保留 authored slots/readiness combo。

该模型默认通道的显式坏路径、加载失败和 named provider 未就绪不回落默认。无 default、条件同名/条件 include、宏改写/别名/生成声明、数组、冲突、非颜色用途和 internal target 不扩大准入。只在已证明默认资产范围退出 nil 即跳过；不采用所有空输入补白或 shader 名特判。元数据核 graph 身份、完整声明、combo 名和宏；固定模型不执行 custom shader，不因无关 variant 准备失败丢弃无条件默认。其 declaration reflection 保留原名，不能替代宏检查。

验收：自有默认白/彩色、null/省略、显式/user 优先及上述拒绝反例，经 reader→prepare→frame→Metal 验像素和释放，再做 Debug build 与隔离真实模型。官方自有 generic4 plane 黑盒仅证明固定条件下 null/省略仍绘制且等价白输入、坏资源不同；不推出内部机制、MDL/normal/reflection 或全样本 parity。shader fixture 改源码同步摘要，缓存隔离且冷/热结果一致；测试与运行范围不能互相替代。
