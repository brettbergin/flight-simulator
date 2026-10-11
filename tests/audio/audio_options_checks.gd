extends RefCounted
# Original MIT. ADR020 options types, atomic rejection and owned results.
const Options = preload("res://audio/audio_options.gd")
var checks: int=0
var failures: Array[String]=[]

static func run() -> Dictionary:
	return new()._run()

func _check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label)

func _run() -> Dictionary:
	var baseline: Dictionary={"enabled":true,"engine_gain":1.0,"airflow_gain":1.0,"show_panel_captions":true}
	var before: Dictionary=baseline.duplicate(true)
	var accepted: Dictionary=Options.validate(baseline)
	_check(accepted.keys().size()==3 and accepted.has("ok") and accepted.has("error") and accepted.has("value") and accepted.ok==true and accepted.error=="" and accepted.value==before,"exact_success_and_defaults")
	_check(baseline==before and Options.validate(baseline)==accepted,"input_preserved_and_repeat_idempotent")
	accepted.value.engine_gain=0.5
	_check(baseline==before,"result_does_not_alias_input")
	baseline.airflow_gain=0.25
	_check(accepted.value.airflow_gain==1.0,"later_input_does_not_alias_result")
	for gain in [0.0,0.125,1.0]:
		var options: Dictionary=before.duplicate(true)
		options.engine_gain=gain; options.airflow_gain=gain
		options.enabled=false; options.show_panel_captions=false
		_check(Options.validate(options).value==options,"gain_endpoints_and_independent_false_"+str(gain))
	for invalid in [null,[],true,1,1.0,"options"]:
		var result: Dictionary=Options.validate(invalid)
		_check(result.keys().size()==3 and result.ok==false and result.value==null and typeof(result.error)==TYPE_STRING and not result.error.is_empty(),"reject_container_"+str(invalid))
	for key in before:
		var missing: Dictionary=before.duplicate(true); missing.erase(key)
		_check(not Options.validate(missing).ok,"missing_"+key)
		var invalids: Array=[null,0,1,"true"] if typeof(before[key])==TYPE_BOOL else [null,true,false,0,1,"0.5",NAN,INF,-INF,-0.001,1.001]
		for invalid in invalids:
			var options: Dictionary=before.duplicate(true); options[key]=invalid
			var original_bytes: PackedByteArray=var_to_bytes(options)
			var result: Dictionary=Options.validate(options)
			_check(not result.ok and result.value==null and not result.error.is_empty() and var_to_bytes(options)==original_bytes,"strict_type_domain_owned_rejection_"+key+"_"+str(invalid))
	var extra: Dictionary=before.duplicate(true); extra.extra=true
	_check(not Options.validate(extra).ok,"extra_key")
	var alias: Dictionary=before.duplicate(true); alias.erase("enabled"); alias[StringName("enabled")]=true
	_check(not Options.validate(alias).ok,"stringname_key_rejected")
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate()}
