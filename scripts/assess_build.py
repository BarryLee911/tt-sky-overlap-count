"""Optional nine-corner diagnostics. Not invoked by the GDS acceptance workflow.

Reads completed build data without modifying provenance or recovering a submission.
The official GDS Action, precheck, and GL test determine workflow success.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--run-dir', type=Path, default=ROOT / 'runs/wokwi')
parser.add_argument('--output', type=Path, default=ROOT / 'verification/build/diagnostics.json')
args = parser.parse_args()
lock = json.loads((ROOT / 'build_lock.json').read_text(encoding='utf-8'))
experiment = json.loads((ROOT / 'experiment.json').read_text(encoding='utf-8'))
resolved = json.loads((args.run_dir / 'resolved.json').read_text(encoding='utf-8'))
metrics = {}
with (args.run_dir / 'final/metrics.csv').open(encoding='utf-8', newline='') as stream:
    for row in csv.DictReader(stream):
        try:
            metrics[row['Metric']] = float(row['Value'])
        except ValueError:
            metrics[row['Metric']] = row['Value']

def finite(value):
    return isinstance(value, (int, float)) and math.isfinite(value)

corners = []
for name in lock['sta_corners']:
    fields = {'setup_ns': 'timing__setup__ws', 'hold_ns': 'timing__hold__ws',
              'slew': 'design__max_slew_violation__count',
              'capacitance': 'design__max_cap_violation__count',
              'fanout': 'design__max_fanout_violation__count'}
    corner = {'corner': name}
    corner.update({label: metrics.get(metric + '__corner:' + name)
                   for label, metric in fields.items()})
    corner['strict_timing_target_met'] = all(finite(corner[key]) and corner[key] >= 0
                                             for key in ('setup_ns', 'hold_ns'))
    corner['strict_electrical_target_met'] = all(finite(corner[key]) and corner[key] == 0
                                                 for key in ('slew', 'capacitance', 'fanout'))
    corners.append(corner)
physical_keys = ['magic__drc_error__count', 'design__lvs_error__count',
                 'route__drc_errors', 'antenna__violating__nets', 'antenna__violating__pins']
report = {'scope': 'diagnostic only; not a submission or workflow acceptance decision',
          'experiment': experiment['id'], 'run_dir': str(args.run_dir.resolve()),
          'source_sha256': hashlib.sha256((ROOT / 'src/project.v').read_bytes()).hexdigest(),
          'source_matches_lock': hashlib.sha256((ROOT / 'src/project.v').read_bytes()).hexdigest() == lock['source_sha256'],
          'resolved_checker_settings': {key: resolved.get(key) for key in experiment['expected_resolved_checker_defaults']},
          'checker_defaults_match': all(resolved.get(key) == value for key, value in experiment['expected_resolved_checker_defaults'].items()),
          'corners': corners, 'physical': {key: metrics.get(key) for key in physical_keys},
          'stdcell_area_um2': metrics.get('design__instance__area__stdcell'),
          'stdcell_count': metrics.get('design__instance__count__stdcell')}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report, indent=2))
