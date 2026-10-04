extends RefCounted
const FlightPanel=preload("res://interactive/flight_panel.gd")
const UNITS={"tas":"m/s","ground_speed":"m/s","pitch":"rad","bank":"rad","heading_true":"rad","ellipsoid_height":"m","vertical_speed":"m/s","body_yaw_rate":"rad/s","fuel_total":"kg"}
var checks: int=0
var failures: Array=[]
var _host: Node
func _check(ok: bool,label: String)->void:
 checks+=1
 if not ok: failures.append(label)
 _host.check(ok,label)
func _reading_fixture()->Dictionary:
 var values={"tas":13.0,"ground_speed":5.0,"pitch":0.25,"bank":-0.5,"heading_true":1.0,"ellipsoid_height":1000.0,"vertical_speed":-12.0,"body_yaw_rate":0.125,"fuel_total":100.0}
 var channels: Dictionary={}
 for id in UNITS: channels[id]={"value":values[id],"unit":UNITS[id],"valid":true,"error":""}
 return {"session_id":"adapter-fixture","tick":"18446744073709551615","state":"live","native_truth":true,"readings":channels,"error":""}
func _unavailable(value: Dictionary,label: String)->void:
 var result: Dictionary=FlightPanel.display_readings(value)
 _check(result=={"valid":false,"tas_valid":false,"channel_valid":{}},label+"_entire_display_unavailable")
func run(host: Node)->Dictionary:
 _host=host
 var input: Dictionary=_reading_fixture();var before: Dictionary=input.duplicate(true)
 var result: Dictionary=FlightPanel.display_readings(input)
 _check(input==before,"adapter_input_owned_unmodified")
 _check(result.valid and result.tas_valid and result.channel_valid.size()==9,"adapter_exact_nine_channels")
 _check(absf(result.tas_kt-13.0*3600.0/1852.0)<=2e-9 and absf(result.altitude_ft-1000.0/0.3048)<=2e-9 and absf(result.vsi_fpm+12.0*60.0/0.3048)<=2e-9,"adapter_declared_unit_conversions")
 _check(absf(result.pitch_deg-0.25*180.0/PI)<=2e-9,"adapter_scalar_degree_conversion")
 for name in ["outer_extra","outer_replaced","numeric_truth","StringName_truth_key","StringName_session","uppercase_session","duplicate_separator","empty_session","unicode_session","tick_leading_zero","tick_overflow","tick_float","tick_unicode","tick_negative","unknown_state","missing_channel","unknown_channel","StringName_channel_key","channel_unknown_key","numeric_valid","StringName_unit","integer_value","nonfinite_value","nan_value","valid_reason","unavailable_value","unavailable_no_reason","long_reason","nonempty_set_error"]:
  var value: Dictionary=_reading_fixture()
  match name:
   "outer_extra": value.extra=true
   "outer_replaced": value.erase("tick");value.extra=true
   "numeric_truth": value.native_truth=1
   "StringName_truth_key": value.erase("native_truth");value[StringName("native_truth")]=true
   "StringName_session": value.session_id=StringName("adapter-fixture")
   "uppercase_session": value.session_id="Adapter-fixture"
   "duplicate_separator": value.session_id="adapter..fixture"
   "empty_session": value.session_id=""
   "unicode_session": value.session_id="adapter\u00e9"
   "tick_leading_zero": value.tick="00"
   "tick_overflow": value.tick="18446744073709551616"
   "tick_float": value.tick=0.0
   "tick_unicode": value.tick="\u0661"
   "tick_negative": value.tick="-1"
   "unknown_state": value.state="live-paused"
   "missing_channel": value.readings.erase("bank")
   "unknown_channel": value.readings.extra={}
   "StringName_channel_key": var channel: Dictionary=value.readings.tas;value.readings.erase("tas");value.readings[StringName("tas")]=channel
   "channel_unknown_key": value.readings.tas.erase("error");value.readings.tas.extra=""
   "numeric_valid": value.readings.tas.valid=1
   "StringName_unit": value.readings.tas.unit=StringName("m/s")
   "integer_value": value.readings.tas.value=13
   "nonfinite_value": value.readings.tas.value=INF
   "nan_value": value.readings.tas.value=NAN
   "valid_reason": value.readings.tas.error="Not valid"
   "unavailable_value": value.readings.tas.valid=false;value.readings.tas.error="Missing"
   "unavailable_no_reason": value.readings.tas.valid=false;value.readings.tas.value=null
   "long_reason": value.readings.tas.valid=false;value.readings.tas.value=null;value.readings.tas.error="x".repeat(1025)
   "nonempty_set_error": value.error="Malformed current set"
  _unavailable(value,"direct_"+name)
 for state in ["invalid","empty"]:
  var value: Dictionary=_reading_fixture();value.state=state
  _unavailable(value,"direct_"+state+"_clears")
 var missing: Dictionary=_reading_fixture()
 missing.readings.ground_speed={"value":null,"unit":"m/s","valid":false,"error":"Unavailable GS"}
 var mapped: Dictionary=FlightPanel.display_readings(missing)
 _check(mapped.valid and not mapped.channel_valid.ground_speed and not mapped.has("ground_kt"),"adapter_missing_GS_not_zero")
 missing.readings.bank={"value":null,"unit":"rad","valid":false,"error":"Euler singularity"}
 mapped=FlightPanel.display_readings(missing)
 _check(mapped.valid and not mapped.channel_valid.bank and not mapped.has("roll_deg") and mapped.channel_valid.pitch,"adapter_singular_bank_not_zero_pitch_retained")
 var overflow: Dictionary=_reading_fixture();overflow.readings.body_yaw_rate.value=1e308
 mapped=FlightPanel.display_readings(overflow)
 _check(mapped.valid and not mapped.channel_valid.body_yaw_rate and not mapped.has("yaw_rate_deg_s"),"adapter_conversion_overflow_no_nonfinite_output")
 result.channel_valid.tas=false;result.tas_kt=-99.0
 _check(FlightPanel.display_readings(input).tas_valid and FlightPanel.display_readings(input).tas_kt>0.0,"adapter_output_owned_next_call_unchanged")
 var panel=FlightPanel.new();host.add_child(panel)
 var raw={"session_id":input.session_id,"tick":input.tick,"contacts":[{"on_ground":true},{"on_ground":false},{"on_ground":true}]}
 var held={"kind":"axes","roll":0.0,"pitch":0.0,"yaw":0.0,"throttle":0.42,"mixture":1.0,"left_brake":1.0,"right_brake":1.0,"trim":0.0}
 panel.set_native_readings(input,raw,held,{"paused":false})
 _check(panel._readings.valid and panel._readings.ground_contacts==2,"adapter_same_publication_actual_bool_contact_count")
 raw.contacts[0].on_ground=false;held.throttle=0.99
 _check(panel._readings.ground_contacts==2 and panel._held.throttle==0.42,"adapter_held_contact_nested_input_copies")
 raw.session_id="different-session";panel.set_native_readings(input,raw,held,{})
 _check(not panel._readings.valid,"adapter_source_session_mismatch_clears")
 raw.session_id=input.session_id;raw.tick="0";panel.set_native_readings(input,raw,held,{})
 _check(not panel._readings.valid,"adapter_source_tick_mismatch_clears")
 raw.tick=input.tick;input.state="historical";panel.set_native_readings(input,raw,held,{"paused":false,"retained":false})
 _check(panel._info.retained==true,"adapter_historical_forces_retained")
 input.state="paused";panel.set_native_readings(input,raw,held,{"paused":false})
 _check(panel._info.paused==true,"adapter_paused_forces_pause_label")
 input.state="live";panel.set_native_readings(input,raw,held,{"paused":true})
 _check(panel._info.paused==false,"adapter_live_cannot_inherit_contradictory_pause_label")
 input.readings.ground_speed.value=1e100;input.readings.fuel_total.value=1e100
 panel.set_native_readings(input,raw,held,{"retained":true})
 _check(not panel._info.retained,"adapter_current_cannot_inherit_retained_label")
 _check(panel._native_number(panel._readings.ground_kt,1).length()<16 and panel._native_number(panel._readings.fuel_kg,1).length()<16,"adapter_huge_GS_fuel_scientific_labels_bounded")
 for pixels in [10,19,28]:
  var label: String=panel._bounded_text(panel._native_number(1e100,1),92.0,pixels)
  _check(panel._font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x<=92.0,"adapter_huge_label_actual_font_width_"+str(pixels))
 panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
 panel.size=Vector2(960,540);panel.queue_redraw();await host.get_tree().process_frame;await host.get_tree().process_frame
 panel.set_cockpit_surface(true);panel.size=Vector2(1024,512);panel.queue_redraw();await host.get_tree().process_frame;await host.get_tree().process_frame
 panel.queue_free();await host.get_tree().process_frame
 return {"passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Actual adapter direct UI-value tests. Independent of scan validator; no native/controller/GPU/hardware/phase acceptance."}
