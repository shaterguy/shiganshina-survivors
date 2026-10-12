class_name FantasyAttackResolver
extends RefCounted
# Pure, bounded proposals. The Core remains the only hit/event authority.
static func chain_records(state: Dictionary, stats: Dictionary, item_id: String, cast_id: String, query: Callable, clear: Callable) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var used := {}
	var point := Vector2(state.player.position[0],state.player.position[1])
	for link in mini(12,int(stats.chain_count)):
		var reach := float(stats.range) if link == 0 else float(stats.hop_range)
		var nearest := INF
		var chosen := -1
		var chosen_id := ""
		for index in query.call(point,reach+48.0):
			var entity: Dictionary = state.entities[index]
			var id := str(entity.id)
			if entity.hp <= 0 or used.has(id): continue
			var target := Vector2(entity.position[0],entity.position[1])
			var distance := point.distance_squared_to(target)
			if distance > pow(reach+float(entity.radius),2): continue
			if distance > nearest or (distance == nearest and chosen >= 0 and id >= chosen_id): continue
			if not clear.call(point,target): continue
			nearest = distance
			chosen = index
			chosen_id = id
		if chosen < 0: break
		var target := Vector2(state.entities[chosen].position[0],state.entities[chosen].position[1])
		var direction := point.direction_to(target)
		if direction.is_zero_approx(): direction = Vector2.RIGHT
		used[chosen_id] = true
		records.append({"attack_id":cast_id+":"+str(link),"cast_id":cast_id,"base_item_id":item_id,"evolution_id":state.evolutions.get(item_id,""),"attack_started_tick":int(state.active_tick),"execute_tick":int(state.active_tick),"stage_index":link,"stage_count":0,"origin_binding":"fixed","origin":[point.x,point.y],"direction":[direction.x,direction.y],"shape":"line","radius":0.0,"length":sqrt(nearest),"width":8.0,"arc_degrees":360.0,"damage":float(stats.damage),"hit_entity_ids":[],"target_id":chosen_id,"pose_tag":"chain_lightning","art_id":"vfx_storm_chain" if state.evolutions.get(item_id,"") == "evo_storm_chain" else "vfx_chain_lightning"})
		point = target
	for record in records: record.stage_count = records.size()
	return records

const Upgrades = preload("res://game/progression/upgrade_catalog.gd")
const FIRE_FIELDS := ["attack_id","cast_id","base_item_id","evolution_id","attack_started_tick","execute_tick","stage_index","stage_count","origin_binding","origin","direction","shape","radius","arc_degrees","damage","hit_entity_ids","pose_tag","art_id","cast_level"]
static func is_fantasy(record: Dictionary) -> bool:
	return record.get("base_item_id","") in ["chain_lightning","fire_zone"]
static func fire_spec(catalog, level: int, evolution: String) -> Dictionary:
	var row: Dictionary = catalog.equipment.fire_zone
	if evolution == "evo_inferno_zone":
		var params: Dictionary = catalog.evolutions.definition(evolution).effect_params
		return {"delays":params.stage_delays,"multipliers":params.damage_multipliers,"radius":float(params.radius),"last_radius":float(params.eruption_radius)}
	var delays := []
	var multipliers := []
	for index in int(row.pulse_count)+(level-1)*int(row.pulse_per_level):
		delays.append(index*int(row.pulse_interval))
		multipliers.append(1.0)
	var radius := float(row.zone_radius)+(level-1)*float(row.zone_radius_per_level)
	return {"delays":delays,"multipliers":multipliers,"radius":radius,"last_radius":radius}
static func fire_records(state: Dictionary, catalog, target: Vector2, direction: Vector2, cast_id: String) -> Array[Dictionary]:
	var level := int(state.equipment.fire_zone)
	var evolution: String = state.evolutions.get("fire_zone","")
	var stats: Dictionary = catalog.weapon_stats(state,"fire_zone",level)
	var spec := fire_spec(catalog,level,evolution)
	var scale: float = catalog.stat(state,"range_multiplier",1.0)
	var records: Array[Dictionary] = []
	for index in spec.delays.size():
		var execute := int(state.active_tick)+int(spec.delays[index])
		if execute > 2147483647: return []
		var eruption: bool = evolution == "evo_inferno_zone" and index == spec.delays.size()-1
		records.append({"attack_id":cast_id+":"+str(index),"cast_id":cast_id,"base_item_id":"fire_zone","evolution_id":evolution,"attack_started_tick":int(state.active_tick),"execute_tick":execute,"stage_index":index,"stage_count":spec.delays.size(),"origin_binding":"fixed","origin":[target.x,target.y],"direction":[direction.x,direction.y],"shape":"circle","radius":float(spec.last_radius if eruption else spec.radius)*scale,"arc_degrees":360.0,"damage":float(stats.damage)*float(spec.multipliers[index]),"hit_entity_ids":[],"pose_tag":"fire_zone","art_id":_fire_art(evolution,eruption),"cast_level":level})
	return records
static func validate_records(state: Dictionary, catalog) -> bool:
	var casts := {}
	var ids := {}
	var owners := {}
	for record in state.player_attack_instances:
		if not record is Dictionary: return false
		if not record.get("attack_id") is String or not record.get("cast_id") is String or not record.get("base_item_id") is String: return false
		if ids.has(record.attack_id) or (owners.has(record.cast_id) and owners[record.cast_id] != record.base_item_id): return false
		ids[record.attack_id] = true
		owners[record.cast_id] = record.base_item_id
		if not is_fantasy(record): continue
		if not _fire_valid(state,catalog,record): return false
		if not casts.has(record.cast_id): casts[record.cast_id] = []
		casts[record.cast_id].append(record)
	if casts.size() > 2: return false
	for records in casts.values():
		var first: Dictionary = records[0]
		var spec := fire_spec(catalog,int(first.cast_level),first.evolution_id)
		var expected := []
		for index in spec.delays.size():
			if int(first.attack_started_tick)+int(spec.delays[index]) > int(state.active_tick): expected.append(index)
		if records.size() != expected.size(): return false
		var seen := {}
		for record in records:
			if not int(record.stage_index) in expected or seen.has(int(record.stage_index)): return false
			seen[int(record.stage_index)] = true
			for field in ["base_item_id","evolution_id","attack_started_tick","origin","direction","cast_level","stage_count"]:
				if record[field] != first[field]: return false
			if absf(float(record.damage)/float(spec.multipliers[int(record.stage_index)])-float(first.damage)/float(spec.multipliers[int(first.stage_index)])) > 0.000001: return false
			var radius_base := float(spec.last_radius) if int(record.stage_index) == spec.delays.size()-1 else float(spec.radius)
			var first_base := float(spec.last_radius) if int(first.stage_index) == spec.delays.size()-1 else float(spec.radius)
			if absf(float(record.radius)/radius_base-float(first.radius)/first_base) > 0.000001: return false
	return true
static func _fire_valid(state: Dictionary, catalog, record: Dictionary) -> bool:
	if record.size() != FIRE_FIELDS.size() or not record.has_all(FIRE_FIELDS) or not Upgrades.json_data_valid(record): return false
	if record.base_item_id != "fire_zone" or not record.evolution_id is String or not record.evolution_id in ["","evo_inferno_zone"]: return false
	if not Upgrades.integer_valid(record.cast_level,1,int(state.equipment.get("fire_zone",0))): return false
	if not record.evolution_id.is_empty() and (record.cast_level != 5 or state.evolutions.get("fire_zone","") != record.evolution_id): return false
	if not record.cast_id is String or not _cast_id_valid(state,record.cast_id): return false
	var spec := fire_spec(catalog,int(record.cast_level),record.evolution_id)
	if not Upgrades.integer_valid(record.stage_index,0,spec.delays.size()-1) or record.stage_count != spec.delays.size(): return false
	if record.attack_id != record.cast_id+":"+str(int(record.stage_index)): return false
	if not Upgrades.integer_valid(record.attack_started_tick,0,int(state.active_tick)) or not Upgrades.integer_valid(record.execute_tick,int(state.active_tick)+1): return false
	if record.execute_tick != int(record.attack_started_tick)+int(spec.delays[int(record.stage_index)]): return false
	if not _position(record.origin) or not _position(record.direction) or not is_equal_approx(Vector2(record.direction[0],record.direction[1]).length_squared(),1.0): return false
	if record.origin_binding != "fixed" or record.shape != "circle" or record.arc_degrees != 360.0 or record.pose_tag != "fire_zone": return false
	var eruption: bool = record.evolution_id == "evo_inferno_zone" and int(record.stage_index) == spec.delays.size()-1
	if record.art_id != _fire_art(record.evolution_id,eruption): return false
	if not record.hit_entity_ids is Array or not record.hit_entity_ids.is_empty(): return false
	return not _canonical_value(state,catalog,record,"damage").is_empty() and not _canonical_value(state,catalog,record,"radius").is_empty()
static func canonicalize(state: Dictionary, catalog) -> bool:
	var changes := []
	for record in state.player_attack_instances:
		if not is_fantasy(record): continue
		var damage := _canonical_value(state,catalog,record,"damage")
		var radius := _canonical_value(state,catalog,record,"radius")
		if damage.size() != 1 or radius.size() != 1: return false
		changes.append({"record":record,"damage":damage[0],"radius":radius[0]})
	for change in changes:
		change.record.cast_level = int(change.record.cast_level)
		change.record.damage = change.damage
		change.record.radius = change.radius
	return true
static func _canonical_value(state: Dictionary, catalog, record: Dictionary, field: String) -> Array:
	if not Upgrades.number_valid(record[field],0,10000000): return []
	var spec := fire_spec(catalog,int(record.cast_level),record.evolution_id)
	var row: Dictionary = catalog.equipment.fire_zone
	var base := float(row.damage)+(int(record.cast_level)-1)*float(row.damage_per_level)
	var multiplier := float(spec.multipliers[int(record.stage_index)])
	var passive := "damage"
	var permanent := float(state.rules.get("permanent_damage_bonus",0.0))
	if field == "radius":
		base = float(spec.last_radius) if int(record.stage_index) == spec.delays.size()-1 else float(spec.radius)
		multiplier = 1.0
		passive = "attack_range"
		permanent = 0.0
	var matches := []
	for level in int(state.passives.get(passive,0))+1:
		var expected := base*(1.0+permanent+float(catalog.passives[passive].increment)*level)*multiplier
		if absf(float(record[field])-expected) <= 0.000001 and not expected in matches: matches.append(expected)
	return matches
static func _fire_art(evolution: String, eruption: bool) -> String:
	return "vfx_inferno_eruption" if eruption else ("vfx_inferno_zone" if evolution == "evo_inferno_zone" else "vfx_fire_zone")
static func _cast_id_valid(state: Dictionary, value: String) -> bool:
	var prefix: String = state.run_id+":attack:"
	if not value.begins_with(prefix): return false
	var suffix := value.substr(prefix.length())
	return suffix.is_valid_int() and str(suffix.to_int()) == suffix and Upgrades.integer_valid(suffix.to_int(),1,int(state.attack_seq))
static func _position(value: Variant) -> bool:
	return value is Array and value.size() == 2 and Upgrades.number_valid(value[0],-10000000,10000000) and Upgrades.number_valid(value[1],-10000000,10000000)
