class_name RunSimulation
extends RefCounted
const Contracts = preload("res://game/contracts/game_contracts.gd")
const SpatialHash = preload("res://game/combat/spatial_hash.gd")
const World = preload("res://game/combat/world_geometry.gd")
const Geometry = preload("res://game/combat/attack_geometry.gd")
const Behaviors = preload("res://game/combat/enemy_behaviors.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const TICKS_PER_SECOND := 60.0
const FINAL_TICK := 108000
const PAUSE_REASONS := ["user","upgrade","rotation","background","controller_lost","slow_frame"]
const MAX_ENTITIES := 512
const MAX_PROJECTILES := 256
const MAX_DROPS := 256
var _catalog = Catalog.new()
var _spatial = SpatialHash.new()
var _world = World.new()
func new_run(chapter: Dictionary, seed: int) -> Dictionary:
	if not chapter.has("chapter_id") or not _position_valid(chapter.get("spawn_position",[])):
		return {"ok":false,"error_code":"invalid_chapter"}
	var world = chapter.get("world_geometry",{})
	if not World.valid(world) or (chapter.get("content_revision","") == "ch01.2" and world.is_empty()) or not World.walkable(_vec(chapter.spawn_position),8.0,world):
		return {"ok":false,"error_code":"invalid_world_geometry"}
	var normalized_seed := seed & 0x7fffffff
	var rng := RandomNumberGenerator.new()
	rng.seed = normalized_seed
	var enemies: Dictionary = {}
	if chapter.has("enemy_catalog"):
		enemies = chapter.enemy_catalog.duplicate(true)
	elif FileAccess.file_exists("res://data/enemies.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))
		if parsed is Dictionary: enemies = parsed
	var allowed: Array = chapter.get("allowed_equipment_ids",_catalog.equipment.keys()).duplicate()
	var equipment: Dictionary = chapter.get("initial_equipment",{"blade_slash":1}).duplicate(true)
	if equipment.size() > 4: return {"ok":false,"error_code":"invalid_initial_equipment"}
	for item_id in equipment:
		if not item_id in allowed or not _catalog.equipment.has(item_id) or int(equipment[item_id]) < 1 or int(equipment[item_id]) > int(_catalog.equipment[item_id].max_level):
			return {"ok":false,"error_code":"invalid_initial_equipment"}
	var state := {"schema_version":1,"content_revision":chapter.get("content_revision","ch01.1"),"chapter_id":chapter.chapter_id,"character_id":"garrison_01","seed":normalized_seed,"rng_state":str(rng.state),"active_tick":0,"survival_tick":0,"next_entity_id":1,"event_seq":0,"phase":"survival","pause_reasons":[],"player":{"id":"player","position":_array(_vec(chapter.spawn_position)),"velocity":[0.0,0.0],"facing":[1.0,0.0],"radius":8.0,"hp":100.0,"max_hp":100.0,"invulnerable_until":0,"xp":0,"level":1,"attack_ready_ticks":{}},"equipment":equipment,"passives":{},"entities":[],"projectiles":[],"drops":[],"telegraphs":[],"boss_ids_fired":[],"reward_ids_claimed":[],"command_ids_applied":[],"upgrade_offer":{},"pending_offers":[],"final_started_tick":-1,"evacuation_ready":false,"escape_zone":chapter.get("escape_zone",[0.0,0.0,32.0,32.0]).duplicate(),"stats":{"kills":0,"damage_dealt":0.0,"minibosses_defeated":0},"rules":{"world_geometry":World.canonical(world),"allowed_equipment_ids":allowed,"enemy_catalog":enemies,"move_speed":100.0,"pickup_radius":30.0,"evacuation_ticks":4500,"progression":chapter.get("progression",_catalog.progression).duplicate(true)}}
	_normalize_saved_numbers(state)
	return state
func step(state: Dictionary, move: Vector2, commands: Array[Dictionary]) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state.phase in ["won","dead"] or not state.pause_reasons.is_empty() or not state.upgrade_offer.is_empty(): return events
	state.active_tick = int(state.active_tick)+1
	if state.phase == "survival": state.survival_tick = mini(FINAL_TICK,int(state.survival_tick)+1)
	for command in commands: _apply_command(state,command,events)
	_move_player(state,move)
	_move_enemies(state,events)
	_spatial.rebuild(state.entities)
	var boss_rewards: Array[Dictionary] = []
	_auto_attack(state,events,boss_rewards)
	_advance_projectiles(state,events,boss_rewards)
	_remove_dead(state)
	_attract_drops(state)
	_collect_drops(state,events)
	for reward in boss_rewards: _claim_boss_reward(state,reward,events)
	_player_damage(state,events)
	if state.player.hp <= 0.0:
		_end_run(state,"dead","damage",events)
		return events
	_regenerate(state)
	if state.phase == "evacuation":
		if int(state.active_tick)-int(state.final_started_tick) >= int(state.rules.evacuation_ticks): state.evacuation_ready = true
		if state.evacuation_ready and _inside_escape(state): _end_run(state,"won","evacuated",events)
	return events
func choose_upgrade(state: Dictionary, offer_id: String, option_id: String) -> Dictionary:
	if state.phase in ["dead","won"] or not state.get("upgrade_offer",null) is Dictionary or state.upgrade_offer.is_empty() or not _offer_valid(state,state.upgrade_offer,true) or state.upgrade_offer.offer_id != offer_id or "offer:"+offer_id in state.reward_ids_claimed:
		return {"ok":false,"error_code":"invalid_offer"}
	var selected: Dictionary = {}
	for option in state.upgrade_offer.options:
		if option.option_id == option_id: selected = option
	if selected.is_empty() or not _catalog.option_valid(state,selected):
		return {"ok":false,"error_code":"invalid_option"}
	var events: Array[Dictionary] = []
	if selected.kind == "recovery":
		state.player.hp = minf(float(state.player.max_hp),float(state.player.hp)+float(selected.amount))
	else:
		var equipped: Dictionary = state.equipment if selected.kind == "equipment" else state.passives
		equipped[selected.item_id] = int(equipped.get(selected.item_id,0))+1
		if selected.kind == "passive" and selected.item_id == "max_health":
			state.player.max_hp = _catalog.stat(state,"max_hp",100.0)
			state.player.hp = minf(float(state.player.max_hp),float(state.player.hp)+20.0)
	_emit(state,events,"upgrade_applied",{"offer_id":offer_id,"option_id":option_id,"item_id":selected.item_id,"kind":selected.kind})
	_claim_id(state.reward_ids_claimed,"offer:"+offer_id)
	state.upgrade_offer = {}
	while not state.pending_offers.is_empty():
		var candidate = state.pending_offers.pop_front()
		if not candidate is Dictionary or not candidate.get("offer_id",null) is String or candidate.offer_id.is_empty(): continue
		if "offer:"+candidate.offer_id in state.reward_ids_claimed: continue
		state.upgrade_offer = candidate
		break
	if not state.upgrade_offer.is_empty():
		# Rebase unshown choices to actual current levels before promotion. Keep
		# their family and FIFO offer ID; redraw unavailable or colliding choices.
		var choices: Array = state.upgrade_offer.get("options",[]) if state.upgrade_offer.get("options",[]) is Array else []
		var rebased: Array[Dictionary] = _catalog.rebase_options(state,choices)
		state.upgrade_offer.options = rebased if rebased.size() == 3 else _generate_options(state)
		state.upgrade_offer.selected_option_id = state.upgrade_offer.options[0].option_id
		_emit(state,events,"upgrade_opened",state.upgrade_offer.duplicate(true))
	else:
		state.pause_reasons.erase("upgrade")
	return {"ok":true,"events":events}
func set_pause(state: Dictionary, reason: String, enabled: bool) -> void:
	if not reason in PAUSE_REASONS: return
	if enabled:
		_claim_id(state.pause_reasons,reason)
	elif reason != "upgrade" or state.upgrade_offer.is_empty():
		state.pause_reasons.erase(reason)
func set_offer_focus(state: Dictionary, option_id: String) -> void:
	if state.upgrade_offer.is_empty(): return
	for option in state.upgrade_offer.options:
		if option.option_id == option_id:
			state.upgrade_offer.selected_option_id = option_id
			return
func abandon_run(state: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state.phase in ["won","dead"]: return events
	_end_run(state,"dead","abandoned",events)
	return events
func snapshot(state: Dictionary) -> Dictionary:
	return state.duplicate(true)
func restore(value: Dictionary) -> Dictionary:
	var errors: Array[String] = Contracts.new().validate_snapshot(value)
	if not errors.is_empty(): return {"ok":false,"error_code":"invalid_snapshot","errors":errors}
	# JSON decodes integer IDs/clocks as floats. Normalize a private copy before
	# comparing string ownership IDs, but reject every lossy integer conversion.
	var restored: Dictionary = value.duplicate(true)
	if not _normalize_saved_numbers(restored): return {"ok":false,"error_code":"invalid_core_state"}
	value = restored
	if not _core_payload_valid(value): return {"ok":false,"error_code":"invalid_core_state"}
	if not value.content_revision in ["ch01.1","ch01.2"] or value.chapter_id != "chapter_01_shiganshina" or value.character_id != "garrison_01":
		return {"ok":false,"error_code":"content_mismatch"}
	if not value.has("rules") or not value.rules is Dictionary:
		return {"ok":false,"error_code":"invalid_core_state"}
	for key in ["allowed_equipment_ids","enemy_catalog","move_speed","pickup_radius","evacuation_ticks","progression"]:
		if not value.rules.has(key): return {"ok":false,"error_code":"invalid_core_state"}
	for key in ["id","position","velocity","facing","radius","hp","max_hp","invulnerable_until","xp","level","attack_ready_ticks"]:
		if not value.player.has(key): return {"ok":false,"error_code":"invalid_player"}
	if not _position_valid(value.player.position) or not _position_valid(value.player.velocity) or not _position_valid(value.player.facing) or not value.player.attack_ready_ticks is Dictionary:
		return {"ok":false,"error_code":"invalid_player"}
	if value.equipment.size() > 4 or float(value.player.hp) < 0.0 or float(value.player.max_hp) <= 0.0 or float(value.player.hp) > float(value.player.max_hp) or int(value.player.level) < 1:
		return {"ok":false,"error_code":"invalid_player"}
	for kind in ["equipment","passives"]:
		var catalog: Dictionary = _catalog.equipment if kind == "equipment" else _catalog.passives
		for item_id in value[kind]:
			if not catalog.has(item_id) or int(value[kind][item_id]) < 1 or int(value[kind][item_id]) > int(catalog[item_id].max_level):
				return {"ok":false,"error_code":"invalid_item"}
	for reason in value.pause_reasons:
		if not reason in PAUSE_REASONS: return {"ok":false,"error_code":"invalid_pause_reason"}
	if not _offer_valid(value,value.upgrade_offer,true): return {"ok":false,"error_code":"invalid_offer"}
	for offer in value.pending_offers:
		if not offer is Dictionary or offer.is_empty() or not _offer_valid(value,offer,false): return {"ok":false,"error_code":"invalid_offer"}
	if not _offer_queue_ids_valid(value): return {"ok":false,"error_code":"invalid_offer_queue"}
	for collection in ["entities","drops","projectiles"]:
		var ids: Array = []
		for record in value[collection]:
			if not record is Dictionary or not record.has("id") or not _position_valid(record.get("position",[])) or str(record.id) in ids:
				return {"ok":false,"error_code":"invalid_entity"}
			ids.append(str(record.id))
	_canonicalize_saved_vectors(restored)
	return {"ok":true,"state":restored}
func _apply_command(state: Dictionary, command: Dictionary, events: Array[Dictionary]) -> void:
	if not command.has("command_id") or not command.command_id is String or command.command_id.is_empty() or not command.has("kind") or not command.get("payload",null) is Dictionary: return
	var command_id := str(command.command_id)
	if command_id in state.command_ids_applied: return
	var payload: Dictionary = command.payload
	var applied := false
	match str(command.kind):
		"spawn_enemy", "spawn_boss":
			applied = _spawn(state,payload,str(command.kind)=="spawn_boss",events)
		"telegraph_attack":
			if _hazard_valid(payload):
				var hazard: Dictionary = payload.duplicate(true)
				hazard.origin = _array(_vec(payload.origin))
				if payload.has("direction"): hazard.direction = _array(_vec(payload.direction))
				hazard.id = _new_id(state)
				hazard.created_tick = int(state.active_tick)
				hazard.active_from_tick = int(state.active_tick)+int(payload.warning_ticks)
				hazard.expires_tick = int(hazard.active_from_tick)+int(payload.active_ticks)
				state.telegraphs.append(hazard)
				applied = true
		"begin_evacuation":
			if state.phase == "survival" and int(state.survival_tick) >= FINAL_TICK and payload.get("boss_id","") == "ch01_final_armored" and _rect_valid(payload.get("escape_zone",[])) and int(payload.get("evacuation_ticks",0)) == 4500:
				state.phase = "evacuation"
				state.survival_tick = FINAL_TICK
				state.final_started_tick = int(state.active_tick)
				state.evacuation_ready = false
				state.escape_zone = payload.escape_zone.duplicate()
				state.rules.evacuation_ticks = int(payload.evacuation_ticks)
				state.entities.clear()
				state.drops.clear()
				state.projectiles.clear()
				state.telegraphs.clear()
				_claim_id(state.boss_ids_fired,"ch01_final_armored")
				_emit(state,events,"boss_spawned",{"boss_id":"ch01_final_armored","unbeatable":true})
				_emit(state,events,"phase_changed",{"phase":"evacuation"})
				applied = true
		"evacuation_ready":
			if state.phase == "evacuation" and int(state.active_tick)-int(state.final_started_tick) >= int(state.rules.evacuation_ticks):
				state.evacuation_ready = true
				applied = true
	if applied: _claim_id(state.command_ids_applied,command_id)
func _spawn(state: Dictionary, payload: Dictionary, boss: bool, events: Array[Dictionary]) -> bool:
	if state.phase != "survival" or not payload.has("entity_id") or not payload.has("enemy_id") or not _position_valid(payload.get("position",[])): return false
	var enemy_id := str(payload.enemy_id)
	if not state.rules.enemy_catalog.has(enemy_id): return false
	if boss:
		if not payload.has("boss_id") or not str(payload.boss_id) in ["ch01_b05","ch01_b10","ch01_b15","ch01_b20","ch01_b25"]: return false
		if payload.boss_id in state.boss_ids_fired: return false
	for entity in state.entities:
		if str(entity.id) == str(payload.entity_id): return false
	if state.entities.size() >= MAX_ENTITIES and not boss: return false
	var definition: Dictionary = state.rules.enemy_catalog[enemy_id]
	var spawn := _spawn_position(state,_vec(payload.position),float(definition.radius))
	if not World.walkable(spawn,float(definition.radius),state.rules.get("world_geometry",{})): return false
	var entity := {"id":payload.entity_id,"entity_id":payload.entity_id,"enemy_id":enemy_id,"position":_array(spawn),"velocity":[0.0,0.0],"hp":float(definition.hp),"max_hp":float(definition.hp),"speed":float(definition.speed),"radius":float(definition.radius),"damage":float(definition.get("damage",definition.get("contact_damage",0.0))),"xp":int(definition.xp),"behavior":definition.get("behavior","chase"),"art_id":definition.get("art_id","titan_basic"),"spawned_tick":int(payload.get("scheduled_tick",payload.get("spawned_tick",state.active_tick))),"boss_id":payload.get("boss_id","")}
	state.entities.append(entity)
	if payload.entity_id is int or payload.entity_id is float: state.next_entity_id = maxi(int(state.next_entity_id),int(payload.entity_id)+1)
	if boss:
		_claim_id(state.boss_ids_fired,str(payload.boss_id))
		_emit(state,events,"boss_spawned",{"boss_id":payload.boss_id,"entity_id":payload.entity_id,"enemy_id":enemy_id})
	return true
func _spawn_position(state: Dictionary, requested: Vector2, radius: float) -> Vector2:
	var world: Dictionary = state.rules.get("world_geometry",{})
	if World.walkable(requested,radius,world): return requested
	var player := _vec(state.player.position)
	var minimum := maxf(radius+float(state.player.radius)+16.0,minf(128.0,requested.distance_to(player)))
	var nearest := World.nearest_walkable(requested,radius,world)
	if World.walkable(nearest,radius,world) and nearest.distance_to(player) >= minimum: return nearest
	# Clamping an outward spawn beside a wall must not drop a new body onto the
	# player. Search the same ring in fixed angular order, with no RNG draws.
	var ring := maxf(160.0,requested.distance_to(player))
	var angle := (requested-player).angle()
	var best := Vector2(INF,INF)
	var cost := INF
	for index in 16:
		var candidate := World.nearest_walkable(player+Vector2.from_angle(angle+TAU*index/16.0)*ring,radius,world)
		var distance := candidate.distance_squared_to(requested)
		if World.walkable(candidate,radius,world) and candidate.distance_to(player) >= minimum and distance < cost:
			best = candidate
			cost = distance
	return best
func _move_player(state: Dictionary, input: Vector2) -> void:
	var move := input.limit_length(1.0) if is_finite(input.x) and is_finite(input.y) else Vector2.ZERO
	var speed := float(state.rules.move_speed)*_catalog.stat(state,"move_multiplier",1.0)
	var velocity := move*speed
	var position := World.move(_vec(state.player.position),velocity/TICKS_PER_SECOND,float(state.player.radius),state.rules.get("world_geometry",{}))
	state.player.position = _array(position)
	state.player.velocity = _array(velocity)
	if not move.is_zero_approx(): state.player.facing = _array(move.normalized())
func _move_enemies(state: Dictionary, events: Array[Dictionary]) -> void:
	for entity in state.entities:
		if not entity.has("action_state"): _initialize_action(state,entity)
		_advance_enemy_action(state,entity,events)
func _initialize_action(state: Dictionary, entity: Dictionary) -> void:
	var direction := _vec(entity.position).direction_to(_vec(state.player.position))
	if direction.is_zero_approx(): direction = Vector2.RIGHT
	entity.facing = _array(direction)
	entity.action_state = "move"
	entity.action_started_tick = int(state.active_tick)
	entity.action_ends_tick = int(state.active_tick)
	entity.next_action_tick = int(state.active_tick)
	entity.pattern_index = 0
	entity.attack_kind = "none"
	entity.locked_origin = entity.position.duplicate()
	entity.locked_direction = _array(direction)
	entity.locked_target = state.player.position.duplicate()
func _advance_enemy_action(state: Dictionary, entity: Dictionary, events: Array[Dictionary]) -> void:
	var profile: Dictionary = Behaviors.profile(entity)
	var tick := int(state.active_tick)
	var player := _vec(state.player.position)
	var position := _vec(entity.position)
	if entity.action_state == "move":
		if profile.kind != "none" and tick >= int(entity.next_action_tick) and position.distance_to(player) <= float(profile.trigger_range):
			_start_enemy_action(state,entity,profile,events)
			return
		var direction := _world.direction(position,player,float(entity.radius),state.rules.get("world_geometry",{}))
		entity.velocity = _array(direction*float(entity.speed))
		entity.position = _array(World.move(position,_vec(entity.velocity)/TICKS_PER_SECOND,float(entity.radius),state.rules.get("world_geometry",{})))
		if not direction.is_zero_approx(): entity.facing = _array(direction)
		return
	if entity.action_state == "windup" and tick >= int(entity.action_ends_tick):
		var action := "airborne" if entity.attack_kind == "leap" else "attack"
		var duration := int(profile.airborne_ticks) if action == "airborne" else int(profile.active_ticks)
		_set_action(entity,action,tick,duration)
	if entity.action_state == "airborne":
		if tick >= int(entity.action_ends_tick):
			entity.position = entity.locked_target.duplicate()
			_set_action(entity,"attack",tick,int(profile.active_ticks))
		else:
			var weight := float(tick-int(entity.action_started_tick))/float(profile.airborne_ticks)
			var next_position := _vec(entity.locked_origin).lerp(_vec(entity.locked_target),weight)
			entity.velocity = _array((next_position-_vec(entity.position))*TICKS_PER_SECOND)
			entity.position = _array(next_position)
			return
	if entity.action_state == "attack":
		if tick >= int(entity.action_ends_tick):
			_set_action(entity,"recover",tick,int(profile.recovery_ticks))
		elif entity.attack_kind in ["charge","grab"]:
			entity.velocity = _array(_vec(entity.locked_direction)*float(profile.rush_speed))
			entity.position = _array(World.sweep(_vec(entity.position),_vec(entity.velocity)/TICKS_PER_SECOND,float(entity.radius),state.rules.get("world_geometry",{})))
			return
	if entity.action_state == "recover" and tick >= int(entity.action_ends_tick):
		_set_action(entity,"move",tick,0)
		entity.next_action_tick = tick+int(profile.cooldown_ticks)
	entity.velocity = [0.0,0.0]
func _set_action(entity: Dictionary, action: String, tick: int, duration: int) -> void:
	entity.action_state = action
	entity.action_started_tick = tick
	entity.action_ends_tick = tick+duration
	entity.velocity = [0.0,0.0]
func _start_enemy_action(state: Dictionary, entity: Dictionary, profile: Dictionary, events: Array[Dictionary]) -> void:
	var direction := _vec(entity.position).direction_to(_vec(state.player.position))
	if direction.is_zero_approx(): direction = _vec(entity.facing)
	entity.attack_kind = profile.kind
	entity.pattern_index = int(entity.pattern_index)+1
	entity.locked_origin = entity.position.duplicate()
	entity.locked_direction = _array(direction)
	entity.locked_target = _array(World.nearest_walkable(_vec(state.player.position),float(entity.radius),state.rules.get("world_geometry",{}))) if profile.kind == "leap" else state.player.position.duplicate()
	entity.facing = _array(direction)
	_set_action(entity,"windup",int(state.active_tick),int(profile.warning_ticks))
	var leap: bool = profile.kind == "leap"
	var shape := "circle" if profile.kind in ["slam","leap"] else ("sector" if profile.kind == "sweep" else "line")
	var warning := int(profile.warning_ticks)+int(profile.get("airborne_ticks",0))
	var payload := {"source_id":str(entity.id),"shape":shape,"origin":entity.locked_target.duplicate() if leap else entity.locked_origin.duplicate(),"direction":entity.locked_direction.duplicate(),"radius":float(profile.get("radius",1.0)),"length":float(profile.get("length",1.0)),"width":maxf(float(profile.get("width",1.0)),float(entity.radius)*2.0),"arc_degrees":float(profile.get("arc_degrees",90.0)),"warning_ticks":warning,"active_ticks":int(profile.active_ticks),"damage":float(entity.damage),"behavior_attack":true}
	_apply_command(state,{"command_id":"behavior:%s:%d"%[str(entity.id),int(entity.pattern_index)],"kind":"telegraph_attack","payload":payload},events)
func _auto_attack(state: Dictionary, events: Array[Dictionary], boss_rewards: Array[Dictionary]) -> void:
	var item_ids: Array = state.equipment.keys()
	item_ids.sort()
	for item_id in item_ids:
		if int(state.player.attack_ready_ticks.get(item_id,0)) > int(state.active_tick): continue
		var definition: Dictionary = _catalog.equipment[item_id]
		var level := int(state.equipment[item_id])-1
		var radius := (float(definition.range)+float(definition.range_per_level)*level)*_catalog.stat(state,"range_multiplier",1.0)
		var targets: Array[int] = _spatial.query(_vec(state.player.position),radius+48.0)
		var target_index := -1
		var nearest := radius+48.0
		for index in targets:
			var entity: Dictionary = state.entities[index]
			if entity.hp <= 0.0: continue
			var distance := _vec(entity.position).distance_to(_vec(state.player.position))
			if distance <= radius+float(entity.radius) and distance < nearest:
				nearest = distance
				target_index = index
		if target_index < 0: continue
		var direction := _vec(state.player.position).direction_to(_vec(state.entities[target_index].position))
		if direction.is_zero_approx(): direction = _vec(state.player.facing)
		var damage := (float(definition.damage)+float(definition.damage_per_level)*level)*_catalog.stat(state,"damage_multiplier",1.0)
		var cooldown := maxi(1,int(round((float(definition.cooldown_ticks)-float(definition.cooldown_per_level)*level)*_catalog.stat(state,"cooldown_multiplier",1.0))))
		state.player.attack_ready_ticks[item_id] = int(state.active_tick)+cooldown
		if definition.mode == "projectile":
			if state.projectiles.size() < MAX_PROJECTILES:
				state.projectiles.append({"id":_new_id(state),"item_id":item_id,"position":state.player.position.duplicate(),"velocity":_array(direction*float(definition.projectile_speed)),"damage":damage,"splash_radius":float(definition.splash_radius),"remaining_distance":radius+48.0,"radius":4.0})
			continue
		var attack := {"origin":state.player.position,"direction":_array(direction),"shape":definition.mode,"radius":radius,"length":radius,"width":float(definition.get("width",28.0)),"arc_degrees":float(definition.get("arc_degrees",150.0))}
		if definition.mode == "combo":
			_hit_entity(state,state.entities[target_index],damage*int(definition.hits),item_id,events,boss_rewards)
		else:
			for index in targets:
				var entity: Dictionary = state.entities[index]
				if entity.hp > 0.0 and Geometry.overlaps(attack,_vec(entity.position),float(entity.radius)):
					_hit_entity(state,entity,damage,item_id,events,boss_rewards)
func _advance_projectiles(state: Dictionary, events: Array[Dictionary], boss_rewards: Array[Dictionary]) -> void:
	var kept: Array = []
	for projectile in state.projectiles:
		var previous := _vec(projectile.position)
		var displacement := _vec(projectile.velocity)/TICKS_PER_SECOND
		projectile.position = _array(previous+displacement)
		projectile.remaining_distance = float(projectile.remaining_distance)-displacement.length()
		var hit := false
		var segment := {"shape":"line","origin":_array(previous),"direction":_array(displacement.normalized()),"length":displacement.length(),"width":float(projectile.radius)*2.0}
		for index in _spatial.query(previous,displacement.length()+48.0):
			var entity: Dictionary = state.entities[index]
			if entity.hp <= 0.0 or not Geometry.overlaps(segment,_vec(entity.position),float(entity.radius)): continue
			hit = true
			var impact := _vec(entity.position)
			if float(projectile.splash_radius) > 0.0:
				for splash_index in _spatial.query(impact,float(projectile.splash_radius)+48.0):
					var splash_target: Dictionary = state.entities[splash_index]
					if _vec(splash_target.position).distance_to(impact) <= float(projectile.splash_radius)+float(splash_target.radius):
						_hit_entity(state,splash_target,float(projectile.damage),str(projectile.item_id),events,boss_rewards)
			else: _hit_entity(state,entity,float(projectile.damage),str(projectile.item_id),events,boss_rewards)
			break
		if not hit and projectile.remaining_distance > 0.0: kept.append(projectile)
	state.projectiles = kept
func _hit_entity(state: Dictionary, entity: Dictionary, damage: float, source: String, events: Array[Dictionary], boss_rewards: Array[Dictionary]) -> void:
	if entity.hp <= 0.0: return
	var amount := minf(float(entity.hp),damage)
	entity.hp = maxf(0.0,float(entity.hp)-damage)
	state.stats.damage_dealt = float(state.stats.damage_dealt)+amount
	_emit(state,events,"damage",{"target_id":entity.id,"source_id":source,"amount":amount,"hp":entity.hp})
	if entity.hp > 0.0: return
	state.stats.kills = int(state.stats.kills)+1
	_add_drop(state,entity.position,int(entity.xp))
	if not str(entity.boss_id).is_empty(): boss_rewards.append({"boss_id":entity.boss_id,"entity_id":entity.id})
func _remove_dead(state: Dictionary) -> void:
	var alive: Array = []
	var defeated: Array[String] = []
	for entity in state.entities:
		if entity.hp > 0.0: alive.append(entity)
		else: defeated.append(str(entity.id))
	state.entities = alive
	if not defeated.is_empty():
		var remaining: Array = []
		for hazard in state.telegraphs:
			if hazard.get("behavior_attack",false) and str(hazard.source_id) in defeated: continue
			remaining.append(hazard)
		state.telegraphs = remaining
func _add_drop(state: Dictionary, position: Array, xp: int) -> void:
	if xp <= 0: return
	var point := _vec(position)
	var cell := Vector2i(floor(point.x/16.0),floor(point.y/16.0))
	for drop in state.drops:
		var existing := _vec(drop.position)
		if Vector2i(floor(existing.x/16.0),floor(existing.y/16.0)) == cell:
			drop.xp = int(drop.xp)+xp
			return
	if state.drops.size() >= MAX_DROPS:
		var nearest: Dictionary = state.drops[0]
		var best_distance := point.distance_squared_to(_vec(nearest.position))
		for drop in state.drops:
			var distance := point.distance_squared_to(_vec(drop.position))
			if distance < best_distance:
				nearest = drop
				best_distance = distance
		nearest.xp = int(nearest.xp)+xp
		return
	state.drops.append({"id":_new_id(state),"position":position.duplicate(),"xp":xp})
func _collect_drops(state: Dictionary, events: Array[Dictionary]) -> void:
	var pickup := _catalog.stat(state,"pickup_radius",float(state.rules.pickup_radius))
	var drop_grid = SpatialHash.new()
	drop_grid.rebuild(state.drops)
	var collected: Array[int] = []
	var xp := 0
	for index in drop_grid.query(_vec(state.player.position),pickup):
		var drop: Dictionary = state.drops[index]
		if _vec(drop.position).distance_to(_vec(state.player.position)) <= pickup:
			collected.append(index)
			xp += int(drop.xp)
	collected.reverse()
	for index in collected: state.drops.remove_at(index)
	if xp == 0: return
	state.player.xp = int(state.player.xp)+xp
	_emit(state,events,"xp_gained",{"amount":xp,"xp":state.player.xp})
	while int(state.player.xp) >= Catalog.xp_to_next(int(state.player.level),state.rules.progression):
		state.player.xp = int(state.player.xp)-Catalog.xp_to_next(int(state.player.level),state.rules.progression)
		state.player.level = int(state.player.level)+1
		_queue_offer(state,"levelup:%d"%int(state.player.level),"levelup",events)
func _claim_boss_reward(state: Dictionary, reward: Dictionary, events: Array[Dictionary]) -> void:
	var reward_id := "boss:"+str(reward.boss_id)
	if reward_id in state.reward_ids_claimed: return
	_claim_id(state.reward_ids_claimed,reward_id)
	state.stats.minibosses_defeated = int(state.stats.minibosses_defeated)+1
	state.player.hp = minf(float(state.player.max_hp),float(state.player.hp)+float(state.player.max_hp)*0.25)
	_emit(state,events,"boss_defeated",reward.duplicate(true))
	_queue_offer(state,reward_id,"boss",events)
func _queue_offer(state: Dictionary, id: String, source: String, events: Array[Dictionary]) -> void:
	if "offer:"+id in state.reward_ids_claimed: return
	if not state.upgrade_offer.is_empty() and state.upgrade_offer.offer_id == id: return
	for pending in state.pending_offers:
		if pending.offer_id == id: return
	var options := _generate_options(state)
	var offer := {"offer_id":id,"options":options,"selected_option_id":options[0].option_id,"source":source}
	if state.upgrade_offer.is_empty():
		state.upgrade_offer = offer
		set_pause(state,"upgrade",true)
		_emit(state,events,"upgrade_opened",offer.duplicate(true))
	else: state.pending_offers.append(offer)
func _generate_options(state: Dictionary) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.state = int(state.rng_state)
	var result: Array[Dictionary] = _catalog.options(state,rng)
	state.rng_state = str(rng.state)
	return result
func _player_damage(state: Dictionary, events: Array[Dictionary]) -> void:
	var kept: Array = []
	for hazard in state.telegraphs:
		if int(state.active_tick) >= int(hazard.expires_tick): continue
		kept.append(hazard)
		if int(state.active_tick) >= int(hazard.active_from_tick) and Geometry.overlaps(hazard,_vec(state.player.position),float(state.player.radius)):
			_damage_player(state,float(hazard.damage),str(hazard.source_id),events)
	state.telegraphs = kept
	for entity in state.entities:
		if entity.get("action_state","move") in ["windup","airborne"]: continue
		if _vec(entity.position).distance_to(_vec(state.player.position)) <= float(entity.radius)+float(state.player.radius):
			_damage_player(state,float(entity.damage),str(entity.id),events)
func _damage_player(state: Dictionary, damage: float, source: String, events: Array[Dictionary]) -> void:
	if state.player.hp <= 0.0 or int(state.active_tick) < int(state.player.invulnerable_until): return
	var amount := maxf(1.0,damage-_catalog.stat(state,"armor",0.0))
	amount = minf(float(state.player.hp),amount)
	state.player.hp = maxf(0.0,float(state.player.hp)-amount)
	state.player.invulnerable_until = int(state.active_tick)+30
	_emit(state,events,"damage",{"target_id":"player","source_id":source,"amount":amount,"hp":state.player.hp})
func _regenerate(state: Dictionary) -> void:
	state.player.hp = minf(float(state.player.max_hp),float(state.player.hp)+_catalog.stat(state,"regen_per_second",0.0)/TICKS_PER_SECOND)
func _inside_escape(state: Dictionary) -> bool:
	var zone: Array = state.escape_zone
	return Rect2(float(zone[0]),float(zone[1]),float(zone[2]),float(zone[3])).has_point(_vec(state.player.position))
func _end_run(state: Dictionary, result: String, reason: String, events: Array[Dictionary]) -> void:
	if state.phase in ["won","dead"]: return
	state.phase = result
	_emit(state,events,"run_ended",{"result":result,"reason":reason,"clear_reward":1 if result == "won" else 0,"chapter_id":state.chapter_id})
func _emit(state: Dictionary, events: Array[Dictionary], type: String, payload: Dictionary) -> void:
	state.event_seq = int(state.event_seq)+1
	events.append({"event_id":"%d:%d"%[int(state.seed),int(state.event_seq)],"type":type,"tick":int(state.active_tick),"payload":payload})
func _claim_id(ids: Array, id: String) -> void:
	if not id in ids:
		ids.append(id)
		ids.sort()
func _new_id(state: Dictionary) -> int:
	var id := int(state.next_entity_id)
	state.next_entity_id = id+1
	return id
func _position_valid(value: Variant) -> bool:
	return value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float) and is_finite(float(value[0])) and is_finite(float(value[1]))
func _rect_valid(value: Variant) -> bool:
	return value is Array and value.size() == 4 and _position_valid([value[0],value[1]]) and _position_valid([value[2],value[3]]) and float(value[2]) > 0.0 and float(value[3]) > 0.0
func _hazard_valid(payload: Dictionary) -> bool:
	if not _id_valid(payload.get("source_id",null)) or not _position_valid(payload.get("origin",[])) or not payload.get("shape","") in ["circle","sector","line"]: return false
	if not _integer_valid(payload.get("warning_ticks",null)) or not _integer_valid(payload.get("active_ticks",null),1) or not _number_valid(payload.get("damage",null)): return false
	if payload.shape in ["circle","sector"] and (not _number_valid(payload.get("radius",null)) or float(payload.radius) <= 0.0): return false
	if payload.shape in ["sector","line"] and not _position_valid(payload.get("direction",[])): return false
	if payload.shape == "line" and (not _number_valid(payload.get("length",null)) or not _number_valid(payload.get("width",null)) or float(payload.length) <= 0.0 or float(payload.width) <= 0.0): return false
	if payload.shape == "sector" and (not _number_valid(payload.get("arc_degrees",90.0)) or float(payload.get("arc_degrees",90.0)) > 360.0): return false
	return true
func _offer_valid(state: Dictionary, offer: Dictionary, applicable: bool) -> bool:
	if offer.is_empty(): return true
	if not offer.get("offer_id",null) is String or offer.offer_id.is_empty() or not offer.get("options",null) is Array or offer.options.size() != 3 or not offer.get("selected_option_id",null) is String: return false
	var ids: Array = []
	var identities: Array[String] = []
	for option in offer.options:
		if not option is Dictionary: return false
		if not _catalog.option_well_formed(state,option) or (applicable and not _catalog.option_valid(state,option)): return false
		var identity := "%s:%s"%[option.kind,option.item_id]
		if option.option_id in ids or identity in identities: return false
		ids.append(option.option_id)
		identities.append(identity)
	return offer.selected_option_id in ids
func _vec(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))
func _array(value: Vector2) -> Array:
	return [value.x,value.y]

func _normalize_saved_numbers(value: Variant, parent_key := "") -> bool:
	# JSON reads every numeric literal as a float. Restore schema integers so
	# canonical replay equality and typed clocks survive a disk roundtrip.
	if value is Dictionary:
		for key in value:
			if value[key] is float and (parent_key in ["equipment","passives","attack_ready_ticks"] or key in ["schema_version","seed","active_tick","survival_tick","next_entity_id","event_seq","final_started_tick","invulnerable_until","xp","level","next_level","kills","minibosses_defeated","evacuation_ticks","base_xp","xp_per_level","spawned_tick","action_started_tick","action_ends_tick","next_action_tick","pattern_index","created_tick","active_from_tick","expires_tick","warning_ticks","active_ticks","id","entity_id"]):
				var number: float = value[key]
				if not is_finite(number) or number != floor(number) or number < -9223372036854775808.0 or number >= 9223372036854775808.0: return false
				value[key] = int(number)
			elif not _normalize_saved_numbers(value[key],str(key)): return false
	elif value is Array:
		for child in value:
			if not _normalize_saved_numbers(child,parent_key): return false
	return true

func _attract_drops(state: Dictionary) -> void:
	var pickup := _catalog.stat(state,"pickup_radius",float(state.rules.pickup_radius))
	var player := _vec(state.player.position)
	for drop in state.drops:
		var point := _vec(drop.position)
		if point.distance_to(player) <= pickup*3.0:
			drop.position = _array(point.move_toward(player,240.0/TICKS_PER_SECOND))
func _number_valid(value: Variant, minimum := 0.0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum
func _integer_valid(value: Variant, minimum := 0) -> bool:
	return _number_valid(value,float(minimum)) and float(value) == floor(float(value))
func _id_valid(value: Variant) -> bool:
	return (value is String and not value.is_empty()) or _integer_valid(value,1)
func _string_set_valid(value: Array) -> bool:
	var seen: Array = []
	for id in value:
		if not id is String or id.is_empty() or id in seen: return false
		seen.append(id)
	return true
func _core_payload_valid(value: Dictionary) -> bool:
	for key in ["schema_version","seed","active_tick","survival_tick","next_entity_id","event_seq"]:
		if not _integer_valid(value.get(key,null)): return false
	if int(value.seed) > 0x7fffffff or not _integer_valid(value.get("final_started_tick",null),-1): return false
	if not value.get("evacuation_ready",null) is bool or not _rect_valid(value.get("escape_zone",null)): return false
	for key in ["boss_ids_fired","reward_ids_claimed","command_ids_applied","pause_reasons"]:
		if not _string_set_valid(value[key]): return false
	var player: Dictionary = value.player
	for key in ["hp","max_hp","radius"]:
		if not _number_valid(player.get(key,null)): return false
	for key in ["invulnerable_until","xp","level"]:
		if not _integer_valid(player.get(key,null)): return false
	if not player.get("attack_ready_ticks",null) is Dictionary: return false
	for item_id in player.attack_ready_ticks:
		if not _catalog.equipment.has(item_id) or not _integer_valid(player.attack_ready_ticks[item_id]): return false
	if not value.get("rules",null) is Dictionary: return false
	var rules: Dictionary = value.rules
	var world = rules.get("world_geometry",{})
	if not World.valid(world) or (value.content_revision == "ch01.2" and world.is_empty()): return false
	if not _position_valid(player.get("position")) or not World.walkable(_vec(player.position),float(player.radius),world): return false
	if not rules.get("allowed_equipment_ids",null) is Array or not _string_set_valid(rules.allowed_equipment_ids): return false
	for item_id in rules.allowed_equipment_ids:
		if not _catalog.equipment.has(item_id): return false
	for item_id in value.equipment:
		if not item_id in rules.allowed_equipment_ids: return false
	for kind in ["equipment","passives"]:
		for item_id in value[kind]:
			if not _integer_valid(value[kind][item_id],1): return false
	if not _number_valid(rules.get("move_speed",null)) or not _number_valid(rules.get("pickup_radius",null)) or not _integer_valid(rules.get("evacuation_ticks",null),1) or int(rules.evacuation_ticks) != 4500: return false
	if not rules.get("progression",null) is Dictionary or not _integer_valid(rules.progression.get("base_xp",null),1) or not _integer_valid(rules.progression.get("xp_per_level",null)): return false
	if not rules.get("enemy_catalog",null) is Dictionary: return false
	for enemy_id in rules.enemy_catalog:
		var definition = rules.enemy_catalog[enemy_id]
		if not definition is Dictionary: return false
		for key in ["hp","speed","radius"]:
			if not _number_valid(definition.get(key,null)): return false
		if not _number_valid(definition.get("damage",definition.get("contact_damage",null))) or not _integer_valid(definition.get("xp",null)): return false
	for key in ["kills","minibosses_defeated"]:
		if not _integer_valid(value.stats.get(key,null)): return false
	if not _number_valid(value.stats.get("damage_dealt",null)): return false
	var seen: Array = []
	for collection in ["entities","projectiles","drops","telegraphs"]:
		for record in value[collection]:
			if not record is Dictionary or not _id_valid(record.get("id",null)) or str(record.id) in seen: return false
			seen.append(str(record.id))
			if collection != "telegraphs" and not _position_valid(record.get("position",null)): return false
			if collection == "entities":
				for key in ["hp","max_hp","speed","radius","damage"]:
					if not _number_valid(record.get(key,null)): return false
				if not _integer_valid(record.get("xp",null)) or not _integer_valid(record.get("spawned_tick",null)) or not _position_valid(record.get("velocity",null)): return false
				if not record.get("boss_id",null) is String or not record.get("enemy_id",null) is String or not rules.enemy_catalog.has(record.enemy_id): return false
				if not _behavior_state_valid(value,record): return false
				if record.get("action_state","") != "airborne" and not World.walkable(_vec(record.position),float(record.radius),world): return false
			elif collection == "projectiles":
				for key in ["damage","splash_radius","remaining_distance","radius"]:
					if not _number_valid(record.get(key,null)): return false
				if not _position_valid(record.get("velocity",null)) or not _catalog.equipment.has(record.get("item_id",null)): return false
			elif collection == "drops":
				if not _integer_valid(record.get("xp",null),1): return false
			elif collection == "telegraphs":
				if not _hazard_valid(record): return false
				for key in ["created_tick","active_from_tick","expires_tick"]:
					if not _integer_valid(record.get(key,null)): return false
				if int(record.active_from_tick) != int(record.created_tick)+int(record.warning_ticks) or int(record.expires_tick) != int(record.active_from_tick)+int(record.active_ticks): return false
	return _run_relationships_valid(value) and _owned_behavior_hazards_valid(value)
func _run_relationships_valid(value: Dictionary) -> bool:
	if int(value.active_tick) < int(value.survival_tick): return false
	if not value.upgrade_offer.is_empty() and not "upgrade" in value.pause_reasons: return false
	if value.upgrade_offer.is_empty() and not value.pending_offers.is_empty(): return false
	var started := int(value.final_started_tick)
	if started == -1:
		return value.phase in ["survival","dead"] and not value.evacuation_ready
	if started < FINAL_TICK or started > int(value.active_tick) or int(value.survival_tick) != FINAL_TICK or value.phase == "survival": return false
	if not "ch01_final_armored" in value.boss_ids_fired: return false
	var elapsed := int(value.active_tick)-started
	if value.evacuation_ready and elapsed < int(value.rules.evacuation_ticks): return false
	if value.phase == "won" and (not value.evacuation_ready or elapsed < int(value.rules.evacuation_ticks)): return false
	return true

func _offer_queue_ids_valid(state: Dictionary) -> bool:
	var ids: Array[String] = []
	var offers: Array = state.pending_offers.duplicate()
	if not state.upgrade_offer.is_empty(): offers.push_front(state.upgrade_offer)
	for offer in offers:
		var id: String = offer.offer_id
		if id in ids or "offer:"+id in state.reward_ids_claimed: return false
		ids.append(id)
	return true

func _behavior_state_valid(state: Dictionary, entity: Dictionary) -> bool:
	var required := ["action_state","action_started_tick","action_ends_tick","next_action_tick","pattern_index","attack_kind","locked_origin","locked_direction","locked_target","facing"]
	var present := false
	for key in required:
		if entity.has(key): present = true
	if not present: return true # A checkpoint predating optional behavior state.
	for key in required:
		if not entity.has(key): return false
	if not entity.action_state in ["move","windup","attack","recover","airborne"] or not entity.attack_kind in ["none","charge","slam","sweep","grab","leap"]: return false
	for key in ["action_started_tick","action_ends_tick","next_action_tick","pattern_index"]:
		if not _integer_valid(entity[key]): return false
	if int(entity.action_started_tick) > int(state.active_tick) or int(entity.action_ends_tick) < int(entity.action_started_tick): return false
	for key in ["locked_origin","locked_direction","locked_target","facing"]:
		if not _position_valid(entity[key]): return false
	if not is_equal_approx(_vec(entity.locked_direction).length_squared(),1.0) or not is_equal_approx(_vec(entity.facing).length_squared(),1.0): return false
	if entity.has("art_id") and not entity.art_id is String: return false
	if entity.action_state == "move": return true
	var profile: Dictionary = Behaviors.profile(entity)
	if entity.attack_kind != profile.kind or entity.attack_kind == "none" or int(entity.pattern_index) < 1 or int(entity.action_ends_tick) <= int(state.active_tick): return false
	var duration_key: String = {"windup":"warning_ticks","airborne":"airborne_ticks","attack":"active_ticks","recover":"recovery_ticks"}[entity.action_state]
	if not profile.has(duration_key) or int(entity.action_ends_tick)-int(entity.action_started_tick) != int(profile[duration_key]): return false
	if entity.action_state == "airborne" and entity.attack_kind != "leap": return false
	if not "behavior:%s:%d"%[str(entity.id),int(entity.pattern_index)] in state.command_ids_applied: return false
	if not World.walkable(_vec(entity.locked_origin),float(entity.radius),state.rules.get("world_geometry",{})): return false
	if entity.attack_kind == "leap" and not World.walkable(_vec(entity.locked_target),float(entity.radius),state.rules.get("world_geometry",{})): return false
	if not _action_motion_valid(state,entity,profile): return false
	if entity.action_state in ["windup","airborne","attack"]:
		var found := false
		for hazard in state.telegraphs:
			if hazard is Dictionary and hazard.get("source_id",null) == str(entity.id) and hazard.get("behavior_attack",false) == true and _behavior_hazard_matches(entity,profile,hazard):
				found = true
		if not found: return false
	return true

func _behavior_hazard_matches(entity: Dictionary, profile: Dictionary, hazard: Dictionary) -> bool:
	if not _hazard_valid(hazard): return false
	for key in ["created_tick","active_from_tick","expires_tick"]:
		if not _integer_valid(hazard.get(key,null)): return false
	var warning := int(profile.warning_ticks)+int(profile.get("airborne_ticks",0))
	if int(hazard.warning_ticks) != warning or int(hazard.active_ticks) != int(profile.active_ticks) or float(hazard.damage) != float(entity.damage): return false
	var created := int(entity.action_started_tick)
	if entity.action_state == "airborne": created -= int(profile.warning_ticks)
	elif entity.action_state == "attack": created -= warning
	if int(hazard.created_tick) != created or int(hazard.active_from_tick) != created+warning: return false
	var origin := _vec(entity.locked_target) if entity.attack_kind == "leap" else _vec(entity.locked_origin)
	if not _vec(hazard.origin).is_equal_approx(origin) or not _vec(hazard.get("direction",[0.0,0.0])).is_equal_approx(_vec(entity.locked_direction)): return false
	var shape := "circle" if entity.attack_kind in ["slam","leap"] else ("sector" if entity.attack_kind == "sweep" else "line")
	if hazard.shape != shape: return false
	if shape in ["circle","sector"] and not is_equal_approx(float(hazard.radius),float(profile.radius)): return false
	if shape == "sector" and not is_equal_approx(float(hazard.get("arc_degrees",90.0)),float(profile.arc_degrees)): return false
	if shape == "line" and (not is_equal_approx(float(hazard.length),float(profile.length)) or not is_equal_approx(float(hazard.width),maxf(float(profile.width),float(entity.radius)*2.0))): return false
	return true

func _action_motion_valid(state: Dictionary, entity: Dictionary, profile: Dictionary) -> bool:
	var position := _vec(entity.locked_origin)
	var velocity := Vector2.ZERO
	var age := int(state.active_tick)-int(entity.action_started_tick)
	if entity.action_state == "airborne":
		var duration := float(profile.airborne_ticks)
		var origin := _vec(entity.locked_origin)
		var target := _vec(entity.locked_target)
		position = origin.lerp(target,float(age)/duration)
		var previous := origin.lerp(target,float(maxi(0,age-1))/duration)
		velocity = (position-previous)*TICKS_PER_SECOND
	elif entity.action_state in ["attack","recover"]:
		if entity.attack_kind in ["charge","grab"]:
			var rush := _vec(entity.locked_direction)*float(profile.rush_speed)
			var step_delta := rush/TICKS_PER_SECOND
			var steps := age+1 if entity.action_state == "attack" else int(profile.active_ticks)
			# Match the engine's real_t rounding at every physical step rather
			# than comparing against a numerically different closed-form sum.
			for index in steps: position = World.sweep(position,step_delta,float(entity.radius),state.rules.get("world_geometry",{}))
			if entity.action_state == "attack": velocity = rush
		elif entity.attack_kind == "leap": position = _vec(entity.locked_target)
	# Absolute subpixel tolerances do not widen with world coordinates.
	return _vec(entity.position).distance_to(position) <= 0.001 and _vec(entity.velocity).distance_to(velocity) <= 0.01 and _vec(entity.facing).distance_to(_vec(entity.locked_direction)) <= 0.0001
func _owned_behavior_hazards_valid(state: Dictionary) -> bool:
	var actors: Dictionary = {}
	for entity in state.entities: actors[str(entity.id)] = entity
	var sources: Array[String] = []
	for hazard in state.telegraphs:
		if hazard.has("behavior_attack") and not hazard.behavior_attack is bool: return false
		if not hazard.get("behavior_attack",false): continue
		var source: String = str(hazard.source_id)
		if source in sources or not actors.has(source): return false
		var actor: Dictionary = actors[source]
		if actor.hp <= 0.0 or not actor.has("action_state") or not actor.action_state in ["windup","airborne","attack"]: return false
		if not _behavior_hazard_matches(actor,Behaviors.profile(actor),hazard): return false
		sources.append(source)
	return true
func _canonicalize_saved_vectors(state: Dictionary) -> void:
	# Engine vectors are real_t float32 values widened into JSON-safe arrays.
	# Reconstruct that representation after decimal parsing; even full-precision
	# JSON can otherwise leave a double ULP on a widened float32 coordinate.
	for key in ["position","velocity","facing"]:
		state.player[key] = _array(_vec(state.player[key]))
	for collection in ["entities","projectiles","drops"]:
		for record in state[collection]:
			for key in ["position","velocity","facing","locked_origin","locked_direction","locked_target"]:
				if record.has(key): record[key] = _array(_vec(record[key]))
	for hazard in state.telegraphs:
		hazard.origin = _array(_vec(hazard.origin))
		if hazard.has("direction"): hazard.direction = _array(_vec(hazard.direction))
