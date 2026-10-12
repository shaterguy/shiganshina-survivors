extends RefCounted
const X = preload("res://tests/fantasy_skills/fantasy_fixture.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Bridge = preload("res://game/presentation/combat_vfx_bridge.gd")
func run(t) -> void:
	var sim = X.simulation()
	var state: Dictionary = X.state(sim)
	state.equipment = {"chain_lightning":1}
	state.player.attack_ready_ticks.chain_lightning = 999999
	F.step(sim,state,Vector2.ZERO,[F.spawn("killing-spark",[80,0],"brute")])
	t.check(state.entities.size() == 1,"killing spark test uses an actually spawned target")
	if state.entities.size() != 1: return
	var former_entity: Dictionary = state.entities[0]
	former_entity.hp = 1.0
	state.player.attack_ready_ticks.chain_lightning = state.active_tick
	var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO)
	var hits := events.filter(func(e): return e.type == "damage" and e.payload.get("target_id") == "killing-spark")
	t.check(hits.size() == 1 and state.entities.is_empty(),"actual killing damage occurs before target leaves the successful snapshot")
	if hits.size() != 1: return
	var hit: Dictionary = hits[0].payload
	t.check(hit.has("position"),"actual transient killing damage carries its contact position")
	if not hit.has("position"): return
	var attacks := events.filter(func(e): return e.type == "player_attack" and e.payload.phase == "executed")
	var geometry: Dictionary = attacks[0].payload.geometry
	var expected := Vector2(geometry.origin[0],geometry.origin[1])+Vector2(geometry.direction[0],geometry.direction[1])*float(geometry.length)
	t.check(Vector2(hit.position[0],hit.position[1]).is_equal_approx(expected),"killing hit position equals actual executed chain endpoint")
	former_entity.position[0] += 500.0
	t.check(Vector2(hit.position[0],hit.position[1]).is_equal_approx(expected),"damage position is a deep copy independent of removed entity storage")
	var snapshot: Dictionary = sim.snapshot(state)
	var original := events.duplicate(true)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	var bridge := Bridge.new(manifest)
	t.check(bridge.consume(events,snapshot),"Bridge accepts actual killing tick after target removal")
	var drawn := bridge.present(snapshot)
	var sparks := drawn.filter(func(c): return c.get("asset_id") == "vfx_hit_spark")
	t.check(sparks.size() == 1 and not sparks[0].has("diagnostic"),"registered original hit spark draws for the actual removed target")
	if sparks.size() != 1 or sparks[0].has("diagnostic"): return
	t.check(sparks[0].world_anchor.is_equal_approx(expected) and sparks[0].contact_size == Vector2(18,18),"killing spark retains exact world contact and existing radius9")
	t.check(events == original,"public VFX never edits transient damage events")
	bridge.consume(events,snapshot)
	t.check(bridge.present(snapshot) == drawn,"repeated killing tick neither duplicates nor moves contact")
	events = F.step(sim,state,Vector2.RIGHT)
	snapshot = sim.snapshot(state)
	bridge.consume(events,snapshot)
	sparks = bridge.present(snapshot).filter(func(c): return c.get("asset_id") == "vfx_hit_spark")
	t.check(sparks.size() == 1 and not sparks[0].has("diagnostic") and sparks[0].world_anchor.is_equal_approx(expected),"short killing recovery stays at real world contact while player moves")
