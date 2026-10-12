extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
class ObservedWorld:
 extends "res://game/presentation/world_view.gd"
 var submissions: Array=[]
 func _world_transform(position: Vector2, rotation:=0.0, scale_value:=Vector2.ONE) -> void:
  submissions.append({"kind":"transform","tail":is_instance_valid(_armored_split) and _armored_split.routing_tail(),"position":position,"rotation":rotation,"scale":scale_value})
  if is_instance_valid(_armored_split) and _armored_split.routing_tail(): super._world_transform(position,rotation,scale_value)
 func _world_region(texture: Texture2D, rect: Rect2, region: Rect2, color:=Color.WHITE) -> void:
  submissions.append({"kind":"region","tail":is_instance_valid(_armored_split) and _armored_split.routing_tail(),"rect":rect,"region":region,"color":color})
  if is_instance_valid(_armored_split) and _armored_split.routing_tail(): super._world_region(texture,rect,region,color)
 func _world_rect(texture: Texture2D, rect: Rect2, tiled: bool, color:=Color.WHITE) -> void:
  submissions.append({"kind":"rect","tail":is_instance_valid(_armored_split) and _armored_split.routing_tail(),"rect":rect,"tiled":tiled,"color":color})
  if is_instance_valid(_armored_split) and _armored_split.routing_tail(): super._world_rect(texture,rect,tiled,color)
 func _draw_armored_raster() -> bool:
  var accepted:=super._draw_armored_raster()
  submissions.append({"kind":"armored","accepted":accepted})
  return accepted
func run(t) -> void:
 for sign_value in [1,-1]:
  var f:=S.make(); S.begin(f); S.arrange_windup(f,Vector2(-210*sign_value,0),Vector2(160*sign_value,0))
  for n in 100:
   var a:=S.actor(f.state)
   if a.action_state=="attack" and f.state.active_tick-a.action_started_tick==12: break
   S.step(f)
  var w:=ObservedWorld.new();t.root.add_child(w);w.set_process(false)
  var snapshot: Dictionary=f.core.snapshot(f.state);w.present(snapshot)
  var status: Dictionary=w.armored_raster_status()
  t.check(status.supported and status.flip==(sign_value<0),"both actual horizontal directions bind with final texture mirror")
  var view: Dictionary=w._actor_view(S.actor(f.state).id,"armored_titan",status.root_position,"attack",1.5,status.flip,0)
  var transform: Transform2D=w._armored_world_transform()
  var opaque:=0;var clear:=0
  for y in range(0,288,8):
   for x in range(0,288,8):
    var local:=Vector2(x+.5,y+.5);var world:=transform*local
    var expected: bool=w._armored_raster.is_opaque_local(local)
    t.check(w._armored_opaque(world)==expected,"world inverse/scale/mirror uses same accepted native alpha sample")
    if expected: opaque+=1
    else: clear+=1
  t.check(opaque>0 and clear>0 and view.render_bounds==transform*w._armored_raster.local_bounds(),"alpha test covers both silhouette and holes using same transformed bounds")
  w._draw()
  var actors:=0;var before:=0;var after:=0;var at_actor:=false
  for submitted in w.submissions:
   if submitted.kind=="armored": actors+=1;at_actor=true;t.check(submitted.accepted,"actual depth pass inserts actor once")
   else:
    t.check(submitted.tail==at_actor,"existing sorted draw traversal only routes later commands to ordinary foreground")
    if at_actor:after+=1
    else:before+=1
  t.check(actors==1 and before>0 and after>0 and w._armored_split.debug_stats().tail_commands==after,"real WorldView traversal keeps before/actor/after passes and old player/warnings above")
  w.reset_presentation()
  t.check(not w._armored_split.routing_tail(),"run reset clears the real tail routing immediately")
  w.free()
 await t.process_frame
