extends RefCounted
## Original MIT. Actual production HUD allocation + shaped fallback-font glyphs.
## Headless geometry/actual drawing calls; original Windows images still required.
const FlightDisplay=preload("res://interactive/flight_panel.gd")
const TITLES=["TRUE AIRSPEED","ATTITUDE","ELLIPSOID ALT","TRUE HEADING","BODY YAW RATE","VERTICAL SPEED"]
const UNITS=["kt · derived","native truth","ft · WGS84","degrees","°/s · body r","ft/min · kinematic"]
const DIMENSIONS=[Vector2(960,540),Vector2(1920,1080),Vector2(2560,1440),Vector2(1600,899),Vector2(1600,900),Vector2(1280,720),Vector2(1600,1000),Vector2(1600,1100),Vector2(1600,1221),Vector2(1600,1222),Vector2(1920,1338),Vector2(1920,1339),Vector2(960,899),Vector2(960,900),Vector2(2560,900),Vector2(1920,1200)]
class CapturedPanel extends FlightDisplay:
 var drawn: Array[Dictionary]=[]
 func _draw() -> void:
  drawn.clear()
  super._draw()
 func _text(at: Vector2,text: String,pixels: float=14.0,color: Color=FlightDisplay.INK,centered: bool=false) -> void:
  drawn.append({"at":at,"text":text,"pixels":maxi(10,roundi(pixels)),"centered":centered})
  super._text(at,text,pixels,color,centered)
var checks: int=0
var failures: Array=[]
var _host: Node
func _check(ok: bool,label: String) -> void:
 checks+=1
 if not ok: failures.append(label)
 _host.check(ok,label)

static func glyph_bounds(font: Font,text: String,center_x: float,baseline: float,pixels: int) -> Rect2:
 # The same shaped font/glyph atlas used by draw_string, including bearings
 # and glyph texture padding; not a guessed average character width.
 var line: TextLine=TextLine.new()
 line.add_string(text,font,pixels)
 var server: TextServer=TextServerManager.get_primary_interface()
 var pen: Vector2=Vector2(center_x-font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x*0.5,baseline)
 var result: Rect2=Rect2()
 var found: bool=false
 for glyph in server.shaped_text_get_glyphs(line.get_rid()):
  for repeat in int(glyph.repeat):
   var offset: Vector2=server.font_get_glyph_offset(glyph.font_rid,Vector2i(glyph.font_size,0),glyph.index)
   var extent: Vector2=server.font_get_glyph_size(glyph.font_rid,Vector2i(glyph.font_size,0),glyph.index)
   if extent.x>0.0 and extent.y>0.0:
    var rect: Rect2=Rect2(pen+glyph.offset+offset,extent)
    result=result.merge(rect) if found else rect
    found=true
   pen.x+=float(glyph.advance)
 return result

static func _legacy_cells(dimensions: Vector2) -> Array[Rect2]:
 # Only the frozen accepted-source before-run uses this branch. Its actual
 # _text calls are still recorded; missing new helpers must not stop that run.
 var height: float=minf(dimensions.y*0.34,455.0)
 var top: float=dimensions.y-height
 var result: Array[Rect2]=[]
 if dimensions.y<900.0:
  var width: float=(dimensions.x-56.0)/6.0
  for index in 6: result.append(Rect2(28+index*width,top+10,width,height-61.0))
 else:
  var slot: float=(height-44.0)*0.5
  for index in 6: result.append(Rect2((dimensions.x-slot*3.0)*0.5+(index%3)*slot,top+34+(index/3)*slot,slot,slot))
 return result

static func caption_metadata(panel: Control) -> Array[Dictionary]:
 var rows: Array[Dictionary]=[]
 var cells: Array[Rect2]=panel._hud_instrument_cells() if panel.has_method("_hud_instrument_cells") else _legacy_cells(panel.size)
 for index in 6:
  var cell: Rect2=cells[index]
  var layout: Dictionary={}
  if panel.has_method("_hud_caption_layout"):
   layout=panel._hud_caption_layout(cell)
  else:
   var old_radius: float=minf(cell.size.x*0.43,(cell.size.y-26.0)*0.5)
   layout={"radius":old_radius,"center":Vector2(cell.get_center().x,cell.position.y+old_radius+4.0),"title_baseline":cell.position.y+old_radius*2.0+20.0,"unit_baseline":cell.position.y+old_radius*2.0+33.0,"title_pixels":maxi(10,roundi(clampf(old_radius*0.14,10.0,15.0))),"unit_pixels":maxi(10,roundi(clampf(old_radius*0.115,10.0,12.0)))}
  var center: Vector2=layout.center
  var radius: float=layout.radius
  var row: Dictionary={"index":index,"cell":cell,"center":center,"radius":radius,
   "ring":Rect2(center-Vector2.ONE*(radius+3.0),Vector2.ONE*(2.0*radius+6.0)),
   "shadow":Rect2(center+Vector2(0,4)-Vector2.ONE*(radius+4.0),Vector2.ONE*(2.0*radius+8.0)),"captions":[]}
  for which in 2:
   var text: String=TITLES[index] if which==0 else UNITS[index]
   var pixels: int=layout.title_pixels if which==0 else layout.unit_pixels
   var baseline: float=layout.title_baseline if which==0 else layout.unit_baseline
   var width: float=panel._font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x
   row.captions.append({"text":text,"pixels":pixels,"baseline":baseline,"ascent":panel._font.get_ascent(pixels),"descent":panel._font.get_descent(pixels),
    "metric_bounds":Rect2(center.x-width*0.5,baseline-panel._font.get_ascent(pixels),width,panel._font.get_ascent(pixels)+panel._font.get_descent(pixels)),
    "glyph_bounds":glyph_bounds(panel._font,text,center.x,baseline,pixels)})
  rows.append(row)
 return rows

func _old_counterexample(panel: Control,dimensions: Vector2) -> void:
 var height: float=minf(dimensions.y*0.34,455.0)
 var slot: float=(height-44.0)*0.5
 var top: float=dimensions.y-height+34.0
 var radius: float=minf(slot*0.43,(slot-26.0)*0.5)
 var unit_pixels: int=maxi(10,roundi(clampf(radius*0.115,10.0,12.0)))
 var old_units: Rect2=glyph_bounds(panel._font,UNITS[0],dimensions.x*0.5,top+radius*2.0+33.0,unit_pixels)
 var next_ring_top: float=top+slot+1.0
 _check(old_units.position.y<next_ring_top and old_units.end.y>next_ring_top,"hud_old_actual_unit_glyph_crosses_next_ring_"+str(dimensions))
 var old_title: Rect2=glyph_bounds(panel._font,TITLES[0],dimensions.x*0.5,top+radius*2.0+20.0,maxi(10,roundi(clampf(radius*0.14,10.0,15.0))))
 _check(old_title.position.y<top+2.0*radius+12.0,"hud_old_title_overlaps_own_shadow_"+str(dimensions))

func _inspect(panel: CapturedPanel,label: String) -> void:
 var rows: Array[Dictionary]=caption_metadata(panel)
 var original: PackedByteArray=var_to_bytes({"snapshot":panel._snapshot,"readings":panel._readings,"held":panel._held,"info":panel._info})
 var viewport_rect: Rect2=Rect2(Vector2.ZERO,panel.size)
 for row in rows:
  _check(row.radius>40.0,"hud_readable_ring_floor_"+label+str(row.index))
  _check(row.cell.grow(0.001).encloses(row.shadow) and row.cell.grow(0.001).encloses(row.ring),"hud_ring_shadow_inside_allocation_"+label+str(row.index))
  var previous: Rect2=Rect2()
  for caption in row.captions:
   for kind in ["metric_bounds","glyph_bounds"]:
    var bounds: Rect2=caption[kind]
    _check(bounds.size.x>0 and bounds.size.y>0 and row.cell.grow(0.001).encloses(bounds) and viewport_rect.encloses(bounds),"hud_full_"+kind+"_inside_cell_viewport_"+label+str(row.index)+caption.text)
    for other in rows:
     _check(not bounds.intersects(other.ring) and not bounds.intersects(other.shadow),"hud_"+kind+"_clear_all_rings_shadows_"+label+str(row.index)+caption.text+str(other.index))
   _check(caption.pixels>=10 and not caption.text.contains("…"),"hud_complete_caption_floor_"+label+caption.text)
   if previous!=Rect2(): _check(not previous.intersects(caption.metric_bounds),"hud_two_complete_metric_lines_disjoint_"+label+str(row.index))
   previous=caption.metric_bounds
   var actual: Array=panel.drawn.filter(func(item: Dictionary) -> bool: return item.text==caption.text)
   _check(actual.size()==1 and actual[0].centered and actual[0].pixels==caption.pixels and actual[0].at.is_equal_approx(Vector2(row.center.x,caption.baseline)),"hud_actual_draw_uses_measured_complete_caption_"+label+caption.text)
  # Independent actual glyph extents for unchanged normal digital formats,
  # including the longest integer-boundary normal branch. Not value shrinking.
  var digital_pixels: int=maxi(10,roundi(maxf(13.0,row.radius*0.23)))
  for value in ["99999","-999999","+9999","359°"]:
   var bounds: Rect2=glyph_bounds(panel._font,value,row.center.x,row.center.y+row.radius*0.52,digital_pixels)
   var inside: bool=true
   for corner in [bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]: inside=inside and corner.distance_to(row.center)<row.radius-2.0
   _check(inside,"hud_unchanged_digital_glyphs_inside_face_"+label+str(row.index)+value)
  if panel.size.y<900.0:
   var footer_top: float=panel.size.y-23.0-panel._font.get_ascent(12)
   _check(row.captions[1].metric_bounds.end.y<=footer_top-3.9,"hud_compact_full_caption_before_held_footer_"+label+str(row.index))
 _check(var_to_bytes({"snapshot":panel._snapshot,"readings":panel._readings,"held":panel._held,"info":panel._info})==original,"hud_measurement_does_not_mutate_copied_truth_"+label)

func _fixture(state: String) -> Dictionary:
 var units: Dictionary={"tas":"m/s","ground_speed":"m/s","pitch":"rad","bank":"rad","heading_true":"rad","ellipsoid_height":"m","vertical_speed":"m/s","body_yaw_rate":"rad/s","fuel_total":"kg"}
 var values: Dictionary={"tas":30.0,"ground_speed":30.0,"pitch":0.1,"bank":0.2,"heading_true":1.0,"ellipsoid_height":1000.0,"vertical_speed":1.0,"body_yaw_rate":0.01,"fuel_total":50.0}
 var channels: Dictionary={}
 for id in units: channels[id]={"value":values[id],"unit":units[id],"valid":true,"error":""}
 return {"session_id":"hud-fixture","tick":"0","state":state,"native_truth":true,"readings":channels,"error":""}

func run(host: Node) -> Dictionary:
 _host=host
 var panel: CapturedPanel=CapturedPanel.new();host.add_child(panel)
 panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
 for dimensions in [Vector2(1920,1080),Vector2(2560,1440)]: _old_counterexample(panel,dimensions)
 _check(panel.has_method("_hud_caption_layout") and panel.has_method("_hud_instrument_cells"),"hud_actual_production_caption_allocation_present")
 for state in ["paused","historical","unavailable","large","default"]:
  var input: Dictionary=_fixture("historical" if state=="historical" else "paused")
  if state=="unavailable":
   for id in input.readings: input.readings[id]={"value":null,"unit":input.readings[id].unit,"valid":false,"error":"Explicit synthetic unavailable channel"}
  if state=="large":
   for id in ["tas","pitch","ellipsoid_height","heading_true","vertical_speed","body_yaw_rate"]: input.readings[id].value=1e12
  var source: Dictionary={"session_id":input.session_id,"tick":input.tick,"contacts":[]}
  if state=="default": input={};source={}
  var held: Dictionary={"throttle":0.3,"left_brake":0.0,"right_brake":0.0,"trim":0.0}
  var copied: PackedByteArray=var_to_bytes([input,source,held])
  panel.set_native_readings(input,source,held,{"paused":true})
  for dimensions in DIMENSIONS:
   panel.size=dimensions;panel.queue_redraw()
   await host.get_tree().process_frame
   await host.get_tree().process_frame
   _inspect(panel,state+str(dimensions))
  _check(var_to_bytes([input,source,held])==copied,"hud_all_view_changes_preserve_input_copies_"+state)
  _check(panel._info.retained==(state=="historical"),"hud_actual_retained_semantics_"+state)
 _check(panel._native_number(1e12,0)=="10.00e11" and panel._native_number(NAN,0)=="—","hud_original_large_unavailable_formatter")
 panel.set_panel_visible(false);panel.queue_redraw()
 await host.get_tree().process_frame
 await host.get_tree().process_frame
 _check(panel.drawn.filter(func(item: Dictionary) -> bool: return item.text in TITLES or item.text in UNITS).is_empty() and not panel._panel_visible,"hud_requested_hidden_stays_hidden_no_instrument_captions")
 for index in 6: _check(panel._physical_dial_caption(index,TITLES[index],UNITS[index])=={"text":TITLES[index]+" · "+UNITS[index],"baseline":262.7 if index<3 else 485.0,"pixels":12},"hud_physical_caption_exact_"+str(index))
 panel.free()
 return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"scope":"Actual production HUD geometry/drawing plus shaped fallback glyph extents and original old-formula negatives; synthetic copied presentation sets only, no native/Windows-pixel/aircraft acceptance"}
