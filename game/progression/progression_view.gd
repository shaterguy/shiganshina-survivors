class_name ProgressionView
extends RefCounted
# NEW derived view: no RNG, authority mutation or implicit choice/offer promotion.
const Upgrades = preload("res://game/progression/upgrade_catalog.gd")
var _catalog
func _init(upgrade_catalog = null) -> void:
	_catalog = Upgrades.new() if upgrade_catalog == null else upgrade_catalog
func build(state: Dictionary) -> Dictionary:
	if not _catalog.presentation_state_valid(state) or not Upgrades.integer_valid(state.get("view_revision")) or not state.get("upgrade_offer") is Dictionary: return {}
	var source: Dictionary = state.upgrade_offer
	# Bound only our DTO fragment. A large valid combat state is not a catalog.
	if not Upgrades.json_data_valid(source): return {}
	var offer := {}
	if not source.is_empty():
		if not source.get("options") is Array or source.options.is_empty() or source.options.size() > 3: return {}
		for field in ["offer_id","source","selected_option_id"]:
			if not source.get(field) is String or source[field].is_empty(): return {}
		if not source.source in ["level","boss"] or not Upgrades.integer_valid(source.get("level_ordinal"),1): return {}
		var options: Array[Dictionary] = []
		var identities := {}
		for original in source.options:
			if not original is Dictionary: return {}
			var option: Dictionary = _catalog.decorate_option(state,original)
			if option.is_empty() or identities.has(option.option_id): return {}
			identities[option.option_id] = true
			options.append(option)
		if not identities.has(source.selected_option_id): return {}
		offer = {"offer_id":source.offer_id,"source":source.source,"level_ordinal":source.level_ordinal,"selected_option_id":source.selected_option_id,"options":options}
	var evolution_views: Array[Dictionary] = []
	for id in _catalog.evolutions.ids(): evolution_views.append(_catalog.evolutions.evaluate(state,id))
	var target: Dictionary = _catalog.evolutions.evaluate(state,state.run_config.target_evolution_id)
	return {"view_revision":int(state.view_revision),"slots":{"equipment":{"used":state.equipment.size(),"max":4},"passive":{"used":state.passives.size(),"max":4}},"target":target,"evolutions":evolution_views,"active_offer":offer,"owned":_owned(state)}

func _owned(state: Dictionary) -> Dictionary:
	var result := {"equipment":[],"passives":[]}
	for kind in ["equipment","passives"]:
		var definitions: Dictionary = _catalog.equipment if kind == "equipment" else _catalog.passives
		var ids: Array = state[kind].keys()
		ids.sort()
		for id in ids:
			var definition: Dictionary = definitions[id]
			var level := int(state[kind][id])
			var row := {"item_id":str(id),"name":definition.name,"level":level,"max_level":int(definition.max_level),"is_max":level == int(definition.max_level),"evolution_id":"","evolution_status":"unavailable","is_evolved":false,"requirements":[],"attack_summary":"","effect_stats":{}}
			if kind == "equipment":
				for recipe_id in _catalog.evolutions.ids():
					var detail: Dictionary = _catalog.evolutions.evaluate(state,recipe_id)
					if detail.base_item_id != id: continue
					row.evolution_id = recipe_id
					row.evolution_status = detail.status
					row.is_evolved = detail.status == "evolved"
					row.requirements = detail.requirements.duplicate(true)
					if row.is_evolved: row.effect_stats = detail.effect_delta.duplicate(true)
					break
				if not row.is_evolved:
					row.effect_stats = _catalog.weapon_stats(state,id,level)
					if definition.mode == "combo": row.effect_stats.total_damage = float(row.effect_stats.damage)*int(row.effect_stats.hits)
				row.attack_summary = _attack_summary(definition,row)
			else:
				var base: float = _catalog._stat_base(state,definition.stat)
				row.effect_stats = {"stat":definition.stat,"value":_catalog.stat(state,definition.stat,base)}
				row.attack_summary = definition.description
			result[kind].append(row)
	return result
func _attack_summary(definition: Dictionary, row: Dictionary) -> String:
	var stats: Dictionary = row.effect_stats
	var interval := String.num(float(stats.cooldown_ticks)/60.0,2)+"초 간격"
	if row.is_evolved:
		var times: Array[String] = []
		for tick in stats.stage_delays: times.append(String.num(float(tick)/60.0,2)+"초")
		var form := "방향을 고정한 연속 베기" if row.evolution_id == "evo_wing_cut" else "고정한 두 지점 포격"
		return "%s · %d회 타격 (%s) · %s" % [form,int(stats.stages)," / ".join(times),interval]
	var form := str({"sector":"전방 부채꼴 베기","circle":"주변 원형 베기","line":"목표 방향 직선 베기","combo":"한 목표 집중 연격","projectile":"목표 방향 투사체"}.get(definition.mode,definition.description))
	if definition.mode == "combo": form += " · 총 피해 "+String.num(float(stats.total_damage),2)
	elif definition.mode == "projectile" and float(stats.splash_radius) > 0: form += " · 폭발 반경 "+String.num(float(stats.splash_radius),1)
	return form+" · "+interval
