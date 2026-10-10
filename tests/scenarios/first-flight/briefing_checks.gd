extends RefCounted
## Original MIT. Independent literal ADR018 launch oracle; frozen before observations.
const FirstFlightPanel = preload("res://ui/first_flight/briefing_panel.gd")
const SHA = "461ded9adf22b5265c6b487c23590efe30acb929f3c056356742a93206d400df"
const EXPECTED = [
	["cold-familiarization",{"id":"original-piston-prop-v1","version":"0.1.0-prototype","backend_model":"original-piston-prop"},"piston-cold-ground",false],
	["ready-flight",{"id":"original-interactive-prototype","version":"0.1.0-prototype","backend_model":"original-interactive"},"ground-ready",true],
	["airborne-orientation",{"id":"original-interactive-prototype","version":"0.1.0-prototype","backend_model":"original-interactive"},"airborne-prepared",false]]
var _checks: int = 0
var _failures: Array[String] = []
var _host: Node
func _check(ok: bool, label: String) -> void:
	_checks+=1
	if not ok: _failures.append(label)
	if _host.has_method("check"): _host.call("check",ok,"first_flight_fixture_"+label)
func run(host: Node, _readback: Dictionary = {}) -> Dictionary:
	_host=host; _checks=0; _failures=[]
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://content/scenarios/first-flight/briefing.json")
	var hash_context: HashingContext = HashingContext.new(); hash_context.start(HashingContext.HASH_SHA256); hash_context.update(bytes)
	_check(hash_context.finish().hex_encode()==SHA,"original_literal_bytes")
	var checked: Dictionary = FirstFlightPanel.validate_fixture_bytes(bytes)
	_check(checked.ok,"original_accepted")
	_check(checked.value.choices.size()==3 and checked.value.steps.size()==4,"closed_literal_roster")
	for expected in EXPECTED:
		var choice: Dictionary = FirstFlightPanel.choice_for(expected[0])
		_check(choice.choice_id==expected[0] and choice.model_identity==expected[1] and choice.named_start==expected[2] and choice.wind=="calm" and choice.circuit_available==expected[3],"mapping_"+expected[0])
		choice.model_identity.id="changed"; choice.required_truth.clear()
		_check(FirstFlightPanel.choice_for(expected[0]).model_identity==expected[1] and not FirstFlightPanel.choice_for(expected[0]).required_truth.is_empty(),"owned_"+expected[0])
	for invalid in ["","READY-FLIGHT","ready-flight ","piston-cold-ground","unknown"]:
		_check(FirstFlightPanel.choice_for(invalid).is_empty(),"unknown_choice_"+invalid)
	for changed in [PackedByteArray(),bytes+PackedByteArray([32]),bytes.get_string_from_utf8().replace('"revision": 1','"revision": 2').to_utf8_buffer(),bytes.get_string_from_utf8().replace('0.1.0-prototype','0.2.0').to_utf8_buffer()]:
		var rejected: Dictionary = FirstFlightPanel.validate_fixture_bytes(changed)
		_check(not rejected.ok and not rejected.error.is_empty() and rejected.value.is_empty(),"drift_rejected")
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures}
