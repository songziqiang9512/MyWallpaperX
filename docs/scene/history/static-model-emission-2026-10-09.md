<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。本批已完成过程；当前工作归断点队列。

# 静态模型发光能量修复（2026-10-09）

本批起点 `e1f37d53`，修复 U12 `3477054430` 的楼宇窗户发暗。现役合同归[运行架构](../architecture/runtime-architecture.md)，未完成事项归[断点队列](../roadmap/scene-open-breakpoint-queue.md#qv-cccea6c-user-report)。这份记录不是整样本验收。

## 首错与有界官方合同

原包模型材质、slot 2 mask 和亮度 `7.4299998` 已进入准备链；默认用户参数令作者脚本输出同一亮度，脚本漏接不能解释默认窗户变暗。首错在 `SceneStaticModel.metal`：把 mask alpha × brightness 钳到 0–1，再用发光色替换照明，导致高亮度平台期和照明损失。

先比较“饱和替换”“亮度独立缩放”“照明叠加”，固定原作者 town 几何/相机，隔离灯、雾、Bloom、HDR，仅改变测试副本中的材质参数。未读取私有 shader/blob，未接触反编译实现。自有平面 MDL 在官方全黑，未纳入数值结论；改用已可见 town 几何承载自有常色纹理。

官方 Wallpaper Engine `2.8.0.42`，当次二进制 SHA256 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`。800×450 客户区中，131946 个稳定材质内部像素给出以下观察；预设 U8 容差 3，亮度 1 重测最大差 0。

| 自有输入 | 官方 RGB 中位数 | 可区分结果 |
|---|---|---|
| 灰底 64、发光色 .25、mask 1、无环境光、gain 1 | 16/16/16 | 发光保留底色乘积 |
| 同上 gain 4 | 64/64/64 | 亮度超过 1 继续增加 |
| 黑底、其余同 gain 1 | 0/0/0 | 此 3D profile 不是独立于底色的 2D 发光合同 |
| 灰底、环境光 1、gain 0 | 32/32/33 | 受光基准 |
| 同环境光、mask 1、gain 1 | 48/48/49 | 相同像素 P5/P50/P95 增量均 16 |
| 同环境光、mask 64/255、gain 1 | 36/36/37 | 相同像素增量均 4，不减掉已有照明 |

以上支持本有界输入的加法能量合同；不是未知 stock shader/PBR 或整场景逐像素等价证明。

## 实现与验证

只改原模型着色器的发光与相邻输出运算：保留同一 mask 资源、UV/sampler、材质常量、雾、覆盖和 compositor；亮度使用 Float，与原照明相加。极端有限颜色/亮度在 Float 表示边界保有限，雾和最终预乘后才限制到 half 存储域，避免先截直通 RGB 丢失有效能量。没有新增 owner、样本分派或每帧准备工作。

- 签名 Debug build 通过，4239 个产品输入在构建期间字节不变。App SHA256 `5c24c8c9dc3fc69f2bec9b87bcd453a6e6bec80453085e70d562b0cb380144d4`，dylib `6acfbe5507d1407cf9ffe2c7df2c3c775607a899e38fd8521d4a687298e1a30d`；shader `126d0a638726db6baa61298432762f50c61eaeb3c73f5179a2c4e740c01c9312`。
- 新 GPU 数值门复用既有 harness 和真实模型 pipeline。修前 81 行中 32 行/96 RGB 通道违反加法预期；修后 84/84 完成、有限且在预设两 Float16 ULP 内。涵盖零/部分/完整 mask、gain 0/.25/1/4/10/100000、黑底、缺 mask、彩色、极端乘积、全雾/部分雾及先预乘后存储。
- 既有 pipeline/rendering 11 门、方向光阴影 7 门通过。旧阴影 harness 漏传 `receiverBounds`，已按现产品职责拆分 caster/receiver，并保留无 caster 的 nil 结果；原 oracle 未改。删除一条被实际预乘像素门取代的源码字符串断言。
- 同固定输入的原 App 常色材质输出灰度 16、64，各有 2390381 个像素精确命中官方锚点。视口不同，此项仅证明材质数值，不作完整画面配准。
- U12 原 `scene.pkg` SHA256 `e524945b1152f50c0be83d7f40dfd4003663d86060728737ac78a615826b9dbe`、project `ae4174518663ecc55d78aea6298a09abfccda806caa23997e5b943649efc20cb` 均未改；实际 App 中前景和远处窗户恢复黄色亮光，首帧/下一帧/resize 的终端后处理进入 GPU 与 compositor，退出排空。

## 覆盖与未闭边界

243 包静态复核：255 个 MDL /57 样本，544 个独立样本+材质引用、543 个材料可解析；发光字段并集 11 pass，发光且 slot 2 非空 10 pass/5 样本，brightness seed>1 共 7 pass/4 样本。代表为 U12、`3470948192`、`3437487219`、`3509243656`。同一 App 对 U29 原包运行 30 秒，越过文字 intro 后水滴仍黑，不能把本修复当作 U29 已获视觉收益；其首错仍待独立追踪。这是声明覆盖，不等于四样本视觉通过；U12 star 虽 gain10 但未声明 mask，不据此扩大资源启用。

U12 两项人工主报告中，窗户发光现象已修，整体颜色仍开放；猫受光、月亮 effect 编译、材料脚本与嵌套用户输入、完整文字/媒体仍需后继验证，不能估算为整样本正确率。下批仍处理 U12，优先月亮已复现的 `max` 重载编译拒绝，再辨明 spot 方向；沿现 shader/typed light owner 修复，不调整作者素材或用亮度补偿。

本机原始身份、官方捕获、输入生成器、前后运行与小数值报告保留于 `.artifacts/tmp/u12-color-emission-20261009`；GPU 与小范围 corpus census 保留于 `.artifacts/tmp/u12-emission-trace-20261009`。这些是本机 provenance，文档不依赖载荷长期存在。停止使用的测试资源、HOME、cache 与编译产物按精确归属清理；只留既有 `.build-cache/solid-source-domains-recovery-20261009` 供连续迭代。
