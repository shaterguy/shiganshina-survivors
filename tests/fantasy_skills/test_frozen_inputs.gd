extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const Finite = preload("res://tests/core/finite_chapter_provider.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
func run(t) -> void:
	var inputs := {}
	for path in Core.GAMEPLAY_PATHS:
		inputs[path] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fantasy_skills/legacy_inputs/"+path.get_file()))
	var sim := Core.new(Finite.new(),null,inputs)
	var state := sim.new_run(Finite.new().load_chapter("chapter_01_shiganshina").chapter,42,F.run_config())
	t.check(not state.has("error_code"),"frozen six-weapon gameplay injection remains a valid historical Core")
	if state.has("error_code"): return
	F.step(sim,state,Vector2.ZERO,[F.spawn("legacy-target",[40,0],"brute")])
	t.check(sim.restore(JSON.parse_string(JSON.stringify(state))).get("ok",false),"frozen legacy gameplay still attacks and cold-restores without new skills")
