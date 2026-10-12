extends RefCounted
const C = preload("res://tests/armored_contact_input/city_fixture.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const F = preload("res://tests/core/core_fixture.gd")
const World = preload("res://game/presentation/world_view.gd")
const Address = preload("res://game/world/world_address.gd")
const Final = preload("res://tests/final_runtime/final_support.gd")
const Dispatch = preload("res://tests/armored_contact_input/test_controller.gd")
func run(t) -> void:
 _rebase(t)
 for failure in ["none","write","unknown"]: _dock(t,failure)
func _rebase(t) -> void:
 var f := C.new().make(t)
 var events := S.step(f)
 var w := World.new(); w.consume_combat_events(events,f.core.snapshot(f.state))
 var old: Dictionary = w.armored_motion_observation()
 t.check(not old.contact.is_empty(),"rebase starts with actual committed city contact")
 f.state.player.position = [766.0,384.0]
 t.check(f.core.prepare_world(f.state,C.HF.hydration(C.H.requirements(f.state))).get("ok",false),"pre-rebase player road boundary is Core valid")
 w.consume_combat_events(S.step(f,Vector2.RIGHT),f.core.snapshot(f.state))
 var pending: Dictionary = f.state.duplicate(true)
 var unchanged: Dictionary = w.armored_motion_observation()
 t.check(f.state.player.position[0] >= 768,"actual accepted player step crosses origin boundary")
 f.audit.rebase_fault = true; f.audit.base_revision = f.state.world.origin_revision
 var bad := S.step(f)
 t.check(bad.is_empty() and f.state == pending,"failed rebase preparation adopts no state")
 w.consume_combat_events(bad,f.core.snapshot(f.state))
 t.check(w.armored_motion_observation() == unchanged,"failed rebase does not clear or translate accepted contact")
 f.audit.rebase_fault = false
 var accepted := S.step(f)
 t.check(f.core.step_status().ok and f.state.world.origin_revision == old.origin_revision+1,"real Core rebase succeeds on repaired retry")
 w.consume_combat_events(accepted,f.core.snapshot(f.state))
 var now: Dictionary = w.armored_motion_observation()
 for key in ["root_position","point","center"]:
  t.check(now.contact[key] == [old.contact[key][0]-768.0,old.contact[key][1]],"cached contact translated exactly once "+key)
 for key in ["tick","event_id","attack_started_tick","normal","locked_direction"]:
  t.check(now.contact[key] == old.contact[key],"rebase preserves non-position contact field "+key)
 t.check(now.contact.origin_revision == now.origin_revision and now.rebase_count == 1 and now.distance == old.distance,"translated contact revision agrees without added distance")
 var terrain: Dictionary = f.core.world_render_view(f.state); terrain.world_revision = f.state.world.world_revision
 for i in 3: t.check(w.present_city(f.core.snapshot(f.state),terrain).ok,"repeated real city presentation remains valid")
 t.check(w.armored_motion_observation() == now,"present never translates same rebase twice")
 w.free()
func _dock(t, failure: String) -> void:
 var f := Final.make(t,ProjectSettings.globalize_path("user://contact_dock_%d_%d/saves"%[OS.get_process_id(),Time.get_ticks_usec()]),false); var app = f.app; app.start_run(42)
 var city := C.new().make(t); city.state.run_id = app.state.run_id; city.state.run_config = app.state.run_config.duplicate(true)
 # Commit an actual restore-valid pre-impact city checkpoint via the existing
 # Controller/store boundary, then perform the real contact through Controller.
 var candidate: Dictionary = app.game_save.duplicate(true); candidate.checkpoint = city.state.duplicate(true)
 app._commit_candidate(candidate,"checkpoint",{},true)
 t.check(app.state.active_tick == city.state.active_tick and app.state.world.stage == "city","dock fixture adopts real pre-impact city checkpoint "+failure)
 var w = Dispatch.new().observe(app)
 app.advance_frame(1.0/60.0)
 var impacts: Array = []
 for packet in w.deliveries: impacts.append_array(F.types(packet.events,"final_charge_contact"))
 t.check(impacts.size() == 1 and not w.armored_motion_observation().get("contact",{}).is_empty(),"actual Controller contact precedes dock "+failure)
 if impacts.is_empty(): app.free(); return
 t.check(not app.state.world.evacuation.is_empty(),"actual final flow selects passage before dock "+failure)
 var target := Address.relative(app.state.world.evacuation.chunk,Vector2(384,384),app.state.world.origin_chunk)
 t.check(target.ok,"selected passage has current local address "+failure)
 app.state.player.position = [target.local.x,target.local.y]
 var prepared: Dictionary = f.runtime.refresh_coverage(app.state)
 t.check(prepared.get("ok",false),"dock approach prepares real geometry "+failure)
 if not prepared.get("ok",false): app.free(); return
 app.simulation = prepared.simulation; app.state = prepared.state
 var source: Dictionary = app.state.duplicate(true); var observed: Dictionary = w.armored_motion_observation()
 var fault := {"replaced":false}
 if failure == "write":
  app.save_store._fault_injector = func(stage): return ERR_CANT_OPEN if stage == "write" else OK
 elif failure == "unknown":
  app.save_store._fault_injector = func(stage):
   if stage == "after_replace_before_return": fault.replaced = true; return ERR_CANT_OPEN
   return ERR_CANT_OPEN if fault.replaced and stage.begins_with("read_") else OK
 app._advance_final_flow()
 if failure != "none":
  t.check(app.state.world.stage == "city" and app.state == source and w.armored_motion_observation() == observed,"failed/unknown dock retains exact city contact until adoption "+failure)
  if failure == "unknown": t.check(fault.replaced and not app._pending_transaction.is_empty(),"unknown dock genuinely committed but remains unconfirmed")
  app.save_store._fault_injector = Callable()
  app.retry_final_transition()
 t.check(app.state.world.stage == "dock","existing Controller confirms real dock adoption "+failure)
 var actor := S.actor(app.state); var original := S.actor(source)
 t.check(app.state.active_tick == source.active_tick and app.state.event_seq == source.event_seq and actor.id == original.id and actor.action_started_tick == original.action_started_tick and actor.action_ends_tick == original.action_ends_tick and app.state.final_started_tick == source.final_started_tick,"same-tick dock preserves actor clocks ID and final75sec epoch "+failure)
 var dock: Dictionary = w.armored_motion_observation()
 t.check(dock.contact.is_empty() and dock.distance == 0 and dock.mode == "restored_grounded","dock synchronous reset/present clears impact and anchor travel "+failure)
 var stale: Array[Dictionary] = []; stale.assign(impacts)
 w.consume_combat_events(stale,app.simulation.snapshot(app.state))
 t.check(w.armored_motion_observation() == dock,"same-tick/sequence stale city impact cannot replay in dock before draw "+failure)
 print("DOCK_INPUT ",JSON.stringify({"case":failure,"stage":app.state.world.stage,"tick":app.state.active_tick,"seq":app.state.event_seq,"mode":dock.mode,"contacts":dock.contact_count,"distance":dock.distance}))
 app.free()
