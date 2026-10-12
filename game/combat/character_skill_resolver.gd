class_name CharacterSkillResolver
extends RefCounted
# Revision 1 is immutable. Core owns admission, execution, hits and events.
const Upgrades = preload("res://game/progression/upgrade_catalog.gd")
const Evolved = preload("res://game/combat/evolved_attack_resolver.gd")
const TOKEN := "character:mikasa_unique_attack"
const REVISION := 1
const MAX_COUNTER := 2147483647
const COOLDOWN := 720
const PROBE_INTERVAL := 6
const RADIUS := 96.0
const ARC := 150.0
const DELAYS := [0,8,16]
const DAMAGE := [18.0,18.0,36.0]
const FIELDS := ["attack_id","cast_id","base_item_id","evolution_id","attack_started_tick","execute_tick","stage_index","stage_count","origin_binding","origin","direction","shape","radius","arc_degrees","damage","hit_entity_ids","pose_tag","target_id","cast_damage_level"]
var _catalog
func _init(catalog = null) -> void:
	_catalog = Upgrades.new() if catalog == null else catalog
static func enabled(state: Dictionary) -> bool:
	var config: Dictionary = state.get("run_config",{})
	return state.get("character_id","") == "mikasa_01" and config.get("character_id","") == "mikasa_01" and Upgrades.integer_valid(config.get("character_skill_revision"),REVISION,REVISION)
static func is_signature(record: Dictionary) -> bool:
	return record.get("base_item_id","") == TOKEN
static func initial_state() -> Dictionary:
	return {"ready_tick":0,"next_probe_tick":1,"pending_cast_id":""}
func choose_target(state: Dictionary, query: Callable, clear: Callable) -> int:
	var origin := Vector2(state.player.position[0],state.player.position[1])
	var nearest := INF
	var chosen := -1
	var chosen_id := ""
	for index in query.call(origin,RADIUS+48.0):
		var entity: Dictionary = state.entities[index]
		if entity.hp <= 0: continue
		var target := Vector2(entity.position[0],entity.position[1])
		var distance := origin.distance_squared_to(target)
		var id := str(entity.id)
		if distance > pow(RADIUS+float(entity.radius),2): continue
		if distance > nearest or (distance == nearest and chosen >= 0 and id >= chosen_id): continue
		if not clear.call(origin,target): continue
		nearest = distance
		chosen = index
		chosen_id = id
	return chosen
func reserve(state: Dictionary, target_id: String, direction: Vector2, cast_id: String) -> Dictionary:
	if not enabled(state) or not _target_id_valid(target_id) or not is_finite(direction.x) or not is_finite(direction.y) or direction.is_zero_approx(): return {"ok":false,"error_code":"invalid_option"}
	if not Upgrades.integer_valid(state.get("active_tick"),1,MAX_COUNTER-COOLDOWN) or not Upgrades.integer_valid(state.get("attack_seq"),0,MAX_COUNTER-1): return {"ok":false,"error_code":"counter_exhausted"}
	if cast_id != state.run_id+":attack:"+str(int(state.attack_seq)+1): return {"ok":false,"error_code":"invalid_core_state"}
	var aim := direction.normalized()
	var level := int(state.passives.get("damage",0))
	var records: Array[Dictionary] = []
	for index in 3:
		records.append({"attack_id":cast_id+":"+str(index),"cast_id":cast_id,"base_item_id":TOKEN,"evolution_id":"","attack_started_tick":int(state.active_tick),"execute_tick":int(state.active_tick)+DELAYS[index],"stage_index":index,"stage_count":3,"origin_binding":"player","origin":state.player.position.duplicate(),"direction":[aim.x,aim.y],"shape":"sector","radius":RADIUS,"arc_degrees":ARC,"damage":_damage(state,index,level),"hit_entity_ids":[],"pose_tag":"blade_slash","target_id":target_id,"cast_damage_level":level})
	return {"ok":true,"records":records,"cooldown_ticks":COOLDOWN}
func validate_records(state: Dictionary) -> bool:
	if not state.get("player_attack_instances") is Array: return false
	var records: Array = state.player_attack_instances.filter(func(record): return record is Dictionary and is_signature(record))
	if not enabled(state): return not state.has("character_skill") and records.is_empty() and not state.get("run_config",{}).has("character_skill_revision")
	var runtime = state.get("character_skill")
	if not runtime is Dictionary or runtime.size() != 3 or not runtime.has_all(["ready_tick","next_probe_tick","pending_cast_id"]): return false
	var tick := int(state.active_tick)
	if not Upgrades.integer_valid(runtime.ready_tick,0,mini(MAX_COUNTER,tick+COOLDOWN)) or not Upgrades.integer_valid(runtime.next_probe_tick,1,mini(MAX_COUNTER,maxi(tick,int(runtime.ready_tick))+PROBE_INTERVAL)): return false
	if runtime.next_probe_tick < runtime.ready_tick or not runtime.pending_cast_id is String: return false
	if records.is_empty(): return runtime.pending_cast_id.is_empty()
	if not Evolved._cast_id_valid(state,runtime.pending_cast_id) or records.size() > 2: return false
	var first: Dictionary = records[0]
	var seen := {}
	for record in records:
		if not _record_valid(state,record) or record.cast_id != runtime.pending_cast_id or seen.has(int(record.stage_index)): return false
		seen[int(record.stage_index)] = true
		if int(record.attack_started_tick)+COOLDOWN != runtime.ready_tick or runtime.next_probe_tick != runtime.ready_tick: return false
		for field in ["target_id","cast_damage_level","attack_started_tick","direction","origin"]:
			if record[field] != first[field]: return false
	for index in 3:
		if (int(first.attack_started_tick)+DELAYS[index] > tick) != seen.has(index): return false
	return true
func _record_valid(state: Dictionary, record: Dictionary) -> bool:
	if record.size() != FIELDS.size() or not record.has_all(FIELDS) or not Upgrades.json_data_valid(record): return false
	if record.base_item_id != TOKEN or record.evolution_id != "" or not record.cast_id is String or not Evolved._cast_id_valid(state,record.cast_id): return false
	if not Upgrades.integer_valid(record.stage_index,0,2) or not Upgrades.integer_valid(record.stage_count,3,3) or record.attack_id != record.cast_id+":"+str(int(record.stage_index)): return false
	if not Upgrades.integer_valid(record.attack_started_tick,1,int(state.active_tick)) or not Upgrades.integer_valid(record.execute_tick,int(state.active_tick)+1): return false
	if record.execute_tick != int(record.attack_started_tick)+DELAYS[int(record.stage_index)]: return false
	if not _target_id_valid(record.target_id) or not Upgrades.integer_valid(record.cast_damage_level,0,int(state.passives.get("damage",0))): return false
	if record.origin_binding != "player" or record.shape != "sector" or record.pose_tag != "blade_slash" or record.radius != RADIUS or record.arc_degrees != ARC: return false
	if not Evolved._position(record.origin) or not Evolved._position(record.direction) or not is_equal_approx(Vector2(record.direction[0],record.direction[1]).length_squared(),1.0): return false
	if not record.hit_entity_ids is Array or not record.hit_entity_ids.is_empty(): return false
	var expected := _damage(state,int(record.stage_index),int(record.cast_damage_level))
	# Only the exact operation result or its own JSON parser representation.
	# Never accept an epsilon range or search today's possible passive levels.
	return Upgrades.number_valid(record.damage,0,10000000) and (record.damage == expected or record.damage == JSON.parse_string(JSON.stringify(expected,"",true,true)))
func canonicalize(state: Dictionary) -> void:
	for record in state.player_attack_instances:
		if is_signature(record): record.damage = _damage(state,int(record.stage_index),int(record.cast_damage_level))
func _damage(state: Dictionary, index: int, level: int) -> float:
	return DAMAGE[index]*(1.0+float(state.rules.get("permanent_damage_bonus",0.0))+float(_catalog.passives.damage.increment)*level)
static func _target_id_valid(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 4096
static func presentation(state: Dictionary) -> Dictionary:
	if state.get("character_id","") != "mikasa_01": return {"visible":false,"text":""}
	if not enabled(state) or not state.get("character_skill") is Dictionary: return {"visible":true,"text":"고유 공격 · 다음 출격부터"}
	var runtime: Dictionary = state.character_skill
	var remaining := maxi(0,int(runtime.ready_tick)-int(state.get("active_tick",0)))
	var label := "연격 중" if not str(runtime.pending_cast_id).is_empty() else ("준비" if remaining == 0 else "%.1f초" % (ceil(float(remaining)/6.0)/10.0))
	return {"visible":true,"text":"고유 · 집중 연격 · "+label}
