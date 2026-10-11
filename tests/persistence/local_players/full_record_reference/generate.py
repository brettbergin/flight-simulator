"""Original MIT. Independent full-record references, not a codec/validator/store.
Only standard-library byte construction, explicit fixtures and integer arithmetic.
No repository module, SQLite, Godot, native library or consumer output is loaded.
--check compares frozen files without writing. Run from any directory.
"""
from pathlib import Path
from dataclasses import dataclass
from copy import deepcopy
from fractions import Fraction
import argparse, hashlib, json

ROOT=Path(__file__).resolve().parent
MAX=(1<<64)-1
SCHEMA='cbd00b3fe47b400e79635ed901d195abfe133a4131d5001feac8e3eedeb0562f'
CODEC='47711d41be89e233efe3c42e8f2cedd33f729e6e0e2c9a78a6026454022b0538'
LEGACY={'id':'original-interactive-prototype','version':'0.1.0-prototype','backend_model':'original-interactive'}
PISTON={'id':'original-piston-prop-v1','version':'0.1.0-prototype','backend_model':'original-piston-prop'}
VARIANTS=['jsbsim-1.3.1-upstream','jsbsim-1.3.1-event-aware-constant-power-v1',
 'jsbsim-1.3.1-event-aware-coupled-midpoint-v1','jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2']
A='a'*32; B='b'*32; P='1'*32; Q='2'*32; R='3'*32
UTC='2026-10-11T06:00:00Z'

def sha(raw): return hashlib.sha256(raw).hexdigest()
def pretty(value): return (json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+'\n').encode('utf8')

@dataclass(frozen=True)
class F:
    be: str
    def le(self): return bytes.fromhex(self.be)[::-1].hex()
    def rational(self):
        n=int(self.be,16); e=(n>>52)&2047; f=n&((1<<52)-1)
        if e==2047: return None
        return (-1 if n>>63 else 1)*Fraction(f if e==0 else (1<<52)|f)*Fraction(2)**(-1074 if e==0 else e-1075)

@dataclass(frozen=True)
class Wrong:
    kind: str
    text: str

Z=F('8000000000000000'); HALF=F('3fe0000000000000'); ONE=F('3ff0000000000000')
SMALL=F('0000000000000001'); FOUR=F('4010000000000000')

def typed(v):
    if isinstance(v,F): return {'type':'FLOAT','binary64_le':v.le()}
    if isinstance(v,Wrong): return {'type':v.kind,'value':v.text}
    if v is None: return {'type':'NIL'}
    if type(v) is bool: return {'type':'BOOL','value':v}
    if type(v) is int: return {'type':'INT','decimal':str(v)}
    if type(v) is str: return {'type':'STRING','value':v}
    if type(v) is list: return {'type':'ARRAY','values':[typed(x) for x in v]}
    assert type(v) is dict and all(type(k) is str for k in v)
    return {'type':'DICTIONARY','entries':[{ 'key':k,'value':typed(v[k])} for k in sorted(v)]}

def quote(s):
    out='"'
    for c in s:
        u=ord(c); assert not 0xd800<=u<=0xdfff
        out+=('\\"' if c=='"' else '\\\\' if c=='\\' else '\\u%04x'%u if u<32 else c)
    return out+'"'

def canonical(v):
    # Fixture-only writer: all numeric positions are authored, not discovered.
    if isinstance(v,F): return '{"$binary64_le":'+quote(v.le())+'}'
    if v is None: return 'null'
    if type(v) is bool: return 'true' if v else 'false'
    if type(v) is int: return str(v)
    if type(v) is str: return quote(v)
    if type(v) is list: return '['+','.join(canonical(x) for x in v)+']'
    assert type(v) is dict and all(type(k) is str and k.isascii() for k in v)
    return '{'+','.join(quote(k)+':'+canonical(v[k]) for k in sorted(v))+'}'

def exact_bytes(v):
    raw=canonical(v).encode('utf8')
    return {'utf8_hex':raw.hex(),'bytes':len(raw),'sha256':sha(raw)}

def envelope(format,payload):
    inner=canonical(payload)
    return {'format':format,'version':1,'payload_json':inner,'payload_sha256':sha(inner.encode('utf8'))}

def fixed(target,value): return {'target':target,'kind':'fixed','value':value}
def keypair(target,negative,positive,rate,gain,returns=False):
    return {'target':target,'kind':'key_pair','negative':negative,'positive':positive,
     'rate':rate,'gain':gain,'return_to_start':returns}
def joy(target,index,centered):
    return {'target':target,'kind':'joy_axis','slot':'stick-A','index':index,
     'range':'centered' if centered else 'unsigned','minimum':-1 if centered else 0,
     'center':Z,'maximum':ONE,'invert':False,'deadzone':Z,'saturation':ONE,'gain':HALF,'slew_per_s':4}

def preset(version,rich=False):
    axes=[fixed(t,1 if t=='mixture' else 0) for t in ['roll','pitch','yaw','throttle','mixture','left_brake','right_brake','trim']]
    p={'type':'InputPreset','version':version,'name':'Original guest','devices':[], 'axes':axes,'actions':[]}
    if rich:
        p['name']='Original "Δ" \\ 飛行'
        p['devices']=[{'slot':'stick-A','label':'Yoke Δ','match':{'guid':'fixture-guid','name':'Fixture device\t飛行','vendor_id':'0123','product_id':'00ab'}}]
        p['axes']=[keypair('roll',[F('4050400000000000')],[68],FOUR,1,True),
         joy('pitch',Z,True),fixed('yaw',-1),joy('throttle',ONE,False),fixed('mixture',ONE),
         keypair('left_brake',[74],[75],1,HALF),fixed('right_brake',0),fixed('trim',Z)]
        p['actions']=[{'id':'recenter','sources':[{'kind':'physical_keys','keys':[82]}]},
         {'id':'look_hold','sources':[{'kind':'mouse_button','button':F('4000000000000000')}]},
         {'id':'view_cycle','sources':[{'kind':'joy_button','slot':'stick-A','index':F('405fc00000000000')}]}]
    if version==2:
        p.update(profile=deepcopy(PISTON),capability_revision='piston-controls-v1',systems=[
         {'id':s,'kind':'momentary' if s=='engine.starter' else 'toggle',
          'sources':[{'kind':'physical_keys','keys':[k]}]}
         for s,k in [('engine.ignition_left',73),('engine.ignition_right',79),('engine.starter',83),('fuel.feed',70)]])
        if rich: p['axes'][4]=keypair('mixture',[77],[78],SMALL,HALF)
    return p

def normalized_rich(p):
    # Explicit normalization oracle for THESE authored leaves, not an input walker.
    n=deepcopy(p);n['version']=2 if 'systems' in n else 1
    n['axes'][0]['negative']=[65];n['axes'][1]['index']=0;n['axes'][3]['index']=1
    n['actions'][1]['sources'][0]['button']=2;n['actions'][2]['sources'][0]['index']=127
    return n

def audio(): return {'enabled':True,'engine_gain':Z,'airflow_gain':HALF,'show_panel_captions':False}
def prefs(legacy=None,piston=None):
    return {'type':'LocalPlayerPreferences','version':1,'player_id':A,'revision':'3',
     'legacy_input':legacy,'piston_input':piston,'audio':audio()}
def player(id=A,name='Ana "Δ" \\ 飛行',rev='3'):
    return {'type':'LocalPlayer','version':1,'id':id,'name':name,'created_utc':'2000-02-29T00:00:00Z',
     'updated_utc':UTC,'revision':rev}
def source(piston=False,variant=None,session='fixture-session'):
    v=variant or VARIANTS[-1]
    return {'session_id':session,'model_identity':deepcopy(PISTON if piston else LEGACY),
     'source_variant':v,'native_source_fingerprint':'4'*64,'prepared_world_sha256':'5'*64,
     'named_start':'piston-cold-ground' if piston else 'airborne-prepared',
     'wind_profile':'calm' if piston else 'from-west',
     'angular_integration_method':None if not piston else 'event_aware_constant_power_v1' if v==VARIANTS[1] else 'event_aware_coupled_midpoint_v1'}
def practice(id=P,owner=A,creation='9',commit='12',session='fixture-session',linked=False):
    p={'type':'LocalPractice','version':1,'id':id,'player_id':owner,'source':source(session=session),
     'started_utc':UTC,'last_observed_utc':'2026-10-11T05:59:59Z','first_tick':'9007199254740993',
     'last_tick':'9007199254741113','observed_ticks':'120','tick_rate_hz':120,
     'status':'manually_ended','end_reason':'user_end','revision':'2',
     'creation_sequence':creation,'commit_sequence':commit,'archive':None}
    if linked:
        p['archive']={'type':'ExternalRecordedReview','version':1,'absolute_path':'C:/fixture-only/Δ/review.json',
         'payload_sha256':'6'*64,'recording_session_id':session,'first_tick':'9007199254741000',
         'last_tick':'9007199254741100','linked_utc':UTC}
    return p
def summary(p):
    p=deepcopy(p);p['archive']={'linked':p['archive'] is not None};return p
def row_player(p):
    blob=exact_bytes(p);return {'commit_sequence':'3','id':p['id'],'revision':p['revision'],'record':blob,'record_sha256':blob['sha256']}
def row_prefs(p):
    blob=exact_bytes(envelope('LocalPlayerPreferences',p));return {'player_id':p['player_id'],'revision':p['revision'],'record':blob,'record_sha256':blob['sha256']}
def row_practice(p):
    return {**{k:p[k] for k in ['id','player_id','creation_sequence','commit_sequence','revision','status']},
     'source_fingerprint':p['source']['native_source_fingerprint'],'source_session':p['source']['session_id'],
     'record':exact_bytes(p),'record_sha256':exact_bytes(p)['sha256']}

def put(v,path,replacement):
    for k in path[:-1]:v=v[k]
    v[path[-1]]=replacement

def build(schema_source):
    assert F('4050400000000000').rational()==65 and F('405fc00000000000').rational()==127
    assert F('405e000000000000').rational()==120 and ONE.rational()==1
    assert Z.rational()==0 and SMALL.rational()==Fraction(1,1<<1074)
    rows=[]
    def add(id,group,input,expected,basis):
        rows.append({'id':id,'group':group,'input':input,'expected':expected,'basis':basis})
    def validprefs(id,raw,norm=None):
        n=norm or raw;e=envelope('LocalPlayerPreferences',n)
        add(id,'complete_preferences',typed(raw),{'valid':True,'normalized':typed(n),
         'payload':exact_bytes(n),'envelope':exact_bytes(e),'decoded':typed(n)},
         'Complete closed records; exact typed and binary64 roundtrip. Physical key name/code roundtrip remains an actual Godot prerequisite.')
    validprefs('P01_defaults',prefs())
    v1=preset(1,True);v1['version']=ONE
    v2=preset(2,True);v2['version']=F('4000000000000000')
    n1=normalized_rich(v1);n2=normalized_rich(v2)
    validprefs('P02_legacy_complete',prefs(v1),prefs(n1))
    validprefs('P03_piston_complete',prefs(None,v2),prefs(None,n2))
    both=prefs(n1,n2);validprefs('P04_both_profiles',both)
    j=deepcopy(both);j['piston_input']['axes'][4]=joy('mixture',2,False);validprefs('P07_piston_unsigned_mixture_axis',j)
    p=prefs(preset(1));p['audio']['airflow_gain']=SMALL;validprefs('P05_audio_subnormal',p)
    p=prefs(preset(1));p['audio']['engine_gain']=ONE;p['audio']['airflow_gain']=ONE
    p['legacy_input']['devices']=[{'slot':'s'+str(i),'label':'','match':{'guid':'','name':'','vendor_id':'','product_id':''}} for i in range(8)]
    validprefs('P06_eight_devices_upper_gains',p)
    negatives=[
     ('audio_INT_gain',['audio','engine_gain'],0,'Audio gains require FLOAT, not INT'),
     ('audio_BOOL_gain',['audio','engine_gain'],False,'BOOL is not a real gain'),
     ('audio_nan',['audio','engine_gain'],F('7ff8000000000001'),'Nonfinite FLOAT rejects'),
     ('audio_negative_subnormal',['audio','airflow_gain'],F('8000000000000001'),'Finite negative gain is below zero'),
     ('audio_gain_above_one',['audio','airflow_gain'],F('3ff0000000000001'),'Exact next binary64 above one rejects'),
     ('legacy_variable_mixture',['legacy_input','axes',4,'value'],HALF,'v1 mixture is exactly one'),
     ('centered_span_too_small',['legacy_input','axes',1,'minimum'],Z,'Centered minimum must be at least .05 below center'),
     ('saturation_equals_deadzone',['legacy_input','axes',1,'saturation'],Z,'Saturation strictly exceeds deadzone'),
     ('fractional_axis_index',['legacy_input','axes',1,'index'],HALF,'Index must be integral'),
     ('unknown_slot',['legacy_input','axes',1,'slot'],'missing','Axis slot must be declared'),
     ('keypair_zero_rate',['legacy_input','axes',0,'rate'],Z,'Rate must be strictly positive; negative zero is zero'),
     ('piston_profile_mismatch',['piston_input','profile','id'],'original-interactive-prototype','Exact piston profile triple'),
     ('piston_mixture_recenter',['piston_input','axes',4,'return_to_start'],True,'Mixture key pair may not return to start'),
     ('piston_alias_collision',['piston_input','systems',0,'sources',0,'keys'],[65],'One physical control cannot own an axis and a system'),
     ('piston_wheel_toggle',['piston_input','systems',3,'sources'],[{'kind':'mouse_button','button':4}],'Wheel event is not persistent system input'),
     ('StringName_kind',['piston_input','axes',0,'kind'],Wrong('STRING_NAME','key_pair'),'Actual String required'),
     ('integral_FLOAT_record_version',['version'],ONE,'Record version is actual INT1; preset normalization does not apply')]
    for name,path,value,basis in negatives:
        p=deepcopy(both);put(p,path,value)
        add('PN_'+name,'complete_preferences_negative',typed(p),{'valid':False,'normalized':None,'bytes':None},basis)
    p=deepcopy(both);p['audio']['extra']=True
    add('PN_unknown_audio_key','complete_preferences_negative',typed(p),{'valid':False,'bytes':None},'Audio is exactly four keys')
    for name,path,value,basis in [
     ('player_name_40_scalars',['name'],'😀'*40,'40 scalars/160 UTF8 bytes is valid'),
     ('player_name_41_scalars',['name'],'😀'*41,'41 scalars/164 bytes exceeds both bounds'),
     ('player_name_trailing_space',['name'],'Ana ','No leading/trailing whitespace'),
     ('player_name_C0',['name'],'A\x01B','No C0 names'),
     ('player_leap_invalid',['created_utc'],'2100-02-29T00:00:00Z','2100 is not Gregorian leap year'),
     ('player_zero_revision',['revision'],'0','Revision must be positive'),
     ('player_fullmax_revision',['revision'],str(MAX),'Full canonical uint64 maximum is permitted'),
     ('player_extra',['extra'],None,'Closed Player shape')]:
        p=player();put(p,path,value);ok=name in ['player_name_40_scalars','player_fullmax_revision']
        add('R_'+name,'complete_player',typed(p),{'valid':ok,'canonical':exact_bytes(p) if ok else None},basis)
    p0=practice(linked=True);q=practice(Q,creation='10',commit='11',session='fixture-session-two')
    for name,path,value,basis in [
     ('duration_mismatch',['observed_ticks'],'119','Exact last-first is120, never float subtraction'),
     ('tick_overflow',['last_tick'],str(MAX+1),'Canonical tick exceeds uint64'),
     ('rate_FLOAT',['tick_rate_hz'],F('405e000000000000'),'Rate must be actual INT120'),
     ('status_reason_mismatch',['end_reason'],'native_terminal','Reason must match manually_ended'),
     ('source_session_mismatch',['archive','recording_session_id'],'another-session','Archive association must match practice source'),
     ('source_hash_uppercase',['source','native_source_fingerprint'],'A'*64,'Hashes are lowercase hex'),
     ('source_extra',['source','extra'],None,'PracticeSource is closed'),
     ('record_BOOL_version',['version'],True,'BOOL never INT')]:
        p=deepcopy(p0);put(p,path,value)
        add('RN_'+name,'complete_practice_negative',typed(p),{'valid':False},basis)
    p=practice();p.update(first_tick='0',last_tick=str(MAX),observed_ticks=str(MAX),revision=str(MAX))
    add('R_practice_full_uint64','complete_practice',typed(p),{'valid':True,'canonical':exact_bytes(p)},'Exact full-range endpoints/difference and revision; no floating duration oracle')
    for name,s,ok,basis in [
     ('legacy_upstream',source(variant=VARIANTS[0]),True,'Legacy admitted under upstream'),
     ('legacy_fourth',source(),True,'Legacy noncalm under fourth variant'),
     ('piston_constant',source(True,VARIANTS[1]),True,'Cold calm constant-power pairing'),
     ('piston_coupled_v1',source(True,VARIANTS[2]),True,'Cold calm coupled method pairing'),
     ('piston_local_v2',source(True),True,'Cold calm local-window uses existing coupled method name'),
     ('piston_upstream',source(True,VARIANTS[0]),False,'No upstream piston history admitted')]:
        add('S_'+name,'complete_source',typed(s),{'shape_and_tuple_valid':ok,'current_flight_authority':False},basis)
    for name,path,value,basis in [
     ('piston_noncalm',['wind_profile'],'from-east','Piston cold admits calm only'),
     ('piston_airborne',['named_start'],'airborne-prepared','Piston requires cold start'),
     ('piston_wrong_method',['angular_integration_method'],'event_aware_constant_power_v1','Method must agree with variant'),
     ('legacy_nonnull_method',['angular_integration_method'],'event_aware_coupled_midpoint_v1','Legacy method must be null'),
     ('session_adjacent_separator',['session_id'],'fixture--session','Canonical wire identifier forbids adjacent separators')]:
        s=source(name!='legacy_nonnull_method');put(s,path,value)
        add('SN_'+name,'complete_source',typed(s),{'shape_and_tuple_valid':False,'current_flight_authority':False},basis)
    pb=player(B,'Ana "Δ" \\ 飛行','1');bp=prefs();bp.update(player_id=B,revision='1')
    other=practice(R,B,'8','8','other-player-session')
    dataset={'meta':{'singleton':1,'schema_version':1,'schema_fingerprint':SCHEMA,'codec_fingerprint':CODEC,
     'store_id':'7'*32,'owner_run_id':'8'*32,'created_utc':UTC,'commit_sequence':'12'},
     'players':[row_player(player()),row_player(pb)],'preferences':[row_prefs(both),row_prefs(bp)],
     'practices':[row_practice(p0),row_practice(q),row_practice(other)]}
    add('D01_complete_two_players','cross_column',dataset,{'qualifies_semantically':True},'Exact typed blobs, actual bytes/hash, owners, revisions, redundant fields and sequence inequalities; duplicate names allowed. Synthetic dataset, not an executed DB.')
    mutations=[
     ('column_player_revision',['players',0,'revision'],'4','Indexed revision disagrees with blob'),
     ('column_player_id',['players',0,'id'],B,'Indexed ID disagrees with blob'),
     ('column_prefs_owner',['preferences',0,'player_id'],B,'Prefs indexed owner disagrees with blob'),
     ('column_prefs_revision',['preferences',0,'revision'],'4','Prefs indexed revision disagrees with blob'),
     ('column_practice_status',['practices',0,'status'],'active','Indexed status disagrees with blob'),
     ('column_source_session',['practices',0,'source_session'],'wrong-session','Indexed session disagrees with blob'),
     ('column_source_fingerprint',['practices',0,'source_fingerprint'],'9'*64,'Indexed fingerprint disagrees with blob'),
     ('column_creation',['practices',0,'creation_sequence'],'7','Indexed immutable creation disagrees with blob'),
     ('column_commit',['practices',0,'commit_sequence'],'11','Indexed latest commit disagrees with blob'),
     ('column_practice_revision',['practices',0,'revision'],'3','Indexed row revision disagrees with blob'),
     ('column_practice_owner',['practices',0,'player_id'],B,'Indexed player disagrees with blob'),
     ('hash_mismatch',['practices',0,'record_sha256'],'0'*64,'Stored digest disagrees with actual bytes'),
     ('meta_behind',['meta','commit_sequence'],'11','Row latest commit12 exceeds meta11')]
    for name,path,value,basis in mutations:
        d=deepcopy(dataset);put(d,path,value)
        add('DN_'+name,'cross_column',d,{'qualifies_semantically':False,'failure':'corrupt_store'},basis)
    d=deepcopy(dataset);d['preferences'].pop()
    add('DN_missing_preferences','cross_column',d,{'qualifies_semantically':False,'failure':'corrupt_store'},'Exactly one preference row per player')
    d=deepcopy(dataset);bad=player(rev='4');d['players'][0]=row_player(bad)
    add('DN_shared_revision','cross_column',d,{'qualifies_semantically':False,'failure':'corrupt_store'},'Internally consistent player/index/hash still disagrees with preference shared revision3')
    d=deepcopy(dataset);bad=deepcopy(p0);bad['observed_ticks']='119';d['practices'][0]=row_practice(bad)
    add('DN_semantic_corruption_rehashed','cross_column',d,{'qualifies_semantically':False,'failure':'corrupt_store'},'Matching blob hash/index fields do not repair wrong endpoint arithmetic')
    # Complete schema SQL is supplied verbatim through an explicitly pinned input.
    sql=Path(schema_source).read_bytes();assert sha(sql)==SCHEMA
    add('SQL_exact','schema',{'utf8_hex':sql.hex()}, {'matches_allocated_schema':True},'Inspection oracle only: actual SQLite sqlite_schema/columns/FKs/index definitions remain runtime prerequisites')
    changes=[('not_strict','\n) STRICT;','\n);'),('fk_missing_cascade','ON DELETE CASCADE',''),
     ('active_index_not_unique','CREATE UNIQUE INDEX practices_one_active','CREATE INDEX practices_one_active'),
     ('mutable_cursor_index','length(creation_sequence) DESC,creation_sequence COLLATE BINARY DESC','length(commit_sequence) DESC,commit_sequence COLLATE BINARY DESC')]
    for name,old,new in changes:
        text=sql.decode('utf8');assert old in text;raw=text.replace(old,new,1).encode('utf8')
        add('SQLN_'+name,'schema',{'utf8_hex':raw.hex()}, {'matches_allocated_schema':False},'Exact DDL declaration mismatch even if stored schema fingerprint column is unchanged')
    add('SQLN_extra_trigger','schema',{'utf8_hex':(sql+b'CREATE TRIGGER extra AFTER INSERT ON players BEGIN SELECT 1; END;\n').hex()},
     {'matches_allocated_schema':False},'Extra triggers forbidden, not merely checked schema fingerprint')
    # Revision/equality witnesses carry complete owned bundle values.
    for name,expected_rev,newbundle,ok,basis in [
     ('stale_equal','2',both,{'state':'failed','error_code':'revision_conflict'},'Expected revision before content equality'),
     ('current_equal','3',both,{'state':'no_change','commit_sequence':'3','value':typed({'player':player(),'preferences':both})},'Current equal bytes preserve timestamps/revisions'),
     ('signed_zero_changes','3',{**both,'audio':{**both['audio'],'engine_gain':F('0000000000000000')}},
      {'state':'committed','next_shared_revision':'4','next_global_sequence':'13'},'Negative and positive zero FLOAT bits are distinct durable preference content')]:
        add('E_'+name,'equality_revision',{'current_player':typed(player()),'current_preferences':typed(both),
         'meta_commit_sequence':'12','player_commit_sequence':'3','expected_revision':expected_rev,'new_preferences':typed(newbundle)},ok,basis)
    summaries=[summary(q),summary(p0)]
    add('PAGE_all','cursor',{'all_owned_rows':typed([summary(p0),summary(other),summary(q)]),'player_id':A,
     'before_creation_sequence':None,'limit':1},{'practice':typed([summary(q)]),'next_before_creation_sequence':'10'},'Numeric creation10 precedes9 despite latest commits11<12; other owner excluded')
    add('PAGE_next','cursor',{'all_owned_rows':typed([summary(p0),summary(other),summary(q)]),'player_id':A,
     'before_creation_sequence':'10','limit':1},{'practice':typed([summary(p0)]),'next_before_creation_sequence':None},'Strictly below cursor and exact end/null; no external archive access')
    add('PAGE_zero','cursor',{'all_owned_rows':typed(summaries),'player_id':A,'before_creation_sequence':'0','limit':50},
     {'practice':typed([]),'next_before_creation_sequence':None},'Zero is valid cursor and selects no positive creation sequence')
    named=player(name='É');decomposed=player(name='E\u0301')
    add('E_unicode_not_normalized','equality_revision',{'composed':typed(named),'decomposed':typed(decomposed)},
     {'both_names_valid':True,'records_equal':False,'composed':exact_bytes(named),'decomposed':exact_bytes(decomposed)},'Unicode scalar sequences preserved; no NFC/case-fold repair')
    # Full export is fixed before consumers; source hashes here are synthetic.
    export_payload={'player':player(),'preferences':both,'practice':summaries}
    export=envelope('LocalPlayerSummary',export_payload);raw=canonical(export).encode('utf8')
    add('EXPORT_two_summaries','canonical_export',{'snapshot':typed(export_payload)},
     {'payload':exact_bytes(export_payload),'file':{'relative_path':'player-summary-v1.json','bytes':len(raw),'sha256':sha(raw)},
      'decoded':typed(export_payload),'practice_id_order':[Q,P],'archive_paths_present':False},
     'Proposed companion fixes complete Array order creation DESC. Exact UTF8 lexical object keys, supplied array order, quote/backslash escapes, literal Unicode, no BOM/whitespace/final LF. Not an actual file save.')
    empty={'player':player(),'preferences':prefs(),'practice':[]}
    add('EXPORT_empty_history','canonical_export',{'snapshot':typed(empty)}, {'envelope':exact_bytes(envelope('LocalPlayerSummary',empty))},'Empty history is [] without truncation; coherent snapshot premise must be observed later')
    e=envelope('LocalPlayerPreferences',both)
    e['payload_sha256']='0'*64
    add('WIRE_digest_mismatch','complete_encoded_preferences',exact_bytes(e),{'valid':False},'Complete envelope digest differs from exact payload bytes')
    e=envelope('LocalPlayerPreferences',both);e['payload_json']=e['payload_json'][:-1]+',"version":1}'
    e['payload_sha256']=sha(e['payload_json'].encode('utf8'))
    add('WIRE_duplicate_rehashed','complete_encoded_preferences',exact_bytes(e),{'valid':False},'Correct digest does not admit duplicate original payload key')
    for name,path,value in [('tag_at_INT_version',['version'],ONE),('nonfinite_gain_tag',['audio','engine_gain'],F('7ff0000000000000'))]:
        p=deepcopy(both);put(p,path,value)
        add('WIRE_'+name,'complete_encoded_preferences',exact_bytes(envelope('LocalPlayerPreferences',p)),{'valid':False},'Whole encoded envelope with correct hash; tagged FLOAT only at admitted finite real-valued paths')
    # Concrete bounded expansion recipe: each complete row is fixed, all 2000
    # IDs/sessions/creation values are specified; no SQLite or source authority.
    template=practice(creation='2',commit='2');template['source']['session_id']='s'+'a'*120+'0000000'
    capplayer=player(name='😀'*40)
    capsummary=[]
    for i in range(2000):
        item=deepcopy(template);item['id']=format(i+1,'032x');item['creation_sequence']=str(i+2);item['commit_sequence']=str(i+2)
        item['source']['session_id']='s'+'a'*120+format(i,'07d');capsummary.append(summary(item))
    capsummary.reverse()
    capexport=envelope('LocalPlayerSummary',{'player':capplayer,'preferences':both,'practice':capsummary})
    capraw=canonical(capexport).encode('utf8');capinner=capexport['payload_json'].encode('utf8')
    add('CAP_full_2000_summary_export','complete_bounded_expansion',{'template':typed(template),'player':typed(capplayer),'preferences':typed(both),
     'count':2000,'i_range':[0,1999],'per_i':{'id':'lowerhex32(i+1)','creation_sequence':'canonicalU64(i+2)',
     'commit_sequence':'canonicalU64(i+2)','source.session_id':'literal s + 120 lowercase a + decimal(i) padded to7'},
     'summary_archive':{'linked':False},'output_order':'i DESC'},
     {'row_count':2000,'inner_bytes':len(capinner),'inner_sha256':sha(capinner),'outer_bytes':len(capraw),'outer_sha256':sha(capraw),
      'first_id':capsummary[0]['id'],'last_id':capsummary[-1]['id'],'below_export_32MiB':len(capraw)<=33554432},
     'Complete expansion oracle at history COUNT cap; not a maximum possible byte-size theorem or real DB/export observation. Outer escaping is independently counted.')
    # Gate boundary inputs are explicitly not semantically admitted records.
    for id,limit,n,encoding in [('byte_cap_exact',614400,614400,'UTF8_ASCII_SPACE'),('byte_cap_plus_one',614400,614401,'UTF8_ASCII_SPACE'),('slot_cap_exact',262144,262144,'UTF8_ASCII_SPACE'),('slot_cap_plus_one',262144,262145,'UTF8_ASCII_SPACE'),('restored_preset_cap_exact',65536,65536,'UTF8_ASCII_SPACE'),('restored_preset_cap_plus_one',65536,65537,'UTF8_ASCII_SPACE'),('export_cap_plus_one',33554432,33554433,'UTF8_ASCII_SPACE'),
     ('string_scalar_exact',1024,1024,'U+1F600'),('string_scalar_plus_one',1024,1025,'U+1F600'),
     ('values_exact',30000,30000,'ARRAY_TOTAL_VALUES_INCLUDING_ROOT'),('values_plus_one',30000,30001,'ARRAY_TOTAL_VALUES_INCLUDING_ROOT')]:
        add('CAP_'+id,'scanner_gate_only',{'expand_exact':encoding,'count':n,'limit':limit},
         {'within_this_cap_only':n<=limit,'semantic_record_admission':False},'Exact expansion recipe exercises preflight cap only. Passing this gate never makes spaces/an arbitrary String/Array a complete preset or record. Value-count convention is proposed companion, not hidden assumption.')
    cap=prefs(preset(1));cap['legacy_input']['devices']=[{'slot':'s'+str(i),'label':'','match':{'guid':'','name':'','vendor_id':'','product_id':''}} for i in range(9)]
    add('CAP_complete_ninth_device','complete_preferences_negative',typed(cap),{'valid':False,'bytes':None},'Complete otherwise-valid eight-device P06 plus one declared ninth device violates max8')
    for depth in [12,13]:
        text='['*depth+'0'+']'*depth
        add('CAP_depth_'+str(depth),'scanner_gate_only',{'utf8_hex':text.encode('ascii').hex(),'root_container_depth':1},
         {'depth':depth,'within_this_cap_only':depth<=12,'semantic_record_admission':False},'Container-depth convention proposed explicitly; no claim this scalar-array is a record')
    for id,rawtext,basis in [
     ('duplicate_key','{"audio":{},"audio":{}}','Duplicate original keys rejected'),
     ('escaped_key','{"\\u0061udio":{}}','Escaped object keys rejected'),
     ('lone_surrogate','{"name":"\\ud800"}','Escaped lone surrogate is not scalar-valid'),
     ('reversed_surrogate','{"name":"\\udc00\\ud800"}','Reversed surrogate escapes rejected'),
     ('naked_negative_zero','{"version":-0}','Naked negative-zero integer token rejected'),
     ('naked_real','{"version":1.0}','Real tokens forbidden even if integral; normalized enums must be canonical INT')]:
        add('GRAMMAR_'+id,'scanner_negative',{'utf8_hex':rawtext.encode('ascii').hex()},{'valid':False},basis+'; fragment is deliberately not a full record and does not claim a specific precedence code')
    result={'schema':'IndependentLocalPlayersFullRecordReferences/v1','status':'PROPOSED_PRECONSUMER_UNRATIFIED',
     'license':'Original MIT','case_count':len(rows),'typed_descriptor_policy':'All values explicit NIL/BOOL/INT decimal/FLOAT LE/STRING/ARRAY/DICTIONARY. STRING_NAME is negative test-only. Byte fields hex restore as bytes; never parse typed INT/FLOAT through ordinary JSON numbers.',
     'authority':'Synthetic source hashes/IDs/paths never grant flight/filesystem authority. No DB/consumer/Godot executed. Complete key-bearing presets require actual OS name/code parity qualification.',
     'rows':rows}
    return pretty(result),raw

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');ap.add_argument('--schema-source',required=True);a=ap.parse_args()
    expected,export=build(a.schema_source)
    outputs={'expected-v1.json':expected,'player-summary-v1.json':export}
    for name,raw in outputs.items():
        p=ROOT/name
        if a.check:
            if p.read_bytes()!=raw: raise SystemExit('Changed independent reference: '+name)
        else:p.write_bytes(raw)
    print(json.dumps({'mode':'read_only_check' if a.check else 'author_original_reference',
     'cases':json.loads(expected)['case_count'],'expected_sha256':sha(expected),'export_sha256':sha(export)}))
if __name__=='__main__':main()
