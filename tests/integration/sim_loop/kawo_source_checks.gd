extends RefCounted
# Original MIT. Synthetic historical values/lexical controls, no native/storage
# execution or source-authenticity assertion. Expected words predate runtime.
const Values=preload("res://replay/observed/values.gd")
const Codec=preload("res://replay/observed_archive/codec.gd")
const Facade=preload("res://simulation/session_facade.gd")
const Scene=preload("res://simulation/flight_scene.gd")
const Worlds=preload("res://world/world_admission.gd")

static func historical_control() -> Dictionary:
	var session: String="kawo-source-control"
	var anchor: Dictionary={"latitude_rad":"fdfc84c1e5e5ea3f".hex_decode().decode_double(0),"longitude_rad":"5eedd3837e0e01c0".hex_decode().decode_double(0),"ellipsoid_height_m":0.0}
	var channels: Dictionary={}
	var negative_zero: float="0000000000000080".hex_decode().decode_double(0)
	var units: Dictionary={"tas":"m/s","ground_speed":"m/s","pitch":"rad","bank":"rad","heading_true":"rad","ellipsoid_height":"m","vertical_speed":"m/s","body_yaw_rate":"rad/s","fuel_total":"kg"}
	for id in units: channels[id]={"value":negative_zero if id=="bank" else (100.0 if id=="fuel_total" else 0.0),"unit":units[id],"valid":true,"error":""}
	var axes: Dictionary={"kind":"axes","roll":0.0,"pitch":0.0,"yaw":0.0,"throttle":0.0,"mixture":1.0,"left_brake":1.0,"right_brake":1.0,"trim":0.0}
	var metadata: Dictionary={"session_id":session,"model_identity":{"id":"original-interactive-prototype","version":"0.1.0-prototype","backend_model":"original-interactive"},"native_source_fingerprint":"a".repeat(64),"prepared_world_sha256":"b2c53308fdc427900d84b541aff51ba66cbb71bc483fcee0ea16d067dbd15cfb","world_anchor":anchor,"seed":"42","clock":{"purpose":"runtime","tick_rate_hz":120},"named_start":"ground-ready","first_tick":"0"}
	var sample: Dictionary={"tick":"0","target_tick":"0","late_by_ticks":0,"skipped_targets_before":0,"gap_before":false,"elapsed_s":0.0,"anchor_eus_position_m":[210.0,17.0,569.0],"readings":{"session_id":session,"tick":"0","state":"paused","native_truth":true,"readings":channels,"error":""},"held_axes":axes}
	return {"contract_version":3,"state":"sealed","metadata":metadata,"last_observed_tick":"0","samples":[sample],"seal_reason":"manual","error":"","skipped_target_count":0,"late_sample_count":0,"uncaptured_tail_targets":0}

func run(host: Node) -> Dictionary:
	var checks: int=0
	var failures: Array[String]=[]
	var check: Callable=func(ok: bool,name: String):
		if not ok: failures.append(name)
		host.call("check",ok,"kawo_source_"+name)
	var record: Dictionary=historical_control()
	check.call(Values.valid_recording(record),"synthetic_historical_revision3_shape"); checks+=1
	var encoded: Dictionary=Codec.encode(record)
	check.call(encoded.ok,"revision3_encode"); checks+=1
	if encoded.ok:
		var restored: Dictionary=Codec.decode(encoded.value)
		check.call(restored.ok and Codec._exact(record,restored.value),"revision3_exact_restore"); checks+=1
		if restored.ok:
			check.call(Codec._encode_binary64(restored.value.samples[0].readings.readings.bank.value).value["$binary64_le"]=="0000000000000080","negative_zero_word"); checks+=1
		var envelope: Dictionary=JSON.parse_string(encoded.value.get_string_from_utf8())
		envelope.archive_version=2
		check.call(not Codec.decode(JSON.stringify(envelope).to_utf8_buffer()).ok,"mixed_envelope_refused"); checks+=1
	var crossed: Dictionary=record.duplicate(true)
	crossed.contract_version=1
	check.call(not Values.valid_recording(crossed),"kawo_cannot_be_revision1"); checks+=1
	crossed=record.duplicate(true); crossed.samples[0]["engine_status"]={}
	check.call(not Values.valid_recording(crossed),"revision3_has_no_engine_status"); checks+=1
	crossed=record.duplicate(true); crossed.samples[0].held_axes.mixture=0.5
	check.call(not Values.valid_recording(crossed),"revision3_legacy_mixture_one"); checks+=1
	crossed=record.duplicate(true); crossed.metadata.world_anchor.ellipsoid_height_m="0000000000000080".hex_decode().decode_double(0)
	check.call(not Values.valid_recording(crossed),"anchor_words_not_numeric_equality"); checks+=1
	var source: Dictionary={"session_id":record.metadata.session_id,"model_identity":record.metadata.model_identity.duplicate(true),"native_source_fingerprint":record.metadata.native_source_fingerprint,"prepared_world_sha256":record.metadata.prepared_world_sha256,"named_start":"ground-ready","wind_profile":"calm","angular_integration_method":null}
	check.call(Scene._recording_matches_source(record,source),"historical_source_link_relation"); checks+=1
	for field in ["session_id","native_source_fingerprint","prepared_world_sha256","named_start"]:
		var wrong: Dictionary=source.duplicate(true)
		wrong[field]="other" if field in ["session_id","named_start"] else "c".repeat(64)
		check.call(not Scene._recording_matches_source(record,wrong),"crossed_link_"+field); checks+=1
	for selector in [null,1,true,StringName("kawo-prototype-v1"),"unknown-world"]:
		check.call(not Worlds.selection(selector,"original-interactive-prototype","ground-ready","calm").ok,"selector_actual_type_"+str(typeof(selector))+str(selector)); checks+=1
	for text in ["{\"x\":1,\"x\":2}","{\"x\":1,\"\\u0078\":2}","{\"x\":1e309}","{\"x\":NaN}","{\"x\":01}","{\"x\":1,}","{\"x\":[1,]}","{\"x\" 1}","{\"x\":1,,\"y\":2}","{\"x\":[1,,2]}","{\"x\":1} {\"y\":2}","{\"x\":\"\\ud800\"}"]:
		check.call(not Facade._pack_json(text.to_utf8_buffer()).ok,"pack_lexical_refusal_"+str(checks)); checks+=1
	check.call(Facade._pack_json("{\"x\":-1.25e2,\"y\":314159,\"z\":null}".to_utf8_buffer()).ok,"ordinary_pack_numbers_not_archive_integer_policy"); checks+=1
	# Independent small row counts exercise the actual JSON-decoder/registry
	# representation boundary, not a second parser or a numeric normalizer.
	var checked_rows: Array=[]
	for path in ["ground.fgrd","airport.json","dossier.json","compile-receipt.json","start-ready34.json","NOTICE.txt"]:
		checked_rows.append({"path":path,"bytes":17,"sha256":"a".repeat(64),"role":"synthetic-"+path})
	var decoded_rows: Array=Facade._pack_json(JSON.stringify({"files":checked_rows}).to_utf8_buffer()).value.files
	check.call(typeof(decoded_rows[0].bytes)==TYPE_FLOAT and Facade._pack_files_equal(decoded_rows,checked_rows),"json_float_counts_match_checked_integer_rows"); checks+=1
	for wrong_count in [18.0,17.5,0.0,-1.0,INF,NAN,"17",true,null]:
		var wrong_rows: Array=decoded_rows.duplicate(true)
		wrong_rows[0].bytes=wrong_count
		check.call(not Facade._pack_files_equal(wrong_rows,checked_rows),"manifest_count_refused_"+str(checks)); checks+=1
	for field in ["path","sha256","role"]:
		var wrong_rows: Array=decoded_rows.duplicate(true)
		wrong_rows[0][field]="crossed"
		check.call(not Facade._pack_files_equal(wrong_rows,checked_rows),"manifest_exact_"+field); checks+=1
	var extra_rows: Array=decoded_rows.duplicate(true)
	extra_rows[0]["extension"]=null
	check.call(not Facade._pack_files_equal(extra_rows,checked_rows),"manifest_closed_row"); checks+=1
	var short_rows: Array=decoded_rows.duplicate(true); short_rows.pop_back()
	check.call(not Facade._pack_files_equal(short_rows,checked_rows),"manifest_exact_six_rows"); checks+=1
	var reordered_rows: Array=decoded_rows.duplicate(true); reordered_rows.reverse()
	check.call(not Facade._pack_files_equal(reordered_rows,checked_rows),"manifest_order_preserved"); checks+=1
	check.call(not Facade._pack_count_equal(17.0,17.0,4194304) and not Facade._pack_count_equal(4194305.0,4194305,4194304),"registry_integer_and_field_bound_preserved"); checks+=1
	var checked_clock: Dictionary={"purpose":"runtime","tick_rate_hz":120}
	var decoded_clock: Dictionary=Facade._pack_json("{\"purpose\":\"runtime\",\"tick_rate_hz\":120}".to_utf8_buffer()).value
	check.call(Facade._pack_clock_equal(decoded_clock,checked_clock),"json_clock_count_matches_checked_integer"); checks+=1
	for rate in [119.0,120.5,121.0,"120",true,null,INF,NAN]:
		var wrong_clock: Dictionary=decoded_clock.duplicate(true); wrong_clock.tick_rate_hz=rate
		check.call(not Facade._pack_clock_equal(wrong_clock,checked_clock),"clock_count_refused_"+str(checks)); checks+=1
	decoded_clock["extra"]=null
	check.call(not Facade._pack_clock_equal(decoded_clock,checked_clock),"clock_closed_shape"); checks+=1
	return {"checks":checks,"failures":failures}
