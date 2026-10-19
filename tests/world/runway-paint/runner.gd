extends Node
# Original MIT. The ordinary root proof route enters before flight/storage.
const Checks=preload("res://runway_paint_tests/checks.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var mode: String=""
	if args.size()==1:
		if args[0]=="--runway-paint-geometry-checks": mode="geometry"
		elif args[0]=="--runway-paint-material-checks": mode="material"
	# A fresh instance preserves the suite's original explicit-mode refusal.
	var result: Dictionary=Checks.new().run(mode)
	print("KAWO_RUNWAY_PAINT_RESULT="+JSON.stringify(result))
	var good: bool=not mode.is_empty() and result.mode==mode and result.failures.is_empty()
	good=good and result.groups.geometry.checks==132 and result.groups.geometry.failures.is_empty()
	good=good and result.groups.material.failures.is_empty() and not result.shader_pixel_cases_exercised and not result.native_flight_exercised
	if mode=="geometry":
		good=good and result.checks==132 and result.groups.material.checks==0 and not result.material_readback_exercised
	elif mode=="material":
		good=good and result.checks==156 and result.groups.material.checks==24 and result.material_readback_exercised
	get_tree().quit(0 if good else 1)
