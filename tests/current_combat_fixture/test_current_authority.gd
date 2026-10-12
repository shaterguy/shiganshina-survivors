extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Finite = preload("res://tests/core/finite_chapter_provider.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Frozen = preload("res://tests/core/frozen_gameplay_fixture.gd")
func run(t) -> void:
	var chapter: Dictionary = F.chapter()
	var actual: Dictionary = Chapters.new().load_chapter("chapter_01_shiganshina").chapter
	t.check(chapter.allowed_equipment_ids == actual.allowed_equipment_ids and chapter.evolution_ids == actual.evolution_ids,"current combat fixture includes exactly the current weapons and ultimate recipes")
	t.check(chapter.enemy_catalog == actual.enemy_catalog and chapter.enemy_role_catalog == actual.enemy_role_catalog,"current combat fixture uses current enemy definitions without relabeling historical content")
	for path in Core.GAMEPLAY_PATHS:
		t.check(chapter.content_definition_hashes[path] == actual.content_definition_hashes[path],"current combat fixture is bound to actual gameplay input: "+path)
	var sim = F.simulation(t)
	var state: Dictionary = sim.new_run(chapter,42,F.run_config())
	t.check(not state.has("error_code"),"current finite combat constructs through strict Core")
	if state.has("error_code"): return
	t.check(chapter.world_mode == "finite_test" and not state.has("world"),"current finite fixture does not claim streamed scenario authority")
	t.check(sim.restore(state).get("ok",false),"current finite checkpoint restores under its own provider")
	var city := Core.new(City.new())
	var city_chapter: Dictionary = City.new().load_chapter("chapter_01_shiganshina").chapter
	var city_state: Dictionary = city.new_run(city_chapter,42,F.run_config(1,"doctrine_standard","evo_storm_chain"))
	t.check(not city_state.has("error_code") and city_state.get("world",{}).get("mode") == "streamed_city","current scenario starts new fantasy target with mandatory city authority")
	t.check(not city.restore(state).get("ok",false) and not sim.restore(city_state).get("ok",false),"current city and finite providers reject each other's checkpoint authority")
	var frozen: Dictionary = Finite.new().load_chapter("chapter_01_shiganshina").chapter
	t.check(frozen.content_fingerprint != chapter.content_fingerprint and frozen.allowed_equipment_ids.size() == 6,"frozen six-weapon provider keeps its distinct historical identity")
	t.check(Core.new(Finite.new()).new_run(frozen,42,F.run_config()).get("error_code") == "content_mismatch","current inputs cannot silently authorize a historical provider")
	var historical_inputs: Dictionary = Frozen.inputs()
	for path in Core.GAMEPLAY_PATHS:
		t.check(Chapters.new().definition_digest(historical_inputs[path]) == frozen.content_definition_hashes[path],"preserved legacy inputs match the frozen digest: "+path)
	var historical = Frozen.simulation()
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/evolution_supply_grabber/run_v2.json")).initial
	t.check(historical.restore(old).get("ok",false),"actual frozen checkpoint restores only with its explicit historical gameplay inputs")
	var before := old.duplicate(true)
	t.check(sim.restore(old).get("error_code") == "content_mismatch" and old == before,"current finite provider rejects old checkpoint without rewriting historical authority")
