extends RefCounted
func run(t) -> void:
	_legacy(t)
	_dto(t)
func _legacy(t) -> void:
	var Registry = load("res://game/progression/character_catalog.gd")
	var registry = Registry.new()
	var profile := {"cleared_chapter_ids":["chapter_01_shiganshina"],"unlocked_character_ids":[]}
	var before := JSON.stringify(profile)
	t.check(registry.run_character_id(profile,"chapter_01_shiganshina") == "garrison_01","Legacy cleared profile retains implicit default protagonist without invented unlock writes")
	t.check(registry.selection_error(profile,"chapter_01_shiganshina","garrison_01") == "","Default character is intrinsically available without a legacy unlock row")
	t.check(registry.selection_error(profile,"chapter_01_shiganshina","mikasa_01") == "character_locked","Intrinsic default never grants a new character")
	t.check(JSON.stringify(profile) == before,"Registry queries do not backfill legacy profile")
	var rows: Array = registry.selection_rows(profile,"chapter_01_shiganshina",false)
	t.check(rows[0].is_selected and rows[0].is_unlocked and rows[0].can_select,"UI truthfully shows legacy default as selected and available")
	var Cases = load("res://tests/fixtures/evolution_supply_fixture.gd")
	var fixture = Cases.new()
	var save: Dictionary = fixture.game_save()
	save.profile.cleared_chapter_ids = ["chapter_01_shiganshina"]
	save.profile.unlocked_character_ids = []
	var Service = load("res://game/economy/supply_service.gd")
	var service = Service.new(fixture.make_run)
	var chapter := {"chapter_id":"chapter_01_shiganshina","content_revision":"ch01.3-rebuild.7-grabber-hand"}
	var start: Dictionary = service.prepare_run_start(save,chapter,42,"start:%s:%d" % [save.career_id,save.next_run_serial],save.store_revision)
	t.check(start.get("ok",false),"Legacy empty unlock list continues to start its original protagonist")
func _dto(t) -> void:
	var Core = load("res://game/core/run_simulation.gd")
	var Finite = load("res://tests/core/finite_chapter_provider.gd")
	var F = load("res://tests/core/new_current_regression_fixture.gd")
	var Catalog = load("res://game/progression/upgrade_catalog.gd")
	var Registry = load("res://game/progression/character_catalog.gd")
	var catalog = Catalog.new()
	var sim = Core.new(Finite.new())
	var config: Dictionary = F.run_config()
	config.character_id = "mikasa_01"
	var state: Dictionary = sim.new_run(F.chapter(),42,config)
	t.check(catalog.state_valid(state),"Actual character DTO is accepted")
	for value in [NAN,INF,-1.0,0.0,0.84,1.01,"0.85",true,null,[],{}]:
		var bad: Dictionary = state.duplicate(true)
		bad.rules.character_blade_cooldown_multiplier = value
		t.check(not catalog.state_valid(bad),"Pure DTO rejects invalid character cooldown: "+str(value))
		# Avoid coercion/runtime warnings on the known-red malformed baseline.
		if not catalog.state_valid(bad): t.check(catalog.weapon_stats(bad,"blade_slash",1).is_empty(),"Invalid trait cannot emit usable weapon stats")
	var legacy: Dictionary = sim.new_run(F.chapter(),42,F.run_config())
	t.check(catalog.state_valid(legacy),"Absent legacy character trait remains valid")
	var registry = Registry.new()
	t.check(registry.definition("mikasa_01").trait_text.contains(catalog.evolutions.definition("evo_wing_cut").name),"Character metadata uses the actual authored evolution name")
