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
	var evolution_views: Array[Dictionary] = []
	for id in _catalog.evolutions.ids(): evolution_views.append(_catalog.evolutions.evaluate(state,id,true))
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
			var option: Dictionary = _catalog.decorate_option(state,original,true)
			if option.is_empty() or identities.has(option.option_id): return {}
			if option.kind != "evolution": option.evolution_previews = _skill_evolutions(option.item_id,option.kind,evolution_views)
			identities[option.option_id] = true
			options.append(option)
		if not identities.has(source.selected_option_id): return {}
		offer = {"offer_id":source.offer_id,"source":source.source,"level_ordinal":source.level_ordinal,"selected_option_id":source.selected_option_id,"options":options}
	var target: Dictionary = _catalog.evolutions.evaluate(state,state.run_config.target_evolution_id,true)
	return {"view_revision":int(state.view_revision),"slots":{"equipment":{"used":state.equipment.size(),"max":4},"passive":{"used":state.passives.size(),"max":4}},"target":target,"evolutions":evolution_views,"active_offer":offer,"owned":_owned(state,evolution_views)}

func _skill_evolutions(item_id: String, kind: String, evolution_views: Array) -> Array[Dictionary]:
	# These are read-only previews, never new offers or eligibility rules.
	var result: Array[Dictionary] = []
	for detail in evolution_views:
		if kind == "equipment" and detail.base_item_id == item_id:
			result.append(detail.duplicate(true))
		elif kind == "passive":
			for required in detail.requirements:
				if required.kind == kind and required.item_id == item_id:
					result.append(detail.duplicate(true))
					break
	return result
func _owned(state: Dictionary, evolution_views: Array) -> Dictionary:
	var result := {"equipment":[],"passives":[]}
	for kind in ["equipment","passives"]:
		var definitions: Dictionary = _catalog.equipment if kind == "equipment" else _catalog.passives
		var ids: Array = state[kind].keys()
		ids.sort()
		for id in ids:
			var definition: Dictionary = definitions[id]
			var level := int(state[kind][id])
			var row := {"item_id":str(id),"name":definition.name,"level":level,"base_level":level,"max_level":int(definition.max_level),"display_level":level,"display_max_level":int(definition.max_level),"icon_id":"skill_"+str(id),"evolution_name":"","evolution_icon_id":"","is_max":level == int(definition.max_level),"evolution_id":"","evolution_status":"unavailable","is_evolved":false,"requirements":[],"attack_summary":"","effect_stats":{}}
			row.evolution_previews = _skill_evolutions(str(id),"equipment" if kind == "equipment" else "passive",evolution_views)
			if kind == "equipment":
				for detail in row.evolution_previews:
					row.evolution_id = detail.evolution_id
					row.max_level = 6
					row.display_max_level = 6
					row.evolution_name = detail.name
					row.evolution_icon_id = detail.icon_id
					row.evolution_status = detail.status
					row.is_evolved = detail.status == "evolved"
					row.requirements = detail.requirements.duplicate(true)
					if row.is_evolved:
						row.level = 6
						row.display_level = 6
						row.icon_id = detail.icon_id
						row.name = detail.name
						row.effect_stats = detail.effect_delta.duplicate(true)
					row.is_max = row.level == row.max_level
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
		var patterns := {"evo_whirlwind":"확장 회전참 3회","evo_sky_lance":"전진 관통참 3구간","evo_echo_assault":"잔영 교차참 3회","evo_wing_squad":"편대 교차 엄호 3줄"}
		if patterns.has(row.evolution_id): return str(patterns[row.evolution_id])+" · "+interval
		if row.evolution_id == "evo_storm_chain": return "폭풍 번개 · 최대 %d연결 · %s" % [int(stats.chain_count),interval]
		if row.evolution_id == "evo_inferno_zone": return "지옥불 %d회 + 마지막 대폭발 · %s초 뒤 폭발 · %s" % [int(stats.stages)-1,String.num(float(stats.stage_delays[-1])/60.0,2),interval]
		var times: Array[String] = []
		for tick in stats.stage_delays: times.append(String.num(float(tick)/60.0,2)+"초")
		var form: String = definition.description
		if row.evolution_id == "evo_wing_cut": form = "방향을 고정한 연속 베기"
		elif row.evolution_id == "evo_crossfire": form = "고정한 두 지점 포격"
		return "%s · %d회 타격 (%s) · %s" % [form,int(stats.stages)," / ".join(times),interval]
	if definition.mode == "chain": return "연쇄번개 · 최대 %d연결 · %s" % [int(stats.chain_count),interval]
	if definition.mode == "zone": return "고정 화염지대 · %d회 타격 · %s초마다 피해 · %s" % [int(stats.pulse_count),String.num(float(stats.pulse_interval)/60.0,2),interval]
	var form := str({"sector":"전방 부채꼴 베기","circle":"주변 원형 베기","line":"목표 방향 직선 베기","combo":"한 목표 집중 연격","projectile":"목표 방향 투사체"}.get(definition.mode,definition.description))
	if definition.mode == "combo": form += " · 총 피해 "+String.num(float(stats.total_damage),2)
	elif definition.mode == "projectile" and float(stats.splash_radius) > 0: form += " · 폭발 반경 "+String.num(float(stats.splash_radius),1)
	return form+" · "+interval
