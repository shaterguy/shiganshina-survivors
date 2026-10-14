extends RefCounted
const F = preload("res://tests/live_coverage/live_fixture.gd")
func run(t) -> void:
	var s := F.make(t)
	if s.is_empty(): return
	t.check(s.runtime.has_method("refresh_live_coverage"),"ordinary live coverage has a separate internal Runtime boundary")
	if not s.runtime.has_method("refresh_live_coverage"): return
	var a = s.pair.simulation
	var state: Dictionary = s.pair.state.duplicate(true)
	state.player.position = [0.0,120.0]
	var before := state.duplicate(true)
	var source = a._streamed
	var terrain: Dictionary = source._world._chunks.duplicate(true)
	var attack: Dictionary = a._attack_view_cache.duplicate(true)
	var builds: Dictionary = s.provider._proof_builds.duplicate(true)
	var hits: Dictionary = s.provider._proof_hits.duplicate(true)
	var b: Dictionary = s.runtime.refresh_live_coverage(a,state)
	t.check(b.get("ok",false),"live coverage prepares B without cold reconstruction")
	if not b.get("ok",false): return
	t.check(s.provider._proof_builds == builds and s.provider._proof_hits == hits,"live coverage never enters content capture/load proof lanes")
	t.check(a != b.simulation and a._streamed == source and b.simulation._streamed != source,"live B owns a different Core and helper")
	t.check(state == before and source._world._chunks == terrain and a._attack_view_cache == attack,"live preparation preserves caller state and all old terrain/view")
	t.check(b.simulation._catalog != a._catalog and b.simulation._supplies != a._supplies,"live B never shares mutable catalogs")
	t.check(b.simulation._catalog.evolutions._owner.get_ref() == b.simulation._catalog and b.simulation._evolved._catalog == b.simulation._catalog and b.simulation._signature._catalog == b.simulation._catalog,"live B reconnects every owner/resolver to its new catalog")
	var cold: Dictionary = s.runtime.refresh_coverage(state)
	t.check(cold.get("ok",false) and cold.state == b.state and cold.simulation.world_render_view(cold.state) == b.simulation.world_render_view(b.state),"live dynamic admission and terrain equal old full cold preparation")
	var commands: Array[Dictionary] = []
	var events_b: Array = b.simulation.step(b.state,Vector2.UP,commands)
	var events_cold: Array = cold.simulation.step(cold.state,Vector2.UP,commands)
	t.check(b.simulation.step_status().get("ok",false) and b.state == cold.state and events_b == events_cold,"private B retry consumes the same one tick, events and RNG")
	var later: Dictionary = b.state.duplicate(true)
	later.player.position = [0.0,100.0]
	builds = s.provider._proof_builds.duplicate(true); hits = s.provider._proof_hits.duplicate(true)
	var c: Dictionary = s.runtime.refresh_live_coverage(b.simulation,later)
	t.check(c.get("ok",false) and s.provider._proof_builds == builds and s.provider._proof_hits == hits,"inherited static provenance qualifies B at a second live boundary")
	if not c.get("ok",false): return
	var invalid := later.duplicate(true); invalid.player.radius = 9
	var old_c = c.simulation._streamed
	var refused: Dictionary = s.runtime.refresh_live_coverage(c.simulation,invalid)
	t.check(not refused.get("ok",false) and c.simulation._streamed == old_c and invalid.player.radius == 9,"live path retains full radius corruption rejection without changing A")
	var foreign := F.Core.new(s.provider)
	var unadmitted: Dictionary = s.runtime.refresh_live_coverage(foreign,later)
	t.check(unadmitted.get("ok",false) and s.provider._proof_hits != hits,"unadmitted constructor cannot impersonate a live static proof and falls back cold")
