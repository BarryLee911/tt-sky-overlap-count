"""Source/configuration provenance checks; no timing or electrical signoff policy."""
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]
lock = json.loads((ROOT / 'build_lock.json').read_text(encoding='utf-8'))
config = json.loads((ROOT / 'src/config.json').read_text(encoding='utf-8'))
info = yaml.safe_load((ROOT / 'info.yaml').read_text(encoding='utf-8'))['project']
experiment = json.loads((ROOT / 'experiment.json').read_text(encoding='utf-8'))
assert experiment['id'] == 'lookahead-1-2'
assert experiment['parent_commit'] == '679dbd88bb4a0062b3611c912f4d5e878e2e3574'
V6_SHA256 = 'e070e8658952ff7314bfd6ce7e69e035233953ccced5e57fa44714ae7d9f2fe2'
assert experiment['baseline_rtl_sha256'] == V6_SHA256 == lock['baseline_source_sha256']
assert experiment['acceptance_profile'] == 'official-ttsky26d-defaults'
removed = {'TIMING_VIOLATION_CORNERS', 'HOLD_VIOLATION_CORNERS',
           'MAX_SLEW_VIOLATION_CORNERS', 'MAX_CAP_VIOLATION_CORNERS'}
assert set(experiment['removed_config_keys']) == removed
assert experiment['config_overrides'] == {}
assert config == {key: value for key, value in experiment['baseline_config'].items()
                  if key not in removed}, 'Implementation configuration changed'
assert not (removed | {'SETUP_VIOLATION_CORNERS'}) & config.keys()
for path, expected_hash in experiment['immutable_files_sha256'].items():
    assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == expected_hash, path
source = (ROOT / 'src/project.v').read_bytes()
assert hashlib.sha256(source).hexdigest() == lock['source_sha256']
# The equivalence reference is the v6 RTL with only the module name changed.
reference = (ROOT / 'test/equivalence/v6_reference.v').read_bytes().replace(
    b'module tt_um_sine_area_detector_v6 #(', b'module tt_um_sine_area_detector #(', 1)
assert hashlib.sha256(reference).hexdigest() == V6_SHA256, 'v6 reference changed'
assert b'parameter integer HANDOFF_WAIT_CYCLES = 80000' in source
assert info['clock_hz'] == 80000000 and info['tiles'] == '6x2'
assert info['top_module'] == lock['top_module']
assert info['source_files'] == ['project.v', 'sky_wrapper.v']
period = Decimal(str(config['CLOCK_PERIOD']))
assert period * info['clock_hz'] == Decimal('1000000000')
assert period * Decimal(str(config['IO_DELAY_CONSTRAINT'])) / 100 == Decimal('2.5')
assert config['STA_CORNERS'] == lock['sta_corners']
# Workflows are the official TTSKY26d template files (ttsky-verilog-template 68c3fd3), unmodified.
for name, expected_hash in lock['template_workflow_sha256'].items():
    data = (ROOT / '.github/workflows' / name).read_bytes()
    assert hashlib.sha256(data).hexdigest() == expected_hash, f'{name} differs from official template'
workflow = yaml.safe_load((ROOT / '.github/workflows/gds.yaml').read_text(encoding='utf-8'))
harden = workflow['jobs']['gds']['steps'][-1]
assert harden['uses'] == 'TinyTapeout/tt-gds-action@ttsky26d' and harden['with'] == {'pdk': 'sky130A'}
for name in ('precheck', 'gl_test', 'viewer'):
    assert workflow['jobs'][name]['needs'] == 'gds' and 'if' not in workflow['jobs'][name]
report = {'status': 'PASS', 'scope': 'source and configuration provenance only',
          'experiment': experiment['id'], 'parent_commit': experiment['parent_commit'],
          'baseline_rtl_sha256': V6_SHA256,
          'acceptance_profile': experiment['acceptance_profile'],
          'workflows': 'official TTSKY26d template (unmodified)',
          'clock_hz': info['clock_hz'], 'clock_period_ns': float(period),
          'io_delay_ns': 2.5, 'tiles': info['tiles'], 'source_sha256': lock['source_sha256'],
          'handoff_cycles': 80000, 'handoff_ms': 1.0,
          'removed_config_keys': sorted(removed)}
out = ROOT / 'verification'
out.mkdir(exist_ok=True)
(out / 'inputs.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report, indent=2))
