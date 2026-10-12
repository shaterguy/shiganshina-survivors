extends RefCounted
# Fixtures copied from the frozen restored-phase probe; this new contract suite
# uses only actual Core.restore and contacts from successful Core.step calls.
const S = preload("res://tests/armored_actor/armored_support.gd")
const Core = preload("res://game/core/run_simulation.gd")
const W = preload("res://game/presentation/world_view.gd")
static func scalar_distance(a: Array,b: Array) -> float:
 var dx := float(a[0])-float(b[0]); var dy := float(a[1])-float(b[1])
 return sqrt(dx*dx+dy*dy)
static func vec(a: Array) -> Vector2: return Vector2(a[0],a[1])
static func mid() -> Dictionary:
 var f := S.make({"bounds":[-2000,-2000,4000,4000],"obstacles":[[-40,-400,80,800]]},[500,500])
 S.begin(f); S.arrange_windup(f,Vector2(-210,0),Vector2(160,0))
 for n in 120:
  var a := S.actor(f.state)
  if a.action_state == "attack" and int(f.state.active_tick)-int(a.action_started_tick) == 12: break
  S.step(f)
 return f
func run(t) -> void:
 var specs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/armored_charge_distance/fixtures/cases.json"))
 for spec in specs:
  if str(spec.id).begins_with("current_") or str(spec.id).begins_with("later_"): one(t,spec)
 for sign_value in [1.0,-1.0]:
  one(t,{"id":"diagonal_"+str(sign_value),"root":[-230.0*sign_value,-90.0],"player":[170.0*sign_value,210.0],"geometry":{"bounds":[-2000,-2000,4000,4000],"obstacles":[[-40,-400,80,800]]},"diagonal":true})
func one(t,spec: Dictionary) -> void:
 var f := S.make(spec.geometry,[500,500]); S.begin(f); S.arrange_windup(f,vec(spec.root),vec(spec.player))
 t.check(f.core.restore(f.state).get("ok",false),spec.id+" windup fixture restore-valid")
 var w := W.new(); w.present(f.core.snapshot(f.state))
 var total := 0.0; var saved := {}; var saved_prefix := 0.0
 var one_before := {}; var one_before_prefix := 0.0; var contact := {}; var stopped := {}; var history: Array[Dictionary] = []
 var maximum_scalar_vs_vector := 0.0
 for n in 150:
  var before: Dictionary = S.actor(f.state).duplicate(true); var state_before: Dictionary = f.state.duplicate(true); var total_before := total
  var events := S.step(f); var a := S.actor(f.state)
  t.check(f.core.step_status().get("ok",false),spec.id+" uninterrupted accepted tick "+str(n))
  if not f.core._final_sweeps.is_empty():
   total += scalar_distance(a.position,before.position)
   maximum_scalar_vs_vector = maxf(maximum_scalar_vs_vector,absf(scalar_distance(a.position,before.position)-vec(a.position).distance_to(vec(before.position))))
  var snapshot: Dictionary = f.core.snapshot(f.state); w.consume_combat_events(events,snapshot); w.present(snapshot)
  var obs: Dictionary = w.armored_motion_observation()
  if a.action_state in ["attack","brake"]:
   t.check(obs.get("charge_distance_known",false),spec.id+" live charge distance known "+str(n))
   t.check(obs.get("charge_distance",-1.0) == total,spec.id+" every tick retains exact double scalar accepted path "+str(n))
  if a.action_state == "attack" and int(f.state.active_tick)-int(a.action_started_tick) == 12:
   saved = f.state.duplicate(true); saved_prefix = total
  var contacts := events.filter(func(e): return e.type == "final_charge_contact")
  if not contacts.is_empty():
   one_before = state_before; one_before_prefix = total_before; stopped = f.state.duplicate(true); history = events
   contact = {"snapshot":snapshot,"actor":a.duplicate(true),"events":events.duplicate(true),"observation":obs,"total":total,"last_scalar":scalar_distance(a.position,before.position)}
   break
 t.check(not saved.is_empty() and not contact.is_empty(),spec.id+" actual age12 snapshot and contact reached")
 if contact.is_empty(): w.free(); return
 t.check(contact.observation.mode == "impact" and contact.observation.contact_count == 1,spec.id+" live impact unchanged")
 var mid_result := restored(t,f,saved,saved_prefix,contact,spec.id+" age12",spec.get("diagonal",false))
 var last_result := restored(t,f,one_before,one_before_prefix,contact,spec.id+" laststep",spec.get("diagonal",false))
 # Restore a stopped checkpoint: historical distance cannot be reconstructed.
 var core = Core.new(f.provider); var result: Dictionary = core.restore(stopped)
 t.check(result.get("ok",false),spec.id+" actual brake checkpoint restores")
 var bw := W.new(); var brake_snapshot: Dictionary = core.snapshot(result.state); bw.present(brake_snapshot)
 var adopted: Dictionary = bw.armored_motion_observation()
 t.check(not adopted.get("charge_distance_known",true) and adopted.get("charge_distance",-1.0) == 0.0,spec.id+" brake adoption distance unknown")
 t.check(adopted.mode == "restored_grounded" and adopted.contact.is_empty() and adopted.distance == 0.0,spec.id+" brake adoption keeps .2 grounded window")
 bw.consume_combat_events(history,brake_snapshot)
 t.check(bw.armored_motion_observation() == adopted,spec.id+" historical actual same-tick contact cannot replay")
 if t.get("traces") is Array: t.traces.append({"id":spec.id,"continuous":contact,"age12":mid_result,"laststep":last_result,"scalar_vs_vector_step_max":maximum_scalar_vs_vector,"brake_adoption":adopted})
 bw.free(); w.free()
func restored(t,f: Dictionary,saved: Dictionary,prefix: float,continuous: Dictionary,label: String,diagonal: bool) -> Dictionary:
 var core = Core.new(f.provider); var result: Dictionary = core.restore(saved)
 t.check(result.get("ok",false),label+" actual Core.restore accepts")
 if not result.get("ok",false): return {}
 var resumed := {"core":core,"state":result.state,"provider":f.provider,"chapter":f.chapter}
 var w := W.new(); w.present(core.snapshot(resumed.state))
 var a := S.actor(resumed.state); var seeded := scalar_distance(a.position,a.locked_origin)
 var adoption: Dictionary = w.armored_motion_observation()
 t.check(adoption.get("charge_distance_known",false) and adoption.get("charge_distance",-1.0) == seeded,label+" seeds authoritative double scalar anchor prefix exactly")
 t.check(adoption.distance == 0.0 and adoption.last_travel == 0.0 and adoption.contact.is_empty(),label+" old window remains zero and no impact replay")
 var expected := seeded; var tail := 0.0; var final := {}; var rows := []
 for n in 100:
  var before: Dictionary = S.actor(resumed.state).duplicate(true); var events := S.step(resumed); a = S.actor(resumed.state)
  t.check(core.step_status().get("ok",false),label+" actual resumed tick "+str(n))
  if not core._final_sweeps.is_empty(): expected += scalar_distance(a.position,before.position); tail += vec(a.position).distance_to(vec(before.position))
  var snapshot: Dictionary = core.snapshot(resumed.state); w.consume_combat_events(events,snapshot); w.present(snapshot)
  var obs: Dictionary = w.armored_motion_observation()
  t.check(obs.get("charge_distance_known",false) and obs.get("charge_distance",-1.0) == expected,label+" exact seeded scalar path "+str(n))
  rows.append({"tick":resumed.state.active_tick,"observation":obs,"expected":expected})
  if not events.filter(func(e): return e.type == "final_charge_contact").is_empty():
   t.check(events == continuous.events and a == continuous.actor,label+" exact real event and actor match uninterrupted")
   t.check(obs.distance == tail and obs.last_travel == vec(a.position).distance_to(vec(before.position)),label+" unchanged observed-window and final partial movement")
   var error := absf(expected-float(continuous.total))
   t.check(error <= 0.00000001 if diagonal else error == 0.0,label+" restores continuous whole-charge phase at real contact")
   t.check(obs.mode == "impact" and obs.contact_count == 1 and obs.contact == continuous.observation.contact,label+" one real live contact preserves witness")
   t.check(before.locked_origin == S.actor(saved).locked_origin and a.locked_origin == a.position,label+" final partial precedes Core anchor overwrite")
   final = {"observation":obs,"expected":expected,"continuous_error":error,"phase_error":error/240.0,"events":events,"partial_scalar":scalar_distance(a.position,before.position)}
   # Repeated present/duplicate contact and stationary accepted brake ticks must
   # not alter the whole-charge distance or count.
   w.consume_combat_events(events,snapshot); w.present(snapshot)
   t.check(w.armored_motion_observation() == obs,label+" contact duplicate/present count once")
   for j in 3:
    var es := S.step(resumed); w.consume_combat_events(es,core.snapshot(resumed.state))
    t.check(w.armored_motion_observation().get("charge_distance",-1.0) == expected,label+" brake retains completed distance "+str(j))
   break
 t.check(not final.is_empty(),label+" real resumed contact reached")
 w.free()
 return {"restore_tick":saved.active_tick,"actual_scalar_prefix":prefix,"anchor_prefix":seeded,"prefix_rounding_error":seeded-prefix,"adoption":adoption,"contact":final,"rows":rows}
