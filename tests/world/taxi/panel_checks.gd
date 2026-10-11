extends RefCounted
# Original MIT. Actual Control interactions over EXPLICIT synthetic presentation
# views only. This does not prove native pause, Scene stale tokens or movement.
const Page = preload("res://ui/taxi/taxi_panel.gd")
const Layout = preload("res://world/taxi/taxi_layout.gd")
const Checks = preload("res://taxi_tests/layout_checks.gd")
var _events: Array = []

func _route(id: String, session: String) -> void:
	_events.append({"kind":"route","id":id,"session":session})
func _next(session: String) -> void:
	_events.append({"kind":"next","session":session})
func _stop(session: String) -> void:
	_events.append({"kind":"stop","session":session})
func _aids(value: bool, session: String) -> void:
	_events.append({"kind":"aids","value":value,"session":session})
func _dismiss(session: String) -> void:
	_events.append({"kind":"dismiss","session":session})

static func _inside(item: Control, viewport: Rect2) -> bool:
	if not item.is_visible_in_tree() or not viewport.encloses(item.get_global_rect()) or item.size.x<=0.0 or item.size.y<=0.0: return false
	var parent: Node = item.get_parent()
	while parent!=null:
		if parent is Control and parent.clip_contents and not parent.get_global_rect().encloses(item.get_global_rect()): return false
		parent=parent.get_parent()
	return true

static func _foreign(page: Control, layout: Dictionary, view: Dictionary) -> Dictionary:
	var result: Dictionary = {"open":page.open(layout,view,"synthetic-panel-only"),"present":page.present(view),"draft":page.draft(),"back":page.get_back_button()}
	page.retire()
	return result

static func _view(layout: Dictionary) -> Dictionary:
	# Independent hand-authored closed presentation fixture. A page does not
	# qualify native source; Root supplies that in real Scene integration tests.
	var itinerary: Dictionary = layout.itineraries[1]
	return {"layout_id":"original-taxi-navigation","layout_revision":1,"state":"active",
		"session_id":"synthetic-panel-only","tick":"0","qualified":true,"paused":true,"historical":false,
		"itinerary_id":"outbound-36","itinerary_label":"To south stop - runway 36","runway":36,
		"point_index":0,"point_count":5,"target_id":"outbound-36-p1",
		"target_label":"To south stop - runway 36 reference 1","target_eus_m":[108.0,0.0,18.0],
		"points":itinerary.points.duplicate(true),"planar_range_m":0.0,"anchor_bearing_deg":null,
		"available":true,"aids_visible":true,"error":""}

func run(host: Node) -> Dictionary:
	_events=[]
	var result: Dictionary = Checks.receipt("Actual Taxi page layout/signals/copies/retirement over labeled synthetic presentation views; no native/Scene/clearance or flight journey proof")
	var loaded: Dictionary = Layout.load()
	Checks.check(result,loaded.ok,"panel_fixed_layout_available")
	if not loaded.ok: return result
	var before_layout: Dictionary = loaded.value.duplicate(true)
	var view: Dictionary = _view(loaded.value)
	var original_view: Dictionary = view.duplicate(true)
	var parent := Control.new()
	parent.size=Vector2(960,540)
	host.add_child(parent)
	var page := Page.new()
	parent.add_child(page)
	page.route_requested.connect(_route)
	page.next_requested.connect(_next)
	page.stop_requested.connect(_stop)
	page.aids_requested.connect(_aids)
	page.dismissed.connect(_dismiss)
	await host.get_tree().process_frame
	var picker: OptionButton = page.find_child("Itinerary",true,false)
	var begin: Button = page.find_child("BeginItinerary",true,false)
	var next_button: Button = page.find_child("NextPoint",true,false)
	var stop: Button = page.find_child("StopItinerary",true,false)
	var aids: CheckBox = page.find_child("ShowAids",true,false)
	var back: Button = page.get_back_button()
	Checks.check(result,picker!=null and begin!=null and next_button!=null and stop!=null and aids!=null and back!=null,"stable_six_controls")
	if picker==null or begin==null or next_button==null or stop==null or aids==null or back==null:
		parent.queue_free()
		await host.get_tree().process_frame
		return result
	for size in [Vector2(960,540),Vector2(1360,768),Vector2(1920,1080),Vector2(2560,1440)]:
		parent.size=size
		Checks.check(result,page.open(loaded.value,view,"synthetic-panel-only"),"valid_copied_open_"+str(size))
		for frame in 4: await host.get_tree().process_frame
		var viewport := Rect2(parent.global_position,size)
		Checks.check(result,page.get_viewport().gui_get_focus_owner()==back,"default_Back_focus_"+str(size))
		for control in [picker,begin,next_button,stop,aids,back]:
			control.grab_focus()
			await host.get_tree().process_frame
			Checks.check(result,_inside(control,viewport) and control.has_focus() and control.focus_next!=NodePath() and control.focus_previous!=NodePath(),"visible_cyclic_focus_"+str(size)+control.name)
		for node_name in ["TaxiHeading","TaxiSummary","TaxiHint"]:
			var label: Label = page.find_child(node_name,true,false)
			Checks.check(result,label!=null and _inside(label,viewport) and not label.clip_text and label.lines_skipped==0 and label.max_lines_visible==-1 and label.visible_characters==-1 and label.get_visible_line_count()==label.get_line_count(),"full_unclipped_text_"+str(size)+node_name)
		page.focus_back()
		Checks.check(result,back.has_focus(),"Back_focus_returns_"+str(size))
		Checks.check(result,page.find_child("TaxiHeading",true,false).text.contains("SYNTHETIC") and page.find_child("TaxiHint",true,false).text.contains("clearance"),"honest_synthetic_manual_labels")
	Checks.check(result,_events.is_empty(),"open_focus_and_present_emit_nothing")
	var draft: Dictionary = page.draft()
	draft.itinerary_id="caller mutation"
	Checks.check(result,page.draft()=={"itinerary_id":"outbound-36"},"owned_draft_copy")
	picker.select(2)
	picker.item_selected.emit(2)
	Checks.check(result,page.draft()=={"itinerary_id":"outbound-18"} and _events.is_empty(),"selection_is_draft_only")
	begin.pressed.emit()
	next_button.pressed.emit()
	stop.pressed.emit()
	aids.button_pressed=false
	back.pressed.emit()
	Checks.check(result,_events==[{"kind":"route","id":"outbound-18","session":"synthetic-panel-only"},{"kind":"next","session":"synthetic-panel-only"},{"kind":"stop","session":"synthetic-panel-only"},{"kind":"aids","value":false,"session":"synthetic-panel-only"},{"kind":"dismiss","session":"synthetic-panel-only"}],"exact_signals_without_adoption_or_hiding")
	var event_count: int = _events.size()
	var copied_draft: Dictionary = page.draft()
	back.grab_focus()
	Checks.check(result,page.present(view) and back.has_focus() and page.draft()==copied_draft and _events.size()==event_count,"present_preserves_draft_focus_and_no_signal")
	var bad: Dictionary = view.duplicate(true)
	bad.extra=true
	Checks.check(result,not page.open(loaded.value,bad,"synthetic-panel-only") and page.draft()==copied_draft and back.has_focus(),"invalid_open_preserves_existing_draft")
	Checks.check(result,not page.present(bad) and begin.disabled and next_button.disabled and stop.disabled and aids.disabled and not back.disabled,"malformed_present_disables_only_mutations")
	Checks.check(result,page.find_child("TaxiSummary",true,false).text=="No current taxi guidance" and page.draft()==copied_draft,"malformed_present_clears_numbers_retains_draft")
	begin.pressed.emit()
	next_button.pressed.emit()
	stop.pressed.emit()
	aids.toggled.emit(true)
	Checks.check(result,_events.size()==event_count,"disabled_mutations_cannot_emit_even_direct_signal")
	Checks.check(result,page.present(view),"valid_present_recovers_guidance")
	var foreign: Dictionary = view.duplicate(true)
	foreign.session_id="synthetic-other-panel-session"
	Checks.check(result,not page.present(foreign) and begin.disabled and page.draft()==copied_draft,"foreign_session_never_rebinds_opening")
	Checks.check(result,page.present(view),"original_session_presentation_restored")
	var unavailable: Dictionary = view.duplicate(true)
	unavailable.qualified=false
	unavailable.paused=false
	unavailable.session_id=null
	unavailable.tick=null
	unavailable.available=false
	unavailable.target_id=null
	unavailable.target_label=null
	unavailable.target_eus_m=null
	unavailable.points=[]
	unavailable.planar_range_m=null
	unavailable.anchor_bearing_deg=null
	unavailable.error="source_unqualified"
	Checks.check(result,page.present(unavailable) and begin.disabled and page.find_child("TaxiSummary",true,false).text=="No current taxi guidance","unavailable_view_no_stale_guidance")
	Checks.check(result,page.present(view),"same_session_recovery_before_retire")
	var before_foreign: Dictionary = page.draft()
	var thread := Thread.new()
	Checks.check(result,thread.start(_foreign.bind(page,loaded.value.duplicate(true),view.duplicate(true)))==OK,"panel_foreign_thread_started")
	if thread.is_started():
		var refused: Dictionary = thread.wait_to_finish()
		Checks.check(result,refused=={"open":false,"present":false,"draft":null,"back":null} and page.draft()==before_foreign and page.visible,"foreign_methods_do_not_read_or_retire_owner_page")
	var ended: Dictionary = view.duplicate(true)
	ended.state="manual-ended"
	ended.point_index=4
	for key in ["target_id","target_label","target_eus_m","planar_range_m","anchor_bearing_deg"]: ended[key]=null
	ended.points=[]
	ended.available=false
	Checks.check(result,page.present(ended) and page.find_child("TaxiSummary",true,false).text.contains("manual itinerary ended") and next_button.disabled and stop.disabled,"ended_is_manual_not_arrival_or_clearance")
	page.retire()
	Checks.check(result,page.draft()==null and not page.visible,"retire_clears_and_hides")
	begin.pressed.emit()
	back.pressed.emit()
	Checks.check(result,_events.size()==event_count,"retired_controls_cannot_emit")
	Checks.check(result,page.open(loaded.value,view,"synthetic-panel-only"),"same_session_new_opening")
	page.hide()
	Checks.check(result,page.draft()==null and not page.present(view),"external_hide_invalidates_opening")
	for frame in 4: await host.get_tree().process_frame
	Checks.check(result,_events.size()==event_count,"retired_hidden_controls_no_delayed_emission")
	Checks.check(result,loaded.value==before_layout and view==original_view,"all_input_children_unchanged")
	parent.queue_free()
	await host.get_tree().process_frame
	return result
