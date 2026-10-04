extends RefCounted
# Original MIT. Private ADR011 qualification and closed owned-value validation.
const NativeReadings = preload("res://cockpit/instruments/native_readings.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
const U64 = preload("res://simulation/uint64.gd")
const Tick = preload("res://replay/observed/tick_math.gd")
const MODEL: Dictionary = {"id":"original-interactive-prototype","version":"0.1.0-prototype","backend_model":"original-interactive"}
const ANCHOR: Dictionary = {"latitude_rad":0.8,"longitude_rad":-2.0,"ellipsoid_height_m":0.0}
const CLOCK: Dictionary = {"purpose":"runtime","tick_rate_hz":120}
const REASONS: Array = ["manual","limit","terminal","closed","invalid_observation","identity_changed","tick_exhausted"]

static func keys(value: Variant, names: Array) -> bool:
	if not value is Dictionary or value.size()!=names.size():
		return false
	for key in value:
		if not key is String or not names.has(key):
			return false
	return true

static func text(value: Variant, limit: int = 1024) -> bool:
	return value is String and value.length()<=limit

static func hex(value: Variant) -> bool:
	if not value is String or value.length()!=64:
		return false
	for i in value.length():
		var code: int = value.unicode_at(i)
		if not ((code>=48 and code<=57) or (code>=97 and code<=102)):
			return false
	return true

static func floats(value: Variant, size: int) -> bool:
	if not value is Array or value.size()!=size:
		return false
	for element in value:
		if typeof(element)!=TYPE_FLOAT or not is_finite(element):
			return false
	return true

static func count(value: Variant, maximum: int = 2400) -> bool:
	return typeof(value)==TYPE_INT and value>=0 and value<=maximum

static func identifier(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length()>128 or value.unicode_at(0)<97 or value.unicode_at(0)>122:
		return false
	var separator: bool = false
	for i in value.length():
		var code: int = value.unicode_at(i)
		if (code>=97 and code<=122) or (code>=48 and code<=57):
			separator=false
		elif code in [46,95,45] and not separator:
			separator=true
		else:
			return false
	return not separator

static func axes(value: Variant) -> bool:
	if not keys(value,["kind","roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"]) or value.kind!="axes":
		return false
	for key in ["roll","pitch","yaw","trim","throttle","mixture","left_brake","right_brake"]:
		if typeof(value[key]) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value[key])):
			return false
		if value[key]<(-1.0 if key in ["roll","pitch","yaw","trim"] else 0.0) or value[key]>1.0:
			return false
	return value.mixture==1.0

static func empty_recording() -> Dictionary:
	return {"contract_version":1,"state":"empty","metadata":null,"last_observed_tick":null,"samples":[],"seal_reason":null,"error":"","skipped_target_count":0,"late_sample_count":0,"uncaptured_tail_targets":0}

static func metadata(readback: Dictionary, first_tick: Variant = null) -> Dictionary:
	return {"session_id":readback.session_id,"model_identity":readback.model_identity.duplicate(true),
		"native_source_fingerprint":readback.native_source_fingerprint,"prepared_world_sha256":readback.prepared_world_sha256,
		"world_anchor":readback.world_anchor.duplicate(true),"seed":readback.atmosphere.seed,
		"clock":readback.aircraft.clock.duplicate(true),"named_start":readback.named_start,
		"first_tick":readback.tick if first_tick==null else first_tick}

static func qualify(value: Variant) -> Dictionary:
	var readings: Dictionary = NativeReadings.from_readback(value)
	if readings.state=="invalid":
		return {"ok":false,"error":readings.error,"kind":"invalid","readings":readings}
	if readings.state=="empty":
		return {"ok":true,"error":"","kind":"empty","readings":readings}
	if value.atmosphere.seed!="42":
		return {"ok":false,"error":"Observed review requires seed42","kind":"invalid","readings":readings}
	if typeof(value.aircraft.elapsed_s)!=TYPE_FLOAT:
		return {"ok":false,"error":"Observed elapsed_s must be binary64","kind":"invalid","readings":readings}
	if value.canonical!=null:
		var anchor: Dictionary = Frames.anchor(value.world_anchor.latitude_rad,value.world_anchor.longitude_rad,value.world_anchor.ellipsoid_height_m)
		var expected: Dictionary = Frames.derive(value.aircraft,anchor)
		if expected.is_empty():
			return {"ok":false,"error":"Cannot derive canonical geometry","kind":"invalid","readings":readings}
		for key in ["ecef_position_m","anchor_eus_position_m","body_to_anchor_eus"]:
			if not floats(value.canonical[key],expected[key].size()):
				return {"ok":false,"error":"Canonical scalars must be binary64","kind":"invalid","readings":readings}
			for i in expected[key].size():
				if absf(value.canonical[key][i]-expected[key][i])>1e-7:
					return {"ok":false,"error":"Canonical geometry differs from native truth","kind":"invalid","readings":readings}
	if readings.state=="historical":
		if value.host_mode not in ["closed","stalled","coverage_blocked","discarded"]:
			return {"ok":false,"error":"Historical observation must be terminal or closed","kind":"invalid","readings":readings}
		return {"ok":true,"error":"","kind":"historical","readings":readings}
	if value.host_mode not in ["live","paused"] or value.historical or value.canonical==null:
		return {"ok":false,"error":"Observation is not current qualified truth","kind":"invalid","readings":readings}
	return {"ok":true,"error":"","kind":"current","readings":readings}

static func changed_identity(value: Variant, bound: Variant) -> bool:
	if bound==null or not value is Dictionary:
		return false
	# Only shape-qualified identity fields classify rejection; never adopt their tick.
	for key in ["session_id","native_source_fingerprint","prepared_world_sha256","named_start"]:
		if value.get(key) is String and value[key]!=bound[key]:
			return true
	for key in ["model_identity","world_anchor"]:
		if value.get(key) is Dictionary and keys(value[key],bound[key].keys()) and value[key]!=bound[key]:
			return true
	if value.get("atmosphere") is Dictionary and U64.valid(value.atmosphere.get("seed")) and value.atmosphere.seed!=bound.seed:
		return true
	return false

static func observation(readback: Dictionary, readings: Dictionary) -> Dictionary:
	return {"aircraft":readback.aircraft.duplicate(true),"atmosphere":readback.atmosphere.duplicate(true),
		"held_axes":readback.held_axes.duplicate(true),"channels":readings.readings.duplicate(true),
		"position":readback.canonical.anchor_eus_position_m.duplicate(true) if readback.canonical!=null else null}

static func same_observation(a: Dictionary, b: Dictionary) -> bool:
	for key in ["aircraft","atmosphere","held_axes","channels"]:
		if a[key]!=b[key]:
			return false
	return a.position==null or b.position==null or a.position==b.position

static func sample(readback: Dictionary, readings: Dictionary, target: String, late: int, skipped: int) -> Dictionary:
	return {"tick":readback.tick,"target_tick":target,"late_by_ticks":late,"skipped_targets_before":skipped,
		"gap_before":skipped>0,"elapsed_s":readback.aircraft.elapsed_s,
		"anchor_eus_position_m":readback.canonical.anchor_eus_position_m.duplicate(true),
		"readings":readings.duplicate(true),"held_axes":readback.held_axes.duplicate(true)}

static func valid_metadata(value: Variant) -> bool:
	if not keys(value,["session_id","model_identity","native_source_fingerprint","prepared_world_sha256","world_anchor","seed","clock","named_start","first_tick"]):
		return false
	if not identifier(value.session_id):
		return false
	if not keys(value.model_identity,MODEL.keys()) or value.model_identity!=MODEL:
		return false
	if not keys(value.world_anchor,ANCHOR.keys()) or value.world_anchor!=ANCHOR:
		return false
	for key in ANCHOR:
		if typeof(value.world_anchor[key])!=TYPE_FLOAT:
			return false
	return hex(value.native_source_fingerprint) and value.prepared_world_sha256==NativeReadings.WORLD and value.seed=="42" and keys(value.clock,CLOCK.keys()) and value.clock.purpose=="runtime" and typeof(value.clock.tick_rate_hz) in [TYPE_INT,TYPE_FLOAT] and value.clock.tick_rate_hz==120 and value.named_start in ["ground-ready","airborne-prepared"] and U64.valid(value.first_tick)

static func valid_readings(value: Variant, session: String, tick: String) -> bool:
	if not keys(value,["session_id","tick","state","native_truth","readings","error"]):
		return false
	if value.session_id!=session or value.tick!=tick or value.state not in ["live","paused"] or typeof(value.native_truth)!=TYPE_BOOL or not value.native_truth or value.error!="":
		return false
	if not keys(value.readings,NativeReadings.UNITS.keys()):
		return false
	for key in NativeReadings.UNITS:
		var channel: Variant = value.readings[key]
		if not keys(channel,["value","unit","valid","error"]) or channel.unit!=NativeReadings.UNITS[key] or typeof(channel.valid)!=TYPE_BOOL or not text(channel.error):
			return false
		if channel.valid:
			if typeof(channel.value)!=TYPE_FLOAT or not is_finite(channel.value) or channel.error!="":
				return false
		elif channel.value!=null or channel.error.is_empty():
			return false
	return true

static func valid_recording(value: Variant) -> bool:
	if not keys(value,["contract_version","state","metadata","last_observed_tick","samples","seal_reason","error","skipped_target_count","late_sample_count","uncaptured_tail_targets"]):
		return false
	if typeof(value.contract_version)!=TYPE_INT or value.contract_version!=1 or not value.state is String or not text(value.error):
		return false
	if not count(value.skipped_target_count) or not count(value.late_sample_count) or not count(value.uncaptured_tail_targets) or not value.samples is Array or value.samples.size()>2401:
		return false
	if value.state=="empty":
		return value==empty_recording()
	if value.state not in ["recording","sealed"] or not valid_metadata(value.metadata) or not U64.valid(value.last_observed_tick) or value.samples.is_empty():
		return false
	if U64.compare(value.last_observed_tick,value.metadata.first_tick)<0:
		return false
	if value.state=="recording":
		if value.seal_reason!=null or value.error!="" or value.uncaptured_tail_targets!=0:
			return false
	else:
		if not value.seal_reason is String or value.seal_reason not in REASONS:
			return false
		if value.seal_reason in ["manual","limit","closed","tick_exhausted"] and value.error!="":
			return false
		if value.seal_reason in ["invalid_observation","identity_changed","terminal"] and value.error.is_empty():
			return false
	var previous_tick: Variant = null
	var previous_grid: int = -1
	var skipped_total: int = 0
	var late_total: int = 0
	for index in value.samples.size():
		var item: Variant = value.samples[index]
		if not keys(item,["tick","target_tick","late_by_ticks","skipped_targets_before","gap_before","elapsed_s","anchor_eus_position_m","readings","held_axes"]):
			return false
		if not U64.valid(item.tick) or not U64.valid(item.target_tick) or not count(item.late_by_ticks,59) or not count(item.skipped_targets_before) or typeof(item.gap_before)!=TYPE_BOOL or item.gap_before!=(item.skipped_targets_before>0):
			return false
		if typeof(item.elapsed_s)!=TYPE_FLOAT or not is_finite(item.elapsed_s) or item.elapsed_s<0.0 or not floats(item.anchor_eus_position_m,3) or not axes(item.held_axes):
			return false
		if not valid_readings(item.readings,value.metadata.session_id,item.tick):
			return false
		# Schema derived-time consistency only; absolute ticks never enter scheduling.
		if absf(item.elapsed_s-float(item.tick)/120.0)>maxf(1e-9,absf(item.elapsed_s)*2.220446049250313e-16*4.0):
			return false
		var relative: Dictionary = Tick.bounded_difference(item.tick,value.metadata.first_tick)
		var target_relative: Dictionary = Tick.bounded_difference(item.target_tick,value.metadata.first_tick)
		if not relative.ok or not target_relative.ok or target_relative.value%60!=0 or relative.value-target_relative.value!=item.late_by_ticks:
			return false
		var grid: int = target_relative.value/60
		if grid<=previous_grid or item.skipped_targets_before!=grid-previous_grid-1 or U64.compare(item.tick,value.last_observed_tick)>0:
			return false
		if index==0 and (item.tick!=value.metadata.first_tick or item.target_tick!=item.tick or item.late_by_ticks!=0):
			return false
		if previous_tick!=null and U64.compare(item.tick,previous_tick)<=0:
			return false
		skipped_total+=item.skipped_targets_before
		late_total+=1 if item.late_by_ticks>0 else 0
		previous_grid=grid
		previous_tick=item.tick
	var span: Dictionary = Tick.subtract(value.last_observed_tick,value.metadata.first_tick)
	var clipped: int = 144000 if U64.compare(span.value,"144000")>0 else int(span.value)
	var tail: int = maxi(0,clipped/60-previous_grid)
	if value.state=="recording" and (clipped>=144000 or tail!=0 or not Tick.add_small(value.metadata.first_tick,(previous_grid+1)*60).ok):
		return false
	if value.uncaptured_tail_targets!=(tail if value.state=="sealed" else 0) or value.skipped_target_count!=skipped_total+value.uncaptured_tail_targets or value.late_sample_count!=late_total:
		return false
	if value.seal_reason=="limit":
		if clipped!=144000:
			return false
		if span.value=="144000" and (previous_tick!=value.last_observed_tick or previous_grid!=2400):
			return false
		if U64.compare(span.value,"144000")>0 and previous_grid==2400:
			return false
	if value.seal_reason=="tick_exhausted" and (previous_grid>=2400 or Tick.add_small(value.metadata.first_tick,(previous_grid+1)*60).ok):
		return false
	return true
