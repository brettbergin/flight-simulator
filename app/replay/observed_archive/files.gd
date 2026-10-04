extends RefCounted
# Original MIT. ADR012 selected NEW files only. Private actor owns exclusive IO;
# caller owns copied data and observes actor exit before any public receipt.
const Codec = preload("res://replay/observed_archive/codec.gd")
const Strict = preload("res://replay/observed_archive/strict_json.gd")
const Values = preload("res://replay/observed/values.gd")
const HELPER: String = "res://replay/observed_archive/windows_io.ps1"
var _owner: int = OS.get_thread_caller_id()
# Private independent-proof hooks, never decoded from archives or exposed in UI.
var _fault: String = ""
var _temporary_name: String = ""
var _before_commit: Callable
var _last_pid: int = 0

static func _receipt(ok: bool, state: String, message: String, path: String = "", temporary: Variant = null, value: Variant = null, digest: Variant = null) -> Dictionary:
	return {"ok":ok,"error":message,"state":state,"path":path,"temp_path":temporary,"value":value,"payload_sha256":digest}

func _foreign() -> Dictionary:
	return _receipt(false,"rejected","Recorded review files belong to their owner thread")

func save_new(path: Variant, bytes: Variant) -> Dictionary:
	if OS.get_thread_caller_id()!=_owner: return _foreign()
	if not _path(path): return _receipt(false,"rejected","Choose an absolute local Windows file path")
	var checked: Dictionary = Codec.decode(bytes)
	if not checked.ok: return _receipt(false,"rejected",checked.error)
	if typeof(_fault)!=TYPE_STRING or _fault not in ["","write","flush","move","receipt","truncate_request","excess_request","post_verify"]:
		return _receipt(false,"rejected","Unsupported private IO proof phase")
	var name: String = _temporary_name
	if name.is_empty(): name=".fsreview-"+Crypto.new().generate_random_bytes(16).hex_encode()+".tmp"
	if not _temp_name(name): return _receipt(false,"rejected","Private temporary name rejected")
	var fault_code: int = ["","write","flush","move","receipt","truncate_request","excess_request"].find(_fault)
	if fault_code<0: fault_code=0
	var process: Dictionary = _start(path,name,bytes.size(),1,fault_code)
	if process.is_empty(): return _receipt(false,"rejected","Fixed Windows review IO helper unavailable")
	var ready: Dictionary = _frame(process)
	if not _matches(ready,path,name) or ready.code!="READY":
		_finish(process)
		return _receipt(false,"rejected","Selected new file or exclusive temporary refused",ready.get("path","") if _matches(ready,path,name) else "")
	var resolved: String = ready.path
	var temporary: String = ready.temp
	var sent: bool = _write(process,bytes.slice(0,bytes.size()-1) if _fault=="truncate_request" else bytes)
	if _fault=="truncate_request":
		_finish(process)
		return _receipt(false,"not_saved","Review not saved: truncated private transfer",resolved,_available(temporary))
	if sent and _fault=="excess_request": sent=_write(process,PackedByteArray([88]))
	var prepared: Dictionary = _frame(process) if sent else {}
	if not _matches(prepared,path,name) or prepared.code!="PREPARED":
		_finish(process)
		return _receipt(false,"not_saved","Review not saved: write or OS flush failed",resolved,_available(temporary))
	var staged: PackedByteArray = _read_file(temporary)
	var staged_record: Dictionary = Codec.decode(staged)
	if staged!=bytes or not staged_record.ok or not Codec._exact(checked.value,staged_record.value):
		_finish(process)
		return _receipt(false,"not_saved","Review not saved: temporary verification failed",resolved,_available(temporary))
	if _before_commit.is_valid(): _before_commit.call(resolved,temporary)
	if not _write(process,PackedByteArray([67])):
		var refused: Dictionary = _frame(process)
		_finish(process)
		if _matches(refused,path,name) and refused.code=="FAILED" and _available(temporary)!=null:
			return _receipt(false,"not_saved","Review not saved: private transfer refused",resolved,temporary)
		return _receipt(false,"recovery_required","Save not verified; recovery required",resolved,_available(temporary))
	var done: Dictionary = _frame(process)
	var exited: bool = _finish(process)
	if exited and _matches(done,path,name) and done.code=="FAILED" and _available(temporary)!=null:
		return _receipt(false,"not_saved","Review not saved: commit guard refused",resolved,temporary)
	if not exited or not _matches(done,path,name) or done.code!="DONE" or OS.get_process_exit_code(_last_pid)!=0:
		return _receipt(false,"recovery_required","Save not verified; recovery required",resolved,_available(temporary))
	if _fault=="post_verify":
		return _receipt(false,"recovery_required","Save not verified; recovery required",resolved,_available(temporary))
	var committed: PackedByteArray = _read_file(resolved)
	var decoded: Dictionary = Codec.decode(committed)
	if committed!=bytes or not decoded.ok or not Codec._exact(checked.value,decoded.value):
		return _receipt(false,"recovery_required","Save not verified; recovery required",resolved,_available(temporary))
	return _receipt(true,"saved","",resolved,null,null,checked.payload_sha256)

func open(path: Variant) -> Dictionary:
	if OS.get_thread_caller_id()!=_owner: return _foreign()
	if not _path(path): return _receipt(false,"rejected","Choose an absolute local Windows file path")
	var process: Dictionary = _start(path,"",0,2,0)
	if process.is_empty(): return _receipt(false,"rejected","Fixed Windows review IO helper unavailable")
	var frame: Dictionary = _frame(process)
	var admitted: bool = _matches(frame,path,"") and frame.code=="OPEN"
	var bytes: PackedByteArray = PackedByteArray()
	if admitted:
		var length: PackedByteArray = _read(process,4)
		if length.size()==4 and length.decode_u32(0)>0 and length.decode_u32(0)<=Strict.MAX_BYTES:
			bytes=_read(process,length.decode_u32(0))
	var exited: bool = _finish(process)
	if not admitted or not exited or OS.get_process_exit_code(_last_pid)!=0:
		return _receipt(false,"rejected","Selected review file could not be read safely",frame.get("path","") if _matches(frame,path,"") else "")
	var decoded: Dictionary = Codec.decode(bytes)
	if not decoded.ok: return _receipt(false,"rejected",decoded.error,frame.path)
	return _receipt(true,"opened","",frame.path,null,decoded.value,decoded.payload_sha256)

static func _path(path: Variant) -> bool:
	if OS.get_name()!="Windows" or typeof(path)!=TYPE_STRING or path.length()<4 or path.length()>4096:
		return false
	var drive: int = path.unicode_at(0)
	return ((drive>=65 and drive<=90) or (drive>=97 and drive<=122)) and path[1]==":" and path[2] in ["/","\\"] and Strict.valid_utf8(path.to_utf8_buffer())

static func _temp_name(name: String) -> bool:
	if name.length()!=46 or not name.begins_with(".fsreview-") or not name.ends_with(".tmp"): return false
	for i in range(10,42):
		var code: int = name.unicode_at(i)
		if not ((code>=48 and code<=57) or (code>=97 and code<=102)): return false
	return true

func _start(path: String, name: String, size: int, operation: int, fault: int) -> Dictionary:
	var executable: String = OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	if not FileAccess.file_exists(executable): return {}
	var source: String = FileAccess.get_file_as_string(HELPER)
	if source.is_empty(): return {}
	# EncodedCommand is trusted fixed code; selected path and up to8MiB bytes are stdin.
	var encoded: String = Marshalls.raw_to_base64(source.to_utf16_buffer())
	if encoded.length()+executable.length()+100>=32767: return {}
	# Blocking writes are intentional: the pinned pipe API does not expose partial
	# write counts. READY precedes payload consumption, and the actor receives the
	# entire bounded payload before disk IO or another response, preventing duplex
	# pipe deadlock. Actor-side read deadlines/watchdog bound stalled transactions.
	var process: Dictionary = OS.execute_with_pipe(executable,PackedStringArray(["-NoProfile","-NonInteractive","-EncodedCommand",encoded]),true)
	if process.is_empty(): return {}
	_last_pid=process.pid
	process.deadline=Time.get_ticks_msec()+100000
	var header: PackedByteArray = "FSAR001".to_ascii_buffer()
	header.append(operation); header.append(fault)
	_field(header,path.to_utf8_buffer()); _field(header,name.to_ascii_buffer())
	var length: PackedByteArray = PackedByteArray(); length.resize(4); length.encode_u32(0,size)
	header.append_array(length)
	if not _write(process,header): _finish(process); return {}
	return process

static func _field(header: PackedByteArray, value: PackedByteArray) -> void:
	var length: PackedByteArray = PackedByteArray(); length.resize(4); length.encode_u32(0,value.size())
	header.append_array(length); header.append_array(value)

static func _write(process: Dictionary, bytes: PackedByteArray) -> bool:
	for offset in range(0,bytes.size(),65536):
		if Time.get_ticks_msec()>process.deadline or not process.stdio.store_buffer(bytes.slice(offset,mini(offset+65536,bytes.size()))): return false
	return true

static func _read(process: Dictionary, count: int) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray()
	if count<0 or count>Strict.MAX_BYTES: return result
	while result.size()<count and Time.get_ticks_msec()<=process.deadline:
		var part: PackedByteArray = process.stdio.get_buffer(mini(65536,count-result.size()))
		if part.is_empty():
			if not OS.is_process_running(process.pid): break
			OS.delay_msec(5)
		else: result.append_array(part)
	return result

static func _frame(process: Dictionary) -> Dictionary:
	var size: PackedByteArray = _read(process,4)
	if size.size()!=4 or size.decode_u32(0)==0 or size.decode_u32(0)>65536: return {}
	var bytes: PackedByteArray = _read(process,size.decode_u32(0))
	if bytes.size()!=size.decode_u32(0) or not Strict.valid_utf8(bytes): return {}
	var parser: JSON = JSON.new()
	if parser.parse(bytes.get_string_from_utf8())!=OK: return {}
	var frame: Variant = parser.data
	if not Values.keys(frame,["code","path","temp"]) or typeof(frame.code)!=TYPE_STRING or frame.code not in ["READY","PREPARED","DONE","OPEN","REJECTED","FAILED","UNCERTAIN"] or typeof(frame.path)!=TYPE_STRING or typeof(frame.temp)!=TYPE_STRING or frame.path.length()>4096 or frame.temp.length()>4096: return {}
	return frame

static func _matches(frame: Dictionary, requested: String, name: String) -> bool:
	if frame.is_empty(): return false
	if frame.path.is_empty(): return frame.code=="REJECTED" and frame.temp.is_empty()
	# Fixed actor resolves separators/dot components; data receipts cannot substitute
	# another selected file or invented recovery temporary.
	var target: String = requested.replace("\\","/").simplify_path()
	if frame.path.replace("\\","/").simplify_path().nocasecmp_to(target)!=0: return false
	if frame.code in ["READY","PREPARED","FAILED"] and frame.temp.is_empty(): return false
	if frame.code in ["OPEN","DONE","REJECTED"] and not frame.temp.is_empty(): return false
	return frame.temp.is_empty() or (not name.is_empty() and frame.temp.replace("\\","/").simplify_path().nocasecmp_to(target.get_base_dir().path_join(name))==0)

static func _finish(process: Dictionary) -> bool:
	process.stdio.close(); process.stderr.close()
	# Closing stdin aborts a PREPARED transaction without a commit. The actor has a
	# fixed85s self watchdog; retain its process handle until observed exit.
	while OS.is_process_running(process.pid): OS.delay_msec(5)
	return OS.get_process_exit_code(process.pid)>=0

static func _read_file(path: String) -> PackedByteArray:
	var file: FileAccess = FileAccess.open(path,FileAccess.READ)
	if file==null: return PackedByteArray()
	var size: int = file.get_length()
	if size<=0 or size>Strict.MAX_BYTES: file.close(); return PackedByteArray()
	var bytes: PackedByteArray = file.get_buffer(size)
	var ok: bool = bytes.size()==size and file.get_error()==OK and file.get_length()==size
	file.close()
	return bytes if ok else PackedByteArray()

static func _available(path: String) -> Variant:
	return path if FileAccess.file_exists(path) else null
