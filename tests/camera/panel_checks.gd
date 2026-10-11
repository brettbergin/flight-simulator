extends RefCounted
# Original MIT. Standalone actual Control checks, not native invariance evidence.
const Page=preload("res://ui/camera/views_panel.gd")
const Checks=preload("res://camera_tests/policy_checks.gd")
var _result: Dictionary
var _host: Node
var _applied: Array=[]
var _canceled: Array=[]

func _check(ok: bool,label: String) -> void:
	Checks.check(_result,ok,label)
	_host.call("check",ok,"camera_panel_"+label)

func _on_apply(settings: Dictionary,session: String) -> void:
	_applied.append({"settings":settings,"session":session})

func _on_cancel(session: String) -> void:
	_canceled.append(session)

static func control(page: Node,name: String) -> Node:
	return page.find_child(name,true,false)

static func choose(page: Node,preset: String) -> void:
	var picker: OptionButton=control(page,"Preset")
	var index: int=Checks.PRESETS.find(preset)
	picker.select(index)
	picker.item_selected.emit(index)

static func edit_fov(page: Node,value: float) -> void:
	var fov: SpinBox=control(page,"Fov")
	fov.value=value

static func response(page: Node,value: String) -> void:
	var picker: OptionButton=control(page,"ExternalResponse")
	var index: int=0 if value=="smooth" else 1
	picker.select(index)
	picker.item_selected.emit(index)

static func press(page: Node,name: String) -> void:
	var button: Button=control(page,name)
	button.pressed.emit()

static func inside_ancestors(item: Control,viewport: Rect2) -> bool:
	var rect: Rect2=item.get_global_rect()
	if rect.size.x<=0.0 or rect.size.y<=0.0 or not viewport.encloses(rect): return false
	var parent: Node=item.get_parent()
	while parent!=null:
		if parent is Control and parent.clip_contents and not parent.get_global_rect().encloses(rect): return false
		parent=parent.get_parent()
	return true

func _pinned_summary(page: Node, viewport: Rect2, label: String) -> void:
	var expected: Dictionary={"ViewsHeading":"VIEWS · FLIGHT PAUSED","CurrentView":"Current view: Left window · FOV 61.5° · immediate response","DraftHint":"Draft only — the camera stays unchanged until Apply. Choices last for this session."}
	for name in expected:
		var item: Label=control(page,name) as Label
		_check(item!=null,label+"_named_label_"+name)
		if item==null: continue
		_check(item.text==expected[name],label+"_truthful_text_"+name)
		_check(item.is_visible_in_tree() and inside_ancestors(item,viewport),label+"_unclipped_label_"+name)
		_check(not item.clip_text and item.lines_skipped==0 and item.max_lines_visible==-1 and item.visible_characters==-1 and item.get_visible_line_count()==item.get_line_count(),label+"_complete_lines_"+name)

func run(host: Node) -> Dictionary:
	_host=host
	_result=Checks.receipt("Standalone Views Control signals, copies, defaults, retirement and layout; no native/scene acceptance")
	var refs: Dictionary=Checks.references(_result)
	if refs.is_empty(): return Checks.finish(_result)
	var parent: Control=Control.new()
	parent.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	parent.size=Vector2(960,540)
	host.add_child(parent)
	var page: Control=Page.new()
	parent.add_child(page)
	page.apply_requested.connect(_on_apply)
	page.cancel_requested.connect(_on_cancel)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var initial: Dictionary=Checks.decode(refs.lifecycle_initial_camera.settings)
	_check(page.open(initial,"camera-reference-session-A"),"valid_open")
	for frame in range(4): await host.get_tree().process_frame
	_check(page.visible and Checks.exact(page.draft(),initial),"L01_initial_owned_draft")
	_check(page.get_cancel_button() is Button and host.get_viewport().gui_get_focus_owner()==page.get_cancel_button(),"L01_initial_focus_cancel")
	for pair in [["Preset","OptionButton"],["Fov","SpinBox"],["ExternalResponse","OptionButton"],["RestoreDefaults","Button"],["Apply","Button"],["Cancel","Button"],["Error","Label"]]:
		var found: Node=control(page,pair[0])
		_check(found!=null and found.is_class(pair[1]),"named_control_"+pair[0])
	if control(page,"Preset")==null or control(page,"Apply")==null:
		page.retire()
		parent.free()
		return Checks.finish(_result)
	var draft: Dictionary=page.draft()
	draft.fov_deg=35.0
	initial.preset="orbit"
	_check(page.draft().preset=="left_window" and Checks.exact(page.draft().fov_deg,61.5),"input_and_returned_draft_do_not_alias")
	initial=Checks.decode(refs.lifecycle_initial_camera.settings)
	for row in refs.mappings:
		choose(page,row.preset)
		_check(page.draft().preset==row.preset and Checks.exact(page.draft().fov_deg,Checks.number(row.default_fov)),"choice_seeds_fov_"+row.preset)
		edit_fov(page,61.5)
		_check(Checks.exact(page.draft().fov_deg,61.5),"explicit_fov_after_choice_"+row.preset)
		choose(page,row.preset)
		_check(Checks.exact(page.draft().fov_deg,61.5),"same_choice_preserves_explicit_fov_"+row.preset)
	response(page,"smooth")
	_check(page.draft().external_response=="smooth" and _applied.is_empty() and _canceled.is_empty(),"editing_does_not_emit")
	var before: Dictionary=page.draft()
	for bad in [null,[],{}, {"preset":"chase","fov_deg":72,"external_response":"smooth"}]:
		_check(not page.open(bad,"camera-reference-session-B") and Checks.exact(page.draft(),before),"invalid_open_preserves_active_draft")
	for bad_session in [null,0,&"camera-reference-session-B",""]:
		_check(not page.open(initial,bad_session) and Checks.exact(page.draft(),before),"invalid_source_preserves_active_draft")
	_check(page.set_error("A bounded visible error") and control(page,"Error").text=="A bounded visible error","visible_error")
	for bad_error in [7,&"wrong type","x".repeat(1025)]:
		_check(not page.set_error(bad_error) and control(page,"Error").text=="A bounded visible error","active_error_rejection")
	choose(page,"right_window")
	edit_fov(page,58.0)
	response(page,"immediate")
	var wanted: Dictionary={"preset":"right_window","fov_deg":58.0,"external_response":"immediate"}
	press(page,"Apply")
	_check(_applied.size()==1 and Checks.exact(_applied[0],{"settings":wanted,"session":"camera-reference-session-A"}),"L05_exact_apply_signal")
	if not _applied.is_empty():
		_applied[0].settings.fov_deg=35.0
		_check(Checks.exact(page.draft(),wanted),"apply_payload_does_not_alias_draft")
	# Scene owns admission and retirement; the standalone receiver does neither.
	page.retire()
	var counts: Vector2i=Vector2i(_applied.size(),_canceled.size())
	press(page,"Apply")
	press(page,"Cancel")
	_check(page.draft()==null and not page.visible and counts==Vector2i(_applied.size(),_canceled.size()),"retired_page_cannot_emit")
	_check(page.open(initial,"camera-reference-session-A"),"reopen_defaults_case")
	press(page,"RestoreDefaults")
	_check(Checks.exact(page.draft(),Checks.decode(refs.defaults.settings)) and counts==Vector2i(_applied.size(),_canceled.size()),"L06_restore_is_draft_only")
	press(page,"Cancel")
	_check(_canceled==["camera-reference-session-A"],"L02_cancel_signal_source")
	page.retire()
	_check(page.open(initial,"camera-reference-session-B"),"reopen_hidden_case")
	page.hide()
	counts=Vector2i(_applied.size(),_canceled.size())
	press(page,"Apply")
	press(page,"Cancel")
	_check(counts==Vector2i(_applied.size(),_canceled.size()),"hidden_page_cannot_emit")
	page.retire()
	var sentinel: Button=Button.new()
	sentinel.text="Separate focus owner"
	parent.add_child(sentinel)
	_check(page.open(initial,"camera-reference-session-retired"),"focus_retirement_setup")
	page.retire()
	sentinel.grab_focus()
	for frame in range(4): await host.get_tree().process_frame
	_check(host.get_viewport().gui_get_focus_owner()==sentinel,"retired_queued_focus_cannot_steal")
	sentinel.free()
	for dimension in [Vector2(960,540),Vector2(1360,768),Vector2(1920,1080),Vector2(2560,1440)]:
		parent.size=dimension
		_check(page.open(initial,"camera-reference-session-layout"),"layout_open_"+str(dimension))
		for frame in range(4): await host.get_tree().process_frame
		_check(inside_ancestors(page.get_cancel_button(),Rect2(parent.global_position,dimension)),"initial_cancel_not_clipped_"+str(dimension))
		_pinned_summary(page,Rect2(parent.global_position,dimension),"initial_cancel_"+str(dimension))
		for name in ["Preset","Fov","ExternalResponse","RestoreDefaults","Apply","Cancel"]:
			var item: Control=control(page,name)
			var focus_item: Control=item.get_line_edit() if item is SpinBox else item
			focus_item.grab_focus()
			for frame in range(4): await host.get_tree().process_frame
			_check(item.visible and focus_item.focus_mode!=Control.FOCUS_NONE and host.get_viewport().gui_get_focus_owner()==focus_item and inside_ancestors(focus_item,Rect2(parent.global_position,dimension)),"layout_focus_and_ancestors_"+str(dimension)+"_"+name)
			_pinned_summary(page,Rect2(parent.global_position,dimension),"focused_"+name+"_"+str(dimension))
		page.focus_cancel()
		for frame in range(4): await host.get_tree().process_frame
		_check(host.get_viewport().gui_get_focus_owner()==page.get_cancel_button(),"layout_cancel_focus_"+str(dimension))
		_pinned_summary(page,Rect2(parent.global_position,dimension),"returned_cancel_"+str(dimension))
		page.retire()
	_check(not page.set_error(7) and not page.set_error(&"wrong type"),"error_rejects_non_string")
	parent.free()
	return Checks.finish(_result)
