<!-- document-role: historical-evidence -->
# 前级与模糊结果公共准入修复（2026-10-12）

> **历史证据 — 非现役入口**。本批已收尾的有界修复记录。目标合同归[准入设计](../capabilities/previous-blurred-composite-admission.md)，当前能力归[图与shader覆盖](../capabilities/render-graph-shader-coverage.md)，开放项归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

修复的通用语义是：作者采样量与 RT 尺寸分离，资源名称不决定合法 Program 的执行权。自有四 pass/two-target metadata 红测确认旧0.01…2准入拒绝2.1/12/32/73及仅改名资源；本批仅改原 GraphAdmission，撤名称helper与上限，保留原下界、finite Float、拓扑、写读、state、producer及后续 source/slot/ABI/whole-Program证明。不新增 Blur 算法、profile、renderer 或fallback；产品净删65行。

## 代码和输入身份

基线 `52552018322dc63bff68c4d8e1747cca0b4930d3`；唯一产品文件 SHA-256 `d5594d4e5f8c5ab4bc17d9c9a9c2cc45fd2f453f69ad0a5839a0f37bab39b50c`。实施前设计已落库并独立接受。中性合同 SHA `6f188711…cc47b78`；实现只消费经审查的 metadata 与完全自有输入，不读取 private GLSL/MSL/SceneScript。旧 stock Blur混合源码测试整体隔离，不作为自有fixture。

本机证据根 `.artifacts/tmp/n05-blur-followup-20261012/` 的 `product-freeze-v1.json`、`product-build-identity.json`、`input-manifest.json`、`heldout-input-manifest.json` 绑定源码/App/helpers及只读原件副本。Debug构建成功；仅隔离App外壳ad hoc，两个编译helpers保原团队Developer ID、无timestamp并通过原team requirement与strict验证；不是Release签名/发布验收。

## 可见与运行结果

3666041758 的layer190两段Blur从每段0材质/4拒绝的整段frontend透传恢复到4+4材质；frame0/1的完整链为16+4+4+1，拒绝0、四图级GPU completed，末effect3 finalConsumer=true。实际窗口截图中尖锐白色中心与粗噪声区域被模糊为平滑渐变；不是单纯profile命中。原主solid138处于作者脚本隐藏状态，141.visibility invalidSource仍独立；官方流体主体与作者输入/显隐状态关系未裁决，不宣布整样本视觉正确或算法parity。

未参与诊断、fixture或调参的2134765860真实前后运行与画面已检查：房间布局、光照、时钟保持，健康246/effect2四材质及最终消费继续成立。每个记录帧37材质、37图级GPU完成、14最终消费；15节点均visibility-disabled跳过，无visual/frontend failure，执行字段与冻结基线相同。四次运行均exit0、ready、surfacesAfter=0、GPU排空；不代表长稳、多屏、全交互或全效果已验。

## 验收门与局限

自有二维颜色尺经真实generic compiler artifact→UniformEncoder→Program→PassEncoder→Metal读回16组像素：12/32/73及(12,32)无裁剪；变量/varying/sampler/resource改名和等价表达式、两source generation保持预期；overflow/nonfinite/错误shape/缺source/未知color共10反例拒绝。metadata门保原userBinding，并补definition/material/shader/FBO全改名、数值/不同pass/格式/state/binding/target邻例。该尺证明typed值和采样结果，不重造或宣称Blur kernel数值对照。

最近Program/动态producer/旧owner近门、effect graph/颜色/属性相邻门、自有GPU门、Debug build及适用治理门通过。graph executor的其余五项通过，汇总项32false仍失败；本次以52552018的284份相同编译/夹具输入独立复跑失败method，32项集合及全部bool结果完全相同，且该门不编译本批唯一改动owner，排除本批新增。证据为`graph-executor-baseline-inputs.json`与`graph-executor-baseline-comparison.json`，未裁决32项的产品/夹具根因，作为验证债保留，不报全部门通过；独立最终审查收据保于本机证据根。既有218-byte `.mimosa`来源未定，residue门仍报保留，不算本批新增。无性能数字、官方逐像素parity或完整数值域承诺；下界与source有界形状按集中例外继续待修。

## 文档归属与产物

稳定设计只拥有目标/边界，覆盖表只记当前有界能力，运行索引与队列只指向本记录；新增短合同与集中例外行的budget调整不复制批次流水账。临时HOME、样本副本、编译probe/cache及冗余ready截图在核验原件哈希/进程退出后清理；保留必要的前后截图、压缩日志、身份与中性收据。全局证据缓存预算不足时不扩大或删除未知材料，精确清理/提取结果记本机cleanup.json。连续迭代仅保留原单份构建缓存供下一批。
