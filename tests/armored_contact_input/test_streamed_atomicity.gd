extends RefCounted
const C = preload("res://tests/armored_contact_input/city_fixture.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const F = preload("res://tests/core/core_fixture.gd")
const World = preload("res://game/presentation/world_view.gd")
func run(t) -> void:
 var f := C.new().make(t)
 if f.is_empty(): return
 # Keep the actual player in walkable space left of the structure. Real blade
 # acquisition now queries cover after the actual contact and structure commit.
 var point: Vector2 = f.target.ground_footprint.position
 f.state.player.position = [point.x-9.0,f.target.ground_footprint.get_center().y]
 f.state.player.attack_ready_ticks.blade_slash = f.state.active_tick
 t.check(f.core.prepare_world(f.state,C.HF.hydration(C.H.requirements(f.state))).get("ok",false),"late-fault arranged player restores and coverage prepares")
 var before: Dictionary = f.state.duplicate(true); var helper = f.core._streamed
 f.audit.armed = true
 var rejected := S.step(f)
 t.check(f.audit.get("injected",false) and f.audit.get("saw_tentative",false) and f.audit.get("fault_phase") in ["auto_attack","player_damage"],"real combat cover failure sees already-emitted tentative contact")
 t.check(rejected.is_empty() and f.state == before and f.core._streamed == helper and f.core._final_sweeps.is_empty(),"late sticky geometry refusal rolls back contact HP RNG structure clock counter and helper")
 print("LATE_FAILURE ",JSON.stringify({"audit":f.audit,"status":f.core.step_status(),"unchanged":f.state == before,"same_helper":f.core._streamed == helper}))
 f.audit.armed = false
 var events := S.step(f)
 t.check(F.types(events,"final_charge_contact").size() == 1 and F.types(events,"structure_destroyed").size() == 1 and f.core.step_status().ok,"repair retries same actual impact once")
 var w := World.new(); w.consume_combat_events(events,f.core.snapshot(f.state))
 var observation: Dictionary = w.armored_motion_observation()
 var current: Dictionary = f.state.duplicate(true)
 # Force a later failed real cover query without adopting an older state.
 f.state.player.attack_ready_ticks.blade_slash = f.state.active_tick
 current = f.state.duplicate(true); f.audit.armed = true
 var failed_again := S.step(f)
 t.check(failed_again.is_empty() and f.state == current,"post-contact speculative failure keeps live snapshot")
 w.consume_combat_events(failed_again,f.core.snapshot(f.state))
 t.check(w.armored_motion_observation() == observation,"speculative rejected tick preserves previously committed visual impact")
 w.free()
 # Determine exact demand from a real structure + physical player-hit tick.
 var budget := C.new().make(t)
 var box: Rect2 = budget.target.ground_footprint
 budget.state.player.position = [box.position.x-9.0,box.get_center().y]
 budget.state.player.invulnerable_until = 0
 t.check(budget.core.prepare_world(budget.state,C.HF.hydration(C.H.requirements(budget.state))).get("ok",false),"streamed counter input restores and coverage prepares")
 var base: Dictionary = budget.state.duplicate(true)
 var real := S.step(budget); var demand := real.size()
 t.check(F.types(real,"final_charge_contact").size() == 1 and F.types(real,"structure_destroyed").size() == 1 and F.types(real,"damage").size() == 1 and demand == 3,"real contact plus later structure and damage require three event slots")
 for missing in [0,1]:
  var core := C.ObservedCore.new(budget.provider,C.FaultCoverHelper.new(budget.chapter.world_definitions,{}))
  var state: Dictionary = base.duplicate(true); state.event_seq = 2147483647-demand+missing
  var hydration: Dictionary = C.HF.hydration(C.H.requirements(state))
  t.check(core.prepare_world(state,hydration).get("ok",false),"streamed near-limit state prepares")
  var old: Dictionary = state.duplicate(true); var old_helper = core._streamed
  var packet := F.step(core,state,Vector2.ZERO,C.Director.new().plan(state,budget.chapter))
  if missing == 0:
   t.check(packet.size() == demand and state.event_seq == 2147483647 and state.player.hp < old.player.hp,"streamed exact full event capacity adopts all later events")
  else:
   t.check(packet.is_empty() and state == old and core._streamed == old_helper and core._final_sweeps.is_empty(),"streamed one slot short rolls back tentative contact and later damage/structure")
   state.event_seq -= 1
   var retry := F.step(core,state,Vector2.ZERO,C.Director.new().plan(state,budget.chapter))
   t.check(retry.size() == demand and F.types(retry,"final_charge_contact").size() == 1 and state.event_seq == 2147483647,"streamed repaired counter retry publishes one complete contact tick")
 print("STREAMED_EVENT_BUDGET ",JSON.stringify({"demand":demand,"types":real.map(func(e): return e.type)}))
