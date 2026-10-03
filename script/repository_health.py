#!/usr/bin/env python3
"""Derive actionable repository signals from existing authorities, without a second debt ledger."""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path

try:
    from script import check_code_health, verify_scene_change
except ModuleNotFoundError:
    import check_code_health
    import verify_scene_change

ROOT = Path(__file__).resolve().parents[1]


def summarize(counts: dict[str, int], health: dict, mapping: dict,
              layout: dict, defense: dict, assertions: dict) -> list[dict]:
    signals = []
    for path, count in sorted(counts.items()):
        if count > health['hardLineLimit']:
            signals.append({'kind': 'hard-limit', 'path': path, 'actual': count,
                            'limit': health['hardLineLimit'],
                            'authority': 'script/code_health_baseline.json',
                            'nextAction': 'Separate actual responsibilities to meet the 1000-line limit.'})
    for path in mapping['unmapped_paths']:
        signals.append({'kind': 'selection-gap', 'path': path,
                        'authority': 'script/scene_validation_gates.json',
                        'nextAction': 'Trace actual consumers and map the nearest existing contract test; report missing tests explicitly.'})
    for row in mapping['mappings']:
        if row['missing_modules']:
            signals.append({'kind': 'missing-test-module', 'path': row['path'],
                            'modules': row['missing_modules'],
                            'authority': 'script/scene_validation_gates.json',
                            'nextAction': 'Repair stale module routing before treating a build as closure.'})
    for rule in layout['render_chain_authority_ratchet']['rules']:
        if rule['role'] != 'inventory' or not rule['baseline_occurrences']:
            continue
        signals.append({'kind': 'frozen-family', 'id': rule['id'],
                        'registeredBudget': rule['baseline_occurrences'],
                        'description': rule['description'],
                        'authority': 'script/scene_source_layout.json',
                        'nextAction': 'Retire duplicate authority within the owning change and ratchet its existing baseline; this is registered budget, not a fresh scan.'})
    for entry in defense.get('canonicalHelpers', []):
        signals.append({'kind': 'canonical-helper', 'id': entry.get('id', entry.get('name', 'helper')),
                        'canonical': entry.get('canonical'), 'registeredCopies': entry.get('allowedCopies'),
                        'owner': entry.get('owner'), 'retirement': entry.get('retirement'),
                        'authority': 'script/scene_defense_baseline.json',
                        'nextAction': 'Use the canonical owner when changing callers; run the existing defense audit before claiming duplicate removal.'})
    shapes = Counter()
    for entry in assertions['entries']:
        shapes[entry['path']] += entry['count']
    for path, count in sorted(shapes.items()):
        signals.append({'kind': 'test-shape', 'path': path, 'registeredCount': count,
                        'authority': 'script/test_assertion_baseline.json',
                        'nextAction': 'Migrate the touched behavior to an executable positive and fault-injected counterexample; detector exclusions remain unmeasured.'})
    for signal in signals:
        signal['actionable'] = 'now' if signal['kind'] in {'hard-limit', 'missing-test-module'} else 'with-owning-change'
        signal['difficulty'] = 'high' if signal['kind'] in {'canonical-helper', 'frozen-family'} or signal.get('actual', 0) > 800 else 'owner-assessment'
        source = signal.get('path', signal.get('canonical') or signal.get('id', ''))
        signal['family'] = 'Compilation' if '/Compilation/' in source or source.startswith('Compilation/') else source.split('/')[0]
    order = {kind: n for n, kind in enumerate(('hard-limit', 'missing-test-module',
        'selection-gap', 'test-shape', 'frozen-family', 'canonical-helper'))}
    return sorted(signals, key=lambda s: (order[s['kind']], -s.get('actual', s.get('registeredCount', 0)), s.get('path', s.get('id', ''))))


def collect() -> dict:
    health = check_code_health.load_current_baseline()
    counts = check_code_health.swift_line_counts(health)
    registry = verify_scene_change.load_registry()
    modules = {path.stem for path in (ROOT / 'script/tests').glob('test_*.py')}
    mapping = verify_scene_change.product_test_mapping(list(counts), registry, modules)
    def load(path):
        return json.loads((ROOT / path).read_text(encoding='utf-8'))
    signals = summarize(counts, health, mapping, load('script/scene_source_layout.json'),
                        load('script/scene_defense_baseline.json'), load('script/test_assertion_baseline.json'))
    return {'evidenceLimit': 'Derived inventory and routing signals only. No test/build/runtime gate is executed; registered budgets are not measured violations.',
            'swiftFiles': len(counts), 'productFiles': len(mapping['product_paths']),
            'mappedProductFiles': len(mapping['mapped_paths']),
            'unmappedProductFiles': len(mapping['unmapped_paths']),
            'signalCounts': dict(sorted(Counter(row['kind'] for row in signals).items())),
            'signals': signals}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--format', choices=('text', 'json'), default='text')
    parser.add_argument('--limit', type=int, default=20)
    parser.add_argument('--path', help='exact repository-relative path to inspect')
    args = parser.parse_args(argv)
    if args.limit < 1:
        parser.error('--limit must be positive')
    try:
        report = collect()
        selected = [row for row in report['signals'] if not args.path or row.get('path') == args.path]
        report['matchedSignals'] = len(selected)
        report['signals'] = selected[:args.limit]
        if args.format == 'json':
            print(json.dumps(report, ensure_ascii=False, indent=2))
        else:
            print(report['evidenceLimit'])
            print(f"Product mapping: {report['mappedProductFiles']}/{report['productFiles']}; unmapped: {report['unmappedProductFiles']}")
            print('Signals: ' + json.dumps(report['signalCounts'], ensure_ascii=False))
            for row in report['signals']:
                print(f"{row['kind']}: {row.get('path', row.get('id'))} -> {row['authority']}")
            print(f"Showing {len(report['signals'])}/{report['matchedSignals']}; use --path or --limit.")
        return 0
    except (OSError, ValueError, KeyError) as error:
        parser.exit(2, f'repository health: {error}\n')


if __name__ == '__main__':
    raise SystemExit(main())
