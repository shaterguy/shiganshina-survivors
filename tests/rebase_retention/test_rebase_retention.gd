extends RefCounted
const F = preload("res://tests/live_coverage/live_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")

func run(t) -> void:
	_ground(t)
	_natural_boost(t)

func _pair(t, position: Array) -> Dictionary:
	var fixture: Dictionary = F.make(t)
	if fixture.is_empty(): return {}
	var state: Dictionary = fixture.pair.state.duplicate(true)
	state.player.position = position.duplicate()
	var ready: Dictionary = fixture.runtime.refresh_coverage(state)
	t.check(ready.get("ok",false),"rebase fixture passes real cold admission")
	if not ready.get("ok",false): return {}
	fixture.pair = ready
	return fixture

func _ready(t, fixture: Dictionary, cold: bool) -> bool:
	var pair: Dictionary = fixture.pair
	if pair.simulation._streamed.readiness(pair.state).get("ok",false): return true
	var next: Dictionary = fixture.runtime.refresh_coverage(pair.state) if cold else fixture.runtime.refresh_live_coverage(pair.simulation,pair.state)
	t.check(next.get("ok",false),"natural movement prepares actual missing coverage")
	if not next.get("ok",false): return false
	fixture.pair = next
	return true

func _step_pair(t, left: Dictionary, right: Dictionary, move: Vector2) -> Dictionary:
	if not _ready(t,left,false) or not _ready(t,right,true): return {}
	var a = left.pair.simulation
	var b = right.pair.simulation
	var old = a._streamed
	var before: Dictionary = left.pair.state.duplicate(true)
	var normalized: Dictionary = H.Address.normalize(before.world.origin_chunk,H.vec(before.player.position))
	var rebasing: bool = normalized.get("ok",false) and normalized.offset != Vector2.ZERO
	var chunks: PackedByteArray = var_to_bytes(old._world._chunks) if rebasing else PackedByteArray()
	var missing := []
	if rebasing:
		var proposal: Dictionary = H.rebase_proposal(before)
		var needed: Dictionary = H.requirements(proposal.state)
		for address in needed.chunks:
			var key: String = H.Address.key(address)
			if not old._world._chunks.has(key): missing.append(key)
	# Test-only removal of the existing admission flag forces the real old path;
	# no product hook or replacement implementation is introduced.
	b._configuration_admitted = false
	var events_a: Array = F.F.step(a,left.pair.state,move)
	var events_b: Array = F.F.step(b,right.pair.state,move)
	t.check(a.step_status().get("ok",false) and b.step_status().get("ok",false),"both real Core paths consume a valid tick")
	t.check(left.pair.state == right.pair.state and events_a == events_b,"retained and cold rebase preserve full state, both RNG streams and events")
	if not rebasing: return {"rebased":false}
	t.check(a._streamed != old and a._streamed._world != old._world and a._streamed._navigation != old._navigation,"ordinary rebase publishes separately owned helper, world and fresh navigation")
	t.check(var_to_bytes(old._world._chunks) == chunks,"ordinary rebase leaves source absolute chunks unchanged")
	var activated: Array = a._streamed._last_status.get("activated",[])
	t.check(activated == missing,"REBASE_MISSING_ONLY: ordinary rebase generates only missing absolute chunks")
	t.check(a.world_render_view(left.pair.state) == b.world_render_view(right.pair.state),"retained rebase geometry and revisions equal cold output")
	return {"rebased":true,"phase":before.player_mobility.phase}

func _ground(t) -> void:
	var a := _pair(t,[1152.0,384.0])
	var b := _pair(t,[1152.0,384.0])
	if a.is_empty() or b.is_empty(): return
	var result := _step_pair(t,a,b,Vector2.RIGHT)
	t.check(result.get("rebased",false) and result.get("phase") == "ground","ground test crosses a genuine normalized origin transition")

func _natural_boost(t) -> void:
	var a := _pair(t,[0.0,192.0])
	var b := _pair(t,[0.0,192.0])
	if a.is_empty() or b.is_empty(): return
	var found := false
	for tick in 120:
		var result := _step_pair(t,a,b,Vector2.UP)
		if result.is_empty(): return
		if result.get("rebased",false) and result.get("phase") == "boost":
			found = true
			break
	t.check(found,"boost rebase is reached through real mobility movement without forced phase/RNG")
