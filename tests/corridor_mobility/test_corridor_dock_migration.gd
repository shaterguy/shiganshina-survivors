extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const M = preload("res://game/core/player_mobility.gd")
func run(t) -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/corridor_mobility/fixtures/legacy_dock_ground.json"))
	var original: Dictionary = fixture.state.duplicate(true)
	var core := Core.new(City.new())
	var result: Dictionary = core.restore(fixture.state,{})
	t.check(result.get("ok",false),"genuine dev7 dock-ground save migrates using finite authored ground geometry")
	if not result.get("ok",false): return
	t.check(result.state.world.stage == "dock" and result.state.player.position == original.player.position and result.state.player.velocity == [0.0,0.0],"dock migration preserves position and clears mobility velocity")
	t.check(result.state.player_mobility.schema_version == 2 and result.state.player_mobility.phase == "ground","dock legacy mobility becomes v2 ground")
	t.check(M.same(original,fixture.state),"dock migration leaves caller save untouched")
	t.check(core.prepare_world(result.state,{}).get("ok",false),"migrated dock authority prepares without streamed chunks")
	var roundtrip: Dictionary = core.restore(result.state,{})
	t.check(roundtrip.get("ok",false) and M.same(result.state,roundtrip.get("state",{})),"migrated dock save roundtrip is exact")
