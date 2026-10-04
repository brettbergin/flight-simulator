extends RefCounted
# Original MIT. ObservedFlightRecorder (ADR011); construction/main-thread owned.
const Tick = preload("res://replay/observed/tick_math.gd")
const Values = preload("res://replay/observed/values.gd")
const U64 = preload("res://simulation/uint64.gd")
const FOREIGN: String = "Observed flight review belongs to its main-thread owner"
var _owner: int = OS.get_thread_caller_id()
var _record: Dictionary = Values.empty_recording()
var _last: Dictionary = {}
var _last_grid: int = 0

func _foreign() -> bool:
	return not Thread.is_main_thread() or OS.get_thread_caller_id()!=_owner

func _result(ok: bool, error: String = "", appended: bool = false) -> Dictionary:
	return {"ok":ok,"error":error,"appended":appended,"status":status()}

func _foreign_result() -> Dictionary:
	return {"ok":false,"error":FOREIGN,"appended":false,"status":null}

func status() -> Variant:
	if _foreign():
		return null
	var metadata: Variant = _record.metadata
	return {"contract_version":1,"state":_record.state,
		"session_id":metadata.session_id if metadata!=null else null,
		"first_tick":metadata.first_tick if metadata!=null else null,
		"last_observed_tick":_record.last_observed_tick,
		"last_sample_tick":_record.samples.back().tick if not _record.samples.is_empty() else null,
		"sample_count":_record.samples.size(),"seal_reason":_record.seal_reason,"error":_record.error,
		"skipped_target_count":_record.skipped_target_count,"late_sample_count":_record.late_sample_count,
		"uncaptured_tail_targets":_record.uncaptured_tail_targets}

func recording() -> Variant:
	return null if _foreign() else _record.duplicate(true)

func _finish(reason: String, error: String = "") -> void:
	if _record.state!="recording":
		return
	var span: Dictionary = Tick.subtract(_record.last_observed_tick,_record.metadata.first_tick)
	var clipped: int = 144000 if U64.compare(span.value,"144000")>0 else int(span.value)
	var tail: int = maxi(0,clipped/60-_last_grid)
	_record.uncaptured_tail_targets=tail
	_record.skipped_target_count+=tail
	_record.state="sealed"
	_record.seal_reason=reason
	_record.error=error.left(1024)

func seal(reason: String) -> Dictionary:
	if _foreign():
		return _foreign_result()
	if reason not in ["manual","closed"]:
		return _result(false,"Unsupported scene seal reason")
	_finish(reason)
	return _result(true)

func begin(readback: Variant, replace_confirmed: bool = false) -> Dictionary:
	if _foreign():
		return _foreign_result()
	var qualified: Dictionary = Values.qualify(readback)
	if not qualified.ok or qualified.kind!="current":
		return _result(false,qualified.error if not qualified.ok else "Begin requires current qualified truth")
	if _record.state!="empty":
		if not replace_confirmed or readback.session_id==_record.metadata.session_id:
			return _result(false,"Replacement requires a confirmed different session")
	_record=Values.empty_recording()
	_record.state="recording"
	_record.metadata=Values.metadata(readback)
	_record.last_observed_tick=readback.tick
	_last=Values.observation(readback,qualified.readings)
	_last_grid=0
	_record.samples.append(Values.sample(readback,qualified.readings,readback.tick,0,0))
	if not Tick.add_small(readback.tick,60).ok:
		_finish("tick_exhausted")
	return _result(true,"",true)

func observe(readback: Variant) -> Dictionary:
	if _foreign():
		return _foreign_result()
	if _record.state=="sealed":
		return _result(false,"Recording is sealed")
	var qualified: Dictionary = Values.qualify(readback)
	if not qualified.ok:
		_finish("identity_changed" if Values.changed_identity(readback,_record.metadata) else "invalid_observation",qualified.error)
		return _result(false,qualified.error)
	if qualified.kind=="empty":
		_finish("closed")
		return _result(true)
	if _record.state=="empty":
		return _result(false,"Begin a recording before observing")
	if Values.metadata(readback,_record.metadata.first_tick)!=_record.metadata:
		_finish("identity_changed","Recorded session identity changed")
		return _result(false,"Recorded session identity changed")
	if U64.compare(readback.tick,_record.last_observed_tick)<0:
		_finish("invalid_observation","Observed tick moved backward")
		return _result(false,"Observed tick moved backward")
	var observation: Dictionary = Values.observation(readback,qualified.readings)
	if readback.tick==_record.last_observed_tick and not Values.same_observation(_last,observation):
		_finish("invalid_observation","Contradictory truth at the same tick")
		return _result(false,"Contradictory truth at the same tick")
	_record.last_observed_tick=readback.tick
	_last=observation
	if qualified.kind=="historical":
		_finish("closed" if readback.host_mode=="closed" else "terminal","" if readback.host_mode=="closed" else "Retained terminal truth; no outcome inferred")
		return _result(true)
	var span: Dictionary = Tick.subtract(readback.tick,_record.metadata.first_tick)
	if U64.compare(span.value,"144000")>0:
		_finish("limit")
		return _result(true)
	var relative: int = int(span.value)
	var grid: int = relative/60
	if grid<=_last_grid:
		return _result(true)
	var target: Dictionary = Tick.add_small(_record.metadata.first_tick,grid*60)
	var skipped: int = grid-_last_grid-1
	var late: int = relative%60
	_record.samples.append(Values.sample(readback,qualified.readings,target.value,late,skipped))
	_record.skipped_target_count+=skipped
	_record.late_sample_count+=1 if late>0 else 0
	_last_grid=grid
	if relative==144000:
		_finish("limit")
	elif not Tick.add_small(_record.metadata.first_tick,(grid+1)*60).ok:
		_finish("tick_exhausted")
	return _result(true,"",true)
