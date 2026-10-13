extends RefCounted
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const F = preload("res://tests/progression/progression_test_fixture.gd")
func run(t) -> void:
	var data := F.read("res://data/evolutions.json")
	data.items.evo_whirlwind.required_equipment = []
	data.items.evo_whirlwind.required_passives = [{"passive_id":"movement","level":1}]
	var catalog := Catalog.new(null,null,data)
	t.check(catalog.validate().is_empty(),"schema two accepts exactly one approved support material at ownership one")
	if not catalog.validate().is_empty(): return
	var state := F.state()
	state.equipment = {"spin_slash":5}
	state.run_config.target_evolution_id = "evo_whirlwind"
	t.check(not catalog.evolutions.evaluate(state,"evo_whirlwind").get("can_evolve",true),"unowned support material cannot evolve")
	state.passives.movement = 1
	var detail: Dictionary = catalog.evolutions.evaluate(state,"evo_whirlwind")
	t.check(detail.get("can_evolve",false) and detail.requirements[1].kind == "passive" and detail.requirements[1].requirement_type == "owned_skill" and detail.requirements[1].owned and detail.requirements[1].icon_id == "skill_movement","support ownership uses the same concise name/icon/owned DTO")
	for level in [0,2,3]:
		var bad := data.duplicate(true)
		bad.items.evo_whirlwind.required_passives[0].level = level
		t.check(not Catalog.new(null,null,bad).validate().is_empty(),"schema two support recipe rejects a material gate other than one: "+str(level))
	var double_material := data.duplicate(true)
	double_material.items.evo_whirlwind.required_equipment = [{"equipment_id":"blade_slash","level":1}]
	t.check(not Catalog.new(null,null,double_material).validate().is_empty(),"schema two cannot secretly require both attack and support materials")
