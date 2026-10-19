extends SceneTree
const Worlds=preload("res://world/world_admission.gd")
var checks: int=0
var failures: Array=[]
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures.append(label)
func _initialize() -> void:
	var legacy: String="original-interactive-prototype"
	var piston: String="original-piston-prop-v1"
	for profile in [legacy,piston]:
		for start in (["ground-ready","airborne-prepared","apron-ready"] if profile==legacy else ["piston-cold-ground","piston-cold-apron"]):
			var selected: Dictionary=Worlds.selection("original-synthetic",profile,start,"calm")
			check(selected.ok,"old closed selection")
			if not selected.ok: continue
			var entry: Dictionary=selected.entry
			var negative: float="0000000000000080".hex_decode().decode_double(0)
			entry.world_anchor.ellipsoid_height_m=negative
			var relation: Dictionary=Worlds.source(entry.model_identity,start,entry.world.sha256,entry.world_anchor)
			check(relation.ok and relation.recording_version==(1 if profile==legacy else 2),"old signed-zero anchor preserved")
	var selected: Dictionary=Worlds.selection("kawo-prototype-v1",legacy,"ground-ready","calm")
	check(selected.ok,"KAWO closed selection")
	if selected.ok:
		var entry: Dictionary=selected.entry
		check(Worlds.source(entry.model_identity,entry.named_start,entry.files[0].sha256,entry.world_anchor).recording_version==3,"full geographic tuple")
		entry.world_anchor.ellipsoid_height_m="0000000000000080".hex_decode().decode_double(0)
		check(not Worlds.source(entry.model_identity,entry.named_start,entry.files[0].sha256,entry.world_anchor).ok,"geographic signed-zero mismatch refused")
		entry.files[0].sha256="f".repeat(64)
		check(Worlds.selection("kawo-prototype-v1",legacy,"ground-ready","calm").entry.files[0].sha256=="b2c53308fdc427900d84b541aff51ba66cbb71bc483fcee0ea16d067dbd15cfb","returned catalog deep copy")
	for selector in [null,true,1,StringName("kawo-prototype-v1"),"other"]:
		check(not Worlds.selection(selector,legacy,"ground-ready","calm").ok,"actual selector type")
	for tuple in [[piston,"ground-ready","calm"],[legacy,"airborne-prepared","calm"],[legacy,"apron-ready","calm"],[legacy,"ground-ready","from-west"]]:
		check(not Worlds.selection("kawo-prototype-v1",tuple[0],tuple[1],tuple[2]).ok,"crossed geographic tuple")
	print(JSON.stringify({"checks":checks,"failures":failures,"scope":"registry source/selection only; no native authority"}))
	quit(0 if failures.is_empty() else 1)
