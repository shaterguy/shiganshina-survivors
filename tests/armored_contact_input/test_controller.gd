extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")
const CitySupport = preload("res://tests/app_city_controller/controller_city_support.gd")
const P = preload("res://tests/armored_contact_input/test_producer.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const F = preload("res://tests/core/core_fixture.gd")
const C = preload("res://tests/armored_contact_input/city_fixture.gd")
class ObservedWorld:
 extends "res://game/presentation/world_view.gd"
 var deliveries: Array = []
 var frames: Array = []
 func consume_combat_events(events: Array[Dictionary], snapshot: Dictionary) -> void:
  super.consume_combat_events(events,snapshot)
  deliveries.append({"events":events.duplicate(true),"snapshot":snapshot.duplicate(true),"observation":armored_motion_observation()})
 func present(snapshot: Dictionary) -> void:
  super.present(snapshot)
  frames.append(armored_motion_observation())
 func present_city(snapshot: Dictionary, terrain: Dictionary) -> Dictionary:
  var result: Dictionary = super.present_city(snapshot,terrain)
  if result.get("ok",false): frames.append(armored_motion_observation())
  return result
func observe(app):
 app.world.free()
 var w := ObservedWorld.new(); app.world = w; app.add_child(w); w.set_process(false)
 return w
func run(t) -> void:
 var p := P.new(); var f := p.wall()
 var previous: Array = []
 for i in 150:
  previous.append(f.state.duplicate(true))
  if previous.size() > 4: previous.pop_front()
  var a := S.actor(f.state)
  if a.action_state == "attack":
   var speed: float = f.core._final_charge_speed(f.state.rules.enemy_catalog.armored_titan.action_profile,int(f.state.active_tick)+1-int(a.action_started_tick))
   var sweep: Dictionary = f.core._final_contact_sweep(f.state,Vector2(a.position[0],a.position[1]),Vector2.RIGHT*speed/60.0,Vector2.RIGHT,f.state.rules.enemy_catalog.armored_titan.action_profile,null)
   if sweep.stopped: break
  S.step(f)
 var restored: Dictionary = f.core.restore(previous[0])
 t.check(restored.get("ok",false),"catch-up begins from restore-valid actual charge")
 var fixture := Support.new().make(t); var app = fixture.app; app.start_run(42)
 app.simulation = f.core; app.state = restored.state; app.chapter = f.chapter
 app._last_phase = app.state.phase; app._last_save_tick = app.state.active_tick
 var w = observe(app); w.present(app.simulation.snapshot(app.state)); w.frames.clear()
 var root_before: Array = S.actor(app.state).position.duplicate(); var start: int = app.state.active_tick
 app.advance_frame(8.0/60.0)
 t.check(w.deliveries.size() == 8 and w.frames.size() == 1,"real Controller eight-tick catch-up forwards eight successes and one final presentation")
 var contact_index := -1
 for i in w.deliveries.size():
  var packet: Dictionary = w.deliveries[i]
  t.check(int(packet.snapshot.active_tick) == start+i+1,"catch-up exact snapshot at input "+str(i))
  if F.types(packet.events,"final_charge_contact").size() == 1: contact_index = i
 t.check(contact_index == 3,"actual wall contact occurs in middle fourth successful tick")
 var obs: Dictionary = w.armored_motion_observation()
 t.check(obs.contact_count == 1 and obs.phase == "brake" and obs.phase_age == 4,"one final frame sees one contact and current Core brake age")
 var partial: float = w.deliveries[3].snapshot.entities[0].position[0]-w.deliveries[2].snapshot.entities[0].position[0]
 t.check(is_equal_approx(obs.distance,78.0-float(root_before[0])) and is_equal_approx(obs.last_travel,partial),"final frame retains exact total and last partial accepted charge travel")
 app.set_user_pause(true); var paused: Dictionary = w.armored_motion_observation(); app.advance_frame(0.5)
 t.check(w.deliveries.size() == 8 and w.armored_motion_observation() == paused,"pause delivers no tick and never ages contact")
 t.check(app.audio.sound_for_event(w.deliveries[3].events.filter(func(e): return e.type == "final_charge_contact")[0]).is_empty(),"input-only event has no audio mapping")
 app.free()
 _city_catchup(t)
 # Actual city Controller rejects failed Core ticks before presentation delivery.
 var city := C.new().make(t); var cf := CitySupport.make(t); var ca = cf.app; ca.start_run(42)
 ca.simulation = city.core; ca.state = city.state; ca.chapter = city.chapter
 ca._last_phase = ca.state.phase; ca._last_save_tick = ca.state.active_tick
 var box: Rect2 = city.target.ground_footprint
 ca.state.player.position = [box.position.x-9.0,box.get_center().y]
 ca.state.player.attack_ready_ticks.blade_slash = ca.state.active_tick
 t.check(ca.simulation.prepare_world(ca.state,C.HF.hydration(C.H.requirements(ca.state))).get("ok",false),"failed-city Controller uses prepared real impact")
 city.audit.armed = true
 var cw = observe(ca); cw.present(ca.simulation.snapshot(ca.state))
 var baseline: Dictionary = ca.state.duplicate(true)
 ca.advance_frame(8.0/60.0)
 t.check(cw.deliveries.is_empty() and ca.state == baseline and not ca._city_step_error.is_empty(),"late failed city tick yields no successful event delivery")
 ca.free()

func _city_catchup(t) -> void:
 var city := C.new().make(t)
 var cf := CitySupport.make(t,ProjectSettings.globalize_path("user://contact_city_catchup_%d_%d/saves"%[OS.get_process_id(),Time.get_ticks_usec()]))
 var app = cf.app; app.start_run(42)
 city.state = city.previous_states[0].duplicate(true)
 city.state.run_id = app.state.run_id; city.state.run_config = app.state.run_config.duplicate(true)
 t.check(city.core.prepare_world(city.state,C.HF.hydration(C.H.requirements(city.state))).get("ok",false),"city catch-up earlier natural attack snapshot prepares")
 var passage: Dictionary = city.core._streamed.passage_proposal(city.state)
 t.check(passage.get("ok",false),"city catch-up selects actual passage outside player position")
 city.state.world = passage.world
 var candidate: Dictionary = app.game_save.duplicate(true); candidate.checkpoint = city.state.duplicate(true)
 app._commit_candidate(candidate,"checkpoint",{},true)
 t.check(app.state.active_tick == city.state.active_tick,"city catch-up pre-impact checkpoint actually adopted")
 var w = observe(app); w.present_city(app.simulation.snapshot(app.state),_terrain(app)); w.frames.clear()
 var first: int = app.state.active_tick; var x: float = S.actor(app.state).position[0]
 app.advance_frame(8.0/60.0)
 t.check(w.deliveries.size() == 8 and w.frames.size() == 1,"actual streamed Controller forwards eight successes and one final city frame")
 var found := -1
 for i in w.deliveries.size():
  t.check(w.deliveries[i].snapshot.active_tick == first+i+1,"city catch-up exact successful tick "+str(i))
  if F.types(w.deliveries[i].events,"final_charge_contact").size() == 1: found = i
 t.check(found == 3,"actual streamed shoulder contact occurs on fourth catch-up tick")
 var final: Dictionary = w.armored_motion_observation()
 var partial: float = w.deliveries[3].snapshot.entities[0].position[0]-w.deliveries[2].snapshot.entities[0].position[0]
 t.check(final.contact_count == 1 and final.phase_age == 4 and is_equal_approx(final.distance,float(S.actor(app.state).position[0])-x) and is_equal_approx(final.last_travel,partial),"one final city frame retains current phase and exact accepted partial movement")
 app.free()
func _terrain(app) -> Dictionary:
 var terrain: Dictionary = app.simulation.world_render_view(app.state)
 terrain.world_revision = app.state.world.world_revision
 return terrain
