extends RefCounted
const Service = preload("res://game/economy/supply_service.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const Loadout = preload("res://game/ui/loadout_panel.gd")
const PF = preload("res://tests/progression/progression_test_fixture.gd")
const MATERIALS := {
	"evo_whirlwind":["passive","movement"],"evo_wing_squad":["passive","damage"],
	"evo_crossfire":["passive","armor"],"evo_inferno_zone":["passive","fire_interval"],
	"evo_wing_cut":["equipment","odm_dash"],"evo_sky_lance":["equipment","reentry_combo"],
	"evo_echo_assault":["equipment","spin_slash"],"evo_storm_chain":["equipment","fire_zone"]
}
func run(t) -> void:
	var profile := {"owned_doctrine_ids":["doctrine_standard"],"consumables":{"field_bandage":0}}
	var before := profile.duplicate(true)
	var service := Service.new(Callable())
	var options: Dictionary = service._loadout_options(profile,false)
	var panel := Loadout.new()
	t.root.add_child(panel)
	panel.present({"view_revision":1,"loadout":{},"loadout_options":options,"can_start":true})
	var visited: Array[String] = []
	var passive_count := 0
	for target in options.targets:
		if not MATERIALS.has(target.id): continue
		visited.append(str(target.id))
		var expected: Array = MATERIALS[target.id]
		var found := false
		for index in target.requirements.size():
			var requirement: Dictionary = target.requirements[index]
			if requirement.get("kind","") != expected[0] or requirement.get("item_id","") != expected[1]: continue
			found = true
			if expected[0] == "passive": passive_count += 1
			t.check(requirement.required == 1 and requirement.get("requirement_type","") == "owned_skill","actual pre-run combination material uses level-one ownership: "+str(target.id))
			t.check(not requirement.has("current") and not requirement.has("owned") and not requirement.has("met"),"pre-run mixed material never fabricates actual held facts")
			var row := panel.get_node("Requirements_"+str(target.id)).get_child(index)
			var icon: TextureRect = row.get_node("Icon")
			var text: Label = row.get_node("Text")
			t.check(icon.texture != null and icon.is_visible_in_tree() and text.is_visible_in_tree(),"actual pre-run material shape and label are present together")
			t.check(text.text.contains(requirement.name) and text.text.contains("필요 보유 1 이상") and not text.text.contains("✓"),"pre-run material names the actual skill and need without an ownership check")
		t.check(found,"actual pre-run target contains its approved attack or defensive/support material: "+str(target.id))
	t.check(visited.size() == 8 and passive_count == 4,"pre-run UI really covers all eight targets and four support/defensive materials")
	t.check(profile == before,"mixed-material target presentation leaves profile inventory and economy untouched")
	panel.free()
	# Preserved schema-one passive Lv3 still means a level gate, never possession.
	var legacy := Catalog.new(null,null,PF.read("res://tests/run_final_evolution/fixtures/dev4-evolutions.json"))
	service._upgrades = legacy
	var old_options: Dictionary = service._loadout_options(profile,false)
	var old_passives := 0
	for target in old_options.targets:
		for requirement in target.requirements:
			if requirement.kind != "passive": continue
			old_passives += 1
			t.check(requirement.required == 3 and requirement.requirement_type == "level","legacy pre-run passive retains its actual level-three gate")
	t.check(old_passives > 0,"legacy passive display assertions actually execute")
