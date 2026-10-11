extends RefCounted
## Original MIT. Independent literal ADR018 mappings; ADR022 review-availability revision2.
const FirstFlightPanel = preload("res://ui/first_flight/briefing_panel.gd")
const SHA = "d75704a7aa6b50724561202bf817e1b74a0d7693ec2043347300cba8a29492c4"
const OLD_SHA = "461ded9adf22b5265c6b487c23590efe30acb929f3c056356742a93206d400df"
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
	_check(checked.value.get("revision")==2,"exact_revision2_literal")
	var cold: Dictionary=FirstFlightPanel.choice_for("cold-familiarization")
	_check(cold.required_truth==["Original cold piston","Idealized starter supply","No aircraft-specific checklist","Recorded flight and engine review available"],"cold_review_available_fact_and_original_warnings")
	_check(not cold.required_truth.has("Recorded review unavailable"),"stale_cold_unavailable_fact_absent")
	# Reverse exactly the two authorized content edits: the complete old bytes
	# must match their pre-consumer pin, including all other choices and steps.
	var historical_bytes: PackedByteArray=bytes.get_string_from_utf8().replace('"revision": 2','"revision": 1').replace("Recorded flight and engine review available","Recorded review unavailable").to_utf8_buffer()
	hash_context=HashingContext.new(); hash_context.start(HashingContext.HASH_SHA256); hash_context.update(historical_bytes)
	_check(hash_context.finish().hex_encode()==OLD_SHA,"only_revision_and_cold_caption_changed_from_frozen_v1")
	var historical: Dictionary=FirstFlightPanel.validate_fixture_bytes(historical_bytes)
	_check(not historical.ok and not historical.error.is_empty() and historical.value.is_empty(),"historical_revision1_exact_bytes_rejected")
	_check(checked.value.choices.size()==3 and checked.value.steps.size()==4,"closed_literal_roster")
	for expected in EXPECTED:
		var choice: Dictionary = FirstFlightPanel.choice_for(expected[0])
		_check(choice.choice_id==expected[0] and choice.model_identity==expected[1] and choice.named_start==expected[2] and choice.wind=="calm" and choice.circuit_available==expected[3],"mapping_"+expected[0])
		choice.model_identity.id="changed"; choice.required_truth.clear()
		_check(FirstFlightPanel.choice_for(expected[0]).model_identity==expected[1] and not FirstFlightPanel.choice_for(expected[0]).required_truth.is_empty(),"owned_"+expected[0])
	for invalid in ["","READY-FLIGHT","ready-flight ","piston-cold-ground","unknown"]:
		_check(FirstFlightPanel.choice_for(invalid).is_empty(),"unknown_choice_"+invalid)
	for changed in [PackedByteArray(),bytes+PackedByteArray([32]),bytes.get_string_from_utf8().replace('"revision": 2','"revision": 1').to_utf8_buffer(),bytes.get_string_from_utf8().replace('"revision": 2','"revision": 3').to_utf8_buffer(),bytes.get_string_from_utf8().replace('"revision": 2','"revision": "2"').to_utf8_buffer(),PackedByteArray([123]),bytes.get_string_from_utf8().replace('0.1.0-prototype','0.2.0').to_utf8_buffer()]:
		var rejected: Dictionary = FirstFlightPanel.validate_fixture_bytes(changed)
		_check(not rejected.ok and not rejected.error.is_empty() and rejected.value.is_empty(),"drift_rejected")
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures,"scope":"Frozen revision2 briefing caption, unchanged original mappings/warnings and strict historical/malformed content rejection; no native or aircraft qualification"}
