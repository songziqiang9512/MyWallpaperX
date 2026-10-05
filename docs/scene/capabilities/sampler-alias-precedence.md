<!-- document-role: stable-contract -->

# Sampler 缺省输入与显式声明的优先级

Owner：`SceneResolvedMaterialShaderSchema`；支持范围见[能力台账](coverage-ledger.md)。

`implicitFramebufferSlots` 只补齐未声明 material 角色的 slot 0。显式 material 必须经现有 alias、authored candidate 或完整 effect-input/color-carrier 证明的 dormant 路径裁决；未知 material 不因 slot 0 自动成为 framebuffer，label 不提供来源身份。有证明的 hidden 任意 key 保留 dormant provenance；未知角色局部失败。不按样本分派，不另建绑定 owner。

Direct static model：原资源准备将 nil slot 0 部件直接跳过；现在仅在 authored texture 与 user 请求皆空时，schema 提供普通颜色 sampler 的默认资产事实，descriptor 保存 `staticModelDefaultAlbedoAssetPath`，既有 VFS/loader 加载 straight albedo，沿原 frame draw、深度、阴影和 compositor 消费。默认事实独立于 uniform `.unavailable`；`.rejected` 仍拒绝部件。普通帧不解析或分配默认输入，不改变 authored slots/readiness combo。

显式坏路径、加载失败和 named provider 未就绪不回落默认。无 default、条件同名/条件 include、宏改写/别名/生成声明、数组、冲突、非颜色用途和 internal target 不扩大准入。只在已证明默认资产范围退出 nil 即跳过；不采用所有空输入补白或 shader 名特判。元数据核 source graph 身份、完整潜在声明、combo 名和宏；固定模型不执行 custom shader，不因无关 variant 准备失败丢弃无条件默认。其 declaration reflection 保留原名，不能替代宏检查。

验收：自有默认白/彩色、null/省略、显式/user 优先及上述拒绝反例，经 reader→prepare→frame→Metal 验像素和释放，再做 Debug build 与隔离真实模型。官方自有 generic4 plane 黑盒仅证明固定条件下 null/省略仍绘制且等价白输入、坏资源不同；不推出内部机制、MDL/normal/reflection 或全样本 parity。shader fixture 改源码同步摘要，缓存隔离且冷/热结果一致；测试与运行范围不能互相替代。
