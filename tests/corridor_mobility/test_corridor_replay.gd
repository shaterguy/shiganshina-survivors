extends RefCounted
const F = preload("res://tests/corridor_mobility/corridor_fixture.gd")
const M = preload("res://game/core/player_mobility.gd")
const A = preload("res://game/world/world_address.gd")
func run(t) -> void:
	var s := F.make(t)
	var rng: Array = [s.state.rng_state,s.state.progression_rng_state]
	F.step(s)
	var raw: Dictionary = s.core.snapshot(s.state)
	var wire: Dictionary = JSON.parse_string(JSON.stringify(raw,"",true,true))
	var restored: Dictionary = s.core.restore(wire,s.hydration)
	t.check(restored.get("ok",false) and M.same(restored.get("state",{}),raw),"active v2 paired ground cast JSON roundtrip is exact")
	if not restored.get("ok",false): return
	var cold := F.F.Core.new(s.provider)
	var replay := {"core":cold,"state":restored.state,"hydration":s.hydration,"provider":s.provider}
	t.check(cold.prepare_world(replay.state,replay.hydration).get("ok",false),"restored paired cast prepares cold spatial cache")
	var rebased := false
	for tick in 42:
		var previous := {"position":s.state.player.position.duplicate(),"origin":s.state.world.origin_chunk.duplicate()}
		var left := F.step(s)
		var right := F.step(replay)
		t.check(M.same(s.state,replay.state) and M.same(left,right),"warm and cold fixed ticks produce exact authority/events")
		var point := A.relative(s.state.world.origin_chunk,M.vec(s.state.player.position),previous.origin)
		t.check(point.ok and point.local.distance_to(M.vec(previous.position)) <= 8.0002,"chunk-boundary movement retains one 8px budget")
		t.check(M.validate(s.state).is_empty() and s.core._streamed.walkable(M.vec(s.state.player.position),8.0).get("walkable",false),"each active tick stays strictly valid on normal ground")
		if s.state.world.origin_chunk != previous.origin: rebased = true
	t.check(rebased,"straight corridor genuinely crosses a chunk origin boundary")
	t.check([s.state.rng_state,s.state.progression_rng_state] == rng,"corridor activation and movement consume no gameplay or progression RNG")
	for mutation in ["duplicate_pair","height","heading","path","progress","hit_ids","clock","revision"]:
		var bad: Dictionary = raw.duplicate(true)
		match mutation:
			"duplicate_pair": bad.player_mobility.anchors[1] = bad.player_mobility.anchors[0].duplicate(true)
			"height": bad.player_mobility.path[1].height = 1.0
			"heading": bad.player_mobility.direction = [0.0,0.0]
			"path": bad.player_mobility.path[1].local[0] += 1.0
			"progress": bad.player_mobility.progress += 0.5
			"hit_ids": bad.player_mobility.hit_ids = ["same","same"]
			"clock": bad.player_mobility.started_tick += 1
			"revision": bad.player_mobility.anchors[0].geometry_revision = "f".repeat(64)
		t.check(not s.core.restore(bad,s.hydration).get("ok",false),"v2 corruption is rejected: "+mutation)
