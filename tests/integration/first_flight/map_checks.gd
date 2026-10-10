extends RefCounted
# Original MIT. Expectations frozen before consumer output, packet SHA256
# 6b85f145645d166766d569e00156d93ef8e367b7f27ffc9d78a8cefcd77e86be.
# Literal exact-rational projection/clip results; final vectors are presentation precision.
const MapView = preload("res://interactive/flight_map.gd")
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
    return {"passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Independent frozen geographic clipping/projection and owned map-layer invariance; no GPU or physics qualification"}
