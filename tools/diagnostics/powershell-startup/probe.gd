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
	var receipt: Dictionary = {"schema_version":1,"passed":passed,"observations":observations,"failures":failures,"order":["A","B","B","A"],"limitations":["Entry time is host-observed with frame polling, not exact child emission time.","ABBA shares the same private environment/profile; cache warming and order effects remain.","No speed assertion or causal finding. Effective module paths may differ from requested paths.","Diagnostic does not replace complete portable and replacement production proofs."]}
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
	var output: PackedByteArray = PackedByteArray()
	var errors: PackedByteArray = PackedByteArray()
	var killed: bool = false
	var observed_exit: bool = false
	while true:
		for pair in [[process.stdio,output],[process.stderr,errors]]:
			var pipe: FileAccess = pair[0]
			var bytes: PackedByteArray = pair[1]
			var available: int = pipe.get_length()
			if available>0:
				if bytes.size()+available>8192:
					result.error="output_bound"
					if not killed: OS.kill(process.pid); killed=true
					# Never consume unbounded output or treat a kill request as join.
				else:
					bytes.append_array(pipe.get_buffer(available))
				if pipe==process.stdio: output=bytes
				else: errors=bytes
		if result.launch_to_entry_ms==null and "FSPS_ENTRY\r\n" in output.get_string_from_utf8():
			result.launch_to_entry_ms=Time.get_ticks_msec()-started
		# Drain once more after the exit observation: DONE might have arrived
		# between the previous PeekNamedPipe and GetExitCodeProcess checks.
		if observed_exit: break
		if not OS.is_process_running(process.pid):
			result.exit_code=OS.get_process_exit_code(process.pid)
			result.joined=result.exit_code>=0
			result.launch_to_exit_ms=Time.get_ticks_msec()-started
			observed_exit=true
			continue
		if Time.get_ticks_msec()-started>=60000 and not killed:
			result.timeout=true
			OS.kill(process.pid)
			killed=true
		# If termination is not observed, remain alive for the outer120s process-tree
		# watchdog; never return an orphan or claim kill==join. Both streams drained.
		await get_tree().process_frame
	process.stdio.close()
	process.stderr.close()
	result.stdout=output.get_string_from_utf8()
	result.stderr=errors.get_string_from_utf8()
	var parsed: Dictionary = _parse(result.stdout)
	result.metadata=parsed
	result.passed=result.environment_restored and result.joined and result.exit_code==0 and not result.timeout and not result.has("error") and errors.is_empty() and parsed.size()==6 and result.launch_to_entry_ms!=null
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
