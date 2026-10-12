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
	return {"view_revision":int(state.view_revision),"slots":{"equipment":{"used":state.equipment.size(),"max":4},"passive":{"used":state.passives.size(),"max":4}},"target":target,"evolutions":evolution_views,"active_offer":offer}
