extends RefCounted
const F = preload("res://tests/progression/progression_test_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const Card = preload("res://game/ui/growth_card.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
func _labels(node: Node) -> String:
	var result := str(node.text) if node is Label else ""
	for child in node.get_children(): result += "\n"+_labels(child)
	return result
func _option(state: Dictionary, kind: String, id: String) -> Dictionary:
	state.upgrade_offer = F.descriptor()
	var level: int = int(state.equipment.get(id,0) if kind == "equipment" else state.passives.get(id,0))
	state.upgrade_offer.options = [{"option_id":kind+":"+id,"item_id":id,"kind":kind,"level":level,"next_level":level+1}]
	state.upgrade_offer.selected_option_id = kind+":"+id
	return View.new().build(state).active_offer.options[0]
func run(t) -> void:
	var state := F.state()
	var catalog := Catalog.new()
	state.rules.allowed_equipment_ids.append_array(["chain_lightning","fire_zone"])
	for id in catalog.evolutions.ids():
		var recipe: Dictionary = catalog.evolutions.definition(id)
		var option := _option(state,"equipment",recipe.base_item_id)
		var before := option.duplicate(true)
		var detail: Dictionary = option.evolution_previews[0]
		var rows := VBoxContainer.new()
		Card.append_evolution_requirements(rows,option)
		var labels := _labels(rows)
		var card := Card.new()
		card.present(option)
		for required in detail.requirements:
			var expected := Card.evolution_requirement_text(required)
			if required.item_id == option.item_id:
				t.check(not labels.contains(expected) and not card.display_text().contains(expected),"selected attack's own level is not repeated as an ultimate condition: "+id)
			else:
				t.check(labels.contains(expected) and card.display_text().contains(expected),"other required skill keeps full name, level and fulfilment: "+id+" "+required.item_id)
		t.check(option == before and detail.requirements[0].item_id == option.item_id,"source recipe retains actual base-level gating: "+id)
		rows.free()
		card.free()
	# A passive card still needs to name the separate attack required by its recipe.
	var passive := _option(state,"passive","movement")
	var rows := VBoxContainer.new()
	Card.append_evolution_requirements(rows,passive)
	for required in passive.evolution_previews[0].requirements:
		t.check(_labels(rows).contains(Card.evolution_requirement_text(required)),"passive previews preserve every distinct recipe requirement")
	rows.free()
	state.equipment.spin_slash = 2
	state.passives.movement = 1
	var partial := _option(state,"equipment","spin_slash")
	rows = VBoxContainer.new()
	Card.append_evolution_requirements(rows,partial)
	t.check(_labels(rows).contains("가벼운 발걸음 · Lv 1/1 · 충족 ✓") and not _labels(rows).contains("회전 베기"),"fulfilled companion retains exact required level and check while own progress is omitted")
	t.check(not catalog.evolutions.evaluate(state,"evo_whirlwind").can_evolve,"omitted base progress still blocks evolution below actual required level")
	rows.free()
	state.equipment.spin_slash = 5
	var evolved: Dictionary = catalog.decorate_option(state,{"option_id":"evolution:evo_whirlwind","item_id":"spin_slash","kind":"evolution","evolution_id":"evo_whirlwind","level":5,"next_level":6},true)
	var unchanged := evolved.duplicate(true)
	rows = VBoxContainer.new()
	Card.append_evolution_requirements(rows,evolved)
	t.check(not _labels(rows).contains("회전 베기") and _labels(rows).contains("가벼운 발걸음"),"final evolution also omits only selected attack from the condition block")
	t.check(evolved == unchanged and evolved.can_select,"filter does not change final evolution eligibility")
	state.passives.erase("movement")
	t.check(not catalog.evolutions.evaluate(state,"evo_whirlwind").can_evolve,"actual missing companion still blocks evolution independently of display filtering")
	rows.free()
