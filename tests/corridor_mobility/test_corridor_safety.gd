extends RefCounted
const F = preload("res://tests/corridor_mobility/corridor_fixture.gd")
const M = preload("res://game/core/player_mobility.gd")
class RejectGround:
	extends RefCounted
	func walkable(_position: Vector2,_radius: float) -> Dictionary: return {"ok":true,"walkable":false}
class LandingOnly:
	extends RefCounted
	var landing := Vector2.ZERO
	func walkable(position: Vector2,_radius: float) -> Dictionary: return {"ok":true,"walkable":position == landing}
class BlockedSweep:
	extends RefCounted
	var helper
	func mobility_pair_check(state: Dictionary,anchors: Array) -> Dictionary: return helper.mobility_pair_check(state,anchors)
	func sweep(position: Vector2,_delta: Vector2,_radius: float) -> Dictionary: return {"ok":true,"fraction":0.0,"position":position}
func run(t) -> void:
	for hp in [2,0]:
		var s := F.make(t)
		F.step(s)
		s.state.world = s.state.world.duplicate(true)
		s.state.world.world_revision += 1
		s.state.world.dirty_chunks = [{"chunk":["0","0"],"props":[{"slot_id":"left","hp":hp,"destroyed":hp == 0}]}]
		var before: Array = s.state.player.position.duplicate()
		var ready: Dictionary = s.core.prepare_world(s.state,s.hydration)
		t.check(ready.get("ok",false),"damaged side hook admits safe ground save before cancellation")
		if not ready.get("ok",false): continue
		var tick: int = s.state.active_tick
		var events: Array = F.step(s)
		t.check(s.state.active_tick == tick+1 and s.state.player_mobility.phase == "ground" and s.state.player.position == before,"stale side ends safely without refusing whole tick")
		t.check(events.filter(func(e): return e.type == "damage" and e.payload.get("source_id") == "player_mobility").is_empty(),"stale side cannot deal damage")
	var broken := F.make(t)
	F.step(broken)
	var anchor: Dictionary = broken.state.player_mobility.anchors[0]
	broken.core._streamed._world._props[anchor.prop_id].hp -= 1
	var position: Array = broken.state.player.position.duplicate()
	F.step(broken)
	t.check(broken.state.player_mobility.phase == "ground" and broken.state.player.position == position,"live pair check notices either hook damaged before movement")
	var no_safe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/corridor_mobility/fixtures/legacy_over.json")).state
	var original: Dictionary = no_safe.duplicate(true)
	var refused: Dictionary = M.migrate_legacy(no_safe,RejectGround.new())
	t.check(not refused.ok and refused.error_code == "mobility_migration_no_safe_point" and M.same(original,no_safe),"migration with no normal ground refuses explicitly without touching state")
	var screen := F.make(t)
	while float(M.activation_value(int(screen.state.seed),int(screen.state.active_tick),0))/4294967296.0 < 1.0-pow(0.25,1.0/60.0): screen.state.active_tick += 1
	t.check(M.advance(screen.state,Vector2.UP,null).status == "ground","failed deterministic draw avoids any geometry access")
	var fallback: Dictionary = original.duplicate(true)
	var landing := LandingOnly.new()
	landing.landing = M.vec(fallback.player_mobility.landing.local)
	var fallback_result := M.migrate_legacy(fallback,landing)
	t.check(fallback_result.ok and fallback.player.position == original.player_mobility.landing.local,"controlled migration chooses stored landing only after current/start rejected")
	var blocked := F.make(t)
	F.step(blocked)
	blocked.state.active_tick += 1
	var wrapper := BlockedSweep.new()
	wrapper.helper = blocked.core._streamed
	var stopped: Dictionary = M.advance(blocked.state,Vector2.UP,wrapper)
	t.check(stopped.status == "accepted" and stopped.mobility.phase == "ground" and stopped.proposed_position == M.vec(blocked.state.player.position) and stopped.sweeps.is_empty(),"newly blocked active ground sweep ends locally instead of refusing whole tick")
