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

## 默认mask补接（2026-10-15）

<a id="default-mask-followup"></a>

基线`be785aa9c`的准备期白名单探针确认：2960821850的215/effect0终端owner、graph与float3静态色均成立；mask1为opacityMask及asset default，作者槽缺席，旧Eligibility错误拒绝。只在该缺席分支复用原`hasTypedAuxiliaryDefault`，显式override仍须非空all-assets；原resolver继续检查purpose/readiness/publication和既有noise缺失替代。探针已撤，无新算法、profile、资源或输出owner。

最终Debug App SHA-256 `8ddd05c9a691cdc1dbbf28bac0e6e4b35a21b7dae67ec6cc25b0d1705f19e9eb`；唯一产品文件SHA `07d5370cfa7df1c1ed81d5291abe3e1d3cf1c19b3b228a0fd0c94df1a6627f26`。相同原包副本的frame0/1均由目标0材质/4拒绝变4/0，后继1–3效果与末compositor消费成立；全帧24→28材质、7→3拒绝，余项均visibility-disabled。真实画面已查，原参数模糊差异小，不计整图视觉闭合或parity。未参与修法的3248220186球粒子/光束/时间实际呈现，frame0/1为9材质、0拒绝；三次运行均正常退出、GPU排空。

新自有CPU门实际经过parser→preparation→原analyzer/schema/purpose→Eligibility，变量/资源改名和采样别名正控，以及default/type/override/identity/color/owner反例共5正/16反全部成立，2测试通过；235源码无漂移。它不证明资源加载或GPU像素，真实输出由上述App运行补足。一次最终独审接受，无可行动P1/P2；只登记最近门，不重复整矩阵，无性能收益声明。

最小身份/日志/前后截图与收据保在`.artifacts/tmp/n05-prepared-probe-20261015/`；全局证据缓存原已超1GiB预算，不扩容、不删未知证据。本轮可重建样本/HOME/缓存、重复截图和生成源码清理，继续复用原单份构建缓存。多屏、HDR物理显示、属性全组合、长期运行与完整画面仍未验。

<a id="zero-axis-followup-20261019"></a>
## 零轴采样量后继（2026-10-19）

沿[同一准入合同](../capabilities/previous-blurred-composite-admission.md)，唯一GraphAdmission将采样量下界`.01→0`，接受非负且Double/Float均有限的原值，包括合法scalar、单轴/全零及微小正数下溢；不改作者值、kernel或四pass/双FBO scale4、两pass同源、source/state/producer与资源门。全零仍执行downsample/combine，不是跳效果；负轴、非有限/溢出、错shape/pass值和零extent等相邻拒绝保持。

准入11个方法由旧11语义subtest红转绿（3.652s），含变量/资源改名、等价表达及非法邻例。复用现自有3tap/四pass/双FBO与二维方块尺，四次App门分别通过横轴、纵轴、全零和双正模式的独立ROI及健康后继；保两个settled enabled像素与连续GPU完成index，不把后者说成相邻帧像素同一或显隐切换定相。一次普通Debug固定`0a4bf577d1bc6726c504168f3bddc9d5e9651394`+唯一Swift `369d471b…16df3`，4312输入和44外部闭包无漂移，31.098s/严格签名0，App `d804dce6…cc33`、dylib `4beef3b7…5cbc`；无性能收益声明。

原360同12s/30FPS/after8、原生3024×1964、静音/outside0，不冻结Date或scene clock；before两FAIL/4rejected→after FAIL[]/4material/0rejected，469×4双target实际GPU、末合成及后继成立。666虽无child，却由默认copyBackground=true、passthrough=true捕获背景，后Opacity alpha1，不是空透明源；实际细条又被615后画白条盖约93%宽/97%高，早先587二维blur已有平滑。两图camera阶段、UI宽度/y位置不同，实图未辨独立像素收益，不为显影复跑，也不把准入修正说成旧光照或整体画面闭合。

未参与修法的2134765860完整原包仅5s/after3候选短窗，exit0/FAIL[]、正常stop1→0/GPU排空；房间、时钟、吊灯、窗和书架可见，右灰白poster仍在。没有本批旧App配对，不认整样本PASS、旧黑块修复或完整官方parity。独审接受产品与真实运行的上述有界解释；本轮不更改两包unreviewed或旧归档分母。

原失败、准入/GPU与metadata更正收据归`.artifacts/tmp/gaussian-zero-axis-20261019/tests/final-receipt.json`，构建与独审归同根`build-reviewed/receipt.json`、`research/independent-review.json`。实际执行源与后续仅修非消费oracle JSON的可提交测试分别留身份；shader、scene/material、实际prereg/ROI数学与像素断言未变，独审接受且未重复四次App门。原包before正式证据保于`.artifacts/scene-evidence/runs/gaussian-zero-axis-before-20261019`，after、heldout与四GPU模式归`gaussian-zero-axis-20261019`，分别12,142,234/24,360,088B，14天、单包低于32MiB。提升/清理收据核28项正式payload hash；结果无损gzip、确认stop/GPU排空与无打开句柄后精确清13目录700,081,602B，保当前candidate与唯一共享DD，旧roughness App退役。
