"""Independent pre-consumer ADR011 arithmetic. No runtime/Readback implementation."""
import hashlib
import json
from decimal import Decimal, localcontext
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
MAX = 2**64 - 1
WINDOW = 144000
GRID = 60

def valid(value):
    return (isinstance(value, str) and value.isascii() and value.isdecimal()
            and (value == '0' or not value.startswith('0'))
            and len(value) <= 20 and int(value) <= MAX)

def arithmetic(kind, a, b):
    if not valid(a): return {'ok': False, 'error_kind': 'invalid_tick', 'decimal': None, 'bounded_int': None}
    if kind == 'subtract':
        if not valid(b): return {'ok': False, 'error_kind': 'invalid_tick', 'decimal': None, 'bounded_int': None}
        result = int(a) - int(b)
        if result < 0: return {'ok': False, 'error_kind': 'reversed', 'decimal': None, 'bounded_int': None}
    else:
        if type(b) is not int or not 0 <= b <= WINDOW:
            return {'ok': False, 'error_kind': 'invalid_small', 'decimal': None, 'bounded_int': None}
        result = int(a) + b
        if result > MAX: return {'ok': False, 'error_kind': 'overflow', 'decimal': None, 'bounded_int': None}
    return {'ok': True, 'error_kind': None, 'decimal': str(result),
            'bounded_int': result if kind == 'subtract' and result <= WINDOW else None}

def event(tick=None, kind='current', position=None):
    return {'kind': kind, 'tick': None if tick is None else str(tick), 'position_xz_m': position or [0, 0]}

def schedule(first, observations):
    samples=[{'tick': str(first), 'target_tick': str(first), 'late_by_ticks': 0,
              'skipped_targets_before': 0, 'gap_before': False, 'position_xz_m': [0, 0]}]
    last=first; next_bucket=1; reason=None
    if first+GRID > MAX: reason='tick_exhausted'
    for item in observations:
        if reason is not None: break
        kind=item['kind']
        if kind in ['foreign','malformed','manual','closed_empty']:
            reason={'foreign':'identity_changed','malformed':'invalid_observation',
                    'manual':'manual','closed_empty':'closed'}[kind]
            break
        tick=int(item['tick'])
        if tick < last: reason='invalid_observation'; break
        last=tick
        relative=tick-first
        if kind=='historical': reason='terminal'; break
        if relative > WINDOW: reason='limit'; break
        bucket=relative//GRID
        if bucket >= next_bucket:
            skips=bucket-next_bucket
            samples.append({'tick': str(tick), 'target_tick': str(first+GRID*bucket),
                            'late_by_ticks': relative-GRID*bucket,
                            'skipped_targets_before': skips, 'gap_before': skips>0,
                            'position_xz_m': item['position_xz_m']})
            next_bucket=bucket+1
            if relative == WINDOW: reason='limit'; break
            if first+GRID*next_bucket > MAX: reason='tick_exhausted'; break
    last_target_bucket=(int(samples[-1]['target_tick'])-first)//GRID
    endpoint_bucket=min(last-first,WINDOW)//GRID
    tail=max(0,endpoint_bucket-last_target_bucket) if reason else 0
    skipped=sum(x['skipped_targets_before'] for x in samples)+tail
    chord=Decimal(0)
    with localcontext() as context:
        context.prec=80
        for older,newer in zip(samples,samples[1:]):
            if newer['gap_before']: continue
            dx=Decimal(newer['position_xz_m'][0])-Decimal(older['position_xz_m'][0])
            dz=Decimal(newer['position_xz_m'][1])-Decimal(older['position_xz_m'][1])
            chord+=(dx*dx+dz*dz).sqrt()
    span=Fraction(min(last-first,WINDOW),120)
    expected={'state':'sealed' if reason else 'recording','first_tick':str(first),
              'last_observed_tick':str(last),'last_sample_tick':samples[-1]['tick'],
              'sample_count':len(samples),'seal_reason':reason,'late_sample_count':sum(x['late_by_ticks']>0 for x in samples),
              'skipped_target_count':skipped,'uncaptured_tail_targets':tail,
              'window_clipped':last-first>WINDOW,
              'counting_span_s_exact':{'numerator':span.numerator,'denominator':span.denominator},
              'sampled_planar_track_m_decimal':str(chord), 'samples':samples}
    return expected

def packet():
    sub=[('zero','0','0'),('one','1','0'),('grid','60','0'),('window','144000','0'),
         ('over_window','144001','0'),('full_range',str(MAX),'0'),('borrow','1000000','999999'),
         ('above_binary64_exact',str(2**53+77),str(2**53+17)),('max_minus60',str(MAX),str(MAX-60)),
         ('reversed','59','60'),('leading_zero','060','0'),('whitespace',' 60','0'),('tick_overflow',str(MAX+1),'0')]
    add=[('zero','0',0),('grid','0',60),('decimal_carry','999999',1),('window','0',144000),
         ('above_binary64_exact',str(2**53+17),60),('maximum_exact',str(MAX-60),60),
         ('overflow',str(MAX-59),60),('negative_amount','1',-1),('noncanonical','01',1),
         ('wrong_tick_type',1,1),('boolean_amount','1',True)]
    arithmetic_cases=[{'id':kind+'_'+name,'operation':kind,'a':a,'b':b,'expected':arithmetic(kind,a,b)}
                      for kind,rows in [('subtract',sub),('add_small',add)] for name,a,b in rows]
    temporal=[
      ('exact_grid',0,[event(30),event(60),event(61),event(120)]),
      ('late_without_missing_target',0,[event(61,position=[3,4])]),
      ('late_then_real_gap',0,[event(61,position=[3,4]),event(181,position=[6,8])]),
      ('several_skipped_targets',0,[event(241,position=[3,4])]),
      ('late_after_exact_grid',0,[event(60,position=[3,4]),event(120,position=[6,8]),event(301,position=[9,12])]),
      ('manual_before_due_target',0,[event(30,position=[3,4]),event(kind='manual')]),
      ('qualified_newer_terminal_tail',0,[event(60),event(181,'historical')]),
      ('terminal_before_first_retained_target',0,[event(30),event(61,'historical')]),
      ('foreign_tick_preserves_verified_endpoint',0,[event(30),event(100000,'foreign')]),
      ('malformed_tick_preserves_verified_endpoint',0,[event(30),event(100000,'malformed')]),
      ('exact_final_window_target',0,[event(WINDOW)]),
      ('dense_complete_window',0,[event(t) for t in range(GRID,WINDOW+1,GRID)]),
      ('qualified_beyond_window',0,[event(60),event(WINDOW+1)]),
      ('later_first_above_2pow53',2**53+17,[event(2**53+47),event(2**53+78),event(2**53+198)]),
      ('near_maximum_decimal_carry',MAX-121,[event(MAX-61),event(MAX-1)]),
      ('last_grid_at_uint64_maximum',MAX-60,[event(MAX)]),
      ('initial_future_target_exhausted',MAX-30,[]),
      ('empty_closed_keeps_previous_tick',0,[event(61),event(kind='closed_empty')]),
    ]
    temporal_cases=[]
    for name,first,items in temporal:
        expected=schedule(first,items)
        if name=='dense_complete_window':
            # Exact compact range specifies all 2401 samples without a sprawling packet.
            expected.pop('samples')
            expected['exact_samples_grid']={'first':str(first),'step_ticks':60,'count':2401,'late':0,'skipped':0,'position_xz_m':[0,0]}
            input_value={'observed_grid':{'first':60,'last':144000,'step':60}}
        else: input_value={'observations':items}
        temporal_cases.append({'id':name,'first_tick':str(first),**input_value,'expected':expected})
    assert len(arithmetic_cases)==24 and len(temporal_cases)==18
    return {'fixture_version':1,'scope':'Independent pre-consumer arithmetic and declared qualification categories only; no Readback/parser/native/Godot/model observation or acceptance.',
            'method':'Python arbitrary-precision integers, Fraction relative times, Decimal80 horizontal chords. No runtime helper implementation, fitted budgets or observed consumer output.',
            'tolerances_before_observation':{'tick_target_count_integer':'exact','relative_time_rational':'exact','chord_abs_m_decimal':'0.0000000001'},
            'qualification_categories':'current/historical/foreign/malformed/closed_empty are test inputs, not proof that actual wire validation qualifies them.',
            'near_maximum_rule':'Evaluate next representable target; horizon-add overflow alone does not discard a representable prefix. First sample retained before next-target exhaustion.',
            'arithmetic_case_count':24,'sampling_case_count':18,'total_case_count':42,
            'arithmetic_cases':arithmetic_cases,'sampling_cases':temporal_cases}

if __name__=='__main__':
    encoded=(json.dumps(packet(),indent=2,ensure_ascii=True)+'\n').encode('utf-8')
    destination=HERE/'expected-v1.json'
    if destination.exists():
        assert destination.read_bytes()==encoded, 'Frozen fixture would change; author a separate revision.'
    else: destination.write_bytes(encoded)
    print('cases=42 sha256='+hashlib.sha256(encoded).hexdigest())
