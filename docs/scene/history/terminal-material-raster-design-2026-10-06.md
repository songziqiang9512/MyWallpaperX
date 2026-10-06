<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。现役职责见[运行架构](../architecture/runtime-architecture.md)，后继顺序见[暂停交接](scene-maintainer-handoff-2026-10-06.md)。

# 终端材质的源纹理与显示光栅分离（已完成设计）

本设计的有界实现已在 `fa02f6bf` 验收，现归档，不是待实施任务。稳定职责见[运行架构](../architecture/runtime-architecture.md#terminal-material-raster)，固定运行证据见[实施记录](terminal-material-raster-implementation-2026-10-06.md)。下文保留当时设计；扩大profile或取消重复小光栅属于未来独立工作。

目标是让很小的作者输入纹理仍能产生连续细线。2026-10-06 自有官方黑盒确认：native 3D solid 的输入保持作者 10×10，固定单遍、无 sampler 的 E1152 探针在选定码格读出 reciprocal UV derivative 1235×1235，与投影约 1235.24 相符；高频条纹也排除先在 10×10 执行再放大。768 导数探针低位混合，严格无效，不用于推断。真实材质的独立 Metal 实验只证明采样密度影响断线，不是完整画面对齐。

## 范围与决策

首批限定 native 3D solid、普通 source-over、单个 material pass、无 FBO/history/function/copy/swap、无 graph-final 的其他消费者、无几何网格、额外 terminal alpha 为 1。输入纹理仍按作者尺寸，Candidate、sampler、resolution uniform 不随屏幕膨胀。准入来自 prepared capability 与实际几何/依赖，不能按样本或 shader 名称选择。

采用有界过渡：原 GraphExecutor 仍执行一次真实源捕获与小尺寸 graph 输出，保留原 transaction/publication/state/completion；同一次 preparation 从冻结 Program 派生 terminal draw，只替换 placement uniforms 与 attachment/blend 角色，不重新解析 shader、选择 variant 或执行 VM。terminal draw 在原作者顺序位置由唯一 SceneMainPassEncoder 编码。Program 的源分辨率和逻辑 renderSize 不变，target-pixel 顶点的 MVP 使用 unit-card MVP 乘逻辑尺寸倒数，inverse 同步派生。

PSO 的 offscreen-overwrite 与 terminal-source-over 角色进入原缓存身份，并在原 launch warmup 预热。终端只接受已证明的 associated color 输出；不把 straight color 直接用于 premultiplied blend。源资源仍由原 submission 固定到 GPU completion。

额外绘制确实重复一次小尺寸光栅化；它避免本批同时改写 graph resource/state 模型。独立 typed receipt 绑定 ticket、epoch、prepared pass 和同一 command buffer，声明 terminal Program 已在 main 编码，不冒称内部输出纹理被采样。没有第二套 VM、graph、缓存、提交或 compositor。

## 失败与退出

未满足准入的层保持原链。inactive、activation bypass、visual fallback 没有 terminal draw，消费本帧真实 graph 输出。PSO/binding/uniform 在整帧 preflight 完成；编码后失败遵守原拒帧机制，不能在部分 main 写入后再补画旧纹理。外部消费者、data 输出和其他 blend 不进入该路线。新路线尺寸不得泄漏给尚未准入的效果。

后继若将终端节点直接表达为 compositor destination，必须同时迁移 state/publication/ticket/completion 守恒，再删除小尺寸终端光栅化；不能把 main target 冒充 graph texture。该迁移不是本批完成条件。

## 验证与退役

实际 Metal 验证输入尺寸不变、投影/resize 密度、背景 source-over、变换、PSO 角色隔离及 stale/wrong-ticket/重复消费拒绝；inactive/不支持图保留旧输出。Debug build 后真实太阳系样本确认轨道连续且其他层和拖动不回退。仅报告已进入真实链路的专项进度，不外推完整 parity。职责并入稳定架构、运行证据归档后退役此卡。
