extends Node
# Standalone read-only diagnostic. No simulation resources or production actor.
const SCRIPT: String = """[Console]::Out.WriteLine('FSPS_ENTRY')
[Console]::Out.Flush()
$clock = [Diagnostics.Stopwatch]::StartNew()
function Metadata([string]$name,[string]$value) {
 if ($value.Length -gt 4096) { throw 'Metadata bound' }
 [Console]::Out.WriteLine($name + '=' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($value)))
}
Metadata 'PSHOME' $PSHOME
Metadata 'VERSION' $PSVersionTable.PSVersion.ToString()
Metadata 'MODULE_PATH' $env:PSModulePath
$smoke = ConvertTo-Json -InputObject @{ probe='fixed-read-only'; schema_version=1 } -Compress
Metadata 'SMOKE' $smoke
Metadata 'UTILITY_PATH' (Get-Command ConvertTo-Json).Module.Path
[Console]::Out.WriteLine('FSPS_DONE=' + $clock.ElapsedMilliseconds.ToString([Globalization.CultureInfo]::InvariantCulture))
[Console]::Out.Flush()
[Environment]::Exit(0)
"""
class PipeReader:
	extends RefCounted
	var mutex: Mutex = Mutex.new()
	var entry_ms: int = -1

	func read(pipe: FileAccess, started: int, observe_entry: bool) -> Dictionary:
		var bytes: PackedByteArray = PackedByteArray()
		var exceeded: bool = false
		while true:
			# Pinned Windows get_buffer returns0 at EOF without ERR_FAIL logging.
			# Single-byte reads avoid assuming a full requested chunk is available.
			var byte: PackedByteArray = pipe.get_buffer(1)
			if byte.is_empty(): break
			if bytes.size()<8192: bytes.append_array(byte)
			else: exceeded=true
			if observe_entry and bytes.size()==12 and bytes=="FSPS_ENTRY\r\n".to_ascii_buffer():
				mutex.lock()
				entry_ms=Time.get_ticks_msec()-started
				mutex.unlock()
		return {"bytes":bytes,"exceeded":exceeded}

	func entry_time() -> int:
		mutex.lock()
		var value: int = entry_ms
		mutex.unlock()
		return value

var observations: Array = []
var failures: Array = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_name() != "Windows":
		failures.append("windows_required")
	else:
		for treatment in ["A", "B", "B", "A"]:
			var result: Dictionary = await _launch(treatment)
			observations.append(result)
			_write_receipt(false)
			if not result.passed:
				failures.append("child_"+str(observations.size()))
				break
	var passed: bool = observations.size()==4 and failures.is_empty()
	_write_receipt(passed)
	print("POWERSHELL_STARTUP_DIAGNOSTIC_PASSED" if passed else "POWERSHELL_STARTUP_DIAGNOSTIC_FAILED")
	get_tree().quit(0 if passed else 1)

func _write_receipt(passed: bool) -> void:
	var receipt: Dictionary = {"schema_version":1,"passed":passed,"observations":observations,"failures":failures,"order":["A","B","B","A"],"limitations":["Entry time is observed by a blocking reader Thread, not exact child emission time.","ABBA shares the same private environment/profile; cache warming and order effects remain.","No speed assertion or causal finding. Effective module paths may differ from requested paths.","Diagnostic does not replace complete portable and replacement production proofs."]}
	var file: FileAccess = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("startup-receipt.json"),FileAccess.WRITE)
	if file == null:
		push_error("Diagnostic receipt unavailable")
		return
	file.store_string(JSON.stringify(receipt))
	file.close()

func _launch(treatment: String) -> Dictionary:
	var root: String = OS.get_environment("SystemRoot")
	var executable: String = root.path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	var requested: String = root.path_join("System32/WindowsPowerShell/v1.0/Modules")
	var result: Dictionary = {"treatment":treatment,"requested_module_path":requested if treatment=="B" else null,"passed":false,"joined":false,"timeout":false,"exit_code":null,"launch_to_entry_ms":null,"launch_to_exit_ms":null,"create_return_ms":null,"stdout":"","stderr":"","metadata":{},"environment_restored":false,"powershell_executable":executable,"powershell_executable_sha256":""}
	if root.is_empty() or not FileAccess.file_exists(executable) or not DirAccess.dir_exists_absolute(requested):
		result.error="builtin_os_dependency_missing"
		return result
	result.powershell_executable_sha256=FileAccess.get_sha256(executable)
	var present: bool = OS.has_environment("PSModulePath")
	var previous: String = OS.get_environment("PSModulePath")
	if treatment=="B": OS.set_environment("PSModulePath",requested)
	else: OS.unset_environment("PSModulePath")
	var encoded: String = Marshalls.raw_to_base64(SCRIPT.to_utf16_buffer())
	var started: int = Time.get_ticks_msec()
	var process: Dictionary = OS.execute_with_pipe(executable,PackedStringArray(["-NoProfile","-NonInteractive","-EncodedCommand",encoded]),true)
	# Restore every modified variable immediately after CreateProcess; the child has
	# its own environment copy. All other cleaned host variables stay untouched.
	if present: OS.set_environment("PSModulePath",previous)
	else: OS.unset_environment("PSModulePath")
	result.environment_restored=OS.has_environment("PSModulePath")==present and OS.get_environment("PSModulePath")==previous
	result.create_return_ms=Time.get_ticks_msec()-started
	if process.is_empty():
		result.error="launch_failed"
		return result
	var stdout_reader: PipeReader = PipeReader.new()
	var stderr_reader: PipeReader = PipeReader.new()
	var stdout_thread: Thread = Thread.new()
	var stderr_thread: Thread = Thread.new()
	var stdout_started: bool = stdout_thread.start(stdout_reader.read.bind(process.stdio,started,true))==OK
	var stderr_started: bool = stderr_thread.start(stderr_reader.read.bind(process.stderr,started,false))==OK
	var killed: bool = false
	if not stdout_started or not stderr_started:
		result.error="reader_start_failed"
		OS.kill(process.pid)
		killed=true
	while OS.is_process_running(process.pid):
		if Time.get_ticks_msec()-started>=60000 and not killed:
			result.timeout=true
			OS.kill(process.pid)
			killed=true
		# A kill request is not join. If exit is not observed, remain alive for the
		# outer120s process-tree watchdog instead of returning an orphan.
		await get_tree().process_frame
	result.exit_code=OS.get_process_exit_code(process.pid)
	result.joined=result.exit_code>=0
	result.launch_to_exit_ms=Time.get_ticks_msec()-started
	# Blocking readers see zero-byte EOF after the child closes its write handles.
	# Do not close a FileAccess concurrently with its reader or Peek at EOF.
	while stdout_thread.is_alive() or stderr_thread.is_alive():
		await get_tree().process_frame
	var out_capture: Dictionary = stdout_thread.wait_to_finish() if stdout_started else {"bytes":PackedByteArray(),"exceeded":false}
	var err_capture: Dictionary = stderr_thread.wait_to_finish() if stderr_started else {"bytes":PackedByteArray(),"exceeded":false}
	result.readers_joined=stdout_started and stderr_started
	result.launch_to_entry_ms=stdout_reader.entry_time()
	if result.launch_to_entry_ms<0: result.launch_to_entry_ms=null
	process.stdio.close()
	process.stderr.close()
	result.stdout=out_capture.bytes.get_string_from_utf8()
	result.stderr=err_capture.bytes.get_string_from_utf8()
	result.output_bound_exceeded=out_capture.exceeded or err_capture.exceeded
	var parsed: Dictionary = _parse(result.stdout)
	result.metadata=parsed
	# Windows PowerShell can emit only its serialization preamble on stderr.
	# Permit that exact bare header; preserve it and reject every other byte/record.
	var stderr_allowed: bool = err_capture.bytes.is_empty() or err_capture.bytes=="#< CLIXML\r\n".to_ascii_buffer()
	result.passed=result.environment_restored and result.joined and result.readers_joined and result.exit_code==0 and not result.timeout and not result.output_bound_exceeded and not result.has("error") and stderr_allowed and parsed.size()==6 and result.launch_to_entry_ms!=null
	return result

static func _parse(output: String) -> Dictionary:
	var rows: PackedStringArray = output.replace("\r\n","\n").strip_edges().split("\n")
	if rows.size()!=7 or rows[0]!="FSPS_ENTRY" or not rows[6].begins_with("FSPS_DONE="): return {}
	var names: Array = ["PSHOME","VERSION","MODULE_PATH","SMOKE","UTILITY_PATH"]
	var metadata: Dictionary = {}
	for i in range(5):
		var prefix: String = names[i]+"="
		if not rows[i+1].begins_with(prefix): return {}
		var encoded: String = rows[i+1].substr(prefix.length())
		var bytes: PackedByteArray = Marshalls.base64_to_raw(encoded)
		if bytes.size()>16384 or Marshalls.raw_to_base64(bytes)!=encoded: return {}
		var value: String = bytes.get_string_from_utf8()
		if value.to_utf8_buffer()!=bytes or value.is_empty(): return {}
		metadata[names[i]]=value
	var inner: String = rows[6].substr(10)
	if inner.is_empty() or inner.length()>12: return {}
	for code in inner.to_ascii_buffer():
		if code<48 or code>57: return {}
	if not metadata.VERSION.begins_with("5.1."): return {}
	metadata.inner_ms=inner.to_int()
	var smoke: Variant = JSON.parse_string(metadata.SMOKE)
	if typeof(smoke)!=TYPE_DICTIONARY or smoke.size()!=2 or smoke.get("probe")!="fixed-read-only" or smoke.get("schema_version")!=1: return {}
	return metadata
