extends RefCounted
# Real dev5 city/seed42 journey that formerly stopped at tick108198.
# Removing canonical phase endpoints must make the same-clock continuation fail.
const S = preload("res://tests/armored_actor/armored_support.gd")
const R = preload("res://tests/armored_actor/test_armored_rebase.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const M = preload("res://game/core/player_mobility.gd")
const A = preload("res://game/world/world_address.gd")
func run(t) -> void:
	var live: Dictionary = R.new()._make(t)
	if live.is_empty(): return
	live.state.passives.movement = 5
	var actor: Dictionary = S.actor(live.state)
	actor.position = [346.0,384.0]
	actor.locked_origin = actor.position.duplicate()
	S.step(live)
	var checkpoints: Dictionary = {}
	for tick in 241:
		var m: Dictionary = live.state.player_mobility
		if m.phase == "over":
			var key: String = A.key(live.state.world.origin_chunk)
			if not checkpoints.has(key): checkpoints[key] = live.core.snapshot(live.state)
			if m.progress == 176.0 and key == "1,1":
				checkpoints["exit"] = live.core.snapshot(live.state)
				break
		if not _advance(live,Vector2(1,1).normalized()): break
	t.check(checkpoints.has_all(["1,0","1,1","exit"]),"real southeast cast supplies pre-rebase, rebased and roof-exit states")
	if not checkpoints.has("exit"): return
	var exit_state: Dictionary = checkpoints.exit
	t.check(exit_state.active_tick == 108198 and exit_state.player_mobility.started_tick == 108177 and exit_state.player_mobility.phase == "over","repro retains the original failing cast and clock")
	var committed: bool = _advance(live,Vector2(1,1).normalized())
	t.check(committed and live.state.active_tick == 108199,"canonical roof exit commits the formerly refused tick108199 after origin1,1 rebase")
	for key in ["1,0","1,1","exit"]:
		if not checkpoints.has(key): continue
		for direction in [Vector2(1,1).normalized(),Vector2.ZERO,Vector2(-1,-1).normalized()]:
			_replay(t,live,checkpoints[key],key,direction)
func _advance(f: Dictionary, direction: Vector2) -> bool:
	var before: int = f.state.active_tick
	f.events = S.step(f,direction)
	if f.state.active_tick == before and f.core.step_status().get("error_code") == "world_not_ready":
		var needed: Dictionary = H.requirements(f.state)
		if not needed.get("ok",false): return false
		if not f.core.prepare_world(f.state,F.hydration(needed)).get("ok",false): return false
		f.events = S.step(f,direction)
	return f.state.active_tick == before+1 and f.core.step_status().get("ok",false)
func _replay(t, source: Dictionary, saved: Dictionary, label: String, direction: Vector2) -> void:
	var hydration: Dictionary = F.hydration(H.requirements(saved))
	var warm_core = S.Core.new(source.provider)
	var warm: Dictionary = {"core":warm_core,"state":saved.duplicate(true),"chapter":source.chapter}
	t.check(warm_core.prepare_world(warm.state,hydration).get("ok",false),"warm exact rooftop geometry prepares "+label)
	var cold_core = S.Core.new(source.provider)
	var raw_restore: Dictionary = cold_core.restore(saved,hydration)
	t.check(raw_restore.get("ok",false) and M.same(saved,raw_restore.get("state",{})),"raw rooftop save restores exact authority "+label)
	var wire: Dictionary = JSON.parse_string(JSON.stringify(saved,"",true,true))
	var restored: Dictionary = cold_core.restore(wire,hydration)
	t.check(restored.get("ok",false),"cold JSON rooftop save restores before continuation "+label)
	if not restored.get("ok",false): return
	t.check(M.same(saved,restored.state),"cold restore changes neither saved position nor path/phase/clock "+label)
	var cold: Dictionary = {"core":cold_core,"state":restored.state,"chapter":source.chapter}
	t.check(cold_core.prepare_world(cold.state,hydration).get("ok",false),"cold helper binds exactly the restored absolute route "+label)
	var finished := false
	for tick in 40:
		var previous: Dictionary = warm.core.snapshot(warm.state)
		var left: bool = _advance(warm,direction)
		var right: bool = _advance(cold,direction)
		t.check(left and right,"warm/cold accepted active tick at rooftop boundary "+label+" input="+str(direction))
		if not left or not right: break
		t.check(M.same(warm.state,cold.state) and M.same(warm.events,cold.events),"warm/cold authority stays exact through roof exit and rebase "+label)
		var absolute: Dictionary = A.relative(warm.state.world.origin_chunk,M.vec(warm.state.player.position),previous.world.origin_chunk)
		t.check(absolute.get("ok",false) and absolute.local.distance_to(M.vec(previous.player.position)) <= M.STEP+0.0002,"phase split and rebase share one8px movement budget "+label)
		t.check(M.validate(warm.state).is_empty(),"strict saved mobility remains valid at every boundary "+label)
		if direction != Vector2(1,1).normalized() and warm.state.player_mobility.phase != "ground":
			t.check(warm.state.player_mobility.cancelled,"release/reversal cancels immediately without path retarget "+label)
		if warm.state.player_mobility.phase == "ground": finished = true; break
	t.check(finished,"continued or cancelled rebased rooftop route lands within40ticks "+label)
	if finished:
		t.check(warm.core._streamed.walkable(M.vec(warm.state.player.position),8.0).get("walkable",false),"canonical exit ends on normal legal ground "+label)
		t.check(warm.core.restore(warm.core.snapshot(warm.state),warm.core._streamed._hydration).get("ok",false),"completed route remains restorable "+label)
