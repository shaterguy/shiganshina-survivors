extends RefCounted
# Changes that invalidate these tests: requiring a seal or material above ownership one, omitting a base
# attack recipe, accepting an owned level above five, or hiding final stage six.
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const Offers = preload("res://game/progression/growth_offer_service.gd")
const View = preload("res://game/progression/progression_view.gd")
const F = preload("res://tests/progression/progression_test_fixture.gd")
const RECIPES := {
	"blade_slash":["evo_wing_cut","equipment","odm_dash"],
	"spin_slash":["evo_whirlwind","passive","movement"],
	"odm_dash":["evo_sky_lance","equipment","reentry_combo"],
	"reentry_combo":["evo_echo_assault","equipment","spin_slash"],
	"wall_cannon":["evo_crossfire","passive","armor"],
	"ally_cover":["evo_wing_squad","passive","damage"],
	"chain_lightning":["evo_storm_chain","equipment","fire_zone"],
	"fire_zone":["evo_inferno_zone","passive","fire_interval"]
}
func run(t) -> void:
	var catalog := Catalog.new()
	t.check(catalog.validate().is_empty(),"final-stage catalog validates")
	t.check(catalog.evolutions.ids().size() == RECIPES.size(),"every basic run attack has exactly one final evolution")
	for base in RECIPES:
		var id: String = RECIPES[base][0]
		var kind: String = RECIPES[base][1]
		var other: String = RECIPES[base][2]
		var recipe: Dictionary = catalog.evolutions.definition(id)
		t.check(not recipe.is_empty(),"final evolution exists for "+base)
		if recipe.is_empty(): continue
		t.check(recipe.required_weapon_level == 5 and recipe.seal_cost == 0,"final evolution has base five and no seal gate: "+base)
		var materials: Array = recipe.required_passives if kind == "passive" else recipe.get("required_equipment",[])
		var unused: Array = recipe.get("required_equipment",[]) if kind == "passive" else recipe.required_passives
		t.check(materials.size() == 1 and unused.is_empty() and materials[0].get("passive_id" if kind == "passive" else "equipment_id") == other and materials[0].level == 1,"final evolution requires its one approved attack or support material at ownership one: "+base)
		var state := F.state()
		state.rules.allowed_equipment_ids = catalog.equipment.keys()
		state.equipment = {base:5}
		state.run_config.target_evolution_id = id
		var absent: Dictionary = catalog.evolutions.evaluate(state,id)
		t.check(not absent.get("can_evolve",true),"missing partner cannot evolve: "+base)
		state["passives" if kind == "passive" else "equipment"][other] = 1
		var detail: Dictionary = catalog.evolutions.evaluate(state,id)
		t.check(detail.get("can_evolve",false) and detail.requirements.size() == 2,"approved attack or support at level one is sufficient without boss reward: "+base)
		if not detail.get("can_evolve",false): continue
		t.check(detail.get("icon_id","") == "skill_"+id,"evolved skill has its own icon identity: "+base)
		t.check(detail.requirements[1].kind == kind and detail.requirements[1].get("icon_id","") == "skill_"+other and detail.requirements[1].get("owned",false) and detail.requirements[1].get("requirement_type","") == "owned_skill","partner DTO binds name, icon and ownership: "+base)
		var materialized := Offers.new(catalog).materialize(state,F.descriptor())
		t.check(materialized.get("ok",false),"ready final evolution materializes: "+base)
		if not materialized.get("ok",false): continue
		var option: Dictionary = materialized.offer.options[0]
		t.check(option.option_id == "evolution:"+id and option.level == 5 and option.next_level == 6 and option.get("max_level",0) == 6,"offer shows final upgrade 5 to 6: "+base)
		var view := View.new(catalog).build(state)
		var row := _owned(view,base)
		t.check(row.get("level",0) == 5 and row.get("max_level",0) == 6 and not row.get("is_max",true),"base five still has the final stage available: "+base)
		state.evolutions[base] = id
		view = View.new(catalog).build(state)
		row = _owned(view,base)
		t.check(row.get("level",0) == 6 and row.get("base_level",0) == 5 and row.get("max_level",0) == 6 and row.get("is_max",false),"evolved display is six while saved base remains five: "+base)
		t.check(row.get("icon_id","") == "skill_"+id and row.get("evolution_name","") == recipe.name,"owned evolution displays its name and unique icon: "+base)
		state.equipment[base] = 6
		t.check(View.new(catalog).build(state).is_empty(),"authority rejects equipment level six: "+base)
	var support := F.state()
	support.passives = {"armor":5}
	var support_view := View.new(catalog).build(support)
	t.check(not support_view.is_empty() and support_view.owned.passives[0].level == 5 and support_view.owned.passives[0].max_level == 5,"defence and support remain five of five")
func _owned(view: Dictionary, id: String) -> Dictionary:
	for row in view.get("owned",{}).get("equipment",[]):
		if row.item_id == id: return row
	return {}
