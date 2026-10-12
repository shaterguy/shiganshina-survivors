extends RefCounted
# Synthetic transport-corruption probes based on a real Core-produced wall
# event. They do not claim that Core or Controller produced these bad batches.
const P = preload("res://tests/armored_contact_input/test_producer.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const W = preload("res://game/presentation/world_view.gd")
func run(t) -> void:
 var p := P.new(); var f := p.wall(); p.before_contact(f)
 var before: Dictionary = f.core.snapshot(f.state)
 var events := S.step(f); var after: Dictionary = f.core.snapshot(f.state)
 for boundary in ["scene","stage","lower_tick","lower_origin"]:
  var initial: Dictionary = before.duplicate(true)
  var next: Dictionary = after.duplicate(true)
  if boundary == "scene": next.world = {"mode":"finite","stage":"","scene_id":"other_scene","origin_chunk":[],"origin_revision":0}
  if boundary == "stage": next.world = {"mode":"finite","stage":"other_stage","scene_id":"","origin_chunk":[],"origin_revision":0}
  if boundary == "lower_tick": initial.active_tick = int(after.active_tick)+1
  if boundary == "lower_origin": initial.origin_revision = 1
  var w := W.new(); w.consume_combat_events([],initial); w.present(initial)
  var saved: Dictionary = w.armored_motion_observation()
  var bridge: Dictionary = w._combat_bridge.debug_stats()
  var adopted: Dictionary = w._combat_snapshot.duplicate(true)
  var scene: Dictionary = w._snapshot.duplicate(true)
  t.check(int(events[0].event_id.get_slice(":",2)) > int(saved.event_seq),"probe event is genuinely fresh at "+boundary)
  for field in ["point","source_id","pattern_index","origin_revision"]:
   var bad: Array[Dictionary] = events.duplicate(true)
   bad[0].payload[field] = {"point":[NAN,0],"source_id":"wrong","pattern_index":999,"origin_revision":99}[field]
   w.consume_combat_events(bad,next)
   t.check(w.armored_motion_observation() == saved,"fresh malformed "+field+" is atomic at "+boundary)
   t.check(w._combat_bridge.debug_stats() == bridge and w._combat_snapshot == adopted and w._snapshot == scene,"fresh malformed "+field+" preserves bridge and snapshots at "+boundary)
  # Corrected same-ID input admits the snapshot boundary without replaying an
  # impact across that boundary. It must not inherit the pre-adoption epoch.
  w.consume_combat_events(events,next)
  var accepted: Dictionary = w.armored_motion_observation()
  t.check(w._combat_snapshot == next and accepted.tick == next.active_tick and accepted.event_seq == next.event_seq,"corrected same-ID batch adopts "+boundary)
  t.check(accepted.contact.is_empty() and accepted.mode == "restored_grounded","corrected boundary still suppresses historical impact at "+boundary)
  w.consume_combat_events(events,next)
  t.check(w.armored_motion_observation() == accepted,"post-adoption duplicate remains non-impact at "+boundary)
  w.free()
 # Lower sequence cannot contain a fresh ID while satisfying the existing
 # envelope: event_seq <= snapshot.seq < previous floor. Historical malformed
 # duplicates stay ignorable; a forged higher ID is rejected by the bridge.
 var lower := W.new(); var high: Dictionary = after.duplicate(true); high.event_seq += 1
 lower.consume_combat_events([],high); lower.present(high)
 var saved: Dictionary = lower.armored_motion_observation(); var bridge: Dictionary = lower._combat_bridge.debug_stats(); var adopted: Dictionary = lower._combat_snapshot.duplicate(true)
 var forged: Array[Dictionary] = events.duplicate(true)
 forged[0].event_id = str(after.run_id)+":"+str(int(high.event_seq)+1)
 forged[0].payload.point = [NAN,0]
 lower.consume_combat_events(forged,after)
 t.check(lower.armored_motion_observation() == saved and lower._combat_snapshot == adopted,"lower-sequence snapshot cannot authorize any ID fresh beyond old floor")
 t.check(lower._combat_bridge.debug_stats().event_seq == bridge.event_seq and lower._combat_bridge.debug_stats().bridge_tick == bridge.bridge_tick,"invalid envelope at lower sequence never advances bridge floor")
 var historical: Array[Dictionary] = events.duplicate(true); historical[0].payload = {"invalid":"already historical"}
 lower.consume_combat_events(historical,after)
 t.check(lower._combat_snapshot == after and lower.armored_motion_observation().contact.is_empty() and lower.armored_motion_observation().event_seq == after.event_seq,"lower-sequence restore ignores historical malformed event and never replays it")
 lower.free()
 # Empty stage adoption remains valid, independently of payload validation.
 var stage := W.new(); stage.consume_combat_events(events,after)
 var target: Dictionary = after.duplicate(true); target.world = {"mode":"finite","stage":"new_stage","scene_id":"new_scene","origin_revision":1,"origin_chunk":[]}
 stage.consume_combat_events([],target)
 t.check(stage._combat_snapshot == target and stage.armored_motion_observation().contact.is_empty() and stage.armored_motion_observation().distance == 0,"normal empty stage adoption clears old contact without invented travel")
 stage.free()
