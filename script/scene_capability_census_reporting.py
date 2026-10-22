"""Project one conserving census into its compact snapshot and two Markdown reports."""

from __future__ import annotations
import json
from collections import Counter
from typing import Any
from scene_capability_census_io import canonical_sha256
from scene_capability_census_contracts import DOMAINS
from scene_capability_census_samples import summarize_audio_declarations


def render_markdown(
    census: dict[str, Any],
    *,
    sample_markdown_link: str = "scene-corpus-sample-inventory.md",
) -> str:
    summary = census["summary"]
    samples = census["samples"]
    family_rows = sorted(
        census["families"],
        key=lambda value: (
            -value["visible_sample_count"],
            -value["sample_count"],
            -value["visible_occurrence_count"],
            value["family_key"],
        ),
    )
    domain_rows = Counter(item["domain"] for item in census["occurrences"])
    family_domains = Counter(item["domain"] for item in census["families"])
    package_anomalies = [
        (sample, diagnostic)
        for sample in samples
        for diagnostic in sample.get("diagnostics", [])
        if diagnostic.get("code") == "duplicate-package-path"
    ]
    anomaly_lines = []
    for sample, diagnostic in package_anomalies:
        indices = "/".join(str(value) for value in diagnostic.get("entry_indices", []))
        equality = "同字节" if diagnostic.get("content_equal") else "不同字节"
        anomaly_lines.append(
            f"样本 `{sample['sample_id']}` 的 `{diagnostic.get('path', 'unknown')}` "
            f"entry重复（indices {indices}，{equality}；该包 "
            f"{sample['package_entry_count']} entries / "
            f"{sample['package_unique_path_count']} unique paths）"
        )
    anomaly_summary = "；".join(anomaly_lines) or "无"
    lines = [
        "# Scene 全样本能力分类与修复事件台账",
        "",
        "> 状态：现役 corpus 事实、公共结构影响面与修复事件索引。",
        ">",
        f"> 本页由 `script/scene_capability_census.py` 从只读 authored corpus 生成；逐样本材料事实见[静态清单]({sample_markdown_link})。完整 family、样本归属、参数/字段 profile、compact layer/pass/slot occurrence index 与守恒摘要在 `.artifacts/scene-evidence/census/scene_capability_census_snapshot.json`。资源 identity 和详细 owner 事实仅在显式 `query --live` 时从私有 corpus 重建。系统 current capability 只以 `coverage-ledger.md` 为摘要，逐项合同/专题内等级以专项表为准，App/GPU/ROI 证据仍以 `runtime-evidence-current.md` 为准。",
        "",
        "## 1. 当前结论",
        "",
        f"- 当前真实 Scene 根发现 **{summary['discovered_sample_count']}** 个样本，**{summary['parsed_sample_count']}/{summary['discovered_sample_count']}** 的 project、PKGV 索引和入口 JSON 可解析。",
        f"- tracked full-matrix baseline 当前覆盖 **{summary['matrix_sample_count']}** 个历史成员，状态为 `{summary['matrix_coverage_state']}`；该成员关系不表示本轮新增或从未运行。实际播放与人工裁决见[验收台账](scene-sample-acceptance-ledger.md)，本 census 不 join 运行证据。",
        f"- 全量 authored census 共保存 **{summary['occurrence_count']}** 个 typed occurrence、**{summary['family_count']}** 个公共结构 family、**{summary['parameter_profile_count']}** 个参数 profile 与 **{summary['schema_field_profile_count']}** 个 JSON 字段 profile。",
        f"- 物理 corpus 共 **{summary['package_entry_count']}** 个 PKG entry / **{summary['package_unique_path_count']}** 个唯一路径，包体约 **{summary['package_byte_count'] / 1_000_000_000:.3f} GB**；tracked baseline 在单独的 milestone 扩容并建立运行期待前仍为 {summary['matrix_sample_count']}，期间不得称为当前完整快照门。",
        f"- package anomaly：{anomaly_summary}；重复entry继续保留在物理守恒中，不是漏扫。",
        f"- 结构 fallback 记录为 **{summary['unclassified_count']}**，另有 **{summary['generic_or_unknown_family_count']}** 个 generic/unknown/unresolved family；两者都不是运行失败数。本 census 未 join 运行证据的样本，其第一 blocker 保持 `unknown`，不得从静态形态猜测。",
        "- 开发按“真实可见链第一断裂边覆盖的共享 family”排序；大类用于汇总，不允许把所有纹理、Effect 或粒子一次性做成巨型补丁。",
        "",
        "## 2. 口径与权威边界",
        "",
        "1. 本 census 回答样本声明了什么：对象、Effect/Material/Shader/Graph/FBO、纹理、粒子、动态来源和参数形态。",
        "2. `observed`、`resolved`、文件存在或 `repair_state` 都不等于 renderer 已支持；运行 owner、GPU、publication、compositor、next-frame 和 ROI 必须引用运行证据索引。",
        "3. `repair_state` 只描述某个 family 的修复事件工作流。`implemented` 表示该事件所述改动已落地，可能只是保真、拒绝或故障隔离；它不是该 family 的能力实现、current、support 或待办状态。`untriaged` 只表示没有登记该 family 的修复事件，不能解释为 missing、unsupported 或 todo。",
        "4. `family_key` 只由公共语义形态生成；sample/layer/path/hash 只作 evidence identity，产品实现不得按具体值 dispatch。",
        "5. 所有参数以名称、类型、arity、范围、wrapper source 和结构签名记录；只保留 project title 元数据，不复制 layer 文字、shader、SceneScript、纹理、JSON 片段或二进制 payload。",
        "6. 修好一族后在 `scene_capability_repair_ledger.json` 记录根因、公共修法、commit、正反门、真实样本、ROI、剩余边界；重新扫描不会覆盖历史，也不会据此改写 capability current。",
        "7. 先以官方公开资料和当前 corpus 界定作者合同；只有公开材料不足、固定客户端静态证据仍不能回答 producer-to-consumer 链，或需要交叉核对结构时，才读取 MirageWallpaper 的明确固定 revision 并记录 divergence。Mirage 只提供 clean-room 的职责、状态流和顺序参考；其 GPL 源码、shader、资产、payload、常量组合、算法表达和测试数据不得进入项目。",
        "",
        "## 3. 大类总览",
        "",
        "| 大类 | occurrence | family | family 语义/专项入口（非 current 状态） |",
        "|---|---:|---:|---|",
    ]
    authorities = {
        "resource": "[格式/资源](scene-format-and-render-graph.md)",
        "shader": "[Graph/Shader](render-graph-shader-coverage.md)",
        "layer": "[格式/对象](scene-format-and-render-graph.md)",
        "material": "[Graph/Shader](render-graph-shader-coverage.md)",
        "effect": "[Effect](effect-execution-coverage.md)",
        "render-graph": "[Graph/Shader](render-graph-shader-coverage.md)",
        "render-target": "[Graph/Shader](render-graph-shader-coverage.md)",
        "texture": "[格式/资源](scene-format-and-render-graph.md) / [Graph/Shader](render-graph-shader-coverage.md) / [Provider](runtime-input-property-coverage.md)",
        "particle": "[粒子](particle-component-coverage.md)",
        "audio-declaration": "[音频声明](coverage-ledger.md)",
        "dynamic-input": "[属性/输入](runtime-input-property-coverage.md)",
        "project-property": "[属性/输入](runtime-input-property-coverage.md)",
    }
    capability_mapping = summary.get("capability_mapping")
    if isinstance(capability_mapping, dict):
        dev_bullet = "- 开发按“真实可见链第一断裂边覆盖的共享 family”排序；大类用于汇总，不允许把所有纹理、Effect 或粒子一次性做成巨型补丁。"
        if dev_bullet in lines:
            lines.insert(lines.index(dev_bullet), (
                f"- 公共能力粗映射：**{capability_mapping['mapped_family_count']}** 个 family "
                f"按声明形态映射到台账登记能力，**{capability_mapping['unknown_family_count']}** 个显式 unknown"
                f"（`{json.dumps(capability_mapping['unknown_reason_counts'], ensure_ascii=False, sort_keys=True)}`）；"
                "映射只表达声明覆盖关系，不表示运行支持。"
            ))
    for domain in DOMAINS:
        lines.append(
            f"| `{domain}` | {domain_rows.get(domain, 0)} | {family_domains.get(domain, 0)} | {authorities[domain]} |"
        )
    texture = summary["texture"]
    lines += [
        "",
        "### 3.1 纹理本体与使用点",
        "",
        f"- 包内物理 TEX：**{texture['physical_resource_count']}**；格式分布：`{json.dumps(texture['physical_format_counts'], ensure_ascii=False, sort_keys=True)}`。",
        f"- TEX 结构特征：`{json.dumps(texture['physical_feature_counts'], ensure_ascii=False, sort_keys=True)}`。这些只证明文件结构可读，不证明上传、purpose、sampler 或合成正确。",
        f"- 纹理使用 occurrence：**{texture['use_occurrence_count']}**；slot 状态：`{json.dumps(texture['use_state_counts'], ensure_ascii=False, sort_keys=True)}`。`runtime-provided` 是 graph/named target 等运行身份，`missing` 需要结合 default/optional combo/VFS 语义判断，不能一律当缺图。",
        "",
        "### 3.2 对象、Effect 与动态输入",
        "",
        f"- 对象类型：`{json.dumps(summary['object_kind_counts'], ensure_ascii=False, sort_keys=True)}`；静态非 hidden：`{json.dumps(summary['visible_object_kind_counts'], ensure_ascii=False, sort_keys=True)}`。",
        f"- Effect instance **{summary['effect_instance_count']}**，粒子 root layer **{summary['particle_layer_count']}**；动态 wrapper：`{json.dumps(summary['dynamic_feature_counts'], ensure_ascii=False, sort_keys=True)}`。",
        f"- 粒子组件分布完整保存在机器快照 `summary.particle.component_counts`；Effect/Graph/FBO、包内 shader uniform/annotation/combo、material authored combo/constant 与全部 JSON 字段可按 family/profile 查询。active/prepared shader variant 仍以专项 census 与运行证据为准。",
    ]
    audio = summary.get("audio_declarations") or summarize_audio_declarations(
        census.get("occurrences", [])
    )
    lines += [
        "",
        "### 3.3 音频声明与 consumer 意图关系",
        "",
        f"- payload-free 音频关系共 **{audio['declaration_occurrence_count']}** 个 occurrence / **{audio['declaration_sample_count']}** 个样本；其中 editor `supportsaudioprocessing=true` 为 **{audio['project_support_sample_count']}** 个样本，存在至少一种非 project 声明关系的样本为 **{audio['relationship_sample_count']}** 个。",
        f"- 标记有而没有非 project 声明关系：`{', '.join(audio['support_without_relationship']) or '无'}`；有声明关系而没有 editor 标记：`{', '.join(audio['relationship_without_support']) or '无'}`。两者都不是运行支持集合，不能从静态相等或差集推导 capture demand。",
        f"- 静态 consumer 意图为 **{audio['static_consumer_intent_sample_count']}** 个样本：`{', '.join(audio['static_consumer_intent_sample_ids']) or '无'}`。这里只接受精确源码数组形状、显式启用的 material/particle 响应或 proven-global 且分辨率有效的 SceneScript 调用；material active variant/host ABI 与所有运行 execution 尚未 join，因此本批 runtime-confirmed 仍为 **{audio['runtime_confirmed_sample_count']}**。",
        f"- 其中同一 SceneScript owner 同时具有静态准入 AudioBuffers 与显式导出 cursor callback 的意图为 **{audio['cursor_audio_intent_sample_count']}** 个样本：`{', '.join(audio['cursor_audio_intent_sample_ids']) or '无'}`；这只登记实例化候选关系，不证明 hit、事件触发、snapshot refresh 或可见输出。",
        f"- editor 标记有而静态意图无：`{', '.join(audio['support_without_static_intent']) or '无'}`；静态意图有而 editor 标记无：`{', '.join(audio['static_intent_without_support']) or '无'}`。普通 App 运行基线必须覆盖这些差集与全部声明关系，不能只测标记集合。",
        "",
        "| 声明关系 | occurrence | 样本 | 静态状态分布 |",
        "|---|---:|---:|---|",
    ]
    for kind, values in audio["by_kind"].items():
        distribution = {
            "activation": values["activation_state_counts"],
            "script_resolution": values["resolution_state_counts"],
            "script_scope": values["scope_state_counts"],
            "script_admission": values["admission_state_counts"],
            "source_abi": values["source_abi_state_counts"],
            "runtime_admission": values["runtime_admission_state_counts"],
            "cursor_audio_consumer":
                values["cursor_audio_consumer_state_counts"],
            "cursor_events": values["cursor_event_export_counts"],
        }
        lines.append(
            f"| `{kind}` | {values['occurrence_count']} | {values['sample_count']} | "
            f"`{json.dumps(distribution, ensure_ascii=False, sort_keys=True)}` |"
        )
    lines += [
        "",
        "## 4. 当前公共 family 影响面索引",
        "",
        "> 这里只按静态可见覆盖排序，不能自动决定实施。最后一列是修复事件工作流，不是能力状态；`untriaged` 不表示缺失。真正开批前必须由 fresh 隔离运行确认第一断裂边；高频但位于链后段的 family 不得抢占当前可见首断点。",
        "",
        "| family | domain/kind | occurrence | 样本 | 可见 occurrence / 样本 | 修复事件（非能力状态） |",
        "|---|---|---:|---:|---:|---|",
    ]
    for family in family_rows[:80]:
        repair = family.get("repair") or {}
        lines.append(
            f"| `{family['family_key']}` | `{family['domain']}/{family['kind']}` | "
            f"{family['occurrence_count']} | {family['sample_count']} | "
            f"{family['visible_occurrence_count']} / {family['visible_sample_count']} | "
            f"`{repair.get('repair_state', 'untriaged')}` |"
        )
    lines += [
        "",
        "完整 family、payload-free feature summary、样本归属与 revision 数在机器快照中；此表故意只保留前 80 个高覆盖项，避免人类文档成为不可维护的 payload 转储。",
        "",
    ]
    if isinstance(capability_mapping, dict):
        lines += [
            "### 4.1 公共能力映射概览",
            "",
            "> family→capability 是 P0.2 的声明覆盖粗映射（`script/scene_capability_family_map.json` 规则驱动，多对多、可反查）；coarse profile 表示语义差异未细化，不能当能力闭合。映射与运行支持无关；每项能力的真实等级只查 [能力台账](coverage-ledger.md)与专项表。",
            "",
            "| capability | 台账 authority 行 | family | occurrence | 样本 |",
            "|---|---|---:|---:|---:|",
        ]
        capability_coverage = capability_mapping["capability_coverage"]
        vocabulary_rows = census.get("capability_vocabulary", {})
        for capability, bucket in capability_coverage.items():
            authority = ((vocabulary_rows.get(capability) or {}).get("authority") or {})
            anchor_doc = str(authority.get("doc", "")).replace("docs/scene/capabilities/", "")
            anchor_row = str(authority.get("row", "")).replace("|", "\\|")
            lines.append(
                f"| `{capability}` | [{anchor_row}]({anchor_doc}) | "
                f"{bucket['family_count']} | {bucket['occurrence_count']} | {bucket['sample_count']} |"
            )
        unknown_reasons = capability_mapping["unknown_reason_counts"]
        lines += [
            "",
            f"显式 unknown family 共 **{capability_mapping['unknown_family_count']}** 个，"
            f"原因分布：`{json.dumps(unknown_reasons, ensure_ascii=False, sort_keys=True)}`；"
            "unknown 是静态不可判定的显式登记，不是运行失败，也不得据此宣称缺失。",
            "",
        ]
    lines += [
        "## 5. 全部样本清单",
        "",
        f"逐样本的对象、Effect、粒子、occurrence 与人工材料状态见[全样本静态明细]({sample_markdown_link})。此处只导航，实际播放与视觉裁决仍归[验收台账](scene-sample-acceptance-ledger.md)。",
        "解析失败的目录仍在明细中保留 identity、失败原因与实际材料事实；零计数不表示已成功播放。",
    ]
    lines += [
        "",
        "## 6. 修复事件记录与防回归合同",
        "",
        "每个已登记公共 family 的修复事件使用三个独立 workflow/evidence 字段；三者都不是 capability current/support/todo 等级：",
        "",
        "- `repair_state`: `untriaged -> diagnosed -> in-progress -> implemented -> bounded-verified`；",
        "- `runtime_proof_state`: `none -> partial-chain -> visible-chain-closed -> official-golden-equivalent`；",
        "- `regression_protection_state`: `none -> synthetic -> targeted-runtime -> milestone`。",
        "",
        "这里的 `implemented` 只表示该 repair event 描述的改动已落地，可能是解析保真、失败关闭或故障隔离，不表示整个 family 已实现。事件记为 `bounded-verified` 至少要求项目自有 synthetic 正例、反例、真实隔离样本 GPU→publication→compositor→next-frame→ROI 和明确剩余边界；`official-golden-equivalent` 还必须有同相位官方 golden 及像素/时序容差。只降低 rejection 数、只 non-black 或只加载资源不能写成修复完成。",
        "",
        "当前已逐族复核并登记的修复事件见机器 repair ledger 与下表；未列 family 显示 `untriaged` 只表示没有修复事件记录，不是 missing/unsupported/todo，也不会因 effect 名、路径或相邻 family 已修而自动产生 current 结论。",
        "",
    ]
    repaired_families = sorted(
        (
            repair for repair in census["repair_ledger"].get("families", [])
            if repair.get("repair_state", "untriaged") != "untriaged"
        ),
        key=lambda repair: repair["family_key"],
    )
    lines += [
        "| family | 修复事件 / 事件运行证据 / 事件回归保护（非能力状态） | 公共修法 | 真实 sentinel | 剩余边界 |",
        "|---|---|---|---|---|",
    ]
    for repair in repaired_families:
        def markdown_cell(value: Any) -> str:
            return str(value).replace("\n", " ").replace("|", "\\|")

        status = " / ".join(
            markdown_cell(repair[key])
            for key in (
                "repair_state",
                "runtime_proof_state",
                "regression_protection_state",
            )
        )
        sentinels = ", ".join(
            f"`{markdown_cell(value)}`" for value in repair.get("targeted_samples", [])
        ) or "无"
        boundaries = "；".join(
            markdown_cell(value) for value in repair.get("remaining_boundaries", [])
        )
        lines.append(
            f"| `{repair['family_key']}` | `{status}` (`{markdown_cell(repair.get('commit', ''))}`) | "
            f"{markdown_cell(repair.get('public_fix', ''))} | {sentinels} | {boundaries} |"
        )
    if not repaired_families:
        lines.append("| _尚无已登记修复_ | - | - | - | - |")
    lines += [
        "",
        "## 7. 更新流程",
        "",
        "1. 新增/删除样本后先只读运行 corpus census，确认 `discovered = parsed + failed`、occurrence 与 JSON leaf 守恒。",
        "2. authored census 一旦发现样本增删，tracked full-matrix baseline 立即标为 `pending-expansion`，不得再称完整；新样本的运行状态先记为本 census 未 join，随后用独立 milestone 扩容批建立运行期待并更新 matrix。",
        "3. 从 fresh 隔离报告定位首个失败 identity，再按现役通用执行计划选择能让未见内容受益、可局部降级且可独立回滚的公共 primitive；不得把 family 名直接变成产品 dispatch。",
        "4. 先核对官方作者合同和现有固定证据；只有材料不足以解释 producer-to-consumer 结构时才按需固定 MirageWallpaper revision，并记录实际读取模块与 divergence。第三方参考不是每批前置，也不提供算法真值。",
        "5. 同批实现公共代码、synthetic 正反门和与声明相称的代表运行门；只有具体 fidelity 修复才强制真实 ROI。再写 repair event 和必要的专项文档，不建立样本专用分支，也不复制第三方算法或 payload。",
        "6. `targeted_samples` 与 `regression_gates` 是后续必须重跑的 sentinel 合同；触达同 family 或它依赖的 selection/Program/publication/composition 时必须执行，不能用新的 aggregate count 覆盖旧视觉正证。",
        "",
        "生成命令：",
        "",
        "```bash",
        "python3.12 script/scene_capability_census.py generate \\",
        "  --samples-root \"$HOME/Movies/MyWallpaperX/创意工坊/Scene\" \\",
        "  --snapshot .artifacts/scene-evidence/census/scene_capability_census_snapshot.json \\",
        "  --markdown docs/scene/capabilities/scene-corpus-capability-inventory.md \\",
        "  --sample-markdown docs/scene/capabilities/scene-corpus-sample-inventory.md",
        "python3.12 script/scene_capability_census.py verify \\",
        "  --samples-root \"$HOME/Movies/MyWallpaperX/创意工坊/Scene\" \\",
        "  --snapshot .artifacts/scene-evidence/census/scene_capability_census_snapshot.json \\",
        "  --markdown docs/scene/capabilities/scene-corpus-capability-inventory.md \\",
        "  --sample-markdown docs/scene/capabilities/scene-corpus-sample-inventory.md",
        "python3.12 script/scene_capability_census.py query \\",
        "  --family <family-key>",
        "# 需要当前私有 corpus 的详细 resource/owner 事实时显式追加 --live",
        "```",
    ]
    return "\n".join(lines)


def render_sample_markdown(
    census: dict[str, Any],
    *,
    overview_link: str = "scene-corpus-capability-inventory.md",
    snapshot_sha256: str | None = None,
) -> str:
    summary = census["summary"]
    lines = [
        "<!-- document-role: current-state -->",
        "",
        "# Scene 全样本静态明细",
        "",
        f"本页由{summary['discovered_sample_count']}目录的同一次静态观察投影；统计方法、family 及参数汇总归[声明统计]({overview_link})。每行只记作者声明和材料是否存在，不判断缺能力或视觉通过；播放与人工裁决归[验收台账](scene-sample-acceptance-ledger.md)。",
        f"{summary['parsed_sample_count']}个可解析；解析失败目录也保留，零计数不表示成功播放。末列仅记旧{summary['matrix_sample_count']}个 matrix 成员，不表示从未运行或本轮新增。作者 preview 不能代替官方金标。",
    ]
    if snapshot_sha256 is not None:
        lines += ["", f"同次机器快照 SHA-256：`{snapshot_sha256}`。"]
    lines += [
        "",
        f"| 样本 | 标题 | 对象 | Effect | 粒子层 | occurrence | 人工对照 | 旧{summary['matrix_sample_count']} matrix成员 |",
        "|---|---|---:|---:|---:|---:|---|---|",
    ]
    failures = []
    for sample in census["samples"]:
        title = (
            str(sample.get("title", sample["sample_id"]))
            .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace("|", "\\|").replace("\r", " ").replace("\n", " ")
        )
        if sample["has_manual_screenshot"]:
            manual = "截图+说明" if sample["has_user_observation"] else "截图"
        else:
            manual = "说明" if sample["has_user_observation"] else "无"
        member = "是" if sample["in_full_matrix"] else "否"
        lines.append(
            f"| `{sample['sample_id']}` | {title} | {sample.get('object_count', 0)} | "
            f"{sample.get('effect_instance_count', 0)} | {sample.get('particle_layer_count', 0)} | "
            f"{len(sample['occurrence_refs'])} | {manual} | {member} |"
        )
        if sample["parse_state"] != "parsed":
            codes = [str(item["code"]) for item in sample["diagnostics"]]
            failures.append(
                f"- `{sample['sample_id']}`（parse_state=`{sample['parse_state']}`）："
                f"`{'`, `'.join(codes)}`。"
            )
    if failures:
        lines += ["", "## 解析失败目录", "", *failures]
    return "\n".join(lines)


def canonical_json_bytes(payload: dict[str, Any]) -> bytes:
    return (json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def snapshot_payload(census: dict[str, Any]) -> dict[str, Any]:
    """Project the conserving in-memory census into a reviewable Git baseline."""
    samples = []
    for value in census["samples"]:
        row = dict(value)
        occurrence_refs = row.pop("occurrence_refs")
        visible_refs = row.pop("visible_occurrence_refs")
        row.update({
            "occurrence_count": len(occurrence_refs),
            "occurrence_index_sha256": canonical_sha256(occurrence_refs),
            "visible_occurrence_count": len(visible_refs),
            "visible_occurrence_index_sha256": canonical_sha256(visible_refs),
        })
        samples.append(row)

    sample_by_occurrence = {
        value["occurrence_id"]: str(value["location"].get("sample_id"))
        for value in census["occurrences"]
    }
    parameter_profiles = []
    for value in census["parameter_profiles"]:
        profile = dict(value)
        occurrence_refs = profile.pop("occurrence_refs")
        sample_ids = sorted({
            sample_by_occurrence[identity]
            for identity in occurrence_refs
            if identity in sample_by_occurrence
        })
        profile["occurrence_index_sha256"] = canonical_sha256(occurrence_refs)
        profile["sample_count"] = len(sample_ids)
        profile["sample_ids"] = sample_ids
        parameter_profiles.append(profile)

    occurrence_index = [
        {
            "occurrence_id": value["occurrence_id"],
            "family_key": value["family_key"],
            "revision_key": value.get("revision_key"),
            "domain": value["domain"],
            "kind": value["kind"],
            "sample_id": value["location"].get("sample_id"),
            "effective_visibility": value.get("effective_visibility"),
            "location": {
                key: value["location"][key]
                for key in (
                    "layer_id", "object_index", "effect_index", "definition_pass_index",
                    "material_pass_index", "slot_index", "fbo_index", "component_category",
                    "component_index", "package_entry_index", "property_name",
                    "owner_occurrence", "declaration_kind", "json_pointer",
                )
                if key in value["location"]
            },
        }
        for value in census["occurrences"]
    ]
    return {
        "schema_version": census["schema_version"],
        "kind": census["kind"],
        "snapshot": census["snapshot"],
        "summary": census["summary"],
        "samples": samples,
        "families": census["families"],
        "capability_vocabulary": census.get("capability_vocabulary", {}),
        "parameter_profiles": parameter_profiles,
        "schema_fields": census["schema_fields"],
        "unclassified": census["unclassified"],
        "repair_ledger": census["repair_ledger"],
        "validation": {
            **census["validation"],
            "occurrence_index": {
                "count": len(occurrence_index),
                "sha256": canonical_sha256(occurrence_index),
                "storage": "compact-baseline-index",
                "items": occurrence_index,
            },
        },
    }
