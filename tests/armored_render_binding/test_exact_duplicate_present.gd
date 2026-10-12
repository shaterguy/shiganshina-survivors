extends RefCounted
const S=preload("res://tests/armored_actor/armored_support.gd")
class ObservedPose:
 extends "res://game/presentation/armored/armored_pose.gd"
 var observations:=0
 func observe(observation:Dictionary,actor:Dictionary)->void:
  observations+=1
  super.observe(observation,actor)
func run(t)->void:
 var f:=S.make(); S.begin(f); S.arrange_windup(f,Vector2(-210,0),Vector2(160,0))
 for n in 100:
  var actor:=S.actor(f.state)
  if actor.action_state=="attack" and f.state.active_tick-actor.action_started_tick==12:break
  S.step(f)
 var w=load("res://game/presentation/world_view.gd").new()
 w._armored_pose=ObservedPose.new(); t.root.add_child(w); w.set_process(false)
 w._viewport_size=Vector2(2000,1000)
 var snapshot:Dictionary=f.core.snapshot(f.state)
 w.present(snapshot)
 t.check(w.armored_raster_status().supported,"duplicate fixture reaches actual supported charge")
 var generation:int=w.armored_raster_status().generation
 for n in 20:w.present(snapshot)
 t.check(w._armored_pose.observations==1 and w.armored_raster_status().generation==generation,"identical owned actor and observation skip pose compilation and packet validation")
 var requests:int=w._armored_raster.debug_stats().update_requests
 w._viewport_size=Vector2.ONE
 var events:=S.step(f); snapshot=f.core.snapshot(f.state)
 w.consume_combat_events(events,snapshot); w.present(snapshot)
 t.check(w._armored_pose.observations==2,"new accepted tick still compiles its actual pose")
 t.check(w._armored_raster.debug_stats().update_requests==requests and not w._armored_raster._actor_visible and w._armored_raster._dirty,"offscreen changed pose is retained without a cancelled viewport update request")
 w._viewport_size=Vector2(2000,1000); w.present(snapshot)
 t.check(w._armored_pose.observations==2 and w._armored_raster.debug_stats().update_requests==requests+1,"camera-only visibility returns latest retained pose exactly once")
 snapshot.entities[0].hp-=1
 w.present(snapshot)
 t.check(w._armored_pose.observations==3,"mutating caller-owned actor cannot mutate the previous cache key")
 var valid=snapshot.entities[0].pattern_index
 snapshot.entities[0].pattern_index=true
 w.present(snapshot)
 t.check(not w.armored_raster_status().supported and w._armored_pose.observations==4,"type-distinct malformed actor cannot reuse a successful pose")
 snapshot.entities[0].pattern_index=valid
 w.present(snapshot)
 t.check(w.armored_raster_status().supported and w._armored_pose.observations==5,"rejected input does not poison the next valid observation")
 w.reset_presentation(); w.present(snapshot)
 t.check(w._armored_pose.observations==6,"reset invalidates the derived-input cache")
 w.free(); await t.process_frame
