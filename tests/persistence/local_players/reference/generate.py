"""Original MIT. Independent preconsumer value references; no consumer imports or IO.
Python integers/Fraction derive arithmetic and IEEE bit interpretation. --check is read-only.
This is not a storage implementation, semantic preset validator, or database test.
"""
from pathlib import Path
from fractions import Fraction
import argparse, hashlib, json, re

MAX=(1<<64)-1

def digest(raw): return hashlib.sha256(raw).hexdigest()
def output_bytes(value): return (json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+'\n').encode('utf8')
def typed_int(value): return {'type':'INT','decimal':str(value)}
def typed_float(bits): return {'type':'FLOAT','binary64_be_hex':bits}
def quote(text):
    # Normative canonical string spelling, not Python json.dumps C0 shortcuts.
    result='"'
    for c in text:
        n=ord(c)
        assert not 0xd800<=n<=0xdfff
        result+=('\\"' if c=='"' else '\\\\' if c=='\\' else '\\u%04x'%n if n<32 else c)
    return result+'"'
def canonical(value):
    # Only original fixed fixture objects contain values; no input parser.
    if value is None:return 'null'
    if type(value) is bool:return 'true' if value else 'false'
    if type(value) is int:return str(value)
    if type(value) is str:return quote(value)
    if type(value) is list:return '['+','.join(canonical(x) for x in value)+']'
    assert type(value) is dict and all(type(k) is str and k.isascii() for k in value)
    return '{'+','.join(quote(k)+':'+canonical(value[k]) for k in sorted(value))+'}'
def fraction_bits(bits):
    n=int(bits,16);sign=-1 if n>>63 else 1;e=(n>>52)&2047;f=n&((1<<52)-1)
    if e==2047:return None
    significand=f if e==0 else (1<<52)|f
    power=-1074 if e==0 else e-1023-52
    return sign*Fraction(significand)*(Fraction(2)**power)
def tag(bits): return {'$binary64_le':int(bits,16).to_bytes(8,'little').hex()}
def scalar_refs():
    cases=[('positive_zero','0000000000000000'),('negative_zero','8000000000000000'),
      ('smallest_positive_subnormal','0000000000000001'),('smallest_negative_subnormal','8000000000000001'),
      ('largest_subnormal','000fffffffffffff'),('smallest_normal','0010000000000000'),
      ('mixture_point06','3faeb851eb851eb8'),('threshold_point05','3fa999999999999a'),
      ('deadzone_point4','3fd999999999999a'),('half','3fe0000000000000'),
      ('one_below','3fefffffffffffff'),('one','3ff0000000000000'),('one_above','3ff0000000000001'),
      ('negative_one','bff0000000000000'),('largest_finite','7fefffffffffffff'),
      ('positive_infinity','7ff0000000000000'),('negative_infinity','fff0000000000000'),('quiet_nan','7ff8000000000001')]
    result=[]
    for name,bits in cases:
        f=fraction_bits(bits);finite=f is not None
        result.append({'id':'B_'+name,'input':typed_float(bits),'finite_primitive':finite,
          'expected_tag':tag(bits) if finite else None,'expected_restored':typed_float(bits) if finite else None,
          'exact_rational':None if f is None else {'numerator':str(f.numerator),'denominator':str(f.denominator)},
          'audio_gain_semantic_admission':finite and 0<=f<=1,
          'scope':'Bit transport primitive; a finite tag alone does not admit any record/path.'})
    return result

def family_refs():
    # Twenty independent source-audit families. Each row is a FIELD witness;
    # other required preset shape, aliases, device ownership and conflicts must
    # be checked separately by the future accepted validator, not inferred here.
    rows=[]
    def add(number,name,path,positive,normalized,negative,reason,context=None):
        rows.append({'id':'T%02d'%number,'family':name,'path':path,'context':context or {},
          'admitted_field_input':positive,'expected_normalized_field':normalized,
          'expected_storage':tag(normalized['binary64_be_hex']) if normalized['type']=='FLOAT' else normalized['decimal'],
          'rejected_field_input':negative,'rejection_basis':reason,'scope':'Field-level witness, not a complete admitted preset.'})
    f=lambda b:typed_float(b);i=typed_int;negzero=f('8000000000000000')
    add(1,'preset_version','$.legacy_input.version',f('3ff0000000000000'),i(1),f('3ff8000000000000'),'Enum must be integral exact1; incoming FLOAT1 normalizes INT1.')
    add(2,'fixed_signed','$.legacy_input.axes[roll].value',negzero,negzero,i(-2),'Signed field [-1,1]; continuous FLOAT negative zero retained.')
    add(3,'fixed_unsigned','$.legacy_input.axes[throttle].value',i(0),i(0),f('8000000000000001'),'Negative subnormal is below0; actual INT0 remains INT.')
    add(4,'fixed_mixture_v1','$.legacy_input.axes[mixture].value',i(1),i(1),f('3fefffffffffffff'),'Legacy mixture exactly1.')
    add(5,'fixed_mixture_v2','$.piston_input.axes[mixture].value',f('3faeb851eb851eb8'),f('3faeb851eb851eb8'),i(2),'Piston mixture0..1; binary64 .06 exact bits retained.')
    add(6,'axis_key_code','$.legacy_input.axes[pitch].negative[0]',f('4050400000000000'),i(65),i(2147483648),'Above2147483647 rejects before backend key roundtrip.',{'kind':'key_pair','physical_key_roundtrip_still_required':True})
    add(7,'key_pair_rate','$.legacy_input.axes[pitch].rate',i(4),i(4),negzero,'rate must be >0 and <=4.')
    add(8,'axis_gain','$.legacy_input.axes[pitch].gain',i(1),i(1),i(0),'gain must be >0 and <=1.')
    add(9,'joy_axis_index','$.legacy_input.axes[roll].index',negzero,i(0),i(10),'Index0..9; FLOAT -0 enum normalizes INT0.',{'kind':'joy_axis','slot':'Stick','slot_declared':True})
    add(10,'joy_calibration','$.legacy_input.axes[roll].{minimum,center,maximum}',i(-1),i(-1),i(-2),'Each calibration field in[-1,1]; sibling-span constraint separate.',{'kind':'joy_axis','range':'centered','minimum':-1,'center':0,'maximum':1})
    add(11,'deadzone','$.legacy_input.axes[roll].deadzone',negzero,negzero,f('3fd999999999999b'),'deadzone0..binary64(0.4) inclusive.')
    add(12,'saturation','$.legacy_input.axes[roll].saturation',i(1),i(1),i(0),'saturation strictly greater than sibling deadzone.',{'deadzone':typed_int(0)})
    add(13,'slew','$.legacy_input.axes[roll].slew_per_s',negzero,negzero,i(5),'slew0..4 inclusive; signed zero retained.')
    add(14,'action_key_code','$.legacy_input.actions[help].sources[0].keys[0]',i(65),i(65),i(31),'Key code<32 rejects; future actual OS roundtrip still required.',{'kind':'physical_keys','physical_key_roundtrip_still_required':True})
    add(15,'action_joy_button','$.legacy_input.actions[help].sources[0].index',f('405fc00000000000'),i(127),i(128),'JOY_BUTTON_MAX128 means0..127.',{'kind':'joy_button','slot':'Stick','slot_declared':True})
    add(16,'action_mouse_button','$.legacy_input.actions[help].sources[0].button',f('4022000000000000'),i(9),i(10),'Action mouse button1..9.')
    add(17,'system_key_code','$.piston_input.systems[engine.fuel_feed].sources[0].keys[0]',i(65),i(65),{'type':'BOOL','value':True},'Boolean is not a key integer; aliases and Escape conflicts separate.',{'kind':'physical_keys','physical_key_roundtrip_still_required':True})
    add(18,'system_joy_button','$.piston_input.systems[engine.fuel_feed].sources[0].index',i(0),i(0),i(-1),'System joy button0..127; slot must be declared.')
    add(19,'system_mouse_button','$.piston_input.systems[engine.fuel_feed].sources[0].button',i(8),i(8),i(4),'Persistent engine controls reject wheel buttons4..7.')
    add(20,'audio_gain','$.audio.engine_gain',negzero,negzero,i(0),'Audio gain requires actual FLOAT; INT0 is not accepted.')
    assert len(rows)==20
    # Independent exact-rational checks on the three integer enum float examples.
    assert fraction_bits('4050400000000000')==65 and fraction_bits('405fc00000000000')==127 and fraction_bits('4022000000000000')==9
    return rows

def bundles():
    rows=[]
    for name,engine,airflow,revision in [('initial','3ff0000000000000','3ff0000000000000','1'),
      ('signed_zero','8000000000000000','0000000000000000','1'),
      ('fraction_full_u64','3faeb851eb851eb8','0000000000000001',str(MAX))]:
        obj={'type':'LocalPlayerPreferences','version':1,'player_id':'0123456789abcdef0123456789abcdef','revision':revision,
          'legacy_input':None,'piston_input':None,'audio':{'enabled':True,'engine_gain':tag(engine),'airflow_gain':tag(airflow),'show_panel_captions':True}}
        payload=canonical(obj);pbytes=payload.encode('utf8');h=digest(pbytes)
        envelope=canonical({'format':'LocalPlayerPreferences','version':1,'payload_json':payload,'payload_sha256':h});eb=envelope.encode('utf8')
        rows.append({'id':'C_'+name,'expected_payload_utf8':payload,'payload_bytes':len(pbytes),'payload_sha256':h,
          'expected_envelope_utf8':envelope,'envelope_bytes':len(eb),'envelope_sha256':digest(eb),
          'restored_types':{'version':'INT','revision':'String','audio.enabled':'BOOL','audio.engine_gain':typed_float(engine),'audio.airflow_gain':typed_float(airflow),'legacy_input':'NIL','piston_input':'NIL'},
          'scope':'Whole closed preferences bundle with null preset slots; exact original byte oracle.'})
    return rows

def u64_refs():
    cases=[]
    for x in ['0','1','9007199254740991','9007199254740992','9007199254740993','9223372036854775808',str(MAX)]:
        cases.append({'id':'U_valid_'+x,'input':{'type':'String','value':x},'canonical_u64':True,'positive_revision':x!='0'})
    for n,x in enumerate(['','00','01','+1','-0','-1','1.0','1e0',' 1','1\n','١',str(MAX+1)]):
        cases.append({'id':'U_invalid_%02d'%n,'input':{'type':'String','value':x},'canonical_u64':False,'positive_revision':False})
    cases.extend([{'id':'U_wrong_'+t,'input':{'type':t,'value':x},'canonical_u64':False,'positive_revision':False} for t,x in [('INT',1),('FLOAT','3ff0000000000000'),('BOOL',True),('StringName','1')]])
    ops=[]
    for a,b in [(0,1),(9007199254740992,1),(9223372036854775807,1),(MAX-1,1),(MAX,1)]:
        ops.append({'id':'A_add_'+str(a),'operation':'checked_add','operands':[str(a),str(b)],'accepted':a+b<=MAX,'expected':str(a+b) if a+b<=MAX else None})
    for a,b in [(MAX,0),(MAX,MAX-120),(9007199254740993,9007199254740992),(0,1)]:
        ops.append({'id':'A_sub_'+str(a)+'_'+str(b),'operation':'checked_subtract','operands':[str(a),str(b)],'accepted':a>=b,'expected':str(a-b) if a>=b else None})
    for a,b in [(9,10),(9007199254740992,9007199254740993),(9223372036854775808,MAX),(MAX,MAX)]:
        ops.append({'id':'A_compare_'+str(a)+'_'+str(b),'operation':'compare','operands':[str(a),str(b)],'accepted':True,'expected':(a>b)-(a<b)})
    return cases,ops

def paging():
    # Fixed hand-authored records: latest commit differs deliberately from immutable creation.
    original=[{'id':name,'creation_sequence':str(c),'commit_sequence':str(m)} for name,c,m in
      [('old',9,100),('ten',10,10),('edited',11,MAX),('p53a',9007199254740992,9007199254740992),
       ('p53b',9007199254740993,9007199254740993),('p63',9223372036854775808,9223372036854775808),('new',MAX-1,MAX-1)]]
    rows=[]
    scenarios=[('initial',original,None,3),('next',original,'9007199254740993',3),('last',original,'10',3),
      ('newer_insert',original+[{'id':'later','creation_sequence':str(MAX),'commit_sequence':str(MAX)}],'9007199254740993',3),
      ('deletion_between_reads',[r for r in original if r['id']!='edited'],'9007199254740993',3)]
    for name,records,cursor,limit in scenarios:
        selected=sorted([r for r in records if cursor is None or int(r['creation_sequence'])<int(cursor)],key=lambda r:int(r['creation_sequence']),reverse=True)
        page=selected[:limit];next_cursor=page[-1]['creation_sequence'] if len(selected)>limit else None
        rows.append({'id':'P_'+name,'records':records,'before_creation_sequence':cursor,'limit':typed_int(limit),'expected_ids':[r['id'] for r in page],'next_before_creation_sequence':next_cursor})
    return rows

def closed_negatives():
    # These are closed reference recipes, not an executed lexer/service or copy implementation.
    examples=[('naked_fraction','$.audio.engine_gain','0.5','FLOAT requires exact tag'),
      ('naked_exponent','$.audio.engine_gain','1e0','Naked real/exponent forbidden'),
      ('negative_integer_zero','$.legacy_input.axes[roll].value','-0','Canonical INT zero token is0'),
      ('leading_integer_zero','$.legacy_input.axes[roll].value','01','Invalid RFC8259/canonical integer'),
      ('duplicate_key','object','{"version":1,"version":1}','Duplicate object key'),
      ('escaped_key','object','{"vers\\u0069on":1}','Escaped object keys forbidden'),
      ('wrong_tag_key','$.audio.engine_gain','{"$binary64_be":"0000000000000000"}','Unknown tag'),
      ('uppercase_tag','$.audio.engine_gain','{"$binary64_le":"B81E85EB51B8AE3F"}','Lowercase required'),
      ('short_tag','$.audio.engine_gain','{"$binary64_le":"00"}','Exactly16lowerhex'),
      ('tag_extra','$.audio.engine_gain','{"$binary64_le":"0000000000000000","extra":0}','Closed singleton tag'),
      ('enum_tag','$.legacy_input.version','{"$binary64_le":"000000000000f03f"}','Enum persisted as INT'),
      ('revision_number','$.revision','1','Full U64 revision stays String'),
      ('digit_vendor_number','$.legacy_input.devices[0].match.vendor_id','1234','Digit-looking vendor ID stays String'),
      ('lone_surrogate','string','"\\ud800"','Unicode scalar admission'),
      ('trailing_comma','object','{"version":1,}','Strict JSON'),
      ('trailing_root','root','{}{}','Exactly one complete root')]
    return [{'id':'N_'+name,'context_path':path,'encoded_fragment':text,'expected':'reject','basis':basis,
      'scope':'Fragment/shape rejection only, not a whole-record codec test.'} for name,path,text,basis in examples]

def revisions_and_copies():
    # Explicit protocol outcomes, not candidate service observations.
    revisions=[
      ('stale_identical','7','6',True,'revision_conflict','7',False),
      ('current_identical','7','7',True,'no_change','7',False),
      ('current_changed','7','7',False,'committed','8',True),
      ('max_identical',str(MAX),str(MAX),True,'no_change',str(MAX),False),
      ('max_changed',str(MAX),str(MAX),False,'counter_exhausted',str(MAX),False)]
    rs=[{'id':'R_'+n,'stored_revision':s,'expected_revision':e,'normalized_bits_equal':eq,'expected_outcome':o,'resulting_revision':v,'durable_content_changed':change,'scope':'Revision freshness precedes equality; no SQL/commit observation.'} for n,s,e,eq,o,v,change in revisions]
    copies=[
      ('mutate_submit_after_accept','accepted job DTO','later caller changes nested gain','reserved request keeps original exact gain bits'),
      ('mutate_load_result','loaded owned bundle','caller changes nested axis key list','store and separately loaded bundle unchanged'),
      ('mutate_status_result','status owned dictionary','caller changes count/state','service owner unchanged'),
      ('mutate_poll_result','polled owned terminal value','caller changes nested preferences revision','store and other queued results unchanged'),
      ('foreign_poll','foreign thread','poll actualINT8','null, no drain/owner state change'),
      ('float_poll','owner thread','poll FLOAT8.0','null, no drain/owner state change'),
      ('stringname_key','direct submit','actual StringName kind key','reject before queue/root/DB mutation'),
      ('boolean_counter','direct submit','actual BOOL where INT limit/version required','reject without coercion')]
    cs=[{'id':'O_'+n,'context':c,'stimulus':s,'expected':e,'scope':'Future actual boundary/copy test recipe, unexecuted here.'} for n,c,s,e in copies]
    return rs,cs

def build():
    u,a=u64_refs();rr,cc=revisions_and_copies()
    value={'schema':'IndependentLocalPlayersValueReferences/v1','status':'PRECONSUMER_PROPOSED_UNRATIFIED',
      'license':'Original MIT','scope':'Original independent exact byte/type/arithmetic expectations and explicit boundary recipes. No consumer, SQLite, Win32, worker, durability, crash, native flight or Godot execution.',
      'binary64':scalar_refs(),'numeric_families':family_refs(),'canonical_bundles':bundles(),'u64':u,'arithmetic':a,'paging':paging(),'encoded_rejections':closed_negatives(),'revision_recipes':rr,'copy_and_boundary_recipes':cc,
      'string_spelling':[{'input_scalars':'Δ "\\\x01\n','expected_canonical_json':quote('Δ "\\\x01\n')},{'input_scalars':'é','expected_canonical_json':quote('é')},{'input_scalars':'e\u0301','expected_canonical_json':quote('e\u0301')}],
      'limitations':['Twenty numeric-family witnesses are field-level; full presets, keys OS roundtrip, conflicts, devices and collection/cap checks remain required.','Exact calibration span binary64 comparisons require actual accepted validator qualification; no decimal rational substitution or epsilon.','Copy/revision recipes are logical requirements, not executed service traces. Paging is exact immutable-key arithmetic, not a concurrent SQLite snapshot test.','Storage IO, queue/thread ownership, KnownFolder, WAL, crash/recovery, exporter and same-process reopen require separately authorized actual tests.','No values or budgets learned from a future consumer. Source contract/publication and Root ratification remain pending.']}
    ids=[r['id'] for group in value.values() if type(group)is list for r in group if type(r)is dict and 'id'in r];assert len(ids)==len(set(ids))
    value['case_counts']={k:len(v) for k,v in value.items() if type(v)is list and v and type(v[0])is dict}
    value['total_cases']=sum(value['case_counts'].values())
    return value

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    destination=Path(__file__).with_name('expected-v1.json');raw=output_bytes(build())
    if args.check:
        if destination.read_bytes()!=raw:raise SystemExit('Frozen references differ; no write performed')
        print('PASS exact read-only reference regeneration '+digest(raw))
    else:
        if destination.exists():raise SystemExit('Refuse overwrite; use --check')
        destination.write_bytes(raw);print(digest(raw))
if __name__=='__main__':main()
