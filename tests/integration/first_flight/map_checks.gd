extends RefCounted
# Original MIT. Expectations frozen before consumer output, packet SHA256
# 6b85f145645d166766d569e00156d93ef8e367b7f27ffc9d78a8cefcd77e86be.
# Literal exact-rational projection/clip results; final vectors are presentation precision.
const MapView = preload("res://interactive/flight_map.gd")
const Board = preload("res://ui/freeflight/landmark_board.gd")
const Geometry = preload("res://world/synthetic/circuit_geometry.gd")
const Sources = preload("res://world_tests/synthetic/circuit_checks.gd")
const CLIPS = [
    ["some_vertices_inside_0",Vector2(212.0,246.0),Vector2(212.0,-874.0),[Vector2(212.0,246.0),Vector2(212.0,56.0)]],
    ["some_vertices_inside_1",Vector2(212.0,-874.0),Vector2(-348.0,-874.0),[]],
    ["some_vertices_inside_2",Vector2(-348.0,-874.0),Vector2(-348.0,726.0),[]],
    ["some_vertices_inside_3",Vector2(-348.0,726.0),Vector2(212.0,726.0),[]],
    ["some_vertices_inside_4",Vector2(212.0,726.0),Vector2(212.0,246.0),[Vector2(212.0,356.0),Vector2(212.0,246.0)]],
    ["all_vertices_outside_but_departure_crosses_0",Vector2(212.0,646.0),Vector2(212.0,-474.0),[Vector2(212.0,356.0),Vector2(212.0,56.0)]],
    ["all_vertices_outside_but_departure_crosses_1",Vector2(212.0,-474.0),Vector2(-348.0,-474.0),[]],
    ["all_vertices_outside_but_departure_crosses_2",Vector2(-348.0,-474.0),Vector2(-348.0,1126.0),[]],
    ["all_vertices_outside_but_departure_crosses_3",Vector2(-348.0,1126.0),Vector2(212.0,1126.0),[]],
    ["all_vertices_outside_but_departure_crosses_4",Vector2(212.0,1126.0),Vector2(212.0,646.0),[]],
    ["translated_ownship_crossing_0",Vector2(172.0,646.0),Vector2(172.0,-474.0),[Vector2(172.0,356.0),Vector2(172.0,56.0)]],
    ["translated_ownship_crossing_1",Vector2(172.0,-474.0),Vector2(-388.0,-474.0),[]],
    ["translated_ownship_crossing_2",Vector2(-388.0,-474.0),Vector2(-388.0,1126.0),[]],
    ["translated_ownship_crossing_3",Vector2(-388.0,1126.0),Vector2(172.0,1126.0),[]],
    ["translated_ownship_crossing_4",Vector2(172.0,1126.0),Vector2(172.0,646.0),[]],
    ["inside_diagram_all_perimeter_outside_0",Vector2(492.0,646.0),Vector2(492.0,-474.0),[]],
    ["inside_diagram_all_perimeter_outside_1",Vector2(492.0,-474.0),Vector2(-68.0,-474.0),[]],
    ["inside_diagram_all_perimeter_outside_2",Vector2(-68.0,-474.0),Vector2(-68.0,1126.0),[]],
    ["inside_diagram_all_perimeter_outside_3",Vector2(-68.0,1126.0),Vector2(492.0,1126.0),[]],
    ["inside_diagram_all_perimeter_outside_4",Vector2(492.0,1126.0),Vector2(492.0,646.0),[]],
    ["outside_diagram_ownship_0",Vector2(-1788.0,-1754.0),Vector2(-1788.0,-2874.0),[]],
    ["outside_diagram_ownship_1",Vector2(-1788.0,-2874.0),Vector2(-2348.0,-2874.0),[]],
    ["outside_diagram_ownship_2",Vector2(-2348.0,-2874.0),Vector2(-2348.0,-1274.0),[]],
    ["outside_diagram_ownship_3",Vector2(-2348.0,-1274.0),Vector2(-1788.0,-1274.0),[]],
    ["outside_diagram_ownship_4",Vector2(-1788.0,-1274.0),Vector2(-1788.0,-1754.0),[]],
    ["both_endpoints_outside_horizontal_0",Vector2(-188.0,206.0),Vector2(612.0,206.0),[Vector2(12.0,206.0),Vector2(412.0,206.0)]],
    ["outside_parallel_rejected_0",Vector2(-188.0,-194.0),Vector2(612.0,-194.0),[]],
    ["diagonal_crossing_0",Vector2(-188.0,-194.0),Vector2(612.0,606.0),[Vector2(62.0,56.0),Vector2(362.0,356.0)]]
]
var checks: int=0
var failures: Array[String]=[]
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok: failures.append(label)
func run(observed_readback: Dictionary={}) -> Dictionary:
    var chart := Rect2(12,56,400,300)
    for row in CLIPS:
        var actual: Array=MapView._clip_circuit_segment(row[1],row[2],chart)
        check(actual.size()==row[3].size(),row[0]+"_interval_presence")
        if actual.size()==2 and row[3].size()==2:
            for i in 2: check(actual[i].is_equal_approx(row[3][i]),row[0]+"_endpoint_"+str(i))
    for bad in [Rect2(0,0,0,2),Rect2(0,0,2,-1),Rect2(NAN,0,2,2),Rect2(0,0,INF,2)]:
        check(MapView._clip_circuit_segment(Vector2.ZERO,Vector2.ONE,bad).is_empty(),"invalid_chart_rejected")
    check(MapView._clip_circuit_segment(Vector2(NAN,0),Vector2.ONE,chart).is_empty(),"invalid_endpoint_rejected")
    # Independent minimum-window rectangles: ordinary routed has only37px
    # chart height, so its24px inset is empty. Other supported charts retain
    # the original containment result and projected geometry.
    for row in [["ordinary_routed",Rect2(12,76,196,37),false],
            ["ordinary_unrouted",Rect2(12,56,196,57),true],
            ["compact_routed",Rect2(12,62,196,72),true],
            ["large_routed",Rect2(12,76,400,280),true]]:
        check(MapView._inset_contains(row[1],row[1].get_center(),24.0)==row[2],row[0]+"_runway_interior")
        check(MapView._inset_contains(row[1],row[1].get_center(),7.0),row[0]+"_runway_dot_interior")
        check(MapView._inset_contains(row[1],row[1].get_center(),18.0),row[0]+"_landmark_interior")
    check(MapView._inset_contains(chart,Vector2(36,80),24.0),"inset_left_top_included")
    check(not MapView._inset_contains(chart,Vector2(388,332),24.0),"inset_right_bottom_excluded")
    check(not MapView._inset_contains(chart,Vector2(35,80),24.0),"inset_outside_rejected")
    for bad in [Rect2(0,0,48,48),Rect2(0,0,47,100),Rect2(0,0,100,47),Rect2(0,0,0,0),Rect2(0,0,-1,100),Rect2(NAN,0,100,100),Rect2(0,0,INF,100)]:
        check(not MapView._inset_contains(bad,Vector2(24,24),24.0),"empty_invalid_inset_rejected")
    check(not MapView._inset_contains(chart,Vector2(NAN,0),24.0),"invalid_inset_point_rejected")
    check(not MapView._inset_contains(chart,chart.get_center(),-1.0),"negative_inset_margin_rejected")
    check(not MapView._inset_contains(chart,chart.get_center(),INF),"infinite_inset_margin_rejected")
    var map_view: Control=MapView.new()
    map_view.size=Vector2(424,463)
    map_view.extent_m=1000.0
    map_view._position=Vector2(0,-1000)
    var position: Vector2=map_view._position
    check(map_view._point(Vector2(0,100),chart).is_equal_approx(Vector2(212,646)),"independent_translated_departure")
    check(map_view._point(Vector2(0,-2700),chart).is_equal_approx(Vector2(212,-474)),"independent_translated_crosswind")
    map_view._position=Vector2(100,-1000)
    check(map_view._point(Vector2(0,100),chart).is_equal_approx(Vector2(172,646)),"independent_east_translation")
    map_view._position=position
    var route: Dictionary={"available":true,"active":true,"target_anchor_eus_m":[100,0,-500],"target_label":"Original target"}
    map_view.set_route(route)
    var before: PackedByteArray=var_to_bytes([map_view.extent_m,map_view._position,map_view._runway,map_view._route,map_view._trail])
    var base: Dictionary=Sources.reference_readback() if observed_readback.is_empty() else observed_readback.duplicate(true)
    var view: Dictionary=Geometry.view(base,"calm",36)
    check(view.available,"source_qualified_map_baseline")
    if not view.available:
        map_view.free()
        return {"passed":false,"checks":checks,"failures":failures,"scope":"Map baseline failed qualification; copied-layer checks not executed"}
    map_view.set_circuit_reference(view)
    check(map_view._circuit==view,"complete_copied_layer")
    var owned: Dictionary=map_view._circuit.duplicate(true)
    view.points_anchor_eus_m[0][0]=999
    check(map_view._circuit==owned,"map_owns_view")
    check(before==var_to_bytes([map_view.extent_m,map_view._position,map_view._runway,map_view._route,map_view._trail]),"layer_preserves_existing_navigation")
    for bad in [{},Geometry.unavailable("Aid off"),{"available":true}]:
        map_view.set_circuit_reference(owned)
        map_view.set_circuit_reference(bad)
        check(map_view._circuit.is_empty(),"unavailable_malformed_clears_prior_layer")
        check(before==var_to_bytes([map_view.extent_m,map_view._position,map_view._runway,map_view._route,map_view._trail]),"clearing_preserves_existing_navigation")
    map_view.free()
    _manual_layout_cases(base)
    return {"passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Independent frozen geographic clipping/projection, copied manual summary, actual font/tooltip fit and map authority invariance; no GPU or physics qualification"}

func _manual_layout_cases(base: Dictionary) -> void:
    var source_bytes: PackedByteArray=var_to_bytes(base)
    var tree := Engine.get_main_loop() as SceneTree
    check(tree!=null,"locator_actual_theme_tree")
    if tree==null: return
    var viewport := SubViewport.new()
    viewport.size=Vector2i(960,540)
    tree.root.add_child(viewport)
    var board := Board.new()
    board.size=Vector2(960,540)
    viewport.add_child(board)
    var map_view := MapView.new()
    map_view.compact_aid_layout=true
    map_view.size=Vector2(250,220)
    viewport.add_child(map_view)
    var landmarks: Array=[{"label":"East Farm","position_eus_m":Vector3(100,0,-500)},{"label":"North Water Tank","position_eus_m":Vector3(300,0,-1500)},{"label":"North Orchard","position_eus_m":Vector3(-900,0,-2200)},{"label":"River Bridge","position_eus_m":Vector3(1000,0,-300)}]
    check(board.configure(landmarks).ok and board.choose([0,1,2,3],base).ok,"locator_actual_board_four_leg_source")
    var view: Dictionary=board.observe(base)
    check(view.available and view.active and view.leg_count==4,"locator_actual_current_board_view")
    if not view.available:
        viewport.free()
        return
    var hints: Dictionary={"zoom_in":{"short":"E +3 alternatives","full":"E OR Add OR R OR T"},"zoom_out":{"short":"Minus","full":"Minus OR Subtract"},"close":{"short":"Tab","full":"Tab"}}
    var info: Dictionary={"paused":true,"outcome":"paused","ground_valid":true,"clearance_m":1.0,"locator_binding_hints":hints}
    var point: Array=base.canonical.anchor_eus_position_m
    map_view.set_state(base.aircraft,Vector3(point[0],point[1],point[2]),Basis.IDENTITY,info)
    map_view.set_route(view)
    var native_navigation: PackedByteArray=var_to_bytes([map_view._position,map_view.extent_m,map_view._runway,map_view._trail])
    var view_bytes: PackedByteArray=var_to_bytes(view)
    for width in [250,320,360]:
        map_view.size=Vector2(width,220);map_view._refresh_presentation()
        check(map_view.renders_manual_summary(),"locator_current_complete_equivalence_"+str(width))
        check(map_view._labels.target.text==board._title.text and map_view._labels.manual.text==board._metrics.text,"locator_current_exact_board_title_metrics_"+str(width))
        check(map_view._labels.footer.text.begins_with(board._state.text+"\n"),"locator_current_exact_full_board_footer_"+str(width))
        check(map_view._labels.status.text.begins_with("Itinerary (tooltip): ") and map_view.tooltip_text.contains(board._leg_text.text),"locator_secondary_explicit_tooltip_and_full_list_"+str(width))
        check(map_view._labels.header.text.ends_with("1/4"),"locator_visible_leg_count_"+str(width))
        check(map_view._presentation.chart==Rect2(12,69,width-24,54),"locator_fixed_current_chart_"+str(width))
        for row in map_view._presentation.rows:
            check(map_view._row_fits(row),"locator_current_actual_font_row_"+row.id+"_"+str(width))
        check(var_to_bytes(map_view._manual_summary)==view_bytes and var_to_bytes(view)==view_bytes,"locator_current_owned_binary_view_"+str(width))
    var copied: Dictionary=view.duplicate(true)
    map_view.set_route(copied)
    copied.route_labels[0]="Changed after publication";copied.target_anchor_eus_m[0]=999
    check(var_to_bytes(map_view._manual_summary)==view_bytes,"locator_summary_recursively_owns_source")
    hints.close.short="Q";hints.close.full="Changed input"
    check(map_view._locator_hints.close.short=="Tab" and map_view.tooltip_text.contains("Close: Tab"),"locator_binding_hints_recursively_own_source")
    # A valid null bearing at a coincident selected target remains admitted and
    # visibly unavailable, never fabricated as north or rejected for null.
    var coincident: Dictionary=view.duplicate(true)
    coincident.planar_range_m=0.0;coincident.bearing_deg=null
    map_view.set_route(coincident)
    check(map_view.renders_manual_summary() and map_view._labels.manual.text=="0.00 km / bearing unavailable","locator_current_null_bearing_complete")
    # All16 required keys and strict Variant domains are independent from the
    # permissive original geographic guard, which still admits terse/extra keys.
    var terse: Dictionary={"available":true,"active":true,"target_anchor_eus_m":[100,0,-500],"target_label":"Original target"}
    map_view.set_route(terse)
    check(not map_view._route.is_empty() and map_view._route.leg_number==1 and map_view._route.leg_count==1 and map_view._manual_summary.is_empty() and not map_view.renders_manual_summary(),"locator_terse_original_geography_only")
    var extra: Dictionary=view.duplicate(true);extra.unapproved=true
    map_view.set_route(extra)
    check(not map_view._route.is_empty() and map_view._manual_summary.is_empty() and not map_view.renders_manual_summary(),"locator_extra_key_clears_only_summary")
    for key in MapView.SUMMARY_KEYS:
        var missing: Dictionary=view.duplicate(true);missing.erase(key)
        map_view.set_route(view);map_view.set_route(missing)
        check(map_view._manual_summary.is_empty() and not map_view.renders_manual_summary(),"locator_missing_summary_key_"+key)
        check(map_view._route.is_empty()==(key in ["available","active","target_anchor_eus_m","target_label"]),"locator_missing_key_independent_original_geography_"+key)
    var bad: Array=[]
    for key in ["paused","historical","available","complete","active","aid_visible"]:
        var changed: Dictionary=view.duplicate(true);changed[key]=1;bad.append([key+"_integer_bool",changed])
    for pair in [["leg_count",4.0],["leg_count",5],["leg_count",-1],["leg_index",0.0],["leg_index",4],["leg_index",-1],["session_id",1],["session_id",""],["tick",0],["tick","00"],["tick","18446744073709551616"],["error",null],["target_label","Other target"],["planar_range_m",-1.0],["planar_range_m",INF],["bearing_deg",-1.0],["bearing_deg",360.0],["bearing_deg",NAN],["target_anchor_eus_m",[20001,0,0]],["target_anchor_eus_m",[0,1,0]],["target_anchor_eus_m",[INF,0,0]],["route_labels",["East Farm"]]]:
        var changed: Dictionary=view.duplicate(true);changed[pair[0]]=pair[1];bad.append([pair[0]+str(bad.size()),changed])
    for pair in [["historical",true],["active",false],["complete",true]]:
        var changed: Dictionary=view.duplicate(true);changed[pair[0]]=pair[1];bad.append(["contradictory_"+pair[0],changed])
    for item in bad:
        if item[0] in ["available_integer_bool","active_integer_bool"]:
            # Protected legacy geography compares these fields to bool and its
            # old out-of-domain int comparison throws. Test the new strict
            # summary boundary directly, without claiming that old call fixed.
            check(MapView._admit_summary(item[1]).is_empty(),"locator_strict_summary_only_"+item[0])
        else:
            map_view.set_route(view);map_view.set_route(item[1])
            check(map_view._manual_summary.is_empty() and not map_view.renders_manual_summary(),"locator_strict_reject_"+item[0])
            # Frozen old geography only cares about its active/current target.
            # Invalid summary-only metadata must not silently clear that line.
            var target_rejected: bool=item[0].begins_with("target_anchor_eus_m") or item[0]=="contradictory_active"
            check(map_view._route.is_empty()==target_rejected,"locator_malformed_independent_original_geography_"+item[0])
    # Actual selected route survives retained/closed truth without recalling any
    # current target/range/bearing. Compare Board's real fallback strings.
    var retained: Dictionary=base.duplicate(true)
    retained.host_mode="coverage_blocked";retained.historical=true;retained.native_outcome="coverage_blocked";retained.paused=true
    var old: Dictionary=board.observe(retained)
    check(old.active and old.historical and not old.available and old.target_label==null,"locator_actual_retained_active_view")
    map_view.set_state(retained.aircraft,Vector3(point[0],point[1],point[2]),Basis.IDENTITY,{"historical":true,"paused":true,"outcome":"coverage_blocked","locator_binding_hints":info.locator_binding_hints})
    map_view.set_route(old)
    for width in [250,320,360]:
        map_view.size=Vector2(width,188);map_view._refresh_presentation()
        check(map_view.renders_manual_summary(),"locator_retained_complete_equivalence_"+str(width))
        check(map_view._route.is_empty() and map_view._presentation.chart==Rect2(),"locator_retained_no_recalled_geography_"+str(width))
        check(map_view._labels.target.text==board._title.text and map_view._labels.manual.text==board._metrics.text and map_view._labels.footer.text==board._state.text,"locator_retained_exact_board_semantics_"+str(width))
        check(map_view._labels.no_current.text=="NO CURRENT GEOGRAPHIC GUIDANCE","locator_retained_explicit_noncurrent_"+str(width))
        check(map_view._labels.leg.text.begins_with("Leg 1/4 · itinerary(tooltip): ") and map_view.tooltip_text.contains(board._leg_text.text),"locator_retained_leg_full_tooltip_"+str(width))
        for row in map_view._presentation.rows: check(map_view._row_fits(row),"locator_retained_actual_font_row_"+row.id+"_"+str(width))
    # A complete synthetic closed Readback uses the existing exact null shape;
    # it is display-only fixture construction, not a new native join claim.
    var closed: Dictionary=base.duplicate(true)
    for key in Sources.Readings.NULLABLE: closed[key]=null
    closed.host_mode="closed";closed.historical=true;closed.native_live=false;closed.paused=false;closed.debt_quanta=0;closed.time_scale=1.0
    check(Sources.Readings.from_readback(closed).state=="empty","locator_full_closed_fixture_contract")
    var closed_view: Dictionary=board.observe(closed)
    map_view.set_state({},Vector3.ZERO,Basis.IDENTITY,{"historical":true,"outcome":"closed","locator_binding_hints":info.locator_binding_hints})
    map_view.set_route(closed_view)
    check(map_view.renders_manual_summary() and closed_view.active and closed_view.session_id==null and closed_view.target_label==null and map_view._route.is_empty(),"locator_closed_preserves_only_selected_itinerary")
    check(map_view._labels.target.text==board._title.text and map_view._labels.manual.text==board._metrics.text and map_view._labels.footer.text=="RETAINED / NO CURRENT GUIDANCE","locator_closed_exact_board_fallback")
    var invalid_view: Dictionary=board.observe({})
    map_view.set_route(invalid_view)
    check(map_view.renders_manual_summary() and not invalid_view.available and map_view._labels.no_current.visible and map_view.tooltip_text.contains(invalid_view.error),"locator_invalid_source_keeps_error_and_no_current_geometry")
    map_view.set_route({})
    check(map_view._manual_summary.is_empty() and not map_view.renders_manual_summary(),"locator_empty_clears_summary")
    # Completed itinerary is a legitimate current publication with no active
    # target; null fields cannot restore a geographic line.
    check(board.choose([0],base).ok and board.next(base).ok,"locator_actual_completed_board")
    var complete: Dictionary=board.observe(base)
    map_view.set_state(base.aircraft,Vector3(point[0],point[1],point[2]),Basis.IDENTITY,info)
    map_view.size=Vector2(250,220);map_view.set_route(complete)
    check(complete.complete and not complete.active and map_view.renders_manual_summary() and map_view._route.is_empty(),"locator_completed_equivalence_without_geography")
    check(map_view._labels.target.text=="Manual itinerary ended" and map_view._labels.manual.text=="Range / bearing unavailable","locator_completed_exact_fallback")
    # Actual maximum32-character target wraps fully; only secondary itinerary
    # is shortened. Every +N/configured/category/action survives alias trimming.
    var long_names: Array=[]
    for i in 4: long_names.append({"label":"W".repeat(31)+str(i),"position_eus_m":Vector3(100+i,0,-500)})
    check(board.configure(long_names).ok and board.choose([0,1,2,3],base).ok,"locator_actual_max_names_board")
    var long_view: Dictionary=board.observe(base)
    var long_hints: Dictionary={}
    for key in ["zoom_in","zoom_out","close"]: long_hints[key]={"short":"cfg "+"W".repeat(32)+":31 +3","full":"CONFIGURED "+"W".repeat(32)+" button31 OR full second OR full third OR full fourth (availability unverified; open Controls)"}
    var long_info: Dictionary=info.duplicate(true);long_info.locator_binding_hints=long_hints
    map_view.set_state(base.aircraft,Vector3(point[0],point[1],point[2]),Basis.IDENTITY,long_info)
    map_view.set_route(long_view)
    check(map_view.renders_manual_summary() and map_view._labels.target.text==long_names[0].label and map_view._labels.target.get_line_count()==2,"locator_max_target_complete_wrap_no_ellipsis")
    check(map_view._labels.status.text.begins_with("Itinerary (tooltip): ") and map_view._labels.status.text.ends_with("…") and map_view.tooltip_text.contains(board._leg_text.text),"locator_max_itinerary_inline_explanation")
    var hints_text: String=map_view._binding_footer(226)
    check(hints_text.count("cfg ")==3 and hints_text.count(" +3")==3 and hints_text.contains("+") and hints_text.contains("−") and hints_text.contains("Close:") and hints_text.contains("…"),"locator_max_alias_only_shortening_keeps_actions_categories_counts")
    check(map_view.tooltip_text.contains("cfg = CONFIGURED") and map_view.tooltip_text.contains("+N means additional configured alternatives") and map_view.tooltip_text.contains(long_hints.close.full),"locator_full_hints_and_definitions_sync_before_draw")
    for count in [0,1,3]:
        var short: String="cfg "+"W".repeat(32)+":31"+(" +%d" % count if count>0 else "")
        var boundary: Dictionary={}
        for key in ["zoom_in","zoom_out","close"]: boundary[key]={"short":short,"full":"CONFIGURED slot button31; availability unverified; "+str(count)+" additional alternatives"}
        var boundary_info: Dictionary=info.duplicate(true);boundary_info.locator_binding_hints=boundary
        map_view.set_state(base.aircraft,Vector3(point[0],point[1],point[2]),Basis.IDENTITY,boundary_info)
        var line: String=map_view._binding_footer(226)
        check(line.count("cfg ")==3 and (line.count(" +%d" % count)==3 if count>0 else not line.contains(" +1") and not line.contains(" +3")) and map_view._font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x<=226,"locator_configured_alias_boundary_count_"+str(count))
        check(map_view.renders_manual_summary(),"locator_configured_full_composition_boundary_"+str(count))
    # Unavailable/malformed hints clear old aliases instead of inventing keys.
    for unavailable in [{},{"locator_binding_hints":{}},{"locator_binding_hints":{"close":{"short":"Tab"}}}]:
        map_view.set_state(base.aircraft,Vector3(point[0],point[1],point[2]),Basis.IDENTITY,unavailable)
        check(map_view._binding_footer(226).count("unbound")==3 and not map_view._binding_footer(226).contains("Tab"),"locator_missing_hints_truthful_no_hardcoded_keys")
        check(map_view.tooltip_text.count("Binding unavailable; open Controls")==3,"locator_missing_complete_binding_tooltip")
    # False equivalence is fail-closed for undersized boxes, hidden maps,
    # stale source identity/tick, long mandatory numeric text and aids hidden.
    map_view.set_state(base.aircraft,Vector3(point[0],point[1],point[2]),Basis.IDENTITY,info)
    map_view.set_route(view)
    for small in [Vector2(249,220),Vector2(250,219)]:
        map_view.size=small;map_view._refresh_presentation()
        check(not map_view.renders_manual_summary(),"locator_unfit_dimensions_never_suppress")
    map_view.size=Vector2(250,220);map_view._refresh_presentation()
    map_view.hide();check(not map_view.renders_manual_summary(),"locator_hidden_never_suppress");map_view.show()
    var stale: Dictionary=view.duplicate(true);stale.tick="1";map_view.set_route(stale)
    check(not map_view.renders_manual_summary(),"locator_stale_tick_never_suppress")
    stale=view.duplicate(true);stale.paused=false;map_view.set_route(stale)
    check(not map_view.renders_manual_summary(),"locator_stale_pause_truth_never_suppress")
    stale=view.duplicate(true);stale.session_id="other-session";map_view.set_route(stale)
    check(not map_view.renders_manual_summary(),"locator_stale_session_never_suppress")
    var huge: Dictionary=view.duplicate(true);huge.planar_range_m=1e300;map_view.set_route(huge)
    check(not map_view.renders_manual_summary() and map_view._manual_summary==huge,"locator_unfit_metric_rejects_equivalence_not_source")
    var hidden_aid: Dictionary=view.duplicate(true);hidden_aid.aid_visible=false;map_view.set_route(hidden_aid)
    check(not map_view.renders_manual_summary(),"locator_hidden_aid_never_suppress")
    map_view.set_route(view)
    var before_accessor: PackedByteArray=var_to_bytes([map_view._manual_summary,map_view._route,map_view._position,map_view._trail,map_view.extent_m,map_view._runway,map_view._locator_hints])
    for i in 4: check(map_view.renders_manual_summary(),"locator_pure_repeat_accessor")
    check(before_accessor==var_to_bytes([map_view._manual_summary,map_view._route,map_view._position,map_view._trail,map_view.extent_m,map_view._runway,map_view._locator_hints]),"locator_accessor_full_presentation_authority_invariance")
    check(native_navigation==var_to_bytes([map_view._position,map_view.extent_m,map_view._runway,map_view._trail]) and var_to_bytes(base)==source_bytes,"locator_layout_hints_summary_preserve_native_navigation_source")
    var event := InputEventMouseButton.new()
    event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=map_view._labels.status.get_global_rect().get_center()
    viewport.push_input(event,true)
    check(not viewport.is_input_handled() and map_view._labels.status.mouse_filter==Control.MOUSE_FILTER_PASS and map_view._labels.status.get_signal_connection_list("gui_input").is_empty(),"locator_sync_unregistered_queue_final_flag_and_Label_configuration")
    check(map_view._labels.status.get_tooltip(Vector2.ZERO).contains("Leg 1 / 4:"),"locator_sync_complete_tooltip_text_before_registration")
    var released := InputEventMouseButton.new()
    released.button_index=MOUSE_BUTTON_LEFT;released.pressed=false;released.position=event.position
    viewport.push_input(released,true)
    check(not viewport.is_input_handled() and before_accessor==var_to_bytes([map_view._manual_summary,map_view._route,map_view._position,map_view._trail,map_view.extent_m,map_view._runway,map_view._locator_hints]) and var_to_bytes(base)==source_bytes,"locator_sync_unregistered_release_queue_final_flag_and_source_invariance")
    viewport.free()
