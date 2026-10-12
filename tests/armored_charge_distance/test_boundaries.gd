extends RefCounted
const R = preload("res://tests/armored_charge_distance/test_restore.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const P = preload("res://tests/armored_contact_input/test_producer.gd")
const W = preload("res://game/presentation/world_view.gd")
const Tracker = preload("res://game/presentation/armored_motion_tracker.gd")
const C = preload("res://tests/armored_contact_input/city_fixture.gd")
const Address = preload("res://game/world/world_address.gd")
func run(t) -> void:
 _cold(t); _identity(t); _invalid(t); _rebase(t); _gaps(t); _minimal(t)
func _cold(t) -> void:
 var p := P.new(); var f := p.wall(); p.before_contact(f)
 var events := S.step(f); var snapshot: Dictionary = f.core.snapshot(f.state)
 var w := W.new(); w.consume_combat_events(events,snapshot)
 var obs: Dictionary = w.armored_motion_observation()
 t.check(obs.mode == "impact" and obs.contact_count == 1,"first valid fresh live contact retains unchanged .2 impact behavior")
 t.check(not obs.get("charge_distance_known",true) and obs.get("charge_distance",-1.0) == 0.0,"first live contact without prior attack remains whole-distance unknown")
 w.consume_combat_events(events,snapshot); w.present(snapshot)
 t.check(w.armored_motion_observation() == obs,"cold live contact duplicates never invent whole-charge distance")
 w.free()
 for n in 22: S.step(f)
 t.check(S.actor(f.state).action_state == "recover","actual cold recovery fixture reached")
 var recover := W.new(); recover.present(f.core.snapshot(f.state))
 t.check(recover.armored_motion_observation().mode == "restored_grounded" and not recover.armored_motion_observation().get("charge_distance_known",true),"snapshot-only cold recovery grounded and whole-distance unknown")
 recover.free()
func _identity(t) -> void:
 var f := R.mid(); var w := W.new(); var snapshot: Dictionary = f.core.snapshot(f.state); w.present(snapshot)
 var baseline: Dictionary = w.armored_motion_observation(); var expected := R.scalar_distance(S.actor(snapshot).position,S.actor(snapshot).locked_origin)
 w.consume_combat_events([],snapshot); w.present(snapshot); w.consume_combat_events([],snapshot)
 t.check(w.armored_motion_observation() == baseline,"same-tick duplicate/empty input and presentation do not count travel")
 var events := S.step(f); var next: Dictionary = f.core.snapshot(f.state); w.consume_combat_events(events,next)
 var accepted: Dictionary = w.armored_motion_observation()
 t.check(accepted.get("charge_distance",-1.0) == expected+R.scalar_distance(S.actor(next).position,S.actor(snapshot).position),"next accepted live step retains seeded prefix")
 var wrong: Array[Dictionary] = events.duplicate(true)
 # A real event envelope from a later successful contact paired to the old
 # snapshot is rejected before any distance or bridge watermark mutation.
 var p := P.new(); var wall := p.wall(); p.before_contact(wall); var contact := S.step(wall)
 w.consume_combat_events(contact,snapshot)
 t.check(w.armored_motion_observation() == accepted,"out-of-order real contact/old snapshot mismatch is an atomic no-op")
 # An actual rollback snapshot is an explicit adoption, not a historical step.
 w.consume_combat_events([],snapshot)
 var rollback: Dictionary = w.armored_motion_observation()
 t.check(rollback.distance == 0.0 and rollback.get("charge_distance",-1.0) == expected and rollback.get("charge_distance_known",false),"valid out-of-order attack snapshot re-adopts authoritative prefix without tail double count")
 var new_run: Dictionary = snapshot.duplicate(true); new_run.run_id = "new-charge-run"; w.consume_combat_events([],new_run)
 t.check(w.armored_motion_observation().get("charge_distance",-1.0) == expected and w.armored_motion_observation().contact_count == 0,"new run identity seeds only its own attack and clears old contact count")
 # Synthetic input boundary: same actor and pattern but a distinct attack
 # epoch must never inherit a previous charge accumulator.
 var epoch: Dictionary = new_run.duplicate(true); epoch.active_tick += 1
 var a := S.actor(epoch); a.action_started_tick = epoch.active_tick; a.action_ends_tick = epoch.active_tick+60
 a.locked_origin = a.position.duplicate()
 w.consume_combat_events([],epoch)
 t.check(w.armored_motion_observation().get("charge_distance_known",false) and w.armored_motion_observation().get("charge_distance",-1.0) == 0.0,"new attack-start identity resets whole distance even when actor/pattern are reused")
 w.free()
 # Actual Core cycle pins ordinary move/reset and subsequent real warning.
 var cycle := P.new().wall(); var cw := W.new(); cw.present(cycle.core.snapshot(cycle.state)); var first_pattern: int = S.actor(cycle.state).pattern_index
 var move_seen := false; var warning_seen := false
 for n in 400:
  var es := S.step(cycle); cw.consume_combat_events(es,cycle.core.snapshot(cycle.state)); var ca := S.actor(cycle.state)
  if ca.action_state == "move" and not move_seen:
   move_seen = true
   t.check(cw.armored_motion_observation().get("charge_distance",-1.0) == 0.0 and not cw.armored_motion_observation().get("charge_distance_known",true),"actual completed charge clears whole distance on move")
  if ca.action_state == "windup" and int(ca.pattern_index) > first_pattern:
   warning_seen = true
   t.check(cw.armored_motion_observation().get("charge_distance",-1.0) == 0.0 and not cw.armored_motion_observation().get("charge_distance_known",true) and cw.armored_motion_observation().contact.is_empty(),"actual new pattern warning cannot inherit completed whole charge")
   break
 t.check(move_seen and warning_seen,"actual completed cycle reaches a new warning identity")
 cw.free()
func _invalid(t) -> void:
 var f := R.mid(); var snapshot: Dictionary = f.core.snapshot(f.state)
 var w := W.new(); w.consume_combat_events([],snapshot); w.present(snapshot)
 var baseline: Dictionary = w.armored_motion_observation(); var bridge: Dictionary = w._combat_bridge.debug_stats(); var combat: Dictionary = w._combat_snapshot.duplicate(true)
 var variants := []
 for field in ["position","locked_origin","locked_direction"]:
  for value in [[],[1.0],[1.0,2.0,3.0],[NAN,0.0],[0.0,INF],["1",0.0],[true,0.0],Vector2.ZERO,[1.0e300,1.0e300]]:
   var bad: Dictionary = snapshot.duplicate(true); S.actor(bad)[field] = value; variants.append({"label":field+"/"+str(value),"snapshot":bad})
 for field in ["active_tick","event_seq","origin_revision"]:
  for value in [-1,0.5,NAN,INF,2147483648,"1",true]:
   var bad: Dictionary = snapshot.duplicate(true); bad[field] = value; variants.append({"label":field+"/"+str(value),"snapshot":bad})
 for field in ["id","spawned_tick","pattern_index","action_started_tick","action_ends_tick"]:
  for value in [-1,0.5,NAN,INF,2147483648,"1",true]:
   var bad: Dictionary = snapshot.duplicate(true); S.actor(bad)[field] = value; variants.append({"label":field+"/"+str(value),"snapshot":bad})
 for value in [NAN,-1,0.5,2147483648,"1",true]:
  var bad: Dictionary = snapshot.duplicate(true); bad.world = {"origin_revision":value,"origin_chunk":[],"mode":"finite"}; variants.append({"label":"world revision/"+str(value),"snapshot":bad})
 for value in [[1],[0,0,0],[NAN,0],[0,0.5],["0",0],[2147483648,0]]:
  var bad: Dictionary = snapshot.duplicate(true); bad.world = {"origin_revision":1,"origin_chunk":value,"mode":"city"}; variants.append({"label":"origin chunk/"+str(value),"snapshot":bad})
 for item in variants:
  w.consume_combat_events([],item.snapshot)
  t.check(w.armored_motion_observation() == baseline,"malformed input preserves tracker "+item.label)
  var now: Dictionary = w._combat_bridge.debug_stats()
  t.check(now.event_seq == bridge.event_seq and now.bridge_tick == bridge.bridge_tick and w._combat_snapshot == combat,"malformed input preserves bridge floor/combat snapshot "+item.label)
  # Test the tracker snapshot-only route without WorldView's unrelated draw
  # code attempting to render deliberately malformed actor positions.
  var tracker := Tracker.new(); tracker.present(snapshot); var before: Dictionary = tracker.debug_observation(); tracker.present(item.snapshot)
  t.check(tracker.debug_observation() == before,"malformed snapshot-only actor cannot alter new phase "+item.label)
 # Finite integral float counters, zero/maximum valid bounds remain supported.
 for value in [2147483647,2147483647.0]:
  var edge: Dictionary = snapshot.duplicate(true); edge.event_seq = value
  var v := W.new(); v.consume_combat_events([],edge)
  t.check(v.armored_motion_observation().get("charge_distance_known",false) and v.armored_motion_observation().event_seq == int(value),"valid maximum event counter preserves double anchor adoption")
  v.free()
 w.free()
func _rebase(t) -> void:
 var f := C.new().make(t); f.state = f.previous_states[0].duplicate(true)
 t.check(f.core.prepare_world(f.state,C.HF.hydration(C.H.requirements(f.state))).get("ok",false),"natural precontact city charge prepares")
 var w := W.new(); w.consume_combat_events([],f.core.snapshot(f.state)); w.present(f.core.snapshot(f.state))
 var start: Dictionary = w.armored_motion_observation()
 t.check(S.actor(f.state).action_state == "attack" and start.get("charge_distance_known",false),"actual streamed midattack seeds whole distance")
 f.state.player.position = [766.0,384.0]
 t.check(f.core.prepare_world(f.state,C.HF.hydration(C.H.requirements(f.state))).get("ok",false),"actual charge rebase fixture prepares road boundary")
 var maximum_rebases := 0; var expected := float(start.get("charge_distance",0.0)); var previous: Dictionary = f.core.snapshot(f.state)
 for n in 7:
  var events := S.step(f,Vector2.RIGHT); var snapshot: Dictionary = f.core.snapshot(f.state)
  t.check(f.core.step_status().get("ok",false),"actual streamed charge/rebase tick "+str(n))
  var prior: Array = S.actor(previous).position.duplicate()
  if snapshot.world.origin_revision != previous.world.origin_revision:
   var shift := Address.relative(previous.world.origin_chunk,Vector2.ZERO,snapshot.world.origin_chunk)
   prior = [prior[0]+shift.local.x,prior[1]+shift.local.y]; maximum_rebases += 1
  if not f.core._final_sweeps.is_empty(): expected += R.scalar_distance(S.actor(snapshot).position,prior)
  w.consume_combat_events(events,snapshot); var observed: Dictionary = w.armored_motion_observation()
  t.check(observed.get("charge_distance_known",false) and observed.get("charge_distance",-1.0) == expected,"rebase subtracts origin once and counts only scalar accepted movement "+str(n))
  var terrain: Dictionary = f.core.world_render_view(f.state); terrain.world_revision = f.state.world.world_revision
  for j in 2: t.check(w.present_city(snapshot,terrain).get("ok",false),"real repeated city present "+str(n)+"/"+str(j))
  t.check(w.armored_motion_observation() == observed,"rebase/present never translates or counts twice "+str(n))
  previous = snapshot
 t.check(maximum_rebases == 1 and w.armored_motion_observation().rebase_count == 1,"actual Core midcharge trajectory rebases exactly once")
 if t.get("traces") is Array: t.traces.append({"id":"actual_city_rebase","initial":start,"final":w.armored_motion_observation(),"expected":expected})
 w.free()
func _gaps(t) -> void:
 var f := R.mid(); var w := W.new(); w.present(f.core.snapshot(f.state))
 # Skipped accepted attack snapshots cannot be summed from a long positional
 # jump. A valid straight-charge anchor can re-seed its authoritative prefix.
 for n in 3: S.step(f)
 var snapshot: Dictionary = f.core.snapshot(f.state); w.consume_combat_events([],snapshot)
 var expected := R.scalar_distance(S.actor(snapshot).position,S.actor(snapshot).locked_origin)
 t.check(w.armored_motion_observation().get("charge_distance",-1.0) == expected and w.armored_motion_observation().get("charge_distance_known",false),"gapped attack input re-seeds authoritative prefix without invented intermediate steps")
 f.state.pause_reasons.append("user"); var paused: Dictionary = w.armored_motion_observation(); var before: Dictionary = f.state.duplicate(true)
 var refused := S.step(f); t.check(refused.is_empty() and f.state == before,"real paused Core produces no accepted movement")
 w.consume_combat_events(refused,f.core.snapshot(f.state)); w.present(f.core.snapshot(f.state))
 t.check(w.armored_motion_observation() == paused,"paused same-tick presentation cannot age whole charge")
 w.free()
 var p := P.new(); var g := p.wall(); var cold := W.new(); cold.present(g.core.snapshot(g.state)); p.before_contact(g)
 var events := S.step(g); cold.consume_combat_events(events,g.core.snapshot(g.state))
 t.check(not cold.armored_motion_observation().get("charge_distance_known",true) and cold.armored_motion_observation().mode == "impact","unobserved attack interval followed by real live contact remains distance unknown, contact valid")
 cold.free()

func _minimal(t) -> void:
 var f := R.mid(); var snapshot: Dictionary = f.core.snapshot(f.state)
 for missing in [["locked_origin"],["locked_direction"],["spawned_tick"],["locked_origin","locked_direction","spawned_tick"]]:
  var minimal: Dictionary = snapshot.duplicate(true)
  for field in missing: S.actor(minimal).erase(field)
  var w := W.new(); w.consume_combat_events([],minimal); w.present(minimal)
  var obs: Dictionary = w.armored_motion_observation()
  t.check(not obs.is_empty() and w._combat_snapshot == minimal,"missing optional whole-distance/identity evidence preserves .2 snapshot admission "+str(missing))
  t.check(obs.get("charge_distance_known",false) == (not "locked_origin" in missing and not "locked_direction" in missing),"missing anchor/direction is unknown; missing optional spawned tick alone does not block seed "+str(missing))
  t.check(obs.get("distance",-1.0) == 0.0,"minimal snapshot keeps original window semantics "+str(missing))
  w.free()
 var zero: Dictionary = snapshot.duplicate(true); S.actor(zero).locked_direction = [0.0,0.0]
 var w := W.new(); w.consume_combat_events([],zero)
 t.check(not w.armored_motion_observation().is_empty() and not w.armored_motion_observation().get("charge_distance_known",true),"finite nonunit direction has no whole-charge evidence but does not expand .2 empty-batch contract")
 w.free()
