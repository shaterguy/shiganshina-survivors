extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const P = preload("res://tests/armored_contact_input/test_producer.gd")
const C = preload("res://tests/armored_contact_input/city_fixture.gd")
const F = preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
 var original_path := "res://tests/armored_contact_input/fixtures/preparation97-core.gd.txt"
 var original := FileAccess.get_file_as_string(original_path)
 t.check(FileAccess.get_sha256(original_path) == "713c951a0e31b3907b0c9bf2f5e5fd2d44bbd68c2f3318a11708f6eacd342d8b","original .5 preparation Core remains frozen")
 var derived := original.replace('const CONTENT_REVISION := "ch01.3-rebuild.5-preparation97"','const CONTENT_REVISION := "ch01.3-rebuild.6-harmless-recovery"').replace('in ["windup","airborne"]: continue','in ["windup","airborne","recover"]: continue')
 t.check(FileAccess.get_file_as_string("res://tests/armored_contact_input/fixtures/harmless-recovery-eventless-core.gd.txt") == derived,"derived comparison fixture differs only by declared revision and harmless recovery predicate; no old save relabeling")
 t.check(FileAccess.get_file_as_string("res://tests/armored_contact_input/fixtures/grabber-hand-eventless-core.gd.txt") == derived.replace("ch01.3-rebuild.6-harmless-recovery","ch01.3-rebuild.7-grabber-hand"),"new comparison input changes only current revision; prior Source23 comparison stays exact")
 var path := OS.get_environment("FROZEN_CORE")
 if path.is_empty(): path = "res://tests/armored_contact_input/fixtures/grabber-hand-eventless-core.gd.txt"
 t.check(not path.is_empty() and FileAccess.file_exists(path),"explicit derived eventless Core input exists for equivalence")
 if path.is_empty() or not FileAccess.file_exists(path): return
 t.check(FileAccess.get_sha256(path) == "b9b9056c29126797424c5ac119da7caa593e7c44b44e10f354b78207df09b623","equivalence Core bytes match declared .7 revision-only derived eventless fixture")
 var script := GDScript.new()
 script.source_code = FileAccess.get_file_as_string(path).replace("class_name RunSimulation\n","")
 t.check(script.reload() == OK,"derived eventless Core compiles with duplicate global class name removed")
 var finite := P.new().wall()
 finite.state.player.invulnerable_until = 112500
 var base = script.new(finite.provider)
 t.check(base.restore(finite.state).get("ok",false),"full75sec paired fixture restores on frozen baseline")
 var old: Dictionary = finite.state.duplicate(true)
 var cumulative := 0; var ticks := 0; var mismatches := []
 while int(finite.state.active_tick) < int(finite.state.final_started_tick)+4500:
  var previous: int = finite.state.active_tick
  var a := S.step(finite)
  var b := F.step(base,old,Vector2.ZERO,S.Director.new().plan(old,finite.chapter))
  var checked := _compare(a,b,finite.state,old,cumulative)
  cumulative = checked.contacts; ticks += 1
  if not checked.ok: mismatches.append({"tick":finite.state.active_tick,"reason":checked.reason}); break
  if finite.state.active_tick == previous: mismatches.append({"stalled":previous}); break
  if finite.state.active_tick < int(finite.state.final_started_tick)+4500 and finite.state.evacuation_ready: mismatches.append({"early_ready":finite.state.active_tick}); break
 t.check(mismatches.is_empty() and ticks == 4499 and cumulative > 0,"all remaining4499 ticks after first final tick preserve exact state with explicit cumulative contact sequence delta")
 t.check(finite.state.active_tick == 112500 and old.active_tick == 112500 and finite.state.evacuation_ready and old.evacuation_ready and finite.state.final_started_tick == 108000,"full4500-active-tick evacuation requirement unchanged")
 print("FINITE_EQUIVALENCE ",JSON.stringify({"compared_ticks":ticks,"contacts":cumulative,"event_seq_delta":int(finite.state.event_seq)-int(old.event_seq),"failures":mismatches,"ready_at":finite.state.active_tick}))
 var city := C.new().make(t)
 var box: Rect2 = city.target.ground_footprint
 city.state.player.position = [box.position.x-9.0,box.get_center().y]
 city.state.player.invulnerable_until = 0
 var hydration: Dictionary = C.HF.hydration(C.H.requirements(city.state))
 t.check(city.core.prepare_world(city.state,hydration).get("ok",false),"paired city candidate input prepares")
 var baseline = script.new(city.provider)
 var state: Dictionary = city.state.duplicate(true)
 t.check(baseline.prepare_world(state,hydration).get("ok",false),"paired frozen city input prepares")
 cumulative = 0; var good := true; var real_damage := false; var real_structure := false
 for i in 80:
  var a := S.step(city); var b := F.step(baseline,state,Vector2.ZERO,S.Director.new().plan(state,city.chapter))
  var checked := _compare(a,b,city.state,state,cumulative); cumulative = checked.contacts
  good = good and checked.ok
  real_damage = real_damage or not F.types(a,"damage").is_empty()
  real_structure = real_structure or not F.types(a,"structure_destroyed").is_empty()
 t.check(good and cumulative == 1 and real_damage and real_structure,"80 actual city ticks preserve full structure HP RNG actor clocks with explicit one event sequence shift")
 print("CITY_EQUIVALENCE ",JSON.stringify({"ticks":80,"contacts":cumulative,"event_seq_delta":int(city.state.event_seq)-int(state.event_seq),"real_damage":real_damage,"real_structure":real_structure,"equal":good}))
 # Counter-exhaustion admission is intentionally different from eventless P97.
 var edge := P.new().wall(); P.new().before_contact(edge)
 edge.state.event_seq = 2147483647
 var edge_before: Dictionary = edge.state.duplicate(true)
 var edge_base = script.new(edge.provider); var edge_old: Dictionary = edge_before.duplicate(true)
 var rejected := S.step(edge); var admitted := F.step(edge_base,edge_old,Vector2.ZERO,S.Director.new().plan(edge_old,edge.chapter))
 t.check(rejected.is_empty() and edge.state == edge_before and admitted.is_empty() and edge_old.active_tick == edge_before.active_tick+1,"explicit finite MAX boundary: eventless baseline advances while required-contact candidate atomically refuses")
 var capacity := C.new().make(t)
 var cb: Rect2 = capacity.target.ground_footprint
 capacity.state.player.position = [cb.position.x-9.0,cb.get_center().y]
 capacity.state.player.invulnerable_until = 0; capacity.state.event_seq = 2147483645
 var ch: Dictionary = C.HF.hydration(C.H.requirements(capacity.state))
 capacity.core.prepare_world(capacity.state,ch)
 var cs: Dictionary = capacity.state.duplicate(true); var bs: Dictionary = cs.duplicate(true)
 var bc = script.new(capacity.provider); bc.prepare_world(bs,ch)
 var ce := S.step(capacity); var be := F.step(bc,bs,Vector2.ZERO,S.Director.new().plan(bs,capacity.chapter))
 t.check(ce.is_empty() and capacity.state == cs and be.size() == 2 and bs.event_seq == 2147483647 and bs.world.world_revision == cs.world.world_revision+1 and bs.player.hp < cs.player.hp,"explicit city two-slot boundary: baseline commits structure/damage but candidate needs third contact slot and refuses all")

func _compare(events: Array, baseline_events: Array, state: Dictionary, baseline_state: Dictionary, cumulative: int) -> Dictionary:
 var index := 0
 for event in events:
  if event.type == "final_charge_contact": cumulative += 1; continue
  if index >= baseline_events.size(): return {"ok":false,"contacts":cumulative,"reason":"extra non-contact event"}
  var expected: Dictionary = baseline_events[index].duplicate(true)
  var seq := int(str(expected.event_id).get_slice(":",str(expected.event_id).get_slice_count(":")-1))
  expected.event_id = str(baseline_state.run_id)+":"+str(seq+cumulative)
  if event != expected: return {"ok":false,"contacts":cumulative,"reason":"non-contact event differs"}
  index += 1
 if index != baseline_events.size(): return {"ok":false,"contacts":cumulative,"reason":"missing baseline event"}
 if int(state.event_seq)-int(baseline_state.event_seq) != cumulative: return {"ok":false,"contacts":cumulative,"reason":"counter not exact cumulative contact delta"}
 var normalized: Dictionary = state.duplicate(true)
 # This adjustment follows the exact assertion above, never masks the counter.
 normalized.event_seq = int(state.event_seq)-cumulative
 return {"ok":normalized == baseline_state,"contacts":cumulative,"reason":"other snapshot field differs" if normalized != baseline_state else ""}
