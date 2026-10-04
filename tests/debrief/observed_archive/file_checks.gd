extends RefCounted
# Original MIT. Actual selected-file tests in a fresh disposable project folder.
# No native/game state. Scope explicitly distinguishes unsupported platforms.
const ArchiveFiles = preload("res://replay/observed_archive/files.gd")
const ArchiveChecks = preload("res://observed_archive_tests/archive_checks.gd")
const REF: String = "res://observed_archive_tests/reference/"
var _root: String = ""
var _race_bytes := "independent competing target; preserve exactly".to_utf8_buffer()

static func _check(r: Dictionary, condition: bool, label: String) -> void:
	r.checks += 1
	if not condition:
		r.failures.append(label)

static func _receipt(r: Dictionary, v: Variant, success: bool, state: String, label: String) -> void:
	var closed: bool = ArchiveChecks._keys(v, ["ok","error","state","path","temp_path","value","payload_sha256"])
	_check(r, closed, label + ":closed-result")
	if not closed:
		return
	_check(r, typeof(v.ok) == TYPE_BOOL and v.ok == success and typeof(v.state) == TYPE_STRING and v.state == state, label + ":outcome")
	_check(r, typeof(v.error) == TYPE_STRING and v.error.length() <= 1024 and typeof(v.path) == TYPE_STRING, label + ":owned-types")
	if success:
		_check(r, v.error == "" and v.temp_path == null and typeof(v.payload_sha256) == TYPE_STRING and v.payload_sha256.length() == 64, label + ":success")
	else:
		_check(r, v.error != "" and v.value == null and v.payload_sha256 == null, label + ":no-partial-value")
	_check(r, v.temp_path == null or typeof(v.temp_path) == TYPE_STRING, label + ":recovery-path-type")

static func _write(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var written: bool = file.store_buffer(bytes)
	file.close()
	return written

static func _retired(r: Dictionary, leaf: RefCounted, label: String) -> void:
	_check(r, leaf._last_pid > 0 and not OS.is_process_running(leaf._last_pid) and OS.get_process_exit_code(leaf._last_pid) >= 0, label + ":actual-helper-exit-observed")

func _race(target: String, _temporary: String) -> void:
	_write(target, _race_bytes)

static func _stage(boundary: String, label: String) -> void:
	# Fixed test labels only; no selected path, recording or aircraft state.
	print("PROOF_STAGE " + boundary + " archive.files." + label + " ms=" + str(Time.get_ticks_msec()))

static func _open(leaf: RefCounted, path: Variant, label: String) -> Dictionary:
	_stage("begin",label)
	var result: Dictionary = leaf.open(path)
	_stage("end",label)
	return result

static func _save(leaf: RefCounted, path: Variant, bytes: Variant, label: String) -> Dictionary:
	_stage("begin",label)
	var result: Dictionary = leaf.save_new(path,bytes)
	_stage("end",label)
	return result

func _fixture(mode: String, asynchronous: bool = false) -> Dictionary:
	_stage("begin","fixture."+mode)
	var executable: String = OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	var source: String = FileAccess.get_file_as_string("res://observed_archive_tests/windows_fixture.ps1")
	var data: String = Marshalls.raw_to_base64(JSON.stringify({"root":_root,"mode":mode}).to_utf8_buffer())
	# Trusted script only; JSON/data is base64 alphabet, never executable path text.
	var command: String = "$env:FS_ARCHIVE_TEST_DATA='" + data + "'\n" + source
	var args := PackedStringArray(["-NoProfile","-NonInteractive","-EncodedCommand",Marshalls.raw_to_base64(command.to_utf16_buffer())])
	if asynchronous:
		var pid: int = OS.create_process(executable,args,false)
		_stage("end","fixture."+mode)
		return {"pid":pid}
	var output: Array = []
	var exit_code: int = OS.execute(executable,args,output,true,false)
	_stage("end","fixture."+mode)
	return {"exit":exit_code,"output":"".join(output)}

static func _wait_marker(path: String, milliseconds: int = 5000) -> bool:
	var end: int = Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < end:
		if FileAccess.file_exists(path):
			return true
		OS.delay_msec(10)
	return false

static func _foreign(leaf: RefCounted, path: String, bytes: PackedByteArray) -> Dictionary:
	return {"open":leaf.open(path), "save":leaf.save_new(path, bytes)}

func run() -> Dictionary:
	var r := {"checks":0,"failures":[],"passed":false,"scope":"Windows local NTFS actual exclusive new-file/flush/verified-open/collision/fault/thread proof; synthetic disposable files only"}
	var bytes := FileAccess.get_file_as_bytes(REF + "minimal.fsreview.json")
	var leaf := ArchiveFiles.new()
	for bad in [null, 1, StringName("C:/not-selected.json"), "res://not-selected.json", "user://not-selected.json", "relative.json", "\\\\server\\share\\review.json"]:
		_receipt(r, leaf.open(bad), false, "rejected", "bad-open-path")
		_receipt(r, leaf.save_new(bad, bytes), false, "rejected", "bad-save-path")
	_check(r, leaf._last_pid == 0, "path-refusals-no-child")
	if OS.get_name() != "Windows":
		_receipt(r, leaf.save_new("C:/no-write.json", bytes), false, "rejected", "unsupported-platform")
		r.scope = "Non-Windows truthful unsupported selected Windows file capability and path/type refusals only; no NTFS/IO durability claim"
		r.passed = r.failures.is_empty()
		return r
	var parent: String = OS.get_cache_dir().replace("\\", "/").simplify_path().trim_suffix("/")
	_root = parent.path_join(".observed-archive-test-" + Crypto.new().generate_random_bytes(16).hex_encode())
	_check(r, _root.begins_with(parent + "/") and _root.get_file().begins_with(".observed-archive-test-"), "disposable-root-contained")
	_check(r, DirAccess.make_dir_absolute(_root) == OK, "disposable-root-create")
	if not DirAccess.dir_exists_absolute(_root):
		return r
	var target: String = _root.path_join("review space \u03a9.json")
	var saved: Dictionary = _save(leaf,target,bytes,"save-target")
	_receipt(r, saved, true, "saved", "actual-new-file")
	_retired(r, leaf, "actual-new-file")
	_check(r, FileAccess.get_file_as_bytes(target) == bytes and saved.value == null, "new-file-exact-bytes")
	var opened: Dictionary = _open(leaf,target,"open-target")
	_receipt(r, opened, true, "opened", "actual-open")
	_retired(r, leaf, "actual-open")
	if opened.ok:
		var outer: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
		ArchiveChecks._compare(r, opened.value, ArchiveChecks._restore_reference(JSON.parse_string(outer.payload_json)), "actual-open-exact-types-bits")
		opened.value.samples[0].held_axes.roll = 0.8
		var again: Dictionary = _open(leaf,target,"open-target")
		_check(r, again.ok and again.value.samples[0].held_axes.roll == 0.0, "actual-open-owned-copies")
	var collision: Dictionary = _save(leaf,target,bytes,"save-target")
	_receipt(r, collision, false, "rejected", "existing-target")
	_retired(r, leaf, "existing-target")
	_check(r, FileAccess.get_file_as_bytes(target) == bytes, "existing-target-unchanged")
	var malformed: String = _root.path_join("malformed.json")
	_check(r, _write(malformed, "{}".to_utf8_buffer()), "malformed-fixture-write")
	_receipt(r, _open(leaf,malformed,"malformed"), false, "rejected", "malformed-open")
	_retired(r, leaf, "malformed-open")
	_check(r, FileAccess.get_file_as_bytes(malformed) == "{}".to_utf8_buffer(), "malformed-unchanged")
	_receipt(r, _open(leaf,_root.path_join("missing.json"),"missing"), false, "rejected", "missing-open")
	_retired(r, leaf, "missing-open")
	_receipt(r, _save(leaf,_root,bytes,"directory"), false, "rejected", "directory-target")
	_retired(r, leaf, "directory-target")
	_receipt(r, _save(leaf,_root.path_join("review.json:stream"),bytes,"ads"), false, "rejected", "alternate-stream")
	_retired(r, leaf, "alternate-stream")
	var invalid_leaf := ArchiveFiles.new()
	var invalid_target: String = _root.path_join("never-written.json")
	_receipt(r, _save(invalid_leaf,invalid_target,"{}".to_utf8_buffer(),"invalid-bytes"), false, "rejected", "invalid-bytes-before-files")
	_check(r, invalid_leaf._last_pid == 0 and not FileAccess.file_exists(invalid_target), "invalid-bytes-no-child-no-create")
	var thread := Thread.new()
	var thread_leaf := ArchiveFiles.new()
	_check(r, thread.start(_foreign.bind(thread_leaf, target, bytes)) == OK, "foreign-thread-start")
	var alien: Variant = thread.wait_to_finish()
	_check(r, alien is Dictionary, "foreign-thread-owned-result")
	if alien is Dictionary:
		for method in ["open","save"]:
			_receipt(r, alien[method], false, "rejected", "foreign-" + method)
			_check(r, alien[method].path == "" and alien[method].temp_path == null, "foreign-empty-path-before-owner-access")
	_check(r, thread_leaf._last_pid == 0 and FileAccess.get_file_as_bytes(target) == bytes, "foreign-no-process-no-mutation")
	var locked_path: String = _root.path_join("locked.json")
	_check(r, _write(locked_path,bytes), "actual-share-lock-fixture")
	var locker: Dictionary = _fixture("lock",true)
	var lock_pid: int = locker.pid
	_check(r, lock_pid > 0 and _wait_marker(_root.path_join("lock-ready")), "actual-share-lock-acquired")
	if lock_pid > 0 and FileAccess.file_exists(_root.path_join("lock-ready")):
		_receipt(r, _open(leaf,locked_path,"share-locked"),false,"rejected","actual-share-locked-open")
		_retired(r,leaf,"actual-share-locked-open")
	_check(r, _write(_root.path_join("lock-release"),"RELEASE".to_utf8_buffer()), "actual-share-lock-release-request")
	_check(r, _wait_marker(_root.path_join("lock-closed")), "actual-share-lock-disposed-marker")
	var lock_deadline: int = Time.get_ticks_msec() + 5000
	while lock_pid > 0 and OS.is_process_running(lock_pid) and Time.get_ticks_msec() < lock_deadline:
		OS.delay_msec(10)
	var lock_joined: bool = lock_pid > 0 and not OS.is_process_running(lock_pid)
	_check(r, lock_joined and OS.get_process_exit_code(lock_pid) == 0, "actual-share-lock-child-retired")
	if lock_pid > 0 and not lock_joined:
		# Only this driver-created child; timeout still fails and is never a join.
		OS.kill(lock_pid)
	_check(r, FileAccess.get_file_as_bytes(locked_path) == bytes, "locked-file-unchanged")
	var junction: Dictionary = _fixture("junction-create")
	_check(r, junction.exit == 0 and junction.output.contains("JUNCTION_READY"), "actual-junction-created")
	if junction.exit == 0:
		var junction_path: String = _root.path_join("junction-link/refused.json")
		_receipt(r,_save(leaf,junction_path,bytes,"reparse"),false,"rejected","actual-reparse-parent-refused")
		_retired(r,leaf,"actual-reparse-parent-refused")
		_check(r, not FileAccess.file_exists(_root.path_join("junction-real/refused.json")), "actual-reparse-no-write")
		var removed: Dictionary = _fixture("junction-remove")
		_check(r, removed.exit == 0 and removed.output.contains("JUNCTION_REMOVED"), "actual-junction-only-link-removed")
	var primitive: Dictionary = _fixture("move-collision")
	_check(r, primitive.exit == 0 and primitive.output.contains("MOVE_REFUSED_BYTES_UNCHANGED"), "actual-dotnet-move-no-overwrite-primitive")
	var temp_leaf := ArchiveFiles.new()
	temp_leaf._temporary_name = ".fsreview-" + "a".repeat(32) + ".tmp"
	var temp_collision: String = _root.path_join(temp_leaf._temporary_name)
	_check(r, _write(temp_collision, _race_bytes), "temp-collision-fixture")
	var temp_target: String = _root.path_join("temporary-collision.json")
	_receipt(r, _save(temp_leaf,temp_target,bytes,"temporary-collision"), false, "rejected", "exclusive-temp-collision")
	_retired(r, temp_leaf, "exclusive-temp-collision")
	_check(r, FileAccess.get_file_as_bytes(temp_collision) == _race_bytes and not FileAccess.file_exists(temp_target), "temp-collision-not-truncated")
	var race_leaf := ArchiveFiles.new()
	race_leaf._before_commit = _race
	var race_target: String = _root.path_join("racing-target.json")
	var raced: Dictionary = _save(race_leaf,race_target,bytes,"target-race")
	_receipt(r, raced, false, "not_saved", "target-creation-race")
	_retired(r, race_leaf, "target-creation-race")
	_check(r, FileAccess.get_file_as_bytes(race_target) == _race_bytes, "racing-target-preserved")
	_check(r, typeof(raced.temp_path) == TYPE_STRING and FileAccess.get_file_as_bytes(raced.temp_path) == bytes, "racing-temp-retained")
	for phase in ["write","flush","move","receipt","post_verify","truncate_request","excess_request"]:
		var fault_leaf := ArchiveFiles.new()
		fault_leaf._fault = phase
		var fault_target: String = _root.path_join("fault-" + phase + ".json")
		var result: Dictionary = _save(fault_leaf,fault_target,bytes,"fault."+phase)
		var installed: bool = phase in ["receipt","post_verify"]
		_receipt(r, result, false, "recovery_required" if installed else "not_saved", "fault-" + phase)
		_retired(r, fault_leaf, "fault-" + phase)
		if installed:
			_check(r, FileAccess.get_file_as_bytes(fault_target) == bytes and result.temp_path == null, "post-install-target-retained-no-invented-temp-" + phase)
		else:
			_check(r, not FileAccess.file_exists(fault_target) and typeof(result.temp_path) == TYPE_STRING and FileAccess.file_exists(result.temp_path), "pre-install-temp-retained-" + phase)
	var dense_bytes := FileAccess.get_file_as_bytes(REF + "dense-2401.fsreview.json")
	var dense_target: String = _root.path_join("dense2401.json")
	_receipt(r, _save(leaf,dense_target,dense_bytes,"dense-save"), true, "saved", "dense-file-save")
	_retired(r, leaf, "dense-file-save")
	var dense_open: Dictionary = _open(leaf,dense_target,"dense-open")
	_receipt(r, dense_open, true, "opened", "dense-file-open")
	_retired(r, leaf, "dense-file-open")
	if dense_open.ok:
		var outer: Dictionary = JSON.parse_string(dense_bytes.get_string_from_utf8())
		ArchiveChecks._compare(r, dense_open.value, ArchiveChecks._restore_reference(JSON.parse_string(outer.payload_json)), "dense-actual-file-all2401-types-bits")
	_stage("begin","cleanup")
	_cleanup(r)
	_stage("end","cleanup")
	r.passed = r.failures.is_empty()
	return r

func _cleanup(r: Dictionary) -> void:
	# Only direct files in the fresh nonce directory. Never recurse/follow links.
	var parent: String = OS.get_cache_dir().replace("\\", "/").simplify_path().trim_suffix("/")
	_check(r, _root.get_base_dir() == parent and _root.get_file().begins_with(".observed-archive-test-"), "cleanup-contained")
	if _root.get_base_dir() != parent or not _root.get_file().begins_with(".observed-archive-test-"):
		return
	var directory := DirAccess.open(_root)
	if directory == null:
		return
	for filename in directory.get_files():
		var path: String = _root.path_join(filename)
		_check(r, not directory.is_link(filename) and path.get_base_dir() == _root, "cleanup-ordinary-direct-file")
		if not directory.is_link(filename) and path.get_base_dir() == _root:
			_check(r, DirAccess.remove_absolute(path) == OK, "cleanup-owned-file")
	_check(r, directory.get_directories().is_empty(), "cleanup-no-unowned-directories")
	directory = null
	_check(r, DirAccess.remove_absolute(_root) == OK, "cleanup-owned-root")
