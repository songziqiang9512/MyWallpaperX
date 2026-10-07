# Puppet 部件裁剪合同

<!-- document-role: stable-contract -->

本页拥有有界 Puppet 裁剪的准备、绘制与失败合同；能力等级见[高级对象表](advanced-object-coverage.md#34-puppet-部件裁剪)，运行身份和验收见[当前证据](runtime-evidence-current.md#e-2026-10-08-puppet-clipping)，实施过程见[历史记录](../history/puppet-clipping-2026-10-08.md)。未证语义保持关闭，不以样本 identity 选择算法。

## 输入与准备

- `MDLV0023` 已证 suffix 保存 16-byte draw-part ranges 与 clipping records。target/source 是零基 part ordinal；保留原 id、flags 和 options，仅接受已证形状。range 必须按序完整划分原 indices，合法 `count=0` part保留原ordinal、不推进index offset，不能压缩表；target 唯一、引用合法；self 与重复 source 在 IR 中保真，执行时排除 target 自身。精确七零字节的无stream/parts/clips后缀兼容返回空IR，包含既存stride48输入；只接受exact length/bytes，不吞畸形populated metadata。未知布局、坏范围或重复 target 拒绝该 mesh，不用完整白 atlas 代替。
- Load 沿现有 TextureLoader 的 preserved-channel 路径读取 R8 paint；关系、资源与依赖顺序在准备期建立。执行source列表仅准备一次，去重并排除self与空part；原DTO的ordinal和source数组不变。额外 vec3 stream 保留边界但不参与变形，旧版无 clip 的 mesh 继续原直绘。普通帧不重读格式、纹理或重建关系。
- 有贡献的source若也是被裁剪target，则先准备其coverage；空part不形成coverage依赖，也不使健康source的union失效。用有界迭代拓扑顺序处理嵌套；cycle 及其真实下游保持不可用，独立分量继续。不新增 graph、clock、pose 或最终输出 owner。

## 当前帧与绘制

- Playback 产出的同一当前 pose 顶点、vertexCoverage 和 attachments 继续供脚本、几何与最终合成消费。静态和动态 mesh 共用 `ScenePuppetClipping` 的辅助准备/原 part 顺序绘制。
- GeometryProduct 在颜色 encoder 前准备 model-local R8 coverage。main 复用 MainPassEncoder 的 offscreen 边界；named provider 在其颜色 encoder 前调用同一路径，分别使用实际 consumer 的 extent/MVP，不拿 main 的采样域代替 named。
- ROI 由变形后 target bounds 和保守投影采样密度决定，增加一格透明边界；paint/ROI 线性采样、边界零覆盖。不得以 authored size 截断动画，也不任意缩成固定分辨率。
- opaque source 的重叠采用 max coverage；paint 取 red，nested source 再与其已准备 coverage 相交。这是有界项目执行合同：固定官方黑/白/128、单 source/两 distinct 同几何 source 对照支持 opaque 重叠不重复累积 paint；不声称恢复官方内部 raster 或全部灰度算法。
- source 顶点 coverage 仅接受 `1±0.0001`；非一骨骼 alpha 的 source 合并规则未证，使依赖它的 clip 局部不可用。target 自身仍沿现有顶点 alpha 与裁剪 coverage 合成。nested 有真实 GPU 输入/输出门，官方 nested 数值 parity 尚未证明。
- R8 lease 归现有 OffscreenTexturePool/资源预算，key 区分 owner、clip、采样域和 extent；资源由 submission pin 保留至 GPU 完成。每次 consumer/submission 重新准备 readiness，取消、失败或 resize 不复用陈旧 mask。
- ImageLayer 与 ColorBlend 在原 mesh 上采样 atlas/graph-final，将裁剪 coverage 只乘一次 premultiplied RGBA。普通 quad 和每次后继 draw 明确关闭裁剪状态；effect graph、颜色混合及唯一 compositor/output 不另建路径。

## 失败与未证范围

缺 paint、非 R8、预算不足、辅助 encoder/ROI 不可用或未准备的 nested 依赖，只隐藏对应 target 和真实下游；健康 part、附件与邻层继续。identity/generation 或格式越界按既有 publication/mesh 安全边界拒绝，不用无裁剪画面回退。

尚未证明：fractional source vertexCoverage 的合并、官方 nested/软边像素 parity、更多 MDL/record 形状及未知 flags/options、任意深度/性能与完整 Workshop 兼容率。上述范围不能由单样本闭眼恢复或本地 GPU 门升级。

## 验证与维护

最近门：`test_scene_puppet_clipping`、`test_scene_puppet_clipping_shader`、`test_scene_puppet_clipping_render`、`test_scene_puppet_clipping_pool`、`test_scene_puppet_buffer_publication`、`test_scene_geometry_auxiliary_lifetime`。它们分别检查格式边界、RGBA/union 输入输出、nested/cycle/局部失败、pool identity/预算/pins 和旧几何保留，不替代固定官方或产品画面验收。

扩展未知 profile 前先修订本合同并取得能区分行为的官方输入；运行结果只写入证据owner。设计批准登记指向本稳定合同，实施与回归证据归档，仍待证明的能力由断点队列推进；设计批准不代表完整样本、性能或官方parity通过。
