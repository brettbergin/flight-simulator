extends RefCounted
# Original MIT. Frozen analytic references; no native executive or scene API.
const Readings=preload("res://cockpit/instruments/native_readings.gd")
const REFERENCE_SHA="413eb124254432f8b39d7079b773d14e276415aa54749de3a1d85e527bf70aae"
const UNITS={"tas":"m/s","ground_speed":"m/s","pitch":"rad","bank":"rad","heading_true":"rad","ellipsoid_height":"m","vertical_speed":"m/s","body_yaw_rate":"rad/s","fuel_total":"kg"}
const BUDGET={"scalar_abs":2e-12,"angle_abs_rad":2e-12,"display_abs":2e-9,"relative":4e-15,"singularity_dimensionless":1e-6}
var checks: int=0
var failures: Array[String]=[]
var covered: Dictionary={}
static func run() -> Dictionary:
 return new()._run()
func _check(ok: bool,label: String) -> void:
 checks+=1
 if not ok: failures.append(label)
func _closed(value: Variant,keys: Array) -> bool:
 if not value is Dictionary or value.size()!=keys.size(): return false
 for key in value:
  if typeof(key)!=TYPE_STRING or key not in keys: return false
 return true
func _near(actual: Variant,expected: float,absolute: float,label: String) -> void:
 _check(typeof(actual)==TYPE_FLOAT and is_finite(actual) and absf(actual-expected)<=maxf(absolute,BUDGET.relative*absf(expected)),label)
func _restore_fixture(value: Dictionary) -> Dictionary:
 var copied: Dictionary=value.duplicate(true)
 var counter: Variant=copied.get("debt_quanta")
 # Only this declared integer counter crosses JSON's floating-number parser.
 var exact: bool=typeof(counter) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(counter)) and float(counter)==0.0
 _check(exact,"fixture_declared_zero_integer_debt")
 if exact: copied.debt_quanta=int(counter)
 return copied
func _shape(value: Variant,label: String) -> bool:
 var good: bool=_closed(value,["session_id","tick","state","native_truth","readings","error"])
 _check(good,label+"_closed_set")
 if not good: return false
 good=typeof(value.state)==TYPE_STRING and value.state in ["empty","live","paused","historical","invalid"] and typeof(value.native_truth)==TYPE_BOOL and value.native_truth and typeof(value.error)==TYPE_STRING
 _check(good,label+"_set_types")
 var channels: bool=_closed(value.readings,UNITS.keys())
 _check(channels,label+"_exact_nine_channels")
 if not channels: return false
 for id in UNITS:
  var channel: Variant=value.readings[id]
  var closed: bool=_closed(channel,["value","unit","valid","error"])
  _check(closed,label+"_"+id+"_closed_channel")
  if not closed: good=false; continue
  var typed: bool=typeof(channel.valid)==TYPE_BOOL and typeof(channel.unit)==TYPE_STRING and channel.unit==UNITS[id] and typeof(channel.error)==TYPE_STRING
  _check(typed,label+"_"+id+"_channel_types_units")
  if not typed: good=false; continue
  var available: bool=typeof(channel.value)==TYPE_FLOAT and is_finite(channel.value) and channel.error.is_empty() if channel.valid else channel.value==null and not channel.error.is_empty()
  _check(available,label+"_"+id+"_availability_value_reason")
  good=good and available
 return good
func _invalid(value: Variant,label: String,state: String="invalid") -> void:
 if not _shape(value,label): return
 _check(value.state==state and value.session_id==null and value.tick==null and not value.error.is_empty(),label+"_invalid_identity_reason")
 for id in UNITS: _check(not value.readings[id].valid and value.readings[id].value==null,label+"_"+id+"_not_stale")
func _case(row: Dictionary) -> void:
 var input: Dictionary=_restore_fixture(row.input)
 var untouched: Dictionary=input.duplicate(true)
 var result: Dictionary=Readings.from_readback(input)
 var id: String=row.id
 _check(not covered.has(id),id+"_unique_reference");covered[id]=true
 _check(input==untouched,id+"_input_unmodified")
 if not _shape(result,id): return
 _check(result.state==row.expected_state,id+"_expected_state")
 if row.expect_null_identity:
  _invalid(result,id+"_null",row.expected_state)
 else:
  _check(typeof(result.session_id)==TYPE_STRING and result.session_id==input.session_id and typeof(result.tick)==TYPE_STRING and result.tick==input.tick and result.error.is_empty(),id+"_exact_identity")
 for channel_id in UNITS:
  var expected: Variant=row.expected_values[channel_id]
  var channel: Dictionary=result.readings[channel_id]
  if expected==null:
   _check(not channel.valid and channel.value==null and not channel.error.is_empty(),id+"_"+channel_id+"_expected_unavailable")
  else:
   _check(channel.valid,id+"_"+channel_id+"_expected_valid")
   _near(channel.value,float(expected),BUDGET.angle_abs_rad if UNITS[channel_id]=="rad" else BUDGET.scalar_abs,id+"_"+channel_id+"_analytic_value")
 for display in ["tas_kt","height_ft","vsi_fpm"]:
  var expected: Variant=row.display_expected[display]
  if expected==null: continue
  var actual: Variant=null
  if display=="tas_kt" and result.readings.tas.valid: actual=result.readings.tas.value*3600.0/1852.0
  elif display=="height_ft" and result.readings.ellipsoid_height.valid: actual=result.readings.ellipsoid_height.value/0.3048
  elif display=="vsi_fpm" and result.readings.vertical_speed.valid: actual=result.readings.vertical_speed.value*60.0/0.3048
  _near(actual,float(expected),BUDGET.display_abs,id+"_"+display+"_frozen_conversion")
func _direct(recipe: Dictionary,baseline: Dictionary) -> void:
 var source: Variant=baseline.duplicate(true)
 var owned_node: Node3D=null
 match recipe.id:
  "nan-required-vector": source.aircraft.velocity_body_mps.x=NAN
  "infinite-system-value": source.aircraft.systems[0].value=INF
  "wrong-readback-object": owned_node=Node3D.new();source=owned_node
  "malformed-fingerprint": source.native_source_fingerprint="g".repeat(64)
  "float-debt-counter": source.debt_quanta=0.0;_check(typeof(source.debt_quanta)==TYPE_FLOAT,"direct_float_counter_reintroduced_after_restoration")
  _: _check(false,"unknown_frozen_direct_recipe");return
 _check(not covered.has(recipe.id),recipe.id+"_unique_reference");covered[recipe.id]=true
 var result: Dictionary=Readings.from_readback(source)
 if owned_node!=null: owned_node.free()
 _invalid(result,recipe.id)
func _structural(baseline: Dictionary) -> int:
 var names: Array=["StringName_axes_kind","StringName_model_id","integer_anchor","negative_mass","unknown_system_validity","nonfinite_pressure","missing_weather_source","wrong_clock","missing_aircraft_pair","unknown_held_axis","nonfinite_canonical","wrong_rotation_size","nonrigid_rotation","mismatched_canonical_point","nonboolean_native_live","negative_debt","invalid_time_scale","wrong_session_type","live_native_absent"]
 for name in names:
  var value: Dictionary=baseline.duplicate(true)
  match name:
   "StringName_axes_kind": value.held_axes.kind=StringName("axes")
   "StringName_model_id": value.model_identity.id=StringName("original-interactive-prototype")
   "integer_anchor": value.world_anchor.ellipsoid_height_m=0
   "negative_mass": value.aircraft.mass_kg=-1.0
   "unknown_system_validity": value.aircraft.systems[0].validity="not_a_validity"
   "nonfinite_pressure": value.atmosphere.pressure_pa=NAN
   "missing_weather_source": value.atmosphere.erase("model_id")
   "wrong_clock": value.aircraft.clock.tick_rate_hz=60.0
   "missing_aircraft_pair": value.aircraft=null
   "unknown_held_axis": value.held_axes.extra=0.0
   "nonfinite_canonical": value.canonical.anchor_eus_position_m[0]=NAN
   "wrong_rotation_size": value.canonical.body_to_anchor_eus.pop_back()
   "nonrigid_rotation": value.canonical.body_to_anchor_eus[0]=5.0
   "mismatched_canonical_point": value.canonical.ecef_position_m[0]+=0.01
   "nonboolean_native_live": value.native_live=1
   "negative_debt": value.debt_quanta=-1
   "invalid_time_scale": value.time_scale=0.75
   "wrong_session_type": value.session_id=StringName("synthetic-reading-reference")
   "live_native_absent": value.native_live=false
  _invalid(Readings.from_readback(value),"structural_"+name)
 for value in [null,[],true,0,"readback"]: _invalid(Readings.from_readback(value),"wrong_top_variant_"+str(typeof(value)))
 return names.size()+5
func _copies_and_cadence(baseline: Dictionary) -> void:
 var original: Dictionary=Readings.from_readback(baseline)
 var input: Dictionary=baseline.duplicate(true)
 var owned: Dictionary=Readings.from_readback(input)
 input.aircraft.velocity_body_mps.x+=7.0;input.atmosphere.wind_toward_ned_mps.y-=3.0
 _check(owned==original,"input_nested_mutation_cannot_change_prior_owned_readings")
 owned.readings.tas.value=-999.0
 _check(Readings.from_readback(baseline)==original,"output_mutation_cannot_change_next_publication")
 for cadence in [30,60,120,240]:
  # Repeated identical copied readback; no clock, render-frame or native step call.
  for i in range(cadence/30): _check(Readings.from_readback(baseline)==original,"same_input_cadence_"+str(cadence)+"_"+str(i))
 var valid: Dictionary=Readings.from_readback(baseline)
 var broken: Dictionary=baseline.duplicate(true);broken.extra=true
 _invalid(Readings.from_readback(broken),"invalid_after_valid_never_retains_channels")
 _check(Readings.from_readback(baseline)==valid,"invalid_call_cannot_poison_next_valid_publication")
func _run() -> Dictionary:
 var path: String="res://instrument_tests/reference.json"
 _check(FileAccess.get_sha256(path)==REFERENCE_SHA,"byte_identical_preconsumer_reference")
 var packet: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
 if not packet is Dictionary: _check(false,"reference_json_dictionary");return _report(0)
 _check(packet.get("schema_version")==1 and packet.get("budgets")==BUDGET and packet.get("units")==UNITS,"frozen_units_and_budgets")
 _check(packet.cases.size()==30 and packet.non_json_cases.size()==5,"frozen_30_json_5_direct")
 for row in packet.cases: _case(row)
 var baseline: Dictionary=_restore_fixture(packet.cases[0].input)
 for recipe in packet.non_json_cases: _direct(recipe,baseline)
 var mutants: int=_structural(baseline)
 _copies_and_cadence(baseline)
 _check(covered.size()==35,"all_35_frozen_references_exercised")
 return _report(mutants)
func _report(mutants: int) -> Dictionary:
 return {"schema_version":1,"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"reference_cases":covered.size(),"reference_sha256":REFERENCE_SHA,"structural_mutants":mutants,"budgets":BUDGET.duplicate(),"scope":"Pure actual reading leaf over frozen analytic/synthetic copied inputs. No native solver, sensed instrument, drawing, device, pilot or phase qualification."}
