extends RefCounted
const Service = preload("res://game/economy/supply_service.gd")
const Loadout = preload("res://game/ui/loadout_panel.gd")
func run(t) -> void:
	var profile := {"owned_doctrine_ids":["doctrine_standard"],"consumables":{"field_bandage":0}}
	var before := profile.duplicate(true)
	var service := Service.new(Callable())
	var options: Dictionary = service._loadout_options(profile,false)
	for target in options.targets:
		t.check(target.get("icon_id","") == "skill_"+str(target.id),"pre-run target shares evolution icon identity: "+str(target.id))
		for requirement in target.requirements:
			t.check(requirement.get("icon_id","") == "skill_"+str(requirement.item_id),"pre-run target prerequisite has the real skill icon identity")
			t.check(requirement.get("requirement_type","") in ["base_level","owned_skill","level"],"pre-run prerequisite identifies level or ownership criterion")
			t.check(not requirement.has("owned") and not requirement.has("met"),"pre-run DTO never fabricates in-run ownership or eligibility")
	var loadout := Loadout.new()
	loadout.present({"view_revision":1,"loadout":{},"loadout_options":options,"can_start":true})
	t.check(not loadout.display_text().contains("보유 ✓"),"pre-run target chips show needed skills without claiming they are already acquired")
	for target in options.targets:
		var button: Button = loadout.option_button("target_evolution_id",str(target.id))
		t.check(button.icon != null,"pre-run option renders the real evolution shape")
	t.check(profile == before,"target presentation keeps economy ownership and inventory unchanged")
	loadout.free()
