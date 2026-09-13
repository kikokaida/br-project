"""Validate actual engine recording, component identity, reconciliation and spike output."""
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
report = json.loads((root / 'report' / 'PERFORMANCE_PHASE1.json').read_text(encoding='utf-8'))
frames = report['frames']
phases = set().union(*(set(frame['native_phase_wall_ms']) for frame in frames))
components = [row for frame in frames for row in frame['hot_components_inclusive']]
objects = [row for frame in frames for row in frame['hot_objects']]
spikes = [json.loads(line) for line in (root / 'report' / 'SPIKES.jsonl').read_text().splitlines()]
checks = {
    'complete_frames_recorded': report['summary']['measured_frames'] > 0,
    'clean_capture': report['coverage_complete'],
    'depsgraph_and_rasterizer_phases': {'Depsgraph', 'Rasterizer'}.issubset(phases),
    'component_hot_list': any('Phase1Smoke' in row['component_or_callback'] for row in components),
    'object_hot_list': any(row['object'] == 'BR1_SmokeCube' for row in objects),
    'explicit_unaccounted_python': bool(frames) and all('UNACCOUNTED PYTHON TIME_ms' in frame['python'] for frame in frames),
    'python_reconciliation': bool(frames) and all(abs(frame['python']['reconciliation_error_ms']) < 1e-6 for frame in frames),
    'phase_reconciliation': bool(frames) and all(abs(frame['wall_reconciliation_error_ms']) < 1e-6 for frame in frames),
    'spike_output': any(frame['frame_ms'] >= 50 for frame in spikes),
    'html_report': (root / 'report' / 'REPORT.html').stat().st_size > 0,
}
result = {'status': 'PASS' if all(checks.values()) else 'FAIL', 'checks': checks,
          'measured_frames': report['summary']['measured_frames'], 'phases': sorted(phases),
          'coverage_warnings': report['coverage_warnings'], 'spike_frames': len(spikes),
          'note': 'Synthetic fixture with a deliberate 60 ms pause. Not a BloodRayne performance measurement.'}
(root / 'CAPTURE_CHECKS.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result, indent=2))
raise SystemExit(0 if result['status'] == 'PASS' else 1)
