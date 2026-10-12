extends RefCounted
const P = preload("res://tests/armored_contact_input/test_producer.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const F = preload("res://tests/core/core_fixture.gd")
const World = preload("res://game/presentation/world_view.gd")
func run(t) -> void:
 var p := P.new(); var f := p.wall(); p.before_contact(f)
 var before: Dictionary = f.core.snapshot(f.state)
 var events := S.step(f); var snapshot: Dictionary = f.core.snapshot(f.state)
 var w := World.new()
 t.check(w.has_method("armored_motion_observation"),"WorldView exposes bounded current Armored input observation")
 if not w.has_method("armored_motion_observation"): w.free(); return
 w.consume_combat_events(events,snapshot)
 var observation: Dictionary = w.armored_motion_observation()
 t.check(observation.contact_count == 1 and observation.mode == "impact" and observation.contact.tick == snapshot.active_tick,"first real contact before first present is admitted")
 t.check(observation.attack_started_tick == events[0].payload.attack_started_tick and observation.phase_started_tick == S.actor(snapshot).action_started_tick,"charge epoch survives overwritten brake epoch")
 w.consume_combat_events(events,snapshot)
 var reordered: Array[Dictionary] = events.duplicate(true); reordered.reverse(); w.consume_combat_events(reordered,snapshot)
 t.check(w.armored_motion_observation() == observation,"duplicate/reordered stream does not replay")
 w.consume_combat_events(events,before)
 t.check(w.armored_motion_observation() == observation,"mismatched event snapshot leaves accepted observation unchanged")
 # Rejected speculative attempt has unchanged snapshot and empty public events.
 w.consume_combat_events([],snapshot)
 t.check(w.armored_motion_observation() == observation,"unchanged empty rejected tick does not erase committed impact")
 for field in ["source_id","pattern_index","origin_revision","point","normal","root_position","locked_direction","attack_started_tick","shape","shape_id","prop_id","fraction"]:
  var bad: Array[Dictionary] = events.duplicate(true)
  var value: Variant = {"source_id":"wrong","pattern_index":999,"origin_revision":99,"point":[NAN,0],"normal":[0,0],"root_position":[999,0],"locked_direction":[0,1],"attack_started_tick":int(snapshot.active_tick)+1,"shape":"body","shape_id":"","prop_id":42,"fraction":INF}[field]
  bad[0].payload[field] = value
  var v := World.new(); v.consume_combat_events(bad,snapshot)
  t.check(v.armored_motion_observation().get("contact",{}).is_empty(),"invalid payload rejected "+field)
  v.free()
 # Invalid fresh payload is an atomic no-op, including its event floor. The
 # same real event may be repaired and retried against the same successful tick.
 var retry_view := World.new(); retry_view.present(before)
 var prior_observation: Dictionary = retry_view.armored_motion_observation()
 for field in ["source_id","pattern_index","origin_revision","point"]:
  var bad: Array[Dictionary] = events.duplicate(true)
  bad[0].payload[field] = {"source_id":"wrong","pattern_index":999,"origin_revision":99,"point":[NAN,0]}[field]
  retry_view.consume_combat_events(bad,snapshot)
  t.check(retry_view.armored_motion_observation() == prior_observation,"invalid fresh payload preserves observation and watermark "+field)
 retry_view.consume_combat_events(events,snapshot)
 t.check(retry_view.armored_motion_observation().contact_count == 1,"correct same-ID retry after invalid payload remains admissible")
 retry_view.free()
 # A new run's first successful ingestion is distinct from same-run stage
 # adoption. It need not have a rendered frame before the real event arrives.
 var next_snapshot: Dictionary = snapshot.duplicate(true); next_snapshot.run_id = "next-run"
 var next_events: Array[Dictionary] = events.duplicate(true)
 for event in next_events: event.event_id = "next-run:"+str(event.event_id).get_slice(":",str(event.event_id).get_slice_count(":")-1)
 var next_view := World.new(); next_view.consume_combat_events(events,snapshot); next_view.present(snapshot)
 next_view.consume_combat_events(next_events,next_snapshot)
 t.check(next_view.armored_motion_observation().contact.get("event_id","").begins_with("next-run:"),"new run first live contact on reused WorldView remains admissible")
 next_view.present(next_snapshot)
 t.check(next_view.armored_motion_observation().contact.get("event_id","").begins_with("next-run:"),"first new-run present preserves previously consumed live contact")
 next_view.reset_presentation(); next_view.consume_combat_events(next_events,next_snapshot)
 t.check(next_view.armored_motion_observation().contact_count == 1,"actual explicit reset permits first new-run live contact before present")
 next_view.free()
 var wrong_run: Array[Dictionary] = events.duplicate(true); wrong_run[0].event_id = "other:1"
 w.consume_combat_events(wrong_run,snapshot)
 t.check(w.armored_motion_observation() == observation,"wrong run cannot erase accepted scene")
 for i in 20: w.consume_combat_events(S.step(f),f.core.snapshot(f.state))
 t.check(w.armored_motion_observation().phase == "recover" and w.armored_motion_observation().contact_count == 1 and w.armored_motion_observation().attack_started_tick == observation.attack_started_tick,"same contact survives brake to recovery action-start overwrite")
 var cold: Dictionary = f.core.restore(JSON.parse_string(JSON.stringify(f.state))).state
 w.reset_presentation(); w.present(cold)
 var restored: Dictionary = w.armored_motion_observation()
 t.check(restored.contact.is_empty() and restored.mode == "restored_grounded" and restored.distance == 0,"cold recovery uses explicit non-impact restored state")
 # Same-tick reset/present/historical-consume, without any draw or VFX command call.
 w.reset_presentation(); w.present(snapshot); w.consume_combat_events(events,snapshot)
 t.check(w.armored_motion_observation().contact.is_empty() and w.armored_motion_observation().mode == "restored_grounded","snapshot seeds historical floor synchronously before draw")
 for kind in ["tick","seq","origin"]:
  var v := World.new(); var newer: Dictionary = snapshot.duplicate(true)
  if kind == "tick": newer.active_tick += 1
  if kind == "seq": newer.event_seq += 1
  if kind == "origin": newer.origin_revision = 1
  v.consume_combat_events([],newer); v.consume_combat_events(events,snapshot)
  t.check(v.armored_motion_observation().get("contact",{}).is_empty(),"decreasing "+kind+" is restoration and suppresses historical contact")
  v.free()
 # Observed accepted charge samples retain exact final partial movement.
 var moving := p.wall(); var m := World.new()
 m.present(moving.core.snapshot(moving.state))
 var expected := 0.0; var previous := Vector2(S.actor(moving.state).position[0],S.actor(moving.state).position[1])
 for i in 150:
  var es := S.step(moving); var a := S.actor(moving.state); var now := Vector2(a.position[0],a.position[1])
  expected += previous.distance_to(now); previous = now
  m.consume_combat_events(es,moving.core.snapshot(moving.state))
  if a.action_state == "brake": break
 var observed: Dictionary = m.armored_motion_observation()
 t.check(is_equal_approx(observed.distance,expected) and is_equal_approx(expected,78.0),"every successful tick includes exact accepted partial final travel")
 var frozen: Dictionary = observed.duplicate(true)
 for i in 3: m.present(moving.core.snapshot(moving.state))
 t.check(m.armored_motion_observation() == frozen,"repeated presentation never ages or recounts travel")
 var pattern: int = S.actor(moving.state).pattern_index
 var returned := false
 for i in 200:
  m.consume_combat_events(S.step(moving),moving.core.snapshot(moving.state))
  if S.actor(moving.state).action_state == "move" and not returned:
   returned = true
   t.check(m.armored_motion_observation().distance == 0 and m.armored_motion_observation().last_travel == 0,"return to ordinary move clears the completed charge family")
  if S.actor(moving.state).pattern_index > pattern: break
 t.check(m.armored_motion_observation().contact.is_empty(),"next pattern cannot inherit previous impact")
 t.check(m.armored_motion_observation().distance == 0 and m.armored_motion_observation().last_travel == 0,"completed charge family drops its travel when actor returns to move or next warning")
 w.free(); m.free()
