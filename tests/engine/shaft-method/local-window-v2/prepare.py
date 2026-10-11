"""Source-only exact extraction and frozen-JSON marshaling; never imports a solver or generator."""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import os
import stat

HERE = Path(__file__).resolve().parent
CPP_REL = 'vendor/src/models/propulsion/FGPropeller.cpp'
H_REL = 'vendor/src/models/propulsion/FGPropeller.h'
OLD = 'third_party/patches/jsbsim/event-aware-coupled-midpoint-v1'
NEW = 'third_party/patches/jsbsim/event-aware-coupled-midpoint-local-window-v2'
REF = 'docs/evidence/P3/piston-local-window-reference'
PINS = {
    OLD + '/' + CPP_REL: 'e0ff11682070f2fa5a40ed7f14dbfcf56719a186089eb03185af8cdf9227d9f4',
    NEW + '/' + CPP_REL: 'ae07b0e30bfc1c14c04f3865dc1f08d3db1b122521953767d6601c429598631c',
    OLD + '/' + H_REL: '730819eba6e87b94c75c8e02606f55a8006e54822f8f8f669f24d2941b1be6a5',
    NEW + '/' + H_REL: '730819eba6e87b94c75c8e02606f55a8006e54822f8f8f669f24d2941b1be6a5',
    REF + '/expected.json': 'da53acdff9600e2577832d1e3d110d8cfd221c45e8d1576ff088ef59514bdd7b',
    REF + '/generate.py': '01d4b45c3abee53d3cf72804540973aec7b27171a8b23cd7d82d63bf22782699',
    REF + '/README.md': 'dea84d14bac0969bed480cd9e5c442d260628d1ac3fe1c1d48790ef6341913d5',
    REF + '/manifest.json': '996dbc36c68fc35b8cb33d2b988fd9b10da235bd5f8e137e4b498101798fc016',
    'docs/decisions/024-certified-local-decay-window.md': '3404f1198d34b4faa3c1d640988be88dd8b3839fdfaff0f4e70213798d6db55b',
    'tests/engine/shaft-method/probes/driver.template.cpp': '0cfb84e5b8097d2de19939b51fe7694cc32bf917f1b4071d85d8c09481e64d5b',
    'tests/engine/shaft-method/coupled-midpoint-v1/references.json': '9496b4d4ed0930f0cb0fb0f994b66806ce45e18beaca439c92bda1b056fc8437',
    'tests/engine/shaft-method/coupled-midpoint-v1/native_fixture.py': '24aff9ed415b03da7f0f4795c6f8cf410413244821c9e8b19cd45ceeedb40c1f',
    'docs/decisions/015-source-law-coupled-shaft.md': 'a1e71c20faf5a648990c2bf06c538fa6a9d328f6ab02029b694a4b8d7af595de',
}
IDS = ['L01_actual_captured', 'L02_authored_local', 'L03_half_time_equal',
       'L04_half_time_excess', 'L05_local_positive', 'L06_constant_power_full',
       'L07_constant_torque_full', 'L08_full_source_endpoint', 'L09_local_before_source',
       'B01_zero_split_at8', 'B02_undecided_at8', 'B03_shared_last3',
       'B04_shared_insufficient', 'R05_split8_unchanged', 'R05_bisect64_unchanged',
       'R05_capacity128_unchanged', 'G01_stagnant_half']

def sha(data):
    return hashlib.sha256(data).hexdigest()

def between(text, start, end):
    assert text.count(start) == 1, start
    at = text.index(start)
    assert text.count(end, at) == 1, end
    return text[at:text.index(end, at)]

def d(q):
    """Marshal an exact dyadic rational to independent canonical integer limbs."""
    n, den = int(q['n']), int(q['d'])
    assert den > 0 and den & (den - 1) == 0, 'Expected dyadic frozen rational'
    if n == 0:
        return '{0,0,{}}'
    sign, n = (-1 if n < 0 else 1), abs(n)
    exponent = -(den.bit_length() - 1)
    while n & 1 == 0:
        n >>= 1
        exponent += 1
    limbs = []
    while n:
        limbs.append(str(n & 0xffffffff) + 'u')
        n >>= 32
    return '{' + f'{sign},{exponent},' + '{' + ','.join(limbs) + '}}'

def integer(n):
    return d({'n': n, 'd': '1'})

def ratio(q):
    return '{' + integer(q['n']) + ',' + integer(q['d']) + '}'

def scalar(q):
    """Only exact binary64 source operands/interval endpoints; reject rounding."""
    n, den = int(q['n']), int(q['d'])
    x = n / den
    xn, xd = x.as_integer_ratio()
    assert xn * den == n * xd, 'No rounding permitted when marshaling scalar input'
    return 'scalar(0x' + struct.pack('>d', x).hex() + 'ull)'

def array(values, emitter):
    return '{' + ','.join(emitter(value) for value in values) + '}'

def boolean(value):
    assert type(value) is bool
    return 'true' if value else 'false'

def cert(value, initial):
    cells = []
    for cell in value['trace']:
        cells.append('{' + ','.join([scalar(cell['lo']), scalar(cell['hi']), d(cell['lower']), d(cell['upper'])]) + '}')
    return '{' + ','.join([boolean(value['certified']), str(initial) + 'u', str(value['used_splits']) + 'u', '{' + ','.join(cells) + '}']) + '}'

def law(c):
    full = c['full_certificate']
    local = '{0,{false,0u,0u,{}},false,{{0,0,{}},{1,0,{1u}}},0}'
    if 'local_certificate' in c:
        has_time = 'half_time' in c
        local = '{' + ','.join([
            scalar(c['half']), cert(c['local_certificate'], full['used_splits']), boolean(has_time),
            ratio(c['half_time']) if has_time else '{{0,0,{}},{1,0,{1u}}}',
            str(c.get('remaining_vs_half_time', 0))]) + '}'
    values = [json.dumps(c['id']), array(c['law'], scalar), scalar(c['w0']), scalar(c['I']),
              scalar(c['endpoint']), boolean(c['original_source_event']), ratio(c['remaining']),
              array(c['time_derivative'], d), cert(full, 0), boolean('local_certificate' in c),
              local, json.dumps(c['expected_v2'])]
    return 'law_case({' + ','.join(values) + '});'

def body(c):
    kind = c['kind']
    if kind == 'frozen_law_policy':
        return law(c)
    if kind == 'certificate_primitive':
        return 'primitive(' + ','.join([array(c['polynomial'], d), scalar(c['lo']), scalar(c['hi']), cert(c['result'], c['initial_used_splits'])]) + ');'
    if c['id'] == 'R05_split8_unchanged':
        return '''const j::CoupledLaw p{0,2,-1,0};
      const auto b=j::CTimeDerivative(p,2);
      check(b.degree==0&&matches(b.c[0],DyadicSpec{0,0,{}}),"r05_zero_derivative");
      unsigned splits=0;certificate(b,2,1,splits,''' + cert(c['certificate'], 0) + ''');
      rejection([](){j::CCertifyDecay({0,2,-1,0},2,1);},''' + json.dumps(c['reason']) + ''');
      rejection([](){immutable::CCertifyDecay({0,2,-1,0},2,1);},''' + json.dumps(c['reason']) + ');'
    if c['id'] == 'R05_bisect64_unchanged':
        return '''const auto p=polynomial(''' + array(c['polynomial'], d) + ''');
      immutable::CoupledPolynomial old;old.degree=p.degree;
      const std::vector<DyadicSpec> coefficients=''' + array(c['polynomial'], d) + ''';
      for(unsigned i=0;i<coefficients.size();++i) {old.c[i]=exact<immutable::CoupledDyadic>(coefficients[i]);}
      rejection([&](){(void)j::CIsolate(p,''' + ','.join(scalar(q) for q in c['initial_bracket']) + ');},' + json.dumps(c['reason']) + ''');
      rejection([&](){(void)immutable::CIsolate(old,''' + ','.join(scalar(q) for q in c['initial_bracket']) + ');},' + json.dumps(c['reason']) + ');'
    if c['id'] == 'R05_capacity128_unchanged':
        return 'rejection([](){(void)j::CAdd(j::CScale(j::CoupledDyadic(1),4096),j::CoupledDyadic(1));},' + json.dumps(c['reason']) + ''');
      rejection([](){(void)immutable::CAdd(immutable::CScale(immutable::CoupledDyadic(1),4096),immutable::CoupledDyadic(1));},''' + json.dumps(c['reason']) + ');'
    if kind == 'midpoint_admission_primitive':
        return 'const double endpoint=' + scalar(c['endpoint']) + ',w=' + scalar(c['w0']) + ''';
      const double half=j::CoupledRounded(endpoint+(w-endpoint)*0.5);
      check(bits(half)==bits(''' + scalar(c['rounded_half']) + '''),"stagnant_half_ties_even");
      check(!(endpoint<half&&half<w),"stagnant_half_strict_admission_rejected");'''
    raise AssertionError('Unrecognized frozen case ' + c['id'])

def fresh_output(path):
    """Admit absent or ordinary empty output without following links/reparse points."""
    output = Path(os.path.abspath(path))
    for item in [*reversed(output.parents), output]:
        try:
            info = item.lstat()
        except FileNotFoundError:
            continue
        assert not stat.S_ISLNK(info.st_mode), 'Output path must not traverse a symlink'
        assert not (getattr(info, 'st_file_attributes', 0) & 0x400), 'Output path must not traverse a reparse point'
        assert stat.S_ISDIR(info.st_mode), 'Output path must contain only ordinary directories'
    if output.exists():
        assert not any(output.iterdir()), 'Fresh empty output required; preserve earlier evidence'
    return output

def write_new(path, raw):
    with path.open('xb') as stream:
        stream.write(raw)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    a = parser.parse_args()
    repo, output = a.repo_root.resolve(), fresh_output(a.output)
    data = {}
    for name, expected in PINS.items():
        raw = (repo / name).read_bytes()
        assert sha(raw) == expected, name
        data[name] = raw
    reference = json.loads(data[REF + '/expected.json'])
    assert reference['format'] == 'PistonLocalWindowRationalReference/v1'
    assert reference['candidate_outputs_consumed'] is False
    assert [c['id'] for c in reference['cases']] == IDS
    assert reference['finite_work']['shared_total_splits'] == 8
    assert reference['finite_work']['max_evaluations'] == 18
    helpers = {}
    for label, prefix in [('immutable', OLD), ('candidate', NEW)]:
        cpp = data[prefix + '/' + CPP_REL].decode('utf-8')
        helpers[label + '_helpers.inc'] = (between(cpp, '// Original project modification, 2026-10-09.', '} // anonymous namespace\n') + '} // anonymous namespace\n').encode('utf-8')
    assert sha(helpers['immutable_helpers.inc']) == 'f207d3d7dde6fe4b36c7112aa78cb235201a1de2172c168a96733c7f6323db6c'
    old_types = between(data[OLD + '/' + H_REL].decode('utf-8'), '// Original project ADR015 internal values,', '/*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%\nCLASS DOCUMENTATION')
    new_types = between(data[NEW + '/' + H_REL].decode('utf-8'), '// Original project ADR015 internal values,', '/*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%\nCLASS DOCUMENTATION')
    assert old_types == new_types
    template = (HERE / 'driver.template.cpp').read_bytes()
    driver = template.decode('utf-8')
    assert driver.count('@@OWNED_TYPES@@') == 2 and driver.count('@@REFERENCE_CASES@@') == 1
    cases = '\n'.join('  run_case(' + json.dumps(c['id']) + ',[](){\n      ' + body(c) + '\n  });' for c in reference['cases'])
    driver = driver.replace('@@OWNED_TYPES@@', old_types).replace('@@REFERENCE_CASES@@', cases)
    assert '@@' not in driver
    output.mkdir(parents=True, exist_ok=True)
    fresh_output(output)
    generated = {'driver.cpp': driver.encode('utf-8'), **helpers}
    for name, raw in generated.items():
        write_new(output / name, raw)
    receipt = {
        'schema': 'PistonLocalWindowNativeTestSourceBinding/v1',
        'status': 'SOURCE_ONLY_NO_GENERATOR_SOLVER_COMPILER_OR_NATIVE_EXECUTION',
        'reference_cases': IDS, 'candidate_outputs_consumed': False,
        'inputs': {name: {'bytes': len(raw), 'sha256': sha(raw)} for name, raw in data.items()},
        'template_sha256': sha(template), 'prepare_sha256': sha(Path(__file__).read_bytes()),
        'generated': {name: {'bytes': len(raw), 'sha256': sha(raw)} for name, raw in generated.items()},
        'scope': 'Verbatim compiled scalar helper consumer only; not actual replaceable DLL/session execution',
        'work_observation_limit': 'Actual final split counter/status and independent frozen-cell CIEval results; no instrumented production visit/evaluation counters',
    }
    write_new(output / 'source-binding.json', (json.dumps(receipt, indent=2) + '\n').encode('utf-8'))
    print(json.dumps({'status': receipt['status'], 'reference_cases': len(IDS), 'generated': receipt['generated']}, indent=2))

if __name__ == '__main__':
    main()
