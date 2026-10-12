extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const Support = preload("res://tests/app/controller_test_support.gd")
const W = preload("res://game/presentation/world_view.gd")
func run(t) -> void:
 var f := S.make(); S.begin(f); S.arrange_windup(f,Vector2(-210,0),Vector2(160,0))
 for n in 100:
  var a := S.actor(f.state)
  if a.action_state=="attack" and f.state.active_tick-a.action_started_tick==2: break
  S.step(f)
 var fixture := Support.new().make(t); var app=fixture.app; app.start_run(42)
 app.simulation=f.core; app.state=f.state; app.chapter=f.chapter
 app._last_phase=app.state.phase; app._last_save_tick=app.state.active_tick
 app.world.present(app.simulation.snapshot(app.state))
 var before: Dictionary=app.world.armored_raster_status(); var tick: int=app.state.active_tick
 t.check(before.supported,"real Controller uses a current live charge raster before catch-up")
 app.advance_frame(8.0/60.0)
 var status: Dictionary=app.world.armored_raster_status(); var actor:=S.actor(app.state)
 t.check(status.supported and app.state.active_tick==tick+8 and status.pose_tick==app.state.active_tick,"eight accepted Core ticks render the final actor tick")
 t.check(status.generation==before.generation+1,"only final presentation compiles/submits once per catch-up frame")
 t.check(status.root_position==Vector2(actor.position[0],actor.position[1]),"Controller final raster root is current actor, not preceding packet")
 app.set_user_pause(true); var paused: Dictionary=app.world.armored_raster_status(); app.advance_frame(.5)
 t.check(app.world.armored_raster_status()==paused and app.state.active_tick==tick+8,"pause freezes generation, accepted tick and root")
 var restored: Dictionary=app.simulation.restore(app.state)
 t.check(restored.get("ok",false),"live midcharge checkpoint stays valid")
 var fresh:=W.new(); t.root.add_child(fresh); fresh.set_process(false)
 fresh.present(app.simulation.snapshot(restored.state))
 var cold: Dictionary=fresh.armored_raster_status()
 t.check(cold.supported and cold.pose_tick==status.pose_tick and cold.root_position==status.root_position,"fresh consumer rebuilds known-distance charge from restored Core")
 t.check(fresh._armored_raster.local_bounds().is_equal_approx(app.world._armored_raster.local_bounds()),"restored whole-distance phase reproduces native bounds")
 fresh.free(); app.free()
 await t.process_frame
