extends RefCounted
# Original MIT. Original saved native engineering Readback, not independent
# physics truth. Capture head bdfcee29efd3a714cf49582a2b0d661110f2f7f1,
# cockpit receipt SHA30613ef74ae6a20a82bf6fab0e06b51efd07b85fc910c7ff04640a1270737620,
# JSON pointer /sessions/0/before/readback, bytes [6214295,6220410).
# Original contacts are false; this makes no settled-ground claim.
const Geometry = preload("res://world/synthetic/circuit_geometry.gd")
const Readings = preload("res://cockpit/instruments/native_readings.gd")
const Cue = preload("res://world/wind/wind_cue.gd")
const CAPTURED_SHA: String = "58b1a7b0ec46161357c1268dbaeeaab27f84bbbd4de70def35571fd45ddb67f9"
const CAPTURED_READBACK: String = """{
          "host_mode": "paused",
          "error": "",
          "historical": false,
          "session_id": "interactive-24728-981779069600-2",
          "tick": "0",
          "aircraft": {
            "type": "AircraftSnapshot",
            "schema_version": 1.0,
            "tick": "0",
            "session_id": "interactive-24728-981779069600-2",
            "clock": {
              "tick_rate_hz": 120.0,
              "purpose": "runtime"
            },
            "elapsed_s": 0.0,
            "position": {
              "latitude_rad": 0.7999999999907527,
              "longitude_rad": -2.0,
              "ellipsoid_height_m": 1.049999999127587
            },
            "ecef_position_m": {
              "x": -1852421.6708183065,
              "y": -4047615.1943075066,
              "z": 4552615.219081322
            },
            "orientation_body_to_ned": {
              "w": 1.0,
              "x": 5.943362342692543e-17,
              "y": 1.3877787807814455e-17,
              "z": -1.0681326253130181e-16
            },
            "velocity_body_mps": {
              "x": 0.0,
              "y": 0.0,
              "z": 0.0
            },
            "angular_rate_body_radps": {
              "x": 0.0,
              "y": 0.0,
              "z": 0.0
            },
            "acceleration_body_mps2": {
              "x": 0.09089660152274984,
              "y": 1.2263705655295382e-15,
              "z": 9.80699848241511
            },
            "mass_kg": 1099.9999848347832,
            "center_of_gravity_body_m": {
              "x": 0.0,
              "y": 0.0,
              "z": 0.0
            },
            "configuration": {
              "flap_fraction": 0.0,
              "gear_fraction": 1.0,
              "trim_fraction": 0.0
            },
            "systems": [
              {
                "id": "fuel.total",
                "quantity": "kg",
                "value": 100.0,
                "validity": "valid"
              },
              {
                "id": "engine.throttle",
                "quantity": "fraction",
                "value": 0.0,
                "validity": "valid"
              }
            ],
            "contacts": [
              {
                "id": "gear.nose",
                "point_body_m": {
                  "x": 2.0000000030400003,
                  "y": 0.0,
                  "z": 1.00000000152
                },
                "force_body_n": {
                  "x": 0.0,
                  "y": 0.0,
                  "z": 0.0
                },
                "on_ground": false
              },
              {
                "id": "gear.left",
                "point_body_m": {
                  "x": -1.00000000152,
                  "y": -1.300000001976,
                  "z": 1.00000000152
                },
                "force_body_n": {
                  "x": 0.0,
                  "y": 0.0,
                  "z": 0.0
                },
                "on_ground": false
              },
              {
                "id": "gear.right",
                "point_body_m": {
                  "x": -1.00000000152,
                  "y": 1.300000001976,
                  "z": 1.00000000152
                },
                "force_body_n": {
                  "x": 0.0,
                  "y": 0.0,
                  "z": 0.0
                },
                "on_ground": false
              }
            ],
            "validity": "valid"
          },
          "atmosphere": {
            "type": "AtmosphereSample",
            "schema_version": 1.0,
            "tick": "0",
            "session_id": "interactive-24728-981779069600-2",
            "position": {
              "latitude_rad": 0.7999999999907527,
              "longitude_rad": -2.0,
              "ellipsoid_height_m": 1.049999999127587
            },
            "pressure_pa": 101312.9310009172,
            "temperature_k": 288.143174767288,
            "density_kgpm3": 1.2248864860419773,
            "relative_humidity": 0.0,
            "wind_toward_ned_mps": {
              "x": 0.0,
              "y": 0.0,
              "z": 0.0
            },
            "turbulence_ned_mps": {
              "x": 0.0,
              "y": 0.0,
              "z": 0.0
            },
            "seed": "42",
            "model_id": "jsbsim-dry-isa"
          },
          "held_axes": {
            "kind": "axes",
            "roll": 0.0,
            "pitch": 0.0,
            "yaw": 0.0,
            "throttle": 0.0,
            "mixture": 1.0,
            "left_brake": 1.0,
            "right_brake": 1.0,
            "trim": 0.0
          },
          "native_outcome": "paused",
          "native_live": true,
          "paused": true,
          "time_scale": 1.0,
          "debt_quanta": 0,
          "native_fault": "",
          "named_start": "ground-ready",
          "model_identity": {
            "id": "original-interactive-prototype",
            "version": "0.1.0-prototype",
            "backend_model": "original-interactive"
          },
          "native_source_fingerprint": "5e0abfeae9ffd249f8be3f4410d9903f30736698fcb276bdf72f3630132102e5",
          "prepared_world_sha256": "04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5",
          "world_anchor": {
            "latitude_rad": 0.8,
            "longitude_rad": -2.0,
            "ellipsoid_height_m": 0.0
          },
          "canonical": {
            "ecef_position_m": [
              -1852421.6708183065,
              -4047615.1943075066,
              4552615.219081322
            ],
            "anchor_eus_position_m": [
              -1.0278683459929994e-10,
              1.0499999997340401,
              5.889074110609904e-05
            ],
            "body_to_anchor_eus": [
              -2.220446049250313e-16,
              1.0,
              -1.6653345369377348e-16,
              9.247380639010316e-12,
              -1.209347928508023e-16,
              -1.0,
              -1.0,
              -2.1081953887457615e-16,
              -9.247602683615241e-12
            ]
          }
        }"""
var checks: int = 0
var failures: Array[String] = []

static func run() -> Dictionary:
	return new()._run()

static func reference_readback() -> Dictionary:
	# Shared integration-test seam: fresh owned values, same exact-byte loader.
	return captured_readback()

static func captured_readback() -> Dictionary:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(CAPTURED_READBACK.to_utf8_buffer())
	if context.finish().hex_encode()!=CAPTURED_SHA: return {}
	var value: Variant=JSON.parse_string(CAPTURED_READBACK)
	if not value is Dictionary: return {}
	# JSON loses integer Variant typing. ONLY this declared exact zero is restored.
	var debt: Variant=value.get("debt_quanta")
	if not typeof(debt) in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(debt)) or float(debt)!=0.0: return {}
	value.debt_quanta=int(debt)
	return value

func _check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label)

func _bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0,value)
	return bytes.hex_encode()

func _unavailable(value: Dictionary, label: String) -> void:
	_check(Geometry.valid_view(value),label+"_closed_shape")
	_check(value.available==false and value.state=="unavailable",label+"_state")
	_check(value.session_id==null and value.tick==null and value.ownship_anchor_eus_m==null,label+"_no_stale_identity_ownship")
	_check(value.points_anchor_eus_m.is_empty() and value.leg_labels.is_empty(),label+"_no_stale_diagram")
	_check(not value.error.is_empty() and value.error.length()<=1024,label+"_reason")

func _rejected(input: Variant, label: String, wind: String="calm", runway: int=36) -> void:
	_unavailable(Geometry.view(input,wind,runway),label)

func _run() -> Dictionary:
	var base: Dictionary=captured_readback()
	_check(not base.is_empty(),"exact_original_capture_hash_and_zero_debt")
	if base.is_empty(): return _result()
	_check(reference_readback()==base,"public_reference_readback_exact_owned_loader")
	_check(base.native_source_fingerprint==Cue.SUPPORTED_SOURCE,"actual_capture_matches_generated_source_without_rewrite")
	_check(Readings.from_readback(base).state=="paused" and Cue.from_readback(base).state=="paused","full_original_baseline_admission")
	var before: Dictionary=base.duplicate(true)
	var view: Dictionary=Geometry.view(base,"calm",36)
	_check(Geometry.valid_view(view) and view.available and view.state=="paused","paused_positive")
	if not view.available:
		_check(false,"baseline_failure_"+view.error)
		return _result()
	_check(view.session_id==base.session_id and view.tick=="0","original_identity")
	_check(view.points_anchor_eus_m==[[0.0,0.0,100.0],[0.0,0.0,-2700.0],[-1400.0,0.0,-2700.0],[-1400.0,0.0,1300.0],[0.0,0.0,1300.0],[0.0,0.0,100.0]],"independent_ADR018_points")
	_check(view.leg_labels==["Departure","Crosswind","Downwind","Base","Final"],"independent_ADR018_labels")
	_check(view.points_anchor_eus_m[0]==[0.0,0.0,100.0] and view.points_anchor_eus_m[5]==view.points_anchor_eus_m[0],"runway36_pavement_endpoint_and_closure")
	for i in 3: _check(_bits(view.ownship_anchor_eus_m[i])==_bits(base.canonical.anchor_eus_position_m[i]),"all_three_direct_binary64_copy_"+str(i))
	_check(base==before,"view_preserves_complete_readback")
	# Clearly synthetic source-qualified lifecycle/scalar cases below; none are
	# presented as new observed native output or physically flown states.
	var live: Dictionary=base.duplicate(true)
	live.host_mode="live"; live.paused=false; live.native_outcome="completed"
	_check(Geometry.view(live,"calm",36).state=="live","synthetic_live_positive")
	for tick in ["9007199254740993","18446744073709551615"]:
		var large: Dictionary=base.duplicate(true)
		large.tick=tick; large.aircraft.tick=tick; large.atmosphere.tick=tick
		large.aircraft.elapsed_s=float(tick)/120.0
		_check(Geometry.view(large,"calm",36).tick==tick,"absolute_decimal_tick_"+tick)
	var scalar: Dictionary=base.duplicate(true)
	scalar.canonical.anchor_eus_position_m=[]
	for hex in ["0000000000b0b43d","24faffffff3f8f40","0000000080d8eebd"]:
		scalar.canonical.anchor_eus_position_m.append(hex.hex_decode().decode_double(0))
	var scalar_view: Dictionary=Geometry.view(scalar,"calm",36)
	for i in 3: _check(_bits(scalar_view.ownship_anchor_eus_m[i])==["0000000000b0b43d","24faffffff3f8f40","0000000080d8eebd"][i],"independent_binary64_fixture_"+str(i))
	var held: Dictionary=view.duplicate(true)
	base.canonical.anchor_eus_position_m[0]+=9999.0
	_check(view==held,"input_mutation_cannot_change_previous_output")
	view.points_anchor_eus_m[0][0]=99.0; view.leg_labels[0]="bad"
	_check(Geometry.view(before,"calm",36).points_anchor_eus_m==held.points_anchor_eus_m,"output_mutation_cannot_change_next_points")
	_check(Geometry.view(before,"calm",36).leg_labels==held.leg_labels,"output_mutation_cannot_change_next_labels")
	base=before.duplicate(true)
	_rejected(null,"null")
	_rejected({},"empty_partial")
	_rejected({"model_identity":base.model_identity,"canonical":base.canonical},"plausible_partial")
	for wind in ["unknown","Calm","crosswind"]: _rejected(base,"adopted_wind_"+wind,wind)
	for runway in [18,0,99]: _rejected(base,"runway_"+str(runway),"calm",runway)
	for part in ["id","version","backend_model"]:
		var wrong: Dictionary=base.duplicate(true); wrong.model_identity[part]+="-wrong"
		_rejected(wrong,"identity_"+part)
	for start in ["airborne-prepared","piston-cold-ground","unknown"]:
		var wrong: Dictionary=base.duplicate(true); wrong.named_start=start
		_rejected(wrong,"named_start_"+start)
	var cold: Dictionary=base.duplicate(true)
	cold.model_identity=Readings.PISTON_PROFILE.duplicate(true); cold.named_start="piston-cold-ground"
	_rejected(cold,"complete_cold_identity_outside_domain")
	for field in ["native_source_fingerprint","prepared_world_sha256"]:
		var wrong: Dictionary=base.duplicate(true); wrong[field]="f".repeat(64)
		_rejected(wrong,field)
	for field in ["model_id","seed"]:
		var wrong: Dictionary=base.duplicate(true); wrong.atmosphere[field]="unsupported"
		_rejected(wrong,"weather_"+field)
	var wrong_seed: Dictionary=base.duplicate(true); wrong_seed.atmosphere.seed=42
	_rejected(wrong_seed,"numeric_seed_not_string")
	for axis in ["x","y","z"]:
		for amount in [1e-12,-1e-300]:
			var wrong: Dictionary=base.duplicate(true); wrong.atmosphere.wind_toward_ned_mps[axis]=amount
			_rejected(wrong,"nonzero_actual_wind_"+axis+str(amount))
		var turbulent: Dictionary=base.duplicate(true); turbulent.atmosphere.turbulence_ned_mps[axis]=1e-12
		_rejected(turbulent,"nonzero_turbulence_"+axis)
	var humid: Dictionary=base.duplicate(true); humid.atmosphere.relative_humidity=1e-12
	_rejected(humid,"nonzero_humidity")
	for field in ["error","native_fault"]:
		var wrong: Dictionary=base.duplicate(true); wrong[field]="fault"
		_rejected(wrong,"current_fault_"+field)
	var blocked: Dictionary=base.duplicate(true); blocked.native_outcome="coverage_blocked"
	_rejected(blocked,"blocked_native_outcome")
	for mode in ["closed","stalled","coverage_blocked","discarded"]:
		var retained: Dictionary=base.duplicate(true)
		retained.host_mode=mode; retained.historical=true; retained.paused=false; retained.native_live=false; retained.native_outcome="discarded"
		_check(Readings.from_readback(retained).state=="historical","legitimate_retained_"+mode)
		_rejected(retained,"retained_"+mode)
	var empty: Dictionary=base.duplicate(true)
	for key in Readings.NULLABLE: empty[key]=null
	empty.host_mode="closed"; empty.historical=true; empty.paused=false; empty.native_live=false
	_rejected(empty,"closed_empty")
	for axis in ["latitude_rad","longitude_rad","ellipsoid_height_m"]:
		var wrong: Dictionary=base.duplicate(true); wrong.world_anchor[axis]+=0.1
		_rejected(wrong,"world_anchor_"+axis)
	for field in ["session_id","tick"]:
		var wrong: Dictionary=base.duplicate(true); wrong.atmosphere[field]="mismatch"
		_rejected(wrong,"pair_"+field)
	var position: Dictionary=base.duplicate(true); position.atmosphere.position.ellipsoid_height_m+=1.0
	_rejected(position,"pair_position")
	for invalid in [NAN,INF,"1",Vector3.ZERO,null]:
		var wrong: Dictionary=base.duplicate(true); wrong.canonical.anchor_eus_position_m[1]=invalid
		_rejected(wrong,"invalid_canonical_"+str(invalid))
	var extra: Dictionary=base.duplicate(true); extra.extra=true
	_rejected(extra,"unknown_Readback_key")
	var fixture_bytes: PackedByteArray=FileAccess.get_file_as_bytes(Geometry.FIXTURE_PATH)
	_check(not Geometry._fixture_from_bytes(fixture_bytes).is_empty(),"frozen_fixture_admitted")
	_check(Geometry._fixture_from_bytes(PackedByteArray()).is_empty(),"missing_fixture_bytes")
	var revised: Dictionary=JSON.parse_string(fixture_bytes.get_string_from_utf8())
	revised.revision=2
	_check(Geometry._fixture_from_bytes(JSON.stringify(revised).to_utf8_buffer()).is_empty(),"unknown_fixture_revision_bytes_rejected")
	fixture_bytes.append(10)
	_check(Geometry._fixture_from_bytes(fixture_bytes).is_empty(),"changed_fixture_bytes_rejected")
	_unavailable(Geometry.unavailable("Aid off"),"aid_off")
	_check(Geometry.unavailable("Aid off").error=="Aid off","exact_off_reason")
	_unavailable(Geometry.unavailable(""),"empty_reason_fallback")
	_check(Geometry.unavailable("a".repeat(2000)).error.length()==1024,"bounded_reason")
	return _result()

func _result() -> Dictionary:
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixture_sha256":Geometry.FIXTURE_SHA256,"captured_readback_sha256":CAPTURED_SHA,"scope":"Pure copied presentation; captured baseline plus explicitly synthetic mutations, no native execution or physics qualification"}
