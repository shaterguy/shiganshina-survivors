extends RefCounted
const Fixture = preload("res://tests/progression/progression_test_fixture.gd")
const Upgrades = preload("res://game/progression/upgrade_catalog.gd")
func run(t) -> void:
	var path := "res://game/progression/evolution_catalog.gd"
	t.check(ResourceLoader.exists(path),"NEW evolution catalog exists")
	if not ResourceLoader.exists(path): return
	var upgrades = Upgrades.new()
	var script = load(path)
	var catalog = script.new(upgrades)
	t.check(catalog.validate().is_empty(),"initial 845 recipes validate")
	t.check(catalog.ids() == ["evo_crossfire","evo_wing_cut"],"recipe IDs have stable sorted order")
	var state := Fixture.state()
	for weapon in [4,5]:
		for passive in [0,2,3]:
			for seals in [0,1]:
				state.equipment = {"blade_slash":weapon}
				state.passives = {} if passive == 0 else {"movement":passive}
				state.tactical_seals = seals
				var detail: Dictionary = catalog.evaluate(state,"evo_wing_cut")
				t.check(detail.get("can_evolve",false) == (weapon == 5 and passive == 3 and seals == 1),"weapon/passive/seal AND boundary %d/%d/%d"%[weapon,passive,seals])
				t.check(detail.get("requirements",[]).size() == 3,"known recipe exposes all three requirements")
	state.equipment = {"blade_slash":5}
	state.passives = {"movement":3}
	state.tactical_seals = 1
	var detail: Dictionary = catalog.evaluate(state,"evo_wing_cut")
	t.check(detail.get("status") == "ready","exact prerequisites produce ready")
	if not detail.has("effect_delta"): return
	t.check(detail.effect_delta.stage_damage == [27.0,36.0] and detail.effect_delta.stage_delays == [0,12],"wing damage and delays are hand-calculated")
	t.check(detail.effect_delta.radius == 88 and detail.effect_delta.arc_degrees == 110 and detail.effect_delta.cooldown_ticks == 48,"wing geometry and cooldown match frozen tuning")
	state.equipment.wall_cannon = 5
	state.passives.fire_interval = 3
	detail = catalog.evaluate(state,"evo_crossfire")
	t.check(detail.status == "ready" and is_equal_approx(detail.effect_delta.stage_damage[0],44.8),"crossfire is independently ready and snapshots64*0.7 damage")
	t.check(detail.effect_delta.stage_delays == [36,66] and detail.effect_delta.radius == 56 and detail.effect_delta.acquisition_range == 456 and detail.effect_delta.point_offset == 24,"crossfire fixed timing/geometry")
	t.check(detail.effect_delta.cooldown_ticks == 128,"three fire interval levels modify168 cooldown once (round127.68)")
	var before := state.duplicate(true)
	for index in range(12): catalog.evaluate(state,"evo_wing_cut")
	t.check(state == before,"evaluate never mutates inputs or consumes any RNG")
	state.evolutions.blade_slash = "evo_wing_cut"
	state.tactical_seals = 0
	detail = catalog.evaluate(state,"evo_wing_cut")
	t.check(detail.status == "evolved" and not detail.can_evolve,"applied evolution is informational only")
	state = Fixture.state()
	state.passives = {"damage":1,"armor":1,"max_health":1,"recovery":1}
	detail = catalog.evaluate(state,"evo_wing_cut")
	t.check(detail.status == "blocked" and detail.requirements[1].blocked_reason == "passive_slots","missing passive with four slots is blocked")
	state = Fixture.maxed()
	state.run_config.target_evolution_id = "evo_crossfire"
	detail = catalog.evaluate(state,"evo_crossfire")
	t.check(detail.status == "blocked" and detail.requirements[0].blocked_reason == "equipment_slots","missing cannon with four weapons is blocked")
	state = Fixture.state()
	state.chapter_id = "chapter_02_future"
	detail = catalog.evaluate(state,"evo_wing_cut")
	t.check(detail.status == "unavailable" and not detail.can_evolve and detail.requirements[0].blocked_reason == "chapter_not_allowed","unapproved chapter makes recipe unavailable")
	state = Fixture.state()
	state.rules.allowed_equipment_ids.erase("blade_slash")
	state.equipment = {}
	detail = catalog.evaluate(state,"evo_wing_cut")
	t.check(detail.status == "unavailable" and not detail.can_evolve,"chapter weapon allow-list restricts recipe")
	t.check(catalog.evaluate(Fixture.state(),"evo_thunder_spear").is_empty(),"unknown recipe returns absent lookup not ready")
	var row: Dictionary = catalog.definition("evo_wing_cut")
	row.required_passives[0].level = 1
	t.check(catalog.definition("evo_wing_cut").required_passives[0].level == 3,"definition returns a deep copy")
	_hostile_data(t,script,upgrades)
func _hostile_data(t,script,upgrades) -> void:
	var data := Fixture.read("res://data/evolutions.json")
	for field in ["story_year","required_weapon_level","seal_cost","effect_id","base_item_id","recipe_id","chapter_ids","required_passives","effect_params"]:
		var bad := data.duplicate(true)
		bad.items.evo_wing_cut.erase(field)
		t.check(not script.new(upgrades,bad).validate().is_empty(),"missing recipe field rejected: "+field)
	var changes := [{"story_year":854},{"story_year":845.5},{"story_year":NAN},{"required_weapon_level":4},{"seal_cost":0},{"effect_id":"thunder_spear"},{"base_item_id":"evo_crossfire"},{"recipe_id":"other"},{"chapter_ids":["chapter_02_future"]},{"required_passives":[{"passive_id":"unknown","level":3}]},{"required_passives":[{"passive_id":"movement","level":6}]},{"required_passives":[{"passive_id":"movement","level":3},{"passive_id":"movement","level":3}]}]
	for change in changes:
		var bad := data.duplicate(true)
		bad.items.evo_wing_cut.merge(change,true)
		var invalid = script.new(upgrades,bad)
		t.check(not invalid.validate().is_empty() and invalid.ids().is_empty() and invalid.definition("evo_wing_cut").is_empty(),"hostile recipe fails closed: "+str(change))
	for value in [-1,0,NAN,INF,"88",2147483648]:
		var bad := data.duplicate(true)
		bad.items.evo_wing_cut.effect_params.radius = value
		t.check(not script.new(upgrades,bad).validate().is_empty(),"invalid radius rejected: "+str(value))
	for bad in [{},{"schema_version":99,"items":{}},{"schema_version":1,"items":[]},{"schema_version":1,"items":{"evo_bad":"bad"}}]:
		t.check(not script.new(upgrades,bad).validate().is_empty(),"invalid recipe container fails closed")
	var private_input := data.duplicate(true)
	var private_catalog = script.new(upgrades,private_input)
	private_input.items.evo_wing_cut.name = "mutated"
	t.check(private_catalog.definition("evo_wing_cut").name != "mutated","catalog does not retain caller-owned definition aliases")
