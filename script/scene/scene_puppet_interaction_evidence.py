"""Correlate Puppet geometry submission with input edges and terminal frames."""
from __future__ import annotations
import datetime
import re


def _time(line: str) -> float | None:
    try:
        return datetime.datetime.strptime(line[:23], '%Y-%m-%d %H:%M:%S.%f').timestamp()
    except ValueError:
        return None


def collect_puppet_interaction_evidence(log: str, layer_ids: list[int], *, response: str) -> dict:
    failures = []
    if response not in {'spring-return', 'no-capture'}:
        return {'passed': False, 'failures': ['unsupported Puppet response'], 'layers': []}
    edges = {}
    sources: dict[int, list[dict]] = {layer: [] for layer in layer_ids}
    terminal: dict[int, set[int]] = {layer: set() for layer in layer_ids}
    for line in log.splitlines():
        fields = dict(re.findall(r'(\w+)=([^\s]+)', line))
        timestamp = _time(line)
        if fields.get('phase') == 'pointer-state' and fields.get('state') in {'press','drag','release'}:
            edges[fields['state']] = timestamp
        try:
            layer, frame = int(fields.get('layer', '-1')), int(fields.get('frame', '-1'))
        except ValueError:
            continue
        if layer not in sources or timestamp is None:
            continue
        if fields.get('axis') == 'graph-execution' and fields.get('gpuCompletion') == 'completed' and fields.get('compositorConsumed') == 'true' and fields.get('outcome') == 'succeeded':
            terminal[layer].add(frame)
        if fields.get('phase') == 'puppet-bone-output':
            if fields.get('gpu') != 'completed':
                continue
            try:
                sources[layer].append({'frame': frame, 'time': timestamp,
                    'revision': int(fields['revision']), 'hash': fields['geometrySHA256'],
                    'script_written': fields.get('scriptWritten') == 'true',
                    'displacement': float(fields['maxBindDisplacement'])})
            except (KeyError, ValueError):
                failures.append(f'{layer}: malformed geometry evidence')
    if any(edges.get(key) is None for key in ['press','drag','release']):
        return {'passed': False, 'failures': ['missing input edges'], 'layers': []}
    if not edges['press'] < edges['drag'] < edges['release']:
        failures.append('input edges are not ordered')
    rows = []
    for layer, records in sources.items():
        before = [r for r in records if r['time'] < edges['press']]
        held = [r for r in records if r['script_written'] and r['time'] > edges['drag']]
        if response == 'no-capture':
            held = [r for r in records if edges['drag'] < r['time'] < edges['release']]
        settled = [r for r in records if r['time'] > edges['release'] + 4]
        if len(before) < 2 or not held or len(settled) < 3:
            failures.append(f'{layer}: missing baseline, held or settled geometry samples')
            continue
        baseline = before[-1]['hash']
        changed = [r for r in held if r['hash'] != baseline and r['displacement'] > 1]
        matching = [r for r in settled if r['hash'] == baseline and r['displacement'] < 0.001]
        terminal_changed = [r['frame'] for r in changed if r['frame'] in terminal[layer]]
        terminal_return = [r['frame'] for r in matching if r['frame'] in terminal[layer]]
        if response == 'spring-return':
            if not terminal_changed:
                failures.append(f'{layer}: no deformed geometry with same-frame terminal compositor')
            if len(terminal_return) < 3:
                failures.append(f'{layer}: no exact geometry return through terminal compositor on later frames')
        else:
            if any(r['hash'] != baseline or r['script_written'] for r in records):
                failures.append(f'{layer}: outside capture changed geometry or wrote pose')
            if not any(r['frame'] in terminal[layer] for r in held) or len(terminal_return) < 3:
                failures.append(f'{layer}: no-capture lacks held and later terminal compositor evidence')
        rows.append({'layer': layer, 'baseline_sha256': baseline,
            'max_held_displacement': max((r['displacement'] for r in held), default=0),
            'deformed_terminal_frames': terminal_changed,
            'returned_terminal_frames': terminal_return,
            'source_samples': len(records), 'response': response})
    if not rows:
        failures.append('no Puppet output evidence')
    return {'passed': not failures, 'failures': failures, 'layers': rows}
