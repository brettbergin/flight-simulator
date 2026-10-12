#!/usr/bin/env python3
"""Original MIT. Complete hypothetical taxi compatibility values, not observations.

Only stdlib and immutable independent pose data. --check never writes fixtures.
"""
from pathlib import Path
from copy import deepcopy
import argparse, hashlib, json, struct

WORLD='04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5'
VARIANT='jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2'
POSE_SHA='fb543ddd1681c3cb040cdfd1c65ff404eb9409e73bb6f613c225a3a501f2e333'
MODELS=[{'id':'original-interactive-prototype','version':'0.1.0-prototype','backend_model':'original-interactive'},{'id':'original-piston-prop-v1','version':'0.1.0-prototype','backend_model':'original-piston-prop'}]
STARTS=['apron-ready','piston-cold-apron']
UNITS={'tas':'m/s','ground_speed':'m/s','pitch':'rad','bank':'rad','heading_true':'rad','ellipsoid_height':'m','vertical_speed':'m/s','body_yaw_rate':'rad/s','fuel_total':'kg'}
ENGINE_UNITS={'fuel.total':'kg','engine.throttle':'fraction','engine.mixture':'fraction','propeller.angular_speed':'radps','engine.running':'bool','engine.ignition_left':'bool','engine.ignition_right':'bool','engine.starter':'bool','fuel.feed':'bool','engine.starved':'bool'}

def sha(raw):return hashlib.sha256(raw).hexdigest()
def canonical(value):return json.dumps(value,sort_keys=True,ensure_ascii=False,separators=(',',':'),allow_nan=False)
def pretty(value):return (json.dumps(value,indent=2,ensure_ascii=True,allow_nan=False)+'\n').encode('ascii')
def descriptor(role):
    return {'type':'OriginalHypotheticalTaxiFixtureIdentity','version':1,'role':role,'author':'Flight Simulator Project original MIT reference','purpose':'non-native preconsumer closed-value fixture only','native_authority':False,'compiled_or_loaded':False}
def identity(role):return sha(canonical(descriptor(role)).encode('utf-8'))
def typed(value):
    if type(value) is float:return {'$binary64_le':struct.pack('<d',value).hex()}
    if type(value) is dict:return {k:typed(v) for k,v in value.items()}
    if type(value) is list:return [typed(v) for v in value]
    return value
def exact(value):return sha(canonical(typed(value)).encode('utf-8'))
def decode_scalar(row):return struct.unpack('<d',bytes.fromhex(row['binary64_le']))[0]
def vec(values):return dict(zip(['x','y','z'],values))
def channel(value,unit,error=''):return {'value':value,'unit':unit,'valid':value is not None,'error':error}

def readback(pose,piston=False,tick='0',session=None):
    i=int(piston);sid=session or 'hypothetical-taxi-'+('piston' if piston else 'legacy')
    xyz=list(map(decode_scalar,pose['selected']['rounded_order_ecef_m']))
    geo=list(map(decode_scalar,pose['selected']['geodetic_rad_m']))
    columns=[[decode_scalar(x) for x in column] for column in pose['selected']['body_to_anchor_eus_columns']]
    rotation=[columns[c][r] for r in range(3) for c in range(3)]
    position=dict(zip(['latitude_rad','longitude_rad','ellipsoid_height_m'],geo))
    axes={'kind':'axes','roll':0.,'pitch':0.,'yaw':0.,'throttle':0.,'mixture':0. if piston else 1.,'left_brake':1.,'right_brake':1.,'trim':0.}
    systems={'fuel.total':100.,'engine.throttle':0.,'engine.mixture':0.,'propeller.angular_speed':0.,'engine.running':False,'engine.ignition_left':False,'engine.ignition_right':False,'engine.starter':False,'fuel.feed':True,'engine.starved':False} if piston else {'fuel.total':100.}
    aircraft={'type':'AircraftSnapshot','schema_version':1,'tick':tick,'session_id':sid,'clock':{'purpose':'runtime','tick_rate_hz':120},'elapsed_s':int(tick)/120.,'position':position,'ecef_position_m':vec(xyz),'orientation_body_to_ned':{'w':1.,'x':0.,'y':0.,'z':0.},'velocity_body_mps':vec([0.,0.,0.]),'angular_rate_body_radps':vec([0.,0.,0.]),'acceleration_body_mps2':vec([0.,0.,0.]),'mass_kg':1100.,'center_of_gravity_body_m':vec([0.,0.,0.]),'configuration':{'flap_fraction':0.,'gear_fraction':1.,'trim_fraction':0.},'systems':[{'id':k,'quantity':ENGINE_UNITS[k],'value':v,'validity':'valid'} for k,v in systems.items()],'contacts':[],'validity':'valid'}
    weather={'type':'AtmosphereSample','schema_version':1,'tick':tick,'session_id':sid,'position':deepcopy(position),'pressure_pa':101325.,'temperature_k':288.15,'density_kgpm3':1.225,'relative_humidity':0.,'wind_toward_ned_mps':vec([0.,0.,0.]),'turbulence_ned_mps':vec([0.,0.,0.]),'seed':'42','model_id':'hypothetical-still-air'}
    return {'host_mode':'paused','error':'','historical':False,'session_id':sid,'tick':tick,'aircraft':aircraft,'atmosphere':weather,'held_axes':axes,'native_outcome':'paused','native_live':True,'paused':True,'time_scale':1.,'debt_quanta':0,'native_fault':'','named_start':STARTS[i],'model_identity':deepcopy(MODELS[i]),'native_source_fingerprint':identity('source'),'prepared_world_sha256':WORLD,'world_anchor':{'latitude_rad':.8,'longitude_rad':-2.,'ellipsoid_height_m':0.},'canonical':{'ecef_position_m':xyz,'anchor_eus_position_m':[108.,1.05,18.],'body_to_anchor_eus':rotation}}

def readings(rb,engine=False):
    state='historical' if rb['historical'] else ('paused' if rb['paused'] else 'live')
    if engine:
        systems={x['id']:x for x in rb['aircraft']['systems']}
        channels={}
        for name,unit in ENGINE_UNITS.items():
            s=systems.get(name)
            channels[name]=channel(s['value'],unit) if s is not None else channel(None,unit,'Native '+name+' is unavailable')
    else:
        # Original authored identity orientation, zero velocity/rates/still air.
        # This is direct independent algebra, not a call to NativeReadings.
        vals={'tas':0.,'ground_speed':0.,'pitch':0.,'bank':0.,'heading_true':0.,'ellipsoid_height':rb['aircraft']['position']['ellipsoid_height_m'],'vertical_speed':-0.,'body_yaw_rate':0.,'fuel_total':100.}
        channels={k:channel(vals[k],u) for k,u in UNITS.items()}
    return {'session_id':rb['session_id'],'tick':rb['tick'],'state':state,'native_truth':True,'readings':channels,'error':''}

def unavailable(error,state='invalid',engine=False):
    units=ENGINE_UNITS if engine else UNITS
    return {'session_id':None,'tick':None,'state':state,'native_truth':True,'readings':{k:channel(None,u,error) for k,u in units.items()},'error':error}

def recording(rbs,reason=None):
    rb=rbs[0];piston=rb['model_identity']==MODELS[1]
    meta={k:deepcopy(rb[k]) for k in ['session_id','model_identity','native_source_fingerprint','prepared_world_sha256','world_anchor','named_start']}
    meta.update(seed='42',clock=deepcopy(rb['aircraft']['clock']),first_tick=rb['tick'])
    samples=[]
    for item in rbs:
        sample={'tick':item['tick'],'target_tick':item['tick'],'late_by_ticks':0,'skipped_targets_before':0,'gap_before':False,'elapsed_s':item['aircraft']['elapsed_s'],'anchor_eus_position_m':deepcopy(item['canonical']['anchor_eus_position_m']),'readings':readings(item),'held_axes':deepcopy(item['held_axes'])}
        if piston:sample['engine_status']=readings(item,True)
        samples.append(sample)
    return {'contract_version':2 if piston else 1,'state':'sealed' if reason else 'recording','metadata':meta,'last_observed_tick':rbs[-1]['tick'],'samples':samples,'seal_reason':reason,'error':'','skipped_target_count':0,'late_sample_count':0,'uncaptured_tail_targets':0}

def archive(record):
    payload=canonical(typed(record));digest=sha(payload.encode('utf-8'));rev=record['contract_version']
    envelope={'format':'ObservedFlightReview','archive_version':rev,'recording_contract_version':rev,'payload_json':payload,'payload_sha256':digest}
    text=canonical(envelope)
    return {'utf8_text':text,'bytes':len(text.encode('utf-8')),'sha256':sha(text.encode('utf-8')),'payload_sha256':digest,'decoded_recording':typed(record)}

def source(rb):
    return {'session_id':rb['session_id'],'model_identity':deepcopy(rb['model_identity']),'source_variant':VARIANT,'native_source_fingerprint':rb['native_source_fingerprint'],'prepared_world_sha256':WORLD,'named_start':rb['named_start'],'wind_profile':'calm','angular_integration_method':'event_aware_coupled_midpoint_v1' if rb['model_identity']==MODELS[1] else None}

def build_original(pose):
    fixtures={};cases=[];lifecycles=[]
    def put(name,value,role):
        assert name not in fixtures
        fixtures[name]={'role':role,'typed_value':typed(value),'exact_typed_sha256':exact(value)}
        return name
    def case(name,kind,fixture,expected):cases.append({'id':name,'boundary':kind,'fixture':fixture,'expected':expected})
    selected=[]
    for piston in [False,True]:
        p='piston' if piston else 'legacy';rbs=[readback(pose,piston,t) for t in ['0','60','120']]
        for rb in rbs:
            ident=put(p+'-paused-'+rb['tick'],rb,'complete hypothetical Readback, no native observation')
            case(ident,'Readback',ident,{'new_domain':'paused','old_reader':'invalid','old_reader_error':'Unknown named start','actual_current_source_qualified':False,'geometry_available_in_synthetic_context':True})
        for rb in rbs:
            put(p+'-readings-'+rb['tick'],readings(rb),'complete independently derived expected ReadingSet')
            if piston:put(p+'-engine-'+rb['tick'],readings(rb,True),'complete expected EngineStatus, authored cold scalars/bools')
        put(p+'-old-reader-rejection',unavailable('Unknown named start'),'complete unchanged older-reader rejection; no fields dropped/relabelled')
        live=deepcopy(rbs[1]);live.update(host_mode='live',paused=False,native_outcome='completed')
        ident=put(p+'-live-60',live,'complete hypothetical live publication')
        case(ident,'Readback',ident,{'new_domain':'live','navigation_mutation':'not_paused','actual_current_source_qualified':False})
        hist=deepcopy(rbs[-1]);hist.update(host_mode='closed',historical=True,native_live=False,paused=False,canonical=None)
        ident=put(p+'-closed-120',hist,'complete retained closed Readback, canonical null')
        case(ident,'Readback',ident,{'new_domain':'historical','navigation_available':False,'current_source_identity':None,'target_eus_m':None,'points':[],'planar_range_m':None,'anchor_bearing_deg':None})
        a=recording(rbs);manual=recording(rbs,'manual');closed=recording(rbs,'closed')
        for suffix,value in [('recording',a),('manual',manual),('closed',closed)]:
            ident=put(p+'-record-'+suffix,value,'complete hypothetical Recording'+str(value['contract_version']))
            case(ident,'Recording',ident,{'new_domain_valid':True,'old_reader_valid':False,'owned_copies_required':True})
        ar=archive(manual);ident=put(p+'-archive',ar,'exact full hypothetical archive envelope text/bytes, not a Save receipt')
        case(ident,'Archive',ident,{'new_domain_decode':True,'old_reader_decode':False,'all_types_bits_preserved':True,'payload_sha256':ar['payload_sha256'],'native_authority_from_decode':False})
        sr=source(rbs[0]);ident=put(p+'-source',sr,'complete PracticeSource, synthetic fingerprint cannot authorize actual flight')
        case(ident,'PracticeSource',ident,{'closed_semantics_new_domain':True,'old_closed_domain':False,'historical_same_shape_hash_may_differ_from_installed':True,'current_adapter_accepts_fixture_as_real_source':False})
        pr={'type':'LocalPractice','version':1,'id':identity('practice-'+p)[:32],'player_id':identity('player')[:32],'source':sr,'started_utc':'2026-10-11T00:00:00Z','last_observed_utc':'2026-10-11T00:00:01Z','first_tick':'0','last_tick':'120','observed_ticks':'120','tick_rate_hz':120,'status':'manually_ended','end_reason':'user_end','revision':'2','creation_sequence':str(3 if piston else 2),'commit_sequence':str(5 if piston else 4),'archive':None}
        ident=put(p+'-practice',pr,'complete hypothetical durable record, not a database or flight receipt')
        case(ident,'Practice',ident,{'new_domain_valid':True,'no_landed_scored_or_physics_resume':True})
        summary=deepcopy(pr);summary['archive']={'linked':False};selected.append(summary)

        # Full malformed values, not only mutation instructions or tuples.
        changes=[('root-extra',lambda x:x.update(extra=True),'Malformed exact Readback shape'),('current-canonical-null',lambda x:x.update(canonical=None),'Current source lacks canonical metadata'),('paused-int',lambda x:x.update(paused=1),'Readback flags must be bool'),('axes-bool',lambda x:x['held_axes'].update(roll=True),'Invalid or missing native-held axes'),('mismatched-source-position',lambda x:x['atmosphere']['position'].update(ellipsoid_height_m=2.),'Source pair/session/tick/position mismatch'),('wrong-start-profile',lambda x:x.update(named_start=STARTS[0 if piston else 1]),'Unknown named start'),('source-nonhex',lambda x:x.update(native_source_fingerprint='not-a-hash'),'Invalid source fingerprint or prepared world identity'),('incomplete-pair',lambda x:x.update(aircraft=None),'Incomplete source pair'),('canonical-extra',lambda x:x['canonical'].update(extra=False),'Malformed canonical metadata')]
        for suffix,mutate,error in changes:
            bad=deepcopy(rbs[0]);mutate(bad);ident=put(p+'-bad-'+suffix,bad,'complete malformed hypothetical Readback')
            rejection=put(ident+'-readings',unavailable(error),'complete expected all-channel invalid ReadingSet')
            case(ident,'Readback',ident,{'new_domain':'invalid','error':error,'expected_readings':rejection,'navigation_available':False,'caller_unchanged':True})
        mismatch_archive=deepcopy(ar); outer=json.loads(mismatch_archive['utf8_text']);outer['payload_sha256']='0'*64
        mismatch_archive['utf8_text']=canonical(outer);mismatch_archive['bytes']=len(mismatch_archive['utf8_text'].encode('utf-8'));mismatch_archive['sha256']=sha(mismatch_archive['utf8_text'].encode('utf-8'));mismatch_archive['payload_sha256']=outer['payload_sha256']
        ident=put(p+'-bad-archive-checksum',mismatch_archive,'complete outer archive with false payload checksum; decoded_recording is only intended source, not a successful decode')
        case(ident,'Archive',ident,{'decode':False,'failure_value':None,'failure_payload_sha256':None,'error_nonempty':True})
        bad=deepcopy(manual);bad['contract_version']=float(bad['contract_version']);ident=put(p+'-bad-record-version-float',bad,'FLOAT at strict Recording INT position')
        case(ident,'Recording',ident,{'valid':False,'caller_unchanged':True})
        bad=deepcopy(manual);bad['metadata']['extra']=False;ident=put(p+'-bad-record-extra',bad,'unknown closed metadata field')
        case(ident,'Recording',ident,{'valid':False,'caller_unchanged':True})
        ident=put(p+'-bad-archive-extra',archive(bad),'rehashed exact malformed archive; failure is not hash-only')
        case(ident,'Archive',ident,{'decode':False,'failure_value':None,'failure_payload_sha256':None,'error_nonempty':True})
        badsrc=deepcopy(sr);badsrc['wind_profile']='from-west';ident=put(p+'-bad-source-wind',badsrc,'new apron pairs are calm-only')
        case(ident,'PracticeSource',ident,{'valid':False,'caller_unchanged':True})
        badsrc=deepcopy(sr);badsrc['model_identity']=deepcopy(MODELS[0 if piston else 1]);ident=put(p+'-bad-source-model',badsrc,'complete crossed profile/source tuple')
        case(ident,'PracticeSource',ident,{'valid':False})
        another=readback(pose,piston,'120','hypothetical-other-'+p);ident=put(p+'-foreign-session',another,'complete distinct-session hypothetical current publication')
        changed=deepcopy(a);changed.update(state='sealed',seal_reason='identity_changed',error='Recorded session identity changed')
        put(p+'-record-foreign-result',changed,'complete expected sealed record; foreign truth is not silently rebound')
        lifecycles.append({'id':p+'-foreign-observation','actions':[{'operation':'Recorder.begin','input':p+'-paused-0'},{'operation':'Recorder.observe','input':p+'-paused-60'},{'operation':'Recorder.observe','input':p+'-paused-120'},{'operation':'Recorder.observe','input':ident}],'expected_recording':p+'-record-foreign-result','expected':{'ok':False,'error':'Recorded session identity changed','metadata_and_samples_retained':True,'foreign_tick_never_adopted':True}})
        lifecycles.append({'id':p+'-same-session-begin-refused','initial_recording':p+'-record-recording','operation':{'name':'Recorder.begin','input':p+'-paused-120','replace_confirmed':True},'expected':{'ok':False,'error':'Replacement requires a confirmed different session','recording_exactly_unchanged':p+'-record-recording'}})
        lifecycles.append({'id':p+'-failed-replacement','actions':[{'operation':'ordinary old close/join','input':p+'-closed-120'},{'operation':'Recorder.observe retained closed truth','input':p+'-closed-120'},{'operation':'new initialization fails before adoption','input':None}],'expected_recording':p+'-record-closed','expected':{'old_sample_metadata_prefix_exact':p+'-record-recording','new_recording_begin_calls':0,'new_practice_begin_calls':0,'new_navigation_fresh_session_calls':0,'current_navigation_available':False,'actual_join_must_be_observed_by_later_runtime_test':True}})
        lifecycles.append({'id':p+'-foreign-owner','initial_recording':p+'-record-recording','input':p+'-paused-120','operation':'Recorder.observe from a real foreign Thread in later runtime test','expected':{'result':{'ok':False,'error':'Observed flight review belongs to its main-thread owner','appended':False,'status':None},'recording_exactly_unchanged':p+'-record-recording','actual_thread_execution':False}})
        lifecycles.append({'id':p+'-navigation-foreign-session','initial_readback':p+'-paused-120','input':p+'-foreign-session','operation':'next with complete qualified foreign Readback and synthetic-context expected pin only','expected':{'ok':False,'error':'session_mismatch','route_and_aids_exactly_unchanged':True,'actual_native_or_page_execution':False}})
        lifecycles.append({'id':p+'-same-session-page-reopen','initial_readback':p+'-paused-120','initial_recording':p+'-record-recording','actions':['open Taxi with opening-token A','dismiss Taxi','reopen same session with opening-token B','invoke stale widget/session/token A callback','present current session for token B'],'expected':{'stale_route_next_stop_aid_callbacks_inert':True,'recording_exactly_unchanged':p+'-record-recording','authority_and_mapper_exactly_unchanged':True,'default_back_focus':True,'real_page_or_native_execution':False}})
        lifecycles.append({'id':p+'-owned-copies','input':p+'-record-manual','actions':['copy supplied Readback/Recording','mutate returned metadata.session_id','mutate returned samples[0].held_axes.throttle','read again'],'expected':{'fresh_copy_exact':p+'-record-manual','caller_input_exactly_unchanged':True,'no_shared_mutable_children':True}})
        mismatch=deepcopy(rbs[0]);mismatch['native_source_fingerprint']=identity('other-source');ident=put(p+'-different-hypothetical-source',mismatch,'complete different synthetic source digest, not real current native identity')
        case(ident,'current-source qualification',ident,{'synthetic_expected_source_sha256':identity('source'),'ok':False,'error':'source_unqualified','before_effects':True,'navigation_available':False})

    # Missing source channel stays unavailable, never guessed or wrongly null in
    # AircraftSnapshot systems (which require a scalar even when unavailable).
    rb=readback(pose,True);rb['aircraft']['systems']=[x for x in rb['aircraft']['systems'] if x['id']!='propeller.angular_speed']
    put('piston-shaft-absent',rb,'complete hypothetical source with absent optional instrument channel')
    status=readings(rb,True);put('piston-shaft-unavailable-status',status,'complete EngineStatus with null unavailable shaft channel')
    rec=recording([rb],'manual');put('piston-shaft-unavailable-record',rec,'complete Recording2 unavailable channel survives review')
    put('piston-shaft-unavailable-archive',archive(rec),'complete archive2 with valid null unavailable engine channel')
    case('piston-shaft-unavailable','EngineStatus','piston-shaft-absent',{'flight_readings_valid':True,'engine_status':'piston-shaft-unavailable-status','shaft_value':None,'shaft_valid':False,'recording_valid':True,'archive_roundtrip':True,'actual_native_cold_channels_qualified':False})
    bad=deepcopy(rb);bad['aircraft']['systems'].append({'id':'propeller.angular_speed','quantity':'radps','value':None,'validity':'unavailable'});put('piston-source-system-null',bad,'null in wire scalar system position is malformed')
    case('piston-source-system-null','Readback','piston-source-system-null',{'state':'invalid','error':'Malformed v1 source shape or semantics','do_not_confuse_with_channel_null':True})
    bad=deepcopy(rec);bad['samples'][0]['engine_status']['readings']['engine.running']['value']=0.;put('piston-engine-bool-as-float',bad,'engine bool cannot be FLOAT0')
    case('piston-engine-bool-as-float','Recording','piston-engine-bool-as-float',{'valid':False})

    empty=deepcopy(readback(pose));empty.update(host_mode='closed',historical=True,native_live=False,paused=False)
    for key in ['session_id','tick','aircraft','atmosphere','held_axes','native_outcome','named_start','model_identity','native_source_fingerprint','prepared_world_sha256','world_anchor','canonical']:empty[key]=None
    put('empty-closed-readings',unavailable('No verified source publication','empty'),'complete expected all-channel empty ReadingSet')
    put('empty-closed',empty,'complete empty historical Readback')
    case('empty-closed','Readback','empty-closed',{'readings_state':'empty','expected_readings':'empty-closed-readings','navigation_available':False,'all_guidance_nullable':True})

    player={'type':'LocalPlayer','version':1,'id':identity('player')[:32],'name':'Original synthetic taxi fixture','created_utc':'2026-10-11T00:00:00Z','updated_utc':'2026-10-11T00:00:00Z','revision':'1'}
    prefs={'type':'LocalPlayerPreferences','version':1,'player_id':player['id'],'revision':'1','legacy_input':None,'piston_input':None,'audio':{'enabled':True,'engine_gain':.5,'airflow_gain':.5,'show_panel_captions':False}}
    put('player',player,'complete hypothetical local player, no product store')
    put('preferences',prefs,'complete default-slot preferences; original rich preset references remain separate')
    payload={'player':player,'preferences':prefs,'practice':list(reversed(selected))}
    text=canonical(typed(payload));envelope={'format':'LocalPlayerSummary','version':1,'payload_json':text,'payload_sha256':sha(text.encode('utf-8'))};raw=canonical(envelope)
    put('selected-player-export',{'snapshot':payload,'envelope':envelope,'utf8_text':raw,'bytes':len(raw.encode('utf-8')),'sha256':sha(raw.encode('utf-8'))},'complete canonical hypothetical selected-player export, not filesystem receipt')
    case('selected-player-export','Export','selected-player-export',{'closed_valid_new_domain':True,'all_selected_rows':2,'practice_order_creation_sequence':['3','2'],'all_source_types_bits_preserved':True,'external_paths_present':False,'native_authority_from_import_or_export':False,'filesystem_or_SQLite_witness':False})
    bad=deepcopy(payload);bad['practice']=list(reversed(bad['practice']));put('bad-export-order',bad,'complete valid-shape snapshot in wrong immutable creation order')
    case('bad-export-order','Export','bad-export-order',{'canonical_snapshot_order_valid':False,'no_silent_resort_or_truncate':True})
    bad=deepcopy(payload);bad['practice'][0]['source']['extra']=True;put('bad-export-source-extra',bad,'complete snapshot with unknown Source field')
    case('bad-export-source-extra','Export','bad-export-source-extra',{'closed_valid':False})
    bad=deepcopy(payload);bad['preferences']['audio']['engine_gain']=1;put('bad-export-audio-int',bad,'Audio gain actualINT is not normalized toFLOAT')
    case('bad-export-audio-int','Export','bad-export-audio-int',{'closed_valid':False})
    # Test-only runtime type recipe over a complete value, no generic consumer
    # tag admission. Caller materializes StringName then uses unchanged shape.
    lifecycles.append({'id':'readback-stringname-root-key','base_fixture':'legacy-paused-0','test_only_type_substitution':{'path':['host_mode'],'key_type':'StringName','text':'host_mode'},'expected':{'state':'invalid','error':'Malformed exact Readback shape','caller_unchanged':True}})
    lifecycles.append({'id':'actual-generated-current-pin-boundary','input':'legacy-paused-0','required_future_actual_harness_context':'read actual generated native resource without modifying/injecting it; require its real fingerprint differ from every synthetic descriptor','expected':{'current_source_qualification':False,'no_scene_recording_practice_or_navigation_adoption':True,'actual_source_still_requires_actual_qualified_observation':True}})
    return {'schema':'HypotheticalApronCompatibilityReferences/v1','status':'PROPOSED preconsumer source/math only; no native or consumer output','license':'Original MIT','transport':{'floats':'Each {$binary64_le:16lowerhex} denotes an actual FLOAT at the same typed-value position; never send these test transport tags directly to Readback validators. BOOL,INT,String,null,Array,Dictionary preserve exact branches. All keys actual String after test materialization.','StringName_negative':'Only explicit test_only_type_substitution is materialized as StringName; never a public DTO extension.','archive':'utf8_text is complete exact no-LF outer JSON, payload_json is exact inner String with path-bound binary64 tags, sha256 hashes exact UTF8 bytes. Snapshot tagged values are test transport, not storage envelope expansion.'},'hypothetical_identities':[{'descriptor':descriptor(role),'canonical_utf8':canonical(descriptor(role)),'sha256':identity(role)} for role in ['source','control','other-source','player','practice-legacy','practice-piston']],'fixtures':fixtures,'cases':cases,'lifecycle_recipes':lifecycles,'criteria':{'schema_types_ids_flags_keys_hashes_bits':'exact','sampling':'exact canonical Strings0/60/120, three samples, no late/skipped/tail; arbitrary authored hypothetical publications, not an observed trajectory','canonical_pose':'Independent frozen mathematical pose; copied anchor[108,1.05,18] intentionally within predeclared1e-7m requalification, never rewritten to derived coordinates','canonical_geometry_abs_m':'1e-7 existing ADR011 qualification, not retuned','availability':'unavailable is null with explicit false/error; never a guessed value','runtime_evidence':'NONE; lifecycle/copy/source-gate recipes are future assertions, not executions','current_native_identity':'Synthetic descriptor hashes can satisfy labeled pure-test expected pins only; never generated production identity, actual native fingerprint, Scene/native adoption or fixture-derived self qualification.'}}

def build(pose):
    packet = build_original(pose)
    fixtures, cases = packet['fixtures'], packet['cases']
    maximum = 18446744073709551615

    def put(name, value, role, boundary, expected):
        assert name not in fixtures
        # Already-typed original values preserve every existing FLOAT bit/tag.
        fixtures[name] = {'role': role, 'typed_value': deepcopy(value),
                          'exact_typed_sha256': sha(canonical(value).encode('utf-8'))}
        cases.append({'id': name, 'boundary': boundary, 'fixture': name,
                      'expected': expected})

    def export(value):
        summary = deepcopy(value)
        summary['archive'] = {'linked': False}
        payload = {'player': deepcopy(fixtures['player']['typed_value']),
                   'preferences': deepcopy(fixtures['preferences']['typed_value']),
                   'practice': [summary]}
        text = canonical(payload)
        envelope = {'format': 'LocalPlayerSummary', 'version': 1,
                    'payload_json': text, 'payload_sha256': sha(text.encode('utf-8'))}
        raw = canonical(envelope)
        return {'snapshot': payload, 'envelope': envelope, 'utf8_text': raw,
                'bytes': len(raw.encode('utf-8')), 'sha256': sha(raw.encode('utf-8'))}

    for prefix in ['legacy', 'piston']:
        original = fixtures[prefix + '-practice']['typed_value']
        active = deepcopy(original)
        active.update(first_tick=str(maximum), last_tick=str(maximum),
                      observed_ticks='0', last_observed_utc=active['started_utc'],
                      status='active', end_reason=None, revision='1',
                      creation_sequence=str(maximum), commit_sequence=str(maximum))
        ended = deepcopy(original)
        ended.update(first_tick=str(maximum - 120), last_tick=str(maximum),
                     observed_ticks='120', creation_sequence=str(maximum - 1),
                     commit_sequence=str(maximum), revision='2')
        for suffix, value in [('max-u64-active', active), ('max-u64-ended', ended)]:
            name = prefix + '-practice-' + suffix
            put(name, value, 'complete hypothetical U64 boundary record; no native or SQLite observation',
                'Practice', {'new_domain_valid': True, 'all_unsigned_fields_exact_strings': True,
                             'observed_ticks_exact': value['observed_ticks'],
                             'creation_not_after_commit': True,
                             'otherwise_admitted_changing_transaction_at_max_meta_sequence': 'counter_exhausted',
                             'native_or_database_witness': False})
            put(name + '-export', export(value),
                'complete exact hypothetical one-row U64 boundary export; no filesystem receipt',
                'Export', {'closed_valid_new_domain': True, 'all_selected_rows': 1,
                           'practice_order_creation_sequence': [value['creation_sequence']],
                           'all_source_types_bits_preserved': True,
                           'external_paths_present': False, 'filesystem_or_SQLite_witness': False})
        for suffix, invalid in [('leading-zero', '00'), ('actual-int', 0),
                                ('overflow', str(maximum + 1))]:
            bad = deepcopy(ended)
            bad['creation_sequence'] = invalid
            name = prefix + '-practice-u64-bad-' + suffix
            put(name, bad, 'complete malformed canonical-U64 record; every other value unchanged',
                'Practice', {'new_domain_valid': False, 'caller_unchanged': True,
                             'invalid_path': ['creation_sequence'],
                             'rejection': 'canonical unsigned decimal String required'})
            put(name + '-export', export(bad),
                'complete rehashed malformed export; semantic rejection despite matching checksums',
                'Export', {'closed_valid_new_domain': False, 'caller_unchanged': True,
                           'invalid_path': ['practice', 0, 'creation_sequence'],
                           'checksums_valid': True, 'no_silent_coercion_or_repair': True})
    return packet


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true',required=True);ap.add_argument('--pose-reference',type=Path,default=Path(__file__).resolve().parents[1]/'start-reference/expected-v1.json');args=ap.parse_args()
    raw=args.pose_reference.read_bytes();assert sha(raw)==POSE_SHA,'Independent immutable pose source differs'
    actual=pretty(build(json.loads(raw)));expected=Path(__file__).with_name('expected-v1.json').read_bytes()
    assert actual==expected,'Frozen complete hypothetical references differ; --check never writes'
    packet=json.loads(actual)
    print('PASS complete hypothetical taxi compatibility source: '+str(len(packet['fixtures']))+' typed values, '+str(len(packet['cases']))+' closed boundary recipes, '+str(len(packet['lifecycle_recipes']))+' unexecuted lifecycle/copy rules; no consumer/native result')

if __name__=='__main__':main()
