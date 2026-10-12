extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Catalog = preload("res://game/presentation/combat_vfx_catalog.gd")
const Director = preload("res://game/presentation/combat_vfx_director.gd")
const Renderer = preload("res://game/presentation/combat_vfx_renderer.gd")
# Mutation counterexamples: absent/zero/negative/string/nonfinite presentation
# bounds must not become a runtime error, invisible command or inverted raster.
func run(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat_vfx.json"))
	var sim = F.simulation(t)
	var state: Dictionary = sim.new_run(F.chapter(),42,F.run_config())
	state.equipment = {"reentry_combo":1}
	var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO,[F.spawn("contract-target",[50,0],"brute")])
	var snapshot: Dictionary = sim.snapshot(state)
	var context := {"tick":snapshot.active_tick,"origin_revision":0,"asset_metadata":manifest}
	var normal := Director.new(); normal.consume(events,snapshot)
	var expected := Renderer.new().commands(normal.present(snapshot),context)
	var triples := expected.filter(func(c): return c.get("asset_id") == "vfx_reentry_triple")
	t.check(triples.size() == 1 and triples[0].contact_size == Vector2(36,36),"valid authored size keeps exact real Core triple")
	t.check(Catalog.new(definitions).validate(manifest) == ["missing_art:vfx_wire_taut"],"new size contract does not reject other recipes")
	for value in [[0,36],[-36,36],"36,36",[36],["36",36],[NAN,36],[INF,36],[36,INF],[true,36],[1.0e100,36],[1.0e-100,36],null]:
		var changed := definitions.duplicate(true)
		for recipe in changed.recipes:
			if recipe.base_item_id != "reentry_combo": continue
			if value == null: recipe.phases.cast.erase("presentation_size_px")
			else: recipe.phases.cast.presentation_size_px = value
		var catalog := Catalog.new(changed)
		t.check("invalid_presentation_size:reentry_combo.cast" in catalog.validate(manifest),"Catalog rejects malformed targeted display bounds: "+str(value))
		var director := Director.new(catalog); director.consume(events,snapshot)
		var commands := Renderer.new().commands(director.present(snapshot),context)
		var rejected := commands.filter(func(c): return c.get("asset_id") == "vfx_reentry_triple")
		t.check(rejected.size() == 1 and rejected[0].get("diagnostic") == "invalid_presentation_size" and not rejected[0].has("atlas_region"),"Renderer fails closed with explicit diagnostic: "+str(value))
		t.check(commands.filter(func(c): return c.get("asset_id") == "vfx_hit_spark").size() == 1,"malformed triple does not suppress independent actual hit feedback")
		t.check(Renderer.new().commands(normal.present(snapshot),context) == expected,"malformed recipe cannot alter existing valid rendering")
