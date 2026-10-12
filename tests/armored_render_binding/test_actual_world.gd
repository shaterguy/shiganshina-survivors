extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const W = preload("res://game/presentation/world_view.gd")
func run(t) -> void:
 var w := W.new(); t.root.add_child(w); w.set_process(false)
 t.check(w.has_method("armored_raster_status"),"WorldView owns one actual actor raster binding")
 if not w.has_method("armored_raster_status"): w.free(); return
 var f := S.make(); S.begin(f); S.arrange_windup(f,Vector2(-210,0),Vector2(160,0))
 var snapshot: Dictionary = f.core.snapshot(f.state); var prior := snapshot.duplicate(true)
 w.present(snapshot)
 t.check(not w.armored_raster_status().supported,"unreviewed warning has explicit atlas fallback")
 t.check(snapshot==prior,"presentation does not mutate authoritative snapshot")
 var submitted := 0
 for n in 85:
  var events := S.step(f); snapshot=f.core.snapshot(f.state); prior=snapshot.duplicate(true)
  w.consume_combat_events(events,snapshot); w.present(snapshot)
  var status: Dictionary = w.armored_raster_status(); var actor := S.actor(f.state)
  if actor.action_state=="attack":
   submitted+=1
   t.check(status.supported and status.pose_tick==snapshot.active_tick,"real charge uses current successful Core tick")
   t.check(status.root_position==Vector2(actor.position[0],actor.position[1]) and status.actor_id==str(actor.id),"raster uses actual actor and root")
   var packet: Dictionary = w._city_render_packet()
   var style: Dictionary = w._city_draw_data.actor[actor.id]
   t.check(style.get("armored_raster",false) and style.position==status.root_position and style.render_bounds.has_area(),"actual sorted depth packet adopts raster bounds")
   var count := 0
   for command in packet.upright:
    if command.id=="actor:i:"+str(actor.id): count+=1
   t.check(count==1,"physical actor appears once in sorted world packet")
   var generation: int=status.generation
   w.present(snapshot)
   t.check(w.armored_raster_status().generation==generation,"duplicate presentation does not submit another raster generation")
  t.check(snapshot==prior,"actual event and display consumer retain exact authoritative snapshot")
 t.check(submitted>0,"test reached real charge rather than only constructing a draw DTO")
 w.reset_presentation()
 t.check(not w.armored_raster_status().supported,"reset clears observed actor without replay")
 w.free()
 await t.process_frame
