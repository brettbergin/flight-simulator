extends RefCounted
# Original MIT. Pure display checks, independent authored rational fit examples.
# Fit cases frozen in engineering packet vectors.json SHA6b85f145645d166766d569e00156d93ef8e367b7f27ffc9d78a8cefcd77e86be before consumers;
# literal rational coordinates below are not fitted to observed drawing output.
const Geometry = preload("res://world/synthetic/circuit_geometry.gd")
const Card = preload("res://ui/first_flight/circuit_guide.gd")
const Sources = preload("res://world_tests/synthetic/circuit_checks.gd")
var checks: int = 0
var failures: Array[String] = []

static func run() -> Dictionary:
	return new()._run()

func _check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label)

func _inside(point: Vector2, rect: Rect2) -> bool:
	return point.x>=rect.position.x and point.x<=rect.end.x and point.y>=rect.position.y and point.y<=rect.end.y

func _clear(card: Control, label: String) -> void:
	_check(not card._view.available and card._view.session_id==null and card._view.tick==null and card._view.ownship_anchor_eus_m==null,label+"_no_identity_ownship")
	_check(card._view.points_anchor_eus_m.is_empty() and card._view.leg_labels.is_empty(),label+"_no_diagram")
	for item in card._labels: _check(not item.visible and item.text.is_empty(),label+"_empty_label")
	_check(card._reason.visible and not card._reason.text.is_empty(),label+"_visible_reason")

func _run() -> Dictionary:
	var base: Dictionary=Sources.captured_readback()
	_check(not base.is_empty(),"approved_original_fixture")
	if base.is_empty(): return _result()
	var view: Dictionary=Geometry.view(base,"calm",36)
	_check(view.available,"qualified_available_view")
	if not view.available: return _result()
	var card := Card.new()
	_check(card.custom_minimum_size==Vector2(280,300),"narrow_card_minimum")
	_check(card.mouse_filter==Control.MOUSE_FILTER_IGNORE,"card_never_intercepts_live_mouse")
	_check(card.has_signal("enabled_requested"),"paused_chooser_signal_seam")
	for child in card.get_children():
		_check(child is Label and child.mouse_filter==Control.MOUSE_FILTER_IGNORE,"no_live_clickable_children")
	var signals_seen: Array=[0]
	card.enabled_requested.connect(func(_enabled: bool,_session: String): signals_seen[0]+=1)
	var snapshot: Dictionary=view.duplicate(true)
	card.set_state(view,true)
	view.points_anchor_eus_m[0][0]=111; view.leg_labels[0]="mutated"; view.ownship_anchor_eus_m[0]=222
	_check(card._view==snapshot,"set_state_recursively_owns_input")
	_check(card._title.text=="OPTIONAL SYNTHETIC CIRCUIT REFERENCE · not evaluated","persistent_optional_not_evaluated")
	_check(card._caption.text=="Fixed schematic · not to map scale","fixed_not_map_scale")
	# Actual window-oriented candidate card sizes. Root owns final placement and
	# independent pixels; these checks establish complete geometry/legend fit only.
	var sizes: Array=[Vector2(280,300),Vector2(280,302),Vector2(280,330),Vector2(360,330),Vector2(420,360)]
	for index in sizes.size():
		card.size=sizes[index]; card._arrange()
		var bounds := Rect2(Vector2.ZERO,card.size)
		var points: Array[Vector2]=Card.schematic_points(card.schematic_rect())
		_check(points.size()==6,"six_points_size_"+str(index))
		for point in points: _check(_inside(point,card.schematic_rect()) and _inside(point,bounds),"complete_fixed_fit_size_"+str(index))
		for i in 5:
			var label: Label=card._labels[i]
			_check(label.visible and label.text=="%d  %s" % [i+1,["Departure","Crosswind","Downwind","Base","Final"][i]],"all_five_exact_labels_size_"+str(index))
			_check(bounds.encloses(label.get_rect()),"legend_bounds_size_"+str(index))
			var glyph: Vector2=label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size"))
			_check(glyph.x<=label.size.x and glyph.y<=label.size.y,"legend_glyph_metrics_size_"+str(index))
		_check(bounds.encloses(card._title.get_rect()) and bounds.encloses(card._caption.get_rect()) and bounds.encloses(card._footer.get_rect()),"persistent_text_bounds_size_"+str(index))
		_check(card._view==snapshot and base==Sources.captured_readback(),"resize_no_source_or_display_state_change_"+str(index))
	# Independent pre-consumer rational cases. These rectangles are arbitrary fit
	# inputs, not mandatory UI rectangles or viewport/map projection expectations.
	var rects: Array=[Rect2(16,56,150,240),Rect2(16,56,230,336),Rect2(16,56,330,448)]
	var expected: Array=[
		[Vector2(133,224),Vector2(133,56),Vector2(49,56),Vector2(49,296),Vector2(133,296),Vector2(133,224)],
		[Vector2(949.0/5.0,1456.0/5.0),Vector2(949.0/5.0,56),Vector2(361.0/5.0,56),Vector2(361.0/5.0,392),Vector2(949.0/5.0,392),Vector2(949.0/5.0,1456.0/5.0)],
		[Vector2(1297.0/5.0,1848.0/5.0),Vector2(1297.0/5.0,56),Vector2(513.0/5.0,56),Vector2(513.0/5.0,504),Vector2(1297.0/5.0,504),Vector2(1297.0/5.0,1848.0/5.0)]]
	for i in 3:
		var actual: Array[Vector2]=Card.schematic_points(rects[i])
		for j in 6: _check(actual[j].is_equal_approx(expected[i][j]),"independent_rational_fit_"+str(i)+"_"+str(j))
	_check(Card.schematic_points(Rect2(0,0,0,10)).is_empty(),"invalid_fit_empty")
	card.size=Vector2(280,330)
	card.set_state(snapshot,true)
	var fixed: Array[Vector2]=Card.schematic_points(card.schematic_rect())
	for ownship in [[0,0,0],[100,0,-1000],[5000,0,5000]]:
		var elsewhere: Dictionary=snapshot.duplicate(true); elsewhere.ownship_anchor_eus_m=ownship
		card.set_state(elsewhere,true)
		_check(Card.schematic_points(card.schematic_rect())==fixed,"ownship_independent_fixed_schematic")
		_check(card._labels[0].text=="1  Departure","no_current_leg_inference")
	card.set_state(snapshot,false)
	_clear(card,"off")
	_check(card._reason.text=="Aid off","exact_off_reason")
	card.set_state(Geometry.unavailable("Unsupported start"),true)
	_clear(card,"unavailable")
	_check(card._reason.text=="Unsupported start","copied_unavailable_reason")
	var cases: Array=[]
	var extra: Dictionary=snapshot.duplicate(true); extra.extra=true; cases.append(extra)
	var wrong_id: Dictionary=snapshot.duplicate(true); wrong_id.fixture_id="wrong"; cases.append(wrong_id)
	var wrong_revision: Dictionary=snapshot.duplicate(true); wrong_revision.fixture_revision=2; cases.append(wrong_revision)
	var numeric_revision: Dictionary=snapshot.duplicate(true); numeric_revision.fixture_revision=1.0; cases.append(numeric_revision)
	var state: Dictionary=snapshot.duplicate(true); state.state="historical"; cases.append(state)
	var tick: Dictionary=snapshot.duplicate(true); tick.tick=0; cases.append(tick)
	var point: Dictionary=snapshot.duplicate(true); point.points_anchor_eus_m[2][0]=-1401; cases.append(point)
	var label: Dictionary=snapshot.duplicate(true); label.leg_labels[0]="Turn now"; cases.append(label)
	var anchor: Dictionary=snapshot.duplicate(true); anchor.ownship_anchor_eus_m[2]=INF; cases.append(anchor)
	var stale: Dictionary=snapshot.duplicate(true); stale.available=false; stale.state="unavailable"; stale.error="stale"; cases.append(stale)
	cases.append({})
	for i in cases.size():
		card.set_state(snapshot,true)
		card.set_state(cases[i],true)
		_clear(card,"malformed_"+str(i))
	_check(signals_seen[0]==0,"set_state_and_resize_emit_no_enable_request")
	_check(card.mouse_filter==Control.MOUSE_FILTER_IGNORE,"off_unavailable_still_mouse_ignore")
	card.free()
	return _result()

func _result() -> Dictionary:
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Pure schematic geometry, copied card and glyph bounds; no final viewport pixels, map integration, native or pilot qualification"}
