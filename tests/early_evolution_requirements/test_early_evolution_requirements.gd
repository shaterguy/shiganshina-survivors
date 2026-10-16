extends RefCounted
const Fixture = preload("res://tests/progression/progression_test_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const Card = preload("res://game/ui/growth_card.gd")
const Detail = preload("res://game/ui/evolution_detail_panel.gd")
func _offer(state: Dictionary, kind: String, id: String, level: int) -> void:
	var option_id := kind+":"+id
	state.upgrade_offer = Fixture.descriptor()
	state.upgrade_offer.options = [{"option_id":option_id,"item_id":id,"kind":kind,"level":level,"next_level":level+1}]
	state.upgrade_offer.selected_option_id = option_id
func _option(state: Dictionary) -> Dictionary:
	return View.new().build(state).active_offer.options[0]
func run(t) -> void:
	var state := Fixture.state()
	_offer(state,"equipment","spin_slash",0)
	var before := state.duplicate(true)
	var option := _option(state)
	var previews: Array = option.get("evolution_previews",[])
	t.check(previews.size() == 1,"unowned skill previews its own ultimate before leveling")
	if previews.size() == 1:
		t.check(previews[0].evolution_id == "evo_whirlwind","spin card previews whirlwind rather than the unrelated run target")
		t.check(previews[0].requirements[0].current == 0 and previews[0].requirements[0].required == 5,"preview preserves authored base requirement and actual unowned level")
		t.check(previews[0].requirements[1].item_id == "movement" and previews[0].requirements[1].required == 1,"preview preserves authored companion skill")
	var card := Card.new()
	card.present(option)
	t.check(card.display_text().contains("태풍 회전참") and card.display_text().contains("가벼운 발걸음"),"skill information names the future ultimate and its required companion")
	t.check(not card.display_text().contains("입체기동 돌진"),"unrelated target recipe is absent from this skill description")
	t.check(not card.disabled,"unmet future ultimate conditions do not disable normal growth")
	var choices: Array = []
	card.chosen.connect(func(id): choices.append(id))
	card.pressed.emit()
	t.check(choices == ["equipment:spin_slash"],"early preview preserves normal option selection")
	if card.has_method("append_evolution_requirements"):
		var rows := VBoxContainer.new()
		card.call("append_evolution_requirements",rows,option)
		t.check(not _labels(rows).contains("Lv 0/5") and _labels(rows).contains("가벼운 발걸음 · Lv 0/1 · 미보유"),"acquisition omits redundant own level but keeps the named companion level and fulfilment")
		t.check(_icon_count(rows) == 1,"the other required skill retains its icon without a duplicate selected-attack icon")
		rows.free()
	else: t.check(false,"shared early requirement icon rows exist")
	card.free()
	t.check(state == before,"preview generation and reading do not mutate authority or RNG")
	_offer(state,"passive","armor",0)
	option = _option(state)
	previews = option.get("evolution_previews",[])
	t.check(previews.size() == 1 and previews[0].evolution_id == "evo_crossfire","new passive previews the ultimate it supports")
	_offer(state,"passive","recovery",0)
	option = _option(state)
	t.check(option.get("evolution_previews",[]).is_empty(),"unrelated passive gains no invented recipe")
	state.equipment.spin_slash = 2
	state.passives.movement = 1
	_offer(state,"equipment","spin_slash",2)
	option = _option(state)
	previews = option.get("evolution_previews",[])
	if previews.size() == 1:
		t.check(previews[0].requirements[0].current == 2 and not previews[0].requirements[0].met,"low level preview reflects current base progress")
		t.check(previews[0].requirements[1].met,"owned companion is shown fulfilled without requiring extra levels")
		previews[0].requirements[0].current = 99
		t.check(state.equipment.spin_slash == 2 and _option(state).evolution_previews[0].requirements[0].current == 2,"preview copies cannot mutate the state or later views")
	var view: Dictionary = View.new().build(state)
	var passive: Dictionary = view.owned.passives[0]
	t.check(passive.get("evolution_previews",[]).size() == 1,"owned passive information retains its supported ultimate")
	var panel := Detail.new()
	panel.present_owned(passive,{})
	t.check(panel.display_text().contains("태풍 회전참") and not panel.display_text().contains("추가 진화 없음"),"owned passive detail explains its real recipe role")
	t.check(not panel.display_text().contains("조건을 갖춘 뒤 성장 카드에서 선택합니다."),"recipe details avoid repetitive instruction prose")
	panel.free()
	_all_recipes(t)
	_legacy_cost_labels(t)
func _legacy_cost_labels(t) -> void:
	var legacy = Fixture.legacy_catalog()
	var state := Fixture.state()
	for choice in [["passive","recovery",0],["equipment","blade_slash",1]]:
		_offer(state,choice[0],choice[1],choice[2])
		var before := state.duplicate(true)
		var option: Dictionary = View.new(legacy).build(state).active_offer.options[0]
		t.check(option.requirements.any(func(required): return required.kind == "seal" and required.required == 1),"legacy fixture retains the unrelated target's real seal requirement")
		var card := Card.new()
		card.present(option)
		t.check(not card.disabled and not card.face_text().contains("개조권"),"ordinary legacy growth never claims an evolution seal cost: "+choice[1])
		if choice[0] == "passive": t.check(not card.display_text().contains("개조권"),"unrelated free passive has no invented seal prerequisite in its description")
		t.check(state == before,"rendering a free legacy upgrade preserves game authority")
		card.free()
	state.equipment.blade_slash = 5
	state.passives.movement = 3
	state.tactical_seals = 1
	var evolution: Dictionary = legacy.decorate_option(state,{"option_id":"evolution:evo_wing_cut","item_id":"blade_slash","kind":"evolution","evolution_id":"evo_wing_cut","level":5,"next_level":5},true)
	t.check(evolution.get("can_select",false) and Card.summary(evolution).contains("개조권 1개 소비"),"actual legacy evolution still discloses its authoritative seal cost")
func _all_recipes(t) -> void:
	var state := Fixture.state()
	state.rules.allowed_equipment_ids.append_array(["chain_lightning","fire_zone"])
	var catalog = preload("res://game/progression/upgrade_catalog.gd").new()
	for id in catalog.evolutions.ids():
		var recipe: Dictionary = catalog.evolutions.definition(id)
		_offer(state,"equipment",recipe.base_item_id,int(state.equipment.get(recipe.base_item_id,0)))
		var option := _option(state)
		var previews: Array = option.get("evolution_previews",[])
		t.check(previews.size() == 1 and previews[0] == catalog.evolutions.evaluate(state,id,true),"every early preview is an exact existing recipe evaluation: "+id)
	var legacy = Fixture.legacy_catalog()
	_offer(state,"equipment","blade_slash",1)
	var legacy_view: Dictionary = View.new(legacy).build(state)
	t.check(legacy_view.active_offer.options[0].evolution_previews[0].requirements.size() == 3,"historical recipe previews preserve their actual passive level and seal requirements")
	state.rules.allowed_equipment_ids.erase("wall_cannon")
	_offer(state,"passive","armor",0)
	var unavailable := _option(state)
	t.check(unavailable.evolution_previews[0].status == "unavailable" and not unavailable.evolution_previews[0].can_evolve,"recipe previews never unlock scenario-restricted equipment")
func _labels(node: Node) -> String:
	var result := str(node.text) if node is Label else ""
	for child in node.get_children(): result += "\n"+_labels(child)
	return result
func _icon_count(node: Node) -> int:
	var count := 1 if node is TextureRect and node.texture != null else 0
	for child in node.get_children(): count += _icon_count(child)
	return count
