extends RefCounted
# The v1 roof-exit stall is covered at the v2 straight endpoint/rebase boundary.
const F = preload("res://tests/terrain_mobility/motion_fixture.gd")
const C = preload("res://tests/corridor_mobility/corridor_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const M = preload("res://game/core/player_mobility.gd")
const A = preload("res://game/world/world_address.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const R = preload("res://tests/armored_actor/test_armored_rebase.gd")
func run(t) -> void:
	_armored_journey(t)
	var live := C.make(t,[F.AF.slot("top","house_narrow",[704,224]),F.AF.slot("bottom","house_narrow",[704,544])],[660.0,384.0])
	if live.is_empty(): return
	var checkpoints := {}
	for tick in 40:
		F.step(live,Vector2.RIGHT)
		var m: Dictionary = live.state.player_mobility
		if m.phase != "boost": continue
		var key: String = A.key(live.state.world.origin_chunk)
		if not checkpoints.has(key): checkpoints[key] = live.core.snapshot(live.state)
		if m.progress == 312.0:
			checkpoints["exit"] = live.core.snapshot(live.state)
			break
	t.check(checkpoints.has_all(["0,0","1,0","exit"]),"real horizontal boost supplies pre-rebase, rebased and exact final-step states")
	if not checkpoints.has("exit"): return
	var clock: int = live.state.active_tick
	F.step(live,Vector2.RIGHT)
	t.check(live.core.step_status().get("ok",false) and live.state.active_tick == clock+1 and live.state.player_mobility.phase == "ground","canonical corridor endpoint accepts the next tick after an origin rebase")
	for key in ["0,0","1,0","exit"]:
		for direction in [Vector2.RIGHT,Vector2.ZERO,Vector2.LEFT]: _replay(t,live,checkpoints[key],key,direction)
func _replay(t, source: Dictionary, saved: Dictionary, label: String, direction: Vector2) -> void:
	var hydration: Dictionary = F.HF.hydration(H.requirements(saved))
	var warm_core := F.Core.new(source.provider)
	var warm := {"core":warm_core,"state":saved.duplicate(true),"hydration":hydration}
	t.check(warm_core.prepare_world(warm.state,hydration).get("ok",false),"warm exact corridor geometry prepares "+label)
	var cold_core := F.Core.new(source.provider)
	var raw_restore: Dictionary = cold_core.restore(saved,hydration)
	t.check(raw_restore.get("ok",false) and M.same(saved,raw_restore.get("state",{})),"raw boost save restores exact authority "+label)
	var wire: Dictionary = JSON.parse_string(JSON.stringify(saved,"",true,true))
	var restored: Dictionary = cold_core.restore(wire,hydration)
	t.check(restored.get("ok",false),"cold JSON boost save restores before continuation "+label)
	if not restored.get("ok",false): return
	t.check(M.same(saved,restored.state),"cold restore changes neither saved position nor path/phase/clock "+label)
	var cold := {"core":cold_core,"state":restored.state,"hydration":hydration}
	t.check(cold_core.prepare_world(cold.state,hydration).get("ok",false),"cold helper binds exactly the restored absolute route "+label)
	var finished := false
	for tick in 40:
		var previous: Dictionary = warm.core.snapshot(warm.state)
		var left: Array[Dictionary] = F.step(warm,direction)
		var right: Array[Dictionary] = F.step(cold,direction)
		t.check(warm.core.step_status().get("ok",false) and cold.core.step_status().get("ok",false) and warm.state.active_tick == previous.active_tick+1,"warm/cold accept each tick at corridor boundary "+label+" input="+str(direction))
		t.check(M.same(warm.state,cold.state) and M.same(left,right),"warm/cold authority stays exact through endpoint and rebase "+label)
		var absolute: Dictionary = A.relative(warm.state.world.origin_chunk,M.vec(warm.state.player.position),previous.world.origin_chunk)
		t.check(absolute.get("ok",false) and absolute.local.distance_to(M.vec(previous.player.position)) <= M.STEP+0.0002,"endpoint and rebase share one 8px movement budget "+label)
		t.check(M.validate(warm.state).is_empty(),"strict saved mobility remains valid at every boundary "+label)
		if direction != Vector2.RIGHT:
			t.check(warm.state.player_mobility.phase == "ground" and absolute.local == M.vec(previous.player.position),"release/reversal ends boost immediately at the saved point "+label)
		if warm.state.player_mobility.phase == "ground": finished = true; break
	t.check(finished,"continued or cancelled rebased corridor completes within 40 ticks "+label)
	if finished:
		t.check(warm.core._streamed.walkable(M.vec(warm.state.player.position),8.0).get("walkable",false),"canonical endpoint ends on normal legal ground "+label)
		t.check(warm.core.restore(warm.core.snapshot(warm.state),warm.hydration).get("ok",false),"completed route remains restorable "+label)

# Preserve the original seed42 final-boss journey as a non-regression control.
# Its obsolete roof-phase timing is replaced by accepted ticks and v2 authority.
func _armored_journey(t) -> void:
	var live: Dictionary = R.new()._make(t)
	if live.is_empty(): return
	live.state.passives.movement = 5
	var actor: Dictionary = S.actor(live.state)
	actor.position = [346.0,384.0]
	actor.locked_origin = actor.position.duplicate()
	S.step(live)
	var initial_tick: int = live.state.active_tick
	for tick in 241:
		var before: Dictionary = live.core.snapshot(live.state)
		var accepted := _advance_armored(live,Vector2(1,1).normalized())
		t.check(accepted and live.state.active_tick == before.active_tick+1,"original seed42 armored journey never stalls at the former roof-exit clock")
		if not accepted: return
		var absolute: Dictionary = A.relative(live.state.world.origin_chunk,M.vec(live.state.player.position),before.world.origin_chunk)
		t.check(absolute.get("ok",false) and absolute.local.distance_to(M.vec(before.player.position)) <= M.STEP+0.0002,"original armored journey preserves its per-tick movement budget across rebase")
		t.check(live.state.player_mobility.phase in ["ground","boost"] and M.validate(live.state).is_empty(),"original armored journey never revives a v1 roof phase")
		if tick in [0,119,240]:
			var hydration: Dictionary = F.HF.hydration(H.requirements(live.state))
			var restored: Dictionary = live.core.restore(JSON.parse_string(JSON.stringify(live.state,"",true,true)),hydration)
			t.check(restored.get("ok",false) and M.same(restored.get("state",{}),live.state),"original armored/rebase checkpoint remains exactly JSON-restorable")
	t.check(live.state.active_tick == initial_tick+241,"entire original final-boss traversal accepts all 241 active ticks")
func _advance_armored(f: Dictionary, direction: Vector2) -> bool:
	var before: int = f.state.active_tick
	S.step(f,direction)
	if f.state.active_tick == before and f.core.step_status().get("error_code") == "world_not_ready":
		var needed: Dictionary = H.requirements(f.state)
		if not needed.get("ok",false): return false
		if not f.core.prepare_world(f.state,F.HF.hydration(needed)).get("ok",false): return false
		S.step(f,direction)
	return f.state.active_tick == before+1 and f.core.step_status().get("ok",false)
