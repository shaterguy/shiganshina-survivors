extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")
const P = preload("res://tests/armored_contact_input/test_producer.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const R = preload("res://tests/armored_charge_distance/test_restore.gd")
const Dispatch = preload("res://tests/armored_contact_input/test_controller.gd")
func run(t) -> void:
 var p := P.new(); var f := p.wall(); var previous: Array = []
 for n in 150:
  previous.append(f.state.duplicate(true)); if previous.size() > 4: previous.pop_front()
  var a := S.actor(f.state)
  if a.action_state == "attack":
   var speed: float = f.core._final_charge_speed(f.state.rules.enemy_catalog.armored_titan.action_profile,int(f.state.active_tick)+1-int(a.action_started_tick))
   var sweep: Dictionary = f.core._final_contact_sweep(f.state,R.vec(a.position),Vector2.RIGHT*speed/60.0,Vector2.RIGHT,f.state.rules.enemy_catalog.armored_titan.action_profile,null)
   if sweep.stopped: break
  S.step(f)
 var result: Dictionary = f.core.restore(previous[0]); t.check(result.get("ok",false),"whole-distance catch-up starts from actual restore-valid midcharge")
 var fixture := Support.new().make(t); var app = fixture.app; app.start_run(42)
 app.simulation = f.core; app.state = result.state; app.chapter = f.chapter; app._last_phase = app.state.phase; app._last_save_tick = app.state.active_tick
 var w = Dispatch.new().observe(app); w.present(app.simulation.snapshot(app.state)); w.frames.clear()
 var origin: Array = S.actor(app.state).locked_origin.duplicate(); var root: Array = S.actor(app.state).position.duplicate(); var start: int = app.state.active_tick
 var seed := R.scalar_distance(root,origin); var seeded: Dictionary = w.armored_motion_observation()
 t.check(seeded.get("charge_distance_known",false) and seeded.get("charge_distance",-1.0) == seed and seeded.distance == 0.0,"midcharge Controller present seeds prefix while old window stays zero")
 app.advance_frame(8.0/60.0)
 t.check(w.deliveries.size() == 8 and w.frames.size() == 1,"actual eight-tick Controller delivers every success and one final frame")
 var expected := seed; var prior: Array = root; var contact_index := -1
 for n in w.deliveries.size():
  var packet: Dictionary = w.deliveries[n]; var a := S.actor(packet.snapshot)
  if n == 0 or S.actor(w.deliveries[n-1].snapshot).action_state == "attack": expected += R.scalar_distance(a.position,prior)
  t.check(packet.observation.get("charge_distance_known",false) and packet.observation.get("charge_distance",-1.0) == expected,"Controller exact whole-distance at successful input "+str(n))
  t.check(packet.snapshot.active_tick == start+n+1,"Controller accepted input clock "+str(n))
  if not packet.events.filter(func(e): return e.type == "final_charge_contact").is_empty(): contact_index = n
  prior = a.position.duplicate()
 var final: Dictionary = w.armored_motion_observation()
 t.check(contact_index == 3 and final.contact_count == 1 and final.phase_age == 4,"partial contact at fourth tick retains one current impact at final frame")
 t.check(final.get("charge_distance",-1.0) == R.scalar_distance(S.actor(app.state).position,origin) and final.get("charge_distance",-1.0) == expected,"final catch-up frame restores exact accepted charge root, including nominal-wall rounding")
 t.check(final.distance == float(S.actor(app.state).position[0])-float(root[0]),"existing Controller adoption-window distance remains exact accepted tail")
 app.set_user_pause(true); var frozen: Dictionary = w.armored_motion_observation(); app.advance_frame(0.5)
 t.check(w.deliveries.size() == 8 and w.armored_motion_observation() == frozen,"actual Controller pause cannot alter whole-charge observation")
 if t.get("traces") is Array: t.traces.append({"id":"eight_tick_controller","adoption":seeded,"final":final,"expected":expected,"contact_index":contact_index})
 app.free()
