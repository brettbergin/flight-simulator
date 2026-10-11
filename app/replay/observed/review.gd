extends RefCounted
# Original MIT. ADR011/022 ObservedReview: copied v1/v2 historical selection; no native references.
const Values = preload("res://replay/observed/values.gd")
const FOREIGN: String = "Observed flight review belongs to its main-thread owner"
var _owner: int = OS.get_thread_caller_id()
var _record: Dictionary = {}
var _index: int = -1

func _foreign() -> bool:
	return not Thread.is_main_thread() or OS.get_thread_caller_id()!=_owner

func _unavailable(error: String) -> Dictionary:
	return {"available":false,"error":error,"sample_index":null,"sample":null,"historical":true}

func set_recording(value: Variant) -> bool:
	if _foreign():
		return false
	if not Values.valid_recording(value):
		_record={}
		_index=-1
		return false
	var unchanged: bool = value==_record
	_record=value.duplicate(true)
	if not unchanged:
		_index=_record.samples.size()-1
	return true

func select(index: int) -> Dictionary:
	if _foreign():
		return _unavailable(FOREIGN)
	if _record.is_empty() or index<0 or index>=_record.samples.size():
		return _unavailable("No recorded sample at this index")
	_index=index
	return selection()

func selection() -> Dictionary:
	if _foreign():
		return _unavailable(FOREIGN)
	if _record.is_empty() or _index<0:
		return _unavailable("No recorded sample selected")
	return {"available":true,"error":"","sample_index":_index,"sample":_record.samples[_index].duplicate(true),"historical":true}
