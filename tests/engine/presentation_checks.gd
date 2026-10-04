extends RefCounted
# Original MIT. Actual menu/container layout; synthetic presentation-only scene.
const Scene=preload("res://simulation/flight_scene.gd")
const Controls=preload("res://ui/controls/controls_panel.gd")
const Mapper=preload("res://input/input_mapper.gd")
const Preset=preload("res://input/input_preset.gd")
class SyntheticScene extends Scene:
 func _ready()->void:pass
 func _process(_seconds:float)->void:pass
 func pause_session(value:bool)->bool:
  paused=value
  return true
var checks:int=0
var failures:Array[String]=[]
var observations:Array=[]
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures.append(label)
func run(host:Node)->Dictionary:
 for dimensions in [Vector2i(960,540),Vector2i(1280,720)]:
  var viewport:=SubViewport.new();viewport.size=dimensions;host.add_child(viewport)
  var scene=SyntheticScene.new();viewport.add_child(scene)
  var canvas:=CanvasLayer.new();scene.add_child(canvas);scene.make_menu(canvas)
  for profile in ["original-interactive-prototype","original-piston-prop-v1"]:
   scene.selected_profile=profile;scene.paused=true
   scene.open_menu("Confirm controls")
   await host.get_tree().process_frame
   await host.get_tree().process_frame
   scene.layout_flight_menu()
   var rect:Rect2=scene.menu.get_global_rect();var bounds:Rect2=Rect2(Vector2.ZERO,Vector2(dimensions))
   check(bounds.encloses(rect),"menu_inside_"+profile+"_"+str(dimensions))
   for button in scene.menu.find_children("*","Button",true,false):
    if button.is_visible_in_tree():check(bounds.encloses(button.get_global_rect()),"button_inside_"+button.text+"_"+str(dimensions))
   var message:String=scene.menu_message.text
   check((message.contains("idealized starter") and not message.contains("Engine already running")) if profile=="original-piston-prop-v1" else (message.contains("Engine already running") and not message.contains("idealized starter")),"profile_instructions_"+profile)
   check(scene.profile_button.text.contains("cold piston") if profile=="original-piston-prop-v1" else scene.profile_button.text.contains("ready-to-fly"),"explicit_profile_choice_"+profile)
   observations.append({"size":[dimensions.x,dimensions.y],"profile":profile,"menu":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"combined_minimum":[scene.menu.get_combined_minimum_size().x,scene.menu.get_combined_minimum_size().y]})
  viewport.queue_free();await host.get_tree().process_frame
 return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"observations":observations.duplicate(true),"scope":"actual headless UI/container/font layout; synthetic paused presentation; no _ready/native/GPU"}
