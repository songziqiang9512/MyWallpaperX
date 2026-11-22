"""Read real responsibility files for legacy, pending-migration source assertions.

These assertions remain structural signals, not execution or behavior evidence.
This helper changes neither Swift harness compilation inputs nor product sources.
The explicit families cover only bodies extracted from the two former entry files.
"""
from pathlib import Path

_EXTRACTED_STAGES = {
    'SceneMetalRenderer.swift': (
        'SceneDrawing', 'OrderedLayerEncoding', 'ImageLayerEncoding', 'Submission',
    ),
    'SceneResolvedMaterialExecutionCapabilityVariant+Compilation.swift': (
        'Preparation', 'ColorAnalysis', 'ProviderAnalysis', 'Artifact',
        'Frontend', 'Finalization', 'CompileProfile',
    ),
}


def read_source_family(entry: Path) -> str:
    stages = _EXTRACTED_STAGES[entry.name]
    prefix = entry.stem.removesuffix('+Compilation')
    paths = [entry, *(entry.with_name(f'{prefix}+{stage}.swift') for stage in stages)]
    return '\n'.join(path.read_text(encoding='utf-8') for path in paths)
